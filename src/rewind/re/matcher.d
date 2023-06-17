module rewind.re.matcher;

import rewind.re.captures;

interface Matcher {
    bool exact();
    bool matches(const(char)[] slice);
    bool hasMatch(const(char)[] slice);
    const(char)[] locate(const(char)[] slice);
    Captures fullyMatch(ref const(char)[] slice);
    Matcher next(); // next matcher in the chain
}

