# Tien's Customizable Hotbar

A second hotbar where any item you carry can go, even one deep in a bag. Press its slot and the item comes out of the
bag into your hands; press again and it goes back where it came from. The game's own hotbar gets the same handle and
buttons, so you can move it anywhere and put its slots in the order you like.

## The Customizable Hotbar

### Putting items on it

- **Any item you carry**, from your inventory or any bag you carry. No belt or holster needed.
- Three ways to add one: click the **+** slot and pick it, drag it from the inventory window onto the bar (onto a slot
  to replace that slot's item), or right-click it in the inventory > **Add to Customizable Hotbar**.
- Up to 40 slots.
- Right-click a slot for **Action**, **Change item** and **Remove from hotbar**.

### Using a slot

- **Out of the bag, into your hands.** Click the slot or press its key: the item is taken out of its bag at the game's
  usual transfer speed (a rifle in a hiking bag is slower to draw than a knife on your belt, on purpose) and equipped.
  Press again: it is put away and goes back into the bag it came from. If that bag is gone or full, it stays in your
  inventory.
- **Switching.** With the gun out, press the knife's slot: the gun goes back into its bag first, then the knife comes
  out.
- **Clothing and bags** are worn and taken off instead of held.
- **Your item first.** A slot remembers the exact item you put on it. If that one isn't on you, another item of the same
  kind is used (a small amber dot shows it); with none on you the slot is faded out.
- **Any action from the item's menu.** Right-click a slot > **Action** and pick from a copy of the item's own menu
  (Drink, Take Pills, Turn On, Wear...). A blue dot marks a slot with its own action. When that action can't be done and
  the item is in your hands, the slot puts it away instead.
- Like the game's hotbar, a slot does nothing while you are busy with another action, attacking or paused.

### Keys

- Options > Key Bindings > **Tien's Customizable Hotbar**: 20 slot keys, none bound at first. Shift, Ctrl and Alt
  combinations work.
- Clicking a slot always works. (Binding 1-0 also fires the game's own hotbar.)

### Looks

- **Like the game's hotbar**: same frame, slot size, slot numbers (or the bound key), hover labels, item tooltip and
  equipped marker.
- Hovering a slot says where the item is ("In: Big Hiking Bag", "In your hands") and which bag it goes back to.
- **Settings** (the gear button, or right-click the bar): size (Small, Normal, Large), item names under the slots,
  vertical, reset position.

## Both hotbars

Each bar has a **dotted handle** at its left end and **four small buttons** at its right end (at the top and bottom
when the Customizable Hotbar is vertical). Hover a button to see what it does.

- **Move the bar**: drag it by the dotted handle. It stays where you put it.
- **Reorder the slots**: drag a slot onto another place on the same bar. A green line or frame shows where it will go.
  A click without dragging still uses the slot.
- **Lock**: the bar and its slots stay where they are; the handle disappears while locked.
- **Swap / insert**: what dropping a dragged slot does. Insert (the default) slides it in between and shifts the others;
  swap trades places with the slot it is dropped on. Each bar has its own setting.
- **Eye**:
  - on the Customizable Hotbar: hides it. Its slot keys keep working.
  - on the game's hotbar: shows or hides the Customizable Hotbar.
- **Gear**: the bar's settings. For the game's hotbar: put it back at the bottom of the screen.
- **Snap together**: drag one bar close to the other and it snaps flush against it (above, below or beside, lined up by
  the edges or the centre). It stays docked: it keeps its place when either bar grows or shrinks and follows when you
  drag the other one. Drag it away by its own handle to undock it; hold Shift while dragging to move without snapping.

## The game's hotbar

- **Reordered slots stay that way**: the number keys follow the new order, and the order and the items on it are kept
  when you log out and back in, in single player and on a server. Belts and bags put on or taken off add and remove
  their slots as usual.
- Everything else works as before: click or press a number to use a slot, drop an item from the inventory onto a slot
  to attach it, right-click a slot for its menu.
- This replaces **Reorder The Hotbar**: don't use the two together.

## Where it is saved

- **The Customizable Hotbar's slots** (which item, which action) and which bag each item goes back to are saved with the
  character (on the server in multiplayer).
- **The game's hotbar slot order** is saved with the character, where the game keeps it.
- **The bars' look, positions, docking, locks, swap / insert choices and whether the Customizable Hotbar is hidden** are
  saved on your computer (`Zomboid/Lua/TienCustomizableHotbar.ini`) and follow you to every save and server.

## Compatibility

Build 42 only. It uses the game's own timed actions (transfer, equip, unequip, wear), so it works in multiplayer like
the vanilla hotbar. In multiplayer the server needs it in its mod list like any other mod. Don't use it with Reorder
The Hotbar.
