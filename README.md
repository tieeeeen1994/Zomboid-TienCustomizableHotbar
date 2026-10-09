# Tien's Customizable Hotbar

A second hotbar where any item you carry can go, even one deep in a bag. Press its slot and the item comes out of the
bag into your hands; press again and it goes back where it came from.

- **Any item you carry.** Click **+** and pick an item from your inventory or any bag you carry, or drag an item from the
  inventory window onto the bar (onto a slot to replace it). The inventory's right-click menu also has **Add to
  Customizable Hotbar**. No belt or holster needed.
- **Out of the bag, into your hands.** The slot takes the item out of its bag at the game's usual transfer speed (a rifle
  in a hiking bag is slower to draw than a knife on your belt, on purpose) and equips it. Press again: it is put away
  and goes back into the bag it came from. If that bag is gone or full, it stays in your inventory.
- **Switching.** With the gun out, press the knife's slot: the gun goes back into its bag first, then the knife comes out.
- **Clothing and bags** are worn and taken off instead of held.
- **Looks like the game's hotbar.** Same frame, slot size, slot numbers, hover labels, item tooltip and equipped
  marker. Hovering a slot says where the item is ("In: Big Hiking Bag", "In your hands") and which bag it goes back to.
- **Your item first.** A slot remembers the exact item you put on it. If that one isn't on you, another item of the same
  kind is used (a small amber dot shows it); with none on you the slot is faded out.
- **Any action from the item's menu.** Right-click a slot > **Action** and pick from a copy of the item's own menu
  (Drink, Take Pills, Turn On, Wear...). A blue dot marks a slot with its own action. When that action can't be done and
  the item is in your hands, the slot puts it away instead.
- **Your keys.** Options > Key Bindings > **Tien's Customizable Hotbar**: 20 slot keys, none bound at first. Shift, Ctrl
  and Alt combinations work. Clicking a slot always works. (Binding 1-0 also fires the game's own hotbar.)
- **Your layout.** Drag slots to reorder them and the bar by the dotted handle at its left end; right-click the bar for size, item names,
  vertical, lock and reset position.
- **The game's hotbar moves too.** Drag the game's own hotbar anywhere on the screen by the same dotted handle; it stays there. Right-click its
  frame to lock it or put it back at the bottom.
- **The two bars snap together.** Drag one bar close to the other and it snaps flush against it (above, below or beside,
  lined up by the edges or the centre). It stays docked there: it keeps its place when either bar grows or shrinks and
  follows when you drag the other one. Drag it away by its own handle to undock it; hold Shift while dragging to move
  without snapping.

Like the game's hotbar, a slot does nothing while you are busy with another action, attacking or paused.

## Where it is saved

- **Slots** (which item, which action) and which bag each item goes back to are saved with the character (on the server
  in multiplayer).
- **The bars' look and positions** are saved on your computer (`Zomboid/Lua/TienCustomizableHotbar.ini`).

Build 42 only. It uses the game's own timed actions (transfer, equip, unequip, wear), so it works in multiplayer like
the vanilla hotbar. In multiplayer the server needs it in its mod list like any other mod.
