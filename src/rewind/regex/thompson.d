/*
    Implementation of Thompson NFA rewind.regex engine.
    Key point is evaluation of all possible threads (states) at each step
    in a breadth-first manner, thereby geting some nice properties:
        - looking at each character only once
        - merging of equivalent threads, that gives matching process linear time complexity
*/
module rewind.regex.thompson;

package:

import std.range.primitives;
import rewind.regex.ir;

//State of VM thread
struct Thread(DataIndex)
{
    Thread* next;    //intrusive linked list
    uint pc;
    uint counter;    //loop counter
    uint uopCounter; //counts micro operations inside one macro instruction (e.g. BackRef)
    Group!DataIndex[1] matches;
}

//head-tail singly-linked list
struct ThreadList(DataIndex)
{
    Thread!DataIndex* tip = null, toe = null;
    //add new thread to the start of list
    void insertFront(Thread!DataIndex* t)
    {
        if (tip)
        {
            t.next = tip;
            tip = t;
        }
        else
        {
            t.next = null;
            tip = toe = t;
        }
    }
    //add new thread to the end of list
    void insertBack(Thread!DataIndex* t)
    {
        if (toe)
        {
            toe.next = t;
            toe = t;
        }
        else
            tip = toe = t;
        toe.next = null;
    }
    //move head element out of list
    Thread!DataIndex* fetch()
    {
        auto t = tip;
        if (tip == toe)
            tip = toe = null;
        else
            tip = tip.next;
        return t;
    }
    //non-destructive iteration of ThreadList
    struct ThreadRange
    {
        const(Thread!DataIndex)* ct;
        this(ThreadList tlist){ ct = tlist.tip; }
        @property bool empty(){ return ct is null; }
        @property const(Thread!DataIndex)* front(){ return ct; }
        @property popFront()
        {
            assert(ct);
            ct = ct.next;
        }
    }
    @property bool empty()
    {
        return tip == null;
    }
    ThreadRange opSlice()
    {
        return ThreadRange(this);
    }
}

template ThompsonOps(E, S, bool withInput:true)
{
@trusted:
    static bool op(IR code:IR.End)(E e, S* state)
    {
        with(e) with(state)
        {
            finish(t, matches, re.ir[t.pc].data);
            //fix endpoint of the whole match
            matches[0].end = index;
            recycle(t);
            //cut off low priority threads
            recycle(clist);
            recycle(worklist);
            debug(std_regex_matcher) writeln("Finished thread ", matches);
            return false; // no more state to eval
        }
    }

    static bool op(IR code:IR.Wordboundary)(E e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            //at start & end of input
            if (atStart && wordMatcher[front])
            {
                t.pc += IRL!(IR.Wordboundary);
                return true;
            }
            else if (atEnd && s.loopBack(index).nextChar(back, bi)
                    && wordMatcher[back])
            {
                t.pc += IRL!(IR.Wordboundary);
                return true;
            }
            else if (s.loopBack(index).nextChar(back, bi))
            {
                bool af = wordMatcher[front];
                bool ab = wordMatcher[back];
                if (af ^ ab)
                {
                    t.pc += IRL!(IR.Wordboundary);
                    return true;
                }
            }
            return popState(e);
        }
    }

    static bool op(IR code:IR.Notwordboundary)(E e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            //at start & end of input
            if (atStart && wordMatcher[front])
            {
                return popState(e);
            }
            else if (atEnd && s.loopBack(index).nextChar(back, bi)
                    && wordMatcher[back])
            {
                return popState(e);
            }
            else if (s.loopBack(index).nextChar(back, bi))
            {
                bool af = wordMatcher[front];
                bool ab = wordMatcher[back]  != 0;
                if (af ^ ab)
                {
                    return popState(e);
                }
            }
            t.pc += IRL!(IR.Notwordboundary);
        }
        return true;
    }

    static bool op(IR code:IR.Bof)(E e, S* state)
    {
        with(e) with(state)
        {
            if (atStart)
            {
                t.pc += IRL!(IR.Bof);
                return true;
            }
            else
            {
                return popState(e);
            }
        }
    }

    static bool op(IR code:IR.Bol)(E e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            if (atStart
                ||(s.loopBack(index).nextChar(back,bi)
                && startOfLine(back, front == '\n')))
            {
                t.pc += IRL!(IR.Bol);
                return true;
            }
            else
            {
                return popState(e);
            }
        }
    }

    static bool op(IR code:IR.Eof)(E e, S* state)
    {
        with(e) with(state)
        {
            if (atEnd)
            {
                t.pc += IRL!(IR.Eol);
                return true;
            }
            else
            {
                return popState(e);
            }
        }
    }

    static bool op(IR code:IR.Eol)(E e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            //no matching inside \r\n
            if (atEnd || (endOfLine(front, s.loopBack(index).nextChar(back, bi)
                    && back == '\r')))
            {
                t.pc += IRL!(IR.Eol);
                return true;
            }
            else
            {
                return popState(e);
            }

        }
    }

    static bool op(IR code:IR.InfiniteStart)(E e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.InfiniteStart);
        return op!(IR.InfiniteEnd)(e,state);
    }

    static bool op(IR code:IR.InfiniteBloomStart)(E e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.InfiniteBloomStart);
        return op!(IR.InfiniteBloomEnd)(e,state);
    }

    static bool op(IR code:IR.InfiniteQStart)(E e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.InfiniteQStart);
        return op!(IR.InfiniteQEnd)(e,state);
    }

    static bool op(IR code:IR.RepeatStart)(E e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.RepeatStart);
        return op!(IR.RepeatEnd)(e,state);
    }

    static bool op(IR code:IR.RepeatQStart)(E e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.RepeatQStart);
        return op!(IR.RepeatQEnd)(e,state);
    }

    static bool op(IR code)(E e, S* state)
        if (code == IR.RepeatEnd || code == IR.RepeatQEnd)
    {
        with(e) with(state)
        {
            //len, step, min, max
                uint len = re.ir[t.pc].data;
                uint step =  re.ir[t.pc+2].raw;
                uint min = re.ir[t.pc+3].raw;
                if (t.counter < min)
                {
                    t.counter += step;
                    t.pc -= len;
                    return true;
                }
                if (merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
                {
                    debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                    t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                    merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
                }
                else
                {
                    debug(std_regex_matcher)
                        writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                            t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                    return popState(e);
                }
                uint max = re.ir[t.pc+4].raw;
                if (t.counter < max)
                {
                    if (re.ir[t.pc].code == IR.RepeatEnd)
                    {
                        //queue out-of-loop thread
                        worklist.insertFront(fork(t, t.pc + IRL!(IR.RepeatEnd),  t.counter % step));
                        t.counter += step;
                        t.pc -= len;
                    }
                    else
                    {
                        //queue into-loop thread
                        worklist.insertFront(fork(t, t.pc - len,  t.counter + step));
                        t.counter %= step;
                        t.pc += IRL!(IR.RepeatEnd);
                    }
                }
                else
                {
                    t.counter %= step;
                    t.pc += IRL!(IR.RepeatEnd);
                }
                return true;
        }
    }

    static bool op(IR code)(E e, S* state)
        if (code == IR.InfiniteEnd || code == IR.InfiniteQEnd)
    {
        with(e) with(state)
        {
            if (merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
            }
            else
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                return popState(e);
            }
            uint len = re.ir[t.pc].data;
            uint pc1, pc2; //branches to take in priority order
            if (re.ir[t.pc].code == IR.InfiniteEnd)
            {
                pc1 = t.pc - len;
                pc2 = t.pc + IRL!(IR.InfiniteEnd);
            }
            else
            {
                pc1 = t.pc + IRL!(IR.InfiniteEnd);
                pc2 = t.pc - len;
            }
            worklist.insertFront(fork(t, pc2, t.counter));
            t.pc = pc1;
            return true;
        }
    }

    static bool op(IR code)(E e, S* state)
        if (code == IR.InfiniteBloomEnd)
    {
        with(e) with(state)
        {
            if (merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
            }
            else
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                return popState(e);
            }
            uint len = re.ir[t.pc].data;
            uint pc1, pc2; //branches to take in priority order
            pc1 = t.pc - len;
            pc2 = t.pc + IRL!(IR.InfiniteBloomEnd);
            uint filterIndex = re.ir[t.pc + 2].raw;
            if (re.filters[filterIndex][front])
                worklist.insertFront(fork(t, pc2, t.counter));
            t.pc = pc1;
            return true;
        }
    }

    static bool op(IR code:IR.OrEnd)(E e, S* state)
    {
        with(e) with(state)
        {
            if (merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, s[index .. s.lastIndex], genCounter, merge[re.ir[t.pc + 1].raw + t.counter] );
                merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
                t.pc += IRL!(IR.OrEnd);
            }
            else
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, s[index .. s.lastIndex], genCounter, merge[re.ir[t.pc + 1].raw + t.counter] );
                return popState(e);
            }
            return true;
        }
    }

    static bool op(IR code:IR.OrStart)(E e, S* state)
    {
        with(e) with(state)
        {
            t.pc += IRL!(IR.OrStart);
            return op!(IR.Option)(e,state);
        }
    }

    static bool op(IR code:IR.Option)(E e, S* state)
    {
        with(e) with(state)
        {
            uint next = t.pc + re.ir[t.pc].data + IRL!(IR.Option);
            //queue next Option
            if (re.ir[next].code == IR.Option)
            {
                worklist.insertFront(fork(t, next, t.counter));
            }
            t.pc += IRL!(IR.Option);
            return true;
        }
    }

    static bool op(IR code:IR.GotoEndOr)(E e, S* state)
    {
        with(e) with(state)
        {
            t.pc = t.pc + re.ir[t.pc].data + IRL!(IR.GotoEndOr);
            return op!(IR.OrEnd)(e, state);
        }
    }

    static bool op(IR code:IR.GroupStart)(E e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            t.matches.ptr[n].begin = index;
            t.pc += IRL!(IR.GroupStart);
            return true;
        }
    }
    static bool op(IR code:IR.GroupEnd)(E e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            t.matches.ptr[n].end = index;
            t.pc += IRL!(IR.GroupEnd);
            return true;
        }
    }

    static bool op(IR code:IR.Backref)(E e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            Group!DataIndex* source = re.ir[t.pc].localRef ? t.matches.ptr : backrefed.ptr;
            assert(source);
            if (source[n].begin == source[n].end)//zero-width Backref!
            {
                t.pc += IRL!(IR.Backref);
                return true;
            }
            else
            {
                size_t idx = source[n].begin + t.uopCounter;
                size_t end = source[n].end;
                if (s[idx .. end].front == front)
                {
                    import std.utf : stride;

                    t.uopCounter += stride(s[idx .. end], 0);
                    if (t.uopCounter + source[n].begin == source[n].end)
                    {//last codepoint
                        t.pc += IRL!(IR.Backref);
                        t.uopCounter = 0;
                    }
                    nlist.insertBack(t);
                }
                else
                    recycle(t);
                t = worklist.fetch();
                return t != null;
            }
        }
    }


    static bool op(IR code)(E e, S* state)
        if (code == IR.LookbehindStart || code == IR.NeglookbehindStart)
    {
        with(e) with(state)
        {
            uint len = re.ir[t.pc].data;
            uint ms = re.ir[t.pc + 1].raw, me = re.ir[t.pc + 2].raw;
            uint end = t.pc + len + IRL!(IR.LookbehindEnd) + IRL!(IR.LookbehindStart);
            bool positive = re.ir[t.pc].code == IR.LookbehindStart;
            static if (Stream.isLoopback)
                auto matcher = fwdMatcher(t.pc, end, me - ms, subCounters.get(t.pc, 0));
            else
                auto matcher = bwdMatcher(t.pc, end, me - ms, subCounters.get(t.pc, 0));
            matcher.backrefed = backrefed.empty ? t.matches : backrefed;
            //backMatch
            auto mRes = matcher.matchOneShot(t.matches.ptr[ms .. me], IRL!(IR.LookbehindStart));
            freelist = matcher.freelist;
            subCounters[t.pc] = matcher.genCounter;
            if ((mRes != 0 ) ^ positive)
            {
                return popState(e);
            }
            t.pc = end;
            return true;
        }
    }

    static bool op(IR code)(E e, S* state)
        if (code == IR.LookaheadStart || code == IR.NeglookaheadStart)
    {
        with(e) with(state)
        {
            auto save = index;
            uint len = re.ir[t.pc].data;
            uint ms = re.ir[t.pc+1].raw, me = re.ir[t.pc+2].raw;
            uint end = t.pc+len+IRL!(IR.LookaheadEnd)+IRL!(IR.LookaheadStart);
            bool positive = re.ir[t.pc].code == IR.LookaheadStart;
            static if (Stream.isLoopback)
                auto matcher = bwdMatcher(t.pc, end, me - ms, subCounters.get(t.pc, 0));
            else
                auto matcher = fwdMatcher(t.pc, end, me - ms, subCounters.get(t.pc, 0));
            matcher.backrefed = backrefed.empty ? t.matches : backrefed;
            auto mRes = matcher.matchOneShot(t.matches.ptr[ms .. me], IRL!(IR.LookaheadStart));
            freelist = matcher.freelist;
            subCounters[t.pc] = matcher.genCounter;
            s.reset(index);
            next();
            if ((mRes != 0) ^ positive)
            {
                return popState(e);
            }
            t.pc = end;
            return true;
        }
    }

    static bool op(IR code)(E e, S* state)
        if (code == IR.LookaheadEnd || code == IR.NeglookaheadEnd ||
            code == IR.LookbehindEnd || code == IR.NeglookbehindEnd)
    {
        with(e) with(state)
        {
                finish(t, matches.ptr[0 .. re.ngroup], re.ir[t.pc].data);
                recycle(t);
                //cut off low priority threads
                recycle(clist);
                recycle(worklist);
                return false; // no more state
        }
    }

    static bool op(IR code:IR.Nop)(E e, S* state)
    {
        with(state) t.pc += IRL!(IR.Nop);
        return true;
    }

    static bool op(IR code:IR.OrChar)(E e, S* state)
    {
        with(e) with(state)
        {
            uint len = re.ir[t.pc].sequence;
            uint end = t.pc + len;
            static assert(IRL!(IR.OrChar) == 1);
            for (; t.pc < end; t.pc++)
                if (re.ir[t.pc].data == front)
                    break;
            if (t.pc != end)
            {
                t.pc = end;
                nlist.insertBack(t);
            }
            else
                recycle(t);
            t = worklist.fetch();
            return t != null;
        }
    }

    static bool op(IR code:IR.Char)(E e, S* state)
    {
        with(e) with(state)
        {
            if (front == re.ir[t.pc].data)
            {
                t.pc += IRL!(IR.Char);
                nlist.insertBack(t);
            }
            else
                recycle(t);
            t = worklist.fetch();
            return t != null;
        }
    }

    static bool op(IR code:IR.Any)(E e, S* state)
    {
        with(e) with(state)
        {
            t.pc += IRL!(IR.Any);
            nlist.insertBack(t);
            t = worklist.fetch();
            return t != null;
        }
    }

    static bool op(IR code:IR.CodepointSet)(E e, S* state)
    {
        with(e) with(state)
        {
            if (re.charsets[re.ir[t.pc].data].scanFor(front))
            {
                t.pc += IRL!(IR.CodepointSet);
                nlist.insertBack(t);
            }
            else
            {
                recycle(t);
            }
            t = worklist.fetch();
            return t != null;
        }
    }

    static bool op(IR code:IR.Trie)(E e, S* state)
    {
        with(e) with(state)
        {
            if (re.matchers[re.ir[t.pc].data][front])
            {
                t.pc += IRL!(IR.Trie);
                nlist.insertBack(t);
            }
            else
            {
                recycle(t);
            }
            t = worklist.fetch();
            return t != null;
        }
    }

}

template ThompsonOps(E,S, bool withInput:false)
{
@trusted:
    // can't match these without input
    static bool op(IR code)(E e, S* state)
        if (code == IR.Char || code == IR.OrChar || code == IR.CodepointSet
        || code == IR.Trie || code == IR.Char || code == IR.Any)
    {
        return state.popState(e);
    }

    // special case of zero-width backref
    static bool op(IR code:IR.Backref)(E e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            Group!DataIndex* source = re.ir[t.pc].localRef ? t.matches.ptr : backrefed.ptr;
            assert(source);
            if (source[n].begin == source[n].end)//zero-width Backref!
            {
                t.pc += IRL!(IR.Backref);
                return true;
            }
            else
                return popState(e);
        }
    }

    // forward all control flow to normal versions
    static bool op(IR code)(E e, S* state)
        if (code != IR.Char && code != IR.OrChar && code != IR.CodepointSet
        && code != IR.Trie && code != IR.Char && code != IR.Any && code != IR.Backref)
    {
        return ThompsonOps!(E,S,true).op!code(e,state);
    }
}

