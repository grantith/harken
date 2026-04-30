; App hotkey bindings (launch or focus).
global Config

HotIf IsSuperKeyPressed
for _, app in Config["apps"] {
    if !app.Has("hotkey") || app["hotkey"] = ""
        continue
    hotkey_name := app["hotkey"]
    win_title := app.Has("win_title") ? app["win_title"] : ""
    run_cmd := app.Has("run") ? app["run"] : ""
    hotkey_id := app["id"]
    Hotkey(hotkey_name, FocusOrRun.Bind(win_title, run_cmd, hotkey_id, app))
}
HotIf
