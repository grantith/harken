; Carousel mode helpers (niri-like horizontal focus/workflow per desktop+monitor).
global Config, AppState
global carousel_order_by_scope := Map()
global carousel_tile_width_ratio := Map()
global carousel_viewport_x_by_scope := Map()
global carousel_last_active_hwnd := 0
global carousel_last_scope_key := ""
global carousel_last_active_by_scope := Map()
global carousel_last_relayout_tick := 0
global carousel_ensure_empty_pending := false
global carousel_status_bar_update_pending := false

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
    CarouselStatusBarUpdate()
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
    PersistCarouselWidthPreference(active_hwnd, center_ratio)
    LogCarouselDebug("width_adjust hwnd=" Format("0x{:X}", active_hwnd) " center=" Round(center_ratio, 3))
    CarouselRelayout("resize")
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

    activated_hwnd := ActivateCarouselWindow(target_hwnd)
    if activated_hwnd
        state["active_hwnd"] := activated_hwnd
    else
        state["active_hwnd"] := target_hwnd
    ; Always advance the carousel viewport on explicit carousel focus moves.
    ; auto_snap_center_on_focus only controls passive/external focus changes.
    CarouselRelayout("focus", state)
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

    moving_hwnd := windows[current_index]
    windows.RemoveAt(current_index)
    windows.InsertAt(target_index, moving_hwnd)
    SetCarouselScopeOrder(state["scope_key"], windows)
    PersistCarouselScopeOrder(state["scope_key"], windows)
    ActivateCarouselWindow(active_hwnd)
    CarouselRelayout("move", state)
}

CarouselRelayout(reason := "general", state := "") {
    if !CarouselModeEnabled()
        return

    if !(state is Map)
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

    gap_px := Config["modes"]["carousel"]["gap_px"]
    scope_key := state["scope_key"]

    col_x := []
    col_w := []
    cursor_x := 0
    for _, hwnd in windows {
        width_px := GetTileWidthPx(hwnd, metrics["w"], gap_px)
        col_x.Push(cursor_x)
        col_w.Push(width_px)
        cursor_x += width_px + gap_px
    }
    total_strip_width := Max(0, cursor_x - gap_px)

    active_start := col_x[active_index]
    active_width := col_w[active_index]
    active_end := active_start + active_width
    viewport_x := carousel_viewport_x_by_scope.Has(scope_key) ? carousel_viewport_x_by_scope[scope_key] : 0
    reveal_margin := Config["modes"]["carousel"]["scroll_reveal_margin_px"]
    max_margin := Max(0, Round((metrics["w"] - active_width) / 2))
    reveal_margin := Min(reveal_margin, max_margin)

    is_manual_center := (reason = "center" || reason = "manual")
    if is_manual_center {
        viewport_x := active_start - Round((metrics["w"] - active_width) / 2)
    } else {
        left_limit := viewport_x + reveal_margin
        right_limit := viewport_x + metrics["w"] - reveal_margin
        if (active_start < left_limit)
            viewport_x := active_start - reveal_margin
        else if (active_end > right_limit)
            viewport_x := active_end + reveal_margin - metrics["w"]
    }

    min_viewport := 0
    max_viewport := Max(0, total_strip_width - metrics["w"])
    if is_manual_center {
        ; Allow edge tiles to truly center, even if that reveals blank margin.
        center_slack := Max(0, Round((metrics["w"] - active_width) / 2))
        min_viewport -= center_slack
        max_viewport += center_slack
    }
    viewport_x := Min(max_viewport, Max(min_viewport, viewport_x))
    carousel_viewport_x_by_scope[scope_key] := viewport_x

    resize_for_this_layout := ShouldResizeForRelayout(reason)

    for i, hwnd in windows {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = 1)
            WinRestore("ahk_id " hwnd)

        target_x := 0
        target_y := metrics["y"]
        target_w := col_w[i]
        target_h := metrics["h"]
        target_x := metrics["x"] + col_x[i] - viewport_x

        ; Even when resize-on-focus is disabled, the active tile should still
        ; restore to its own stored focus width when revisited.
        allow_resize := resize_for_this_layout || (i = active_index)
        MoveWindowIfNeeded(hwnd, target_x, target_y, target_w, target_h, allow_resize)
    }

    global carousel_last_relayout_tick
    carousel_last_relayout_tick := A_TickCount
    ScheduleCarouselStatusBarUpdate()
}

ActivateCarouselWindow(hwnd) {
    if !hwnd
        return 0
    if !WindowExistsAcrossDesktops(hwnd)
        return 0
    ; Carousel windows are already filtered to current desktop/monitor.
    ; Prefer direct activation to avoid extra virtual desktop API calls.
    try {
        WinActivate "ahk_id " hwnd
        return WinGetID("A")
    } catch {
        return ActivateWindowAcrossDesktops(hwnd)
    }
}

ScheduleCarouselStatusBarUpdate(delay_ms := 40) {
    global carousel_status_bar_update_pending
    if carousel_status_bar_update_pending
        return
    carousel_status_bar_update_pending := true
    SetTimer(CarouselStatusBarUpdateDeferredTick, -delay_ms)
}

CarouselStatusBarUpdateDeferredTick(*) {
    global carousel_status_bar_update_pending
    try CarouselStatusBarUpdate()
    carousel_status_bar_update_pending := false
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
    ScheduleCarouselStatusBarUpdate(80)
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
    ScheduleCarouselStatusBarUpdate(80)
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
    ScheduleCarouselStatusBarUpdate()
}

MoveWindowToRelativeDesktopWithFollow(delta, follow_desktop := true) {
    if !VirtualDesktopEnabled()
        return
    moving_hwnd := WinGetID("A")
    if !moving_hwnd
        return
    source_monitor := Screen.FromWindow("ahk_id " moving_hwnd)
    if (source_monitor <= 0)
        source_monitor := MonitorGetPrimary()

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

    IntegrateMovedWindowIntoDestinationScope(moving_hwnd, target, source_monitor)

    RefreshVirtualDesktopState()
    ScheduleEnsureCarouselTrailingEmptyDesktop()
    ScheduleCarouselStatusBarUpdate()
}

IntegrateMovedWindowIntoDestinationScope(moving_hwnd, target_desktop_num, monitor_num) {
    if !moving_hwnd
        return
    if (target_desktop_num <= 0 || monitor_num <= 0)
        return

    scope_key := target_desktop_num ":" monitor_num
    discovered := GetCarouselWindows(monitor_num, target_desktop_num)

    active_hwnd := 0
    if carousel_last_active_by_scope.Has(scope_key)
        active_hwnd := carousel_last_active_by_scope[scope_key]

    ordered := BuildScopeOrder(scope_key, discovered, active_hwnd)
    moving_index := CarouselIndexOf(ordered, moving_hwnd)
    if (moving_index > 0)
        ordered.RemoveAt(moving_index)

    anchor_index := CarouselIndexOf(ordered, active_hwnd)
    if (anchor_index > 0)
        ordered.InsertAt(anchor_index + 1, moving_hwnd)
    else
        ordered.Push(moving_hwnd)

    SetCarouselScopeOrder(scope_key, ordered)
    carousel_last_active_by_scope[scope_key] := moving_hwnd
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
        ScheduleCarouselStatusBarUpdate()
        return
    }
    ; Snap viewport to externally focused windows (Task View selection,
    ; app hotkeys, mouse focus, etc.) without forcing auto-centering.
    if changed {
        if (A_TickCount - carousel_last_relayout_tick > 250)
            CarouselRelayout("focus")
    }
    carousel_last_active_hwnd := hwnd
    carousel_last_scope_key := scope_key
    carousel_last_active_by_scope[scope_key] := hwnd
    if changed
        ScheduleCarouselStatusBarUpdate()
}

EnsureCarouselTrailingEmptyDesktop() {
    if !CarouselModeEnabled() || !VirtualDesktopEnabled()
        return
    if !Config["modes"]["carousel"]["ensure_empty_desktop"]
        return
    EnsureVirtualDesktopTrailingEmpty(true)
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

GetTileCenterWidthRatio(hwnd) {
    default_ratio := Config["modes"]["carousel"]["center_width_ratio"]
    if !hwnd
        return default_ratio
    if carousel_tile_width_ratio.Has(hwnd) && WindowExistsAcrossDesktops(hwnd)
        return carousel_tile_width_ratio[hwnd]
    if carousel_tile_width_ratio.Has(hwnd) && !WindowExistsAcrossDesktops(hwnd)
        carousel_tile_width_ratio.Delete(hwnd)

    persisted_ratio := GetPersistedCarouselWidthRatio(hwnd)
    if (persisted_ratio != "") {
        carousel_tile_width_ratio[hwnd] := persisted_ratio
        return persisted_ratio
    }

    return default_ratio
}

GetPersistedCarouselWidthRatio(hwnd) {
    global AppState
    if !(AppState is Map)
        return ""
    if !AppState.Has("carousel_tile_width_ratio_by_exe")
        return ""

    ratio_by_exe := AppState["carousel_tile_width_ratio_by_exe"]
    if !(ratio_by_exe is Map)
        return ""

    app_key := GetCarouselPersistentWidthKey(hwnd)
    if (app_key = "") || !ratio_by_exe.Has(app_key)
        return ""

    persisted_ratio := ratio_by_exe[app_key]
    if !IsNumber(persisted_ratio)
        return ""

    persisted_ratio := Min(0.9, Max(0.2, persisted_ratio))
    LogCarouselDebug("width_restore key=" app_key " center=" Round(persisted_ratio, 3))
    return persisted_ratio
}

PersistCarouselWidthPreference(hwnd, center_ratio) {
    global AppState
    app_key := GetCarouselPersistentWidthKey(hwnd)
    if (app_key = "")
        return

    if !(AppState is Map)
        AppState := Map()
    if !AppState.Has("carousel_tile_width_ratio_by_exe") || !(AppState["carousel_tile_width_ratio_by_exe"] is Map)
        AppState["carousel_tile_width_ratio_by_exe"] := Map()

    ratio_by_exe := AppState["carousel_tile_width_ratio_by_exe"]
    ratio_by_exe[app_key] := center_ratio
    SaveState(AppState)
    LogCarouselDebug("width_persist key=" app_key " center=" Round(center_ratio, 3))
}

GetCarouselPersistentWidthKey(hwnd) {
    return GetCarouselPersistentAppKey(hwnd)
}

GetCarouselPersistentAppKey(hwnd) {
    if !hwnd
        return ""
    process_name := ""
    try process_name := StrLower(WinGetProcessName("ahk_id " hwnd))
    if !process_name
        return ""
    return process_name
}

GetTileWidthPx(hwnd, monitor_width, gap_px := 0) {
    ratio := GetTileCenterWidthRatio(hwnd)
    ; Account for one inter-tile gap so two default 50% tiles can sit flush
    ; within the viewport without slight overflow-induced extra panning.
    available_width := Max(120, monitor_width - gap_px)
    width_px := Round(available_width * ratio)
    width_px := Min(Max(120, width_px), monitor_width)
    return width_px
}

ShouldResizeForRelayout(reason) {
    if (reason = "resize" || reason = "move" || reason = "startup" || reason = "manual")
        return true
    return Config["modes"]["carousel"]["resize_on_focus"]
}

MoveWindowIfNeeded(hwnd, target_x, target_y, target_w, target_h, allow_resize := true) {
    epsilon := Config["modes"]["carousel"]["layout_epsilon_px"]
    x := 0
    y := 0
    w := 0
    h := 0
    try WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)
    catch
        return

    move_needed := (Abs(x - target_x) > epsilon) || (Abs(y - target_y) > epsilon)
    size_needed := (Abs(w - target_w) > epsilon) || (Abs(h - target_h) > epsilon)
    if !move_needed && (!allow_resize || !size_needed)
        return

    if allow_resize
        WinMoveEx(target_x, target_y, target_w, target_h, "ahk_id " hwnd)
    else
        WinMoveEx(target_x, target_y,,, "ahk_id " hwnd)
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
    used_persisted_order := false
    if carousel_order_by_scope.Has(scope_key)
        existing := carousel_order_by_scope[scope_key]
    else {
        persisted_order := BuildPersistedScopeOrder(scope_key, discovered)
        used_persisted_order := (persisted_order.Length > 0)
        if used_persisted_order
            existing := persisted_order
    }
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

    if !used_persisted_order && (active_hwnd && CarouselIndexOf(ordered, active_hwnd) = 0 && CarouselIndexOf(discovered, active_hwnd) > 0)
        ordered.InsertAt(1, active_hwnd)

    SetCarouselScopeOrder(scope_key, ordered)
    PersistCarouselScopeOrder(scope_key, ordered)
    return ordered
}

BuildPersistedScopeOrder(scope_key, discovered) {
    ordered := []
    seen := Map()
    persisted_keys := GetPersistedCarouselScopeOrderKeys(scope_key)
    if (persisted_keys.Length = 0)
        return ordered

    ; Best-effort restore maps persisted app order to current live windows.
    ; Duplicate app windows are consumed in discovery order.
    for _, app_key in persisted_keys {
        if !app_key
            continue
        for _, hwnd in discovered {
            if seen.Has(hwnd)
                continue
            if (GetCarouselPersistentAppKey(hwnd) != app_key)
                continue
            ordered.Push(hwnd)
            seen[hwnd] := true
            break
        }
    }

    if (ordered.Length > 0)
        LogCarouselDebug("order_restore scope=" scope_key " matched=" ordered.Length " discovered=" discovered.Length)
    return ordered
}

GetPersistedCarouselScopeOrderKeys(scope_key) {
    global AppState
    if !(AppState is Map)
        return []
    if !AppState.Has("carousel_order_by_scope")
        return []

    by_scope := AppState["carousel_order_by_scope"]
    if !(by_scope is Map)
        return []
    if !by_scope.Has(scope_key)
        return []

    persisted_keys := by_scope[scope_key]
    if !(persisted_keys is Array)
        return []
    return persisted_keys
}

PersistCarouselScopeOrder(scope_key, windows) {
    global AppState
    if !(windows is Array)
        return

    keys := []
    for _, hwnd in windows {
        app_key := GetCarouselPersistentAppKey(hwnd)
        if app_key
            keys.Push(app_key)
    }
    if (keys.Length = 0)
        return

    if !(AppState is Map)
        AppState := Map()
    if !AppState.Has("carousel_order_by_scope") || !(AppState["carousel_order_by_scope"] is Map)
        AppState["carousel_order_by_scope"] := Map()

    by_scope := AppState["carousel_order_by_scope"]
    if by_scope.Has(scope_key) && (by_scope[scope_key] is Array) && CarouselStringArraysEqual(by_scope[scope_key], keys)
        return

    by_scope[scope_key] := keys
    SaveState(AppState)
    LogCarouselDebug("order_persist scope=" scope_key " windows=" windows.Length)
}

CarouselStringArraysEqual(a, b) {
    if !(a is Array) || !(b is Array)
        return false
    if (a.Length != b.Length)
        return false
    for i, value in a {
        if (value != b[i])
            return false
    }
    return true
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
    top += CarouselStatusBarReservedTopPx(monitor_num)
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
