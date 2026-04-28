module rewind.re.prefilter;

struct Prefilter {
    ubyte[64] tables;
    size_t length;

    void add(bool last, char ch) {
        size_t offset = last ? 32 : 0;
        auto table = tables.ptr + offset;
        table[ch/8] |= 1 << (ch%8);
    }

    void end(size_t len) {
        length = len;
    }

    ptrdiff_t find(const(char)[] slice) {
        return rewindRePrefilterTT(slice.ptr, slice.ptr+slice.length, length, tables.ptr, tables.ptr+32).offset;
    }
}

struct FilterResult {
    long offset;
    ulong mask;
}

extern(C) @nogc nothrow FilterResult rewindRePrefilterTT(const(char)* start, const(char)* end, size_t length, 
    const(ubyte)* first, const(ubyte)* last);

extern(C) @nogc nothrow FilterResult rewindRePrefilterBB(const(char)* start, const(char)* end, ubyte first, ubyte last, ulong len);

unittest {
    char[] haystack = new char[256];
    haystack[] = 'A';
    haystack[$-37] = 'B';
    Prefilter prefilter;
    prefilter.add(false, 'B');
    prefilter.end(1);
    //assert(prefilter.find(haystack) == haystack.length-32);
    import std.stdio;
    auto filt = rewindRePrefilterBB(haystack.ptr, haystack.ptr+haystack.length, 'A', 'B', 32);
    writefln("%d %b", filt.offset, filt.mask);
}
