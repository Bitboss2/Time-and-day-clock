-- layout_settings.lua
-- Free-positioning layout for DtDisplay elements.
-- Place this file in the DtDisplay plugin folder alongside advanced_settings.lua.
--
-- This file is only read when "Advanced settings" is enabled in the DtDisplay
-- menu AND layout.enabled is set to true below.
--
-- When layout.enabled = false (default), the standard stacked layout from the
-- UI is used — nothing here changes the display.
--
-- COORDINATE SYSTEM
-- -----------------
--   x  Horizontal offset from the screen centre.
--      Negative values move the element left, positive values move it right.
--   y  Vertical offset from the screen centre.
--      Negative values move the element up, positive values move it down.
--   z  Stacking layer (paint order).
--      Higher z is drawn on top of lower z.
--      Elements with equal z are drawn in the order: time → date → status.
--
-- The *centre* of each element is placed at (screen_centre_x + x, screen_centre_y + y).
-- All element backgrounds are fully transparent, so overlapping elements are
-- visible through each other.
--
-- EXAMPLES
-- --------
--   Place the clock in the top-left quadrant, date below it, status at bottom-centre:
--
--     time   = { x = -200, y = -150, z = 2 },
--     date   = { x = -200, y =  -80, z = 2 },
--     status = { x =    0, y =  250, z = 1 },
--
--   Layer the time behind a PNG overlay (PNG rendered at z = 3 by the engine):
--
--     time   = { x = 0, y = 0, z = 1 },

return {
    -- Set to true to activate free positioning.
    -- The default stacked layout is completely unchanged when this is false.
    enabled = true,

    elements = {
        time = {
            x = 0,    -- pixels from screen centre, negative = left
            y = -40,  -- pixels from screen centre, negative = up
            z = 2,    -- stacking layer
        },
        date = {
            x = 0,
            y = 60,
            z = 1,
        },
        status = {
            x = 0,
            y = 130,
            z = 0,
        },
    },
}
