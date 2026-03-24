local CombatEvents = require("src.systems.combat_events")
local DevLog = require("src.ui.devlog")

local DevEventEcho = {}

local function describeStatus(payload)
    local status_id = payload and payload.status_id or "unknown"
    local target_id = payload and payload.target_id or "unknown_target"
    local stacks = payload and payload.stacks or 1
    local remaining = payload and payload.remaining_duration
    if type(remaining) == "number" then
        return string.format("%s target=%s stacks=%s remaining=%.2f", tostring(status_id), tostring(target_id), tostring(stacks), remaining)
    end
    return string.format("%s target=%s stacks=%s", tostring(status_id), tostring(target_id), tostring(stacks))
end

function DevEventEcho.init()
    CombatEvents.subscribe("OnStatusApplied", function(payload)
        DevLog.push("sys", "[status] applied " .. describeStatus(payload))
    end)
    CombatEvents.subscribe("OnStatusRefreshed", function(payload)
        DevLog.push("sys", "[status] refreshed " .. describeStatus(payload))
    end)
    CombatEvents.subscribe("OnStatusExpired", function(payload)
        DevLog.push("sys", "[status] expired " .. describeStatus(payload))
    end)
    CombatEvents.subscribe("OnCleanse", function(payload)
        DevLog.push("sys", "[status] cleanse " .. describeStatus(payload))
    end)
    CombatEvents.subscribe("OnPurge", function(payload)
        DevLog.push("sys", "[status] purge " .. describeStatus(payload))
    end)
    return true
end

return DevEventEcho
