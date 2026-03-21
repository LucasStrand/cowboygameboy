-- One-way thin platforms: pass through when moving upward or entirely below the top surface.
-- Thick floors (oneWay == false) always use solid collision.

local PlatformCollision = {}

function PlatformCollision.shouldPassThroughOneWay(item, plat)
    if not plat.oneWay then
        return false
    end
    -- Moving upward: always pass through
    if (item.vy or 0) < 0 then return true end
    -- Feet still inside or below the platform top: player is mid-pass-through, keep ignoring
    if item.y + item.h > plat.y then return true end
    return false
end

return PlatformCollision
