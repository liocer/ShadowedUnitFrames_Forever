# Misc modules: cast, range, fader, portrait, indicators, combat text

Files: `modules/cast.lua`, `modules/range.lua`, `modules/fader.lua`, `modules/portrait.lua`,
`modules/indicators.lua`, `modules/combattext.lua`, and one small edit to `modules/defaultlayout.lua`.
All six modules pass `luac -p` and luacheck with 0 warnings. Old C functions the docs leave out
(`GetReadyCheckStatus`, `GetPartyAssignment`, `HasLFGRestrictions`, `IsEveryoneAssistant`,
`UnitHasIncomingResurrection`, `HasPetUI`, `GetLootMethod`) and GlobalStrings are read through `_G`,
with nil checks. Blizzard's own code calls each of these functions on this build.

## cast.lua

- Every unit has a cast bar. Real units use events. Fake units (targettarget etc.) use the existing
  0.1 s polling monitor, rewritten so it's secret-safe.
- **Plain path** (start and end times aren't secret): behaves as before. Timer text, red pushback
  text, finish detection in OnUpdate, "finished" colour and fade.
- **Secret path** (times are secret):
  - The bar uses `UnitCastingDuration`/`UnitChannelDuration` with
    `StatusBar:SetTimerDuration(duration, Immediate, ElapsedTime|RemainingTime)`.
  - The timer text is `SetFormattedText("%.1f", duration:GetRemainingDuration())`, refreshed every
    0.05 s inside a pcall.
  - The name and icon go straight to `SetText`/`SetTexture`.
  - There's no pushback text, because it can't be computed.
  - The end of the cast comes from the STOP / CHANNEL_STOP / INTERRUPTED events.
  - If there's no duration object, the bar shows full with no time text.
- **Colours:** cast, channel, interrupted, uninterruptible and finished are all kept. A secret
  `notInterruptible` uses `SetVertexColorFromBoolean` on the bar texture and background, and honours
  the `invert` option.
- **Event matching:**
  - `castGUID` is compared only when it isn't secret.
  - `castBarID` is never secret, but its docs don't say whether it's unique per cast. So a
    *different* castBarID rules an event out, but a *matching* one isn't trusted.
  - If the ids can't be told, FAILED is ignored while the unit is still casting, so "another action
    in progress" doesn't kill the bar. STOP is accepted.
- **Channels:**
  - CHANNEL_STOP now has its own handler (`EventStopChannel`).
  - A non-nil or secret `interruptedBy` shows the "Interrupted" state.
  - Before, channel interrupts only showed through INTERRUPTED.
- `UnitCastingInfo`/`UnitChannelInfo` are wrapped in pcall, because the unit argument is
  `UnitTokenPvPRestrictedForAddOns`.
- The BigWigs rename only runs when `spellID` isn't secret.
- There are no empowered casts. The upstream module had no latency display, so none was added.
- New public helper: `Cast:StopCast(frame)`, which fades out the current cast.
- No settings changed.

## range.lua

- LibSpellRange is dropped (it was no longer referenced anywhere else).
- **Order of checks:**
  1. `C_Spell.IsSpellInRange` over a list of class spells. In range if *any* spell says yes, which
     covers the hunter 8-yard dead zone and melee plus ranged. A spell that returns nil (invalid) is
     skipped.
  2. `UnitInRange` for group members. This result can be secret.
  3. `CheckInteractDistance(unit, 4)` (28 yards), only out of combat and inside a pcall.
  4. Otherwise the unit counts as in range, as before.
- A secret result is applied with `frame:SetAlphaFromBoolean(inRange, inAlpha, oorAlpha)`. That is
  skipped while the fader has range alpha disabled. In that case `frame.rangeAlpha` is set to nil,
  so it fixes itself on the next 0.5 s tick.
- **Default spells** are stored as rank-1 IDs, turned into names with `C_Spell.GetSpellName`, and
  kept only if known (`C_Spell.GetSpellInfo(name)` or `IsSpellUsable`). The name resolves to the
  highest known rank.

  | Class | Friendly | Hostile |
  |---|---|---|
  | Priest | Lesser Heal 2050, Flash Heal 2061, Renew 139, Power Word: Shield 17 | Shadow Word: Pain 589, Smite 585, Mind Blast 8092 |
  | Druid | Healing Touch 5185, Rejuvenation 774 | Wrath 5176, Moonfire 8921 |
  | Paladin | Holy Light 635, Flash of Light 19750 | Holy Shock 20473, Judgement 20271, Hammer of Justice 853 (10 yards only) |
  | Shaman | Healing Wave 331, Lesser Healing Wave 8004 | Lightning Bolt 403, Earth Shock 8042 |
  | Mage | Remove Lesser Curse 475, Arcane Intellect 1459 | Frostbolt 116, Fireball 133, Fire Blast 2136 |
  | Warlock | Unending Breath 5697 | Shadow Bolt 686, Immolate 348, Corruption 172 |
  | Hunter | none | Arcane Shot 3044, Auto Shot 75, Serpent Sting 1978, Wing Clip 2974, Raptor Strike 2973 |
  | Rogue | none | Throw 2764, Shoot Bow 2480, Shoot Gun 7918, Shoot Crossbow 7919, Sinister Strike 1752 |
  | Warrior | none | Shoot Bow 2480, Shoot Gun 7918, Shoot Crossbow 7919, Throw 2764, Heroic Strike 78 |

- **Custom spells:** `range.friendly<CLASS>`, `range.friendlyAlt<CLASS>`, `range.hostile<CLASS>`
  and `range.hostileAlt<CLASS>` work as before. If either one is known, the custom pair replaces the
  defaults, and both are checked with the same "any in range" rule.
- The spell cache refreshes on `SPELLS_CHANGED` instead of `PLAYER_SPECIALIZATION_CHANGED`.
- The phase check uses `UnitPhaseReason` and only counts it when it isn't secret. This also fixes an
  old bug: the `or Enum.PhaseReason.TimerunningHwt` term was always true.
- No settings changed.

## fader.lua

- **Secret health or power** counts as "not full", so the frame fades in. This keeps frames visible
  rather than hiding them. Out of combat this is rare for the player or party.
- **Secret current alpha** (after a secret range result) counts as 1 when a fade starts, and as a
  plain value for the aura swipe fix.
- **Cast GUIDs for the casting fade-in** are compared only when they aren't secret. If one is secret,
  any start or stop counts.
- No settings changed.

## portrait.lua

- The 3D portrait uses `ShadowUF.Units.ReadGUID`. A nil (secret) GUID always refreshes the model, so
  the animation may jump on full updates for restricted units.
- The class portrait uses `GetClassAtlas` only if `C_Texture.GetAtlasInfo` confirms the atlas
  exists. Otherwise it falls back to the old `UI-CharacterCreate-Classes` sheet with
  `CLASS_ICON_TCOORDS`.
- 2D portraits (`SetPortraitTexture`) are unchanged.

## indicators.lua

- **Removed:** `arenaSpec` (no specs or arenas) and `petBattle` (no pet battles in Classic content).
  `UpdateArenaSpec`, `UpdatePetBattle` and the `GetArenaOpponentSpec`/`GetSpecializationInfoByID`
  role code are gone. `lfdRole` for arena frames now just hides.
- **Added:** `happiness`, the hunter pet happiness indicator, taken from SUF's classic branch.
  - It uses `C_PetInfo.GetPetHappiness` (falling back to `GetPetHappiness`) and `HasPetUI`.
  - It listens to `UNIT_HAPPINESS` and `UNIT_PET`.
  - It uses the `UI-PetMad`/`UI-PetNeutral`/`UI-PetHappiness` atlases if they exist, otherwise the
    `Interface\PetPaperDollFrame\UI-PetHappiness` texture with coords.
  - It only shows when the frame's unit is "pet".
- **Secret handling:**
  - Secret booleans go through `SetAlphaFromBoolean`. This applies to quest boss, resurrect,
    combat status, the PvP flag and the leader crown.
  - A secret leader flag shows only the leader crown, because the code can't pick between the
    leader and assistant icons.
  - A secret raid target index is passed straight to `SetRaidTargetIconTexture`, which uses
    `SetSpriteSheetCell` and accepts secrets.
  - `UnitIsUnit`, `UnitInRaid`, `UnitInParty`, `UnitGroupRolesAssigned`, `UnitPhaseReason`,
    `UnitFactionGroup`, `GetReadyCheckStatus` and summon status are read through
    `Secrets.Read`. Secret counts as no.
- Master looter uses `C_PartyInfo.GetLootMethod` and `Enum.LootMethod.Masterlooter`, falling back
  to `GetLootMethod`.
- **Ready check:** the atlas names fall back to literal names if the `READY_CHECK_*_TEXTURE` globals
  are missing. A new ready check now cancels the old one's fade.
- Phase now also refreshes on `UNIT_PHASE`.

## combattext.lua

- Blizzard's `CombatFeedback_OnCombatEvent` does `amount ~= 0`, and `UNIT_COMBAT`'s amount is
  always secret (`SecretValue = true`), so calling it from addon code would error. The module now
  has its own version of the same logic and its own fade OnUpdate (same timings).
- A secret amount only goes to `C_StringUtil.BreakUpLargeNumbers` (through `Secrets.BreakUp`) and
  `SetText`.
- With a secret amount, a WOUND whose flags are ABSORB, BLOCK or RESIST shows that word. Any other
  WOUND shows the number, so a zero-damage "WOUND" could show "0" instead of "Miss". Real misses
  come as their own events, so this should be rare.
- The scale is computed from the size multiplier instead of measuring `GetStringHeight`, which could
  be secret.

## Settings

- **New:** `units.pet.indicators.happiness`. Default:
  `{enabled = true, anchorPoint = "RC", size = 20, x = 0, y = 0, anchorTo = "$parent"}`, added to
  the pet unit in defaultlayout.lua.
  - Suggested label: "Pet Happiness".
  - Suggested description: "Indicator for the current pet happiness."
- **Removed (ignored by the module):** `indicators.arenaSpec` (core already removed the default) and
  `indicators.petBattle`. The `petBattle` defaults are still in defaultlayout.lua for target and
  focus. Options/core can drop them.
- No enUS edits were needed, because missing keys fall back to the key text.

## Changes needed elsewhere

- **ShadowedUF_Forever_Options/config.lua:**
  - Add `["happiness"] = L["Pet Happiness"]` to `INDICATOR_NAMES` and
    `["happiness"] = L["Indicator for the current pet happiness."]` to `INDICATOR_DESC`.
    Otherwise the tree shows "happiness".
  - Remove `petBattle` and `arenaSpec` from both tables.
  - The options are built from `Indicators.list`, which already reflects these changes.
- **ShadowedUF_Forever_Options/config.lua, line ~235:** this line hides the cast bar options for fake units. The cast
  module supports them through polling, so options could stop hiding `castBar` there if cast bars
  are wanted on every unit. That is the options owner's call, because it costs a 0.1 s ticker per
  frame.
- **Range options:**
  - The help text ("defaults appropriate for your class") still applies.
  - The hostile description says "Name of a friendly spell"; that is an old upstream typo.
  - `validateSpell` should accept spell names known through `C_Spell.GetSpellInfo`.
- **units.lua:** nothing required. Note that after a secret range result `frame:GetAlpha()` returns
  a secret. Anything outside fader.lua that reads the unit frame's alpha must not do maths on it.

## Unsure / untested in-game

- Whether `SetMinMaxValues`/`SetValue` cancels a bar started with `SetTimerDuration`, so the fade
  shows a full bar. If it doesn't, the fading bar keeps showing progress. That would only look odd.
- Whether `UnitCastingDuration` (SecretReturns) hands back an object that addon code may pass to
  `SetTimerDuration`. The call is in a pcall, so if it fails the bar shows full without a timer.
- Whether a secret-wrapped `interruptedBy` can mean "nil". If so, every restricted channel would end
  as "Interrupted".
- What `castBarID` means (per cast or per bar slot). The code is written to work either way.
- `CheckInteractDistance` on hostile units, which may be restricted. It runs out of combat in a
  pcall.
- Paladin hostile range is only 10–20 yards, because Classic has no long-range paladin attack.
- The pet happiness atlas and `HasPetUI` on camelot: `PetHappiness.lua` is tagged
  `[AllowLoadGameType mainline]`. The code falls back to the texture file.
