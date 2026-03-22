local StatRegistry = require("src.data.stat_registry")
local Statuses = require("src.data.statuses")

local ContentValidator = {}

local KNOWN_RARITIES = {
    common = true,
    uncommon = true,
    rare = true,
    legendary = true,
}

local KNOWN_SLOTS = {
    hat = true,
    vest = true,
    boots = true,
    melee = true,
    shield = true,
}

local KNOWN_TAGS = {
    physical = true,
    magical = true,
    true_damage = true,
    burn = true,
    bleed = true,
    shock = true,
    wet = true,
    projectile = true,
    melee = true,
    player = true,
    enemy = true,
    dot = true,
    buildup = true,
}

local KNOWN_TAG_PREFIXES = {
    attack = true,
    weapon = true,
    damage = true,
    status = true,
    set = true,
    boon = true,
    setup = true,
    cc = true,
}

local function fail(content_type, content_id, field, reason)
    error(string.format("[content_validator] %s '%s' invalid field '%s': %s", content_type, tostring(content_id), tostring(field), tostring(reason)), 0)
end

local function validateStatId(content_type, content_id, field, stat_id)
    if not StatRegistry.normalizeId(stat_id) then
        fail(content_type, content_id, field, "unknown stat id '" .. tostring(stat_id) .. "'")
    end
end

local function validateStatMap(content_type, content_id, field, stat_map)
    if type(stat_map) ~= "table" then
        fail(content_type, content_id, field, "expected table")
    end
    for stat_id in pairs(stat_map) do
        validateStatId(content_type, content_id, field, stat_id)
    end
end

local function validateOptionalFileRef(content_type, content_id, field, path)
    if not path then
        return
    end
    if type(path) ~= "string" then
        fail(content_type, content_id, field, "expected string file path")
    end
    if love and love.filesystem and not love.filesystem.getInfo(path) then
        fail(content_type, content_id, field, "missing file '" .. path .. "'")
    end
end

local function validateOptionalTags(content_type, content_id, field, tags)
    if not tags then
        return
    end
    if type(tags) ~= "table" then
        fail(content_type, content_id, field, "expected table")
    end
    for _, tag in ipairs(tags) do
        if type(tag) ~= "string" then
            fail(content_type, content_id, field, "expected string tag")
        end
        local prefix = tag:match("^([%w_%-]+):")
        if not KNOWN_TAGS[tag] and not (prefix and KNOWN_TAG_PREFIXES[prefix]) then
            fail(content_type, content_id, field, "unknown tag '" .. tostring(tag) .. "'")
        end
    end
end

local function validateStatusApplications(content_type, content_id, field, applications)
    if not applications then
        return
    end
    if type(applications) ~= "table" then
        fail(content_type, content_id, field, "expected table")
    end
    for index, app in ipairs(applications) do
        if type(app) ~= "table" then
            fail(content_type, content_id, field, "expected table entry")
        end
        local status_id = app.id
        if not status_id or not Statuses.get(status_id) then
            fail(content_type, content_id, field, "unknown status id at entry " .. tostring(index))
        end
    end
end

local function validateGuns()
    local Guns = require("src.data.guns")
    for _, gun in ipairs(Guns.pool or {}) do
        local id = gun.id or "<missing>"
        if not gun.id then fail("gun", id, "id", "missing id") end
        if not gun.name then fail("gun", id, "name", "missing name") end
        if gun.rarity and not KNOWN_RARITIES[gun.rarity] then
            fail("gun", id, "rarity", "unknown rarity '" .. tostring(gun.rarity) .. "'")
        end
        if type(gun.dropWeight) ~= "number" then
            fail("gun", id, "dropWeight", "expected number")
        end
        if type(gun.baseStats) ~= "table" then
            fail("gun", id, "baseStats", "missing baseStats")
        end
        validateStatMap("gun", id, "baseStats", gun.baseStats)
        validateOptionalFileRef("gun", id, "sprite", gun.sprite and ("assets/weapons/Weapons/" .. gun.sprite) or nil)
        validateOptionalTags("gun", id, "tags", gun.tags)
        validateStatusApplications("gun", id, "status_applications", gun.status_applications)
    end
end

local function validatePerks()
    local Perks = require("src.data.perks")
    for _, perk in ipairs(Perks.pool or {}) do
        local id = perk.id or "<missing>"
        if not perk.id then fail("perk", id, "id", "missing id") end
        if not perk.name then fail("perk", id, "name", "missing name") end
        if type(perk.description) ~= "string" then
            fail("perk", id, "description", "expected string")
        end
        if perk.rarity and not KNOWN_RARITIES[perk.rarity] then
            fail("perk", id, "rarity", "unknown rarity '" .. tostring(perk.rarity) .. "'")
        end
        if type(perk.weight) ~= "number" then
            fail("perk", id, "weight", "expected number")
        end
        if type(perk.apply) ~= "function" then
            fail("perk", id, "apply", "expected function")
        end
        validateOptionalTags("perk", id, "tags", perk.tags)
    end
end

local function validateGear()
    local GearData = require("src.data.gear")
    for _, gear in ipairs(GearData.pool or {}) do
        local id = gear.id or "<missing>"
        if not gear.id then fail("gear", id, "id", "missing id") end
        if not gear.name then fail("gear", id, "name", "missing name") end
        if not KNOWN_SLOTS[gear.slot] then
            fail("gear", id, "slot", "unknown slot '" .. tostring(gear.slot) .. "'")
        end
        if type(gear.tier) ~= "number" then
            fail("gear", id, "tier", "expected number")
        end
        validateStatMap("gear", id, "stats", gear.stats)
        validateOptionalFileRef("gear", id, "tooltip_key", gear.tooltipKey)
        validateOptionalTags("gear", id, "tags", gear.tags)
    end
end

local function validateWeapons()
    local Weapons = require("src.data.weapons")
    for slot, item in pairs(Weapons.defaults or {}) do
        local id = item.id or slot
        if not item.name then
            fail("weapon_default", id, "name", "missing name")
        end
        if item.stats then
            validateStatMap("weapon_default", id, "stats", item.stats)
        end
        if item.icon and item.icon.sheet then
            validateOptionalFileRef("weapon_default", id, "icon.sheet", item.icon.sheet)
        end
    end
end

local function validateBuffs()
    local Buffs = require("src.systems.buffs")
    for id, def in pairs(Buffs._definitions or {}) do
        if type(def.name) ~= "string" then
            fail("buff", id, "name", "expected string")
        end
        if def.statMods then
            validateStatMap("buff", id, "statMods", def.statMods)
        end
        validateOptionalFileRef("buff", id, "icon", def.icon and ((def.isBuff == false and "assets/[VerArc Stash] Basic_Skills_and_Buffs/Debuffs/" or "assets/[VerArc Stash] Basic_Skills_and_Buffs/Buffs/") .. def.icon) or nil)
        validateOptionalTags("buff", id, "tags", def.tags)
    end
end

local function validateStatuses()
    for id, def in pairs(Statuses.definitions or {}) do
        if type(def.name) ~= "string" then
            fail("status", id, "name", "expected string")
        end
        if def.statMods then
            validateStatMap("status", id, "statMods", def.statMods)
        end
        validateOptionalTags("status", id, "tags", def.tags)
    end
end

function ContentValidator.validate_combat_content()
    validateGuns()
    validatePerks()
    validateGear()
    validateWeapons()
    validateBuffs()
    validateStatuses()
    return true
end

function ContentValidator.validate_all()
    return ContentValidator.validate_combat_content()
end

return ContentValidator
