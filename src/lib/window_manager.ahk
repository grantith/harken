/**
 * You can use the follow example hotkeys to move the window to a specific position and size if you want
 * width and height pertain to the window.
 * In the F1 example with a width of 2 and a height of 3,
 * imagine you're making a grid that is 2x3, i.e. 2 across and 3 down, 6 possible positions
 * x would be in the second column and y would be the second one down (in the middle)
 * In the F2 example, it would pertain to a 3x3 grid (1/3 width 1/3 height) and
 * the x, y coordinates would put the window in the bottom left
 * In the F3 example, as you can see, you can circumvent the grid_size limit
 https://www.reddit.com/r/AutoHotkey/comments/17qv594/window_management_tool/
 */
; F1::Window.Move({x: 2, y: 2, width: 2, height: 3})
; F2::Window.Move({x: 1, y: 3, width: 3, height: 3})
; F3::Window.Move({x: 3, y: 2, width: 7, height: 6})

global Config


; Window manager utilities: grid math, move/resize, exceptions.
class Window
{
    ;-------------------------------------------------------------------------------
    ; @public
    ; everything up until the @private section can be changed
    ;-------------------------------------------------------------------------------
    /**
     * @grid_size is the amount of rows and columns allowed
     * e.g. a grid_size of 3 means a 3x3 grid
     * Increasing this value too much is not recommended. Some windows have
     * a minimum size and won't play nice in a small-grid layout
     */
    static grid_size := Config["window_manager"]["grid_size"]
    static move_mode := false
    static side_cycle_index := Map()



    /**
     * windows (by class name) to ignore (taskbar, secondary taskbar, desktop, ahk guis, alt-tab menu)
     * I believe the class name of the alt-tab menu is different across several Windows versions.
     * Non-Windows 11 users will have to use Windows Spy to figure out the name of theirs.
     */
    static exceptions := Config["window_manager"]["exceptions_regex"]



    static __New()
    {
        HotIf (*) => IsSuperKeyPressed()
            && !GetKeyState('Shift', 'P')
            && !GetKeyState('Ctrl', 'P')
            && !GetKeyState('LAlt', 'P')
            && !GetKeyState('RAlt', 'P')
            && !this.IsMoveMode()
        Hotkey('*k', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveUp')))
        Hotkey('*h', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveLeft')))
        Hotkey('*j', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveDown')))
        Hotkey('*l', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveRight')))
        Hotkey('*u', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveToPreviousMonitor')))
        Hotkey('*o', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveToNextMonitor')))
        Hotkey('*n', ObjBindMethod(this, 'HotkeyCallback', ObjBindMethod(this, 'MoveToNearestPosition')))
        Hotkey('*m', ObjBindMethod(this, 'Maximize'))
        HotIf

        ; releasing modifier key destroys gui guides
        RegisterSuperKeyHotkey("*", " up", ObjBindMethod(Gui_Guides, 'Destroy_Guis'))
    }

    static SetMoveMode(state) => Window.move_mode := state
    static IsMoveMode(*) => Window.move_mode



    ;-------------------------------------------------------------------------------
    ; @private
    ; the following is not intended to be changed
    ;-------------------------------------------------------------------------------
    /**
     * The minimum grid position
     * The farthest left and top position can never be below this variable
     */
    static min_grid => 1



    /**
     * @param {function object} @Callback the method to call
     * This method acts as a medium before the actual method is called.
     * It is used to prevent methods from being called if the window is an exception
     * and determining what grid point the window is closest to in case it's been resized
     */
    static HotkeyCallback(Callback, *)
    {
        if Window.IsException()                                         ; if window is an exception
            return                                                      ; don't move or update it

        coords := Window.GetCurrentPosition()                           ; get current position
        Callback(coords)                                                ; determine next position
    }



    static GetCurrentPosition()
    {
        WinGetPosEx(&x, &y, &w, &h, 'A')                                ; get window position and size
        x := Abs(x - Screen.left)                                       ; make x relative to left of screen
        y := Abs(y - Screen.top)                                        ; make y relative to right of screen

        screenWidth := Screen.width                                     ; store screen width
        screenHeight := Screen.height                                   ; store screen height

        closest_xPos      := screenWidth                                ; temp var to remember grid x position closest to window x
        closest_yPos      := screenHeight                               ; temp var to remember grid y position closest to window y
        closest_in_width  := screenWidth                                ; temp var to remember plot width closest to window width
        closest_in_height := screenHeight                               ; temp var to remember plot height closest to window height


        /**
         * get width and height of grid point closest to the window
         */
        grid_w_max := Max(Window.grid_size, 4)
        grid_h_max := Window.grid_size

        loop grid_w_max
        {
            plot_width  := screenWidth  // A_Index                      ; screen width divided by 1, 2, 3, etc.
            diffW := Abs(plot_width  - w)                               ; difference between grid plot width and window width

            if diffW <= closest_in_width {                              ; if difference is less than the last difference calculated
                closest_in_width := diffW                               ; remember new value for next iteration
                grid_w := A_Index                                       ; remember width in grid
            }
        }

        loop grid_h_max
        {
            plot_height := screenHeight // A_Index                      ; screen height divided by 1, 2, 3, etc.
            diffH := Abs(plot_height - h)                               ; difference between grid plot height and window height

            if diffH <= closest_in_height {                             ; if difference is less than the last difference calculated
                closest_in_height := diffH                              ; remember new value for next iteration
                grid_h := A_Index                                       ; remember height in grid
            }
        }


        /**
         * closest width found denotes the x grid count
         */
        plot_x := screenWidth // grid_w                                 ; screen width divided by how many times the window width fits on screen

        loop grid_w
        {
            diffX := Abs(plot_x * (A_Index - 1) - x)                    ; get x grid position in order of appropriate layout

            if diffX <= closest_xPos {                                  ; if difference is less than the last difference calculated
                closest_xPos := diffX                                   ; remember new value for next iteration
                grid_x := A_Index                                       ; remember x grid position
            }
        }


        /**
         * closest height found denotes the y grid count
         */
        plot_y := screenHeight // grid_h                                ; screen height dividied by how many times the window height fits on screen

        loop grid_h
        {
            diffY := Abs(plot_y * (A_Index - 1) - y)                    ; get y grid position in order of appropriate layout

            if diffY <= closest_yPos {                                  ; if difference is less than the last difference calculated
                closest_yPos := diffY                                   ; remember new value for next iteration
                grid_y := A_Index                                       ; remember y grid position
            }
        }


        return {                                                        ; return current grid formation and window position in the grid
            x: grid_x,
            y: grid_y,
            width: grid_w,
            height: grid_h
        }
    }



    static IsException(id := 'A') => InStr(Window.exceptions, WinGetClass(id))



    /**
     * Move window in specified direction or position
     */
    static MoveLeft(coords)
    {
        side_max_width := 4
        if (coords.width > side_max_width) {
            coords.width := side_max_width
            coords.x := Min(coords.x, coords.width)
        }

        if --coords.x < this.min_grid                                   ; if x-1 coord is out of grid bounds
        {
            coords.x := this.min_grid                                   ; set x coord to minimum grid

            if coords.width = side_max_width                            ; if width is at max size
            {
                coords.y := 1                                           ; set y coord to top of screen

                (coords.height = 1 ? (coords.width  := 2)               ; if height is already screen height, make window width half-screen
                                : (coords.height := 1))              ; else set window height to height of screen
            }
            else                                                        ; if width is less than max size
            {
                WinGetPosEx(,, &w,, 'A')                                ; get window width
                coords.width := Window.GetNextSideWidthFromCycle(w)
            }
        }
        Window.UpdatePosition(coords)                                   ; update the window position
    }


    static MoveRight(coords)
    {
        side_max_width := 4
        if (coords.width > side_max_width) {
            coords.width := side_max_width
            coords.x := Min(coords.x, coords.width)
        }

        if ++coords.x > coords.width                                    ; if x+1 coord is greater than window width
        {
            if coords.x > side_max_width                                ; if x coord is out of grid bounds
            {
                coords.y := 1                                           ; set y coord to top of screen

                (coords.height = 1 ? (coords.width  := 2)               ; if height is already screen height, make window width half-screen
                                : (coords.height := 1))              ; else set window height to height of screen
                coords.x := coords.width                                ; set x coord to window width
            }
            else                                                        ; if x coord is within grid
            {
                WinGetPosEx(,, &w,, 'A')                                ; get window width
                coords.width := Window.GetNextSideWidthFromCycle(w)
                coords.x := coords.width
            }
        }
        Window.UpdatePosition(coords)                                   ; update the window position
    }

    static GetSideWidthDivisors()
    {
        return [4.0, 3.0, 2.0, 1.5]
    }

    static GetNextSideWidthFromCycle(window_width)
    {
        hwnd := WinExist("A")
        if !hwnd
            return 2.0

        screen_width := Screen.width
        if (screen_width <= 0)
            return 2.0

        divisors := Window.GetSideWidthDivisors()
        base_index := Window.GetClosestSideDivisorIndex(window_width, screen_width, divisors)
        current_index := base_index
        if Window.side_cycle_index.Has(hwnd) {
            stored_index := Window.side_cycle_index[hwnd]
            if (stored_index >= 1 && stored_index <= divisors.Length) {
                if Window.IsWidthNearDivisor(window_width, screen_width, divisors[stored_index])
                    current_index := stored_index
            }
        }

        next_index := current_index + 1
        if (next_index > divisors.Length)
            next_index := 1

        Window.side_cycle_index[hwnd] := next_index
        return divisors[next_index]
    }

    static GetClosestSideDivisorIndex(window_width, screen_width, divisors)
    {
        closest_index := 1
        closest_diff := Abs((screen_width / divisors[1]) - window_width)
        for i, divisor in divisors {
            diff := Abs((screen_width / divisor) - window_width)
            if (diff < closest_diff) {
                closest_diff := diff
                closest_index := i
            }
        }
        return closest_index
    }

    static IsWidthNearDivisor(window_width, screen_width, divisor, tolerance_px := 12)
    {
        expected := screen_width / divisor
        return Abs(window_width - expected) <= tolerance_px
    }

    static GetNextSideWidthDivisor(window_width)
    {
        screen_width := Screen.width
        if (screen_width <= 0)
            return ""

        divisors := Window.GetSideWidthDivisors()
        closest_index := 1
        closest_diff := Abs((screen_width / divisors[1]) - window_width)
        for i, divisor in divisors {
            diff := Abs((screen_width / divisor) - window_width)
            if (diff < closest_diff) {
                closest_diff := diff
                closest_index := i
            }
        }

        if (closest_index < divisors.Length)
            return divisors[closest_index + 1]
        return divisors[1]
    }


    static MoveUp(coords)
    {
        if --coords.y < this.min_grid                                   ; if y-1 coord is out of grid bounds
        {
            coords.y := this.min_grid                                   ; set y coord to minimum grid value

            if coords.height = this.grid_size                           ; if height is at max size
            {
                if coords.width = 1                                     ; if width is already screen width
                    return this.Maximize()                              ; maximize window and return early
                else {                                                  ; if window width is not screen width
                    coords.x := 1                                       ; set x coord to left of screen
                    coords.width := 1                                   ; set window width to width of screen
                }
            }
            else                                                        ; if y coord is within grid
                coords.height := Min(++coords.height, this.grid_size)   ; increase height of window if there is room
        }
        Window.UpdatePosition(coords)                                   ; update the window position
    }


    static MoveDown(coords)
    {
        if ++coords.y > coords.height                                   ; if y+1 coordinate is greater than window height
        {
            if coords.y > this.grid_size                                ; if y coord is out of grid bounds
            {
                coords.x := 1                                           ; set x coord to left of screen

                (coords.width = 1 ? (coords.height := 2)                ; if width is already screen width, make window height half-screen
                                : (coords.width  := 1))               ; else set window width to width of screen
                coords.y := coords.height                               ; set y coord to window height
            }
            else                                                        ; if y coord is within grid
                coords.height := Min(++coords.height, this.grid_size)   ; increase height of window if there is room
        }
        Window.UpdatePosition(coords)                                   ; update the window position
    }



    static MoveToNearestPosition(coords) => Window.Move(coords)



    static Maximize(*)
    {
        if Window.IsException()                                         ; if window is an exception
            return                                                      ; don't move it
        Gui_Guides.Destroy_Guis()                                       ; destroy any gui guides
        Window.Move({ x: 1, y: 1, width: 1, height: 1 }, 'A')            ; maximize within padded work area
    }



    static IsMaximized(coords)
    {
        if WinGetMinMax('A') = 1                                        ; if window is maximized
            return true                                                 ; return true

        for i, v in coords.OwnProps()                                   ; loop through coord properties
            if v != Window.min_grid                                     ; if value is not equivalent to maxmized window values (1)
                return false                                            ; return false
        return true                                                     ; return true if window coords are equal to maximized window
    }



    static MoveToPreviousMonitor(coords) {
        Send('#+{Left}')                                                ; move window to the previous monitor
        Window.UpdatePosition(coords)                                   ; update window position and adjust gui guides
    }



    static MoveToNextMonitor(coords) {
        Send('#+{Right}')                                               ; move window to the next monitor
        Window.UpdatePosition(coords)                                   ; update window position and adjust gui guides
    }



    static UpdatePosition(coords) {
        this.Move(coords)                                  ; determine position and size of window
        Gui_Guides().Create(coords)                                     ; create gui guides to show positions to move window
        Gui_Guides.ScheduleDestroy()                                   ; fallback in case key-up isn't detected
    }



    /**
     * Determine where on the screen the window should be
     * and the window's width and height
     */
    static Move(coords, hwnd := 'A')
    {
        width_is_int := IsInteger(coords.width)
        height_is_int := IsInteger(coords.height)

        if width_is_int {
            fractionX := Mod(100, coords.width) != 0                    ; check if window / width isn't a whole number
            x_pos := (coords.x - 1) * (100 // coords.width)             ; get x position window should be in
            width := (100 // coords.width) +                            ; 100 / window width, rounded down
                (fractionX and (coords.x = coords.width) ? 1 : 0)       ; add one if layout size isn't evenly divided by window and window is furthest right in the grid
        } else {
            width := 100 / coords.width
            x_pos := (coords.x - 1) * width
        }

        if height_is_int {
            fractionY := Mod(100, coords.height) != 0                   ; check if window / height isn't a whole number
            y_pos := (coords.y - 1) * (100 // coords.height)            ; get y position window should be in
            height := (100 // coords.height) +                          ; 100 / window height, rounded down
                (fractionY and (coords.y = coords.height) ? 1 : 0)      ; add one if layout size isn't evenly divided by window and window is furthest bottom in the grid
        } else {
            height := 100 / coords.height
            y_pos := (coords.y - 1) * height
        }

        WinRestore(hwnd)                                                ; unmaximizes window if maximized

        target_x := Screen.X_Pos_Percent(x_pos)
        target_y := Screen.Y_Pos_Percent(y_pos)
        target_w := Screen.Width_Percent(width)
        target_h := Screen.Height_Percent(height)

        gap_px := Config["window_manager"]["gap_px"]
        if (gap_px > 0) {
            left_inset := gap_px
            right_inset := gap_px
            top_inset := gap_px
            bottom_inset := gap_px

            target_x += left_inset
            target_y += top_inset
            target_w -= (left_inset + right_inset)
            target_h -= (top_inset + bottom_inset)

            if (target_w <= 0 || target_h <= 0)
                return
        }

        WinMoveEx(                                                      ; move window taking invisible borders into account
            target_x,                                                   ; move window x_pos to x% of the screen
            target_y,                                                   ; move window y_pos to x% of the screen
            target_w,                                                   ; resize window width to x%
            target_h,                                                   ; resize window height to x%
            hwnd                                                        ; window to move
        )


        /**
         * The following code prevents the window from bleeding onto another screen if the window has a
         * minimum width or height and it's placement wouldn't allow it's size to fit within the screen.
         * On a smaller screen (or portrait mode), multiple side-by-side windows with a large minimum
         * width or height could result in overlapping windows
         */
        WinGetPosEx(&x, &y, &width, &height, hwnd)                      ; window dimensions

        if x + width > Screen.right                                     ; if window x position + window width goes off the right side of the screen
            WinMove(Screen.right - width,,,, hwnd)                      ; move window back onto screen
        if y + height > Screen.bottom                                   ; if window y position + window height goes off the bottom of the screen
            WinMove(, Screen.bottom - height,,, hwnd)                   ; move window back onto screen
    }
}



class Gui_Guides
{
    static list := Map()                                                ; keeps track of existing gui guides
    static destroy_timer := ObjBindMethod(Gui_Guides, "Destroy_Guis")

    __New() {
        Gui_Guides.Destroy_Guis()                                       ; destroy old guis when creating new ones
    }



    Create(coords)
    {
        if Window.IsMaximized(coords)                                   ; window is in maximized state
            return Gui_Guides.Destroy_Guis()                            ; destroy any gui guides and return early

        if coords.x < coords.width                                      ; check if guides can be created to the right of the window position
        {
            coords.x++                                                  ; increase x position
            this.Make_Gui_Guide(coords)                                 ; create gui guide based on that position and size
            coords.x--                                                  ; revert value change to referenced object
        }

        if coords.x > Window.min_grid                                   ; check if guides can be created to the left of the window position
        {
            coords.x--                                                  ; decrease x position
            this.Make_Gui_Guide(coords)                                 ; create gui guide based on that position and size
            coords.x++                                                  ; revert value change to referenced object
        }

        if coords.y < coords.height                                     ; check if guides can be created below the window position
        {
            coords.y++                                                  ; increase y position
            this.Make_Gui_Guide(coords)                                 ; create gui guide based on that position and size
            coords.y--                                                  ; revert value change to referenced object
        }

        if coords.y > Window.min_grid                                   ; check if guides can be created above the window position
        {
            coords.y--                                                  ; decrease y position
            this.Make_Gui_Guide(coords)                                 ; create gui guide based on that position and size
        }
    }



    static Destroy_Guis(*)
    {
    for gui in this.list                                             ; for each gui in the map
        gui.Destroy()                                                 ; destroy the gui

    this.list.Clear()                                                ; clear map to make room for new guis
    }

    static ScheduleDestroy(delay_ms := 400)
    {
        SetTimer(this.destroy_timer, 0)
        SetTimer(this.destroy_timer, -delay_ms)
    }




    /**
     * @private @methods
     */
    Make_Gui_Guide(guide_coords)
    {
        this.gui := Gui('+AlwaysOnTop -SysMenu +ToolWindow -Caption -Border +E0x20')
        WinSetTransparent(50, this.gui)                                 ; transparency of 50

        this.gui.Show('NoActivate')                                     ; show gui
        Gui_Guides.list.Set(this.gui, this.gui.Hwnd)                    ; add gui to map
        Window.Move(guide_coords, this.gui.Hwnd)           ; move gui guide to correct location
        this.CornerRadius()                                             ; curve corners of gui
    }


    CornerRadius(curve := 15)
    {
        if !this.gui
            return
        if !WinExist("ahk_id " this.gui.Hwnd)
            return
        this.gui.GetPos(,, &width, &height)                             ; get position of gui
        WinSetRegion('0-0 w' width ' h' height ' r'                     ; use position to round the corners
        curve '-' curve, this.gui)                                      ; using this curve value
    }
}


class Screen
{
    static top_margin := Config["window_manager"]["margins"]["top"]
    static left_margin := Config["window_manager"]["margins"]["left"]
    static right_margin := Config["window_manager"]["margins"]["right"]
    static bottom_margin := Config["window_manager"]["margins"]["bottom"]
    static activeWindowIsOn => Screen.FromWindow()
    static top    => this.GetScreenCoordinates(this.activeWindowIsOn, 'top')
    static bottom => this.GetScreenCoordinates(this.activeWindowIsOn, 'bottom')
    static left   => this.GetScreenCoordinates(this.activeWindowIsOn, 'left')
    static right  => this.GetScreenCoordinates(this.activeWindowIsOn, 'right')
    static width  => this.GetScreenCoordinates(this.activeWindowIsOn, 'width')
    static height => this.GetScreenCoordinates(this.activeWindowIsOn, 'height')



    /**
     * @param @mon monitor number to get dimensions of
     * @param @coord what aspect of the screen to return
     */
    static GetScreenCoordinates(mon, coord)
    {
        MonitorGetWorkArea(mon, &left, &top, &right, &bottom)           ; get dimensions of screen

        if this.top_margin
            top += this.top_margin
        if this.left_margin
            left += this.left_margin
        if this.right_margin
            right -= this.right_margin
        if this.bottom_margin
            bottom -= this.bottom_margin

        width  := Abs(right  - left)                                    ; calculate width of screen
        height := Abs(bottom - top)                                     ; calculate height of screen

        return %coord%                                                  ; return coord dimension
    }



    /**
     * @example: invoking Screen.X_Pos_Percent(40) returns position 40% from the left of the screen
     */
    static X_Pos_Percent(percent)  => Integer(this.width  * (percent / 100) + this.left)
    static Y_Pos_Percent(percent)  => Integer(this.height * (percent / 100) + this.top)
    static Width_Percent(percent)  => Integer(this.width  * (percent / 100))
    static Height_Percent(percent) => Integer(this.height * (percent / 100))



    static FromWindow(id := 'A')
    {
        try monFromWin := DllCall('MonitorFromWindow', 'Ptr', WinGetID(id), 'UInt', 2)  ; get monitor handle number window is on
        catch {                                                                         ; if it fails because of something weird active like alt-tab menu,
            return MonitorGetPrimary()                                                  ; return primary monitor number as a fallback
        }
        return Screen.__ConvertHandleToNumber(monFromWin)                               ; convert handle to monitor number and return it
    }



    static __ConvertHandleToNumber(handle)
    {
        monCallback   := CallbackCreate(__EnumMonitors, 'Fast', 4)                      ; fast-mode, 4 parameters
        monHandleList := ''                                                             ; initialize monitor handle number list

        if Screen.EnumerateDisplays(monCallback)                                        ; enumerates all monitors
        {
            loop parse, monHandleList, '`n'                                             ; loop list of monitor handle numbers
                if A_LoopField = handle                                                 ; if the handle number matches the monitor the mouse is on
                    return A_Index                                                      ; set monFromMouse to monitor number
        }

        __EnumMonitors(hMonitor, hDevCon, pRect, args) {                                ; callback function for enumeration DLL
            monHandleList .= hMonitor '`n'                                              ; add monitor handle number to list
            return true                                                                 ; continues enumeration
        }
    }

    static EnumerateDisplays(callback) => DllCall('EnumDisplayMonitors', 'Ptr', 0, 'Ptr', 0, 'Ptr', callback, 'UInt', 0)
}


;-------------------------------------------------------------------------------
; WINDOW POSITION WITHOUT INVISIBLE BORDERS
;-------------------------------------------------------------------------------
/**
 * @author plankoe
 * @source https://old.reddit.com/r/AutoHotkey/comments/14xjya7/force_window_size_and_position/
 */
WinMoveEx(x?, y?, w?, h?, hwnd?)        ; move window and fix offset from invisible border
{
    if !(hwnd is integer)
        hwnd := WinExist(hwnd)
    if !IsSet(hwnd)
        hwnd := WinExist()

    ; compare pos and get offset
    WinGetPosEx(&fX, &fY, &fW, &fH, hwnd)
    WinGetPos(&wX, &wY, &wW, &wH, hwnd)
    xDiff := fX - wX
    hDiff := wH - fH

    ; new x, y, w, h with offset corrected.
    IsSet(x) && nX := x - xDiff
    IsSet(y) && nY := y
    IsSet(w) && nW := w + xDiff * 2
    IsSet(h) && nH := h + hDiff
    WinMove(nX?, nY?, nW?, nH?, hwnd?)
}

WinGetPosEx(&x?, &y?, &w?, &h?, hwnd?)  ; get window position without the invisible border
{
    static DWMWA_EXTENDED_FRAME_BOUNDS := 9

    if !(hwnd is integer)
        hwnd := WinExist(hwnd)
    if !IsSet(hwnd)
        hwnd := WinExist() ; last found window

    DllCall('dwmapi\DwmGetWindowAttribute',
            'Ptr' , hwnd,
            'UInt', DWMWA_EXTENDED_FRAME_BOUNDS,
            'Ptr' , RECT := Buffer(16, 0),
            'Int' , RECT.size,
            'UInt')
    x := NumGet(RECT,  0, 'Int')
    y := NumGet(RECT,  4, 'Int')
    w := NumGet(RECT,  8, 'Int') - x
    h := NumGet(RECT, 12, 'Int') - y
}
