module rewind.re.bytecode;

import std.array, std.range, std.uni;

import rewind.re.impl.stack;


enum Opcode : ubyte {
    ANY = 0,
    CHAR,
    NOTCHAR,
    ONE_OF,
    NOT_ONE_OF,
    INTERVALS,
    BIT,
    TRIE,
    MARK,

    JMP,
    FORK,

    END,

    MERGE_POINT = 0x80
}

struct BytecodeBuilder {
    Appender!(uint[]) app;
    this(int capacity) {
        app = appender!(uint[])();
        app.reserve(capacity);
    }

    size_t offset() {return app.length; }

    size_t code(Opcode op, int value) {
        app ~= (op << 24) | (cast(uint)value & 0xFF_FFFF); // negative values are clamped to 24 bits
        return app.data.length-1;
    }

    size_t raw(uint value) {
        app ~= value;
        return app.data.length-1;
    }

    size_t code(CodepointSet set) {
        auto inv = set.inverted;
        auto ivals = set.byInterval.array;
        size_t ofs = app.data.length;
        if (set.length == 1) {
            code(Opcode.CHAR, set.byCodepoint.take(1).front);
        } else if (inv.length == 1) {
            code(Opcode.NOTCHAR, set.byCodepoint.take(1).front);
        } else if(set.length < 4) {
            code(Opcode.ONE_OF, cast(int)set.length);
            foreach (dchar ch; set.byCodepoint) {
                raw(ch);
            }
        } else if(inv.length < 4) {
            code(Opcode.NOT_ONE_OF, cast(int)inv.length);
            foreach (dchar ch; inv.byCodepoint) {
                raw(ch);
            }
        } else if(ivals.length < 4) {
            code(Opcode.INTERVALS, cast(int)ivals.length);
            foreach (ival; ivals) {
                raw(ival[0]);
                raw(ival[1]);
            }
        } else if (ivals[$-1][1] <= 0x80) {
            code(Opcode.BIT, 4);
            uint[4] values;
            foreach (ch; set.byCodepoint) {
                values[ch/32] |= 1<<(ch % 32);
            }
            foreach (v; values) {
                raw(v);
            }
        } else {
            code(Opcode.TRIE, 0); //TODO: support trie table
        }
        return ofs;
    }

    void fixup(size_t idx, size_t dest) {
        app.data[idx] = (app.data[idx] & 0xFF00_0000) | ((dest - idx) & 0xFF_FFFF);
    }

    uint[] build() {
        return app.data;
    }
}

size_t setMergePoints(uint[] code) {
    int pc = 0;
    bool[] passes = new bool[code.length];
    Stack!int threads;
    size_t mergePoints = 0;
L_outer:
    while (pc < code.length) {
        auto op = (code[pc] >> 24) & 0x7F;
        auto val = code[pc] & 0xFF_FFFF;
        while (passes[pc] == true) { // execution passes more then once
            mergePoints++;
            code[pc] |= (1<<31);
            if (threads.empty) break L_outer;
            pc = threads.pop();
        }
        passes[pc] = true;
        switch(op) with (Opcode) {
            case ANY:
            case CHAR:
            case NOTCHAR:
            case TRIE:
            case MARK:
                pc++;
                break;
            case ONE_OF:
            case NOT_ONE_OF:
                pc += 1 + val;
                break;
            case INTERVALS:
                pc += 1 + 2 * val;
                break;
            case BIT:
                pc += 5;
                break;
            case JMP:
                pc = (pc + val) & 0xFF_FFFF;
                break;
            case FORK:
                threads.push((pc + val) & 0xFF_FFFF);
                pc++;
                break;
            case END:
                pc++;
                break L_outer;
            default:
                assert(false);
        }
    }
    if (!threads.empty) {
        pc = threads.pop();
        goto L_outer;
    }
    return mergePoints;
}

string decode(uint[] code) pure {
    import std.format, std.algorithm, std.conv, std.range;
    auto app = appender!(char[])();
    size_t pc = 0;
    string charRepr(uint value)  {
        return isGraphical(cast(dchar)value) ? "'"~(cast(dchar)value).to!string~"'" : format("0x%x", value);
    }
    while (pc < code.length) {
        auto op = (code[pc] >> 24) & 0x7F;
        auto mergePoint = code[pc] & (1<<31);
        auto val = code[pc] & 0xFF_FFFF;
        formattedWrite(app, "%d\t", pc);
        switch(op) with(Opcode) {
            case ANY:
                app.put("ANY");
                pc++;
                break;
            case CHAR:
                formattedWrite(app, "CHAR %s", charRepr(val));
                pc++;
                break;
            case NOTCHAR:
                formattedWrite(app, "NOT_CHAR %s", charRepr(val));
                pc++;
                break;
            case ONE_OF:
                formattedWrite(app, "ONE_OF %( %s, %)", code[pc+1..pc+1+val].map!(x => charRepr(x)));
                pc += 1 + val;
                break;
            case NOT_ONE_OF:
                formattedWrite(app, "NOT_ONE_OF %( %s, %)", code[pc+1..pc+1+val].map!(x => charRepr(x)));
                pc += 1 + val;
                break;
            case INTERVALS:
                formattedWrite(app, "INTERVALS %( %s, %)", 
                    code[pc+1..pc+1+2*val].chunks(2).map!(x => charRepr(x[0]) ~ ".." ~ charRepr(x[1]-1))
                );
                pc += 1 + 2 * val;
                break;
            case BIT:
                formattedWrite(app, "BIT %( %x, %)", code[pc+1..pc+5]);
                pc += 5;
                break;
            case TRIE:
                formattedWrite(app, "TRIE %d", val);
                pc++;
                break;
            case MARK:
                formattedWrite(app, "MARK %d", val);
                pc++;
                break;
            case JMP:
                auto target = (val + pc) & 0xFF_FFFF;
                formattedWrite(app, "JMP => %d", target);
                pc++;
                break;
            case FORK:
                auto target = (val + pc) & 0xFF_FFFF;
                formattedWrite(app, "FORK => %d", target);
                pc++;
                break;
            case END:
                formattedWrite(app, "END %d", val);
                pc++;
                break;
            default:
                assert(false);
        }
        if (mergePoint) {
            app.put(" MERGE POINT");
        }
        app.put("\n");
    }
    return app.data.idup;
}

unittest {
    auto builder = BytecodeBuilder(1);
    string result = "0\tANY
1\tCHAR 'a'
2\tNOT_CHAR 'b'
3\tONE_OF  \"'a'\",  \"'b'\" MERGE POINT
6\tINTERVALS  \"'a'..'z'\"
9\tNOT_ONE_OF  \"'a'\",  \"'d'\"
12\tBIT  0,  0,  0,  400052
17\tJMP => 19
18\tCHAR 'z'
19\tFORK => 3
20\tMARK 42
21\tEND 1
";
    with (Opcode) with(builder) {
        code(ANY, 0);
        code(CHAR, 'a');
        code(NOTCHAR, 'b');
        size_t forkDest = code(CodepointSet('a', 'a'+1, 'b', 'b'+1));
        code(CodepointSet('a', 'z'+1));
        code(CodepointSet('a', 'a'+1, 'd', 'd'+1).inverted);
        code(CodepointSet('a', 'a'+1, 'd', 'd'+1, 'f', 'f'+1, 'v', 'v'+1));
        code(JMP, 2);
        code(CHAR, 'z');
        size_t forkStart = code(FORK, 0);
        fixup(forkStart, forkDest);
        code(MARK, 42);
        code(END, 1);
    }
    uint[] code = builder.build;
    size_t mergePoints = code.setMergePoints();
    assert(mergePoints == 1);
    assert(decode(code) == result);
}