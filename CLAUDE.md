# Tien's Customizable Hotbar

Project Zomboid B42 mod (client only): a second hotbar whose slots hold any item the player carries, bags included.
A slot takes its item out of its bag and equips it (or wears it), and puts it back into that bag on the next press; or
it runs any action from the item's own context menu. The live code is under `Contents/mods/TienCustomizableHotbar/42/`.
General engine findings go in `~/Zomboid/Workshop/ZomboidFixesB42/CLAUDE.md` ("Hotbar attachments and carry weight",
"UI building blocks learned for the hotbar"); this file only holds the reasoning behind this mod.

The Lua source has no comments on purpose. Non-obvious reasoning lives here; update this file when it changes.

## Status

First implementation 2026-10-09. The user has run it in game (dragging the game's hotbar works); the rest of "To verify"
has not been confirmed. Lua checked with luaparser (syntax and free globals).

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
  - Looks like vanilla's `ISHotbar:render` (the user asked, 2026-10-09): panel 0.5 black + 0.8 grey borders
    (`drawRectStatic` / `drawRectBorderStatic`), 60 px slots with 10 px margins and gaps at Normal size (Small 0.75,
    Large 1.25 scale everything), slot number top left (the bound key instead when there is one), hover = white 0.2
    tint (red while dragging an item that is not carried), item icon from `item:getTexture()` at its own size, the
    equipped marker `media/ui/icon.png` bottom right for held / worn items, faded (0.25) script icon when not carried,
    a dark label box above the hovered slot (drawn by the bar's `render`, outside its bounds, like vanilla) and the
    item's `ISToolTipInv` like vanilla's `update`. Vanilla's label names the attachment point; ours says where the
    item is (bag / hands / worn / not on you, "(not the one you assigned)"), where it goes back to, and a custom action.
    Kept from before because vanilla has no equivalent: the "+" slot, the amber (stand-in item) and blue (custom
    action) dots, item names under the slots, vertical. Only the handle drags (user's choice, 2026-10-09): the admin
    hotbar's grip (three 3 px dots, `Mod.DrawGrip`) in the left margin (top margin when vertical), shown while unlocked; `Bar:onMouseDown` lets
    `ISPanel.onMouseDown` start a move only inside that margin (`isOnHandle`), and swallows presses elsewhere on the
    frame. The game's hotbar gets the same grip and handle in its left margin while unlocked
    (`ISHotbar:render` wrapped, after vanilla's drawing).
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
  - Settings file `Zomboid/Lua/TienCustomizableHotbar.ini`: `version`, `x`, `y`, `size` (1-3: scale 0.75 / 1 / 1.25),
    `labels`, `vertical`, `locked`, and for the game's hotbar `gameX` (its centre), `gameY` (its top), `gameLocked`.
- `client/TienCustomizableHotbar_GameHotbar.lua`: the vanilla hotbar made draggable (user's request, 2026-10-09).
  - Vanilla's `ISHotbar:update` calls `setSizeAndPosition()` every update, which centres it at the bottom of the
    player's screen. Wrapped (at `OnGameStart`, outermost) to move it afterwards: while dragging to the drag position,
    else to the saved one, clamped to player 0's screen (`getPlayerScreen*`), keeping `FONT_HGT_SMALL` above it for the
    hover label. The centre x is saved, so it stays balanced when worn items add or remove slots.
  - Drag = a press on the handle (its left margin, `isOnHandle`; vanilla has no `onMouseDown`; ISPanelJoypad's does
    nothing with `moveWithMouse` off) that moves 6 px with the button held; a press there that does not move is
    swallowed too, since vanilla's `onMouseUp` would use the nearest slot (slot 1). Past 6 px `setCapture(true)`,
    and the release ends the drag instead of reaching vanilla's `onMouseUp` (which would use the slot or drop a dragged item). Presses and clicks on the slots are untouched.
    `endDrag` must place from the drag **before** clearing `tchDrag`: `Place` without a drag goes to the saved
    position, so clearing first put the bar back on the old spot and saved that (every drag after the first snapped
    back, 2026-10-09). Player 0 only (vanilla hides the other players' hotbars).
  - Vanilla's `getSlotIndexAt` maps every point inside the bar, margins included, to the nearest slot, so a right-click
    on the frame is told apart with `isOnSlot` (slot rects from `margins`, `slotWidth`, `slotPad`, `slotHeight`); there
    it opens Lock / Put back at the bottom. They used to be listed in this bar's Hotbar settings too, under its own
    Lock / Reset: the user took them for this bar's and found the game's hotbar changing (2026-10-09), so each bar's
    menu now only holds its own options.
- `client/TienCustomizableHotbar_Dock.lua`: snapping and docking the two bars together (user's choice of "snap and
  dock", flush, 2026-10-09).
  - A dock = `{ side, align, offset }`: the docked bar sits `above` / `below` / `left` / `right` of the other, lined
    up by `start` / `end` / `center` of the cross axis, or `offset` px from the other's start when no alignment was
    within reach. Saved flat in the ini as `customDock/customAlign/customOffset` (our bar docked to the game's) and
    `gameDock/gameAlign/gameOffset`; at most one is set (docking one clears the other), so there is never a cycle.
  - `Snap(x, y, w, h, other)` during a drag: each side counts when the cross axes overlap and the edges are within
    16 px (`SNAP`); the alignment within 16 px wins, else an offset; lowest total distance wins. Shift skips it. A bar
    whose partner is docked to it never snaps (the partner follows it, so they could not meet anyway).
  - Following happens every rendered frame (the user saw the docked bar trail behind, 2026-10-09): our bar in
    `Bar:prerender` (`dragUpdate` while dragged, else `followDock`, then `clampToScreen`), the game's hotbar in a
    wrapped `ISHotbar:prerender` → `Game.Place` (also still from vanilla's per-update `setSizeAndPosition`).
    Positions set in a prerender draw that same frame. The follower first brings its leader up to date
    (`followDock` calls `Game.Place(hotbar)`, `Game.Place` calls `Mod.bar:dragUpdate()` while our bar is dragged),
    so the draw order of the two top-level elements does not cost a frame; no recursion, since only one is docked.
    Both work from the other bar's live rect, so width changes (slots added,
    a belt worn) and the other bar's drags carry over. A drag of the docked bar undocks it once it moves (our bar: 3
    px; the game's: the 6 px drag threshold). Reset position clears the bar's dock.
  - Our bar no longer uses ISPanel's `moveWithMouse` (relative `dx` moves would drift from the mouse after a snap):
    `onMouseDown` on the handle keeps an anchor (mouse + bar position), `dragUpdate` places it at anchor + mouse delta
    and snaps, `endBarDrag` stores the dock and saves; a release seen as `isMouseButtonDown(0) == false` also ends it.
- Translations: `shared/Translate/EN/IG_UI.json` (`IGUI_TienCustomizableHotbar_*`), `UI.json` (key binding labels).

- `scripts/make_art.py` (`python3 scripts/make_art.py`, Pillow): icon (128), poster and `preview.png` (512). Pack
  reader, sticker, slot copied from TienActionableHotbar's script. Poster (third try, 2026-10-09): a small UI scene
  like TienCustomizableLeftSidebar's art: a vanilla-looking inventory window (title bar, rows of item icons with grey
  bars for names; water bottle, the assault rifle row lit gold, hammer, whiskey) with the green big hiking bag as a
  sticker on its top-right corner, a gold curved arrow (`bez`, `curve`, `head`) from the rifle row down into the lit
  slot 2 of the hotbar below (dotted grip, hunting knife, rifle, beta blockers, "+" slot). No key cap. Icon: one lit
  slot holding the rifle, the bag sticker on its empty bottom-right corner. The user approved this one (2026-10-09).
  Earlier tries the user called ugly: the
  bag drawn huge with the rifle half out of its top; then Actionable Hotbar's layout (rifle rising from slot 1 with a
  bag badge). Lesson: item icons are 32 px, so blown up 7-8x they look crude; keep them at 1-2x inside UI mock-ups
  and let the layout tell the story. `fill_holes` keeps a sticker's white outline off see-through holes.

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
- Docking: snap our bar above / below / beside the game's and the game's to ours; each alignment; drag the partner
  (the docked one follows); add a slot / put on a belt (stays aligned); drag the docked one away (undocks); Shift
  drag; restart (dock kept); vanilla's hover label over our bar when docked flush above it.
- Side by side with the game's hotbar at Normal size: same frame, slot size, number, hover tint, label, tooltip, marker.
- Game's hotbar: drag it, click its slots after (no slot used by the drag), drop an inventory item on it, put on a
  belt (slot count changes, stays centred where it was), right-click its frame; lock; put back; restart.
- Key binds with and without Shift; a bind on 1 also fires the vanilla hotbar (documented).
- MP: slots and homes survive a reconnect (transmitModData); draws work on a server; the `Then` action never reaches the
  server. With ZomboidFixesB42's fast forward and TransferResync on.
- With TienActionableHotbar and Plysken Attachments Reborn loaded.
