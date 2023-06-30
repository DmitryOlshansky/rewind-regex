// Lots of rudemntary things copied from std
// All of that shouldn't exist once std has `stack`
// and more extensive std.uni API.
module rewind.regex.impl.misc;

import std.range.primitives, std.uni, std.exception;
import rewind.regex.impl.tables;

//basic stack, just in case it gets used anywhere else then Parser
struct Stack(T)
{
@safe:
    T[] data;
    @property bool empty(){ return data.empty; }

    @property size_t length(){ return data.length; }

    void push(T val){ data ~= val;  }

    @trusted T pop()
    {
        assert(!empty);
        auto val = data[$ - 1];
        data = data[0 .. $ - 1];
        if (!__ctfe) data.assumeSafeAppend();
        return val;
    }

    @property ref T top()
    {
        assert(!empty);
        return data[$ - 1];
    }
}

/*
    Return a range of all $(CODEPOINTS) that casefold to
    and from this $(D ch).
*/
auto simpleCaseFoldings(dchar ch) @safe
{
     // generated file
    import rewind.regex.impl.tables : simpleCaseTable;
    alias sTable = simpleCaseTable;
    static struct Range
    {
    @safe pure nothrow:
        uint idx; //if == uint.max, then read c.
        union
        {
            dchar c; // == 0 - empty range
            uint len;
        }
        @property bool isSmall() const { return idx == uint.max; }

        this(dchar ch)
        {
            idx = uint.max;
            c = ch;
        }

        this(uint start, uint size)
        {
            idx = start;
            len = size;
        }

        @property dchar front() const
        {
            assert(!empty);
            if (isSmall)
            {
                return c;
            }
            auto ch = sTable[idx].ch;
            return ch;
        }

        @property bool empty() const
        {
            if (isSmall)
            {
                return c == 0;
            }
            return len == 0;
        }

        @property size_t length() const
        {
            if (isSmall)
            {
                return c == 0 ? 0 : 1;
            }
            return len;
        }

        void popFront()
        {
            if (isSmall)
                c = 0;
            else
            {
                idx++;
                len--;
            }
        }
    }
    immutable idx = ch; // TODO: simpleCaseTrie[ch];
    if (idx == EMPTY_CASE_TRIE)
        return Range(ch);
    auto entry = sTable[idx];
    immutable start = idx - entry.n;
    return Range(start, entry.size);
}

/*
unittest
{
    import std.algorithm.comparison : equal;
    import std.algorithm.searching : canFind;
    import std.array : array;
    auto r = simpleCaseFoldings('Э').array;
    assert(r.length == 2);
    assert(r.canFind('э') && r.canFind('Э'));
    auto sr = simpleCaseFoldings('~');
    assert(sr.equal("~"));
    //A with ring above - casefolds to the same bucket as Angstrom sign
    sr = simpleCaseFoldings('Å');
    assert(sr.length == 3);
    assert(sr.canFind('å') && sr.canFind('Å') && sr.canFind('\u212B'));
}
*/

//test if a given string starts with hex number of maxDigit that's a valid codepoint
//returns it's value and skips these maxDigit chars on success, throws on failure
dchar parseUniHex(Range)(ref Range str, size_t maxDigit)
{
    import std.exception : enforce;
    //std.conv.parse is both @system and bogus
    uint val;
    for (int k = 0; k < maxDigit; k++)
    {
        enforce(!str.empty, "incomplete escape sequence");
        //accepts ascii only, so it's OK to index directly
        immutable current = str.front;
        if ('0' <= current && current <= '9')
            val = val * 16 + current - '0';
        else if ('a' <= current && current <= 'f')
            val = val * 16 + current -'a' + 10;
        else if ('A' <= current && current <= 'F')
            val = val * 16 + current - 'A' + 10;
        else
            throw new Exception("invalid escape sequence");
        str.popFront();
    }
    enforce(val <= 0x10FFFF, "invalid codepoint");
    return val;
}

@safe unittest
{
    import std.algorithm.searching : canFind;
    import std.exception : collectException;
    string[] non_hex = [ "000j", "000z", "FffG", "0Z"];
    string[] hex = [ "01", "ff", "00af", "10FFFF" ];
    int[] value = [ 1, 0xFF, 0xAF, 0x10FFFF ];
    foreach (v; non_hex)
        assert(collectException(parseUniHex(v, v.length)).msg
          .canFind("invalid escape sequence"));
    foreach (i, v; hex)
        assert(parseUniHex(v, v.length) == value[i]);
    string over = "0011FFFF";
    assert(collectException(parseUniHex(over, over.length)).msg
      .canFind("invalid codepoint"));
}

static dchar parseControlCode(Parser)(ref Parser p)
{
    with(p)
    {
        popFront();
        enforce(!empty, "Unfinished escape sequence");
        enforce(('a' <= front && front <= 'z')
            || ('A' <= front && front <= 'Z'),
        "Only letters are allowed after \\c");
        return front & 0x1f;
    }
}

//parse and return a CodepointSet for \p{...Property...} and \P{...Property..},
//\ - assumed to be processed, p - is current
static CodepointSet parsePropertySpec(Range)(ref Range p,
    bool negated, bool casefold)
{
    static import std.ascii;
    with(p)
    {
        enum MAX_PROPERTY = 128;
        char[MAX_PROPERTY] result;
        uint k = 0;
        popFront();
        enforce(!empty, "eof parsing unicode property spec");
        if (front == '{')
        {
            popFront();
            while (k < MAX_PROPERTY && !empty && front !='}'
                && front !=':')
            {
                if (front != '-' && front != ' ' && front != '_')
                    result[k++] = cast(char) std.ascii.toLower(front);
                popFront();
            }
            enforce(k != MAX_PROPERTY, "invalid property name");
            enforce(front == '}', "} expected ");
        }
        else
        {//single char properties e.g.: \pL, \pN ...
            enforce(front < 0x80, "invalid property name");
            result[k++] = cast(char) front;
        }
        auto s = getUnicodeSet(result[0 .. k], negated, casefold);
        enforce(!s.empty, "unrecognized unicode property spec");
        popFront();
        return s;
    }
}

@trusted CodepointSet getUnicodeSet(const scope char[] name, bool negated,  bool casefold)
{
    CodepointSet s = unicode(name);
    //FIXME: caseEnclose for new uni as Set | CaseEnclose(SET && LC)
    if (casefold)
       s = caseEnclose(s);
    if (negated)
        s = s.inverted;
    return s;
}

auto caseEnclose(CodepointSet set)
{
    auto cased = set & unicode.LC;
    foreach (dchar ch; cased.byCodepoint)
    {
        foreach (c; simpleCaseFoldings(ch))
            set |= c;
    }
    return set;
}
