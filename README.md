# RegExTester
An AHK v2 RegEx Tester that uses placeholders.  As with all of my scripts, the exe is not a compiled version of the ahk.  It is a renamed copy of AutoHotkey.exe.  Both (RegExTester.ahk and RegExTester.exe) must be kept in the same folder. 

![Screenshot of main window](https://github.com/kunkel321/RegExTester/blob/main/ScreenSnip_20260728_145403.png)

# From code comments
#################################

App: REGEX TESTER for AHK v2

By: kunkel321 (with Claude)

Date: (updated in code comments)

AHK Forum: https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140951

GitHub: https://github.com/kunkel321/RegExTester

#################################
A live RegEx tester that runs on AutoHotkey's own PCRE engine, so what you
see here is exactly what RegExMatch()/RegExReplace() will do in a script.

The distinguishing feature is "placeholders": named sub-patterns defined once
and then referenced from the main pattern (or from each other) as %name%.
That mirrors how patterns get built by string concatenation in real scripts,
e.g. OutlookMagnet2.ahk:

    reMonth   := "\b((Jan|Feb)(r?u(ary)?)?|Mar(ch)?|...)\b"
    re1st31st := "\b(?<!:)([0-2]?[0-9]|30|31)(st|nd|rd|th)?(?!:)\b"
    RegExMatch(txt, "i)(" reMonth "\s" re1st31st ")", &myDate)

...which in this tester is just:   (%reMonth%\s%re1st31st%)

The AHK Code tab regenerates the concatenated-variable form above, ready to
paste into a script.  File > Import from AHK code goes the other direction.

Requires: Tools\RichEdit.ahk  (github.com/AHK-just-me/AHK2_RichEdit) — the
haystack pane is a rich edit control so every match can be shaded in place.

Notes:
  - The Pattern box holds the RAW pattern (what PCRE sees), NOT an AHK string
    literal.  Type \t or a real tab, not `t.  Edit > "Copy pattern as AHK
    literal" does the escaping when you're ready to paste into code.
  - Options go in the checkboxes, not in the pattern.  The tester always
    emits an explicit "opts)" prefix, so a pattern that legitimately starts
    with ")" or with option letters still behaves correctly.
  - Shading the matches pushes entries onto the rich edit's undo stack, so
    Ctrl+Z in the haystack pane can take a few presses to reach your typing.
  - A pathological pattern (catastrophic backtracking) will hang the GUI just
    as it would hang a real script.  Untick "Live" before trying one.
