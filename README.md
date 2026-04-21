# Apocalipse [BR] - PvP System

A Project Zomboid Build 42 mod that adds a configurable PvP shield system with out-of-combat regeneration.

## What the mod does

- Adds a craftable head-slot item: `ApocalipseBR.PvPShield_Basic`.
- When equipped, the shield intercepts player-vs-player hit damage.
- Blocked damage is converted into shield HP loss.
- Shield HP regenerates only after an out-of-combat delay.
- Shows a HUD bar with current shield HP and regen state.

## Gameplay flow

1. Player crafts and equips `Basic PvP Shield` in the head slot.
2. During PvP, incoming damage is fully blocked while shield HP is above zero.
3. Shield HP is reduced by the blocked hit amount.
4. If shield HP reaches `0`, protection stops.
5. After no recent PvP damage for `ShieldRegenDelay`, HP regenerates at `ShieldRegenRate` HP/s.

## Current crafting balance

Recipe: `MakeBasicPvPShield`

- `30x` Electronics Scrap (`Base.ElectronicsScrap`)
- `20x` Sheet Metal (`Base.SheetMetal`)
- `10x` Duct Tape (`Base.DuctTape`)

This is a 10x material increase to keep shield availability and power balanced for PvP servers.

## Configurable sandbox options

Defined in `common/media/sandbox-options.txt`:

- `ApocalipseBR.ShieldEnabled` (boolean, default: `true`)
- `ApocalipseBR.ShieldMaxHP` (integer, default: `50`, min: `10`, max: `500`)
- `ApocalipseBR.ShieldRegenRate` (double, default: `2.0`, min: `0.0`, max: `50.0`)
- `ApocalipseBR.ShieldRegenDelay` (integer, default: `8`, min: `1`, max: `60`)

## Technical overview

- Shared config and item state keys:
  - `common/media/lua/shared/ApocalipseBR/PvPShield_Config.lua`
- Client HUD, local state, and regen heartbeat:
  - `common/media/lua/client/ApocalipseBR/PvPShield_Client.lua`
- Server-side PvP interception and authoritative regen application:
  - `common/media/lua/server/ApocalipseBR/PvPShield_Server.lua`
- Item and recipe definition:
  - `common/media/scripts/pvp_shield.txt`

## Project structure notes

The repository contains a workspace wrapper and the actual mod content folder:

- Root workspace files and automation scripts.
- Mod source under:
  - `Apocalipse [BR] - PvP System/Apocalipse [BR] - PvP System/`

## Build workflow (PZ Studio)

In `Apocalipse [BR] - PvP System/`:

- `npm run clean`
- `npm run build`
- `npm run watch`

## Compatibility

- Project Zomboid Build 42+
- `mod.info` currently sets `versionMin=42.15`
