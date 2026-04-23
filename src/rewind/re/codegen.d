module rewind.re.codegen;

import std.exception, std.uni;

import rewind.re.impl.stack;

import rewind.re.bytecode, rewind.re.ast;

struct Program {
    uint[] code;
    CodepointSet[uint] chars;
    int groups;
    size_t mergePoints;
}

struct ProgramPair {
    Program forward, backward;
}

auto compile(Ast pattern) {
    scope fwd = new Codegen(true);
    scope bwd = new Codegen(false);
    pattern.accept(fwd);
    pattern.accept(bwd);
    auto fwdProg = Program(fwd.code, fwd.chars, fwd.groupCounter, fwd.mergePoints);
    auto bwdProg = Program(bwd.code, bwd.chars, fwd.groupCounter, fwd.mergePoints);
    return ProgramPair(fwdProg, bwdProg);
}

class Codegen : Visitor {
private:
    bool forward;
    int groupCounter;
    size_t mergePoints;
    CodepointSet[uint] chars;
    BytecodeBuilder builder;
    uint[] code;
public:
    this(bool forward) {
        this.forward = forward;
        this.builder = BytecodeBuilder(256);
    }

    void visitAll(T)(T[] members) {
        if (forward) {
            foreach (a; members) {
                a.accept(this);
            }
        } else {
            foreach_reverse (a; members) {
                a.accept(this);
            }
        }
    }

    void visit(Pattern p) {
        builder.code(Opcode.MARK, 0); // full match is group #0
        visitAll(p.children);
        builder.code(Opcode.MARK, 1);
        builder.code(Opcode.END, 1);
        code = builder.build();
        mergePoints = code.setMergePoints();
    }

    void visit(Group g) {
        int gn = ++groupCounter;
        builder.code(Opcode.MARK, gn*2);
        g.inner.accept(this);
        builder.code(Opcode.MARK, gn*2+1);
    }

    void visit(Alt alt) {
        size_t[] finals;
        void processAlt(Ast a, bool last) {
            if (!last) {
                size_t start = builder.code(Opcode.FORK, 0);
                a.accept(this);
                size_t end = builder.code(Opcode.JMP, 0);
                finals ~= end;
                builder.fixup(start, end+1);
            } else {
                a.accept(this);
            }
        }
        // order of alternatives is the same forward or backward
        foreach(i, a; alt.alts) {
            processAlt(a, i == alt.alts.length-1);
        }
        foreach (target; finals) {
            builder.fixup(target, builder.offset);
        }
    }

    void visit(Rep rep) {
        enforce(rep.max != 0, "regex repetition maximum cannot be 0");
        if (rep.max != -1) {
            enforce(rep.min <= rep.max, "regex repetition maximum cannot be smaller then minimum");
        }
        if (rep.max != -1) {
            // simply unroll the first rep.min times
            foreach (i; 0..rep.min) {
                rep.ast.accept(this);
            }
            // FORK ===> stepOver1
            // [code x 1]
            // stepOver1:
            // FORK ===> stepOver2
            // [code x 2]
            // stepOver2: 
            // ...
            // FORK ==> stepOver{rep.max}
            // [code x rep.max]
            // stepOver{rep.max}: ... <to be generated>
            foreach (i; rep.min..rep.max) {
                size_t start = builder.code(Opcode.FORK, 0);
                rep.ast.accept(this);
                builder.fixup(start, builder.offset);
            }
        } else {
            if (rep.min > 0) { //{x, }
                // [code x 1] 
                //  ...
                // offset: [code x rep.min]
                // FORK ===> offset
                size_t offset = 0;
                foreach (i; 0..rep.min) {
                    offset = builder.offset;
                    rep.ast.accept(this);
                }
                size_t jumpBack = builder.code(Opcode.FORK, 0);
                builder.fixup(jumpBack, offset);
            } else { // {0, }
                // jumpFwd: JMP ==> jumpBwd
                // blockStart: [code]
                // jumpBwd: FORK ==> blockStart
                size_t jumpFwd = builder.code(Opcode.JMP, 0);
                size_t blockStart = builder.offset;
                rep.ast.accept(this);
                size_t jumpBack = builder.code(Opcode.FORK, 0);
                builder.fixup(jumpFwd, jumpBack);
                builder.fixup(jumpBack, blockStart);
            }
        }
    }

    void visit(Seq seq) {
        visitAll(seq.seq);
    }

    void visit(Dot d) {
        chars[cast(uint)builder.offset] = unicode.any;
        builder.code(Opcode.ANY, 0);
    }

    void visit(Char c) {
        chars[cast(uint)builder.offset] = CodepointSet(c.ch, c.ch+1);
        builder.code(Opcode.CHAR, c.ch);
    }

    void visit(CharClass cc) {
        chars[cast(uint)builder.offset] = cc.chars;
        builder.code(cc.chars);
    }
}

version(unittest)
void testCompile(string pattern, void delegate(BytecodeBuilder, BytecodeBuilder) generator) {
    import rewind.re.parser;
    auto ast = parse(pattern);
    auto prog = compile(ast);
    auto fwd = BytecodeBuilder(128);
    auto bwd = BytecodeBuilder(128);
    generator(fwd, bwd);
    void check(uint[] gen, uint[] manual, string type) {
        if (gen != manual) {
            import std.stdio;
            writeln("Generated:");
            writeln(decode(gen));
            writeln("Manual:");
            writeln(decode(manual));
            assert(false, type~" compile error in "~pattern);    
        }
    }
    auto fwdCode = fwd.build;
    fwdCode.setMergePoints();
    auto bwdCode = bwd.build;
    bwdCode.setMergePoints();
    check(prog.forward.code, fwdCode, "forward");
    check(prog.backward.code, bwdCode, "backward");
}

version(unittest)
void testCompileSym(string pattern, void delegate(BytecodeBuilder) generator) {
    testCompile(pattern, (fwd, bwd) {
        generator(fwd);
        generator(bwd);
    });
}

unittest {
    // simple sequence + group
    testCompile("ab(c)", (fwd, bwd) {
        with (fwd) with (Opcode) {
            code(MARK, 0);
            code(CHAR, 'a');
            code(CHAR, 'b');
            code(MARK, 2);
            code(CHAR, 'c');
            code(MARK, 3);
            code(MARK, 1);
            code(END, 1);
        }
        with(bwd) with (Opcode) {
            code(MARK, 0);
            code(MARK, 2);
            code(CHAR, 'c');
            code(MARK, 3);
            code(CHAR, 'b');
            code(CHAR, 'a');
            code(MARK, 1);
            code(END, 1);
        }
    });
    // simple alternatives
    testCompile("(a|b)c", (fwd, bwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            code(MARK, 2);
            size_t start = code(FORK, 0);
            code(CHAR, 'a');
            size_t toEnd = code(JMP, 0);
            size_t nextAlt = code(CHAR, 'b');
            size_t end = code(MARK, 3);
            code(CHAR, 'c');
            fixup(start, nextAlt);
            fixup(toEnd, end);
            code(MARK, 1);
            code(END, 1);
        }
        with(bwd) with (Opcode) {
            code(MARK, 0);
            code(CHAR, 'c');
            code(MARK, 2);
            size_t alt = code(FORK, 0);
            code(CHAR, 'a');
            size_t toEnd = code(JMP, 0);
            size_t altTarget = code(CHAR, 'b');
            size_t end = code(MARK, 3);
            code(MARK, 1);
            code(END, 1);
            fixup(alt, altTarget);
            fixup(toEnd, end);
        }
    });
    testCompileSym("(ab)*(ab)*", (fwd) { 
        with(fwd) with(Opcode) {
            code(MARK, 0);
            code(MARK, 1);
            code(END, 1);
        }
    });
    testCompileSym("a|b|c", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            size_t start = code(FORK, 0);
            code(CHAR, 'a');
            size_t toEnd = code(JMP, 0);
            size_t nextAlt = code(FORK, 0);
            code(CHAR, 'b');
            size_t toEnd2 = code(JMP, 0);
            size_t lastAlt = code(CHAR, 'c');
            size_t end = code(MARK, 1);
            fixup(start, nextAlt);
            fixup(nextAlt, lastAlt);
            fixup(toEnd, end);
            fixup(toEnd2, end);
            code(END, 1);
        }
    });
    // TODO: to be optimized - empty alternatives
    testCompileSym("a|", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            size_t start = code(FORK, 0);
            code(CHAR, 'a');
            size_t end = code(JMP, 0);
            size_t endOfAlt = code(MARK, 1);
            code(END, 1);
            fixup(start, endOfAlt);
            fixup(end, endOfAlt);
        }
    });
    // simple repetitions
    testCompileSym("a*", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            size_t jumpToLoop = code(JMP, 0);
            size_t loopEnd = code(CHAR, 'a');
            size_t loopStart = code(FORK, 0);
            code(MARK, 1);
            code(END, 1);
            fixup(loopStart, loopEnd);
            fixup(jumpToLoop, loopStart);
        }
    });
    testCompileSym("a+", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            size_t loopEnd = code(CHAR, 'a');
            size_t loopStart = code(FORK, 0);
            code(MARK, 1);
            code(END, 1);
            fixup(loopStart, loopEnd);
        }
    });
    testCompileSym("a{3}", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            foreach (_; 0..3) {
                code(CHAR, 'a');
            }
            code(MARK, 1);
            code(END, 1);
        }
    });
    testCompileSym("a{0,3}", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            foreach (_; 0..3) {
                size_t sideStep = code(FORK, 0);
                code(CHAR, 'a');
                fixup(sideStep, fwd.offset);
            }
            code(MARK, 1);
            code(END, 1);
        }
    });
    testCompileSym("a{1,3}", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            code(CHAR, 'a');
            foreach (_; 0..2) {
                size_t sideStep = code(FORK, 0);
                code(CHAR, 'a');
                fixup(sideStep, fwd.offset);
            }
            code(MARK, 1);
            code(END, 1);
        }
    });
    testCompileSym("a{3,}", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            code(CHAR, 'a');
            code(CHAR, 'a');
            size_t loopStart = code(CHAR, 'a');
            size_t loop = code(FORK, 0);
            fixup(loop, loopStart);
            code(MARK, 1);
            code(END, 1);
        }
    });
    testCompileSym("(a{2,})+", (fwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            size_t outerLoopStart = code(MARK, 2);
            code(CHAR, 'a');
            size_t loopStart = code(CHAR, 'a');
            size_t loop = code(FORK, 0);
            fixup(loop, loopStart);
            code(MARK, 3);
            size_t outerLoop = code(FORK, 0);
            fixup(outerLoop, outerLoopStart);
            code(MARK, 1);
            code(END, 1);
        }
    });
    testCompile("(ab)+", (fwd, bwd) {
        with (fwd) with(Opcode) {
            code(MARK, 0);
            size_t loopStart = code(MARK, 2);
            code(CHAR, 'a');
            code(CHAR, 'b');
            code(MARK, 3);
            size_t loop = code(FORK, 0);
            fixup(loop, loopStart);
            code(MARK, 1);
            code(END, 1);
        }

        with (bwd) with(Opcode) {
            code(MARK, 0);
            size_t loopStart = code(MARK, 2);
            code(CHAR, 'b');
            code(CHAR, 'a');
            code(MARK, 3);
            size_t loop = code(FORK, 0);
            fixup(loop, loopStart);
            code(MARK, 1);
            code(END, 1);
        }
    });
}



// this produces bytecode without MARK and later anchors such as start of the line / end of the line
Program stripZeroWidth(Program prog) {
    uint[] code = prog.code;
    size_t[] translation = new size_t[code.length]; // map for before --> after offsets
    uint[] stripped = new uint[code.length];
    size_t target = 0;
    foreach (pc; 0..code.length) {
        auto op = opcode(code[pc]);
        translation[pc] = target;
        if (op != Opcode.MARK) {
            stripped[target++] = code[pc];
        }
    }
    foreach (pc; 0..code.length) {
        auto op = opcode(code[pc]);
        if (op == Opcode.JMP || op == Opcode.FORK) {
            auto arg = argument(code[pc]);
            auto dest = (pc + arg) & 0xFF_FFFF;
            stripped[translation[pc]] = ((op << 24) | (translation[dest] - translation[pc]) & 0XFF_FFFF);
        }
    }
    setMergePoints(stripped);
    CodepointSet[uint] chars;
    foreach( k,v; prog.chars) {
        chars[cast(uint)translation[k]] = v;
    }
    return Program(stripped[0..target], chars, prog.groups, prog.mergePoints);
}

unittest {
    auto builder = BytecodeBuilder(128);
    with (builder) with (Opcode) {
        code(MARK, 1);
        size_t start = code(FORK, 0);
        code(MARK, 2);
        code(CHAR, 'a');
        size_t end = code(MARK, 3);
        code(CHAR, 'b');
        size_t jmp = code(JMP, 0);
        fixup(start, end);
        fixup(jmp, start);
        code(END, 1);
    }
    auto fullCode = builder.build();
    Program full;
    full.groups = 1;
    full.code = fullCode;
    full.mergePoints = setMergePoints(full.code);
    full.chars[3] = CodepointSet('a', 'a'+1);
    full.chars[5] = CodepointSet('b', 'b'+1);
    
    auto stripped = stripZeroWidth(full);
    auto strippedBuilder = BytecodeBuilder(128);
    with (strippedBuilder) with(Opcode) {
        size_t start = code(FORK, 0);
        code(CHAR, 'a');
        size_t end = code(CHAR, 'b');
        size_t jmp = code(JMP, 0);
        fixup(start, end);
        fixup(jmp, start);
        code(END, 1);
    }
    auto expected = strippedBuilder.build();
    setMergePoints(expected);
    assert(stripped.code[] == expected[]);
    assert(stripped.chars[1] == CodepointSet('a', 'a'+1));
    assert(stripped.chars[2] == CodepointSet('b', 'b'+1));
}