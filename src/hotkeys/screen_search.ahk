; Screen search hotkey binding.
global Config

if Config.Has("screen_search") && Config["screen_search"]["enabled"] {
    hotkey_name := Config["screen_search"]["hotkey"]
    if (hotkey_name != "")
        RegisterSuperComboHotkey(hotkey_name, (*) => ScreenSearch.Toggle())
}
