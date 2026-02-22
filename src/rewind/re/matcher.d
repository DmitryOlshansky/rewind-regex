module rewind.re.matcher;

import rewind.re.captures;

interface Matcher {
    bool exact();
    bool realMatches(const(char)[] slice);
    bool realHasMatch(const(char)[] slice);
    const(char)[] realLocate(const(char)[] slice);
    Captures realFullyMatch(ref const(char)[] slice);
    Matcher next(); // next matcher in the chain
}

Captures match(Matcher matcher, ref const(char)[] slice) {
    return matcher.realFullyMatch(slice);
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
    Captures realFullyMatch(ref const(char)[] slice) {
        if (slice.length > 0) {
            const cap = slice[0..1];
            slice = slice[1..$];
            return [cap];
        }
        return null;
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
    Captures realFullyMatch(ref const(char)[] slice) {
        auto p = cast(char*)memchr(slice.ptr, ch, slice.length);
        const(char)[][] captures = [];
        captures ~= p == null ? null : slice[p - slice.ptr .. $];
        return captures;
    }
    Matcher next(){ return next_; }
}

final class Backtracking : Matcher {
    import rewind.re.ir;
    private ubyte[] code;
    private Matcher _next;

    this(ubyte[] code, Matcher next) {
        this.code = code;
        this._next = next;
    }
    override bool exact() => true;
    override bool realMatches(const(char)[] slice) {
        return code.backtracking(slice);
    }
    override bool realHasMatch(const(char)[] slice) {
        foreach (idx, ch; slice) {
            auto p = slice[idx..$];
            if (code.backtracking(p)) {
                return true;
            }
        }
        return false;
    }
    override const(char)[] realLocate(const(char)[] slice) {
        foreach (idx, ch; slice) {
            auto p = slice[idx..$];
            if (code.backtracking(p)) {
                slice = p;
                return p;
            }
        }
        return null;
    }
    override Captures realFullyMatch(ref const(char)[] slice) {
        foreach (idx, ch; slice) {
            auto p = slice[idx..$];
            if (code.backtracking(p)) {
                slice = p;
                return [p];
            }
        }
        return null;
    }
    override Matcher next() => _next;
}

class Thompson : Matcher {
    import rewind.re.ir;
    private ubyte[] code;
    private Matcher _next;

    this(ubyte[] code, Matcher next) {
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
/*
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