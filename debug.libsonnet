/*

Outputs to stderr the given string txt and object obj converted to string and returns result as the result.
Default result is {}.
Output is formatted as coded below.

Example use: 
    local debug = (import 'debug.jsonnet')(std.thisFile, (import 'globals.json').debug),
    debug.new('##99', { a:1, b:2 }, [])
*/

function(filename, debug=false)
  {
    on: debug,

    new(txt, obj, result={})::
      if !$.on then result else
        std.trace('[' + filename + ']' + '[' + txt + ']:' + std.toString(obj), result),
  }
