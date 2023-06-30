module rewind.re.ir;

import std.uni;
import rewind.re.matcher;


/++
    $(D Regex) object holds regular expression pattern in compiled form.

    Instances of this object are constructed via calls to $(D regex).
    This is an intended form for caching and storage of frequently
    used regular expressions.

    Example:

    Test if this object doesn't contain any compiled pattern.
    ---
    Regex!char r;
    assert(r.empty);
    r = regex(""); // Note: "" is a valid regex pattern.
    assert(!r.empty);
    ---

    Getting a range of all the named captures in the regex.
    ----
    import std.range;
    import std.algorithm;

    auto re = regex(`(?P<name>\w+) = (?P<var>\d+)`);
    auto nc = re.namedCaptures;
    static assert(isRandomAccessRange!(typeof(nc)));
    assert(!nc.empty);
    assert(nc.length == 2);
    assert(nc.equal(["name", "var"]));
    assert(nc[0] == "name");
    assert(nc[1..$].equal(["var"]));
    ----
+/
struct Re {
    string pattern;
    string flags;
    int ngroup;
    int[string] dict;
    ubyte[] code;
    Matcher matcher;

    this(string pattern, string flags, int ngroup, int[string] dict, ubyte[] code, Matcher matcher) {
        this.pattern = pattern;
        this.flags = flags;
        this.ngroup = ngroup;
        this.dict = dict;
        this.code = code;
        this.matcher = matcher;
    }

    Matcher engine() => matcher;

    auto withFlags(string extra) {
        auto copy = this;
        copy.flags ~= extra;
        return copy;
    }
}

enum Opcode : ubyte {
    ANY = 0,
    CHAR,
    NOTCHAR,
    CHARCLASS,
    NOTCHARCLASS,
    JMP,
    FORK,
    COUNTED_LOOP
}

void put32(ref ubyte[] dest, uint arg) {
    dest ~= arg & 0xFF;
    dest ~= (arg >> 8) & 0xFF;
    dest ~= (arg >> 16) & 0xFF;
    dest ~= (arg >> 24) & 0xFF;
}

int get32(ubyte[] code, size_t idx) {
    uint ret = (code[idx] & 0xFF);
    ret |= (code[idx+1] & 0xFF) << 8;
    ret |= (code[idx+2] & 0xFF) << 16;
    ret |= (code[idx+3] & 0xFF) << 24;
    return ret;
}

void encode(Opcode op, T...)(ref ubyte[] dest, T args) {
    import std.range;
    dest ~= op;
    ubyte[] putTable(CodepointSet set) {
        ubyte[] table;
        foreach (ch; set.byCodepoint) {
            if (table.length*8 <= ch) {
                table.length = ch / 8 + 1; 
            }
            table[ch/8] |= 1<<(ch % 8);
        }
        return table;
    }
    static if (op == Opcode.ANY) {
        //nop
    } else static if (op == Opcode.CHAR) {
        put32(dest, args[0]);
    } else static if (op == Opcode.NOTCHAR) {
        put32(dest, args[0]);
    } else static if (op == Opcode.CHARCLASS) {
        put32(dest, args[0].byCodepoint.front);
        dchar last;
        foreach (c; args[0].byCodepoint) {
            last = c;
        }
        put32(dest, last);
        dest ~= putTable(args[0]);
    } else static if (op == Opcode.NOTCHARCLASS) {
        auto inv = args[0].invert;
        put32(dest, inv.byCodepoint.front);
        dchar last;
        foreach (c; inv.byCodepoint) {
            last = c;
        }
        put32(dest, last);
        dest ~= putTable(inv);
    } else static if (op == Opcode.JMP) {
        put32(dest, args[0]);
    } else static if (op == Opcode.FORK) {
        put32(dest, args[0]);
        put32(dest, args[1]);
    } else static if (op == Opcode.COUNTED_LOOP) {
        put32(dest, args[0]);
        put32(dest, args[1]);
        put32(dest, args[2]);
    } else {
        static assert(false, "Unexpected opcode " ~ op.to!string);
    }
}

string decode(ubyte[] code) {
    import std.format, std.conv;
    size_t index = 0;
    string listing; 
    while (index < code.length) {
        ubyte op = code[index];
        switch (op) with(Opcode) {
            case ANY:
                listing ~= "%d\t%s\n".format(index, "ANY");
                index++;
                break;
            case CHAR:
                auto ch = get32(code, index);
                listing ~= "%d\t%s(%c)\n".format(index, "CHAR", cast(dchar)ch);
                index += 5;
                break;
            case NOTCHAR:
                auto ch = get32(code, index);
                listing ~= "%d\t%s(%c)\n".format(index, "NOTCHAR", cast(dchar)ch);
                index += 5;
                break;
            case CHARCLASS:
                auto first = get32(code, index + 1);
                auto last = get32(code, index + 5);
                auto len = last - first;
                auto table = code[5 .. len + 5]; 
                listing ~= "%d\t%s(%c, %c)\t%s\n".format(
                    index, 
                    "CHARCLASS",
                    cast(dchar)first,
                    cast(dchar)last,
                    table
                );
                index += 5 + len;
                break;
            case NOTCHARCLASS:
                auto first = get32(code, index + 1);
                auto last = get32(code, index + 5);
                auto len = last - first;
                auto table = code[9 .. len + 9]; 
                listing ~= "%d\t%s(%c, %c)\t%s\n".format(
                    index, 
                    "NOTCHARCLASS",
                    cast(dchar)first,
                    cast(dchar)last,
                    table
                );
                index += 9 + len;
                break;
            case JMP:
                auto offset = get32(code, index + 1);
                listing ~= "%d\t%s => %s".format(index, "JMP", offset);
                index += 5;
                break;
            case FORK:
                auto left = get32(code, index + 1);
                auto right = get32(code, index + 5);
                listing ~= "%d\t%s => %s => %s".format(index, "FORK", left, right);
                index += 9;
                break;
            case COUNTED_LOOP:
                auto min = get32(code, index + 1);
                auto max = get32(code, index + 5);
                auto target = get32(code, index + 9);
                listing ~= "%d\t%s (%s,%s) => %s".format(index, "COUNTED_LOOP", min, max, target);
                index += 13;
                break;
            default:
                assert(false, "Reached unknown opcode "~op.to!string);
        }
    }
    return listing;
}

bool backtracking(ubyte[] code, ref const(char)[] slice) {
    struct State {
        int pc, idx;
    }
    int pc = 0;
    int idx;
    State[] stack;
    void backtrack() {
        if (stack.length == 0) {
            pc = cast(int)code.length;
            return;
        }
        auto p = stack[$-1];
        pc = p.pc;
        idx = p.idx;
        stack = stack[0 .. $-1];
        stack.assumeSafeAppend();
    }

    while (pc < code.length) {
        auto op = code[pc];
        switch (op) with (Opcode) {
            case ANY:
                if (idx < slice.length) {
                    idx++;
                    pc++;
                } else {
                    backtrack();
                } 
                break;
            case CHAR:
                auto ch = get32(code, pc + 1);
                if (slice[idx] == ch) {
                    pc += 5;
                    idx++;
                } else {
                    backtrack();
                }
                break;
            case NOTCHAR:
                auto ch = get32(code, pc + 1);
                if (slice[idx] != ch) {
                    pc += 5;
                    idx++;
                } else {
                    backtrack();
                }
                break;
            case CHARCLASS:
                auto min = get32(code, pc + 1);
                auto max = get32(code, pc + 5);
                auto len = max - min;
                auto table = code[pc + 9 .. pc + len + 9];
                if (table[slice[idx]/8] & (1<<(slice[idx]%8))) {
                    pc += 9 + len;
                    idx++;
                } else {
                    backtrack();
                }
                break;
            case NOTCHARCLASS:
                auto min = get32(code, pc + 1);
                auto max = get32(code, pc + 5);
                auto len = max - min;
                auto table = code[pc + 9 .. pc + len + 9];
                if (!(table[slice[idx]/8] & (1<<(slice[idx]%8)))) {
                    pc += 9 + len;
                    idx++;
                } else {
                    backtrack();
                }
                break;
            case JMP:
                pc += get32(code, pc + 1);
                break;
            case FORK:
                auto left = get32(code, pc + 1);
                auto right = get32(code, pc + 5);
                stack ~= State(right, idx);
                pc = left;
                break;
            case COUNTED_LOOP:
                assert(false, "TODO!");
            default:
                assert(false, "Unsupported for now");
        }
    }
    slice = slice[idx..$];
    return true;
}

unittest {
    import std.stdio;
    ubyte[] code;
    with (Opcode) {
        encode!ANY(code);
        encode!(CHAR)(code, 'a');
        encode!(NOTCHAR)(code, 'b');
        encode!(CHARCLASS)(code, CodepointSet('a', 'z'+1));
        encode!(JMP)(code, 1);
        encode!(CHAR)(code, 'z');
        encode!(COUNTED_LOOP)(code, 1, 2, 41);
        encode!(FORK)(code, 41, 0);
        writeln(decode(code));
    }
}

unittest {
    ubyte[] code;
    const(char)[] str = "abc";
    with (Opcode) {
        encode!CHAR(code, 'a');
        encode!CHAR(code, 'b');
        encode!ANY(code);
    }
    assert(code.backtracking(str));
}

unittest {
    ubyte[] code;
    const(char)[] str = "aaaabc";
    with (Opcode) {
        encode!CHAR(code, 'a');
        encode!FORK(code, 0, 14);
        encode!CHAR(code, 'b');
        encode!CHAR(code, 'c');
    }
    assert(code.backtracking(str));
    assert(str == null);
}

bool thompson(ubyte[] code, ref const(char)[] slice) {
    static import std.utf;
    struct State {
        size_t pc, idx;
        State* next;
    }
    State* cur = new State(0,0,null);
    State* freelist = null;
    for (;;) {
        if (cur.pc == code.length) return true;
        while (cur != null) {
            auto op = code[cur.pc];
            switch (op) with (Opcode) {
                case ANY:
                    cur.pc++;
                    std.utf.decode(slice, cur.idx);
                    break;
                case CHAR:
                    auto ch = std.utf.decode(slice, cur.idx);
                    if (ch != get32(code, cur.pc + 1)) {
                        auto tail = freelist;
                        cur.next = tail;
                        freelist = cur;
                        cur = cur.next;
                        if (cur == null) return false;
                        break;
                    }
                    cur.pc++;
                    cur = cur.next;
                    break;
                case FORK:
                    auto left = get32(code, cur.pc + 1);
                    auto right = get32(code, cur.pc + 5);
                    cur.next = new State(right, cur.idx, null);
                    cur.pc = left;
                    break;
                default:
                    assert(false, "TODO!");
            }
        }
    }
}