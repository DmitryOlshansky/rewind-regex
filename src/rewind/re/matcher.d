module rewind.re.matcher;

import rewind.re.match;

interface Matcher {
    bool exact();
    bool realMatches(const(char)[] slice);
    bool realHasMatch(const(char)[] slice);
    const(char)[] realLocate(const(char)[] slice);
    bool realFullyMatch(ref const(char)[] slice, ref Captures captures);
    Matcher next(); // next matcher in the chain
}

bool match(Matcher matcher, ref const(char)[] slice, ref Captures captures) {
    return matcher.realFullyMatch(slice, captures);
}

bool matches(Matcher matcher, const(char)[] slice) {
    return matcher.realMatches(slice);
}

bool hasMatch(Matcher matcher, const(char)[] slice) {
    return matcher.realHasMatch(slice);
}

bool locate(Matcher matcher, ref const(char)[] slice) {
    auto p = matcher.realLocate(slice);
    if (p == null) return false;
    else {
        slice = p;
        return true;
    }
}

final class Empty : Matcher {
    private Matcher next_;
    bool exact() { return true; }
    bool realMatches(const(char)[] slice) { return true; }
    bool realHasMatch(const(char)[] slice) { return true; }
    const(char)[] realLocate(const(char)[] slice) { return null; }
    bool realFullyMatch(ref const(char)[] slice, ref Captures captures) {
        if (slice.length > 0) {
            const cap = slice[0..1];
            slice = slice[1..$];
            return true;
        }
        return false;
    }
    Matcher next(){ return next_; }
}

final class Char : Matcher {
    import core.stdc.string;
    private char ch;
    private bool exact_;
    private Matcher next_;

    this(char ch, bool exact) {
        this.ch = ch;
        this.exact_ = exact;
    }
    bool exact(){ return exact_; }
    bool realMatches(const(char)[] slice) {
        return slice.length > 0 ? slice[0] == ch : false;
    }
    bool realHasMatch(const(char)[] slice) {
        return memchr(slice.ptr, ch, slice.length) != null;
    }
    const(char)[] realLocate(const(char)[] slice) {
        auto p = cast(char*)memchr(slice.ptr, ch, slice.length);
        return p == null ? null : slice[p - slice.ptr .. $];
    }
    bool realFullyMatch(ref const(char)[] slice, ref Captures captures) {
        auto p = cast(char*)memchr(slice.ptr, ch, slice.length);
        if (p != null) {
            captures[0] = slice[p - slice.ptr .. $];
        }
        return p != null;
    }
    Matcher next(){ return next_; }
}
/*
class Thompson : Matcher {
    import rewind.re.re;
    private uint[] code;
    private Matcher _next;

    this(uint[] code, Matcher next) {
        this.code = code;
        this._next = next;
    }
    override bool exact() => true;
    override bool realMatches(const(char)[] slice) {
        return code.thompson(slice);
    }
    override bool realHasMatch(const(char)[] slice) {
        foreach (size_t i, dchar ch; slice) {
            auto p = slice[i..$];
            if (code.thompson(p)) return true;
        }
        return false;
    }
    override const(char)[] realLocate(const(char)[] slice) {
        foreach (size_t i, dchar ch; slice) {
            auto p = slice[i..$];
            if (code.thompson(p)) return p;
        }
        return null;
    }
    override Captures realFullyMatch(ref const(char)[] slice) {
        foreach (size_t i, dchar ch; slice) {
            auto p = slice[i..$];
            if (code.thompson(p)) {
                slice = p;
                return [p];
            }
        }
        return null;
    }
    override Matcher next() => _next;
}

unittest {
    import rewind.re.ir;
    ubyte[] code;
    with (Opcode) {
        encode!CHAR(code, 'a');
        encode!CHAR(code, 'z');
    }
    auto m = new Backtracking(code, null);
    assert(m.matches("az"));
    assert(m.hasMatch("aaaza"));
    const(char)[] test = "AAAzzzaza";
    assert(m.locate(test));
    const(char)[] test2 = "az";
    auto s = m.match(test2);
    // assert(s == ["az"]);
}

unittest {
    import rewind.re.ir;
    ubyte[] code;
    with (Opcode) {
        encode!CHAR(code, 'a');
        encode!CHAR(code, 'z');
    }
    auto m = new Thompson(code, null);
    assert(m.matches("az"));
    assert(m.hasMatch("aaaza"));
    const(char)[] test = "AAAzzzaza";
    assert(m.locate(test));
    const(char)[] test2 = "az";
    auto s = m.match(test2);
}
*/