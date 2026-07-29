#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\Tools\RichEdit.ahk    ; <-- by "just me"; same copy SpeedReader uses
SetWorkingDir(A_ScriptDir)

; Distinguishes this script from the other AHK tools in the tray.  Bare try:
; if a future Windows drops imageres.dll we just keep the default icon.
; The hover text is set by UpdateTitle(), which also names the loaded session
; file -- deliberately not duplicated here, since APP_TITLE isn't declared
; until the TUNABLES block below.
try TraySetIcon("imageres.dll", 20)          ; a window with a green checkmark

;#################################
; App: REGEX TESTER for AHK v2
; By: kunkel321 (with Claude)
; Date: 7-29-2026
;#################################
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
global COLOR_DELAY  := 150             ; ms of idle before recolouring the pattern
global MAX_HISTORY  := 25              ; remembered patterns
global APP_TITLE    := "RegEx Tester for AHK v2"
global TIP_WIDTH    := 560             ; px before a hover tip wraps (see
                                       ;   TipMaxWidth; both tooltip libraries
                                       ;   default to "never wrap")

; --- pattern box syntax colours -------------------------------------------
; Set PAT_FULL_SYNTAX false to colour only the %placeholders% and leave the
; rest of the pattern plain black.
global PAT_FULL_SYNTAX := true
global PC_PH_FG    := 0x000090, PC_PH_BG    := 0xDCE9FF   ; %known% placeholder
global PC_BADPH_FG := 0x900000, PC_BADPH_BG := 0xFFD6D6   ; %unknown% placeholder
global PC_BAD_FG   := 0xFFFFFF, PC_BAD_BG   := 0xD04040   ; unbalanced ( or [
global PC_ESC      := 0x008080         ; \d \b \s \1 ...
global PC_CLASS    := 0xB05000         ; [abc] character class
global PC_QUANT    := 0x0060C0         ; * + ? {2,5}
global PC_ALT      := 0xC000C0         ; |
global PC_ANCHOR   := 0x008000         ; ^ $
global PC_DOT      := 0x909000         ; .
global PC_SPECIAL  := 0x707070         ; (?i) inline options
global PC_COMMENT  := 0x808080         ; (?#...) and, with x, #comments
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
    static Shading  := false       ; suppresses EN_CHANGE while we recolour
    static PatShading := false     ; ditto, for the pattern box
    static LastPatText := ""       ; pattern text as of the last recolour
    static History  := []          ; saved patterns, newest first
    static HistDelete := false     ; next history pick removes instead of loads
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
    static cbPh := ""              ; "Show && use sub-pattern placeholders", lblPat := "", lblSubj := "", lblEol := ""
    static btnAdd := "", btnDel := "", btnUp := "", btnDn := ""
    static rePattern := "", edMoreOpts := "", edEffective := ""
    static btnHist := "", btnAddHist := ""
    static lblOpts := "", lblMore := "", lblEff := "", cbWrap := ""
    static rdMatch := "", rdReplace := "", lblRepl := "", edRepl := ""
    static lblLimit := "", edLimit := "", cbAll := "", cbLive := ""
    static ddlEol := "", cbShade := "", btnRun := ""
    static reSubject := "", tabs := ""
    static lvMatches := "", lvGroups := "", edReplaced := ""
    static edCode := "", edCheat := "", sb := ""
    static optBoxes := Map()
    static cbTips := ""            ; "Show tips on hover"
    ; One LVHeaderToolTips instance per ListView.  They must outlive BuildGui,
    ; because each one owns a watchdog timer that re-reads the header rects.
    static TipsPh := "", TipsMatch := "", TipsGroup := ""
}

BuildGui()
LoadSession()                  ; may overwrite RT.WinW / RT.WinH
ApplyPhVisible()               ; before the first layout, so nothing flashes
UpdateTitle()                  ; LoadSession bails to the demo when there is no
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
    mFile.Add("Load &demo (OutlookMagnet)", (*) => LoadDemo())
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
    RT.cbPh := g.Add("CheckBox", "x10 y10 w700 h20 Checked",
        "Show && use sub-pattern placeholders   —   double-click a row to insert %name% into the pattern")
    RT.cbPh.OnEvent("Click", (*) => TogglePh())
    ; Top-right corner.  OnSizeGui pins it to the right edge and shortens
    ; lblPh to match.
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
    RT.edPhPat  := g.Add("Edit", "x136 y146 w680 h22", "")
    RT.edPhName.OnEvent("Change", (*) => PhEdited())
    RT.edPhPat.OnEvent("Change",  (*) => PhEdited())

    ; ---------- main pattern ----------
    FontUI(g)
    RT.lblPat := g.Add("Text", "x10 y176 w700 h20 +0x200", "Pattern   (raw PCRE — use %name% to pull in a placeholder)")
    RT.btnAddHist := g.Add("Button", "x706 y174 w110 h22", "Add to History")
    RT.btnAddHist.OnEvent("Click", (*) => AddCurrentToHistory())
    RT.btnHist := g.Add("Button", "x820 y174 w96 h22", "History  " Chr(0x25BE))
    RT.btnHist.OnEvent("Click", (*) => ShowHistoryMenu())

    ; Also a rich edit, so placeholders and regex syntax can be coloured.
    RT.rePattern := RichEdit(g, "x10 y196 w900 h48")
    RT.rePattern.SetDefaultFont({Name: SUBJ_FONT, Size: SUBJ_SIZE})
    RT.rePattern.WordWrap(true)
    HideHScroll(RT.rePattern.Hwnd)      ; word wrap is on, so it can never scroll
    RT.rePattern.SetEventMask(["CHANGE"])
    RT.rePattern.OnCommand(0x0300, (*) => PatternChanged())     ; EN_CHANGE

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
    RT.edEffective := g.Add("Edit", "x10 y300 w900 h40 +Multi +ReadOnly", "")

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

    ; The haystack is a rich edit control so matches can be shaded in place.
    RT.reSubject := RichEdit(g, "x10 y402 w1000 h120")
    RT.reSubject.SetDefaultFont({Name: SUBJ_FONT, Size: SUBJ_SIZE})
    RT.reSubject.WordWrap(true)
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
    if (MinMax = -1 || !RT.lvPh)
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
    phLvH := 110, patH := 48, effH := 40
    ; The placeholder block is optional.  Hidden, its rows cost nothing and the
    ; whole height goes to the haystack and the results tabs instead; the row 1
    ; strip holding the two checkboxes always stays.
    phShown := PhOn()
    phBlockH := phShown ? (phLvH + sp + rowH + sp * 2) : sp
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
    subjH := Max(60, Integer(spare / 2))
    tabsH := Max(150, spare - subjH)

    y := m
    tipsW := 164
    RT.cbPh.Move(m, y, Max(120, innerW - tipsW - sp), lblH)
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
        RT.edPhPat.Move(m + 136, y, innerW - 136, rowH - 2)
        y += rowH + sp * 2
    } else {
        y += sp                         ; keep phBlockH and the layout in step
    }

    RT.lblPat.Move(m, y, Max(160, innerW - 226), lblH)
    RT.btnAddHist.Move(m + innerW - 212, y - 2, 110, lblH + 2)
    RT.btnHist.Move(m + innerW - 96, y - 2, 96, lblH + 2)
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
    y += lblH
    RT.reSubject.Move(m, y, innerW, subjH)
    y += subjH + sp

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
PhOn() {
    return (RT.cbPh && RT.cbPh.Value) ? true : false
}

TogglePh() {
    ApplyPhVisible()
    ScheduleRun()                  ; the effective pattern just changed meaning
    SchedulePatternColors()
    on := PhOn()
    Status(on ? "Placeholder support on."
              : "Placeholder support off -- %name% is now matched as literal text.")
}

ApplyPhVisible() {
    on := PhOn()
    for c in [RT.lvPh, RT.btnAdd, RT.btnDel, RT.btnUp, RT.btnDn, RT.edPhName, RT.edPhPat]
        c.Visible := on
    RT.cbWrap.Enabled := on        ; nothing left to wrap
    ; Don't poll a header nobody can see.
    if (RT.TipsPh is LVHeaderToolTips)
        RT.TipsPh.Enabled := on && RT.cbTips.Value
    if (RT.Shown)
        OnSizeGui(RT.gui, 0, RT.WinW, RT.WinH)
}

; The pattern box has word wrap on, so its horizontal scroll bar can never do
; anything -- but the control still reserves and paints one.  Strip WS_HSCROLL
; along with ES_DISABLENOSCROLL (which is what keeps a dead bar visible instead
; of hidden) and ask for a frame recalc so the space is actually given back.
HideHScroll(hwnd) {
    static GWL_STYLE := -16
    static WS_HSCROLL := 0x00100000, ES_DISABLENOSCROLL := 0x2000
    static SB_HORZ := 0
    static SWP_NOSIZE := 0x1, SWP_NOMOVE := 0x2, SWP_NOZORDER := 0x4, SWP_FRAMECHANGED := 0x20
    gwl := (A_PtrSize = 8) ? "GetWindowLongPtr" : "GetWindowLong"
    swl := (A_PtrSize = 8) ? "SetWindowLongPtr" : "SetWindowLong"
    st := DllCall(gwl, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
    DllCall(swl, "Ptr", hwnd, "Int", GWL_STYLE
          , "Ptr", st & ~WS_HSCROLL & ~ES_DISABLENOSCROLL, "Ptr")
    DllCall("ShowScrollBar", "Ptr", hwnd, "Int", SB_HORZ, "Int", 0)
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0
          , "UInt", SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED)
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
    CtrlToolTip(RT.edPhPat,
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
    CtrlToolTip(RT.btnAddHist,
        "Banks the current pattern in the History list.`n`n"
      . "Nothing is ever recorded automatically -- a pattern is remembered`n"
      . "only when you press this, so the list stays worth reading.")
    CtrlToolTip(RT.btnHist,
        "Recall, remove or clear a banked pattern.  The last " MAX_HISTORY "`n"
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
        "Tints each match in the haystack, alternating two colours so that`n"
      . "two matches which touch stay distinguishable.`n`n"
      . "Shading pushes entries onto the rich edit's undo stack, so Ctrl+Z`n"
      . "in that pane can take a few presses to reach your own typing.")

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
    RT.edPhName.Value := "", RT.edPhPat.Value := ""
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
    RT.edPhPat.Value  := RT.PhMap[RT.PhNames[row]]
    RT.Loading := false
}

; Live edit of the selected row's name / pattern.
PhEdited() {
    if (RT.Loading || !RT.CurPh || RT.CurPh > RT.PhNames.Length)
        return
    oldName := RT.PhNames[RT.CurPh]
    newName := Trim(RT.edPhName.Value)
    newPat  := RT.edPhPat.Value

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
    SchedulePatternColors()
}

PatternChanged() {
    if (RT.PatShading)                       ; our own recolouring
        return
    if (PatternText() == RT.LastPatText)     ; formatting-only notification
        return
    SchedulePatternColors()
    ScheduleRun()
}

; Colouring is scheduled independently of ScheduleRun() so that the pattern
; box stays live even when the "Live" checkbox is off — it costs nothing,
; since it never runs the regex against the haystack.
SchedulePatternColors() {
    if (RT.Loading)
        return
    SetTimer(ApplyPatternColors, -COLOR_DELAY)
}

; Left-to-right tokenizer.  It is a highlighter, not a validator: anything it
; can't classify is simply left in the default colour.  Returns an array of
; {s, e, fg, bg} runs using zero-based, end-exclusive offsets.
TokenizePattern(pat) {
    runs := [], openStack := [], depth := 0
    n := StrLen(pat), i := 1
    xMode := RT.optBoxes["x"].Value
    while (i <= n) {
        c := SubStr(pat, i, 1)

        ; --- %placeholder% : the whole point of this tester -----------------
        if (PhOn() && c = "%" && RegExMatch(pat, "A)%([A-Za-z_]\w*)%", &pm, i)) {
            known := RT.PhMap.Has(pm[1])
            runs.Push({s: i - 1, e: i - 1 + pm.Len,
                       fg: known ? PC_PH_FG : PC_BADPH_FG,
                       bg: known ? PC_PH_BG : PC_BADPH_BG})
            i += pm.Len
            continue
        }
        if (!PAT_FULL_SYNTAX) {
            i++
            continue
        }

        ; --- x-mode comment ------------------------------------------------
        if (xMode && c = "#") {
            e := InStr(pat, "`n", , i)
            e := e ? e - 1 : n
            runs.Push({s: i - 1, e: e, fg: PC_COMMENT, bg: ""})
            i := e + 1
            continue
        }

        ; --- escape sequence -----------------------------------------------
        if (c = "\") {
            len := 2
            if (SubStr(pat, i + 1, 1) = "x" && SubStr(pat, i + 2, 1) = "{")
                len := (cl := InStr(pat, "}", , i + 2)) ? cl - i + 1 : 2
            if (i = n)                                  ; trailing lone backslash
                runs.Push({s: i - 1, e: i, fg: PC_BAD_FG, bg: PC_BAD_BG})
            else
                runs.Push({s: i - 1, e: i - 1 + len, fg: PC_ESC, bg: ""})
            i += len
            continue
        }

        ; --- character class -----------------------------------------------
        if (c = "[") {
            j := i + 1
            if (SubStr(pat, j, 1) = "^")
                j++
            if (SubStr(pat, j, 1) = "]")                ; a leading ] is literal
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
            unterminated := (j > n)
            e := unterminated ? n : j
            runs.Push({s: i - 1, e: e, fg: unterminated ? PC_BAD_FG : PC_CLASS,
                       bg: unterminated ? PC_BAD_BG : ""})
            i := e + 1
            continue
        }

        ; --- groups ---------------------------------------------------------
        if (c = "(") {
            if RegExMatch(pat, "A)\(\?[imsxUXJ-]*\)", &gm, i) {          ; (?i) etc
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_SPECIAL, bg: ""})
                i += gm.Len
                continue
            }
            if RegExMatch(pat, "A)\(\?#[^)]*\)", &gm, i) {               ; comment
                runs.Push({s: i - 1, e: i - 1 + gm.Len, fg: PC_COMMENT, bg: ""})
                i += gm.Len
                continue
            }
            len := 1
            if (SubStr(pat, i + 1, 1) = "?") {
                len := RegExMatch(pat, "A)\(\?(P?<[A-Za-z_]\w*>|'[A-Za-z_]\w*'|<[=!]|[:=!>|])", &gm, i)
                     ? gm.Len : 2
            }
            openStack.Push(i - 1)
            runs.Push({s: i - 1, e: i - 1 + len,
                       fg: PC_PAREN[Mod(depth, PC_PAREN.Length) + 1], bg: ""})
            depth++
            i += len
            continue
        }
        if (c = ")") {
            if (depth > 0) {
                depth--
                openStack.Pop()
                runs.Push({s: i - 1, e: i, fg: PC_PAREN[Mod(depth, PC_PAREN.Length) + 1], bg: ""})
            } else {
                runs.Push({s: i - 1, e: i, fg: PC_BAD_FG, bg: PC_BAD_BG})
            }
            i++
            continue
        }

        ; --- the small fry ---------------------------------------------------
        if (c = "|")
            runs.Push({s: i - 1, e: i, fg: PC_ALT, bg: ""})
        else if (c = "*" || c = "+" || c = "?")
            runs.Push({s: i - 1, e: i, fg: PC_QUANT, bg: ""})
        else if (c = "{" && RegExMatch(pat, "A)\{\d+(,\d*)?\}", &qm, i)) {
            runs.Push({s: i - 1, e: i - 1 + qm.Len, fg: PC_QUANT, bg: ""})
            i += qm.Len
            continue
        }
        else if (c = "^" || c = "$")
            runs.Push({s: i - 1, e: i, fg: PC_ANCHOR, bg: ""})
        else if (c = ".")
            runs.Push({s: i - 1, e: i, fg: PC_DOT, bg: ""})
        i++
    }
    ; Anything still on the stack never got closed.  These are pushed last so
    ; they paint over the depth colour already applied to them.
    for openPos in openStack
        runs.Push({s: openPos, e: openPos + 1, fg: PC_BAD_FG, bg: PC_BAD_BG})
    return runs
}

ApplyPatternColors(*) {
    SetTimer(ApplyPatternColors, 0)
    if (!RT.rePattern)
        return
    ; Recolouring has to save and restore the selection, and doing that in the
    ; middle of a click-drag cancels the drag.  Wait until the button is up.
    if (GetKeyState("LButton", "P")) {
        SetTimer(ApplyPatternColors, -COLOR_DELAY)
        return
    }
    RE := RT.rePattern
    pat := PatternText()
    RT.LastPatText := pat

    RT.PatShading := true
    sel := RE.GetSel()
    scr := RE.GetScrollPos()
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)

    RE.SetSel(0, -1)
    RE.SetFont({Color: "Auto", BkColor: "Auto"})

    for r in TokenizePattern(pat) {
        RE.SetSel(r.s, r.e)
        RE.SetFont(r.bg = "" ? {Color: r.fg} : {Color: r.fg, BkColor: r.bg})
    }

    RE.SetSel(sel.S, sel.E)
    RE.SetScrollPos(scr.X, scr.Y)
    DllCall("user32\SendMessageW", "Ptr", RE.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("InvalidateRect", "Ptr", RE.Hwnd, "Ptr", 0, "Int", 1)
    RT.PatShading := false
}

; ============================== PATTERN HISTORY ===========================
; History is deliberate, not inferred: nothing is recorded unless you press
; "Add to History".  The pattern you are currently working on is saved with
; the session separately, so it survives a restart whether or not you bank it.
AddCurrentToHistory() {
    pat := PatternText()
    if (pat = "") {
        Status("Nothing to add — the pattern box is empty.")
        return
    }
    if (AddHistory(pat))
        Status("Added to history (" RT.History.Length " of " MAX_HISTORY ").")
    else
        Status("That pattern was already in the history; moved it to the top.")
    RT.rePattern.Focus()
}

; Returns true when the pattern was new, false when it was already present.
AddHistory(pat) {
    if (pat = "")
        return false
    for i, h in RT.History {
        if (h == pat) {                            ; already known -> promote it
            RT.History.RemoveAt(i)
            RT.History.InsertAt(1, pat)
            return false
        }
    }
    RT.History.InsertAt(1, pat)
    while (RT.History.Length > MAX_HISTORY)
        RT.History.Pop()
    return true
}

ShowHistoryMenu() {
    mh := Menu()
    if (!RT.History.Length) {
        mh.Add("(nothing saved yet — use Add to History)", (*) => 0)
        mh.Disable("(nothing saved yet — use Add to History)")
    } else {
        for i, h in RT.History {
            label := OneLine(h)
            if (StrLen(label) > 88)
                label := SubStr(label, 1, 88) Chr(0x2026)
            ; & is the menu accelerator marker, and the index keeps every
            ; label unique even when two entries truncate to the same text.
            mh.Add(i ".  " StrReplace(label, "&", "&&"), HistoryPick.Bind(i))
        }
        mh.Add()
        mh.Add("Remove the entry I pick next", (*) => (RT.HistDelete := true, ShowHistoryMenu()))
        mh.Add("Clear history", (*) => ClearHistory())
    }
    mh.Show()
}

HistoryPick(idx, *) {
    if (idx > RT.History.Length)
        return
    if (RT.HistDelete) {
        RT.HistDelete := false
        RT.History.RemoveAt(idx)
        Status("Removed that entry from the history.")
        return
    }
    SetPatternText(RT.History[idx])
    RunTest()
    RT.rePattern.Focus()
}

ClearHistory() {
    RT.History := []
    Status("Pattern history cleared.")
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
    if (RT.cbLive && !RT.cbLive.Value)
        return
    SetTimer(RunTest, -RUN_DELAY)
}

SubjectChanged() {
    if (RT.Shading)                      ; our own recolouring, not a real edit
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
        ShowError(e.Message)
        return
    }
    opts := BuildOptions()
    needle := opts ")" expanded
    RT.edEffective.Value := needle

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
    RT.edPhName.Value := "", RT.edPhPat.Value := "", RT.CurPh := 0
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
    for h in RT.History
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
        LoadDemo()
        return
    }
    try {
        txt := FileRead(path, "UTF-8")
    } catch {
        LoadDemo()
        return
    }
    RT.SessionFile := path         ; "Open session" adopts it too -- see above
    UpdateTitle()
    RT.Loading := true
    RT.PhNames := [], RT.PhMap := Map(), RT.CurPh := 0
    RT.History := []
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
            case "WINW":    RT.WinW := ClampSize(val, true)
            case "WINH":    RT.WinH := ClampSize(val, false)
            case "EOL":     RT.ddlEol.Value := Max(1, Min(3, Integer(val)))
            case "LIMIT":   RT.edLimit.Value := Dec(val)
            case "PAT":     SetPatternText(Dec(val))
            case "REPL":    RT.edRepl.Value := Dec(val)
            case "SUBJ":    subj := Dec(val)
            case "HIST":    RT.History.Push(Dec(val))
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
    RT.edPhName.Value := "", RT.edPhPat.Value := ""
    SetPatternText(""), RT.edRepl.Value := ""
    SetSubjectText("")
    RT.Loading := false
    SchedulePatternColors()
    RunTest()
}

LoadDemo() {
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

PATTERN BOX COLOURS
  A %name% on a pale blue background resolves to a placeholder in the table.
  A %name% on a pink background does NOT — usually a typo in the name, and it
  will be matched as literal text rather than expanded.
  White on red marks an unbalanced ( or ), an unclosed [ , or a trailing \.
  Nested groups cycle through three colours by depth, which makes the shape of
  a long alternation much easier to read.
  Escapes, character classes, quantifiers, | and anchors each get their own
  colour.  Set PAT_FULL_SYNTAX := false near the top of the script to colour
  only the placeholders and leave everything else black.

PATTERN HISTORY
  Nothing is recorded automatically.  Press "Add to History" to bank the
  pattern currently in the box; the History button lists what you have saved,
  newest first, and picking one loads it.  Adding a pattern that is already
  saved just moves it back to the top rather than duplicating it.
  The history menu also offers "Remove the entry I pick next" and
  "Clear history".  History is stored in the session file.
  The pattern you are working on is saved with the session independently of
  the history, so it is still there next time whether or not you banked it.
    )"
}

; ============================== HOTKEYS ===================================
#HotIf RT.gui && WinActive("ahk_id " RT.gui.Hwnd)
F5::RunTest()
^s::SaveSession(true)
#HotIf
