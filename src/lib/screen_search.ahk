global Config

; Screen search (UI hints) using UI Automation.
class ScreenSearch
{
    static active := false
    static gui := ""
    static hints := Map()
    static hint_labels := []
    static hint_elements := []
    static input_buffer := ""
    static input_hook := 0
    static build_timer := 0
    static hide_timer := 0
    static focus_timer := 0
    static hidden := false
    static target_hwnd := 0
    static explorer_active := false

    static Toggle(*) {
        if ScreenSearch.active {
            ScreenSearch.Hide()
            return
        }
        ScreenSearch.Show()
    }

    static IsActive(*) => ScreenSearch.active

    static Show(*) {
        global Config
        if !Config.Has("screen_search") || !Config["screen_search"]["enabled"]
            return
        if ReloadModeActive() || Window.IsMoveMode()
            return
        hwnd := 0
        try hwnd := WinGetID("A")
        if !hwnd
            return

        ScreenSearch.active := true
        ScreenSearch.target_hwnd := hwnd
        ScreenSearch.explorer_active := ScreenSearch.IsExplorerWindow(hwnd)
        ScreenSearch.input_buffer := ""
        ScreenSearch.hidden := false
        ScreenSearch.ResetDebugLog()
        ScreenSearch.DestroyGui()
        ScreenSearch.StartBuild()
        ScreenSearch.StartInputHook()
        ScreenSearch.StartFocusWatch()
    }

    static Hide(*) {
        ScreenSearch.active := false
        ScreenSearch.hidden := false
        ScreenSearch.target_hwnd := 0
        ScreenSearch.input_buffer := ""
        ScreenSearch.StopBuild()
        ScreenSearch.StopInputHook()
        ScreenSearch.StopFocusWatch()
        ScreenSearch.DestroyGui()
    }

    static StartBuild() {
        ScreenSearch.StopBuild()
        ScreenSearch.build_timer := ObjBindMethod(ScreenSearch, "BuildHints")
        SetTimer(ScreenSearch.build_timer, -10)
    }

    static StopBuild() {
        if ScreenSearch.build_timer
            SetTimer(ScreenSearch.build_timer, 0)
        ScreenSearch.build_timer := 0
    }

    static StartFocusWatch() {
        if ScreenSearch.focus_timer
            return
        ScreenSearch.focus_timer := ObjBindMethod(ScreenSearch, "CheckFocus")
        SetTimer(ScreenSearch.focus_timer, 120)
    }

    static StopFocusWatch() {
        if ScreenSearch.focus_timer
            SetTimer(ScreenSearch.focus_timer, 0)
        ScreenSearch.focus_timer := 0
    }

    static CheckFocus() {
        if !ScreenSearch.active
            return
        hwnd := 0
        try hwnd := WinGetID("A")
        if !hwnd || (ScreenSearch.target_hwnd && hwnd != ScreenSearch.target_hwnd)
            ScreenSearch.Hide()
    }

    static StartInputHook() {
        ScreenSearch.StopInputHook()
        ScreenSearch.input_hook := InputHook("L0")
        ScreenSearch.input_hook.KeyOpt("{All}", "NS")
        ScreenSearch.input_hook.OnKeyDown := ObjBindMethod(ScreenSearch, "OnKeyDown")
        ScreenSearch.input_hook.Start()
    }

    static StopInputHook() {
        if ScreenSearch.input_hook {
            try ScreenSearch.input_hook.Stop()
            ScreenSearch.input_hook := 0
        }
        ScreenSearch.StopHideTimer()
    }

    static StopHideTimer() {
        if ScreenSearch.hide_timer
            SetTimer(ScreenSearch.hide_timer, 0)
        ScreenSearch.hide_timer := 0
    }

    static OnKeyDown(hook, vk, sc) {
        if !ScreenSearch.active
            return
        key_name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        if ScreenSearch.IsSuperKeyName(key_name) {
            ScreenSearch.Hide()
            return
        }
        if (key_name = "Esc" || key_name = "Escape") {
            ScreenSearch.Hide()
            return
        }
        if (key_name = "Space") {
            ScreenSearch.HideHints()
            return
        }
        if (key_name = "Backspace") {
            if (StrLen(ScreenSearch.input_buffer) > 0)
                ScreenSearch.input_buffer := SubStr(ScreenSearch.input_buffer, 1, -1)
            ScreenSearch.UpdateHintVisibility()
            return
        }

        if (StrLen(key_name) != 1)
            return

        input_char := StrLower(key_name)
        if !ScreenSearch.IsHintChar(input_char)
            return
        ScreenSearch.input_buffer .= input_char
        ScreenSearch.MatchInput()
    }

    static IsSuperKeyName(key_name) {
        global Config
        if !key_name
            return false
        super_keys := Config["super_key"]
        if !(super_keys is Array)
            super_keys := [super_keys]
        key_lower := StrLower(key_name)
        for _, key in super_keys {
            if (StrLower(key) = key_lower)
                return true
        }
        return false
    }

    static IsHintChar(char) {
        global Config
        hint_chars := Config["screen_search"]["hint_chars"]
        if !hint_chars
            hint_chars := "asdfghjklqwertyuiopzxcvbnm"
        return InStr(hint_chars, char) > 0
    }

    static HideHints() {
        if !ScreenSearch.active || ScreenSearch.hidden
            return
        ScreenSearch.hidden := true
        if ScreenSearch.gui
            ScreenSearch.gui.Hide()
        ScreenSearch.hide_timer := ObjBindMethod(ScreenSearch, "CheckSpaceRelease")
        SetTimer(ScreenSearch.hide_timer, 30)
    }

    static CheckSpaceRelease() {
        if !ScreenSearch.active {
            ScreenSearch.StopHideTimer()
            return
        }
        if GetKeyState("Space", "P")
            return
        ScreenSearch.StopHideTimer()
        ScreenSearch.ShowHints()
    }

    static ShowHints() {
        if !ScreenSearch.active || !ScreenSearch.hidden
            return
        ScreenSearch.hidden := false
        if ScreenSearch.gui
            ScreenSearch.gui.Show("NoActivate")
    }

    static MatchInput() {
        if !ScreenSearch.active
            return
        input := ScreenSearch.input_buffer
        if (input = "")
        {
            ScreenSearch.UpdateHintVisibility()
            return
        }
        ScreenSearch.UpdateHintVisibility()
        if !ScreenSearch.hints.Has(input) {
            has_prefix := false
            for label in ScreenSearch.hints {
                if InStr(label, input) = 1 {
                    has_prefix := true
                    break
                }
            }
            if !has_prefix
                ScreenSearch.input_buffer := ""
            return
        }
        hint := ScreenSearch.hints[input]
        ScreenSearch.ActivateHint(hint)
    }

    static UpdateHintVisibility() {
        if !ScreenSearch.gui
            return
        input := ScreenSearch.input_buffer
        for label, hint in ScreenSearch.hints {
            ctrl := hint["control"]
            if !ctrl
                continue
            if (input = "") {
                try ctrl.Visible := true
                continue
            }
            try ctrl.Visible := (InStr(label, input) = 1)
        }
    }

    static ActivateHint(hint) {
        ScreenSearch.Hide()
        if !(hint is Map)
            return
        if !hint.Has("element")
            return
        element := hint["element"]
        if !element
            return
        control_type := hint.Has("control_type") ? hint["control_type"] : 0
        if ScreenSearch.TryInvokeElement(element)
            return
        if ScreenSearch.TrySelectionElement(element)
            return
        if ScreenSearch.TryToggleElement(element)
            return
        if ScreenSearch.TryExpandCollapseElement(element)
            return
        if ScreenSearch.explorer_active && ScreenSearch.IsListControlType(control_type) {
            if ScreenSearch.TryExplorerEnterElement(element)
                return
        }
        if ScreenSearch.explorer_active && ScreenSearch.IsListControlType(control_type) {
            if ScreenSearch.TryDoubleClickElement(element)
                return
        }
        ScreenSearch.TryClickElement(element)
    }

    static TryInvokeElement(element) {
        try {
            if element.GetCachedPropertyValue(UIA.Property.IsInvokePatternAvailable) {
                element.InvokePattern.Invoke()
                return true
            }
        }
        return false
    }

    static TrySelectionElement(element) {
        try {
            if element.GetCachedPropertyValue(UIA.Property.IsSelectionItemPatternAvailable) {
                element.SelectionItemPattern.Select()
                return true
            }
        }
        return false
    }

    static TryToggleElement(element) {
        try {
            if element.GetCachedPropertyValue(UIA.Property.IsTogglePatternAvailable) {
                element.TogglePattern.Toggle()
                return true
            }
        }
        return false
    }

    static TryExpandCollapseElement(element) {
        try {
            if element.GetCachedPropertyValue(UIA.Property.IsExpandCollapsePatternAvailable) {
                element.ExpandCollapsePattern.Expand()
                return true
            }
        }
        try {
            if element.GetCachedPropertyValue(UIA.Property.IsExpandCollapsePatternAvailable) {
                element.ExpandCollapsePattern.Collapse()
                return true
            }
        }
        return false
    }

    static TryClickElement(element) {
        try {
            element.Click()
            return true
        }
        return false
    }

    static TryDoubleClickElement(element) {
        try {
            element.Click("left", 2)
            return true
        }
        return false
    }

    static TryExplorerEnterElement(element) {
        try {
            element.SetFocus()
            Send "{Enter}"
            return true
        }
        return false
    }

    static BuildHints(*) {
        if !ScreenSearch.active
            return
        if !ScreenSearch.target_hwnd || !WinExist("ahk_id " ScreenSearch.target_hwnd) {
            ScreenSearch.Hide()
            return
        }
        elements := ScreenSearch.CollectElements(ScreenSearch.target_hwnd)
        if (elements.Length = 0) {
            ScreenSearch.Hide()
            return
        }
        ScreenSearch.RenderHints(elements)
    }

    static CollectElements(hwnd) {
        global Config
        results := []
        hint_config := Config["screen_search"]
        max_results := hint_config["max_results"]
        min_size := hint_config["min_size_px"]
        min_distance := hint_config["min_distance_px"]

        cache_request := UIA.CreateCacheRequest([
            "BoundingRectangle",
            "IsOffscreen",
            "IsEnabled",
            "IsKeyboardFocusable",
            "IsInvokePatternAvailable",
            "IsExpandCollapsePatternAvailable",
            "IsTogglePatternAvailable",
            "IsSelectionItemPatternAvailable",
            "ControlType",
            "Name"
        ])

        centers := []
        hwnds := ScreenSearch.GetThreadWindows(hwnd)
        for _, target_hwnd in hwnds {
            window_rect := ScreenSearch.GetWindowRect(target_hwnd)
            if !window_rect
                continue
            elements := []
            try {
                root := UIA.ElementFromHandle(target_hwnd)
                elements := root.FindAllBuildCache(cache_request, UIA.TrueCondition, 4)
            } catch {
                continue
            }

            for _, element in elements {
                rect := ""
                try rect := element.CachedBoundingRectangle
                catch
                    continue
                if !rect
                    continue
                width := rect.r - rect.l
                height := rect.b - rect.t
                if (width <= 0 || height <= 0)
                    continue
                if (width < min_size && height < min_size)
                    continue
                maxed_out := results.Length >= max_results

                is_offscreen := 0
                is_enabled := 0
                try is_offscreen := element.GetCachedPropertyValue(UIA.Property.IsOffscreen)
                catch
                    continue
                try is_enabled := element.GetCachedPropertyValue(UIA.Property.IsEnabled)
                catch
                    continue
                if is_offscreen
                    continue
                if !is_enabled
                    continue

                is_focusable := 0
                is_invoke := 0
                is_expand := 0
                is_toggle := 0
                is_select := 0
                control_type := 0
                try is_focusable := element.GetCachedPropertyValue(UIA.Property.IsKeyboardFocusable)
                try is_invoke := element.GetCachedPropertyValue(UIA.Property.IsInvokePatternAvailable)
                try is_expand := element.GetCachedPropertyValue(UIA.Property.IsExpandCollapsePatternAvailable)
                try is_toggle := element.GetCachedPropertyValue(UIA.Property.IsTogglePatternAvailable)
                try is_select := element.GetCachedPropertyValue(UIA.Property.IsSelectionItemPatternAvailable)
                try control_type := element.GetCachedPropertyValue(UIA.Property.ControlType)
                name := ""
                try name := element.GetCachedPropertyValue(UIA.Property.Name)
                if !(is_focusable || is_invoke || is_expand || is_toggle || is_select || control_type = UIA.Type.Button) {
                    continue
                }

                actionable := is_invoke || is_select || is_toggle || is_expand
                center_x := rect.l + (width / 2)
                center_y := rect.t + (height / 2)
                if actionable {
                    if (center_x < window_rect["left"] || center_x > window_rect["right"]
                        || center_y < window_rect["top"] || center_y > window_rect["bottom"])
                        continue
                } else if (rect.l < window_rect["left"] || rect.r > window_rect["right"]
                    || rect.t < window_rect["top"] || rect.b > window_rect["bottom"]) {
                    continue
                }

                adaptive_min_distance := Round(height * 0.6)
                if (adaptive_min_distance < 1)
                    adaptive_min_distance := 1
                if (adaptive_min_distance > min_distance)
                    adaptive_min_distance := min_distance

                area := width * height
                replace_index := 0
                best_replace_area := 0
                too_close := false
                for center_index, center in centers {
                    dx := center["x"] - center_x
                    dy := center["y"] - center_y
                    min_spacing := adaptive_min_distance
                    if (center["min_distance"] < min_spacing)
                        min_spacing := center["min_distance"]
                    if (dx * dx + dy * dy < min_spacing * min_spacing) {
                        too_close := true
                        if (actionable && !center["actionable"]) {
                            replace_index := center_index
                            break
                        }
                        if (actionable = center["actionable"]) {
                            if (area < center["area"] && center["area"] > best_replace_area) {
                                best_replace_area := center["area"]
                                replace_index := center_index
                            }
                        }
                    }
                }
                if too_close {
                    if (replace_index > 0) {
                        result_index := centers[replace_index]["result_index"]
                        centers[replace_index] := Map(
                            "x", center_x,
                            "y", center_y,
                            "area", area,
                            "actionable", actionable,
                            "min_distance", adaptive_min_distance,
                            "result_index", result_index
                        )
                        results[result_index] := Map(
                            "element", element,
                            "x", center_x,
                            "y", center_y,
                            "area", area,
                            "actionable", actionable,
                            "control_type", control_type,
                            "height", height,
                            "width", width,
                            "focusable", is_focusable,
                            "invoke", is_invoke,
                            "expand", is_expand,
                            "toggle", is_toggle,
                            "select", is_select,
                            "name", name
                        )
                    }
                    continue
                }

                if maxed_out
                    continue

                centers.Push(Map(
                    "x", center_x,
                    "y", center_y,
                    "area", area,
                    "actionable", actionable,
                    "min_distance", adaptive_min_distance,
                    "result_index", results.Length + 1
                ))
                results.Push(Map(
                    "element", element,
                    "x", center_x,
                    "y", center_y,
                    "area", area,
                    "actionable", actionable,
                    "control_type", control_type,
                    "height", height,
                    "width", width,
                    "focusable", is_focusable,
                    "invoke", is_invoke,
                    "expand", is_expand,
                    "toggle", is_toggle,
                    "select", is_select,
                    "name", name
                ))
            }
        }

        return results
    }

    static GetThreadWindows(hwnd) {
        hwnds := [hwnd]
        if !hwnd
            return hwnds
        thread_id := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid := 0, "uint")
        if !thread_id
            return hwnds

        callback := CallbackCreate(__EnumThreadWindows, "Fast", 2)
        DllCall("EnumThreadWindows", "uint", thread_id, "ptr", callback, "ptr", 0)
        CallbackFree(callback)
        return hwnds

        __EnumThreadWindows(window_hwnd, lparam) {
            if (window_hwnd = hwnd)
                return true
            if !DllCall("IsWindowVisible", "ptr", window_hwnd)
                return true
            if !IsWindowOnCurrentDesktop(window_hwnd)
                return true
            if ScreenSearch.IsWindowCloaked(window_hwnd)
                return true
            hwnds.Push(window_hwnd)
            return true
        }
    }

    static IsWindowCloaked(hwnd) {
        cloaked := 0
        if !DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 14, "int*", &cloaked, "int", 4)
            return false
        return cloaked != 0
    }

    static GetWindowRect(hwnd) {
        rect := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect)
            return ""
        left := NumGet(rect, 0, "int")
        top := NumGet(rect, 4, "int")
        right := NumGet(rect, 8, "int")
        bottom := NumGet(rect, 12, "int")
        return Map("left", left, "top", top, "right", right, "bottom", bottom)
    }

    static IsExplorerWindow(hwnd) {
        class_name := ""
        try class_name := WinGetClass("ahk_id " hwnd)
        return class_name = "CabinetWClass" || class_name = "ExploreWClass"
    }


    static RenderHints(elements) {
        ScreenSearch.DestroyGui()
        ScreenSearch.hints := Map()
        ScreenSearch.hint_labels := []
        if ScreenSearch.explorer_active
            elements := ScreenSearch.CollapseExplorerRows(elements)
        elements := ScreenSearch.SortHints(elements)
        ScreenSearch.hint_elements := elements
        if (elements.Length = 0)
            return

        hint_chars := ScreenSearch.GetHintChars()
        label_length := ScreenSearch.ComputeLabelLength(elements.Length, hint_chars.Length)

        ScreenSearch.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000", "harken Screen Search")
        ScreenSearch.gui.BackColor := "FF00FF"
        ScreenSearch.gui.SetFont("s10 w700", "Segoe UI")
        ScreenSearch.gui.MarginX := 0
        ScreenSearch.gui.MarginY := 0

        dpi_scale := A_ScreenDPI / 96
        padding := Round(4 * dpi_scale)
        if (padding < 3)
            padding := 3
        bg_color := "F3C623"
        text_color := "101010"

        virtual_left := SysGet(76)
        virtual_top := SysGet(77)
        virtual_width := SysGet(78)
        virtual_height := SysGet(79)

        placed_rects := []
        for index, hint in elements {
            label := ScreenSearch.IndexToLabel(index - 1, label_length, hint_chars)
            label_display := StrUpper(label)
            label_key := StrLower(label)
            x := Round(hint["x"])
            y := Round(hint["y"])
            text_w := (StrLen(label_display) * 8) + (padding * 2)
            text_h := Round(18 * dpi_scale)
            pos_x := x - (text_w // 2) - virtual_left
            pos_y := y - (text_h // 2) - virtual_top
            pos_x := ScreenSearch.Clamp(pos_x, 0, virtual_width - text_w)
            pos_y := ScreenSearch.Clamp(pos_y, 0, virtual_height - text_h)

            nudged := ScreenSearch.NudgeHintRect(pos_x, pos_y, text_w, text_h, placed_rects,
                virtual_width, virtual_height)
            pos_x := nudged["x"]
            pos_y := nudged["y"]
            placed_rects.Push(Map("x", pos_x, "y", pos_y, "w", text_w, "h", text_h))

            ctrl := ScreenSearch.gui.AddText(
                "x" pos_x " y" pos_y " w" text_w " h" text_h " Center Background" bg_color " c" text_color,
                label_display
            )
        ScreenSearch.hints[label_key] := Map(
            "element", hint["element"],
            "control", ctrl,
            "control_type", hint.Has("control_type") ? hint["control_type"] : 0
        )
            ScreenSearch.hint_labels.Push(label_key)
        }

        ScreenSearch.gui.Show("Hide x" virtual_left " y" virtual_top " w" virtual_width " h" virtual_height)
        ScreenSearch.ApplyHintOpacity()
        ScreenSearch.gui.Show("NoActivate x" virtual_left " y" virtual_top " w" virtual_width " h" virtual_height)
        ScreenSearch.ApplyHintOpacity()
    }

    static SortHints(elements) {
        try elements.Sort((a, b) => ScreenSearch.CompareHints(a, b))
        return elements
    }

    static CompareHints(a, b) {
        a_actionable := a.Has("actionable") ? a["actionable"] : false
        b_actionable := b.Has("actionable") ? b["actionable"] : false
        if (a_actionable != b_actionable)
            return a_actionable ? -1 : 1
        a_area := a.Has("area") ? a["area"] : 0
        b_area := b.Has("area") ? b["area"] : 0
        if (a_area != b_area)
            return a_area < b_area ? -1 : 1
        if (a["y"] != b["y"])
            return a["y"] < b["y"] ? -1 : 1
        if (a["x"] != b["x"])
            return a["x"] < b["x"] ? -1 : 1
        return 0
    }

    static CollapseExplorerRows(elements) {
        if (elements.Length <= 1)
            return elements
        rows := []
        filtered := []
        list_items := []
        for _, element in elements {
            control_type := element.Has("control_type") ? element["control_type"] : 0
            if ScreenSearch.IsExplorerRowControlType(control_type)
                list_items.Push(element)
        }

        if (list_items.Length > 0) {
            try list_items.Sort((a, b) => ScreenSearch.CompareRowPosition(a, b))
        }

        for _, element in elements {
            control_type := element.Has("control_type") ? element["control_type"] : 0
            is_list_item := ScreenSearch.IsExplorerRowControlType(control_type)
            height := element.Has("height") ? element["height"] : 0

            if !is_list_item {
                ; Avoid duplicate hint rows by skipping non-list elements that sit on list items.
                if ScreenSearch.IsInListRow(element, list_items)
                    continue
                filtered.Push(element)
                continue
            }

            matched_row := 0
            for row_index, row in rows {
                threshold := Max(row["height"], height) * 0.6
                if (threshold < 10)
                    threshold := 10
                if (Abs(row["y"] - element["y"]) <= threshold) {
                    matched_row := row_index
                    break
                }
            }

            if (matched_row = 0) {
                rows.Push(Map(
                    "y", element["y"],
                    "height", height,
                    "best", element
                ))
                continue
            }

            row := rows[matched_row]
            if ScreenSearch.IsBetterExplorerRowCandidate(element, row["best"]) {
                row["best"] := element
            }
        }

        for _, row in rows {
            filtered.Push(row["best"])
        }

        if ScreenSearch.ShouldDebugLog() {
            ScreenSearch.LogExplorerRows(rows)
        }

        return filtered
    }

    static IsInListRow(element, list_items) {
        if (list_items.Length = 0)
            return false
        for _, list_item in list_items {
            y_threshold := Max(list_item["height"], element.Has("height") ? element["height"] : 0) * 0.6
            if (y_threshold < 10)
                y_threshold := 10
            x_threshold := Max(list_item.Has("width") ? list_item["width"] : 0,
                element.Has("width") ? element["width"] : 0) * 0.6
            if (x_threshold < 40)
                x_threshold := 40
            if (Abs(list_item["y"] - element["y"]) <= y_threshold
                && Abs(list_item["x"] - element["x"]) <= x_threshold)
                return true
        }
        return false
    }

    static IsListControlType(control_type) {
        return control_type = UIA.Type.ListItem || control_type = UIA.Type.TreeItem || control_type = UIA.Type.DataItem
    }

    static IsExplorerRowControlType(control_type) {
        return control_type = UIA.Type.ListItem || control_type = UIA.Type.DataItem
    }

    static CompareRowPosition(a, b) {
        if (a["y"] != b["y"])
            return a["y"] < b["y"] ? -1 : 1
        if (a["x"] != b["x"])
            return a["x"] < b["x"] ? -1 : 1
        return 0
    }

    static IsBetterExplorerRowCandidate(candidate, current) {
        if !current
            return true
        candidate_rank := ScreenSearch.PatternRank(candidate)
        current_rank := ScreenSearch.PatternRank(current)
        if (candidate_rank != current_rank)
            return candidate_rank > current_rank
        candidate_area := candidate.Has("area") ? candidate["area"] : 0
        current_area := current.Has("area") ? current["area"] : 0
        if (candidate_area != current_area)
            return candidate_area < current_area
        return false
    }

    static PatternRank(element) {
        if element.Has("select") && element["select"]
            return 4
        if element.Has("invoke") && element["invoke"]
            return 3
        if (element.Has("toggle") && element["toggle"]) || (element.Has("expand") && element["expand"])
            return 2
        if element.Has("focusable") && element["focusable"]
            return 1
        return 0
    }

    static ShouldDebugLog() {
        global Config
        return Config.Has("screen_search") && Config["screen_search"]["debug_log"]
    }

    static ResetDebugLog() {
        if !ScreenSearch.ShouldDebugLog()
            return
        log_path := ScreenSearch.DebugLogPath()
        try FileDelete(log_path)
    }

    static DebugLogPath() {
        return A_AppData "\harken\screen_search.debug.log"
    }

    static LogExplorerRows(rows) {
        if !ScreenSearch.ShouldDebugLog()
            return
        log_path := ScreenSearch.DebugLogPath()
        output := "Explorer rows: " rows.Length
        for _, row in rows {
            best := row["best"]
            output .= "`n" ScreenSearch.DescribeElement(best)
        }
        FileAppend(output "`n", log_path)
    }

    static DescribeElement(element) {
        name := element.Has("name") ? element["name"] : ""
        control_type := element.Has("control_type") ? element["control_type"] : 0
        line := "row y=" element["y"] " x=" element["x"] " type=" control_type " name=" name
        line .= " select=" ScreenSearch.BoolStr(element, "select")
        line .= " invoke=" ScreenSearch.BoolStr(element, "invoke")
        line .= " toggle=" ScreenSearch.BoolStr(element, "toggle")
        line .= " expand=" ScreenSearch.BoolStr(element, "expand")
        line .= " focusable=" ScreenSearch.BoolStr(element, "focusable")
        return line
    }

    static BoolStr(element, key) {
        if element.Has(key) && element[key]
            return "1"
        return "0"
    }

    static ApplyHintOpacity() {
        global Config
        opacity := 255
        if Config.Has("screen_search") && Config["screen_search"].Has("hint_opacity")
            opacity := Config["screen_search"]["hint_opacity"]
        if !IsNumber(opacity)
            return
        if (opacity < 40)
            opacity := 40
        if (opacity > 255)
            opacity := 255
        color_key := 0x00FF00FF
        DllCall("SetLayeredWindowAttributes", "ptr", ScreenSearch.gui.Hwnd, "uint", color_key, "uchar", opacity, "uint", 0x3)
    }

    static DestroyGui() {
        if ScreenSearch.gui {
            try ScreenSearch.gui.Destroy()
        }
        ScreenSearch.gui := ""
    }

    static GetHintChars() {
        global Config
        hint_chars := Config["screen_search"]["hint_chars"]
        if !hint_chars
            hint_chars := "asdfghjklqwertyuiopzxcvbnm"
        chars := []
        loop parse, hint_chars
            chars.Push(A_LoopField)
        return chars
    }

    static Clamp(value, min_value, max_value) {
        if (value < min_value)
            return min_value
        if (value > max_value)
            return max_value
        return value
    }

    static NudgeHintRect(x, y, w, h, placed_rects, bounds_w, bounds_h) {
        if (placed_rects.Length = 0)
            return Map("x", x, "y", y)

        if !ScreenSearch.RectIntersectsAny(x, y, w, h, placed_rects)
            return Map("x", x, "y", y)

        step := 8
        max_rings := 6
        offsets := [
            [0, -1],
            [-1, 0],
            [-1, -1],
            [1, 0],
            [0, 1],
            [1, 1],
            [1, -1],
            [-1, 1]
        ]

        loop max_rings {
            radius := A_Index * step
            for _, dir in offsets {
                candidate_x := x + (dir[1] * radius)
                candidate_y := y + (dir[2] * radius)
                candidate_x := ScreenSearch.Clamp(candidate_x, 0, bounds_w - w)
                candidate_y := ScreenSearch.Clamp(candidate_y, 0, bounds_h - h)
                if !ScreenSearch.RectIntersectsAny(candidate_x, candidate_y, w, h, placed_rects)
                    return Map("x", candidate_x, "y", candidate_y)
            }
        }

        return Map("x", x, "y", y)
    }

    static RectIntersectsAny(x, y, w, h, placed_rects) {
        for _, rect in placed_rects {
            if ScreenSearch.RectsOverlap(x, y, w, h, rect["x"], rect["y"], rect["w"], rect["h"])
                return true
        }
        return false
    }

    static RectsOverlap(x1, y1, w1, h1, x2, y2, w2, h2) {
        if (x1 + w1 <= x2)
            return false
        if (x2 + w2 <= x1)
            return false
        if (y1 + h1 <= y2)
            return false
        if (y2 + h2 <= y1)
            return false
        return true
    }

    static ComputeLabelLength(count, base) {
        length := 1
        while (base ** length < count)
            length += 1
        return length
    }

    static IndexToLabel(index, length, chars) {
        base := chars.Length
        label := ""
        loop length {
            digit := Mod(index, base)
            label := chars[digit + 1] . label
            index := Floor(index / base)
        }
        return label
    }
}
