module rewind.re.parser;

import std.uni, std.typecons, std.conv, std.exception;
import pry;
import rewind.re.ast;

private alias Stream = SimpleStream!(const(char)[]);
private alias env = parsers!Stream;
env.DynamicParser!Ast parser;

class ParseException : Exception {
    this(string msg){
        super(msg);
    }
}

static this() {
    CodepointSet addChars(CodepointSet set, string chars) {
        foreach(dchar ch; chars) {
            set.add(ch, ch+1);
        }
        return set;
    }
    auto allowedChars =	addChars(unicode.Cc, "{}()\\.?*+").inverted;
    auto digits = CodepointSet('0', '9'+1);
    auto hex = CodepointSet('0', '9'+1, 'a', 'f'+1, 'A', 'F'+1);
    with(env) {
        auto num = set(digits).rep.map!(x => x.to!int);
        auto expr = dynamic!Ast();
        auto escapes = seq(tk!'\\', any(
            tk!'"',
            tk!'\\',
            tk!'/',
            tk!'b'.map!(_ => cast(dchar)'\b'),
            tk!'f'.map!(_ => cast(dchar)'\f'),
            tk!'n'.map!(_ => cast(dchar)'\n'),
            tk!'r'.map!(_ => cast(dchar)'\r'),
            tk!'t'.map!(_ => cast(dchar)'\t'),
            seq(tk!'u', set(hex).rep!(4,4)).map!(x => cast(dchar)to!int(x[1], 16))
        )).map!(x => x[1]);
        auto atom = any(
            seq(tk!'(', expr, tk!')').map!(x => cast(Ast)new Group(x[1])),
            escapes.map!(x => cast(Ast) new Char(x)),
            tk!'.'.map!(x => cast(Ast) new Dot()),
            set(allowedChars).map!(x => cast(Ast) new Char(x))
        );
        auto quantified = seq(
            atom,
            any(
                seq(tk!'{', num, tk!',', num, tk!'}').map!(x => tuple(x[1], x[3])),
                tk!'*'.map!(x => tuple(0, -1)),
                tk!'+'.map!(x => tuple(1, -1)),
                tk!'?'.map!(x => tuple(0, 1)),
            ).optional
        ).map!(x => x[1].isNull ? x[0] : cast(Ast)new Rep(x[0], x[1][0], x[1][1]));
        expr = delimited(quantified.array.map!(x => cast(Ast)new Seq(x)), tk!'|').map!(x => cast(Ast)new Alt(x));
        parser = expr;
    }
}

Ast parse(const(char)[] pattern) {
    Stream.Error err;
    Ast v;
    auto stream = stream(pattern);
    counter = 1;
    if (!parser.parse(stream, v, err) || !stream.empty) {
        auto s = "Regex pattern failed to parse '"~err.reason~"': `"~pattern[0..err.location]~" <<HERE>> "~pattern[err.location..$];
        throw new ParseException(s.idup);
    }
    return v;
}


unittest {
    assertThrown!ParseException(parse("abc("));
    assert(parse("A|B").repr == "A|B");
    assert(parse("(A+C)B").repr == "(A{1,-1}C)B");
}