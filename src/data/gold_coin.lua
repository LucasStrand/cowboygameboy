--- World coin pickups: gold pieces (5 wallet gold each) and silver pieces (1 each).
--- Exact totals use splitExact(total) → counts of each coin; no uneven remainders.
local M = {}

M.GOLD_VALUE = 5
M.SILVER_VALUE = 1
--- Alias for chest tables (multiples of gold only).
M.VALUE = M.GOLD_VALUE

--- Exact breakdown: n5 × 5 + n1 × 1 = math.floor(total) for total ≥ 0.
function M.splitExact(total)
    if not total or total <= 0 then return 0, 0 end
    total = math.floor(total + 0.5)
    local n5 = math.floor(total / M.GOLD_VALUE)
    local n1 = total % M.GOLD_VALUE
    return n5, n1
end

--- @deprecated Use splitExact — kept for older call sites.
function M.floorToCoins(total)
    return M.splitExact(total)
end

--- @deprecated Prefer splitExact for enemy drops (exact change).
function M.roundToNearest(total)
    if not total or total <= 0 then return 0 end
    return math.floor((total + M.GOLD_VALUE / 2) / M.GOLD_VALUE) * M.GOLD_VALUE
end

--- Build ordered pickup specs (gold first, then silver). If maxPickups is set, drop extras from the end and return overflow wallet gold.
function M.pickupSpecsForTotal(totalGold, maxPickups)
    local n5, n1 = M.splitExact(totalGold)
    local specs = {}
    for _ = 1, n5 do
        specs[#specs + 1] = { type = "gold", value = M.GOLD_VALUE }
    end
    for _ = 1, n1 do
        specs[#specs + 1] = { type = "silver", value = M.SILVER_VALUE }
    end
    local overflow = 0
    if maxPickups and #specs > maxPickups then
        while #specs > maxPickups do
            local sp = table.remove(specs)
            overflow = overflow + (sp and sp.value or 0)
        end
    end
    return specs, overflow
end

return M
