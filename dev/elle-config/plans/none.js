// The empty button plan (4BI-50). Source of truth for data/Plan.lua:  node dev/elle-config/emit-plan.js none
// Cesar, 2026-11-24: "yes empty it". The plan shipped until then was plans/thara.js, written at level 24; at level 37
// `/qb bars apply` would have put those buttons back over the ones he had arranged since. An empty plan in the addon
// folder also stands in front of any plan left in the saved settings, so `/qb bars apply` places nothing.
// His buttons are now saved with every state file (`bars`) and read live with `q bars`; a plan to restore them can be
// written from one of those when it is wanted.
module.exports = {
  name: 'none (emptied 2026-11-24)',
  macros: [],
  seats: [],
};
