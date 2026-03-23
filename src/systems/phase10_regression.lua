-- Headless checks for recap/metadata/scoreboard seams (run: love . --phase10-regression)

local RunMetadata = require("src.systems.run_metadata")
local MetaRuntime = require("src.systems.meta_runtime")
local run_recap = require("src.states.run_recap")

local M = {}

function M.run()
    local errors = {}

    local function expectEq(actual, expected, label)
        if actual ~= expected then
            errors[#errors + 1] = string.format("%s (got %s, expected %s)", label, tostring(actual), tostring(expected))
        end
    end

    local function expectTrue(cond, label)
        if not cond then
            errors[#errors + 1] = label
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

    -- Boss milestone → summarize bossesKilled
    local mBoss = RunMetadata.new(7, { world_id = "bw", world_name = "BossWorld" })
    RunMetadata.recordBossKilled(mBoss, { actorId = "bossactor", typeId = "ogreboss", name = "Ogre" }, {
        room_id = "boss_room",
        room_name = "Boss Room",
        world_id = "bw",
        room_index = 12,
        total_cleared = 11,
    })
    RunMetadata.finishRun(mBoss, {
        outcome = "victory",
        source = "regression",
        level = 5,
        rooms_cleared = 12,
        gold = 50,
        perks_count = 3,
        total_damage_dealt = mBoss.combat.total_damage_dealt,
        damage_breakdown = mBoss.combat.breakdown,
        build_snapshot = { level = 5, perks = {} },
    })
    local sBoss = MetaRuntime.summarize(mBoss, {})
    expectEq(sBoss.bossesKilled, 1, "summarize bossesKilled after recordBossKilled")

    -- Persist: in-memory export/import round-trip → same summarize totals
    local mPersist = RunMetadata.new(99, { world_id = "p", world_name = "Persist" })
    RunMetadata.recordDamageDealt(mPersist, 22, { magical = true }, {
        amount = 22,
        source_type = "weapon",
        source_id = "slot2",
        packet_kind = "direct_hit",
        family = "magical",
        target_id = "e9",
    })
    RunMetadata.finishRun(mPersist, {
        outcome = "death",
        source = "regression",
        level = 2,
        rooms_cleared = 3,
        gold = 10,
        perks_count = 1,
        total_damage_dealt = mPersist.combat.total_damage_dealt,
        damage_breakdown = mPersist.combat.breakdown,
        build_snapshot = { level = 2, perks = {} },
    })
    local sBefore = MetaRuntime.summarize(mPersist, {})
    local exported = RunMetadata.exportPersistable(mPersist)
    expectTrue(exported ~= nil, "exportPersistable")
    local mImported, impErr = RunMetadata.importPersistable({
        metadata_persistence_version = RunMetadata.METADATA_PERSISTENCE_VERSION,
        payload = exported,
    })
    expectTrue(mImported ~= nil and impErr == nil, "importPersistable memory " .. tostring(impErr))
    local sAfter = MetaRuntime.summarize(mImported, {})
    expectEq(sAfter.totalDamageDealt, sBefore.totalDamageDealt, "persist round-trip totalDamageDealt")
    expectEq(sAfter.damageBreakdown and sAfter.damageBreakdown.magical or 0, sBefore.damageBreakdown and sBefore.damageBreakdown.magical or 0, "persist round-trip magical bucket")
    expectEq(sAfter.roomsCleared, sBefore.roomsCleared, "persist round-trip roomsCleared")

    -- Disk round-trip (requires LOVE filesystem)
    if love and love.filesystem and love.filesystem.write and love.filesystem.load and love.filesystem.remove then
        local path = "phase10_regression_persist_tmp.lua"
        local okSave, saveErr = RunMetadata.saveToFile(path, mPersist)
        expectTrue(okSave, "saveToFile " .. tostring(saveErr))
        local mDisk, loadErr = RunMetadata.loadFromFile(path)
        expectTrue(mDisk ~= nil and loadErr == nil, "loadFromFile " .. tostring(loadErr))
        local sDisk = MetaRuntime.summarize(mDisk, {})
        expectEq(sDisk.totalDamageDealt, sBefore.totalDamageDealt, "disk round-trip totalDamageDealt")
        pcall(love.filesystem.remove, path)
    end

    -- Recap export text: stable header / format line
    local mExport = RunMetadata.new(1, { world_id = "w", world_name = "ExportWorld" })
    RunMetadata.finishRun(mExport, {
        outcome = "death",
        source = "regression",
        level = 1,
        rooms_cleared = 0,
        gold = 0,
        perks_count = 0,
        total_damage_dealt = 0,
        damage_breakdown = mExport.combat.breakdown,
        build_snapshot = { level = 1, perks = {} },
    })
    local summEx = MetaRuntime.summarize(mExport, {})
    local statsEx = { level = 1 }
    local buildEx = {
        stats = {
            armor = 0,
            max_hp = 10,
            luck_pct = 0,
            bullet_damage = 0,
            damage_multiplier_pct = 0,
            crit_chance_pct = 0,
        },
        perks = {},
        weapons = {},
        gear = {},
    }
    local txt = run_recap.buildRunReportText(mExport, summEx, statsEx, buildEx)
    expectTrue(txt and txt:find("Run Recap Export", 1, true), "export report title")
    local fmtLine = string.format(
        "Format v%d | metadata retention policy v%d",
        RunMetadata.RECAP_EXPORT_VERSION,
        RunMetadata.METADATA_RETENTION_VERSION
    )
    expectTrue(txt:find(fmtLine, 1, true), "export format retention line")

    if #errors > 0 then
        return false, table.concat(errors, " | ")
    end
    return true
end

return M
