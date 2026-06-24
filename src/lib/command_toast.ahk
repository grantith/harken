global Config, AppState
; Command overlay UI + helper toggle state.
global command_helper_enabled := false
global command_toast_gui := ""
global command_toast_text := ""
global command_toast_visible := false
global command_toast_view_key := ""
global command_toast_apps_list := ""
global command_toast_actions_list := ""
global command_toast_image_list := ""
global command_toast_icon_cache := Map()
global command_toast_default_icon_index := 0
global command_toast_last_mode := ""
global command_toast_normal_refresh_pending := false
global command_toast_visibility_timer := 0
global command_toast_temp_visible := false
global command_toast_input_hook := 0
global command_toast_input_timer := 0
global command_toast_keydown_enabled := false
global command_toast_keydown_handler := 0

InitCommandToast() {
    global Config, AppState, command_helper_enabled
    command_helper_enabled := Config["helper"]["enabled"]
    if (AppState is Map && AppState.Has("command_helper_enabled"))
        command_helper_enabled := AppState["command_helper_enabled"]
}

UpdateCommandToastVisibility() {
    global command_helper_enabled, command_toast_temp_visible
    if !command_helper_enabled && !command_toast_temp_visible {
        StopCommandToastVisibilityTimer()
        HideCommandToast()
        return
    }

    if ReloadModeActive() || Window.IsMoveMode() || command_toast_temp_visible {
        ShowCommandToast(command_toast_temp_visible)
        StartCommandToastVisibilityTimer()
    } else {
        StopCommandToastVisibilityTimer()
        HideCommandToast()
    }
}

StartCommandToastVisibilityTimer() {
    global command_toast_visibility_timer
    if !command_toast_visibility_timer
        command_toast_visibility_timer := CommandToastVisibilityTick
    SetTimer(command_toast_visibility_timer, 200)
}

StopCommandToastVisibilityTimer() {
    global command_toast_visibility_timer
    if command_toast_visibility_timer
        SetTimer(command_toast_visibility_timer, 0)
}

CommandToastVisibilityTick(*) {
    UpdateCommandToastVisibility()
}

ShowCommandToast(force_show := false) {
    global command_helper_enabled, command_toast_gui, command_toast_visible, command_toast_view_key, command_toast_last_mode, command_toast_normal_refresh_pending
    if !command_helper_enabled && !force_show
        return

    model := BuildCommandToastModel()
    if !(model is Map) || !model.Has("key") || (model["key"] = "")
        return

    if (model["mode"] = "normal" && command_toast_last_mode != "normal") {
        command_toast_view_key := ""
        command_toast_normal_refresh_pending := true
    }

    if !command_toast_gui || (command_toast_view_key != model["key"]) {
        if command_toast_gui
            command_toast_gui.Destroy()
        command_toast_gui := ""
        command_toast_text := ""
        command_toast_apps_list := ""
        command_toast_actions_list := ""
        command_toast_image_list := ""
        command_toast_icon_cache := Map()
        command_toast_default_icon_index := 0
        CreateCommandToastGui(model)
        command_toast_view_key := model["key"]
    } else if (model["mode"] = "normal" && command_toast_normal_refresh_pending) {
        ; defer refresh until after show to avoid flicker
    }

    opacity := NormalizeOverlayOpacity()
    if (opacity < 255)
        WinSetTransparent(opacity, command_toast_gui)

    command_toast_gui.Show("NoActivate")
    command_toast_gui.GetPos(&x, &y, &w, &h)
    GetCommandToastWorkArea(&left, &top, &right, &bottom)
    dpi_scale := A_ScreenDPI / 96
    margin := Round(24 * dpi_scale)
    if (margin < 16)
        margin := 16
    if (margin > 64)
        margin := 64
    pos_x := left + (right - left - w) / 2
    pos_y := top + (bottom - top - h) / 2
    command_toast_gui.Show("NoActivate x" pos_x " y" pos_y)
    if (model["mode"] = "normal" && command_toast_normal_refresh_pending) {
        RefreshCommandToastIcons(model)
        command_toast_normal_refresh_pending := false
    }
    command_toast_visible := true
    command_toast_last_mode := model["mode"]
}

CreateCommandToastGui(model) {
    global command_toast_gui, command_toast_text, command_toast_apps_list, command_toast_actions_list, command_toast_image_list
    command_toast_gui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "harken Command Overlay")
    command_toast_gui.MarginX := 12
    command_toast_gui.MarginY := 10
    opacity := NormalizeOverlayOpacity()
    if (opacity < 255)
        WinSetTransparent(opacity, command_toast_gui)

    command_toast_gui.SetFont("s10 w600", "Segoe UI")
    command_toast_gui.AddText("xm", model["title"])

    GetCommandToastWorkArea(&work_left, &work_top, &work_right, &work_bottom)
    work_w := work_right - work_left
    work_h := work_bottom - work_top
    width_ratio := (work_w > 2000) ? 0.15 : 0.25
    overlay_width := Round(ClampValue(work_w * width_ratio, 380, 640))
    row_height := 22
    apps_rows_max := ClampValue(Floor((work_h * 0.22) / row_height), 6, 12)
    actions_rows_max := ClampValue(Floor((work_h * 0.5) / row_height), 10, 26)

    if (model["mode"] = "normal") {
        command_toast_gui.SetFont("s9 w600", "Segoe UI")
        command_toast_gui.AddText("xm y+6", "Apps")
        command_toast_gui.SetFont("s9", "Segoe UI")

        row_count := Max(1, Min(apps_rows_max, model["apps"].Length))
        command_toast_apps_list := command_toast_gui.AddListView("xm w" overlay_width " r" row_count " -Multi NoSortHdr", ["Key", "App"])
        command_toast_image_list := IL_Create(16)
        command_toast_default_icon_index := EnsureDefaultAppIcon()
        command_toast_apps_list.SetImageList(command_toast_image_list, 1)
        apps_key_width := Round(ClampValue(overlay_width * 0.2, 80, 140))
        command_toast_apps_list.ModifyCol(1, apps_key_width)
        command_toast_apps_list.ModifyCol(2, overlay_width - apps_key_width - 20)

        for _, app in model["apps"] {
            icon_index := GetAppIconIndex(app["icon_path"])
            command_toast_apps_list.Add("Icon" icon_index, app["hotkey"], app["label"])
        }

        command_toast_gui.SetFont("s9", "Segoe UI")
        rows := model["rows"]
        row_count := Max(1, Min(actions_rows_max, rows.Length))
        command_toast_actions_list := command_toast_gui.AddListView("xm y+6 w" overlay_width " r" row_count " -Multi NoSortHdr", ["Key", "Action"])
        actions_key_width := Round(ClampValue(overlay_width * 0.45, 180, 320))
        command_toast_actions_list.ModifyCol(1, actions_key_width)
        command_toast_actions_list.ModifyCol(2, overlay_width - actions_key_width - 20)

        for _, row in rows {
            command_toast_actions_list.Add("", row["key"], row["desc"])
        }
        return
    }

    command_toast_gui.SetFont("s9", "Consolas")
    command_toast_text := command_toast_gui.AddText("xm y+6 w" overlay_width, model["body_text"])
}

RefreshCommandToastIcons(model) {
    global command_toast_apps_list, command_toast_image_list, command_toast_icon_cache, command_toast_default_icon_index
    if !command_toast_apps_list
        return
    if !(model is Map) || !model.Has("apps")
        return

    command_toast_icon_cache := Map()
    command_toast_image_list := IL_Create(16)
    command_toast_default_icon_index := EnsureDefaultAppIcon()
    command_toast_apps_list.SetImageList(command_toast_image_list, 1)
    command_toast_apps_list.Delete()
    row_count := Max(1, Min(8, model["apps"].Length))
    command_toast_apps_list.Opt("r" row_count)
    for _, app in model["apps"] {
        icon_index := GetAppIconIndex(app["icon_path"])
        command_toast_apps_list.Add("Icon" icon_index, app["hotkey"], app["label"])
    }
}

HideCommandToast() {
    global command_toast_gui, command_toast_visible, command_toast_temp_visible
    if command_toast_gui {
        command_toast_gui.Hide()
        command_toast_visible := false
    }
    command_toast_temp_visible := false
    StopCommandToastInputHook()
    UnregisterCommandToastKeydown()
}

ToggleCommandHelper() {
    global command_helper_enabled, AppState
    command_helper_enabled := !command_helper_enabled
    if !(AppState is Map)
        AppState := Map()
    AppState["command_helper_enabled"] := command_helper_enabled
    SaveState(AppState)
    status := command_helper_enabled ? "enabled" : "disabled"
    TrayTip("", "")
    TrayTip("harken", "Command overlay " status, 2)
    UpdateCommandToastVisibility()
}

ShowCommandToastTemporary() {
    global command_helper_enabled, command_toast_temp_visible
    ; Allow the temporary overlay even if persistent helper overlay is disabled.
    command_toast_temp_visible := true
    ShowCommandToast(true)
    StartCommandToastInputHook()
    RegisterCommandToastKeydown()
}

StartCommandToastInputHook() {
    global command_toast_input_timer
    if ReloadModeActive() || Window.IsMoveMode()
        return
    StopCommandToastInputHook()
    command_toast_input_timer := CommandToastStartInputHook
    SetTimer(command_toast_input_timer, -100)
}

CommandToastStartInputHook(*) {
    global command_toast_input_hook
    if ReloadModeActive() || Window.IsMoveMode()
        return
    command_toast_input_hook := InputHook("V")
    command_toast_input_hook.KeyOpt("{All}", "E")
    command_toast_input_hook.OnKeyDown := CommandToastOnKeyDown
    command_toast_input_hook.Start()
}

StopCommandToastInputHook() {
    global command_toast_input_timer, command_toast_input_hook
    if command_toast_input_timer
        SetTimer(command_toast_input_timer, 0)
    command_toast_input_timer := 0
    if command_toast_input_hook {
        try command_toast_input_hook.Stop()
        command_toast_input_hook := 0
    }
}

RegisterCommandToastKeydown() {
    global command_toast_keydown_enabled, command_toast_keydown_handler
    if command_toast_keydown_enabled
        return
    if !command_toast_keydown_handler
        command_toast_keydown_handler := CommandToastKeydownHandler
    OnMessage(0x100, command_toast_keydown_handler)
    OnMessage(0x104, command_toast_keydown_handler)
    command_toast_keydown_enabled := true
}

UnregisterCommandToastKeydown() {
    global command_toast_keydown_enabled, command_toast_keydown_handler
    if !command_toast_keydown_enabled
        return
    if command_toast_keydown_handler {
        OnMessage(0x100, command_toast_keydown_handler, 0)
        OnMessage(0x104, command_toast_keydown_handler, 0)
    }
    command_toast_keydown_enabled := false
}

CommandToastKeydownHandler(*) {
    if ReloadModeActive() || Window.IsMoveMode()
        return
    HideCommandToast()
}

CommandToastOnKeyDown(*) {
    if ReloadModeActive() || Window.IsMoveMode()
        return
    ; Any input dismisses the temporary overlay in normal mode.
    HideCommandToast()
}

GetCommandToastWorkArea(&left, &top, &right, &bottom) {
    mon := ""
    try hwnd := WinGetID("A")
    if hwnd {
        try mon_handle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        if mon_handle
            mon := ConvertMonitorHandleToNumber(mon_handle)
    }
    if !mon
        mon := MonitorGetPrimary()
    MonitorGetWorkArea(mon, &left, &top, &right, &bottom)
}

ConvertMonitorHandleToNumber(handle) {
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

BuildCommandToastModel() {
    global Config
    is_command_mode := ReloadModeActive()
    is_move_mode := Window.IsMoveMode()
    key_width := 22
    model := Map()

    if is_move_mode {
        lines := []
        lines.Push(FormatRow("h/j/k/l", "move window", key_width))
        lines.Push(FormatRow(Config["window"]["move_mode"]["cancel_key"], "exit move mode", key_width))
        model["mode"] := "move"
        model["title"] := "Move Mode"
        model["body_text"] := StrJoin(lines, "`n")
        model["key"] := "move|" model["body_text"]
        return model
    }

    if is_command_mode {
        lines := []
        lines.Push(FormatRow("r", "reload config", key_width))
        lines.Push(FormatRow("e", "open config file", key_width))
        lines.Push(FormatRow("i", "window inspector", key_width))
        lines.Push(FormatRow("n", "toggle command overlay", key_width))
        lines.Push(FormatRow("w", "new window (active app)", key_width))
        if Config["window"]["move_mode"]["enable"]
            lines.Push(FormatRow("m", "enter move mode", key_width))
        lines.Push(FormatRow("g", "reapply app desktops", key_width))
        lines.Push(FormatRow("Esc/super", "exit command mode", key_width))
        model["mode"] := "command"
        model["title"] := "Command Mode"
        model["body_text"] := StrJoin(lines, "`n")
        model["key"] := "command|" model["body_text"]
        return model
    }

    model["mode"] := "normal"
    model["title"] := "harken"
    model["apps"] := BuildAppRows()
    model["rows"] := BuildCommandToastRows(key_width)
    model["key"] := "normal|" BuildCommandToastRowsKey(model["rows"]) "|" BuildAppsKey(model["apps"])
    return model
}

BuildCommandToastRows(key_width := 16) {
    global Config
    rows := []
    rows.Push(Map("key", "Window", "desc", ""))
    rows.Push(Map("key", "super+arrows", "desc", "resize"))
    rows.Push(Map("key", "super+alt+arrows", "desc", "resize center"))
    if CarouselModeEnabled() {
        rows.Push(Map("key", "super+h/l", "desc", "carousel focus"))
        rows.Push(Map("key", "super+shift+h/l", "desc", "carousel move"))
        rows.Push(Map("key", "super+j/k", "desc", "desktop next/prev"))
        rows.Push(Map("key", "super+shift+j/k", "desc", "move desktop (follow toggle)"))
        rows.Push(Map("key", "super+space", "desc", "center active tile"))
        if Config["modes"]["carousel"]["native_desktop_reorder"]
            rows.Push(Map("key", "super+ctrl+shift+j/k", "desc", "reorder current desktop"))
        rows.Push(Map("key", "super+- / =", "desc", "current tile width -/+"))
        rows.Push(Map("key", "super+f", "desc", "toggle desktop move follow"))
    } else {
        rows.Push(Map("key", "super+h/l", "desc", "focus left/right"))
        rows.Push(Map("key", "super+[ / ]", "desc", "cycle stacked"))
        rows.Push(Map("key", "super+j/k", "desc", "desktop next/prev"))
        rows.Push(Map("key", "super+shift+j/k", "desc", "move desktop"))
        rows.Push(Map("key", "super+u/i", "desc", "focus monitor prev/next"))
        rows.Push(Map("key", "super+shift+u/i", "desc", "move monitor prev/next"))
    }
    rows.Push(Map("key", "super+ctrl+h/j/k/l", "desc", "move/snap"))
    rows.Push(Map("key", "super+m", "desc", "maximize"))
    if Config["window"].Has("super_double_tap_action") && Config["window"]["super_double_tap_action"] = "overview"
        rows.Push(Map("key", "double-super", "desc", "native overview"))
    rows.Push(Map("key", "super+o", "desc", "native overview"))
    rows.Push(Map("key", "overview h/j/k/l", "desc", "navigate"))
    rows.Push(Map("key", "alt+-", "desc", "minimize"))
    rows.Push(Map("key", "alt+q", "desc", "close"))
    rows.Push(Map("key", "super+" Config["window"]["cycle_app_windows_hotkey"], "desc", "cycle app windows"))
    if (Config["window"]["cycle_app_windows_current_hotkey"] != "")
        rows.Push(Map("key", "super+" Config["window"]["cycle_app_windows_current_hotkey"], "desc", "cycle app windows (current desktop)"))
    if Config.Has("window_selector") && Config["window_selector"]["enabled"] {
        rows.Push(Map("key", "super+" Config["window_selector"]["hotkey"], "desc", "window selector"))
    }
    if Config.Has("screen_search") && Config["screen_search"]["enabled"] {
        rows.Push(Map("key", "super+" Config["screen_search"]["hotkey"], "desc", "screen search"))
    }
    rows.Push(Map("key", "", "desc", ""))
    rows.Push(Map("key", "Global Hotkeys", "desc", ""))
    for _, hotkey_config in Config["global_hotkeys"] {
        if hotkey_config["enabled"]
            rows.Push(Map("key", hotkey_config["hotkey"], "desc", hotkey_config["send_keys"]))
    }
    rows.Push(Map("key", "", "desc", ""))
    rows.Push(Map("key", "Command Mode", "desc", ""))
    rows.Push(Map("key", ";", "desc", "enter command mode"))
    return rows
}

BuildCommandToastRowsKey(rows) {
    key := ""
    for _, row in rows {
        key .= row["key"] "|" row["desc"] "||"
    }
    return key
}

BuildAppRows() {
    global Config
    rows := []
    for _, app in Config["apps"] {
        if !app.Has("hotkey") || app["hotkey"] = ""
            continue
        icon_path := ResolveAppIconPath(app)
        rows.Push(Map(
            "hotkey", app["hotkey"],
            "label", app["id"],
            "icon_path", icon_path
        ))
    }
    return rows
}

BuildAppsKey(apps) {
    key := ""
    for _, app in apps {
        key .= app["hotkey"] "|" app["label"] "|" app["icon_path"] "||"
    }
    return key
}

ResolveAppIconPath(app) {
    if !(app is Map)
        return ""
    if app.Has("win_title") && app["win_title"] != "" {
        path := FindAppWindowPath(app["win_title"])
        if (path != "")
            return path
    }
    if app.Has("run") {
        path := ResolveRunPath(app["run"], app)
        if path && FileExist(path)
            return path
    }
    return ""
}

FindAppWindowPath(win_title) {
    if !win_title
        return ""
    hwnds := WinGetList(win_title)
    if (hwnds.Length = 0)
        return ""

    for _, hwnd in hwnds {
        if (InStr(win_title, "explorer.exe")) {
            class_name := WinGetClass("ahk_id " hwnd)
            if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd")
                continue
        }
        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        try {
            path := WinGetProcessPath("ahk_id " hwnd)
            if path
                return path
        } catch {
        }
    }
    return ""
}

GetAppIconIndex(path) {
    global command_toast_image_list, command_toast_icon_cache, command_toast_default_icon_index
    if (path != "" && command_toast_icon_cache.Has(path))
        return command_toast_icon_cache[path]

    if (path = "" || !FileExist(path))
        return command_toast_default_icon_index

    icon_index := 0
    try icon_index := IL_Add(command_toast_image_list, path, 1)
    if (!icon_index)
        icon_index := command_toast_default_icon_index

    if (path != "")
        command_toast_icon_cache[path] := icon_index
    return icon_index
}

EnsureDefaultAppIcon() {
    global command_toast_image_list
    icon_index := 0
    try icon_index := IL_Add(command_toast_image_list, "shell32.dll", 1)
    if (!icon_index)
        icon_index := 1
    return icon_index
}

NormalizeOverlayOpacity() {
    global Config
    opacity := 255
    if Config.Has("helper") && Config["helper"].Has("overlay_opacity")
        opacity := Config["helper"]["overlay_opacity"]
    if !IsNumber(opacity)
        opacity := 255
    opacity := Floor(opacity)
    if (opacity < 0)
        opacity := 0
    if (opacity > 255)
        opacity := 255
    return opacity
}

StrJoin(items, sep) {
    output := ""
    for i, item in items {
        if (i > 1)
            output .= sep
        output .= item
    }
    return output
}

FormatRow(key, desc, key_width) {
    return "  " PadRight(key, key_width) "  " desc
}

PadRight(text, width) {
    if (StrLen(text) >= width)
        return text
    return text . RepeatChar(" ", width - StrLen(text))
}

RepeatChar(char, count) {
    output := ""
    loop count
        output .= char
    return output
}

ClampValue(value, min_value, max_value) {
    return Max(min_value, Min(value, max_value))
}
