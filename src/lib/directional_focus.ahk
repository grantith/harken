; Directional focus calculations and stacked cycling.
global Config
global directional_focus_history := Map()
global directional_focus_debug_enabled := false
global directional_focus_debug_gui := ""
global directional_focus_debug_text := ""
global directional_focus_debug_buffer := []
global directional_focus_debug_limit := 5
global directional_focus_last_history_target := 0
global directional_focus_last_stacked_hwnd := 0
global directional_focus_last_reason := ""
global directional_focus_last_guard_max := ""
global directional_focus_last_min_primary := ""
global directional_focus_last_frontmost_hwnd := ""
global directional_focus_last_frontmost_z := ""
global directional_focus_last_frontmost_list := ""
global directional_focus_last_scored_count := 0
global directional_focus_last_filtered_count := 0
global directional_focus_last_activated_hwnd := ""
global directional_focus_last_activation_match := ""
global directional_focus_last_selected_z := ""
global directional_focus_last_selected_primary := ""
global directional_focus_last_selected_overlap := ""
global directional_focus_last_filtered_list := ""

DirectionalFocus(direction) {
    if !Config.Has("directional_focus") || !Config["directional_focus"]["enabled"]
        return

    active_hwnd := WinExist("A")
    if !active_hwnd || Window.IsException("ahk_id " active_hwnd)
        return

    WinGetPosEx(&ax, &ay, &aw, &ah, "ahk_id " active_hwnd)
    if (aw <= 0 || ah <= 0)
        return

    active := Map(
        "hwnd", active_hwnd,
        "x", ax,
        "y", ay,
        "w", aw,
        "h", ah,
        "cx", ax + aw / 2,
        "cy", ay + ah / 2,
        "area", aw * ah,
        "monitor", Screen.FromWindow("ahk_id " active_hwnd)
    )

    ResetDirectionalDebugTracking()
    ResetDirectionalDebugTracking()
    threshold := Config["directional_focus"]["stacked_overlap_threshold"]
    stack_tolerance := Config["directional_focus"]["stack_tolerance_px"]
    prefer_topmost := Config["directional_focus"]["prefer_topmost"]
    frontmost_guard := Config["directional_focus"]["frontmost_guard_px"]
    overlap_min := Config["directional_focus"]["perpendicular_overlap_min"]
    prefer_last_stacked := Config["directional_focus"]["prefer_last_stacked"]
    cross_monitor := Config["directional_focus"]["cross_monitor"]
    z_list := WinGetList()
    z_map := BuildZOrderMapFromList(z_list)

    if (IsActiveStacked(active, threshold, stack_tolerance, cross_monitor))
        directional_focus_last_stacked_hwnd := active["hwnd"]

    candidates := GetDirectionalCandidates(active, threshold, stack_tolerance, cross_monitor, z_map)
    if (candidates.Length = 0)
    {
        ResetDirectionalDebugTracking()
        directional_focus_last_reason := "none"
        UpdateDirectionalFocusDebug("direction", direction, active, [], [], 0, z_map)
        return
    }

    disable_stateful := true
    if !disable_stateful {
        history_target := GetHistoryTarget(active["hwnd"], direction, active, threshold, stack_tolerance, cross_monitor)
        directional_focus_last_history_target := history_target
        if (history_target != 0 && CandidateListHas(candidates, history_target)) {
            ResetDirectionalDebugTracking()
            directional_focus_last_reason := "history"
            directional_focus_last_activated_hwnd := ActivateWindow(history_target)
            directional_focus_last_activation_match := (directional_focus_last_activated_hwnd = history_target)
            UpdateDirectionalFocusDebug("direction", direction, active, candidates, [], history_target, z_map)
            if (IsStackedTarget(history_target, candidates, threshold, stack_tolerance))
                directional_focus_last_stacked_hwnd := history_target
            return
        }

        if prefer_last_stacked {
            last_stacked := GetLastStackedCandidate(active, candidates, direction, threshold, stack_tolerance)
            if (last_stacked != 0) {
                ResetDirectionalDebugTracking()
                directional_focus_last_reason := "last_stacked"
                directional_focus_last_activated_hwnd := ActivateWindow(last_stacked)
                directional_focus_last_activation_match := (directional_focus_last_activated_hwnd = last_stacked)
                UpdateDirectionalFocusDebug("direction", direction, active, candidates, [], last_stacked, z_map)
                RecordDirectionalHistory(active["hwnd"], last_stacked, direction)
                return
            }
        }
    }

    ResetDirectionalDebugTracking()
    best := FindDirectionalBest(active, candidates, direction, prefer_topmost, frontmost_guard, overlap_min, z_map)
    if (best is Map) {
        directional_focus_last_activated_hwnd := ActivateWindow(best["hwnd"])
        directional_focus_last_activation_match := (directional_focus_last_activated_hwnd = best["hwnd"])
        UpdateDirectionalFocusDebug("direction", direction, active, candidates, [], best["hwnd"], z_map)
        RecordDirectionalHistory(active["hwnd"], best["hwnd"], direction)
        if (IsStackedTarget(best["hwnd"], candidates, threshold, stack_tolerance))
            directional_focus_last_stacked_hwnd := best["hwnd"]
    } else {
        UpdateDirectionalFocusDebug("direction", direction, active, candidates, [], 0, z_map)
    }
}

DirectionalFocusStacked(direction) {
    if !Config.Has("directional_focus") || !Config["directional_focus"]["enabled"]
        return

    active_hwnd := WinExist("A")
    if !active_hwnd || Window.IsException("ahk_id " active_hwnd)
        return

    WinGetPosEx(&ax, &ay, &aw, &ah, "ahk_id " active_hwnd)
    if (aw <= 0 || ah <= 0)
        return

    active := Map(
        "hwnd", active_hwnd,
        "x", ax,
        "y", ay,
        "w", aw,
        "h", ah,
        "cx", ax + aw / 2,
        "cy", ay + ah / 2,
        "area", aw * ah,
        "monitor", Screen.FromWindow("ahk_id " active_hwnd)
    )

    threshold := Config["directional_focus"]["stacked_overlap_threshold"]
    stack_tolerance := Config["directional_focus"]["stack_tolerance_px"]
    cross_monitor := Config["directional_focus"]["cross_monitor"]
    z_map := BuildZOrderMap()
    stacked := GetStackedWindows(active, threshold, stack_tolerance, cross_monitor, z_map)
    if (stacked.Length < 2)
    {
        ResetDirectionalDebugTracking()
        directional_focus_last_reason := "stacked_none"
        UpdateDirectionalFocusDebug("stacked", direction, active, [], stacked, 0, z_map)
        return
    }

    ordered := OrderByStableStack(stacked)
    if (ordered.Length < 2)
    {
        ResetDirectionalDebugTracking()
        directional_focus_last_reason := "stacked_none"
        UpdateDirectionalFocusDebug("stacked", direction, active, [], ordered, 0, z_map)
        return
    }

    current_index := 0
    for i, win in ordered {
        if (win["hwnd"] = active_hwnd) {
            current_index := i
            break
        }
    }
    if (current_index = 0)
    {
        ResetDirectionalDebugTracking()
        directional_focus_last_reason := "stacked_none"
        UpdateDirectionalFocusDebug("stacked", direction, active, [], ordered, 0, z_map)
        return
    }

    if (direction = "prev")
        next_index := (current_index <= 1) ? ordered.Length : current_index - 1
    else
        next_index := (current_index >= ordered.Length) ? 1 : current_index + 1

    ResetDirectionalDebugTracking()
    directional_focus_last_reason := "stacked_cycle"
    directional_focus_last_activated_hwnd := ActivateWindow(ordered[next_index]["hwnd"])
    directional_focus_last_activation_match := (directional_focus_last_activated_hwnd = ordered[next_index]["hwnd"])
    UpdateDirectionalFocusDebug("stacked", direction, active, [], ordered, ordered[next_index]["hwnd"], z_map)
    directional_focus_last_stacked_hwnd := ordered[next_index]["hwnd"]
}

ToggleDirectionalFocusDebug() {
    global directional_focus_debug_enabled
    directional_focus_debug_enabled := !directional_focus_debug_enabled
    UpdateDirectionalFocusDebug("toggle", "", "", [], [], 0, Map())
}

SetLastStackedFromActive() {
    global directional_focus_last_stacked_hwnd
    hwnd := WinExist("A")
    if hwnd
        directional_focus_last_stacked_hwnd := hwnd
}

UpdateDirectionalFocusDebug(mode, direction, active, candidates, stacked, selected_hwnd, z_map) {
    global Config, directional_focus_debug_enabled, directional_focus_debug_gui, directional_focus_debug_text
    global directional_focus_debug_buffer, directional_focus_debug_limit
    if !Config.Has("directional_focus")
        return
    if !Config["directional_focus"]["debug_enabled"] && !directional_focus_debug_enabled
        return

    if !directional_focus_debug_gui {
        directional_focus_debug_gui := Gui("+AlwaysOnTop +ToolWindow", "harken Directional Focus Debug")
        directional_focus_debug_gui.SetFont("s9", "Consolas")
        directional_focus_debug_text := directional_focus_debug_gui.AddEdit("w720 r22 ReadOnly", "")
        directional_focus_debug_gui.OnEvent("Close", (*) => directional_focus_debug_gui.Hide())
    }

    if (!directional_focus_debug_enabled && Config["directional_focus"]["debug_enabled"]) {
        directional_focus_debug_enabled := true
    }

    entry := BuildDirectionalDebugText(mode, direction, active, candidates, stacked, selected_hwnd, z_map)
    directional_focus_debug_buffer.Push(entry)
    while (directional_focus_debug_buffer.Length > directional_focus_debug_limit)
        directional_focus_debug_buffer.RemoveAt(1)

    directional_focus_debug_text.Text := DirectionalStrJoin(directional_focus_debug_buffer, "`n`n" DirectionalRepeatChar("-", 48) "`n`n")
    directional_focus_debug_gui.Show("NoActivate")
}

BuildDirectionalDebugText(mode, direction, active, candidates, stacked, selected_hwnd, z_map) {
    global directional_focus_last_history_target, directional_focus_last_stacked_hwnd
    lines := []
    lines.Push("Directional Focus Debug")
    lines.Push("mode=" mode " direction=" direction)
    lines.Push("")
    if (active is Map) {
        lines.Push("Active: " FormatWindowLine(active, z_map))
    } else {
        lines.Push("Active: (none)")
    }
    lines.Push("Selected hwnd: " (selected_hwnd ? Format("0x{:X}", selected_hwnd) : ""))
    lines.Push("Activated hwnd: " (directional_focus_last_activated_hwnd ? Format("0x{:X}", directional_focus_last_activated_hwnd) : ""))
    lines.Push("Activation match: " directional_focus_last_activation_match)
    lines.Push("Reason: " directional_focus_last_reason)
    if (mode = "direction") {
        lines.Push("Selected z: " directional_focus_last_selected_z)
        lines.Push("Selected primary: " directional_focus_last_selected_primary)
        lines.Push("Selected overlap: " directional_focus_last_selected_overlap)
        lines.Push("Min primary: " directional_focus_last_min_primary)
        lines.Push("Guard max: " directional_focus_last_guard_max)
        lines.Push("Scored count: " directional_focus_last_scored_count)
        lines.Push("Filtered count: " directional_focus_last_filtered_count)
        lines.Push("Frontmost pick: " (directional_focus_last_frontmost_hwnd ? Format("0x{:X}", directional_focus_last_frontmost_hwnd) : ""))
        lines.Push("Frontmost z: " directional_focus_last_frontmost_z)
        lines.Push("Frontmost list: " directional_focus_last_frontmost_list)
        lines.Push("Filtered list: " directional_focus_last_filtered_list)
    }
    lines.Push("")

    if (candidates.Length) {
        lines.Push("Candidates:")
        for _, win in candidates {
            dir_ok := IsInDirection(active, win, direction)
            overlap := (direction = "left" || direction = "right") ? OverlapRatioVertical(active, win) : OverlapRatioHorizontal(active, win)
            primary := (direction = "left" || direction = "right") ? Abs(active["cx"] - win["cx"]) : Abs(active["cy"] - win["cy"])
            overlap_min := Config["directional_focus"]["perpendicular_overlap_min"]
            base_score := dir_ok ? DirectionScore(active, win, direction) : "n/a"
            score := dir_ok ? base_score : "n/a"
            lines.Push("- " FormatWindowLine(win, z_map)
                " dir=" (dir_ok ? "y" : "n")
                " primary=" Round(primary, 1)
                " overlap=" Round(overlap, 3)
                " min_overlap=" overlap_min
                " score=" score)
        }
    } else {
        lines.Push("Candidates: (none)")
    }
    lines.Push("")

    if (stacked.Length) {
        lines.Push("Stacked:")
        for _, win in stacked {
            lines.Push("- " FormatWindowLine(win, z_map))
        }
    } else {
        lines.Push("Stacked: (none)")
    }

    return DirectionalStrJoin(lines, "`n")
}

FormatWindowLine(win, z_map) {
    hwnd := win["hwnd"]
    title := ""
    exe := ""
    try title := WinGetTitle("ahk_id " hwnd)
    try exe := WinGetProcessName("ahk_id " hwnd)
    z := win.Has("z") ? win["z"] : (z_map.Has(hwnd) ? z_map[hwnd] : 0)
    return Format("0x{:X} z:{} {} [{}] x{} y{} w{} h{}",
        hwnd,
        z,
        exe,
        title,
        Round(win["x"]),
        Round(win["y"]),
        Round(win["w"]),
        Round(win["h"]))
}

DirectionalStrJoin(items, sep) {
    output := ""
    for i, item in items {
        if (i > 1)
            output .= sep
        output .= item
    }
    return output
}

DirectionalRepeatChar(char, count) {
    output := ""
    loop count
        output .= char
    return output
}

GetHistoryTarget(active_hwnd, direction, active, threshold, stack_tolerance, cross_monitor) {
    global directional_focus_history
    if !directional_focus_history.Has(active_hwnd)
        return 0
    dir_map := directional_focus_history[active_hwnd]
    if !(dir_map is Map) || !dir_map.Has(direction)
        return 0
    target_hwnd := dir_map[direction]
    if !target_hwnd
        return 0
    if !WinExist("ahk_id " target_hwnd)
        return 0
    if !IsDirectionalCandidate(target_hwnd, active, cross_monitor)
        return 0
    target_info := BuildWindowInfo(target_hwnd)
    if !(target_info is Map)
        return 0
    if !IsInDirection(active, target_info, direction)
        return 0
    if (IsStacked(active, target_info, threshold, stack_tolerance))
        return 0
    return target_hwnd
}

RecordDirectionalHistory(from_hwnd, to_hwnd, direction) {
    global directional_focus_history
    if !from_hwnd || !to_hwnd
        return
    opposite := OppositeDirection(direction)
    if (opposite = "")
        return
    if !directional_focus_history.Has(to_hwnd)
        directional_focus_history[to_hwnd] := Map()
    directional_focus_history[to_hwnd][opposite] := from_hwnd
}

OppositeDirection(direction) {
    if (direction = "left")
        return "right"
    if (direction = "right")
        return "left"
    if (direction = "up")
        return "down"
    if (direction = "down")
        return "up"
    return ""
}

GetDirectionalCandidates(active, threshold, stack_tolerance, cross_monitor, z_map) {
    list := []
    for _, hwnd in WinGetList() {
        if (hwnd = active["hwnd"])
            continue
        if !IsDirectionalCandidate(hwnd, active, cross_monitor)
            continue

        win := BuildWindowInfo(hwnd, z_map)
        if !(win is Map)
            continue

        if (IsStacked(active, win, threshold, stack_tolerance))
            continue

        list.Push(win)
    }
    return list
}

GetStackedWindows(active, threshold, stack_tolerance, cross_monitor, z_map := "") {
    list := []
    for _, hwnd in WinGetList() {
        if !IsDirectionalCandidate(hwnd, active, cross_monitor)
            continue

        win := BuildWindowInfo(hwnd, z_map)
        if !(win is Map)
            continue

        if (IsStacked(active, win, threshold, stack_tolerance))
            list.Push(win)
    }
    return list
}

IsDirectionalCandidate(hwnd, active, cross_monitor) {
    if !hwnd
        return false
    if Window.IsException("ahk_id " hwnd)
        return false
    if (WinGetMinMax("ahk_id " hwnd) = -1)
        return false
    if !IsWindowVisible(hwnd)
        return false
    if !cross_monitor {
        if (Screen.FromWindow("ahk_id " hwnd) != active["monitor"])
            return false
    }
    return true
}

IsWindowVisible(hwnd) {
    ex_style := WinGetExStyle("ahk_id " hwnd)
    if (ex_style & 0x80) || (ex_style & 0x8000000)
        return false
    if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
        return false
    return true
}

BuildWindowInfo(hwnd, z_map := "") {
    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)
    if (w <= 0 || h <= 0)
        return ""
    info := Map(
        "hwnd", hwnd,
        "x", x,
        "y", y,
        "w", w,
        "h", h,
        "cx", x + w / 2,
        "cy", y + h / 2,
        "area", w * h,
        "z", 999999
    )
    if (z_map is Map && z_map.Has(hwnd))
        info["z"] := z_map[hwnd]
    return info
}

FindDirectionalBest(active, candidates, direction, prefer_topmost := false, frontmost_guard := 0, overlap_min := 0, z_map := "") {
    global directional_focus_last_reason, directional_focus_last_guard_max, directional_focus_last_min_primary
    global directional_focus_last_frontmost_hwnd, directional_focus_last_frontmost_z, directional_focus_last_frontmost_list
    global directional_focus_last_scored_count, directional_focus_last_filtered_count
    global directional_focus_last_selected_z, directional_focus_last_selected_primary, directional_focus_last_selected_overlap
    global directional_focus_last_filtered_list
    scored := []
    min_primary := ""

    center_band := GetCenterBandBounds()
    active_in_side_band := IsActiveInSideBand(active, center_band)

    for _, win in candidates {
        if !IsInDirection(active, win, direction)
            continue

        if ((direction = "up" || direction = "down") && active_in_side_band) {
            if IsCandidateInCenterBand(win, center_band)
                continue
        }

        overlap := (direction = "left" || direction = "right")
            ? OverlapRatioVertical(active, win)
            : OverlapRatioHorizontal(active, win)
        if (overlap < overlap_min)
            continue

        primary := GetPrimaryDistance(active, win, direction)
        base_score := DirectionScore(active, win, direction)

        if (min_primary = "" || primary < min_primary)
            min_primary := primary

        z_value := win["z"]
        if (z_map is Map && z_map.Has(win["hwnd"]))
            z_value := z_map[win["hwnd"]]
        scored.Push(Map(
            "win", win,
            "primary", primary,
            "score", base_score,
            "z", z_value,
            "overlap", overlap
        ))
    }

    directional_focus_last_scored_count := scored.Length
    if (scored.Length = 0) {
        directional_focus_last_reason := "none"
        directional_focus_last_guard_max := ""
        directional_focus_last_min_primary := ""
        directional_focus_last_frontmost_list := ""
        directional_focus_last_filtered_count := 0
        directional_focus_last_selected_z := ""
        directional_focus_last_selected_primary := ""
        directional_focus_last_selected_overlap := ""
        directional_focus_last_filtered_list := ""
        return ""
    }

    guard_max := ""
    if (frontmost_guard > 0 && min_primary != "")
        guard_max := min_primary + frontmost_guard

    filtered := []
    if (guard_max != "") {
        for _, entry in scored {
            if (entry["primary"] <= guard_max)
                filtered.Push(entry)
        }
    } else {
        filtered := scored
    }
    directional_focus_last_filtered_count := filtered.Length
    filtered_list := []
    for _, entry in filtered {
        filtered_list.Push(entry["win"]["hwnd"] ":" entry["z"] ":" Round(entry["primary"], 1) ":" Round(entry["overlap"], 3))
    }
    directional_focus_last_filtered_list := DirectionalStrJoin(filtered_list, ", ")

    if (filtered.Length > 0) {
        best_front := ""
        frontmost_list := []
        for _, entry in filtered {
            frontmost_list.Push(entry["win"]["hwnd"] ":" entry["z"])
            if (best_front = "" || entry["z"] < best_front["z"]) {
                best_front := entry
            }
        }
        if (best_front != "") {
            directional_focus_last_reason := "frontmost_guard"
            directional_focus_last_guard_max := guard_max
            directional_focus_last_min_primary := min_primary
            directional_focus_last_frontmost_hwnd := best_front["win"]["hwnd"]
            directional_focus_last_frontmost_z := best_front["z"]
            directional_focus_last_frontmost_list := DirectionalStrJoin(frontmost_list, ", ")
            directional_focus_last_selected_z := best_front["z"]
            directional_focus_last_selected_primary := best_front["primary"]
            directional_focus_last_selected_overlap := best_front["overlap"]
            return best_front["win"]
        }
    }

    best_entry := ""
    best_score := ""
    for _, entry in scored {
        if (best_entry = "" || entry["score"] < best_score) {
            best_entry := entry
            best_score := entry["score"]
        } else if (prefer_topmost && entry["score"] = best_score) {
            if (entry["z"] < best_entry["z"])
                best_entry := entry
        }
    }

    directional_focus_last_reason := "score"
    directional_focus_last_guard_max := guard_max
    directional_focus_last_min_primary := min_primary
    directional_focus_last_frontmost_hwnd := ""
    directional_focus_last_frontmost_z := ""
    directional_focus_last_frontmost_list := ""
    directional_focus_last_filtered_list := ""
    directional_focus_last_selected_z := best_entry["z"]
    directional_focus_last_selected_primary := best_entry["primary"]
    directional_focus_last_selected_overlap := best_entry["overlap"]
    directional_focus_last_filtered_count := filtered.Length
    return (best_entry != "") ? best_entry["win"] : ""
}

GetCenterBandBounds() {
    left := Screen.left
    right := Screen.right
    width := right - left
    band_left := left + (width / 3)
    band_right := left + (width * 2 / 3)
    return Map(
        "left", band_left,
        "right", band_right
    )
}

IsActiveInSideBand(active, center_band) {
    if !(active is Map)
        return false
    return (active["cx"] < center_band["left"] || active["cx"] > center_band["right"])
}

IsCandidateInCenterBand(win, center_band) {
    if !(win is Map)
        return false
    return (win["cx"] >= center_band["left"] && win["cx"] <= center_band["right"])
}

ActivateWindow(hwnd) {
    if !hwnd
        return 0
    if VirtualDesktopSwitchOnFocus()
        return ActivateWindowAcrossDesktops(hwnd)

    WinActivate("ahk_id " hwnd)
    try WinWaitActive("ahk_id " hwnd,, 0.2)
    active_hwnd := WinGetID("A")
    if (active_hwnd = hwnd)
        return active_hwnd

    WinActivate("ahk_id " hwnd)
    try WinWaitActive("ahk_id " hwnd,, 0.4)
    return WinGetID("A")
}

ResetDirectionalDebugTracking() {
    global directional_focus_last_reason, directional_focus_last_guard_max, directional_focus_last_min_primary
    global directional_focus_last_frontmost_hwnd, directional_focus_last_frontmost_z, directional_focus_last_frontmost_list
    global directional_focus_last_scored_count, directional_focus_last_filtered_count
    global directional_focus_last_activated_hwnd, directional_focus_last_activation_match
    global directional_focus_last_selected_z, directional_focus_last_selected_primary, directional_focus_last_selected_overlap
    global directional_focus_last_filtered_list
    directional_focus_last_reason := ""
    directional_focus_last_guard_max := ""
    directional_focus_last_min_primary := ""
    directional_focus_last_frontmost_hwnd := ""
    directional_focus_last_frontmost_z := ""
    directional_focus_last_frontmost_list := ""
    directional_focus_last_scored_count := 0
    directional_focus_last_filtered_count := 0
    directional_focus_last_activated_hwnd := ""
    directional_focus_last_activation_match := ""
    directional_focus_last_selected_z := ""
    directional_focus_last_selected_primary := ""
    directional_focus_last_selected_overlap := ""
    directional_focus_last_filtered_list := ""
}

IsInDirection(active, win, direction) {
    if (direction = "left")
        return win["cx"] < active["cx"] - 1
    if (direction = "right")
        return win["cx"] > active["cx"] + 1
    if (direction = "up")
        return win["cy"] < active["cy"] - 1
    if (direction = "down")
        return win["cy"] > active["cy"] + 1
    return false
}

DirectionScore(active, win, direction) {
    primary := 0
    overlap_ratio := 0

    if (direction = "left" || direction = "right") {
        primary := Abs(active["cx"] - win["cx"])
        overlap_ratio := OverlapRatioVertical(active, win)
    } else {
        primary := Abs(active["cy"] - win["cy"])
        overlap_ratio := OverlapRatioHorizontal(active, win)
    }

    return primary + (1 - overlap_ratio) * 5000
}

GetPrimaryDistance(active, win, direction) {
    if (direction = "left" || direction = "right")
        return Abs(active["cx"] - win["cx"])
    return Abs(active["cy"] - win["cy"])
}

OverlapRatioVertical(a, b) {
    overlap := OverlapLength(a["y"], a["y"] + a["h"], b["y"], b["y"] + b["h"])
    return overlap / Max(1, Min(a["h"], b["h"]))
}

OverlapRatioHorizontal(a, b) {
    overlap := OverlapLength(a["x"], a["x"] + a["w"], b["x"], b["x"] + b["w"])
    return overlap / Max(1, Min(a["w"], b["w"]))
}

OverlapLength(a1, a2, b1, b2) {
    return Max(0, Min(a2, b2) - Max(a1, b1))
}

IsStacked(a, b, threshold, tolerance_px := 0) {
    if (tolerance_px > 0) {
        if (Abs(a["cx"] - b["cx"]) <= tolerance_px && Abs(a["cy"] - b["cy"]) <= tolerance_px)
            return true
        if (Abs(a["x"] - b["x"]) <= tolerance_px
            && Abs(a["y"] - b["y"]) <= tolerance_px
            && Abs(a["w"] - b["w"]) <= tolerance_px
            && Abs(a["h"] - b["h"]) <= tolerance_px)
            return true
    }
    overlap_w := OverlapLength(a["x"], a["x"] + a["w"], b["x"], b["x"] + b["w"])
    overlap_h := OverlapLength(a["y"], a["y"] + a["h"], b["y"], b["y"] + b["h"])
    overlap_area := overlap_w * overlap_h
    if (overlap_area <= 0)
        return false

    min_area := Min(a["area"], b["area"])
    ratio := overlap_area / Max(1, min_area)
    return ratio >= threshold
}

BuildZOrderMap() {
    z_list := WinGetList()
    return BuildZOrderMapFromList(z_list)
}

BuildZOrderMapFromList(z_list) {
    z_map := Map()
    for i, hwnd in z_list {
        z_map[hwnd] := i
    }
    return z_map
}

OrderByZ(z_list, windows) {
    ordered := []
    window_map := Map()
    for _, win in windows {
        window_map[win["hwnd"]] := win
    }
    for _, hwnd in z_list {
        if window_map.Has(hwnd)
            ordered.Push(window_map[hwnd])
    }
    return ordered
}

OrderByZMap(z_map, windows) {
    ordered := []
    if !(z_map is Map)
        return ordered

    for _, win in windows {
        if !win.Has("z")
            win["z"] := z_map.Has(win["hwnd"]) ? z_map[win["hwnd"]] : 999999
        ordered.Push(win)
    }

    count := ordered.Length
    if (count < 2)
        return ordered

    loop count - 1 {
        i := A_Index
        loop count - i {
            j := A_Index
            if (ordered[j]["z"] > ordered[j + 1]["z"]) {
                temp := ordered[j]
                ordered[j] := ordered[j + 1]
                ordered[j + 1] := temp
            }
        }
    }
    return ordered
}

OrderByStableStack(windows) {
    ordered := []
    for _, win in windows
        ordered.Push(win)

    count := ordered.Length
    if (count < 2)
        return ordered

    loop count - 1 {
        i := A_Index
        loop count - i {
            j := A_Index
            if (ordered[j]["hwnd"] > ordered[j + 1]["hwnd"]) {
                temp := ordered[j]
                ordered[j] := ordered[j + 1]
                ordered[j + 1] := temp
            }
        }
    }
    return ordered
}

CandidateListHas(candidates, hwnd) {
    for _, win in candidates {
        if (win["hwnd"] = hwnd)
            return true
    }
    return false
}

GetLastStackedCandidate(active, candidates, direction, threshold, stack_tolerance) {
    global directional_focus_last_stacked_hwnd
    if !directional_focus_last_stacked_hwnd
        return 0

    last_candidate := ""
    for _, win in candidates {
        if (win["hwnd"] = directional_focus_last_stacked_hwnd) {
            last_candidate := win
            break
        }
    }
    if !(last_candidate is Map)
        return 0

    for _, win in candidates {
        if (win["hwnd"] = last_candidate["hwnd"])
            continue
        if (IsStacked(last_candidate, win, threshold, stack_tolerance))
            return AllowLastStackedForDirection(active, last_candidate, direction, threshold) ? last_candidate["hwnd"] : 0
    }
    return 0
}

AllowLastStackedForDirection(active, last_candidate, direction, threshold) {
    if !(active is Map) || !(last_candidate is Map)
        return false
    if (direction = "left" || direction = "right")
        return OverlapRatioVertical(active, last_candidate) >= threshold
    if (direction = "up" || direction = "down")
        return OverlapRatioHorizontal(active, last_candidate) >= threshold
    return false
}

IsActiveStacked(active, threshold, stack_tolerance, cross_monitor) {
    stacked := GetStackedWindows(active, threshold, stack_tolerance, cross_monitor)
    return stacked.Length >= 2
}

IsStackedTarget(target_hwnd, candidates, threshold, stack_tolerance) {
    for _, win in candidates {
        if (win["hwnd"] = target_hwnd)
            continue
        if (IsStackedByHwnd(target_hwnd, win, threshold, stack_tolerance))
            return true
    }
    return false
}

IsStackedByHwnd(target_hwnd, win, threshold, stack_tolerance) {
    target_info := BuildWindowInfo(target_hwnd)
    if !(target_info is Map)
        return false
    return IsStacked(target_info, win, threshold, stack_tolerance)
}
