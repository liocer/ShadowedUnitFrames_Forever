# Porting notes: SUF → WoW Forever

Working notes for the port. Read this before touching any module.

## The client

- WoW Forever (product `wowf`), build **1.60.1.70862**, TOC interface **16001**.
- A *modern mainline engine* (Midnight-era API: `C_UnitAuras`, `C_Spell`, `C_CurveUtil`,
  duration objects, secret values) running *Classic-era content* (level 60, vanilla classes
  and spells). Game type is called **camelot**: `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT (18)`.
- Gone/never here: specializations (`GetSpecialization` is nil), runes, soul shards, holy
  power, chi, arcane charges, essence, stagger, insanity, evokers, monks, DKs, DHs.
  Dual spec exists (talent groups), LibDualSpec already handles it.
- Combo points live **on the target** (vanilla style): `GetComboPoints("player", "target")`,
  events `UNIT_POWER_UPDATE`/`UNIT_POWER_FREQUENT` (COMBO_POINTS) plus `PLAYER_TARGET_CHANGED`
  and `COMBO_TARGET_CHANGED`. See Blizzard_UnitFrame/Camelot/TargetBoundComboPointBar.lua.
- Druids have mana while in bear/cat form; shamans have totems (`GetTotemInfo`, may be secret).

## Reference material (local)

Scratch dir: `$S = /tmp/claude-1000/-home-rob-Games-Battlenet-pfx-drive-c-Program-Files--x86--World-of-Warcraft--forever--Interface-AddOns/e36ffed5-b699-4ba0-90b2-c6b458ae04da/scratchpad`

- `$S/src/blizz/Interface/AddOns/` – Blizzard's UI code for **this exact build**
  (Gethe/wow-ui-source, branch `forever`). Toc lines tagged `[AllowLoadGameType camelot]`
  or `[Game]` are the Forever versions; `[Family]` = Mainline code that Forever also loads
  unless `[ExcludeLoadGameType camelot]`.
  - API docs with secret flags: `Blizzard_APIDocumentationGenerated/*.lua`
  - Blizzard's own unit frames (heal prediction, absorbs, mana cost prediction):
    `Blizzard_UnitFrame/Mainline/UnitFrame.lua`, `.../Shared/*`, `.../Camelot/*`
  - Raid frames (how Blizzard filters auras/dispels under secrets):
    `Blizzard_UnitFrame/Shared/CompactUnitFrame.lua`
  - Cast bars: `Blizzard_UIPanels_Game` / search `CastingBarFrame`
- `tools/secret_apis.txt` – one line per API that can return secrets or has secret argument
  rules, generated from the docs. `SecretReturns=true` = may return secrets.
  `SecretArguments="AllowedWhenTainted"` = addon code may pass secrets in.
  `"AllowedWhenUntainted"` = addon code may NOT pass secrets in.
- `tools/forever_globals.lua` – every global the client UI defines/documents. Used by
  `.luacheckrc`. Run: `$S/rocks/bin/luacheck --no-color <files>` from the repo root.
  The docs are incomplete for some old C functions (e.g. `GetReadyCheckStatus`,
  `GetPartyAssignment`) – if Blizzard's own code calls a function, it exists.
- `$S/src/suf-classic` – upstream SUF's `classic` branch checked out (also `git show upstream/classic:modules/xyz.lua`),
  which may help for vanilla-specific bits.
- The user's own addon `/home/rob/code/RobUI/Bars.lua` already does secret-safe health,
  power, heal prediction, cast-cost ("spend") preview, combo pips via step curves, etc.
  It's proven to work in this client. Steal its patterns.

## Secret value rules (addon/tainted code)

A secret value can be: stored in locals/tables (as a *value*), passed to functions, passed to
APIs/widgets marked as accepting secrets, concatenated (`..` gives a secret string),
`string.format`ed / `tostring`ed (gives a secret string).

A secret value can NOT be (each raises a Lua error):
- compared (`==`, `~=`, `<`, `>`, ...), including against nil,
- used in arithmetic or `#`,
- tested for truthiness (`if x`, `x and y`, `x or y`, `not x`) – assume this errors too,
- used as a table key, indexed or called.

So: **before any test, check `issecretvalue(x)`** (or use `ShadowUF.Secrets` helpers in
`modules/secrets.lua`). Write code so the secret path still shows something sensible.

What usually works for display:
- Bars: `bar:SetMinMaxValues(0, max)` / `bar:SetValue(cur)` take secrets. A bar's
  `GetValue()` then returns a secret too. Overlay bars (heal prediction, cost) should be
  their own StatusBars anchored to the main bar's fill texture end (see RobUI), so no maths.
- Text: `fs:SetText(secret)` / `fs:SetFormattedText("%s / %s", cur, max)`;
  `C_StringUtil.AbbreviateNumbers`, `AbbreviateLargeNumbers`, `BreakUpLargeNumbers` accept
  secrets.
- Percent: `UnitHealthPercent(unit, usePredicted, CurveConstants.ScaleTo100)`,
  `UnitPowerPercent(unit, powerType, unmodified, curve)`. `UnitHealthMissing`, `UnitPowerMissing`.
- Colour gradients: `C_CurveUtil.CreateColorCurve()` + `UnitHealthPercent(unit, true, colorCurve)`
  returns a (possibly secret) color; check what `SetStatusBarColor`/`SetVertexColor` accept.
- Show/hide on a secret boolean: `region:SetAlphaFromBoolean(bool, alphaTrue, alphaFalse)`,
  `SetVertexColorFromBoolean`, `C_CurveUtil.EvaluateColorFromBoolean`. `SetShown(secret)` is
  NOT allowed from addon code.
- Step curves to turn a secret percent into 0/1 (alpha): see RobUI combo pips / Claw tick.
- Auras: `C_UnitAuras.GetAuraDataByIndex/GetUnitAuras/GetAuraDataByAuraInstanceID`; in
  combat fields can be secret. Filtering by spell name/ID won't work on secret auras; use
  the filter strings ("HELPFUL|PLAYER", "HARMFUL|RAID", ...) and the game's own helpers
  (`C_UnitAuras.IsAuraFilteredOutByInstanceID`, `GetAuraDuration`/duration objects,
  `Cooldown:SetCooldownFromDurationObject`, `GetAuraApplicationDisplayCount`,
  `GetAuraDispelTypeColor`). Look at how CompactUnitFrame.lua does it.
- `C_Secrets.*` can tell you ahead of time whether something will be secret.

Non-secret values (e.g. out of combat, or NPC targets) should keep SUF's original rich
behaviour (exact numbers, custom formats, gradients). Degrade gracefully only when secret.

## Ground rules for this port

- Keep SUF's architecture, module API, saved variable layout and options; change as little
  as needed. Keep credit to the original authors in file headers you touch heavily.
- Remove retail-only features rather than leaving dead code that errors (and tell the
  options work what was removed - write it in your notes file).
- Every file must pass `luac -p` and luacheck (`.luacheckrc`) with no new
  undefined-global warnings.
- Don't commit; the lead commits.
- Write what you changed, any new saved settings (key, default, suggested option label and
  description), removed settings, and open questions to `notes/<area>.md`.
