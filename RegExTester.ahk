#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\Tools\RichEdit.ahk ; https://github.com/AHK-just-me/AHK2_RichEdit
SetWorkingDir(A_ScriptDir)

; Distinguishes this script from the other AHK tools in the tray.  Bare try:
; if a future Windows drops imageres.dll we just keep the default icon.
; The hover text is set by UpdateTitle(), which also names the loaded session
; file -- deliberately not duplicated here, since APP_TITLE isn't declared
; until the TUNABLES block below.
try TraySetIcon("imageres.dll", 20)          ; a window with a green checkmark

;###############################################################
; App:          REGEX TESTER for AHK v2
; By:           kunkel321 (with Claude)
; Date:         8-3-2026
; AHK Forum:    https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140951
; GitHub:       https://github.com/kunkel321/RegExTester
;###############################################################
; A live RegEx tester that runs on AutoHotkey's own PCRE engine, so what you
; see here is exactly what RegExMatch()/RegExReplace() will do in a script.
;
; The distinguishing feature is "placeholders": named sub-patterns defined once
; and then referenced from the main pattern (or from each other) as %name%.
; That mirrors how patterns get built by string concatenation in real scripts,
; e.g. OutlookMagnet2.ahk:
;
;     reMonth   := "\b((Jan|Feb)(r?u(ary)?)?|Mar(ch)?|...)\b"
;     re1st31st := "\b(?<!:)([0-2]?[0-9]|30|31)(st|nd|rd|th)?(?!:)\b"
;     RegExMatch(txt, "i)(" reMonth "\s" re1st31st ")", &myDate)
;
; ...which in this tester is just:   (%reMonth%\s%re1st31st%)
;
; The AHK Code tab regenerates the concatenated-variable form above, ready to
; paste into a script.  File > Import from AHK code goes the other direction.
;
; Requires: Tools\RichEdit.ahk  (github.com/AHK-just-me/AHK2_RichEdit) — the
; haystack pane is a rich edit control so every match can be shaded in place.
;
; Notes:
;   - The Pattern box holds the RAW pattern (what PCRE sees), NOT an AHK string
;     literal.  Type \t or a real tab, not `t.  Edit > "Copy pattern as AHK
;     literal" does the escaping when you're ready to paste into code.
;   - Options go in the checkboxes, not in the pattern.  The tester always
;     emits an explicit "opts)" prefix, so a pattern that legitimately starts
;     with ")" or with option letters still behaves correctly.
;   - Shading the matches pushes entries onto the rich edit's undo stack, so
;     Ctrl+Z in the haystack pane can take a few presses to reach your typing.
;   - A pathological pattern (catastrophic backtracking) will hang the GUI just
;     as it would hang a real script.  Untick "Live" before trying one.
;   - "Show tips on hover" (top right) puts an explanatory tooltip on every
;     control and on each ListView column header.  Some of that text overlaps
;     the Cheat Sheet tab on purpose — the tip is for the control you are
;     looking at, the tab is for browsing.
;   - The window size is remembered in the session file along with everything
;     else, so the tester reopens the size you left it.
;#################################

; ============================== TUNABLES ==================================
global MATCH_BG_A   := 0xFFF3A0        ; shading for odd-numbered matches
global MATCH_BG_B   := 0xC9EEC9        ; shading for even-numbered matches (so
                                       ;   two matches that touch stay distinct)
global SUBJ_FONT    := "Consolas"
global SUBJ_SIZE    := 11
global MAX_SHADED   := 400             ; stop shading past this many matches
global MAX_MATCHES  := 5000            ; hard cap on the find-all loop
global RUN_DELAY    := 300             ; ms of idle before a live re-run
global COLOR_DELAY  := 150             ; ms of idle before recoloring the pattern
global MAX_SNIPPETS := 25              ; banked patterns
global APP_TITLE    := "RegEx Tester for AHK v2"
global TIP_WIDTH    := 560             ; px before a hover tip wraps (see
                                       ;   TipMaxWidth; both tooltip libraries
                                       ;   default to "never wrap")

; --- pattern box syntax colors -------------------------------------------
; Set PAT_FULL_SYNTAX false to color only the %placeholders% and leave the
; rest of the pattern plain black.  That also switches off the matching-paren
; highlight, since the pairing comes out of the same parse.
;
; The palette is grouped by MEANING rather than by character, so that things
; which behave alike look alike:
;     green   asserts a position and consumes nothing  (^ $ \b \A, and the
;             ?= ?! ?<= ?<! of a lookaround)
;     teal    matches a character                      (\d \w \s \p{L})
;     blue    repetition                               (* + ? {2,5})
;     orange  character class, plus a pale tint across the whole [...]
;     purple / blue / amber, cycling: nesting depth
;     gray    punctuation that only holds a construct together
;     a pale green wash behind whatever the pattern matches literally
;
; White on red is reserved for things PCRE will REFUSE TO COMPILE, so red
; always means broken and never merely unusual.  Notably NOT red: a lone "]",
; a lone "}", and a "{" that is not a quantifier.  PCRE demotes all three to
; ordinary literal characters, so they get PC_LITERAL -- "you typed a
; metacharacter, but here it is only a character" -- which is the honest
; answer.  Calling them errors would condemn patterns that work fine.
global PAT_FULL_SYNTAX := true
global PC_PH_FG    := 0x000090, PC_PH_BG    := 0xDCE9FF   ; %known% placeholder
global PC_BADPH_FG := 0x900000, PC_BADPH_BG := 0xFFD6D6   ; %unknown% placeholder
global PC_BAD_FG   := 0xFFFFFF, PC_BAD_BG   := 0xD04040   ; will not compile
global PC_ESC      := 0x008080         ; \d \w \s \h \p{L} -- matches a character
global PC_ESCNUM   := 0x0090B0         ; \x41 \x{263A} \cA \t -- one code point
global PC_ESCLIT   := 0x9A6B3A         ; \. \( \\ -- metacharacter made ordinary
global PC_BACKREF  := 0x2040E0         ; \1 \k<name> (?P=name) (?&name)
global PC_CLASS    := 0xB05000         ; the [ ^ ] of a character class
global PC_CLASS_BG := 0xFFF2E4         ; tint across the whole class, so it reads
                                       ;   as one unit while its contents keep
                                       ;   their own foreground colors
global PC_RANGE    := 0xD07000         ; the - in [a-z]
global PC_POSIX    := 0x8040A0         ; [:alpha:] and friends
global PC_QUANT    := 0x0060C0         ; * + ? {2,5}
global PC_LAZY     := 0x60A8E8         ; the ? or + that makes one lazy/possessive
global PC_ALT      := 0xC000C0         ; |
global PC_ANCHOR   := 0x008000         ; ^ $ \b \A \z, and (?= (?! (?<= (?<!
global PC_DOT      := 0x909000         ; .
global PC_SPECIAL  := 0x707070         ; (?i) (?(1) (*SKIP) -- inline directives
global PC_NONCAP   := 0x9A9AB0         ; the ?: ?> ?< > plumbing of a group
global PC_GNAME    := 0x2050B0         ; the name itself in (?<name>...)
global PC_COMMENT  := 0x808080         ; (?#...) and, with x, #comments
global PC_LITERAL  := 0xA0A0A0         ; ] } and a { that is not a quantifier
global PC_LIT_BG   := 0xEBF7E7         ; text the pattern matches literally.  A
                                       ;   background rather than a foreground:
                                       ;   black stays the most readable color
                                       ;   there is, and the job here is to
                                       ;   group the words, not to recolor them
global PC_XWS_BG   := 0xF2F2F2         ; with x, whitespace the engine discards.
                                       ;   Whitespace has no ink to dim, so the
                                       ;   only way to show it is behind it --
                                       ;   set to "" to leave it untinted.
global PC_PARMATCH_BG := 0xB6E3FF      ; the ( ) pair on either side of the caret
global PC_PAREN    := [0x6A00C0, 0x0077A8, 0xB07000]   ; group depth, cycling

; Option letters, in the canonical order they get emitted.
global OPT_LETTERS := ["i", "m", "s", "x", "A", "D", "J", "U", "X", "S"]

;###########################################################################
; EMBEDDED TOOLTIP LIBRARIES
;###########################################################################
; These are two standalone libraries, pasted in rather than #Included so that
; RegExTester.ahk stays a single portable file.  Both are short; if either is
; wanted elsewhere, lift the block out again -- neither depends on anything
; else in this file.
;
; WHY IT IS UP HERE AND NOT AT THE BOTTOM:  a class definition is not purely
; declarative.  AHK emits the class's static-initializer block as real code at
; the spot where the class appears, so a class placed after the auto-execute
; section's "return" is unreachable -- AHK says so out loud:
;     Warning: This line will never execute, due to Return preceding it.
; Plain functions hoist and can live anywhere; classes cannot.  That is why
; class RT has always been above the return, and why this block has to be too.
; Move it back down and LVHeaderToolTips stops being initialized.
;
;   CtrlToolTip()      -- by MESUT AKCAN.  v1.1, 2026-07-08.
;                         github.com/mesutakcan/CtrlToolTip
;                         Reproduced with only its indentation changed, from
;                         tabs to this file's four spaces.  All credit for it
;                         belongs to Mesut; please take any bug in it up with
;                         this copy rather than with him.
;
;   LVHeaderToolTips   -- companion class (kunkel321 with Claude).  Does for
;   CtrlToolTipsEnable    ListView COLUMN HEADERS what CtrlToolTip does for
;   TipMaxWidth           whole controls, and adds the on/off plumbing.
;###########################################################################

/*
===============================================================================
CtrlToolTip -- Adds a standard Windows tooltip to a Gui control.
version : 1.1
author  : Mesut Akcan
date    : 2026-07-08
source  : https://github.com/mesutakcan/CtrlToolTip

Usage:  CtrlToolTip(myControl, "Tooltip text")
===============================================================================
*/

; ctrl: Target Gui.Control that should display the tooltip.
; text: Tooltip text to show when the mouse hovers the control.
CtrlToolTip(ctrl, text) {
    static tipHandles := Map()         ; Map to store tooltip control handles for each parent Gui HWND
    static textBuffers := Map()        ; Map to store text buffers for each control to prevent garbage collection
    static registeredControls := Map() ; Map to track which controls have been registered with the tooltip control
    static GWL_STYLE := -16            ; Offset for GetWindowLongPtr to retrieve the window style
    static SS_NOTIFY := 0x0100         ; Style flag for static controls to receive notification messages (required for tooltips)
    guiHwnd := 0                       ; Variable to hold the parent Gui's HWND
    hTip := 0                          ; Variable to hold the tooltip control's HWND

    ; Ensure the provided control is a Gui.Control object
    if !(ctrl is Gui.Control)
        throw TypeError("CtrlToolTip: Gui.Control expected.", -1)

    guiHwnd := ctrl.Gui.Hwnd ; Get the parent Gui's HWND to associate the tooltip with it.

    ; Ensure static text controls have the SS_NOTIFY style for tooltip support.
    if (ctrl.Type = "Text") {  ; If the control is a Text control, check and set the SS_NOTIFY style
        ; Use GetWindowLongPtr on 64-bit, GetWindowLong on 32-bit
        gwlFunc := (A_PtrSize = 8) ? "GetWindowLongPtr" : "GetWindowLong"
        swlFunc := (A_PtrSize = 8) ? "SetWindowLongPtr" : "SetWindowLong"
        ; Get the current window style of the control
        style := DllCall(gwlFunc, "Ptr", ctrl.Hwnd, "Int", GWL_STYLE, "Ptr")
        ; If the control does not already have the SS_NOTIFY style, add it
        if !(style & SS_NOTIFY)
            ; Add the SS_NOTIFY style to the control's window style
            DllCall(swlFunc, "Ptr", ctrl.Hwnd, "Int", GWL_STYLE, "Ptr", style | SS_NOTIFY, "Ptr")
    }

    ; Check if a tooltip control already exists for this Gui, and create one if not.
    if tipHandles.Has(guiHwnd)
        hTip := tipHandles[guiHwnd] ; Retrieve the existing tooltip control handle for this Gui

    ; Get or create the tooltip window handle for this Gui.
    if !hTip || !DllCall("IsWindow", "Ptr", hTip, "Int") { ; If the tooltip control does not exist or is not a valid window, create it
        ; Create the tooltip control for this Gui with standard tooltip window styles.
        hTip := DllCall(
            "CreateWindowEx"            ; lpExStyle
            , "UInt", 0                 ; dwExStyle
            , "Str", "tooltips_class32" ; lpClassName
            , "Ptr", 0                  ; lpWindowName
            , "UInt", 0x80000003        ; Tooltip window styles
            , "Int", 0x80000000         ; CW_USEDEFAULT
            , "Int", 0x80000000         ; CW_USEDEFAULT
            , "Int", 0x80000000         ; CW_USEDEFAULT
            , "Int", 0x80000000         ; CW_USEDEFAULT
            , "Ptr", guiHwnd            ; hwndParent
            , "Ptr", 0                  ; hMenu
            , "Ptr", 0                  ; hInstance
            , "Ptr", 0                  ; lpParam
            , "Ptr"                     ; Return value is the tooltip control's HWND
        )

        ; CreateWindowEx failed, throw an error.
        if !hTip
            throw Error("CtrlToolTip: Failed to create tooltip control.", -1)

        ; Set the maximum tooltip width so the text can wrap to multiple lines.
        SendMessage(0x0418, 0, A_ScreenWidth, hTip) ; TTM_SETMAXTIPWIDTH
        ; Store the tooltip handle for this Gui's HWND.
        tipHandles[guiHwnd] := hTip
    }

    ; Prepare the buffer for the tooltip text.
    ti := Buffer(24 + (A_PtrSize * 6), 0)                ; Size of TOOLINFO for the current pointer size
    textBuf := Buffer(StrPut(text, "UTF-16") * 2, 0)     ; Buffer for the tooltip text in UTF-16 encoding
    StrPut(text, textBuf, "UTF-16")                      ; Write the tooltip text into the buffer

    NumPut("UInt", ti.Size, ti)                          ; cbSize
    NumPut("UInt", 0x11, ti, 4)                          ; TTF_IDISHWND | TTF_SUBCLASS
    NumPut("Ptr", guiHwnd, ti, 8)                        ; hwnd
    NumPut("Ptr", ctrl.Hwnd, ti, 8 + A_PtrSize)          ; uId (use the control's HWND as the unique identifier)
    NumPut("Ptr", textBuf.Ptr, ti, 24 + (A_PtrSize * 3)) ; lpszText

    ; Update the existing tooltip text for this control.
    ; If the control is not yet registered, add it to the tooltip control.
    if registeredControls.Has(ctrl.Hwnd)
        SendMessage(0x0439, 0, ti.Ptr, hTip) ; TTM_UPDATETIPTEXTW
    else {
        SendMessage(0x0432, 0, ti.Ptr, hTip) ; TTM_ADDTOOLW
        registeredControls[ctrl.Hwnd] := true ; Mark this control as registered
    }

    ; Store the text buffer to prevent it from being garbage collected,
    ; which would cause the tooltip to display empty text.
    textBuffers[ctrl.Hwnd] := textBuf
}


/*
===============================================================================
LVHeaderToolTips.ahk    v1.1
Per-column tooltips for a ListView's column headers.

Companion to Mesut Akcan's CtrlToolTip above -- same native tooltip control,
but registers RECTANGLE-based tools on the ListView's internal SysHeader32
window instead of one HWND-based tool covering the whole control.

Why a separate class is needed:
  - CtrlToolTip uses TTF_IDISHWND with uId := ctrl.Hwnd, so one tool covers
    an entire control. You cannot vary the text per column that way.
  - The header is a separate SysHeader32 window (a child of the ListView),
    not a Gui.Control, so CtrlToolTip's type check rejects it.

Usage:
    hdrTips := LVHeaderToolTips(myLV, ["col 1 tip", "col 2 tip", ""])
    hdrTips.Set(3, "Third column explanation")   ; 1-based column numbers
    hdrTips.Enabled := false                     ; full teardown, zero cost
    hdrTips.Enabled := true                      ; rebuild from cached texts

Notes:
  - Construct it AFTER Gui.Show() and after the columns have been added, so
    the header rects are already laid out.
  - Keep the returned object in a variable that outlives the Gui. Call
    Dispose() on Gui close to break the object <-> timer reference cycle.
===============================================================================
*/

class LVHeaderToolTips {

    ; ------------------------------------------------------------------
    ; lv      : the Gui.ListView control (Report view, header present)
    ; tips    : optional array of strings, index = 1-based column number
    ; enabled : start switched on (default) or off
    ; ------------------------------------------------------------------
    __New(lv, tips := "", enabled := true) {
        static LVM_GETHEADER := 0x101F

        if !(lv is Gui.Control) || (lv.Type != "ListView")
            throw TypeError("LVHeaderToolTips: a ListView control is required.", -1)

        this.lv   := lv
        this.hGui := lv.Gui.Hwnd
        this.hHdr := DllCall("user32\SendMessageW", "Ptr", lv.Hwnd, "UInt", LVM_GETHEADER
                           , "Ptr", 0, "Ptr", 0, "Ptr")

        if !this.hHdr
            throw Error("LVHeaderToolTips: that ListView has no header (NoHeader / non-Report view?).", -1)

        this.texts   := Map()   ; col -> tooltip text  (master record -- survives disable)
        this.buffers := Map()   ; col -> Buffer, held so the text isn't collected
        this.added   := Map()   ; col -> true once TTM_ADDTOOL has succeeded
        this.sig     := ""      ; cached header layout signature
        this.hTip    := 0
        this._tick   := 0

        if (tips is Array) {
            Loop tips.Length {
                if (tips.Has(A_Index) && tips[A_Index] != "")
                    this.texts[A_Index] := tips[A_Index]
            }
        }

        if enabled
            this.Enabled := true
    }

    ; ------------------------------------------------------------------
    ; The on/off switch.
    ;
    ; false -> deletes every registered tool (which is what removes the
    ;          TTF_SUBCLASS hook from the header's message path), destroys
    ;          the tooltip window, releases the text buffers and stops the
    ;          watchdog timer. Nothing of ours is left running or hooked.
    ; true  -> recreates the tooltip window and re-registers from this.texts,
    ;          reading fresh header rects, so column changes made while
    ;          switched off are picked up correctly.
    ; ------------------------------------------------------------------
    Enabled {
        get => this.hTip ? true : false

        set {
            want := value ? true : false
            if (want = (this.hTip ? true : false))
                return                              ; already in that state

            if want {
                this.hTip := this._CreateTipWindow()
                this.added.Clear()
                this.Refresh()
                this.sig := this._Signature()
                if !this._tick
                    this._tick := ObjBindMethod(this, "_Poll")
                SetTimer(this._tick, 250)
            } else {
                if this._tick
                    SetTimer(this._tick, 0)

                ; Delete the tools explicitly before destroying the window.
                ; TTM_DELTOOL is the documented path that un-subclasses the
                ; tool window, so don't rely on WM_DESTROY to do it for us.
                cols := []
                for col in this.added
                    cols.Push(col)
                for col in cols
                    this._DelTool(col)

                if DllCall("IsWindow", "Ptr", this.hTip, "Int")
                    DllCall("DestroyWindow", "Ptr", this.hTip)
                this.hTip := 0
                this.added.Clear()
                this.buffers.Clear()
                this.sig := ""
            }
        }
    }

    ; ------------------------------------------------------------------
    ; Add / change / remove the tooltip for one column (1-based).
    ; Pass an empty string to remove. Works whether or not tips are enabled;
    ; while disabled it just updates the cached text.
    ; ------------------------------------------------------------------
    Set(col, text) {
        if (text = "") {
            if this.hTip
                this._DelTool(col)
            if this.texts.Has(col)
                this.texts.Delete(col)
            if this.buffers.Has(col)
                this.buffers.Delete(col)
        } else {
            this.texts[col] := text
            if this.hTip {
                this.Refresh()
                this.sig := this._Signature()
            }
        }
        return this
    }

    ; ------------------------------------------------------------------
    ; Re-read every column's header rect and (re)register the tools.
    ; Call manually after changing column widths in code if you don't want
    ; to wait for the 250 ms watchdog.
    ; ------------------------------------------------------------------
    Refresh() {
        static HDM_GETITEMRECT    := 0x1207
        static TTM_ADDTOOLW       := 0x0432
        static TTM_NEWTOOLRECTW   := 0x0434
        static TTM_UPDATETIPTEXTW := 0x0439

        if !this.hTip || !DllCall("IsWindow", "Ptr", this.hHdr, "Int")
            return false

        rc := Buffer(16, 0)
        for col, text in this.texts {
            ; Header item rect, in the header's own client coordinates --
            ; exactly the coordinate space TOOLINFO.rect expects.
            if !DllCall("user32\SendMessageW", "Ptr", this.hHdr, "UInt", HDM_GETITEMRECT
                      , "Ptr", col - 1, "Ptr", rc.Ptr, "Ptr")
                continue                       ; column doesn't exist (yet)

            buf := Buffer(StrPut(text, "UTF-16") * 2, 0)
            StrPut(text, buf, "UTF-16")
            this.buffers[col] := buf           ; keep alive -- else the tip shows empty

            ti := this._ToolInfo(col, rc, buf)
            if this.added.Has(col) {
                DllCall("user32\SendMessageW", "Ptr", this.hTip, "UInt", TTM_NEWTOOLRECTW
                      , "Ptr", 0, "Ptr", ti.Ptr, "Ptr")
                DllCall("user32\SendMessageW", "Ptr", this.hTip, "UInt", TTM_UPDATETIPTEXTW
                      , "Ptr", 0, "Ptr", ti.Ptr, "Ptr")
            } else {
                DllCall("user32\SendMessageW", "Ptr", this.hTip, "UInt", TTM_ADDTOOLW
                      , "Ptr", 0, "Ptr", ti.Ptr, "Ptr")
                this.added[col] := true
            }
        }
        return true
    }

    ; ------------------------------------------------------------------
    ; Permanent tear down. Call from the Gui's Close handler.
    ; ------------------------------------------------------------------
    Dispose() {
        this.Enabled := false
        this._tick := 0                        ; breaks the object <-> timer cycle
        this.texts.Clear()
    }

    ; ==================================================================
    ; internals
    ; ==================================================================

    _CreateTipWindow() {
        static TTM_SETMAXTIPWIDTH := 0x0418
        static CW_USEDEFAULT := 0x80000000
        static TTSTYLE := 0x80000003           ; WS_POPUP | TTS_NOPREFIX | TTS_ALWAYSTIP

        hTip := DllCall("CreateWindowEx"
            , "UInt", 0                        ; dwExStyle
            , "Str" , "tooltips_class32"       ; lpClassName
            , "Ptr" , 0                        ; lpWindowName
            , "UInt", TTSTYLE
            , "Int" , CW_USEDEFAULT
            , "Int" , CW_USEDEFAULT
            , "Int" , CW_USEDEFAULT
            , "Int" , CW_USEDEFAULT
            , "Ptr" , this.hGui                ; hwndParent -- owns the tip's lifetime
            , "Ptr" , 0, "Ptr", 0, "Ptr", 0
            , "Ptr")

        if !hTip
            throw Error("LVHeaderToolTips: failed to create the tooltip window.", -1)

        ; Allow wrapping so `n in the text produces multi-line tips.
        DllCall("user32\SendMessageW", "Ptr", hTip, "UInt", TTM_SETMAXTIPWIDTH
              , "Ptr", 0, "Ptr", A_ScreenWidth, "Ptr")
        return hTip
    }

    ; TOOLINFO layout (both 32- and 64-bit):
    ;   0                cbSize      UInt
    ;   4                uFlags      UInt
    ;   8                hwnd        Ptr
    ;   8 + PtrSize      uId         Ptr
    ;   8 + PtrSize*2    rect        4 x Int
    ;   rect + 16        hinst       Ptr
    ;   rect + 16 + Ptr  lpszText    Ptr
    _ToolInfo(col, rc, textBuf := 0) {
        static TTF_SUBCLASS := 0x0010
        static rcOff := 8 + (A_PtrSize * 2)

        ti := Buffer(24 + (A_PtrSize * 6), 0)
        NumPut("UInt", ti.Size,      ti, 0)                 ; cbSize
        NumPut("UInt", TTF_SUBCLASS, ti, 4)                 ; NOT TTF_IDISHWND -- rect mode
        NumPut("Ptr" , this.hHdr,    ti, 8)                 ; hwnd = the header window
        NumPut("Ptr" , col,          ti, 8 + A_PtrSize)     ; uId  = 1-based column number

        NumPut("Int", NumGet(rc,  0, "Int")                 ; rect.left
             , "Int", NumGet(rc,  4, "Int")                 ; rect.top
             , "Int", NumGet(rc,  8, "Int")                 ; rect.right
             , "Int", NumGet(rc, 12, "Int")                 ; rect.bottom
             , ti, rcOff)

        if textBuf
            NumPut("Ptr", textBuf.Ptr, ti, rcOff + 16 + A_PtrSize)   ; lpszText
        return ti
    }

    _DelTool(col) {
        static TTM_DELTOOLW := 0x0433
        if (!this.hTip || !this.added.Has(col))
            return
        rc := Buffer(16, 0)
        ti := this._ToolInfo(col, rc)
        DllCall("user32\SendMessageW", "Ptr", this.hTip, "UInt", TTM_DELTOOLW
              , "Ptr", 0, "Ptr", ti.Ptr, "Ptr")
        this.added.Delete(col)
    }

    ; Compact fingerprint of the current header layout. If this changes, a
    ; column was resized, reordered, or the LV was scrolled horizontally.
    _Signature() {
        static HDM_GETITEMRECT := 0x1207
        rc := Buffer(16, 0)
        s  := ""
        for col in this.texts {
            if DllCall("user32\SendMessageW", "Ptr", this.hHdr, "UInt", HDM_GETITEMRECT
                     , "Ptr", col - 1, "Ptr", rc.Ptr, "Ptr")
                s .= NumGet(rc, 0, "Int") "," NumGet(rc, 8, "Int") ";"
            else
                s .= "x;"
        }
        return s
    }

    _Poll() {
        if !this.hTip
            return
        if !DllCall("IsWindow", "Ptr", this.hHdr, "Int") {
            this.Dispose()                     ; Gui was destroyed
            return
        }
        ; Do nothing at all unless this window is in front -- keeps the cost
        ; of the watchdog effectively zero for a background script.
        if (DllCall("GetForegroundWindow", "Ptr") != this.hGui)
            return

        if ((s := this._Signature()) != this.sig) {
            this.sig := s
            this.Refresh()
        }
    }
}


/*
===============================================================================
CtrlToolTipsEnable(guiObj, enable)

Switches every tooltip belonging to one Gui on and off, WITHOUT modifying
Mesut's CtrlToolTip above.

CtrlToolTip keeps its tooltip handles in function-static Maps with no
accessor, so we find the window instead: it creates one tooltips_class32
popup per Gui, passing the Gui HWND as hwndParent. For a WS_POPUP window that
parameter becomes the OWNER, so GW_OWNER identifies it unambiguously.
TTM_ACTIVATE then mutes or unmutes the whole tooltip control at once.

LVHeaderToolTips creates its windows the same way, so this sweep reaches
those too -- which is exactly what we want from one checkbox, but it is why
ApplyTipState() is careful about ordering.

Caveat: this DEACTIVATES rather than frees. The subclass on each control and
the tooltip window itself stay allocated -- a few KB, no CPU. That is the
price of not touching the third-party code.
===============================================================================
*/
CtrlToolTipsEnable(guiObj, enable) {
    static TTM_ACTIVATE := 0x0401
    static GW_OWNER     := 4

    prev := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        pid := DllCall("GetCurrentProcessId", "UInt")
        for hTip in WinGetList("ahk_class tooltips_class32 ahk_pid " pid) {
            if (DllCall("GetWindow", "Ptr", hTip, "UInt", GW_OWNER, "Ptr") = guiObj.Hwnd)
                DllCall("user32\SendMessageW", "Ptr", hTip, "UInt", TTM_ACTIVATE
                      , "Ptr", enable ? 1 : 0, "Ptr", 0, "Ptr")
        }
    } catch as err {
        return false
    } finally {
        DetectHiddenWindows(prev)
    }
    return true
}

; Both libraries above set the maximum tip width to A_ScreenWidth, which in
; practice means "never wrap" -- a long tip becomes one absurdly wide line.
; Rather than edit either one, find their windows the same way
; CtrlToolTipsEnable does and narrow them all in one pass.
;
; This has to be re-applied whenever LVHeaderToolTips recreates its windows,
; i.e. every time the tips are switched back on. ApplyTipState() does that.
TipMaxWidth(guiObj, px) {
    static TTM_SETMAXTIPWIDTH := 0x0418
    static GW_OWNER           := 4

    prev := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        pid := DllCall("GetCurrentProcessId", "UInt")
        for hTip in WinGetList("ahk_class tooltips_class32 ahk_pid " pid) {
            if (DllCall("GetWindow", "Ptr", hTip, "UInt", GW_OWNER, "Ptr") = guiObj.Hwnd)
                DllCall("user32\SendMessageW", "Ptr", hTip, "UInt", TTM_SETMAXTIPWIDTH
                      , "Ptr", 0, "Ptr", px, "Ptr")
        }
    } catch as err {
        return false
    } finally {
        DetectHiddenWindows(prev)
    }
    return true
}


; ============================== STATE =====================================
class RT {
    ; --- data ---
    static PhNames  := []          ; ordered placeholder names
    static PhMap    := Map()       ; name -> raw pattern text
    static Matches  := []          ; RegExMatchInfo objects from the last run
    static Spans    := []          ; {s,e} zero-based control offsets per match
    static Subject  := ""          ; text the regex was actually run against
    static Raw      := ""          ; canonical CR-per-break copy of the haystack
    static Loading  := false       ; suppresses live re-run during bulk updates
    static Shading  := false       ; suppresses EN_CHANGE while we recolor
    static PatShading := false     ; ditto, for the pattern box
    static LastPatText := ""       ; pattern text as of the last recolor

    ; --- matching-paren highlight, all filled in by ApplyPatternColors ---
    static PatPairs   := ""        ; 0-based paren position -> its partner's
    static PatParenFg := ""        ; 0-based paren position -> its normal color
    static PatHL      := ""        ; [openPos, closePos] lit right now, or ""
    static ParenBusy  := false     ; stops our own SetSel re-entering EN_SELCHANGE

    ; --- the Color Key window, built once and then hidden/shown ---
    static keyGui := "", keyRE := "", keyBtn := ""

    ; --- the placeholder pattern box, now a rich edit like the other two ---
    static PhShading := false      ; suppresses EN_CHANGE from our own writes
    static LastPhPatText := ""
    static cbTabs := "", TabsCbW := 165
    static Snippets := []          ; banked patterns, newest first
    static SnipDelete := false     ; next snippet pick removes instead of loads
    static NoJump   := false       ; suppresses caret movement on auto-selection
    static CurPh    := 0           ; placeholder row currently being edited
    static LastErr  := ""
    static Shown    := false       ; true once the window has been Show()n

    ; --- remembered client size (what Gui.Show's w/h actually set) ---
    static WinW     := 1040
    static WinH     := 820

    static SessionFile := A_ScriptDir "\RegExTesterSession.txt"

    ; --- gui + controls ---
    static gui := "", lvPh := "", edPhName := "", edPhPat := ""
    static cbPh := ""              ; "Show && use sub-pattern placeholders"
    static lblPhHint := ""         ; the "double-click a row..." hint beside it
    static PhCbW := 240            ; measured width of cbPh, set in BuildGui, lblPat := "", lblSubj := "", lblEol := ""
    static btnAdd := "", btnDel := "", btnUp := "", btnDn := ""
    static rePattern := "", edMoreOpts := "", edEffective := ""
    static btnSnips := "", btnAddSnip := "", btnKey := ""
    static lblOpts := "", lblMore := "", lblEff := "", cbWrap := ""
    static rdMatch := "", rdReplace := "", lblRepl := "", edRepl := ""
    static lblLimit := "", edLimit := "", cbAll := "", cbLive := ""
    static ddlEol := "", cbShade := "", btnRun := ""
    static reSubject := "", tabs := ""
    static lvMatches := "", lvGroups := "", edReplaced := ""
    static edCode := "", edCheat := "", sb := ""
    static optBoxes := Map()
    ; --- effective-pattern group spans, computed lazily on first group click ---
    static EffText  := ""          ; the string edEffective was last given
    static EffCaps  := ""          ; array of {s, e} per capture group, or "" if not parsed yet
    static EffBase  := 0           ; chars of option prefix ("i)") ahead of the pattern
    static cbTips := ""            ; "Show tips on hover"
    ; One LVHeaderToolTips instance per ListView.  They must outlive BuildGui,
    ; because each one owns a watchdog timer that re-reads the header rects.
    static TipsPh := "", TipsMatch := "", TipsGroup := ""
}

BuildGui()
LoadSession()                  ; may overwrite RT.WinW / RT.WinH
ApplyPhVisible()               ; before the first layout, so nothing flashes
ApplyTabsVisible()             ; ditto
UpdateTitle()                  ; LoadSession bails to a demo when there is no
                               ;   file yet, so set the title unconditionally
; Controls are created at rough coordinates and then positioned by OnSizeGui.
; Running the layout once before Show() means the first paint already has
; everything in its final spot, so there is no ghosting pass at startup.
OnSizeGui(RT.gui, 0, RT.WinW, RT.WinH)
RT.gui.Show("w" RT.WinW " h" RT.WinH)
RT.Shown := true
; Both tooltip systems go up AFTER Show().  The header tips have to: their
; rects don't exist until the window is realised, and registering early would
; peg every tool to a zero-width rectangle.  The control tips don't strictly
; need to wait, but keeping both on the same side of the first paint means
; there is only one ordering rule to remember.
AttachToolTips()
AttachHeaderTips()
RunTest()
return

; ============================== GUI =======================================
BuildGui() {
    g := Gui("+Resize +MinSize820x620", APP_TITLE)
    g.MarginX := 10, g.MarginY := 10
    RT.gui := g

    ; ---------- menu bar ----------
    mFile := Menu()
    mFile.Add("&Save session`tCtrl+S", (*) => SaveSession(true))
    mFile.Add("Save session &as...", (*) => SaveSessionAs())
    mFile.Add("&Open session...", (*) => OpenSessionFile())
    mFile.Add()
    mFile.Add("&Import from AHK code...", (*) => ImportDialog())
    mFile.Add()
    ; Two demos, because they show off opposite halves of the tool: one is all
    ; placeholders, the other is a single self-contained pattern of the sort any
    ; other regex tester would take.
    mDemo := Menu()
    mDemo.Add("&Date phrases, built from placeholders  (OutlookMagnet)", (*) => LoadDemoDates())
    mDemo.Add("&Hotstring parser, one big pattern  (AutoCorrect2)", (*) => LoadDemoHotstrings())
    mFile.Add("Load &demo", mDemo)
    mFile.Add("&Clear everything", (*) => ClearAll())
    mFile.Add()
    mFile.Add("E&xit", (*) => OnCloseGui())

    mEdit := Menu()
    mEdit.Add("Copy &effective pattern", (*) => CopyText(RT.edEffective.Value))
    mEdit.Add("Copy pattern as AHK &literal", (*) => CopyAsLiteral())
    mEdit.Add("Copy generated AHK &code", (*) => CopyText(RT.edCode.Value))
    mEdit.Add()
    mEdit.Add("&Pull option prefix out of pattern", (*) => PullOptionPrefix())

    mHelp := Menu()
    mHelp.Add("RegEx &quick reference (web)", (*) => Run("https://www.autohotkey.com/docs/v2/misc/RegEx-QuickRef.htm"))
    mHelp.Add("&RegExMatch docs (web)", (*) => Run("https://www.autohotkey.com/docs/v2/lib/RegExMatch.htm"))
    mHelp.Add("Reg&ExReplace docs (web)", (*) => Run("https://www.autohotkey.com/docs/v2/lib/RegExReplace.htm"))

    mb := MenuBar()
    mb.Add("&File", mFile)
    mb.Add("&Edit", mEdit)
    mb.Add("&Help", mHelp)
    g.MenuBar := mb

    ; ---------- placeholders ----------
    FontUI(g)
    ; The checkbox doubles as the section label.  Note the doubled "&&": a
    ; single & in a control's text is an accelerator and would show as an
    ; underline under the "u" instead of an ampersand.
    ;
    ; Deliberately created with NO width, so AHK sizes it to its own caption.
    ; The measured result is where the hint label starts -- reading it back
    ; beats hardcoding an offset, which would drift at 125% DPI or under any
    ; other scaling.
    RT.cbPh := g.Add("CheckBox", "x10 y10 Checked", "Show && use sub-pattern placeholders")
    RT.cbPh.OnEvent("Click", (*) => TogglePh())
    RT.cbPh.GetPos(&cbX, &cbY, &cbW)
    RT.PhCbW := cbW
    ; A separate control rather than more caption text, so that clicking the
    ; hint doesn't toggle the checkbox.  ApplyPhVisible() shows and hides it.
    RT.lblPhHint := g.Add("Text", "x260 y10 w450 h20 +0x200"
        , "—   double-click a row to insert %name% into the pattern")
    ; Top-right corner.  OnSizeGui pins it to the right edge and gives the
    ; hint label whatever room is left between the two.
    RT.cbTips := g.Add("CheckBox", "x846 y10 w164 h20 Checked", "Show tips on hover")
    RT.cbTips.OnEvent("Click", (*) => ToggleTips())

    FontMono(g)
    RT.lvPh := g.Add("ListView", "x10 y30 w800 h110 -Multi +Grid", ["Name", "Pattern", "Hits"])
    RT.lvPh.OnEvent("ItemFocus", (*) => PhRowFocused())
    RT.lvPh.OnEvent("DoubleClick", (*) => InsertPhToken())

    FontUI(g)
    RT.btnAdd := g.Add("Button", "x820 y30 w80 h24", "Add")
    RT.btnDel := g.Add("Button", "x820 y58 w80 h24", "Delete")
    RT.btnUp  := g.Add("Button", "x820 y86 w80 h24", "Move up")
    RT.btnDn  := g.Add("Button", "x820 y114 w80 h24", "Move dn")
    RT.btnAdd.OnEvent("Click", (*) => PhAdd())
    RT.btnDel.OnEvent("Click", (*) => PhDelete())
    RT.btnUp.OnEvent("Click",  (*) => PhMove(-1))
    RT.btnDn.OnEvent("Click",  (*) => PhMove(1))

    FontMono(g)
    RT.edPhName := g.Add("Edit", "x10 y146 w120 h22", "")
    RT.edPhName.OnEvent("Change", (*) => PhEdited())
    ; A rich edit rather than a plain one, so a placeholder's pattern gets the
    ; same coloring as the main pattern box -- these fragments are exactly where
    ; a missed paren hides, and until now they were the one regex on screen
    ; shown in flat black.  Two lines tall with wrap on, matching rePattern:
    ; a one-line rich edit would need a horizontal scrollbar, and a scrollbar
    ; inside a 22px control leaves no room for the text.
    RT.edPhPat := RichEdit(g, "x136 y146 w680 h40")
    RT.edPhPat.SetDefaultFont({Name: SUBJ_FONT, Size: SUBJ_SIZE})
    RT.edPhPat.WordWrap(true)
    HideHScroll(RT.edPhPat.Hwnd)
    RT.edPhPat.SetEventMask(["CHANGE"])
    RT.edPhPat.OnCommand(0x0300, (*) => PhPatChanged())          ; EN_CHANGE

    ; ---------- main pattern ----------
    FontUI(g)
    RT.lblPat := g.Add("Text", "x10 y176 w700 h20 +0x200", "Pattern   (raw PCRE — use %name% to pull in a placeholder)")
    RT.btnKey := g.Add("Button", "x616 y174 w86 h22", "Color Key")
    RT.btnKey.OnEvent("Click", (*) => ShowColorKey())
    RT.btnAddSnip := g.Add("Button", "x706 y174 w110 h22", "Add Snippet")
    RT.btnAddSnip.OnEvent("Click", (*) => AddCurrentSnippet())
    RT.btnSnips := g.Add("Button", "x820 y174 w96 h22", "Snippets  " Chr(0x25BE))
    RT.btnSnips.OnEvent("Click", (*) => ShowSnippetMenu())

    ; Also a rich edit, so placeholders and regex syntax can be colored.
    RT.rePattern := RichEdit(g, "x10 y196 w900 h48")
    RT.rePattern.SetDefaultFont({Name: SUBJ_FONT, Size: SUBJ_SIZE})
    RT.rePattern.WordWrap(true)
    HideHScroll(RT.rePattern.Hwnd)      ; word wrap is on, so it can never scroll
    ; SELCHANGE is what drives the matching-paren highlight.  It fires on plain
    ; caret movement as well as on real selections, which is exactly what is
    ; wanted -- but only while ENM_SELCHANGE is in the event mask, so the two
    ; lines below have to stay together.
    RT.rePattern.SetEventMask(["CHANGE", "SELCHANGE"])
    RT.rePattern.OnCommand(0x0300, (*) => PatternChanged())     ; EN_CHANGE
    RT.rePattern.OnNotify(0x0702, (*) => UpdateParenMatch())    ; EN_SELCHANGE

    ; ---------- options row ----------
    FontUI(g)
    RT.lblOpts := g.Add("Text", "x10 y252 w52 h20 +0x200", "Options:")
    xx := 66
    for letter in OPT_LETTERS {
        cb := g.Add("CheckBox", "x" xx " y252 w30 h20", letter)
        cb.OnEvent("Click", (*) => ScheduleRun())
        RT.optBoxes[letter] := cb
        xx += 32
    }
    RT.lblMore := g.Add("Text", "x" (xx + 6) " y252 w40 h20 +0x200", "more:")
    FontMono(g)
    RT.edMoreOpts := g.Add("Edit", "x" (xx + 48) " y251 w70 h22", "")
    RT.edMoreOpts.OnEvent("Change", (*) => ScheduleRun())
    FontUI(g)
    RT.cbWrap := g.Add("CheckBox", "x" (xx + 130) " y252 w210 h20", "Wrap each %ref% in (?:...)")
    RT.cbWrap.OnEvent("Click", (*) => ScheduleRun())

    FontUI(g)
    RT.lblEff := g.Add("Text", "x10 y280 w300", "Effective pattern (what AHK receives):")
    FontMono(g)
    ; +0x100 is ES_NOHIDESEL: keeps the group highlight visible while focus is
    ; on the groups ListView.  Without it the selection is drawn only when the
    ; Edit itself has focus, i.e. never, for the way this box is used.
    RT.edEffective := g.Add("Edit", "x10 y300 w900 h40 +Multi +ReadOnly +0x100", "")

    ; ---------- mode row ----------
    FontUI(g)
    RT.rdMatch   := g.Add("Radio", "x10 y350 w110 h22 +Group Checked", "RegExMatch")
    RT.rdReplace := g.Add("Radio", "x124 y350 w120 h22", "RegExReplace")
    RT.rdMatch.OnEvent("Click",   (*) => ModeChanged())
    RT.rdReplace.OnEvent("Click", (*) => ModeChanged())

    RT.lblRepl := g.Add("Text", "x252 y352 w84 h20 +0x200", "Replacement:")
    FontMono(g)
    RT.edRepl := g.Add("Edit", "x338 y349 w260 h22", "")
    RT.edRepl.OnEvent("Change", (*) => ScheduleRun())

    FontUI(g)
    RT.lblLimit := g.Add("Text", "x608 y352 w38 h20 +0x200", "Limit:")
    RT.edLimit := g.Add("Edit", "x648 y349 w48 h22 +Number", "")
    RT.edLimit.OnEvent("Change", (*) => ScheduleRun())

    RT.cbAll  := g.Add("CheckBox", "x708 y352 w76 h20 Checked", "Find all")
    RT.cbLive := g.Add("CheckBox", "x790 y352 w56 h20 Checked", "Live")
    RT.cbAll.OnEvent("Click", (*) => ScheduleRun())
    RT.btnRun := g.Add("Button", "x944 y349 w66 h24", "Run F5")
    RT.btnRun.OnEvent("Click", (*) => RunTest())

    ; ---------- subject ----------
    RT.lblSubj := g.Add("Text", "x10 y382 w150 h20 +0x200", "Subject / haystack")
    RT.lblEol  := g.Add("Text", "x170 y382 w80 h20 +0x200", "Line endings:")
    RT.ddlEol  := g.Add("DropDownList", "x252 y379 w120", ["CRLF (``r``n)", "LF (``n)", "CR (``r)"])
    RT.ddlEol.Value := 1
    RT.ddlEol.OnEvent("Change", (*) => RunTest())
    RT.cbShade := g.Add("CheckBox", "x384 y382 w130 h20 Checked", "Shade matches")
    RT.cbShade.OnEvent("Click", (*) => RunTest())
    ; Given an explicit width rather than measured like cbPh is.  cbPh can be
    ; measured because it is the very first control on its row and everything
    ; else keys off it; this one is pinned to the RIGHT edge, so a width that
    ; comes back as zero puts it at innerW - 0 with nothing to draw -- present,
    ; correct, and completely invisible.  A constant cannot fail that way.
    ; It sits on the haystack's label row rather than over the tabs because
    ; that is the pane it hands the space to.
    RT.cbTabs := g.Add("CheckBox", "x520 y382 w165 h20 Checked", "Show results tabs")
    RT.cbTabs.OnEvent("Click", (*) => ToggleTabs())

    ; The haystack is a rich edit control so matches can be shaded in place.
    RT.reSubject := RichEdit(g, "x10 y402 w1000 h120")
    RT.reSubject.SetDefaultFont({Name: SUBJ_FONT, Size: SUBJ_SIZE})
    RT.reSubject.WordWrap(true)
    HideHScroll(RT.reSubject.Hwnd)      ; wraps too, so it can never scroll
    RT.reSubject.SetEventMask(["CHANGE"])
    RT.reSubject.OnCommand(0x0300, (*) => SubjectChanged())     ; EN_CHANGE

    ; ---------- results ----------
    FontUI(g)
    RT.tabs := g.Add("Tab3", "x10 y530 w1000 h230", ["Matches", "Replaced", "AHK Code", "Cheat Sheet"])

    RT.tabs.UseTab(1)
    FontMono(g)
    RT.lvMatches := g.Add("ListView", "x20 y558 w440 h190 -Multi +Grid", ["#", "Pos", "Len", "Match"])
    RT.lvMatches.OnEvent("ItemFocus", (*) => MatchRowFocused())
    RT.lvGroups  := g.Add("ListView", "x466 y558 w530 h190 -Multi +Grid", ["#", "Name", "Pos", "Len", "Value"])
    RT.lvGroups.OnEvent("ItemFocus", (*) => GroupRowFocused())

    RT.tabs.UseTab(2)
    RT.edReplaced := g.Add("Edit", "x20 y558 w976 h190 +Multi +ReadOnly", "")

    RT.tabs.UseTab(3)
    RT.edCode := g.Add("Edit", "x20 y558 w976 h190 +Multi +ReadOnly -Wrap +HScroll +VScroll", "")

    RT.tabs.UseTab(4)
    RT.edCheat := g.Add("Edit", "x20 y558 w976 h190 +Multi +ReadOnly -Wrap +HScroll +VScroll", CheatSheet())

    RT.tabs.UseTab(0)

    FontUI(g)
    RT.sb := g.Add("StatusBar")
    RT.sb.SetText("  Ready.")

    g.OnEvent("Size", OnSizeGui)
    g.OnEvent("Close", (*) => OnCloseGui())
    ModeChanged()
}

FontUI(gu)   => gu.SetFont("s10 norm", "Segoe UI")
FontMono(gu) => gu.SetFont("s10 norm", "Consolas")

; ============================== LAYOUT ====================================
OnSizeGui(guiObj, MinMax, W, H) {
    static WM_SETREDRAW := 0x000B
    ; Moving a child while redraw is off leaves its old pixels on the parent.
    ; RDW_ERASE repaints the background underneath, RDW_FRAME redraws control
    ; borders, and RDW_UPDATENOW forces it all to happen before we return —
    ; without these the controls appear ghosted at their previous positions.
    static RDW_INVALIDATE := 0x0001, RDW_ERASE := 0x0004, RDW_ALLCHILDREN := 0x0080
    static RDW_UPDATENOW := 0x0100, RDW_FRAME := 0x0400
    ; reSubject is the last of these created in BuildGui, so testing it proves
    ; every control this function touches exists.  Testing lvPh would not:
    ; the list view is built before either rich edit.
    if (MinMax = -1 || !RT.lvPh || !RT.reSubject)
        return

    ; Remember the size only while restored.  MinMax = 1 is maximized, and
    ; saving a maximized size would reopen the window filling the screen but
    ; not actually maximized — which looks like a bug.
    if (MinMax = 0 && W > 0 && H > 0)
        RT.WinW := W, RT.WinH := H

    DllCall("user32\SendMessageW", "Ptr", guiObj.Hwnd, "UInt", WM_SETREDRAW, "Ptr", 0, "Ptr", 0)

    m := 10, sp := 6, rowH := 24, lblH := 20, btnW := 80
    sbH := 24
    try RT.sb.GetPos(, , , &sbH)
    if (!sbH)
        sbH := 24                       ; not yet measurable before the first Show

    innerW := W - m * 2
    phLvH := 110, patH := 48, effH := 40, phPatH := 40
    ; The placeholder block is optional.  Hidden, its rows cost nothing and the
    ; whole height goes to the haystack and the results tabs instead; the row 1
    ; strip holding the two checkboxes always stays.
    phShown := PhOn()
    phBlockH := phShown ? (phLvH + sp + phPatH + sp * 2) : sp
    fixed := lblH + phBlockH
           + lblH + patH + sp + rowH + sp
           + lblH + effH + sp * 2
           + rowH + sp * 2
           + lblH + sp + m * 2
    ; Spare vertical space is shared out: a small slice to the placeholder
    ; table while it is showing, then whatever is left is split 50/50 between
    ; the haystack and the results tabs.  The even split is the rule in both
    ; states, so folding the table away grows both panes rather than dumping
    ; the whole gain into the tabs.
    flex := H - sbH - fixed
    phExtra := phShown ? Max(0, Integer(flex * 0.15)) : 0
    phLvH += phExtra
    spare := flex - phExtra
    tabsShown := TabsOn()
    if (tabsShown) {
        subjH := Max(60, Integer(spare / 2))
        tabsH := Max(150, spare - subjH)
    } else {
        ; The even split only makes sense while there are two panes to split
        ; between.  With the tabs folded away the haystack takes the lot --
        ; which is the whole reason for the toggle.
        subjH := Max(60, spare)
        tabsH := 0
    }
    ; Those two minimums are wishes, not guarantees.  When the window is short
    ; they can between them ask for more height than `spare` actually is, and
    ; without this the surplus runs straight off the bottom -- the tab control
    ; is drawn over the status bar.  Showing the placeholder block is what
    ; usually triggers it, because the block costs ~152px of fixed height plus
    ; its 15% slice of the flex, so the same window that was fine with the
    ; table folded away is short by 20-odd pixels with it open.
    ;
    ; Hand the surplus back rather than letting it overflow.  Take it from the
    ; haystack first, down to its own minimum, then off the tabs.  A cramped
    ; pane is recoverable by dragging the window taller; a status bar with the
    ; warnings hidden under a list view is the bug being reported.
    over := subjH + tabsH - spare
    if (over > 0 && tabsShown) {
        give := Min(over, subjH - 60)
        subjH -= give
        over -= give
        tabsH := Max(48, tabsH - over)   ; 48 keeps th (tabsH - 38) positive
    }

    y := m
    tipsW := 164
    RT.cbPh.Move(m, y, RT.PhCbW, lblH)
    hintX := m + RT.PhCbW + sp
    RT.lblPhHint.Move(hintX, y, Max(0, m + innerW - tipsW - sp - hintX), lblH)
    RT.cbTips.Move(m + innerW - tipsW, y, tipsW, lblH)
    y += lblH
    if (phShown) {
        lvW := innerW - btnW - sp
        RT.lvPh.Move(m, y, lvW, phLvH)
        RT.lvPh.ModifyCol(1, 130), RT.lvPh.ModifyCol(3, 68)
        RT.lvPh.ModifyCol(2, Max(120, lvW - 130 - 68 - 26))
        bx := m + lvW + sp
        RT.btnAdd.Move(bx, y, btnW, rowH)
        RT.btnDel.Move(bx, y + 28, btnW, rowH)
        RT.btnUp.Move(bx, y + 56, btnW, rowH)
        RT.btnDn.Move(bx, y + 84, btnW, rowH)
        y += phLvH + sp
        RT.edPhName.Move(m, y, 130, rowH - 2)
        RT.edPhPat.Move(m + 136, y, innerW - 136, phPatH)
        y += phPatH + sp * 2
    } else {
        y += sp                         ; keep phBlockH and the layout in step
    }

    RT.lblPat.Move(m, y, Max(160, innerW - 318), lblH)
    RT.btnKey.Move(m + innerW - 304, y - 2, 86, lblH + 2)
    RT.btnAddSnip.Move(m + innerW - 212, y - 2, 110, lblH + 2)
    RT.btnSnips.Move(m + innerW - 96, y - 2, 96, lblH + 2)
    y += lblH
    RT.rePattern.Move(m, y, innerW, patH)
    y += patH + sp

    RT.lblOpts.Move(m, y + 2, 56, lblH)
    xx := m + 56
    for letter in OPT_LETTERS {
        RT.optBoxes[letter].Move(xx, y + 2, 30, lblH)
        xx += 32
    }
    RT.lblMore.Move(xx + 6, y + 2, 40, lblH)
    RT.edMoreOpts.Move(xx + 48, y, 70, rowH - 2)
    RT.cbWrap.Move(xx + 130, y + 2, 210, lblH)
    y += rowH + sp

    RT.lblEff.Move(m, y, 300, lblH)
    y += lblH
    RT.edEffective.Move(m, y, innerW, effH)
    y += effH + sp * 2

    RT.rdMatch.Move(m, y + 1, 110, rowH - 2)
    RT.rdReplace.Move(m + 114, y + 1, 120, rowH - 2)
    RT.lblRepl.Move(m + 242, y + 3, 84, lblH)
    tailW := 38 + 48 + 10 + 76 + 56 + 70 + 40         ; limit..run button
    replW := Max(120, innerW - 242 - 84 - tailW - 20)
    RT.edRepl.Move(m + 328, y, replW, rowH - 2)
    rx := m + 328 + replW + 12
    RT.lblLimit.Move(rx, y + 3, 38, lblH)
    RT.edLimit.Move(rx + 40, y, 48, rowH - 2)
    RT.cbAll.Move(rx + 98, y + 3, 76, lblH)
    RT.cbLive.Move(rx + 178, y + 3, 56, lblH)
    RT.btnRun.Move(W - m - 70, y, 70, rowH)
    y += rowH + sp * 2

    RT.lblSubj.Move(m, y, 150, lblH)
    RT.lblEol.Move(m + 160, y, 80, lblH)
    RT.ddlEol.Move(m + 242, y - 3, 120, rowH)
    RT.cbShade.Move(m + 374, y, 130, lblH)
    RT.cbTabs.Move(m + innerW - RT.TabsCbW, y, RT.TabsCbW, lblH)
    y += lblH
    RT.reSubject.Move(m, y, innerW, subjH)
    y += subjH + sp

    ; Guarded rather than returned early: the redraw restore and the
    ; SuppressHScroll calls at the bottom of this function have to run in
    ; both states.
    if (tabsShown) {
        RT.tabs.Move(m, y, innerW, tabsH)
        tx := m + 10, ty := y + 28, tw := innerW - 20, th := tabsH - 38
        lvmW := Integer(tw * 0.44)
        RT.lvMatches.Move(tx, ty, lvmW, th)
        RT.lvMatches.ModifyCol(1, 34), RT.lvMatches.ModifyCol(2, 55), RT.lvMatches.ModifyCol(3, 45)
        RT.lvMatches.ModifyCol(4, Max(80, lvmW - 34 - 55 - 45 - 26))
        RT.lvGroups.Move(tx + lvmW + 6, ty, tw - lvmW - 6, th)
        RT.lvGroups.ModifyCol(1, 34), RT.lvGroups.ModifyCol(2, 90)
        RT.lvGroups.ModifyCol(3, 55), RT.lvGroups.ModifyCol(4, 45)
        RT.lvGroups.ModifyCol(5, Max(80, tw - lvmW - 6 - 34 - 90 - 55 - 45 - 26))
        RT.edReplaced.Move(tx, ty, tw, th)
        RT.edCode.Move(tx, ty, tw, th)
        RT.edCheat.Move(tx, ty, tw, th)
    }

    ; All three rich edits word-wrap, so none can ever scroll sideways -- but
    ; being Moved above makes them re-assert a horizontal bar.  Undo that here,
    ; still inside the redraw-off window, so the RedrawWindow below picks it up
    ; and nothing flickers.
    SuppressHScroll(RT.rePattern.Hwnd)
    SuppressHScroll(RT.reSubject.Hwnd)
    if (phShown)
        SuppressHScroll(RT.edPhPat.Hwnd)

    DllCall("user32\SendMessageW", "Ptr", guiObj.Hwnd, "UInt", WM_SETREDRAW, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", guiObj.Hwnd, "Ptr", 0, "Ptr", 0,
        "UInt", RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW | RDW_FRAME)
}

; Shows which saved session is loaded.  Document-name-first, matching the
; Windows convention, so the file is still legible when the taskbar truncates.
;
; Base name only while the file sits beside the script -- the usual case, where
; the folder adds nothing.  Full path once it doesn't, because that is exactly
; when two sessions can share a name and the base name stops being an answer.
UpdateTitle() {
    SplitPath(RT.SessionFile, &name, &dir)
    shown := (dir = "" || dir = A_ScriptDir) ? name : RT.SessionFile
    RT.gui.Title := shown " - " APP_TITLE
    A_IconTip := name " - " APP_TITLE        ; tray hover, same question
}

; ====================== PLACEHOLDER SUPPORT TOGGLE ========================
; "Show && use sub-pattern placeholders" is a mode switch, not just a view
; option.  Unticked, the placeholder table disappears AND %name% stops being a
; reference: the pattern box then means exactly what it would mean in any other
; regex tester, and the AHK Code tab stops declaring variables that the pattern
; no longer uses.  The definitions are kept, not discarded, so ticking it again
; brings everything back.
;
; Every code path that asks "is this a placeholder?" routes through ExpandText
; or SplitRefs, so gating those two covers expansion, code generation, the
; top-level-| hazard analysis and the hit counts.
; ---- the placeholder pattern box -------------------------------------------
; Same tokenizer, same colors, same guard-against-our-own-writes dance as the
; main pattern box.  What it deliberately does NOT get is the matching-paren
; highlight: that machinery is written against RT.rePattern's cached pairing,
; and a second copy of it for a two-line box would cost more than it returns.
PhPatText() {
    t := RT.edPhPat.GetText()
    t := StrReplace(t, "`r`n", "`n")
    t := StrReplace(t, "`r", "`n")
    ; A placeholder pattern is a fragment on one line.  If somebody pastes
    ; several, fold them together rather than letting a stray newline into the
    ; middle of the effective pattern, where it would match literally.
    return StrReplace(t, "`n", "")
}

SetPhPatText(txt) {
    RT.PhShading := true
    RT.edPhPat.SetText(txt)
    RT.edPhPat.SetSel(0, -1)
    RT.edPhPat.SetFont({Name: SUBJ_FONT, Size: SUBJ_SIZE, Style: "N"
                      , Color: "Auto", BkColor: "Auto"})
    RT.edPhPat.SetSel(0, 0)
    RT.PhShading := false
    SuppressHScroll(RT.edPhPat.Hwnd)
    RT.LastPhPatText := txt
    SchedulePhPatColors()
}

PhPatChanged() {
    if (RT.PhShading)
        return
    t := PhPatText()
    if (t == RT.LastPhPatText)       ; a formatting-only notification
        return
    RT.LastPhPatText := t
    PhEdited()
    SchedulePhPatColors()
}

SchedulePhPatColors() {
    if (RT.Loading || !RT.edPhPat)
        return
    SetTimer(ApplyPhPatColors, -COLOR_DELAY)
}

ApplyPhPatColors(*) {
    SetTimer(ApplyPhPatColors, 0)
    if (!RT.edPhPat || !PhOn())
        return
    ; Recoloring saves and restores the selection, which cancels a drag in
    ; progress -- but only a drag inside THIS control.  Clicking a row in the
    ; list view above also leaves the button physically down, and deferring for
    ; that would add a visible pause to exactly the case that should feel
    ; instant, so the focus test lets it through.
    if (GetKeyState("LButton", "P") && RT.edPhPat.Focused) {
        SetTimer(ApplyPhPatColors, -COLOR_DELAY)
        return
    }
    RE := RT.edPhPat
    info := AnalyzePattern(PhPatText())
    RT.PhShading := true
    sel := RE.GetSel()
    scr := RE.GetScrollPos()
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    RE.SetSel(0, -1)
    RE.SetFont({Style: "N", Color: "Auto", BkColor: "Auto"})
    ApplyRuns(RE, info.runs)
    RE.SetSel(sel.S, sel.E)
    RE.SetScrollPos(scr.X, scr.Y)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("InvalidateRect", "Ptr", RE.Hwnd, "Ptr", 0, "Int", 1)
    RT.PhShading := false
}

; ---- the results tabs ------------------------------------------------------
; Folding the tabs away hands their half of the flexible height to the
; haystack, which is the point: a long subject is far easier to read at double
; the height, and the tabs are not much use while you are still pasting text in.
TabsOn() {
    return (RT.cbTabs && RT.cbTabs.Value) ? true : false
}

ToggleTabs() {
    ApplyTabsVisible()
    Status(TabsOn() ? "Results tabs shown."
                    : "Results tabs hidden -- the haystack now has the whole pane.")
}

ApplyTabsVisible() {
    on := TabsOn()
    ; The tab control and NOTHING ELSE.  Under Tab3 the page controls are real
    ; children of the tab control, so they follow it without being asked.
    ;
    ; Touching them individually is actively harmful, which is worth recording
    ; because it looks like the safer option: setting Visible on a control that
    ; lives on a tab page takes it out of the tab control's hands for good.
    ; AHK then stops re-showing it when its page is selected, so hiding pages
    ; 2-4 here to avoid them stacking up left them permanently blank -- the tab
    ; still switched, but there was nothing on it any more.
    RT.tabs.Visible := on
    if (RT.Shown)
        OnSizeGui(RT.gui, 0, RT.WinW, RT.WinH)
}

PhOn() {
    return (RT.cbPh && RT.cbPh.Value) ? true : false
}

TogglePh() {
    ApplyPhVisible()
    ScheduleRun()                  ; the effective pattern just changed meaning
    SchedulePatternColors()
    SchedulePhPatColors()          ; %refs% inside a placeholder change meaning too
    on := PhOn()
    Status(on ? "Placeholder support on."
              : "Placeholder support off -- %name% is now matched as literal text.")
}

ApplyPhVisible() {
    on := PhOn()
    for c in [RT.lvPh, RT.btnAdd, RT.btnDel, RT.btnUp, RT.btnDn, RT.edPhName]
        c.Visible := on
    ; RichEdit exposes Visible as a get-only property, so the wrapper cannot be
    ; assigned to the way a Gui.Control can.  Opt() is delegated properly and
    ; does the same job.
    RT.edPhPat.Opt(on ? "-Hidden" : "+Hidden")
    RT.lblPhHint.Visible := on
    ; The pattern label advertises %name% only while it means something.
    if (on)
        RT.lblPat.Text := "Pattern   (raw PCRE — use %name% to pull in a placeholder)"
    else
        RT.lblPat.Text := "Pattern   (raw PCRE)"
    RT.cbWrap.Enabled := on        ; nothing left to wrap
    ; Don't poll a header nobody can see.
    if (RT.TipsPh is LVHeaderToolTips)
        RT.TipsPh.Enabled := on && RT.cbTips.Value
    if (RT.Shown)
        OnSizeGui(RT.gui, 0, RT.WinW, RT.WinH)
}

; ------------------------ HORIZONTAL SCROLL BAR ---------------------------
; Both rich edits have word wrap on, so neither can ever scroll sideways --
; but the control still reserves and paints a dead horizontal bar.  Two
; functions suppress it: HideHScroll() once at creation, and SuppressHScroll()
; again every time the control re-lays itself out.
;
; The repetition is deliberate, not a leftover.  The obvious root fix -- never
; give the control the styles in the first place -- is NOT available, because
; of the order RichEdit.__New() assembles its option string in
; (Tools\RichEdit.ahk, the CtrlOpts line):
;
;   CtrlOpts := "Class" MSFTEDIT_CLASS " " Options " +" Styles " +E" ExStyles
;
; The caller's Options go in first and the class's own Styles follow, and AHK
; applies +/- style tokens left to right against a running value, so the later
; "+Styles" wins.  Styles always carries ES_AUTOHSCROLL, plus WS_HSCROLL and
; ES_DISABLENOSCROLL whenever MultiLine is true -- which is its default.
; Passing "-0x102080" in the options string here is therefore a no-op.  It was
; tried.  It does nothing.
;
; Stripping the bits afterwards does not fully stick either: the control
; re-derives its scroll bars from creation-time internal state on every
; re-layout, which is why the bar came back on two separate triggers -- a
; resize (the placeholder toggle calls OnSizeGui, which Moves every control)
; and a text replacement (opening a different session file).  Hence the cheap
; repeated call rather than one fix at creation.
;
; Side effect worth knowing about: dropping ES_DISABLENOSCROLL unpins the
; VERTICAL bar as well, so it now comes and goes as the text grows past the
; box, and the wrap width shifts when it does.  Keeping the style would pin
; the vertical bar, but it is also precisely what keeps a dead horizontal one
; painted instead of hidden, so it has to go.
;
; The one-time half: strip the styles, then ask for a frame recalc so the
; space the bar was holding is actually given back.
HideHScroll(hwnd) {
    static GWL_STYLE := -16
    static WS_HSCROLL := 0x00100000, ES_DISABLENOSCROLL := 0x2000, ES_AUTOHSCROLL := 0x0080
    static SWP_NOSIZE := 0x1, SWP_NOMOVE := 0x2, SWP_NOZORDER := 0x4, SWP_FRAMECHANGED := 0x20
    gwl := (A_PtrSize = 8) ? "GetWindowLongPtr" : "GetWindowLong"
    swl := (A_PtrSize = 8) ? "SetWindowLongPtr" : "SetWindowLong"
    st := DllCall(gwl, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
    ; ES_AUTOHSCROLL is in the list because without it the control has no
    ; reason to want a horizontal bar at all; ES_DISABLENOSCROLL is what keeps
    ; a dead one painted instead of hidden.
    DllCall(swl, "Ptr", hwnd, "Int", GWL_STYLE
          , "Ptr", st & ~WS_HSCROLL & ~ES_DISABLENOSCROLL & ~ES_AUTOHSCROLL, "Ptr")
    SuppressHScroll(hwnd)
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0
          , "UInt", SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED)
}

; The cheap half, which has to be repeated -- see the block above HideHScroll()
; for why once at creation is not enough.  No SetWindowPos here, just style
; bits, so it is safe to run on every resize and every text load.  Called from
; four places: the end of OnSizeGui for both boxes, inside the WM_SETREDRAW-off
; window so it cannot flicker, and from SetPatternText() and SetSubjectText().
; Confirmed to hold through both triggers.
SuppressHScroll(hwnd) {
    static SB_HORZ := 0
    static EM_SHOWSCROLLBAR := 0x0460
    ; Two calls, and the names are an unfortunate collision -- they are not the
    ; same function:
    ;   EM_SHOWSCROLLBAR    tells the rich edit's own layout engine
    ;   user32\ShowScrollBar  tells the window
    ;
    ; The first one is RichEdit.ShowScrollBar(0, false) written out by hand:
    ; that method is just SendMessage(0x0460, SB, !!Mode, This.HWND), same
    ; message, same arguments.  It is spelled out here rather than called
    ; because this runs from OnSizeGui, which fires once BEFORE Gui.Show() (see
    ; the startup sequence), and AHK's SendMessage does window matching that
    ; has failed on this file in early-GUI paths.  Same reason OnSizeGui uses
    ; DllCall for WM_SETREDRAW.  Using the method would also mean passing the
    ; RichEdit object instead of a HWND, at four call sites.
    ;
    ; The library has no wrapper for the second call, so the pair cannot
    ; collapse into one method call either way.  Which of the two is actually
    ; load bearing was never isolated -- the pair works, and dropping one would
    ; save nothing measurable, so both stay.
    DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", EM_SHOWSCROLLBAR
          , "Ptr", SB_HORZ, "Ptr", 0, "Ptr")
    DllCall("ShowScrollBar", "Ptr", hwnd, "Int", SB_HORZ, "Int", 0)
}

; ============================== TOOLTIPS ==================================
; Two mechanisms, one checkbox:
;   CtrlToolTip()       -- one tip per control          (Mesut Akcan)
;   LVHeaderToolTips    -- one tip per ListView COLUMN  (companion class)
; Both are embedded near the TOP of this file rather than #Included, so the
; tester stays a single portable script.  See the attribution block there --
; it also explains why they sit above the auto-execute return.
;
; Some of this text repeats the Cheat Sheet tab.  That is deliberate: the tab
; is for browsing, the tip is for the control you happen to be looking at.

; Registers the per-control tips.  These are registered once and stay
; registered; the checkbox only activates/deactivates the tooltip window,
; which is far cheaper than building and tearing them down each time.
AttachToolTips() {
    ; --- placeholder table -----------------------------------------------
    CtrlToolTip(RT.cbTips,
        "Turns these hover tips on and off -- both the control tips and the`n"
      . "ListView column-header tips.  Remembered in the session file.")

    CtrlToolTip(RT.cbPh,
        "A placeholder is a named piece of pattern.  Define it once in the`n"
      . "table, then pull it into the main pattern -- or into another`n"
      . "placeholder -- by writing %name%.  This mirrors the way real scripts`n"
      . "build a pattern by concatenating variables, which is what the AHK`n"
      . "Code tab regenerates.`n`n"
      . "UNTICK to fold the table away and turn the feature OFF entirely.`n"
      . "%name% then matches as literal text and the generated code stops`n"
      . "declaring variables, so this behaves like an ordinary regex tester.`n"
      . "Your definitions are kept either way -- tick it again to get them`n"
      . "back.")

    CtrlToolTip(RT.btnAdd,
        "Adds an empty placeholder row and puts the caret in the Name box.")
    CtrlToolTip(RT.btnDel,
        "Deletes the selected row.  Any %name% still referring to it turns`n"
      . "red in the pattern box, since it no longer resolves.")
    CtrlToolTip(RT.btnUp,
        "Moves the selected row up.  Order is cosmetic -- it changes neither`n"
      . "matching nor the generated code, which is sorted by dependency.")
    CtrlToolTip(RT.btnDn,
        "Moves the selected row down.  Order is cosmetic -- it changes neither`n"
      . "matching nor the generated code, which is sorted by dependency.")

    CtrlToolTip(RT.edPhName,
        "Name of the selected row.  Letters, digits and underscore, not`n"
      . "starting with a digit -- the same rule as an AHK variable, because`n"
      . "that is exactly what it becomes on the AHK Code tab.")
    ; .RE is the wrapper's inner Gui.Custom control.  CtrlToolTip type-checks
    ; for Gui.Control and would reject the RichEdit object itself.
    CtrlToolTip(RT.edPhPat.RE,
        "Pattern text of the selected row, as RAW PCRE -- not an AHK string`n"
      . "literal.  Type a backslash-t for a tab, not a backtick-t.`n`n"
      . "A placeholder may reference other placeholders as %name%.`n"
      . "Circular references are detected and reported rather than hanging.")

    ; --- main pattern -----------------------------------------------------
    CtrlToolTip(RT.lblPat,
        "The main pattern, as RAW PCRE -- what the engine sees, not an AHK`n"
      . "string literal.  Options belong in the checkboxes below, not at the`n"
      . "front of the pattern.`n`n"
      . "Double-click a placeholder row to drop its %name% in at the caret.")
    CtrlToolTip(RT.btnKey,
        "Opens a legend for the pattern box: every coloring rule, shown in`n"
      . "the color it actually produces, next to a sample that produces it.`n`n"
      . "The samples are run through the same tokenizer that colors the`n"
      . "pattern box, so the legend cannot fall out of date.")
    CtrlToolTip(RT.btnAddSnip,
        "Banks the current pattern in the Snippets list.`n`n"
      . "Nothing is ever recorded automatically -- a pattern is remembered`n"
      . "only when you press this, so the list stays worth reading.")
    CtrlToolTip(RT.btnSnips,
        "Recall, remove or clear a banked pattern.  The last " MAX_SNIPPETS "`n"
      . "are kept, newest first, and they are saved with the session.")

    ; --- options ----------------------------------------------------------
    CtrlToolTip(RT.lblOpts,
        "Option letters are prepended to the pattern as an explicit " Chr(34) "opts)" Chr(34) "`n"
      . "prefix.  Setting them here rather than typing them into the pattern`n"
      . "means a pattern that legitimately starts with " Chr(34) ")" Chr(34) " still works.")

    optTips := Map(
        "i", "Case-insensitive.",
        "m", "Multiline: ^ and $ also match at internal line breaks, not`n"
           . "only at the two ends of the haystack.",
        "s", "Dot-all: . also matches a newline.`n`n"
           . "With CRLF line endings a break is TWO characters, so it takes`n"
           . "two dots to cross one.",
        "x", "Extended: literal whitespace in the pattern is ignored and #`n"
           . "starts a comment.  Use \s, \x20 or a character class when you`n"
           . "actually mean a space.",
        "A", "Anchored: match only at the start of the haystack.`n`n"
           . "This is the right way to anchor at a start position; a leading`n"
           . "^ still refers to the true start of the string.",
        "D", "Dollar-endonly: $ matches only at the very end, even when the`n"
           . "haystack ends in a newline.  Ignored when m is also on.",
        "J", "Allow two capture groups to share one name.",
        "U", "Ungreedy: quantifiers become lazy by default, and a following`n"
           . "? makes them greedy again -- the reverse of the usual meaning.",
        "X", "PCRE_EXTRA: a backslash followed by a letter that has no`n"
           . "meaning throws an error instead of being taken as the letter.",
        "S", "Study the pattern.  A small speedup when the same pattern is`n"
           . "run many times; it cannot change what matches.")
    for letter in OPT_LETTERS
        if optTips.Has(letter)
            CtrlToolTip(RT.optBoxes[letter], letter "   " optTips[letter])

    CtrlToolTip(RT.lblMore,
        "Option characters that have no checkbox of their own.")
    CtrlToolTip(RT.edMoreOpts,
        "Anything typed here is appended to the letters ticked above.`n`n"
      . "Use it for C (auto-callout), for the newline-marker options, or`n"
      . "for a leading (*VERB) that has to reach the engine verbatim.")
    CtrlToolTip(RT.cbWrap,
        "Wraps every %name% expansion in a non-capturing group (?:...)`n"
      . "before the pattern is run.`n`n"
      . "OFF by default, because plain concatenation is what a real script`n"
      . "does -- and showing you when that bites is half the point of this`n"
      . "tester.  Tick it to confirm that a stray top-level | inside a`n"
      . "placeholder is the reason a pattern is matching too much.`n`n"
      . "The AHK Code tab emits the wrap too, so pasted code behaves the`n"
      . "same way it did here.")

    CtrlToolTip(RT.lblEff,
        "The pattern after every %name% has been expanded and the option`n"
      . "prefix has been prepended -- literally the string handed to`n"
      . "RegExMatch().  It turns pink when that string will not compile.")

    ; --- mode row ---------------------------------------------------------
    CtrlToolTip(RT.rdMatch,
        "Run RegExMatch() and list every match with its capture groups.")
    CtrlToolTip(RT.rdReplace,
        "Run RegExReplace() and show the result on the Replaced tab.`n`n"
      . "The match and group lists are still filled in, so you can see`n"
      . "exactly what each replacement acted on.")
    CtrlToolTip(RT.lblRepl,  ReplTipText())
    CtrlToolTip(RT.edRepl,   ReplTipText())
    CtrlToolTip(RT.lblLimit, LimitTipText())
    CtrlToolTip(RT.edLimit,  LimitTipText())
    CtrlToolTip(RT.cbAll,
        "Ticked: find every match.`n"
      . "Unticked: stop after the first, which is what a bare RegExMatch()`n"
      . "call does in a script.")
    CtrlToolTip(RT.cbLive,
        "Re-run automatically a moment after you stop typing.`n`n"
      . "Untick it before trying a pattern that might backtrack`n"
      . "catastrophically.  A runaway pattern hangs this window exactly`n"
      . "as it would hang a real script -- the engine is the same one.")
    CtrlToolTip(RT.btnRun,
        "Run once, now.  F5 does the same.")

    ; --- subject ----------------------------------------------------------
    CtrlToolTip(RT.lblSubj,
        "The text the pattern runs against.  Type or paste anything;`n"
      . "it is saved with the session.")
    CtrlToolTip(RT.lblEol,  EolTipText())
    CtrlToolTip(RT.ddlEol,  EolTipText())
    CtrlToolTip(RT.cbShade,
        "Tints each match in the haystack, alternating two colors so that`n"
      . "two matches which touch stay distinguishable.`n`n"
      . "Shading pushes entries onto the rich edit's undo stack, so Ctrl+Z`n"
      . "in that pane can take a few presses to reach your own typing.")

    CtrlToolTip(RT.cbTabs,
        "Folds the results tabs away and hands their share of the window to`n"
      . "the haystack, which is useful while you are still pasting text in.`n`n"
      . "The haystack and the tabs normally split the flexible height evenly.`n"
      . "With the tabs hidden the haystack takes all of it, so this roughly`n"
      . "doubles the room for the text you are matching against.`n`n"
      . "Matching still runs while they are hidden; the Matches list is`n"
      . "simply not on screen to show you the result.  The setting is saved`n"
      . "with the session.")

    ; --- status bar -------------------------------------------------------
    ; Status() replaces this text on every update.  Registering it here just
    ; means the tool exists from the first paint.
    CtrlToolTip(RT.sb,
        "Result count and warnings.  The bar is one narrow line and truncates,`n"
      . "so the full message — every warning, one per line — shows up here.")
}

; Used on both the label and its edit, so the text lives in one place.
ReplTipText() {
    return "Replacement text.  $1 $2 ... for capture groups, ${name} for a`n"
         . "named one, $0 for the whole match, and $$ for a literal dollar`n"
         . "sign.  $U1 / $L1 upper- or lower-case that group."
}
LimitTipText() {
    return "Maximum number of replacements to make.  Leave it blank to`n"
         . "replace every match."
}
EolTipText() {
    return "How line breaks are presented to the regex engine.`n`n"
         . "The edit control itself stores one CR per break; this setting`n"
         . "decides whether the engine is handed CRLF, LF or CR.  It changes`n"
         . "what $, . and \n can match, so it is not a cosmetic choice.`n`n"
         . "Match positions are adjusted to compensate, so the shading still`n"
         . "lands in the right place either way."
}

; Per-column header tips.  MUST be called after Show(), or every header rect
; is still zero-width and the tools register over nothing.
AttachHeaderTips() {
    on := RT.cbTips.Value ? true : false
    RT.TipsPh := LVHeaderToolTips(RT.lvPh, [
        "The placeholder's name.  Reference it from the main pattern, or`n"
      . "from another placeholder, by writing %name%.",
        "The raw PCRE fragment that the name expands to.`n`n"
      . "Flattened to one line here -- " Chr(0x00B6) " stands for a line break and`n"
      . Chr(0x2192) " for a tab.  Edit the real text in the box below the list.",
        "How many times this sub-pattern ALONE matches the haystack, with`n"
      . "the current options applied.`n`n"
      . "This is how you find which piece of a long pattern is the one`n"
      . "that isn't firing.  " Chr(0x2205) " means the sub-pattern can match an empty`n"
      . "string, which is usually why a count looks impossibly large.`n"
      . Chr(34) "err" Chr(34) " means it does not compile on its own."
    ], on && PhOn())
    RT.TipsMatch := LVHeaderToolTips(RT.lvMatches, [
        "Match number, in the order found.`n"
      . "Click a row to select that match in the haystack.",
        "1-based character position of the match -- the same number that`n"
      . "RegExMatch() reports as Match.Pos.",
        "Length of the match in characters.  Zero means the pattern matched`n"
      . "an empty string here, which also means it matches between every`n"
      . "pair of characters.  That is almost never intended.",
        "The matched text, flattened to one line: " Chr(0x00B6) " is a line break`n"
      . "and " Chr(0x2192) " is a tab."
    ], on)
    RT.TipsGroup := LVHeaderToolTips(RT.lvGroups, [
        "Capture group number.  Row 0 is the whole match.`n"
      . "Click a row to select just that group in the haystack.",
        "The group's name, if it was written as (?<name>...).`n"
      . "Blank for an ordinary numbered group.",
        "1-based start of the group.`n`n"
      . "Zero means the group did NOT take part in this match, which is a`n"
      . "different thing from matching an empty string -- an optional group`n"
      . "that was skipped reports 0, not a position with length 0.",
        "Length of the captured text in characters.",
        "The captured text, flattened to one line: " Chr(0x00B6) " is a line break`n"
      . "and " Chr(0x2192) " is a tab."
    ], on)
    ApplyTipState()
}

; The single switch behind the checkbox.  Returns the new state.
;
; Order matters.  Switching ON, the header windows have to exist before the
; TTM_ACTIVATE sweep runs, or the sweep never sees them.  Switching OFF, they
; are destroyed first and the sweep then only has to mute what is left.
ApplyTipState() {
    on := RT.cbTips.Value ? true : false
    for t in [RT.TipsPh, RT.TipsMatch, RT.TipsGroup]
        if (t is LVHeaderToolTips)
            t.Enabled := on
    CtrlToolTipsEnable(RT.gui, on)
    if (on)
        TipMaxWidth(RT.gui, TIP_WIDTH)     ; header windows are new each time
    return on
}

ToggleTips() {
    on := ApplyTipState()
    Status(on ? "Hover tips on." : "Hover tips off.")
}

ModeChanged() {
    isRepl := RT.rdReplace.Value
    RT.edRepl.Enabled := isRepl
    RT.edLimit.Enabled := isRepl
    RT.cbAll.Enabled := !isRepl
    if (isRepl)
        RT.tabs.Value := 2
    ScheduleRun()
}

; ============================== PLACEHOLDER TABLE =========================
PhAdd() {
    n := "re" (RT.PhNames.Length + 1)
    while RT.PhMap.Has(n)
        n .= "x"
    RT.PhNames.Push(n)
    RT.PhMap[n] := ""
    RefreshPhList()
    RT.lvPh.Modify(RT.PhNames.Length, "Select Focus Vis")
    PhRowFocused()
    RT.edPhName.Focus()
}

PhDelete() {
    row := RT.lvPh.GetNext()
    if !row
        return
    RT.PhMap.Delete(RT.PhNames[row])
    RT.PhNames.RemoveAt(row)
    RT.CurPh := 0
    RefreshPhList()
    RT.edPhName.Value := "", SetPhPatText("")
    ScheduleRun()
}

PhMove(delta) {
    row := RT.lvPh.GetNext()
    if (!row)
        return
    newRow := row + delta
    if (newRow < 1 || newRow > RT.PhNames.Length)
        return
    tmp := RT.PhNames[row]
    RT.PhNames[row] := RT.PhNames[newRow]
    RT.PhNames[newRow] := tmp
    RefreshPhList()
    RT.lvPh.Modify(newRow, "Select Focus Vis")
    RT.CurPh := newRow
    ScheduleRun()
}

PhRowFocused() {
    row := RT.lvPh.GetNext(, "F")
    if (!row)
        return
    RT.CurPh := row
    RT.Loading := true
    RT.edPhName.Value := RT.PhNames[row]
    SetPhPatText(RT.PhMap[RT.PhNames[row]])
    RT.Loading := false
    ; SetPhPatText() asks for a recolor, but RT.Loading was still set when it
    ; did, and SchedulePhPatColors() bails while loading -- that flag is here to
    ; stop the Change events these two assignments raise from being mistaken for
    ; user edits.  So the request was swallowed and the pattern sat in flat black
    ; until the first keystroke woke it up.  Ask again now the flag is clear.
    ; SetPatternText() never hits this because every one of its callers already
    ; re-schedules after clearing the flag.
    SchedulePhPatColors()
}

; Live edit of the selected row's name / pattern.
PhEdited() {
    if (RT.Loading || !RT.CurPh || RT.CurPh > RT.PhNames.Length)
        return
    oldName := RT.PhNames[RT.CurPh]
    newName := Trim(RT.edPhName.Value)
    newPat  := PhPatText()

    if (newName != oldName) {
        if (newName = "" || !RegExMatch(newName, "^[A-Za-z_]\w*$")) {
            Status("Placeholder name must be a valid AHK identifier — letters, digits and underscore, not starting with a digit.", true)
            return
        }
        if RT.PhMap.Has(newName) {
            Status("Placeholder name '" newName "' is already in use.", true)
            return
        }
        RT.PhMap.Delete(oldName)
        RT.PhNames[RT.CurPh] := newName
    }
    RT.PhMap[newName] := newPat
    RT.lvPh.Modify(RT.CurPh, "Col1", newName)
    RT.lvPh.Modify(RT.CurPh, "Col2", OneLine(newPat))
    ScheduleRun()
}

RefreshPhList() {
    RT.lvPh.Opt("-Redraw")
    RT.lvPh.Delete()
    for name in RT.PhNames
        RT.lvPh.Add(, name, OneLine(RT.PhMap[name]), "")
    RT.lvPh.Opt("+Redraw")
}

; Double-click a placeholder row: drop %name% in at the pattern box's caret.
InsertPhToken() {
    row := RT.lvPh.GetNext()
    if (!row)
        return
    tok := "%" RT.PhNames[row] "%"
    RT.rePattern.Focus()
    RT.rePattern.ReplaceSel(tok)
    SchedulePatternColors()
    ScheduleRun()
}

; ============================== PATTERN BOX ===============================
; The rich edit stores one CR per line break; swapping CR for LF is a 1:1
; character substitution, so offsets still line up with EM_EXSETSEL.
PatternText() {
    t := RT.rePattern.GetText()
    t := StrReplace(t, "`r`n", "`n")
    return StrReplace(t, "`r", "`n")
}

SetPatternText(txt) {
    RT.PatShading := true
    RT.rePattern.SetText(txt)
    RT.rePattern.SetSel(0, -1)
    RT.rePattern.SetFont({Name: SUBJ_FONT, Size: SUBJ_SIZE, Style: "N", Color: "Auto", BkColor: "Auto"})
    RT.rePattern.SetSel(0, 0)
    RT.PatShading := false
    RT.PatPairs := "", RT.PatHL := ""    ; the reset above cleared any highlight
    SuppressHScroll(RT.rePattern.Hwnd)   ; replacing the text re-asserts it
    SchedulePatternColors()
}

PatternChanged() {
    if (RT.PatShading)                       ; our own recoloring
        return
    if (PatternText() == RT.LastPatText)     ; formatting-only notification
        return
    ; Every offset in the pairing map just moved.  Drop it rather than let the
    ; caret highlight two arbitrary characters during the COLOR_DELAY window
    ; before ApplyPatternColors() rebuilds it.
    RT.PatPairs := "", RT.PatHL := ""
    SchedulePatternColors()
    ScheduleRun()
}

; Coloring is scheduled independently of ScheduleRun() so that the pattern
; box stays live even when the "Live" checkbox is off — it costs nothing,
; since it never runs the regex against the haystack.
SchedulePatternColors() {
    if (RT.Loading)
        return
    SetTimer(ApplyPatternColors, -COLOR_DELAY)
}

; ==========================================================================
;                        PATTERN SYNTAX COLORING
; ==========================================================================
; AnalyzePattern() is one left-to-right pass over the raw pattern.  It is first
; and foremost a HIGHLIGHTER -- anything it cannot classify keeps the default
; color rather than being called a mistake -- but it does flag the handful of
; constructs PCRE itself will not compile.  That division is the whole design
; rule: white-on-red means "this pattern will not run", never "this looks odd
; to me".  Anything merely unusual gets a color, not an accusation.
;
; Two consequences worth spelling out, because they look like omissions:
;
;   * A lone "]", a lone "}", and a "{" that is not quantifier-shaped are NOT
;     errors.  Outside a character class PCRE demotes all three to ordinary
;     literal characters.  They get PC_LITERAL, which says "that bracket is
;     not doing what it looks like" without pretending the pattern is broken.
;
;   * A quantifier is only called out when there is unambiguously nothing to
;     repeat -- at the very start, straight after "(", after "|", or after a
;     quantifier that has already been consumed.  \b* and ^* are left alone,
;     because PCRE accepts them and a false red is worse than a missed one.
;
; Returns {runs, pairs, parenFg}:
;   runs    -- array of {s, e, fg, bg, st}, zero-based and end-exclusive.
;              "" in fg, bg or st means "leave that attribute alone".  That is
;              what lets the pale tint over a character class survive while the
;              escapes inside it get their own foreground colors painted on
;              top, in a later run over the same characters.
;   pairs   -- Map of 0-based paren position -> its partner's position, filled
;              in both directions.  Drives the caret's matching-paren
;              highlight, and is the reason that feature can ignore an escaped
;              \( or a "(" sitting inside a character class.
;   parenFg -- Map of 0-based paren position -> the color it was painted, so
;              the highlight can be lifted again without re-running the pass.
; The three optional parameters exist for the Color Key window, which has to
; render each specimen the same way every time regardless of which option boxes
; happen to be ticked.  Left unset -- which is every call from the pattern box
; -- they fall through to the live controls, so ordinary coloring is unchanged.
AnalyzePattern(pat, xOpt?, jOpt?, phMap?) {
    runs := [], pairs := Map(), parenFg := Map(), openStack := []
    names := Map(), nameDefs := [], backrefs := [], litSpans := []
    capOpens := []                       ; "(" position of capture group N, in order
    names.CaseSense := true              ; PCRE subpattern names are case-sensitive
    depth := 0, capCount := 0
    lastAtom := false                    ; is there anything a quantifier could repeat?
    n := StrLen(pat), i := 1

    ; The x and J options change what is legal, so the coloring has to know
    ; about the checkboxes.  Guarded because a stray early call would otherwise
    ; die on an empty optBoxes map.
    xMode := IsSet(xOpt) ? xOpt : (RT.optBoxes.Has("x") ? RT.optBoxes["x"].Value : 0)
    jMode := IsSet(jOpt) ? jOpt : (RT.optBoxes.Has("J") ? RT.optBoxes["J"].Value : 0)

    if (!PAT_FULL_SYNTAX) {
        PushPlaceholders(pat, runs, phMap?)
        return {runs: runs, pairs: pairs, parenFg: parenFg, caps: []}
    }

    while (i <= n) {
        c := SubStr(pat, i, 1)

        ; --- whitespace the x option throws away ---------------------------
        ; lastAtom is deliberately NOT touched here: in "a *" the star still
        ; repeats the a, because the space is gone before PCRE ever sees it.
        if (xMode && (c = " " || c = "`t" || c = "`r" || c = "`n")) {
            if (PC_XWS_BG != "")
                runs.Push({s: i - 1, e: i, fg: "", bg: PC_XWS_BG, st: ""})
            i++
            continue
        }

        ; --- x-mode comment ------------------------------------------------
        if (xMode && c = "#") {
            e := InStr(pat, "`n", , i)
            e := e ? e - 1 : n
            runs.Push({s: i - 1, e: e, fg: PC_COMMENT, bg: "", st: ""})
            i := e + 1
            continue
        }

        ; --- \Q ... \E : everything between is literal ----------------------
        if (c = "\" && SubStr(pat, i + 1, 1) == "Q") {   ; == : see ScanEscape
            qS := i - 1
            q := InStr(pat, "\E", , i + 2)
            runs.Push({s: i - 1, e: i + 1, fg: PC_ESC, bg: "", st: ""})
            if (q) {
                if (q > i + 2)
                    runs.Push({s: i + 1, e: q - 1, fg: PC_ESCLIT, bg: "", st: ""})
                runs.Push({s: q - 1, e: q + 1, fg: PC_ESC, bg: "", st: ""})
                i := q + 2
            } else {                          ; unterminated \Q runs to the end
                if (n > i + 1)
                    runs.Push({s: i + 1, e: n, fg: PC_ESCLIT, bg: "", st: ""})
                i := n + 1
            }
            litSpans.Push({s: qS, e: i - 1})     ; the whole \Q...\E run
            lastAtom := true
            continue
        }

        ; --- every other escape ---------------------------------------------
        if (c = "\") {
            es := ScanEscape(pat, i, n, false)
            bad := (es.kind = "bad")
            runs.Push({s: i - 1, e: i - 1 + es.len,
                       fg: bad ? PC_BAD_FG : EscColor(es.kind),
                       bg: bad ? PC_BAD_BG : "", st: ""})
            if (es.kind = "backref" && es.ref != "")
                backrefs.Push({s: i - 1, e: i - 1 + es.len, ref: es.ref})
            ; \. and \( match one ordinary character, so they belong with the
            ; literal run either side of them.  That is what keeps Mr\. Smith
            ; reading as one tinted string instead of three.
            if (es.kind = "lit")
                litSpans.Push({s: i - 1, e: i - 1 + es.len})
            i += es.len
            lastAtom := true
            continue
        }

        ; --- character class -------------------------------------------------
        if (c = "[") {
            nxt := ScanClass(pat, i, n, runs)
            if (!nxt)                         ; unterminated; the rest is already red
                break
            i := nxt
            lastAtom := true
            continue
        }

        ; --- everything that starts with "(" ---------------------------------
        if (c = "(") {
            ; (*ACCEPT) (*SKIP:label) (*UTF) -- backtracking control verbs.
            ; Tested first because the old tokenizer read the "*" as a
            ; quantifier and let the "(" open a group that never closed, so a
            ; perfectly good verb produced a spurious unbalanced-paren error.
            if RegExMatch(pat, "A)\(\*[A-Za-z_]*(:[^)]*)?\)", &gm, i) {
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_SPECIAL, bg: "", st: ""})
                i += gm.Len
                lastAtom := true
                continue
            }
            ; (?#...) -- comment
            if RegExMatch(pat, "A)\(\?#[^)]*\)", &gm, i) {
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_COMMENT, bg: "", st: ""})
                i += gm.Len
                continue
            }
            ; (?i) (?-x) (?^im) -- an option SET, not a group: no depth change
            if RegExMatch(pat, "A)\(\?\^?[imsxJUXn]*(-[imsxJUXn]+)?\)", &gm, i) {
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_SPECIAL, bg: "", st: ""})
                i += gm.Len
                continue
            }
            ; (?C) (?C7) -- callout
            if RegExMatch(pat, "A)\(\?C\d*\)", &gm, i) {
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_SPECIAL, bg: "", st: ""})
                i += gm.Len
                continue
            }
            ; (?R) (?1) (?-2) (?&name) (?P>name) (?P=name) -- recursion and
            ; subroutine calls.  Complete tokens, so they open nothing.
            if RegExMatch(pat, "A)\(\?(P=(\w+)|P>(\w+)|&(\w+)|R|[+-]?\d+)\)", &gm, i) {
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_BACKREF, bg: "", st: ""})
                nm := gm[2] != "" ? gm[2] : (gm[3] != "" ? gm[3] : gm[4])
                if (nm != "")
                    backrefs.Push({s: i - 1, e: i - 1 + gm.Len, ref: nm})
                i += gm.Len
                lastAtom := true
                continue
            }
            ; (?(1)yes|no) (?(<name>)...) (?(DEFINE)...) -- conditional group.
            ; The whole condition is eaten as the opener so its ")" does not
            ; get counted as closing anything.  The (?(?=...)...) form is not
            ; matched here on purpose: it falls through to the generic "(?"
            ; branch below, which opens one group and lets the inner assertion
            ; open and close its own -- which comes out with the depth right.
            if RegExMatch(pat, "A)\(\?\((\d+|<\w+>|'\w+'|R\d*|R&\w+|DEFINE|[+-]\d+)\)", &gm, i) {
                col := ParenColor(depth)
                runs.Push({s: i - 1, e: i, fg: col, bg: "", st: ""})
                runs.Push({s: i, e: i - 1 + gm.Len, fg: PC_SPECIAL, bg: "", st: ""})
                parenFg[i - 1] := col
                openStack.Push(i - 1), depth++
                i += gm.Len
                lastAtom := false
                continue
            }

            if (SubStr(pat, i + 1, 1) = "?") {
                ; --- named capturing group: (?<name>  (?'name'  (?P<name> ----
                ; The bracket itself keeps the depth color so the group is
                ; still findable by shape; only the plumbing and the name get
                ; their own treatment.
                if RegExMatch(pat, "A)\(\?(P?<|')([A-Za-z_]\w*)(>|')", &gm, i) {
                    lead := 2 + StrLen(gm[1])          ; "(" + "?" + "<" / "P<" / "'"
                    nmS  := i - 1 + lead
                    nmE  := nmS + StrLen(gm[2])
                    col  := ParenColor(depth)
                    runs.Push({s: i - 1, e: i,  fg: col,       bg: "", st: ""})
                    runs.Push({s: i,     e: nmS, fg: PC_NONCAP, bg: "", st: ""})
                    runs.Push({s: nmS,   e: nmE, fg: PC_GNAME,  bg: "", st: "B"})
                    runs.Push({s: nmE, e: i - 1 + gm.Len, fg: PC_NONCAP, bg: "", st: ""})
                    parenFg[i - 1] := col
                    nameDefs.Push({s: nmS, e: nmE, name: gm[2]})
                    names[gm[2]] := names.Has(gm[2]) ? names[gm[2]] + 1 : 1
                    capCount++, capOpens.Push(i - 1)
                    openStack.Push(i - 1), depth++
                    i += gm.Len
                    lastAtom := false
                    continue
                }
                ; --- lookaround: (?=  (?!  (?<=  (?<! ------------------------
                ; Green, the same as ^ $ \b, because they are the same kind of
                ; thing: they assert about a position and consume nothing.
                ; (The \w+ in the test above cannot match "=" or "!", so a
                ; lookbehind can never be mistaken for a named group.)
                if RegExMatch(pat, "A)\(\?(<[=!]|[=!])", &gm, i) {
                    col := ParenColor(depth)
                    runs.Push({s: i - 1, e: i, fg: col, bg: "", st: ""})
                    runs.Push({s: i, e: i - 1 + gm.Len, fg: PC_ANCHOR, bg: "", st: ""})
                    parenFg[i - 1] := col
                    openStack.Push(i - 1), depth++
                    i += gm.Len
                    lastAtom := false
                    continue
                }
                ; --- (?:  (?i:  (?-x:  (?>  (?| ------------------------------
                ; Scoped option groups used to fall off the end of this chain
                ; and get two characters colored out of four.
                if RegExMatch(pat, "A)\(\?(\^?[imsxJUXn]*(-[imsxJUXn]+)?:|>|\|)", &gm, i) {
                    col := ParenColor(depth)
                    runs.Push({s: i - 1, e: i, fg: col, bg: "", st: ""})
                    runs.Push({s: i, e: i - 1 + gm.Len, fg: PC_NONCAP, bg: "", st: ""})
                    parenFg[i - 1] := col
                    openStack.Push(i - 1), depth++
                    i += gm.Len
                    lastAtom := false
                    continue
                }
                ; --- some "(?" form this tokenizer does not know -------------
                ; Opened as a plain group rather than flagged, so that one
                ; unrecognized construct cannot cascade into a string of
                ; bogus unbalanced-paren errors further along the pattern.
                col := ParenColor(depth)
                runs.Push({s: i - 1, e: i, fg: col, bg: "", st: ""})
                runs.Push({s: i, e: i + 1, fg: PC_SPECIAL, bg: "", st: ""})
                parenFg[i - 1] := col
                openStack.Push(i - 1), depth++
                i += 2
                lastAtom := false
                continue
            }

            ; --- plain capturing group -------------------------------------
            col := ParenColor(depth)
            runs.Push({s: i - 1, e: i, fg: col, bg: "", st: ""})
            parenFg[i - 1] := col
            capCount++, capOpens.Push(i - 1)
            openStack.Push(i - 1), depth++
            i++
            lastAtom := false
            continue
        }

        if (c = ")") {
            if (depth > 0) {
                depth--
                op  := openStack.Pop()
                col := ParenColor(depth)      ; same depth the opener was given
                runs.Push({s: i - 1, e: i, fg: col, bg: "", st: ""})
                parenFg[i - 1] := col
                pairs[op] := i - 1
                pairs[i - 1] := op
                lastAtom := true
            } else {
                runs.Push({s: i - 1, e: i, fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})
                lastAtom := false
            }
            i++
            continue
        }

        ; --- quantifiers, with their lazy / possessive suffix ---------------
        if (c = "*" || c = "+" || c = "?"
            || (c = "{" && RegExMatch(pat, "A)\{\d+(,\d*)?\}", &qm, i))) {
            qLen := (c = "{") ? qm.Len : 1
            if (!lastAtom) {
                ; PCRE: "quantifier does not follow a repeatable item"
                runs.Push({s: i - 1, e: i - 1 + qLen,
                           fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})
            } else {
                runs.Push({s: i - 1, e: i - 1 + qLen, fg: PC_QUANT, bg: "", st: ""})
                sfx := SubStr(pat, i + qLen, 1)
                if (sfx = "?" || sfx = "+") {  ; a?? is lazy, a?+ is possessive
                    runs.Push({s: i - 1 + qLen, e: i + qLen,
                               fg: PC_LAZY, bg: "", st: ""})
                    qLen++
                }
            }
            i += qLen
            lastAtom := false                  ; so a third ? in a??? is caught
            continue
        }

        ; --- the small fry ---------------------------------------------------
        if (c = "|") {
            runs.Push({s: i - 1, e: i, fg: PC_ALT, bg: "", st: ""})
            lastAtom := false
        } else if (c = "^" || c = "$") {
            runs.Push({s: i - 1, e: i, fg: PC_ANCHOR, bg: "", st: ""})
            lastAtom := true
        } else if (c = ".") {
            runs.Push({s: i - 1, e: i, fg: PC_DOT, bg: "", st: ""})
            lastAtom := true
        } else if (c = "]" || c = "}" || c = "{") {
            ; Legal, and literal.  See the note at the top of this function.
            runs.Push({s: i - 1, e: i, fg: PC_LITERAL, bg: "", st: ""})
            litSpans.Push({s: i - 1, e: i})
            lastAtom := true
        } else {
            litSpans.Push({s: i - 1, e: i})
            lastAtom := true
        }
        i++
    }

    ; --- text the pattern matches literally --------------------------------
    ; Collected during the pass and merged here rather than pushed a character
    ; at a time: a 300-character literal would otherwise mean 300 SetSel and
    ; SetFont round trips instead of one.  Merging is also what makes the tint
    ; read as words rather than as a row of separate blocks.
    ;
    ; A background rather than a foreground, because literals are usually the
    ; majority of a pattern -- recoloring them would repaint most of the box
    ; and cost black, which is the most readable color available for the part
    ; you most want to read.  A wash behind them groups without shouting.
    ;
    ; Pushed BEFORE the error runs below so nothing dilutes a red mark, and
    ; before the placeholders, whose own background wins over this one.  Runs
    ; inside a character class never get here, so a class keeps its own tint.
    if (litSpans.Length) {
        cs := litSpans[1].s, ce := litSpans[1].e
        loop litSpans.Length - 1 {
            nx := litSpans[A_Index + 1]
            if (nx.s = ce) {                     ; touching the previous one
                ce := nx.e
                continue
            }
            runs.Push({s: cs, e: ce, fg: "", bg: PC_LIT_BG, st: ""})
            cs := nx.s, ce := nx.e
        }
        runs.Push({s: cs, e: ce, fg: "", bg: PC_LIT_BG, st: ""})
    }

    ; --- "(" that never closed.  Pushed after the loop so they paint over the
    ; --- depth color the opener already got.
    for openPos in openStack
        runs.Push({s: openPos, e: openPos + 1, fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})

    ; --- references to groups that do not exist ---------------------------
    ; Checked at the end rather than in line, because PCRE allows a forward
    ; reference: \2 may legitimately appear before group 2 is defined.
    for br in backrefs {
        if (br.ref ~= "^\d+$") {
            v := Integer(br.ref)
            if (v > 0 && v <= capCount)
                continue                       ; a real backreference
            ; A SINGLE digit is always a backreference to PCRE, so \3 with two
            ; groups is a hard error.  Two or more digits fall back to being an
            ; octal code point when the number is too big to be a group and the
            ; digits allow it -- \12 in a pattern with no groups is chr(0o12).
            if (StrLen(br.ref) > 1 && br.ref ~= "^[0-7]+$") {
                runs.Push({s: br.s, e: br.e, fg: PC_ESCNUM, bg: "", st: ""})
                continue
            }
            runs.Push({s: br.s, e: br.e, fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})
            continue
        }
        if (br.ref ~= "^[+-]")                 ; relative: not worth resolving
            continue
        if (!names.Has(br.ref))
            runs.Push({s: br.s, e: br.e, fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})
    }

    ; --- two subpatterns with the same name -------------------------------
    ; PCRE refuses this outright unless DUPNAMES is on, which is the J option.
    ; Worth having: the big HotstringHelper pattern defines (?<Repl>...) twice
    ; and simply will not compile with J unticked, which is a much better
    ; thing to see under the name than to read in the status bar.
    if (!jMode) {
        for d in nameDefs
            if (names[d.name] > 1)
                runs.Push({s: d.s, e: d.e, fg: PC_BAD_FG, bg: PC_BAD_BG, st: "B"})
    }

    PushPlaceholders(pat, runs, phMap?)

    ; --- capture group N -> the span of pattern text that defines it --------
    ; capOpens holds the "(" of every capturing group in encounter order,
    ; which is exactly PCRE's numbering, and pairs already knows where each
    ; one closes.  Zero-based, end-exclusive, same convention as runs.  A
    ; group whose ")" is missing is given a one-character span so an
    ; unbalanced pattern still highlights something rather than throwing.
    caps := []
    for op in capOpens
        caps.Push({s: op, e: (pairs.Has(op) ? pairs[op] + 1 : op + 1)})

    return {runs: runs, pairs: pairs, parenFg: parenFg, caps: caps}
}

ParenColor(depth) => PC_PAREN[Mod(depth, PC_PAREN.Length) + 1]

EscColor(kind) {
    switch kind {
        case "assert":  return PC_ANCHOR       ; \b \A \z -- a position, like ^
        case "class":   return PC_ESC          ; \d \w \p{L} -- a character
        case "num":     return PC_ESCNUM       ; \x41 \t -- a specific code point
        case "lit":     return PC_ESCLIT       ; \. \( -- just that character
        case "backref": return PC_BACKREF
        case "bad":     return PC_BAD_FG
    }
    return PC_ESC
}

; %name% is painted LAST, over whatever else laid claim to those characters,
; and it scans the whole pattern with the identical regex ExpandText() uses.
;
; That is the point of doing it this way.  The old tokenizer handled "%" inline
; and swallowed a character class in one bite, so [%vowels%] got no placeholder
; color -- while ExpandText(), which just scans the raw string, substituted it
; regardless.  Highlighting and expansion disagreed.  Now they cannot: the same
; expression at the same offsets decides both, so what is tinted is exactly
; what gets swapped in, inside classes and (?#comments) included.
PushPlaceholders(pat, runs, phMap?) {
    if (!IsSet(phMap)) {
        if (!PhOn())
            return
        phMap := RT.PhMap
    }
    pos := 1
    while (fp := RegExMatch(pat, "%([A-Za-z_]\w*)%", &pm, pos)) {
        known := phMap.Has(pm[1])
        runs.Push({s: fp - 1, e: fp - 1 + pm.Len,
                   fg: known ? PC_PH_FG : PC_BADPH_FG,
                   bg: known ? PC_PH_BG : PC_BADPH_BG, st: "N"})
        pos := fp + pm.Len
    }
}

; Classifies the escape starting at the backslash at 1-based position i.
; Returns {len, kind, ref}; 'ref' is filled in only for backreferences.
;   assert   \b \B \A \Z \z \G \K              a position
;   class    \d \w \s \h \v \R \N \X \C \p{}   a character
;   num      \x41 \x{263A} \o{17} \cA \012 \t  a specific code point
;   lit      \. \( \\                          a metacharacter made ordinary
;   backref  \1 \g{2} \k<name>                 a reference
;   quote    \Q          endq  \E
;   bad      PCRE will not compile this
;
; The 'inClass' flag is not a detail: inside a character class \b means
; backspace rather than word boundary, and \A \z \R \X \C \N and the
; backreference forms are outright errors.  Getting that wrong in either
; direction produces a red mark on a working pattern.
ScanEscape(pat, i, n, inClass) {
    ; EVERY letter test below uses == rather than =, and must keep doing so.
    ; AHK's = compares case-INSENSITIVELY, so c = "g" is also true for "G" --
    ; which sent \G and \K down the \g{name} backreference branch, found no
    ; brace or angle after them, and reported two perfectly good assertions as
    ; errors.  The same trap was waiting for \X (caught by the \x hex test),
    ; \C (caught by \cA, swallowing the following character), \q (caught by
    ; \Q) and \e (caught by \E).
    static valid := "ABCDEGHKNPQRSVWXZabcdefghknoprstvwxz"
    if (i >= n)                                ; trailing lone backslash
        return {len: 1, kind: "bad", ref: ""}
    c := SubStr(pat, i + 1, 1)

    if (c == "Q")
        return {len: 2, kind: "quote", ref: ""}
    if (c == "E")
        return {len: 2, kind: "endq", ref: ""}

    ; --- \x41  \x{263A} ---------------------------------------------------
    if (c == "x") {
        if (SubStr(pat, i + 2, 1) = "{") {
            cl := InStr(pat, "}", , i + 2)
            if (!cl)
                return {len: 2, kind: "bad", ref: ""}
            return {len: cl - i + 1, kind: "num", ref: ""}
        }
        RegExMatch(pat, "A)\\x[0-9A-Fa-f]{0,2}", &m, i)   ; bare \x is a valid NUL
        return {len: m.Len, kind: "num", ref: ""}
    }

    ; --- \o{17} -----------------------------------------------------------
    if (c == "o") {
        if (SubStr(pat, i + 2, 1) != "{")
            return {len: 2, kind: "bad", ref: ""}
        cl := InStr(pat, "}", , i + 2)
        if (!cl)
            return {len: 2, kind: "bad", ref: ""}
        return {len: cl - i + 1, kind: "num", ref: ""}
    }

    ; --- \cA --------------------------------------------------------------
    if (c == "c") {
        if (i + 2 > n)
            return {len: 2, kind: "bad", ref: ""}
        return {len: 3, kind: "num", ref: ""}
    }

    ; --- \p{L}  \P{^Lu}  \pL ----------------------------------------------
    if (c == "p" || c == "P") {
        if (SubStr(pat, i + 2, 1) = "{") {
            cl := InStr(pat, "}", , i + 2)
            if (!cl)
                return {len: 2, kind: "bad", ref: ""}
            return {len: cl - i + 1, kind: "class", ref: ""}
        }
        if RegExMatch(pat, "A)\\[pP][A-Za-z]", &m, i)
            return {len: 3, kind: "class", ref: ""}
        return {len: 2, kind: "bad", ref: ""}
    }

    ; --- digits: octal, or a backreference --------------------------------
    ; Whether \12 is group 12 or the character 0o12 depends on how many groups
    ; the pattern actually has, which is not known yet.  All the digits are
    ; taken here and the decision is deferred to the end of AnalyzePattern().
    if (InStr("0123456789", c, true)) {
        RegExMatch(pat, "A)\\\d+", &m, i)
        digits := SubStr(m[0], 2)
        if (c = "0" || inClass)                ; unambiguously octal in both cases
            return {len: m.Len, kind: (digits ~= "^[0-7]+$") ? "num" : "bad", ref: ""}
        return {len: m.Len, kind: "backref", ref: digits}
    }

    ; --- \g1  \g{2}  \g{-1}  \g<name>  \k<name>  \k{name} -----------------
    if (c == "g" || c == "k") {
        if (inClass)
            return {len: 2, kind: "bad", ref: ""}
        if RegExMatch(pat, "A)\\[gk](\{[+-]?\w+\}|<[+-]?\w+>|'[+-]?\w+'|[+-]?\d+)", &m, i)
            return {len: m.Len, kind: "backref", ref: Trim(m[1], "{}<>'")}
        return {len: 2, kind: "bad", ref: ""}
    }

    ; --- position assertions ----------------------------------------------
    if (!inClass && InStr("bBAZzGK", c, true))
        return {len: 2, kind: "assert", ref: ""}
    if (inClass && c == "b")                    ; inside a class, \b is backspace
        return {len: 2, kind: "num", ref: ""}

    ; --- escapes that match a character -----------------------------------
    if (InStr("dDwWsShHvV", c, true))
        return {len: 2, kind: "class", ref: ""}
    if (!inClass && InStr("RNXC", c, true))
        return {len: 2, kind: "class", ref: ""}

    ; --- control characters written by name -------------------------------
    if (InStr("nrtfae", c, true))
        return {len: 2, kind: "num", ref: ""}

    ; --- escaping a non-alphanumeric is always legal and always literal ----
    if !(c ~= "[A-Za-z0-9]")
        return {len: 2, kind: "lit", ref: ""}

    ; --- a letter with no meaning: PCRE says "unrecognized character follows \"
    if (inClass)
        return {len: 2, kind: "bad", ref: ""}
    return {len: 2, kind: InStr(valid, c, true) ? "class" : "bad", ref: ""}
}

; Walks the character class beginning at the "[" at 1-based position i, pushing
; its runs.  Returns the 1-based position just past the closing "]", or 0 if it
; is never closed -- which, unlike a stray "]", really is a compile error.
;
; The class gets a pale background across its whole span and then has its
; contents painted on top, so it still reads as one object while \d, [:alpha:]
; and the range hyphens keep the same colors they have everywhere else.
ScanClass(pat, i, n, runs) {
    static posix := "alpha,alnum,ascii,blank,cntrl,digit,graph,lower,print,"
                  . "punct,space,upper,word,xdigit"
    j := i + 1
    neg := (SubStr(pat, j, 1) = "^")
    if (neg)
        j++

    ; Find the closing bracket first, so an unterminated class can be marked in
    ; one piece.  A "]" in the very first position is a member, not the end.
    k := j
    if (SubStr(pat, k, 1) = "]")
        k++
    while (k <= n) {
        ch := SubStr(pat, k, 1)
        if (ch = "\") {
            k += 2
            continue
        }
        if (ch = "[" && SubStr(pat, k + 1, 1) = ":") {
            if (cl := InStr(pat, ":]", , k + 2)) {
                k := cl + 2
                continue
            }
        }
        if (ch = "]")
            break
        k++
    }
    if (k > n) {
        runs.Push({s: i - 1, e: n, fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})
        return 0
    }

    runs.Push({s: i - 1, e: k,     fg: "",       bg: PC_CLASS_BG, st: ""})
    runs.Push({s: i - 1, e: i,     fg: PC_CLASS, bg: "", st: ""})      ; [
    if (neg)
        runs.Push({s: i, e: i + 1, fg: PC_CLASS, bg: "", st: ""})      ; ^
    runs.Push({s: k - 1, e: k,     fg: PC_CLASS, bg: "", st: ""})      ; ]

    p := j
    prevLit := ""            ; code point of the previous single-character member
    prevEnd := 0             ; and where it ended, so "-" can tell range from dash
    if (SubStr(pat, p, 1) = "]") {                    ; the leading literal "]"
        runs.Push({s: p - 1, e: p, fg: PC_LITERAL, bg: "", st: ""})
        prevLit := Ord("]"), prevEnd := p
        p++
    }
    while (p < k) {
        ch := SubStr(pat, p, 1)

        if (ch = "\") {
            es  := ScanEscape(pat, p, n, true)
            bad := (es.kind = "bad")
            runs.Push({s: p - 1, e: p - 1 + es.len,
                       fg: bad ? PC_BAD_FG : EscColor(es.kind),
                       bg: bad ? PC_BAD_BG : "", st: ""})
            prevLit := "", prevEnd := p - 1 + es.len
            p += es.len
            continue
        }

        if (ch = "[" && SubStr(pat, p + 1, 1) = ":") {
            cl := InStr(pat, ":]", , p + 2)
            if (cl && cl < k) {
                nm := LTrim(SubStr(pat, p + 2, cl - p - 2), "^")
                ok := InStr("," posix ",", "," nm ",", true)
                runs.Push({s: p - 1, e: cl + 1,
                           fg: ok ? PC_POSIX : PC_BAD_FG,
                           bg: ok ? "" : PC_BAD_BG, st: ""})
                prevLit := "", prevEnd := cl + 1
                p := cl + 2
                continue
            }
        }

        ; A "-" is a range operator only between two members.  First or last in
        ; the class it is an ordinary hyphen, and so is the one in [a-z-x],
        ; which is why prevEnd is cleared after a range rather than moved on.
        if (ch = "-" && prevEnd = p - 1 && p + 1 < k) {
            hiPos := p + 1, hiLen := 1, hiOrd := "", hiFg := ""
            hc := SubStr(pat, hiPos, 1)
            if (hc = "\") {
                es := ScanEscape(pat, hiPos, n, true)
                hiLen := es.len
                hiFg  := (es.kind = "bad") ? PC_BAD_FG : EscColor(es.kind)
            } else {
                hiOrd := Ord(hc)
            }
            bad := (prevLit != "" && hiOrd != "" && hiOrd < prevLit)   ; [z-a]
            runs.Push({s: p - 1, e: p, fg: bad ? PC_BAD_FG : PC_RANGE,
                       bg: bad ? PC_BAD_BG : "", st: ""})
            if (bad)
                runs.Push({s: hiPos - 1, e: hiPos - 1 + hiLen,
                           fg: PC_BAD_FG, bg: PC_BAD_BG, st: ""})
            else if (hiFg != "")
                runs.Push({s: hiPos - 1, e: hiPos - 1 + hiLen,
                           fg: hiFg, bg: "", st: ""})
            prevLit := "", prevEnd := 0
            p := hiPos + hiLen
            continue
        }
        if (ch = "-")
            runs.Push({s: p - 1, e: p, fg: PC_LITERAL, bg: "", st: ""})

        prevLit := (ch = "-") ? "" : Ord(ch)
        prevEnd := p
        p++
    }
    return k + 1
}

ApplyPatternColors(*) {
    SetTimer(ApplyPatternColors, 0)
    if (!RT.rePattern)
        return
    ; Recoloring has to save and restore the selection, and doing that in the
    ; middle of a click-drag cancels the drag.  Wait until the button is up.
    if (GetKeyState("LButton", "P")) {
        SetTimer(ApplyPatternColors, -COLOR_DELAY)
        return
    }
    RE := RT.rePattern
    pat := PatternText()
    RT.LastPatText := pat

    info := AnalyzePattern(pat)

    RT.PatShading := true
    sel := RE.GetSel()
    scr := RE.GetScrollPos()
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)

    RE.SetSel(0, -1)
    RE.SetFont({Style: "N", Color: "Auto", BkColor: "Auto"})

    ApplyRuns(RE, info.runs)

    RE.SetSel(sel.S, sel.E)
    RE.SetScrollPos(scr.X, scr.Y)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("InvalidateRect", "Ptr", RE.Hwnd, "Ptr", 0, "Int", 1)
    RT.PatShading := false

    ; The wholesale repaint above wiped any pair highlight, so drop the record
    ; of it and let the caret's current position put one back.
    RT.PatPairs   := info.pairs
    RT.PatParenFg := info.parenFg
    RT.PatHL      := ""
    UpdateParenMatch()
}

; ---------------------- MATCHING PAREN HIGHLIGHT --------------------------
; With the caret beside a structural "(" or ")", that bracket and its partner
; both get a background block, so the extent of a group is readable at a glance
; even in a 200-character pattern.
;
; "Structural" is the whole trick.  The pairing is whatever AnalyzePattern()
; worked out, so an escaped \( , a "(" sitting inside a character class, and
; the "(" of a (?i) option set -- which opens nothing -- are all correctly
; passed over.  A naive bracket-counting scan gets every one of those wrong,
; which is why this is worth deriving from the parse rather than doing on the
; raw text.
;
; Only two characters are repainted, never the whole box: a full recolor on
; every caret movement would be visible as a flicker.  The color to put back
; comes from RT.PatParenFg, recorded during the same pass that did the pairing,
; which is also why RT.PatPairs is cleared the moment the text changes -- a
; stale map would happily highlight the wrong two characters during the
; COLOR_DELAY window before the recolor catches up.
UpdateParenMatch(*) {
    SetTimer(UpdateParenMatch, 0)
    if (!RT.rePattern || RT.PatShading || RT.ParenBusy)
        return
    if (!IsObject(RT.PatPairs))                ; no parse yet, or text just changed
        return
    RE := RT.rePattern
    if (GetKeyState("LButton", "P")) {         ; same click-drag hazard as above
        SetTimer(UpdateParenMatch, -80)
        return
    }

    sel  := RE.GetSel()
    want := ""
    if (sel.S = sel.E) {                       ; a selection, not a caret: no pair
        if (RT.PatPairs.Has(sel.S - 1))        ; prefer the bracket just behind
            want := sel.S - 1
        else if (RT.PatPairs.Has(sel.S))
            want := sel.S
    }
    if (want = "") {
        if (!IsObject(RT.PatHL))
            return                             ; nothing lit, nothing to light
    } else if (IsObject(RT.PatHL) && (RT.PatHL[1] = want || RT.PatHL[2] = want))
        return                                 ; already showing this very pair

    RT.ParenBusy := true
    scr := RE.GetScrollPos()
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)

    if (IsObject(RT.PatHL)) {
        for p in RT.PatHL
            PaintParenAt(RE, p, RT.PatParenFg.Has(p) ? RT.PatParenFg[p] : "Auto",
                         "Auto", "N")
        RT.PatHL := ""
    }
    if (want != "") {
        q := RT.PatPairs[want]
        for p in [want, q]
            PaintParenAt(RE, p, RT.PatParenFg.Has(p) ? RT.PatParenFg[p] : "Auto",
                         PC_PARMATCH_BG, "B")
        RT.PatHL := [want, q]
    }

    RE.SetSel(sel.S, sel.E)
    RE.SetScrollPos(scr.X, scr.Y)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("InvalidateRect", "Ptr", RE.Hwnd, "Ptr", 0, "Int", 1)
    RT.ParenBusy := false
}

; Runs are applied in the order they were pushed, and later ones deliberately
; overpaint earlier ones -- that is how the class tint ends up underneath its
; own contents, and how %placeholders% win over everything.  A run only sets the
; attributes it actually names, so overpainting a color does not disturb a
; background laid down earlier.
;
; 'off' shifts every run along by a fixed number of characters, which is what
; lets the Color Key window paste a specimen into the middle of a much longer
; block of text and still color it with the real tokenizer.
ApplyRuns(RE, runs, off := 0) {
    for r in runs {
        RE.SetSel(off + r.s, off + r.e)
        f := {}
        if (r.fg != "")
            f.Color := r.fg
        if (r.bg != "")
            f.BkColor := r.bg
        if (r.st != "")
            f.Style := r.st
        if ObjOwnPropCount(f)
            RE.SetFont(f)
    }
}

PaintParenAt(RE, pos, fg, bg, st) {
    RE.SetSel(pos, pos + 1)
    RE.SetFont({Color: fg, BkColor: bg, Style: st})
}

; ============================== COLOR KEY =================================
; A legend for the pattern box, in a window of its own.
;
; The Cheat Sheet tab is a plain Edit control, so it can only ever DESCRIBE the
; colors in words -- and "royal blue means a reference to a group" is no use
; whatever to someone who cannot see royal blue.  Hence a second window with a
; rich edit in it, showing each rule rendered exactly as the pattern box would
; render it.
;
; The important part is that nothing here is hand-colored.  Each row carries a
; specimen pattern, that specimen is put through the real AnalyzePattern(), and
; the runs it returns are pasted in at the specimen's offset by ApplyRuns().
; The legend is therefore generated BY the highlighter rather than written to
; describe it, and the two cannot drift apart: change a color or a rule and
; this window follows on its own.  A row that stops looking right here is a
; genuine bug in the tokenizer, not a stale piece of documentation.
;
; That is also why AnalyzePattern() takes the x, J and placeholder overrides.
; Several rows only demonstrate anything under a particular setting -- the
; discarded-whitespace row needs x on, the duplicate-name row needs J off --
; and the legend has to look the same whatever the option boxes happen to say.
ColorKeyRows() {
    ; {h: heading}  |  {d: ""} blank spacer  |  {p: specimen, d: what it shows}
    ; x, j and ph are per-row overrides handed straight to AnalyzePattern.
    return [
      {h: "TEXT MATCHED LITERALLY"},
      {p: "Mon|Tue(s)?|Wed",     d: "tinted in runs, so the words read as words"},
      {p: "Mr\. Smith",          d: "an escaped metacharacter joins the run"},
      {p: "a b",                 d: "a literal space, invisible in plain black"},
      {d: ""},
      {h: "STRUCTURE"},
      {p: "(cat(dog(bird)))",     d: "nesting depth, cycling through three colors"},
      {p: "(?:x) (?>x) (?|x)",    d: "non-capturing, atomic, branch reset"},
      {p: "(?<year>\d{4})",       d: "a named group; the name itself is picked out"},
      {p: "(?i) (?-x) (*SKIP)",   d: "directives that change how the rest is read"},
      {p: "(?#a note)",           d: "a comment inside the pattern"},
      {d: ""},
      {h: "MATCHING A POSITION, CONSUMING NOTHING"},
      {p: "^ $ \b \B \A \Z \z \G \K",   d: "anchors and boundaries"},
      {p: "(?=x) (?!x) (?<=x) (?<!x)",  d: "lookaround: same green, same idea"},
      {d: ""},
      {h: "MATCHING A CHARACTER"},
      {p: "\d \w \s \h \v \R \N \p{L}", d: "one character of a kind"},
      {p: "\t \n \x41 \x{263A} \cA",    d: "one specific code point"},
      {p: "\. \( \\ \+",                d: "a metacharacter made ordinary"},
      {p: ".",                          d: "any character except a line break"},
      {d: ""},
      {h: "CHARACTER CLASSES, TINTED ACROSS THE WHOLE [...]"},
      {p: "[a-z0-9_]",            d: "a range, and ordinary members"},
      {p: "[^\d[:punct:]]",       d: "negation and POSIX names; escapes keep theirs"},
      {d: ""},
      {h: "REPETITION AND CHOICE"},
      {p: "a* b+ c? d{2,5}",      d: "greedy quantifiers"},
      {p: "a*? b++ c{2,5}?",      d: "the ? or + that makes one lazy or possessive"},
      {p: "cat|dog",              d: "alternation"},
      {d: ""},
      {h: "REFERRING BACK TO A GROUP"},
      {p: "(a)\1 (?<n>x)\k<n> (?&n)",   d: "backreferences and subroutine calls"},
      {d: ""},
      {h: "LOOKS SPECIAL, IS NOT"},
      {p: "a] b} c{d",            d: "PCRE reads all three as ordinary characters"},
      {p: "a b # note", x: 1,     d: "with x ticked, discarded space and a comment"},
      {d: ""},
      {h: "PLACEHOLDERS, THIS TESTER ONLY"},
      {p: "%reMonth%", ph: Map("reMonth", 1), d: "resolves to a row in the table above"},
      {p: "%reMnoth%", ph: Map("reMonth", 1), d: "does not; it is matched as literal text"},
      {d: ""},
      {h: "WILL NOT COMPILE, AND ONLY EVER THIS"},
      {p: "(a",                   d: "a ( with no ), or a ) with no ("},
      {p: "[abc",                 d: "a character class that is never closed"},
      {p: "\q",                   d: "a backslash-letter with no meaning"},
      {p: "*a",                   d: "a quantifier with nothing to repeat"},
      {p: "[z-a]",                d: "a range whose ends are the wrong way round"},
      {p: "(?<n>a)(?<n>b)",       d: "two groups sharing a name, with J unticked"},
      {p: "(a)\3",                d: "a reference to a group that does not exist"}
    ]
}

ShowColorKey(*) {
    static COL := 32                 ; column the descriptions start in
    static DESC_FG := 0x606060       ; muted, so the specimens are what you read
    static SPACES := "                                                  "

    if (RT.keyGui) {                 ; already built: just bring it back
        RT.keyGui.Show()
        return
    }

    ; --- lay the text out first, remembering where each specimen landed ---
    rows := ColorKeyRows()
    txt := "", specimens := [], heads := []
    for r in rows {
        if (!r.HasOwnProp("p")) {
            if (r.HasOwnProp("h"))
                heads.Push({off: StrLen(txt), len: StrLen(r.h)}), txt .= r.h
            txt .= "`n"
            continue
        }
        specimens.Push({off: StrLen(txt), row: r})
        txt .= r.p SubStr(SPACES, 1, Max(2, COL - StrLen(r.p))) r.d "`n"
    }

    g := Gui("+Resize +MinSize520x260", "Pattern Box Color Key")
    g.MarginX := 10, g.MarginY := 10
    g.BackColor := "FFFFFF"

    ; Sized from the content that is actually there rather than from a guess,
    ; then clamped so the window can never open taller than the screen.
    maxLen := 0
    for line in StrSplit(txt, "`n")
        maxLen := Max(maxLen, StrLen(line))
    wantW := Integer((maxLen + 3) * SUBJ_SIZE * 0.80)
    wantH := Min(A_ScreenHeight - 200,
                 Integer(StrSplit(txt, "`n").Length * SUBJ_SIZE * 1.7) + 30)

    RE := RichEdit(g, "x10 y10 w" wantW " h" wantH)
    RE.SetDefaultFont({Name: SUBJ_FONT, Size: SUBJ_SIZE})
    RE.WordWrap(false)               ; a wrapped specimen would be unreadable
    RE.SetText(txt)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x00CF, "Ptr", 1, "Ptr", 0) ; EM_SETREADONLY
    RT.keyRE := RE

    FontUI(g)
    btn := g.Add("Button", "x10 y" (wantH + 18) " w90 h24 Default", "Close")
    btn.OnEvent("Click", (*) => RT.keyGui.Hide())
    RT.keyBtn := btn

    g.OnEvent("Close", (*) => RT.keyGui.Hide())
    g.OnEvent("Escape", (*) => RT.keyGui.Hide())
    g.OnEvent("Size", OnSizeKeyGui)

    ; --- three passes, coarse to fine ---------------------------------------
    ; Everything goes gray, then each specimen is reset to the pattern box's own
    ; default, then the tokenizer's runs go on top.  Painting the reset first is
    ; what keeps a specimen's ordinary literal characters black instead of
    ; leaving them in the description color.
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    RE.SetSel(0, -1)
    RE.SetFont({Style: "N", Color: DESC_FG, BkColor: "Auto"})
    for h in heads {
        RE.SetSel(h.off, h.off + h.len)
        RE.SetFont({Style: "B", Color: 0x202020})
    }
    for sp in specimens {
        r := sp.row
        RE.SetSel(sp.off, sp.off + StrLen(r.p))
        RE.SetFont({Style: "N", Color: "Auto"})
        info := AnalyzePattern(r.p,
                               r.HasOwnProp("x")  ? r.x  : 0,
                               r.HasOwnProp("j")  ? r.j  : 0,
                               r.HasOwnProp("ph") ? r.ph : Map())
        ApplyRuns(RE, info.runs, sp.off)
    }
    RE.SetSel(0, 0)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("InvalidateRect", "Ptr", RE.Hwnd, "Ptr", 0, "Int", 1)

    ; Published only now that it is fully built, so a failure part way through
    ; cannot leave the early-return above handing back a half-made window.
    RT.keyGui := g
    g.Show("AutoSize")
}

OnSizeKeyGui(guiObj, MinMax, W, H) {
    if (MinMax = -1 || !RT.keyRE)
        return
    RT.keyRE.Move(10, 10, W - 20, H - 54)
    RT.keyBtn.Move(10, H - 34, 90, 24)
}

; ============================== SNIPPETS ==================================
; Called snippets rather than history because nothing lands here on its own:
; a pattern is banked only when you press "Add Snippet".  A history that has
; to be filled in by hand is not a history, and the old name kept promising a
; record of what had been tried, which this list has never been.
;
; The pattern you are currently working on is saved with the session quite
; separately, so it survives a restart whether or not you ever bank it.
AddCurrentSnippet() {
    pat := PatternText()
    if (pat = "") {
        Status("Nothing to add — the pattern box is empty.")
        return
    }
    if (AddSnippet(pat))
        Status("Added as snippet " RT.Snippets.Length " of " MAX_SNIPPETS ".")
    else
        Status("That pattern was already saved; moved it to the top.")
    RT.rePattern.Focus()
}

; Returns true when the pattern was new, false when it was already present.
AddSnippet(pat) {
    if (pat = "")
        return false
    for i, h in RT.Snippets {
        if (h == pat) {                            ; already known -> promote it
            RT.Snippets.RemoveAt(i)
            RT.Snippets.InsertAt(1, pat)
            return false
        }
    }
    RT.Snippets.InsertAt(1, pat)
    while (RT.Snippets.Length > MAX_SNIPPETS)
        RT.Snippets.Pop()
    return true
}

ShowSnippetMenu() {
    mh := Menu()
    if (!RT.Snippets.Length) {
        mh.Add("(nothing saved yet — use Add Snippet)", (*) => 0)
        mh.Disable("(nothing saved yet — use Add Snippet)")
    } else {
        for i, h in RT.Snippets {
            label := OneLine(h)
            if (StrLen(label) > 88)
                label := SubStr(label, 1, 88) Chr(0x2026)
            ; & is the menu accelerator marker, and the index keeps every
            ; label unique even when two entries truncate to the same text.
            mh.Add(i ".  " StrReplace(label, "&", "&&"), SnippetPick.Bind(i))
        }
        mh.Add()
        mh.Add("Remove the entry I pick next", (*) => (RT.SnipDelete := true, ShowSnippetMenu()))
        mh.Add("Clear all snippets", (*) => ClearSnippets())
    }
    mh.Show()
}

SnippetPick(idx, *) {
    if (idx > RT.Snippets.Length)
        return
    if (RT.SnipDelete) {
        RT.SnipDelete := false
        RT.Snippets.RemoveAt(idx)
        Status("Removed that snippet.")
        return
    }
    SetPatternText(RT.Snippets[idx])
    RunTest()
    RT.rePattern.Focus()
}

ClearSnippets() {
    RT.Snippets := []
    Status("All snippets cleared.")
}

; ============================== EXPANSION =================================
; Walk a pattern, replacing %name% with the (recursively expanded) placeholder.
; Unknown names are left alone and collected into 'unknown' for reporting.
ExpandText(pat, visiting, unknown, wrap := false) {
    ; Support off: %name% is not a reference at all, just literal text, exactly
    ; as an ordinary regex tester would treat it.  Returning early rather than
    ; looking the names up in an empty map matters — the miss path would file
    ; every %name% as an UNDEFINED placeholder and warn about it.
    if !PhOn()
        return pat
    out := "", chunkStart := 1, pos := 1
    while (fp := RegExMatch(pat, "%([A-Za-z_]\w*)%", &m, pos)) {
        name := m[1]
        if RT.PhMap.Has(name) {
            if visiting.Has(name)
                throw Error("Circular placeholder reference: %" name "%")
            out .= SubStr(pat, chunkStart, fp - chunkStart)
            visiting[name] := true
            inner := ExpandText(RT.PhMap[name], visiting, unknown, wrap)
            out .= wrap ? "(?:" inner ")" : inner
            visiting.Delete(name)
            chunkStart := fp + m.Len
        } else {
            unknown[name] := true
        }
        pos := fp + m.Len
    }
    return out . SubStr(pat, chunkStart)
}

; Break a pattern into alternating literal / placeholder-reference pieces.
SplitRefs(pat) {
    ; One literal chunk when support is off.  This single gate is what also
    ; disables the generated variable declarations (via CollectDeps) and the
    ; top-level-| hazard analysis (via AltHazards) — both reach placeholders
    ; only through here.
    if !PhOn()
        return [{t: "lit", v: pat}]
    res := [], chunkStart := 1, pos := 1
    while (fp := RegExMatch(pat, "%([A-Za-z_]\w*)%", &m, pos)) {
        if RT.PhMap.Has(m[1]) {
            res.Push({t: "lit", v: SubStr(pat, chunkStart, fp - chunkStart)})
            res.Push({t: "ref", v: CanonName(m[1])})
            chunkStart := fp + m.Len
        }
        pos := fp + m.Len
    }
    res.Push({t: "lit", v: SubStr(pat, chunkStart)})
    return res
}

; AHK variable names are case-insensitive, and so is a default Map; return the
; casing actually stored so generated code matches what was typed.
CanonName(name) {
    for n in RT.PhNames
        if (n = name)
            return n
    return name
}

BuildOptions() {
    o := ""
    for letter in OPT_LETTERS
        if RT.optBoxes[letter].Value
            o .= letter
    return o . Trim(RT.edMoreOpts.Value)
}

; Does this pattern contain a "|" at nesting level zero?  Such a placeholder is
; a trap when concatenated: in "%a%\s%b%", a bare | inside %b% splits the WHOLE
; pattern rather than just %b%, so groups from the other branch never capture.
HasTopLevelAlt(pat) {
    n := StrLen(pat), i := 1, depth := 0
    while (i <= n) {
        c := SubStr(pat, i, 1)
        if (c = "\") {
            i += 2
            continue
        }
        if (c = "[") {                              ; step over a character class
            j := i + 1
            if (SubStr(pat, j, 1) = "^")
                j++
            if (SubStr(pat, j, 1) = "]")
                j++
            while (j <= n) {
                ch := SubStr(pat, j, 1)
                if (ch = "\") {
                    j += 2
                    continue
                }
                if (ch = "]")
                    break
                j++
            }
            i := j + 1
            continue
        }
        if (c = "(")
            depth++
        else if (c = ")")
            depth--
        else if (c = "|" && depth <= 0)
            return true
        i++
    }
    return false
}

; Names of placeholders that are spliced into a bigger expression while
; carrying a bare top-level alternation.  A placeholder used on its own is
; fine, so those are not reported.
AltHazards() {
    risky := Map()
    seen := Map(), order := []
    CollectDeps(PatternText(), seen, order)
    bodies := [PatternText()]
    for nm in order
        bodies.Push(RT.PhMap[nm])

    for body in bodies {
        others := "", refs := []
        for p in SplitRefs(body) {
            if (p.t = "lit")
                others .= p.v
            else
                refs.Push(p.v)
        }
        if (refs.Length = 1 && others = "")          ; a plain alias, harmless
            continue
        for nm in refs {
            try {
                if HasTopLevelAlt(ExpandText("%" nm "%", Map(), Map(), false))
                    risky[nm] := true
            }
        }
    }
    return risky
}

; ============================== WARNINGS =================================
; Static checks for the traps that bite people over and over.  Each returns a
; complete sentence; the caller joins them for the status bar and stacks them
; one per line for the bar's hover tooltip.
;
; Rule of thumb for adding one: it has to be cheap, and it has to be quiet.
; A check that cries wolf on legitimate patterns is worse than no check,
; because it teaches you to ignore the bar.  Anything speculative is worded as
; a heads-up rather than an accusation.
CollectWarnings(expanded, subj, unknown) {
    w := []
    pat := PatternText()
    xOn := RT.optBoxes["x"].Value
    mOn := RT.optBoxes["m"].Value

    ; --- undefined placeholders ------------------------------------------
    if (unknown.Count) {
        list := ""
        for k in unknown
            list .= (list = "" ? "" : ", ") "%" k "%"
        w.Push("Undefined placeholder(s) left literal: " list ".")
    }

    ; --- option prefix typed into the pattern ----------------------------
    if RegExMatch(pat, "^[imsxADJUXSC ``\t]*\)")
        w.Push("Pattern starts with an option prefix — options belong in the"
             . " checkboxes (Edit > Pull option prefix).")

    ; --- AHK escapes typed into a RAW pattern box -------------------------
    ; The single most common mix-up for AHK users: this box is not a string
    ; literal, so a backtick is just a backtick and `n is backtick-then-n.
    if RegExMatch(pat, "``[nrtbafvs]")
        w.Push("Pattern contains a backtick escape such as `n or `t. This box"
             . " holds the RAW pattern, not an AHK string literal, so a"
             . " backtick is a literal backtick here — write \n, \t, \r"
             . " instead.")

    ; --- stray whitespace from a paste ------------------------------------
    if (!xOn && pat != "") {
        lead := SubStr(pat, 1, 1), tail := SubStr(pat, -1)
        if (lead = " " || lead = "`t" || tail = " " || tail = "`t")
            w.Push("Pattern begins or ends with a space or tab, which matches"
                 . " literally. Usually a paste artefact.")
    }

    ; --- alternation precedence -------------------------------------------
    ; | binds looser than anything else, so anchors do not distribute over it.
    if (HasTopLevelAlt(expanded) && RegExMatch(expanded, "(^|[^\\])[\^$]"))
        w.Push("A top-level | with ^ or $ in the pattern: | has the LOWEST"
             . " precedence, so ^cat|dog$ means (^cat) or (dog$), not"
             . " ^(cat|dog)$. Wrap the alternation in (?:...).")

    ; --- CRLF plus m: $ leaves the CR inside the match ---------------------
    if (RT.ddlEol.Value = 1 && mOn && RegExMatch(expanded, "(^|[^\\])\$"))
        w.Push("CRLF line endings with the m option: $ matches before the \n"
             . " but AFTER the \r, so anything capturing to end-of-line keeps"
             . " a trailing carriage return. Use \r?$ or switch the line"
             . " endings to LF.")

    ; --- nested quantifiers ------------------------------------------------
    ; Deliberately a heads-up, not a verdict: the cheap test cannot tell
    ; (\w+)+ from the harmless (ab?c)+, and a false positive here costs the
    ; reader nothing.
    if RegExMatch(expanded, "\((\?:)?[^()]*[*+{][^()]*\)[*+]")
        w.Push("A quantified group whose body is also quantified, e.g. (\w+)+."
             . " On text that ALMOST matches, this can backtrack"
             . " catastrophically and hang the window. Untick Live before"
             . " running it against anything long.")

    ; --- placeholder splicing hazard ---------------------------------------
    if (!RT.cbWrap.Value) {
        risky := AltHazards()
        if (risky.Count) {
            list := ""
            for k in risky
                list .= (list = "" ? "" : ", ") "%" CanonName(k) "%"
            w.Push(list " has a top-level | — spliced into a bigger pattern it"
                 . " splits the WHOLE pattern, so groups in the other branches"
                 . " never capture. Tick " Chr(34) "Wrap each %ref%" Chr(34)
                 . " or put (?:...) around it.")
        }
    }

    ; --- replacement-side mistakes -----------------------------------------
    if (RT.rdReplace.Value) {
        rep := RT.edRepl.Value
        if RegExMatch(rep, "\\\d")
            w.Push("Replacement uses \1 for a backreference. AHK follows PCRE"
                 . " here and wants $1 — a backslash-digit is passed through"
                 . " as literal text.")
    }

    ; --- %name% written while support is off -------------------------------
    if (!PhOn() && RegExMatch(pat, "%[A-Za-z_]\w*%"))
        w.Push("Placeholder support is off, so a token like %name% is matched"
             . " as literal text. Tick " Chr(34) "Show & use sub-pattern"
             . " placeholders" Chr(34) " if you meant it to expand.")

    ; --- nothing to match against ------------------------------------------
    if (subj = "" && pat != "")
        w.Push("The haystack is empty, so there is nothing to match against.")

    return w
}

; Highest group number referenced by a replacement string: $1, ${12}, $U3.
; Returns 0 when there are none.  "$$" is a literal dollar and is stripped
; first so it cannot be misread as a reference.
MaxGroupRef(rep) {
    hi := 0, pos := 1
    rep := StrReplace(rep, "$$", "")
    while (fp := RegExMatch(rep, "\$[ULTult]?\{?(\d+)\}?", &m, pos)) {
        hi := Max(hi, Integer(m[1]))
        pos := fp + m.Len
    }
    return hi
}

; Notes joined onto one line for the status bar itself.
OneLineNotes(notes) {
    s := ""
    for n in notes
        s .= "   " Chr(0x2022) " " n
    return s
}

; The same notes stacked one per line, for the bar's hover tooltip — which is
; the only place a long list is actually readable.
StackedNotes(notes) {
    s := ""
    for n in notes
        s .= "`n`n" Chr(0x2022) " " n
    return s
}

; ============================== RUN =======================================
ScheduleRun() {
    if (RT.Loading)
        return
    SchedulePatternColors()
    SchedulePhPatColors()          ; the x and J boxes change its coloring too
    if (RT.cbLive && !RT.cbLive.Value)
        return
    SetTimer(RunTest, -RUN_DELAY)
}

SubjectChanged() {
    if (RT.Shading)                      ; our own recoloring, not a real edit
        return
    if (CanonText() == RT.Raw)           ; formatting-only notification
        return
    ScheduleRun()
}

; The rich edit stores one CR per line break, so a canonical CR-per-break copy
; of the text has offsets that line up 1:1 with EM_EXSETSEL.
CanonText() {
    t := RT.reSubject.GetText()
    t := StrReplace(t, "`r`n", "`r")
    t := StrReplace(t, "`n", "`r")
    return t
}

RunTest(*) {
    SetTimer(RunTest, 0)
    if (!RT.gui)
        return

    ; --- haystack --------------------------------------------------------
    RT.Raw := CanonText()
    switch RT.ddlEol.Value {
        case 2:  RT.Subject := StrReplace(RT.Raw, "`r", "`n")
        case 3:  RT.Subject := RT.Raw
        default: RT.Subject := StrReplace(RT.Raw, "`r", "`r`n")
    }
    subj := RT.Subject

    ; --- expand the pattern ----------------------------------------------
    unknown := Map()
    try {
        expanded := ExpandText(PatternText(), Map(), unknown, RT.cbWrap.Value)
    } catch as e {
        RT.edEffective.Value := PatternText()
        RT.EffText := PatternText(), RT.EffCaps := "", RT.EffBase := 0
        ShowError(e.Message)
        return
    }
    opts := BuildOptions()
    needle := opts ")" expanded
    RT.edEffective.Value := needle
    ; Only the text is recorded here; the group spans are not worked out until
    ; a group row is actually clicked, so a feature nobody is using costs a
    ; string assignment per keystroke rather than a second parse.
    RT.EffText := needle, RT.EffCaps := "", RT.EffBase := StrLen(opts) + 1

    ; Everything the tester can spot statically, as one note per entry so
    ; the tooltip can stack them.
    warn := CollectWarnings(expanded, subj, unknown)

    UpdatePhHits(opts, subj)

    if (RT.rdReplace.Value)
        DoReplace(needle, subj, warn)
    else
        DoMatch(needle, subj, warn)

    RT.edCode.Value := BuildAhkCode(expanded, opts)
}

DoMatch(needle, subj, warn) {
    RT.Matches := [], RT.Spans := []
    limit := RT.cbAll.Value ? -1 : 1
    try {
        CollectMatches(needle, subj, limit)
    } catch as e {
        ShowError(e.Message)
        return
    }
    ClearError()
    RT.edReplaced.Value := ""
    FillMatchList()
    n := RT.Matches.Length
    head := (n = 0 ? "No match." : n " match" (n = 1 ? "" : "es") ".")
    notes := warn.Clone()
    if (z := ZeroLenNote())
        notes.InsertAt(1, z)
    Status(head OneLineNotes(notes), false, head StackedNotes(notes))
}

DoReplace(needle, subj, warn) {
    RT.Matches := [], RT.Spans := []
    limit := Trim(RT.edLimit.Value) = "" ? -1 : Integer(RT.edLimit.Value)
    cnt := 0
    try {
        result := RegExReplace(subj, needle, RT.edRepl.Value, &cnt, limit)
    } catch as e {
        ShowError(e.Message)
        return
    }
    ClearError()
    RT.edReplaced.Value := result

    ; Collect the same matches RegExReplace acted on, so they can be shaded in
    ; the haystack AND listed below — without the list there is no way to see
    ; which groups actually captured, which is usually why $1 comes out empty.
    try {
        CollectMatches(needle, subj, limit)
    } catch as e {
        RT.Matches := []                  ; listing is cosmetic; the count stands
    }
    FillMatchList()
    notes := warn.Clone()
    if (z := ZeroLenNote())
        notes.InsertAt(1, z)
    ; Only checkable once something has matched, since that is where the group
    ; count comes from — hence here rather than in CollectWarnings().
    if (RT.Matches.Length) {
        want := MaxGroupRef(RT.edRepl.Value), have := RT.Matches[1].Count
        if (want > have)
            notes.Push("Replacement refers to $" want " but the pattern has only "
                     . have " capture group" (have = 1 ? "" : "s")
                     . ". A reference past the end comes through as an empty"
                     . " string, silently.")
    }
    head := cnt " replacement" (cnt = 1 ? "" : "s") "."
    Status(head OneLineNotes(notes), false, head StackedNotes(notes))
}

; Walk the haystack gathering matches.  Limit < 0 means "all".
CollectMatches(needle, subj, limit) {
    pos := 1, n := 0
    while (fp := RegExMatch(subj, needle, &mm, pos)) {
        if (limit >= 0 && n >= limit)
            break
        RT.Matches.Push(mm)
        n++
        pos := mm.Pos + Max(mm.Len, 1)              ; Max() guards zero-width matches
        if (pos > StrLen(subj) + 1 || n >= MAX_MATCHES)
            break
    }
}

FillMatchList() {
    RT.lvMatches.Opt("-Redraw")
    RT.lvMatches.Delete(), RT.lvGroups.Delete()
    for i, mm in RT.Matches
        RT.lvMatches.Add(, i, mm.Pos, mm.Len, mm.Len ? OneLine(mm[0]) : "(empty)")
    RT.lvMatches.Opt("+Redraw")
    ComputeSpans()
    ApplyShading()
    if (RT.Matches.Length) {
        ; Modify() raises ItemFocus synchronously; NoJump stops that handler
        ; from scrolling the haystack out from under whatever is being typed.
        RT.NoJump := true
        RT.lvMatches.Modify(1, "Select Focus")
        RT.NoJump := false
        MatchRowFocused(false)
    }
}

; A pattern that can match nothing also matches between every pair of
; characters.  That is almost never intended, and it is the usual explanation
; for a replacement that sprinkles itself through the whole haystack.
ZeroLenNote() {
    z := 0
    for mm in RT.Matches
        if (!mm.Len)
            z++
    if (!z)
        return ""
    return z " of them are ZERO-LENGTH — the pattern can match an empty"
         . " string, so it also matches between characters. Look for a "
         . Chr(34) "?" Chr(34) " or " Chr(34) "*" Chr(34)
         . " that makes every branch optional."
}


; Per-placeholder match count against the current haystack — handy for finding
; which sub-pattern is the one that isn't firing.
UpdatePhHits(opts, subj) {
    ; Invisible when the table is hidden, and not cheap: it compiles and runs
    ; every placeholder separately against the whole haystack.
    if !PhOn()
        return
    if (StrLen(subj) > 200000) {
        for i, name in RT.PhNames
            RT.lvPh.Modify(i, "Col3", "-")
        return
    }
    for i, name in RT.PhNames {
        hits := ""
        try {
            nd := opts ")" ExpandText("%" name "%", Map(), Map(), false)
            p := 1, c := 0, empty := false
            while (fp := RegExMatch(subj, nd, &mm, p)) {
                c++
                if (!mm.Len)
                    empty := true
                p := mm.Pos + Max(mm.Len, 1)
                if (p > StrLen(subj) + 1 || c >= 2000)
                    break
            }
            ; U+2205 flags a sub-pattern that can match nothing at all, which
            ; is what a suspiciously huge hit count usually means.
            hits := c (empty ? " " Chr(0x2205) : "")
        } catch {
            hits := "err"
        }
        RT.lvPh.Modify(i, "Col3", hits)
    }
}

; ============================== HIGHLIGHTING ==============================
; Match positions are 1-based indices into RT.Subject.  The rich edit stores one
; character per line break, so when the haystack is being tested as CRLF every
; preceding break costs one extra character that the control doesn't have.
ComputeSpans() {
    RT.Spans := []
    extraPerBreak := (RT.ddlEol.Value = 1)          ; only CRLF is two chars wide
    subj := RT.Subject
    prevPos := 1, running := 0
    for mm in RT.Matches {
        if (extraPerBreak) {
            n := 0
            StrReplace(SubStr(subj, prevPos, mm.Pos - prevPos), "`n", , , &n)
            running += n
        }
        s := mm.Pos - 1 - running
        inner := 0
        if (extraPerBreak) {
            StrReplace(SubStr(subj, mm.Pos, mm.Len), "`n", , , &inner)
            running += inner
        }
        RT.Spans.Push({s: s, e: s + mm.Len - inner})
        prevPos := mm.Pos + mm.Len
    }
}

ApplyShading(*) {
    if (GetKeyState("LButton", "P")) {       ; don't fight a drag-select
        SetTimer(ApplyShading, -200)
        return
    }
    SetTimer(ApplyShading, 0)
    RE := RT.reSubject
    RT.Shading := true
    sel := RE.GetSel()                              ; don't disturb the caret
    scr := RE.GetScrollPos()
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)  ; WM_SETREDRAW off

    RE.SetSel(0, -1)
    RE.SetFont({BkColor: "Auto"})

    if (RT.cbShade.Value) {
        for i, sp in RT.Spans {
            if (i > MAX_SHADED)
                break
            RE.SetSel(sp.s, sp.e)
            RE.SetFont({BkColor: (Mod(i, 2) ? MATCH_BG_A : MATCH_BG_B)})
        }
    }

    RE.SetSel(sel.S, sel.E)
    RE.SetScrollPos(scr.X, scr.Y)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)  ; WM_SETREDRAW on
    DllCall("InvalidateRect", "Ptr", RE.Hwnd, "Ptr", 0, "Int", 1)
    RT.Shading := false
}

SelectSpan(s, e) {
    RT.Shading := true
    RT.reSubject.SetSel(s, e)
    RT.reSubject.ScrollCaret()
    RT.Shading := false
}

; -------------------- EFFECTIVE PATTERN GROUP HIGHLIGHT -------------------
; Clicking a capture group in the results already selects that group's text in
; the haystack.  These select the piece of the PATTERN that produced it, which
; is the other half of the same question -- with 32 numbered groups in a
; placeholder-built pattern, "where does group 15 live?" is not answerable by
; eye.
;
; A plain Edit and EM_SETSEL rather than a rich edit and a background color:
; only one group is ever selected at a time, so there is nothing to layer, and
; the system highlight cannot collide with the syntax coloring scheme.
;
; The spans come from AnalyzePattern(), so an escaped \( , a "(" inside a
; character class, and the "(" of a (?i) option set are all correctly skipped,
; and a nested group gets its true extent rather than the nearest ")".
;
; Known gap: under the branch reset (?|...), PCRE reuses numbers across
; branches while this counts them straight through, so group numbers past such
; a construct will point at the wrong span.  Nothing else in the tokenizer
; needs it either, so it is left alone rather than half-solved.
EnsureEffCaps() {
    if (IsObject(RT.EffCaps))                     ; already parsed this text
        return true
    if (RT.EffText = "")
        return false
    ; The option letters and their ")" are not part of the pattern -- feeding
    ; them to the tokenizer would let that ")" pop the stack immediately.
    body := SubStr(RT.EffText, RT.EffBase + 1)
    opts := RT.EffBase > 1 ? SubStr(RT.EffText, 1, RT.EffBase - 1) : ""
    info := AnalyzePattern(body, InStr(opts, "x", true) ? 1 : 0
                               , InStr(opts, "J", true) ? 1 : 0)
    RT.EffCaps := info.caps
    return true
}

; A multiline Edit stores "`r`n" per line break.  Everything upstream of here
; normalises to a bare "`n" (see PatternText), so a character offset into the
; string runs one short per break against the control's own offsets.
EffOffset(pos) {
    if (pos <= 0)
        return 0
    n := 0
    StrReplace(SubStr(RT.EffText, 1, pos), "`n", , , &n)
    return pos + n
}

; gnum 0 clears the highlight.
HighlightEffGroup(gnum) {
    static EM_SETSEL := 0x00B1, EM_SCROLLCARET := 0x00B7
    if (!RT.edEffective)
        return
    if (!gnum || !EnsureEffCaps() || gnum > RT.EffCaps.Length) {
        DllCall("user32\SendMessageW", "Ptr", RT.edEffective.Hwnd
              , "UInt", EM_SETSEL, "Ptr", 0, "Ptr", 0)
        return
    }
    c := RT.EffCaps[gnum]
    s := EffOffset(c.s + RT.EffBase), e := EffOffset(c.e + RT.EffBase)
    DllCall("user32\SendMessageW", "Ptr", RT.edEffective.Hwnd
          , "UInt", EM_SETSEL, "Ptr", s, "Ptr", e)
    DllCall("user32\SendMessageW", "Ptr", RT.edEffective.Hwnd
          , "UInt", EM_SCROLLCARET, "Ptr", 0, "Ptr", 0)
}

; ============================== RESULT NAVIGATION =========================
MatchRowFocused(jump := true) {
    row := RT.lvMatches.GetNext(, "F")
    if (!row || row > RT.Matches.Length)
        return
    mm := RT.Matches[row]
    RT.lvGroups.Opt("-Redraw"), RT.lvGroups.Delete()
    RT.lvGroups.Add(, 0, "(whole)", mm.Pos, mm.Len, OneLine(mm[0]))
    Loop mm.Count
        RT.lvGroups.Add(, A_Index, mm.Name[A_Index], mm.Pos[A_Index], mm.Len[A_Index], OneLine(mm[A_Index]))
    RT.lvGroups.Opt("+Redraw")
    HighlightEffGroup(0)                 ; the list just changed under it
    if (jump && !RT.NoJump && row <= RT.Spans.Length)
        SelectSpan(RT.Spans[row].s, RT.Spans[row].e)
}

; Clicking a capture group selects just that group's span in the haystack.
GroupRowFocused() {
    if (RT.NoJump)
        return
    row := RT.lvGroups.GetNext(, "F")
    mRow := RT.lvMatches.GetNext(, "F")
    if (!row || !mRow || mRow > RT.Matches.Length || mRow > RT.Spans.Length)
        return
    mm := RT.Matches[mRow]
    idx := row - 1                                   ; row 1 is the whole match
    ; Done before the Pos check below: a group that did not participate has no
    ; position in the haystack but still has a definition in the pattern, and
    ; showing WHERE it is, is most of the answer to why it came back empty.
    HighlightEffGroup(idx)
    p := mm.Pos[idx], l := mm.Len[idx]
    if (!p)
        return
    ; Shift by the same amount the whole match was shifted, then by any extra
    ; line breaks lying between the match start and this group's start.
    base := RT.Spans[mRow].s - (mm.Pos - 1)
    inner := 0
    if (RT.ddlEol.Value = 1)
        StrReplace(SubStr(RT.Subject, mm.Pos, p - mm.Pos), "`n", , , &inner)
    s := p - 1 + base - inner
    innerLen := 0
    if (RT.ddlEol.Value = 1)
        StrReplace(SubStr(RT.Subject, p, l), "`n", , , &innerLen)
    SelectSpan(s, s + l - innerLen)
}

; ============================== AHK CODE GENERATION =======================
; Rebuild the concatenated-variable form:
;     reMonth := "\b(...)\b"
;     if RegExMatch(Haystack, "i)(" reMonth "\s" re1st31st ")", &Match)
BuildAhkCode(expandedPattern, opts) {
    seen := Map(), order := []
    CollectDeps(PatternText(), seen, order)

    code := ""
    if (order.Length) {
        code .= "; --- sub-pattern placeholders ---`r`n"
        for name in order
            code .= name " := " BuildExpr(RT.PhMap[name]) "`r`n"
        code .= "`r`n"
    }

    needleExpr := BuildExpr(opts ")" PatternText())

    if (RT.rdReplace.Value) {
        limit := Trim(RT.edLimit.Value)
        code .= "Result := RegExReplace(Haystack, " needleExpr ", "
             .  Lit(AhkEsc(RT.edRepl.Value)) ", &Count"
             .  (limit = "" ? "" : ", " limit) ")`r`n"
    } else {
        code .= "if RegExMatch(Haystack, " needleExpr ", &Match) {`r`n"
             .  "    MsgBox(" Lit("Match: ") " Match[0])`r`n"
             .  "}`r`n"
    }
    code .= "`r`n; --- the same thing, fully expanded into one literal ---`r`n"
    code .= "Needle := " Lit(AhkEsc(opts ")" expandedPattern)) "`r`n"
    return code
}

; Depth-first, dependencies before dependents, so the output pastes and runs.
CollectDeps(pat, seen, order) {
    for p in SplitRefs(pat) {
        if (p.t != "ref" || seen.Has(p.v))
            continue
        seen[p.v] := true
        CollectDeps(RT.PhMap[p.v], seen, order)
        order.Push(p.v)
    }
}

BuildExpr(pat) {
    wrap := RT.cbWrap.Value
    out := ""
    for p in SplitRefs(pat) {
        if (p.t = "lit") {
            if (p.v = "")
                continue
            out .= (out = "" ? "" : " ") Lit(AhkEsc(p.v))
        } else if (wrap) {
            out .= (out = "" ? "" : " ") Lit("(?:") " " p.v " " Lit(")")
        } else {
            out .= (out = "" ? "" : " ") p.v
        }
    }
    return out = "" ? Lit("") : out
}

Lit(s) => Chr(34) s Chr(34)

; Escape raw text so it survives inside an AHK v2 double-quoted string.
AhkEsc(s) {
    bt := Chr(96), dq := Chr(34)
    s := StrReplace(s, bt, bt bt)              ; backtick first!
    s := StrReplace(s, dq, bt dq)
    s := StrReplace(s, "`r", bt "r")
    s := StrReplace(s, "`n", bt "n")
    s := StrReplace(s, "`t", bt "t")
    return s
}

CopyAsLiteral() {
    try {
        expanded := ExpandText(PatternText(), Map(), Map(), RT.cbWrap.Value)
    } catch as e {
        Status(e.Message, true)
        return
    }
    CopyText(Lit(AhkEsc(BuildOptions() ")" expanded)))
}

; ============================== IMPORT FROM AHK CODE ======================
ImportDialog() {
    ig := Gui("+Owner" RT.gui.Hwnd, "Import from AHK code")
    ig.SetFont("s10", "Segoe UI")
    ig.Add("Text", "x10 y10 w620",
        "Paste AHK code below.  Every  name := " Chr(34) "pattern" Chr(34) "  assignment becomes a placeholder,`n"
      . "and the first RegExMatch()/RegExReplace() call supplies the main pattern and its options.")
    ig.SetFont("s10", "Consolas")
    ed := ig.Add("Edit", "x10 y56 w620 h320 +Multi +WantTab -Wrap +HScroll +VScroll", "")
    ig.SetFont("s10", "Segoe UI")
    cbClear := ig.Add("CheckBox", "x10 y386 w240 h22 Checked", "Replace existing placeholders")
    btnOk := ig.Add("Button", "x450 y384 w86 h26 Default", "Import")
    btnCancel := ig.Add("Button", "x544 y384 w86 h26", "Cancel")
    btnCancel.OnEvent("Click", (*) => ig.Destroy())
    btnOk.OnEvent("Click", (*) => (DoImport(ed.Value, cbClear.Value), ig.Destroy()))
    ig.Show("w640 h424")
    ed.Focus()
}

DoImport(code, clearFirst) {
    if (clearFirst)
        RT.PhNames := [], RT.PhMap := Map()

    added := 0, gotPattern := false
    ; --- assignments -> placeholders ---
    Loop Parse code, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^\s*([A-Za-z_]\w*)\s*:=\s*(.+)$", &am)
            continue
        name := am[1], expr := am[2]
        if RegExMatch(expr, "^\s*[A-Za-z_]\w*\s*\(")      ; right side is a call, not a pattern
            continue
        ok := true
        val := ParseAhkExpr(expr, &ok)
        if (val = "")
            continue
        if !RT.PhMap.Has(name)
            RT.PhNames.Push(name)
        RT.PhMap[name] := val
        added++
    }

    ; --- first RegExMatch/RegExReplace call -> main pattern ---
    if RegExMatch(code, "i)\bRegEx(Match|Replace)\s*\(", &cm) {
        args := SplitTopLevelArgs(GrabToMatchingParen(code, cm.Pos + cm.Len))
        if (args.Length >= 2) {
            ok := true
            pat := ParseAhkExpr(args[2], &ok)
            opts := ""
            if RegExMatch(pat, "^([imsxADJUXSC ``\t]*)\)", &om) {
                opts := Trim(om[1])
                pat := SubStr(pat, om.Len + 1)
            }
            SetPatternText(pat)
            SetOptions(opts)
            gotPattern := true
            if (cm[1] = "Replace") {
                RT.rdReplace.Value := 1, RT.rdMatch.Value := 0
                if (args.Length >= 3) {
                    ok2 := true
                    RT.edRepl.Value := ParseAhkExpr(args[3], &ok2)
                }
                ModeChanged()
            }
        }
    }

    ; An import that defined placeholders has to show them, or it looks inert.
    if (added) {
        RT.cbPh.Value := 1
        ApplyPhVisible()
    }
    RefreshPhList()
    RT.edPhName.Value := "", SetPhPatText(""), RT.CurPh := 0
    Status("Imported " added " placeholder" (added = 1 ? "" : "s")
         . (gotPattern ? " and the main pattern." : ".  (No RegExMatch/RegExReplace call found.)"))
    RunTest()
}

; Turn an AHK expression made of string literals and variable names into raw
; pattern text, with variable references written back as %name%.
ParseAhkExpr(expr, &ok) {
    out := "", i := 1, n := StrLen(expr)
    ok := true
    while (i <= n) {
        c := SubStr(expr, i, 1)
        if (c = Chr(34) || c = Chr(39)) {
            quote := c, i++
            while (i <= n) {
                ch := SubStr(expr, i, 1)
                if (ch = Chr(96)) {
                    out .= UnescapeAhkChar(SubStr(expr, i + 1, 1))
                    i += 2
                    continue
                }
                if (ch = quote) {
                    if (SubStr(expr, i + 1, 1) = quote) {        ; doubled quote
                        out .= quote, i += 2
                        continue
                    }
                    i++
                    break
                }
                out .= ch, i++
            }
        } else if RegExMatch(c, "[A-Za-z_]") {
            RegExMatch(expr, "[A-Za-z_]\w*", &vm, i)
            out .= "%" vm[0] "%"
            i += vm.Len
        } else if (c = " " || c = "`t" || c = ".") {
            i++
        } else if (c = ";") {
            break                                                ; trailing comment
        } else {
            ok := false
            i++
        }
    }
    return out
}

UnescapeAhkChar(c) {
    switch c {
        case "n": return "`n"
        case "r": return "`r"
        case "t": return "`t"
        case "b": return Chr(8)
        case "a": return Chr(7)
        case "f": return Chr(12)
        case "v": return Chr(11)
        default:  return c
    }
}

; From just past an opening "(", return the text up to its matching ")".
GrabToMatchingParen(s, startPos) {
    depth := 1, i := startPos, n := StrLen(s), out := ""
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = Chr(34) || c = Chr(39)) {
            quote := c, out .= c, i++
            while (i <= n) {
                ch := SubStr(s, i, 1)
                out .= ch
                if (ch = Chr(96)) {
                    out .= SubStr(s, i + 1, 1), i += 2
                    continue
                }
                i++
                if (ch = quote)
                    break
            }
            continue
        }
        if (c = "(")
            depth++
        else if (c = ")" && --depth = 0)
            break
        out .= c, i++
    }
    return out
}

SplitTopLevelArgs(s) {
    args := [], cur := "", depth := 0, i := 1, n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = Chr(34) || c = Chr(39)) {
            quote := c, cur .= c, i++
            while (i <= n) {
                ch := SubStr(s, i, 1)
                cur .= ch
                if (ch = Chr(96)) {
                    cur .= SubStr(s, i + 1, 1), i += 2
                    continue
                }
                i++
                if (ch = quote)
                    break
            }
            continue
        }
        if (c = "(" || c = "[" || c = "{")
            depth++
        else if (c = ")" || c = "]" || c = "}")
            depth--
        else if (c = "," && depth = 0) {
            args.Push(Trim(cur)), cur := "", i++
            continue
        }
        cur .= c, i++
    }
    args.Push(Trim(cur))
    return args
}

SetOptions(opts) {
    rest := opts
    for letter in OPT_LETTERS {
        has := InStr(opts, letter, true) ? 1 : 0
        RT.optBoxes[letter].Value := has
        if (has)
            rest := StrReplace(rest, letter, , true)
    }
    RT.edMoreOpts.Value := Trim(rest)
}

PullOptionPrefix() {
    pat := PatternText()
    if !RegExMatch(pat, "^([imsxADJUXSC ``\t]*)\)", &om) {
        Status("No option prefix found at the start of the pattern.")
        return
    }
    SetOptions(Trim(om[1]))
    SetPatternText(SubStr(pat, om.Len + 1))
    RunTest()
}

; ============================== SESSION FILE ==============================
; Patterns can end in whitespace and can contain "=", so IniRead/IniWrite are a
; poor fit (the OS API trims).  This is a plain text file with escaped fields.
Enc(s) {
    s := StrReplace(s, "&", "&a;")
    s := StrReplace(s, "`r", "&r;")
    s := StrReplace(s, "`n", "&n;")
    s := StrReplace(s, "`t", "&t;")
    return s
}
Dec(s) {
    s := StrReplace(s, "&t;", "`t")
    s := StrReplace(s, "&n;", "`n")
    s := StrReplace(s, "&r;", "`r")
    return StrReplace(s, "&a;", "&")           ; ampersand last
}

SaveSession(announce := false, path := "") {
    if (path = "")
        path := RT.SessionFile
    txt := "RegExTesterSession v1`r`n"
    txt .= "OPT=" Enc(BuildOptions()) "`r`n"
    txt .= "MODE=" (RT.rdReplace.Value ? "replace" : "match") "`r`n"
    txt .= "FINDALL=" (RT.cbAll.Value ? 1 : 0) "`r`n"
    txt .= "LIVE=" (RT.cbLive.Value ? 1 : 0) "`r`n"
    txt .= "SHADE=" (RT.cbShade.Value ? 1 : 0) "`r`n"
    txt .= "EOL=" RT.ddlEol.Value "`r`n"
    txt .= "WRAP=" (RT.cbWrap.Value ? 1 : 0) "`r`n"
    txt .= "TIPS=" (RT.cbTips.Value ? 1 : 0) "`r`n"
    txt .= "PHON=" (RT.cbPh.Value ? 1 : 0) "`r`n"
    txt .= "TABS=" (RT.cbTabs.Value ? 1 : 0) "`r`n"
    ; Client size, i.e. the same numbers Gui.Show's w/h take, so it round-trips
    ; without having to guess at the border and title-bar thickness.
    txt .= "WINW=" RT.WinW "`r`n"
    txt .= "WINH=" RT.WinH "`r`n"
    txt .= "LIMIT=" Enc(RT.edLimit.Value) "`r`n"
    for name in RT.PhNames
        txt .= "PH=" name "`t" Enc(RT.PhMap[name]) "`r`n"
    txt .= "PAT=" Enc(PatternText()) "`r`n"
    txt .= "REPL=" Enc(RT.edRepl.Value) "`r`n"
    txt .= "SUBJ=" Enc(CanonText()) "`r`n"
    for h in RT.Snippets
        txt .= "HIST=" Enc(h) "`r`n"
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend(txt, path, "UTF-8")
        ; "Save session as" adopts the new file, the way any editor would.
        ; Without this, Ctrl+S and the save-on-exit would keep writing to the
        ; OLD path while the title bar advertised the new one -- a worse bug
        ; than having no title at all.  Inside the try, so a failed write does
        ; not adopt a file it could not create.
        RT.SessionFile := path
        UpdateTitle()
        if (announce)
            Status("Session saved to " path)
    } catch as e {
        Status("Could not save session: " e.Message, true)
    }
}

SaveSessionAs() {
    path := FileSelect("S16", RT.SessionFile, "Save session as", "Text (*.txt)")
    if (path != "")
        SaveSession(true, path)
}

OpenSessionFile() {
    path := FileSelect(3, RT.SessionFile, "Open session", "Text (*.txt)")
    if (path != "")
        LoadSession(path)
}

LoadSession(path := "") {
    if (path = "")
        path := RT.SessionFile
    if !FileExist(path) {
        LoadDemoDates()
        return
    }
    try {
        txt := FileRead(path, "UTF-8")
    } catch {
        LoadDemoDates()
        return
    }
    RT.SessionFile := path         ; "Open session" adopts it too -- see above
    UpdateTitle()
    RT.Loading := true
    RT.PhNames := [], RT.PhMap := Map(), RT.CurPh := 0
    RT.Snippets := []
    optStr := "", mode := "match", subj := ""
    Loop Parse txt, "`n", "`r" {
        line := A_LoopField
        if !(p := InStr(line, "="))
            continue
        key := SubStr(line, 1, p - 1), val := SubStr(line, p + 1)
        switch key {
            case "OPT":     optStr := Dec(val)
            case "MODE":    mode := val
            case "FINDALL": RT.cbAll.Value := (val = "1")
            case "LIVE":    RT.cbLive.Value := (val = "1")
            case "SHADE":   RT.cbShade.Value := (val = "1")
            case "WRAP":    RT.cbWrap.Value := (val = "1")
            case "TIPS":    RT.cbTips.Value := (val = "1")
            case "PHON":    RT.cbPh.Value := (val = "1")
            case "TABS":    RT.cbTabs.Value := (val = "1")
            case "WINW":    RT.WinW := ClampSize(val, true)
            case "WINH":    RT.WinH := ClampSize(val, false)
            case "EOL":     RT.ddlEol.Value := Max(1, Min(3, Integer(val)))
            case "LIMIT":   RT.edLimit.Value := Dec(val)
            case "PAT":     SetPatternText(Dec(val))
            case "REPL":    RT.edRepl.Value := Dec(val)
            case "SUBJ":    subj := Dec(val)
            case "HIST":    RT.Snippets.Push(Dec(val))
            case "PH":
                if (t := InStr(val, "`t")) {
                    nm := SubStr(val, 1, t - 1)
                    if !RT.PhMap.Has(nm)
                        RT.PhNames.Push(nm)
                    RT.PhMap[nm] := Dec(SubStr(val, t + 1))
                }
        }
    }
    SetOptions(optStr)
    RT.rdReplace.Value := (mode = "replace") ? 1 : 0
    RT.rdMatch.Value := (mode = "replace") ? 0 : 1
    RefreshPhList()
    SetSubjectText(subj)
    RT.Loading := false
    ; At startup these are read before the window exists; the caller uses
    ; RT.WinW/RT.WinH for the initial Show and the checkbox for the initial
    ; AttachHeaderTips.  Opening a session later has to apply them here.
    if (RT.Shown) {
        RT.gui.Show("w" RT.WinW " h" RT.WinH)
        ApplyTipState()
        ApplyPhVisible()
    }
    ModeChanged()
    SchedulePatternColors()
}

; Guards against a hand-edited or stale session file.  Never smaller than the
; Gui's MinSize, never larger than the whole virtual desktop -- Steve runs two
; monitors, so SM_CXVIRTUALSCREEN is the right ceiling, not SM_CXSCREEN.
ClampSize(val, isWidth) {
    static SM_CXVIRTUALSCREEN := 78, SM_CYVIRTUALSCREEN := 79
    if !IsInteger(val)
        return isWidth ? RT.WinW : RT.WinH
    v := Integer(val)
    if (isWidth)
        return Max(820, Min(v, SysGet(SM_CXVIRTUALSCREEN)))
    return Max(620, Min(v, SysGet(SM_CYVIRTUALSCREEN)))
}

ClearAll() {
    if (MsgBox("Clear all placeholders, the pattern and the haystack text?", "RegEx Tester", 0x24) != "Yes")
        return
    RT.Loading := true
    RT.PhNames := [], RT.PhMap := Map(), RT.CurPh := 0
    RefreshPhList()
    RT.edPhName.Value := "", SetPhPatText("")
    SetPatternText(""), RT.edRepl.Value := ""
    SetSubjectText("")
    RT.Loading := false
    SchedulePatternColors()
    RunTest()
}

LoadDemoDates() {
    RT.Loading := true
    RT.PhNames := [], RT.PhMap := Map(), RT.CurPh := 0
    AddPh("reMonth",     "\b((Jan|Feb)(r?u(ary)?)?|Mar(ch)?|Apr(il)?|May|Jun(e)?|Jul(y)?|Aug(ust)?|(Sep(tem)?|Oct(o)?|Nov|Dec)(em)?(ber)?)\b")
    AddPh("re1st31st",   "\b(?<!:)([0-2]?[0-9]|30|31)(st|nd|rd|th)?(?!:)\b")
    AddPh("reWDay",      "\b(((Mon|Tue(s)?|Wed(nes|s)?|Thu(rs|r)?|Fri|Sat(ur)?|Sun))(day|d)?|(day\safter\s)?tomorrow)\b")
    AddPh("re2WeeksPre", "(((2|two)\sweeks\s)(from\s)?|((week\s)?after next\s(on\s)?))")
    AddPh("re2WeeksSuf", "(((in\s)?(2|two) weeks)|((week )?after next))")
    AddPh("reDateWord",  "(%reMonth%\s%re1st31st%|%re1st31st%\sof\s%reMonth%)")
    RefreshPhList()
    SetPatternText("%reDateWord%")
    SetOptions("i")
    RT.edRepl.Value := "[$1]"
    ; Sample sentences lifted from the header of OutlookMagnet2.ahk.
    demo := "There is a conference for Jimmy Bob after school next Wed in the Resource Room.`r"
    demo .= "Let's do Monday in 2 weeks in Rm 101.`r"
    demo .= "The Feb 20th transition meeting for Jenny is at noon in the Commons.`r"
    demo .= "Nov 17 before school for Billy's thing.`r"
    demo .= "Day after tomorrow in the morning in your office.`r"
    demo .= "Open House on Sept. 12th from 5:30 - 7:15`r"
    demo .= "Rescheduled to the 3rd of March, and again to April 1."
    SetSubjectText(demo)
    RT.rdMatch.Value := 1, RT.rdReplace.Value := 0
    RT.ddlEol.Value := 1
    ; The demo is entirely about placeholders, so force the section open --
    ; otherwise loading it would look like it had done nothing.
    RT.cbPh.Value := 1
    ApplyPhVisible()
    RT.Loading := false
    ModeChanged()
    SchedulePatternColors()
    RunTest()
}

; The other demo, and deliberately the opposite kind of thing: no placeholders
; at all, just one large self-contained pattern of the sort any regex tester
; would be handed.  Between the two, a first-time user sees both what makes
; this tester different and what it does for everybody else.
;
; The pattern is AndyMBody's hotstring parser, the one AutoCorrect2's
; HotstringHelper uses.  It earns its place beyond being realistic: it needs
; the J option to compile at all, and it is long enough that the
; matching-paren highlight starts to pay for itself.
;
; Worth knowing when reading the results: HotstringHelper feeds this pattern a
; single line at a time, and on one line it is exact.  Run against a whole
; library, as here, the second (?<Repl>) branch is [\s\S]+?, which will cross
; a line break to reach the next "  ;" it can find -- so the first match runs
; on past where you would expect it to stop.  Nothing is broken; the pattern is
; being asked a question it was not written for.
;
; Both strings below are continuation sections rather than quoted literals,
; which is what CheatSheet() does and for the same reason: the text is full of
; double quotes, and inside a continuation section quotes are literal.  Two
; things still need escaping -- a backtick, and a ")" at the start of a line,
; which would otherwise end the section early.
LoadDemoHotstrings() {
    RT.Loading := true

    ; Emptied, not merely hidden.  Leaving the date placeholders lying about
    ; would put six unused rows into the generated AHK code on the other tab.
    RT.PhNames := [], RT.PhMap := Map(), RT.CurPh := 0
    RefreshPhList()
    RT.edPhName.Value := "", SetPhPatText("")

    SetPatternText("
    (
^:(?<Opts>[^:]+)*:(?<Trig>[^:]+)::(?:f\("(?<Repl>[^"]*)"(?:\h*,\h*(?<Log>[01]))?(?:\h*,\h*(?<Paste>[01]))?\)|(?<Repl>[\s\S]+?)(?=\h+;|\z))?(?<Comm>\h+;.+)?$
    )")

    ; J is not optional: (?<Repl>...) is defined once per branch of the
    ; alternation, and without DUPNAMES the pattern does not compile.  Untick
    ; it and both copies of the name turn red in the pattern box.
    SetOptions("imJ")
    RT.edRepl.Value := "[${Trig}]"

    ; RTrim0 because several lines end in meaningful tabs, and a continuation
    ; section would otherwise trim them away.
    demo := "
    (RTrim0
Note:  The above big regex was written by AndyMBody.
; Vanilla AHK hotstring 
::trigger::replacement
::;rrr::reading, writing, and math
:B0X*:alltime::f("all-time") ; Fixes 1 word 
:B0X*:alma matter::f("alma mater") ; Fixes 1 word

:B0X*:along it's::f("along its") ; Fixes 1 word

; To-be-typed boilerplate items are now wrapped in f() function calls.  This allows InputBuffering with Descolada's InputBuffer class.  We don't want to log these, so they get '0' as a second param.  We want to type (not paste) them, and paste=0 is the default, so no need to include the third param. 
:B0X:;sdda::f("Developmental Disabilities Administration (DDA)", 0)
:B0X:;sdi::f("specially-designed instruction", 0)
:B0X:;sdial::f("Developmental Indicators for the Assessment of Learning-Fourth Ed (DIAL-4)", 0)

; This is a larger boilerplate item.  It also does not get logged (only AutoCorrections get logged) so it needs the second param.  Also, it does get pasted, rather than typed, which is not the f() default, so the third param is also needed. 
:B0X:;rrrr::f("
(RTrim0
Basic Reading		
Reading Comprehension	
Reading Fluency		
Math Calculations	
Applied Math		
Written Expression	
`)",0,1)


::ttfn::f("Ta Ta For Now (TTFN)")


:B0X:;homer::f("
(
Homer Simpson
Marge Simpson
Bart Simpson
Lisa Simpson
Maggie Simpson
Ned Flanders
Maude Flanders
Rod Flanders
Todd Flanders
Seymour Skinner
Edna Krabappel
Moe Szyslak
Barney Gumble
Apu Nahasapeemapetilon
Clancy Wiggum
Ralph Wiggum
Milhouse Van Houten
Nelson Muntz
Martin Prince
Comic Book Guy
Sideshow Bob
Krusty the Clown
Superintendent Chalmers
Otto Mann
Agnes Skinner
`)",0,1)

:B0X:;homer2::f("Homer Simpson``nMarge Simpson``nBart Simpson``nLisa Simpson``nMaggie Simpson``nNed Flanders``nMaude Flanders``nRod Flanders``nTodd Flanders``nSeymour Skinner``nEdna Krabappel``nMoe Szyslak``nBarney Gumble``nApu Nahasapeemapetilon``nClancy Wiggum``nRalph Wiggum``nMilhouse Van Houten``nNelson Muntz``nMartin Prince``nComic Book Guy``nSideshow Bob``nKrusty the Clown``nSuperintendent Chalmers``nOtto Mann``nAgnes Skinner2", 0, 1)

:B0X:mltest::f(" ; Optional comment here
(
One
Two
Three
`)",0) ; What about this comment?

:B0X:mltest::f(" ; Optional comment here
(
One
Two
Three
`)",0,1)

:B0X:mltest::f(" ; Optional comment here
(
One
Two (parenth not at beginning of line)
Three
`)",0,1)

::;trig::replacement ;This is a comment.
::;trig::replacement;This not is a comment.
    )"
    SetSubjectText(StrReplace(demo, "`n", "`r"))

    RT.rdMatch.Value := 1, RT.rdReplace.Value := 0
    RT.cbAll.Value := 1
    RT.ddlEol.Value := 1

    ; Folded away: with nothing in it, an open placeholder table would only be
    ; an empty list taking height off the haystack, and this demo is precisely
    ; the case where placeholders are not the point.
    RT.cbPh.Value := 0
    ApplyPhVisible()

    RT.Loading := false
    ModeChanged()
    SchedulePatternColors()
    RunTest()
}

AddPh(name, pat) {
    RT.PhNames.Push(name)
    RT.PhMap[name] := pat
}

SetSubjectText(txt) {
    RT.Shading := true
    RE := RT.reSubject
    RE.SetText(txt)
    RE.SetSel(0, -1)
    RE.SetFont({Name: SUBJ_FONT, Size: SUBJ_SIZE, Style: "N", Color: "Auto", BkColor: "Auto"})
    RE.SetSel(0, 0)
    RT.Shading := false
    SuppressHScroll(RE.Hwnd)             ; replacing the text re-asserts it
    RT.Raw := CanonText()
}

; ============================== SMALL HELPERS =============================
OneLine(s) {
    s := StrReplace(s, "`r`n", Chr(0x00B6))        ; ¶
    s := StrReplace(s, "`n", Chr(0x00B6))
    s := StrReplace(s, "`r", Chr(0x00B6))
    return StrReplace(s, "`t", Chr(0x2192))        ; →
}

; The status bar is a single narrow line and silently truncates whatever
; doesn't fit — which is exactly the messages worth reading, since the warning
; list is the long one.  So every status update also feeds the bar's own hover
; tooltip, where the whole thing fits and the notes are stacked one per line.
;
; 'full' is the stacked form.  When it is omitted the tooltip just repeats the
; bar text, which still helps whenever the window is narrow.
;
; Note this rides on the same tooltip window as everything else, so unticking
; "Show tips on hover" silences it too.
Status(msg, isError := false, full := "") {
    RT.sb.SetText("  " (isError ? "ERROR: " : "") msg)
    if (RT.Shown)
        CtrlToolTip(RT.sb, (isError ? "ERROR: " : "") (full = "" ? msg : full))
}

ShowError(msg) {
    RT.LastErr := msg
    RT.edEffective.Opt("+BackgroundFFD6D6")
    RT.lvMatches.Delete(), RT.lvGroups.Delete()
    RT.edReplaced.Value := ""
    RT.Matches := [], RT.Spans := []
    ApplyShading()
    Status(msg, true)
}

ClearError() {
    if (RT.LastErr != "") {
        RT.edEffective.Opt("-Background")
        RT.LastErr := ""
    }
}

CopyText(txt) {
    A_Clipboard := txt
    Status("Copied " StrLen(txt) " characters to the clipboard.")
}

OnCloseGui() {
    SaveSession()
    ; Each instance owns a watchdog timer that holds a reference back to the
    ; instance; Dispose() is what breaks that cycle.
    for t in [RT.TipsPh, RT.TipsMatch, RT.TipsGroup]
        if (t is LVHeaderToolTips)
            t.Dispose()
    ExitApp()
}

; ============================== CHEAT SHEET ===============================
CheatSheet() {
    return "
    (
OPTIONS  (case-sensitive, placed before the ")" at the very start of the pattern)
  i   case-insensitive
  m   multiline: ^ and $ also match at internal line breaks
  s   dot-all: . also matches newlines (two dots needed to span a CRLF pair)
  x   ignore literal whitespace in the pattern; # starts a comment
  A   anchored: match only at the start of the haystack
  D   $ matches only at the very end, even after a trailing newline (ignored with m)
  J   allow duplicate named subpatterns
  U   ungreedy: quantifiers become lazy, and ? then makes them greedy
  X   PCRE_EXTRA: an unrecognized backslash+letter throws instead of being literal
  S   study the pattern (small speedup when it will be run many times)
  C   auto-callout mode
  ``a  recognize extra newline markers (VT, FF, NEL, LS, PS); also sets (*BSR_UNICODE)
  ``n  linefeed is the only newline marker
  ``r  carriage return is the only newline marker
  Spaces and tabs may separate options.  This tester always emits the ")", so a
  pattern that starts with ")" or with option letters is never misread.

CHARACTERS
  .          any char except CR/LF (see the s option)
  \d \D      digit / non-digit          \w \W   word char / non-word char
  \s \S      whitespace / non-ws        \h \v   horizontal / vertical ws
  \t \r \n   tab, CR, LF                \xhh    char by hex code
  [abc]      any one of a, b, c         [^abc]  any one char except those
  [a-z0-9_]  ranges inside a class      \Q...\E literal run, no escaping needed
  Escape these to use them literally:   \ . * ? + [ { | ( ) ^ $

QUANTIFIERS   (append ? for lazy, + for possessive)
  *  0 or more     +  1 or more     ?  0 or 1
  {3}  exactly 3   {2,}  2 or more  {2,5}  2 through 5

ANCHORS AND BOUNDARIES
  ^   start of haystack (or of a line with m)
  $   end of haystack, before a trailing newline (or of a line with m; see D)
  \b  word boundary        \B  not a word boundary
  \A  start of haystack    \z  very end     \Z  end, before a trailing newline

GROUPS
  (...)          capturing group -> Match[1], Match[2], ...
  (?:...)        non-capturing group
  (?<name>...)   named group -> Match["name"]  (still numbered as well)
  a|b            alternation
  \1             backreference to group 1

LOOKAROUND  (zero width — they assert but consume nothing)
  (?=...)   followed by             (?!...)   not followed by
  (?<=...)  preceded by             (?<!...)  not preceded by
  \K        drop everything matched so far from the reported match

MATCH OBJECT   RegExMatch(Haystack, Needle, &Match [, StartingPos])
  Match[0]        whole match           Match[N] / Match["name"]  a subpattern
  Match.Pos       position of match     Match.Pos[N]   position of subpattern N
  Match.Len       length of match       Match.Len[N]   length of subpattern N
  Match.Count     number of subpatterns
  Match.Name[N]   name of subpattern N, if it has one
  Match.Mark      name from the last (*MARK:NAME) encountered
  RegExMatch returns the position of the match, or 0 when there is none.

REPLACEMENT TEXT
  RegExReplace(Haystack, Needle, Replacement, &Count, Limit, StartingPos)
  $0 .. $9      backreferences         ${10}, ${name}   braced form
  $U1 $L1 $T1   upper / lower / title case that subpattern
  $$            a literal dollar sign
  Backreferences that did not participate come through as empty strings.

TWO TRAPS THAT BITE WHEN PATTERNS ARE BUILT BY CONCATENATION
  1. A bare top-level | escapes its placeholder.  If %reTime% is defined as
     a|b|c and you write %reDay%\s%reTime%, the alternation splits the ENTIRE
     pattern into "%reDay%\s a", "b" and "c" — so a match coming from b or c
     never fills in the groups from the first branch, and $1 comes back empty.
     Define it as (?:a|b|c), or tick "Wrap each %ref% in (?:...)" to have the
     tester (and the generated code) add the group for you.
  2. A sub-pattern that can match nothing matches EVERYWHERE.  If every branch
     is optional — say ((a)|(b)?) — the pattern also matches the empty string
     between every pair of characters, and RegExReplace sprinkles the
     replacement right through the haystack.  The status bar counts
     zero-length matches, and the Hits column marks such placeholders with the
     empty-set sign.

PLACEHOLDERS  (this tester only)
  %name%   is swapped in from the table above before the regex is compiled.
  Placeholders may reference other placeholders; circular references are caught.
  A %name% with no matching definition stays in the pattern as literal text.
  Double-click a table row to insert its token at the caret.
  The Hits column counts that placeholder's own matches in the haystack.
  The AHK Code tab turns the references back into concatenated variables.

PATTERN BOX COLORS
  Press "Color Key" above the pattern box for the legend itself — every rule
  shown in the color it actually produces, which is not something this tab can
  do, being plain black text.  What follows is only what the colors MEAN.

  The palette is grouped by what things DO, so that things behaving alike look
  alike: green asserts a position and consumes nothing (^ $ \b \A, and the
  ?= ?! ?<= ?<! of a lookaround); teal matches a character; blue is repetition;
  orange is a character class; and ( and ) cycle through three colors by
  nesting depth, which is what makes the shape of a long alternation readable.

  WHITE ON RED means PCRE will refuse to compile the pattern.  It is never used
  for anything that merely looks unusual.  It marks: an unbalanced ( or ), an
  unclosed [ , a trailing \, a backslash-letter with no meaning (\q, \y), a
  quantifier with nothing to repeat, a backwards range such as [z-a], an
  unknown [:posix:] name, a reference to a group that does not exist, and two
  named groups sharing a name while J is unticked.

  Literal text — the words the pattern is actually looking for — sits on a pale
  green wash, merged into runs so that Mon|Tue|Wed reads as three words rather
  than as scattered letters.  An escaped metacharacter counts as literal and
  joins the run, so Mr\. Smith stays one block.  A useful side effect: a
  literal space, invisible in plain black, now shows up as a green gap.

  Conversely ] and } and a { that is not a quantifier are NOT errors — PCRE
  reads all three as ordinary characters — so they get a pale gray that says
  the bracket is not doing what it looks like, and nothing stronger.

  Put the caret beside any ( or ) and it lights up together with its partner,
  which is the quickest way to find the end of a long group.  Escaped and
  in-class brackets are skipped, because the pairing comes from the same parse
  that does the coloring rather than from counting brackets.

  A %name% on a pale blue background resolves to a placeholder in the table; on
  a pink background it does not, which usually means a typo in the name, and it
  will be matched as literal text rather than expanded.  Placeholders are
  painted over everything else, including inside character classes, because
  that is where they are substituted too.

  Set PAT_FULL_SYNTAX := false near the top of the script to color only the
  placeholders, leave everything else black, and switch off the paren pairing.

SNIPPETS
  Nothing is recorded automatically.  Press "Add Snippet" to bank the pattern
  currently in the box; the Snippets button lists what you have saved, newest
  first, and picking one loads it.  Adding a pattern that is already saved
  just moves it back to the top rather than duplicating it.
  The menu also offers "Remove the entry I pick next" and "Clear all
  snippets".  Snippets are stored in the session file.
  The pattern you are working on is saved with the session independently of
  the snippets, so it is still there next time whether or not you banked it.
    )"
}

; ============================== HOTKEYS ===================================
#HotIf RT.gui && WinActive("ahk_id " RT.gui.Hwnd)
F5::RunTest()
^s::SaveSession(true)
#HotIf
