# Tien's Customizable Hotbar

Project Zomboid B42 mod (client only): a second hotbar whose slots hold any item the player carries, bags included.
A slot takes its item out of its bag and equips it (or wears it), and puts it back into that bag on the next press; or
it runs any action from the item's own context menu. The live code is under `Contents/mods/TienCustomizableHotbar/42/`.
General engine findings go in `~/Zomboid/Workshop/ZomboidFixesB42/CLAUDE.md` ("Hotbar attachments and carry weight",
"UI building blocks learned for the hotbar"); this file only holds the reasoning behind this mod.

The Lua source has no comments on purpose. Non-obvious reasoning lives here; update this file when it changes.

## Status

First implementation (2026-10-09), not yet run in game. Only checked with luaparser (syntax and free globals). No art
yet: mod.info has no `poster` / `icon` and there is no `preview.png` (needed for the Workshop upload). See "To verify".

## Origin

The user first wanted items attached to a bag's hotbar slots to weigh as if inside the bag; that cannot be done from Lua
(the load sum is Java, see ZomboidFixesB42 "Hotbar attachments and carry weight"). This mod came instead. User's
choices (2026-10-09): its own bar rather than hijacking vanilla's; key binds assignable, none bound by default, slots
clickable; a slot keeps the exact item as its priority and falls back to another of the same full type, greyed out with
none; switching slots puts the held item back into its bag first, with vanilla timed actions; slots can run any action
from the item's menu like TienActionableHotbar.

## Files

- `client/TienCustomizableHotbar_Core.lua`: data, item lookup, bag memory, action records.
  - Player modData `TienCustomizableHotbar = { slots = { { id, type, action } ... }, homes = { ["<item id>"] = <bag id> } }`,
    sent with `transmitModData()` on every change (what vanilla's `ISHotbar:savePosition` does for its layout). Item IDs
    are stable across bags and on a server, so they identify "the exact item". `Mod.version` bumps on every change and
    the bar rebuilds.
  - `Resolve(player, slot)`: the exact item (`getItemWithIDRecursiv`, same full type), else the best item of the type in
    the tree: not assigned to another slot (+20), not broken (+10), then in hand > worn > main inventory > bag. Returns
    `item, exact`.
  - `EachItem` walks the main inventory and bags inside it, 6 deep (own walk: `getAllTypeRecurse` matches by its own
    type rules and gives no container).
  - Homes: the bag an item goes back to. Recorded when the item is seen in a bag on the player (`RememberHome`: at
    assignment, before every use, and by the bar's `Track` every 500 ms for every slot's item), so even an item equipped
    by hand from a bag goes back there. Forgotten only after the item has lain loose in the main inventory, not held or
    worn, for 15 s (`LOOSE_FORGET_MS`): long enough to cover the transfer → equip gap of a draw, short enough that moving
    the item into the main inventory on purpose sticks. Pruned to items still carried past 60 entries.
  - Action records, `Snapshot`, `Match`, `FunctionName`: copied from TienActionableHotbar (each mod keeps its own copy).
    A slot's action is one record (no per-type / per-item scopes: the slot is the scope). `BuildLeaves` builds the item's
    menu silently (`Mod.silent`, `closeAll()` in the same frame) and skips this mod's and Actionable Hotbar's own options.
- `client/TienCustomizableHotbar_Use.lua`: what a press does.
  - `CanUseNow`: vanilla `ISHotbar:isAllowedToActivateSlot` rules (paused, dead, attacking, radial open, action queue not
    empty → nothing).
  - Default: held or worn → `PutAway` (unequip: `ISUnequipAction` 20 like vanilla's hotbar for hand items, vanilla
    `unequipItem` for worn and lit candles / lanterns; then `QueueReturn`). Wearable (Clothing, or an
    InventoryContainer with `canBeEquipped()`) → `onWearItems` (transfers first). Else `Equip`.
  - `Equip` copies vanilla `ISHotbar:equipItem` hand rules (two-handed → both; weapon → primary; a non-weapon to the off
    hand unless only the off hand is full) and its heavy-item drop. Hand items the equip will displace (from
    `ISEquipWeaponAction:complete`: primary displaces primary and a both-hands secondary; secondary displaces secondary
    and a two-handed primary) that have a home are put away **first** (unequip + transfer back), so the order is "gun
    back in the bag, then knife out". Then `transferIfNeeded` (vanilla's bag → main inventory transfer, its normal speed:
    the draw is slower on purpose), `ISEquipWeaponAction(20)`, and a `Then` action that sends back any other hand item
    the equip pushed out (the handgun rule clears a secondary HandWeapon, two-handed items...).
  - `Then` (`TienCustomizableHotbarThen`): a 1-tick client-only timed action (no `complete`, so never a server action)
    that runs a function in `perform`; transfers it queues there start right after it. It is dropped with the queue when
    the equip before it fails.
  - `QueueReturn`: transfer main inventory → home bag (`newInventoryTransferAction` + `setAllowMissingItems(true)` like
    vanilla's put-backs), refused with a halo text when the bag is gone, does not allow the item or has no room.
  - Custom action: match the record in a freshly built menu, run its `onSelect` like `ISContextMenu:onMouseUp`. Not
    found / greyed out: put away if held or worn (so "Equip Primary" toggles), else a bad halo text.
- `client/TienCustomizableHotbar_Bar.lua`: the bar, menus, keys.
  - Created at `OnGameStart` for player 0 only (split screen players have their own vanilla hotbars; keys are player 0
    only like vanilla's). `OnTick` shows it while player 0 is alive and rebuilds when the slots change (version, player,
    slots table or count).
  - Per frame it draws from a cache (`Resolve` every 250 ms), never walking the inventory in render.
  - Slot look: held / worn = green, not carried = dim with the script icon, amber dot top right = another item of the
    type stands in, blue dot bottom right = custom action, key text top left, optional name below.
  - Reordering by drag (admin hotbar's code: threshold, capture, ghost, drop marker); off while locked.
  - Inventory drops: a slot's / the bar's `onMouseUp` with `ISMouseDrag.dragging` set and no press of its own takes the
    first dragged item carried by the player (onto a slot = replace its item, elsewhere = new slot), then ends the drag
    the way `ISInventoryPage`'s container buttons do (`draggingFocus:onMouseUp(0, 0)`, both fields nil).
  - Item picker (+, bar right-click > Add an item, slot > Change item): one submenu per container (Inventory, then each
    bag), items grouped by full type and sorted by name; a type with several items opens a list of each (ammo and
    condition shown for weapons and clothing) so the exact one can be picked. The inventory context menu adds "Add to
    Customizable Hotbar" (or a greyed "On the Customizable Hotbar (slot n)").
  - Keys: vanilla key bindings (section `[Customizable Hotbar]`, 20 binds `TCH Slot n`, key 0), the admin hotbar's
    pattern (see ZomboidFixesB42 CLAUDE.md: mod options would drop Shift/Ctrl/Alt). `OnKeyPressed` (on release, like
    vanilla's hotbar).
  - Settings file `Zomboid/Lua/TienCustomizableHotbar.ini`: `version`, `x`, `y`, `size` (1-4: 36/44/52/60 px + 4 per font
    size step), `labels`, `vertical`, `locked`.
- Translations: `shared/Translate/EN/IG_UI.json` (`IGUI_TienCustomizableHotbar_*`), `UI.json` (key binding labels).

## To verify in game

- Gun in a backpack: +, pick it; press: transfer bar, then equip; press again: unequip, then back into the backpack.
- Gun out, press the knife's slot: gun back into its bag, then knife out. Two-handed rifle → pistol and back.
- Equip the gun by hand from the bag (vanilla menu), then press its slot: it goes back to the bag (home remembered).
- Move the gun into the main inventory on purpose: after 15 s a press-press leaves it there.
- Two M16s: the assigned one is drawn; drop it: the other is used (amber dot); drop both: greyed, "You have no ...".
- Bag full or dropped while the gun is out: halo text, gun stays in the inventory.
- Clothing / backpack slot: wear, take off, back into the bag.
- Custom actions: whiskey > Drink > All from a bag; painkillers > Take Pills; flashlight > Turn on; "Equip Primary" on a
  bat toggles. The menu copy never flashes on screen.
- Drag from the inventory onto a slot and onto the bar; reorder by drag; lock; vertical; names; sizes; position kept.
- Key binds with and without Shift; a bind on 1 also fires the vanilla hotbar (documented).
- MP: slots and homes survive a reconnect (transmitModData); draws work on a server; the `Then` action never reaches the
  server. With ZomboidFixesB42's fast forward and TransferResync on.
- With TienActionableHotbar and Plysken Attachments Reborn loaded.
