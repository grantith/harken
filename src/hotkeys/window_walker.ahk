; Window walker hotkey binding.
global Config

if Config.Has("window_selector") && Config["window_selector"]["enabled"] {
    hotkey_name := Config["window_selector"]["hotkey"]
    RegisterSuperComboHotkey(hotkey_name, (*) => WindowWalker.Toggle())
}
