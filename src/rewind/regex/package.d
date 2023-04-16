/++
  $(LINK2 https://en.wikipedia.org/wiki/Regular_expression, Regular expressions)
  are a commonly used method of pattern matching
  on strings, with $(I regex) being a catchy word for a pattern in this domain
  specific language. Typical problems usually solved by regular expressions
  include validation of user input, deep packet inspection and 
  the ubiquitous find $(AMP) replace in text processing tools and IDEs.

  $(SECTION Synopsis)
  ---
  import rewind.regex;
  import std.stdio;
  void main()
  {
      // Print out all possible dd/mm/yy(yy) dates found in user input.
      auto r = regex(`\b[0-9][0-9]?/[0-9][0-9]?/[0-9][0-9](?:[0-9][0-9])?\b`);
      foreach (line; stdin.byLine)
      {
        // matchAll() returns a range that can be iterated
        // to get all subsequent matches.
        foreach (c; matchAll(line, r))
            writeln(c.hit);
      }
  }
  ...
  // multi-pattern regex
  auto multi = regex([`\d+,\d+`,`(a-z]+):(\d+)`]);
  auto m = "abc:43 12,34".matchAll(multi);
  assert(m.front.whichPattern == 2);
  assert(m.front[1] == "abc");
  assert(m.front[2] == "43");
  m.popFront();
  assert(m.front.whichPattern == 1);
  assert(m.front[1] == "12");
  ...

  // The result of the `matchAll/matchFirst` is directly testable with if/assert/while.
  // e.g. test if a string consists of letters:
  assert(matchFirst("Letter", `^\p{L}+$`));
  ---

  $(SECTION Syntax and general information)
  The general usage guideline is to keep regex complexity on the side of simplicity.
  Regex capabilities reside in purely character-level recognition and manipulation.
  As such it's ill-suited for tasks involving higher level invariants
  like matching an integer number $(U bounded) in an [a,b] interval.
  Checks of this sort of are better addressed by simple additional post-processing.

  The basic syntax shouldn't surprise experienced users of regular expressions.
 
  There are other web resources on regular expressions to help newcomers,
  and a good $(HTTP www.regular-expressions.info, reference with tutorial)
  can easily be found.

  This library uses a remarkably common ECMAScript syntax flavor
  with the following extensions:
  $(UL
    $(LI Named subexpressions, with Python syntax. )
    $(LI Unicode properties such as Scripts, Blocks and common binary properties e.g Alphabetic, White_Space, Hex_Digit etc.)
    $(LI Arbitrary length and complexity lookbehind, including lookahead in lookbehind and vise-versa.)
  )

  $(REG_START Pattern syntax )
  $(I rewind.regex operates on codepoint level, 'character' in this table denotes a single Unicode codepoint.)
  $(REG_TABLE
    $(REG_TITLE Pattern element, Semantics )
    $(REG_TITLE Atoms, Match single characters )
    $(REG_ROW any character except [{|*+?()^$, Matches the character itself. )
    $(REG_ROW ., In single line mode matches any character.
      Otherwise it matches any character except '\n' and '\r'. )
    $(REG_ROW [class], Matches a single character
      that belongs to this character class. )
    $(REG_ROW [^class], Matches a single character that
      does $(U not) belong to this character class.)
    $(REG_ROW \cC, Matches the control character corresponding to letter C)
    $(REG_ROW \xXX, Matches a character with hexadecimal value of XX. )
    $(REG_ROW \uXXXX, Matches a character  with hexadecimal value of XXXX. )
    $(REG_ROW \U00YYYYYY, Matches a character with hexadecimal value of YYYYYY. )
    $(REG_ROW \f, Matches a formfeed character. )
    $(REG_ROW \n, Matches a linefeed character. )
    $(REG_ROW \r, Matches a carriage return character. )
    $(REG_ROW \t, Matches a tab character. )
    $(REG_ROW \v, Matches a vertical tab character. )
    $(REG_ROW \d, Matches any Unicode digit. )
    $(REG_ROW \D, Matches any character except Unicode digits. )
    $(REG_ROW \w, Matches any word character (note: this includes numbers).)
    $(REG_ROW \W, Matches any non-word character.)
    $(REG_ROW \s, Matches whitespace, same as \p{White_Space}.)
    $(REG_ROW \S, Matches any character except those recognized as $(I \s ). )
    $(REG_ROW \\, Matches \ character. )
    $(REG_ROW \c where c is one of [|*+?(), Matches the character c itself. )
    $(REG_ROW \p{PropertyName}, Matches a character that belongs
        to the Unicode PropertyName set.
      Single letter abbreviations can be used without surrounding {,}. )
    $(REG_ROW  \P{PropertyName}, Matches a character that does not belong
        to the Unicode PropertyName set.
      Single letter abbreviations can be used without surrounding {,}. )
    $(REG_ROW \p{InBasicLatin}, Matches any character that is part of
          the BasicLatin Unicode $(U block).)
    $(REG_ROW \P{InBasicLatin}, Matches any character except ones in
          the BasicLatin Unicode $(U block).)
    $(REG_ROW \p{Cyrillic}, Matches any character that is part of
        Cyrillic $(U script).)
    $(REG_ROW \P{Cyrillic}, Matches any character except ones in
        Cyrillic $(U script).)
    $(REG_TITLE Quantifiers, Specify repetition of other elements)
    $(REG_ROW *, Matches previous character/subexpression 0 or more times.
      Greedy version - tries as many times as possible.)
    $(REG_ROW *?, Matches previous character/subexpression 0 or more times.
      Lazy version  - stops as early as possible.)
    $(REG_ROW +, Matches previous character/subexpression 1 or more times.
      Greedy version - tries as many times as possible.)
    $(REG_ROW +?, Matches previous character/subexpression 1 or more times.
      Lazy version  - stops as early as possible.)
    $(REG_ROW {n}, Matches previous character/subexpression exactly n times. )
    $(REG_ROW {n$(COMMA)}, Matches previous character/subexpression n times or more.
      Greedy version - tries as many times as possible. )
    $(REG_ROW {n$(COMMA)}?, Matches previous character/subexpression n times or more.
      Lazy version - stops as early as possible.)
    $(REG_ROW {n$(COMMA)m}, Matches previous character/subexpression n to m times.
      Greedy version - tries as many times as possible, but no more than m times. )
    $(REG_ROW {n$(COMMA)m}?, Matches previous character/subexpression n to m times.
      Lazy version - stops as early as possible, but no less then n times.)
    $(REG_TITLE Other, Subexpressions $(AMP) alternations )
    $(REG_ROW (regex),  Matches subexpression regex,
      saving matched portion of text for later retrieval. )
    $(REG_ROW (?#comment), An inline comment that is ignored while matching.)
    $(REG_ROW (?:regex), Matches subexpression regex,
      $(U not) saving matched portion of text. Useful to speed up matching. )
    $(REG_ROW A|B, Matches subexpression A, or failing that, matches B. )
    $(REG_ROW (?P$(LT)name$(GT)regex), Matches named subexpression
        regex labeling it with name 'name'.
        When referring to a matched portion of text,
        names work like aliases in addition to direct numbers.
     )
    $(REG_TITLE Assertions, Match position rather than character )
    $(REG_ROW ^, Matches at the begining of input or line (in multiline mode).)
    $(REG_ROW $, Matches at the end of input or line (in multiline mode). )
    $(REG_ROW \b, Matches at word boundary. )
    $(REG_ROW \B, Matches when $(U not) at word boundary. )
    $(REG_ROW (?=regex), Zero-width lookahead assertion.
        Matches at a point where the subexpression
        regex could be matched starting from the current position.
      )
    $(REG_ROW (?!regex), Zero-width negative lookahead assertion.
        Matches at a point where the subexpression
        regex could $(U not) be matched starting from the current position.
      )
    $(REG_ROW (?<=regex), Zero-width lookbehind assertion. Matches at a point
        where the subexpression regex could be matched ending
        at the current position (matching goes backwards).
      )
    $(REG_ROW  (?<!regex), Zero-width negative lookbehind assertion.
      Matches at a point where the subexpression regex could $(U not)
      be matched ending at the current position (matching goes backwards).
     )
  )

  $(REG_START Character classes )
  $(REG_TABLE
    $(REG_TITLE Pattern element, Semantics )
    $(REG_ROW Any atom, Has the same meaning as outside of a character class.)
    $(REG_ROW a-z, Includes characters a, b, c, ..., z. )
    $(REG_ROW [a||b]$(COMMA) [a--b]$(COMMA) [a~~b]$(COMMA) [a$(AMP)$(AMP)b],
     Where a, b are arbitrary classes, means union, set difference,
     symmetric set difference, and intersection respectively.
     $(I Any sequence of character class elements implicitly forms a union.) )
  )

  $(REG_START Regex flags )
  $(REG_TABLE
    $(REG_TITLE Flag, Semantics )
    $(REG_ROW i, Case insensitive matching. )
    $(REG_ROW m, Multi-line mode, match ^, $ on start and end line separators
       as well as start and end of input.)
    $(REG_ROW s, Single-line mode, makes . match '\n' and '\r' as well. )
    $(REG_ROW x, Free-form syntax, ignores whitespace in pattern,
      useful for formatting complex regular expressions. )
  )

  $(SECTION Unicode support)

  This library provides full Level 1 support* according to
    $(HTTP unicode.org/reports/tr18/, UTS 18). Specifically:
  $(UL
    $(LI 1.1 Hex notation via any of \uxxxx, \U00YYYYYY, \xZZ.)
    $(LI 1.2 Unicode properties.)
    $(LI 1.3 Character classes with set operations.)
    $(LI 1.4 Word boundaries use the full set of "word" characters.)
    $(LI 1.5 Using simple casefolding to match case
        insensitively across the full range of codepoints.)
    $(LI 1.6 Respecting line breaks as any of
        \u000A | \u000B | \u000C | \u000D | \u0085 | \u2028 | \u2029 | \u000D\u000A.)
    $(LI 1.7 Operating on codepoint level.)
  )
  *With exception of point 1.1.1, as of yet, normalization of input
    is expected to be enforced by user.

    $(SECTION Replace format string)

    A set of functions in this module that do the substitution rely
    on a simple format to guide the process. In particular the table below
    applies to the $(D format) argument of
    $(LREF replaceFirst) and $(LREF replaceAll).

    The format string can reference parts of match using the following notation.
    $(REG_TABLE
        $(REG_TITLE Format specifier, Replaced by )
        $(REG_ROW $$(AMP), the whole match. )
        $(REG_ROW $(DOLLAR)$(BACKTICK), part of input $(I preceding) the match. )
        $(REG_ROW $', part of input $(I following) the match. )
        $(REG_ROW $$, '$' character. )
        $(REG_ROW \c $(COMMA) where c is any character, the character c itself. )
        $(REG_ROW \\, '\' character. )
        $(REG_ROW $(DOLLAR)1 .. $(DOLLAR)99, submatch number 1 to 99 respectively. )
    )

  $(SECTION Slicing and zero memory allocations guarantee)

  All matches returned by pattern matching functionality in this library
    are slices of the original input. The notable exception is the $(D replace)
    family of functions  that generate a new string from the input.

    In cases where producing the replacement is the ultimate goal
    $(LREF replaceFirstInto) and $(LREF replaceAllInto) could come in handy
    as functions that  avoid allocations even for replacement.

  Copyright: Copyright Dmitry Olshansky, 2018-

  License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).

  Authors: Dmitry Olshansky

Macros:
    REG_ROW = $(TR $(TD $(I $1 )) $(TD $+) )
    REG_TITLE = $(TR $(TD $(B $1)) $(TD $(B $2)) )
    REG_TABLE = <table border="1" cellspacing="0" cellpadding="5" > $0 </table>
    REG_START = <h3><div align="center"> $0 </div></h3>
    SECTION = <h3><a id="$1" href="#$1" class="anchor">$0</a></h3>
    S_LINK = <a href="#$1">$+</a>
+/
module rewind.regex;

import std.range.primitives;
import rewind.regex.ir;

/++
    $(D Regex) object holds regular expression pattern in compiled form.

    Instances of this object are constructed via calls to $(D regex).
    This is an intended form for caching and storage of frequently
    used regular expressions.

    Example:

    Test if this object doesn't contain any compiled pattern.
    ---
    Regex!char r;
    assert(r.empty);
    r = regex(""); // Note: "" is a valid regex pattern.
    assert(!r.empty);
    ---

    Getting a range of all the named captures in the regex.
    ----
    import std.range;
    import std.algorithm;

    auto re = regex(`(?P<name>\w+) = (?P<var>\d+)`);
    auto nc = re.namedCaptures;
    static assert(isRandomAccessRange!(typeof(nc)));
    assert(!nc.empty);
    assert(nc.length == 2);
    assert(nc.equal(["name", "var"]));
    assert(nc[0] == "name");
    assert(nc[1..$].equal(["var"]));
    ----
+/


/++
    Compile regular expression pattern for the later execution.
    Returns: $(D Regex) object that works on inputs having
    the same character width as $(D pattern).

    Params:
    pattern = A single regular expression to match.
    patterns = An array of regular expression strings.
        The resulting `Regex` object will match any expression;
        use $(LREF whichPattern) to know which.
    flags = The _attributes (g, i, m, s and x accepted)

    Throws: $(D RegexException) if there were any errors during compilation.
+/
@trusted public auto regex(const(char)[][] patterns, const(char)[] flags="")
{
    import std.array : appender;
    enum cacheSize = 8; //TODO: invent nice interface to control regex caching
    const(char)[] pat;
    if (patterns.length > 1)
    {
        auto app = appender!(const(char)[])();
        foreach (i, p; patterns)
        {
            if (i != 0)
                app.put("|");
            app.put("(?:");
            app.put(patterns[i]);
            // terminator for the pattern
            // to detect if the pattern unexpectedly ends
            app.put("\\");
            app.put(cast(dchar)(privateUseStart+i));
            app.put(")");
            // another one to return correct whichPattern
            // for all of potential alternatives in the patterns[i]
            app.put("\\");
            app.put(cast(dchar)(privateUseStart+i));
        }
        pat = app.data;
    }
    else
        pat = patterns[0];

    return Regex(pat, flags);
}

///ditto
@trusted public auto regex(const(char)[] pattern, const(char)[] flags="")
{
    return regex([pattern], flags);
}

///
@system unittest
{
    // multi-pattern regex example
    auto multi = regex([`([a-z]+):(\d+)`, `(\d+),\d+`]); // multi regex
    auto m = "abc:43 12,34".matchAll(multi);
    assert(m.front.whichPattern == 1);
    assert(m.front[1] == "abc");
    assert(m.front[2] == "43");
    m.popFront();
    assert(m.front.whichPattern == 2);
    assert(m.front[1] == "12");
}

enum isRegexFor(RegEx, R) = is(RegEx : const(Regex!(BasicElementOf!R)));

/++
    $(D Captures) object contains submatches captured during a call
    to $(D match) or iteration over $(D RegexMatch) range.

    First element of range is the whole match.
+/
@trusted public struct Captures
{//@trusted because of union inside
    alias DataIndex = size_t;
private:
    import std.conv : text;
    enum smallString = 3;
    enum SMALL_MASK = 0x8000_0000, REF_MASK= 0x1FFF_FFFF;
    union
    {
        Group!DataIndex[] big_matches;
        Group!DataIndex[smallString] small_matches;
    }
    struct NamedGroup
    {
        Group!DataIndex group;
        string name;
    }
    const(NamedGroup)[] _names;
    const(char)[] _input;
    int _nMatch;
    uint _f, _b;
    uint _refcount; // ref count or SMALL MASK + num groups

    this(const(char)[] input, uint n, const(NamedGroup)[] named)
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
        _names = rmatch._engine.pattern.dict;
        immutable n = rmatch._engine.pattern.ngroup;
        newMatches(n);
        _b = n;
        _f = 0;
    }

    @property inout(Group!DataIndex[]) matches() inout
    {
       return (_refcount & SMALL_MASK)  ? small_matches[0 .. _refcount & 0xFF] : big_matches;
    }

    void newMatches(uint n)
    {
        import core.stdc.stdlib : calloc;
        import std.exception : enforce;
        if (n > smallString)
        {
            auto p = cast(Group!DataIndex*) enforce(
                calloc(Group!DataIndex.sizeof,n),
                "Failed to allocate Captures struct"
            );
            big_matches = p[0 .. n];
            _refcount = 1;
        }
        else
        {
            _refcount = SMALL_MASK | n;
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
        import rewind.regex;
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
    const(char)[] opIndex(String)(String i) /*const*/ //@@@BUG@@@
        if (isSomeString!String)
    {
        size_t index = lookupNamedGroup(_names, i);
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

    this(const(char)[] input, Regex prog)
    {
        _input = input;
        _factory = prog.factory;
        _engine = _factory.create(prog, input);
        assert(_engine.refCount == 1);
        _captures = Captures!R(this);
        _captures._nMatch = _engine.match(_captures.matches);
    }

public:
    this(this)
    {
        if (_engine) _factory.incRef(_engine);
    }

    ~this()
    {
        if (_engine) _factory.decRef(_engine);
    }

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
        // CoW - if refCount is not 1, we are aliased by somebody else
        if (_engine.refCount != 1)
        {
            // we create a new engine & abandon this reference
            auto old = _engine;
            _engine = _factory.dup(old, _input);
            _factory.decRef(old);
        }
        if (!_captures.unique)
        {
            // has external references - allocate new space
            _captures.newMatches(_engine.pattern.ngroup);
        }
        _captures._nMatch = _engine.match(_captures.matches);
    }

    ///ditto
    auto save(){ return this; }

    ///Test if this match object is empty.
    @property bool empty() const { return _captures._nMatch == 0; }

    ///Same as !(x.empty), provided for its convenience  in conditional statements.
    T opCast(T:bool)(){ return !empty; }
}

private @trusted auto matchOnce(const(char)[] input, Regex prog)
{
    //TODO:
    /*auto factory = prog.factory;
    auto engine = factory.create(prog, input);
    scope(exit) factory.decRef(engine); // destroys the engine
    auto captures = Captures!const(char)[](input, prog.ngroup, prog.dict);
    captures._nMatch = engine.match(captures.matches);
    return captures;
    */
}

private auto matchMany(const(char)[] input, Regex re) @safe
{
    return RegexMatch(input, re.withFlags(re.flags | RegexOption.global));
}

/++
    Find the first (leftmost) slice of the $(D input) that
    matches the pattern $(D re). This function picks the most suitable
    regular expression engine depending on the pattern properties.

    $(D re) parameter can be one of three types:
    $(UL
      $(LI Plain string(s), in which case it's compiled to bytecode before matching. )
      $(LI Regex!char (wchar/dchar) that contains a pattern in the form of
        compiled  bytecode. )
      $(LI StaticRegex!char (wchar/dchar) that contains a pattern in the form of
        compiled native machine code. )
    )

    Returns:
    $(LREF Captures) containing the extent of a match together with all submatches
    if there was a match, otherwise an empty $(LREF Captures) object.
+/
public auto matchFirst(const(char)[] input, Regex re)
{
    return matchOnce(input, re);
}

///ditto
public auto matchFirst(const(char)[] input, const(char)[] re)
{
    return matchOnce(input, regex(re));
}

///ditto
public auto matchFirst(const(char)[] input, const(char)[][] re...)
{
    return matchOnce(input, regex(re));
}

/++
    Initiate a search for all non-overlapping matches to the pattern $(D re)
    in the given $(D input). The result is a lazy range of matches generated
    as they are encountered in the input going left to right.

    This function picks the most suitable regular expression engine
    depending on the pattern properties.

    $(D re) parameter can be one of three types:
    $(UL
      $(LI Plain string(s), in which case it's compiled to bytecode before matching. )
      $(LI Regex!char (wchar/dchar) that contains a pattern in the form of
        compiled  bytecode. )
      $(LI StaticRegex!char (wchar/dchar) that contains a pattern in the form of
        compiled native machine code. )
    )

    Returns:
    $(LREF RegexMatch) object that represents matcher state
    after the first match was found or an empty one if not present.
+/
public auto matchAll(const(char)[] input, Regex re)
{
    return matchMany(input, re);
}

///ditto
public auto matchAll(const(char)[] input, const(char)[][] re...)
{
    return matchMany(input, regex(re));
}

// another set of tests just to cover the new API
@system unittest
{
    import std.algorithm.comparison : equal;
    import std.algorithm.iteration : map;
    import std.conv : to;

    static foreach (String; AliasSeq!(string, wstring, const(dchar)[]))
    {{
        auto str1 = "blah-bleh".to!String();
        auto pat1 = "bl[ae]h".to!String();
        auto mf = matchFirst(str1, pat1);
        assert(mf.equal(["blah".to!String()]));
        auto mAll = matchAll(str1, pat1);
        assert(mAll.equal!((a,b) => a.equal(b))
            ([["blah".to!String()], ["bleh".to!String()]]));

        auto str2 = "1/03/12 - 3/03/12".to!String();
        auto pat2 = regex([r"(\d+)/(\d+)/(\d+)".to!String(), "abc".to!String]);
        auto mf2 = matchFirst(str2, pat2);
        assert(mf2.equal(["1/03/12", "1", "03", "12"].map!(to!String)()));
        auto mAll2 = matchAll(str2, pat2);
        assert(mAll2.front.equal(mf2));
        mAll2.popFront();
        assert(mAll2.front.equal(["3/03/12", "3", "03", "12"].map!(to!String)()));
        mf2.popFrontN(3);
        assert(mf2.equal(["12".to!String()]));
    }}
}


///Exception object thrown in case of errors during regex compilation.
public class RegexException : Exception {
    this(string message) {
        super(message);
    }
}

/++
  A range that lazily produces a string output escaped
  to be used inside of a regular expression.
+/
auto escaper(Range)(Range r)
{
    import std.algorithm.searching : find;
    static immutable escapables = [Escapables];
    static struct Escaper // template to deduce attributes
    {
        Range r;
        bool escaped;

        @property ElementType!Range front(){
          if (escaped)
              return '\\';
          else
              return r.front;
        }

        @property bool empty(){ return r.empty; }

        void popFront(){
          if (escaped) escaped = false;
          else
          {
              r.popFront();
              if (!r.empty && !escapables.find(r.front).empty)
                  escaped = true;
          }
        }

        @property auto save(){ return Escaper(r.save, escaped); }
    }

    bool escaped = !r.empty && !escapables.find(r.front).empty;
    return Escaper(r, escaped);
}

///
@system unittest
{
    import std.algorithm.comparison;
    import rewind.regex;
    string s = `This is {unfriendly} to *regex*`;
    assert(s.escaper.equal(`This is \{unfriendly\} to \*regex\*`));
}

@system unittest
{
    import std.algorithm.comparison;
    import std.conv;
    static foreach (S; AliasSeq!(string, wstring, dstring))
    {{
      auto s = "^".to!S;
      assert(s.escaper.equal(`\^`));
      auto s2 = "";
      assert(s2.escaper.equal(""));
    }}
}
