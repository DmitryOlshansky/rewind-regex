/*
    Implementation of rewind-regex IR, an intermediate representation
    of a regular expression pattern.

    This is a common ground between frontend regex component (parser)
    and backend components - generators, matchers and other "filters".
*/
module rewind.regex.ir;

import std.uni, std.meta;

// just a common trait, may be moved elsewhere
alias BasicElementOf(Range) = Unqual!(ElementEncodingType!Range);

enum privateUseStart = '\U000F0000', privateUseEnd ='\U000FFFFD';

// heuristic value determines maximum CodepointSet length suitable for linear search
enum maxCharsetUsed = 6;

// another variable to tweak behavior of caching generated Tries for character classes
enum maxCachedMatchers = 8;

alias Trie = CodepointSetTrie!(13, 8);
alias makeTrie = codepointSetTrie!(13, 8);

CharMatcher[CodepointSet] matcherCache;

//accessor with caching
@trusted CharMatcher getMatcher(CodepointSet set)
{// @@@BUG@@@ 6357 almost all properties of AA are not @safe
    if (__ctfe || maxCachedMatchers == 0)
        return CharMatcher(set);
    else
    {
        auto p = set in matcherCache;
        if (p)
            return *p;
        if (matcherCache.length == maxCachedMatchers)
        {
            // flush enmatchers in trieCache
            matcherCache = null;
        }
        return (matcherCache[set] = CharMatcher(set));
    }
}

@property ref wordMatcher()()
{
    static bool inited = false;
    static CharMatcher matcher;
    if (!inited) {
        matcher = CharMatcher(wordCharacter);
        inited = true;
    }
    return matcher;
}

//property for \w character class
package @property @safe CodepointSet wordCharacter()
{
    static CodepointSet set;
    if (set.empty) {
        set = unicode.Alphabetic | unicode.Mn | unicode.Mc
            | unicode.Me | unicode.Nd | unicode.Pc;
    }
    return set;
}

// some special Unicode white space characters
private enum NEL = '\u0085', LS = '\u2028', PS = '\u2029';

//Regular expression engine/parser options:
// global - search  all nonoverlapping matches in input
// casefold - case insensitive matching, do casefolding on match in unicode mode
// freeform - ignore whitespace in pattern, to match space use [ ] or \s
// multiline - switch  ^, $ detect start and end of linesinstead of just start and end of input
enum RegexOption: uint {
    global = 0x1,
    casefold = 0x2,
    freeform = 0x4,
    nonunicode = 0x8,
    multiline = 0x10,
    singleline = 0x20
}
//do not reorder this list
alias RegexOptionNames = AliasSeq!('g', 'i', 'x', 'U', 'm', 's');
static assert( RegexOption.max < 0x80);
// flags that allow guide execution of engine
enum RegexInfo : uint { oneShot = 0x80 }

// IR bit pattern: 0b1_xxxxx_yy
// where yy indicates class of instruction, xxxxx for actual operation code
//     00: atom, a normal instruction
//     01: open, opening of a group, has length of contained IR in the low bits
//     10: close, closing of a group, has length of contained IR in the low bits
//     11 unused
//
// Loops with Q (non-greedy, with ? mark) must have the same size / other properties as non Q version
// Possible changes:
//* merge group, option, infinite/repeat start (to never copy during parsing of (a|b){1,2})
//* reorganize groups to make n args easier to find, or simplify the check for groups of similar ops
//  (like lookaround), or make it easier to identify hotspots.

enum IR:uint {
    Char              = 0b1_00000_00, //a character
    Any               = 0b1_00001_00, //any character
    CodepointSet      = 0b1_00010_00, //a most generic CodepointSet [...]
    Trie              = 0b1_00011_00, //CodepointSet implemented as Trie
    //match with any of a consecutive OrChar's in this sequence
    //(used for case insensitive match)
    //OrChar holds in upper two bits of data total number of OrChars in this _sequence_
    //the drawback of this representation is that it is difficult
    // to detect a jump in the middle of it
    OrChar             = 0b1_00100_00,
    Nop                = 0b1_00101_00, //no operation (padding)
    End                = 0b1_00110_00, //end of program
    Bol                = 0b1_00111_00, //beginning of a line ^
    Eol                = 0b1_01000_00, //end of a line $
    Wordboundary       = 0b1_01001_00, //boundary of a word
    Notwordboundary    = 0b1_01010_00, //not a word boundary
    Backref            = 0b1_01011_00, //backreference to a group (that has to be pinned, i.e. locally unique) (group index)
    GroupStart         = 0b1_01100_00, //start of a group (x) (groupIndex+groupPinning(1bit))
    GroupEnd           = 0b1_01101_00, //end of a group (x) (groupIndex+groupPinning(1bit))
    Option             = 0b1_01110_00, //start of an option within an alternation x | y (length)
    GotoEndOr          = 0b1_01111_00, //end of an option (length of the rest)
    Bof                = 0b1_10000_00, //begining of "file" (string) ^
    Eof                = 0b1_10001_00, //end of "file" (string) $
    //... any additional atoms here

    OrStart            = 0b1_00000_01, //start of alternation group  (length)
    OrEnd              = 0b1_00000_10, //end of the or group (length,mergeIndex)
    //with this instruction order
    //bit mask 0b1_00001_00 could be used to test/set greediness
    InfiniteStart      = 0b1_00001_01, //start of an infinite repetition x* (length)
    InfiniteEnd        = 0b1_00001_10, //end of infinite repetition x* (length,mergeIndex)
    InfiniteQStart     = 0b1_00010_01, //start of a non eager infinite repetition x*? (length)
    InfiniteQEnd       = 0b1_00010_10, //end of non eager infinite repetition x*? (length,mergeIndex)
    InfiniteBloomStart = 0b1_00011_01, //start of an filtered infinite repetition x* (length)
    InfiniteBloomEnd   = 0b1_00011_10, //end of filtered infinite repetition x* (length,mergeIndex)
    RepeatStart        = 0b1_00100_01, //start of a {n,m} repetition (length)
    RepeatEnd          = 0b1_00100_10, //end of x{n,m} repetition (length,step,minRep,maxRep)
    RepeatQStart       = 0b1_00101_01, //start of a non eager x{n,m}? repetition (length)
    RepeatQEnd         = 0b1_00101_10, //end of non eager x{n,m}? repetition (length,step,minRep,maxRep)

    //
    LookaheadStart     = 0b1_00110_01, //begin of the lookahead group (length)
    LookaheadEnd       = 0b1_00110_10, //end of a lookahead group (length)
    NeglookaheadStart  = 0b1_00111_01, //start of a negative lookahead (length)
    NeglookaheadEnd    = 0b1_00111_10, //end of a negative lookahead (length)
    LookbehindStart    = 0b1_01000_01, //start of a lookbehind (length)
    LookbehindEnd      = 0b1_01000_10, //end of a lookbehind (length)
    NeglookbehindStart = 0b1_01001_01, //start of a negative lookbehind (length)
    NeglookbehindEnd   = 0b1_01001_10, //end of negative lookbehind (length)
}

// simple 128-entry bit-table used with a hash function
struct BitTable {
    uint[4] filter;

    this(CodepointSet set){
        foreach (iv; set.byInterval)
        {
            foreach (v; iv.a .. iv.b)
                add(v);
        }
    }

    void add()(dchar ch){
        immutable i = index(ch);
        filter[i >> 5]  |=  1<<(i & 31);
    }
    // non-zero -> might be present, 0 -> absent
    bool opIndex()(dchar ch) const{
        immutable i = index(ch);
        return (filter[i >> 5]>>(i & 31)) & 1;
    }

    static uint index()(dchar ch){
        return ((ch >> 7) ^ ch) & 0x7F;
    }
}

struct CharMatcher {
    BitTable ascii; // fast path for ASCII
    Trie trie;      // slow path for Unicode

    this(CodepointSet set)
    {
        auto asciiSet = set & unicode.ASCII;
        ascii = BitTable(asciiSet);
        trie = makeTrie(set);
    }

    bool opIndex()(dchar ch) const
    {
        if (ch < 0x80)
            return ascii[ch];
        else
            return trie[ch];
    }
}

struct Regex {
    ubyte[] prog;
    this(const(char)[] pattern, const(char)[] flags) {
        prog = [];
    }
}

struct Group(DataIndex)
{
    DataIndex begin, end;
    @trusted string toString()() const
    {
        import std.array : appender;
        import std.format : formattedWrite;
        auto a = appender!string();
        formattedWrite(a, "%s..%s", begin, end);
        return a.data;
    }
}