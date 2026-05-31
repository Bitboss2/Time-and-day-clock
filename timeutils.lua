local Datetime = require("frontend/datetime")

local TimeUtils = {}

function TimeUtils.getDateText(now, use_locale)
    return Datetime.secondsToDate(now, use_locale)
end

-- clock_format: "follow" (default), "24", or "12"
function TimeUtils.getTimeText(now, clock_format)
    local twelve_hour
    if clock_format == "24" then
        twelve_hour = false
    elseif clock_format == "12" then
        twelve_hour = true
    else
        -- "follow" or nil: mirror KOReader's own setting
        twelve_hour = G_reader_settings:isTrue("twelve_hour_clock")
    end
    return Datetime.secondsToHour(now, twelve_hour, false)
end

return TimeUtils