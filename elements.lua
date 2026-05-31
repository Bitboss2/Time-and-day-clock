-- elements.lua
-- Defines the position and layer of each element on the display.
-- Edit this file and relaunch the widget to see changes immediately.
-- No KOReader restart needed.
--
-- ============================================================
-- COORDINATE SYSTEM
--   (0, 0)  = the CENTER of the screen
--   x > 0   = move RIGHT      x < 0 = move LEFT
--   y > 0   = move DOWN       y < 0 = move UP
--
-- UNITS (per element)
--   "px"  = raw pixels
--   "%"   = percentage of screen dimension
--           e.g. y = -20 with "%" → 20% of screen height above center
--
-- Z-ORDER (layers)
--   Lower z = painted first = further behind
--   Higher z = painted last = in front
--
-- VISIBILITY
--   visible = true  → element is drawn
--   visible = false → element is skipped entirely
-- ============================================================

return {

    -- PNG image overlay — behind everything (z=1)
    -- It will show through the transparent text widgets above it.
    png = {
        x       = 0,
        y       = 0,
        unit    = "%",
        z       = 3,
        visible = true,
    },

    -- Date line — above center
    date = {
        x       = 0,
        y       = -10,
        unit    = "%",
        z       = 4,
        visible = true,
    },

    -- Large clock / time — centered
    time = {
        x       = 0,
        y       = 0,
        unit    = "px",
        z       = 2,
        visible = true,
    },

    -- Status line (battery · wifi · memory) — below center
    status = {
        x       = 0,
        y       = 10,
        unit    = "%",
        z       = 2,
        visible = true,
    },
    wifi    = {
        x = -150,
        y = 20,
        unit = "%",
        z = 2,
        visible = false,
    },
    battery = {
        x = 0,
        y = -45,
        unit = "%",
        z = 2,
        visible = true,
    },
    memory  = {
        x = 150,
        y = 20,
        unit = "%",
        z = 2,
        visible = false,
    },
}