local SourceRef = require("src.systems.source_ref")

local DamagePacket = {}

local KNOWN_FAMILIES = {
    physical = true,
    magical = true,
    true = true,
    true_damage = true,
}

local function cloneArray(list)
    local out = {}
    for i, value in ipairs(list or {}) do
        out[i] = value
    end
    return out
end

function DamagePacket.new(spec)
    spec = spec or {}
    local family = spec.family or "physical"
    if not KNOWN_FAMILIES[family] then
        error("[damage_packet] unknown family '" .. tostring(family) .. "'", 0)
    end

    return {
        kind = spec.kind or "direct_hit",
        family = family,
        amount = spec.amount or 0,
        source = SourceRef.new(spec.source or {}),
        tags = cloneArray(spec.tags),
        can_crit = spec.can_crit ~= false,
        counts_as_hit = spec.counts_as_hit ~= false,
        can_trigger_proc = spec.can_trigger_proc ~= false,
        snapshot = spec.snapshot,
        target_id = spec.target_id,
        metadata = spec.metadata or {},
    }
end

return DamagePacket
