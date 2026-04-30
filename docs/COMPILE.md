## Option 1: Use Ahk2Exe (official GUI)

1. Install AutoHotkey v2.
2. Open **Ahk2Exe** (included with the AutoHotkey install).
3. Configure:
   - **Source (Script)**: your `.ahk` file
   - **Destination (Exe)**: output path
   - **Base File**: v2 base (e.g. `AutoHotkey64.exe`)
   - *(Optional)* **Icon**: `.ico`
4. Click **Convert**.

Result: a standalone `.exe` that runs without AutoHotkey installed.


## Option 2: Command-line Ahk2Exe

```powershell
& Ahk2Exe.exe `
  /in  .\harken.ahk `
  /out .\dist\harken.exe `
  /base .\ahk\AutoHotkey64.exe
```
