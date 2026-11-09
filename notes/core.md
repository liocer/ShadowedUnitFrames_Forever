# Core (ShadowedUnitFrames.lua, units, layout, movers, defaultlayout, helpers, localization)

All my files pass `luac -p` and luacheck with 0 warnings.

## Per file

### ShadowedUnitFrames.lua
- **Guard for the original addon.** If `ShadowedUnitFrames` is loaded too (checked with `C_AddOns.IsAddOnLoaded`), or the
  global `ShadowUF` is already some other table, we set `ShadowUF.conflict`:
  - `ShadowUF` still points at our namespace while our files load, so our modules register with us.
  - On our own `ADDON_LOADED` the global is handed back to the original.
  - We never call `OnInitialize`, and we skip the slash commands and `CONFIGMODE_CALLBACKS` (they share names
    with the original).
  - On `PLAYER_LOGIN` we print one clear message. We also check again at login, in case the original loaded later.
  - The file uses `local ShadowUF = namespace`, so its code always talks to our table.
- **dbRevision 63 → 64.** New `ShadowUF:RemoveRetailSettings()` runs for profiles at revision 63 or lower (imported
  retail/classic profiles). It removes the removed modules' unit settings, text rows anchored to those bars, the
  `arenaSpec` indicator, and the class/power colours for things that don't exist here. The lists are in
  `ShadowUF.removedModules`, `removedClassColors`, `removedPowerColors` and `removedIndicators`, in case options needs them.
  Retail upgrade steps 56 and 62, which added DH/evoker/new bars, are deleted. Step 46 no longer adds `arenaSpec`.
- **Unit defaults.** Removed `runeBar, priestBar, shamanBar, soulShards, arcaneCharges, staggerBar, holyPower, chi,
  essence` from `player`, and `indicators.arenaSpec` from `arena`. Player gets 1 extra default text row instead of
  3; row 7 is the totem timer.
- **Aura indicator defaults** trimmed to Classic-era spells: 20707, 19705, 774, 6788, 139, 17, 23335, 23333, 586, 8936,
  1022 and 29166. The Monk entries, retail-only spells and the Hellfire Citadel list are gone. The keys are first-rank
  spell IDs. auraindicators also matches by name, but higher ranks have different IDs (auras area).
  `auraIndicators.disabled` is now built from `CLASS_SORT_ORDER` (the camelot class list) instead of `RAID_CLASS_COLORS`.
- `ShadowUF.UnitAuraBySpell` is now secret-safe: it uses pcall, skips auras whose `spellId` is secret, and returns
  nothing if the aura's name is secret, so callers can still use it in an `if`.
- **HideBlizzardFrames.** Every frame is nil-guarded, and `_G[...]` is used for frames that may not exist.
  - Target: `TargetFrame`, `ComboFrame` (camelot's combo ring on the target portrait) and `TargetFrame.totFrame`.
    `TargetFrameToT` and `FocusFrameToT` are created by `CreateTargetofTarget`; the field is used here.
  - Focus: `FocusFrame` and `FocusFrame.totFrame`.
  - Class power (`playerPower`): now hides `TotemFrame` (the only class resource frame on camelot). The retail
    names stay in the list for future builds; they are all nil here.
  - Player: `PlayerFrame` and `AlternatePowerBar` (the druid's mana bar while shapeshifted).
  - Party: the `PartyFrame` pool and `CompactPartyFrame`.
  - Raid: the CompactRaidFrameManager functions are looked up first.
  - Arena: hiding needs `Blizzard_Deprecated_ArenaUI`; `ADDON_LOADED` for that addon now re-runs the hiding.
  - Boss: the boss frame bars are found through `TargetFrameContent`.
  - The hiding methods are the same as upstream retail SUF (reparent to a hidden frame plus an OnShow rehide;
    `Show = noop` only for the cast bars and arena, as upstream does).
- **Slash commands** kept (`/suf`, `/shadowuf`, `/shadoweduf`, `/shadowedunitframes`); the config loader points at
  `ShadowedUF_Forever_Options`. New `/suf help` (also `credits` and `about`) prints usage plus the credits line naming
  Shadowed and Hendrik Leppkes (Nevcairiel). The first login per account prints a welcome and the credits once
  (`db.global.foreverWelcomed`).
- The info panel text no longer mentions Chi or Holy Power.

### modules/units.lua
- **Secret-safe unit identity.**
  - New `readGUID(unit)`, also available as `Units.ReadGUID`, returns `guid, isSecret`. `frame.unitGUID` is only ever
    a plain GUID or nil.
  - `CheckUnitStatus`: if the GUID is secret it does a full update (when the unit exists) because it can't tell
    whether the unit changed.
  - Vehicle code: a secret vehicle GUID counts as *unchanged*. This check runs inside FullUpdate, so "changed"
    would loop forever.
  - `UnitHealthMax` checks go through `hasHealthData`, where secret counts as "has data".
- **`frame:UnitClassToken()`** returns nil when `UnitClass` is secret, so it's always safe as a table key (also
  available as `Units.ClassToken`). The arena override that used `GetArenaOpponentSpec` is removed; that function is
  always secret and there are no specs.
- **No specs.** `GetSpecialization()` is replaced with nil. A module registered with a spec (the `spec` argument of
  `RegisterModule`) is therefore never enabled. Only totems.lua passes specs now (the retail druid, monk, mage and
  warlock variants), so those stay off, which is what we want.
- **Zone checks** use the new `ShadowUF:GetInstanceType()` (helpers.lua). `CanHearthAndResurrectFromArea` is looked
  up defensively; it exists, since QueueStatusFrame calls it on camelot.
- **canCure** covers the Classic dispels:
  - Priest: Dispel Magic (527, 988), Cure Disease (528), Abolish Disease (552)
  - Druid: Remove Curse (2782), Cure Poison (8946), Abolish Poison (2893)
  - Paladin: Purify (1152), Cleanse (4987)
  - Shaman: Cure Poison (526), Cure Disease (2870)
  - Mage: Remove Lesser Curse (475)
  - Warlock Felhunter: Devour Magic 19505/19731/19734/19736, checked in the pet spell bank

  Detection uses `C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Player/Pet)`, then `IsSpellInSpellBook`,
  then `IsPlayerSpell` if it ever exists. It refreshes on `SPELLS_CHANGED`, `LEARNED_SPELL_IN_SKILL_LINE` (this
  client's name for LEARNED_SPELL_IN_TAB), `ACTIVE_TALENT_GROUP_CHANGED` and, for warlocks, `UNIT_PET`.
  `PLAYER_SPECIALIZATION_CHANGED` is dropped. The table is wiped, not replaced, so references to it stay valid.
  - **New helper `ShadowUF.Units:CanCure(auraType)`** returns nil for a secret or nil dispel type.
- Raid `groupBy = CLASS` ordering now lists the 9 vanilla classes.
- `InitializeArena` treats `GetNumArenaOpponentSpecs` as optional and possibly secret. The arena prep events are
  registered with pcall.
- On a conflict, the central event frame unregisters itself and the wrapper frame is created unnamed.
- Clique support (`ClickCastFrames`, `ClickCastHeader`), the secure headers, child units and the fake-unit 0.5 s
  polling are unchanged. The polling never compares unit data.
- Vehicle and possess handling is kept: `UnitHasVehicleUI` and the vehicle events exist on this client, even though
  Classic content probably never uses them.

### modules/layout.lua
- `SetupText` no longer errors on a text row anchored to `$parent` or to a module that doesn't exist (a removed
  bar in an imported profile). Bar ordering is driven entirely by config; there was no hard-coded list to change.

### modules/movers.lua (config mode test data)
- Removed the holy power, soul shard, essence, chi, rune, stagger and arena spec mocks. Test power types are now
  mana, rage, focus and energy, and health numbers are at Classic scale.
- Added a mock `C_UnitAuras` (`GetAuraDataByIndex`, `GetBuffDataByIndex`, `GetDebuffDataByIndex` return fake aura
  tables; everything else falls through to the real API). The old `UnitAura` mock is kept.

### modules/defaultlayout.lua
- Removed the DK, Monk, DH and Evoker class colours.
- Removed these power colours: RUNES, RUNIC_POWER, INSANITY, MAELSTROM, LUNAR_POWER, HOLYPOWER, SOULSHARDS,
  ARCANECHARGES, CHI, FURY, PAIN, STATUE, RUNEOFPOWER, MUSHROOMS, STAGGER_*, ESSENCE.
- Removed the retail player bars, the rune and stagger text rows, and the arena `arenaSpec` indicator.
- Kept the totem bar, druid bar, combo points, aura points, xp, cast, alt power and everything else, so the look is
  unchanged.

### modules/helpers.lua
- Added `ShadowUF:GetInstanceType(ignoreWorldPvP)`. It returns `none`, `pvp`, `arena`, `party`, `raid` or
  `neighborhood`; anything without a visibility table counts as `none`.

### localization/enUS.lua
- The "missing key returns the key" fallback used to be inside `--@debug@`, which a packager strips. It's now always
  on, because this fork doesn't use the original's CurseForge localization project. New strings are English-keyed:
  - the credits line
  - the conflict message
  - the welcome message
  - the `/suf help` line
  - the edited combo-point info text

## Settings
- **Added:** `db.global.foreverWelcomed` (internal, no option needed).
- **Removed** (options must drop their entries):
  - Player bars: `units.player.{runeBar, soulShards, holyPower, chi, staggerBar, arcaneCharges, essence, priestBar, shamanBar}`
  - Indicator: `units.arena.indicators.arenaSpec`
  - Class colours: `classColors.{DEATHKNIGHT, MONK, DEMONHUNTER, EVOKER}`
  - Power colours: the list above. ShadowedUF_Forever_Options/config.lua still has `powerColors.STAGGER_*`, `RUNIC_POWER`, `RUNES`,
    `INSANITY`, `MAELSTROM`, `HOLYPOWER`, `SOULSHARDS` and so on, which will now read nil.
- The `hidden.*` keys are unchanged. Suggested option labels on Forever:
  - `playerPower`: "Hide Blizzard totem frame / class resource bars".
  - `target`: also hides the combo point ring and the target-of-target frame.

## For other areas
- **auras / highlight / health / auraindicators:** they index `canCure[auraType]` directly. If `auraType` (the
  aura's `dispelName`) can be secret, that errors. Use `ShadowUF.Units:CanCure(auraType)` or check `issecretvalue`
  first.
- **tags:** `UnitAuraBySpell` returns nothing for secret auras. The druid form tags only check truthiness, so they're fine.
- **totems.lua (bars):** the druid, monk, mage and warlock variants pass specs, so they're never enabled. They also
  point at the removed `MUSHROOMS`, `STATUE` and `RUNEOFPOWER` colours. Remove those branches and keep only the
  shaman totem bar.
- **indicators:** remove `arenaSpec` and the `GetSpecializationInfoByID` use for lfdRole. The defaults no longer have
  `arenaSpec`; the module's existing nil checks cope.
- **options:** remove the settings listed above, the class colour pickers for removed classes, and anything for the
  retail bars.
- Any module that needs a GUID can use `ShadowUF.Units.ReadGUID(unit)`; portrait.lua and tags.lua compare GUIDs.
- Config mode: if the health or power modules switch to `UnitHealthPercent` or curves, the movers env doesn't mock
  those. Fake units like "party1" will show whatever the real API returns, so mock them in movers if needed (tell me
  or edit movers.lua).
- **TOC (lead):** the SavedVariables name is still `ShadowedUFDB`, the same as the original. It's a per-addon file,
  so that's fine.

## Unsure / needs in-game testing
- Whether the camelot `ComboFrame`, `TotemFrame` and `AlternatePowerBar` hide cleanly and stay hidden, and that
  hiding `PlayerFrame` doesn't cause Edit Mode taint (upstream does the same thing on retail).
- `UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")` and the CompactRaidFrameManager hooks on this build.
- The `[petbattle]` state driver conditional on camelot; it should just never be true.
- The conflict guard is only reasoned through. The original's retail TOC probably won't load on Forever at all
  unless out-of-date addons are allowed.
- Whether `C_SpellBook.IsSpellKnown` with the Pet bank detects the Felhunter's Devour Magic.
- Exactly when `UnitGUID` is secret. If it's secret for party or raid members in combat, every `UNIT_NAME_UPDATE`
  causes a full update (correct, but more work).
