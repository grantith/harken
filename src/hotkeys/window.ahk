global Config

resize_step := Config["window"]["resize_step"]
move_step := Config["window"]["move_step"]
super_double_tap_ms := Config["window"]["super_double_tap_ms"]
move_mode_enabled := Config["window"]["move_mode"]["enable"]
move_mode_cancel_key := Config["window"]["move_mode"]["cancel_key"]
; Window hotkeys (resize/move/cycle) and virtual desktop bindings.
center_cycle_hotkey := Config["window"]["center_width_cycle_hotkey"]
cycle_app_windows_hotkey := Config["window"]["cycle_app_windows_hotkey"]
cycle_app_windows_current_hotkey := Config["window"]["cycle_app_windows_current_hotkey"]
vd_config := Config.Has("virtual_desktop") ? Config["virtual_desktop"] : Map()
vd_prev_hotkey := vd_config.Has("prev_hotkey") ? vd_config["prev_hotkey"] : ""
vd_next_hotkey := vd_config.Has("next_hotkey") ? vd_config["next_hotkey"] : ""
vd_move_prev_hotkey := vd_config.Has("move_prev_hotkey") ? vd_config["move_prev_hotkey"] : ""
vd_move_next_hotkey := vd_config.Has("move_next_hotkey") ? vd_config["move_next_hotkey"] : ""
vd_desktop_hotkeys := vd_config.Has("desktop_hotkeys") ? vd_config["desktop_hotkeys"] : []
vd_goto_hotkeys := vd_config.Has("goto_hotkeys") ? vd_config["goto_hotkeys"] : []
vd_move_hotkeys := vd_config.Has("move_hotkeys") ? vd_config["move_hotkeys"] : []
minimize_others_hotkey := ""
if Config["window"].Has("minimize_others_hotkey")
    minimize_others_hotkey := Config["window"]["minimize_others_hotkey"]

vd_prev_hotkey := NormalizeAltHotkey(vd_prev_hotkey)
vd_next_hotkey := NormalizeAltHotkey(vd_next_hotkey)
vd_move_prev_hotkey := NormalizeAltHotkey(vd_move_prev_hotkey, true)
vd_move_next_hotkey := NormalizeAltHotkey(vd_move_next_hotkey, true)

last_super_tap := 0
max_restore := Map()
app_cycle_cache := Map()
cycle_hwnd_desktop := Map()
debug_logs_initialized := false

ResizeActiveWindow(delta_w, delta_h) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if IsAltPressed() || AltPressedSoon()
        return

    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)

    new_w := w + delta_w
    new_h := h + delta_h

    if (new_w <= 0 || new_h <= 0)
        return

    if (x < Screen.left)
        x := Screen.left
    if (y < Screen.top)
        y := Screen.top

    max_w := Screen.right - x
    max_h := Screen.bottom - y
    new_w := Min(new_w, max_w)
    new_h := Min(new_h, max_h)

    WinMoveEx(x, y, new_w, new_h, "ahk_id " hwnd)
}

ResizeActiveWindowCentered(delta_w, delta_h) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if IsAltPressed() || AltPressedSoon()
        return

    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)

    new_w := w + (delta_w * 2)
    new_h := h + (delta_h * 2)
    new_x := x - delta_w
    new_y := y - delta_h

    if (new_w <= 0 || new_h <= 0)
        return

    if (new_x < Screen.left) {
        new_w -= (Screen.left - new_x)
        new_x := Screen.left
    }
    if (new_y < Screen.top) {
        new_h -= (Screen.top - new_y)
        new_y := Screen.top
    }

    max_w := Screen.right - new_x
    max_h := Screen.bottom - new_y
    new_w := Min(new_w, max_w)
    new_h := Min(new_h, max_h)

    if (new_w <= 0 || new_h <= 0)
        return

    WinMoveEx(new_x, new_y, new_w, new_h, "ahk_id " hwnd)
}

MoveActiveWindow(delta_x, delta_y) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)

    new_x := x + delta_x
    new_y := y + delta_y

    min_x := Screen.left
    min_y := Screen.top
    max_x := Screen.right - w
    max_y := Screen.bottom - h

    new_x := Min(Max(new_x, min_x), max_x)
    new_y := Min(Max(new_y, min_y), max_y)

    WinMoveEx(new_x, new_y, w, h, "ahk_id " hwnd)
}

SortWindowList(list) {
    sorted := []
    for _, id in list
        sorted.Push(id)

    count := sorted.Length
    loop count - 1 {
        i := A_Index
        loop count - i {
            j := A_Index
            if (sorted[j] > sorted[j + 1]) {
                temp := sorted[j]
                sorted[j] := sorted[j + 1]
                sorted[j + 1] := temp
            }
        }
    }

    return sorted
}

IsAltPressed() {
    return GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")
}

AltPressedSoon() {
    if IsAltPressed()
        return true
    KeyWait "Alt", "D T0.05"
    return IsAltPressed()
}

NormalizeAltHotkey(hotkey_name, require_shift := false) {
    if !hotkey_name
        return ""
    normalized := hotkey_name
    if (SubStr(normalized, 1, 1) != "*")
        normalized := "*" normalized
    if !InStr(normalized, "!")
        normalized := "!" normalized
    if (require_shift && !InStr(normalized, "+"))
        normalized := "+" normalized
    return normalized
}


FilterWindowList(exe, list) {
    filtered := []
    for _, id in list {
        if !WindowExistsAcrossDesktops(id)
            continue
        try class_name := WinGetClass("ahk_id " id)
        catch
            continue
        if (exe = "explorer.exe") {
            if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd")
                continue
        }
        try ex_style := WinGetExStyle("ahk_id " id)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        try style := WinGetStyle("ahk_id " id)
        catch
            continue
        allow_invisible := false
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(id)
            if (desktop_num <= 0)
                allow_invisible := true
            else if (desktop_num != VD.getCurrentDesktopNum())
                allow_invisible := true
        }
        if (!allow_invisible && !(style & 0x10000000))
            continue
        filtered.Push(id)
    }
    return filtered
}

ApplyDesktopCyclePreference(list, current_only := false) {
    if !VirtualDesktopEnabled()
        return list

    current := []
    other := []
    for _, id in list {
        desktop_num := GetWindowDesktopForCycle(id)
        is_current := (desktop_num > 0 && desktop_num = VD.getCurrentDesktopNum())
        if is_current
            current.Push(id)
        else if !current_only
            other.Push(id)
    }

    if current_only
        return current

    if !Config["virtual_desktop"]["cycle_prefer_current"]
        return list

    ordered := []
    for _, id in current
        ordered.Push(id)
    for _, id in other
        ordered.Push(id)
    return ordered
}

ApplyCurrentDesktopOrder(exe, win_list, active_hwnd, current_only := false) {
    if !VirtualDesktopEnabled()
        return win_list
    current_order := GetCurrentDesktopOrderedList(exe)
    current_set := Map()
    for _, id in current_order
        current_set[id] := true

    ; Current-desktop ordering uses visible windows to avoid skipping local tiles.
    if (current_order.Length = 0) {
        if (current_only && active_hwnd && WindowExistsAcrossDesktops(active_hwnd))
            return [active_hwnd]
        return win_list
    }

    if current_only {
        ; Keep stable ordering to avoid z-order oscillation while cycling.
        ordered := []
        for _, id in win_list {
            if current_set.Has(id)
                ordered.Push(id)
        }
        return ordered
    }

    if !Config["virtual_desktop"]["cycle_prefer_current"]
        return win_list

    ; Preserve win_list order while preferring current desktop windows first.
    ordered := []
    for _, id in win_list {
        if current_set.Has(id)
            ordered.Push(id)
    }
    for _, id in win_list {
        if !current_set.Has(id)
            ordered.Push(id)
    }
    return ordered
}

GetCurrentDesktopWindowSet(exe) {
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := false
    list := WinGetList("ahk_exe " exe)
    A_DetectHiddenWindows := bak_detect_hidden_windows

    list := FilterCurrentDesktopWindowList(exe, list)
    set := Map()
    for _, id in list
        set[id] := true
    return set
}

GetCurrentDesktopOrderedList(exe) {
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := false
    list := WinGetList("ahk_exe " exe)
    A_DetectHiddenWindows := bak_detect_hidden_windows

    return FilterCurrentDesktopWindowList(exe, list)
}

FilterCurrentDesktopWindowList(exe, list) {
    filtered := []
    for _, id in list {
        if !WinExist("ahk_id " id)
            continue
        try class_name := WinGetClass("ahk_id " id)
        catch
            continue
        if (exe = "explorer.exe") {
            if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd")
                continue
        }
        try ex_style := WinGetExStyle("ahk_id " id)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        filtered.Push(id)
    }
    return filtered
}

GetWindowDesktopForCycle(hwnd) {
    desktop_num := GetWindowDesktopNum(hwnd)
    if (desktop_num > 0)
        return desktop_num
    if cycle_hwnd_desktop.Has(hwnd)
        return cycle_hwnd_desktop[hwnd]
    return 0
}

CycleDebugEnabled() {
    if !Config.Has("virtual_desktop")
        return false
    return Config["virtual_desktop"].Has("debug_cycle") && Config["virtual_desktop"]["debug_cycle"]
}

HotkeyDebugEnabled() {
    if !Config.Has("virtual_desktop")
        return false
    return Config["virtual_desktop"].Has("debug_hotkeys") && Config["virtual_desktop"]["debug_hotkeys"]
}

EnsureDebugLogInit() {
    global debug_logs_initialized
    if debug_logs_initialized
        return
    if !(CycleDebugEnabled() || HotkeyDebugEnabled())
        return
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    if CycleDebugEnabled() {
        TryResetLogFile(log_dir "\\cycle.debug.log")
    }
    if HotkeyDebugEnabled() {
        TryResetLogFile(log_dir "\\vd.hotkeys.log")
        TryResetLogFile(log_dir "\\vd.actions.log")
    }
    debug_logs_initialized := true
}

TryResetLogFile(path) {
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend("", path)
    }
}

LogCycleDebug(lines) {
    if !CycleDebugEnabled()
        return
    EnsureDebugLogInit()
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    log_path := log_dir "\\cycle.debug.log"
    header := "[" A_Now "] "
    if !(lines is Array)
        lines := [lines]
    for _, line in lines {
        FileAppend(header line "`n", log_path)
    }
}

LogVirtualDesktopHotkeys(lines) {
    if !HotkeyDebugEnabled()
        return
    EnsureDebugLogInit()
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.hotkeys.log"
    header := "[" A_Now "] "
    if !(lines is Array)
        lines := [lines]
    for _, line in lines {
        FileAppend(header line "`n", log_path)
    }
}

LogVirtualDesktopAction(lines) {
    if !HotkeyDebugEnabled()
        return
    EnsureDebugLogInit()
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.actions.log"
    header := "[" A_Now "] "
    if !(lines is Array)
        lines := [lines]
    for _, line in lines {
        FileAppend(header line "`n", log_path)
    }
}

RegisterDesktopHotkey(kind, hotkey_name, desktop_num, callback) {
    if (hotkey_name = "")
        return
    Hotkey(hotkey_name, (*) => (
        LogVirtualDesktopAction(kind " hotkey=" hotkey_name " desktop=" desktop_num " current=" GetCurrentDesktopNumFresh()),
        callback()
    ))
}

GetCycleDebugDir() {
    appdata := EnvGet("APPDATA")
    if appdata
        return appdata "\\harken"
    return GetConfigDir()
}

UpdateAppCycleCache(exe, win_list) {
    if !app_cycle_cache.Has(exe)
        app_cycle_cache[exe] := Map()

    cache := app_cycle_cache[exe]
    for _, hwnd in win_list {
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num > 0)
            cache[hwnd] := desktop_num
        else if !cache.Has(hwnd)
            cache[hwnd] := 0
        if (desktop_num > 0)
            cycle_hwnd_desktop[hwnd] := desktop_num
    }

    for hwnd, _ in cache {
        if !WindowExistsAcrossDesktops(hwnd)
            cache.Delete(hwnd)
    }

    return cache
}

BuildCycleWindowList(exe, win_list) {
    if !VirtualDesktopEnabled()
        return win_list

    ; Cache app windows seen across desktops since WinGetList can hide off-desktop windows.
    cache := UpdateAppCycleCache(exe, win_list)
    if (cache.Count = 0)
        return win_list

    dedup := Map()
    merged := []
    for _, hwnd in win_list {
        dedup[hwnd] := true
        merged.Push(hwnd)
    }
    for hwnd, _ in cache {
        if !dedup.Has(hwnd) {
            merged.Push(hwnd)
            dedup[hwnd] := true
        }
    }
    return merged
}

HandleSuperTap() {
    global last_super_tap, super_double_tap_ms

    if Window.IsMoveMode() {
        Window.SetMoveMode(false)
        UpdateCommandToastVisibility()
        return
    }

    if (A_TickCount - last_super_tap <= super_double_tap_ms) {
        Window.SetMoveMode(true)
        UpdateCommandToastVisibility()
        last_super_tap := 0
        return
    }

    last_super_tap := A_TickCount
}

OnSuperKeyUp() {
    global move_mode_enabled
    if move_mode_enabled
        HandleSuperTap()
    if ReloadModeActive() {
        global reload_mode_activated_at
        if (A_TickCount - reload_mode_activated_at < 500) {
            UpdateCommandToastVisibility()
            return
        }
        ClearReloadMode()
    }
    UpdateCommandToastVisibility()
}

RegisterSuperKeyHotkey("", " up", (*) => OnSuperKeyUp())

Hotkey("~LButton", (*) => BeginSuperDrag())

CenterWidthCycle(*) {
    static state := 0
    state := Mod(state + 1, 3)

    hwnd := WinExist("A")
    if !hwnd
        return

    ; Restore if maximized so Move works correctly
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    ; Get work area of current monitor
    MonitorGetWorkArea(MonitorGetPrimary(), &mx1, &my1, &mx2, &my2)
    mw := mx2 - mx1
    mh := my2 - my1

    left_margin := Screen.left_margin
    right_margin := Screen.right_margin
    top_margin := Screen.top_margin
    bottom_margin := Screen.bottom_margin
    gap_px := Config["window_manager"]["gap_px"]

    mx1 += left_margin
    mw := mw - left_margin - right_margin
    mh := mh - top_margin - bottom_margin

    if (gap_px > 0) {
        mx1 += gap_px
        my1 += gap_px
        mw -= gap_px * 2
        mh -= gap_px * 2
    }

    if (mw <= 0 || mh <= 0)
        return

    if (state = 0) {
        ; center 1/3
        w := mw / 3
    } else if (state = 1) {
        ; center 1/2
        w := mw / 2
    } else {
        ; center 2/3
        w := mw * 2 / 3
    }

    w := Min(w, mw)
    x := mx1 + (mw - w) / 2
    y := my1 + top_margin

    WinMove x, y, w, mh, "ahk_id " hwnd
}

ToggleMaximize(*) {
    hwnd := WinExist("A")
    if !hwnd
        return

    coords := Window.GetCurrentPosition()
    if Window.IsMaximized(coords) {
        if max_restore.Has(hwnd) {
            saved := max_restore[hwnd]
            WinRestore "ahk_id " hwnd
            WinMoveEx(saved.x, saved.y, saved.w, saved.h, "ahk_id " hwnd)
        }
        return
    }

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)
    max_restore[hwnd] := { x: x, y: y, w: w, h: h }
    Window.Maximize()
}

CloseWindow(*) {
    hwnd := WinExist("A")
    if !hwnd
        return
    WinClose "ahk_id " hwnd
}

MinimizeWindow(*) {
    hwnd := WinExist("A")
    if !hwnd
        return
    WinMinimize "ahk_id " hwnd
    ActivateMostRecentWindow(hwnd)
}

CycleAppWindows(*) {
    hwnd := WinExist("A")
    if !hwnd
        return

    exe := WinGetProcessName("ahk_id " hwnd)
    if !exe
        return

    win_list := GetWindowsAcrossDesktops("ahk_exe " exe)
    win_list := FilterWindowList(exe, win_list)
    win_list := BuildCycleWindowList(exe, win_list)
    if (win_list.Length < 2)
        return

    if CycleDebugEnabled() {
        lines := []
        lines.Push("cycle_all exe=" exe " active=" Format("0x{:X}", hwnd) " current_desktop=" GetCurrentDesktopNumFresh() " cache_count=" (app_cycle_cache.Has(exe) ? app_cycle_cache[exe].Count : 0))
        for _, id in win_list {
            desktop_num := GetWindowDesktopNum(id)
            exists := WindowExistsAcrossDesktops(id) ? "1" : "0"
            lines.Push("  hwnd=" Format("0x{:X}", id) " desktop=" desktop_num " exists=" exists)
        }
        LogCycleDebug(lines)
    }

    found_current := false
    for _, id in win_list {
        if (id = hwnd) {
            found_current := true
            break
        }
    }
    if (!found_current && WindowExistsAcrossDesktops(hwnd))
        win_list.Push(hwnd)

    win_list := SortWindowList(win_list)
    win_list := ApplyDesktopCyclePreference(win_list, false)
    win_list := ApplyCurrentDesktopOrder(exe, win_list, hwnd, false)
    if (win_list.Length < 2)
        return

    current_index := 0
    for i, id in win_list {
        if (id = hwnd) {
            current_index := i
            break
        }
    }

    next_index := (current_index >= win_list.Length || current_index = 0) ? 1 : current_index + 1
    ActivateNextAvailableWindow(win_list, next_index)
}

CycleAppWindowsCurrent(*) {
    hwnd := WinExist("A")
    if !hwnd
        return

    exe := WinGetProcessName("ahk_id " hwnd)
    if !exe
        return

    win_list := GetWindowsAcrossDesktops("ahk_exe " exe)
    win_list := FilterWindowList(exe, win_list)
    win_list := BuildCycleWindowList(exe, win_list)
    if (win_list.Length < 2)
        return

    if CycleDebugEnabled() {
        lines := []
        lines.Push("cycle_current exe=" exe " active=" Format("0x{:X}", hwnd) " current_desktop=" GetCurrentDesktopNumFresh() " cache_count=" (app_cycle_cache.Has(exe) ? app_cycle_cache[exe].Count : 0))
        for _, id in win_list {
            desktop_num := GetWindowDesktopNum(id)
            exists := WindowExistsAcrossDesktops(id) ? "1" : "0"
            lines.Push("  hwnd=" Format("0x{:X}", id) " desktop=" desktop_num " exists=" exists)
        }
        LogCycleDebug(lines)
    }

    found_current := false
    for _, id in win_list {
        if (id = hwnd) {
            found_current := true
            break
        }
    }
    if (!found_current && WindowExistsAcrossDesktops(hwnd))
        win_list.Push(hwnd)

    win_list := SortWindowList(win_list)
    win_list := ApplyDesktopCyclePreference(win_list, true)
    win_list := ApplyCurrentDesktopOrder(exe, win_list, hwnd, true)
    if (win_list.Length < 2)
        return

    current_index := 0
    for i, id in win_list {
        if (id = hwnd) {
            current_index := i
            break
        }
    }

    next_index := (current_index >= win_list.Length || current_index = 0) ? 1 : current_index + 1
    ActivateNextAvailableWindow(win_list, next_index)
}

ActivateNextAvailableWindow(win_list, start_index) {
    count := win_list.Length
    if (count = 0)
        return

    index := start_index
    loop count {
        if (index > count)
            index := 1
        hwnd := win_list[index]
        if WindowExistsAcrossDesktops(hwnd) {
            activated := ActivateWindowAcrossDesktops(hwnd)
            if CycleDebugEnabled()
                LogCycleDebug("  try hwnd=" Format("0x{:X}", hwnd) " activated=" activated)
            if activated
                return
        }
        index += 1
    }
}

GoToRelativeDesktop(delta) {
    if !VirtualDesktopEnabled()
        return
    RefreshVirtualDesktopState()
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    target := VD.modulusResolveDesktopNum(current + delta)
    LogVirtualDesktopAction("goto_relative current=" current " delta=" delta " target=" target)
    RefreshVirtualDesktopState()
    VD.goToDesktopNum(target)
    VD.WaitDesktopSwitched(target)
    RefreshVirtualDesktopState()
}

GoToDesktopNumber(desktop_num) {
    if !VirtualDesktopEnabled()
        return
    if (desktop_num <= 0)
        return
    LogVirtualDesktopAction("goto_absolute target=" desktop_num " current=" GetCurrentDesktopNumFresh())
    RefreshVirtualDesktopState()
    GetCurrentDesktopNumFresh()
    VD.goToDesktopNum(desktop_num)
    VD.WaitDesktopSwitched(desktop_num)
    RefreshVirtualDesktopState()
}

MoveWindowToRelativeDesktop(delta) {
    if !VirtualDesktopEnabled()
        return
    RefreshVirtualDesktopState()
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    target := VD.modulusResolveDesktopNum(current + delta)
    LogVirtualDesktopAction("move_relative current=" current " delta=" delta " target=" target)
    RefreshVirtualDesktopState()
    VD.MoveWindowToDesktopNum("A", target, true)
    VD.WaitDesktopSwitched(target)
    RefreshVirtualDesktopState()
}

MoveWindowToDesktopNumber(desktop_num) {
    if !VirtualDesktopEnabled()
        return
    if (desktop_num <= 0)
        return
    LogVirtualDesktopAction("move_absolute target=" desktop_num " current=" GetCurrentDesktopNumFresh())
    RefreshVirtualDesktopState()
    GetCurrentDesktopNumFresh()
    VD.MoveWindowToDesktopNum("A", desktop_num, true)
    VD.WaitDesktopSwitched(desktop_num)
    RefreshVirtualDesktopState()
}

HotIf (*) => IsSuperKeyPressed() && !IsAltPressed()
Hotkey(center_cycle_hotkey, CenterWidthCycle)
Hotkey("Left", (*) => ResizeActiveWindow(-resize_step, 0))
Hotkey("Right", (*) => ResizeActiveWindow(resize_step, 0))
Hotkey("Up", (*) => ResizeActiveWindow(0, -resize_step))
Hotkey("Down", (*) => ResizeActiveWindow(0, resize_step))
Hotkey("+h", (*) => ResizeActiveWindowCentered(-resize_step, 0))
Hotkey("+l", (*) => ResizeActiveWindowCentered(resize_step, 0))
Hotkey("+j", (*) => ResizeActiveWindowCentered(0, -resize_step))
Hotkey("+k", (*) => ResizeActiveWindowCentered(0, resize_step))
Hotkey("^h", (*) => MoveActiveWindow(-move_step, 0))
Hotkey("^l", (*) => MoveActiveWindow(move_step, 0))
Hotkey("^j", (*) => MoveActiveWindow(0, move_step))
Hotkey("^k", (*) => MoveActiveWindow(0, -move_step))
HotIf IsSuperKeyPressed
Hotkey("m", ToggleMaximize)
Hotkey("q", CloseWindow)
Hotkey(cycle_app_windows_hotkey, CycleAppWindows)
if (cycle_app_windows_current_hotkey != "")
    Hotkey(cycle_app_windows_current_hotkey, CycleAppWindowsCurrent)
RegisterSuperComboHotkey("/", (*) => ShowCommandToastTemporary())
if (minimize_others_hotkey != "")
    Hotkey(minimize_others_hotkey, MinimizeOtherWindows)
HotIf

HotIf (*) => IsSuperKeyPressed() && IsAltPressed() && !GetKeyState("Shift", "P")
if (vd_prev_hotkey != "")
    Hotkey(vd_prev_hotkey, (*) => (
        LogVirtualDesktopAction("goto_relative hotkey=" vd_prev_hotkey " delta=-1 current=" GetCurrentDesktopNumFresh()),
        GoToRelativeDesktop(-1)
    ))
if (vd_next_hotkey != "")
    Hotkey(vd_next_hotkey, (*) => (
        LogVirtualDesktopAction("goto_relative hotkey=" vd_next_hotkey " delta=1 current=" GetCurrentDesktopNumFresh()),
        GoToRelativeDesktop(1)
    ))
LogVirtualDesktopHotkeys("prev_hotkey=" vd_prev_hotkey " next_hotkey=" vd_next_hotkey)
for _, entry in vd_goto_hotkeys {
    if !(entry is Map)
        continue
    if !entry.Has("hotkey") || !entry.Has("desktop")
        continue
    hotkey_name := NormalizeAltHotkey(entry["hotkey"])
    desktop_num := entry["desktop"]
    key_copy := hotkey_name
    num_copy := desktop_num
    if (key_copy != "") {
        callback := GoToDesktopNumber.Bind(num_copy)
        RegisterDesktopHotkey("goto_absolute", key_copy, num_copy, callback)
    }
    LogVirtualDesktopHotkeys("map goto hotkey=" key_copy " desktop=" num_copy)
}
if (vd_desktop_hotkeys is Array && vd_desktop_hotkeys.Length > 0) {
    LogVirtualDesktopHotkeys("desktop_hotkeys_count=" vd_desktop_hotkeys.Length)
    for _, entry in vd_desktop_hotkeys {
        if !(entry is Map)
            continue
        if !entry.Has("hotkey") || !entry.Has("desktop")
            continue
        hotkey_name := NormalizeAltHotkey(entry["hotkey"])
        desktop_num := entry["desktop"]
        key_copy := hotkey_name
        num_copy := desktop_num
        if (key_copy != "") {
            callback := GoToDesktopNumber.Bind(num_copy)
            RegisterDesktopHotkey("goto_absolute", key_copy, num_copy, callback)
        }
        LogVirtualDesktopHotkeys("map goto hotkey=" key_copy " desktop=" num_copy)
    }
}
HotIf

HotIf (*) => IsSuperKeyPressed() && IsAltPressed() && GetKeyState("Shift", "P")
if (vd_move_prev_hotkey != "")
    Hotkey(vd_move_prev_hotkey, (*) => (
        LogVirtualDesktopAction("move_relative hotkey=" vd_move_prev_hotkey " delta=-1 current=" GetCurrentDesktopNumFresh()),
        MoveWindowToRelativeDesktop(-1)
    ))
if (vd_move_next_hotkey != "")
    Hotkey(vd_move_next_hotkey, (*) => (
        LogVirtualDesktopAction("move_relative hotkey=" vd_move_next_hotkey " delta=1 current=" GetCurrentDesktopNumFresh()),
        MoveWindowToRelativeDesktop(1)
    ))
LogVirtualDesktopHotkeys("move_prev_hotkey=" vd_move_prev_hotkey " move_next_hotkey=" vd_move_next_hotkey)
for _, entry in vd_move_hotkeys {
    if !(entry is Map)
        continue
    if !entry.Has("hotkey") || !entry.Has("desktop")
        continue
    hotkey_name := NormalizeAltHotkey(entry["hotkey"], true)
    desktop_num := entry["desktop"]
    key_copy := hotkey_name
    num_copy := desktop_num
    if (key_copy != "") {
        callback := MoveWindowToDesktopNumber.Bind(num_copy)
        RegisterDesktopHotkey("move_absolute", key_copy, num_copy, callback)
    }
    LogVirtualDesktopHotkeys("map move hotkey=" key_copy " desktop=" num_copy)
}
if (vd_desktop_hotkeys is Array && vd_desktop_hotkeys.Length > 0) {
    LogVirtualDesktopHotkeys("desktop_hotkeys_count=" vd_desktop_hotkeys.Length)
    for _, entry in vd_desktop_hotkeys {
        if !(entry is Map)
            continue
        if !entry.Has("hotkey") || !entry.Has("desktop")
            continue
        hotkey_name := NormalizeAltHotkey(entry["hotkey"], true)
        desktop_num := entry["desktop"]
        key_copy := hotkey_name
        num_copy := desktop_num
        if (key_copy != "") {
            callback := MoveWindowToDesktopNumber.Bind(num_copy)
            RegisterDesktopHotkey("move_absolute", key_copy, num_copy, callback)
        }
        LogVirtualDesktopHotkeys("map move hotkey=" key_copy " desktop=" num_copy)
    }
}
HotIf

Hotkey("!-", MinimizeWindow)

if move_mode_enabled {
    HotIf Window.IsMoveMode
    Hotkey("h", (*) => MoveActiveWindow(-move_step, 0))
    Hotkey("l", (*) => MoveActiveWindow(move_step, 0))
    Hotkey("j", (*) => MoveActiveWindow(0, move_step))
    Hotkey("k", (*) => MoveActiveWindow(0, -move_step))
    Hotkey(move_mode_cancel_key, (*) => ExitMoveMode())
    HotIf
}

ExitMoveMode() {
    Window.SetMoveMode(false)
    UpdateCommandToastVisibility()
}

BeginSuperDrag(*) {
    if !IsSuperKeyPressed()
        return
    if Window.IsMoveMode()
        return
    MouseGetPos(, , &hwnd)
    if !hwnd
        return
    if Window.IsException("ahk_id " hwnd)
        return
    if (WinGetMinMax("ahk_id " hwnd) = -1)
        return
    WinActivate "ahk_id " hwnd
    DllCall("ReleaseCapture")
    SendMessage(0xA1, 2, 0, , "ahk_id " hwnd)
}

MinimizeOtherWindows(*) {
    active_hwnd := WinGetID("A")
    if !active_hwnd
        return
    active_monitor := Screen.FromWindow("ahk_id " active_hwnd)
    for _, hwnd in WinGetList() {
        if (hwnd = active_hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            continue
        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        if (Screen.FromWindow("ahk_id " hwnd) != active_monitor)
            continue
        WinMinimize "ahk_id " hwnd
    }
}

ActivateMostRecentWindow(exclude_hwnd := 0) {
    z_list := WinGetList()
    for _, hwnd in z_list {
        if (hwnd = exclude_hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            continue
        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        WinActivate "ahk_id " hwnd
        return
    }
}
