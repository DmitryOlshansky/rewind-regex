module rewind.re.bench;

import rewind.re.bytecode, rewind.re.thompson, rewind.re.bitnfa, rewind.re.codegen, rewind.re.parser,
    rewind.re.shiftor;

version(unittest) {}
else {

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

void main() {
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
    auto fwd = compile(parse("(ab)+c")).forward;
    auto stripped = stripZeroWidth(fwd);
    auto bitNFA = buildBitNFA(stripped);
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
        () { return testInterpretted(); },
        () { return testNative(); },
        () { return testBitNFA(); },
        () { return testShiftOR(); },
        () { return testVectorShiftOR(); }
    )(10_000_000);
    writeln("Interpretted ", timings[0]);
    writeln("Native ", timings[1]);
    writeln("BitNFA ", timings[2]);
    writeln("Scalar Shiftor ", timings[3]);
    writeln("Vector Shiftor ", timings[4]);
}

}