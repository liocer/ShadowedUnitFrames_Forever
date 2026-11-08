# Bars and resources: notes (bars agent)

Files: modules/health.lua, power.lua, incheal.lua, incabsorb.lua, healabsorb.lua, druid.lua,
altpower.lua, xp.lua, empty.lua, basecombopoints.lua, combopoints.lua, aurapoints.lua,
totems.lua, and the new powerprediction.lua. All 14 pass `luac -p` and luacheck with 0 warnings.

Deleted (`git rm`, not committed): runes, soulshards, holypower, chi, monkstagger, priest,
shaman, arcanecharges, essence.

## Required follow-ups in files I don't own

1. **ShadowedUnitFrames.lua `LoadUnitDefaults`: add the powerPrediction defaults.** Without
   them the module never turns on, because SetVisibility skips modules that have no config
   table, and defaultlayout's `verifyTable` strips tables that aren't in the defaults.
   Suggested change, in the unit loop next to incHeal (all real units):
   ```lua
   self.defaults.profile.units[unit].powerPrediction = {enabled = (unit == "player"), shade = 0.6}
   ```
   Doing it for the player only is enough: `self.defaults.profile.units.player.powerPrediction = {enabled = true, shade = 0.6}`.
2. **options/config.lua: add a "Power cost prediction" group** (next to incHeal/incAbsorb), see
   the settings table below. Also hide it for fake units (`hideRestrictedOption`), as incHeal
   is. The removed class bars' options (soulShards, arcaneCharges, runes, holy power, chi,
   stagger, essence, priest/shaman bars) are still in config.lua and need removing (options agent).
   Remove the totem bar's druid/monk/mage/warlock/DK wording too.
3. **tags.lua `[hp:color]`:** `ShadowUF.modules.healthBar.getGradientColor(unit)` still returns
   **plain numbers only**, so `ShadowUF:Hex` won't error. When health is secret it falls back
   to the yellow (50%) colour. The secret-capable version is `Health.getGradientColorAny(unit)`.
   It returns r, g, b that may be secret, so use it only with SetTextColor/SetVertexColor, not Hex.
4. **tags.lua `[totem:timer]`:** it reads `block.endTime`, which is set only for readable totem
   slots. For secret slots the bar runs from `GetTotemDuration(slot)`. A tag could show
   `GetTotemDuration(block.id):FormatRemainingDuration(...)` or use a DurationTextBinding;
   I haven't done that.
5. **aurapoints.lua:** its spell table is empty (the retail mage entry was commented out
   upstream), so the module returns before registering. It's harmless and lint-clean, so I left it.
   The lead could drop it from the TOC along with the `auraPoints` defaults, defaultlayout
   entries and options.
6. **Hunter pet happiness:** the client has `GetPetHappiness`, `UNIT_HAPPINESS` and
   `Enum.PowerType.Happiness = 27`. SUF retail had no happiness display. If wanted, it belongs
   in indicators (icon) and isn't something for the power bar.
7. units.lua: no changes needed. `CreateBar` and `SetBarColor`/`SetBlockColor` work as they are,
   and SetBlockColor passes (maybe secret) r,g,b straight to SetStatusBarColor/SetVertexColor,
   which accept secrets.

## New / changed settings

| db key | default | label | description |
|---|---|---|---|
| `units.<unit>.powerPrediction.enabled` | true for player, otherwise off/absent | Show power cost prediction | While the unit casts, the part of its power bar (or druid mana bar in forms) the spell will use is shown in a darker shade at the end of the bar. |
| `units.<unit>.powerPrediction.shade` | 0.6 | Cost shade | How bright the cost is drawn, as a fraction of the bar's own colour (0 = black, 1 = same colour). Range 0.1 to 1, step 0.05. |

Unchanged settings that still work: `healthBar.colorType/reactionType/colorAggro/colorDispel/invert/background/vertical/reverse`,
`powerBar.onlyMana/colorType`, `incHeal.cap`, `incAbsorb.cap`, `healAbsorb.cap` (healAbsorb's cap no longer
does anything, see below), `comboPoints.*` (isBar, showAlways, growth, size, spacing, background),
`totemBar.*` (icon, secure, showAlways, vertical, reverse), `xpBar`, `emptyBar`, `altPowerBar`.

Removed: totem bar variants for druid (mushrooms), monk (statue), mage (rune of power), warlock
and DK. The colours `powerColors.MUSHROOMS/STATUE/RUNEOFPOWER` are no longer used.

## Per file

- **incheal.lua** (rewritten). Each prediction bar is now its own StatusBar, as long as the health
  bar and on its 0 to max health scale. Its edge is anchored to the end of the health fill
  texture, so it follows the bar's orientation and reverse fill. A clip frame of size
  bar × `cap` from the bar's start enforces the "Outside bar limit" setting. No Lua maths on
  secret values. Amounts come from `CreateUnitHealPredictionCalculator` +
  `UnitGetDetailedHealPrediction(unit, "player", calc)`, set to MaximumHealth clamps (the clip
  does the capping). It falls back to `UnitGetIncomingHeals/UnitGetTotalAbsorbs/UnitGetTotalHealAbsorbs`.
  Shared helpers are exported for other modules: `ShadowUF.IncHeal.CreateClip(bar, cap)`, `UpdateClip`,
  `CreateOverlay(clip)`, `AnchorOverlay(overlay, bar, anchorTexture, inward)`,
  `SetOverlayValue(overlay, max, amount)` and `GetAmounts(frame)`. GetAmounts returns heals,
  absorbs, healAbsorbs and myHeals. myHeals isn't drawn yet; SUF never split my heals from others' heals.
  The old "simple vs complex" positioning modes are gone. The overlays draw only past the fill,
  so bar alpha < 1 no longer darkens anything.
- **incabsorb.lua**: damage absorbs, stacked after the incoming-heal bar's fill end (or after the
  health fill if incHeal is off).
- **healabsorb.lua**: heal absorbs, now drawn Blizzard-style *inside* the end of the health, growing
  back into it. With heal absorbs shown, the calculator uses `ReducedByIncomingHeals`: heals and
  heal absorbs cancel and only the remainder shows. Its cap setting is effectively ignored (it's
  clipped to the health bar), so the options could hide `healAbsorb.cap`. Previously SUF drew heal
  absorbs *after* the health.
- **health.lua**: values go through `Secrets.SetBar`. Gradient colouring uses the original maths when
  health is readable. When it's secret it uses a colour curve (red 0, yellow 0.5, green 1, rebuilt
  when the colours change) evaluated by `UnitHealthPercent(unit, false, curve)`. Dispel colouring
  finds the first debuff via the game's `"HARMFUL|RAID"` filter (player-dispellable, works on secret
  auras), with `Units:CanCure` on readable auras as a fallback. A readable `dispelName` uses SUF's
  own colour table (`Health.dispelColors`, the old DebuffTypeColor, which doesn't exist here).
  A secret one goes through `C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, stepCurve)`.
  Threat, reaction and class token are read through `Secrets.Plain`.
- **power.lua**: secret-safe bar values, guards on UnitPowerType returns, and it refreshes the cost
  preview on colour changes.
- **druid.lua**: secret-safe mana, also updates on `UPDATE_SHAPESHIFT_FORM`, and refreshes the cost preview.
- **powerprediction.lua** (new): see its header. Events are UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED/SUCCEEDED,
  UNIT_MAXPOWER and UNIT_DISPLAYPOWER. Costs come from `C_Spell.GetSpellPowerCost` and may be secret.
  A stop only clears the preview for the same cast GUID. FAILED for a different (or secret)
  GUID ("another action is in progress" / spell queue) is ignored. After clearing,
  `UnitCastingInfo` picks up any cast still going. It works for any unit whose casts fire events
  (target, party). For other units the cost is the player's version of that spell, which is approximate.
- **basecombopoints.lua**: when the count is secret, every point is shown and its alpha comes
  from a per-point step curve via the module's `GetPointAlpha`. The bar stays shown because it
  can't be hidden on a secret count. `ShadowUF.ComboPoints.GetStepCurve(id, max)` is exported.
- **combopoints.lua**: target-bound `GetComboPoints("player","target")`, updated on PLAYER_TARGET_CHANGED,
  COMBO_TARGET_CHANGED and power events. Shown for rogues, and for druids only in cat form
  (UPDATE_SHAPESHIFT_FORM). When secret it uses `UnitPowerPercent("player", ComboPoints, false, stepCurve)`, the same as RobUI.
  The vehicle (Malygos) code is removed.
- **totems.lua**: shaman only, as asked. Secret slots are detected with
  `C_Secrets.ShouldTotemSlotBeSecret` and use `SetTimerDuration(GetTotemDuration(slot), Immediate, RemainingTime)`
  plus `SetAlphaFromBoolean(haveTotem, 1, 0)`. Readable slots keep the original OnUpdate timer.
- **xp.lua**: pet XP via `GetPetExperience` (an undocumented C function; looked up with `_G[...]`).
  Max level comes from `GetMaxLevelForPlayerExpansion`. Rested XP and reputation
  (`C_Reputation.GetWatchedFactionData`) are kept. Nil and secret values hide the bar.
- **altpower.lua**: kept, since the UnitPowerBarAlt API and Blizzard's UnitPowerBarAlt load in
  Forever. It's probably rarely used with Classic content. Values are secret-safe.
- **empty.lua**: creature family, class and reaction are read through `Secrets.Plain`.

## Unsure / please test in game

- Overlays anchored to a StatusBar's fill texture when the value is 0. Hopefully the texture
  edge stays at the bar start; RobUI relies on this too. Stacked absorbs anchor to the
  incHeal overlay's fill texture, which hasn't been checked in game.
- `SetClipsChildren` on the clip frames when cap > 1: the clip reaches outside the unit frame,
  which is intended.
- Dispel type IDs used for the curve: Magic 1, Curse 2, Disease 3, Poison 4, Enrage 9, Bleed 11
  (from Midnight; not in this build's docs). Also whether `aura.auraInstanceID` stays readable
  in combat, and whether the `HARMFUL|RAID` filter really means "player can dispel" here.
- Whether `UnitHealthPercent(..., colorCurve)` returns a ColorMixin we can call `:GetRGB()` on in
  combat. It's pcall'd, and falls back to the yellow colour.
- The heal prediction calculator's enum names (`Enum.UnitIncomingHealClampMode` etc.) are taken
  from the docs. If anything fails it falls back to the raw APIs.
- `GetSpellPowerCost` entry fields (`type`, `cost`): costs with `hasRequiredAura` variants
  aren't filtered.
- Secret combo count: whether UnitPowerPercent(ComboPoints) follows the target-bound count.
  RobUI says yes.
- Totem `SetTimerDuration` is "AllowedWhenUntainted" for secret args. A duration object isn't
  itself a secret value, but if the call errors, the bar shows empty (pcall'd).
