local Device = require("device")
local PluginShare = require("pluginshare")
local logger = require("logger")

local SystemUtils = {}

-- ---------------------------------------------------------------------------
-- AutoSuspend Management
-- ---------------------------------------------------------------------------
-- Instead of fighting KOReader's AutoSuspend, we work WITH it.
-- We save the original timeout and restore it on close.
-- We never set it to 1 second (that caused the death spiral).
-- ---------------------------------------------------------------------------

function SystemUtils.setAutoSuspend(seconds)
    local autosuspend = PluginShare.live_autosuspend
    if autosuspend then
        -- Save the timeout for later restoration if we haven't saved it yet
        if not SystemUtils._original_auto_suspend_timeout then
            SystemUtils._original_auto_suspend_timeout = autosuspend.auto_suspend_timeout_seconds
        end

        autosuspend.auto_suspend_timeout_seconds = seconds
        G_reader_settings:saveSetting("auto_suspend_timeout_seconds", seconds)

        if type(autosuspend._unschedule) == "function" then
            autosuspend:_unschedule()
        end
        if seconds > 0 and type(autosuspend._start) == "function" then
            autosuspend:_start()
        end

        if Device:isKindle() then
            if type(autosuspend._unschedule_kindle) == "function" then
                autosuspend:_unschedule_kindle()
            end
            if type(autosuspend._start_kindle) == "function" then
                autosuspend:_start_kindle()
            end
        end
    end
end

--- Restore AutoSuspend to its original value before the clock was opened.
function SystemUtils.restoreAutoSuspend()
    if SystemUtils._original_auto_suspend_timeout then
        SystemUtils.setAutoSuspend(SystemUtils._original_auto_suspend_timeout)
        SystemUtils._original_auto_suspend_timeout = nil
    end
end

-- ---------------------------------------------------------------------------
-- Frontlight Management
-- ---------------------------------------------------------------------------

function SystemUtils.hasFrontlight()
    if not Device:hasFrontlight() then return false end
    local powerd = Device:getPowerDevice()
    return powerd ~= nil and type(powerd.setIntensity) == "function"
end

function SystemUtils.getBrightness()
    if not SystemUtils.hasFrontlight() then return nil end
    local powerd = Device:getPowerDevice()
    if type(powerd.isFrontlightOn) == "function" and not powerd:isFrontlightOn() then
        return 0
    end
    return powerd.fl_intensity
end

function SystemUtils.setBrightness(level)
    if not SystemUtils.hasFrontlight() or not level then return end
    local powerd = Device:getPowerDevice()
    if level <= 0 then
        if type(powerd.turnOffFrontlight) == "function" then
            powerd:turnOffFrontlight()
        end
        return
    end
    local max_intensity = powerd.fl_max or 24
    if level > max_intensity then level = max_intensity end
    powerd:setIntensity(level)
end

-- ---------------------------------------------------------------------------
-- Wake Lock Management
-- ---------------------------------------------------------------------------
-- On Kobo, the wake lock (powerd:turnOnKeepAwake) prevents the kernel from
-- entering deep sleep. We use it ONLY during the brief render phase (~0.5 s)
-- and release it afterwards so the device can naturally enter deep sleep.
-- ---------------------------------------------------------------------------

function SystemUtils.turnOnKeepAwake()
    local powerd = Device:getPowerDevice()
    if powerd and type(powerd.turnOnKeepAwake) == "function" then
        powerd:turnOnKeepAwake()
    end
end

function SystemUtils.turnOffKeepAwake()
    local powerd = Device:getPowerDevice()
    if powerd and type(powerd.turnOffKeepAwake) == "function" then
        powerd:turnOffKeepAwake()
    end
end

-- ---------------------------------------------------------------------------
-- CPU Governor Management
-- ---------------------------------------------------------------------------

local CPUFREQ_GOV_PATH = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

function SystemUtils.getCpuGovernor()
    local f = io.open(CPUFREQ_GOV_PATH, "r")
    if not f then return nil end
    local gov = f:read("*l")
    f:close()
    return gov and gov:match("^%S+")
end

function SystemUtils.setCpuGovernor(governor)
    if not governor then return false end
    local f = io.open(CPUFREQ_GOV_PATH, "w")
    if not f then return false end
    f:write(governor)
    f:close()
    for i = 1, 3 do
        local p = ("/sys/devices/system/cpu/cpu%d/cpufreq/scaling_governor"):format(i)
        local fN = io.open(p, "w")
        if fN then fN:write(governor); fN:close() end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- RTC Alarm & WakeupMgr Integration
-- ---------------------------------------------------------------------------
-- KOReader on Kobo has Device.wakeup_mgr (WakeupMgr) which properly manages
-- the RTC wakealarm sysfs interface. We use it when available to avoid
-- conflicts with KOReader's own alarm management.
--
-- When WakeupMgr is NOT available (older KOReader versions), we fall back to
-- direct sysfs writes, but we take care to not conflict with KOReader's own
-- alarm scheduling.
--
-- Key design principle: We schedule the NEXT alarm AFTER rendering, then let
-- KOReader's AutoSuspend naturally put the device to sleep. When the RTC
-- fires, KOReader's onResume is called, which triggers our clock update.
-- ---------------------------------------------------------------------------

local RTC_WAKEALARM = "/sys/class/rtc/rtc0/wakealarm"

--- Check if WakeupMgr is available on this device.
-- @return boolean
function SystemUtils.hasWakeupMgr()
    return Device.wakeup_mgr ~= nil
end

--- Get the WakeupMgr instance if available.
-- @return table|nil
function SystemUtils.getWakeupMgr()
    return Device.wakeup_mgr
end

--- Schedule a wakeup via WakeupMgr (preferred method on modern KOReader).
-- @param seconds number  Delay in seconds
-- @param callback function  Callback to execute on wakeup
-- @return boolean  true if scheduled successfully
function SystemUtils.scheduleWakeupMgr(seconds, callback)
    local wakeup_mgr = SystemUtils.getWakeupMgr()
    if not wakeup_mgr then return false end

    -- Remove any existing task we scheduled
    if SystemUtils._wakeup_task then
        pcall(function()
            wakeup_mgr:removeTasks(nil, SystemUtils._wakeup_task)
        end)
    end

    SystemUtils._wakeup_task = callback
    SystemUtils._wakeup_scheduled = true

    -- addTask(seconds, callback) schedules a wakeup in `seconds` seconds
    local ok, err = pcall(function()
        wakeup_mgr:addTask(seconds, callback)
    end)

    if not ok then
        logger.warn("SystemUtils: WakeupMgr addTask failed:", err)
        SystemUtils._wakeup_scheduled = false
        return false
    end

    logger.dbg("SystemUtils: WakeupMgr scheduled wakeup in", seconds, "seconds")
    return true
end

--- Cancel any previously scheduled WakeupMgr task.
function SystemUtils.cancelWakeupMgr()
    if not SystemUtils._wakeup_scheduled then return end
    local wakeup_mgr = SystemUtils.getWakeupMgr()
    if wakeup_mgr and SystemUtils._wakeup_task then
        pcall(function()
            wakeup_mgr:removeTasks(nil, SystemUtils._wakeup_task)
        end)
    end
    SystemUtils._wakeup_task = nil
    SystemUtils._wakeup_scheduled = false
end

--- Program the RTC alarm directly via sysfs (fallback for older KOReader).
-- @param seconds number  Delay in seconds
-- @return boolean  true if alarm was set successfully
function SystemUtils.setRtcAlarm(seconds)
    if not seconds or seconds <= 0 then return false end
    local sec = math.floor(seconds)

    -- Step 1: Clear existing alarm
    local f = io.open(RTC_WAKEALARM, "w")
    if not f then return false end
    f:write("0\n")
    f:close()

    -- Step 2: Write new alarm as absolute epoch time
    local wake_time = os.time() + sec
    f = io.open(RTC_WAKEALARM, "w")
    if not f then return false end
    f:write(tostring(wake_time) .. "\n")
    f:close()
    return true
end

--- Cancel the RTC alarm (sysfs fallback).
function SystemUtils.clearRtcAlarm()
    local f = io.open(RTC_WAKEALARM, "w")
    if f then
        f:write("0\n")
        f:close()
    end
end

--- Schedule a wakeup using the best available method.
-- Tries WakeupMgr first, falls back to direct sysfs.
-- @param seconds number  Delay in seconds
-- @param callback function|nil  Callback for WakeupMgr (ignored for sysfs)
-- @return boolean
function SystemUtils.scheduleRtcWakeup(seconds, callback)
    -- Try WakeupMgr first (properly integrates with KOReader's power management)
    if callback and SystemUtils.scheduleWakeupMgr(seconds, callback) then
        return true
    end

    -- Fallback to direct sysfs
    logger.dbg("SystemUtils: Falling back to direct sysfs RTC alarm")
    return SystemUtils.setRtcAlarm(seconds)
end

--- Cancel all RTC wakeups (both WakeupMgr and sysfs).
function SystemUtils.cancelRtcWakeup()
    if SystemUtils.hasWakeupMgr() then
        SystemUtils.cancelWakeupMgr()
    else
        SystemUtils.clearRtcAlarm()
    end
end

--- Calculate the number of seconds until the start of the next minute.
-- Used for per-minute clock updates.
-- @param margin number  Extra seconds to add as safety margin (default: 2)
-- @return number  Seconds until next minute boundary + margin
function SystemUtils.secondsUntilNextMinute(margin)
    margin = margin or 2
    local current_sec = tonumber(os.date("%S", os.time()))
    local sec = 60 - current_sec + margin
    if sec < 15 then
        sec = sec + 60
    end
    return sec
end

return SystemUtils
