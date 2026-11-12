// MF Nameplates settings for Thara (4BI-43). Source of truth for data/Plates.lua:  node dev/elle-config/emit-plates.js
// Written into the character's profile in MF Nameplates' saved table (MFNameplatesDB) by /qb layout apply.
// MF Nameplates is all rights reserved and its code was not read. Every name below was seen in Cesar's own settings file
// (2026-11-12), where the profile "MF Forever" holds units.friendlyplayer.name.size = 18 and .level.size = 16.
module.exports = {
  name: 'nameplates: friendly player text at 12 (2026-11-12)',
  // [path inside the profile, value]
  sets: [
    // Cesar, 2026-11-12: "The friendly plate text is too big". Enemy names are 12 in the same file.
    [['units', 'friendlyplayer', 'name', 'size'], 12],
    [['units', 'friendlyplayer', 'level', 'size'], 12],
  ],
  // Not here yet, on purpose:
  // - the target marker: Cesar sees a glow though the file says "arrows"; waiting for a screenshot
  // - combo points on the plates: kept ("they belong to that specific enemy"); their flakiness is not understood yet
  // - friendly NPC plates: the profile sets nothing for them and the setting names are not known
};
