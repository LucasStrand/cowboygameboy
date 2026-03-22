local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
local PerkCard = require("src.ui.perk_card")
local BlurBG = require("src.ui.blur_bg")
local Cursor = require("src.ui.cursor")
local game = require("src.states.game")
local Sfx = require("src.systems.sfx")
local RewardRuntime = require("src.systems.reward_runtime")
local RunMetadata = require("src.systems.run_metadata")
local DevLog = require("src.ui.devlog")

local levelup = {}

local perks = {}
local player = nil
local hoveredIndex = nil
local callback = nil

function levelup:enter(_, _player, _callback)
    player = _player
    callback = _callback
    perks = Progression.rollLevelUpPerks(player, {
        run_metadata = player and player.runMetadata or nil,
        source = "levelup",
    })
    hoveredIndex = nil
    Cursor.setDefault()
    Sfx.play("level_up")
    if player and player.runMetadata then
        local profile = RewardRuntime.buildProfile(player, { source = "levelup" })
        DevLog.push("sys", "[reward] levelup profile: " .. RewardRuntime.describeProfile(profile))
        for i, perk in ipairs(perks or {}) do
            DevLog.push("sys", string.format(
                "[reward] levelup %d: %s [%s/%s] %s",
                i,
                tostring(perk.name),
                tostring(perk.reward_bucket or "unknown"),
                tostring(perk.reward_role or "power"),
                tostring(perk.reward_reason or "no reason")
            ))
        end
    end
end

function levelup:update(dt)
    local mx, my = windowToGame(love.mouse.getPosition())
    hoveredIndex = PerkCard.getHovered(perks, mx, my)
end

function levelup:keypressed(key)
    local num = tonumber(key)
    if num and num >= 1 and num <= #perks then
        selectPerk(num)
    end
end

function levelup:mousepressed(x, y, button)
    if button == 1 and hoveredIndex then
        selectPerk(hoveredIndex)
    end
end

function selectPerk(index)
    local perk = perks[index]
    if perk then
        Sfx.play("ui_confirm")
        Progression.applyPerk(player, perk)
        if player and player.runMetadata then
            local profile = RewardRuntime.buildProfile(player, { source = "levelup_choice" })
            RewardRuntime.recordChoice(player.runMetadata, {
                kind = "levelup_choice",
                source = "levelup",
                chosen = {
                    id = perk.id,
                    name = perk.name,
                    reward_bucket = perk.reward_bucket,
                    reward_role = perk.reward_role,
                },
                offers = perks,
                build_snapshot = RunMetadata.snapshotBuild(player, profile),
            })
        end
        Gamestate.pop()
        if callback then
            callback()
        end
    end
end

function levelup:draw()
    BlurBG.drawBlurredGame(game)
    -- Lighten readabilty over the blurred gameplay
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
    love.graphics.setColor(1, 1, 1, 1)
    PerkCard.draw(perks, nil, hoveredIndex)
end

return levelup
