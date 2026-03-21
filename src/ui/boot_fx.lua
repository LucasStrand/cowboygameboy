--[[
  Procedural western boot-screen effects: dust, scanlines, film flicker, horizon hero band,
  sun flares, rolling hay bale.
  State (dust positions) is owned by the caller; pass a table `dust` with `.motes` array.
]]

local BootFx = {}

local function pushBlendAdd()
    love.graphics.setBlendMode("add", "alphamultiply")
end

local function popBlendAlpha()
    love.graphics.setBlendMode("alpha", "alphamultiply")
end

local function hash2d(i, seed)
    local x = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
    return x - math.floor(x)
end

--- Initialize or resize dust motes. `dustState` = { motes = { {x,y,vx,vy,a,r}, ... } }
function BootFx.initDust(dustState, count, w, h, seed)
    seed = seed or 1
    dustState.motes = {}
    for i = 1, count do
        dustState.motes[i] = {
            x = hash2d(i, seed) * w,
            y = hash2d(i + 17, seed) * h,
            vx = (hash2d(i + 3, seed) - 0.5) * 14,
            vy = (hash2d(i + 5, seed) - 0.35) * -10,
            a = 0.12 + hash2d(i + 7, seed) * 0.35,
            r = 0.6 + hash2d(i + 9, seed) * 1.4,
        }
    end
end

function BootFx.updateDust(dustState, dt, w, h)
    if not dustState.motes then return end
    for _, m in ipairs(dustState.motes) do
        m.x = m.x + m.vx * dt
        m.y = m.y + m.vy * dt
        if m.x < -4 then m.x = w + 4 end
        if m.x > w + 4 then m.x = -4 end
        if m.y < -4 then m.y = h + 4 end
        if m.y > h + 4 then m.y = -4 end
    end
end

function BootFx.drawDust(dustState, mul, dustColor)
    mul = mul or 1
    if not dustState.motes then return end
    local dr = dustColor and dustColor[1] or 0.85
    local dg = dustColor and dustColor[2] or 0.78
    local db = dustColor and dustColor[3] or 0.62
    for _, m in ipairs(dustState.motes) do
        love.graphics.setColor(dr, dg, db, m.a * mul)
        love.graphics.circle("fill", m.x, m.y, m.r)
    end
end

function BootFx.drawScanlines(w, h, alpha)
    love.graphics.setColor(0, 0, 0, alpha)
    local step = 4
    for y = 0, h, step do
        love.graphics.rectangle("fill", 0, y, w, 1)
    end
end

--- Subtle random dimming (call after base fill; uses alpha)
function BootFx.drawFilmFlicker(w, h, strength, t)
    local j = (love.math.random() - 0.5) * 2 * strength
    j = math.max(0, math.min(0.12, j + math.sin(t * 21.7) * strength * 0.5))
    love.graphics.setColor(0, 0, 0, j)
    love.graphics.rectangle("fill", 0, 0, w, h)
end

function BootFx.drawAccentLines(w, h, y1, y2, color, alphaMul)
    alphaMul = alphaMul or 1
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    a = a * alphaMul
    love.graphics.setColor(r, g, b, a * 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, y1, w, y1)
    love.graphics.line(0, y2, w, y2)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(r, g, b, a)
    love.graphics.line(w * 0.18, y1 + 1, w * 0.82, y1 + 1)
    love.graphics.line(w * 0.18, y2 - 1, w * 0.82, y2 - 1)
    love.graphics.setLineWidth(1)
end

--- Parchment / aged paper fill with subtle horizontal grain.
function BootFx.drawParchmentBg(w, h, bgColor, t)
    local br, bg, bb = bgColor[1], bgColor[2], bgColor[3]
    love.graphics.setColor(br, bg, bb, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    -- Horizontal grain streaks (very subtle tone variation)
    love.graphics.setLineWidth(1)
    local seed = 7.31
    for y = 0, h, 3 do
        local n = math.sin(y * 0.37 + seed) * 0.5 + math.sin(y * 1.13 + seed * 2.7) * 0.3
        local drift = math.sin(t * 0.3 + y * 0.01) * 0.008
        local tone = 0.03 * n + drift
        if tone > 0 then
            love.graphics.setColor(1, 0.95, 0.85, tone)
        else
            love.graphics.setColor(0, 0, 0, -tone)
        end
        love.graphics.line(0, y, w, y)
    end
    love.graphics.setLineWidth(1)
end

--- Edge vignette: darkens corners and borders without washing the center.
function BootFx.drawEdgeVignette(w, h, color)
    local cr, cg, cb, ca = color[1], color[2], color[3], color[4] or 0.45
    local bandW = w * 0.28
    local bandH = h * 0.22
    -- Left / right strips
    for x = 0, math.floor(bandW) do
        local k = 1 - (x / bandW)
        love.graphics.setColor(cr, cg, cb, ca * k * k)
        love.graphics.rectangle("fill", x, 0, 1, h)
        love.graphics.rectangle("fill", w - 1 - x, 0, 1, h)
    end
    -- Top / bottom strips
    for y = 0, math.floor(bandH) do
        local k = 1 - (y / bandH)
        love.graphics.setColor(cr, cg, cb, ca * k * k * 0.7)
        love.graphics.rectangle("fill", 0, y, w, 1)
        love.graphics.rectangle("fill", 0, h - 1 - y, w, 1)
    end
end

--- Vertical gradient dim: fades from maxAlpha at `y` to 0 at `y + height`.
function BootFx.drawGradientDim(w, y, height, maxAlpha)
    if height < 1 or maxAlpha <= 0 then return end
    for i = 0, math.floor(height) do
        local k = 1 - (i / height)
        love.graphics.setColor(0, 0, 0, maxAlpha * k * k)
        love.graphics.rectangle("fill", 0, y + i, w, 1)
    end
end

--- Warm lens streaks and orbs (call with sun already drawn; uses additive blending).
function BootFx.drawSunFlares(sunX, sunY, sunR, w, h, t)
    pushBlendAdd()
    local pulse = 0.85 + math.sin(t * 1.9) * 0.08
    -- Horizontal streak through sun
    love.graphics.setColor(1, 0.45, 0.12, 0.14 * pulse)
    love.graphics.polygon(
        "fill",
        -40,
        sunY - 3,
        w + 40,
        sunY - 1,
        w + 40,
        sunY + 4,
        -40,
        sunY + 2
    )
    -- Diagonal secondary
    love.graphics.setColor(1, 0.35, 0.2, 0.08 * pulse)
    love.graphics.polygon(
        "fill",
        sunX - 120,
        sunY + 80,
        sunX + 220,
        sunY - 140,
        sunX + 200,
        sunY - 120,
        sunX - 100,
        sunY + 100
    )
    -- Ghost orbs (lens artifacts)
    local orbs = {
        { sunX - sunR * 2.8, sunY + sunR * 0.4, 28, 0.06, 0.5, 0.85 },
        { sunX + sunR * 3.2, sunY - sunR * 0.2, 18, 0.08, 0.35, 0.9 },
        { sunX - sunR * 1.2, sunY - sunR * 2.1, 14, 0.1, 0.55, 0.95 },
    }
    for _, o in ipairs(orbs) do
        love.graphics.setColor(o[4], o[5], o[6], 0.12 * pulse)
        love.graphics.circle("fill", o[1], o[2], o[3])
    end
    popBlendAlpha()
end

--- Tumbleweed: round, spiky, straw-colored.
function BootFx.drawHayBale(cx, cy, rot, r, t)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rot)

    -- Core: round straw mass
    love.graphics.setColor(0.62, 0.48, 0.28, 1)
    love.graphics.circle("fill", 0, 0, r)
    love.graphics.setColor(0.52, 0.38, 0.20, 1)
    love.graphics.circle("fill", 0, 0, r * 0.7)

    -- Spiky branches radiating outward
    love.graphics.setLineWidth(2)
    local spokes = 14
    for i = 0, spokes - 1 do
        local ang = (i / spokes) * math.pi * 2
        local len = r * (0.85 + hash2d(i + 31, 5) * 0.55)
        local x0, y0 = math.cos(ang) * r * 0.35, math.sin(ang) * r * 0.35
        local x1, y1 = math.cos(ang) * len, math.sin(ang) * len
        love.graphics.setColor(0.55, 0.42, 0.22, 0.85)
        love.graphics.line(x0, y0, x1, y1)
        -- Small fork at end
        local fa = ang + 0.35
        local fb = ang - 0.3
        local fl = len * 0.3
        love.graphics.setColor(0.50, 0.38, 0.20, 0.6)
        love.graphics.line(x1, y1, x1 + math.cos(fa) * fl, y1 + math.sin(fa) * fl)
        love.graphics.line(x1, y1, x1 + math.cos(fb) * fl, y1 + math.sin(fb) * fl)
    end

    -- Inner tangle lines
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.45, 0.34, 0.18, 0.5)
    for i = 0, 5 do
        local a1 = hash2d(i + 50, 9) * math.pi * 2
        local a2 = hash2d(i + 60, 9) * math.pi * 2
        local l1, l2 = r * 0.5, r * 0.55
        love.graphics.line(
            math.cos(a1) * l1, math.sin(a1) * l1,
            math.cos(a2) * l2, math.sin(a2) * l2
        )
    end

    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

--- Fills 0..bandY; bottom rows blend into the hero band's top color (purple-dusk)
--- to eliminate the visible seam at bandY.
function BootFx.drawSkyBackdrop(w, bandY, t)
    bandY = math.floor(bandY)
    if bandY < 1 then
        return
    end
    -- Match hero band top row (k=0): (0.18, 0.08, 0.28)
    local tr, tg, tb = 0.18, 0.08, 0.28
    for y = 0, bandY - 1 do
        local k = y / bandY
        local r = 0.08 + k * (tr - 0.08)
        local g = 0.04 + k * (tg - 0.04)
        local b = 0.12 + k * (tb - 0.12)
        local sh = 1 + math.sin(t * 0.7 + y * 0.02) * 0.015
        love.graphics.setColor(r * sh, g * sh, b * sh, 1)
        love.graphics.rectangle("fill", 0, y, w, 1)
    end
end

--- Small drifting birds (screen coords)
function BootFx.drawBirds(w, bandY, t)
    love.graphics.setColor(0.08, 0.06, 0.07, 0.65)
    for i = 1, 4 do
        local bx = (w * 0.2 * i + t * 12 + i * 40) % (w + 80) - 40
        local by = bandY + 18 + math.sin(t * 0.8 + i) * 6
        local s = 5 + i
        love.graphics.line(bx - s, by, bx, by - s * 0.5)
        love.graphics.line(bx, by - s * 0.5, bx + s, by)
    end
end

--[[
  Hero band: vivid sunset, sun + flares, mesa, foreground hay bale optional.
  Returns sunX, sunY, sunR for layering hints.
]]
function BootFx.drawHorizonHero(w, h, bandY, bandH, t)
    local by = bandY
    local bh = bandH
    -- Sky: deep blue-violet top → warm peach → bright orange at horizon
    for i = 0, bh do
        local k = i / bh
        local r, g, b
        if k < 0.3 then
            local u = k / 0.3
            r = 0.18 + u * 0.30
            g = 0.08 + u * 0.14
            b = 0.28 + u * (-0.05)
        elseif k < 0.6 then
            local u = (k - 0.3) / 0.3
            r = 0.48 + u * 0.38
            g = 0.22 + u * 0.28
            b = 0.23 + u * (-0.08)
        else
            local u = (k - 0.6) / 0.4
            r = 0.86 + u * 0.12
            g = 0.50 + u * 0.30
            b = 0.15 + u * 0.05
        end
        love.graphics.setColor(r, g, b, 1)
        love.graphics.rectangle("fill", 0, by + i, w, 1)
    end

    BootFx.drawBirds(w, by, t)

    -- Sun (drift + “heat” shimmer)
    local sunX = w * 0.72 + math.sin(t * 0.35) * 10
    local sunY = by + bh * 0.36 + math.sin(t * 1.1) * 3
    local sunR = 44
    -- Warm orange glow rings
    for i = 6, 1, -1 do
        love.graphics.setColor(1, 0.55 + i * 0.04, 0.18, 0.07 * i)
        love.graphics.circle("fill", sunX, sunY, sunR + i * 14)
    end
    love.graphics.setColor(1, 0.82, 0.28, 1)
    love.graphics.circle("fill", sunX, sunY, sunR)
    love.graphics.setColor(1, 0.92, 0.55, 0.6)
    love.graphics.circle("fill", sunX - 8, sunY - 6, sunR * 0.38)

    BootFx.drawSunFlares(sunX, sunY, sunR, w, h, t)

    -- Ground plane: warm dusty brown, gradient from horizon to bottom
    local gTop = by + bh * 0.6
    local gH = bh * 0.42
    for gi = 0, math.floor(gH) do
        local gk = gi / gH
        local gr = 0.30 - gk * 0.12
        local gg = 0.18 - gk * 0.07
        local gb = 0.10 - gk * 0.04
        love.graphics.setColor(gr, gg, gb, 1)
        love.graphics.rectangle("fill", 0, gTop + gi, w, 1)
    end
    -- Horizon rim glow
    love.graphics.setColor(0.7, 0.42, 0.18, 0.3)
    love.graphics.rectangle("fill", 0, by + bh * 0.56, w, bh * 0.08)

    -- Mesa silhouette (warm dark brown, not black)
    love.graphics.setColor(0.14, 0.09, 0.06, 1)
    local base = by + bh * 0.56
    love.graphics.polygon(
        "fill",
        0,
        base + 40,
        w * 0.15,
        base,
        w * 0.22,
        base + 12,
        w * 0.35,
        base - 8,
        w * 0.5,
        base + 20,
        w * 0.68,
        base + 4,
        w * 0.82,
        base + 28,
        w,
        base + 50,
        w,
        by + bh,
        0,
        by + bh
    )

    -- Revolver + saloon “suggestion”: cylinder + window rects (very abstract)
    love.graphics.setColor(0.12, 0.08, 0.05, 0.9)
    love.graphics.rectangle("fill", w * 0.12, base + 18, 52, 22, 3, 3)
    love.graphics.setColor(0.28, 0.2, 0.12, 0.85)
    for c = 0, 5 do
        local cx = w * 0.12 + 10 + c * 7
        love.graphics.circle("line", cx, base + 29, 3)
    end
    love.graphics.setColor(0.15, 0.10, 0.07, 1)
    love.graphics.rectangle("fill", w * 0.78, base - 2, 36, 42, 2, 2)
    love.graphics.setColor(0.42, 0.32, 0.18, 0.9)
    love.graphics.rectangle("fill", w * 0.79, base + 6, 8, 10, 1, 1)
    love.graphics.rectangle("fill", w * 0.88, base + 6, 8, 10, 1, 1)
end

--- Rear view of a revolver cylinder: metal drum + six chambers; `filled` = rounds loaded 0..6
function BootFx.drawRevolverCylinder(cx, cy, filled, activeGold)
    local drumR = 34
    local metal = { 0.26, 0.22, 0.2 }
    local metalLine = { 0.12, 0.1, 0.09 }
    local r, g, b = activeGold[1], activeGold[2], activeGold[3]

    love.graphics.setColor(metalLine[1], metalLine[2], metalLine[3], 1)
    love.graphics.circle("line", cx, cy, drumR + 2)
    love.graphics.setColor(metal[1], metal[2], metal[3], 1)
    love.graphics.circle("fill", cx, cy, drumR)
    love.graphics.setColor(metalLine[1], metalLine[2], metalLine[3], 0.95)
    love.graphics.circle("line", cx, cy, drumR)

    local chamberR = 6.5
    local ringR = drumR * 0.52
    for i = 0, 5 do
        local ang = (i / 6) * math.pi * 2 - math.pi / 2
        local x = cx + math.cos(ang) * ringR
        local y = cy + math.sin(ang) * ringR
        if i < filled then
            love.graphics.setColor(r * 0.95, g * 0.95, b * 0.95, 1)
            love.graphics.circle("fill", x, y, chamberR)
            love.graphics.setColor(r * 0.45, g * 0.45, b * 0.45, 1)
            love.graphics.circle("line", x, y, chamberR)
        else
            love.graphics.setColor(0.07, 0.055, 0.045, 1)
            love.graphics.circle("fill", x, y, chamberR)
            love.graphics.setColor(0.22, 0.18, 0.14, 0.85)
            love.graphics.circle("line", x, y, chamberR)
        end
    end

    -- Barrel / frame stub (reads as cylinder axis)
    love.graphics.setColor(metalLine[1], metalLine[2], metalLine[3], 1)
    love.graphics.rectangle("fill", cx + drumR - 4, cy - 7, 22, 14, 2, 2)
    love.graphics.setColor(metal[1], metal[2], metal[3], 0.9)
    love.graphics.rectangle("line", cx + drumR - 4, cy - 7, 22, 14, 2, 2)
end

--- Six chamber ticks (0 = empty .. 1 = all lit). `filled` = number 0..6
function BootFx.drawChamberTicks(cx, cy, filled, radius, activeGold)
    local r, g, b = activeGold[1], activeGold[2], activeGold[3]
    for i = 0, 5 do
        local ang = (i / 6) * math.pi * 2 - math.pi / 2
        local x = cx + math.cos(ang) * radius
        local y = cy + math.sin(ang) * radius
        if i < filled then
            love.graphics.setColor(r, g, b, 1)
            love.graphics.circle("fill", x, y, 5)
            love.graphics.setColor(r * 0.5, g * 0.5, b * 0.5, 1)
            love.graphics.circle("line", x, y, 5)
        else
            love.graphics.setColor(0.15, 0.1, 0.08, 0.85)
            love.graphics.circle("fill", x, y, 5)
            love.graphics.setColor(0.35, 0.28, 0.2, 0.7)
            love.graphics.circle("line", x, y, 5)
        end
    end
end

return BootFx
