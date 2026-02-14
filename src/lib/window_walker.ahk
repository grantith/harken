global Config

; Window selector UI (fuzzy list + activation).
class WindowWalker
{
    static gui := ""
    static search_edit := ""
    static list_view := ""
    static windows := []
    static filtered := []
    static focus_timer := ""
    static nav_hotkeys_ready := false
    static visible := false
    static image_list := ""
    static icon_cache := Map()
    static corner_radius := 8
    static excluded_exes := Map(
        "applicationframehost", true,
        "lockapp", true,
        "searchexperiencehost", true,
        "searchhost", true,
        "searchapp", true,
        "searchui", true,
        "shellexperiencehost", true,
        "startmenuexperiencehost", true,
        "systemsettings", true,
        "textinputhost", true
    )

    static Show(*)
    {
        if !Config.Has("window_selector") || !Config["window_selector"]["enabled"]
            return

        WindowWalker.EnsureGui()
        WindowWalker.EnsureNavigationHotkeys()
        WindowWalker.RefreshWindows()
        WindowWalker.ApplyFilter()
        WindowWalker.ShowCentered()
        WindowWalker.visible := true
        WindowWalker.search_edit.Focus()
        WindowWalker.StartFocusWatch()
    }

    static Toggle(*)
    {
        if WindowWalker.IsActive() {
            WindowWalker.Hide()
            return
        }
        WindowWalker.Show()
    }

    static Hide(*)
    {
        if WindowWalker.gui {
            WindowWalker.gui.Hide()
        }
        WindowWalker.visible := false
        WindowWalker.StopFocusWatch()
    }

    static IsActive(*)
    {
        return WindowWalker.visible && WindowWalker.gui && WinActive("ahk_id " WindowWalker.gui.Hwnd)
    }

    static EnsureGui()
    {
        if WindowWalker.gui
            return

        WindowWalker.gui := Gui("+AlwaysOnTop +ToolWindow -Caption", "harken Window Selector")
        WindowWalker.gui.MarginX := 12
        WindowWalker.gui.MarginY := 10
        WindowWalker.gui.SetFont("s10", "Segoe UI")

        WindowWalker.search_edit := WindowWalker.gui.AddEdit("w600", "")
        WindowWalker.search_edit.OnEvent("Change", (*) => WindowWalker.ApplyFilter())

        WindowWalker.list_view := WindowWalker.gui.AddListView("w600 r10 -Multi", ["App", "Title", "Desk"])
        WindowWalker.image_list := IL_Create(20)
        WindowWalker.list_view.SetImageList(WindowWalker.image_list, 1)
        WindowWalker.list_view.ModifyCol(1, 150)
        WindowWalker.list_view.ModifyCol(2, 360)
        WindowWalker.list_view.ModifyCol(3, 60)
        WindowWalker.list_view.OnEvent("DoubleClick", (*) => WindowWalker.ActivateSelected())

        WindowWalker.gui.OnEvent("Close", (*) => WindowWalker.Hide())
    }

    static ShowCentered()
    {
        WindowWalker.gui.Show("Hide AutoSize")
        WindowWalker.gui.GetPos(&x, &y, &w, &h)

        WindowWalker.GetActiveWorkArea(&left, &top, &right, &bottom)
        pos_x := left + (right - left - w) / 2
        pos_y := top + (bottom - top - h) / 2
        WindowWalker.gui.Show("x" pos_x " y" pos_y)
        WindowWalker.ApplyRoundedCorners(w, h)
    }

    static ApplyRoundedCorners(width := 0, height := 0)
    {
        if !WindowWalker.gui
            return
        if (!width || !height) {
            WindowWalker.gui.GetPos(,, &width, &height)
        }
        if (width <= 0 || height <= 0)
            return
        radius := WindowWalker.corner_radius
        try WinSetRegion("0-0 w" width " h" height " r" radius "-" radius, WindowWalker.gui)
    }

    static StartFocusWatch()
    {
        if !Config["window_selector"]["close_on_focus_loss"]
            return

        if !WindowWalker.focus_timer
            WindowWalker.focus_timer := ObjBindMethod(WindowWalker, "CheckFocus")
        SetTimer(WindowWalker.focus_timer, 0)
        SetTimer(WindowWalker.focus_timer, 120)
    }

    static StopFocusWatch()
    {
        if WindowWalker.focus_timer
            SetTimer(WindowWalker.focus_timer, 0)
    }

    static CheckFocus()
    {
        if !WindowWalker.visible || !WindowWalker.gui
            return
        if !WinActive("ahk_id " WindowWalker.gui.Hwnd)
            WindowWalker.Hide()
    }

    static EnsureNavigationHotkeys()
    {
        if WindowWalker.nav_hotkeys_ready
            return

        HotIf (*) => WindowWalker.IsActive()
        Hotkey("Up", (*) => WindowWalker.MoveSelection(-1))
        Hotkey("Down", (*) => WindowWalker.MoveSelection(1))
        Hotkey("^k", (*) => WindowWalker.MoveSelection(-1))
        Hotkey("^j", (*) => WindowWalker.MoveSelection(1))
        Hotkey("Enter", (*) => WindowWalker.ActivateSelected())
        Hotkey("Esc", (*) => WindowWalker.Hide())
        HotIf
        WindowWalker.nav_hotkeys_ready := true
    }

    static MoveSelection(delta)
    {
        if !WindowWalker.list_view
            return

        count := WindowWalker.list_view.GetCount()
        if (count = 0)
            return

        row := WindowWalker.list_view.GetNext(0, "F")
        if (row = 0)
            row := 1
        else {
            row += delta
            if (row < 1)
                row := count
            if (row > count)
                row := 1
        }

        WindowWalker.list_view.Modify(0, "-Select -Focus")
        WindowWalker.list_view.Modify(row, "Select Focus Vis")
    }

    static ActivateSelected()
    {
        if !WindowWalker.list_view
            return

        row := WindowWalker.list_view.GetNext(0, "F")
        if (row = 0)
            row := WindowWalker.list_view.GetNext(0, "S")
        if (row = 0)
            row := 1

        if (row < 1 || row > WindowWalker.filtered.Length)
            return

        hwnd := WindowWalker.filtered[row]["hwnd"]
        if !hwnd
            return

        WindowWalker.Hide()
        if WindowExistsAcrossDesktops(hwnd) {
            try {
                if (WinGetMinMax("ahk_id " hwnd) = -1)
                    WinRestore "ahk_id " hwnd
            }
            ActivateWindowAcrossDesktops(hwnd)
        }
    }

    static RefreshWindows()
    {
        WindowWalker.windows := []
        win_list := GetWindowsAcrossDesktops()
        bak_detect_hidden_windows := A_DetectHiddenWindows
        A_DetectHiddenWindows := true

        for _, hwnd in win_list {
            if WindowWalker.gui && (hwnd = WindowWalker.gui.Hwnd)
                continue

            if !WindowWalker.IsWindowEligible(hwnd)
                continue

            title := WinGetTitle("ahk_id " hwnd)
            if (Trim(title) = "")
                continue

            exe := WinGetProcessName("ahk_id " hwnd)
            if (exe = "")
                exe := "unknown"
            exe_path := ""
            try exe_path := WinGetProcessPath("ahk_id " hwnd)
            desktop_label := WindowWalker.DesktopLabel(hwnd)

            WindowWalker.windows.Push(Map(
                "hwnd", hwnd,
                "title", title,
                "exe", exe,
                "exe_path", exe_path,
                "desktop", desktop_label,
                "order", A_Index
            ))
        }

        A_DetectHiddenWindows := bak_detect_hidden_windows
    }

    static ApplyFilter()
    {
        if !WindowWalker.list_view || !WindowWalker.search_edit
            return

        query := Trim(WindowWalker.search_edit.Text)
        match_title := Config["window_selector"]["match_title"]
        match_exe := Config["window_selector"]["match_exe"]
        max_results := Config["window_selector"]["max_results"]
        preview_len := Config["window_selector"]["title_preview_len"]

        matches := []
        for _, win in WindowWalker.windows {
            match_text := WindowWalker.BuildMatchText(win, match_title, match_exe)
            score := WindowWalker.FuzzyScore(query, match_text)
            if (score < 0)
                continue
            matches.Push(Map(
                "score", score,
                "order", win["order"],
                "hwnd", win["hwnd"],
                "exe", win["exe"],
                "exe_display", WindowWalker.DisplayExe(win["exe"]),
                "exe_path", win["exe_path"],
                "title", win["title"],
                "title_preview", WindowWalker.TruncateText(win["title"], preview_len),
                "desktop", win["desktop"]
            ))
        }

        WindowWalker.SortMatches(matches)
        if (max_results > 0 && matches.Length > max_results) {
            while matches.Length > max_results
                matches.Pop()
        }

        WindowWalker.filtered := matches
        WindowWalker.list_view.Delete()

        for _, item in matches {
            icon_index := WindowWalker.GetIconIndex(item["exe"], item["exe_path"])
            WindowWalker.list_view.Add("Icon" icon_index, item["exe_display"], item["title_preview"], item["desktop"])
        }

        if (WindowWalker.list_view.GetCount() > 0)
            WindowWalker.list_view.Modify(1, "Select Focus Vis")
    }

    static BuildMatchText(win, match_title, match_exe)
    {
        text := ""
        if match_exe
            text := win["exe"]
        if match_title {
            if (text != "")
                text .= " "
            text .= win["title"]
        }
        return text
    }

    static IsWindowEligible(hwnd)
    {
        if !WindowExistsAcrossDesktops(hwnd)
            return false
        if Window.IsException("ahk_id " hwnd)
            return false

        try exe_name := WinGetProcessName("ahk_id " hwnd)
        catch
            return false
        exe_name := StrLower(exe_name)
        if (SubStr(exe_name, -4) = ".exe")
            exe_name := SubStr(exe_name, 1, -4)
        if WindowWalker.excluded_exes.Has(exe_name)
            return false

        if (!Config["window_selector"]["include_minimized"] && WinGetMinMax("ahk_id " hwnd) = -1)
            return false

        try ex_style := WinGetExStyle("ahk_id " hwnd)
        catch
            return false
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            return false
        try style := WinGetStyle("ahk_id " hwnd)
        catch
            return false
        allow_invisible := false
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(hwnd)
            if (desktop_num > 0 && desktop_num != VD.getCurrentDesktopNum())
                allow_invisible := true
        }
        if (!allow_invisible && !(style & 0x10000000))
            return false

        return true
    }

    static DesktopLabel(hwnd)
    {
        if !VirtualDesktopEnabled()
            return ""
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num = -1 || desktop_num = -2)
            return "all"
        if (desktop_num <= 0)
            return ""
        return desktop_num
    }

    static SortMatches(matches)
    {
        count := matches.Length
        if (count < 2)
            return

        loop count - 1 {
            i := A_Index
            loop count - i {
                j := A_Index
                a := matches[j]
                b := matches[j + 1]
                if (a["score"] < b["score"]) || (a["score"] = b["score"] && a["order"] > b["order"]) {
                    matches[j] := b
                    matches[j + 1] := a
                }
            }
        }
    }

    static FuzzyScore(query, text)
    {
        if (query = "")
            return 0

        q := StrLower(query)
        t := StrLower(text)
        q_len := StrLen(q)
        t_len := StrLen(t)
        if (q_len = 0 || t_len = 0)
            return -1

        qi := 1
        score := 0
        last_match := 0
        loop t_len {
            if (qi > q_len)
                break
            ti := A_Index
            if (SubStr(t, ti, 1) = SubStr(q, qi, 1)) {
                score += 10
                if (ti = last_match + 1)
                    score += 5
                if (ti = 1 || WindowWalker.IsWordBoundary(SubStr(t, ti - 1, 1)))
                    score += 3
                last_match := ti
                qi += 1
            }
        }

        if (qi <= q_len)
            return -1

        score += Max(0, 30 - t_len)
        return score
    }

    static IsWordBoundary(char)
    {
        return InStr(" _-./\\()[]{}", char)
    }

    static TruncateText(text, max_len)
    {
        if (max_len <= 0)
            return ""
        if (StrLen(text) <= max_len)
            return text
        if (max_len <= 3)
            return SubStr(text, 1, max_len)
        return SubStr(text, 1, max_len - 3) "..."
    }

    static DisplayExe(exe)
    {
        if (exe = "")
            return exe
        return RegExReplace(exe, "(?i)\.exe$", "")
    }

    static GetIconIndex(exe, exe_path)
    {
        if (exe_path != "" && WindowWalker.icon_cache.Has(exe_path))
            return WindowWalker.icon_cache[exe_path]
        if (exe_path = "" && WindowWalker.icon_cache.Has(exe))
            return WindowWalker.icon_cache[exe]

        icon_index := 0
        if (exe_path != "") {
            try icon_index := IL_Add(WindowWalker.image_list, exe_path, 1)
        }
        if (!icon_index) {
            try icon_index := IL_Add(WindowWalker.image_list, "shell32.dll", 1)
        }
        if (!icon_index)
            icon_index := 1

        cache_key := exe_path != "" ? exe_path : exe
        WindowWalker.icon_cache[cache_key] := icon_index
        return icon_index
    }

    static GetActiveWorkArea(&left, &top, &right, &bottom)
    {
        mon := ""
        try hwnd := WinGetID("A")
        if hwnd {
            try mon_handle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
            if mon_handle
                mon := WindowWalker.ConvertMonitorHandleToNumber(mon_handle)
        }
        if !mon
            mon := MonitorGetPrimary()
        MonitorGetWorkArea(mon, &left, &top, &right, &bottom)
    }

    static ConvertMonitorHandleToNumber(handle)
    {
        mon_handle_list := ""
        mon_callback := CallbackCreate(__EnumMonitors, "Fast", 4)

        if DllCall("EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", mon_callback, "UInt", 0) {
            loop parse, mon_handle_list, "`n"
                if (A_LoopField = handle)
                    return A_Index
        }
        return ""

        __EnumMonitors(hMonitor, hDevCon, pRect, args) {
            mon_handle_list .= hMonitor "`n"
            return true
        }
    }
}
