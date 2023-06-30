/++
  $(LINK2 https://en.wikipedia.org/wiki/Regular_expression, Regular expressions)
  are a commonly used method of pattern matching
  on strings, with $(I regex) being a catchy word for a pattern in this domain
  specific language. Typical problems usually solved by regular expressions
  include validation of user input, deep packet inspection and 
  the ubiquitous find $(AMP) replace in text processing tools and IDEs.

  $(SECTION Synopsis)
  ---
  import rewind.re;
  import std.stdio;
  void main()
  {
      // Print out all possible dd/mm/yy(yy) dates found in user input.
      auto r = re(`\b[0-9][0-9]?/[0-9][0-9]?/[0-9][0-9](?:[0-9][0-9])?\b`);
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
  auto multi = re([`\d+,\d+`,`(a-z]+):(\d+)`]);
  auto m = "abc:43 12,34".matchAll(multi);
  assert(m.front[1] == "abc");
  assert(m.front[2] == "43");
  m.popFront();
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
module rewind.re;

import std.range.primitives;
import rewind.re.ast, rewind.re.ir, rewind.re.captures;

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
@trusted public auto re(const(char)[][] patterns, const(char)[] flags="")
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
            app.put(cast(dchar)('\U000F0000'+i));
            app.put(")");
            // another one to return correct whichPattern
            // for all of potential alternatives in the patterns[i]
            app.put("\\");
            app.put(cast(dchar)('\U000F0000'+i));
        }
        pat = app.data;
    }
    else
        pat = patterns[0];

    return Re(pat.idup, flags.idup, 0, null, null, null);
}

///ditto
@trusted public auto re(const(char)[] pattern, const(char)[] flags="")
{
    return re([pattern], flags.idup);
}

///
/*
@system unittest
{
    // multi-pattern regex example
    auto multi = re([`([a-z]+):(\d+)`, `(\d+),\d+`]); // multi regex
    auto m = "abc:43 12,34".matchAll(multi);
    assert(m.front[1] == "abc");
    assert(m.front[2] == "43");
    m.popFront();
    assert(m.front[1] == "12");
}
*/

private @trusted auto matchOnce(const(char)[] input, Re prog)
{
    auto engine = prog.engine();
    auto captures = engine.realFullyMatch(input);
    return captures;
}

private auto matchMany(const(char)[] input, Re re) @safe
{
    return RegexMatch(input, re.withFlags(re.flags ~ "g"));
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
public auto matchFirst(const(char)[] input, Re re)
{
    return matchOnce(input, re);
}

///ditto
public auto matchFirst(const(char)[] input, const(char)[] pattern)
{
    return matchOnce(input, re(pattern));
}

///ditto
public auto matchFirst(const(char)[] input, const(char)[][] patterns...)
{
    return matchOnce(input, re(patterns));
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
public auto matchAll(const(char)[] input, Re re)
{
    return matchMany(input, re);
}

///ditto
public auto matchAll(const(char)[] input, const(char)[][] patterns...)
{
    return matchMany(input, re(patterns));
}

// another set of tests just to cover the new API
/*@system unittest
{
    import std.algorithm.comparison : equal;
    import std.algorithm.iteration : map;
    import std.conv : to;

    alias String = string;
    {{
        auto str1 = "blah-bleh".to!String();
        auto pat1 = "bl[ae]h".to!String();
        auto mf = matchFirst(str1, pat1);
        assert(mf.equal(["blah".to!String()]));
        auto mAll = matchAll(str1, pat1);
        assert(mAll.equal!((a,b) => a.equal(b))
            ([["blah".to!String()], ["bleh".to!String()]]));

        auto str2 = "1/03/12 - 3/03/12".to!String();
        auto pat2 = re([r"(\d+)/(\d+)/(\d+)".to!String(), "abc".to!String]);
        auto mf2 = matchFirst(str2, pat2);
        assert(mf2.equal(["1/03/12", "1", "03", "12"].map!(to!String)()));
        auto mAll2 = matchAll(str2, pat2);
        assert(mAll2.front.equal(mf2));
        mAll2.popFront();
        assert(mAll2.front.equal(["3/03/12", "3", "03", "12"].map!(to!String)()));
        mf2.popFrontN(3);
        assert(mf2.equal(["12".to!String()]));
    }}
}*/


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
/*auto escaper(Range)(Range r)
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
    import rewind.re;
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
*/