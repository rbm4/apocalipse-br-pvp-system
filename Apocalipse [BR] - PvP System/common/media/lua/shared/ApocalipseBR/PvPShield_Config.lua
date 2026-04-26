---@class PvPShieldConfig
PvPShieldConfig = PvPShieldConfig or {}

-- Network module name for client/server commands
PvPShieldConfig.NET_MODULE = "PvPShield"

-- ModData keys stored on item
PvPShieldConfig.MD_HP = "PvPShield.HP"
PvPShieldConfig.MD_MAX_HP = "PvPShield.MaxHP"

-- Shield type definitions keyed by fullType
PvPShieldConfig.ShieldTypes = {
    ["ApocalipseBR.PvPShield_Basic"] = {
        maxHP = 50,
        regenRate = 2.0,
        regenDelay = 8,
    },
}

-- Max distance (tiles) for broadcasting shield updates to nearby players
PvPShieldConfig.BROADCAST_RANGE = 30

-- Minimum seconds between regen ticks from client
PvPShieldConfig.REGEN_TICK_INTERVAL = 1


--- Get the shield config for an item, or nil if not a shield
---@param item InventoryItem
---@return table|nil
function PvPShieldConfig.getShieldConfig(item)
    if not item then return nil end
    return PvPShieldConfig.ShieldTypes[item:getFullType()]
end

--- Get sandbox-overridden max HP, falling back to config default
---@param itemFullType string
---@return number
function PvPShieldConfig.getMaxHP(itemFullType)
    local cfg = PvPShieldConfig.ShieldTypes[itemFullType]
    if not cfg then return 0 end
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldMaxHP then
        return SandboxVars.ApocalipseBR.ShieldMaxHP
    end
    return cfg.maxHP
end

--- Get regen rate (HP per second)
---@return number
function PvPShieldConfig.getRegenRate()
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldRegenRate then
        return SandboxVars.ApocalipseBR.ShieldRegenRate
    end
    return 2.0
end

--- Get regen delay (seconds out of combat)
---@return number
function PvPShieldConfig.getRegenDelay()
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldRegenDelay then
        return SandboxVars.ApocalipseBR.ShieldRegenDelay
    end
    return 8
end

--- Get minimum shield damage per successful PvP hit
---@return number
function PvPShieldConfig.getMinDamagePerHit()
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldMinDamagePerHit then
        return SandboxVars.ApocalipseBR.ShieldMinDamagePerHit
    end
    return 3
end

--- Check if shield system is enabled
---@return boolean
function PvPShieldConfig.isEnabled()
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldEnabled ~= nil then
        return SandboxVars.ApocalipseBR.ShieldEnabled
    end
    return true
end

--- Check if shield HUD should be rendered
---@return boolean
function PvPShieldConfig.isHUDEnabled()
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldHUDEnabled ~= nil then
        return SandboxVars.ApocalipseBR.ShieldHUDEnabled
    end
    return true
end

--- Check if shield regen pulse effect should be rendered
---@return boolean
function PvPShieldConfig.isPulseEnabled()
    if SandboxVars and SandboxVars.ApocalipseBR and SandboxVars.ApocalipseBR.ShieldPulseEnabled ~= nil then
        return SandboxVars.ApocalipseBR.ShieldPulseEnabled
    end
    return true
end

--- Initialize a shield item's modData if not already set
---@param item InventoryItem
---@return number hp, number maxHp
function PvPShieldConfig.initializeShieldItem(item)
    local modData = item:getModData()
    local fullType = item:getFullType()
    local maxHP = PvPShieldConfig.getMaxHP(fullType)

    if not modData[PvPShieldConfig.MD_MAX_HP] then
        modData[PvPShieldConfig.MD_MAX_HP] = maxHP
        modData[PvPShieldConfig.MD_HP] = maxHP
    end

    return modData[PvPShieldConfig.MD_HP], modData[PvPShieldConfig.MD_MAX_HP]
end
