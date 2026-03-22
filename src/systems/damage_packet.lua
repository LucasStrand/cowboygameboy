local SourceRef = require("src.systems.source_ref")

local DamagePacket = {}

local KNOWN_FAMILIES = {
    physical = true,
    magical = true,
    ["true"] = true,
    true_damage = true,
}

local function cloneArray(list)
    local out = {}
    for i, value in ipairs(list or {}) do
        out[i] = value
    end
    return out
end

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneTable(v)
    end
    return copy
end

function DamagePacket.new(spec)
    spec = spec or {}
    local family = spec.family or spec.damage_family or "physical"
    if family == "true_damage" then
        family = "true"
    end
    if not KNOWN_FAMILIES[family] then
        error("[damage_packet] unknown family '" .. tostring(family) .. "'", 0)
    end

    local amount = spec.amount
    local base_min = spec.base_min
    local base_max = spec.base_max
    if amount ~= nil then
        base_min = amount
        base_max = amount
    end
    if base_min == nil then
        base_min = 0
    end
    if base_max == nil then
        base_max = base_min
    end
    if base_max < base_min then
        base_min, base_max = base_max, base_min
    end

    return {
        kind = spec.kind or spec.packet_kind or "direct_hit",
        family = family,
        amount = amount or base_min,
        base_min = base_min,
        base_max = base_max,
        source = SourceRef.new(spec.source or spec.source_ref or {}),
        tags = cloneArray(spec.tags or spec.damage_tags),
        can_crit = spec.can_crit ~= false,
        counts_as_hit = spec.counts_as_hit ~= false,
        can_trigger_on_hit = spec.can_trigger_on_hit ~= false,
        can_trigger_proc = spec.can_trigger_proc ~= false,
        can_lifesteal = spec.can_lifesteal ~= false,
        allow_zero_damage = spec.allow_zero_damage == true,
        snapshots = spec.snapshots ~= false,
        proc_depth = spec.proc_depth or 0,
        snapshot_data = cloneTable(spec.snapshot_data or spec.snapshot),
        target_id = spec.target_id,
        status_applications = cloneTable(spec.status_applications or {}),
        metadata = cloneTable(spec.metadata or {}),
    }
end

return DamagePacket
