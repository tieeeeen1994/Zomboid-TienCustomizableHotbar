require "TimedActions/ISBaseTimedAction"
require "TienCustomizableHotbar_Core"

local Mod = TienCustomizableHotbar

local Then = ISBaseTimedAction:derive("TienCustomizableHotbarThen")
Mod.ThenAction = Then

function Then:isValid()
    return true
end

function Then:start()
end

function Then:update()
end

function Then:perform()
    local ok, err = pcall(self.fn)
    if not ok then
        Mod.log(err)
    end
    ISBaseTimedAction.perform(self)
end

function Then:new(character, fn)
    local o = ISBaseTimedAction.new(self, character)
    o.fn = fn
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun = false
    o.stopOnAim = false
    o.useProgressBar = false
    return o
end

function Mod.CanUseNow(player)
    if not player or player:isDead() then
        return false
    end
    if isGamePaused() or player:isAttacking() then
        return false
    end
    local radial = getPlayerRadialMenu(player:getPlayerNum())
    if radial and radial:isReallyVisible() then
        return false
    end
    local queue = ISTimedActionQueue.queues[player]
    if queue and #queue.queue > 0 then
        return false
    end
    return true
end

local function isLitLight(item)
    return item:getType() == "CandleLit" or item:getType() == "Lantern_HurricaneLit" or item:hasTag(ItemTag.LIT_LANTERN)
end

function Mod.QueueReturn(player, item)
    local bag = Mod.HomeOf(player, item)
    if not bag then
        return false
    end
    local dest = bag:getInventory()
    if dest:contains(item) then
        return true
    end
    if not dest:isItemAllowed(item) or not dest:hasRoomFor(player, item) then
        HaloTextHelper.addBadText(player, Mod.txt("NoRoom", Mod.BagName(bag)))
        return false
    end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, player:getInventory(), dest)
    if action.setAllowMissingItems then
        action:setAllowMissingItems(true)
    end
    ISTimedActionQueue.add(action)
    return true
end

function Mod.Unequip(player, item)
    if player:isEquippedClothing(item) or isLitLight(item) then
        ISInventoryPaneContextMenu.unequipItem(item, player:getPlayerNum())
    elseif player:isHandItem(item) then
        ISTimedActionQueue.add(ISUnequipAction:new(player, item, 20))
    end
end

function Mod.PutAway(player, item)
    Mod.Unequip(player, item)
    Mod.QueueReturn(player, item)
end

local function addOnce(list, item)
    if not item then
        return
    end
    for _, other in ipairs(list) do
        if other == item then
            return
        end
    end
    table.insert(list, item)
end

function Mod.Equip(player, item)
    local playerNum = player:getPlayerNum()
    local primaryItem = player:getPrimaryHandItem()
    local secondaryItem = player:getSecondaryHandItem()
    local twoHands = item:isTwoHandWeapon()
    local primary = twoHands or item:IsWeapon()
    if not primary and secondaryItem and not primaryItem then
        primary = true
    end

    if primaryItem and isForceDropHeavyItem and isForceDropHeavyItem(primaryItem) then
        ISInventoryPaneContextMenu.dropItem(primaryItem, playerNum)
        if secondaryItem == primaryItem then
            secondaryItem = nil
        end
        primaryItem = nil
    end

    local displaced = {}
    if twoHands then
        addOnce(displaced, primaryItem)
        addOnce(displaced, secondaryItem)
    elseif primary then
        addOnce(displaced, primaryItem)
        if secondaryItem and (secondaryItem == primaryItem or secondaryItem:isRequiresEquippedBothHands()) then
            addOnce(displaced, secondaryItem)
        end
    else
        addOnce(displaced, secondaryItem)
        if primaryItem and primaryItem == secondaryItem then
            addOnce(displaced, primaryItem)
        end
    end

    local handled = {}
    for _, held in ipairs(displaced) do
        if held ~= item and Mod.HomeOf(player, held) then
            Mod.PutAway(player, held)
            table.insert(handled, held)
        end
    end
    local before = {}
    local function keep(held)
        for _, other in ipairs(handled) do
            if other == held then
                return
            end
        end
        addOnce(before, held)
    end
    keep(primaryItem)
    keep(secondaryItem)

    if Mod.RememberHome(player, item) then
        Mod.Transmit(player)
    end
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(ISEquipWeaponAction:new(player, item, 20, primary, twoHands))
    ISTimedActionQueue.add(Then:new(player, function()
        for _, held in ipairs(before) do
            if held ~= item and not Mod.IsHeldOrWorn(player, held) and player:getInventory():contains(held) then
                Mod.QueueReturn(player, held)
            end
        end
    end))
end

function Mod.Wear(player, item)
    if Mod.RememberHome(player, item) then
        Mod.Transmit(player)
    end
    ISInventoryPaneContextMenu.onWearItems({ item }, player:getPlayerNum())
end

function Mod.DefaultUse(player, item)
    if Mod.IsHeldOrWorn(player, item) then
        Mod.PutAway(player, item)
    elseif Mod.IsWearable(item) then
        Mod.Wear(player, item)
    else
        Mod.Equip(player, item)
    end
end

function Mod.Use(player, slot)
    if not slot or not Mod.CanUseNow(player) then
        return
    end
    local item = Mod.Resolve(player, slot)
    if not item then
        HaloTextHelper.addBadText(player, Mod.txt("NotCarried", Mod.SlotName(slot)))
        return
    end
    if not slot.action then
        Mod.DefaultUse(player, item)
        return
    end
    local playerNum = player:getPlayerNum()
    local leaf = Mod.Match(Mod.BuildLeaves(playerNum, item), slot.action)
    if leaf and leaf.available then
        if Mod.RememberHome(player, item) then
            Mod.Transmit(player)
        end
        Mod.RunLeaf(playerNum, leaf)
        return
    end
    if Mod.IsHeldOrWorn(player, item) then
        Mod.PutAway(player, item)
        return
    end
    HaloTextHelper.addBadText(player, Mod.txt("CantNow", Mod.Label(slot.action)))
end
