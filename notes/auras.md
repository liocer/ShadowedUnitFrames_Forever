# Auras port notes (auras.lua, auraindicators.lua, highlight.lua)

All three files pass `luac -p` and luacheck with no warnings.

## Key facts about this build (what the code relies on)

- In combat the aura fields (`name`, `spellId`, `icon`, `applications`, `duration`, `expirationTime`,
  `dispelName`, `sourceUnit`, `isBossAura`, `isStealable`, ...) can be secret. **`auraInstanceID` is assumed
  to stay readable.** That matches Midnight, but if it is secret too the code falls back: no tooltip by
  instance ID, no timer, no incremental updates. Every use is guarded with `issecretvalue`.
- Blizzard's own aura UIs on this build (TargetFrameAuraContainer, CompactUnitFrame / PrivateAurasUI,
  Blizzard_AuraContainer) all run in the *secure* environment, so we can't copy their approach directly. The
  addon-usable tools are:
  - `C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter)`. The filter strings work with secret auras: `PLAYER`
    means cast by the player, pet or vehicle; `RAID` on harmful auras means debuffs the player can dispel;
    `RAID` on helpful auras means buffs the player can cast.
  - `C_UnitAuras.GetAuraDuration` with `Cooldown:SetCooldownFromDurationObject(obj, true)`.
  - `C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, 2)` for stack text.
  - `C_UnitAuras.GetAuraDispelTypeColor(unit, id, colorCurve)`, where the curve's x is the dispel type ID:
    0 none, 1 Magic, 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed.
  - `Texture:SetTexture`, `FontString:SetText` and `Texture:SetVertexColor` accept secrets. `Cooldown:SetCooldown`
    and curve `:Evaluate` do **not** accept secrets from addon code.
- `DebuffTypeColor` is gone. `DEBUFF_TYPE_*_COLOR` globals aren't in the docs either. I hard-coded the classic
  `DebuffTypeColor` values in `ShadowUF.Auras.debuffColors`.
- `CancelUnitBuff` and `GetInventoryItemTexture` aren't in the API docs, but Blizzard_BuffFrame calls them on
  this build. Each is localised with `-- luacheck: ignore 113`.

## modules/auras.lua

The module is exposed as `ShadowUF.Auras`, with shared helpers for the other aura modules:
- `debuffColors`, `dispelTypeIDs`
- `GetDispelColorCurve()` (Step colour curve)
- `GetDispelColor(unit, auraData[, dispelName])` returns r, g, b, which may be secret
- `GetFilterSet(unit, filter, tbl)` returns a `{[auraInstanceID]=true}` set
- `PassesFilter(unit, id, filter)`
- `GetStackText(unit, auraData)`
- `SetCooldown(cooldown, unit, auraData)`
- `ReadAura(info, auraData)`, which reads the non-secret fields and keeps cached ones

Behaviour:
- **Categories** (player / boss / raid / misc) now come from filter sets (`HELPFUL|PLAYER`, `HARMFUL|RAID`,
  `HELPFUL|RAID`) in both modes, so the game decides what's curable or castable. `canCure` is only a fallback
  if the API is missing.
- **Boss** uses `isBossAura`. It's unknown while secret, unless the aura was seen before combat, so in combat a
  new boss aura is treated as "misc". With "Show any other auras" off, such auras disappear in combat. Classic
  has few boss-flagged auras.
- **Removable/stealable** (enemy buffs) uses `isStealable` when readable. When secret it uses the
  `HELPFUL|RAID_PLAYER_DISPELLABLE` set (purgeable by someone in the group), so in combat it can highlight
  slightly different buffs. The filter is wrapped in pcall, so an unsupported token just means nothing gets
  highlighted.
- **White/black/override lists** (by name or spell ID) apply when the aura is readable, or when it was readable
  earlier. Readable info is cached per frame by `auraInstanceID` and pruned each full scan, so buffs applied
  before a pull keep list filtering in combat. Auras that first appear while secret skip the lists and use the
  category filters ("Show your auras", etc.).
- **Timers:** plain `SetCooldown` when the values are readable, otherwise the duration object. `ALL`, `SELF`
  and `BOSS` are respected.
- **Stacks:** the plain count, otherwise `GetAuraApplicationDisplayCount`.
- **Border colour:** from the dispel type table, otherwise the dispel colour curve. Grey for friendly buffs and
  the removable colour for removable enemy buffs, as before.
- **Enlarge** (SELF, BOSS, REMOVABLE), size, per row, anchors, growth and prioritize are unchanged. The
  positioning code is untouched.
- **Tooltips:** `GameTooltip:SetUnitBuffByAuraInstanceID` / `SetUnitDebuffByAuraInstanceID`, falling back to
  `SetUnitAura`. The tooltip refresh is now throttled to 0.2s.
- **Right-click cancel:** own buffs only, never under `InCombatLockdown()`. Uses `CancelUnitBuff(unit, index,
  "HELPFUL")` as Blizzard's BuffFrame does, falling back to `C_UnitAuras.CancelAuraByInstanceID`. **New:**
  right-click also cancels a weapon enchant out of combat, via `C_PaperDollInfo.CancelTemporaryEnchantment(slot)`
  or `CancelItemTempEnchantment(slot - 15)`.
- **Temporary enchants:** read from `C_PaperDollInfo.GetTemporaryEnchantmentInfo(16/17)`, then
  `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.*)`, then the global `GetWeaponEnchantInfo`. The first one that
  works is used. Fixed `lastTemporary` being nil.
- **UNIT_AURA updateInfo:** now registered as `UpdateAuras`.
  - Removed IDs that aren't shown are ignored.
  - Updated IDs that are shown get their button refreshed in place (icon, stack, timer).
  - Anything else does a full scan: full update, added auras, secret payload, or a shown aura removed.
  - The FullUpdate path still calls `Update`.

## modules/auraindicators.lua

- **Fixed the backdrop path.** It now points to `...ShadowedUnitFrames_Forever\\media\\textures\\backdrop` for
  both bgFile and edgeFile. `media\backdrop` doesn't exist; the file is `media/textures/backdrop.tga`.
- **Classic default aura list:** `Indicators.defaultAuras`. Keys are the rank 1 spell IDs.
  - Priest: Renew tr, PW:Shield tl (prio 20), Weakened Soul tl (prio 10, so it shows after the shield breaks),
    Power Infusion c.
  - Druid: Rejuvenation tr, Regrowth br, Innervate c.
  - Paladin: Blessing of Protection c, Divine Shield c.
  - WSG flags bl.
  - Listed with no indicator (users pick one): Fortitude and Prayer of Fortitude, Divine Spirit and Prayer of
    Spirit, Shadow Protection and its prayer, Fear Ward, Inspiration, Abolish Disease, Fade; Mark and Gift of
    the Wild, Thorns, Abolish Poison; Arcane Intellect and Brilliance, Amplify and Dampen Magic; all
    Blessings and Greater Blessings, Blessing of Freedom, Forbearance; Ancestral Fortitude, Healing Way;
    Battle Shout; Soulstone; Well Fed (missing).
  - The retail entries are removed: Monk, Hellfire Citadel, Lifebloom, Beacon, Riptide, Kotmogu flags, etc.
  - The list is applied by `hooksecurefunc(ShadowUF, "LoadUnitDefaults", ...)`, which replaces
    `defaults.profile.auraIndicators.auras`. **Core owner:** you can instead paste `Indicators.defaultAuras`
    into ShadowedUnitFrames.lua's `LoadUnitDefaults` and drop the hook. The hook is harmless either way.
- **Rank matching:** a configured spell ID also matches every rank by spell name, through a name to key map
  built from `C_Spell.GetSpellName`. The map is rebuilt when the number of auras changes or on
  OnLayoutApplied. `auraIndicators.linked[from] = to` is now honoured; the options already wrote it but the
  module ignored it. The class `disabled` list is checked by key and by name.
- **Secret auras:**
  - Specific auras match only when readable, or cached from before combat.
  - The `curable` filter uses the `HARMFUL|RAID` set, so it works in combat.
  - `boss` only works when readable.
  - Icon, stack and timer go through the secret-safe helpers in `ShadowUF.Auras`, so secret values are only
    handed to widgets.
  - "Missing" indicators are only shown when every aura on the unit was readable, or when
    `C_Secrets.ShouldSpellAuraBeSecret(spell) == false`. This avoids false "missing" flags in combat.
- Small fixes: the cooldown ring is now explicitly shown and sized (it was never re-shown after a Hide);
  alpha is applied on every layout, not only at creation; nil auraConfig is guarded; player detection uses the
  `PLAYER`-filter result or `sourceUnit`.

## modules/highlight.lua

- **Debuff highlight:** the first aura from `GetUnitAuraInstanceIDs(unit, "HARMFUL|RAID", 1)`, which is only
  what the player can dispel and works in combat. The colour comes from `ShadowUF.Auras:GetDispelColor` (table
  or curve, may be secret, passed to SetVertexColor). If that API fails, it falls back to a debuff scan with
  `Units:CanCure`.
- **Threat:** `UnitThreatSituation` may be secret. When it is, the aggro highlight is off; addon code can't
  compare it or feed it to a curve.
- **Target/focus attention:** `UnitIsUnit` may be secret. Then there's no attention highlight for that frame.
- Classification is guarded against secrets.
- `DebuffTypeColor` is no longer used.

## Settings

No new, removed or renamed saved settings. All existing aura, indicator and highlight options keep their db
keys and meaning. Suggested option description tweaks for **ShadowedUF_Forever_Options/config.lua**:
- Aura filter group: "In combat the game hides aura names, so white/black lists only apply to auras that were
  already on the unit before combat; new auras use the filters below."
- "Show casted by boss": "Boss auras that first appear in combat can't be recognised and count as 'other auras'."
- Aura indicators: "Auras tracked by name only update in combat if they were already up before combat; the
  Curable filter always works."
- Highlight aggro and target: "May not show in combat when the game hides threat or unit comparisons."
- "Enable temporary enchants" desc: "...right-click to cancel out of combat."

## Changes needed elsewhere

- **units.lua:** `Units:CanCure` compares `auraType == nil` *before* `issecretvalue(auraType)`. Comparing a
  secret value errors, so swap the order: `if issecretvalue(auraType) or auraType == nil then return nil end`.
  My modules only pass plain values, so they're safe either way. canCure already has Classic IDs (per
  notes/core.md). My modules hardly need it now because they use the `RAID` filter.
- **movers.lua (config mode):** test auras mock only the old `UnitAura` global. These modules use
  `C_UnitAuras.GetAuraDataByIndex` from local functions, which the mover's setfenv doesn't reach, so config
  mode shows the real auras (same as upstream retail). To get fake auras, movers would need to mock
  `C_UnitAuras` globally while in config mode.
- **ShadowedUnitFrames.lua:** optionally replace the retail default aura indicator list (see above).
  `ShadowUF.UnitAuraBySpell` compares `data.spellId == spell`, which errors on secret auras; it needs an
  `issecretvalue` guard.

## Unsure / needs in-game checking

- That `auraInstanceID` stays readable in combat on Forever.
- That `HELPFUL|RAID_PLAYER_DISPELLABLE` is a valid filter on camelot. It's pcall-guarded.
- The dispel type IDs used for the colour curve (taken from Midnight).
- Whether `CancelUnitBuff` and the temp-enchant cancel APIs are callable by addons out of combat
  (`HasRestrictions`). If they trigger ADDON_ACTION_BLOCKED, remove the cancel calls.
- Whether `SetCooldownFromDurationObject` with `clearIfZero` correctly blanks permanent auras.
- Whether `GameTooltip:SetUnitBuffByAuraInstanceID` works with secret auras from addon code (CompactUnitFrame
  uses it).
- Instance-ID cache: if instance IDs aren't unique across units, a target switch could briefly reuse another
  unit's cached name. The cache is pruned on every full scan.
