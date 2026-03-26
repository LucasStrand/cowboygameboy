local ImpactFX = require("src.systems.impact_fx")
local GameRng = require("src.systems.game_rng")
local Sfx = require("src.systems.sfx")

local Bullet = {}
Bullet.__index = Bullet

local AMMO_SHEET_PATH = "assets/weapons/Ammunition/Normal/Set 32x32.png"
local AMMO_TILE = 32
-- Ammo art faces diagonally in-sheet; compensate so sprite forward matches travel angle.
local AMMO_ANGLE_OFFSET = math.pi * 0.25
local ammoSheet = nil
local ammoSheetAttempted = false
local ammoQuads = nil

local function getAmmoSheet()
    if ammoSheetAttempted then
        return ammoSheet
    end
    ammoSheetAttempted = true
    local ok, img = pcall(love.graphics.newImage, AMMO_SHEET_PATH)
    if ok and img then
        img:setFilter("nearest", "nearest")
        ammoSheet = img
    end
    return ammoSheet
end

local function getAmmoQuads()
    if ammoQuads then
        return ammoQuads
    end
    local sheet = getAmmoSheet()
    if not sheet then
        return nil
    end
    -- Keep these indices centralized so swapping bullet art is one edit.
    local function q(col, row)
        return love.graphics.newQuad(col * AMMO_TILE, row * AMMO_TILE, AMMO_TILE, AMMO_TILE, sheet:getDimensions())
    end
    ammoQuads = {
        player = q(0, 0),
        enemy = q(1, 0),
        ult = q(2, 0),
    }
    return ammoQuads
end

function Bullet.new(data)
    local self = setmetatable({}, Bullet)
    self.x = data.x
    self.y = data.y
    -- Small axis-aligned hitbox (visual is drawn along travel direction below).
    self.w = data.w or 3
    self.h = data.h or 2
    self.angle = data.angle
    self.speed = data.speed or 500
    self.packet = data.packet
    self.source_actor = data.source_actor
    self.damage = data.damage or (self.packet and self.packet.base_max) or 10
    self.explosive = data.explosive or false
    self.ricochet = self.explosive and 0 or (data.ricochet or 0)
    self.fromEnemy = data.fromEnemy or false
    self.ultBullet = data.ultBullet or false
    self.source_ref = data.source_ref or (self.packet and self.packet.source) or nil
    self.packet_kind = data.packet_kind or (self.packet and self.packet.kind) or nil
    self.damage_family = data.damage_family or (self.packet and self.packet.family) or nil
    self.damage_tags = data.damage_tags or (self.packet and self.packet.tags) or nil
    local metadata = self.packet and self.packet.metadata or {}
    self.impact_fx_id = data.impact_fx_id or metadata.impact_fx_id
    self.muzzle_fx_id = data.muzzle_fx_id or metadata.muzzle_fx_id
    self.explosion_tier = data.explosion_tier or metadata.explosion_tier
    self.explosion_sfx_id = data.explosion_sfx_id or metadata.explosion_sfx_id or "explosion"
    self.isBullet = true
    self.alive = true
    self.lifetime = 3
    return self
end

function Bullet:update(dt, world)
    self.lifetime = self.lifetime - dt
    if self.lifetime <= 0 then
        self.alive = false
        return
    end

    local vx = math.cos(self.angle) * self.speed
    local vy = math.sin(self.angle) * self.speed

    local goalX = self.x + vx * dt
    local goalY = self.y + vy * dt

    local actualX, actualY, cols, len = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    for i = 1, len do
        local col = cols[i]
        local other = col.other

        if other.isEnemy and not self.fromEnemy then
            self.hitEnemy = other
            self.alive = false
            return
        end

        if other.isPlayer and self.fromEnemy then
            self.hitPlayer = true
            self.alive = false
            return
        end

        if not other.isEnemy and not other.isPickup and not other.isBullet and not other.isDoor and not other.isPlayer then
            if self.explosive then
                if not self.fromEnemy then
                    Sfx.play(self.explosion_sfx_id)
                end
                ImpactFX.spawn(
                    self.x + self.w / 2,
                    self.y + self.h / 2,
                    self.impact_fx_id or "explosion_medium",
                    { scale_mul = 0.78 }
                )
                self.alive = false
                return
            elseif self.ricochet > 0 then
                self.ricochet = self.ricochet - 1
                if col.normal.x ~= 0 then
                    self.angle = math.pi - self.angle
                elseif col.normal.y ~= 0 then
                    self.angle = -self.angle
                end
                self.x = self.x + col.normal.x * 2
                self.y = self.y + col.normal.y * 2
                world:update(self, self.x, self.y)
                if not self.fromEnemy then
                    local meta = self.packet and self.packet.metadata
                    local wid = meta and meta.source_weapon_id
                    if wid == "revolver" then
                        local idx = GameRng.random("revolver_ricochet", 1, 3)
                        local ids = { "ricochet_revolver_1", "ricochet_revolver_2", "ricochet_revolver_3" }
                        Sfx.play(ids[idx])
                    else
                        Sfx.play("ricochet")
                    end
                end
                if debugLog then debugLog("Ricochet bounce (" .. self.ricochet .. " left)") end
                return
            else
                if not self.fromEnemy then
                    Sfx.play("hit_wall")
                end
                ImpactFX.spawn(
                    self.x + self.w / 2,
                    self.y + self.h / 2,
                    "hit_wall",
                    { angle = self.angle }
                )
                self.alive = false
                return
            end
        end
    end
end

function Bullet.filter(item, other)
    if other.isBullet then return nil end
    if other.isPickup then return nil end
    if item.fromEnemy and other.isEnemy then return nil end
    if not item.fromEnemy and other.isPlayer then return nil end
    if other.isDoor then return nil end
    -- Solid geometry blocks shots and line-of-sight probes (isPlatform / isWall)
    if other.isPlatform or other.isWall then
        return "slide"
    end
    return "cross"
end

function Bullet:draw()
    local cx = self.x + self.w * 0.5
    local cy = self.y + self.h * 0.5
    local quads = getAmmoQuads()
    local sheet = getAmmoSheet()

    if quads and sheet then
        local quad = quads.player
        if self.ultBullet then
            quad = quads.ult or quad
        elseif self.fromEnemy then
            quad = quads.enemy or quad
        end

        local targetSize = self.ultBullet and 11 or 8
        local scale = targetSize / AMMO_TILE
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            sheet,
            quad,
            cx,
            cy,
            self.angle + AMMO_ANGLE_OFFSET,
            scale,
            scale,
            AMMO_TILE * 0.5,
            AMMO_TILE * 0.5
        )
        return
    end

    -- Fallback: procedural slug if ammo sheet fails to load.
    local len = self.ultBullet and 8.5 or 5.5
    local halfW = self.ultBullet and 1.15 or 0.95

    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.angle)

    if self.ultBullet then
        love.graphics.setColor(0.95, 0.72, 0.2)
        love.graphics.rectangle("fill", -len * 0.5 + 0.4, -halfW, len - 1.2, halfW * 2, 0.45, 0.45)
        love.graphics.setColor(1, 0.95, 0.55)
        love.graphics.rectangle("fill", len * 0.5 - 1.6, -halfW * 0.7, 1.6, halfW * 1.4, 0.35, 0.35)
    elseif self.fromEnemy then
        love.graphics.setColor(0.55, 0.14, 0.12)
        love.graphics.rectangle("fill", -len * 0.5 + 0.4, -halfW, len - 1.2, halfW * 2, 0.45, 0.45)
        love.graphics.setColor(1, 0.45, 0.38)
        love.graphics.rectangle("fill", len * 0.5 - 1.35, -halfW * 0.72, 1.35, halfW * 1.44, 0.3, 0.3)
    else
        love.graphics.setColor(0.5, 0.38, 0.14)
        love.graphics.rectangle("fill", -len * 0.5 + 0.4, -halfW, len - 1.2, halfW * 2, 0.45, 0.45)
        love.graphics.setColor(0.92, 0.88, 0.78)
        love.graphics.rectangle("fill", len * 0.5 - 1.35, -halfW * 0.72, 1.35, halfW * 1.44, 0.3, 0.3)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return Bullet
