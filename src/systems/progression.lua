local Perks = require("src.data.perks")
local RewardRuntime = require("src.systems.reward_runtime")

local Progression = {}

function Progression.rollLevelUpPerks(player, context)
    local rewards = RewardRuntime.rollLevelUpChoices(player, context)
    if rewards and #rewards > 0 then
        return rewards
    end
    return Perks.rollPerks(3, player.stats.luck)
end

function Progression.applyPerk(player, perk)
    player:applyPerk(perk)
end

function Progression.getXPProgress(player)
    return player.xp / player.xpToNext
end

return Progression
