/*
Utilities.
*/

{
  metricLabelName(name)::
    std.strReplace(std.strReplace(std.strReplace(name, '-', '_'), '.', '_'), '/', '_'),
}
