## REwind Regex

REwind Regex is designed to be a simpler, more innovative alternative to std.regex library.
Unleashed from contraints of std.library REwind Regex aims to provide greater speeds and
streaming capabilities, sacrificing complex features for more powerful use cases.

That being said most easy wins battle tested in REwind Regex would eventually be backported.

In general - pick std.regex if:
- need stability over performance
- compile-time regex (if you have patience and RAM to afford it)
- need backreferences
- love helpers such as splitter, replaceFirst/replaceAll etc.

Try REwind Regex if your use case is:
- grep-like tool or search engine
- streaming with IOpipe library (related to previous point)
- performance is more important then having e.g. backreference
- hate useless cruft that you can easily implement yourself
- 100% @nogc (in the future) once exceptions are tackled by the lanauge

## Technical details

TBD.
