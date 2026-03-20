local Perks = require("src.data.perks")

local Progression = {}

function Progression.rollLevelUpPerks(player)
    return Perks.rollPerks(3, player.stats.luck)
end

function Progression.applyPerk(player, perk)
    player:applyPerk(perk)
end

function Progression.getXPProgress(player)
    return player.xp / player.xpToNext
end

return Progression
