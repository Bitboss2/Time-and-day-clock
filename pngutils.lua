local Device = require("device")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local PngUtils = {}

function PngUtils.getNativePortraitResolution()
    local screen_size = Screen:getSize()
    local sw, sh = screen_size.w, screen_size.h
    if sw > sh then
        return sh, sw
    end
    return sw, sh
end

function PngUtils.getPngDimensions(filepath)
    local f = io.open(filepath, "rb")
    if not f then
        return nil, nil
    end
    local header = f:read(24)
    f:close()
    if not header or #header < 24 then
        return nil, nil
    end
    local png_sig = "\137PNG\r\n\026\n"
    if header:sub(1, 8) ~= png_sig then
        return nil, nil
    end
    local function read_be_uint32(s, offset)
        local b1, b2, b3, b4 = s:byte(offset, offset + 3)
        return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    end
    local w = read_be_uint32(header, 17)
    local h = read_be_uint32(header, 21)
    return w, h
end

function PngUtils.checkPngResolution(filepath)
    local img_w, img_h = PngUtils.getPngDimensions(filepath)
    if not img_w or not img_h then
        return nil
    end
    local native_w, native_h = PngUtils.getNativePortraitResolution()
    if img_w == native_w and img_h == native_h then
        return "normal"
    elseif img_w == native_h and img_h == native_w then
        return "inverted"
    end
    return nil
end

function PngUtils.isPortraitOrientation()
    local screen_size = Screen:getSize()
    return screen_size.w <= screen_size.h
end

function PngUtils.getImageRotationAngle(resolution_type)
    if not PngUtils.isPortraitOrientation() then
        return 0
    end
    if resolution_type == "inverted" then
        return 90
    end
    return 0
end

return PngUtils