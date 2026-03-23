local PROJECT_ROOT = [[C:\Users\9914k\Dev\Cowboygamejam\cowboygameboy]]
local OUTPUT_PATH = PROJECT_ROOT .. [[\tmp\status_runtime_harness_output.txt]]

package.path = table.concat({
    PROJECT_ROOT .. [[\?.lua]],
    PROJECT_ROOT .. [[\?\init.lua]],
    package.path,
}, ";")

local lines = {}
local failures = {}
local event_log = {}

local function log(msg)
    lines[#lines + 1] = tostring(msg)
end

local function assertCase(name, condition, detail)
    if condition then
        log("[assert] PASS " .. name)
    else
        local message = "[assert] FAIL " .. name .. (detail and (" :: " .. detail) or "")
        log(message)
        failures[#failures + 1] = message
    end
end

DEBUG = true
function debugLog(msg)
    log("[debug] " .. tostring(msg))
end

local CombatEvents = require("src.systems.combat_events")
local Buffs = require("src.systems.buffs")
local GameRng = require("src.systems.game_rng")
local SourceRef = require("src.systems.source_ref")

local function subscribe(name)
    CombatEvents.subscribe(name, function(payload)
        event_log[#event_log + 1] = {
            name = name,
            payload = payload,
        }
        local status_id = payload and payload.status_id or "nil"
        local reason = payload and payload.reason or ""
        log(string.format("[event] %s status=%s reason=%s", tostring(name), tostring(status_id), tostring(reason)))
    end)
end

subscribe("status_applied")
subscribe("status_refreshed")
subscribe("status_stacked")
subscribe("status_ticked")
subscribe("status_removed")
subscribe("status_expired")

local function resetRuntime(seed)
    CombatEvents.clear()
    event_log = {}
    subscribe("status_applied")
    subscribe("status_refreshed")
    subscribe("status_stacked")
    subscribe("status_ticked")
    subscribe("status_removed")
    subscribe("status_expired")
    GameRng.setCurrent(GameRng.new(seed or 12345))
end

local function countEvents(name, status_id)
    local total = 0
    for _, entry in ipairs(event_log) do
        if entry.name == name and (status_id == nil or (entry.payload and entry.payload.status_id == status_id)) then
            total = total + 1
        end
    end
    return total
end

local function findLastEvent(name, status_id)
    for i = #event_log, 1, -1 do
        local entry = event_log[i]
        if entry.name == name and (status_id == nil or (entry.payload and entry.payload.status_id == status_id)) then
            return entry.payload
        end
    end
    return nil
end

local function makeActor(id, defense_kind)
    local actor = {
        actorId = id,
        typeId = id,
        name = id,
        hp = 100,
        armor = defense_kind == "enemy" and 10 or 0,
        statuses = nil,
        resolved_hits = {},
        getEffectiveStats = function()
            return {
                armor = defense_kind == "player" and 20 or 0,
                magicResist = 10,
                blockReduction = 0,
            }
        end,
        applyResolvedDamage = function(self, result, _, packet)
            self.hp = self.hp - (result.final_damage or 0)
            self.resolved_hits[#self.resolved_hits + 1] = {
                result = result,
                packet = packet,
            }
            return true, result.final_damage or 0, self.hp <= 0
        end,
    }
    return actor
end

local function newTracker(owner_actor, owner_kind)
    owner_actor.statuses = Buffs.newTracker(
        SourceRef.new({
            owner_actor_id = owner_actor.actorId,
            owner_source_type = "debug_tool",
            owner_source_id = "status_harness",
        }),
        {
            owner_actor = owner_actor,
            owner_actor_id = owner_actor.actorId,
            owner_kind = owner_kind,
        }
    )
    return owner_actor.statuses
end

local function sourceContext(base, family)
    return {
        base_min = base,
        base_max = base,
        damage = 1,
        physical_damage = family == "physical" and 0 or 0,
        magical_damage = family == "magical" and 0 or 0,
        true_damage = 0,
        crit_chance = 0,
        crit_damage = 1.5,
        armor_pen = 0,
        magic_pen = 0,
    }
end

local function applyStatus(tracker, status_id, spec)
    spec = spec or {}
    spec.id = status_id
    spec.source = spec.source or SourceRef.new({
        owner_actor_id = "source_actor",
        owner_source_type = "debug_tool",
        owner_source_id = "status_harness:" .. status_id,
    })
    return Buffs.applyStatus(tracker, spec)
end

local function scenarioTickPacing()
    log("== scenario: bleed / burn tick pacing ==")
    resetRuntime(101)
    local actor = makeActor("tick_target", "player")
    local tracker = newTracker(actor, "player")

    applyStatus(tracker, "bleed", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        snapshot_data = {
            tick_damage = 4,
            tick_damage_per_stack = true,
            family = "physical",
            source_context = sourceContext(4, "physical"),
        },
    })
    applyStatus(tracker, "burn", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        snapshot_data = {
            tick_damage = 6,
            tick_damage_per_stack = true,
            family = "magical",
            source_context = sourceContext(6, "magical"),
        },
    })

    Buffs.update(tracker, 0.49, { owner_actor = actor, target_kind = "player" })
    assertCase("no bleed tick before 0.5s", countEvents("status_ticked", "bleed") == 0)
    assertCase("no burn tick before 0.5s", countEvents("status_ticked", "burn") == 0)

    Buffs.update(tracker, 0.02, { owner_actor = actor, target_kind = "player" })
    assertCase("bleed ticks at 0.5s pacing", countEvents("status_ticked", "bleed") == 1)
    assertCase("burn ticks at 0.5s pacing", countEvents("status_ticked", "burn") == 1)

    Buffs.update(tracker, 0.49, { owner_actor = actor, target_kind = "player" })
    Buffs.update(tracker, 0.02, { owner_actor = actor, target_kind = "player" })
    assertCase("bleed ticks again at 1.0s pacing", countEvents("status_ticked", "bleed") == 2)
    assertCase("burn ticks again at 1.0s pacing", countEvents("status_ticked", "burn") == 2)
end

local function scenarioShockOverloadAndDR()
    log("== scenario: shock overload + stun DR ==")
    resetRuntime(202)
    local actor = makeActor("shock_target", "enemy")
    local tracker = newTracker(actor, "enemy")

    local shock_spec = {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "enemy" },
        source_actor = { actorId = "caster" },
        snapshot_data = {
            overload_damage = 12,
            overload_stun_duration = 0.8,
            source_context = sourceContext(12, "magical"),
        },
    }

    applyStatus(tracker, "shock", shock_spec)
    applyStatus(tracker, "shock", shock_spec)
    local ok, stun_instance = applyStatus(tracker, "shock", shock_spec)

    assertCase("shock third stack still applies", ok == true)
    assertCase("shock overload consumes shock stacks", Buffs.hasStatus(tracker, "shock") == false)
    assertCase("shock overload applies stun", stun_instance ~= nil and Buffs.hasStatus(tracker, "stun"))
    assertCase("shock overload produced magical payoff hit", actor.resolved_hits[#actor.resolved_hits] and actor.resolved_hits[#actor.resolved_hits].packet.kind == "status_payoff_hit")

    local first_duration = 0
    if Buffs.hasStatus(tracker, "stun") then
        local top = Buffs.getTopStatuses(tracker, 5)
        for _, entry in ipairs(top) do
            if entry.id == "stun" then
                first_duration = entry.remaining_duration
            end
        end
    end
    assertCase("first stun DR duration is base 0.8", math.abs(first_duration - 0.8) < 0.001, tostring(first_duration))

    local _, stun_two = applyStatus(tracker, "stun", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "enemy" },
    })
    assertCase("second stun DR halves duration", stun_two and math.abs(stun_two.remaining_duration - 0.4) < 0.001, stun_two and tostring(stun_two.remaining_duration) or "nil")

    local _, stun_three = applyStatus(tracker, "stun", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "enemy" },
    })
    assertCase("third stun DR quarters duration", stun_three and math.abs(stun_three.remaining_duration - 0.2) < 0.001, stun_three and tostring(stun_three.remaining_duration) or "nil")

    local immune_ok, immune_reason = applyStatus(tracker, "stun", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "enemy" },
    })
    assertCase("fourth stun hits hard-cc immunity", immune_ok == false and immune_reason == "immune", tostring(immune_reason))
end

local function scenarioOrdering()
    log("== scenario: status ordering ==")
    resetRuntime(303)
    local actor = makeActor("ordering_target", "player")
    local tracker = newTracker(actor, "player")

    applyStatus(tracker, "speed_boost", { target_actor = actor, runtime_ctx = { owner_actor = actor, target_kind = "player" } })
    applyStatus(tracker, "wet", { target_actor = actor, runtime_ctx = { owner_actor = actor, target_kind = "player" } })
    applyStatus(tracker, "burn", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        snapshot_data = {
            tick_damage = 5,
            tick_damage_per_stack = true,
            family = "magical",
            source_context = sourceContext(5, "magical"),
        },
    })
    applyStatus(tracker, "stun", { target_actor = actor, runtime_ctx = { owner_actor = actor, target_kind = "player" } })

    local top = Buffs.getTopStatuses(tracker, 5)
    local ids = {}
    for _, entry in ipairs(top) do
        ids[#ids + 1] = entry.id
    end
    log("[ordering] " .. table.concat(ids, ","))
    assertCase("status HUD ordering sorts by visual priority", ids[1] == "stun" and ids[2] == "burn" and ids[3] == "wet" and ids[4] == "speed_boost", table.concat(ids, ","))
end

local function scenarioRemoveOps()
    log("== scenario: remove-op behavior ==")
    resetRuntime(404)
    local actor = makeActor("remove_target", "player")
    local tracker = newTracker(actor, "player")

    applyStatus(tracker, "speed_boost", { target_actor = actor, runtime_ctx = { owner_actor = actor, target_kind = "player" } })
    applyStatus(tracker, "bleed", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        snapshot_data = {
            tick_damage = 4,
            tick_damage_per_stack = true,
            family = "physical",
            source_context = sourceContext(4, "physical"),
        },
    })
    applyStatus(tracker, "shock", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        snapshot_data = {
            overload_damage = 8,
            overload_stun_duration = 0.8,
            source_context = sourceContext(8, "magical"),
        },
    })
    applyStatus(tracker, "stun", { target_actor = actor, runtime_ctx = { owner_actor = actor, target_kind = "player" } })

    local cleanse_removed = Buffs.cleanse(tracker, { negative = true })
    assertCase("cleanse removes negative statuses including hard cc", cleanse_removed == 3, tostring(cleanse_removed))
    assertCase("cleanse leaves positive boons intact", Buffs.hasStatus(tracker, "speed_boost") == true)

    local purge_removed = Buffs.purge(tracker, { positive = true })
    assertCase("purge removes positive boons", purge_removed == 1, tostring(purge_removed))
    assertCase("purge removes speed_boost", Buffs.hasStatus(tracker, "speed_boost") == false)

    applyStatus(tracker, "shock", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        snapshot_data = {
            overload_damage = 8,
            overload_stun_duration = 0.8,
            source_context = sourceContext(8, "magical"),
        },
    })
    local consumed = Buffs.consume(tracker, "shock", "consume")
    local removed_payload = findLastEvent("status_removed", "shock")
    assertCase("consume removes targeted status", consumed == true and Buffs.hasStatus(tracker, "shock") == false)
    assertCase("consume emits status_removed with consume reason", removed_payload and removed_payload.reason == "consume", removed_payload and tostring(removed_payload.reason) or "nil")

    applyStatus(tracker, "wet", {
        target_actor = actor,
        runtime_ctx = { owner_actor = actor, target_kind = "player" },
        duration = 0.1,
    })
    Buffs.update(tracker, 0.11, { owner_actor = actor, target_kind = "player" })
    local expired_payload = findLastEvent("status_expired", "wet")
    assertCase("expire removes timed status", expired_payload ~= nil)
end

local function writeOutput()
    local fh = assert(io.open(OUTPUT_PATH, "w"))
    fh:write(table.concat(lines, "\n"))
    fh:write("\n")
    if #failures == 0 then
        fh:write("SUMMARY: PASS\n")
    else
        fh:write("SUMMARY: FAIL (" .. tostring(#failures) .. ")\n")
    end
    fh:close()
end

function love.load()
    local ok, err = xpcall(function()
        scenarioTickPacing()
        scenarioShockOverloadAndDR()
        scenarioOrdering()
        scenarioRemoveOps()
    end, debug.traceback)

    if not ok then
        log("[fatal] " .. tostring(err))
        failures[#failures + 1] = tostring(err)
    end

    writeOutput()
    love.event.quit(0)
end
