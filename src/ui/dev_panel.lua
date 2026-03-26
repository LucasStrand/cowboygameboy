local Perks = require("src.data.perks")
local Guns  = require("src.data.guns")

local DevPanel = {}

local ROW_H = 26
local INFO_H = 34
local SECTION_H = 24
local GAP = 4
local PANEL_PAD = 14
local PANEL_W = 620
local FOOTER_H = 28
local SEARCH_GAP = 6
local SEARCH_FIELD_H = 26

-- Sentinel hit id for the filter field (game/saloon handle focus + typing).
DevPanel.HIT_SEARCH = "__dev_search"

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
    local desiredW = math.min(760, math.max(PANEL_W, math.floor(screenW * 0.66)))
    local desiredH = math.min(820, math.floor(screenH * 0.88))
    local pw = math.min(desiredW, screenW - 20)
    local ph = math.min(desiredH, screenH - 24)
    return 10, 18, pw, ph
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
            "toggle_dev_pause",
            (args.gameplayPaused ~= false) and "Gameplay: PAUSED" or "Gameplay: LIVE"
        )
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

    if addSection("quick", "Quick Setups") then
        rows[#rows + 1] = rowInfo("One-click Phase 6 presets for rapid perk/weapon testing.")
        rows[#rows + 1] = rowAction("preset_phase6_revolver_explosive", "Phase 6: revolver + explosive")
        rows[#rows + 1] = rowAction("preset_phase6_ak_explosive", "Phase 6: AK-47 + explosive")
        rows[#rows + 1] = rowAction("preset_phase6_blunderbuss_explosive", "Phase 6: blunderbuss + explosive")
        rows[#rows + 1] = rowAction("preset_phase6_proc_revolver", "Phase 6: revolver + Phantom Third")
        rows[#rows + 1] = rowAction("preset_phase9_clutter_readability", "Phase 9: clutter / HUD readability test")
        rows[#rows + 1] = rowAction("preset_phase10_proc_explosion_stress", "Phase 10: proc + explosive stress (blunderbuss)")
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

    if addSection("rewards", "Rewards / Tooltips") then
        rows[#rows + 1] = rowInfo("Test current reward-facing tooltip surfaces directly in dev arena.")
        rows[#rows + 1] = rowInfo("Build profile: " .. tostring(args.rewardLab and args.rewardLab.profileSummary or "none"))
        rows[#rows + 1] = rowInfo(string.format(
            "Gold: $%d | level-up reroll: $%d | shop reroll: $%d",
            tonumber(args.rewardLab and args.rewardLab.gold or 0) or 0,
            tonumber(args.rewardLab and args.rewardLab.levelupRerollCost or 0) or 0,
            tonumber(args.rewardLab and args.rewardLab.shopRerollCost or 0) or 0
        ))
        rows[#rows + 1] = rowAction("reward_dump_profile", "Dump reward profile to DevLog")
        rows[#rows + 1] = rowAction("reward_dump_pressure", "Dump gold pressure to DevLog")
        rows[#rows + 1] = rowAction("force_levelup", "Open level-up choice")
        rows[#rows + 1] = rowAction("reward_refresh_shop", "Refresh dev shop offers")
        rows[#rows + 1] = rowAction("reward_reroll_shop", "Spend gold and reroll dev shop")
        local offers = args.rewardLab and args.rewardLab.offers or {}
        if #offers == 0 then
            rows[#rows + 1] = rowInfo("No dev shop offers available.")
        else
            for i, offer in ipairs(offers) do
                local price = offer.price and (" $" .. tostring(offer.price)) or ""
                local sold = offer.sold and " [APPLIED]" or ""
                local bucket = offer.reward_bucket and (" [" .. tostring(offer.reward_bucket) .. "]") or ""
                local role = offer.reward_role and (" {" .. tostring(offer.reward_role) .. "}") or ""
                rows[#rows + 1] = rowAction("reward_apply_shop_offer:" .. tostring(i), string.format("Offer %d: %s%s%s%s%s", i, offer.name or "Offer", bucket, role, price, sold))
                if offer.description and offer.description ~= "" then
                    rows[#rows + 1] = rowInfo(offer.description)
                end
                if offer.reward_reason and offer.reward_reason ~= "" then
                    rows[#rows + 1] = rowInfo("Reason: " .. offer.reward_reason)
                end
            end
        end
    end

    if addSection("meta", "Meta / Recap") then
        local summary = args.metaLab and args.metaLab.summary or {}
        rows[#rows + 1] = rowInfo(string.format(
            "Rooms %d | Checkpoints %d | Bosses %d | Picks %d | Rerolls %d",
            tonumber(summary.roomsCleared or 0) or 0,
            tonumber(summary.checkpointsReached or 0) or 0,
            tonumber(summary.bossesKilled or 0) or 0,
            tonumber(summary.perksPicked or 0) or 0,
            tonumber(summary.rerollsUsed or 0) or 0
        ))
        rows[#rows + 1] = rowInfo(string.format(
            "Gold earned $%d | spent $%d",
            tonumber(summary.goldEarned or 0) or 0,
            tonumber(summary.goldSpent or 0) or 0
        ))
        if summary.dominantTags and #summary.dominantTags > 0 then
            rows[#rows + 1] = rowInfo("Dominant tags: " .. table.concat(summary.dominantTags, ", "))
        end
        rows[#rows + 1] = rowAction("meta_dump_summary", "Dump meta summary to DevLog")
        rows[#rows + 1] = rowAction("meta_dump_last_damage", "Dump last damage / proc recap fields")
        rows[#rows + 1] = rowAction("meta_dump_retention", "Dump run metadata retention counts vs caps")
        rows[#rows + 1] = rowAction("meta_save_snapshot", "Save run metadata snapshot to save folder (Phase 10)")
        rows[#rows + 1] = rowAction("meta_open_recap", "Open recap screen from current run")
    end

    if addSection("statuses", "Status Lab") then
        local nearestEnemyLabel = args.statusLab and args.statusLab.nearestEnemyLabel or "none"
        rows[#rows + 1] = rowInfo("Dev-only status verification. No live weapon or ultimate hooks.")
        rows[#rows + 1] = rowInfo("Target enemy: " .. nearestEnemyLabel)
        rows[#rows + 1] = rowAction("status_dump_player", "Player: dump")
        rows[#rows + 1] = rowAction("status_clear_player", "Player: clear all")
        rows[#rows + 1] = rowAction("status_cleanse_player", "Player: cleanse negatives")
        rows[#rows + 1] = rowAction("status_step_player_1s", "Player: advance statuses 1s")
        rows[#rows + 1] = rowAction("status_step_player_5s", "Player: advance statuses 5s")
        rows[#rows + 1] = rowAction("status_player:bleed", "Player: bleed")
        rows[#rows + 1] = rowAction("status_player:burn", "Player: burn")
        rows[#rows + 1] = rowAction("status_player:shock", "Player: shock")
        rows[#rows + 1] = rowAction("status_player:wet", "Player: wet")
        rows[#rows + 1] = rowAction("status_player:stun", "Player: stun")
        rows[#rows + 1] = rowAction("status_player:slow", "Player: slow")
        rows[#rows + 1] = rowAction("status_player:speed_boost", "Player: speed boost")
        rows[#rows + 1] = rowAction("status_dump_enemy", "Enemy: dump nearest")
        rows[#rows + 1] = rowAction("status_clear_enemy", "Enemy: clear nearest")
        rows[#rows + 1] = rowAction("status_purge_enemy", "Enemy: purge positives")
        rows[#rows + 1] = rowAction("status_consume_enemy_shock", "Enemy: consume shock")
        rows[#rows + 1] = rowAction("status_step_enemy_1s", "Enemy: advance statuses 1s")
        rows[#rows + 1] = rowAction("status_step_enemy_5s", "Enemy: advance statuses 5s")
        rows[#rows + 1] = rowAction("status_enemy:bleed", "Enemy: bleed")
        rows[#rows + 1] = rowAction("status_enemy:burn", "Enemy: burn")
        rows[#rows + 1] = rowAction("status_enemy:shock", "Enemy: shock")
        rows[#rows + 1] = rowAction("status_enemy:wet", "Enemy: wet")
        rows[#rows + 1] = rowAction("status_enemy:stun", "Enemy: stun")
        rows[#rows + 1] = rowAction("status_enemy:slow", "Enemy: slow")
        rows[#rows + 1] = rowAction("status_enemy:speed_boost", "Enemy: speed boost")
    end

    return rows
end

--- Case-insensitive substring filter. Keeps section headers when any row in that block matches,
--- or shows the whole section when the section header matches.
function DevPanel.filterRows(rows, query)
    if not rows or #rows < 1 then return rows end
    local q = string.gsub(query or "", "^%s+", "")
    q = string.gsub(q, "%s+$", "")
    if q == "" then
        return rows
    end
    q = string.lower(q)

    local function contains(hay)
        hay = string.lower(tostring(hay or ""))
        return string.find(hay, q, 1, true) ~= nil
    end

    local function rowMatches(row)
        if row.kind == "section" then
            return contains(row.id) or contains(row.label)
        elseif row.kind == "action" then
            return contains(row.id) or contains(row.label)
        elseif row.kind == "info" then
            return contains(row.label)
        end
        return false
    end

    local out = {}
    local i = 1
    while i <= #rows do
        local row = rows[i]
        if row.kind ~= "section" then
            if rowMatches(row) then
                out[#out + 1] = row
            end
            i = i + 1
        else
            local j = i + 1
            while j <= #rows and rows[j].kind ~= "section" do
                j = j + 1
            end
            local sec = row
            local secMatch = rowMatches(sec)
            local block = {}
            for k = i + 1, j - 1 do
                block[#block + 1] = rows[k]
            end
            if secMatch then
                out[#out + 1] = sec
                for _, r in ipairs(block) do
                    out[#out + 1] = r
                end
            else
                local any = {}
                for _, r in ipairs(block) do
                    if rowMatches(r) then
                        any[#any + 1] = r
                    end
                end
                if #any > 0 then
                    out[#out + 1] = sec
                    for _, r in ipairs(any) do
                        out[#out + 1] = r
                    end
                end
            end
            i = j
        end
    end
    return out
end

local function rowHeight(row, rowFont, innerW)
    if row.kind == "section" then
        return SECTION_H + GAP
    elseif row.kind == "info" then
        if rowFont and innerW then
            local _, wrapped = rowFont:getWrap(row.label or "", math.max(32, innerW))
            local lines = math.max(1, #wrapped)
            local textH = lines * rowFont:getHeight()
            return math.max(INFO_H, textH + 10) + GAP
        end
        return INFO_H + GAP
    end
    return ROW_H + GAP
end

function DevPanel.rowsHeight(rows, rowFont, panelW)
    local h = 0
    local innerW = panelW and (panelW - 2 * PANEL_PAD) or nil
    for _, row in ipairs(rows) do
        h = h + rowHeight(row, rowFont, innerW)
    end
    return h
end

function DevPanel.titleBlockHeight(titleFont)
    return PANEL_PAD + titleFont:getHeight() + 12
end

function DevPanel.searchBarHeight()
    return SEARCH_GAP + SEARCH_FIELD_H
end

--- Title row + search field (fixed; list scrolls below).
function DevPanel.headerHeight(titleFont)
    return DevPanel.titleBlockHeight(titleFont) + DevPanel.searchBarHeight()
end

function DevPanel.searchFieldRect(px, py, pw, titleFont)
    local x0 = px + PANEL_PAD
    local y0 = py + DevPanel.titleBlockHeight(titleFont) + SEARCH_GAP
    local w = pw - 2 * PANEL_PAD
    return x0, y0, w, SEARCH_FIELD_H
end

function DevPanel.maxScroll(rows, titleFont, rowFont, panelW, panelH)
    local rowsH = DevPanel.rowsHeight(rows, rowFont, panelW)
    local titleH = DevPanel.headerHeight(titleFont)
    local viewH = panelH - titleH - PANEL_PAD - FOOTER_H - 8
    if viewH < 40 then return 0 end
    return math.max(0, rowsH - viewH)
end

function DevPanel.hitTest(rows, mx, my, scrollY, px, py, pw, ph, titleFont, rowFont)
    if mx < px or my < py or mx > px + pw or my > py + ph then
        return nil
    end

    local sx, sy, sw, sh = DevPanel.searchFieldRect(px, py, pw, titleFont)
    if mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh then
        return DevPanel.HIT_SEARCH
    end

    local y = py + DevPanel.headerHeight(titleFont) - scrollY
    local x0 = px + PANEL_PAD
    local innerW = pw - 2 * PANEL_PAD
    local contentBottom = py + ph - PANEL_PAD - FOOTER_H

    for _, row in ipairs(rows) do
        local h = rowHeight(row, rowFont, innerW)
        if row.kind == "section" then
            if my >= y and my <= y + SECTION_H and mx >= x0 and mx <= x0 + innerW and my < contentBottom then
                return "section:" .. row.id
            end
        elseif row.kind == "action" then
            if my >= y and my <= y + ROW_H and mx >= x0 and mx <= x0 + innerW and my < contentBottom then
                return row.id
            end
        end
        y = y + h
    end

    return nil
end

function DevPanel.draw(rows, scrollY, px, py, pw, ph, hoverId, fonts, searchOpts)
    searchOpts = searchOpts or {}
    local titleFont = fonts.title
    local rowFont = fonts.row
    local q = searchOpts.query or ""
    local searchFocus = searchOpts.focused
    local searchHover = searchOpts.hover

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

    do
        local sfx, sfy, sfw, sfh = DevPanel.searchFieldRect(px, py, pw, titleFont)
        local shov = searchHover or searchFocus
        love.graphics.setColor(0.07, 0.065, 0.09, 0.96)
        love.graphics.rectangle("fill", sfx - 2, sfy - 2, sfw + 4, sfh + 4, 4, 4)
        love.graphics.setColor(shov and 0.42 or 0.28, shov and 0.35 or 0.24, shov and 0.2 or 0.14, 0.98)
        love.graphics.setLineWidth(shov and 2 or 1)
        love.graphics.rectangle("line", sfx - 2, sfy - 2, sfw + 4, sfh + 4, 4, 4)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(rowFont)
        local display = (#q > 0) and q or "Search…"
        local r, g, b = 0.88, 0.86, 0.82
        if #q == 0 then
            r, g, b = 0.45, 0.44, 0.48
        end
        if searchFocus then
            r, g, b = 0.95, 0.93, 0.88
        end
        love.graphics.setColor(r, g, b, (#q > 0 or searchFocus) and 1 or 0.85)
        local maxW = sfw - 8
        local text = display
        if rowFont:getWidth(text) > maxW then
            while #text > 1 and rowFont:getWidth(text .. "…") > maxW do
                text = text:sub(1, -2)
            end
            text = text .. "…"
        end
        love.graphics.print(text, sfx + 4, sfy + math.max(2, (sfh - rowFont:getHeight()) * 0.5))
    end

    local innerY = py + DevPanel.headerHeight(titleFont) - scrollY
    local x0 = px + PANEL_PAD
    local innerW = pw - 2 * PANEL_PAD
    local contentBottom = py + ph - PANEL_PAD - FOOTER_H

    love.graphics.setScissor(px, py, pw, math.max(0, contentBottom - py))
    love.graphics.setFont(rowFont)
    for _, row in ipairs(rows) do
        local h = rowHeight(row, rowFont, innerW)
        if row.kind == "section" then
            local hovered = hoverId == ("section:" .. row.id)
            love.graphics.setColor(hovered and 0.16 or 0.11, hovered and 0.13 or 0.1, hovered and 0.08 or 0.07, 0.92)
            love.graphics.rectangle("fill", x0 - 4, innerY - 1, innerW + 8, SECTION_H, 4, 4)
            love.graphics.setColor(0.72, 0.63, 0.5, 0.95)
            love.graphics.print((row.open and "v " or "> ") .. row.label, x0, innerY + 2)
        elseif row.kind == "info" then
            love.graphics.setColor(0.18, 0.18, 0.22, 0.72)
            love.graphics.rectangle("fill", x0 - 4, innerY - 2, innerW + 8, h - GAP, 4, 4)
            love.graphics.setColor(0.72, 0.74, 0.78, 0.95)
            love.graphics.printf(row.label, x0, innerY + 4, innerW, "left")
        else
            local hovered = hoverId == row.id
            if hovered then
                love.graphics.setColor(0.2, 0.16, 0.12, 0.9)
                love.graphics.rectangle("fill", x0 - 4, innerY - 2, innerW + 8, ROW_H, 4, 4)
            end
            love.graphics.setColor(hovered and 1 or 0.82, hovered and 0.95 or 0.8, hovered and 0.7 or 0.68)
            love.graphics.print(row.label, x0, innerY + 3)
        end
        innerY = innerY + h
    end

    love.graphics.setScissor()

    local footerY = py + ph - PANEL_PAD - FOOTER_H + 4
    love.graphics.setColor(0.1, 0.09, 0.12, 0.95)
    love.graphics.rectangle("fill", px + 1, footerY - 6, pw - 2, FOOTER_H + PANEL_PAD + 1, 0, 0)
    love.graphics.setColor(0.26, 0.22, 0.18, 0.95)
    love.graphics.line(x0 - 4, footerY - 6, x0 + innerW + 4, footerY - 6)
    love.graphics.setFont(rowFont)
    love.graphics.setColor(0.55, 0.55, 0.58)
    love.graphics.printf("F1 close  |  wheel scroll  |  type to filter list", x0, footerY, innerW, "center")
end

return DevPanel
