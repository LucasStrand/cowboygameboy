--- Map Activities system: randomly places interactive encounters on platforms
--- in generated rooms. Runs after room assembly, before game loop starts.
---
--- Activities: shrines, merchants, weapon altars, wild pickups,
---             normal chests, fake-ambush chests, trapped chests,
---             secret area rewards + entrance markers.

local Shrine         = require("src.entities.shrine")
local Merchant       = require("src.entities.merchant")
local WeaponAltar    = require("src.entities.weapon_altar")
local Chest          = require("src.entities.chest")
local Pickup         = require("src.entities.pickup")
local Guns           = require("src.data.guns")
local SpikeTrap      = require("src.entities.spike_trap")
local PressurePlate  = require("src.entities.pressure_plate")
local SecretEntrance = require("src.entities.secret_entrance")
local SlotMachine    = require("src.entities.slot_machine")

local MapActivities = {}

---------------------------------------------------------------------------
-- Configuration — spawn chances per room (0..1)
---------------------------------------------------------------------------
local ACTIVITY_CHANCES = {
    shrine        = 0.25,   -- 25% chance a shrine spawns
    merchant      = 0.15,   -- 15% chance a travelling merchant
    weapon_altar  = 0.12,   -- 12% chance for a weapon altar
    normal_chest  = 0.30,   -- 30% chance for a normal loot chest
    fake_ambush   = 0.18,   -- 18% chance for a fake-ambush chest (looks scary, harmless)
    wild_pickup   = 0.35,   -- 35% chance for items in the wild
    trapped_chest = 0.22,   -- 22% chance for a pressure-plate trapped chest
    slot_machine  = 0.15,   -- 15% chance for a dusty slot machine
}

-- Maximum activities per room (keeps things from getting cluttered)
local MAX_ACTIVITIES = 3

-- Minimum distance between any two placed activities
local MIN_SPACING = 80

-- Minimum distance from player spawn and exit door
local MIN_SPAWN_CLEAR = 100
local MIN_DOOR_CLEAR  = 80

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

--- Find walkable platforms suitable for placing an activity.
--- Filters out very small platforms, one-way thin steps, and platforms
--- too close to spawn/door.
local function findSuitablePlatforms(room)
    local candidates = {}
    local spawn = room.playerSpawn
    local door  = room.exitDoor or room.door
    for _, plat in ipairs(room.platforms) do
        -- Need enough width for an activity (at least 60px)
        if plat.w >= 60 and plat.h >= 14 then
            -- Check distance from spawn
            local platCx = plat.x + plat.w / 2
            local platY  = plat.y
            local okSpawn = true
            local okDoor  = true
            if spawn then
                okSpawn = dist2(platCx, platY, spawn.x, spawn.y) > MIN_SPAWN_CLEAR * MIN_SPAWN_CLEAR
            end
            if door then
                local doorCx = door.x + (door.w or 32) / 2
                okDoor = dist2(platCx, platY, doorCx, door.y) > MIN_DOOR_CLEAR * MIN_DOOR_CLEAR
            end
            if okSpawn and okDoor then
                candidates[#candidates + 1] = plat
            end
        end
    end
    return candidates
end

--- Pick a random X on a platform, with margin from edges.
local function randomXOnPlatform(plat, objWidth, margin)
    margin = margin or 16
    local minX = plat.x + margin
    local maxX = plat.x + plat.w - objWidth - margin
    if maxX <= minX then return plat.x + plat.w / 2 - objWidth / 2 end
    return minX + math.random() * (maxX - minX)
end

---------------------------------------------------------------------------
-- Main generation function
---------------------------------------------------------------------------

--- Generate activities for a room. Returns a table of activity instances.
--- @param room table  The assembled room data (may include secretAreas)
--- @param difficulty number  Current difficulty level
--- @param roomIndex number  Which room in the sequence (1-based)
--- @return table  { shrines, merchants, weaponAltars, wildPickups, extraChests,
---                  pressurePlates, spikeTraps, secretEntrances }
function MapActivities.generate(room, difficulty, roomIndex)
    local result = {
        shrines         = {},
        merchants       = {},
        weaponAltars    = {},
        wildPickups     = {},
        extraChests     = {},
        pressurePlates  = {},
        spikeTraps      = {},
        secretEntrances = {},
        slotMachines    = {},
    }

    local platforms = findSuitablePlatforms(room)
    if #platforms == 0 then return result end

    -- Track placed positions to enforce spacing
    local placed = {}
    local activityCount = 0

    --- Try to place an activity. Returns x, y, platform or nil.
    local function tryPlace(objWidth, objHeight)
        if activityCount >= MAX_ACTIVITIES then return nil end
        -- Try up to 10 random platforms
        for _ = 1, 10 do
            local plat = platforms[math.random(#platforms)]
            local ax = randomXOnPlatform(plat, objWidth)
            local ay = plat.y - objHeight
            -- Check spacing
            local tooClose = false
            for _, pos in ipairs(placed) do
                if dist2(ax + objWidth / 2, ay, pos.x, pos.y) < MIN_SPACING * MIN_SPACING then
                    tooClose = true
                    break
                end
            end
            -- Also check spacing against existing room chests
            if not tooClose and room.chests then
                for _, ch in ipairs(room.chests) do
                    if dist2(ax + objWidth / 2, ay, ch.x + 24, ch.y) < MIN_SPACING * MIN_SPACING then
                        tooClose = true
                        break
                    end
                end
            end
            if not tooClose then
                placed[#placed + 1] = { x = ax + objWidth / 2, y = ay }
                activityCount = activityCount + 1
                return ax, ay, plat
            end
        end
        return nil
    end

    -- Roll each activity type
    -- Shrine
    if math.random() < ACTIVITY_CHANCES.shrine then
        local ax, ay = tryPlace(32, 48)
        if ax then
            local shrine = Shrine.new(ax, ay)
            result.shrines[#result.shrines + 1] = shrine
        end
    end

    -- Merchant (rarer in early rooms)
    local merchantChance = ACTIVITY_CHANCES.merchant
    if roomIndex and roomIndex <= 1 then merchantChance = merchantChance * 0.5 end
    if math.random() < merchantChance then
        local ax, ay = tryPlace(24, 36)
        if ax then
            local merchant = Merchant.new(ax, ay, difficulty)
            result.merchants[#result.merchants + 1] = merchant
        end
    end

    -- Weapon altar
    if math.random() < ACTIVITY_CHANCES.weapon_altar then
        -- Needs a wider platform (3 pedestals)
        local ax, ay = tryPlace(112, 44)
        if ax then
            local altar = WeaponAltar.new(ax, ay)
            result.weaponAltars[#result.weaponAltars + 1] = altar
        end
    end

    -- Normal chest (additional to chunk-defined chests)
    if math.random() < ACTIVITY_CHANCES.normal_chest then
        local ax, ay, plat = tryPlace(48, 32)
        if ax and plat then
            -- Snap Y so sprite bottom sits on the platform surface
            local snappedY = Chest.snapYToGround(room.platforms, ax, ay, 32)
            local chest = Chest.new(ax, snappedY, { tier = "normal", spriteRow = 0 })
            result.extraChests[#result.extraChests + 1] = chest
        end
    end

    -- Fake ambush chest (has bone pile visuals but no actual skeletons)
    if math.random() < ACTIVITY_CHANCES.fake_ambush then
        local ax, ay, plat = tryPlace(48, 32)
        if ax and plat then
            local snappedY = Chest.snapYToGround(room.platforms, ax, ay, 32)
            local floorY = plat.y - 28  -- bone pile sits near floor level
            local bonePiles = {
                { x = ax - 26, y = floorY, w = 18, h = 28, fake = true },
                { x = ax + 52, y = floorY, w = 18, h = 28, fake = true },
            }
            local chest = Chest.new(ax, snappedY, {
                tier = "normal",
                spriteRow = 2,  -- dark chest (even row = idle, row 3 = opening anim)
                bonePiles = bonePiles,
                fakeAmbush = true,
            })
            result.extraChests[#result.extraChests + 1] = chest
        end
    end

    -- Trapped chest: a rich chest flanked by pressure plates that trigger spike traps.
    -- Layout (120px zone): [plate(28)] [gap(8)] [chest(48)] [gap(8)] [plate(28)]
    -- Observant players can jump over the plates; others get spiked reaching for the loot.
    if math.random() < ACTIVITY_CHANCES.trapped_chest then
        local ax, ay, plat = tryPlace(120, 32)
        if ax and plat then
            -- Rich chest in the centre of the zone
            local chestX   = ax + 36
            local snappedY = Chest.snapYToGround(room.platforms, chestX, ay, 32)
            local chest = Chest.new(chestX, snappedY, { tier = "rich" })
            result.extraChests[#result.extraChests + 1] = chest

            -- Spike trap bases flush with the platform surface
            local trapY = plat.y - 4
            local trap1 = SpikeTrap.new(ax,      trapY, 28)
            local trap2 = SpikeTrap.new(ax + 92, trapY, 28)

            -- Pressure plates on top of the trap bases; stepping on either fires both traps
            local plateY = plat.y - 5
            local plate1 = PressurePlate.new(ax,      plateY, { trap1, trap2 })
            local plate2 = PressurePlate.new(ax + 92, plateY, { trap1, trap2 })

            result.pressurePlates[#result.pressurePlates + 1] = plate1
            result.pressurePlates[#result.pressurePlates + 1] = plate2
            result.spikeTraps[#result.spikeTraps + 1]     = trap1
            result.spikeTraps[#result.spikeTraps + 1]     = trap2
        end
    end

    -- Slot machine: dusty gambling cabinet found in the wild
    if math.random() < ACTIVITY_CHANCES.slot_machine then
        local ax, ay = tryPlace(48, 72)
        if ax then
            local sm = SlotMachine.new(ax, ay)
            result.slotMachines[#result.slotMachines + 1] = sm
        end
    end

    -- Wild pickups (items just lying around)
    if math.random() < ACTIVITY_CHANCES.wild_pickup then
        -- Place 1-3 wild pickups
        local count = math.random(1, 3)
        for _ = 1, count do
            local pickType
            local pickValue
            local roll = math.random()
            if roll < 0.10 then
                -- 10% weapon drop
                local gun = Guns.rollDrop(0)
                if gun then
                    pickType = "weapon"
                    pickValue = gun
                end
            elseif roll < 0.35 then
                pickType = "health"
                pickValue = math.random(10, 25)
            elseif roll < 0.65 then
                pickType = "gold"
                pickValue = math.random(5, 15)
            else
                pickType = "xp"
                pickValue = math.random(10, 30)
            end

            if pickType then
                -- Place on a random platform
                if #platforms > 0 then
                    local plat = platforms[math.random(#platforms)]
                    local px = randomXOnPlatform(plat, 10, 8)
                    local py = plat.y - 12
                    local pickup = Pickup.new(px, py, pickType, pickValue)
                    pickup.grounded = true  -- already on the platform
                    result.wildPickups[#result.wildPickups + 1] = pickup
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Secret area rewards: guaranteed rich chest + shrine in each secret chunk
    ---------------------------------------------------------------------------
    if room.secretAreas then
        for _, sa in ipairs(room.secretAreas) do
            -- Collect platforms within this secret cell's bounding box
            local secretPlats = {}
            for _, plat in ipairs(room.platforms) do
                local platCx = plat.x + plat.w / 2
                if plat.w >= 60
                   and platCx >= sa.x and platCx <= sa.x + sa.w
                   and plat.y >= sa.y and plat.y <= sa.y + sa.h then
                    secretPlats[#secretPlats + 1] = plat
                end
            end

            if #secretPlats > 0 then
                -- Sort top-to-bottom; place loot on an upper platform for exploration reward
                table.sort(secretPlats, function(a, b) return a.y < b.y end)

                -- Rich chest on the highest reachable platform
                local chestPlat = secretPlats[1]
                if chestPlat.w >= 64 then
                    local cx = chestPlat.x + math.max(8, math.floor((chestPlat.w - 48) / 2))
                    local snappedY = Chest.snapYToGround(room.platforms, cx, chestPlat.y - 32, 32)
                    local chest = Chest.new(cx, snappedY, { tier = "rich" })
                    result.extraChests[#result.extraChests + 1] = chest
                end

                -- Shrine on the floor platform (lowest in the secret area)
                local shrinePlat = secretPlats[#secretPlats]
                if shrinePlat.w >= 60 then
                    local sx = shrinePlat.x + math.max(8, math.floor((shrinePlat.w - 32) / 2))
                    local shrine = Shrine.new(sx, shrinePlat.y - 48)
                    result.shrines[#result.shrines + 1] = shrine
                end
            end

            -- Secret entrance: cracked-wall visual at the passage opening
            if sa.entrance then
                local e = sa.entrance
                local se = SecretEntrance.new(e.x, e.y, e.w, e.h)
                result.secretEntrances[#result.secretEntrances + 1] = se
            end
        end
    end

    return result
end

return MapActivities
