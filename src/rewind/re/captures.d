module rewind.re.captures;

import rewind.re.ir, rewind.re.matcher;


/++
    $(D Captures) object contains submatches captured during a call
    to $(D match) or iteration over $(D RegexMatch) range.

    First element of range is the whole match.
+/
alias Captures = const(char)[][];

/++
    A regex engine state, as returned by $(D match) family of functions.

    Effectively it's a forward range of Captures, produced
    by lazily searching for matches in a given input.
+/
@trusted public struct RegexMatch
{
private:
    const(char)[] _input;
    Captures _captures;
    Re _re;

public:
    this(const(char)[] input, Re prog)
    {
        _input = input;
        _re = prog;
        _captures = _re.engine().match(input);
    }

    ///Shorthands for front.pre, front.post, front.hit.
    @property const(char)[] pre()
    {
        return _input[0.._captures[0].ptr-_input.ptr];
    }

    ///ditto
    @property const(char)[] post()
    {
        return _input[_captures[$-1].ptr-_input.ptr..$];
    }

    ///ditto
    @property const(char)[] hit()
    {
        return _captures[0];
    }

    /++
        Functionality for processing subsequent matches of global regexes via range interface:
        ---
        import rewind.regex;
        auto m = matchAll("Hello, world!", regex(`\w+`));
        assert(m.front.hit == "Hello");
        m.popFront();
        assert(m.front.hit == "world");
        m.popFront();
        assert(m.empty);
        ---
    +/
    @property inout(Captures) front() inout
    {
        return _captures;
    }

    ///ditto
    void popFront()
    {
        _captures = _re.engine().match(_input);
    }

    ///ditto
    auto save(){ return this; }

    ///Test if this match object is empty.
    @property bool empty() const { return _captures == null; }

    ///Same as !(x.empty), provided for its convenience  in conditional statements.
    T opCast(T:bool)(){ return !empty; }
}
