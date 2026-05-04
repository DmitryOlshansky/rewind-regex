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

    FilterResult find(const(char)[] slice) {
        return rewindRePrefilterTT(slice.ptr, slice.ptr+slice.length, tables.ptr, tables.ptr+32, length);
    }
}

struct FilterResult {
    long offset;
    ulong mask;
}

version(AArch64) {

extern(C) @nogc nothrow FilterResult rewindRePrefilterTT(const(char)* start, const(char)* end, 
    const(ubyte)* first, const(ubyte)* last,  ulong length);

extern(C) @nogc nothrow FilterResult rewindRePrefilterBB(const(char)* start, const(char)* end, 
    ubyte first, ubyte last, ulong length);
}

extern(C) @nogc nothrow FilterResult rewindRePrefilterTT(const(char)* start, const(char)* end, 
    const(ubyte)* first, const(ubyte)* last,  ulong length) {
    return FilterResult.init;
}

extern(C) @nogc nothrow FilterResult rewindRePrefilterBB(const(char)* start, const(char)* end, 
    ubyte first, ubyte last, ulong length) {
    asm @nogc nothrow {
        naked;
        mov RAX, RCX;
        
        ret;
    }
}

version(unittest) {
    
    void checkPos(int pos, int len, int haystackLen) {
        import core.bitop, std.conv;
        char[] haystack = new char[haystackLen];
        haystack[] = 0x7F;
        haystack[pos] = 0xFF;
        auto filt = rewindRePrefilterBB(haystack.ptr, haystack.ptr+haystack.length, 0x7F, 0xFF, len);
        if (pos >= len-1) {
            assert(filt.offset + bsf(filt.mask) == pos-len+1, text(filt.offset,  " mask ", filt.mask, " vs ", pos));
        } else {
            assert(filt.offset == -1, text(filt.offset, " mask ", filt.mask, " vs ", pos));
        }
    }

    void checkPosTable(int pos, int len, int haystackLen) {
        import core.bitop, std.conv;
        char[] haystack = new char[haystackLen];
        haystack[] = 0x7F;
        haystack[pos] = 0xFF;
        Prefilter prefilter;
        prefilter.add(false, 0x7F);
        prefilter.add(true, 0xFF);
        prefilter.end(len);
        auto filt = prefilter.find(haystack);
        if (pos >= len-1) {
            assert(filt.offset + bsf(filt.mask) == pos-len+1, text(filt.offset,  " mask ", filt.mask, " vs ", pos));
        } else {
            assert(filt.offset == -1, text(filt.offset, " mask ", filt.mask, " vs ", pos));
        }
    }
}

unittest {
    foreach(h; [255, 256])
    foreach (i; 0..255) {
        checkPos(i, 3, h);
        checkPos(i, 11, h);
        checkPos(i, 17, h);
        checkPos(i, 32, h);
    }
}

version(AArch64) {

unittest {
    foreach(h; [255, 256])
    foreach (i; 0..255) {
        checkPosTable(i, 3, h);
        checkPosTable(i, 11, h);
        checkPosTable(i, 17, h);
        checkPosTable(i, 32, h);
    }
}

}