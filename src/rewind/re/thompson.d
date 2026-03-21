module rewind.re.thompson;

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
    size_t[0] marks; // 2x captures, including the whole match
    
    static size_t sizeOf(int numMarks) {
        return (ThompsonThread*).sizeof + size_t.sizeof * numMarks;
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

bool thompson(uint[] code, ulong[] mergeTable, ref size_t genCounter, int marks, int mergePoints, ref const(char)[] slice, ref const(char)[][] captures) {
    assert(marks % 2 == 0);
    void[] memory = arena.allocate(ThompsonThread.sizeOf(marks) * (mergePoints + 2));
    void* stack = memory.ptr;
    auto ret = thompsonVM(code.ptr, stack, mergeTable.ptr, genCounter, marks, slice);
    if (ret == null) {
        return false;
    }
    size_t[] m = ret.marks.ptr[0..marks];
    for (size_t i = 0; i < m.length; i += 2) {
        captures[i/2] = slice[m[i]..m[i+1]];
    }
    return true;
}

ThompsonThread* thompsonVM(uint* code, void* stack, ulong* mergeTable, ref size_t genCounter, int marks,  ref const(char)[] slice) {
    static import std.utf;
    ThompsonThread* freelist = null;
    return null;
}