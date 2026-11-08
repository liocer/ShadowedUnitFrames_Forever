# Tags (modules/tags.lua)

Owner: tags agent. Files touched: `modules/tags.lua` (largely rewritten, original structure kept),
new `tools/check_tags.lua`, new `tools/test_tags.lua`. I didn't need to change `localization/enUS.lua`
(it falls back to the key, so new `L[...]` strings work as they are) or `modules/defaultlayout.lua`
(the core agent had already removed the `[rune:timer]` and `[monk:abs:stagger]` text rows).

## How to check

```
lua5.1 tools/check_tags.lua $S/rocks/bin/luacheck   # compiles + luacheck on every default tag
lua5.1 tools/test_tags.lua [-v]                     # runs every tag with plain and fake secret values
$S/rocks/bin/luacheck --no-color modules/tags.lua
```
All three are clean: 78 tags, 0 warnings, 2719 runs, 0 failures.

To check that the harness catches real problems, `TAGS_FILE=<orig tags.lua> lua5.1 tools/test_tags.lua`
runs it against the original file. That fails about 50 tags.

`check_tags.lua` adds `GetGuildInfo GetRaidRosterInfo GetNumGroupMembers` as read globals. They're
missing from `tools/forever_globals.lua`, but Blizzard's own code for this build calls them.

The harness can't catch everything. Lua 5.1 can't intercept truthiness tests (`if x`, `x and y`,
`x or y`, `not x`) or `secret == plain` on a userdata. I reviewed every tag and the machinery for
those by hand, and the test also greps for `UnitX(...) or` and `UnitX(...) <op>` patterns.

## Machinery changes

- Tag results are only tested after `issecretvalue()`. Results that are `nil` or `false` become `""`,
  and secret results are passed straight to `SetFormattedText` (the docs say it takes secrets from
  tainted code). The pre/append wrappers (`[(x)tag(y)]`) concatenate secrets, which is allowed.
- The power-type event filter skips filtering if the event's powerType arg is secret.
  `UpdatePowerType` guards `UnitPowerType`.
- **Custom tags** (anything in `db.profile.tags` that isn't a default tag) run inside `pcall`. An error
  blanks only that tag. The first error per tag per session goes to `geterrorhandler()` as
  `Shadowed Unit Frames: custom tag [x] failed: ...`. Default tags are not wrapped, as the brief asked.
- **Removed tags** (`Tags.removedTags`) show nothing instead of `[tag-error]`, so old saved texts stay
  quiet: `rune:timer, sshards, hpower, monk:chipoints, monk:stagger, monk:abs:stagger`.
- **Aliases** (`Tags.tagAliases`): `sec:curpp/abscurpp/curmaxpp/absolutepp` now point at the
  `druid:*` tags. In Classic only druids have mana as a secondary power (there's no Insanity or
  Maelstrom), so they were identical. Events and frequency follow the alias. A custom tag with the
  same name still wins.
- **Fading a single-tag text.** A tag can call `ShadowUF.Tags.FadeText(fontString, alpha)`, where
  `alpha` may be secret. It only takes effect when the font string's text is that one tag and nothing
  else but spaces. It then calls `fontString:SetAlpha(alpha)` in a pcall, and the alpha goes back to 1
  on the next update or on unregister. `[missinghp]` and `[missingpp]` use it to vanish at full when
  the values are secret.
- `abbrevCache` used to cache under the abbreviated name, so it never hit. It's keyed by the
  original name now, and only ever with plain names.
- Tag lookup uses plain `string.find`, because tag names contain `-` and `:`.
- Events: added `COMBO_TARGET_CHANGED` as unitless. Removed `UNIT_COMBO_POINTS`,
  `RUNE_POWER_UPDATE` and `RUNE_TYPE_UPDATE`. The custom-tag event scanner (`APIEvents`) now knows
  `UnitHealthPercent/Missing`, `UnitPowerPercent/Missing`, `UnitGetIncomingHeals`,
  `UnitGetTotalHealAbsorbs` and `GetPetHappiness`. `GetComboPoints` maps to
  `UNIT_POWER_FREQUENT PLAYER_TARGET_CHANGED COMBO_TARGET_CHANGED`. The rune APIs are gone.
- GUID compares use `ShadowUF.Units.ReadGUID` (from core), which gives nil for secret GUIDs.

## Helpers (public, usable in custom tags)

| Helper | What it does |
|---|---|
| `ShadowUF.Tags.Plain(v)` | `v`, or nil if `v` is secret |
| `ShadowUF.Tags.Abs(v)` | `v`; a secret number becomes a (secret) `"%d"` string |
| `ShadowUF:FormatLargeNumber(v)` / `:SmartFormatNumber(v)` | Unchanged for plain values. For secret values they use `C_StringUtil.AbbreviateNumbers` with breakpoints copying SUF's formats (`9999`, `12.3k`, `1.23m`, `123m`). Those breakpoints are only used if a test with plain numbers at load gives exactly SUF's output; otherwise the game's default (`12K`) is used. |
| `ShadowUF.Tags.HealthPercentText(unit, fmt)` / `PowerPercentText(unit, fmt[, powerType])` | `string.format(fmt, UnitHealthPercent/UnitPowerPercent(..., ScaleTo100))` |
| `ShadowUF.Tags.HealthNotFull(unit)` / `PowerNotFull(unit)` | Secret 1/0 from a step curve |
| `ShadowUF.Tags.FadeText(fontString, alpha)` | See above |
| `ShadowUF.Tags.HealthGradientHex(unit)` | `[hp:color]` when health is secret |
| `ShadowUF.Tags.HasAura(unit, spell)` | true, false, or nil if it can't be told |
| `ShadowUF.Tags.DruidForm(unit)` | `"Cat"`, `"Bear"`, ... or nil |
| `ShadowUF:Hex(...)` | Returns nil for secret or missing colours instead of erroring |
| `ShadowUF:GetClassColor(unit)` | Returns nil if the class is secret or has no colour (DK/Monk/DH/Evoker colours were removed) |

The helpers never call unit APIs on the plain path. The movers' config mode swaps the tag
functions' environment for fake `UnitHealth` and friends, so tag code calls those APIs itself.

## Behaviour per tag when values are secret

Plain values give exactly the original output in every case.

| Tag(s) | When secret |
|---|---|
| curhp, maxhp, curmaxhp, curpp, maxpp, curmaxpp, incheal, incabsorb, healabsorb, druid:curpp, druid:curmaxpp | Game abbreviation using SUF's breakpoints (see above) |
| smart:curmaxhp, smart:curmaxpp | Same, but millions only |
| abscurhp, absmaxhp, absolutehp, abscurpp, absmaxpp, absolutepp, abs:incheal, abs:incabsorb, abs:healabsorb, druid:abscurpp, druid:absolutepp, cpoints | `"%d"` of the secret |
| perhp, perpp | `UnitHealthPercent` / `UnitPowerPercent` with `"%.0f%%"` (the plain path rounds the same way) |
| dechp | Same, with `"%.1f%%"` |
| missinghp, missingpp | `"-" .. abbreviated UnitHealthMissing/UnitPowerMissing`. Alone in a text it fades out at full; next to other text it shows `-0` at full |
| def:name | Shows the name (can't tell whether anything is missing) |
| hp:color | Three linear curves (r, g, b × 255) over health, red → yellow → green, from `healthColors`. Built with `string.format("%02x")` on the secret curve outputs |
| incheal, incabsorb, healabsorb and their abs: forms | Always secret in Forever (`SecretReturns=true`), so they **show 0 when nothing is incoming**. There's no way to hide 0 in a string, and no API turns a secret number into a boolean or alpha. |
| incheal:name, incabsorb:name | The name |
| per:incheal | Nothing |
| name, abbrev:name, colorname, guild, race, class, creature, smartclass, smartrace, faction | Secret strings pass through. abbrev:name shows the full name; colorname has no colour if the class is secret |
| server | Nothing |
| sex | Nothing |
| afk, afk:time | Nothing; the AFK timer isn't reset (secret during chat lockdown) |
| situation, unit:situation, general:sit, color:*, unit:color:* | Nothing (`GetThreatStatusColor` doesn't take secrets) |
| scaled:threat | `"%d%%"` of the secret |
| group | Nothing if the unit's name or raid index is secret; roster entries with secret names are skipped |
| unit:raid:targeting, unit:raid:assist | Nothing if the unit's GUID is secret; raid members whose target GUID is secret aren't counted |
| level, levelcolor, smartlevel, classification, plus, rare, shortclassification, reactcolor, pvp:time, status, status:time | The docs say these APIs never return secrets. They're guarded anyway: a secret level shows as a number with no colour, everything else shows nothing |
| druidform, short:druidform | Nothing if the aura data is secret. Dire Bear Form (9634) was added; before, it showed nothing |
| totem:timer | Nothing if `block.endTime` is secret |

## Tags removed, changed or added

- **Removed:** `rune:timer`, `sshards`, `hpower`, `monk:chipoints`, `monk:stagger`, `monk:abs:stagger`.
  Their events, categories, help, names and restrictions are gone too. Saved texts using them show
  nothing.
- **Folded into druid:\*:** `sec:curpp`, `sec:abscurpp`, `sec:curmaxpp`, `sec:absolutepp`. They no
  longer appear in the tag list, but still work in saved texts.
- **Changed:**
  - `cpoints` uses `GetComboPoints("player", "target")` (falling back to `UnitPower(ComboPoints)`),
    and the vehicle branch is gone. Events are `UNIT_POWER_FREQUENT PLAYER_TARGET_CHANGED
    COMBO_TARGET_CHANGED`, plus a 0.25 s poll: the target frame's unit events are filtered to
    "target", but combo point power events fire for "player".
  - `druid:*` no longer checks LunarPower, so they show only in Bear or Cat form.
- **Added:** `[pet:happiness]` shows Happy, Content or Unhappy (`PET_HAPPINESS1..3`, falling back to
  `L[...]`). It uses `C_PetInfo.GetPetHappiness()` if that exists. Restricted to the pet unit, event
  `UNIT_HAPPINESS`, category `classspec`.
- I didn't add `[dead]`, `[offline]`, `[threat]`, `[shortclass]`, `[healcolor]` or `[absorbs]`. The
  brief named them, but they aren't SUF tags; `[status]`, `[situation]`, `[class]`, `[incabsorb]` and
  friends cover the same ground.

## For the options agent

Help and name text lives in `Tags.defaultHelp` and `Tags.defaultNames` in tags.lua, which
options/config.lua reads, so most of it is already updated:
- New `|n...` sentences on the help for missinghp, missingpp, def:name, incheal, abs:incheal,
  per:incheal, incheal:name, incabsorb, abs:incabsorb, incabsorb:name, healabsorb, abs:healabsorb,
  abbrev:name, unit:raid:targeting, unit:raid:assist, and the six threat situation/colour tags.
- New entry `pet:happiness`: name "Pet happiness", help "Your hunter pet's happiness: Happy, Content
  or Unhappy. Shows nothing if the game doesn't report it."
- Options may still mention the removed tags, or categories that are now empty or Forever-irrelevant
  (`classtimer` only has totem:timer now). Please check `options/config.lua` for references to
  rune/stagger/chi/holy power/soul shard tags.
- Suggested text for the custom tag help: "Health, power, names and more can be secret in combat:
  check `issecretvalue(x)` before comparing or testing a value. Secrets can be concatenated,
  string.format'ed or returned as they are. `ShadowUF.Tags.Plain`, `ShadowUF.Tags.Abs` and
  `ShadowUF:FormatLargeNumber` are secret-safe. A custom tag that errors shows nothing, and the
  error is reported once."

## Bug in secrets.lua (not mine, please fix)

`Secrets.HealthPercent` and `Secrets.PowerPercent` test `value ~= nil` on the result of
`UnitHealthPercent` / `UnitPowerPercent`, which is secret in combat. The porting rules say comparing a
secret against nil raises an error. `Secrets.SetBar` has the same problem with `if( pct ~= nil )`.
Use `issecretvalue(value) or value ~= nil` instead. tags.lua doesn't call those helpers.

## Unsure in game

- Whether `string.format("%02x", secret)` and `"%d"` / `"%.0f"` on secrets work. The porting rules
  say string.format on secrets is allowed; RobUI only proves `SetFormattedText("%d")`. If they fail:
  - `Tags.Abs` and the percent helpers return the raw secret;
  - `hp:color` returns nil (it's in a pcall);
  - the percent tags would error (they're not in a pcall).
  Worth one in-combat test of `[perhp]` and `[hp:color]`.
- Whether `C_StringUtil.CreateAbbreviateConfig` / `breakpointData` accept SUF's breakpoints. If they
  don't, the check at load falls back to the game's default abbreviation (e.g. `12K`).
- Whether a secret number passed to `SetFormattedText` as `%s` works. Tags mostly return secret
  strings rather than secret numbers, to be safe.
- Whether `FontString:SetAlpha(secret)` is allowed. The docs say AllowedWhenTainted for regions; it's
  pcall'd and falls back to alpha 1.
- Whether the step curve hits exactly 1.0 at full health, so `[missinghp]` fades.
- Whether `C_PetInfo.GetPetHappiness` exists and works on camelot. `PetHappiness.lua` only loads for
  mainline, but the API is documented for this build.
- Spell IDs 33891, 40120 and 33943 (Tree and the flight forms) are TBC; `GetSpellName` gives nil if
  they're absent, which is harmless.
- `[scaled:threat]` in combat: `"%d%%"` of a secret percent.
