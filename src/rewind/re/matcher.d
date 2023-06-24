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