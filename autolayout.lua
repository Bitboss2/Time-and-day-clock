-- autolayout.lua
-- Automatic vertical layout engine for DtDisplay.
-- Prevents widget overlap by stacking visible elements dynamically based on
-- their actual rendered height, with configurable gaps.
--
-- When enabled, this module overrides the static x/y positions from
-- elements.lua and centres all widgets vertically on screen.

local Device = require("device")
local Screen = Device.screen

local AutoLayout = {}

--- Default vertical gap between widgets (pixels).
AutoLayout.DEFAULT_GAP = 20

--- Order in which widgets should be stacked top-to-bottom.
--  Widgets not listed here (or not visible) are skipped.
AutoLayout.STACK_ORDER = { "date", "time", "status", "battery", "wifi", "memory" }

-- ---------------------------------------------------------------------------
-- Compute automatic positions for all visible widgets.
--
-- @param render_list  table  Array of { widget, px, py, z, is_png, name }
--                            (the 'name' field must be set before calling)
-- @param elements     table  The current elements config (from elements.lua)
-- @param gap          number Vertical spacing between widgets (px)
-- @return table  The same render_list, with px/py updated
-- ---------------------------------------------------------------------------
function AutoLayout.apply(render_list, elements, gap)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    if not gap or gap == 20 then
        gap = math.max(20, math.floor(sh * 0.035))
    end

    -- Separate PNG items (keep their original position) from text widgets
    local text_items = {}
    local other_items = {}

    -- Build a lookup by name for ordering
    local name_order = {}
    for i, name in ipairs(AutoLayout.STACK_ORDER) do
        name_order[name] = i
    end

    for _, item in ipairs(render_list) do
        if item.is_png then
            table.insert(other_items, item)
        else
            -- Only include if the element is in our stack order
            if item.name and name_order[item.name] then
                table.insert(text_items, item)
            else
                table.insert(other_items, item)
            end
        end
    end

    -- Sort text items according to STACK_ORDER
    table.sort(text_items, function(a, b)
        local oa = name_order[a.name] or 999
        local ob = name_order[b.name] or 999
        return oa < ob
    end)

    -- Calculate total height of all text widgets
    local total_h = 0
    for _, item in ipairs(text_items) do
        local size = item.widget:getSize()
        total_h = total_h + size.h
    end
    -- Add gaps
    if #text_items > 1 then
        total_h = total_h + (#text_items - 1) * gap
    end

    -- Start Y so the whole block is vertically centred
    local y_cursor = math.floor((sh - total_h) / 2)
    if y_cursor < 10 then y_cursor = 10 end -- small margin safety

    -- Assign positions
    for _, item in ipairs(text_items) do
        local size = item.widget:getSize()
        item.px = math.floor((sw - size.w) / 2) -- centred horizontally
        item.py = y_cursor
        y_cursor = y_cursor + size.h + gap
    end

    -- Rebuild the full render_list preserving z-order
    local result = {}
    for _, item in ipairs(other_items) do table.insert(result, item) end
    for _, item in ipairs(text_items) do table.insert(result, item) end
    table.sort(result, function(a, b) return a.z < b.z end)

    return result
end

return AutoLayout
