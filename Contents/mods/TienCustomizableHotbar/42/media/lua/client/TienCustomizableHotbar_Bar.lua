require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TienCustomizableHotbar_Use"

local Mod = TienCustomizableHotbar

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local SCALES = { 0.75, 1, 1.25 }
local SIZE_KEYS = { "SizeSmall", "SizeNormal", "SizeLarge" }
local SLOT = 60
local SPACING = 10
local ICON = 32
local DRAG_THRESHOLD = 6
local CACHE_MS = 250
local TRACK_MS = 500
local PRUNE_MS = 60000
local MAX_SAME = 25
local BORDER = { r = 0.8, g = 0.8, b = 0.8, a = 0.8 }
local AMBER = { r = 1, g = 0.7, b = 0.2 }
local BLUE = { r = 0.45, g = 0.7, b = 1 }
local MARKER = { r = 0.35, g = 0.75, b = 0.35 }

local KEY_SECTION = "[Customizable Hotbar]"

local function defaultSettings()
    return { size = 2, labels = false, vertical = false, locked = false, gameLocked = false }
end

Mod.settings = Mod.settings or defaultSettings()

function Mod.LoadSettings()
    local s = defaultSettings()
    local reader = getFileReader(Mod.FILE, false)
    if reader then
        local line = reader:readLine()
        while line do
            local key, value = string.match(line, "^(%a+)=(.*)$")
            if key == "x" or key == "y" or key == "gameX" or key == "gameY" then
                s[key] = tonumber(value)
            elseif key == "size" then
                local n = tonumber(value)
                if n and SCALES[n] then
                    s.size = n
                end
            elseif key == "labels" or key == "vertical" or key == "locked" or key == "gameLocked" then
                s[key] = value == "true"
            end
            line = reader:readLine()
        end
        reader:close()
    end
    Mod.settings = s
end

local function writeNumber(writer, key, value)
    if value then
        writer:write(key .. "=" .. string.format("%d", math.floor(value)) .. "\n")
    end
end

function Mod.SaveSettings()
    local writer = getFileWriter(Mod.FILE, true, false)
    if not writer then
        return
    end
    local s = Mod.settings
    writer:write("version=" .. string.format("%d", Mod.VERSION) .. "\n")
    writeNumber(writer, "x", s.x)
    writeNumber(writer, "y", s.y)
    writeNumber(writer, "size", s.size)
    writer:write("labels=" .. tostring(s.labels == true) .. "\n")
    writer:write("vertical=" .. tostring(s.vertical == true) .. "\n")
    writer:write("locked=" .. tostring(s.locked == true) .. "\n")
    writeNumber(writer, "gameX", s.gameX)
    writeNumber(writer, "gameY", s.gameY)
    writer:write("gameLocked=" .. tostring(s.gameLocked == true) .. "\n")
    writer:close()
end

local function circle()
    return getTexture("media/ui/circle.png")
end

local function equippedIcon()
    return getTexture("media/ui/icon.png")
end

local function truncate(text, width, font)
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= width then
        return text
    end
    local cut = text
    while #cut > 1 and tm:MeasureStringX(font, cut .. "..") > width do
        cut = string.sub(cut, 1, #cut - 1)
    end
    return cut .. ".."
end

local function indexOf(player, slot)
    for i, other in ipairs(Mod.Slots(player)) do
        if other == slot then
            return i
        end
    end
    return nil
end

local function endInventoryDrag()
    if ISMouseDrag.draggingFocus then
        ISMouseDrag.draggingFocus:onMouseUp(0, 0)
        ISMouseDrag.draggingFocus = nil
    end
    ISMouseDrag.dragging = nil
end

local function draggedCarriedItem(player)
    local dragging = ISMouseDrag.dragging
    if not player or type(dragging) ~= "table" then
        return nil
    end
    for _, item in ipairs(ISInventoryPane.getActualItems(dragging)) do
        if Mod.IsOnPlayer(player, item) then
            return item
        end
    end
    return nil
end

local function itemLabel(item)
    local name = item:getDisplayName()
    local extra = {}
    if instanceof(item, "HandWeapon") and item:getMaxAmmo() > 0 then
        table.insert(extra, string.format("%d/%d", item:getCurrentAmmoCount(), item:getMaxAmmo()))
    end
    if (instanceof(item, "HandWeapon") or item:IsClothing()) and item:getConditionMax() > 0 then
        table.insert(extra, string.format("%d%%", math.floor(item:getCondition() * 100 / item:getConditionMax() + 0.5)))
    end
    if #extra > 0 then
        name = name .. " (" .. table.concat(extra, ", ") .. ")"
    end
    return name
end

local function drawIcon(element, slot, item, cx, cy, scale, maxSize, alpha)
    local tex = item and item:getTexture() or nil
    if tex then
        local w = math.min(tex:getWidth() * scale, maxSize)
        local h = math.min(tex:getHeight() * scale, maxSize)
        element:drawTextureScaled(tex, cx - w / 2, cy - h / 2, w, h, alpha, 1, 1, 1)
        return
    end
    local size = math.min(ICON * scale, maxSize)
    if item then
        element:drawItemIcon(item, cx - size / 2, cy - size / 2, alpha, size, size)
        return
    end
    local script = Mod.ScriptItem(slot.type)
    if script then
        element:drawScriptItemIcon(script, cx - size / 2, cy - size / 2, alpha, size, size)
    end
end

local Bar = ISPanel:derive("TienCustomizableHotbarBar")
local SlotButton = ISButton:derive("TienCustomizableHotbarSlot")
local DragGhost = ISPanel:derive("TienCustomizableHotbarGhost")
Mod.Bar = Bar

function SlotButton:new(x, y, width, height, bar, slot, index)
    local o = ISButton.new(self, x, y, width, height, "", bar, Bar.onSlotClick)
    o.bar = bar
    o.slot = slot
    o.index = index
    o.displayBackground = false
    return o
end

function SlotButton:isDropTarget()
    return ISMouseDrag.dragging ~= nil and not self.pressed and not self.bar.dragging and self:isMouseOver()
end

function SlotButton:prerender()
    local w, h = self.width, self.height
    if self.bar.dragging == self then
        return
    end
    self:drawRectBorderStatic(0, 0, w, h, BORDER.a, BORDER.r, BORDER.g, BORDER.b)
    if self:isMouseOver() then
        local r, g, b = 1, 1, 1
        if self:isDropTarget() and not draggedCarriedItem(getSpecificPlayer(0)) then
            r, g, b = 1, 0, 0
        end
        self:drawRect(0, 0, w, h, 0.2, r, g, b)
    end
end

function SlotButton:render()
    if self.bar.dragging == self then
        return
    end
    local bar = self.bar
    local scale = bar.scale
    local cell = bar.cell
    local player = getSpecificPlayer(0)
    local dropped = self:isDropTarget() and draggedCarriedItem(player) or nil

    if not self.slot and not dropped then
        self:drawTextCentre("+", self.width / 2, (cell - FONT_HGT_MEDIUM) / 2, 1, 1, 1, 0.6, UIFont.Medium)
        return
    end

    local entry = self.slot and bar.cache[self.slot] or {}
    local item = dropped or entry.item
    local alpha = item and 1 or 0.25
    drawIcon(self, self.slot, item, self.width / 2, cell / 2, scale, cell - 4, alpha)
    if dropped or not self.slot then
        return
    end

    if item and player and Mod.IsHeldOrWorn(player, item) then
        local tex = equippedIcon()
        if tex then
            local tw, th = tex:getWidth() * scale, tex:getHeight() * scale
            self:drawTextureScaled(tex, self.width - tw - 5 * scale, cell - th - 5 * scale, tw, th, 1, 1, 1, 1)
        end
    end
    local dotTex = circle()
    local dot = math.max(5, math.floor(8 * scale))
    if dotTex and item and not entry.exact then
        self:drawTextureScaled(dotTex, self.width - dot - 3, 3, dot, dot, 1, AMBER.r, AMBER.g, AMBER.b)
    end
    if dotTex and self.slot.action then
        self:drawTextureScaled(dotTex, 3, cell - dot - 3, dot, dot, 1, BLUE.r, BLUE.g, BLUE.b)
    end
    self:drawText(self.keyText or string.format("%d", self.index), 3, 1, 1, 1, 1, 1, UIFont.Small)
    if Mod.settings.labels then
        local name = item and item:getDisplayName() or Mod.SlotName(self.slot)
        self:drawTextCentre(truncate(name, self.width - 4, UIFont.Small), self.width / 2, cell, 1, 1, 1, math.max(alpha, 0.5), UIFont.Small)
    end
end

function DragGhost:new(button)
    local o = ISPanel:new(getMouseX(), getMouseY(), button.width, button.height)
    setmetatable(o, self)
    self.__index = self
    o.button = button
    o.background = false
    return o
end

function DragGhost:prerender()
    self:setX(getMouseX() - self.width / 2)
    self:setY(getMouseY() - self.height / 2)
    self:drawRectStatic(0, 0, self.width, self.height, 0.5, 0, 0, 0)
    self:drawRectBorderStatic(0, 0, self.width, self.height, BORDER.a, BORDER.r, BORDER.g, BORDER.b)
    local bar = self.button.bar
    local entry = bar.cache[self.button.slot] or {}
    drawIcon(self, self.button.slot, entry.item, self.width / 2, bar.cell / 2, bar.scale, bar.cell - 4, 0.9)
end

function SlotButton:onMouseDown(x, y)
    ISButton.onMouseDown(self, x, y)
    if self.slot then
        self.dragFrom = { x = getMouseX(), y = getMouseY() }
    end
end

function SlotButton:checkDrag()
    if not self.pressed or not self.dragFrom or self.bar.dragging or Mod.settings.locked then
        return
    end
    local moved = math.abs(getMouseX() - self.dragFrom.x) + math.abs(getMouseY() - self.dragFrom.y)
    if moved < DRAG_THRESHOLD then
        return
    end
    self.bar.dragging = self
    self:setCapture(true)
    local ghost = DragGhost:new(self)
    ghost:initialise()
    ghost:addToUIManager()
    ghost:setAlwaysOnTop(true)
    ghost:setWantMouseEvents(false)
    self.ghost = ghost
end

function SlotButton:onMouseMove(dx, dy)
    ISButton.onMouseMove(self, dx, dy)
    self:checkDrag()
end

function SlotButton:onMouseMoveOutside(dx, dy)
    ISButton.onMouseMoveOutside(self, dx, dy)
    self:checkDrag()
end

function SlotButton:endDrag()
    self:setCapture(false)
    self.pressed = false
    self.dragFrom = nil
    if self.ghost then
        self.ghost:removeFromUIManager()
        self.ghost = nil
    end
    local bar = self.bar
    bar.dragging = nil
    local target = bar:dropIndex()
    local player = getSpecificPlayer(0)
    if target and player then
        local from = indexOf(player, self.slot)
        if from then
            Mod.MoveSlot(player, from, target)
        end
    end
end

function SlotButton:onMouseUp(x, y)
    if self.bar.dragging == self then
        return self:endDrag()
    end
    self.dragFrom = nil
    if ISMouseDrag.dragging and not self.pressed then
        self.bar:dropItems(self.slot)
        return true
    end
    return ISButton.onMouseUp(self, x, y)
end

function SlotButton:onMouseUpOutside(x, y)
    if self.bar.dragging == self then
        return self:endDrag()
    end
    self.dragFrom = nil
    return ISButton.onMouseUpOutside(self, x, y)
end

function SlotButton:onRightMouseUp(x, y)
    if self.slot then
        self.bar:showSlotMenu(self.slot)
    else
        self.bar:showBarMenu()
    end
    return true
end

function Bar:new()
    local o = ISPanel:new(0, 0, 100, 50)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = not Mod.settings.locked
    o.buttons = {}
    o.cache = {}
    o.scale = 1
    o.cell = SLOT
    o.builtVersion = -1
    o.lastCache = 0
    o.lastTrack = 0
    o.lastPrune = 0
    o.lastKeys = 0
    return o
end

function Bar:rebuild()
    for _, button in ipairs(self.buttons) do
        self:removeChild(button)
    end
    self.buttons = {}

    local player = getSpecificPlayer(0)
    local slots = player and Mod.Slots(player) or {}
    local s = Mod.settings
    self.scale = SCALES[s.size] or 1
    self.cell = math.floor(SLOT * self.scale + 0.5)
    self.spacing = math.floor(SPACING * self.scale + 0.5)
    local slotWidth = self.cell
    local slotHeight = self.cell + (s.labels and (FONT_HGT_SMALL + 2) or 0)
    local edge = self.spacing + 1

    local pos = edge
    for i = 1, #slots + 1 do
        local slot = slots[i]
        local x, y = pos, edge
        if s.vertical then
            x, y = edge, pos
        end
        local button = SlotButton:new(x, y, slotWidth, slotHeight, self, slot, slot and i or nil)
        button:initialise()
        button:instantiate()
        self:addChild(button)
        table.insert(self.buttons, button)
        pos = pos + (s.vertical and slotHeight or slotWidth) + self.spacing
    end
    local length = pos - self.spacing + edge
    if s.vertical then
        self:setWidth(slotWidth + edge * 2)
        self:setHeight(length)
    else
        self:setWidth(length)
        self:setHeight(slotHeight + edge * 2)
    end
    self.moveWithMouse = not s.locked
    self.builtVersion = Mod.version
    self.builtPlayer = player
    self.builtSlots = player and Mod.Data(player).slots or nil
    self:updateKeyTexts()
    self:refreshCache(true)
    self:clampToScreen()
end

function Bar:isStale(player)
    if self.builtVersion ~= Mod.version or self.builtPlayer ~= player then
        return true
    end
    local slots = Mod.Slots(player)
    return self.builtSlots ~= Mod.Data(player).slots or #self.buttons ~= #slots + 1
end

function Bar:refreshCache(force)
    local now = getTimestampMs()
    if not force and now - self.lastCache < CACHE_MS then
        return
    end
    self.lastCache = now
    self.cache = {}
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    for _, button in ipairs(self.buttons) do
        if button.slot then
            local item, exact = Mod.Resolve(player, button.slot)
            self.cache[button.slot] = { item = item, exact = exact }
        end
    end
end

function Bar:track()
    local now = getTimestampMs()
    if now - self.lastTrack < TRACK_MS then
        return
    end
    self.lastTrack = now
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    local changed = false
    for _, entry in pairs(self.cache) do
        if entry.item and Mod.Track(player, entry.item, now) then
            changed = true
        end
    end
    if now - self.lastPrune >= PRUNE_MS then
        self.lastPrune = now
        if Mod.PruneHomes(player) then
            changed = true
        end
    end
    if changed then
        Mod.Transmit(player)
    end
end

function Bar:slotKeyName(index)
    return "TCH Slot " .. string.format("%d", index)
end

function Bar:updateKeyTexts()
    for _, button in ipairs(self.buttons) do
        button.keyText = nil
        if button.index and button.index <= Mod.KEY_SLOTS then
            button.keyText = Mod.SlotKeyText(button.index)
        end
    end
end

function Bar:defaultPosition()
    local core = getCore()
    self:setX(math.floor(core:getScreenWidth() / 2 - self.width / 2))
    self:setY(math.floor(core:getScreenHeight() - self.height - 100))
end

function Bar:clampToScreen()
    local core = getCore()
    local x = math.max(0, math.min(self:getX(), core:getScreenWidth() - self.width))
    local y = math.max(FONT_HGT_SMALL, math.min(self:getY(), core:getScreenHeight() - self.height))
    if x ~= self:getX() then
        self:setX(x)
    end
    if y ~= self:getY() then
        self:setY(y)
    end
end

function Bar:rememberPosition()
    self:clampToScreen()
    local s = Mod.settings
    if s.x ~= self:getX() or s.y ~= self:getY() then
        s.x, s.y = self:getX(), self:getY()
        Mod.SaveSettings()
    end
end

function Bar:onSlotClick(button)
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    if not button.slot then
        self:showAddMenu()
        return
    end
    Mod.Use(player, button.slot)
end

function Bar:dropIndex()
    local mx, my = getMouseX() - self:getAbsoluteX(), getMouseY() - self:getAbsoluteY()
    local margin = self.cell
    if mx < -margin or my < -margin or mx > self.width + margin or my > self.height + margin then
        return nil
    end
    local vertical = Mod.settings.vertical
    local along = vertical and my or mx
    local count = 0
    for _, button in ipairs(self.buttons) do
        if button.index then
            count = count + 1
            local middle = vertical and (button:getY() + button:getHeight() / 2) or (button:getX() + button:getWidth() / 2)
            if along < middle then
                return button.index
            end
        end
    end
    return count + 1
end

function Bar:drawDropMarker()
    local target = self:dropIndex()
    if not target then
        return
    end
    local vertical = Mod.settings.vertical
    local position
    for _, button in ipairs(self.buttons) do
        if button.index == target then
            position = vertical and button:getY() or button:getX()
        end
    end
    if not position then
        local last = self.buttons[#self.buttons - 1]
        if not last then
            return
        end
        position = vertical and (last:getBottom() + self.spacing) or (last:getRight() + self.spacing)
    end
    local half = math.floor(self.spacing / 2) + 1
    if vertical then
        self:drawRect(2, position - half - 1, self.width - 4, 2, 1, MARKER.r, MARKER.g, MARKER.b)
    else
        self:drawRect(position - half - 1, 2, 2, self.height - 4, 1, MARKER.r, MARKER.g, MARKER.b)
    end
end

function Mod.DrawGrip(element, edge, vertical)
    local tex = circle()
    if not tex then
        return
    end
    local across = math.floor((edge - 3) / 2)
    for i = 0, 2 do
        if vertical then
            element:drawTextureScaled(tex, element.width / 2 - 7 + i * 5, across, 3, 3, 0.8, 0.7, 0.7, 0.7)
        else
            element:drawTextureScaled(tex, across, element.height / 2 - 7 + i * 5, 3, 3, 0.8, 0.7, 0.7, 0.7)
        end
    end
end

function Bar:prerender()
    self:drawRectStatic(0, 0, self.width, self.height, 0.5, 0, 0, 0)
    self:drawRectBorderStatic(0, 0, self.width, self.height, BORDER.a, BORDER.r, BORDER.g, BORDER.b)
    if not Mod.settings.locked then
        Mod.DrawGrip(self, (self.spacing or SPACING) + 1, Mod.settings.vertical)
    end
    if self.dragging then
        self:drawDropMarker()
    end
end

function Bar:hoverLines(button)
    if not button.slot then
        return { Mod.txt("AddLabel") }
    end
    local player = getSpecificPlayer(0)
    local entry = self.cache[button.slot] or {}
    local item = entry.item
    local lines = {}
    if ISMouseDrag.dragging and not button.pressed then
        local dropped = draggedCarriedItem(player)
        return { dropped and dropped:getDisplayName() or Mod.txt("NotOnYou") }
    end
    if not item or not player then
        table.insert(lines, Mod.txt("TipNotCarried", Mod.SlotName(button.slot)))
    else
        local where
        if player:isHandItem(item) then
            where = Mod.txt("TipHands")
        elseif player:isEquippedClothing(item) then
            where = Mod.txt("TipWorn")
        else
            local bag = Mod.BagOf(player, item)
            where = bag and Mod.txt("TipIn", Mod.BagName(bag)) or Mod.txt("TipInventory")
        end
        if not entry.exact then
            where = where .. " " .. Mod.txt("TipOther")
        end
        table.insert(lines, where)
        local home = Mod.HomeOf(player, item)
        if home and Mod.BagOf(player, item) ~= home then
            table.insert(lines, Mod.txt("TipHome", Mod.BagName(home)))
        end
    end
    if button.slot.action then
        table.insert(lines, Mod.txt("TipAction", Mod.Label(button.slot.action)))
    end
    return lines
end

function Bar:hoveredButton()
    if self.dragging then
        return nil
    end
    for _, button in ipairs(self.buttons) do
        if button:isMouseOver() then
            return button
        end
    end
    return nil
end

function Bar:render()
    local button = self:hoveredButton()
    if not button then
        return
    end
    local context = getPlayerContextMenu(0)
    if context and context:isAnyVisible() then
        return
    end
    local lines = self:hoverLines(button)
    local tm = getTextManager()
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, tm:MeasureStringX(UIFont.Small, line))
    end
    local height = #lines * FONT_HGT_SMALL
    local x, y
    if Mod.settings.vertical then
        x = -width - 6
        y = button:getY() + (button:getHeight() - height) / 2
        if self:getAbsoluteX() + x < 0 then
            x = self.width + 2
        end
    else
        x = button:getX() + (button:getWidth() - width) / 2
        y = -height
    end
    self:drawRect(x - 2, y, width + 4, height, 0.6, 0, 0, 0)
    for i, line in ipairs(lines) do
        local lineWidth = tm:MeasureStringX(UIFont.Small, line)
        self:drawText(line, x + (width - lineWidth) / 2, y + (i - 1) * FONT_HGT_SMALL, 1, 1, 1, 1, UIFont.Small)
    end
end

function Bar:updateItemTooltip()
    local button = self:hoveredButton()
    local item = nil
    if button and button.slot and not ISMouseDrag.dragging then
        item = (self.cache[button.slot] or {}).item
    end
    local context = getPlayerContextMenu(0)
    if item and not (context and context:isAnyVisible()) then
        if self.toolRender then
            self.toolRender:setItem(item)
            self.toolRender:bringToTop()
        else
            self.toolRender = ISToolTipInv:new(item)
            self.toolRender:initialise()
            self.toolRender:addToUIManager()
            self.toolRender:setOwner(self)
            self.toolRender:setCharacter(getSpecificPlayer(0))
        end
        self.toolRender:setVisible(true)
    elseif self.toolRender then
        self.toolRender:setVisible(false)
    end
end

function Bar:update()
    ISPanel.update(self)
    self:refreshCache(false)
    self:track()
    self:updateItemTooltip()
    local now = getTimestampMs()
    if now - self.lastKeys >= 1000 then
        self.lastKeys = now
        self:updateKeyTexts()
    end
end

function Bar:close()
    if self.toolRender then
        self.toolRender:removeFromUIManager()
        self.toolRender = nil
    end
    self:removeFromUIManager()
end

function Bar:onMouseUp(x, y)
    if ISMouseDrag.dragging and not self.moving then
        self:dropItems(nil)
        return true
    end
    ISPanel.onMouseUp(self, x, y)
    self:rememberPosition()
end

function Bar:onMouseUpOutside(x, y)
    ISPanel.onMouseUpOutside(self, x, y)
    self:rememberPosition()
end

function Bar:onRightMouseUp(x, y)
    self:showBarMenu()
    return true
end

function Bar:dropItems(slot)
    local player = getSpecificPlayer(0)
    if not player or type(ISMouseDrag.dragging) ~= "table" then
        return
    end
    local chosen = draggedCarriedItem(player)
    endInventoryDrag()
    if not chosen then
        HaloTextHelper.addBadText(player, Mod.txt("NotOnYou"))
        return
    end
    local index = slot and indexOf(player, slot)
    if index then
        Mod.SetSlotItem(player, index, chosen)
    else
        Mod.AddSlot(player, chosen)
    end
end

function Mod.DefaultActionText(slot, item)
    local wearable = false
    if item then
        wearable = Mod.IsWearable(item)
    else
        local script = Mod.ScriptItem(slot.type)
        wearable = script ~= nil and script:isItemType(ItemType.CLOTHING)
    end
    return Mod.txt(wearable and "DefaultWear" or "DefaultEquip")
end

function Bar:fillItemPicker(context, onPick)
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    local inventory = player:getInventory()
    local groups = {}
    local byContainer = {}
    local function groupFor(container, holder)
        local group = byContainer[container]
        if not group then
            group = { title = holder and Mod.BagName(holder) or Mod.txt("Inventory"), holder = holder, items = {} }
            byContainer[container] = group
            table.insert(groups, group)
        end
        return group
    end
    groupFor(inventory, nil)
    Mod.EachItem(inventory, function(item, container, holder)
        table.insert(groupFor(container, holder).items, item)
        return false
    end)

    local any = false
    for _, group in ipairs(groups) do
        if #group.items > 0 then
            any = true
            local option = context:addOption(group.title, nil, nil)
            if group.holder then
                option.itemForTexture = group.holder
            end
            local sub = context:getNew(context)
            context:addSubMenu(option, sub)
            local byType, order, names = {}, {}, {}
            for _, item in ipairs(group.items) do
                local fullType = item:getFullType()
                if not byType[fullType] then
                    byType[fullType] = {}
                    names[fullType] = item:getDisplayName()
                    table.insert(order, fullType)
                end
                table.insert(byType[fullType], item)
            end
            table.sort(order, function(a, b)
                return names[a] < names[b]
            end)
            for _, fullType in ipairs(order) do
                local list = byType[fullType]
                if #list == 1 then
                    local itemOption = sub:addOption(itemLabel(list[1]), self, onPick, list[1])
                    itemOption.itemForTexture = list[1]
                else
                    local typeOption = sub:addOption(names[fullType] .. " (" .. string.format("%d", #list) .. ")", nil, nil)
                    typeOption.itemForTexture = list[1]
                    local each = sub:getNew(sub)
                    sub:addSubMenu(typeOption, each)
                    for k = 1, math.min(#list, MAX_SAME) do
                        local itemOption = each:addOption(itemLabel(list[k]), self, onPick, list[k])
                        itemOption.itemForTexture = list[k]
                    end
                end
            end
        end
    end
    if not any then
        local option = context:addOption(Mod.txt("NothingToAdd"), nil, nil)
        option.notAvailable = true
    end
end

function Bar:onPickNew(item)
    local player = getSpecificPlayer(0)
    if player and item then
        Mod.AddSlot(player, item)
    end
end

function Bar:showAddMenu()
    local context = ISContextMenu.get(0, getMouseX(), getMouseY())
    local hint = context:addOption(Mod.txt("DragHint"), nil, nil)
    hint.notAvailable = true
    self:fillItemPicker(context, Bar.onPickNew)
end

function Bar:onPickAction(slot, leaf)
    local player = getSpecificPlayer(0)
    local index = player and indexOf(player, slot)
    if not index then
        return
    end
    local rec = leaf and Mod.RecordFromLeaf(leaf) or nil
    Mod.SetSlotAction(player, index, rec)
    local text = rec and Mod.Label(rec) or Mod.DefaultActionText(slot, Mod.Resolve(player, slot))
    HaloTextHelper.addText(player, Mod.txt("Set", string.format("%d", index), text))
end

function Bar:mirror(menu, nodes, slot, checked)
    for _, node in ipairs(nodes) do
        local option
        if node.children then
            option = menu:addOption(node.name, nil, nil)
            local sub = menu:getNew(menu)
            menu:addSubMenu(option, sub)
            self:mirror(sub, node.children, slot, checked)
        else
            option = menu:addOption(node.name, self, Bar.onPickAction, slot, node)
        end
        if node == checked then
            menu:setOptionChecked(option, true)
        else
            option.iconTexture = node.iconTexture
            option.itemForTexture = node.itemForTexture
        end
    end
end

function Bar:onChangeItem(slot, item)
    local player = getSpecificPlayer(0)
    local index = player and indexOf(player, slot)
    if index and item then
        Mod.SetSlotItem(player, index, item)
    end
end

function Bar:onRemoveSlot(slot)
    local player = getSpecificPlayer(0)
    local index = player and indexOf(player, slot)
    if index then
        Mod.RemoveSlot(player, index)
    end
end

function Bar:showSlotMenu(slot)
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    local item = Mod.Resolve(player, slot)
    local leaves, nodes = {}, {}
    if item then
        leaves, nodes = Mod.BuildLeaves(0, item)
    end
    local context = ISContextMenu.get(0, getMouseX(), getMouseY())

    local actionOption = context:addOption(Mod.txt("Action"), nil, nil)
    local actionTip = ISInventoryPaneContextMenu.addToolTip()
    actionTip.description = Mod.txt("ActionTooltip")
    actionOption.toolTip = actionTip
    local actions = context:getNew(context)
    context:addSubMenu(actionOption, actions)
    local default = actions:addOption(Mod.DefaultActionText(slot, item), self, Bar.onPickAction, slot, nil)
    if not slot.action then
        actions:setOptionChecked(default, true)
    end
    if item then
        self:mirror(actions, nodes, slot, Mod.Match(leaves, slot.action))
    else
        local missing = actions:addOption(Mod.txt("CarryToPick", Mod.SlotName(slot)), nil, nil)
        missing.notAvailable = true
    end

    local changeOption = context:addOption(Mod.txt("ChangeItem"), nil, nil)
    local change = context:getNew(context)
    context:addSubMenu(changeOption, change)
    self:fillItemPicker(change, function(bar, picked)
        bar:onChangeItem(slot, picked)
    end)

    context:addOption(Mod.txt("Remove"), self, Bar.onRemoveSlot, slot)
    self:addSettings(context)
end

function Bar:showBarMenu()
    local context = ISContextMenu.get(0, getMouseX(), getMouseY())
    local addOption = context:addOption(Mod.txt("AddItem"), nil, nil)
    local add = context:getNew(context)
    context:addSubMenu(addOption, add)
    self:fillItemPicker(add, Bar.onPickNew)
    self:addSettings(context)
end

function Bar:setSetting(key, value)
    Mod.settings[key] = value
    Mod.SaveSettings()
    self:rebuild()
end

function Bar:resetPosition()
    self:defaultPosition()
    self:rememberPosition()
end

function Bar:addSettings(context)
    local s = Mod.settings
    local option = context:addOption(Mod.txt("Settings"), nil, nil)
    local sub = context:getNew(context)
    context:addSubMenu(option, sub)

    local sizeOption = sub:addOption(Mod.txt("Size"), nil, nil)
    local sizes = sub:getNew(sub)
    sub:addSubMenu(sizeOption, sizes)
    for i, key in ipairs(SIZE_KEYS) do
        local sizeChoice = sizes:addOption(Mod.txt(key), self, Bar.setSetting, "size", i)
        if s.size == i then
            sizes:setOptionChecked(sizeChoice, true)
        end
    end

    local labels = sub:addOption(Mod.txt("ShowNames"), self, Bar.setSetting, "labels", not s.labels)
    if s.labels then
        sub:setOptionChecked(labels, true)
    end
    local vertical = sub:addOption(Mod.txt("Vertical"), self, Bar.setSetting, "vertical", not s.vertical)
    if s.vertical then
        sub:setOptionChecked(vertical, true)
    end
    local locked = sub:addOption(Mod.txt("Lock"), self, Bar.setSetting, "locked", not s.locked)
    if s.locked then
        sub:setOptionChecked(locked, true)
    end
    sub:addOption(Mod.txt("ResetPosition"), self, Bar.resetPosition)
    if Mod.GameHotbar then
        Mod.GameHotbar.AddOptions(sub)
    end
end

local function addKeyBindings()
    if not keyBinding then
        return
    end
    for _, bind in ipairs(keyBinding) do
        if bind.value == KEY_SECTION then
            return
        end
    end
    table.insert(keyBinding, { value = KEY_SECTION })
    for i = 1, Mod.KEY_SLOTS do
        table.insert(keyBinding, { value = Bar:slotKeyName(i), key = 0 })
    end
end

addKeyBindings()

local function bindOf(name)
    for _, bind in ipairs(MainOptions and MainOptions.keys or {}) do
        if bind.value == name then
            return bind
        end
    end
    return nil
end

function Mod.SlotKeyText(index)
    local name = Bar:slotKeyName(index)
    local key = getCore():getKey(name)
    if not key or key == 0 then
        return nil
    end
    local bind = bindOf(name) or {}
    local prefix = (bind.ctrl and "C+" or "") .. (bind.alt and "A+" or "") .. (bind.shift and "S+" or "")
    return prefix .. getKeyName(key)
end

local function onKeyPressed(key)
    if not key or key == 0 or not Mod.bar or JoypadState.players[1] then
        return
    end
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    local core = getCore()
    for i = 1, Mod.KEY_SLOTS do
        if core:isKey(Bar:slotKeyName(i), key) then
            local slot = Mod.Slots(player)[i]
            if slot then
                Mod.Use(player, slot)
            end
            return
        end
    end
end

local function onFillInventoryMenu(playerNum, context, items)
    if Mod.silent or playerNum ~= 0 or not Mod.bar then
        return
    end
    local player = getSpecificPlayer(0)
    if not player or type(items) ~= "table" then
        return
    end
    local actual = ISInventoryPane.getActualItems(items)
    local item = actual[1]
    if not item or not Mod.IsOnPlayer(player, item) then
        return
    end
    local existing = Mod.FindSlotWithItem(player, item)
    if existing then
        local option = context:addOption(Mod.txt("OnHotbar", string.format("%d", existing)), nil, nil)
        option.notAvailable = true
        return
    end
    context:addOption(Mod.txt("AddToHotbar"), Mod.bar, Bar.onPickNew, item)
end

local function onTick()
    local bar = Mod.bar
    if not bar then
        return
    end
    local player = getSpecificPlayer(0)
    local show = player ~= nil and not player:isDead()
    if bar:getIsVisible() ~= show then
        bar:setVisible(show)
        if not show and bar.toolRender then
            bar.toolRender:setVisible(false)
        end
    end
    if show and bar:isStale(player) then
        bar:rebuild()
    end
end

local function onGameStart()
    if MainOptions and MainOptions.loadKeys and not bindOf(Bar:slotKeyName(1)) then
        MainOptions.loadKeys()
    end
    Mod.LoadSettings()
    if Mod.bar then
        Mod.bar:close()
    end
    local bar = Bar:new()
    bar:initialise()
    bar:addToUIManager()
    Mod.bar = bar
    bar:rebuild()
    local s = Mod.settings
    if s.x and s.y then
        bar:setX(s.x)
        bar:setY(s.y)
        bar:clampToScreen()
    else
        bar:defaultPosition()
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryMenu)
