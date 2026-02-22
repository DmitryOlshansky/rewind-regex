module rewind.re.shiftor;

struct ScalarBuilder {
private:
    ulong[256] table = ulong.max;
    ulong finishMask = 0;
    ulong length = 0;
pure nothrow public:
    void add(size_t index, char start, char end) {
        for (char i=start; i<=end; i++){
            table[i] &= ~(1UL<<index);
        }
    }

    void end(size_t index) nothrow {
        finishMask = 1UL << index;
        length = index+1;
    }

    auto build() {
        return ScalarShiftOr(this);
    }
}

struct ScalarShiftOr {
private:
    ulong[256] table;
    ulong finishMask;
    ulong length;
pure nothrow public:
    this(const ref ScalarBuilder builder) {
        table = builder.table;
        finishMask = builder.finishMask;
        length = builder.length;
    }

    ptrdiff_t search(const(char)[] slice) const {
        ulong state = ulong.max;
        const(char)* ptr = slice.ptr;
        size_t len = slice.length;
        for (size_t idx = 0; idx < len; idx++) {
            state <<= 1;
            state |= table[ptr[idx]];
            if ((finishMask & state) == 0) {
                return idx - length + 1;
            }
        }
        return -1;
    }
}

auto buildShiftOr(Builder)(const(char)[] needle) {
    auto builder = Builder();
    for (size_t i = 0; i < needle.length; i++) {
        builder.add(i, needle[i], needle[i]);
    }
    builder.end(needle.length-1);
    return builder.build();
}

ptrdiff_t find(Searcher)(const(char)[] slice, ref const Searcher searcher)  {
    return searcher.search(slice);
}

unittest {
    immutable searcher = buildShiftOr!ScalarBuilder("abc");
    import std.stdio;
    assert(find("abc", searcher) == 0);
    assert(find("aaabca", searcher) == 2);
    assert(find("bbc", searcher) == -1);
}

version(X86_64) {

import ldc.simd;

alias v4u64 = __vector(ulong[4]);

struct SimdBuilder {
private:
    v4u64[256] table = v4u64([ulong.max, ulong.max, ulong.max, ulong.max]);
    v4u64 finishMask;
    ulong length;
pure nothrow public:
    void add(size_t index, char start, char end) {
        v4u64 mask = [0, 0, 0, 0];
        mask[index/64] = 1UL<<(index%64);
        mask = ~mask;
        
        for (char i=start; i<=end; i++){
            table[i] &= mask;
        }
    }

    void end(size_t index) nothrow {
        finishMask[index/64] = 1UL << (index % 64);
        length = index+1;
    }

    auto build() {
        return SimdShiftOr(this);
    }
}

struct SimdShiftOr {
private:
    v4u64[256] table;
    v4u64 finishMask;
    ulong length;
pure nothrow public:
    this(const ref SimdBuilder builder) {
        table = builder.table;
        finishMask = builder.finishMask;
        length = builder.length;
    }

    ptrdiff_t search(const(char)[] slice) const {
        v4u64 state = v4u64([ulong.max, ulong.max, ulong.max, ulong.max]);
        v4u64 maskCarry = v4u64([0x8000_0000_0000_0000UL, 0x8000_0000_0000_0000UL, 0x8000_0000_0000_0000UL, 0]);
        const(char)* ptr = slice.ptr;
        size_t len = slice.length;
        for (size_t idx = 0; idx < len; idx++) {
            v4u64 carry = state & maskCarry;
            state <<= 1;
            carry >>= 63;
            state |= shufflevector!(v4u64, 3, 0, 1, 2)(carry, carry);
            state |= table[ptr[idx]];
            v4u64 finish = (finishMask & state);
            if ((finish[0] | finish[1] | finish[2] | finish[3]) == 0) {
                return idx - length + 1;
            }
        }
        return -1;
    }
}

unittest {
    immutable searcher = buildShiftOr!SimdBuilder("abc");
    assert(find("abc", searcher) == 0);
    assert(find("abac", searcher) == -1);
    assert(find("aaabca", searcher) == 2);
    assert(find("bbc", searcher) == -1);
    import std.range, std.array;
    auto longNeedle = chain(
        iota('a',  cast(char)('z'+1)), 
        iota('a',  cast(char)('z'+1)), 
        iota('a', cast(char)('z'+1))
    ).array;
    immutable longSearcher = buildShiftOr!SimdBuilder(longNeedle);
    auto text = longNeedle.dup;
    assert(find(text, longSearcher) == 0);
    text[75] = 'A';
    assert(find(text, longSearcher) == -1);
}

}