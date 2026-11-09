# Shadowed Unit Frames Forever

Shadowed Unit Frames, ported to WoW Forever.

All credit for SUF goes to its authors: **Shadowed** (Mayen), who wrote it, and **Hendrik Leppkes
(Nevcairiel)**, who has maintained it since. This is a fork of the upstream code at
<https://github.com/Nevcairiel/ShadowedUnitFrames>, with its full history. The upstream repository
has no licence file, so treat this as a personal port: ask the authors before publishing it.

## Installing

The repository holds two addons, each in its own folder:

| Folder in `Interface/AddOns` | Is |
|---|---|
| `ShadowedUnitFrames_Forever` | The addon |
| `ShadowedUF_Forever_Options` | Its options (loaded when you open them) |

Copy (or symlink) both folders into `Interface/AddOns`, or unzip a release zip there: it has the
two folders at the top. On this machine they're symlinks into
`/home/rob/code/ShadowedUnitFrames_Forever/<folder>`.

Don't enable the original Shadowed Unit Frames at the same time. If it's loaded, SUF Forever stays
off and says so in chat.

`/suf` opens the options, `/suf help` lists the commands and credits.

## What's different from SUF

WoW Forever is a modern client running Classic content, and in combat the game gives addons
"secret" values: health, power, auras, casts and sometimes names can be shown but not compared or
used in maths. SUF did a lot of maths, so most modules were reworked:

- **Health and power bars** take the values straight from the game. The health gradient colour is
  worked out by the game in combat (a colour curve), and by SUF's own maths out of combat.
- **Incoming heals, absorbs and heal absorbs** are drawn as bars starting at the end of your
  health, the way Blizzard's Forever frames do, using the game's heal prediction.
- **Power cost prediction (new):** while you cast, the part of your power bar the spell will
  use is drawn in a darker shade, like Blizzard's Forever player frame. On druids in a form it's
  shown on the mana bar. Options: *Power cost prediction*, on by default for the player.
- **Text tags** all work in combat. Numbers and percentages come from the game. Tags that need
  maths in combat fall back sensibly; see `notes/tags.md` for each one.
- **Auras** use the game's own filters in combat ("yours", "curable", "castable"), so they keep
  working. White and black lists by name still apply to anything the game lets SUF read. Auras
  that were on before a fight are remembered by name.
- **Cast bars** are driven by the game when cast details are secret.
- **Range** uses the game's checks with Classic spells for each class (no LibSpellRange).
- **Classic content:** target-bound combo points, druid mana in forms, shaman totems, hunter pet
  happiness, Classic dispels per class (and the Felhunter's Devour Magic), Classic aura indicator
  spells.
- **Removed** (they don't exist on Forever): runes, soul shards, holy power, chi, stagger, arcane
  charges, essence, priest/shaman alternate mana bars, arena specs, specialization handling. Old
  settings for them are cleaned out of profiles automatically.

What can't be done in combat (the game doesn't allow it):

- Aggro and target/focus highlights switch off when threat or unit identity is secret.
- A boss debuff that first appears in combat can't be told apart from other debuffs.
- Threat text, AFK, server and similar tags show nothing while secret.

## Testing in game

Nothing here has run in the real client yet. Things worth checking first, roughly in order:

1. It loads without errors and `/suf` opens the options.
2. In combat: health/power numbers and percentages (`[perhp]`, `[hp:color]`), the health
   gradient, incoming heals on a party member, and the spend preview while casting.
3. Auras in combat: timers, stacks, debuff border colours, your own buffs.
4. Cast bars on you and your target in combat.
5. Rogue/druid combo points on a target in combat, shaman totem timers.
6. Range fading on party members.
7. Blizzard's frames stay hidden (combo point ring, totem frame, druid mana bar).

Each `notes/*.md` file ends with a list of what that area wasn't sure about.

## Development

Repository layout:

```
ShadowedUnitFrames_Forever/   the addon (TOC, code, libs, media, localization)
ShadowedUF_Forever_Options/   the options addon
tools/  notes/  PORTING.md    development only, not packaged
.pkgmeta  .github/workflows/  packaging
```

Releases: push a tag (for example `git tag v1.0.1 && git push --tags`). GitHub Actions runs
luacheck, then the BigWigs packager builds `ShadowedUnitFrames_Forever-<tag>.zip` with both
addon folders and attaches it to a GitHub release. To build the zip locally without uploading,
run `release.sh -d` from <https://github.com/BigWigsMods/packager>; it lands in `.release/`.

- `PORTING.md`: client facts and the rules for secret values.
- `notes/`: what changed in each area of the port.
- `tools/forever_globals.lua`: every global the Forever client defines, used by `.luacheckrc`, so
  luacheck flags APIs that don't exist here.
- `tools/secret_apis.txt`: which APIs can return secrets, from the client's API docs.
- `tools/harness/`: a mock Forever client. `cd tools/harness && lua5.1 run.lua <repo root>` loads the
  addon, plays updates out of combat and in combat with fake secret values, opens the options,
  and lists every error. `CLASS=ROGUE` etc. picks the player's class.
- `tools/check_tags.lua`, `tools/test_tags.lua`: lint and test every default tag.

The API data comes from Blizzard's UI source for this exact build (Gethe/wow-ui-source, branch
`forever`).
