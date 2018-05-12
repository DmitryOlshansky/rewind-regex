import std.stdio;

// works for x86_64 ;)
R enterThreadedCode(R, T)(R function(T) target, T arg) {
    asm @nogc nothrow {
        naked;
        mov RAX, RSP;
        mov RSP, [RDI];
        push RAX;
        mov RAX, [RDI];
        mov [RAX], RBP;
        call RSI;
        pop RSP;
        ret;
    }
}

R tailCallOf1(R, T)(R function(T) target, T arg) {
    asm @nogc nothrow {
        naked;
        mov RSP, [RDI];
        jmp RSI;
    }
}

int push(State* state) {
    state.stack ~= state.pc.arg;
    return tailCallOf1((++state.pc).code, state);
}

int add(State* state) {
    auto stk = state.stack;
    auto rhs = stk[$-1];
    auto lhs = stk[$-2];
    stk[$-2] = lhs + rhs;
    state.stack = stk[0..$-1];
    return tailCallOf1((++state.pc).code, state);
}

int jnz(State* state) {
    if (state.stack[$-1] == 0) {
        return tailCallOf1((++state.pc).code, state);
    }
    else {
        state.pc += state.pc.arg;
        return tailCallOf1(state.pc.code, state);
    }
}

int start(State* state) {
    return tailCallOf1((++state.pc).code, state);
}

int ret(State* state) {
    writeln(state.stack[0]);
    return state.stack[0];
}

struct Inst {
    int function(State*) code;
    int arg;
}

struct State {
    void* hardwareStack;
    int[] stack;
    Inst* pc;

    this(Inst[] prog) {
        stack = [];
        hardwareStack = new void[1024*1024].ptr;
        pc = prog.ptr;
    }
}

void terminatesWith(Inst[] program, int result)
{
    State state = State(program);
    assert(state.pc.code(&state) == result);
}

void main() {
    /*[
        Inst(&start),
        Inst(&push, 1),
        Inst(&push, 2),
        Inst(&add),
        Inst(&ret)
    ].terminatesWith(3);
    */
    [
        Inst(&start),
        Inst(&push, 1_000_000),
        Inst(&push, -1),
        Inst(&add),
        Inst(&jnz, -2),
        Inst(&ret)
    ].terminatesWith(0);
}
