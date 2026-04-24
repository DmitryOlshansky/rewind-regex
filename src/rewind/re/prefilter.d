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
        return rewindRePrefilter(slice.ptr, slice.ptr+slice.length, length, tables.ptr, tables.ptr+32);
    }
}

extern(C) @nogc nothrow ptrdiff_t rewindRePrefilter(const(char)* start, const(char)* end, size_t length, 
    const(ubyte)* first, const(ubyte)* last);


unittest {
    char[] haystack = new char[256];
    haystack[] = 'A';
    haystack[$-17] = 'B';
    Prefilter prefilter;
    prefilter.add(false, 'B');
    prefilter.end(1);
    assert(prefilter.find(haystack) == haystack.length-32);
}