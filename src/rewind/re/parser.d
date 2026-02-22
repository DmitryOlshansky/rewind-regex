module rewind.re.parser;

import std.uni;
import pry;

struct Parser {
    private const(char)[] pattern;
    this(const(char)[] pattern) {
        this.pattern = pattern;
        /*auto allowedChars =
		unicode.Cc.add('"', '"'+1).add('\\', '\\'+1).inverted;
        auto all = CodepointSet(dchar.min, dchar.max);
        auto hex = CodepointSet('0', '9'+1, 'a', 'f'+1, 'A', 'F'+1);
        with(parsers!(SimpleStream!(const(char)[]))) {
            auto expr = dynamic();
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
            auto atoms = any(
                seq(tk!'(', expr, tk!')'),
                escapes,
                tk!'.',
                set(all)
            );
            auto quantified = seq(
                atoms,
                any(
                    seq(tk!'{', num, tk!',', num, tk!'}').map!(x => tuple(x[1], x[3])),
                    tk!'*'.map!(x => tuple(0, -1)),
                    tk!'+'.map!(x => tuple(1, -1)),
                    tk!'?'.map!(x => tuple(0, 1)),
                )
            );
            

        }*/
    }

}
