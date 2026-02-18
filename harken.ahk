#Requires AutoHotkey v2.0
; Entry point: loads config, initializes modules, registers hotkeys.
#SingleInstance

#Include src/lib/JXON.ahk
#Include src/lib/toml.ahk
#Include src/lib/config_loader.ahk
#Include src/lib/state_store.ahk
#Include src/lib/virtual_desktop.ahk
#Include src/lib/focus_or_run.ahk
#Include src/lib/command_toast.ahk
#Include src/lib/window_inspector.ahk

config_dir := GetConfigDir()
DirCreate(config_dir)
global config_path := config_dir "\harken.toml"
EnsureConfigExists(config_path, DefaultConfig())
config_result := LoadConfig(config_path, DefaultConfig())
global Config := config_result["config"]
config_errors := config_result["errors"]
config_warnings := config_result["warnings"]
if (config_errors.Length) {
    appdata_dir := GetAppDataDir()
    LogConfigErrors(config_errors, appdata_dir "\config.errors.log", config_path)
    return
}
if (config_warnings.Length) {
    appdata_dir := GetAppDataDir()
    LogConfigWarnings(config_warnings, appdata_dir "\config.warnings.log", config_path)
    ShowConfigWarnings(config_warnings, appdata_dir "\config.warnings.log")
}
InitVirtualDesktop()
global AppState := LoadState()
InitCommandToast()

super_keys := Config["super_key"]
if !(super_keys is Array)
    super_keys := [super_keys]

RegisterSuperKeyHotkey("~", "", (*) => OnSuperKeyDown())
if HasSuperKey("CapsLock")
    SetCapsLockState "AlwaysOff"

global reload_mode_active := false
reload_mode_timeout := 20000
RegisterSuperComboHotkey(";", (*) => ActivateReloadMode(reload_mode_timeout))
HotIf ReloadModeActive
Hotkey("r", (*) => ExecuteCommand(() => Reload()))
Hotkey("i", (*) => ExecuteCommand(OpenWindowInspector))
Hotkey("n", (*) => ExecuteCommand(ToggleCommandHelper))
Hotkey("w", (*) => ExecuteCommand(OpenNewWindowForActiveApp))
Hotkey("g", (*) => ExecuteCommand(ReapplyDesktopAssignments))
Hotkey("e", (*) => ExecuteCommand(OpenConfigFile))
Hotkey("Esc", ClearReloadMode)
HotIf

if Config.Has("config_watch") && Config["config_watch"]["enabled"]
    StartConfigWatcher(config_path, Config["config_watch"]["interval_ms"])

SetWinDelay(-1)

#Include src/lib/window_manager.ahk
#Include src/lib/directional_focus.ahk
#Include src/lib/focus_border.ahk
#Include src/lib/window_walker.ahk
#Include src/hotkeys/global_hotkey.ahk
#Include src/hotkeys/apps.ahk
#Include src/hotkeys/window.ahk
#Include src/hotkeys/directional_focus.ahk
#Include src/hotkeys/window_walker.ahk
#Include src/hotkeys/unbound.ahk

DefaultConfig() {
    return Map(
        "config_version", 1,
        "super_key", ["CapsLock"],
        "apps", [
            Map("id", "files", "hotkey", "e", "win_title", "ahk_exe explorer.exe", "exclude_titles", [], "run", "explorer"),
            Map("id", "editor", "hotkey", "v", "win_title", "ahk_exe Code.exe", "exclude_titles", [], "run", "code"),
            Map("id", "terminal", "hotkey", "s", "win_title", "ahk_exe WindowsTerminal.exe", "exclude_titles", [], "run", "wt"),
            Map("id", "notes", "hotkey", "n", "win_title", "ahk_exe notepad++.exe", "exclude_titles", [], "run", "notepad++")
        ],
        "global_hotkeys", [
            Map(
                "enabled", true,
                "hotkey", "Alt",
                "target_exes", [],
                "send_keys", "^{Tab}"
            )
        ],
        "window", Map(
            "resize_step", 20,
            "move_step", 20,
            "super_double_tap_ms", 300,
            "move_mode", Map(
                "enable", true,
                "cancel_key", "Esc"
            ),
            "cycle_app_windows_hotkey", "c",
            "cycle_app_windows_current_hotkey", "+c",
            "center_width_cycle_hotkey", "Space",
            "minimize_others_hotkey", ""
        ),
        "window_selector", Map(
            "enabled", true,
            "hotkey", "w",
            "max_results", 12,
            "title_preview_len", 60,
            "match_title", true,
            "match_exe", true,
            "include_minimized", true,
            "close_on_focus_loss", true
        ),
        "config_watch", Map(
            "enabled", false,
            "interval_ms", 2500
        ),
        "window_manager", Map(
            "grid_size", 3,
            "margins", Map(
                "top", 6,
                "left", 4,
                "right", 4,
                "bottom", 5
            ),
            "gap_px", 0,
            "exceptions_regex", "(Shell_TrayWnd|Shell_SecondaryTrayWnd|WorkerW|XamlExplorerHostIslandWindow)"
        ),
        "virtual_desktop", Map(
            "enabled", true,
            "switch_on_focus", true,
            "ensure_count", 0,
            "cycle_prefer_current", true,
            "prev_hotkey", "h",
            "next_hotkey", "l",
            "move_prev_hotkey", "h",
            "move_next_hotkey", "l",
            "desktop_hotkeys", [],
            "goto_hotkeys", [],
            "move_hotkeys", [],
            "debug_cycle", false,
            "debug_hotkeys", false,
            "debug_focus", false,
            "tray_indicator", false,
            "tray_format", "{current}/{total}",
            "auto_assign", false,
            "auto_assign_interval_ms", 500
        ),
        "directional_focus", Map(
            "enabled", true,
            "stacked_overlap_threshold", 0.5,
            "stack_tolerance_px", 25,
            "prefer_topmost", true,
            "prefer_last_stacked", true,
            "frontmost_guard_px", 200,
            "perpendicular_overlap_min", 0.2,
            "cross_monitor", false,
            "debug_enabled", false
        ),
        "focus_border", Map(
            "enabled", true,
            "border_color", "#357EC7",
            "move_mode_color", "#2ECC71",
            "command_mode_color", "#FFD400",
            "border_thickness", 4,
            "corner_radius", 16,
            "update_interval_ms", 20
        ),
        "helper", Map(
            "enabled", true,
            "overlay_opacity", 200
        ),
        "config_watch", Map(
            "enabled", false,
            "interval_ms", 2500
        )
    )
}

LogConfigErrors(errors, log_path, config_path := "") {
    DirCreate(GetAppDataDir())
    header := "[" A_Now "] Config errors:" "`n"
    FileAppend(header, log_path)
    for _, err in errors {
        FileAppend("- " err "`n", log_path)
    }
    FileAppend("`n", log_path)

    summary := "Config errors detected.`n"
    summary .= "Log: " log_path "`n"
    if config_path
        summary .= "Config: " config_path "`n"

    details := summary "`n"
    for _, err in errors {
        details .= "- " err "`n"
    }

    ShowConfigErrorsGui(details, log_path)
}

LogConfigWarnings(warnings, log_path, config_path := "") {
    DirCreate(GetAppDataDir())
    header := "[" A_Now "] Config warnings:" "`n"
    FileAppend(header, log_path)
    if (config_path != "")
        FileAppend("Config: " config_path "`n", log_path)
    for _, warning in warnings {
        FileAppend("- " warning "`n", log_path)
    }
    FileAppend("`n", log_path)
}

ShowConfigWarnings(warnings, log_path) {
    static warning_gui := ""
    if warning_gui {
        warning_gui.Destroy()
        warning_gui := ""
    }

    warning_gui := Gui("+AlwaysOnTop +ToolWindow", "Harken Config Warnings")
    warning_gui.SetFont("s10", "Segoe UI")
    warning_gui.AddText("xm", "Unknown config keys detected. See log for details.")

    preview := ""
    max_lines := 8
    for i, warning in warnings {
        if (i > max_lines) {
            preview .= "..." "`n"
            break
        }
        preview .= warning "`n"
    }
    warning_gui.AddEdit("xm w520 r" max_lines " ReadOnly", preview)

    open_btn := warning_gui.AddButton("xm y+10 w120", "Open Log")
    open_btn.OnEvent("Click", (*) => Run(log_path))
    close_btn := warning_gui.AddButton("x+10 yp w120", "Close")
    close_btn.OnEvent("Click", (*) => warning_gui.Destroy())
    warning_gui.Show()
}

ShowConfigErrorsGui(details, log_path) {
    error_gui := Gui("+AlwaysOnTop", "harken Config Errors")
    error_gui.SetFont("s10", "Segoe UI")
    edit := error_gui.AddEdit("w760 r18 ReadOnly", details)
    open_btn := error_gui.AddButton("xm y+10 w120", "Open Log")
    open_btn.OnEvent("Click", (*) => Run(log_path))
    close_btn := error_gui.AddButton("x+10 yp w120", "Close")
    close_btn.OnEvent("Click", (*) => error_gui.Destroy())
    error_gui.Show()
}

EnsureConfigExists(config_path, default_config) {
    if FileExist(config_path)
        return

    config_text := TomlDump(default_config, ["apps", "global_hotkeys"])
    FileAppend(config_text, config_path, "UTF-8")
}

GetConfigDir() {
    user_profile := EnvGet("USERPROFILE")
    if !user_profile
        user_profile := A_ScriptDir
    return user_profile "\.config\harken"
}

GetAppDataDir() {
    appdata := EnvGet("APPDATA")
    if appdata
        return appdata "\harken"
    return GetConfigDir()
}

ResetDebugLogs() {
    if !Config.Has("virtual_desktop") || !(Config["virtual_desktop"] is Map)
        return
    vd_config := Config["virtual_desktop"]
    debug_cycle := vd_config.Has("debug_cycle") && vd_config["debug_cycle"]
    debug_hotkeys := vd_config.Has("debug_hotkeys") && vd_config["debug_hotkeys"]
    if !(debug_cycle || debug_hotkeys)
        return

    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    if debug_cycle {
        TryDeleteFile(log_dir "\cycle.debug.log")
    }
    if debug_hotkeys {
        TryDeleteFile(log_dir "\vd.hotkeys.log")
        TryDeleteFile(log_dir "\vd.actions.log")
    }
}

TryDeleteFile(path) {
    try {
        if FileExist(path)
            FileDelete(path)
    }
}

StartConfigWatcher(path, interval_ms := 1000) {
    global config_watch_mtime := ""
    global config_watch_handle := 0
    global config_watch_dir := ""
    global config_watch_path := path
    global config_watch_use_fallback := false
    global config_watch_fallback_notified := false

    if FileExist(path)
        config_watch_mtime := FileGetTime(path, "M")

    try {
        SplitPath(path, &config_watch_filename, &config_watch_dir)
        flags := 0x00000010 | 0x00000001
        config_watch_handle := DllCall("FindFirstChangeNotificationW", "str", config_watch_dir, "int", false, "uint", flags, "ptr")
        if (!config_watch_handle || config_watch_handle = -1)
            throw Error("FindFirstChangeNotificationW failed")
    } catch {
        config_watch_use_fallback := true
        NotifyConfigWatcherFallback()
    }

    SetTimer((*) => CheckConfigWatcher(), interval_ms)
}

CheckConfigWatcher() {
    global config_watch_mtime, config_watch_handle, config_watch_path, config_watch_use_fallback
    if config_watch_use_fallback {
        CheckConfigWatcherPoll()
        return
    }

    if (!config_watch_handle || config_watch_handle = -1) {
        config_watch_use_fallback := true
        NotifyConfigWatcherFallback()
        CheckConfigWatcherPoll()
        return
    }

    result := DllCall("WaitForSingleObject", "ptr", config_watch_handle, "uint", 0)
    if (result != 0)
        return

    if !FileExist(config_watch_path) {
        DllCall("FindNextChangeNotification", "ptr", config_watch_handle)
        return
    }

    current := FileGetTime(config_watch_path, "M")
    if (config_watch_mtime = "") {
        config_watch_mtime := current
    } else if (current != config_watch_mtime) {
        config_watch_mtime := current
        Reload()
        return
    }

    if !DllCall("FindNextChangeNotification", "ptr", config_watch_handle) {
        config_watch_use_fallback := true
        NotifyConfigWatcherFallback()
    }
}

CheckConfigWatcherPoll() {
    global config_watch_mtime, config_watch_path
    if !FileExist(config_watch_path)
        return

    current := FileGetTime(config_watch_path, "M")
    if (config_watch_mtime = "") {
        config_watch_mtime := current
        return
    }
    if (current != config_watch_mtime) {
        config_watch_mtime := current
        Reload()
    }
}

NotifyConfigWatcherFallback() {
    global config_watch_fallback_notified
    if config_watch_fallback_notified
        return
    config_watch_fallback_notified := true
    TrayTip("harken", "Config watcher fell back to polling.", 5)
}

ActivateReloadMode(timeout_ms := 1500) {
    global reload_mode_active := true
    global reload_mode_activated_at := A_TickCount
    SetTimer(ClearReloadMode, 0)
    SetTimer(ClearReloadMode, -timeout_ms)
    UpdateCommandToastVisibility()
}

ClearReloadMode(*) {
    global reload_mode_active := false
    UpdateCommandToastVisibility()
}

ReloadModeActive(*) {
    global reload_mode_active
    return reload_mode_active
}

ExecuteCommand(callback) {
    callback.Call()
    ClearReloadMode()
}

OnSuperKeyDown() {
    if WindowWalker.IsActive() {
        WindowWalker.Hide()
        return
    }
    if command_toast_temp_visible {
        HideCommandToast()
        return
    }
    UpdateCommandToastVisibility()
}

IsSuperKeyPressed(*) {
    global super_keys
    for _, key in super_keys {
        if GetKeyState(key, "P")
            return true
    }
    return false
}

HasSuperKey(target_key) {
    global super_keys
    target_lower := StrLower(target_key)
    for _, key in super_keys {
        if (StrLower(key) = target_lower)
            return true
    }
    return false
}

RegisterSuperKeyHotkey(prefix, suffix, callback) {
    global super_keys
    for _, key in super_keys
        Hotkey(prefix key suffix, callback)
}

RegisterSuperComboHotkey(hotkey_name, callback) {
    global super_keys
    for _, key in super_keys
        Hotkey(key " & " hotkey_name, callback)
}

global WINDOW_MATCH_CACHE_TTL_MS := 300000
global window_match_cache := Map()

MatchAppWindow(app, hwnd := 0) {
    if !(app is Map)
        return false
    if (hwnd = 0)
        try hwnd := WinGetID("A")
    if !hwnd
        return false

    if AppConfigExcludesTitle(app, hwnd)
        return false

    if app.Has("match") && (app["match"] is Map)
        return MatchWindowFields(app["match"], hwnd)

    if app.Has("win_title") && app["win_title"] != "" {
        active_hwnd := 0
        try active_hwnd := WinGetID("A")
        if (active_hwnd && hwnd = active_hwnd)
            return WinActive(app["win_title"])
    }

    return false
}

AppConfigExcludesTitle(app, hwnd) {
    ; Exclude helper windows that should not be matched to an app.
    if !(app is Map)
        return false
    if !app.Has("exclude_titles") || !(app["exclude_titles"] is Array)
        return false

    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    catch
        return false

    for _, pattern in app["exclude_titles"] {
        if (pattern = "")
            continue
        if !RegExMatch(pattern, "^\(\?i\)")
            pattern := "(?i)" pattern
        if RegExMatch(title, pattern)
            return true
    }

    return false
}

MatchWindowFields(match, hwnd) {
    if !WindowExistsAcrossDesktops(hwnd)
        return false
    ; Window handles can go stale during app switching; guard WinGet* calls.
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    exe_name := ""
    class_name := ""
    title := ""
    pid := 0
    got_any := false
    try {
        exe_name := WinGetProcessName("ahk_id " hwnd)
        got_any := true
    }
    try {
        class_name := WinGetClass("ahk_id " hwnd)
        got_any := true
    }
    try {
        title := WinGetTitle("ahk_id " hwnd)
        got_any := true
    }
    try {
        pid := WinGetPID("ahk_id " hwnd)
        got_any := true
    }
    A_DetectHiddenWindows := bak_detect_hidden_windows
    if (pid = 0)
        pid := GetWindowPidForMatch(hwnd)

    if (!got_any) {
        cached := GetWindowMatchCache(hwnd)
        if (cached = "")
            return false
    } else {
        cached := GetWindowMatchCache(hwnd)
    }

    if (exe_name = "" && cached)
        exe_name := cached["exe"]
    if (exe_name = "" && pid)
        exe_name := GetProcessNameFromPid(pid)
    if (exe_name = "" && pid)
        exe_name := GetProcessNameFromSnapshot(pid)
    if (class_name = "" && cached)
        class_name := cached["class"]
    if (title = "" && cached)
        title := cached["title"]
    if (pid = 0 && cached)
        pid := cached["pid"]
    if (pid = 0)
        pid := GetWindowPidForMatch(hwnd)

    if (got_any)
        SetWindowMatchCache(hwnd, exe_name, class_name, title, pid)

    if !MatchField(match, "exe", exe_name)
        return false
    if !MatchField(match, "class", class_name)
        return false
    if !MatchField(match, "title", title)
        return false

    if match.Has("process_tree") && (match["process_tree"] is Map) {
        if !MatchProcessTree(match["process_tree"], hwnd)
            return false
    }

    return true
}

MatchField(match, field_key, value) {
    if !match.Has(field_key) || match[field_key] = ""
        return true

    pattern := match[field_key]
    regex_key := field_key "_regex"
    use_regex := match.Has(regex_key) && match[regex_key]

    if use_regex {
        if !RegExMatch(pattern, "^\(\?i\)")
            pattern := "(?i)" pattern
        return RegExMatch(value, pattern) != 0
    }

    return StrLower(value) = StrLower(pattern)
}

MatchProcessTree(process_tree, hwnd) {
    if !(process_tree is Map)
        return true
    if !WinExist("ahk_id " hwnd)
        return false

    exe_list := []
    if process_tree.Has("exe") {
        exe_value := process_tree["exe"]
        if (exe_value is Array)
            exe_list := exe_value
        else if (exe_value is String && exe_value != "")
            exe_list := [exe_value]
    }
    if (exe_list.Length = 0)
        return false

    mode := process_tree.Has("mode") && process_tree["mode"] != "" ? process_tree["mode"] : "descendant"
    max_depth := process_tree.Has("max_depth") ? process_tree["max_depth"] : 0
    use_regex := process_tree.Has("exe_regex") && process_tree["exe_regex"]
    negate := process_tree.Has("negate") && process_tree["negate"]
    debug_enabled := process_tree.Has("debug") && process_tree["debug"]

    pid := 0
    try pid := WinGetPID("ahk_id " hwnd)
    catch
        pid := 0
    if (pid = 0) {
        cached := GetWindowMatchCache(hwnd)
        if (cached)
            pid := cached["pid"]
    }
    if (pid = 0)
        return false

    matched := ""
    context := GetMatchRunContext()
    if (context is Map) {
        signature := BuildProcessTreeSignature(mode, use_regex, max_depth, negate, exe_list)
        memo_key := pid "|" signature
        if context["memo"].Has(memo_key)
            matched := context["memo"][memo_key]
    }

    if (matched = "") {
        matched := ProcessTreeHasExe(pid, mode, exe_list, use_regex, max_depth)
        if (context is Map)
            context["memo"][memo_key] := matched
    }
    if debug_enabled
        LogProcessTreeDebug(hwnd, pid, mode, exe_list, use_regex, max_depth, negate, matched)
    return negate ? !matched : matched
}

GetProcessTreeMatchDetail(process_tree, hwnd) {
    detail := Map("enabled", false)
    if !(process_tree is Map)
        return detail
    if !WindowExistsAcrossDesktops(hwnd)
        return detail

    exe_list := []
    if process_tree.Has("exe") {
        exe_value := process_tree["exe"]
        if (exe_value is Array)
            exe_list := exe_value
        else if (exe_value is String && exe_value != "")
            exe_list := [exe_value]
    }
    if (exe_list.Length = 0)
        return detail

    mode := process_tree.Has("mode") && process_tree["mode"] != "" ? process_tree["mode"] : "descendant"
    max_depth := process_tree.Has("max_depth") ? process_tree["max_depth"] : 0
    use_regex := process_tree.Has("exe_regex") && process_tree["exe_regex"]
    negate := process_tree.Has("negate") && process_tree["negate"]

    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    pid := 0
    try pid := WinGetPID("ahk_id " hwnd)
    catch
        pid := 0
    A_DetectHiddenWindows := bak_detect_hidden_windows
    if (pid = 0)
        pid := GetWindowPidForMatch(hwnd)
    if (pid = 0)
        return detail

    matched := ProcessTreeHasExe(pid, mode, exe_list, use_regex, max_depth)
    detail["enabled"] := true
    detail["matched"] := matched
    detail["final"] := negate ? !matched : matched
    detail["negate"] := negate
    detail["mode"] := mode
    detail["max_depth"] := max_depth
    return detail
}

ProcessTreeHasExe(pid, mode, exe_list, use_regex, max_depth := 0) {
    snapshot := GetProcessSnapshot()
    parent_map := snapshot["parent_map"]
    exe_map := snapshot["exe_map"]
    children_map := snapshot["children_map"]
    ; Guardrail to keep descendant scans from stalling on huge trees.
    max_nodes := 1000

    if (mode = "ancestor")
        return ProcessTreeMatchAncestors(pid, parent_map, exe_map, exe_list, use_regex, max_depth)
    if (mode = "descendant")
        return ProcessTreeMatchDescendants(pid, children_map, exe_map, exe_list, use_regex, max_depth, max_nodes)
    if (mode = "either") {
        if ProcessTreeMatchAncestors(pid, parent_map, exe_map, exe_list, use_regex, max_depth)
            return true
        return ProcessTreeMatchDescendants(pid, children_map, exe_map, exe_list, use_regex, max_depth, max_nodes)
    }

    return false
}

ProcessTreeMatchAncestors(pid, parent_map, exe_map, exe_list, use_regex, max_depth := 0) {
    depth := 0
    current := pid
    visited := Map()
    while parent_map.Has(current) {
        parent := parent_map[current]
        if (parent = 0)
            break
        if visited.Has(parent)
            break
        visited[parent] := true
        depth += 1
        if (max_depth > 0 && depth > max_depth)
            break
        if ProcessExeMatches(parent, exe_map, exe_list, use_regex)
            return true
        current := parent
    }
    return false
}

ProcessTreeMatchDescendants(pid, children_map, exe_map, exe_list, use_regex, max_depth := 0, max_nodes := 0) {
    queue := []
    depth_map := Map()
    queue.Push(pid)
    depth_map[pid] := 0
    scanned := 0

    while queue.Length {
        current := queue.RemoveAt(1)
        depth := depth_map[current]
        if (max_depth > 0 && depth >= max_depth)
            continue
        if !children_map.Has(current)
            continue
        for _, child in children_map[current] {
            scanned += 1
            if (max_nodes > 0 && scanned > max_nodes)
                return false
            if ProcessExeMatches(child, exe_map, exe_list, use_regex)
                return true
            if !depth_map.Has(child) {
                depth_map[child] := depth + 1
                queue.Push(child)
            }
        }
    }

    return false
}

ProcessExeMatches(pid, exe_map, exe_list, use_regex) {
    if !exe_map.Has(pid)
        return false
    exe_name := exe_map[pid]
    if (exe_name = "")
        return false
    for _, pattern in exe_list {
        if (pattern = "")
            continue
        if use_regex {
            if !RegExMatch(pattern, "^\(\?i\)")
                pattern := "(?i)" pattern
            if RegExMatch(exe_name, pattern)
                return true
        } else if (StrLower(exe_name) = StrLower(pattern)) {
            return true
        }
    }
    return false
}

GetProcessSnapshot() {
    ; Cache per match run to avoid repeated toolhelp scans.
    context := GetMatchRunContext()
    if (context is Map && (context["snapshot"] is Map))
        return context["snapshot"]

    ; Reuse snapshots briefly across hotkey runs to reduce lag.
    static cache_tick := 0
    static cache_snapshot := Map()
    now := A_TickCount
    if (cache_tick && now - cache_tick < 500)
        return cache_snapshot

    snapshot := BuildProcessSnapshot()
    if (context is Map)
        context["snapshot"] := snapshot
    cache_tick := now
    cache_snapshot := snapshot
    return snapshot
}

BuildProcessSnapshot() {
    parent_map := Map()
    exe_map := Map()
    children_map := Map()

    snap := DllCall("CreateToolhelp32Snapshot", "UInt", 0x00000002, "UInt", 0, "Ptr")
    if (snap = -1)
        return Map("parent_map", parent_map, "exe_map", exe_map, "children_map", children_map)

    size := (A_PtrSize = 8) ? 568 : 556
    entry := Buffer(size, 0)
    NumPut("UInt", size, entry, 0)
    offset_pid := 8
    offset_parent := (A_PtrSize = 8) ? 32 : 24
    offset_exe := (A_PtrSize = 8) ? 44 : 36

    if DllCall("Process32FirstW", "Ptr", snap, "Ptr", entry) {
        loop {
            pid := NumGet(entry, offset_pid, "UInt")
            ppid := NumGet(entry, offset_parent, "UInt")
            exe_name := StrGet(entry.Ptr + offset_exe, 260, "UTF-16")
            if (pid != 0) {
                parent_map[pid] := ppid
                exe_map[pid] := exe_name
                if !children_map.Has(ppid)
                    children_map[ppid] := []
                children_map[ppid].Push(pid)
            }
            if !DllCall("Process32NextW", "Ptr", snap, "Ptr", entry)
                break
        }
    }

    DllCall("CloseHandle", "Ptr", snap)
    return Map("parent_map", parent_map, "exe_map", exe_map, "children_map", children_map)
}

BeginMatchRun() {
    global process_tree_match_run, process_tree_match_run_depth
    ; Scope expensive process snapshot + memo cache to a single hotkey run.
    if !IsSet(process_tree_match_run_depth)
        process_tree_match_run_depth := 0
    process_tree_match_run_depth += 1
    if (process_tree_match_run_depth = 1) {
        process_tree_match_run := Map(
            "snapshot", "",
            "memo", Map()
        )
    }
}

EndMatchRun() {
    global process_tree_match_run, process_tree_match_run_depth
    if !IsSet(process_tree_match_run_depth)
        process_tree_match_run_depth := 0
    process_tree_match_run_depth := Max(process_tree_match_run_depth - 1, 0)
    if (process_tree_match_run_depth = 0)
        process_tree_match_run := ""
}

GetMatchRunContext() {
    global process_tree_match_run, process_tree_match_run_depth
    if !IsSet(process_tree_match_run_depth) || process_tree_match_run_depth = 0
        return ""
    if !(process_tree_match_run is Map)
        return ""
    return process_tree_match_run
}

BuildProcessTreeSignature(mode, use_regex, max_depth, negate, exe_list) {
    return mode "|" use_regex "|" max_depth "|" negate "|" StrJoin(exe_list, ",")
}

GetWindowMatchCache(hwnd) {
    global window_match_cache, WINDOW_MATCH_CACHE_TTL_MS
    if !IsSet(WINDOW_MATCH_CACHE_TTL_MS)
        WINDOW_MATCH_CACHE_TTL_MS := 300000
    if !IsSet(window_match_cache) || !(window_match_cache is Map)
        window_match_cache := Map()
    if !window_match_cache.Has(hwnd)
        return ""
    entry := window_match_cache[hwnd]
    if !(entry is Map) {
        window_match_cache.Delete(hwnd)
        return ""
    }
    if !entry.Has("seen_at") || (A_TickCount - entry["seen_at"] > WINDOW_MATCH_CACHE_TTL_MS) {
        window_match_cache.Delete(hwnd)
        return ""
    }
    return entry
}

SetWindowMatchCache(hwnd, exe_name, class_name, title, pid := 0) {
    global window_match_cache
    if !IsSet(window_match_cache) || !(window_match_cache is Map)
        window_match_cache := Map()
    entry := window_match_cache.Has(hwnd) ? window_match_cache[hwnd] : Map()
    entry["exe"] := exe_name
    entry["class"] := class_name
    entry["title"] := title
    entry["pid"] := pid
    entry["seen_at"] := A_TickCount
    window_match_cache[hwnd] := entry
}

TryUpdateWindowMatchCache(hwnd) {
    exe_name := ""
    class_name := ""
    title := ""
    pid := 0
    got_any := false
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    if VirtualDesktopEnabled() {
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num <= 0)
            return
    }
    try {
        exe_name := WinGetProcessName("ahk_id " hwnd)
        got_any := true
    }
    try {
        class_name := WinGetClass("ahk_id " hwnd)
        got_any := true
    }
    try {
        title := WinGetTitle("ahk_id " hwnd)
        got_any := true
    }
    try {
        pid := WinGetPID("ahk_id " hwnd)
        got_any := true
    }
    A_DetectHiddenWindows := bak_detect_hidden_windows
    if (pid = 0)
        pid := GetWindowPidForMatch(hwnd)
    if (exe_name = "" && pid)
        exe_name := GetProcessNameFromPid(pid)
    if (exe_name = "" && pid)
        exe_name := GetProcessNameFromSnapshot(pid)
    if !got_any
        return

    global window_match_cache
    if !IsSet(window_match_cache) || !(window_match_cache is Map)
        window_match_cache := Map()
    cached := window_match_cache.Has(hwnd) ? window_match_cache[hwnd] : ""
    if (exe_name = "" && cached)
        exe_name := cached["exe"]
    if (class_name = "" && cached)
        class_name := cached["class"]
    if (title = "" && cached)
        title := cached["title"]
    if (pid = 0 && cached)
        pid := cached["pid"]

    SetWindowMatchCache(hwnd, exe_name, class_name, title, pid)
}

UpdateWindowMatchCacheFromList(hwnds) {
    if !(hwnds is Array)
        return
    for _, hwnd in hwnds
        TryUpdateWindowMatchCache(hwnd)
}

GetCachedWindowsByExe(exe_name) {
    global window_match_cache
    if !IsSet(window_match_cache) || !(window_match_cache is Map)
        window_match_cache := Map()
    list := []
    if (exe_name = "")
        return list
    target := StrLower(exe_name)
    for hwnd, entry in window_match_cache {
        if !WindowExistsAcrossDesktops(hwnd) {
            window_match_cache.Delete(hwnd)
            continue
        }
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(hwnd)
            if (desktop_num <= 0)
                continue
        }
        cached := GetWindowMatchCache(hwnd)
        if (cached = "")
            continue
        exe_value := cached.Has("exe") ? cached["exe"] : ""
        if (exe_value = "")
            continue
        if (StrLower(exe_value) = target)
            list.Push(hwnd)
    }
    return list
}

GetProcessNameFromPid(pid) {
    if (pid <= 0)
        return ""
    try return ProcessGetName(pid)
    catch
        return ""
}

GetProcessNameFromSnapshot(pid) {
    if (pid <= 0)
        return ""
    snapshot := GetProcessSnapshot()
    exe_map := snapshot["exe_map"]
    if exe_map.Has(pid)
        return exe_map[pid]
    return ""
}

GetWindowPidForMatch(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    return pid
}

LogProcessTreeDebug(hwnd, pid, mode, exe_list, use_regex, max_depth, negate, matched) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\process_tree.debug.log"

    lines := []
    lines.Push("[" A_Now "] hwnd=" Format("0x{:X}", hwnd) " pid=" pid)
    lines.Push("  mode=" mode " use_regex=" use_regex " max_depth=" max_depth " negate=" negate " matched=" matched)
    lines.Push("  exe_list=" StrJoin(exe_list, ","))

    snapshot := GetProcessSnapshot()
    parent_map := snapshot["parent_map"]
    exe_map := snapshot["exe_map"]
    children_map := snapshot["children_map"]

    lines.Push("  ancestors:")
    for _, item in BuildProcessTreeAncestorSummary(pid, parent_map, exe_map, max_depth)
        lines.Push("    " item)

    lines.Push("  descendants:")
    for _, item in BuildProcessTreeDescendantSummary(pid, children_map, exe_map, max_depth)
        lines.Push("    " item)

    SafeFileAppend(StrJoin(lines, "`n") "`n", log_path)
}

BuildProcessTreeAncestorSummary(pid, parent_map, exe_map, max_depth := 0) {
    max_rows := 20
    rows := []
    depth := 0
    current := pid
    visited := Map()
    while parent_map.Has(current) {
        parent := parent_map[current]
        if (parent = 0)
            break
        if visited.Has(parent)
            break
        visited[parent] := true
        depth += 1
        if (max_depth > 0 && depth > max_depth)
            break
        exe_name := exe_map.Has(parent) ? exe_map[parent] : ""
        rows.Push("d" depth " pid=" parent " exe=" exe_name)
        if (rows.Length >= max_rows)
            break
        current := parent
    }
    if (rows.Length = 0)
        rows.Push("(none)")
    return rows
}

BuildProcessTreeDescendantSummary(pid, children_map, exe_map, max_depth := 0) {
    max_rows := 40
    rows := []
    queue := []
    depth_map := Map()
    queue.Push(pid)
    depth_map[pid] := 0

    while queue.Length {
        current := queue.RemoveAt(1)
        depth := depth_map[current]
        if (max_depth > 0 && depth >= max_depth)
            continue
        if !children_map.Has(current)
            continue
        for _, child in children_map[current] {
            exe_name := exe_map.Has(child) ? exe_map[child] : ""
            rows.Push("d" (depth + 1) " pid=" child " exe=" exe_name)
            if (rows.Length >= max_rows)
                return rows
            if !depth_map.Has(child) {
                depth_map[child] := depth + 1
                queue.Push(child)
            }
        }
    }

    if (rows.Length = 0)
        rows.Push("(none)")
    return rows
}

SafeFileAppend(text, path, retries := 3) {
    ; Guard against re-entrancy and transient file locks.
    static writing := false
    if writing
        return false
    writing := true
    attempt := 0
    loop retries {
        attempt += 1
        try {
            FileAppend(text, path)
            writing := false
            return true
        } catch {
            Sleep(20)
        }
    }
    writing := false
    return false
}

OpenWindowInspector() {
    ShowWindowInspector()
}

OpenConfigFile() {
    global config_path
    if !config_path
        return
    if FileExist(config_path)
        Run(config_path)
}

OpenNewWindowForActiveApp() {
    hwnd := WinExist("A")
    if !hwnd
        return

    exe := WinGetProcessName("ahk_id " hwnd)
    if !exe
        return

    app_config := FindAppConfigByWindow(hwnd)
    if (app_config is Map) {
        RunResolved(app_config["run"], app_config)
        return
    }

    RunResolved(exe)
}

FindAppConfigByWindow(hwnd) {
    for _, app in Config["apps"] {
        if MatchAppWindow(app, hwnd)
            return app
    }
    return ""
}
