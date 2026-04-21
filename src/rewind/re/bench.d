module rewind.re.bench;

import rewind.re.bytecode, rewind.re.thompson, rewind.re.bitnfa, rewind.re.codegen, rewind.re.parser;

version(unittest) {}
else {

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
    enum haystack = "abababababababababc";
    bool testInterpretted() {
        return interpretted.run(haystack, null);
    }
    bool testNative() {
        return native.run(haystack, null);
    }
    bool testBitNFA() {
        return bitNFA.search(haystack) > 0;
    }
    auto timings = benchmark!(
        () { return testInterpretted(); },
        () { return testNative(); },
        () { return testBitNFA(); }
    )(1_000_000);
    writeln(testBitNFA());
    writeln("Interpretted ", timings[0]);
    writeln("Native ", timings[1]);
    writeln("BitNFA ", timings[2]);
}

}