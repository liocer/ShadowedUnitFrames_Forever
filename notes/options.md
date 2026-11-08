# Options (options/config.lua)

Removed (the features don't exist on Forever):
- Bar groups and settings for soul shards, arcane charges, holy power, shadow orbs and chi
- Rune, stagger, priest mana and shaman mana bar toggles
- Stagger colour group and the retail power colours (runic power, runes, insanity, maelstrom, holy power,
  soul shards, arcane charges, chi, fury, pain, lunar power, mushrooms, statue, rune of power)
- Arena spec and pet battle indicators

Added or changed:
- Pet happiness indicator (`indicators.happiness`)
- Class/misc bars: "Enable Power cost prediction" (`powerPrediction.enabled`) and "Power cost brightness"
  (`powerPrediction.shade`, 10-100%), player and global only
- Totem bar description is shaman-only
- Range spells: accepts spell IDs or names (names resolve only for spells you know)
- Heal absorb "Outside bar limit" is hidden: heal absorbs are drawn inside the health bar now

Not done: in-combat caveats in option descriptions (aura lists, aggro highlight, range). The behaviour is
described in README.md instead.

Harness: every option's name/desc/hidden/disabled/values/get runs clean, and set() runs clean for every
toggle and range. The only error left comes from the harness not opening the real dialog.
