TienCustomizableHotbar = TienCustomizableHotbar or {}

local Mod = TienCustomizableHotbar

Mod.MODDATA = "TienCustomizableHotbar"
Mod.FILE = "TienCustomizableHotbar.ini"
Mod.VERSION = 1
Mod.MAX_SLOTS = 40
Mod.KEY_SLOTS = 20
Mod.MENU_DEPTH = 6
Mod.TREE_DEPTH = 6
Mod.PARAMS = 10
Mod.MAX_HOMES = 60
Mod.LOOSE_FORGET_MS = 15000

Mod.silent = false
Mod.version = 0
Mod.loose = {}

local FIRST_TABLES = { "ISInventoryPaneContextMenu", "ISHotbar", "ISWorldObjectContextMenu", "ISTimedActionQueue" }
local functionNames = {}

function Mod.log(message)
    print("[TienCustomizableHotbar] " .. tostring(message))
end

function Mod.txt(key, ...)
    return getText("IGUI_TienCustomizableHotbar_" .. key, ...)
end

local function idKey(id)
    return string.format("%d", id)
end

function Mod.Data(player)
    local modData = player:getModData()
    local data = modData[Mod.MODDATA]
    if type(data) ~= "table" then
        data = {}
        modData[Mod.MODDATA] = data
    end
    if type(data.slots) ~= "table" then
        data.slots = {}
    end
    if type(data.homes) ~= "table" then
        data.homes = {}
    end
    return data
end

function Mod.Slots(player)
    local slots = Mod.Data(player).slots
    local clean = {}
    local broken = false
    for i = 1, #slots do
        local slot = slots[i]
        if type(slot) == "table" and type(slot.type) == "string" then
            table.insert(clean, slot)
        else
            broken = true
        end
    end
    if broken then
        Mod.Data(player).slots = clean
    end
    return Mod.Data(player).slots
end

function Mod.Transmit(player)
    if isClient() then
        player:transmitModData()
    end
end

function Mod.Changed(player)
    Mod.version = Mod.version + 1
    Mod.Transmit(player)
end

function Mod.ScriptItem(fullType)
    return getScriptManager():getItem(fullType)
end

function Mod.SlotName(slot)
    local script = Mod.ScriptItem(slot.type)
    if script then
        return script:getDisplayName()
    end
    return slot.type
end

function Mod.NewSlot(item)
    return { id = item:getID(), type = item:getFullType() }
end

function Mod.FindSlotWithItem(player, item)
    local id = item:getID()
    for i, slot in ipairs(Mod.Slots(player)) do
        if slot.id == id then
            return i
        end
    end
    return nil
end

function Mod.AddSlot(player, item, index)
    local slots = Mod.Slots(player)
    if #slots >= Mod.MAX_SLOTS then
        HaloTextHelper.addBadText(player, Mod.txt("Full"))
        return nil
    end
    local existing = Mod.FindSlotWithItem(player, item)
    if existing then
        HaloTextHelper.addBadText(player, Mod.txt("AlreadyOn", string.format("%d", existing)))
        return existing
    end
    index = math.max(1, math.min(index or (#slots + 1), #slots + 1))
    table.insert(slots, index, Mod.NewSlot(item))
    Mod.RememberHome(player, item)
    Mod.Changed(player)
    return index
end

function Mod.SetSlotItem(player, index, item)
    local slots = Mod.Slots(player)
    local slot = slots[index]
    if not slot then
        return
    end
    local existing = Mod.FindSlotWithItem(player, item)
    if existing and existing ~= index then
        HaloTextHelper.addBadText(player, Mod.txt("AlreadyOn", string.format("%d", existing)))
        return
    end
    if slot.type ~= item:getFullType() then
        slot.action = nil
    end
    slot.id = item:getID()
    slot.type = item:getFullType()
    Mod.RememberHome(player, item)
    Mod.Changed(player)
end

function Mod.RemoveSlot(player, index)
    local slots = Mod.Slots(player)
    if slots[index] then
        table.remove(slots, index)
        Mod.Changed(player)
    end
end

function Mod.MoveSlot(player, from, insertBefore)
    local slots = Mod.Slots(player)
    local slot = slots[from]
    if not slot then
        return
    end
    local target = insertBefore
    if target > from then
        target = target - 1
    end
    target = math.max(1, math.min(target, #slots))
    if target == from then
        return
    end
    table.remove(slots, from)
    table.insert(slots, target, slot)
    Mod.Changed(player)
end

function Mod.SwapSlots(player, a, b)
    local slots = Mod.Slots(player)
    if a == b or not slots[a] or not slots[b] then
        return
    end
    slots[a], slots[b] = slots[b], slots[a]
    Mod.Changed(player)
end

function Mod.SetSlotAction(player, index, rec)
    local slot = Mod.Slots(player)[index]
    if not slot then
        return
    end
    slot.action = Mod.CopyRecord(rec)
    Mod.Changed(player)
end

function Mod.EachItem(container, fn, depth, holder)
    depth = depth or 1
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if fn(item, container, holder, depth) then
            return true
        end
        if depth < Mod.TREE_DEPTH and instanceof(item, "InventoryContainer") then
            local inner = item:getInventory()
            if inner and Mod.EachItem(inner, fn, depth + 1, item) then
                return true
            end
        end
    end
    return false
end

function Mod.IsOnPlayer(player, item)
    return item ~= nil and item:getOutermostContainer() == player:getInventory()
end

function Mod.IsHeldOrWorn(player, item)
    return player:isHandItem(item) or player:isEquippedClothing(item)
end

local function exactIds(player, except)
    local ids = {}
    for _, slot in ipairs(Mod.Slots(player)) do
        if slot ~= except and slot.id then
            ids[slot.id] = true
        end
    end
    return ids
end

function Mod.Resolve(player, slot)
    local inventory = player:getInventory()
    if slot.id then
        local exact = inventory:getItemWithIDRecursiv(slot.id)
        if exact and exact:getFullType() == slot.type then
            return exact, true
        end
    end
    local others = exactIds(player, slot)
    local best, bestScore = nil, -1
    Mod.EachItem(inventory, function(item, container)
        if item:getFullType() == slot.type then
            local score = 1
            if player:isHandItem(item) then
                score = 4
            elseif player:isEquippedClothing(item) then
                score = 3
            elseif container == inventory then
                score = 2
            end
            if not item:isBroken() then
                score = score + 10
            end
            if not others[item:getID()] then
                score = score + 20
            end
            if score > bestScore then
                best, bestScore = item, score
            end
        end
        return false
    end)
    return best, false
end

function Mod.BagOf(player, item)
    local container = item:getContainer()
    if not container or container == player:getInventory() then
        return nil
    end
    local bag = container:getContainingItem()
    if bag and instanceof(bag, "InventoryContainer") and Mod.IsOnPlayer(player, bag) then
        return bag
    end
    return nil
end

function Mod.RememberHome(player, item)
    if not item or Mod.IsHeldOrWorn(player, item) then
        return false
    end
    local homes = Mod.Data(player).homes
    local key = idKey(item:getID())
    local bag = Mod.BagOf(player, item)
    if bag then
        Mod.loose[key] = nil
        if homes[key] ~= bag:getID() then
            homes[key] = bag:getID()
            return true
        end
    end
    return false
end

function Mod.Track(player, item, now)
    if not item then
        return false
    end
    local key = idKey(item:getID())
    if Mod.IsHeldOrWorn(player, item) then
        Mod.loose[key] = nil
        return false
    end
    if Mod.BagOf(player, item) then
        return Mod.RememberHome(player, item)
    end
    local homes = Mod.Data(player).homes
    if homes[key] == nil or item:getContainer() ~= player:getInventory() then
        Mod.loose[key] = nil
        return false
    end
    local since = Mod.loose[key]
    if not since then
        Mod.loose[key] = now
        return false
    end
    if now - since >= Mod.LOOSE_FORGET_MS then
        Mod.loose[key] = nil
        homes[key] = nil
        return true
    end
    return false
end

function Mod.PruneHomes(player)
    local homes = Mod.Data(player).homes
    local count = 0
    for _ in pairs(homes) do
        count = count + 1
    end
    if count <= Mod.MAX_HOMES then
        return false
    end
    local inventory = player:getInventory()
    local stale = {}
    for key in pairs(homes) do
        local id = tonumber(key)
        if not id or not inventory:getItemWithIDRecursiv(id) then
            table.insert(stale, key)
        end
    end
    for _, key in ipairs(stale) do
        homes[key] = nil
    end
    return #stale > 0
end

function Mod.HomeOf(player, item)
    local id = Mod.Data(player).homes[idKey(item:getID())]
    if not id then
        return nil
    end
    local bag = player:getInventory():getItemWithIDRecursiv(id)
    if not bag or bag == item or not instanceof(bag, "InventoryContainer") or not bag:getInventory() then
        return nil
    end
    if instanceof(item, "InventoryContainer") and item:getInventory() and item:getInventory():containsRecursive(bag) then
        return nil
    end
    return bag
end

function Mod.BagName(bag)
    return bag:getName() or bag:getDisplayName()
end

function Mod.IsWearable(item)
    if item:IsClothing() then
        return true
    end
    return instanceof(item, "InventoryContainer") and item:canBeEquipped() ~= nil
end

local function clean(text)
    return (string.gsub(text, "[\r\n]", " "))
end

function Mod.EncodeParam(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" then
        return string.sub(kind, 1, 1) .. ":" .. tostring(value)
    end
    if kind == "string" and not string.find(value, "[\r\n]") then
        return "s:" .. value
    end
    return nil
end

function Mod.CopyRecord(rec)
    if type(rec) ~= "table" or type(rec.path) ~= "table" then
        return nil
    end
    local out = { path = {}, params = {} }
    if type(rec.fn) == "string" and rec.fn ~= "" then
        out.fn = rec.fn
    end
    for i = 1, #rec.path do
        out.path[i] = tostring(rec.path[i])
    end
    if type(rec.params) == "table" then
        for index, code in pairs(rec.params) do
            local n = tonumber(index)
            if n and type(code) == "string" then
                out.params[n] = code
            end
        end
    end
    if #out.path == 0 then
        return nil
    end
    return out
end

function Mod.Label(rec)
    return table.concat(rec.path, " > ")
end

local function keyOf(tbl, fn)
    for key, value in pairs(tbl) do
        if value == fn and type(key) == "string" then
            return key
        end
    end
    return nil
end

local function searchGlobals(fn)
    local found = nil
    pcall(function()
        for name, value in pairs(_G) do
            if type(name) == "string" then
                if value == fn then
                    found = name
                    return
                end
                if type(value) == "table" then
                    local key = keyOf(value, fn)
                    if key then
                        found = name .. "." .. key
                        return
                    end
                end
            end
        end
    end)
    return found
end

function Mod.FunctionName(fn)
    if fn == nil then
        return nil
    end
    local cached = functionNames[fn]
    if cached ~= nil then
        return cached or nil
    end
    local name = nil
    for _, tableName in ipairs(FIRST_TABLES) do
        local tbl = _G[tableName]
        if type(tbl) == "table" then
            local key = keyOf(tbl, fn)
            if key then
                name = tableName .. "." .. key
                break
            end
        end
    end
    if not name then
        name = searchGlobals(fn)
    end
    functionNames[fn] = name or false
    return name
end

function Mod.ResolveFunction(name)
    if not name then
        return nil
    end
    local tableName, key = string.match(name, "^([^%.]+)%.(.+)$")
    if not tableName then
        return _G[name]
    end
    local tbl = _G[tableName]
    if type(tbl) ~= "table" then
        return nil
    end
    return tbl[key]
end

local function snapshotMenu(menu, path, depth, leaves, nodes, skip)
    for _, option in ipairs(menu.options) do
        local name = option.name
        if type(name) == "string" and name ~= "" and not (skip and skip[name]) then
            local optionPath = {}
            for i, part in ipairs(path) do
                optionPath[i] = part
            end
            table.insert(optionPath, clean(name))
            if option.subOption then
                local sub = menu:getSubMenu(option.subOption)
                if sub and depth < Mod.MENU_DEPTH then
                    local children = {}
                    snapshotMenu(sub, optionPath, depth + 1, leaves, children, nil)
                    if #children > 0 then
                        table.insert(nodes, {
                            name = name,
                            children = children,
                            iconTexture = option.iconTexture,
                            itemForTexture = option.itemForTexture,
                        })
                    end
                end
            elseif option.onSelect then
                local params = {}
                for i = 1, Mod.PARAMS do
                    params[i] = option["param" .. i]
                end
                local leaf = {
                    name = name,
                    path = optionPath,
                    onSelect = option.onSelect,
                    target = option.target,
                    params = params,
                    available = not option.notAvailable and not option.isDisabled,
                    iconTexture = option.iconTexture,
                    itemForTexture = option.itemForTexture,
                }
                table.insert(leaves, leaf)
                table.insert(nodes, leaf)
            end
        end
    end
end

function Mod.Snapshot(menu, skip)
    local leaves, nodes = {}, {}
    snapshotMenu(menu, {}, 1, leaves, nodes, skip)
    return leaves, nodes
end

function Mod.RecordFromLeaf(leaf)
    local rec = { path = {}, params = {}, fn = Mod.FunctionName(leaf.onSelect) }
    for i, part in ipairs(leaf.path) do
        rec.path[i] = part
    end
    for i = 1, Mod.PARAMS do
        rec.params[i] = Mod.EncodeParam(leaf.params[i])
    end
    return rec
end

local function samePath(leaf, rec)
    if #leaf.path ~= #rec.path then
        return false
    end
    for i = 1, #rec.path do
        if leaf.path[i] ~= rec.path[i] then
            return false
        end
    end
    return true
end

local function sameParams(leaf, rec)
    for index, code in pairs(rec.params) do
        if Mod.EncodeParam(leaf.params[index]) ~= code then
            return false
        end
    end
    return true
end

function Mod.Match(leaves, rec)
    if not rec then
        return nil
    end
    local fn = Mod.ResolveFunction(rec.fn)
    for _, leaf in ipairs(leaves) do
        if samePath(leaf, rec) and (not fn or leaf.onSelect == fn) then
            return leaf
        end
    end
    if not fn then
        return nil
    end
    local lastName = rec.path[#rec.path]
    local count, only, byParams, byName = 0, nil, nil, nil
    for _, leaf in ipairs(leaves) do
        if leaf.onSelect == fn then
            count = count + 1
            only = leaf
            local params = sameParams(leaf, rec)
            local named = leaf.path[#leaf.path] == lastName
            if params and named then
                return leaf
            end
            if params and not byParams then
                byParams = leaf
            end
            if named and not byName then
                byName = leaf
            end
        end
    end
    if byParams then
        return byParams
    end
    if byName then
        return byName
    end
    if count == 1 then
        return only
    end
    return nil
end

function Mod.Skip()
    return {
        [Mod.txt("AddToHotbar")] = true,
        [getText("IGUI_TienActionableHotbar_ChangeDefault")] = true,
    }
end

function Mod.BuildLeaves(playerNum, item)
    Mod.silent = true
    local ok, err = pcall(ISInventoryPaneContextMenu.createMenu, playerNum, true, { item }, getMouseX(), getMouseY())
    Mod.silent = false
    local context = getPlayerContextMenu(playerNum)
    local leaves, nodes = {}, {}
    if ok and context then
        leaves, nodes = Mod.Snapshot(context, Mod.Skip())
    end
    if context then
        context:closeAll()
    end
    if not ok then
        Mod.log(err)
    end
    return leaves, nodes
end

function Mod.RunLeaf(playerNum, leaf)
    local p = leaf.params
    ISContextMenu.globalPlayerContext = playerNum
    leaf.onSelect(leaf.target, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10])
end
