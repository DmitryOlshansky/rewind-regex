module rewind.re.parser;

import std.uni;
//import pry;

struct Parser {
    private const(char)[] pattern;
    this(const(char)[] pattern) {
        this.pattern = pattern;
        auto allowedChars =
		unicode.Cc.add('"', '"'+1).add('\\', '\\'+1).inverted;
        enum hex = CodepointSet('0', '9'+1, 'a', 'f'+1, 'A', 'F'+1);
        /*with(parsers!(SimpleStream!(const(char)[]))) {
            auto escapes = seq(tk!'\\', any(
                tk!'"',
                tk!'\\',
                tk!'/',
                tk!'b'.map!(_ => cast(dchar)'\b'),
                tk!'f'.map!(_ => cast(dchar)'\f'),
                tk!'n'.map!(_ => cast(dchar)'\n'),
                tk!'r'.map!(_ => cast(dchar)'\r'),
                tk!'t'.map!(_ => cast(dchar)'\t'),
                seq(tk!'u', set!hex.rep!(4,4)).map!(x => cast(dchar)to!int(x[1], 16))
            )).map!(x => x[1]);
        }*/
    }

}
