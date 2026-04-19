module rewind.re.ast;

import std.array, std.format, std.conv, std.uni, std.algorithm;

import rewind.re.bytecode;

abstract class Ast {
    static int counter = 0;
    void accept(Visitor visitor);
    string toDot();
    string repr();
}

interface Visitor {
    void visit(Pattern p);
    void visit(Group g);
    void visit(Alt a);
    void visit(Seq s);
    void visit(Rep rep);
    void visit(Char c);
    void visit(CharClass cc);
    void visit(Dot dot);
}

class Pattern : Ast {
    Ast[] children;
    
    this(Ast[] children) {
        this.children = children;
    }

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        auto result = "digraph Pattern {\n";
        result ~= format("f%s", counter);
        foreach(ast; children) {
            result ~= ast.toDot();
        }
        result ~= "}\n";
        return result;
    }

    override string repr() {
        return children.map!(x => x.repr()).join("");
    }
}

class Group : Ast {
    Ast inner;

    this(Ast inner) {
        this.inner = inner;
    }

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        return inner.toDot(); // TODO: add grouping to DOT
    }

    override string repr() {
        return "(" ~ inner.repr ~ ")";
    }
}

class Seq : Ast {
    Ast[] seq;

    this(Ast[] seq) {
        this.seq = seq;
    }

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        auto self = counter;
        auto result = format("f%d [label=\"%s\"]\n", counter++, repr());
        foreach (ast; seq) {
            auto cnt = counter;
            result ~= ast.toDot();
            result ~= format("f%d -> f%d\n", self, cnt);
        }
        return result;
    }

    override string repr() {
        return seq.map!(x => x.repr()).join("");
    }
}

class Alt : Ast {
    Ast[] alts;

    this(Ast[] alts) {
        this.alts = alts;
    }

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }


    override string toDot() {
        auto self = counter;
        auto result = format("f%d [label=\"%s\"]\n", counter++, repr());
        foreach (ast; alts) {
            auto cnt = counter;
            result ~= ast.toDot();
            result ~= format("f%d -> f%d\n", self, cnt);
        }
        return result;
    }

    override string repr() {
        return alts.map!(x => x.repr()).join("|");
    }
}

class Rep : Ast {
    Ast ast;
    int min, max; 

    this(Ast ast, int min, int max) {
        this.ast = ast;
        this.min = min;
        this.max = max;
    }

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        return format("f%d [label=\"%s\"]\n", counter++, repr());
    }

    override string repr() {
        return ast.repr() ~ format("{%d,%d}", min, max);
    }
}

class Char : Ast {
    dchar ch;

    this(dchar ch) {
        this.ch = ch;
    }
    
    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        return format("f%d [label=\"%c\"]\n", counter++, ch);
    }

    override string repr() {
        return to!string(ch);
    }
}

class Dot : Ast {
    this() {}

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        return format("f%d [label=\".\"]\n", counter++);
    }
    
    override string repr() {
        return ".";
    }
}

class CharClass : Ast {
    CodepointSet chars;

    this(CodepointSet chars) {
        this.chars = chars;
    }

    override void accept(Visitor visitor) {
        visitor.visit(this);
    }

    override string toDot() {
        return format("f%d [label=\"%s\"]", counter++, repr());
    }

    override string repr() {
        return chars.byInterval.map!(pair => pair.a.to!string ~ "-" ~ pair.b.to!string).join("");
    }
}
