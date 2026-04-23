module rewind.re.bitnfa;

import rewind.re.bytecode, rewind.re.codegen;

import std.array, std.uni;

import core.bitop;

enum mul = 0x9E3779B97F4A7C15L;

ulong hash(ulong x, uint n) {
    return (x * mul) >> (64 - n);
}

auto isPow2(size_t size) => (size & (size-1)) == 0;

// aka simple immutable hash table
// the idea is that it's built once and used many times for lookups
struct SIHT {
    static struct Entry {
        ulong key = -1;
        ulong value = -1;
    }
    Entry* entries;
    uint length;
    uint mask;
    uint items;
    uint log2Size;

    this(size_t size) {
        assert(isPow2(size) && size >= 4);
        entries = (new Entry[size]).ptr;
        length = cast(uint)size;
        log2Size = bsr(size);
        mask = cast(uint)(size - 1);
    }

    void insert(ulong key, ulong value) {
        if (2*items > length) rehash();
        auto h = hash(key, log2Size);
        auto idx = h & mask;
        for (;;) {
            assert(entries[idx].key != key); // prevent double inserts
            if (entries[idx].key == -1) {
                entries[idx] = Entry(key, value);
                items++;
                break;
            }
            idx = (idx + 1) & mask;
        }
    }

    ulong opIndex(size_t key) {
        auto h = hash(key, log2Size);
        auto idx = h & mask;
        for (;;) {
            if (entries[idx].key == key) {
                return entries[idx].value;
            }
            if (entries[idx].key == -1) {
                return -1;
            }
            idx = (idx + 1) & mask;
        }
    }

    // double the table size
    void rehash() {
        SIHT extended = SIHT(length * 2);
        for (size_t i = 0; i < length; i++) {
            if (entries[i].key != -1) {
                extended.insert(entries[i].key, entries[i].value);
            }
        }
        this = extended;
    }
}

unittest {
    auto t = SIHT(4);
    foreach (i; 0..32) {
        t.insert(1<<i, ~(1<<i));
    }
    assert(t.length == 64);
    assert(t.mask == 63);
    foreach (i; 0..ushort.max) {
        assert((isPow2(i) && t[i] == ~i) || t[i] == -1);
    }
}

struct BitNFABuilder {
//outputs & state
    ulong[256] table = -1;
    SIHT jumps;
    ulong jumpMask = -1;
    ulong finishMask = 0;
// internal state
    size_t[][] jumpTargets;
    void* native;

    this(size_t size) {
        assert(size > 0 && size < 64);
        jumpTargets = new size_t[][size];
        jumps = SIHT(16);
    }

    void add(size_t index, char start, char end) {
        for (char i=start; i<=end; i++){
            table[i] &= ~(1UL<<index);
        }
    }

    void add(size_t index, CodepointSet set) {
        set &= CodepointSet(0, 0x80); // TODO: think about non-ascii BitNFA
        foreach (ival; set.byInterval) {
            add(index, cast(char)ival[0], cast(char)(ival[1]-1));
        }
    }

    void jumpTarget(size_t from, size_t to) {
        jumpTargets[from] ~= to;
    }

    void end(size_t index) nothrow {
        finishMask = 1UL << index;
    }

    ref build() {
        struct E {
            ulong jumpMask;
            ulong jumpTargetMask;
        }
        E[] entries;
        foreach (i, jts; jumpTargets) {
            if (!jts.empty) {
                jumpMask &= ~(1UL<<i); // cumulative mask
                ulong jumpTargetMask = -1; // this offset target mask
                foreach (j; jts) {
                    jumpTargetMask &= ~(1UL<<j);
                }
                entries ~= E(~(1UL<<i), jumpTargetMask);
            }
        }
        // populate SIHT table with all permutations, 0 is -1 which is default for not found
        for (size_t i = 1; i < (1<<entries.length); i++) {
            size_t j = i;
            ulong mask = -1;
            ulong targetsMask = -1;
            while (j != 0) {
                auto bit = bsf(j);
                mask &= entries[bit].jumpMask;
                targetsMask &= entries[bit].jumpTargetMask;
                j = j & (j-1);
            }
            jumps.insert(mask, targetsMask);
        }
        return this;
    }

    ref buildNative() {
        version(AArch64) {
            import rewind.re.dynasm.arm64;
            static struct Entry {
                size_t branch;
                size_t[] targets;
            }
            Entry[] entries;
            foreach (i, jts; jumpTargets) {
                if (!jts.empty) {
                    entries ~= Entry(i, jts);
                }
            }
            Assembler assembler = Assembler(16 * 4096);
            with (assembler) with(Condition) {
                enum {
                    FINISH = x(0),
                    TABLE = x(1),
                    LENGTH = x(2),
                    INPUT_END = LENGTH,
                    INPUT = x(3),
                    STATE = x(5),
                    LOOKUP_W = w(6),
                    LOOKUP = x(6),
                    SCRATCH = x(7),
                    PTR = x(8),
                    SCRATCH_2 = x(9),
                    SCRATCH_3 = x(18)
                }
                auto loopStart = createLabel();
                auto lastStep = createLabel();
                auto found = createLabel();
                mov(PTR, INPUT);
                movn(STATE, imm(0));
                add(INPUT_END, INPUT, LENGTH);
                foreach (i, e; entries) {
                    movn(x(10+cast(int)i), imm(1));
                    if (e.branch != 0) {
                        ror(x(10+cast(int)i), x(10+cast(int)i), imm(64 - cast(int)e.branch));
                    }
                }
            bind(loopStart);
                cmp(PTR, INPUT_END);
                b(EQ, lastStep);
                lsl(STATE, STATE, imm(1));
                foreach (i, e; entries) {
                    orr(SCRATCH_2, STATE, x(10+cast(int)i));
                    foreach (t; e.targets) {
                        if (e.branch > t) {
                            ror(SCRATCH, SCRATCH_2, imm(cast(uint)(e.branch-t)));
                            and(STATE, STATE, SCRATCH_3);
                        }
                        else if (t > e.branch) {
                            ror(SCRATCH_3, SCRATCH_2, imm(cast(uint)(64 - t + e.branch)));
                            and(STATE, STATE, SCRATCH_3);
                        }
                    }
                }
                ldrb(LOOKUP_W, post(PTR, 1));
                ldr(SCRATCH, mem(TABLE, LOOKUP, ExtendType.LSL, true));
                orr(STATE, STATE, SCRATCH);
                and(SCRATCH, STATE, FINISH);
                b(NE, loopStart);
            bind(found);
                sub(x(0), PTR, INPUT);
                ret();
            bind(lastStep);
                lsl(STATE, STATE, imm(1));
                and(SCRATCH, STATE, FINISH);
                cmp(SCRATCH, imm(0));
                b(EQ, found);
                movn(x(0), imm(0));
                ret();
            }
            assembler.finalize();
            native = assembler.data.ptr;
        }
        return this;
    }
}

auto buildBitNFA(NFA)(Program prog) {
    auto builder = BitNFABuilder(prog.code.length);
    void collectJumpTargets(size_t i, ref bool[size_t] targets) {
        auto op = opcode(prog.code[i]);
        auto arg = argument(prog.code[i]);
        if (op == Opcode.JMP) {
            targets[(i + arg) & 0xFF_FFFF] = true;
            collectJumpTargets((i + arg) & 0xFF_FFFF, targets);
        } else if (op == Opcode.FORK) {
            targets[i + 1] = true;
            targets[(i + arg) & 0xFF_FFFF] = true;
            collectJumpTargets(i + 1, targets);
            collectJumpTargets((i + arg) & 0xFF_FFFF, targets);
        }
    }
    foreach (i, code; prog.code) with (Opcode) {
        auto op = opcode(code);
        auto arg = argument(code);
        switch(op) {
            case JMP:
            case FORK:
                bool[size_t] jumps;
                collectJumpTargets(i, jumps);
                foreach (k, v; jumps) {
                    builder.jumpTarget(i, k);
                }
                break;
            case END:
                builder.add(i, cast(char)0, cast(char)0x7F); // TODO: check non-ascii cases
                builder.end(i);
                break;
            case MARK:
                assert(false, "must trim zero-width arguments");
            case ANY, CHAR, NOTCHAR, ONE_OF, NOT_ONE_OF, INTERVALS, BIT, TRIE:
                builder.add(i, prog.chars[cast(uint)i]);
                break;
            default:
                assert(false);
        }
    }
    static if(is(NFA == NativeBitNFA)) {
        return NFA(builder.buildNative);
    }
    else {
        return NFA(builder.build);
    }   
}

struct NativeBitNFA {
    ulong[256] table;
    ulong finishMask;
    void* native;

    this(ref BitNFABuilder builder) {
        table = builder.table;
        finishMask = builder.finishMask;
        native = builder.native;
    }

    ptrdiff_t search(const(char)[] slice) {
        auto fn = cast(ptrdiff_t function(ulong, ulong*, const(char)[] slice))native;
        return fn(finishMask, table.ptr, slice);
    }
}

struct BitNFA {
    ulong[256] table;
    SIHT jumps;
    ulong jumpMask;
    ulong finishMask;

    this(ref BitNFABuilder builder) {
        table = builder.table;
        jumps = builder.jumps;
        jumpMask = builder.jumpMask;
        finishMask = builder.finishMask;
    }
    
    ptrdiff_t search(const(char)[] slice) {
        ulong state = ulong.max;
        const(char)* ptr = slice.ptr;
        size_t len = slice.length;
        for (size_t idx = 0; idx < len; idx++) {
            state <<= 1;
            /*import std.stdio;
            writefln("S %b", state);
            writefln("J %b", jumpMask);*/
            auto m = state | jumpMask;
            /*
            writefln("T %b", jumps[m]);
            writefln("M %b", table[ptr[idx]]);
            */
            state &= jumps[m];
            state |= table[ptr[idx]];
            //writefln("-----");
            if ((finishMask & state) == 0) {
                return idx;
            }
        }
        state <<= 1;
        auto m = state | jumpMask;
        state &= jumps[m];
        if ((finishMask & state) == 0) {
            return slice.length;
        }
        return -1;
    }
}

version(unittest)
auto bitNFA(string pattern) {
    import rewind.re.parser;
    auto ast = parse(pattern);
    auto pp = compile(ast);
    auto trimmed = pp.forward.stripZeroWidth();
    return buildBitNFA!BitNFA(trimmed);
}

version(unittest)
auto nativeBitNFA(string pattern) {
    import rewind.re.parser;
    auto ast = parse(pattern);
    auto pp = compile(ast);
    auto trimmed = pp.forward.stripZeroWidth();
    return buildBitNFA!NativeBitNFA(trimmed);
}

unittest {    
    auto bit = bitNFA("a+b");
    assert(bit.search("aab") == 3);
    assert(bit.search("aaa") == -1);
    assert(bit.search("b") == -1);
    auto bit2 = bitNFA("a+b+c");
    assert(bit2.search("abc") == 3);
    assert(bitNFA("a*b*c").search("abc") == 3);
    assert(bitNFA("a*b*c").search("abca") == 3);
    assert(bitNFA("a*b*").search("abc") == 0);
}

unittest {
    auto bit = nativeBitNFA("aaab");
    assert(bit.search("aaab") == 4);
    assert(nativeBitNFA("a+b").search("aaab") == 4);
    assert(nativeBitNFA("a*b").search("aab") == 3);
}