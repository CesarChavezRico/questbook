// Thara's cooldown display (4BI-51), decided with Cesar on 2026-11-24. Read by emit-cooldowns.js.
// Spell ids are the ranks Thara had at level 37 (the game's answer of 2026-11-24). A new rank is a new id: run the
// question again and update this file when one of these spells is trained up.
//
// native = in Blizzard's cooldown list for the class (its category set). custom = not in it: EllesmereUI draws those
// itself and warns that they may not work fully.
// rule:  form = 'cat' | 'bear' | 'prowl'   shown only on that page of the stance bar (the others close the gap)
//        when = 'cooldown'                 hidden while ready, shown while on cooldown
//        when = 'usable'                   shown only while the game says the spell can be cast (Energy aside)
module.exports = {
  name: 'Thara cooldowns: press now by form, on cooldown only, cat rotation (2026-11-24)',
  spec: '102',
  rows: {
    // row 1, large: press now
    cooldowns: [
      { id: 1259799, name: "Elune's Light" },
      { id: 16689, name: "Nature's Grasp" },
      { id: 5229, name: 'Enrage', form: 'bear' },
      { id: 6798, name: 'Bash', form: 'bear' },
    ],
    // row 2, small: nothing while everything is ready
    utility: [
      { id: 1238122, name: 'Feral Charge', when: 'cooldown' },
      { id: 1850, name: 'Dash', when: 'cooldown' },
      { id: 20580, name: 'Shadowmeld', when: 'cooldown' },
      { id: 6795, name: 'Growl', when: 'cooldown' },
    ],
  },
  // a new bar: the options in a cat fight
  rotation: {
    key: 'custom_6_4bi51',
    name: 'Cat rotation',
    iconSize: 40,
    position: { point: 'LEFT', relPoint: 'CENTER', x: -104, y: -145 },
    spells: [
      { id: 6785, name: 'Ravage', custom: true, form: 'prowl' },
      { id: 1823, name: 'Rake', form: 'cat' },
      { id: 3029, name: 'Claw', custom: true, form: 'cat' },
      { id: 22568, name: 'Ferocious Bite', custom: true, form: 'cat', when: 'usable' },
      { id: 9493, name: 'Rip', form: 'cat', when: 'usable' },
    ],
  },
  // Blizzard's cooldown list entries that are shown nowhere: parked on EllesmereUI's hidden bar, or it puts them back
  hidden: [
    { id: 8927, name: 'Moonfire' }, { id: 5570, name: 'Insect Swarm' }, { id: 778, name: 'Faerie Fire' }, { id: 8972, name: 'Maul' },
    { id: 407995, name: 'Primal Bite' }, { id: 1328617, name: 'Lacerate' }, { id: 408120, name: 'Wild Growth' }, { id: 18562, name: 'Swiftmend' },
    { id: 1322605, name: 'Shifting Power' }, { id: 5209, name: 'Challenging Roar' }, { id: 8998, name: 'Cower' }, { id: 22812, name: 'Barkskin' },
    { id: 22842, name: 'Frenzied Regeneration' }, { id: 17116, name: "Nature's Swiftness" }, { id: 740, name: 'Tranquility' },
    { id: 29166, name: 'Innervate' }, { id: 20739, name: 'Rebirth' },
  ],
  // the buffs bar: these first (Blizzard's tracked buff ids): Elune's Light while it runs, Rake and Rip on the target
  buffsFirst: [
    { cd: 200190, name: "Elune's Light" }, { cd: 199495, name: 'Rake' }, { cd: 199499, name: 'Rip' },
  ],
};
