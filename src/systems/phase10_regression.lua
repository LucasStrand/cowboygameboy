-- Headless checks for recap/metadata/scoreboard seams (run: love . --phase10-regression)

local RunMetadata = require("src.systems.run_metadata")
local MetaRuntime = require("src.systems.meta_runtime")

local M = {}

function M.run()
    local errors = {}

    local function expectEq(actual, expected, label)
        if actual ~= expected then
            errors[#errors + 1] = string.format("%s (got %s, expected %s)", label, tostring(actual), tostring(expected))
        end
    end

    local meta = RunMetadata.new(42, { world_id = "test", world_name = "TestWorld" })
    RunMetadata.recordDamageDealt(meta, 10, { physical = true }, {
        amount = 10,
        source_type = "weapon",
        source_id = "slot1",
        packet_kind = "direct_hit",
        family = "physical",
        target_id = "e1",
    })
    RunMetadata.recordDamageDealt(meta, 5, { explosion = true }, {
        amount = 5,
        source_type = "weapon",
        source_id = "slot1",
        packet_kind = "delayed_secondary_hit",
        family = "physical",
        target_id = "e2",
    })

    RunMetadata.finishRun(meta, {
        outcome = "death",
        source = "regression",
        level = 3,
        rooms_cleared = 7,
        gold = 120,
        perks_count = 2,
        total_damage_dealt = meta.combat.total_damage_dealt,
        damage_breakdown = meta.combat.breakdown,
        dominant_tags = { "burn" },
        visible_buff_count = 1,
        build_snapshot = { level = 3, perks = {} },
    })

    local s = MetaRuntime.summarize(meta, {})
    expectEq(s.totalDamageDealt, 15, "summarize totalDamageDealt")
    expectEq(s.roomsCleared, 7, "summarize roomsCleared")
    expectEq(s.outcome, "death", "summarize outcome")
    expectEq(s.damageBreakdown and s.damageBreakdown.physical or 0, 10, "summarize physical breakdown")
    expectEq(s.damageBreakdown and s.damageBreakdown.explosion or 0, 5, "summarize explosion breakdown")

    for i = 1, 300 do
        RunMetadata.recordDamageDealt(meta, 1, { physical = true }, {
            amount = 1,
            source_type = "weapon",
            source_id = "slot1",
            packet_kind = "direct_hit",
            family = "physical",
            target_id = "t" .. tostring(i),
        })
    end
    local st = RunMetadata.retentionStats(meta)
    expectEq(st.damage_events, 240, "damage_events ring cap")

    local sNil = MetaRuntime.summarize(nil, { outcome = "aborted", roomsCleared = 2 })
    expectEq(sNil.totalDamageDealt, 0, "nil meta totalDamageDealt")
    expectEq(sNil.roomsCleared, 2, "nil meta fallback rooms")

    if #errors > 0 then
        return false, table.concat(errors, " | ")
    end
    return true
end

return M
