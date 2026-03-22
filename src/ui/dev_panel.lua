local Perks = require("src.data.perks")
local Guns  = require("src.data.guns")

local DevPanel = {}

local ROW_H = 26
local INFO_H = 34
local SECTION_H = 24
local GAP = 4
local PANEL_PAD = 14
local PANEL_W = 430

local function rowSection(id, label, open)
    return { kind = "section", id = id, label = label, open = open ~= false }
end

local function rowAction(id, label)
    return { kind = "action", id = id, label = label }
end

local function rowInfo(label)
    return { kind = "info", label = label }
end

function DevPanel.panelRect(screenW, screenH)
    local pw = math.min(PANEL_W, screenW - 24)
    local ph = math.min(664, screenH - 56)
    return 12, 44, pw, ph
end

function DevPanel.buildRows(args)
    args = args or {}
    local sections = args.sections or {}
    local npc = args.npc or {}

    local rows = {}
    local function open(id)
        return sections[id] ~= false
    end
    local function addSection(id, label)
        local isOpen = open(id)
        rows[#rows + 1] = rowSection(id, label, isOpen)
        return isOpen
    end
    local function timeLabel(id, text)
        local nightOverride = args.nightOverride
        local on = (id == "time_auto" and nightOverride == nil)
            or (id == "time_day" and nightOverride == false)
            or (id == "time_night" and nightOverride == true)
        return (on and "[x] " or "[ ] ") .. text
    end
    local function countLabel(count)
        return string.format("%sx", tostring(count or 1))
    end

    if addSection("debug", "Debug") then
        rows[#rows + 1] = rowAction(
            "toggle_hitboxes",
            (args.showHitboxes ~= false) and "Hitboxes: ON" or "Hitboxes: OFF"
        )
    end

    if addSection("player", "Player") then
        rows[#rows + 1] = rowAction("kill_player", "Kill player")
        rows[#rows + 1] = rowAction("full_heal", "Full heal")
        rows[#rows + 1] = rowAction("hurt_1", "Hurt 1 HP")
        rows[#rows + 1] = rowAction("toggle_god", "Toggle god mode")
        rows[#rows + 1] = rowAction("ult_full", "Full ult charge")
        rows[#rows + 1] = rowAction("gold_100", "+$100 gold")
        rows[#rows + 1] = rowAction("gold_500", "+$500 gold")
        rows[#rows + 1] = rowAction("xp_50", "+50 XP")
        rows[#rows + 1] = rowAction("xp_200", "+200 XP")
        rows[#rows + 1] = rowAction("force_levelup", "Open level-up choice")
    end

    if addSection("world", "World / Room") then
        rows[#rows + 1] = rowAction("time_auto", timeLabel("time_auto", "Auto (room `night` flag)"))
        rows[#rows + 1] = rowAction("time_day", timeLabel("time_day", "Force day (full bright)"))
        rows[#rows + 1] = rowAction("time_night", timeLabel("time_night", "Force night (lamp + fog)"))
        rows[#rows + 1] = rowAction(
            "goto_dev_arena",
            (args.inDevArena and "[x] " or "") .. (args.inDevArena and "Dev arena (active)" or "Go to dev arena (new run)")
        )
        rows[#rows + 1] = rowAction("open_door", "Open exit door")
        rows[#rows + 1] = rowAction("clear_enemies", "Clear all enemies")
        rows[#rows + 1] = rowAction("clear_bullets", "Clear bullets")
        rows[#rows + 1] = rowAction(
            "toggle_boss_fight",
            ((args.bossFightActive == true) and "[x] " or "[ ] ") .. "Boss fight music (room)"
        )
    end

    if addSection("npc", "NPC Spawn") then
        if npc.placement then
            rows[#rows + 1] = rowInfo(string.format(
                "Placing %s | %s | left click world to spawn | right click / ESC cancel",
                npc.placement.label or npc.placement.typeId or "NPC",
                countLabel(npc.count)
            ))
            if npc.preview then
                rows[#rows + 1] = rowInfo(string.format(
                    "Cursor preview: %d/%d valid | %s%s",
                    npc.preview.validCount or 0,
                    npc.preview.totalCount or npc.count or 1,
                    npc.peaceful and "peaceful  " or "",
                    npc.unarmed and "unarmed" or "armed"
                ))
            end
            rows[#rows + 1] = rowAction("npc_cancel_placement", "Cancel placement")
        else
            rows[#rows + 1] = rowInfo("Choose an NPC below, then place it directly in the world with the mouse.")
        end

        rows[#rows + 1] = rowAction("npc_toggle_peaceful", (npc.peaceful and "[x] " or "[ ] ") .. "Peaceful")
        rows[#rows + 1] = rowAction("npc_toggle_unarmed", (npc.unarmed and "[x] " or "[ ] ") .. "Unarmed / no weapon")
        rows[#rows + 1] = rowAction("npc_count_1", ((npc.count or 1) == 1 and "[x] " or "[ ] ") .. "Spawn count: 1x")
        rows[#rows + 1] = rowAction("npc_count_5", ((npc.count or 1) == 5 and "[x] " or "[ ] ") .. "Spawn count: 5x")
        rows[#rows + 1] = rowAction("npc_count_10", ((npc.count or 1) == 10 and "[x] " or "[ ] ") .. "Spawn count: 10x")

        rows[#rows + 1] = rowAction("spawn_bandit", "Place bandit")
        rows[#rows + 1] = rowAction("spawn_nightborne", "Place nightborne")
        rows[#rows + 1] = rowAction("spawn_gunslinger", "Place gunslinger")
        rows[#rows + 1] = rowAction("spawn_necromancer", "Place necromancer")
        rows[#rows + 1] = rowAction("spawn_buzzard", "Place buzzard")
        rows[#rows + 1] = rowAction("spawn_ogreboss", "Place ogre boss")
    end

    if addSection("weapons", "Weapons") then
        rows[#rows + 1] = rowInfo("Click to equip a weapon immediately.")
        for _, gun in ipairs(Guns.pool) do
            local rarity = gun.rarity and (" [" .. gun.rarity .. "]") or ""
            rows[#rows + 1] = rowAction("gun:" .. gun.id, gun.name .. rarity)
        end
    end

    if addSection("perks", "Perks") then
        rows[#rows + 1] = rowInfo("Click to add a perk to the player.")
        for _, perk in ipairs(Perks.pool) do
            rows[#rows + 1] = rowAction("perk:" .. perk.id, perk.name .. "  [" .. perk.id .. "]")
        end
    end

    if addSection("statuses", "Status Lab") then
        local nearestEnemyLabel = args.statusLab and args.statusLab.nearestEnemyLabel or "none"
        rows[#rows + 1] = rowInfo("Dev-only status verification. Applies statuses to the player or the nearest living enemy without changing live content hooks.")
        rows[#rows + 1] = rowInfo("Nearest enemy target: " .. nearestEnemyLabel)
        rows[#rows + 1] = rowAction("status_dump_player", "Dump player statuses")
        rows[#rows + 1] = rowAction("status_dump_enemy", "Dump nearest enemy statuses")
        rows[#rows + 1] = rowAction("status_clear_player", "Clear player statuses")
        rows[#rows + 1] = rowAction("status_clear_enemy", "Clear nearest enemy statuses")
        rows[#rows + 1] = rowAction("status_cleanse_player", "Cleanse player negatives")
        rows[#rows + 1] = rowAction("status_purge_enemy", "Purge nearest enemy positives")
        rows[#rows + 1] = rowAction("status_consume_enemy_shock", "Consume nearest enemy shock")
        rows[#rows + 1] = rowAction("status_player:bleed", "Apply bleed to player")
        rows[#rows + 1] = rowAction("status_player:burn", "Apply burn to player")
        rows[#rows + 1] = rowAction("status_player:shock", "Apply shock to player")
        rows[#rows + 1] = rowAction("status_player:wet", "Apply wet to player")
        rows[#rows + 1] = rowAction("status_player:stun", "Apply stun to player")
        rows[#rows + 1] = rowAction("status_player:slow", "Apply slow to player")
        rows[#rows + 1] = rowAction("status_enemy:bleed", "Apply bleed to nearest enemy")
        rows[#rows + 1] = rowAction("status_enemy:burn", "Apply burn to nearest enemy")
        rows[#rows + 1] = rowAction("status_enemy:shock", "Apply shock to nearest enemy")
        rows[#rows + 1] = rowAction("status_enemy:wet", "Apply wet to nearest enemy")
        rows[#rows + 1] = rowAction("status_enemy:stun", "Apply stun to nearest enemy")
        rows[#rows + 1] = rowAction("status_enemy:slow", "Apply slow to nearest enemy")
        rows[#rows + 1] = rowAction("status_player:speed_boost", "Apply speed boost to player")
        rows[#rows + 1] = rowAction("status_enemy:speed_boost", "Apply speed boost to nearest enemy")
    end

    return rows
end

local function rowHeight(row)
    if row.kind == "section" then
        return SECTION_H + GAP
    elseif row.kind == "info" then
        return INFO_H + GAP
    end
    return ROW_H + GAP
end

function DevPanel.rowsHeight(rows)
    local h = 0
    for _, row in ipairs(rows) do
        h = h + rowHeight(row)
    end
    return h
end

function DevPanel.titleBlockHeight(titleFont)
    return PANEL_PAD + titleFont:getHeight() + 12
end

function DevPanel.maxScroll(rows, titleFont, panelH)
    local rowsH = DevPanel.rowsHeight(rows)
    local titleH = DevPanel.titleBlockHeight(titleFont)
    local viewH = panelH - titleH - PANEL_PAD
    if viewH < 40 then return 0 end
    return math.max(0, rowsH - viewH)
end

function DevPanel.hitTest(rows, mx, my, scrollY, px, py, pw, ph, titleFont)
    if mx < px or my < py or mx > px + pw or my > py + ph then
        return nil
    end

    local y = py + DevPanel.titleBlockHeight(titleFont) - scrollY
    local x0 = px + PANEL_PAD
    local innerW = pw - 2 * PANEL_PAD

    for _, row in ipairs(rows) do
        if row.kind == "section" then
            if my >= y and my <= y + SECTION_H and mx >= x0 and mx <= x0 + innerW then
                return "section:" .. row.id
            end
        elseif row.kind == "action" then
            if my >= y and my <= y + ROW_H and mx >= x0 and mx <= x0 + innerW then
                return row.id
            end
        end
        y = y + rowHeight(row)
    end

    return nil
end

function DevPanel.draw(rows, scrollY, px, py, pw, ph, hoverId, fonts)
    local titleFont = fonts.title
    local rowFont = fonts.row

    love.graphics.setColor(0.05, 0.045, 0.07, 0.94)
    love.graphics.rectangle("fill", px, py, pw, ph, 8, 8)
    love.graphics.setColor(0.55, 0.4, 0.2, 0.98)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", px, py, pw, ph, 8, 8)
    love.graphics.setLineWidth(1)

    love.graphics.setScissor(px, py, pw, ph)
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.75, 0.25)
    love.graphics.print("DEV TOOLS", px + PANEL_PAD, py + 8)

    local innerY = py + DevPanel.titleBlockHeight(titleFont) - scrollY
    local x0 = px + PANEL_PAD
    local innerW = pw - 2 * PANEL_PAD

    love.graphics.setFont(rowFont)
    for _, row in ipairs(rows) do
        if row.kind == "section" then
            local hovered = hoverId == ("section:" .. row.id)
            love.graphics.setColor(hovered and 0.16 or 0.11, hovered and 0.13 or 0.1, hovered and 0.08 or 0.07, 0.92)
            love.graphics.rectangle("fill", x0 - 4, innerY - 1, innerW + 8, SECTION_H, 4, 4)
            love.graphics.setColor(0.72, 0.63, 0.5, 0.95)
            love.graphics.print((row.open and "v " or "> ") .. row.label, x0, innerY + 2)
        elseif row.kind == "info" then
            love.graphics.setColor(0.18, 0.18, 0.22, 0.62)
            love.graphics.rectangle("fill", x0 - 4, innerY - 2, innerW + 8, INFO_H, 4, 4)
            love.graphics.setColor(0.72, 0.74, 0.78, 0.95)
            love.graphics.printf(row.label, x0, innerY + 3, innerW, "left")
        else
            local hovered = hoverId == row.id
            if hovered then
                love.graphics.setColor(0.2, 0.16, 0.12, 0.9)
                love.graphics.rectangle("fill", x0 - 4, innerY - 2, innerW + 8, ROW_H, 4, 4)
            end
            love.graphics.setColor(hovered and 1 or 0.82, hovered and 0.95 or 0.8, hovered and 0.7 or 0.68)
            love.graphics.print(row.label, x0, innerY + 3)
        end
        innerY = innerY + rowHeight(row)
    end

    love.graphics.setScissor()
end

return DevPanel
