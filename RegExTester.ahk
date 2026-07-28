#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\Tools\RichEdit.ahk ; https://www.autohotkey.com/boards/viewtopic.php?t=117275
SetWorkingDir(A_ScriptDir)
;#################################
; App: REGEX TESTER for AHK v2
; By: kunkel321 (with Claude)
; Date: 7-28-2026
; AHK Forum: https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140951
; GitHub: https://github.com/kunkel321/RegExTester
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

TraySetIcon("imageres.dll",20) ; A window with a green checkmark.

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

    static SessionFile := A_ScriptDir "\RegExTesterSession.txt"

    ; --- gui + controls ---
    static gui := "", lvPh := "", edPhName := "", edPhPat := ""
    static lblPh := "", lblPat := "", lblSubj := "", lblEol := ""
    static btnAdd := "", btnDel := "", btnUp := "", btnDn := ""
    static rePattern := "", edMoreOpts := "", edEffective := ""
    static btnHist := "", btnAddHist := ""
    static lblOpts := "", lblMore := "", lblEff := ""
    static rdMatch := "", rdReplace := "", lblRepl := "", edRepl := ""
    static lblLimit := "", edLimit := "", cbAll := "", cbLive := ""
    static ddlEol := "", cbShade := "", btnRun := ""
    static reSubject := "", tabs := ""
    static lvMatches := "", lvGroups := "", edReplaced := ""
    static edCode := "", edCheat := "", sb := ""
    static optBoxes := Map()
}

BuildGui()
LoadSession()
; Controls are created at rough coordinates and then positioned by OnSizeGui.
; Running the layout once before Show() means the first paint already has
; everything in its final spot, so there is no ghosting pass at startup.
OnSizeGui(RT.gui, 0, 1040, 820)
RT.gui.Show("w1040 h820")
RunTest()
return

; ============================== GUI =======================================
BuildGui() {
    g := Gui("+Resize +MinSize820x620", "RegEx Tester for AHK v2")
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
    RT.lblPh := g.Add("Text", "x10 y10 w700", "Sub-pattern placeholders   —   double-click a row to insert %name% into the pattern")

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

    DllCall("user32\SendMessageW", "Ptr", guiObj.Hwnd, "UInt", WM_SETREDRAW, "Ptr", 0, "Ptr", 0)

    m := 10, sp := 6, rowH := 24, lblH := 20, btnW := 80
    sbH := 24
    try RT.sb.GetPos(, , , &sbH)
    if (!sbH)
        sbH := 24                       ; not yet measurable before the first Show

    innerW := W - m * 2
    phLvH := 110, patH := 48, effH := 40
    fixed := lblH + phLvH + sp + rowH + sp * 2
           + lblH + patH + sp + rowH + sp
           + lblH + effH + sp * 2
           + rowH + sp * 2
           + lblH + sp + m * 2
    ; Spare vertical space is shared out: a little to the placeholder table,
    ; some to the haystack, the rest to the results tabs.
    flex := H - sbH - fixed
    phExtra := Max(0, Integer(flex * 0.15))
    phLvH += phExtra
    subjH := Max(60, Integer(flex * 0.30))
    tabsH := Max(150, flex - phExtra - subjH)

    y := m
    RT.lblPh.Move(m, y, innerW, lblH)
    y += lblH
    lvW := innerW - btnW - sp
    RT.lvPh.Move(m, y, lvW, phLvH)
    RT.lvPh.ModifyCol(1, 130), RT.lvPh.ModifyCol(3, 50)
    RT.lvPh.ModifyCol(2, Max(120, lvW - 130 - 50 - 26))
    bx := m + lvW + sp
    RT.btnAdd.Move(bx, y, btnW, rowH)
    RT.btnDel.Move(bx, y + 28, btnW, rowH)
    RT.btnUp.Move(bx, y + 56, btnW, rowH)
    RT.btnDn.Move(bx, y + 84, btnW, rowH)
    y += phLvH + sp
    RT.edPhName.Move(m, y, 130, rowH - 2)
    RT.edPhPat.Move(m + 136, y, innerW - 136, rowH - 2)
    y += rowH + sp * 2

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
        if (c = "%" && RegExMatch(pat, "A)%([A-Za-z_]\w*)%", &pm, i)) {
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
ExpandText(pat, visiting, unknown) {
    out := "", chunkStart := 1, pos := 1
    while (fp := RegExMatch(pat, "%([A-Za-z_]\w*)%", &m, pos)) {
        name := m[1]
        if RT.PhMap.Has(name) {
            if visiting.Has(name)
                throw Error("Circular placeholder reference: %" name "%")
            out .= SubStr(pat, chunkStart, fp - chunkStart)
            visiting[name] := true
            out .= ExpandText(RT.PhMap[name], visiting, unknown)
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
        expanded := ExpandText(PatternText(), Map(), unknown)
    } catch as e {
        RT.edEffective.Value := PatternText()
        ShowError(e.Message)
        return
    }
    opts := BuildOptions()
    needle := opts ")" expanded
    RT.edEffective.Value := needle

    warn := ""
    if (unknown.Count) {
        list := ""
        for k in unknown
            list .= (list = "" ? "" : ", ") "%" k "%"
        warn .= "  Undefined placeholder(s) left literal: " list "."
    }
    if RegExMatch(PatternText(), "^[imsxADJUXSC ``\t]*\)")
        warn .= "  Pattern starts with an option prefix — options belong in the checkboxes (Edit > Pull option prefix)."

    UpdatePhHits(opts, subj)

    if (RT.rdReplace.Value)
        DoReplace(needle, subj, warn)
    else
        DoMatch(needle, subj, warn)

    RT.edCode.Value := BuildAhkCode(expanded, opts)
}

DoMatch(needle, subj, warn) {
    RT.Matches := [], RT.Spans := []
    RT.lvMatches.Opt("-Redraw"), RT.lvMatches.Delete()
    RT.lvGroups.Delete()

    findAll := RT.cbAll.Value
    pos := 1, n := 0
    try {
        while (fp := RegExMatch(subj, needle, &mm, pos)) {
            RT.Matches.Push(mm)
            n++
            RT.lvMatches.Add(, n, mm.Pos, mm.Len, OneLine(mm[0]))
            if (!findAll)
                break
            pos := mm.Pos + Max(mm.Len, 1)          ; Max() guards zero-width matches
            if (pos > StrLen(subj) + 1 || n >= MAX_MATCHES)
                break
        }
    } catch as e {
        RT.lvMatches.Opt("+Redraw")
        ShowError(e.Message)
        return
    }
    RT.lvMatches.Opt("+Redraw")
    ClearError()

    RT.edReplaced.Value := ""
    ComputeSpans()
    ApplyShading()
    if (n) {
        ; Modify() raises ItemFocus synchronously; NoJump stops that handler
        ; from scrolling the haystack out from under whatever is being typed.
        RT.NoJump := true
        RT.lvMatches.Modify(1, "Select Focus")
        RT.NoJump := false
        MatchRowFocused(false)
    }

    Status((n = 0 ? "No match." : n " match" (n = 1 ? "" : "es") ".") warn)
}

DoReplace(needle, subj, warn) {
    RT.Matches := [], RT.Spans := []
    RT.lvMatches.Delete(), RT.lvGroups.Delete()
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

    ; Shade what WOULD be replaced, so the effect is visible in the haystack.
    try {
        pos := 1, n := 0
        while (fp := RegExMatch(subj, needle, &mm, pos)) {
            if (limit >= 0 && n >= limit)
                break
            RT.Matches.Push(mm)
            n++
            pos := mm.Pos + Max(mm.Len, 1)
            if (pos > StrLen(subj) + 1 || n >= MAX_MATCHES)
                break
        }
    } catch as e {
        RT.Matches := []                  ; shading is cosmetic; the count above stands
    }
    ComputeSpans()
    ApplyShading()
    Status(cnt " replacement" (cnt = 1 ? "" : "s") "." warn)
}

; Per-placeholder match count against the current haystack — handy for finding
; which sub-pattern is the one that isn't firing.
UpdatePhHits(opts, subj) {
    if (StrLen(subj) > 200000) {
        for i, name in RT.PhNames
            RT.lvPh.Modify(i, "Col3", "-")
        return
    }
    for i, name in RT.PhNames {
        hits := ""
        try {
            nd := opts ")" ExpandText("%" name "%", Map(), Map())
            p := 1, c := 0
            while (fp := RegExMatch(subj, nd, &mm, p)) {
                c++
                p := mm.Pos + Max(mm.Len, 1)
                if (p > StrLen(subj) + 1 || c >= 2000)
                    break
            }
            hits := c
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
    out := ""
    for p in SplitRefs(pat) {
        if (p.t = "lit") {
            if (p.v = "")
                continue
            out .= (out = "" ? "" : " ") Lit(AhkEsc(p.v))
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
        expanded := ExpandText(PatternText(), Map(), Map())
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
    ModeChanged()
    SchedulePatternColors()
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

Status(msg, isError := false) {
    RT.sb.SetText("  " (isError ? "ERROR: " : "") msg)
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
