; Global hotkey bindings (super + key combos).
global Config

for _, hotkey_config in Config["global_hotkeys"] {
    if !hotkey_config["enabled"]
        continue

    send_keys := hotkey_config["send_keys"]
    hotkey_name := hotkey_config["hotkey"]
    target_exes := hotkey_config["target_exes"]

    if (target_exes.Length > 0) {
        HotIf (*) => ScopedHotIf(target_exes)
        RegisterSuperComboHotkey(hotkey_name, (*) => Send(send_keys))
        HotIf
    } else {
        RegisterSuperComboHotkey(hotkey_name, (*) => Send(send_keys))
    }
}

ScopedHotIf(target_exes, *) {
    for _, exe in target_exes {
        if WinActive("ahk_exe " exe)
            return true
    }
    return false
}
