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

final class Empty : Matcher {
    bool exact() { return true; }
    bool realMatches(const(char)[] slice) { return true; }
    bool realHasMatch(const(char)[] slice) { return true; }
    const(char)[] realLocate(const(char)[] slice) { return null; }
    Captures realFullyMatch(ref const(char)[] slice) {
        if (slice.length > 0) {
            const cap = slice[0..1];
            slice = slice[1..$];
            return Captures(cap);
        }
        return Captures();
    }
}

final class Char : Matcher {
    private char ch;
    private bool exact;
    this(char ch, bool exact) {
        this.ch = ch;
        this.exact = exact;
    }
    bool exact(){ return exact; }
    bool realMatches(const(char)[] slice) {
        return slice.length > 0 ? slice[0] == ch : false;
    }
    bool realHasMatch(const(char)[] slice) {
        import core.stdc.string;
        return memchr(slice.ptr, slice.length, ch) != null;
    }

}