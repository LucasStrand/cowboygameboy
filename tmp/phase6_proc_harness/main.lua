local PROJECT_ROOT = [[C:\Users\9914k\Dev\Cowboygamejam\cowboygameboy]]
local OUTPUT_LOG = PROJECT_ROOT .. [[\tmp\phase6_proc_harness_output.txt]]

package.path = table.concat({
    PROJECT_ROOT .. [[\?.lua]],
    PROJECT_ROOT .. [[\?\init.lua]],
    package.path,
}, ";")

DEBUG = true
debugLog = function(_) end

local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local ProcRuntime = require("src.systems.proc_runtime")
local SourceRef = require("src.systems.source_ref")

local lines = {}

local function log(msg)
    lines[#lines + 1] = msg
end

local function newDummy(id, x)
    local target = {
        actorId = id,
        isEnemy = true,
        alive = true,
        x = x,
        y = 100,
        w = 16,
        h = 16,
        hp = 300,
        armor = 0,
        magic_resist = 0,
    }
    function target:applyResolvedDamage(result)
        self.hp = self.hp - result.final_damage
        if self.hp <= 0 then
            self.alive = false
        end
        return true, result.final_damage, not self.alive
    end
    return target
end

local player = {
    actorId = "player",
    isPlayer = true,
    perks = { "phantom_third" },
}

local targetA = newDummy("dummy_a", 80)
local targetB = newDummy("dummy_b", 160)
local enemies = { targetA, targetB }

local observed = {
    direct_hits = 0,
    delayed_hits = 0,
    delayed_onhit_events = 0,
    last_delayed_source_type = nil,
    last_delayed_parent = nil,
}

local function makePacket(source_id, slot_index, target_id)
    return DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        base_min = 10,
        base_max = 10,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        source = SourceRef.new({
            owner_actor_id = player.actorId,
            owner_source_type = "weapon_slot",
            owner_source_id = source_id,
        }),
        target_id = target_id,
        snapshot_data = {
            source_context = {
                base_min = 10,
                base_max = 10,
                damage = 1,
                physical_damage = 0,
                magical_damage = 0,
                true_damage = 0,
                crit_chance = 0,
                crit_damage = 1.5,
                armor_pen = 0,
                magic_pen = 0,
            },
        },
        metadata = {
            source_slot_index = slot_index,
        },
    })
end

local function fire(source_id, slot_index, target)
    local result = DamageResolver.resolve_packet({
        packet = makePacket(source_id, slot_index, target.actorId),
        source_actor = player,
        target_actor = target,
        target_kind = "enemy",
    })
    local secondary = DamageResolver.processSecondaryJobs({
        dt = 0.09,
        enemies = enemies,
        player = player,
    })
    return result, secondary
end

function love.load()
    assert(io.open(PROJECT_ROOT .. [[\assets\weapons\Weapons\ColtSingleActionArmy.png]], "rb")):close()
    CombatEvents.clear()
    ProcRuntime.init(player)

    CombatEvents.subscribe("OnDamageTaken", function(payload)
        if payload.packet_kind == "direct_hit" then
            observed.direct_hits = observed.direct_hits + 1
        elseif payload.packet_kind == "delayed_secondary_hit" then
            observed.delayed_hits = observed.delayed_hits + 1
            observed.last_delayed_source_type = payload.source_ref and payload.source_ref.owner_source_type or "none"
            observed.last_delayed_parent = payload.source_ref and payload.source_ref.parent_source_id or "none"
        end
    end)

    CombatEvents.subscribe("OnHit", function(payload)
        if payload.packet_kind == "delayed_secondary_hit" then
            observed.delayed_onhit_events = observed.delayed_onhit_events + 1
        end
    end)

    local _, secondary1 = fire("revolver", 1, targetA)
    log("hit 1 targetA delayed=" .. tostring(#secondary1))

    local _, secondary2 = fire("revolver", 1, targetA)
    log("hit 2 targetA delayed=" .. tostring(#secondary2))

    local _, secondary3 = fire("revolver", 1, targetA)
    log("hit 3 targetA delayed=" .. tostring(#secondary3))

    local _, secondary4 = fire("revolver", 1, targetB)
    local _, secondary5 = fire("revolver", 1, targetB)
    log("hit 1-2 targetB delayed=" .. tostring(#secondary4 + #secondary5))

    local _, secondary6 = fire("shotgun", 2, targetA)
    local _, secondary7 = fire("shotgun", 2, targetA)
    log("hit 1-2 shotgun targetA delayed=" .. tostring(#secondary6 + #secondary7))

    local _, secondary8 = fire("revolver", 1, targetB)
    log("hit 3 targetB delayed=" .. tostring(#secondary8))

    local _, secondary9 = fire("shotgun", 2, targetA)
    log("hit 3 shotgun targetA delayed=" .. tostring(#secondary9))

    local pass = true
    pass = pass and observed.direct_hits == 9
    pass = pass and observed.delayed_hits == 3
    pass = pass and observed.delayed_onhit_events == 0
    pass = pass and observed.last_delayed_source_type == "perk"
    pass = pass and (observed.last_delayed_parent == "revolver" or observed.last_delayed_parent == "shotgun")

    log("observed direct_hits=" .. tostring(observed.direct_hits))
    log("observed delayed_hits=" .. tostring(observed.delayed_hits))
    log("observed delayed_onhit_events=" .. tostring(observed.delayed_onhit_events))
    log("last delayed source_type=" .. tostring(observed.last_delayed_source_type))
    log("last delayed parent_source_id=" .. tostring(observed.last_delayed_parent))
    log("SUMMARY: " .. (pass and "PASS" or "FAIL"))

    local fh = assert(io.open(OUTPUT_LOG, "w"))
    for _, line in ipairs(lines) do
        fh:write(line, "\n")
    end
    fh:close()
    love.event.quit(pass and 0 or 1)
end
