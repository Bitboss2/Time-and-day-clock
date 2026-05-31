local Device = require("device")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Font = require("ui/font")
local Screen = Device.screen

local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local Blitbuffer = require("ffi/blitbuffer")

local TimeUtils = require("timeutils")
local StatusUtils = require("statusutils")

local RenderUtils = {}

-- =========================================================================
-- GENERIC SPRITE CACHE WIDGET
-- Replaces TextBoxWidget for massive energy savings by never
-- recalculating fonts after the initial render.
-- =========================================================================
function RenderUtils.createSpriteWidget(opts)
    local widget = {
        text = opts.text or "",
        _face = opts.face,
        _sprites = {},
        dimen = Geom:new { x = 0, y = 0, w = opts.width or Screen:getWidth(), h = 0 },
        alignment = opts.alignment or "center",
        bold = opts.bold,
        fgcolor = opts.fgcolor or Blitbuffer.COLOR_BLACK
    }

    function widget:_getSprite(char)
        if not self._sprites[char] then
            if char == " " then char = "_" end
            local tw = TextWidget:new {
                text = char, face = self._face, fgcolor = self.fgcolor, bold = self.bold
            }
            tw:getSize() -- Force render
            self._sprites[char] = tw
        end
        return self._sprites[char]
    end

    -- Get font height (using space or any character sprite size)
    local initial_sprite = widget:_getSprite(" ")
    local font_height = initial_sprite:getSize().h

    -- Set initial height
    local lines = 1
    for _ in widget.text:gmatch("\n") do lines = lines + 1 end
    widget.dimen.h = lines * font_height

    function widget:setText(new_text)
        if self.text == new_text then return end
        self.text = new_text
        local lines = 1
        for _ in self.text:gmatch("\n") do lines = lines + 1 end
        local fh = self:_getSprite(" "):getSize().h
        self.dimen.h = lines * fh
    end

    function widget:getSize()
        return self.dimen
    end

    function widget:free()
        for _, s in pairs(self._sprites) do
            if type(s.free) == "function" then s:free() end
        end
        self._sprites = {}
    end

    function widget:paintTo(bb, x, y)
        local lines = {}
        for line in self.text:gmatch("[^\n]+") do table.insert(lines, line) end
        if #lines == 0 then return end
        
        local fh = self:_getSprite(" "):getSize().h
        local total_h = #lines * fh
        local line_dims = {}
        for _, line in ipairs(lines) do
            local lw = 0
            for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                if char ~= " " then
                    local sprite = self:_getSprite(char)
                    local sz = sprite:getSize()
                    lw = lw + sz.w
                else
                    lw = lw + math.floor(self._face.size / 3)
                end
            end
            table.insert(line_dims, { w = lw, h = fh, text = line })
        end
        
        local start_y = y + math.floor((self.dimen.h - total_h) / 2)
        local cy = start_y
        
        for _, ldim in ipairs(line_dims) do
            local cx = x
            if self.alignment == "center" then
                cx = x + math.floor((self.dimen.w - ldim.w) / 2)
            elseif self.alignment == "right" then
                cx = x + self.dimen.w - ldim.w
            end
            for char in ldim.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                if char ~= " " then
                    local sprite = self:_getSprite(char)
                    sprite:paintTo(bb, cx, cy)
                    cx = cx + sprite:getSize().w
                else
                    cx = cx + math.floor(self._face.size / 3)
                end
            end
            cy = cy + ldim.h
        end
    end

    return widget
end

-- clock_format: "follow" | "24" | "12"  (forwarded to TimeUtils)
function RenderUtils.renderTimeWidget(now, width, font_face, clock_format)
    return RenderUtils.createSpriteWidget {
        text = TimeUtils.getTimeText(now, clock_format),
        face = font_face or Font:getFace("tfont", 119),
        width = width or Screen:getWidth(),
        alignment = "center",
        bold = true,
    }
end

function RenderUtils.renderDateWidget(now, width, font_face, use_locale)
    return RenderUtils.createSpriteWidget {
        text = TimeUtils.getDateText(now, use_locale),
        face = font_face or Font:getFace("infofont", 32),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end

function RenderUtils.renderStatusWidget(width, font_face)
    return RenderUtils.createSpriteWidget {
        text = StatusUtils.getStatusText(),
        face = font_face or Font:getFace("infofont"),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end

function RenderUtils.renderWifiWidget(width, font_face)
    return RenderUtils.createSpriteWidget {
        text = StatusUtils.getWifiStatusText(),
        face = font_face or Font:getFace("infofont", 24),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end

function RenderUtils.renderBatteryWidget(width, font_face, format)
    return RenderUtils.createSpriteWidget {
        text = StatusUtils.getBatteryText(format),
        face = font_face or Font:getFace("infofont", 24),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end

function RenderUtils.renderMemoryWidget(width, font_face)
    return RenderUtils.createSpriteWidget {
        text = StatusUtils.getMemoryStatusText() or "",
        face = font_face or Font:getFace("infofont", 24),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end



return RenderUtils