; Device detection helpers (keyboard presence).
IsKeyboardPresent(vidPid)
{
    try {
        wmi := ComObjGet("winmgmts:")
        query := "SELECT * FROM Win32_PnPEntity WHERE PNPClass='Keyboard' OR PNPClass='HIDClass'"
        for device in wmi.ExecQuery(query) {
            ids := device.HardwareID
            if IsObject(ids) {
                for id in ids {
                    if InStr(id, vidPid)
                        return true
                }
            } else if (ids && InStr(ids, vidPid)) {
                return true
            }
        }
    } catch {
        return false
    }
    return false
}
