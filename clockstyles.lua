-- clockstyles.lua
-- Clock style renderers for DtDisplay.
-- Each style provides methods to render the clock directly onto a Blitbuffer
-- or to return a widget-compatible object.

local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local Screen     = Device.screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget    = require("ui/widget/textwidget")
local TimeUtils   = require("timeutils")
local RenderUtils = require("renderutils")

local ClockStyles = {}

-- Available style identifiers
ClockStyles.STYLES = {
    "classic",       -- existing behaviour
    "fullscreen",    -- digits fill entire screen width
    "analog",        -- analog clock face with hands
    "outlined",      -- text with thick outline (great over PNG overlays)
    "wordclock",     -- time spelled out in words (French)
}

-- =========================================================================
-- TEXT SIZE PRESETS
-- Maps size names to multipliers of screen height for time and date.
-- =========================================================================

ClockStyles.SIZE_PRESETS = {
    small  = { time_frac = 0.05,  date_frac = 0.015, status_frac = 0.015 },
    medium = { time_frac = 0.09,  date_frac = 0.02,  status_frac = 0.02  },
    big    = { time_frac = 0.14,  date_frac = 0.03,  status_frac = 0.025 },
    huge   = { time_frac = 0.20,  date_frac = 0.045, status_frac = 0.03  },
}

--- Resolve a size preset name into pixel font sizes.
-- @param preset_name  string  "small", "medium", "big", "huge"
-- @param screen_h     number  screen height in pixels
-- @return time_size, date_size, status_size
function ClockStyles.resolvePresetSizes(preset_name, screen_h)
    local preset = ClockStyles.SIZE_PRESETS[preset_name]
                   or ClockStyles.SIZE_PRESETS["medium"]
    return math.floor(screen_h * preset.time_frac),
           math.floor(screen_h * preset.date_frac),
           math.floor(screen_h * preset.status_frac)
end

-- =========================================================================
-- STYLE: FULLSCREEN DIGITAL
-- Giant digits that fill the screen width. No other widgets shown.
-- =========================================================================

function ClockStyles.renderFullscreen(now, sw, sh, font_name, clock_format)
    -- Stacked design: Hours on top, Minutes on bottom
    local is_12_hour = (clock_format == "12h")
    local format_str = is_12_hour and "%I\n%M" or "%H\n%M"
    local time_text = os.date(format_str, now)

    -- Force full available height/width metrics explicitly for portrait and landscape
    local avail_w = math.floor(sw * 0.95)
    local avail_h = math.floor(sh * 0.90)

    -- Cache the font size calculation per screen dimension and font
    ClockStyles._fullscreen_cache = ClockStyles._fullscreen_cache or {}
    local cache_key = string.format("%d_%d_%s_%s", sw, sh, font_name, clock_format)
    local best = ClockStyles._fullscreen_cache[cache_key]

    if not best then
        -- Binary search for the largest font that cleanly fits TWO lines on the screen boundary
        local lo, hi = 60, sh
        best = lo
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local face = Font:getFace(font_name, mid)
            local test_w = TextBoxWidget:new({
                text = time_text, face = face, width = avail_w,
                alignment = "center",
            })
            local sz = test_w:getSize()
            test_w:free()
            
            if sz.h <= avail_h and sz.w <= avail_w then
                best = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end
        ClockStyles._fullscreen_cache[cache_key] = best
    end

    local face = Font:getFace(font_name, best)
    
    local widget = RenderUtils.createSpriteWidget {
        text = time_text,
        face = face,
        width = sw,
        alignment = "center",
        bold = true,
    }
    widget.dimen.h = sh -- Force fullscreen bounds

    -- Override setText to preserve the forced fullscreen bounds
    local original_setText = widget.setText
    function widget:setText(new_text)
        original_setText(self, new_text)
        self.dimen.h = sh
    end

    -- Override paintTo to center the content vertically in the exact sh boundary
    local original_paintTo = widget.paintTo
    function widget:paintTo(bb, x, y)
        original_paintTo(self, bb, x, y)
    end

    return widget
end

-- =========================================================================
-- STYLE: ANALOG CLOCK
-- Draws a classic clock face with hour/minute hands using Blitbuffer.
-- Returns a widget-like table with paintTo/getSize/free methods.
-- =========================================================================

local function drawThickLine(bb, x1, y1, x2, y2, thickness, color)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end

    local px = -dy / len
    local py = dx / len
    local half_t = thickness / 2

    local steps = math.ceil(thickness)
    for i = 0, steps do
        local t = -half_t + (i / steps) * thickness
        local ox = math.floor(px * t + 0.5)
        local oy = math.floor(py * t + 0.5)

        local sx, sy = x1 + ox, y1 + oy
        local ex, ey = x2 + ox, y2 + oy
        local adx = math.abs(ex - sx)
        local ady = math.abs(ey - sy)
        local step_x = sx < ex and 1 or -1
        local step_y = sy < ey and 1 or -1
        local err = adx - ady
        local cx, cy = sx, sy
        for _ = 0, adx + ady + 1 do
            if cx >= 0 and cy >= 0 and cx < bb:getWidth() and cy < bb:getHeight() then
                bb:setPixelClamped(cx, cy, color)
            end
            if cx == ex and cy == ey then break end
            local e2 = 2 * err
            if e2 > -ady then err = err - ady; cx = cx + step_x end
            if e2 < adx  then err = err + adx; cy = cy + step_y end
        end
    end
end

function ClockStyles.renderAnalog(now, sw, sh, style_opts)
    style_opts = style_opts or {}
    local numerals = style_opts.numerals or "arabic"

    local cx = math.floor(sw / 2)
    local cy = math.floor(sh / 2)
    local radius = math.floor(math.min(sw, sh) * 0.42)

    -- Dynamic defaults scaling with screen size
    local default_hand_hour = math.max(3, math.floor(radius * 0.025))
    local default_hand_min  = math.max(2, math.floor(radius * 0.016))
    local hand_width_hour = style_opts.hand_width_hour or default_hand_hour
    local hand_width_min  = style_opts.hand_width_min or default_hand_min

    local BLACK = Blitbuffer.COLOR_BLACK
    local LIGHT_GRAY = Blitbuffer.Color8(0xA0)

    local t = os.date("*t", now)
    local hour = t.hour % 12
    local min  = t.min

    local widget = {}
    widget.dimen = Geom:new { x = 0, y = 0, w = sw, h = sh }

    function widget:getSize()
        return Geom:new { w = sw, h = sh }
    end

    -- Cache static geometry to save CPU cycles
    local bg_cache = nil

    local function buildBgCache(ox, oy)
        bg_cache = { ticks = {}, numerals = {} }
        
        -- Dynamic tick inset and outer radius matching e-ink screens
        local tick_inset_hour = math.max(12, math.floor(radius * 0.07))
        local tick_inset_min  = math.max(6, math.floor(radius * 0.035))
        local outer_ring_inset = math.max(2, math.floor(radius * 0.01))
        local outer_r = radius - outer_ring_inset

        -- 3. Hour markers geometry
        for i = 0, 59 do
            local angle = (i * 6 - 90) * math.pi / 180
            local is_hour_mark = (i % 5 == 0)
            local inner_r = is_hour_mark and (radius - tick_inset_hour) or (radius - tick_inset_min)
            local thickness = is_hour_mark and math.max(2, math.floor(radius * 0.007)) or 1

            table.insert(bg_cache.ticks, {
                x1 = ox + cx + math.floor(math.cos(angle) * inner_r),
                y1 = oy + cy + math.floor(math.sin(angle) * inner_r),
                x2 = ox + cx + math.floor(math.cos(angle) * outer_r),
                y2 = oy + cy + math.floor(math.sin(angle) * outer_r),
                t = thickness
            })
        end

        -- 4. Numerals geometry (scaled and positioned inside ticks with safety margin)
        if numerals ~= "none" then
            local roman = {"XII","I","II","III","IV","V","VI","VII","VIII","IX","X","XI"}
            -- Inset numerals: ticks end at radius - tick_inset_hour, so put numerals at radius * 0.73
            local num_r = math.floor(radius * 0.73)
            -- Numeral font size scaled as 9.5% of radius
            local num_font_size = math.max(12, math.floor(radius * 0.095))
            local num_face = Font:getFace("infofont", num_font_size)
            for i = 1, 12 do
                local angle = ((i * 30) - 90) * math.pi / 180
                local nx = ox + cx + math.floor(math.cos(angle) * num_r)
                local ny = oy + cy + math.floor(math.sin(angle) * num_r)
                local label = numerals == "roman" and roman[i] or tostring(i)
                
                local tw = TextWidget:new {
                    text = label, face = num_face, fgcolor = BLACK,
                }
                local tsz = tw:getSize()
                table.insert(bg_cache.numerals, {
                    widget = tw,
                    x = nx - math.floor(tsz.w / 2),
                    y = ny - math.floor(tsz.h / 2)
                })
            end
        end
    end

    function widget:free()
        if bg_cache then
            for _, num in ipairs(bg_cache.numerals) do
                num.widget:free()
            end
            bg_cache = nil
        end
    end

    function widget:paintTo(bb, ox, oy)
        if not bg_cache then buildBgCache(ox, oy) end

        -- 1. Outer circle ring
        local ring_thickness = math.max(2, math.floor(radius * 0.007))
        bb:paintCircle(ox + cx, oy + cy, radius, BLACK, ring_thickness)
        -- 2. Inner circle (subtle)
        local inner_circle_r = radius - math.max(4, math.floor(radius * 0.015))
        bb:paintCircle(ox + cx, oy + cy, inner_circle_r, LIGHT_GRAY, 1)

        -- 3. Hour markers
        for _, t in ipairs(bg_cache.ticks) do
            drawThickLine(bb, t.x1, t.y1, t.x2, t.y2, t.t, BLACK)
        end

        -- 4. Numerals
        for _, num in ipairs(bg_cache.numerals) do
            num.widget:paintTo(bb, num.x, num.y)
        end

        -- 5. Hour hand
        local hour_angle = ((hour + min / 60) * 30 - 90) * math.pi / 180
        local hour_len = math.floor(radius * 0.55)
        local hx = ox + cx + math.floor(math.cos(hour_angle) * hour_len)
        local hy = oy + cy + math.floor(math.sin(hour_angle) * hour_len)
        drawThickLine(bb, ox + cx, oy + cy, hx, hy, hand_width_hour, BLACK)

        -- 6. Minute hand
        local min_angle = (min * 6 - 90) * math.pi / 180
        local min_len = math.floor(radius * 0.78)
        local mx = ox + cx + math.floor(math.cos(min_angle) * min_len)
        local my = oy + cy + math.floor(math.sin(min_angle) * min_len)
        drawThickLine(bb, ox + cx, oy + cy, mx, my, hand_width_min, BLACK)

        -- 7. Centre dot
        local center_dot_r = math.max(5, math.floor(radius * 0.03))
        bb:paintCircle(ox + cx, oy + cy, center_dot_r, BLACK)
    end

    return widget
end

--- Render mini-info text at the bottom of the analog clock
-- @param now      number   os.time()
-- @param sw       number   screen width
-- @param sh       number   screen height
-- @param infos    table    list of info IDs to show: "date", "battery", "memory", "worldclock_nyc"
-- @param font_face         font face for the info text
-- @return widget  a TextBoxWidget with the combined info text
function ClockStyles.renderAnalogInfoBar(now, sw, sh, infos, font_face)
    local StatusUtils = require("statusutils")
    local parts = {}

    for _, info_id in ipairs(infos or {"battery"}) do
        if info_id == "date" then
            table.insert(parts, TimeUtils.getDateText(now, true))
        elseif info_id == "battery" then
            table.insert(parts, StatusUtils.getBatteryText("percent"))
        elseif info_id == "memory" then
            local mem = StatusUtils.getMemoryStatusText()
            if mem and mem ~= "" then table.insert(parts, mem) end
        elseif info_id == "worldclock_nyc" then
            -- NYC = UTC-5 (EST) / UTC-4 (EDT)
            -- Simple approach: assume UTC offset -5 (EST). DST is complex.
            local utc_now = os.time(os.date("!*t", now))
            local nyc_offset = -5 * 3600  -- EST
            local nyc_time = utc_now + nyc_offset
            local nyc_t = os.date("*t", nyc_time)
            table.insert(parts, string.format("NYC %02d:%02d", nyc_t.hour, nyc_t.min))
        end
    end

    local text = table.concat(parts, "  ·  ")
    if text == "" then text = " " end

    return RenderUtils.createSpriteWidget {
        text = text,
        face = font_face,
        width = sw,
        alignment = "center",
    }
end

-- =========================================================================
-- STYLE: OUTLINED TEXT
-- Text drawn with a thick outline for readability over complex backgrounds.
-- =========================================================================

function ClockStyles.renderOutlinedTimeWidget(now, sw, font_face, clock_format, outline_px)
    outline_px = outline_px or 3
    local time_text = TimeUtils.getTimeText(now, clock_format)

    local inner = RenderUtils.createSpriteWidget {
        text = time_text, face = font_face, width = sw,
        alignment = "center", bold = true,
    }

    local widget = {}
    widget.text = time_text
    widget.dimen = Geom:new { x = 0, y = 0, w = sw, h = inner:getSize().h + outline_px * 2 }

    function widget:getSize()
        return Geom:new { w = sw, h = inner:getSize().h + outline_px * 2 }
    end

    function widget:setText(new_text)
        self.text = new_text
        inner:setText(new_text)
        self.dimen.h = inner:getSize().h + outline_px * 2
    end

    function widget:free()
        inner:free()
    end

    function widget:paintTo(bb, x, y)
        local offsets = {}
        for dx = -outline_px, outline_px do
            for dy = -outline_px, outline_px do
                if dx ~= 0 or dy ~= 0 then
                    table.insert(offsets, { dx, dy })
                end
            end
        end

        for _, off in ipairs(offsets) do
            inner:paintTo(bb, x + off[1], y + outline_px + off[2])
        end

        local sz = inner:getSize()
        local rx = x
        local ry = y + outline_px
        bb:invertRect(rx, ry, sz.w, sz.h)
        inner:paintTo(bb, rx, ry)
        bb:invertRect(rx, ry, sz.w, sz.h)
    end

    return widget
end

-- =========================================================================
-- STYLE: WORD CLOCK (French)
-- Spells out the current time in French words.
-- =========================================================================

local UNITS_FR = {
    [0] = "", [1] = "une", [2] = "deux", [3] = "trois", [4] = "quatre",
    [5] = "cinq", [6] = "six", [7] = "sept", [8] = "huit", [9] = "neuf",
    [10] = "dix", [11] = "onze", [12] = "douze", [13] = "treize",
    [14] = "quatorze", [15] = "quinze", [16] = "seize",
}

local TENS_FR = {
    [2] = "vingt", [3] = "trente", [4] = "quarante",
    [5] = "cinquante",
}

local function numberToFrench(n)
    if n == 0 then return "" end
    if n <= 16 then return UNITS_FR[n] end
    if n < 20 then return "dix-" .. UNITS_FR[n - 10] end
    if n < 70 then
        local tens = math.floor(n / 10)
        local units = n % 10
        local base = TENS_FR[tens]
        if units == 0 then return base end
        if units == 1 then return base .. " et un" end
        return base .. "-" .. UNITS_FR[units]
    end
    if n < 80 then
        local units = n - 60
        if units == 11 then return "soixante et onze" end
        return "soixante-" .. numberToFrench(units)
    end
    if n == 80 then return "quatre-vingts" end
    if n < 100 then
        return "quatre-vingt-" .. numberToFrench(n - 80)
    end
    return tostring(n)
end

local function timeToFrenchWords(hour, min)
    local h12 = hour % 12
    if h12 == 0 then h12 = 12 end

    local parts = {}
    table.insert(parts, "Il est")

    if h12 == 1 then
        table.insert(parts, "une heure")
    else
        table.insert(parts, numberToFrench(h12) .. " heures")
    end

    if min == 0 then
        table.insert(parts, "pile")
    elseif min == 15 then
        table.insert(parts, "et quart")
    elseif min == 30 then
        table.insert(parts, "et demie")
    elseif min == 45 then
        table.insert(parts, "moins le quart")
    else
        table.insert(parts, numberToFrench(min))
    end

    return table.concat(parts, "\n")
end

function ClockStyles.renderWordClock(now, sw, font_face)
    local text = ClockStyles.getWordClockText(now)
    return RenderUtils.createSpriteWidget {
        text = text,
        face = font_face,
        width = sw,
        alignment = "center",
    }
end

function ClockStyles.getWordClockText(now)
    local t = os.date("*t", now)
    return timeToFrenchWords(t.hour, t.min)
end

-- =========================================================================
-- DECORATIONS
-- =========================================================================

--- Draw a horizontal decorative separator line.
-- Only draws if there's actual space between elements (no overlap).
function ClockStyles.drawSeparator(bb, x, y, w, style, color)
    color = color or Blitbuffer.COLOR_BLACK
    style = style or "line"

    if style == "line" then
        bb:paintRect(x + 20, y, w - 40, 1, color)
        local cx = x + math.floor(w / 2)
        local diamond_size = 4
        for dy = -diamond_size, diamond_size do
            local dw = diamond_size - math.abs(dy)
            if dw > 0 then
                bb:paintRect(cx - dw, y + dy, dw * 2, 1, color)
            end
        end

    elseif style == "dots" then
        local dot_spacing = 12
        local dot_r = 2
        local start_x = x + 30
        local end_x = x + w - 30
        local px = start_x
        while px <= end_x do
            bb:paintCircle(px, y, dot_r, color)
            px = px + dot_spacing
        end

    elseif style == "diamond" then
        local cx = x + math.floor(w / 2)
        local diamond_size = 5
        for _, offset in ipairs({-30, 0, 30}) do
            local dx = cx + offset
            for dy = -diamond_size, diamond_size do
                local dw = diamond_size - math.abs(dy)
                if dw > 0 then
                    bb:paintRect(dx - dw, y + dy, dw * 2, 1, color)
                end
            end
        end

    elseif style == "ornament" then
        local cx = x + math.floor(w / 2)
        bb:paintCircle(cx, y, 4, color, 1)
        bb:paintCircle(cx, y, 2, color)
        bb:paintRect(x + 40, y, cx - x - 50, 1, color)
        bb:paintRect(cx + 10, y, cx - x - 50, 1, color)
        bb:paintCircle(x + 38, y, 2, color)
        bb:paintCircle(x + w - 38, y, 2, color)
    end
end

--- Draw a decorative border frame around the screen.
function ClockStyles.drawBorderFrame(bb, sw, sh, style, color)
    color = color or Blitbuffer.COLOR_BLACK
    style = style or "simple"

    local margin = 15

    if style == "simple" then
        bb:paintBorder(margin, margin, sw - 2 * margin, sh - 2 * margin, 2, color)

    elseif style == "double" then
        bb:paintBorder(margin, margin, sw - 2 * margin, sh - 2 * margin, 1, color)
        bb:paintBorder(margin + 5, margin + 5, sw - 2 * (margin + 5), sh - 2 * (margin + 5), 1, color)

    elseif style == "corner" then
        local corner_len = 40
        local bw = 2
        bb:paintRect(margin, margin, corner_len, bw, color)
        bb:paintRect(margin, margin, bw, corner_len, color)
        bb:paintRect(sw - margin - corner_len, margin, corner_len, bw, color)
        bb:paintRect(sw - margin - bw, margin, bw, corner_len, color)
        bb:paintRect(margin, sh - margin - bw, corner_len, bw, color)
        bb:paintRect(margin, sh - margin - corner_len, bw, corner_len, color)
        bb:paintRect(sw - margin - corner_len, sh - margin - bw, corner_len, bw, color)
        bb:paintRect(sw - margin - bw, sh - margin - corner_len, bw, corner_len, color)
    end
end

return ClockStyles
