-- Headless checks for actor defense seam, attack profiles, enemy proc path (run: love . --phase11-actor-regression)

local AttackPacketBuilder = require("src.systems.attack_packet_builder")
local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local ProcRuntime = require("src.systems.proc_runtime")
local SourceRef = require("src.systems.source_ref")

local M = {}

function M.run()
    local errors = {}

    local function expect(cond, label)
        if not cond then
            errors[#errors + 1] = label
        end
    end

    CombatEvents.clear()
    DamageResolver._secondary_jobs = {}

    do
        local mock_enemy = {
            actorId = "e_armor_test",
            isEnemy = true,
            get_defense_state = function()
                return {
                    armor = 100,
                    magic_resist = 0,
                    armor_shred = 0,
                    magic_shred = 0,
                    incoming_damage_mul = 1,
                    incoming_physical_mul = 1,
                    incoming_magical_mul = 1,
                    block_damage_mul = 1,
                }
            end,
            applyResolvedDamage = function(_, result)
                return true, result.final_damage or 0, false
            end,
        }

        local packet = DamagePacket.new({
            kind = "direct_hit",
            family = "physical",
            base_min = 100,
            base_max = 100,
            can_crit = false,
            counts_as_hit = true,
            source = SourceRef.new({
                owner_actor_id = "p_test",
                owner_source_type = "test_weapon",
                owner_source_id = "test",
            }),
            snapshot_data = {
                source_context = {
                    base_min = 100,
                    base_max = 100,
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
                source_context_kind = "snapshot_only",
            },
        })

        local r = DamageResolver.resolve_direct_hit({
            packet = packet,
            source_actor = nil,
            target_actor = mock_enemy,
            target_kind = "enemy",
        })
        expect(r.applied and r.final_damage == 50, "defense_state armor mitigation (expected 50 final vs 100 armor)")
    end

    DamageResolver._secondary_jobs = {}
    CombatEvents.clear()

    do
        local player = {
            actorId = "p_proc_test",
            isPlayer = true,
            get_defense_state = function()
                return {
                    armor = 0,
                    magic_resist = 0,
                    armor_shred = 0,
                    magic_shred = 0,
                    incoming_damage_mul = 1,
                    incoming_physical_mul = 1,
                    incoming_magical_mul = 1,
                    block_damage_mul = 1,
                }
            end,
            applyResolvedDamage = function(_, result)
                return true, result.final_damage or 0, false
            end,
            getProcRules = function()
                return {}
            end,
        }

        local enemy = {
            actorId = "e_proc_test",
            isEnemy = true,
            damage = 10,
            contact_attack_id = "atk_phase11_proc_ping",
            typeId = "regression_enemy",
        }

        ProcRuntime.init(player)

        local packet = AttackPacketBuilder.build_enemy_hit(enemy, "contact")
        packet.target_id = player.actorId

        DamageResolver.resolve_direct_hit({
            packet = packet,
            source_actor = enemy,
            target_actor = player,
            target_kind = "player",
        })

        local executed = DamageResolver.processSecondaryJobs({
            dt = 1,
            player = player,
            enemies = {},
        })
        expect(#executed >= 1, "enemy attack_profile proc should enqueue secondary hit")
        if executed[1] then
            expect((executed[1].result.final_damage or 0) >= 2, "proc secondary should apply min_damage")
        end
    end

    if #errors > 0 then
        return false, table.concat(errors, " | ")
    end
    return true
end

return M
