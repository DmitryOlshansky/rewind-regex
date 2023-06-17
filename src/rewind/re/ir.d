module rewind.re.ir;

import rewind.re.matcher;


/++
    $(D Regex) object holds regular expression pattern in compiled form.

    Instances of this object are constructed via calls to $(D regex).
    This is an intended form for caching and storage of frequently
    used regular expressions.

    Example:

    Test if this object doesn't contain any compiled pattern.
    ---
    Regex!char r;
    assert(r.empty);
    r = regex(""); // Note: "" is a valid regex pattern.
    assert(!r.empty);
    ---

    Getting a range of all the named captures in the regex.
    ----
    import std.range;
    import std.algorithm;

    auto re = regex(`(?P<name>\w+) = (?P<var>\d+)`);
    auto nc = re.namedCaptures;
    static assert(isRandomAccessRange!(typeof(nc)));
    assert(!nc.empty);
    assert(nc.length == 2);
    assert(nc.equal(["name", "var"]));
    assert(nc[0] == "name");
    assert(nc[1..$].equal(["var"]));
    ----
+/
struct Re {
    string pattern;
    string flags;
    ubyte[] code;

    Matcher engine();
}