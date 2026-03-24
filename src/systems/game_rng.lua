local GameRng = {}
GameRng.__index = GameRng

local current_rng = nil

local function hashString(value)
    local hash = 5381
    local s = tostring(value or "")
    for i = 1, #s do
        hash = ((hash * 33) + string.byte(s, i)) % 2147483647
    end
    if hash == 0 then
        hash = 1
    end
    return hash
end

local function normalizeSeed(seed)
    local n = tonumber(seed)
    if not n then
        n = hashString(seed or "six-chambers")
    end
    n = math.floor(math.abs(n))
    n = (n % 2147483646) + 1
    return n
end

local function nextFloat(state)
    state = (state * 48271) % 2147483647
    return state, (state - 1) / 2147483646
end

local function fallbackRandom(a, b)
    if a == nil then
        return math.random()
    end
    if b == nil then
        return math.random(a)
    end
    return math.random(a, b)
end

function GameRng.seedFromTime()
    local t = os.time()
    if love and love.timer then
        t = t + math.floor(love.timer.getTime() * 1000000)
    end
    return normalizeSeed(t)
end

function GameRng.new(run_seed)
    local self = setmetatable({}, GameRng)
    self.run_seed = normalizeSeed(run_seed or GameRng.seedFromTime())
    self.channels = {}
    return self
end

function GameRng:setCurrent()
    current_rng = self
end

function GameRng.setCurrent(rng)
    current_rng = rng
end

function GameRng.current()
    return current_rng
end

function GameRng:_stateFor(channel)
    local key = channel or "default"
    local state = self.channels[key]
    if not state then
        state = normalizeSeed(self.run_seed + hashString(key))
        self.channels[key] = state
    end
    return key, state
end

function GameRng:float(channel, min_value, max_value)
    local key, state = self:_stateFor(channel)
    local next_state, base = nextFloat(state)
    self.channels[key] = next_state

    local minv = min_value
    local maxv = max_value
    if minv == nil then
        minv = 0
        maxv = 1
    elseif maxv == nil then
        maxv = minv
        minv = 0
    end
    return minv + (maxv - minv) * base
end

function GameRng:int(channel, min_value, max_value)
    local minv = min_value
    local maxv = max_value
    if maxv == nil then
        maxv = minv
        minv = 1
    end
    if maxv < minv then
        minv, maxv = maxv, minv
    end
    local roll = self:float(channel, 0, 1)
    return minv + math.floor(roll * (maxv - minv + 1))
end

function GameRng:chance(channel, probability)
    return self:float(channel, 0, 1) < (probability or 0)
end

function GameRng.random(channel, a, b)
    local rng = current_rng
    if not rng then
        return fallbackRandom(a, b)
    end
    if a == nil then
        return rng:float(channel, 0, 1)
    end
    if b == nil then
        return rng:int(channel, 1, a)
    end
    return rng:int(channel, a, b)
end

function GameRng.randomFloat(channel, min_value, max_value)
    local rng = current_rng
    if not rng then
        if min_value == nil then
            return math.random()
        end
        if max_value == nil then
            return math.random() * min_value
        end
        return min_value + math.random() * (max_value - min_value)
    end
    return rng:float(channel, min_value, max_value)
end

function GameRng.randomChance(channel, probability)
    local rng = current_rng
    if not rng then
        return math.random() < (probability or 0)
    end
    return rng:chance(channel, probability)
end

return GameRng
