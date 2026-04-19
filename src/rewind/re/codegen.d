module rewind.re.codegen;

import rewind.re.impl.stack;

import rewind.re.bytecode, rewind.re.ast;

struct Program {
    uint[] forward, backward;
    int groups;
    int mergePoints;
}

auto compile(Pattern pattern) {
    auto fwd = Codegen(true);
    auto bwd = Codegen(false);
    pattern.accept(fwd);
    pattern.accept(bwd);
    return Program(fwd.code, bwd.code, fwd.groupCounter, fwd.mergePoints);
}

class Codegen : Visitor {
private:
    bool forward;
    int groupCounter;
    int mergePoints;
    BytecodeBuilder builder;
    uint[] code;
public:
    this(bool forward) {
        this.forward = true;
        this.builder = BytecodeBuilder(256);
    }

    void visit(Pattern p) {
        builder.code(Opcode.MARK, 0); // full match is group #0
        if (forward) {
            foreach (a; p.children) {
                a.accept(this);
            }
        } else {
            foreach_reverse (a; p.children) {
                a.accept(this);
            }
        }
        builder.code(Opcode.MARK, 1);
        builder.code(Opcode.END, 1);
        code = builder.build();
        mergePoints = code.setMergePoints();
    }

    void visit(Group g) {
        int gn = ++groupCounter;
        builder.code(Opcode.MARK, gn*2);
        if (forward) {
            foreach (a; g.inner){
                a.accept(this);
            }
        } else {
            foreach_reverse (a; g.inner) {
                a.accept(this);
            }
        }
        builder.code(Opcode.MARK, gn*2+1);
    }

    void visit(Alt alt) {
        int[] finals;
        void processAlt(Ast a, bool last) {
            if (!last) {
                size_t start = builder.code(Opcode.FORK, 0);
                a.accept(this);
                size_t end = builder.code(Opcode.JMP, 0);
                finals ~= end;
                builder.fixup(start, cast(int)((end+1) - start));
            } else {
                a.accept(this);
            }
        }
        if (forward) {
            foreach(i, a; alt.alts) {
                processAlt(a, i == alt.alts.length-1);
            }
        } else {
            foreach_reverse(i, a; alt.alts) {
                processAlt(a, i == alt.alts.length-1);
            }   
        }
        foreach (target; finals) {
            builder.fixup(target, cast(int)(builder.offset - target));
        }
    }

    void visit(Rep rep) {
        if (rep.min == 0) {
            size_t start = builder.code(Opcode.JMP, 0);
        }
    }

    void visit(Seq seq) {
        if (forward) {
            foreach(a; seq.seq) {
                a.accept(this);
            }
        } else {
            foreach_reverse(a; seq.seq) {
                a.accept(this);
            }
        }
    }

    void visit(Dot d) {
        builder.code(Opcode.ANY, 0);
    }

    void visit(Char c) {
        builder.code(Opcode.CHAR, c.ch);
    }

    void visit(CharClass cc) {
        builder.code(cc);
    }
}