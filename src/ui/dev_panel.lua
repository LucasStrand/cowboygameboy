--- Layout + hit-testing for the in-game dev panel (see `game.lua` when DEBUG).
local Perks = require("src.data.perks")
local Guns  = require("src.data.guns")

local DevPanel = {}

local ROW_H = 26
local HEADER_H = 20
local GAP = 4
local PANEL_PAD = 12

local function rowHeader(label)
    return { kind = "header", label = label }
end

local function rowAction(id, label)
    return { kind = "action", id = id, label = label }
end

--- @param showHitboxes boolean|nil current state for the hitbox overlay row label
function DevPanel.buildRows(showHitboxes)
    local rows = {}
    rows[#rows + 1] = rowHeader("Debug")
    rows[#rows + 1] = rowAction(
        "toggle_hitboxes",
        (showHitboxes ~= false) and "Hitboxes: ON" or "Hitboxes: OFF"
    )

    rows[#rows + 1] = rowHeader("Player")
    rows[#rows + 1] = rowAction("kill_player", "Kill player")
    rows[#rows + 1] = rowAction("full_heal", "Full heal")
    rows[#rows + 1] = rowAction("hurt_1", "Hurt 1 HP")
    rows[#rows + 1] = rowAction("toggle_god", "Toggle god mode")

    rows[#rows + 1] = rowHeader("Resources")
    rows[#rows + 1] = rowAction("gold_100", "+$100 gold")
    rows[#rows + 1] = rowAction("gold_500", "+$500 gold")
    rows[#rows + 1] = rowAction("xp_50", "+50 XP")
    rows[#rows + 1] = rowAction("xp_200", "+200 XP")
    rows[#rows + 1] = rowAction("force_levelup", "Open level-up choice")

    rows[#rows + 1] = rowHeader("Room")
    rows[#rows + 1] = rowAction("open_door", "Open exit door")
    rows[#rows + 1] = rowAction("clear_enemies", "Clear all enemies")
    rows[#rows + 1] = rowAction("clear_bullets", "Clear bullets")
    rows[#rows + 1] = rowAction("spawn_bandit", "Spawn bandit (near)")
    rows[#rows + 1] = rowAction("spawn_gunslinger", "Spawn gunslinger (near)")
    rows[#rows + 1] = rowAction("spawn_buzzard", "Spawn buzzard (near)")

    rows[#rows + 1] = rowHeader("Weapons (click to equip)")
    for _, gun in ipairs(Guns.pool) do
        local rarity = gun.rarity and (" [" .. gun.rarity .. "]") or ""
        rows[#rows + 1] = rowAction("gun:" .. gun.id, gun.name .. rarity)
    end

    rows[#rows + 1] = rowHeader("Perks (click to add)")
    for _, perk in ipairs(Perks.pool) do
        rows[#rows + 1] = rowAction("perk:" .. perk.id, perk.name .. "  [" .. perk.id .. "]")
    end

    return rows
end

--- Height of all rows (scrollable content only).
function DevPanel.rowsHeight(rows)
    local h = 0
    for _, row in ipairs(rows) do
        if row.kind == "header" then
            h = h + HEADER_H + GAP
        else
            h = h + ROW_H + GAP
        end
    end
    return h
end

function DevPanel.titleBlockHeight(titleFont)
    return PANEL_PAD + titleFont:getHeight() + 10
end

--- Max scroll so the last row can reach the bottom of the rows viewport.
function DevPanel.maxScroll(rows, titleFont, panelH)
    local rowsH = DevPanel.rowsHeight(rows)
    local titleH = DevPanel.titleBlockHeight(titleFont)
    local viewH = panelH - titleH - PANEL_PAD
    if viewH < 40 then return 0 end
    return math.max(0, rowsH - viewH)
end

--- @return action id string or nil
function DevPanel.hitTest(rows, mx, my, scrollY, px, py, pw, ph, titleFont)
    if mx < px or my < py or mx > px + pw or my > py + ph then
        return nil
    end
    local y = py + DevPanel.titleBlockHeight(titleFont) - scrollY
    for _, row in ipairs(rows) do
        local rh = row.kind == "header" and (HEADER_H + GAP) or (ROW_H + GAP)
        if row.kind == "action" then
            if my >= y and my <= y + ROW_H and mx >= px + PANEL_PAD and mx <= px + pw - PANEL_PAD then
                return row.id
            end
        end
        y = y + rh
    end
    return nil
end

function DevPanel.draw(rows, scrollY, px, py, pw, ph, hoverId, fonts)
    local titleFont = fonts.title
    local rowFont = fonts.row

    love.graphics.setColor(0.06, 0.05, 0.08, 0.92)
    love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)
    love.graphics.setColor(0.55, 0.4, 0.2, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", px, py, pw, ph, 6, 6)
    love.graphics.setLineWidth(1)

    love.graphics.setScissor(px, py, pw, ph)
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.75, 0.25)
    love.graphics.print("DEV", px + PANEL_PAD, py + 8)

    local innerY = py + DevPanel.titleBlockHeight(titleFont) - scrollY
    local x0 = px + PANEL_PAD
    local innerW = pw - 2 * PANEL_PAD

    love.graphics.setFont(rowFont)
    for _, row in ipairs(rows) do
        if row.kind == "header" then
            love.graphics.setColor(0.65, 0.62, 0.58)
            love.graphics.print(row.label, x0, innerY)
            innerY = innerY + HEADER_H + GAP
        else
            local hovered = hoverId == row.id
            if hovered then
                love.graphics.setColor(0.2, 0.16, 0.12, 0.85)
                love.graphics.rectangle("fill", x0 - 4, innerY - 2, innerW + 8, ROW_H, 4, 4)
            end
            love.graphics.setColor(hovered and 1 or 0.82, hovered and 0.95 or 0.78, hovered and 0.7 or 0.62)
            love.graphics.print(row.label, x0, innerY)
            innerY = innerY + ROW_H + GAP
        end
    end

    love.graphics.setScissor()
end

return DevPanel
