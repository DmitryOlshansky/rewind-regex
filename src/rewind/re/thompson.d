module rewind.re.thompson;

import rewind.re.bytecode;

import std.utf;

// single arena of memory setup for reuse
struct MemoryArena {
private:
    void[] memory;
public:
    void[] allocate(size_t size) {
        if (size > memory.length) {
            memory.length = size; 
        }
        return memory[0..size];
    }
}

MemoryArena arena; // TLS cache of memory for thompson VM use

struct ThompsonThread { // this is variably sized depending on number of captures
    ThompsonThread* next;
    size_t pc;
    size_t[0] marks; // 2x captures, including the whole match
    
    static size_t sizeOf(int numMarks) {
        return (ThompsonThread*).sizeof + size_t.sizeof + size_t.sizeof * numMarks;
    }

    static ThompsonThread* allocate(ref void* stack, int numMarks) {
        ThompsonThread* p = cast(ThompsonThread*)stack;
        stack += sizeOf(numMarks);
        return p;
    }
}

struct HeadTailList {
    ThompsonThread* head, tail;
    
    void push(ThompsonThread* t) {
        if (tail == null) {
            head = tail = t;
        } else {
            tail.next = t;
            tail = t;
        }
    }

    bool empty(){ return head == null; }

    ThompsonThread* pop() {
        ThompsonThread* t = head;
        if (head == tail) {
            head = tail = null;
            return t;
        }
        head = head.next;
        return t;
    }
}

bool thompson(uint[] code, bool search, ulong[] mergeTable, ref size_t genCounter, int marks, size_t mergePoints, ref const(char)[] slice, const(char)[][] captures, void* nativeCode=null) {
    assert(marks % 2 == 0);
    void[] memory = arena.allocate(ThompsonThread.sizeOf(marks) * (mergePoints + 2));
    void* stack = memory.ptr;
    auto input = slice;
    ThompsonThread* ret;
    if (nativeCode) {
        auto nativeFn = cast(ThompsonThread* function(bool, void*, ulong*, ref size_t, int,  ref const(char)[] slice)) nativeCode;
        ret = nativeFn(search, stack, mergeTable.ptr, genCounter, marks, slice);
    } else {
        ret = thompsonVM(code.ptr, search, stack, mergeTable.ptr, genCounter, marks, slice);
    }
    if (ret == null) {
        return false;
    }
    size_t[] m = ret.marks.ptr[0..marks];
    for (size_t i = 0; i < m.length; i += 2) {
        captures[i/2] = input[m[i]..m[i+1]];
    }
    return true;
}

ThompsonThread* thompsonVM(uint* code, bool search, void* stack, ulong* mergeTable, ref size_t genCounter, int marks,  ref const(char)[] slice) {
    static import std.utf;
    ThompsonThread* freelist = null;
    ThompsonThread* fork(size_t pc, size_t[] markArray = null) {
        ThompsonThread* t = null;
        if (freelist) {
            t = freelist;
            freelist = freelist.next;
        } else {
            t = ThompsonThread.allocate(stack, marks);
        }
        if (markArray) {
            assert(marks == markArray.length);
            t.marks.ptr[0..marks] = markArray[];
        } else {
            t.marks.ptr[0..marks] = 0;
        }
        t.next = null;
        t.pc = pc;
        return t;
    }

    void terminate(ThompsonThread* thread) {
        thread.next = freelist;
        freelist = thread;
    }

    HeadTailList clist, nlist; // current and future execution lists
    size_t genCnt = genCounter+1;
    size_t idx = 0;
    const(char)[] input = slice;
    
    ThompsonThread* exec(bool withInput)(dchar ch, size_t ofs) {
        ThompsonThread* cur = clist.pop();
        while (cur) {
            auto op = (code[cur.pc] >> 24) & 0x7f;
            auto val = code[cur.pc] & 0xFF_FFFF;
            if (code[cur.pc] & (1<<31)) {
                if (mergeTable[cur.pc] == genCnt) {
                    terminate(cur);
                    cur = clist.pop();
                    continue;
                } else {
                    mergeTable[cur.pc] = genCnt;
                }
            }
            switch(op) with(Opcode) {
                static if(withInput) {
                case ANY:
                    cur.pc++;
                    nlist.push(cur);
                    cur = clist.pop();
                    break;
                case CHAR:
                    if (ch == val) {
                        cur.pc++;
                        nlist.push(cur);
                    } else {
                        terminate(cur);
                    }
                    cur = clist.pop();
                    break;
                case NOTCHAR:
                    if (ch != val) {
                        cur.pc++;
                        nlist.push(cur);
                    } else {
                        terminate(cur);
                    }
                    cur = clist.pop();
                    break;
                case ONE_OF:
                    size_t i = cur.pc+1;
                    size_t end = cur.pc+val+1;
                    for (; i < end; i++) {
                        if (ch == code[i]) {
                            cur.pc += val + 1;
                            nlist.push(cur);
                            break;
                        }
                    }
                    if (i == end) {
                        terminate(cur);
                    }
                    cur = clist.pop();
                    break;
                case NOT_ONE_OF:
                    size_t i = cur.pc+1;
                    size_t end = cur.pc+val+1;
                    for (; i < end; i++) {
                        if (ch == code[i]) {
                            terminate(cur);
                            break;
                        }
                    }
                    if (i == end) {
                        cur.pc = end;
                        nlist.push(cur);
                    }
                    cur = clist.pop();
                    break;
                case INTERVALS:
                    size_t i = cur.pc+1;
                    size_t end = cur.pc+2*val+1;
                    for (; i < end; i+= 2) {
                        if (ch >= code[i] && ch < code[i+1]) {
                            cur.pc = end;
                            nlist.push(cur);
                            break;
                        }
                    }
                    if (i == end) {
                        terminate(cur);
                    }
                    cur = clist.pop();
                    break;
                case BIT:
                    size_t i = cur.pc+1;
                    if (ch <= 0x80 && (code[i + ch/32] & (1<<(ch % 32)))) {
                        cur.pc = cur.pc+5;
                        nlist.push(cur);
                    }
                    else {
                        terminate(cur);
                    }
                    cur = clist.pop();
                    break;
                case TRIE:
                    assert(false); // TODO: implement trie table
                }
                else {
                // without input all matching opcodes terminate a thread 
                case ANY:
                case CHAR:
                case NOTCHAR:
                case ONE_OF:
                case NOT_ONE_OF:
                case INTERVALS:
                case BIT:
                case TRIE:
                    terminate(cur);
                    cur = clist.pop();
                    break;
                }
                case MARK:
                    if (marks) {
                        cur.marks.ptr[val] = ofs;
                    }
                    cur.pc++;
                    break;
                case JMP:
                    cur.pc = (cur.pc + val) & 0xFF_FFFF;
                    break;
                case FORK:
                    auto t = fork((cur.pc + val) & 0xFF_FFFF, cur.marks.ptr[0..marks]);
                    clist.push(t);
                    cur.pc++;
                    break;
                case END:
                    return cur;
                default:
                    assert(false);
            }
        }
        return null;
    }

    clist.push(fork(0));
    ThompsonThread* t;
    while(!clist.empty) {
        size_t offset = idx;
        if (idx == input.length) {
            t = exec!false(dchar.init, idx);
        } else {
            dchar ch = decode(input, idx);
            t = exec!true(ch, offset);
            if (search) {
                nlist.push(fork(0));
            }
        }
        genCnt++;
        if (t) {
            slice = input[offset..$];
            break;
        }
        clist = nlist;
        nlist = HeadTailList(null, null);
    }
    genCounter = genCnt;
    return t;
}

struct Thompson {
    uint[] code;
    ulong[] mergeTable;
    size_t mergePoints;
    size_t genCounter;
    void* nativeCode;

    bool run(const(char)[] slice, const(char)[][] captures) {
        return thompson(code, false, mergeTable, genCounter, cast(int)captures.length*2, mergePoints, slice, captures, nativeCode);
    }

    bool search(const(char)[] slice, const(char)[][] captures) {
        return thompson(code, true, mergeTable, genCounter, cast(int)captures.length*2, mergePoints, slice, captures, nativeCode);
    }
}

Thompson toVM(BytecodeBuilder builder, bool native=false) {
    uint[] code = builder.build();
    size_t mergePoints = code.setMergePoints();
    ulong[] mergeTable = new ulong[code.length];
    void* nativeCode =  native ? compileNativeCode(code) : null;
    return Thompson(code, mergeTable, mergePoints, 0, nativeCode);
}

// basic test
unittest {
    BytecodeBuilder builder;
    with(builder) with(Opcode) {
        code(CHAR, 'a');
        code(CHAR, 'b');
        code(CHAR, 'c');
        code(END, 1);
    }
    uint[] code = builder.build();
    size_t mergePoints = code.setMergePoints();
    ulong[] mergeTable = new ulong[code.length];
    size_t genCounter = 0;
    const(char)[] slice = "abc";
    assert(thompson(code, false, mergeTable, genCounter, 0, mergePoints, slice, null));
    assert(slice == "");
    slice = "abb";
    assert(!thompson(code, false, mergeTable, genCounter, 0, mergePoints, slice, null));
    slice = "aaabcd";
    assert(thompson(code, true, mergeTable, genCounter, 0, mergePoints, slice, null));
    assert(slice == "d");
}

// simple loop
unittest {
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        size_t ofs = code(ANY, 0);
        size_t fork = code(FORK, 0);
        code(CHAR, 'b');
        code(END, 1);
        fixup(fork, ofs);
    }
    auto vm = builder.toVM();
    assert(vm.run("abc", null));
    assert(vm.run("ab", null));
    assert(!vm.run("acc", null));
}

//marks and jmps
unittest {
    import std.uni;
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        code(MARK, 0);
        code(NOTCHAR, 'a');
        code(MARK, 2);
        size_t to_end = code(JMP, 0);
        size_t start = code(CodepointSet('a', 'z'+1, 'A', 'Z'+1, '0', '9'+1));
        size_t loop_back = code(FORK, 0);
        fixup(to_end, loop_back);
        fixup(loop_back, start);
        code(MARK, 3);
        code(CodepointSet('a', 'a'+1, 'c', 'c'+1));
        code(MARK, 1);
        code(END, 1);
    }
    auto vm = builder.toVM();
    assert(!vm.run("abc", null));
    assert(vm.run("bbc", null));
    const(char)[][] cap = new const(char)[][](2);
    assert(vm.run("bbAZ09c", cap));
    assert(cap[0] == "bbAZ09c");
    assert(cap[1] == "bAZ09");
}

version(AArch64) {

void* compileNativeCode(uint[] code) {
    import rewind.re.dynasm.arm64;
    import std.conv;
    enum {
        SEARCH = x(0),
        STACK = x(1),
        MERGE_TABLE = x(2),
        REF_GENCOUNTER = x(3),
        MARKS = x(4),
        SLICE = x(5),
        CURRENT = x(6),
        CLIST_HEAD = x(7),
        CLIST_TAIL = x(8),
        NLIST_HEAD = x(9),
        NLIST_TAIL = x(10),
        FREELIST = x(11),
        CUR_CHAR = w(12),
        SCRATCH = x(13),
        GEN_COUNTER = x(14),
        INPUT = x(15),
        INPUT_END = x(16),
        SCRATCH_2 = x(17),
        ZERO = x(31)
    }
    Assembler assembler = Assembler(64 * 1024);
    Label[] codeLabels = new Label[code.length];
    for (size_t i = 0; i < codeLabels.length; i++) {
        codeLabels[i] = assembler.createLabel();
    }
    with(assembler) with (Condition) {
        auto nextStep = createLabel();
        auto nextStepCont = createLabel();
        mov(CLIST_HEAD, imm(0));
        mov(CLIST_TAIL, imm(0));
        mov(NLIST_HEAD, imm(0));
        mov(NLIST_TAIL, imm(0));
        mov(FREELIST, imm(0));
        ldr(INPUT, mem(SLICE, 8));
        ldr(INPUT_END, mem(SLICE));
        add(INPUT_END, INPUT_END, INPUT);
        ldr(GEN_COUNTER, mem(REF_GENCOUNTER));
        void fork(Register reg, ref Label lbl, bool marks) {
            auto end = createLabel();
            auto stack = createLabel();
            cmp(FREELIST, imm(0));
            b(EQ, stack);
            mov(reg, FREELIST);
            ldr(FREELIST, mem(FREELIST));
            b(end);
        bind(stack);
            mov(reg, STACK);
            mov(SCRATCH, imm(cast(uint)ThompsonThread.sizeOf(0)));
            add(STACK, STACK, SCRATCH); 
        bind(end);
            adr(SCRATCH, lbl);
            str(ZERO, mem(reg)); // next pointer
            str(SCRATCH, mem(reg, 8)); // set pc to the target label
            // TODO: compute size of marks and copy/zero out
        }
        void pushList(Register reg, Register head, Register tail) {
            auto append = createLabel();
            auto end = createLabel();
            cmp(head, ZERO);
            b(NE, append);
            mov(head, reg);
            b(end);
        bind(append);
            str(reg, mem(tail)); // tail.next = reg
        bind(end);
            mov(tail, reg);
        }
        void popList(Register reg, Register head, Register tail) {
            auto last = createLabel();
            auto loaded = createLabel();
            auto end = createLabel();
            mov(reg, head);
            cmp(head, tail);
            b(EQ, last);
            ldr(head, mem(head)); // head = head.next
            b(loaded);
        bind(last);
            mov(head, ZERO);
            mov(tail, ZERO);
        bind(loaded);
            cmp(reg, ZERO);
            b(EQ, end);
            str(ZERO, mem(reg)); // nulify next pointer for reg
        bind(end);
        }
        void readChar() {
            auto empty = createLabel();
            auto end = createLabel();
            cmp(INPUT, INPUT_END);
            b(EQ, empty);
            ldrb(CUR_CHAR, post(INPUT, 1));
            b(end);
        bind(empty);
            mov(CUR_CHAR, imm(-1));
        bind(end);
        }
        void terminate() {
            str(FREELIST, mem(CURRENT)); // current.next = freelist
            mov(FREELIST, CURRENT);
        }
        void dispatch() {
            popList(CURRENT, CLIST_HEAD, CLIST_TAIL);
            cmp(CURRENT, ZERO);
            b(EQ, nextStep);
            ldr(SCRATCH, mem(CURRENT, 8));
            br(SCRATCH);
        }
        readChar();
        add(GEN_COUNTER, GEN_COUNTER, imm(1));
        fork(CURRENT, codeLabels[0], false);
        ldr(SCRATCH, mem(CURRENT, 8));
        br(SCRATCH);
    bind(nextStep);
        mov(CLIST_HEAD, NLIST_HEAD);
        mov(CLIST_TAIL, NLIST_TAIL);
        mov(NLIST_HEAD, imm(0));
        mov(NLIST_TAIL, imm(0));
        popList(CURRENT, CLIST_HEAD, CLIST_TAIL);
        cmp(CURRENT, ZERO);
        b(NE, nextStepCont);
        mov(x(0), ZERO);
        ret();
    bind(nextStepCont);
        readChar();
        add(GEN_COUNTER, GEN_COUNTER, imm(1));
        ldr(SCRATCH, mem(CURRENT, 8));
        br(SCRATCH);
        for (size_t i = 0; i < code.length; i++) {
        bind(codeLabels[i]);
            auto op = (code[i] >> 24) & 0x7f;
            auto val = code[i] & 0xFF_FFFF;
            if (code[i] & (1<<31)) { // MERGE_POINT
                
            }
            switch (op) with (Opcode)  {
            case CHAR:
                auto noMatch = createLabel();
                auto skipOver = createLabel();
                mov(SCRATCH, imm(val)); // TODO: extend mov to handle large immediates
                cmp(CUR_CHAR, SCRATCH);
                b(NE, noMatch);
                adr(SCRATCH, codeLabels[i+1]);
                str(SCRATCH, mem(CURRENT, 8));
                pushList(CURRENT, NLIST_HEAD, NLIST_TAIL);
                b(skipOver);
            bind(noMatch);
                terminate();
            bind(skipOver);
                dispatch();
                break;
            case FORK:
                fork(SCRATCH_2, codeLabels[(i+val) & 0XFF_FFFF], true);
                pushList(SCRATCH_2, CLIST_HEAD, CLIST_TAIL);
                break;
            case END:
                mov(x(0), CURRENT);
                ret();
                break;
            default:
                assert(false, "Not supprted opcode "~to!string(op));
            }
        }
    }
    assembler.finalize();
    return assembler.data.ptr;
}

} else {
    void* compileNativeCode(uint[] code) {
        return null;
    }
}

unittest {
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        code(CHAR, 'a');
        code(CHAR, 'b');
        code(CHAR, 'c');
        code(END, 1);
    }
    auto native = toVM(builder, true);
    assert(native.run("abc", null));
    assert(!native.run("bc", null));
    assert(!native.run("abd", null));
}

unittest {
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        size_t start = code(CHAR, 'a');
        code(CHAR, 'b');
        size_t forked = code(FORK, 0);
        code(CHAR, 'c');
        code(END, 1);
        fixup(forked, start);
    }
    auto native = toVM(builder, true);
    assert(native.run("abc", null));
    assert(native.run(
        "ababababababababababababababababababababababababababababababababababababababababababababababab" ~
        "ababababababababababababababababababababababababababababababababababababababababababababababab" ~
        "ababababababababababababababababababababababababababababababababababababababababababababababab" ~
        "ababababababababababababababababababababababababababababababababababababababababababababababab" ~ 
        "ababababababababababababababababababababababababababababababababababababababababababababababab" ~
        "ababababababababababababababababababababababababababababababababababababababababababababababc", null));
    assert(!native.run("ab", null));
}
