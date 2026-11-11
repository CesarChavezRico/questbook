// Thara's button plan (4BI-41). Source of truth for data/Plan.lua:  node dev/elle-config/emit-plan.js thara
// Seats follow the circles layout of dev/elle-config (which bar is which seat) and the pages in
// interests/wow/thara-forever-keybinds.md (4bits-cesar), level 24, decided by Cesar 2026-11-10.
// A page is 12 action slots; slot = (page - 1) * 12 + button.
const S = (name) => ({ kind: 'spell', name });
const M = (name) => ({ kind: 'macro', name });
const E = { kind: 'empty' };

module.exports = {
  name: 'Thara, level 24',
  // one macro per seat that changes with the form and is not on action bar 1
  macros: [
    ['QB Top M', '/cast [form:bear] Bash; [noform] Regrowth'],
    ['QB Top I', '/cast [form:bear/cat] Feral Charge; [noform] Healing Touch'],
    ['QB Home M', '/cast [form:cat] Rake; [noform] Rejuvenation'],
    ['QB Thumb 1', '/cast [form:cat] Ferocious Bite; [form:bear] Enrage; [noform] Thorns'],
    ['QB Thumb 2', '/cast [form:cat] Rip; [form:bear] Demoralizing Roar; [noform] Mark of the Wild'],
    ['QB Thumb 3', '/cast [form:cat] Prowl; [form:bear] Growl; [noform] Entangling Roots'],
    // the map key (Cesar, 2026-11-11: "use the key below the mousewheel"): one press per step of the map loop
    ['QB Map', '/qb overlay cycle', 'INV_Misc_Map_01'],
  ],
  // [page, button, what]. Every button the layout shows is listed, so nothing old lingers.
  seats: [
    // bottom key row = action bar 1 (the bar the game pages by form): caster 1, cat 7, bear 9
    [1, 1, E], [1, 2, E], [1, 3, S('Starfire')], [1, 4, S('Wrath')],
    [7, 1, E], [7, 2, E], [7, 3, S('Shred')], [7, 4, S('Claw')],
    [9, 1, E], [9, 2, E], [9, 3, E], [9, 4, S('Maul')],
    // home key row = bar 4 (page 3): pinky, ring, middle, index
    [3, 1, S('Cat Form')], [3, 2, E], [3, 3, M('QB Home M')], [3, 4, E],
    // top key row = bar 2 (page 6)
    [6, 1, E], [6, 2, E], [6, 3, M('QB Top M')], [6, 4, M('QB Top I')],
    // left thumb keys = bar 5 (page 4)
    [4, 1, E], [4, 2, S('Swipe')],
    // mouse thumbs = bar 7 (page 14): up, down. Buttons 3 and 4 were the gap and the single button of the first layout.
    [14, 1, M('QB Thumb 1')], [14, 2, M('QB Thumb 2')], [14, 3, E], [14, 4, E],
    // mouse big thumb button = bar 6 (page 13)
    [13, 1, M('QB Thumb 3')],
    // mouse index = bar 8 (page 15): front, rear
    [15, 1, S('Moonfire')], [15, 2, S('Faerie Fire')],
    // wheel = bar 9 (page 2): up, click, down, the button below the wheel
    [2, 1, S('Cat Form')], [2, 2, E], [2, 3, S('Bear Form')], [2, 4, M('QB Map')],
    // tilts = bar 10 (page 10)
    [10, 1, E], [10, 2, E],
  ],
};
