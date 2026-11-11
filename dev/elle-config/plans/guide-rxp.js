// RestedXP Guides settings for Thara (4BI-42). Source of truth for data/Guide.lua:  node dev/elle-config/emit-guide.js
// Written into the profile of RestedXP's AceDB settings table (RXPSettings) by /qb layout apply.
// Key names and the shape of framePositions come from RestedXP's SettingsPanel.lua (read 2026-11-11). Positions are in UI units;
// Cesar's screen is 2867 x 1200 units (3440 x 1440 at UI scale 0.64).
module.exports = {
  name: 'guide in the upper left, 2026-11-11',
  values: {
    // Cesar, 2026-11-11: quest automation OFF (he listens to the quest text); skipping gossip would skip that text too
    enableQuestAutomation: false,
    enableGossipAutomation: false,
    // our theme (modules/Guide.lua)
    activeTheme: 'QuestBook',
    // its defaults are sized for UI scale 1; at 0.64 they are small
    windowScale: 1.25,
    // the guide window in the upper left ("on the upper left is what I mean"), its helper windows under it instead of mid-screen
    framePositions: {
      RXPFrame: [['TOPLEFT', 'UIParent', 'TOPLEFT', 30, -60]],
      activeItemFrame: [['TOPLEFT', 'UIParent', 'TOPLEFT', 30, -420]],
      activeTargetFrame: [['TOPLEFT', 'UIParent', 'TOPLEFT', 30, -480]],
    },
  },
  // left at RestedXP's defaults on purpose: minimap pins on ("I would say on, but I need more info"), mob marking on
  // ("this should be better than what we get from the plates"), flight path and innkeeper automation on, the arrow at the top centre
};
