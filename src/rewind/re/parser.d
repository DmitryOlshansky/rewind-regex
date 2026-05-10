module rewind.re.parser;

import std.uni, std.typecons, std.conv, std.exception, std.meta;
import pry;
import rewind.re.ast, rewind.re.impl.misc;

private alias Stream = SimpleStream!(const(char)[]);
private alias env = parsers!Stream;
env.DynamicParser!Ast parser;

class ParseException : Exception {
    this(string msg){
        super(msg);
    }
}

struct UnicodeSetParser(Stream)
{
    import std.typecons : tuple, Tuple;
    import rewind.re.impl.stack;
    import rewind.re.impl.misc;
    
    
    Stream range;
    bool casefold_;

    @property bool empty(){ return range.empty; }
    @property dchar front(){ return range.front; }
    void popFront(){ range.popFront(); }

    static void check(bool expr, string msg) {
        if(!expr) {
            throw new ParseException(msg);
        }
    }

    //CodepointSet operations relatively in order of priority
    enum Operator:uint {
        Open = 0, Negate,  Difference, SymDifference, Intersection, Union, None
    }

    //parse unit of CodepointSet spec, most notably escape sequences and char ranges
    //also fetches next set operation
    Tuple!(CodepointSet,Operator) parseCharTerm()
    {
        import std.range : drop;
        enum privateUseStart = '\U000F0000', privateUseEnd ='\U000FFFFD';
        enum State{ Start, Char, Escape, CharDash, CharDashEscape,
            PotentialTwinSymbolOperator }
        Operator op = Operator.None;
        dchar last;
        CodepointSet set;
        State state = State.Start;

        void addWithFlags(ref CodepointSet set, uint ch)
        {
            if (casefold_)
            {
                auto foldings = simpleCaseFoldings(ch);
                foreach (v; foldings)
                    set |= v;
            }
            else
                set |= ch;
        }

        static Operator twinSymbolOperator(dchar symbol)
        {
            switch (symbol)
            {
            case '|':
                return Operator.Union;
            case '-':
                return Operator.Difference;
            case '~':
                return Operator.SymDifference;
            case '&':
                return Operator.Intersection;
            default:
                assert(false);
            }
        }

        L_CharTermLoop:
        for (;;)
        {
            final switch (state)
            {
            case State.Start:
                switch (front)
                {
                case '|':
                case '-':
                case '~':
                case '&':
                    state = State.PotentialTwinSymbolOperator;
                    last = front;
                    break;
                case '[':
                    op = Operator.Union;
                    goto case;
                case ']':
                    break L_CharTermLoop;
                case '\\':
                    state = State.Escape;
                    break;
                default:
                    state = State.Char;
                    last = front;
                }
                break;
            case State.Char:
                // xxx last front xxx
                switch (front)
                {
                case '|':
                case '~':
                case '&':
                    // then last is treated as normal char and added as implicit union
                    state = State.PotentialTwinSymbolOperator;
                    addWithFlags(set, last);
                    last = front;
                    break;
                case '-': // still need more info
                    state = State.CharDash;
                    break;
                case '\\':
                    set |= last;
                    state = State.Escape;
                    break;
                case '[':
                    op = Operator.Union;
                    goto case;
                case ']':
                    addWithFlags(set, last);
                    break L_CharTermLoop;
                default:
                    state = State.Char;
                    addWithFlags(set, last);
                    last = front;
                }
                break;
            case State.PotentialTwinSymbolOperator:
                // xxx last front xxxx
                // where last = [|-&~]
                if (front == last)
                {
                    op = twinSymbolOperator(last);
                    popFront();//skip second twin char
                    break L_CharTermLoop;
                }
                goto case State.Char;
            case State.Escape:
                // xxx \ front xxx
                switch (front)
                {
                case 'f':
                    last = '\f';
                    state = State.Char;
                    break;
                case 'n':
                    last = '\n';
                    state = State.Char;
                    break;
                case 'r':
                    last = '\r';
                    state = State.Char;
                    break;
                case 't':
                    last = '\t';
                    state = State.Char;
                    break;
                case 'v':
                    last = '\v';
                    state = State.Char;
                    break;
                case 'c':
                    last = parseControlCode(this);
                    state = State.Char;
                    break;
                foreach (val; Escapables)
                {
                case val:
                }
                    last = front;
                    state = State.Char;
                    break;
                case 'p':
                    set.add(parsePropertySpec(this, false, casefold_));
                    state = State.Start;
                    continue L_CharTermLoop; //next char already fetched
                case 'P':
                    set.add(parsePropertySpec(this, true, casefold_));
                    state = State.Start;
                    continue L_CharTermLoop; //next char already fetched
                case 'x':
                    popFront();
                    last = parseUniHex(this, 2);
                    state = State.Char;
                    continue L_CharTermLoop;
                case 'u':
                    popFront();
                    last = parseUniHex(this, 4);
                    state = State.Char;
                    continue L_CharTermLoop;
                case 'U':
                    popFront();
                    last = parseUniHex(this, 8);
                    state = State.Char;
                    continue L_CharTermLoop;
                case 'd':
                    set.add(unicode.Nd);
                    state = State.Start;
                    break;
                case 'D':
                    set.add(unicode.Nd.inverted);
                    state = State.Start;
                    break;
                case 's':
                    set.add(unicode.White_Space);
                    state = State.Start;
                    break;
                case 'S':
                    set.add(unicode.White_Space.inverted);
                    state = State.Start;
                    break;
                case 'w':
                    set.add(wordCharacter);
                    state = State.Start;
                    break;
                case 'W':
                    set.add(wordCharacter.inverted);
                    state = State.Start;
                    break;
                default:
                    if (front >= privateUseStart && front <= privateUseEnd)
                        check(false, "no matching ']' found while parsing character class");
                    check(false, "invalid escape sequence");
                }
                break;
            case State.CharDash:
                // xxx last - front xxx
                switch (front)
                {
                case '[':
                    op = Operator.Union;
                    goto case;
                case ']':
                    //means dash is a single char not an interval specifier
                    addWithFlags(set, last);
                    addWithFlags(set, '-');
                    break L_CharTermLoop;
                 case '-'://set Difference again
                    addWithFlags(set, last);
                    op = Operator.Difference;
                    popFront();//skip '-'
                    break L_CharTermLoop;
                case '\\':
                    state = State.CharDashEscape;
                    break;
                default:
                    check(last <= front, "inverted range");
                    if (casefold_)
                    {
                        for (uint ch = last; ch <= front; ch++)
                            addWithFlags(set, ch);
                    }
                    else
                        set.add(last, front + 1);
                    state = State.Start;
                }
                break;
            case State.CharDashEscape:
            //xxx last - \ front xxx
                uint end;
                switch (front)
                {
                case 'f':
                    end = '\f';
                    break;
                case 'n':
                    end = '\n';
                    break;
                case 'r':
                    end = '\r';
                    break;
                case 't':
                    end = '\t';
                    break;
                case 'v':
                    end = '\v';
                    break;
                foreach (val; Escapables)
                {
                case val:
                }
                    end = front;
                    break;
                case 'c':
                    end = parseControlCode(this);
                    break;
                case 'x':
                    popFront();
                    end = parseUniHex(this, 2);
                    check(last <= end,"inverted range");
                    set.add(last, end + 1);
                    state = State.Start;
                    continue L_CharTermLoop;
                case 'u':
                    popFront();
                    end = parseUniHex(this, 4);
                    check(last <= end,"inverted range");
                    set.add(last, end + 1);
                    state = State.Start;
                    continue L_CharTermLoop;
                case 'U':
                    popFront();
                    end = parseUniHex(this, 8);
                    check(last <= end,"inverted range");
                    set.add(last, end + 1);
                    state = State.Start;
                    continue L_CharTermLoop;
                default:
                    if (front >= privateUseStart && front <= privateUseEnd)
                        check(false, "no matching ']' found while parsing character class");
                    check(false, "invalid escape sequence");
                }
                // Lookahead to check if it's a \T
                // where T is sub-pattern terminator in multi-pattern scheme
                auto lookahead = range.save.drop(1);
                if (end == '\\' && !lookahead.empty)
                {
                    if (lookahead.front >= privateUseStart && lookahead.front <= privateUseEnd)
                        check(false, "no matching ']' found while parsing character class");
                }
                check(last <= end,"inverted range");
                set.add(last, end + 1);
                state = State.Start;
                break;
            }
            popFront();
            check(!empty, "unexpected end of CodepointSet");
        }
        return tuple(set, op);
    }

    alias ValStack = Stack!(CodepointSet);
    alias OpStack = Stack!(Operator);

    CodepointSet parseSet()
    {
        ValStack vstack;
        OpStack opstack;
        import std.functional : unaryFun;
        check(!empty, "unexpected end of input");
        check(front == '[', "expected '[' at the start of unicode set");
        //
        static bool apply(Operator op, ref ValStack stack)
        {
            switch (op)
            {
            case Operator.Negate:
                check(!stack.empty, "no operand for '^'");
                stack.top = stack.top.inverted;
                break;
            case Operator.Union:
                auto s = stack.pop();//2nd operand
                check(!stack.empty, "no operand for '||'");
                stack.top.add(s);
                break;
            case Operator.Difference:
                auto s = stack.pop();//2nd operand
                check(!stack.empty, "no operand for '--'");
                stack.top -= s;
                break;
            case Operator.SymDifference:
                auto s = stack.pop();//2nd operand
                check(!stack.empty, "no operand for '~~'");
                stack.top ~= s;
                break;
            case Operator.Intersection:
                auto s = stack.pop();//2nd operand
                check(!stack.empty, "no operand for '&&'");
                stack.top &= s;
                break;
            default:
                return false;
            }
            return true;
        }
        static bool unrollWhile(alias cond)(ref ValStack vstack, ref OpStack opstack)
        {
            while (cond(opstack.top))
            {
                if (!apply(opstack.pop(),vstack))
                    return false;//syntax error
                if (opstack.empty)
                    return false;
            }
            return true;
        }

        L_CharsetLoop:
        do
        {
            switch (front)
            {
            case '[':
                opstack.push(Operator.Open);
                popFront();
                check(!empty, "unexpected end of character class");
                if (front == '^')
                {
                    opstack.push(Operator.Negate);
                    popFront();
                    check(!empty, "unexpected end of character class");
                }
                else if (front == ']') // []...] is special cased
                {
                    popFront();
                    check(!empty, "wrong character set");
                    auto pair = parseCharTerm();
                    pair[0].add(']', ']'+1);
                    if (pair[1] != Operator.None)
                    {
                        if (opstack.top == Operator.Union)
                            unrollWhile!(unaryFun!"a == a.Union")(vstack, opstack);
                        opstack.push(pair[1]);
                    }
                    vstack.push(pair[0]);
                }
                break;
            case ']':
                check(unrollWhile!(unaryFun!"a != a.Open")(vstack, opstack),
                    "character class syntax error");
                check(!opstack.empty, "unmatched ']'");
                opstack.pop();
                popFront();
                if (opstack.empty)
                    break L_CharsetLoop;
                auto pair  = parseCharTerm();
                if (!pair[0].empty)//not only operator e.g. -- or ~~
                {
                    vstack.top.add(pair[0]);//apply union
                }
                if (pair[1] != Operator.None)
                {
                    if (opstack.top == Operator.Union)
                        unrollWhile!(unaryFun!"a == a.Union")(vstack, opstack);
                    opstack.push(pair[1]);
                }
                break;
            //
            default://yet another pair of term(op)?
                auto pair = parseCharTerm();
                if (pair[1] != Operator.None)
                {
                    if (opstack.top == Operator.Union)
                        unrollWhile!(unaryFun!"a == a.Union")(vstack, opstack);
                    opstack.push(pair[1]);
                }
                vstack.push(pair[0]);
            }

        }while (!empty || !opstack.empty);
        while (!opstack.empty)
            apply(opstack.pop(),vstack);
        assert(vstack.length == 1);
        return vstack.top;
    }
}

struct CharClassParser {
    bool casefold;
    bool parse(ref Stream stream, ref CodepointSet value, ref Stream.Error err) const {
        if(stream.empty) {
            err.location = stream.location;
            err.reason = "unexpected end of stream";
            return false;
        }
        auto p =  UnicodeSetParser!Stream(stream, casefold);
        try {
            value = p.parseSet();
            stream = p.range;
            return true;
        } catch (ParseException e) {
            err.location = p.range.location;
            err.reason = e.msg;
            return false;
        }
    }
}

CodepointSet wordCharacter;

static this() {
    wordCharacter = unicode.Alphabetic | unicode.Mn | unicode.Mc
        | unicode.Me | unicode.Nd | unicode.Pc;
    CodepointSet addChars(CodepointSet set, string chars) {
        foreach(dchar ch; chars) {
            set.add(ch, ch+1);
        }
        return set;
    }
    auto allowedChars =	addChars(unicode.Cc, "[]{}()\\.?*+|").inverted;
    auto digits = CodepointSet('0', '9'+1);
    auto hex = CodepointSet('0', '9'+1, 'a', 'f'+1, 'A', 'F'+1);
    auto cc = CodepointSet('a', 'z'+1, 'A', 'Z'+1);
    with(env) {
        auto num = set(digits).rep.map!(x => x.to!int);
        auto expr = dynamic!Ast();
        auto escapes = seq(tk!'\\',
            any( 
                any(
                    staticMap!(tk, Escapables),
                    tk!'b'.map!(_ => cast(dchar)'\b'),
                    tk!'f'.map!(_ => cast(dchar)'\f'),
                    tk!'n'.map!(_ => cast(dchar)'\n'),
                    tk!'r'.map!(_ => cast(dchar)'\r'),
                    tk!'t'.map!(_ => cast(dchar)'\t'),
                    seq(tk!'c', set(cc).map!(x => x & 0x1f)).map!(x => cast(dchar)x[1]),
                    seq(tk!'x', set(hex).rep!(2,2)).map!(x => cast(dchar)to!int(x[1], 16)),
                    seq(tk!'u', set(hex).rep!(4,4)).map!(x => cast(dchar)to!int(x[1], 16)),
                    seq(tk!'U', set(hex).rep!(8,8)).map!(x => cast(dchar)to!int(x[1], 16))
                ).map!(x => cast(Ast) new Char(x)),
                any(
                    tk!'s'.map!(_ => cast(Ast)new CharClass(unicode.whitespace)),
                    tk!'S'.map!(_ => cast(Ast)new CharClass(unicode.whitespace.inverted)),
                    tk!'w'.map!(_ => cast(Ast)new CharClass(wordCharacter)),
                    tk!'W'.map!(_ => cast(Ast)new CharClass(wordCharacter.inverted)),
                    tk!'d'.map!(_ => cast(Ast)new CharClass(unicode.Nd)),
                    tk!'D'.map!(_ => cast(Ast)new CharClass(unicode.Nd.inverted)),
                )
            )
        ).map!(x => x[1]);
        auto atom = any(
            seq(tk!'(', expr, tk!')').map!(x => cast(Ast)new Group(x[1])),
            escapes,
            tk!'.'.map!(x => cast(Ast) new Dot()),
            CharClassParser(false).map!(x => cast(Ast)new CharClass(x)),
            set(allowedChars).map!(x => cast(Ast) new Char(x))
        );
        auto quantified = seq(
            atom,
            any(
                seq(tk!'{', num, tk!',', num, tk!'}').map!(x => tuple(x[1], x[3])),
                seq(tk!'{', num, tk!',', tk!'}').map!(x => tuple(x[1], -1)),
                seq(tk!'{', num, tk!'}').map!(x => tuple(x[1], x[1])),
                tk!'*'.map!(x => tuple(0, -1)),
                tk!'+'.map!(x => tuple(1, -1)),
                tk!'?'.map!(x => tuple(0, 1)),
            ).optional
        ).map!(x => x[1].isNull ? x[0] : cast(Ast)new Rep(x[0], x[1][0], x[1][1]));
        expr = delimited(quantified.array!0.map!(x => cast(Ast)new Seq(x)), tk!'|').map!(x => cast(Ast)new Alt(x));
        auto p = dynamic!Ast();
        p = expr.map!(x => cast(Ast)new Pattern([x]));
        parser = p;
    }
}

Ast parse(const(char)[] pattern) {
    Stream.Error err;
    Ast v;
    auto stream = stream(pattern);
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
    assert(parse("a[a-z]c").repr == "a[\\u0061-\\u007a]c");
    assert(parse("a[a-z--z]c").repr == "a[\\u0061-\\u0079]c");
    assert(parse("[a]").repr == "[\\u0061-\\u0061]");
    assertThrown!ParseException(parse("[a"));
    assert(parse("\\cA").repr == "\x01");
    assert(parse("\\cz").repr == "\x1a");
    assert(parse("\\cA").repr == "\x01");
    assertThrown(parse("\\c"));
    assertThrown(parse("\\c1"));
    void testCharSet(string pat, CodepointSet set) {
        auto p = (cast(Pattern)parse(pat)).children[0];
        auto alt = cast(Alt)p;
        auto inner = alt.alts[0];
        auto seq = cast(Seq)inner;
        auto ch = cast(CharClass)seq.seq[0];
        assert(ch.chars == set);
    }
    testCharSet("\\s", unicode.whitespace);
    testCharSet("\\S", unicode.whitespace.inverted);
    testCharSet("\\w", wordCharacter);
    testCharSet("\\W", wordCharacter.inverted);
    testCharSet("\\d", unicode.Nd);
    testCharSet("\\D", unicode.Nd.inverted);
}