require "ApocalipseBR/PvPShield_Config"

local PvPShieldServer = {}

-- Rate limiting: playerOnlineID -> os.time() of last regen tick
local lastRegenTime = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Get the equipped shield item for a player, or nil
---@param player IsoPlayer
---@return InventoryItem|nil
local function getEquippedShield(player)
    local headItem = player:getClothingItem_Head()
    if headItem and PvPShieldConfig.getShieldConfig(headItem) then
        return headItem
    end
    return nil
end

--- Broadcast a command to all online players within range of sourcePlayer
---@param sourcePlayer IsoPlayer
---@param command string
---@param args table
local function broadcastToNearby(sourcePlayer, command, args)
    if not isServer() then return end

    local onlinePlayers = getOnlinePlayers()
    if not onlinePlayers then return end

    local px = sourcePlayer:getX()
    local py = sourcePlayer:getY()
    local rangeSq = PvPShieldConfig.BROADCAST_RANGE * PvPShieldConfig.BROADCAST_RANGE

    for i = 0, onlinePlayers:size() - 1 do
        local other = onlinePlayers:get(i)
        local dx = other:getX() - px
        local dy = other:getY() - py
        if dx * dx + dy * dy <= rangeSq then
            sendServerCommand(other, PvPShieldConfig.NET_MODULE, command, args)
        end
    end
end

---------------------------------------------------------------------------
-- Core: Damage blocking
---------------------------------------------------------------------------

--- OnWeaponHitCharacter handler – blocks PvP damage when shield is active
---@param wielder IsoGameCharacter
---@param target IsoGameCharacter
---@param weapon HandWeapon
---@param damageSplit number
local function onWeaponHitCharacter(wielder, target, weapon, damageSplit)
    if not PvPShieldConfig.isEnabled() then return end

    -- Only intercept player-vs-player hits
    if not instanceof(wielder, "IsoPlayer") then return end
    if not instanceof(target, "IsoPlayer") then return end
    if damageSplit <= 0 then return end

    -- Check shield
    local shieldItem = getEquippedShield(target)
    if not shieldItem then return end

    -- Initialize if first use
    local hp, maxHp = PvPShieldConfig.initializeShieldItem(shieldItem)
    if hp <= 0 then return end

    -- Block the entire hit (sets flag that Java checks immediately after this event)
    target:setAvoidDamage(true)

    -- Deduct shield HP
    hp = hp - damageSplit
    if hp < 0 then hp = 0 end

    -- Persist on item
    local modData = shieldItem:getModData()
    modData[PvPShieldConfig.MD_HP] = hp

    -- Broadcast to nearby players (MP)
    local args = { hp = hp, maxHp = maxHp, pid = target:getOnlineID() }
    broadcastToNearby(target, "ShieldUpdate", args)

    if hp <= 0 then
        broadcastToNearby(target, "ShieldBreak", { pid = target:getOnlineID() })
    end
end

---------------------------------------------------------------------------
-- Regen processing (called when client sends RegenTick)
---------------------------------------------------------------------------

--- Apply one tick of shield regeneration to a player
---@param player IsoPlayer
function PvPShieldServer.applyRegen(player)
    if not PvPShieldConfig.isEnabled() then return end

    local shieldItem = getEquippedShield(player)
    if not shieldItem then return end

    local modData = shieldItem:getModData()
    local hp = modData[PvPShieldConfig.MD_HP]
    local maxHp = modData[PvPShieldConfig.MD_MAX_HP]

    if not hp or not maxHp then
        hp, maxHp = PvPShieldConfig.initializeShieldItem(shieldItem)
    end

    if hp >= maxHp then return end

    -- Apply regen (1 tick = regenRate * interval)
    local regenAmount = PvPShieldConfig.getRegenRate() * PvPShieldConfig.REGEN_TICK_INTERVAL
    hp = math.min(hp + regenAmount, maxHp)
    modData[PvPShieldConfig.MD_HP] = hp

    -- Broadcast
    local args = { hp = hp, maxHp = maxHp, pid = player:getOnlineID() }
    broadcastToNearby(player, "ShieldUpdate", args)
end

---------------------------------------------------------------------------
-- State request (client asks for current shield state)
---------------------------------------------------------------------------

---@param player IsoPlayer
local function handleRequestState(player)
    local shieldItem = getEquippedShield(player)
    local hp, maxHp = 0, 0

    if shieldItem then
        hp, maxHp = PvPShieldConfig.initializeShieldItem(shieldItem)
    end

    if isServer() then
        sendServerCommand(player, PvPShieldConfig.NET_MODULE, "ShieldUpdate", {
            hp = hp,
            maxHp = maxHp,
            pid = player:getOnlineID(),
        })
    end
end

---------------------------------------------------------------------------
-- Network: OnClientCommand receiver
---------------------------------------------------------------------------

---@param module string
---@param command string
---@param player IsoPlayer
---@param args table
local function onClientCommand(module, command, player, args)
    if module ~= PvPShieldConfig.NET_MODULE then return end

    if command == "RegenTick" then
        -- Server-side rate limiting: max 1 regen tick per second per player
        local pid = player:getOnlineID()
        local now = os.time()
        if lastRegenTime[pid] and now - lastRegenTime[pid] < 1 then
            return
        end
        lastRegenTime[pid] = now
        PvPShieldServer.applyRegen(player)

    elseif command == "RequestState" then
        handleRequestState(player)
    end
end

---------------------------------------------------------------------------
-- Cleanup disconnected players from rate-limit table
---------------------------------------------------------------------------

---@param player IsoPlayer
local function onPlayerDisconnect(player)
    if player then
        lastRegenTime[player:getOnlineID()] = nil
    end
end

---------------------------------------------------------------------------
-- Register events
---------------------------------------------------------------------------

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnClientCommand.Add(onClientCommand)

if Events.OnPlayerDisconnect then
    Events.OnPlayerDisconnect.Add(onPlayerDisconnect)
end

return PvPShieldServer
