module rewind.regex.ast;

import std.format;

abstract class Ast {
    static int counter = 0;
    string toDot();
}

class Pattern : Ast {
    Ast[] children;
    
    this(Ast[] children) {
        this.children = children;
    }

    string toDot() {
        auto result = "digraph Pattern {\n";
        result ~= format("f%s", counter);
        foreach(ast; children) {
            result ~= ast.toDot();
        }
        result ~= "}\n";
        return toDot();
    }
}