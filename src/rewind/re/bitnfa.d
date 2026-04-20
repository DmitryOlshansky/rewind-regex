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
    Entry[] entries;
    uint mask;
    uint items;
    uint log2Size;

    this(size_t size) {
        assert(isPow2(size) && size >= 4);
        entries = new Entry[size];
        log2Size = bsr(size);
        mask = cast(uint)(size - 1);
    }

    void insert(ulong key, ulong value) {
        if (2*items > entries.length) rehash();
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
        SIHT extended = SIHT(entries.length * 2);
        for (size_t i = 0; i < entries.length; i++) {
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
    assert(t.entries.length == 64);
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
}

auto buildBitNFA(Program prog) {
    auto builder = BitNFABuilder(prog.code.length);
    foreach (i, code; prog.code) with (Opcode) {
        auto op = opcode(code);
        auto arg = argument(code);
        switch(op) {
            case JMP:
                builder.jumpTarget(i, (i + arg) & 0xFF_FFFF);
                break;
            case FORK:
                builder.jumpTarget(i, (i + arg) & 0xFF_FFFF);
                builder.jumpTarget(i, i + 1);
                break;
            case END:
                builder.end(i-1);
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
    return BitNFA(builder.build);
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
            import std.stdio;
            writefln("S %b", state);
            writefln("J %b", jumpMask);
            auto m = state | jumpMask;
            
            writefln("T %b", jumps[m]);
            writefln("M %b", table[ptr[idx]]);
            
            state &= jumps[m];
            state |= table[ptr[idx]];
            writefln("-----");
            if ((finishMask & state) == 0) {
                return idx;
            }
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
    return buildBitNFA(trimmed);
}

unittest {    
    /*auto bit = bitNFA("a+b");
    assert(bit.search("aab") == 2);
    assert(bit.search("aaa") == -1);
    assert(bit.search("b") == -1);*/
    auto bit2 = bitNFA("a+b+c");
    assert(bit2.search("abc") == 2);
}
