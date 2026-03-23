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

bool thompson(uint[] code, ulong[] mergeTable, ref size_t genCounter, int marks, size_t mergePoints, ref const(char)[] slice, const(char)[][] captures) {
    assert(marks % 2 == 0);
    void[] memory = arena.allocate(ThompsonThread.sizeOf(marks) * (mergePoints + 2));
    void* stack = memory.ptr;
    auto input = slice;
    auto ret = thompsonVM(code.ptr, stack, mergeTable.ptr, genCounter, marks, slice);
    if (ret == null) {
        return false;
    }
    size_t[] m = ret.marks.ptr[0..marks];
    for (size_t i = 0; i < m.length; i += 2) {
        captures[i/2] = input[m[i]..m[i+1]];
    }
    return true;
}

ThompsonThread* thompsonVM(uint* code, void* stack, ulong* mergeTable, ref size_t genCounter, int marks,  ref const(char)[] slice) {
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
        if (idx == input.length) {
            t = exec!false(dchar.init, idx);
        } else {
            size_t offset = idx;
            dchar ch = decode(input, idx);
            t = exec!true(ch, offset);
        }
        genCnt++;
        if (t) {
            break;
        }
        clist = nlist;
        nlist = HeadTailList(null, null);
    }
    if (t) {
        slice = input[idx..$];
    }
    genCounter = genCnt;
    return t;
}

struct Thompson {
    uint[] code;
    ulong[] mergeTable;
    size_t mergePoints;
    size_t genCounter;

    bool run(const(char)[] slice, const(char)[][] captures) {
        return thompson(code, mergeTable, genCounter, cast(int)captures.length*2, mergePoints, slice, captures);
    }
}

Thompson toVM(BytecodeBuilder builder) {
    uint[] code = builder.build();
    size_t mergePoints = code.setMergePoints();
    ulong[] mergeTable = new ulong[code.length];
    return Thompson(code, mergeTable, mergePoints, 0);
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
    assert(thompson(code, mergeTable, genCounter, 0, mergePoints, slice, null));
    assert(slice == "");
    slice = "abb";
    assert(!thompson(code, mergeTable, genCounter, 0, mergePoints, slice, null));
}

// simple loop
unittest {
    BytecodeBuilder builder;
    with (builder) with(Opcode) {
        size_t ofs = code(ANY, 0);
        size_t fork = code(FORK, 0);
        code(CHAR, 'b');
        code(END, 1);
        fixup(fork, cast(int)(ofs - fork));
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
        fixup(to_end, cast(int)(loop_back - to_end));
        fixup(loop_back, cast(int)(start - loop_back));
        code(MARK, 3);
        code(CodepointSet('a', 'a'+1, 'c', 'c'+1));
        code(MARK, 1);
        code(END, 1);
    }
    auto vm = builder.toVM();
    assert(vm.run("bbc", null));
    const(char)[][] cap = new const(char)[][](2);
    assert(vm.run("bbAZ09c", cap));
    assert(cap[0] == "bbAZ09c");
    assert(cap[1] == "bAZ09");
}