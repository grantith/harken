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
    if !WinExist("ahk_id " hwnd)
        return false
    ; Window handles can go stale during app switching; guard WinGet* calls.
    try exe_name := WinGetProcessName("ahk_id " hwnd)
    catch
        return false
    try class_name := WinGetClass("ahk_id " hwnd)
    catch
        return false
    try title := WinGetTitle("ahk_id " hwnd)
    catch
        return false

    if !MatchField(match, "exe", exe_name)
        return false
    if !MatchField(match, "class", class_name)
        return false
    if !MatchField(match, "title", title)
        return false

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
