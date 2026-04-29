module rewind.re.bench;

import rewind.re.bytecode, rewind.re.thompson, rewind.re.bitnfa, rewind.re.codegen, rewind.re.parser,
    rewind.re.shiftor, rewind.re.prefilter;

version(unittest) {}
else {

ref scramble(T)(T arg) {
    scramble(arg);
}

ref scramble(T)(ref T arg) {
    version(X86_64) {
        asm {
            naked;
            mov RAX, RDI;
            ret;
        }
    }
    else version(AArch64) {
        import ldc.llvmasm;
        immutable(char)[]* ptr;
        __asm("mov $0, $1", "r,r", ptr, arg);
        return *ptr;
    }
}

void synthetic() {
    import std.datetime.stopwatch, std.stdio;
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        size_t start = code(CHAR, 'a');
        code(CHAR, 'b');
        size_t forked = code(FORK, 0);
        code(CHAR, 'c');
        code(END, 1);
        fixup(forked, start);
    }
    auto fwd = compile(parse("(ab)+(ab)+(ab)+(ab)+c")).forward;
    auto stripped = stripZeroWidth(fwd);
    auto bitNFA = buildBitNFA!BitNFA(stripped);
    auto nativeBitNFA = buildBitNFA!NativeBitNFA(stripped);
    auto interpretted = builder.toVM(false);
    auto native = builder.toVM(true);
    auto haystack = "abababababababababc";
    auto shiftOr = buildShiftOr!ScalarBuilder(haystack);
    auto vectorShiftOr = buildShiftOr!SimdBuilder(haystack);
    bool testInterpretted() {
        scramble(haystack);
        scramble(interpretted);
        return interpretted.run(haystack, null);
    }
    bool testNative() {
        scramble(haystack);
        scramble(native);
        return native.run(haystack, null);
    }
    bool testBitNFA() {
        scramble(haystack);
        scramble(bitNFA);
        return bitNFA.search(haystack) > 0;
    }
    bool testNativeBitNFA() {
        scramble(haystack);
        scramble(bitNFA);
        return nativeBitNFA.search(haystack) > 0;
    }
    bool testShiftOR() {
        scramble(haystack);
        scramble(shiftOr);
        return shiftOr.search(haystack) > 0;
    }
    bool testVectorShiftOR() {
        scramble(haystack);
        scramble(vectorShiftOr);
        return vectorShiftOr.search(haystack) > 0;
    }
    auto timings = benchmark!(
        () { return scramble(testInterpretted()); },
        () { return scramble(testNative()); },
        () { return scramble(testBitNFA()); },
        () { return scramble(testNativeBitNFA()); },
        () { return scramble(testShiftOR()); },
        () { return scramble(testVectorShiftOR()); }
    )(1_000_000);
    writeln("Interpretted ", timings[0]);
    writeln("Native ", timings[1]);
    writeln("BitNFA ", timings[2]);
    writeln("Native BitNFA ", timings[3]);
    writeln("Scalar Shiftor ", timings[4]);
    writeln("Vector Shiftor ", timings[5]);
}

void realistic() {
    import std.datetime.stopwatch, std.stdio;
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        size_t start = code(CHAR, 'a');
        size_t forked = code(FORK, 0);
        code(CHAR, 'b');
        code(END, 1);
        fixup(forked, start);
    }
    auto needle = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab";
    auto fwd = compile(parse("a*a*a*a*b")).forward;
    auto stripped = stripZeroWidth(fwd);
    auto bitNFA = buildBitNFA!BitNFA(stripped);;
    auto nativeBitNFA = buildBitNFA!NativeBitNFA(stripped);
    auto interpretted = builder.toVM(false);
    auto native = builder.toVM(true);
    auto shiftOr = buildShiftOr!ScalarBuilder(needle);
    auto vectorShiftOr = buildShiftOr!SimdBuilder(needle);
    auto prefilter = Prefilter();
    prefilter.add(false, 'b');
    prefilter.end(1);
    char[] haystack = new char[1024*1024];
    haystack[] = 'a';
    haystack[$-1] = 'b';
    import std.file : read, write;
    write("data.dat", haystack);
    haystack = cast(char[])read("data.dat");
    bool testInterpretted() {
        scramble(haystack);
        scramble(interpretted);
        return interpretted.run(haystack, null);
    }
    bool testNative() {
        scramble(haystack);
        scramble(native);
        return native.run(haystack, null);
    }
    bool testBitNFA() {
        scramble(haystack);
        scramble(bitNFA);
        return bitNFA.search(haystack) > 0;
    }
    bool testNativeBitNFA() {
        scramble(haystack);
        scramble(bitNFA);
        return nativeBitNFA.search(haystack) > 0;
    }
    bool testShiftOR() {
        scramble(haystack);
        scramble(shiftOr);
        return shiftOr.search(haystack) > 0;
    }
    bool testVectorShiftOR() {
        scramble(haystack);
        scramble(vectorShiftOr);
        return vectorShiftOr.search(haystack) > 0;
    }
    bool testPrefilter() {
        scramble(haystack);
        scramble(prefilter);
        return prefilter.find(haystack) > 0;
    }
    bool testPrefilterBB() {
        scramble(haystack);
        return rewindRePrefilterBB(haystack.ptr, haystack.ptr+haystack.length, 'a', 'b', needle.length).offset > 0;
    }
    bool testMemChr() {
        import core.stdc.string;
        scramble(haystack);
        return memchr(haystack.ptr, 'b', haystack.length) != null;
    }
    auto timings = benchmark!(
        () { return scramble(testInterpretted()); },
        () { return scramble(testNative()); },
        () { return scramble(testBitNFA()); },
        () { return scramble(testNativeBitNFA()); },
        () { return scramble(testShiftOR()); },
        () { return scramble(testVectorShiftOR()); },
        () { return scramble(testPrefilter()); },
        () { return scramble(testPrefilterBB()); },
        () { return scramble(testMemChr()); }
    )(1);
    size_t i = 0;
    writeln("Interpretted ", timings[i++]);
    writeln("Native ", timings[i++]);
    writeln("BitNFA ", timings[i++]);
    writeln("Native BitNFA ", timings[i++]);
    writeln("Scalar Shiftor ", timings[i++]);
    writeln("Vector Shiftor ", timings[i++]);
    writeln("Prefilter ", timings[i++]);
    writeln("PrefilterBB ", timings[i++]);  
    writeln("memchr ", timings[i++]);
}

void main() {
    import std.stdio;
    writeln("Small haystack:");
    synthetic();
    writeln("Large haystack:");
    realistic();
}

}