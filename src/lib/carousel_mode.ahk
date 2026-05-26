; Carousel mode helpers (niri-like horizontal focus/workflow per desktop+monitor).
global Config
global carousel_order_by_scope := Map()
global carousel_tile_width_ratio := Map()
global carousel_last_active_hwnd := 0
global carousel_last_scope_key := ""
global carousel_last_relayout_tick := 0
global carousel_ensure_empty_pending := false

IsCarouselModeActive() {
    if !Config.Has("modes") || !(Config["modes"] is Map)
        return false
    if !Config["modes"].Has("active")
        return false
    return Config["modes"]["active"] = "carousel"
}

CarouselModeEnabled() {
    if !IsCarouselModeActive()
        return false
    if !Config["modes"].Has("carousel") || !(Config["modes"]["carousel"] is Map)
        return false
    return Config["modes"]["carousel"]["enabled"]
}

CarouselDesktopMoveFollowsFocus() {
    if !CarouselModeEnabled()
        return true
    return Config["modes"]["carousel"]["desktop_move_follows_focus"]
}

ToggleCarouselDesktopMoveFollow() {
    if !CarouselModeEnabled()
        return
    current := CarouselDesktopMoveFollowsFocus()
    Config["modes"]["carousel"]["desktop_move_follows_focus"] := !current
    LogCarouselDebug("toggle_follow enabled=" (!current))
    UpdateCommandToastVisibility()
}

CarouselOpenOverview(*) {
    Send("#{Tab}")
}

CarouselAdjustCenterWidth(delta) {
    if !CarouselModeEnabled()
        return
    carousel := Config["modes"]["carousel"]
    step := carousel["width_step"]
    active_hwnd := WinGetID("A")
    if !active_hwnd
        return
    center_ratio := GetTileCenterWidthRatio(active_hwnd) + delta * step
    center_ratio := Min(0.9, Max(0.2, center_ratio))
    carousel_tile_width_ratio[active_hwnd] := center_ratio
    LogCarouselDebug("width_adjust hwnd=" Format("0x{:X}", active_hwnd) " center=" Round(center_ratio, 3))
    CarouselRelayout()
}

CarouselFocus(direction) {
    if !CarouselModeEnabled()
        return
    if (direction != "left" && direction != "right")
        return

    state := BuildCarouselState()
    if (state["windows"].Length < 2)
        return

    active_hwnd := state["active_hwnd"]
    current_index := CarouselIndexOf(state["windows"], active_hwnd)
    if (current_index = 0)
        current_index := 1

    wrap := Config["modes"]["carousel"]["wrap_enabled"]
    target_index := current_index
    if (direction = "left") {
        if (current_index <= 1)
            target_index := wrap ? state["windows"].Length : 1
        else
            target_index := current_index - 1
    } else {
        if (current_index >= state["windows"].Length)
            target_index := wrap ? 1 : state["windows"].Length
        else
            target_index := current_index + 1
    }

    target_hwnd := state["windows"][target_index]
    if (target_hwnd = active_hwnd && !wrap)
        return

    ActivateWindowAcrossDesktops(target_hwnd)
    if Config["modes"]["carousel"]["auto_snap_center_on_focus"]
        CarouselRelayout()
}

CarouselMove(direction) {
    if !CarouselModeEnabled()
        return
    if (direction != "left" && direction != "right")
        return

    state := BuildCarouselState()
    windows := state["windows"]
    if (windows.Length < 2)
        return

    active_hwnd := state["active_hwnd"]
    current_index := CarouselIndexOf(windows, active_hwnd)
    if (current_index = 0)
        return

    wrap := Config["modes"]["carousel"]["wrap_enabled"]
    target_index := current_index
    if (direction = "left") {
        if (current_index <= 1)
            target_index := wrap ? windows.Length : 1
        else
            target_index := current_index - 1
    } else {
        if (current_index >= windows.Length)
            target_index := wrap ? 1 : windows.Length
        else
            target_index := current_index + 1
    }
    if (target_index = current_index)
        return

    temp := windows[current_index]
    windows[current_index] := windows[target_index]
    windows[target_index] := temp
    SetCarouselScopeOrder(state["scope_key"], windows)
    ActivateWindowAcrossDesktops(active_hwnd)
    CarouselRelayout()
}

CarouselRelayout(*) {
    if !CarouselModeEnabled()
        return

    state := BuildCarouselState()
    windows := state["windows"]
    if (windows.Length = 0)
        return

    active_hwnd := state["active_hwnd"]
    active_index := CarouselIndexOf(windows, active_hwnd)
    if (active_index = 0)
        active_index := 1

    metrics := GetCarouselMonitorMetrics(state["monitor_num"])
    if (metrics["w"] <= 0 || metrics["h"] <= 0)
        return

    center_ratio := GetTileCenterWidthRatio(active_hwnd)
    side_ratio := Config["modes"]["carousel"]["side_width_ratio"]
    max_side_ratio := (1.0 - center_ratio) / 2.0
    side_ratio := Min(side_ratio, max_side_ratio)
    gap_px := Config["modes"]["carousel"]["gap_px"]
    center_w := Round(metrics["w"] * center_ratio)
    side_w := Round(metrics["w"] * side_ratio)
    center_w := Min(Max(120, center_w), metrics["w"])
    side_w := Min(Max(80, side_w), metrics["w"])

    center_x := metrics["x"] + Round((metrics["w"] - center_w) / 2)
    left_x := center_x - gap_px - side_w
    right_x := center_x + center_w + gap_px

    overflow_policy := Config["modes"]["carousel"]["overflow_policy"]
    left_offscreen_x := metrics["x"] - side_w - gap_px
    right_offscreen_x := metrics["x"] + metrics["w"] + gap_px

    for i, hwnd in windows {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = 1)
            WinRestore("ahk_id " hwnd)

        if (i = active_index)
            WinMoveEx(center_x, metrics["y"], center_w, metrics["h"], "ahk_id " hwnd)
        else if (i = active_index - 1)
            WinMoveEx(left_x, metrics["y"], side_w, metrics["h"], "ahk_id " hwnd)
        else if (i = active_index + 1)
            WinMoveEx(right_x, metrics["y"], side_w, metrics["h"], "ahk_id " hwnd)
        else if (i < active_index) {
            target_x := (overflow_policy = "stack_peek") ? left_x : left_offscreen_x
            WinMoveEx(target_x, metrics["y"], side_w, metrics["h"], "ahk_id " hwnd)
        } else {
            target_x := (overflow_policy = "stack_peek") ? right_x : right_offscreen_x
            WinMoveEx(target_x, metrics["y"], side_w, metrics["h"], "ahk_id " hwnd)
        }
    }

    global carousel_last_relayout_tick
    carousel_last_relayout_tick := A_TickCount
}

CarouselSwitchDesktop(delta) {
    if !CarouselModeEnabled()
        return
    ; Prevent plain desktop-switch handler from firing on shift-modified
    ; combos such as super+shift+j/k (which are reserved for moving tiles).
    if GetKeyState("Shift", "P")
        return
    GoToRelativeDesktopFast(delta)
    ScheduleEnsureCarouselTrailingEmptyDesktop()
}

CarouselHandleDesktopKey(delta) {
    if !CarouselModeEnabled() || Window.IsMoveMode()
        return
    if GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P") {
        if Config["modes"]["carousel"]["native_desktop_reorder"]
            CarouselMoveCurrentDesktop(delta)
        return
    }
    if GetKeyState("Shift", "P") {
        CarouselMoveWindowDesktop(delta)
        return
    }
    CarouselSwitchDesktop(delta)
}

CarouselMoveWindowDesktop(delta) {
    if !CarouselModeEnabled()
        return
    MoveWindowToRelativeDesktopWithFollow(delta, CarouselDesktopMoveFollowsFocus())
}

CarouselMoveCurrentDesktop(delta) {
    if !CarouselModeEnabled() || !VirtualDesktopEnabled()
        return
    if !Config["modes"]["carousel"]["native_desktop_reorder"]
        return
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    count := VD.getCount()
    if (count <= 1)
        return
    target := current + delta
    if (target < 1)
        target := 1
    if (target > count)
        target := count
    if (target = current)
        return
    try {
        moved := VD.moveDesktop(current, target)
        if moved
            LogCarouselDebug("desktop_reorder current=" current " target=" target)
    } catch as err {
        LogCarouselDebug("desktop_reorder_failed current=" current " target=" target " err=" err.Message)
    }
    RefreshVirtualDesktopState()
}

MoveWindowToRelativeDesktopWithFollow(delta, follow_desktop := true) {
    if !VirtualDesktopEnabled()
        return
    RefreshVirtualDesktopState()
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    target := VD.modulusResolveDesktopNum(current + delta)
    LogVirtualDesktopAction("move_relative current=" current " delta=" delta " target=" target " follow=" follow_desktop)
    RefreshVirtualDesktopState()
    if follow_desktop {
        VD.MoveWindowToDesktopNum("A", target, true)
    } else {
        VD.MoveWindowToDesktopNum("A", target, false)
    }
    RefreshVirtualDesktopState()
    ScheduleEnsureCarouselTrailingEmptyDesktop()
}

GoToRelativeDesktopFast(delta) {
    if !VirtualDesktopEnabled()
        return
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    target := VD.modulusResolveDesktopNum(current + delta)
    LogVirtualDesktopAction("goto_relative_fast current=" current " delta=" delta " target=" target)
    try VD.goToDesktopNum(target)
}

CarouselFocusWatcherTick(*) {
    global carousel_last_active_hwnd, carousel_last_scope_key, carousel_last_relayout_tick
    if !CarouselModeEnabled()
        return
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return
    if Window.IsException("ahk_id " hwnd)
        return

    monitor_num := Screen.FromWindow("ahk_id " hwnd)
    desktop_num := VirtualDesktopEnabled() ? GetCurrentDesktopNumFresh() : 0
    scope_key := desktop_num ":" monitor_num
    changed := (hwnd != carousel_last_active_hwnd) || (scope_key != carousel_last_scope_key)
    if (changed && IsOverviewActive()) {
        carousel_last_active_hwnd := hwnd
        carousel_last_scope_key := scope_key
        return
    }
    if changed && Config["modes"]["carousel"]["auto_snap_center_on_focus"] {
        if (A_TickCount - carousel_last_relayout_tick > 250)
            CarouselRelayout()
    }
    carousel_last_active_hwnd := hwnd
    carousel_last_scope_key := scope_key
}

EnsureCarouselTrailingEmptyDesktop() {
    if !CarouselModeEnabled() || !VirtualDesktopEnabled()
        return
    if !Config["modes"]["carousel"]["ensure_empty_desktop"]
        return

    occupied := GetOccupiedDesktopSet()
    highest_occupied := 0
    for desktop_num, _ in occupied {
        if (desktop_num > highest_occupied)
            highest_occupied := desktop_num
    }

    desired := Max(1, highest_occupied + 1)
    RefreshVirtualDesktopState()
    count := VD.getCount()
    if (count < desired)
        VD.createUntil(desired)

    ; Keep this non-destructive. Avoid auto-removing desktops that might hold state.
}

ScheduleEnsureCarouselTrailingEmptyDesktop(delay_ms := 700) {
    global carousel_ensure_empty_pending
    if carousel_ensure_empty_pending
        return
    carousel_ensure_empty_pending := true
    SetTimer(CarouselEnsureEmptyDesktopDeferredTick, -delay_ms)
}

CarouselEnsureEmptyDesktopDeferredTick(*) {
    global carousel_ensure_empty_pending
    try EnsureCarouselTrailingEmptyDesktop()
    carousel_ensure_empty_pending := false
}

GetOccupiedDesktopSet() {
    set := Map()
    windows := GetWindowsAcrossDesktops()
    for _, hwnd in windows {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        ex_style := 0
        try ex_style := WinGetExStyle("ahk_id " hwnd)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num > 0)
            set[desktop_num] := true
    }
    return set
}

GetTileCenterWidthRatio(hwnd) {
    default_ratio := Config["modes"]["carousel"]["center_width_ratio"]
    if !hwnd
        return default_ratio
    if carousel_tile_width_ratio.Has(hwnd) && WindowExistsAcrossDesktops(hwnd)
        return carousel_tile_width_ratio[hwnd]
    if carousel_tile_width_ratio.Has(hwnd) && !WindowExistsAcrossDesktops(hwnd)
        carousel_tile_width_ratio.Delete(hwnd)
    return default_ratio
}

BuildCarouselState() {
    active_hwnd := WinGetID("A")
    if !active_hwnd
        return Map("windows", [], "active_hwnd", 0, "monitor_num", 0, "scope_key", "")

    monitor_num := Screen.FromWindow("ahk_id " active_hwnd)
    desktop_num := VirtualDesktopEnabled() ? GetCurrentDesktopNumFresh() : 0
    scope_key := desktop_num ":" monitor_num
    discovered := GetCarouselWindows(monitor_num, desktop_num)
    windows := BuildScopeOrder(scope_key, discovered, active_hwnd)
    return Map(
        "windows", windows,
        "active_hwnd", active_hwnd,
        "monitor_num", monitor_num,
        "scope_key", scope_key
    )
}

GetCarouselWindows(monitor_num, desktop_num := 0) {
    include_minimized := Config["modes"]["carousel"]["include_minimized"]
    excluded_apps := Config["modes"]["carousel"]["excluded_apps"]
    windows := []
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    list := WinGetList()
    A_DetectHiddenWindows := bak_detect_hidden_windows
    for _, hwnd in list {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        minmax := 0
        try minmax := WinGetMinMax("ahk_id " hwnd)
        catch
            continue
        if !include_minimized && (minmax = -1)
            continue
        ex_style := 0
        try ex_style := WinGetExStyle("ahk_id " hwnd)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        style := 0
        try style := WinGetStyle("ahk_id " hwnd)
        catch
            continue
        if !include_minimized && !(style & 0x10000000)
            continue
        if (Screen.FromWindow("ahk_id " hwnd) != monitor_num)
            continue
        if (VirtualDesktopEnabled() && desktop_num > 0) {
            hwnd_desktop := GetWindowDesktopNum(hwnd)
            if (hwnd_desktop > 0 && hwnd_desktop != desktop_num)
                continue
        }
        process_name := ""
        try process_name := StrLower(WinGetProcessName("ahk_id " hwnd))
        if CarouselExcludedProcess(process_name, excluded_apps)
            continue
        windows.Push(hwnd)
    }
    return windows
}

CarouselExcludedProcess(process_name, excluded_apps) {
    if !process_name
        return false
    for _, excluded in excluded_apps {
        if (StrLower(excluded) = process_name)
            return true
    }
    return false
}

BuildScopeOrder(scope_key, discovered, active_hwnd) {
    existing := []
    if carousel_order_by_scope.Has(scope_key)
        existing := carousel_order_by_scope[scope_key]
    ordered := []
    seen := Map()

    for _, hwnd in existing {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if CarouselIndexOf(discovered, hwnd) = 0
            continue
        ordered.Push(hwnd)
        seen[hwnd] := true
    }

    for _, hwnd in discovered {
        if !seen.Has(hwnd) {
            ordered.Push(hwnd)
            seen[hwnd] := true
        }
    }

    if (active_hwnd && CarouselIndexOf(ordered, active_hwnd) = 0 && CarouselIndexOf(discovered, active_hwnd) > 0)
        ordered.InsertAt(1, active_hwnd)

    SetCarouselScopeOrder(scope_key, ordered)
    return ordered
}

SetCarouselScopeOrder(scope_key, windows) {
    copy := []
    for _, hwnd in windows
        copy.Push(hwnd)
    carousel_order_by_scope[scope_key] := copy
}

GetCarouselMonitorMetrics(monitor_num) {
    MonitorGetWorkArea(monitor_num, &left, &top, &right, &bottom)
    left += Screen.left_margin
    top += Screen.top_margin
    right -= Screen.right_margin
    bottom -= Screen.bottom_margin
    width := right - left
    height := bottom - top
    return Map("x", left, "y", top, "w", width, "h", height)
}

CarouselIndexOf(list, hwnd) {
    for i, id in list {
        if (id = hwnd)
            return i
    }
    return 0
}

LogCarouselDebug(message) {
    if !CarouselModeEnabled()
        return
    if !Config["modes"]["carousel"]["debug_enabled"]
        return

    appdata := EnvGet("APPDATA")
    if !appdata
        return
    log_path := appdata "\\harken\\carousel.debug.log"
    DirCreate(appdata "\\harken")
    FileAppend("[" A_Now "] " message "`n", log_path)
}
