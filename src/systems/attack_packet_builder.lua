local AttackProfiles = require("src.data.attack_profiles")
local DamagePacket = require("src.systems.damage_packet")
local SourceRef = require("src.systems.source_ref")

local M = {}

local CRIT_DAMAGE_DEFAULT = 1.5

local function neutralSnapshotContext(base)
    return {
        base_min = base,
        base_max = base,
        damage = 1,
        physical_damage = 0,
        magical_damage = 0,
        true_damage = 0,
        crit_chance = 0,
        crit_damage = CRIT_DAMAGE_DEFAULT,
        armor_pen = 0,
        magic_pen = 0,
    }
end

--- @param enemy table Enemy instance (actorId, damage, contact_attack_id / ranged_attack_id)
--- @param delivery string "contact" | "projectile"
function M.build_enemy_hit(enemy, delivery)
    delivery = delivery or "contact"
    local profile_id = (delivery == "projectile") and enemy.ranged_attack_id or enemy.contact_attack_id
    local profile = profile_id and AttackProfiles.get(profile_id) or nil

    local base = enemy.damage or 1
    local family = "physical"
    local tags = { "enemy", "contact" }
    local source_type = "enemy_contact"
    local context_kind = "enemy_contact"
    local can_crit = false
    local counts_as_hit = true
    local can_trigger_on_hit = true
    local can_trigger_proc = true
    local can_lifesteal = false

    if profile then
        family = profile.family or family
        if profile.tags then
            tags = {}
            for i, t in ipairs(profile.tags) do
                tags[i] = t
            end
        end
        can_crit = profile.can_crit == true
        counts_as_hit = profile.counts_as_hit ~= false
        can_trigger_on_hit = profile.can_trigger_on_hit ~= false
        can_trigger_proc = profile.can_trigger_proc ~= false
        can_lifesteal = profile.can_lifesteal == true
        if delivery == "projectile" or profile.delivery == "projectile" then
            source_type = "enemy_projectile"
            context_kind = "enemy_projectile"
        end
        profile_id = profile.id
    else
        if delivery == "projectile" then
            source_type = "enemy_projectile"
            context_kind = "enemy_projectile"
            tags = { "projectile", "enemy" }
        end
        profile_id = enemy.typeId or enemy.name or "enemy"
    end

    local snap = neutralSnapshotContext(base)
    local packet = DamagePacket.new({
        kind = profile and profile.kind or "direct_hit",
        family = family,
        base_min = base,
        base_max = base,
        can_crit = can_crit,
        counts_as_hit = counts_as_hit,
        can_trigger_on_hit = can_trigger_on_hit,
        can_trigger_proc = can_trigger_proc,
        can_lifesteal = can_lifesteal,
        source = SourceRef.new({
            owner_actor_id = enemy.actorId or enemy.typeId or "enemy",
            owner_source_type = source_type,
            owner_source_id = profile_id,
        }),
        tags = tags,
        target_id = nil,
        status_applications = profile and profile.status_applications,
        snapshot_data = {
            source_context = snap,
        },
        metadata = {
            source_context_kind = context_kind,
            source_attack_id = profile_id,
        },
    })

    return packet, profile
end

return M
