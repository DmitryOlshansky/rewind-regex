module rewind.re.impl.stack;

import std.array;

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

