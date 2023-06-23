module rewind.re.captures;

import rewind.re.ir, rewind.re.matcher;


/++
    $(D Captures) object contains submatches captured during a call
    to $(D match) or iteration over $(D RegexMatch) range.

    First element of range is the whole match.
+/
@trusted public struct Captures
{//@trusted because of union inside
private:
    import std.conv : text;
    enum smallString = 3;
    enum SMALL_MASK = 0x8000_0000, REF_MASK= 0x1FFF_FFFF;

    struct Group {
        size_t begin, end;
    }

    union
    {
        Group[] big_matches;
        Group[smallString] small_matches;
    }
    int[string] _names;
    const(char)[] _input;
    int _nMatch;
    uint _f, _b;
    uint _refcount; // ref count or SMALL MASK + num groups

    this(const(char)[] input, uint n, int[string] named)
    {
        _input = input;
        _names = named;
        newMatches(n);
        _b = n;
        _f = 0;
    }

    this(ref RegexMatch rmatch)
    {
        _input = rmatch._input;
        _names = rmatch._re.dict;
        immutable n = rmatch._re.dict.length;
        newMatches(n);
        _b = cast(uint)n;
        _f = 0;
    }

    @property inout(Group[]) matches() inout
    {
       return (_refcount & SMALL_MASK)  ? small_matches[0 .. _refcount & 0xFF] : big_matches;
    }

    void newMatches(size_t n)
    {
        import core.stdc.stdlib : calloc;
        import std.exception : enforce;
        if (n > smallString)
        {
            auto p = cast(Group*) enforce(
                calloc(Group.sizeof,n),
                "Failed to allocate Captures struct"
            );
            big_matches = p[0 .. n];
            _refcount = 1;
        }
        else
        {
            _refcount = SMALL_MASK | cast(uint)n;
        }
    }

    bool unique()
    {
        return (_refcount & SMALL_MASK) || _refcount == 1;
    }

public:
    this(this)
    {
        if (!(_refcount & SMALL_MASK))
        {
            _refcount++;
        }
    }

    ~this()
    {
        import core.stdc.stdlib : free;
        if (!(_refcount & SMALL_MASK))
        {
            if (--_refcount == 0)
            {
                free(big_matches.ptr);
                big_matches = null;
            }
        }
    }
    ///Slice of input prior to the match.
    @property const(char)[] pre()
    {
        return _nMatch == 0 ? _input[] : _input[0 .. matches[0].begin];
    }

    ///Slice of input immediately after the match.
    @property const(char)[] post()
    {
        return _nMatch == 0 ? _input[] : _input[matches[0].end .. $];
    }

    ///Slice of matched portion of input.
    @property const(char)[] hit()
    {
        assert(_nMatch, "attempted to get hit of an empty match");
        return _input[matches[0].begin .. matches[0].end];
    }

    ///Range interface.
    @property const(char)[] front()
    {
        assert(_nMatch, "attempted to get front of an empty match");
        return _input[matches[_f].begin .. matches[_f].end];
    }

    ///ditto
    @property const(char)[] back()
    {
        assert(_nMatch, "attempted to get back of an empty match");
        return _input[matches[_b - 1].begin .. matches[_b - 1].end];
    }

    ///ditto
    void popFront()
    {
        assert(!empty);
        ++_f;
    }

    ///ditto
    void popBack()
    {
        assert(!empty);
        --_b;
    }

    ///ditto
    @property bool empty() const { return _nMatch == 0 || _f >= _b; }

    ///ditto
    inout(const(char)[]) opIndex()(size_t i) inout
    {
        assert(_f + i < _b,text("requested submatch number ", i," is out of range"));
        assert(matches[_f + i].begin <= matches[_f + i].end,
            text("wrong match: ", matches[_f + i].begin, "..", matches[_f + i].end));
        return _input[matches[_f + i].begin .. matches[_f + i].end];
    }

    /++
        Explicit cast to bool.
        Useful as a shorthand for !(x.empty) in if and assert statements.

        ---
        import rewind.regex;

        assert(!matchFirst("nothing", "something"));
        ---
    +/

    @safe bool opCast(T:bool)() const nothrow { return _nMatch != 0; }

    /++
        Number of pattern matched counting, where 1 - the first pattern.
        Returns 0 on no match.
    +/

    @safe @property int whichPattern() const nothrow { return _nMatch; }

    ///
    @system unittest
    {
        import rewind.re;
        assert(matchFirst("abc", "[0-9]+", "[a-z]+").whichPattern == 2);
    }

    /++
        Lookup named submatch.

        ---
        import rewind.regex;
        import std.range;

        auto c = matchFirst("a = 42;", regex(`(?P<var>\w+)\s*=\s*(?P<value>\d+);`));
        assert(c["var"] == "a");
        assert(c["value"] == "42");
        popFrontN(c, 2);
        //named groups are unaffected by range primitives
        assert(c["var"] =="a");
        assert(c.front == "42");
        ----
    +/
    const(char)[] opIndex(const(char)[] i) /*const*/ //@@@BUG@@@
    {
        size_t index = _names[i];
        return _input[matches[index].begin .. matches[index].end];
    }

    ///Number of matches in this object.
    @property size_t length() const { return _nMatch == 0 ? 0 : _b - _f;  }

    void opAssign()(auto ref Captures rhs)
    {
        if (rhs._refcount & SMALL_MASK)
            small_matches[0 .. rhs._refcount & 0xFF] = rhs.small_matches[0 .. rhs._refcount & 0xFF];
        else
            big_matches = rhs.big_matches;
        assert(&this.tupleof[0] is &big_matches);
        assert(&this.tupleof[1] is &small_matches);
        this.tupleof[2 .. $] = rhs.tupleof[2 .. $];
    }
}

///
@system unittest
{
    import std.range.primitives : popFrontN;

    auto c = matchFirst("@abc#", regex(`(\w)(\w)(\w)`));
    assert(c.pre == "@"); // Part of input preceding match
    assert(c.post == "#"); // Immediately after match
    assert(c.hit == c[0] && c.hit == "abc"); // The whole match
    assert(c[2] == "b");
    assert(c.front == "abc");
    c.popFront();
    assert(c.front == "a");
    assert(c.back == "c");
    c.popBack();
    assert(c.back == "b");
    popFrontN(c, 2);
    assert(c.empty);

    assert(!matchFirst("nothing", "something"));
}

/++
    A regex engine state, as returned by $(D match) family of functions.

    Effectively it's a forward range of Captures, produced
    by lazily searching for matches in a given input.
+/
@trusted public struct RegexMatch
{
private:
    // TODO: Matcher!Char _engine;
    const(char)[] _input;
    Captures _captures;
    Re _re;

    this(const(char)[] input, Re prog)
    {
        _input = input;
        _re = prog;
        _captures = Captures(this);
        _captures._nMatch = _re.engine().match(_captures.matches);
    }

public:

    ///Shorthands for front.pre, front.post, front.hit.
    @property const(char)[] pre()
    {
        return _captures.pre;
    }

    ///ditto
    @property const(char)[] post()
    {
        return _captures.post;
    }

    ///ditto
    @property const(char)[] hit()
    {
        return _captures.hit;
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
        _captures.newMatches(_re.dict.length);
        _captures._nMatch = _re.engine().match(_captures.matches);
    }

    ///ditto
    auto save(){ return this; }

    ///Test if this match object is empty.
    @property bool empty() const { return _captures._nMatch == 0; }

    ///Same as !(x.empty), provided for its convenience  in conditional statements.
    T opCast(T:bool)(){ return !empty; }
}
