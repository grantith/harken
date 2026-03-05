; Helper: focus existing window, otherwise run app.
; Launch-or-focus helpers + per-app matching.
; If the target window is already active, toggle back to the previous window
; recorded for this hotkey.
FocusOrRun(winTitle, exePath, hotkey_id, app_config := "", *) {
    static last_window := Map()
    target_hwnd := 0
    BeginMatchRun()
    hwnds := GetAppWindowList(winTitle, app_config)
    EndMatchRun()
    if VirtualDesktopFocusDebugEnabled()
        LogFocusOrRunCandidates(hotkey_id, app_config, hwnds)
    current_hwnd := 0
    try current_hwnd := WinGetID("A")
    catch
        current_hwnd := 0

    if (hwnds.Length) {
        target_hwnd := PickFocusableAppWindow(hwnds, winTitle)
        if (!target_hwnd)
            target_hwnd := PickDesktopAssignedWindow(hwnds)
    }

    if target_hwnd {
        if VirtualDesktopFocusDebugEnabled()
            LogFocusOrRunSelection(hotkey_id, app_config, target_hwnd)
        if (current_hwnd = target_hwnd) {
            if last_window.Has(hotkey_id) && WindowExistsAcrossDesktops(last_window[hotkey_id]) {
                ActivateWindowAcrossDesktops(last_window[hotkey_id])
            }
            return
        }
        if current_hwnd && (current_hwnd != target_hwnd) {
            last_window[hotkey_id] := current_hwnd
        }
        ActivateWindowAcrossDesktops(target_hwnd)
    } else {
        if VirtualDesktopFocusDebugEnabled()
            LogFocusOrRunMiss(hotkey_id, app_config)
        RunResolved(exePath, app_config)
        ScheduleMoveAppWindowToDesktop(winTitle, app_config)
    }
}

GetAppWindowList(win_title, app_config := "") {
    if (app_config is Map && app_config.Has("match") && app_config["match"] is Map) {
        return GetWindowsByMatch(app_config["match"], app_config)
    }
    if !win_title
        return []
    win_list := GetWindowsAcrossDesktops(win_title)
    if RegExMatch(win_title, "i)^ahk_exe\s+") {
        exe_name := RegExReplace(win_title, "i)^ahk_exe\s+", "")
        win_list := MergeWindowLists(win_list, CollectWindowsByExeFallback(exe_name, win_list))
    }
    win_list := FilterDesktopAssignedWindows(win_list, true)
    UpdateWindowMatchCacheFromList(win_list)
    return FilterExcludedWindows(win_list, app_config)
}

GetWindowsByMatch(match, app_config := "") {
    matches := []
    match_true := 0
    exclude_true := 0
    debug_results := []
    win_list := GetWindowsByMatchCandidates(match)
    win_list := FilterDesktopAssignedWindows(win_list, true)
    UpdateWindowMatchCacheFromList(win_list)
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    for _, hwnd in win_list {
        matched := MatchWindowFields(match, hwnd)
        if matched
            match_true += 1
        excluded := AppConfigExcludesTitle(app_config, hwnd)
        if excluded
            exclude_true += 1
        if VirtualDesktopFocusDebugEnabled() {
            debug_results.Push(Map(
                "hwnd", hwnd,
                "matched", matched,
                "excluded", excluded
            ))
        }
        if matched && !excluded
            matches.Push(hwnd)
    }
    A_DetectHiddenWindows := bak_detect_hidden_windows
    if VirtualDesktopFocusDebugEnabled() && matches.Length = 0 {
        LogMatchDiagnostics(match, win_list, app_config, debug_results)
        LogMatchCounts(match_true, exclude_true, win_list)
    }
    return matches
}

GetWindowsByMatchCandidates(match) {
    if !(match is Map)
        return GetWindowsAcrossDesktops()
    if match.Has("exe") && match["exe"] != "" && !(match.Has("exe_regex") && match["exe_regex"]) {
        exe_name := match["exe"]
        if RegExMatch(exe_name, "i)^ahk_exe\s+")
            exe_name := RegExReplace(exe_name, "i)^ahk_exe\s+", "")
        win_list := GetWindowsAcrossDesktops("ahk_exe " exe_name)
        return MergeWindowLists(win_list, CollectWindowsByExeFallback(exe_name, win_list))
    }
    return GetWindowsAcrossDesktops()
}

MergeWindowLists(primary, fallback) {
    if !(fallback is Array)
        return primary
    if !(primary is Array)
        primary := []
    if (fallback.Length = 0)
        return primary
    dedup := Map()
    merged := []
    for _, hwnd in primary {
        dedup[hwnd] := true
        merged.Push(hwnd)
    }
    for _, hwnd in fallback {
        if !dedup.Has(hwnd) {
            merged.Push(hwnd)
            dedup[hwnd] := true
        }
    }
    return merged
}

FilterDesktopAssignedWindows(hwnds, allow_fallback := false) {
    if !VirtualDesktopEnabled()
        return hwnds
    filtered := []
    for _, hwnd in hwnds {
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num <= 0)
            continue
        filtered.Push(hwnd)
    }
    if (allow_fallback && filtered.Length = 0)
        return hwnds
    return filtered
}

CollectWindowsByExeFallback(exe_name, win_list) {
    merged := []
    cached := GetCachedWindowsByExe(exe_name)
    merged := MergeWindowLists(merged, cached)
    expanded := []
    if ShouldExpandExeSearch(win_list)
        expanded := CollectWindowsByExe(exe_name)
    merged := MergeWindowLists(merged, expanded)
    if VirtualDesktopFocusDebugEnabled()
        LogFocusOrRunExeFallback(exe_name, win_list, cached, expanded, merged)
    return merged
}

ShouldExpandExeSearch(win_list) {
    if !VirtualDesktopEnabled()
        return false
    if !(win_list is Array) || win_list.Length = 0
        return true
    has_valid := false
    has_invalid := false
    for _, hwnd in win_list {
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num > 0)
            has_valid := true
        else
            has_invalid := true
    }
    if VirtualDesktopFocusDebugEnabled()
        LogExeExpandDecision(win_list.Length, has_valid, has_invalid)
    return !has_valid
}

CollectWindowsByExe(exe_name) {
    if (exe_name = "")
        return []
    filtered := []
    ; WinGetList may miss off-desktop windows for some apps.
    win_list := GetAllTopLevelWindows()
    pid_set := BuildProcessPidSet(exe_name)
    total_windows := win_list.Length
    pid_zero := 0
    pid_match := 0
    pid_miss := 0
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    for _, hwnd in win_list {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        pid := GetWindowPid(hwnd)
        if (pid = 0) {
            pid_zero += 1
            continue
        }
        if !pid_set.Has(pid) {
            pid_miss += 1
            continue
        }
        pid_match += 1
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(hwnd)
            if (desktop_num <= 0)
                continue
        }
        filtered.Push(hwnd)
    }
    A_DetectHiddenWindows := bak_detect_hidden_windows
    if VirtualDesktopFocusDebugEnabled() {
        LogFocusOrRunEnumStats(exe_name, total_windows, pid_set.Count, pid_match, pid_miss, pid_zero)
        if (pid_set.Count = 0)
            LogFocusOrRunSnapshotStats(exe_name)
    }
    return filtered
}

BuildProcessPidSet(exe_name) {
    pid_set := Map()
    if (exe_name = "")
        return pid_set
    snapshot := GetProcessSnapshot()
    exe_map := snapshot["exe_map"]
    target := StrLower(exe_name)
    for pid, name in exe_map {
        if (StrLower(name) = target)
            pid_set[pid] := true
    }
    return pid_set
}

LogFocusOrRunEnumStats(exe_name, total_windows, pid_set_count, pid_match, pid_miss, pid_zero) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    line := "[" A_Now "] enum_stats exe=" exe_name
    line .= " windows=" total_windows
    line .= " pid_set=" pid_set_count
    line .= " pid_match=" pid_match
    line .= " pid_miss=" pid_miss
    line .= " pid_zero=" pid_zero
    SafeFileAppend(line "`n", log_path)
}

LogFocusOrRunSnapshotStats(exe_name) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    snapshot := GetProcessSnapshot()
    exe_map := snapshot["exe_map"]
    exact := 0
    contains_count := 0
    total := 0
    target := StrLower(exe_name)
    needle := StrLower(RegExReplace(exe_name, "\.exe$", ""))
    for _, name in exe_map {
        total += 1
        lower := StrLower(name)
        if (lower = target)
            exact += 1
        if (InStr(lower, needle))
            contains_count += 1
    }
    line := "[" A_Now "] snapshot_stats exe=" exe_name
    line .= " total=" total
    line .= " exact=" exact
    line .= " contains=" contains_count
    SafeFileAppend(line "`n", log_path)
}

GetAllTopLevelWindows() {
    hwnds := []
    global enum_windows_target := hwnds
    callback := CallbackCreate(EnumWindowsCallback, "Fast")
    DllCall("EnumWindows", "Ptr", callback, "Ptr", 0)
    CallbackFree(callback)
    enum_windows_target := ""
    return hwnds
}

EnumWindowsCallback(hwnd, lparam) {
    global enum_windows_target
    if (enum_windows_target is Array)
        enum_windows_target.Push(hwnd)
    return true
}

GetWindowPid(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    return pid
}

LogFocusOrRunCandidates(hotkey_id, app_config, hwnds) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    app_id := (app_config is Map && app_config.Has("id")) ? app_config["id"] : ""
    lines := []
    lines.Push("[" A_Now "] focus_candidates hotkey=" hotkey_id " app=" app_id " count=" (hwnds is Array ? hwnds.Length : 0))
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    if (hwnds is Array) {
        for _, hwnd in hwnds {
            desktop_num := VirtualDesktopEnabled() ? GetWindowDesktopNum(hwnd) : 0
            exe_name := ""
            class_name := ""
            title := ""
            exe_name := ""
            try exe_name := WinGetProcessName("ahk_id " hwnd)
            if (exe_name = "") {
                pid := GetWindowPid(hwnd)
                exe_name := GetProcessNameFromPid(pid)
                if (exe_name = "")
                    exe_name := GetProcessNameFromSnapshot(pid)
            }
            try class_name := WinGetClass("ahk_id " hwnd)
            try title := WinGetTitle("ahk_id " hwnd)
            lines.Push("  hwnd=" Format("0x{:X}", hwnd) " desktop=" desktop_num " exe=" exe_name " class=" class_name " title=" title)
        }
    }
    A_DetectHiddenWindows := bak_detect_hidden_windows
    SafeFileAppend(StrJoin(lines, "`n") "`n", log_path)
}

LogFocusOrRunSelection(hotkey_id, app_config, hwnd) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    app_id := (app_config is Map && app_config.Has("id")) ? app_config["id"] : ""
    desktop_num := VirtualDesktopEnabled() ? GetWindowDesktopNum(hwnd) : 0
    exe_name := ""
    class_name := ""
    title := ""
    try exe_name := WinGetProcessName("ahk_id " hwnd)
    try class_name := WinGetClass("ahk_id " hwnd)
    try title := WinGetTitle("ahk_id " hwnd)
    line := "[" A_Now "] focus_select hotkey=" hotkey_id " app=" app_id
    line .= " hwnd=" Format("0x{:X}", hwnd) " desktop=" desktop_num " exe=" exe_name " class=" class_name " title=" title
    SafeFileAppend(line "`n", log_path)
}

LogFocusOrRunMiss(hotkey_id, app_config) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    app_id := (app_config is Map && app_config.Has("id")) ? app_config["id"] : ""
    SafeFileAppend("[" A_Now "] focus_miss hotkey=" hotkey_id " app=" app_id "`n", log_path)
}

LogFocusOrRunExeFallback(exe_name, win_list, cached, expanded, merged) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    line := "[" A_Now "] exe_fallback exe=" exe_name
    line .= " winget=" (win_list is Array ? win_list.Length : 0)
    line .= " cached=" (cached is Array ? cached.Length : 0)
    line .= " enum=" (expanded is Array ? expanded.Length : 0)
    line .= " merged=" (merged is Array ? merged.Length : 0)
    SafeFileAppend(line "`n", log_path)
}

LogMatchDiagnostics(match, win_list, app_config := "", debug_results := "") {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    exe_pattern := match.Has("exe") ? match["exe"] : ""
    class_pattern := match.Has("class") ? match["class"] : ""
    title_pattern := match.Has("title") ? match["title"] : ""
    exe_regex := match.Has("exe_regex") && match["exe_regex"]
    class_regex := match.Has("class_regex") && match["class_regex"]
    title_regex := match.Has("title_regex") && match["title_regex"]

    lines := []
    lines.Push("[" A_Now "] match_diag exe=" exe_pattern " class=" class_pattern " title=" title_pattern)
    lines.Push("  regex exe=" exe_regex " class=" class_regex " title=" title_regex " candidates=" (win_list is Array ? win_list.Length : 0))
    process_tree := match.Has("process_tree") && (match["process_tree"] is Map) ? match["process_tree"] : ""

    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    sample_max := 12
    if (win_list is Array) {
        debug_index := 1
        for _, hwnd in win_list {
            if (sample_max <= 0)
                break
            sample_max -= 1
            exists := WindowExistsAcrossDesktops(hwnd)
            desktop_num := VirtualDesktopEnabled() ? GetWindowDesktopNum(hwnd) : 0
            pid := GetWindowPid(hwnd)
            exe_name := ""
            class_name := ""
            title := ""
            try exe_name := WinGetProcessName("ahk_id " hwnd)
            if (exe_name = "" && pid)
                exe_name := GetProcessNameFromPid(pid)
            if (exe_name = "" && pid)
                exe_name := GetProcessNameFromSnapshot(pid)
            try class_name := WinGetClass("ahk_id " hwnd)
            try title := WinGetTitle("ahk_id " hwnd)

            exe_ok := MatchFieldValue(exe_pattern, exe_name, exe_regex)
            class_ok := MatchFieldValue(class_pattern, class_name, class_regex)
            title_ok := MatchFieldValue(title_pattern, title, title_regex)
            tree_ok := ""
            tree_matched := ""
            if (process_tree is Map) {
                detail := GetProcessTreeMatchDetail(process_tree, hwnd)
                if detail["enabled"] {
                    tree_ok := detail["final"]
                    tree_matched := detail["matched"]
                }
            }
            match_ok := MatchWindowFields(match, hwnd)
            exclude_ok := ""
            if (app_config is Map)
                exclude_ok := AppConfigExcludesTitle(app_config, hwnd)
            lines.Push("  hwnd=" Format("0x{:X}", hwnd) " desktop=" desktop_num " pid=" pid)
            lines.Push("    exists=" exists " match_ok=" match_ok " exclude=" exclude_ok)
            lines.Push("    exe=" exe_name " match=" exe_ok)
            lines.Push("    class=" class_name " match=" class_ok)
            lines.Push("    title=" title " match=" title_ok)
            if (tree_ok != "")
                lines.Push("    process_tree matched=" tree_matched " final=" tree_ok)
            if (debug_results is Array && debug_index <= debug_results.Length) {
                entry := debug_results[debug_index]
                debug_index += 1
                loop_match := entry.Has("matched") ? entry["matched"] : ""
                loop_exclude := entry.Has("excluded") ? entry["excluded"] : ""
                lines.Push("    loop matched=" loop_match " excluded=" loop_exclude)
            }
        }
    }
    A_DetectHiddenWindows := bak_detect_hidden_windows
    SafeFileAppend(StrJoin(lines, "`n") "`n", log_path)
}

LogMatchCounts(match_true, exclude_true, win_list) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    total := (win_list is Array ? win_list.Length : 0)
    line := "[" A_Now "] match_counts total=" total " matched=" match_true " excluded=" exclude_true
    SafeFileAppend(line "`n", log_path)
}

MatchFieldValue(pattern, value, use_regex) {
    if (pattern = "")
        return true
    if use_regex {
        if !RegExMatch(pattern, "^\(\?i\)")
            pattern := "(?i)" pattern
        return RegExMatch(value, pattern) != 0
    }
    return StrLower(value) = StrLower(pattern)
}

LogExeExpandDecision(count, has_valid, has_invalid) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"
    line := "[" A_Now "] exe_expand candidates=" count " has_valid=" has_valid " has_invalid=" has_invalid
    SafeFileAppend(line "`n", log_path)
}

FilterExcludedWindows(hwnds, app_config := "") {
    if !(app_config is Map)
        return hwnds
    if !app_config.Has("exclude_titles") || !(app_config["exclude_titles"] is Array)
        return hwnds

    filtered := []
    for _, hwnd in hwnds {
        if !AppConfigExcludesTitle(app_config, hwnd)
            filtered.Push(hwnd)
    }

    return filtered
}

PickFocusableAppWindow(hwnds, win_title) {
    for hwnd in hwnds {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if (InStr(win_title, "explorer.exe")) {
            try class_name := WinGetClass("ahk_id " hwnd)
            catch
                continue
            if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd")
                continue
        }
        try ex_style := WinGetExStyle("ahk_id " hwnd)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        try style := WinGetStyle("ahk_id " hwnd)
        catch
            continue
        allow_invisible := false
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(hwnd)
            if (desktop_num <= 0)
                continue
            if (desktop_num > 0 && desktop_num != VD.getCurrentDesktopNum())
                allow_invisible := true
        }
        if (!allow_invisible && !(style & 0x10000000))
            continue

        try state := WinGetMinMax("ahk_id " hwnd)
        catch
            continue
        if (state = -1)
            continue
        return hwnd
    }

    for hwnd in hwnds {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        try state := WinGetMinMax("ahk_id " hwnd)
        catch
            continue
        if (state = -1)
            return hwnd
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(hwnd)
            if (desktop_num <= 0)
                continue
        }
    }
    return 0
}

PickDesktopAssignedWindow(hwnds) {
    for hwnd in hwnds {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(hwnd)
            if (desktop_num <= 0)
                continue
        }
        return hwnd
    }
    return 0
}

ScheduleMoveAppWindowToDesktop(win_title, app_config := "") {
    if !VirtualDesktopEnabled()
        return
    target_desktop := GetAppTargetDesktop(app_config)
    if (target_desktop <= 0)
        return

    follow_on_spawn := GetAppFollowOnSpawn(app_config)
    attempts := 0
    callback := 0
    callback := () => TryMoveAppWindowToDesktop(win_title, app_config, target_desktop, follow_on_spawn, &attempts, callback)
    SetTimer(callback, 200)
}

GetAppTargetDesktop(app_config := "") {
    if !(app_config is Map)
        return 0
    if !app_config.Has("desktop")
        return 0
    return app_config["desktop"]
}

GetAppFollowOnSpawn(app_config := "") {
    if (app_config is Map && app_config.Has("follow_on_spawn"))
        return app_config["follow_on_spawn"]
    return true
}

TryMoveAppWindowToDesktop(win_title, app_config, target_desktop, follow_on_spawn, &attempts, callback) {
    attempts += 1
    hwnds := GetAppWindowList(win_title, app_config)
    hwnd := PickFocusableAppWindow(hwnds, win_title)
    if (!hwnd && hwnds.Length)
        hwnd := hwnds[1]

    if (hwnd) {
        VD.MoveWindowToDesktopNum("ahk_id " hwnd, target_desktop, follow_on_spawn)
        if follow_on_spawn {
            curtain_visible := BeginDesktopSwitchCurtain()
            try {
                VD.goToDesktopNum(target_desktop)
                VD.WaitDesktopSwitched(target_desktop)
            } finally {
                EndDesktopSwitchCurtain(curtain_visible)
            }
        }
        try {
            assigned_desktop := GetWindowDesktopNum(hwnd)
            if (assigned_desktop > 0 && assigned_desktop != target_desktop)
                VD.MoveWindowToDesktopNum("ahk_id " hwnd, target_desktop, follow_on_spawn)
        }
        SetTimer(callback, 0)
        return
    }

    if (attempts >= 30)
        SetTimer(callback, 0)
}

RunResolved(command, app_config := "") {
    resolved := ResolveRunPath(command, app_config)
    run_start_in := ""
    if (app_config is Map && app_config.Has("run_start_in"))
        run_start_in := app_config["run_start_in"]
    try {
        if (run_start_in = "") {
            link_info := ResolveShortcutStartIn(resolved)
            if (link_info is Map) {
                resolved := link_info["target"]
                run_start_in := link_info["start_in"]
            }
        } else if (StrLower(SubStr(resolved, -4)) = ".lnk") {
            shortcut := ResolveShortcutTarget(resolved)
            if shortcut
                resolved := shortcut
        }
        if (run_start_in != "")
            Run resolved, run_start_in
        else
            Run resolved
    } catch as err {
        MsgBox(
            "Failed to launch: " command "`n" err.Message "`n`n" .
            "Tip: set apps[].run to a full path or an App Paths-registered exe.",
            "harken",
            "Iconx"
        )
    }
}

ResolveRunPath(command, app_config := "") {
    command := Trim(command, " `t")
    if (SubStr(command, 1, 1) = '"' && SubStr(command, -1) = '"')
        command := SubStr(command, 2, -1)
    if (StrLower(SubStr(command, -4)) = ".lnk") {
        return command
    }
    if (InStr(command, "\\") || InStr(command, "/") || InStr(command, ":")) {
        if FileExist(command)
            return command
        return command
    }

    candidates := [command, command ".exe"]
    reg_roots := [
        "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\",
        "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\"
    ]

    for _, name in candidates {
        for _, root in reg_roots {
            try {
                path := RegRead(root name)
                if path
                    return path
            }
        }
    }

    shortcut_target := FindStartMenuShortcut(command)
    if shortcut_target
        return shortcut_target

    exe_name := command
    if !InStr(StrLower(exe_name), ".exe")
        exe_name := exe_name ".exe"

    extra_paths := []
    if (app_config is Map && app_config.Has("run_paths") && app_config["run_paths"] is Array) {
        for _, path in app_config["run_paths"]
            extra_paths.Push(path)
    }

    for _, path in extra_paths {
        path := ExpandEnvVars(path)
        candidate := path "\\" exe_name
        if FileExist(candidate)
            return candidate
    }

    alias_target := FindWindowsAppsAlias(exe_name)
    if alias_target
        return alias_target

    uninstall_target := FindUninstallEntry(command)
    if uninstall_target
        return uninstall_target

    common_target := FindExeInCommonLocations(exe_name)
    if common_target
        return common_target

    for _, base in GetCommonRunPaths() {
        candidate := base "\\" exe_name
        if FileExist(candidate)
            return candidate
    }

    return command
}

GetCommonRunPaths() {
    paths := []
    user_profile := EnvGet("USERPROFILE")
    app_data := EnvGet("APPDATA")
    local_app_data := EnvGet("LOCALAPPDATA")
    program_files := EnvGet("ProgramFiles")
    program_files_x86 := EnvGet("ProgramFiles(x86)")

    if app_data
        paths.Push(app_data)
    if local_app_data
        paths.Push(local_app_data)
    if program_files
        paths.Push(program_files)
    if program_files_x86
        paths.Push(program_files_x86)
    if user_profile
        paths.Push(user_profile)

    return paths
}

ExpandEnvVars(path) {
    if !path
        return ""

    expanded := path
    if InStr(expanded, "%") {
        loop {
            start := InStr(expanded, "%")
            if !start
                break
            end := InStr(expanded, "%",, start + 1)
            if !end
                break
            var_name := SubStr(expanded, start + 1, end - start - 1)
            var_value := EnvGet(var_name)
            expanded := SubStr(expanded, 1, start - 1) var_value SubStr(expanded, end + 1)
        }
    }

    if (SubStr(expanded, 1, 2) = "~\\") {
        user_profile := EnvGet("USERPROFILE")
        if user_profile
            expanded := user_profile SubStr(expanded, 2)
    }

    return expanded
}

FindStartMenuShortcut(command) {
    name := StrLower(command)
    if InStr(name, ".exe")
        name := SubStr(name, 1, StrLen(name) - 4)

    folders := [A_StartMenu, A_StartMenuCommon]
    for _, base in folders {
        path := base "\\Programs"
        if !DirExist(path)
            continue
        loop files, path "\\*.lnk", "R" {
            SplitPath(A_LoopFileName, &file_name)
            file_name := StrLower(file_name)
            if !(InStr(file_name, name)) {
                target := ResolveShortcutTarget(A_LoopFilePath)
                if !target
                    continue
                if InStr(StrLower(target), name)
                    return A_LoopFilePath
                continue
            }
            target := ResolveShortcutTarget(A_LoopFilePath)
            if target
                return A_LoopFilePath
        }
    }
    return ""
}

ResolveShortcutTarget(link_path) {
    if !link_path || !FileExist(link_path)
        return ""
    try {
        shell := ComObject("WScript.Shell")
        shortcut := shell.CreateShortcut(link_path)
        target := Trim(shortcut.TargetPath " " shortcut.Arguments)
        return target
    } catch {
        return ""
    }
}

ResolveShortcutStartIn(link_path) {
    if !link_path || !FileExist(link_path)
        return ""
    if (StrLower(SubStr(link_path, -4)) != ".lnk")
        return ""
    try {
        shell := ComObject("WScript.Shell")
        shortcut := shell.CreateShortcut(link_path)
        return Map(
            "target", Trim(shortcut.TargetPath " " shortcut.Arguments),
            "start_in", shortcut.WorkingDirectory
        )
    } catch {
        return ""
    }
}

FindWindowsAppsAlias(exe_name) {
    apps_path := EnvGet("LOCALAPPDATA") "\\Microsoft\\WindowsApps"
    if !DirExist(apps_path)
        return ""
    alias_path := apps_path "\\" exe_name
    if FileExist(alias_path)
        return alias_path
    return ""
}

FindUninstallEntry(command) {
    name := StrLower(command)
    if InStr(name, ".exe")
        name := SubStr(name, 1, StrLen(name) - 4)

    roots := [
        "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
        "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
        "HKEY_LOCAL_MACHINE\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
    ]

    for _, root in roots {
        loop reg, root, "K" {
            subkey_path := A_LoopRegKey "\\" A_LoopRegName
            try display_name := RegRead(subkey_path, "DisplayName")
            if !display_name
                continue
            if !InStr(StrLower(display_name), name)
                continue

            try install_loc := RegRead(subkey_path, "InstallLocation")
            if install_loc {
                exe_path := FindExeInDirectory(install_loc, name ".exe")
                if exe_path
                    return exe_path
            }

            try display_icon := RegRead(subkey_path, "DisplayIcon")
            if display_icon {
                icon_path := Trim(display_icon, " `t")
                if (SubStr(icon_path, 1, 1) = '"' && SubStr(icon_path, -1) = '"')
                    icon_path := SubStr(icon_path, 2, -1)
                if FileExist(icon_path)
                    return icon_path
            }
        }
    }
    return ""
}

FindExeInCommonLocations(exe_name) {
    for _, base in GetCommonRunPaths() {
        candidate := FindExeInDirectory(base, exe_name)
        if candidate
            return candidate
        candidate := FindExeInDirectory(base "\\Programs", exe_name)
        if candidate
            return candidate
    }
    return ""
}

FindExeInDirectory(base, exe_name) {
    if !DirExist(base)
        return ""
    loop files, base "\\*\\" exe_name, "R" {
        return A_LoopFilePath
    }
    return ""
}
