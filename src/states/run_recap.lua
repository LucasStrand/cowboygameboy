local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Cursor = require("src.ui.cursor")
local MetaRuntime = require("src.systems.meta_runtime")
local RunMetadata = require("src.systems.run_metadata")
local RunScoreboard = require("src.systems.run_scoreboard")
local Guns = require("src.data.guns")
local GearData = require("src.data.gear")
local Perks = require("src.data.perks")

local run_recap = {}

local fonts = {}
local summary = nil
local stats = nil
local latestBuild = nil
local topRuns = {}
local runMeta = nil
local copyMessage = nil
local copyMessageTimer = 0
local showCausalDetail = false

--- Larger canvas (tall window) ⇒ scale recap UI so text stays readable (see main.lua syncGameDimensions).
local function recapUiScale()
    local h = GAME_HEIGHT or 720
    return math.max(1, math.min(3, h / 720))
end

local recapFontScaleKey = nil

local function ensureFonts()
    local sc = recapUiScale()
    local key = string.format("%.3f", sc)
    if recapFontScaleKey == key and fonts.title then
        return
    end
    recapFontScaleKey = key
    fonts = {
        title = Font.new(math.max(22, math.floor(32 * sc + 0.5))),
        section = Font.new(math.max(14, math.floor(20 * sc + 0.5))),
        body = Font.new(math.max(12, math.floor(16 * sc + 0.5))),
        small = Font.new(math.max(11, math.floor(14 * sc + 0.5))),
    }
end

local function formatPercent(value)
    return string.format("%d%%", tonumber(value or 0) or 0)
end

local function buildWeaponRows(build)
    local rows = {}
    for _, entry in ipairs(build and build.weapons or {}) do
        local gun = Guns.getById(entry.gun_id)
        rows[#rows + 1] = string.format(
            "Slot %d  %s",
            tonumber(entry.slot or 0) or 0,
            gun and gun.name or "Empty"
        )
    end
    return rows
end

local function buildGearRows(build)
    local rows = {}
    for _, entry in ipairs(build and build.gear or {}) do
        local gear = GearData.getById(entry.gear_id)
        rows[#rows + 1] = string.format(
            "%s  %s",
            string.upper(tostring(entry.slot or "?")),
            gear and gear.name or "Empty"
        )
    end
    return rows
end

local function buildPerkRows(build)
    local rows = {}
    for _, perk_id in ipairs(build and build.perks or {}) do
        local perk = Perks.getById(perk_id)
        rows[#rows + 1] = perk and perk.name or tostring(perk_id)
    end
    if #rows == 0 then
        rows[1] = "No perks"
    end
    return rows
end

local function buildLoadoutRows(build)
    local rows = {}
    for _, row in ipairs(buildWeaponRows(build)) do
        rows[#rows + 1] = row
    end
    rows[#rows + 1] = " "
    for _, row in ipairs(buildGearRows(build)) do
        rows[#rows + 1] = row
    end
    return rows
end

local function truncateRow(s, maxLen)
    if not s or type(s) ~= "string" then
        return s
    end
    if #s <= maxLen then
        return s
    end
    return s:sub(1, math.max(1, maxLen - 1)) .. "…"
end

--- opts.body_font — optional font for row text.
--- Rows use Font:getWrap so multi-line strings do not overlap; spacing = visual lines × font height + rowGap.
local function drawPanel(x, y, w, h, title, rows, accent, opts)
    accent = accent or { 0.88, 0.72, 0.28 }
    opts = opts or {}
    local sc = opts.ui_scale or 1
    local bodyFont = opts.body_font or fonts.body
    local bottomPad = opts.bottom_pad or math.floor(24 * sc + 0.5)
    local padX = math.floor(16 * sc + 0.5)
    local padTitleY = math.floor(14 * sc + 0.5)

    local fontH = bodyFont:getHeight()
    local bodyLh = bodyFont:getLineHeight()
    if type(bodyLh) ~= "number" or bodyLh <= 0 then
        bodyLh = 1
    end
    -- printf advances each wrapped line by getHeight() * getLineHeight(); must match or rows overlap.
    local lineAdvance = fontH * math.max(bodyLh, 1)
    local rowGap = math.max(4, math.floor(6 * sc + 0.5))

    local secFont = fonts.section
    local secH = secFont:getHeight() * math.max(secFont:getLineHeight() or 1, 1)
    local bodyTop = math.max(
        math.floor(52 * sc + 0.5),
        padTitleY + secH + math.floor(10 * sc + 0.5)
    )

    if opts.opaque_fill then
        love.graphics.setColor(0.08, 0.07, 0.06, 1)
    else
        love.graphics.setColor(0.08, 0.07, 0.06, 0.92)
    end
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)
    love.graphics.setColor(accent[1], accent[2], accent[3], 1)
    love.graphics.setLineWidth(math.max(1, math.floor(2 * sc + 0.5)))
    love.graphics.rectangle("line", x, y, w, h, 10, 10)
    love.graphics.setFont(fonts.section)
    love.graphics.printf(title, x + padX, y + padTitleY, w - padX * 2, "left")

    local lineY = y + bodyTop
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.88, 0.84, 0.78, 1)
    local clipped = false
    local textW = math.max(40, w - padX * 2)
    for _, row in ipairs(rows or {}) do
        local text = tostring(row)
        local _, wrapped = bodyFont:getWrap(text, textW)
        local numVisualLines = math.max(1, wrapped and #wrapped or 1)
        local blockH = numVisualLines * lineAdvance + rowGap
        if lineY + blockH > y + h - bottomPad then
            clipped = true
            break
        end
        love.graphics.printf(text, x + padX, lineY, textW, "left")
        lineY = lineY + blockH
    end
    if clipped then
        love.graphics.setColor(0.65, 0.62, 0.58, 1)
        local ellipsisH = lineAdvance + rowGap
        if lineY + ellipsisH <= y + h - bottomPad then
            love.graphics.printf("…", x + padX, lineY, textW, "left")
        end
    end
    love.graphics.setLineWidth(1)
end

local function joinTags(tags)
    if not tags or #tags == 0 then
        return "-"
    end
    return table.concat(tags, ",")
end

local function buildSourceSummaryRows(run_meta)
    local totals = {}
    for _, event in ipairs(run_meta and run_meta.combat and run_meta.combat.damage_events or {}) do
        local key = table.concat({
            tostring(event.source_type or "unknown"),
            tostring(event.source_id or "unknown"),
            tostring(event.family or "unknown"),
        }, " | ")
        totals[key] = (totals[key] or 0) + (tonumber(event.amount or 0) or 0)
    end

    local items = {}
    for key, amount in pairs(totals) do
        items[#items + 1] = { key = key, amount = amount }
    end
    table.sort(items, function(a, b)
        if a.amount == b.amount then
            return a.key < b.key
        end
        return a.amount > b.amount
    end)

    local rows = {}
    for i = 1, math.min(8, #items) do
        rows[#rows + 1] = string.format("%d  %s", items[i].amount, items[i].key)
    end
    if #rows == 0 then
        rows[1] = "No damage trace recorded"
    end
    return rows
end

local function buildDamageTraceText(run_meta)
    local lines = {
        "Damage Trace",
        "============",
    }
    for _, event in ipairs(run_meta and run_meta.combat and run_meta.combat.damage_events or {}) do
        lines[#lines + 1] = string.format(
            "%4d | %s/%s | %s | %s | target=%s | room=%s | tags=%s",
            tonumber(event.amount or 0) or 0,
            tostring(event.source_type or "unknown"),
            tostring(event.source_id or "unknown"),
            tostring(event.packet_kind or "unknown"),
            tostring(event.family or "unknown"),
            tostring(event.target_id or "unknown"),
            tostring(event.room_name or event.room_id or "unknown"),
            joinTags(event.tags)
        )
    end
    if #lines == 2 then
        lines[#lines + 1] = "No damage events recorded."
    end
    return table.concat(lines, "\n")
end

local function buildRunReportText(run_meta, current_summary, current_stats, build)
    local buildStats = build and build.stats or {}
    local lines = {
        "Run Recap Export",
        string.format(
            "Format v%d | metadata retention policy v%d",
            RunMetadata.RECAP_EXPORT_VERSION or 0,
            RunMetadata.METADATA_RETENTION_VERSION or 0
        ),
        "================",
        string.format("Outcome: %s", tostring(current_summary.outcome or current_stats.outcome or "unknown")),
        string.format("World: %s", tostring(current_summary.worldName or current_summary.worldId or "unknown")),
        string.format("Level: %d", tonumber(current_stats.level or 1) or 1),
        string.format("Rooms Cleared: %d", tonumber(current_summary.roomsCleared or 0) or 0),
        string.format("Bosses Killed: %d", tonumber(current_summary.bossesKilled or 0) or 0),
        string.format("Gold Earned: %d", tonumber(current_summary.goldEarned or 0) or 0),
        string.format("Gold Spent: %d", tonumber(current_summary.goldSpent or 0) or 0),
        string.format("Rerolls: %d", tonumber(current_summary.rerollsUsed or 0) or 0),
        "",
        "Build Stats",
        "-----------",
        string.format("Armor: %d", tonumber(buildStats.armor or 0) or 0),
        string.format("Max HP: %d", tonumber(buildStats.max_hp or 0) or 0),
        string.format("Luck: %s", formatPercent(buildStats.luck_pct or 0)),
        string.format("Bullet Damage: %d", tonumber(buildStats.bullet_damage or 0) or 0),
        string.format("Damage Bonus: %s", formatPercent(buildStats.damage_multiplier_pct or 0)),
        string.format("Crit Chance: %s", formatPercent(buildStats.crit_chance_pct or 0)),
        "",
        "Damage Breakdown",
        "----------------",
        string.format("Total: %d", tonumber(current_summary.totalDamageDealt or 0) or 0),
        string.format("Ultimate: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.ultimate or 0) or 0),
        string.format("Explosion: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.explosion or 0) or 0),
        string.format("Proc: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.proc or 0) or 0),
        string.format("Melee: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.melee or 0) or 0),
        string.format("Physical: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.physical or 0) or 0),
        string.format("Magical: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.magical or 0) or 0),
        string.format("True: %d", tonumber(current_summary.damageBreakdown and current_summary.damageBreakdown.true_damage or 0) or 0),
        "",
        "Weapons",
        "-------",
    }
    for _, row in ipairs(buildWeaponRows(build)) do
        lines[#lines + 1] = row
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Gear"
    lines[#lines + 1] = "----"
    for _, row in ipairs(buildGearRows(build)) do
        lines[#lines + 1] = row
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Perks"
    lines[#lines + 1] = "-----"
    for _, row in ipairs(buildPerkRows(build)) do
        lines[#lines + 1] = row
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Readability (Phase 9)"
    lines[#lines + 1] = "-------------------"
    local lastHitTech = current_summary.lastDamageToPlayerLineTechnical or current_summary.lastDamageToPlayerLine
    local procTech = current_summary.lastMajorProcLineTechnical or current_summary.lastMajorProcLine
    if lastHitTech then
        lines[#lines + 1] = "Last hit taken: " .. tostring(lastHitTech)
    end
    if procTech then
        lines[#lines + 1] = "Major proc: " .. tostring(procTech)
    end
    if current_summary.damageTracePrimarySource then
        lines[#lines + 1] = "Damage trace first (dealt): " .. tostring(current_summary.damageTracePrimarySource)
    end
    if current_summary.damageTraceLastEventSource then
        lines[#lines + 1] = "Damage trace last (dealt): " .. tostring(current_summary.damageTraceLastEventSource)
    end
    if current_summary.damageTraceLastIncomingSource then
        lines[#lines + 1] = "Last incoming source id: " .. tostring(current_summary.damageTraceLastIncomingSource)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = buildDamageTraceText(run_meta)
    return table.concat(lines, "\n")
end

local function copyText(label, text)
    if love.system and love.system.setClipboardText then
        love.system.setClipboardText(text)
        copyMessage = label .. " copied"
    else
        copyMessage = "Clipboard unavailable"
    end
    copyMessageTimer = 2.5
end

function run_recap:enter(_, args)
    ensureFonts()
    Cursor.setDefault()
    args = args or {}
    stats = {
        level = args.level or 1,
        roomsCleared = args.roomsCleared or 0,
        gold = args.gold or 0,
        perksCount = args.perksCount or 0,
        outcome = args.outcome or "death",
    }
    runMeta = args.runMetadata
    local fb = {
        roomsCleared = args.roomsCleared,
        perksCount = args.perksCount,
        outcome = args.outcome or "death",
    }
    local okSum, summ = pcall(MetaRuntime.summarize, args.runMetadata, fb)
    summary = (okSum and summ) or MetaRuntime.summarize(nil, fb)
    latestBuild = summary.latestBuild or {}
    local okScore, runsOrErr = pcall(RunScoreboard.recordRun, stats, summary)
    topRuns = okScore and runsOrErr or RunScoreboard.getRuns()
    showCausalDetail = false
end

function run_recap:update(dt)
    if copyMessageTimer > 0 then
        copyMessageTimer = math.max(0, copyMessageTimer - dt)
        if copyMessageTimer <= 0 then
            copyMessage = nil
        end
    end
end

function run_recap:keypressed(key)
    if key == "t" then
        showCausalDetail = not showCausalDetail
    elseif key == "c" then
        copyText("Run report", buildRunReportText(runMeta, summary, stats, latestBuild))
    elseif key == "x" then
        copyText("Damage trace", buildDamageTraceText(runMeta))
    elseif key == "return" or key == "space" then
        local game = require("src.states.game")
        Gamestate.switch(game, { introCountdown = true })
    elseif key == "escape" then
        local menu = require("src.states.menu")
        Gamestate.switch(menu)
    end
end

function run_recap:draw()
    ensureFonts()

    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local sc = recapUiScale()
    local margin = math.floor(34 * sc + 0.5)
    local gutter = math.floor(18 * sc + 0.5)
    local topY = math.floor(28 * sc + 0.5)
    local fullW = screenW - margin * 2
    local leftW = math.floor(fullW * 0.34)
    local rightW = fullW - leftW - gutter
    local rightColW = math.floor((rightW - gutter) * 0.5)
    local rightCol2W = rightW - gutter - rightColW
    local leftX = margin
    local rightX = leftX + leftW + gutter
    local highScoresH = math.floor(106 * sc + 0.5)
    local headerH = math.max(
        math.floor(140 * sc + 0.5),
        margin + highScoresH + math.floor(12 * sc + 0.5)
    )
    local titleX = leftX + leftW + gutter
    local titleW = math.max(120, screenW - margin - titleX)

    love.graphics.setColor(0.11, 0.09, 0.07, 1)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    love.graphics.setColor(0.18, 0.14, 0.11, 1)
    love.graphics.rectangle("fill", 0, 0, screenW, headerH)

    -- High-signal lines first so they stay visible if the panel clips.
    local overviewRows = {
        string.format("Level  %d", tonumber(stats.level or 1) or 1),
        string.format("Rooms Cleared  %d", tonumber(summary.roomsCleared or 0) or 0),
        string.format("Bosses Killed  %d", tonumber(summary.bossesKilled or 0) or 0),
        string.format("Perks Picked  %d", tonumber(summary.perksPicked or 0) or 0),
    }
    if summary.lastDamageToPlayerLine then
        overviewRows[#overviewRows + 1] = "Last hit  " .. tostring(summary.lastDamageToPlayerLine)
    end
    if summary.lastMajorProcLine then
        overviewRows[#overviewRows + 1] = "Big proc  " .. tostring(summary.lastMajorProcLine)
    end
    overviewRows[#overviewRows + 1] = string.format("Gold Earned  $%d", tonumber(summary.goldEarned or 0) or 0)
    overviewRows[#overviewRows + 1] = string.format("Gold Spent  $%d", tonumber(summary.goldSpent or 0) or 0)
    overviewRows[#overviewRows + 1] = string.format("Rerolls  %d", tonumber(summary.rerollsUsed or 0) or 0)
    overviewRows[#overviewRows + 1] = string.format("World  %s", tostring(summary.worldName or summary.worldId or "unknown"))
    if summary.dominantTags and #summary.dominantTags > 0 then
        local tagStr = table.concat(summary.dominantTags, ", ")
        overviewRows[#overviewRows + 1] = truncateRow("Build tags  " .. tagStr, math.floor(72 * sc + 24))
    end
    if showCausalDetail then
        overviewRows[#overviewRows + 1] = "--- Damage trace (detail) ---"
        if summary.lastDamageToPlayerLineTechnical then
            overviewRows[#overviewRows + 1] = truncateRow("Last hit detail  " .. tostring(summary.lastDamageToPlayerLineTechnical), 80)
        end
        if summary.lastMajorProcLineTechnical then
            overviewRows[#overviewRows + 1] = truncateRow("Proc detail  " .. tostring(summary.lastMajorProcLineTechnical), 80)
        end
        if summary.damageTracePrimarySource then
            overviewRows[#overviewRows + 1] = truncateRow("First dealt: " .. tostring(summary.damageTracePrimarySource), 80)
        end
        if summary.damageTraceLastEventSource then
            overviewRows[#overviewRows + 1] = truncateRow("Last dealt: " .. tostring(summary.damageTraceLastEventSource), 80)
        end
        if summary.damageTraceLastIncomingSource then
            overviewRows[#overviewRows + 1] = truncateRow("Last incoming: " .. tostring(summary.damageTraceLastIncomingSource), 80)
        end
        if summary.visibleBuffCount ~= nil then
            overviewRows[#overviewRows + 1] = "Statuses at end  " .. tostring(summary.visibleBuffCount)
        end
    end

    local buildStats = latestBuild and latestBuild.stats or {}
    local combatRows = {
        string.format("Total Damage  %d", tonumber(summary.totalDamageDealt or 0) or 0),
        string.format("Ultimate  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.ultimate or 0) or 0),
        string.format("Explosions  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.explosion or 0) or 0),
        string.format("Procs  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.proc or 0) or 0),
        string.format("Melee  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.melee or 0) or 0),
        string.format("Physical  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.physical or 0) or 0),
        string.format("Magical  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.magical or 0) or 0),
        string.format("True  %d", tonumber(summary.damageBreakdown and summary.damageBreakdown.true_damage or 0) or 0),
    }

    local statRows = {
        string.format("Armor  %d", tonumber(buildStats.armor or 0) or 0),
        string.format("Max HP  %d", tonumber(buildStats.max_hp or 0) or 0),
        string.format("Luck  %s", formatPercent(buildStats.luck_pct or 0)),
        string.format("Bullet Damage  %d", tonumber(buildStats.bullet_damage or 0) or 0),
        string.format("Damage Bonus  %s", formatPercent(buildStats.damage_multiplier_pct or 0)),
        string.format("Crit Chance  %s", formatPercent(buildStats.crit_chance_pct or 0)),
        string.format("Move Speed  %d", tonumber(buildStats.move_speed or 0) or 0),
    }

    local highScoreRows = {}
    for index, entry in ipairs(topRuns or {}) do
        highScoreRows[#highScoreRows + 1] = string.format(
            "%d. %d pts  |  L%d  |  R%d  |  $%d",
            index,
            tonumber(entry.score or 0) or 0,
            tonumber(entry.level or 0) or 0,
            tonumber(entry.rooms or 0) or 0,
            tonumber(entry.gold or 0) or 0
        )
    end
    if #highScoreRows == 0 then
        highScoreRows[1] = "No runs saved yet"
    end
    local sourceRows = buildSourceSummaryRows(runMeta)

    -- High Scores first (opaque) so "RUN RECAP" never bleeds through; title only in the column to the right.
    drawPanel(leftX, margin, leftW, highScoresH, "High Scores", highScoreRows, { 0.9, 0.78, 0.48 }, {
        ui_scale = sc,
        opaque_fill = true,
    })

    love.graphics.setFont(fonts.title)
    love.graphics.setColor(0.96, 0.82, 0.36, 1)
    love.graphics.printf("RUN RECAP", titleX, topY, titleW, "left")
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(0.86, 0.8, 0.72, 1)
    love.graphics.printf(
        string.format(
            "Outcome  %s   |   Score  %d",
            string.upper(tostring(summary.outcome or "death")),
            RunScoreboard.computeScore(stats)
        ),
        titleX,
        topY + fonts.title:getHeight() + math.floor(8 * sc + 0.5),
        titleW,
        "left"
    )

    local lowerY = headerH + math.floor(16 * sc + 0.5)
    local topPanelH = math.floor(228 * sc + 0.5)
    local footerReserve = math.floor(48 * sc + 0.5)
    local bottomPanelH = screenH - lowerY - topPanelH - gutter - footerReserve
    if bottomPanelH < math.floor(100 * sc + 0.5) then
        topPanelH = math.max(
            math.floor(160 * sc + 0.5),
            screenH - lowerY - gutter - footerReserve - math.floor(100 * sc + 0.5)
        )
        bottomPanelH = screenH - lowerY - topPanelH - gutter - footerReserve
    end
    local perksPanelH = math.floor(bottomPanelH * 0.42)
    local tracePanelY = lowerY + topPanelH + gutter + perksPanelH + gutter
    local tracePanelH = bottomPanelH - perksPanelH - gutter
    local overviewBottomPad = math.floor(40 * sc + 0.5)

    drawPanel(leftX, lowerY, leftW, screenH - lowerY - overviewBottomPad, "Overview", overviewRows, { 0.93, 0.75, 0.31 }, {
        ui_scale = sc,
        bottom_pad = math.floor(20 * sc + 0.5),
    })
    drawPanel(rightX, lowerY, rightColW, topPanelH, "Combat Breakdown", combatRows, { 0.86, 0.46, 0.31 }, {
        ui_scale = sc,
    })
    drawPanel(rightX + rightColW + gutter, lowerY, rightCol2W, topPanelH, "Build Stats", statRows, { 0.74, 0.62, 0.34 }, {
        ui_scale = sc,
    })

    drawPanel(rightX, lowerY + topPanelH + gutter, rightColW, bottomPanelH, "Weapons & Gear", buildLoadoutRows(latestBuild), { 0.57, 0.73, 0.42 }, {
        ui_scale = sc,
    })
    drawPanel(rightX + rightColW + gutter, lowerY + topPanelH + gutter, rightCol2W, perksPanelH, "Perks", buildPerkRows(latestBuild), { 0.55, 0.7, 0.82 }, {
        ui_scale = sc,
    })
    drawPanel(rightX + rightColW + gutter, tracePanelY, rightCol2W, tracePanelH, "Damage Sources", sourceRows, { 0.9, 0.52, 0.44 }, {
        ui_scale = sc,
    })

    local footerY = screenH - math.floor(26 * sc + 0.5)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.78, 0.74, 0.68, 1)
    love.graphics.printf(
        "T  Causal detail   |   C  Copy report   |   X  Copy damage trace   |   ENTER  Retry   |   ESC  Menu",
        margin,
        footerY,
        fullW,
        "center"
    )
    if copyMessage then
        love.graphics.setColor(0.96, 0.82, 0.36, 1)
        love.graphics.printf(copyMessage, margin, footerY - math.floor(22 * sc + 0.5), fullW, "center")
    end
end

return run_recap
