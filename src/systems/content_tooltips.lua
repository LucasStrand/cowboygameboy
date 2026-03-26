local Perks = require("src.data.perks")
local TooltipTemplates = require("src.data.tooltip_templates")

local ContentTooltips = {}

local function shallowCopy(value)
    if type(value) ~= "table" then
        return {}
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

local function splitLines(text)
    local lines = {}
    if type(text) ~= "string" or text == "" then
        return lines
    end
    for line in text:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    if #lines == 0 then
        lines[1] = text
    end
    return lines
end

local function formatTokenValue(value)
    if type(value) == "number" then
        local rounded = math.floor(value * 100 + 0.5) / 100
        if rounded == math.floor(rounded) then
            return tostring(math.floor(rounded))
        end
        return string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
    end
    if value == nil then
        return "?"
    end
    return tostring(value)
end

local function applyTemplate(line, tokens)
    return (line:gsub("{([%w_]+)}", function(key)
        return formatTokenValue(tokens[key])
    end))
end

local function findPerkProcRule(item)
    if type(item.proc_rules) ~= "table" then
        return nil
    end
    return item.proc_rules[1]
end

local function resolvePerkTokens(item)
    local tokens = shallowCopy(item.tooltip_tokens)
    local rule = findPerkProcRule(item)
    if rule and type(rule.counter) == "table" then
        tokens.every_n = tokens.every_n or rule.counter.every_n
    end
    if rule and type(rule.effect) == "table" then
        tokens.delay = tokens.delay or rule.effect.delay
        tokens.damage_scale_pct = tokens.damage_scale_pct or math.floor((rule.effect.damage_scale or 0) * 100 + 0.5)
        tokens.min_damage = tokens.min_damage or rule.effect.min_damage
    end
    return tokens
end

local function resolveGunTokens(item)
    local tokens = shallowCopy(item.tooltip_tokens)
    local stats = item.baseStats or {}
    tokens.cylinder_size = tokens.cylinder_size or stats.cylinderSize
    tokens.reload_speed = tokens.reload_speed or stats.reloadSpeed
    tokens.bullet_damage = tokens.bullet_damage or stats.bulletDamage
    tokens.bullet_count = tokens.bullet_count or stats.bulletCount
    tokens.spread_angle = tokens.spread_angle or stats.spreadAngle
    tokens.shoot_cooldown = tokens.shoot_cooldown or stats.shootCooldown
    tokens.melee_damage = tokens.melee_damage or stats.meleeDamage
    tokens.melee_range = tokens.melee_range or stats.meleeRange
    tokens.melee_cooldown = tokens.melee_cooldown or stats.meleeCooldown
    tokens.melee_knockback = tokens.melee_knockback or stats.meleeKnockback
    return tokens
end

local function resolveGearTokens(item)
    local tokens = shallowCopy(item.tooltip_tokens)
    local stats = item.stats or {}
    tokens.max_hp = tokens.max_hp or stats.maxHP
    tokens.armor = tokens.armor or stats.armor
    tokens.move_speed = tokens.move_speed or stats.moveSpeed
    tokens.damage_flat = tokens.damage_flat or stats.damage
    if tokens.damage_pct == nil and type(stats.damageMultiplier) == "number" then
        tokens.damage_pct = math.floor(stats.damageMultiplier * 100 + 0.5)
    end
    if tokens.luck_pct == nil and type(stats.luck) == "number" then
        tokens.luck_pct = math.floor(stats.luck * 100 + 0.5)
    end
    tokens.melee_damage = tokens.melee_damage or stats.meleeDamage
    tokens.melee_range = tokens.melee_range or stats.meleeRange
    tokens.melee_cooldown = tokens.melee_cooldown or stats.meleeCooldown
    tokens.melee_knockback = tokens.melee_knockback or stats.meleeKnockback
    return tokens
end

local function resolveStatusTokens(item)
    local tokens = shallowCopy(item.tooltip_tokens)
    tokens.duration = tokens.duration or item.duration or item.base_duration
    tokens.max_stacks = tokens.max_stacks or item.max_stacks
    tokens.tick_interval = tokens.tick_interval or item.tick_interval
    return tokens
end

local function resolveOfferTokens(item)
    return shallowCopy(item.tooltip_tokens)
end

local function resolveAttackProfileTokens(item)
    local tokens = shallowCopy(item.tooltip_tokens)
    tokens.base_min = tokens.base_min or item.base_min
    tokens.base_max = tokens.base_max or item.base_max
    tokens.family = tokens.family or item.family
    return tokens
end

function ContentTooltips.getLines(content_type, item, runtime_ctx)
    local _ = runtime_ctx
    if type(item) ~= "table" then
        return {}
    end

    if type(item.tooltip_override) == "string" and item.tooltip_override ~= "" then
        return splitLines(item.tooltip_override)
    end

    local tooltip_key = item.tooltip_key
    if type(tooltip_key) == "string" and TooltipTemplates.has(tooltip_key) then
        local tokens
        if content_type == "gun" then
            tokens = resolveGunTokens(item)
        elseif content_type == "gear" then
            tokens = resolveGearTokens(item)
        elseif content_type == "status" then
            tokens = resolveStatusTokens(item)
        elseif content_type == "offer" then
            tokens = resolveOfferTokens(item)
        elseif content_type == "attack_profile" then
            tokens = resolveAttackProfileTokens(item)
        else
            tokens = resolvePerkTokens(item)
        end
        local lines = {}
        for _, line in ipairs(TooltipTemplates.get(tooltip_key)) do
            lines[#lines + 1] = applyTemplate(line, tokens)
        end
        return lines
    end

    if type(item.description) == "string" then
        return splitLines(item.description)
    end

    return {}
end

function ContentTooltips.getJoinedText(content_type, item, runtime_ctx)
    return table.concat(ContentTooltips.getLines(content_type, item, runtime_ctx), "\n")
end

function ContentTooltips.getPerkNames(player)
    local names = {}
    for _, perk_id in ipairs((player and player.perks) or {}) do
        local perk = Perks.getById and Perks.getById(perk_id) or nil
        names[#names + 1] = perk and perk.name or perk_id
    end
    return names
end

return ContentTooltips
