local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
local PerkCard = require("src.ui.perk_card")
local BlurBG = require("src.ui.blur_bg")
local Cursor = require("src.ui.cursor")
local Font = require("src.ui.font")
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
local rerollMessage = nil
local hintFont = nil

function levelup:enter(_, _player, _callback)
    player = _player
    callback = _callback
    perks = Progression.rollLevelUpPerks(player, {
        run_metadata = player and player.runMetadata or nil,
        source = "levelup",
    })
    hoveredIndex = nil
    rerollMessage = nil
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
    elseif key == "r" then
        local offers, cost, err = RewardRuntime.reroll("levelup", player, {
            run_metadata = player and player.runMetadata or nil,
            source = "levelup",
            current_offers = perks,
        })
        if offers then
            perks = offers
            hoveredIndex = nil
            rerollMessage = string.format("Rerolled for $%d", cost or 0)
            Sfx.play("ui_confirm")
            local profile = RewardRuntime.buildProfile(player, { source = "levelup_reroll" })
            DevLog.push("sys", "[reward] levelup reroll: " .. RewardRuntime.describeProfile(profile))
        else
            rerollMessage = err or "Not enough gold"
        end
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
    if not hintFont then
        hintFont = Font.new(14)
    end
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.86, 0.82, 0.72, 1)
    love.graphics.printf(
        string.format("Gold: $%d   |   [R] Reroll $%d", player and player.gold or 0, RewardRuntime.getRerollCost("levelup", player and player.runMetadata or nil)),
        0,
        GAME_HEIGHT - 56,
        GAME_WIDTH,
        "center"
    )
    if rerollMessage and rerollMessage ~= "" then
        love.graphics.setColor(0.7, 0.72, 0.78, 1)
        love.graphics.printf(rerollMessage, 0, GAME_HEIGHT - 34, GAME_WIDTH, "center")
    end
end

return levelup
