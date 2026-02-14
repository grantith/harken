; Helper: focus existing window, otherwise run app.
; Launch-or-focus helpers + per-app matching.
; If the target window is already active, toggle back to the previous window
; recorded for this hotkey.
FocusOrRun(winTitle, exePath, hotkey_id, app_config := "", *) {
    static last_window := Map()
    target_hwnd := 0
    hwnds := GetAppWindowList(winTitle, app_config)
    current_hwnd := 0
    try current_hwnd := WinGetID("A")
    catch
        current_hwnd := 0

    if (hwnds.Length) {
        target_hwnd := PickFocusableAppWindow(hwnds, winTitle)
        if (!target_hwnd)
            target_hwnd := hwnds[1]
    }

    if target_hwnd {
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
        RunResolved(exePath, app_config)
        ScheduleMoveAppWindowToDesktop(winTitle, app_config)
    }
}

GetAppWindowList(win_title, app_config := "") {
    if (app_config is Map && app_config.Has("match") && app_config["match"] is Map) {
        return GetWindowsByMatch(app_config["match"])
    }
    if !win_title
        return []
    return GetWindowsAcrossDesktops(win_title)
}

GetWindowsByMatch(match) {
    matches := []
    for _, hwnd in GetWindowsAcrossDesktops() {
        if MatchWindowFields(match, hwnd)
            matches.Push(hwnd)
    }
    return matches
}

PickFocusableAppWindow(hwnds, win_title) {
    for hwnd in hwnds {
        if !WinExist("ahk_id " hwnd)
            continue
        if (InStr(win_title, "explorer.exe")) {
            class_name := WinGetClass("ahk_id " hwnd)
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
                allow_invisible := true
            else if (desktop_num != VD.getCurrentDesktopNum())
                allow_invisible := true
        }
        if (!allow_invisible && !(style & 0x10000000))
            continue

        state := WinGetMinMax("ahk_id " hwnd)
        if (state = -1)
            continue
        return hwnd
    }

    for hwnd in hwnds {
        if !WinExist("ahk_id " hwnd)
            continue
        state := WinGetMinMax("ahk_id " hwnd)
        if (state = -1)
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
            VD.goToDesktopNum(target_desktop)
            VD.WaitDesktopSwitched(target_desktop)
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
