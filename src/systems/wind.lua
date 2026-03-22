-- Wind system — visual particles and physical force for the train world.
-- Particles stream right→left in world space (headwind from train movement).
-- Physical force is a gentle leftward nudge applied each frame by game.lua.

local Wind = {}

Wind.active = false

local BASE_FORCE    = -55   -- px/s leftward push (base headwind)
local GUST_FORCE    = -160  -- px/s during a gust
local GUST_MIN_DUR  = 0.6
local GUST_MAX_DUR  = 2.0
local GUST_MIN_WAIT = 3.0
local GUST_MAX_WAIT = 9.0

local _force        = BASE_FORCE
local _targetForce  = BASE_FORCE
local _isGusting    = false
local _gustTimer    = 0
local _nextGustIn   = 0

-- Particle pool
local _particles   = {}
local _spawnTimer  = 0

-- Camera snapshot set each update (used for particle spawning)
local _camX, _camY, _viewW, _viewH = 0, 0, 426, 240

local function rnd(a, b) return a + math.random() * (b - a) end

function Wind.activate()
    Wind.active    = true
    _force         = BASE_FORCE
    _targetForce   = BASE_FORCE
    _isGusting     = false
    _gustTimer     = 0
    _nextGustIn    = rnd(GUST_MIN_WAIT, GUST_MAX_WAIT)
    _particles     = {}
    _spawnTimer    = 0
end

function Wind.deactivate()
    Wind.active  = false
    _particles   = {}
end

--- Returns the current physics force (px/s to apply to vx each second).
function Wind.getForce()
    return _force
end

function Wind.isGusting()
    return _isGusting
end

function Wind.update(dt, camX, camY, viewW, viewH)
    if not Wind.active then return end

    _camX, _camY   = camX, camY
    _viewW, _viewH = viewW or 426, viewH or 240

    -- ── Gust state machine ────────────────────────────────────────────
    if _isGusting then
        _gustTimer = _gustTimer - dt
        if _gustTimer <= 0 then
            _isGusting    = false
            _targetForce  = BASE_FORCE
            _nextGustIn   = rnd(GUST_MIN_WAIT, GUST_MAX_WAIT)
        end
    else
        _nextGustIn = _nextGustIn - dt
        if _nextGustIn <= 0 then
            _isGusting   = true
            _gustTimer   = rnd(GUST_MIN_DUR, GUST_MAX_DUR)
            _targetForce = GUST_FORCE
        end
    end

    -- Smoothly lerp force toward target (0.6s half-life)
    _force = _force + (_targetForce - _force) * math.min(1, dt * 5)

    -- ── Particle spawning ─────────────────────────────────────────────
    -- More particles (and faster) during gusts
    local rate = _isGusting and 0.018 or 0.055   -- seconds per particle
    _spawnTimer = _spawnTimer - dt
    while _spawnTimer <= 0 do
        _spawnTimer = _spawnTimer + rate

        local speed = _isGusting and rnd(240, 380) or rnd(120, 200)
        local len   = _isGusting and rnd(14, 28)  or rnd(5, 14)
        local alpha = rnd(0.25, 0.65)
        -- Spawn at the right edge of the visible area (+small random margin)
        local spawnX = _camX + _viewW * 0.5 + rnd(0, 40)
        local spawnY = _camY + rnd(-_viewH * 0.5, _viewH * 0.5)

        table.insert(_particles, {
            x     = spawnX,
            y     = spawnY,
            vx    = -speed,
            vy    = rnd(-15, 15),
            len   = len,
            life  = rnd(0.3, 0.9),
            maxL  = 1,   -- set below
            alpha = alpha,
        })
        _particles[#_particles].maxL = _particles[#_particles].life
    end

    -- ── Particle update ───────────────────────────────────────────────
    local i = 1
    local leftEdge = _camX - _viewW * 0.5 - 50
    while i <= #_particles do
        local p = _particles[i]
        p.x    = p.x + p.vx * dt
        p.y    = p.y + p.vy * dt
        p.life = p.life - dt
        if p.life <= 0 or p.x < leftEdge then
            _particles[i] = _particles[#_particles]
            _particles[#_particles] = nil
        else
            i = i + 1
        end
    end
end

--- Draw particles (call inside camera:attach block, world-space coordinates).
function Wind.draw()
    if not Wind.active or #_particles == 0 then return end

    love.graphics.setLineWidth(1)
    for _, p in ipairs(_particles) do
        local fade = p.life / p.maxL
        -- Desert-dust colour: warm tan/white
        love.graphics.setColor(0.95, 0.88, 0.70, p.alpha * fade)
        local ex = p.x + p.len   -- tail is to the right (direction it came from)
        love.graphics.line(p.x, p.y, ex, p.y)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Wind
