#Requires AutoHotkey v2.0

; Window inspector UI for titles/classes/PIDs.
ShowWindowInspector() {
    static inspector_gui := ""
    static window_list := ""
    static refresh_timer := 0

    if inspector_gui {
        inspector_gui.Show()
        RefreshList(window_list)
        StartAutoRefresh(window_list, &refresh_timer)
        return
    }

    inspector_gui := Gui("+Resize", "harken Window Inspector")
    inspector_gui.SetFont("s10", "Segoe UI")

    ; Include active column and auto-refresh to reflect focus changes.
    window_list := inspector_gui.AddListView("w1020 r26 Grid", ["Active", "Title", "Exe", "Class", "PID", "HWND"])
    window_list.ModifyCol(1, 60)
    window_list.ModifyCol(2, 380)
    window_list.ModifyCol(3, 140)
    window_list.ModifyCol(4, 200)
    window_list.ModifyCol(5, 80)
    window_list.ModifyCol(6, 120)

    refresh_btn := inspector_gui.AddButton("xm y+10 w110", "Refresh")
    refresh_btn.OnEvent("Click", (*) => RefreshList(window_list))

    copy_selected_btn := inspector_gui.AddButton("x+10 yp w140", "Copy Selected")
    copy_selected_btn.OnEvent("Click", (*) => CopySelected(window_list))

    copy_all_btn := inspector_gui.AddButton("x+10 yp w120", "Copy All")
    copy_all_btn.OnEvent("Click", (*) => CopyAll(window_list))

    export_btn := inspector_gui.AddButton("x+10 yp w140", "Export File")
    export_btn.OnEvent("Click", (*) => ExportAll(window_list))

    inspector_gui.OnEvent("Close", (*) => HideInspector(inspector_gui, &refresh_timer))
    inspector_gui.Show()

    RefreshList(window_list)
    StartAutoRefresh(window_list, &refresh_timer)
}

RefreshList(window_list) {
    window_list.Delete()
    active_hwnd := 0
    try active_hwnd := WinGetID("A")

    for _, hwnd in WinGetList() {
        title := WinGetTitle("ahk_id " hwnd)
        exe := WinGetProcessName("ahk_id " hwnd)
        class_name := WinGetClass("ahk_id " hwnd)
        pid := WinGetPID("ahk_id " hwnd)
        active_label := (hwnd = active_hwnd) ? "active" : ""
        window_list.Add("", active_label, title, exe, class_name, pid, Format("0x{:X}", hwnd))
    }
}

StartAutoRefresh(window_list, &refresh_timer) {
    if refresh_timer
        SetTimer(refresh_timer, 0)
    refresh_timer := (*) => RefreshList(window_list)
    SetTimer(refresh_timer, 2000)
}

HideInspector(inspector_gui, &refresh_timer) {
    if refresh_timer
        SetTimer(refresh_timer, 0)
    inspector_gui.Hide()
}

CopySelected(window_list) {
    rows := []
    row := 0
    while row := window_list.GetNext(row) {
        rows.Push(GetRowValues(window_list, row))
    }
    if rows.Length = 0
        return
    A_Clipboard := BuildOutput(rows)
}

CopyAll(window_list) {
    rows := []
    loop window_list.GetCount() {
        rows.Push(GetRowValues(window_list, A_Index))
    }
    if rows.Length = 0
        return
    A_Clipboard := BuildOutput(rows)
}

ExportAll(window_list) {
    rows := []
    loop window_list.GetCount() {
        rows.Push(GetRowValues(window_list, A_Index))
    }
    if rows.Length = 0
        return

    default_path := A_Desktop "\\window-list.txt"
    save_path := FileSelect("S", default_path, "Export Window List", "Text (*.txt)")
    if !save_path
        return

    FileDelete(save_path)
    FileAppend(BuildOutput(rows), save_path)
}

GetRowValues(window_list, row) {
    return [
        window_list.GetText(row, 1),
        window_list.GetText(row, 2),
        window_list.GetText(row, 3),
        window_list.GetText(row, 4),
        window_list.GetText(row, 5),
        window_list.GetText(row, 6)
    ]
}

BuildOutput(rows) {
    output := "Active\tTitle\tExe\tClass\tPID\tHWND`n"
    for _, row in rows {
        output .= row[1] "\t" row[2] "\t" row[3] "\t" row[4] "\t" row[5] "\t" row[6] "`n"
    }
    return output
}
