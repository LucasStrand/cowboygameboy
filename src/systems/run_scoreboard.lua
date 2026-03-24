local RunScoreboard = {}

local SAVE_PATH = "run_scoreboard.lua"
local MAX_RUNS = 8

local cached = nil

local function escapeString(value)
    return string.format("%q", tostring(value or ""))
end

local function cloneRuns(runs)
    local out = {}
    for _, entry in ipairs(runs or {}) do
        if type(entry) == "table" then
            out[#out + 1] = {
                score = math.max(0, tonumber(entry.score or 0) or 0),
                level = math.max(0, tonumber(entry.level or 0) or 0),
                rooms = math.max(0, tonumber(entry.rooms or 0) or 0),
                gold = math.max(0, tonumber(entry.gold or 0) or 0),
                outcome = type(entry.outcome) == "string" and entry.outcome ~= "" and entry.outcome or "unknown",
                world_name = type(entry.world_name) == "string" and entry.world_name ~= "" and entry.world_name
                    or "unknown",
                summary = type(entry.summary) == "string" and entry.summary or "",
            }
        end
    end
    return out
end

local function sortRuns(runs)
    table.sort(runs, function(a, b)
        if (a.score or 0) == (b.score or 0) then
            if (a.rooms or 0) == (b.rooms or 0) then
                return (a.level or 0) > (b.level or 0)
            end
            return (a.rooms or 0) > (b.rooms or 0)
        end
        return (a.score or 0) > (b.score or 0)
    end)
end

local function serialize(runs)
    local lines = {
        "return {",
        "  runs = {",
    }
    for _, entry in ipairs(runs or {}) do
        lines[#lines + 1] = string.format(
            "    { score = %d, level = %d, rooms = %d, gold = %d, outcome = %s, world_name = %s, summary = %s },",
            tonumber(entry.score or 0) or 0,
            tonumber(entry.level or 0) or 0,
            tonumber(entry.rooms or 0) or 0,
            tonumber(entry.gold or 0) or 0,
            escapeString(entry.outcome or "unknown"),
            escapeString(entry.world_name or "unknown"),
            escapeString(entry.summary or "")
        )
    end
    lines[#lines + 1] = "  }"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

local function ensureLoaded()
    if cached ~= nil then
        return cached
    end

    cached = { runs = {} }
    local info = love.filesystem.getInfo(SAVE_PATH)
    if not info then
        return cached
    end

    local okLoad, chunk = pcall(love.filesystem.load, SAVE_PATH)
    if not okLoad or not chunk then
        return cached
    end

    local okData, data = pcall(chunk)
    if not okData or type(data) ~= "table" then
        return cached
    end

    cached.runs = cloneRuns(data.runs)
    sortRuns(cached.runs)
    return cached
end

function RunScoreboard.computeScore(s)
    s = s or {}
    local gold = tonumber(s.gold or 0) or 0
    local rooms = tonumber(s.roomsCleared or s.rooms or 0) or 0
    local level = tonumber(s.level or 1) or 1
    local perks = tonumber(s.perksCount or s.perks or 0) or 0
    return gold + rooms * 100 + level * 50 + perks * 75
end

function RunScoreboard.recordRun(stats, summary)
    local store = ensureLoaded()
    local entry = {
        score = RunScoreboard.computeScore(stats),
        level = tonumber(stats and stats.level or 0) or 0,
        rooms = tonumber(summary and summary.roomsCleared or stats and stats.roomsCleared or 0) or 0,
        gold = tonumber(stats and stats.gold or 0) or 0,
        outcome = summary and summary.outcome or stats and stats.outcome or "unknown",
        world_name = summary and (summary.worldName or summary.worldId) or "unknown",
        summary = summary and summary.dominantTags and #summary.dominantTags > 0
            and table.concat(summary.dominantTags, ", ")
            or "",
    }
    local snapshot = cloneRuns(store.runs)
    table.insert(store.runs, entry)
    sortRuns(store.runs)
    while #store.runs > MAX_RUNS do
        table.remove(store.runs)
    end
    local ok, err = pcall(love.filesystem.write, SAVE_PATH, serialize(store.runs))
    if not ok then
        store.runs = snapshot
        return cloneRuns(store.runs)
    end
    return cloneRuns(store.runs)
end

function RunScoreboard.getRuns()
    local store = ensureLoaded()
    return cloneRuns(store.runs)
end

return RunScoreboard
