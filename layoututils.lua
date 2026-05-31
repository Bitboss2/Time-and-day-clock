-- layoututils.lua
-- Builds a free-positioned OverlapGroup from layout_settings.lua.
-- Used by DisplayWidget when layout_settings.enabled = true.

local Device      = require("device")
local Geom        = require("ui/geometry")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen      = Device.screen

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"

local LayoutUtils = {}

-- ---------------------------------------------------------------------------
-- Load layout_settings.lua from the plugin directory.
-- Returns the table on success, or nil if the file is missing / broken.
-- ---------------------------------------------------------------------------
function LayoutUtils.loadSettings()
    local path = PLUGIN_DIR .. "layout_settings.lua"
    local ok, result = pcall(dofile, path)
    if ok and type(result) == "table" then
        return result
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Return true when free positioning should be active.
-- Must be called with props.advanced_settings_enabled so free layout only
-- fires when the user has explicitly enabled Advanced settings in the UI.
-- ---------------------------------------------------------------------------
function LayoutUtils.isEnabled(advanced_settings_on)
    if not advanced_settings_on then return false end
    local s = LayoutUtils.loadSettings()
    return s ~= nil and s.enabled == true
end

-- ---------------------------------------------------------------------------
-- Attach an overlap_offset to a widget so OverlapGroup places it correctly.
--
--   widget   : a TextBoxWidget (or any widget with getSize())
--   cx, cy   : screen centre in pixels
--   ex, ey   : element offsets from layout_settings (x, y)
-- ---------------------------------------------------------------------------
local function attachOffset(widget, cx, cy, ex, ey)
    local size = widget:getSize()
    -- Centre the widget on (cx + ex, cy + ey)
    local abs_x = cx + ex - math.floor(size.w / 2)
    local abs_y = cy + ey - math.floor(size.h / 2)
    widget.overlap_offset = { abs_x, abs_y }
    return widget
end

-- ---------------------------------------------------------------------------
-- Build the OverlapGroup for the free-layout mode (text widgets only).
-- The PNG overlay is kept outside this hierarchy: DisplayWidget:paintTo
-- paints it directly so night-mode inversion can be applied selectively.
--
--   screen_size   : { w, h }
--   time_widget   : rendered TextBoxWidget for the clock
--   date_widget   : rendered TextBoxWidget for the date
--   status_widget : rendered TextBoxWidget for the status line
--
-- Returns:
--   overlap_group : OverlapGroup containing the three text widgets
--   dirty_dimen   : Geom covering all three widgets (for setDirty calls)
-- ---------------------------------------------------------------------------
function LayoutUtils.buildLayout(screen_size, time_widget, date_widget, status_widget)
    local settings = LayoutUtils.loadSettings()
    -- Provide sane defaults if elements are missing from the file
    local el = (settings and settings.elements) or {}
    local time_cfg   = el.time   or { x = 0, y = -40, z = 2 }
    local date_cfg   = el.date   or { x = 0, y =  60, z = 2 }
    local status_cfg = el.status or { x = 0, y = 130, z = 2 }

    local sw, sh = screen_size.w, screen_size.h
    local cx, cy = math.floor(sw / 2), math.floor(sh / 2)

    -- Attach absolute screen positions to each text widget
    attachOffset(time_widget,   cx, cy, time_cfg.x   or 0, time_cfg.y   or 0)
    attachOffset(date_widget,   cx, cy, date_cfg.x   or 0, date_cfg.y   or 0)
    attachOffset(status_widget, cx, cy, status_cfg.x or 0, status_cfg.y or 0)

    -- Sort text elements by z (ascending = bottom to top)
    local text_elements = {
        { widget = time_widget,   z = time_cfg.z   or 2 },
        { widget = date_widget,   z = date_cfg.z   or 2 },
        { widget = status_widget, z = status_cfg.z or 2 },
    }
    table.sort(text_elements, function(a, b)
        return a.z < b.z
    end)

    -- Build OverlapGroup without table.unpack (not available in Lua 5.1 / LuaJIT)
    local og_args = { dimen = Geom:new { w = sw, h = sh } }
    for i, entry in ipairs(text_elements) do
        og_args[i] = entry.widget
    end
    local overlap_group = OverlapGroup:new(og_args)

    -- Build a dirty region that covers all three text widgets (union of bounding boxes)
    local function widget_rect(w)
        local off = w.overlap_offset or { 0, 0 }
        local sz  = w:getSize()
        return { x = off[1], y = off[2], w = sz.w, h = sz.h }
    end
    local rects = {
        widget_rect(time_widget),
        widget_rect(date_widget),
        widget_rect(status_widget),
    }
    local x1 = rects[1].x
    local y1 = rects[1].y
    local x2 = rects[1].x + rects[1].w
    local y2 = rects[1].y + rects[1].h
    for i = 2, #rects do
        local r = rects[i]
        if r.x       < x1 then x1 = r.x       end
        if r.y       < y1 then y1 = r.y       end
        if r.x + r.w > x2 then x2 = r.x + r.w end
        if r.y + r.h > y2 then y2 = r.y + r.h end
    end
    local dirty_dimen = Geom:new { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }

    return overlap_group, dirty_dimen
end

-- ---------------------------------------------------------------------------
-- Re-attach offsets for the three text widgets after an in-place text update.
-- Call this from DisplayWidget:refresh() instead of rebuilding from scratch.
-- ---------------------------------------------------------------------------
function LayoutUtils.refreshOffsets(screen_size, time_widget, date_widget, status_widget)
    local settings = LayoutUtils.loadSettings()
    local el = (settings and settings.elements) or {}
    local time_cfg   = el.time   or { x = 0, y = -40, z = 2 }
    local date_cfg   = el.date   or { x = 0, y =  60, z = 2 }
    local status_cfg = el.status or { x = 0, y = 130, z = 2 }

    local cx = math.floor(screen_size.w / 2)
    local cy = math.floor(screen_size.h / 2)

    attachOffset(time_widget,   cx, cy, time_cfg.x   or 0, time_cfg.y   or 0)
    attachOffset(date_widget,   cx, cy, date_cfg.x   or 0, date_cfg.y   or 0)
    attachOffset(status_widget, cx, cy, status_cfg.x or 0, status_cfg.y or 0)
end

return LayoutUtils