require "ISUI/ISPanel"
require "ApocalipseBR/PvPShield_Config"

---------------------------------------------------------------------------
-- Client state
---------------------------------------------------------------------------

local PvPShieldClient = {}

PvPShieldClient.state = {
    hp           = 0,
    maxHp        = 0,
    lastDamageTime  = 0,   -- os.time() when HP last decreased
    lastRegenSec    = 0,   -- os.time() when last regen tick was sent
    isRegenerating  = false,
    hasShield       = false,
}

-- Track head item type to detect equip/unequip changes
local lastHeadItemType      = nil
local requestedInitialState = false
local lastStateRequestSec   = -1

local function requestStateThrottled(player)
    if not player then return end
    local now = os.time()
    if now == lastStateRequestSec then return end
    lastStateRequestSec = now
    sendClientCommand(player, PvPShieldConfig.NET_MODULE, "RequestState", {})
end

---------------------------------------------------------------------------
-- Shield HUD panel
---------------------------------------------------------------------------

PvPShieldHUD = ISPanel:derive("PvPShieldHUD")

function PvPShieldHUD:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background   = false
    o.moveWithMouse = false
    return o
end

function PvPShieldHUD:render()
    local s = PvPShieldClient.state
    if PvPShieldConfig.isHUDEnabled and not PvPShieldConfig.isHUDEnabled() then return end
    if not s.hasShield or s.maxHp <= 0 then return end

    local barW = self.width
    local barH = 10
    local barY = self.height - barH
    local fillRatio = math.max(0, math.min(1, s.hp / s.maxHp))

    -- Background
    self:drawRect(0, barY, barW, barH, 0.6, 0.05, 0.05, 0.1)

    -- Fill bar (cyan/blue for active, dim when depleted)
    if s.hp > 0 then
        if s.isRegenerating then
            -- Use a tick-based pulse to avoid per-frame trig calls.
            local pulse = 0.8
            if PvPShieldConfig.isPulseEnabled and PvPShieldConfig.isPulseEnabled() then
                local t = getTimestampMs and getTimestampMs() or 0
                pulse = ((math.floor(t / 180) % 2) == 0) and 0.9 or 0.6
            end
            self:drawRect(0, barY, barW * fillRatio, barH, pulse, 0.15, 0.55, 0.95)
        else
            self:drawRect(0, barY, barW * fillRatio, barH, 0.85, 0.15, 0.55, 0.95)
        end
    end

    -- Border
    self:drawRectBorder(0, barY, barW, barH, 0.7, 0.3, 0.5, 0.7)

    -- Label
    local hpText = math.ceil(s.hp) .. "/" .. math.ceil(s.maxHp)
    local label  = "Shield: " .. hpText
    if s.isRegenerating then
        label = label .. "  [REGEN]"
    end
    self:drawTextCentre(label, barW / 2, barY - 16, 0.8, 0.9, 1.0, 0.9, UIFont.Small)
end

---------------------------------------------------------------------------
-- HUD instance management
---------------------------------------------------------------------------

local hudInstance = nil

local function ensureHUD()
    if hudInstance then return end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w  = 160
    local h  = 28
    hudInstance = PvPShieldHUD:new(sw / 2 - w / 2, sh - 100, w, h)
    hudInstance:addToUIManager()
    hudInstance:setVisible(true)
end

---------------------------------------------------------------------------
-- State synchronisation
---------------------------------------------------------------------------

--- Update local state; detects whether HP decreased (= took a hit)
---@param hp number
---@param maxHp number
local function updateShieldState(hp, maxHp)
    local s = PvPShieldClient.state

    -- Detect damage: HP went down since last known value
    if hp < s.hp and s.hp > 0 then
        s.lastDamageTime = os.time()
        s.isRegenerating = false
    end

    s.hp       = hp
    s.maxHp    = maxHp
    s.hasShield = maxHp > 0
end

--- SP-only: read shield state directly from the equipped item's modData
local function pollShieldStateSP(player, headItem)
    player = player or getSpecificPlayer(0)
    if not player then return end

    headItem = headItem or player:getClothingItem_Head()
    if not headItem then
        updateShieldState(0, 0)
        return
    end

    local cfg = PvPShieldConfig.getShieldConfig(headItem)
    if not cfg then
        updateShieldState(0, 0)
        return
    end

    local hp, maxHp = PvPShieldConfig.initializeShieldItem(headItem)
    updateShieldState(hp, maxHp)
end

---------------------------------------------------------------------------
-- Regen heartbeat
---------------------------------------------------------------------------

local function processRegenTick()
    local s = PvPShieldClient.state
    if not s.hasShield then return end
    if s.maxHp <= 0 then return end
    if s.hp >= s.maxHp then
        s.isRegenerating = false
        return
    end

    local now       = os.time()
    local regenDelay = PvPShieldConfig.getRegenDelay()

    -- Still in combat cooldown
    if now - s.lastDamageTime < regenDelay then
        s.isRegenerating = false
        return
    end

    s.isRegenerating = true

    -- Throttle: one tick per second
    if now == s.lastRegenSec then return end
    s.lastRegenSec = now

    local player = getSpecificPlayer(0)
    if not player then return end

    if isClient() then
        -- MP: send heartbeat to server; server will validate and apply
        sendClientCommand(player, PvPShieldConfig.NET_MODULE, "RegenTick", {})
    else
        -- SP: apply regen locally (server Lua doesn't receive client commands in SP)
        local headItem = player:getClothingItem_Head()
        if not headItem then return end
        local cfg = PvPShieldConfig.getShieldConfig(headItem)
        if not cfg then return end

        local modData = headItem:getModData()
        local hp    = modData[PvPShieldConfig.MD_HP] or 0
        local maxHp = modData[PvPShieldConfig.MD_MAX_HP] or cfg.maxHP

        local regenAmount = PvPShieldConfig.getRegenRate() * PvPShieldConfig.REGEN_TICK_INTERVAL
        hp = math.min(hp + regenAmount, maxHp)
        modData[PvPShieldConfig.MD_HP] = hp

        updateShieldState(hp, maxHp)
    end
end

---------------------------------------------------------------------------
-- SP combat detection (OnWeaponHitCharacter fires locally in SP)
---------------------------------------------------------------------------

local function onWeaponHitCharacterClient(wielder, target, weapon, damageSplit)
    if isClient() then return end -- MP: rely on server ShieldUpdate commands instead

    local player = getSpecificPlayer(0)
    if not player then return end
    if target ~= player then return end
    if not instanceof(wielder, "IsoPlayer") then return end

    -- Record hit time so regen pauses
    PvPShieldClient.state.lastDamageTime = os.time()
    PvPShieldClient.state.isRegenerating = false

    -- Re-read HP (server-side handler already modified modData)
    pollShieldStateSP()
end

---------------------------------------------------------------------------
-- Network: OnServerCommand receiver (MP)
---------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= PvPShieldConfig.NET_MODULE then return end

    local player = getSpecificPlayer(0)
    if not player then return end

    if command == "ShieldUpdate" then
        if args and args.pid == player:getOnlineID() then
            updateShieldState(args.hp or 0, args.maxHp or 0)
        end
    elseif command == "ShieldBreak" then
        if args and args.pid == player:getOnlineID() then
            updateShieldState(0, PvPShieldClient.state.maxHp)
        end
    end
end

---------------------------------------------------------------------------
-- Main tick (throttled to ~1 Hz for shield logic)
---------------------------------------------------------------------------

local lastTickSec = 0

local function onTick()
    if not PvPShieldConfig.isEnabled() then return end

    local player = getSpecificPlayer(0)
    if not player then return end

    -- MP: one-time initial state request
    if isClient() and not requestedInitialState then
        requestedInitialState = true
        requestStateThrottled(player)
    end

    -- Throttle main logic to once per second
    local now = os.time()
    if now == lastTickSec then return end
    lastTickSec = now

    -- Detect equip/unequip changes
    local headItem = player:getClothingItem_Head()
    local currentType = headItem and headItem:getFullType() or nil

    if currentType ~= lastHeadItemType then
        lastHeadItemType = currentType
        if isClient() then
            requestStateThrottled(player)
        else
            pollShieldStateSP(player, headItem)
        end
    end

    -- SP: poll item modData periodically
    if not isClient() then
        pollShieldStateSP(player, headItem)
    end

    -- Process regen heartbeat
    processRegenTick()

    -- Ensure HUD exists when shield is active
    if PvPShieldClient.state.hasShield and (not PvPShieldConfig.isHUDEnabled or PvPShieldConfig.isHUDEnabled()) then
        ensureHUD()
    end
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

local function onPlayerDeath(player)
    if player == getSpecificPlayer(0) then
        PvPShieldClient.state.hp        = 0
        PvPShieldClient.state.maxHp     = 0
        PvPShieldClient.state.hasShield = false
        PvPShieldClient.state.isRegenerating = false
    end
end

---------------------------------------------------------------------------
-- Register events
---------------------------------------------------------------------------

Events.OnTick.Add(onTick)
Events.OnServerCommand.Add(onServerCommand)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacterClient)

return PvPShieldClient
