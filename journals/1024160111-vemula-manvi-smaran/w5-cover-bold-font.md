# Week 5 : SRS Cover Title Would Not Turn Bold

# LaTeX Font Encoding

## Error:

On the SRS cover page the very large title came out in a
light weight, and stopped growing past a certain size, so
it did not match the template screenshot.

## Relevant Context

The document loads `T1` font encoding, and the cover
used:

``` latex
\bfseries
{\Huge SOFTWARE REQUIREMENTS\\SPECIFICATION}
```

## Key Observation

Two limits met here. In `T1` encoding the bold face at
that size was not installed, so LaTeX swapped in a regular
one. `OT1` does have bold Computer Modern, but its sizes
stop at 24.88pt (`\Huge`), so asking for more changes
nothing.

## Solution

Switch the cover alone to `OT1` for the bold shapes, keep
`\Huge`, and scale the whole block up instead of asking
for a bigger font size:

``` latex
\begin{titlepage}
  \fontencoding{OT1}\selectfont
  \scalebox{1.17}{\begin{minipage}{5.85in}
    \begin{flushright}\bfseries
      {\Huge SOFTWARE REQUIREMENTS\\SPECIFICATION}
      ...
```

**Because**

LaTeX picks a font by encoding, family, series and size.
If that exact combination is missing it falls back
quietly and only prints a warning in the log.
