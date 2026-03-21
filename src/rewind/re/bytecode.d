module rewind.re.bytecode;

import std.array;

enum Opcode : ubyte {
    ANY = 0,
    CHAR,
    NOTCHAR,
    ONE_OF,
    NOT_ONE_OF,
    INTERVALS,
    TRIE,
    JMP,
    FORK,
    END
}

struct BytecodeBuilder {
    Appender!(uint[]) app;
    this(int capacity) {
        app = appender!(uint[])();
        app.reserve(capacity);
    }

    size_t code(Opcode op, int value) {
        app ~= (op << 24) | (cast(uint)value & 0xFF_FFFF); // negative values are clamped to 24 bits
        return app.data.length-1;
    }

    void fixup(size_t idx, int value) {
        app.data[idx] = (app.data[idx] & 0xFF00_FFFF) | (cast(uint)value & 0xFF_FFFF);
    }

    uint[] build() {
        return app.data;
    }
}


/*unittest {
    import std.stdio;
    ubyte[] code;
    with (Opcode) {
        encode!ANY(code);
        encode!(CHAR)(code, 'a');
        encode!(NOTCHAR)(code, 'b');
        encode!(CHARCLASS)(code, CodepointSet('a', 'z'+1));
        encode!(JMP)(code, 1);
        encode!(CHAR)(code, 'z');
        encode!(COUNTED_LOOP)(code, 1, 2, 41);
        encode!(FORK)(code, 41, 0);
        writeln(decode(code));
    }
}*/
