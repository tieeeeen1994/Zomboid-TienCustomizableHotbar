require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TienCustomizableHotbar_Use"
require "TienCustomizableHotbar_Dock"
require "TienCustomizableHotbar_Tools"

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
local BOOLEANS = { labels = true, vertical = true, locked = true, gameLocked = true, hidden = true, swap = true,
    gameSwap = true }

local function defaultSettings()
    return { size = 2, labels = false, vertical = false, locked = false, gameLocked = false, hidden = false,
        swap = false, gameSwap = false }
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
            elseif BOOLEANS[key] then
                s[key] = value == "true"
            elseif key == "customDock" or key == "customAlign" or key == "gameDock" or key == "gameAlign" then
                s[key] = value
            elseif key == "customOffset" or key == "gameOffset" then
                s[key] = tonumber(value)
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
    writer:write("hidden=" .. tostring(s.hidden == true) .. "\n")
    writer:write("swap=" .. tostring(s.swap == true) .. "\n")
    writeNumber(writer, "gameX", s.gameX)
    writeNumber(writer, "gameY", s.gameY)
    writer:write("gameLocked=" .. tostring(s.gameLocked == true) .. "\n")
    writer:write("gameSwap=" .. tostring(s.gameSwap == true) .. "\n")
    for _, prefix in ipairs({ "custom", "game" }) do
        local dock = Mod.Dock.Get(s, prefix)
        if dock then
            writer:write(prefix .. "Dock=" .. dock.side .. "\n")
            writer:write(prefix .. "Align=" .. dock.align .. "\n")
            writeNumber(writer, prefix .. "Offset", dock.offset)
        end
    end
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
    local stepCount = #Mod.Steps(self.slot)
    if stepCount > 0 then
        local x = self.slot.action and (dot + 5) or 3
        self:drawText("+" .. string.format("%d", stepCount), x, cell - FONT_HGT_SMALL - 1, 1, 1, 1, 0.9, UIFont.Small)
    end
    if self.keyText then
        self:drawText(self.keyText, 3, 1, 1, 1, 1, 1, UIFont.Small)
    end
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
    local player = getSpecificPlayer(0)
    local from = player and indexOf(player, self.slot)
    if not from then
        return
    end
    if Mod.settings.swap then
        local target = bar:swapIndex()
        if target then
            Mod.SwapSlots(player, from, target)
        end
    else
        local target = bar:dropIndex()
        if target then
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
    o.moveWithMouse = false
    o.buttons = {}
    o.cache = {}
    o.scale = 1
    o.cell = SLOT
    o.builtVersion = -1
    o.lastCache = 0
    o.lastTrack = 0
    o.lastPrune = 0
    o.lastKeys = 0
    o.lead = SPACING + 1
    o.icons = {
        {
            texture = function() return Mod.settings.locked and "lock" or "unlock" end,
            tip = function() return Mod.txt(Mod.settings.locked and "TipLocked" or "TipUnlocked") end,
            click = function() o:setSetting("locked", not Mod.settings.locked) end,
        },
        {
            texture = function() return Mod.settings.swap and "swap" or "insert" end,
            tip = function() return Mod.txt(Mod.settings.swap and "TipSwap" or "TipInsert") end,
            click = function() o:setSetting("swap", not Mod.settings.swap) end,
        },
        {
            texture = function() return "eye" end,
            tip = function() return Mod.txt("TipHide") end,
            click = function() Mod.SetHidden(true) end,
        },
        {
            texture = function() return "gear" end,
            tip = function() return Mod.txt("Settings") end,
            click = function() o:showSettingsMenu() end,
        },
    }
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
    local m = Mod.Tools.Metrics(self.scale)
    self.lead = edge + m.grip

    local pos = self.lead
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
    local cross = (s.vertical and slotWidth or slotHeight) + edge * 2
    local per, block = Mod.Tools.Block(m, #self.icons, cross)
    Mod.Tools.Layout(self.icons, m, s.vertical, pos, cross, per)
    local length = pos + block + m.margin + 1
    if s.vertical then
        self:setWidth(cross)
        self:setHeight(length)
    else
        self:setWidth(length)
        self:setHeight(cross)
    end
    self.moveWithMouse = false
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
            for _, step in ipairs(Mod.Steps(button.slot)) do
                local stepItem, stepExact = Mod.Resolve(player, step)
                self.cache[step] = { item = stepItem, exact = stepExact }
            end
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

function Bar:swapIndex()
    local mx, my = getMouseX() - self:getAbsoluteX(), getMouseY() - self:getAbsoluteY()
    local margin = self.cell
    if mx < -margin or my < -margin or mx > self.width + margin or my > self.height + margin then
        return nil
    end
    local vertical = Mod.settings.vertical
    local along = vertical and my or mx
    local last = nil
    for _, button in ipairs(self.buttons) do
        if button.index then
            local finish = vertical and button:getBottom() or button:getRight()
            if along < finish + self.spacing / 2 then
                return button.index
            end
            last = button.index
        end
    end
    return last
end

function Bar:drawSwapMarker()
    local target = self:swapIndex()
    for _, button in ipairs(self.buttons) do
        if target and button.index == target then
            local x, y, w, h = button:getX(), button:getY(), button:getWidth(), button:getHeight()
            self:drawRect(x, y, w, h, 0.25, MARKER.r, MARKER.g, MARKER.b)
            self:drawRectBorder(x - 2, y - 2, w + 4, h + 4, 1, MARKER.r, MARKER.g, MARKER.b)
            self:drawRectBorder(x - 1, y - 1, w + 2, h + 2, 1, MARKER.r, MARKER.g, MARKER.b)
        end
    end
end

function Bar:drawDropMarker()
    if Mod.settings.swap then
        return self:drawSwapMarker()
    end
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

function Bar:prerender()
    if not Mod.GameHotbarShown() then
        self:applyVisible(false)
        return
    end
    if self.moving then
        self:dragUpdate()
    else
        self:followDock()
    end
    self:drawRectStatic(0, 0, self.width, self.height, 0.5, 0, 0, 0)
    self:drawRectBorderStatic(0, 0, self.width, self.height, BORDER.a, BORDER.r, BORDER.g, BORDER.b)
    if not Mod.settings.locked then
        Mod.Tools.DrawGrip(self, self.lead, Mod.settings.vertical)
    end
    Mod.Tools.Draw(self, self.icons)
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
    for _, step in ipairs(Mod.Steps(button.slot)) do
        local stepItem = (self.cache[step] or {}).item
        local name = stepItem and stepItem:getDisplayName() or Mod.SlotName(step)
        if step.action then
            table.insert(lines, Mod.txt("TipStepAction", name, Mod.Label(step.action)))
        else
            table.insert(lines, Mod.txt("TipStep", name))
        end
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
    if not self.dragging and not self.moving then
        local icon = Mod.Tools.At(self.icons, self:getMouseX(), self:getMouseY())
        if icon then
            Mod.Tools.DrawTip(self, icon, Mod.settings.vertical)
            return
        end
    end
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
    self:followDock()
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

function Bar:isOnHandle(x, y)
    local lead = self.lead
    if Mod.settings.vertical then
        return y >= 0 and y < lead and x >= 0 and x < self.width
    end
    return x >= 0 and x < lead and y >= 0 and y < self.height
end

function Bar:followDock()
    if self.moving then
        return
    end
    local dock = Mod.Dock.Get(Mod.settings, "custom")
    local hotbar = getPlayerHotbar(0)
    if not dock or not hotbar then
        return
    end
    if Mod.GameHotbar then
        Mod.GameHotbar.Place(hotbar)
    end
    local x, y = Mod.Dock.Position(self.width, self.height, Mod.Dock.Rect(hotbar), dock)
    if x ~= self:getX() then
        self:setX(x)
    end
    if y ~= self:getY() then
        self:setY(y)
    end
    self:clampToScreen()
end

function Bar:onMouseDown(x, y)
    self.moving = false
    self.pressedIcon = Mod.Tools.At(self.icons, x, y)
    if self.pressedIcon or Mod.settings.locked or not self:isOnHandle(x, y) then
        return true
    end
    self.moving = true
    self.dragMoved = false
    self.pendingDock = nil
    self.dragAnchor = { mx = getMouseX(), my = getMouseY(), x = self:getX(), y = self:getY() }
    self:bringToTop()
    return true
end

function Bar:dragUpdate()
    local anchor = self.dragAnchor
    if not self.moving or not anchor then
        return
    end
    if not isMouseButtonDown(0) then
        self:endBarDrag()
        return
    end
    local x = anchor.x + getMouseX() - anchor.mx
    local y = anchor.y + getMouseY() - anchor.my
    if not self.dragMoved then
        if math.abs(x - anchor.x) + math.abs(y - anchor.y) < 3 then
            return
        end
        self.dragMoved = true
        Mod.Dock.Set(Mod.settings, "custom", nil)
    end
    local dock = nil
    local hotbar = getPlayerHotbar(0)
    if hotbar and hotbar:isVisible() and not Mod.Dock.Get(Mod.settings, "game") then
        x, y, dock = Mod.Dock.Snap(x, y, self.width, self.height, Mod.Dock.Rect(hotbar))
    end
    self.pendingDock = dock
    self:setX(x)
    self:setY(y)
end

function Bar:endBarDrag()
    if not self.moving then
        return
    end
    self.moving = false
    self.dragAnchor = nil
    if self.dragMoved then
        if self.pendingDock then
            Mod.Dock.Set(Mod.settings, "custom", self.pendingDock)
            Mod.Dock.Set(Mod.settings, "game", nil)
        end
        self:rememberPosition()
        Mod.SaveSettings()
    end
    self.dragMoved = false
    self.pendingDock = nil
end

function Bar:onMouseMove(dx, dy)
    ISPanel.onMouseMove(self, dx, dy)
    self:dragUpdate()
end

function Bar:onMouseMoveOutside(dx, dy)
    ISPanel.onMouseMoveOutside(self, dx, dy)
    self:dragUpdate()
end

function Bar:onMouseUp(x, y)
    local icon = self.pressedIcon
    self.pressedIcon = nil
    if ISMouseDrag.dragging and not self.moving then
        self:dropItems(nil)
        return true
    end
    if icon then
        if Mod.Tools.At(self.icons, x, y) == icon then
            Mod.Tools.Click(icon)
        end
        return true
    end
    self:endBarDrag()
    return true
end

function Bar:onMouseUpOutside(x, y)
    self.pressedIcon = nil
    self:endBarDrag()
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

function Bar:mirror(menu, nodes, pick, checked)
    for _, node in ipairs(nodes) do
        local option
        if node.children then
            option = menu:addOption(node.name, nil, nil)
            local sub = menu:getNew(menu)
            menu:addSubMenu(option, sub)
            self:mirror(sub, node.children, pick, checked)
        else
            option = menu:addOption(node.name, self, pick, node)
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

local function addTooltip(option, text)
    local tip = ISInventoryPaneContextMenu.addToolTip()
    tip.description = text
    option.toolTip = tip
end

local function menuEntry(player, entry)
    local item = Mod.Resolve(player, entry)
    local leaves, nodes = {}, {}
    if item then
        leaves, nodes = Mod.BuildLeaves(0, item)
    end
    return { entry = entry, item = item, leaves = leaves, nodes = nodes }
end

function Bar:addActionMenu(context, info, pick)
    local entry = info.entry
    local actionOption = context:addOption(Mod.txt("Action"), nil, nil)
    addTooltip(actionOption, Mod.txt("ActionTooltip"))
    local actions = context:getNew(context)
    context:addSubMenu(actionOption, actions)
    local default = actions:addOption(Mod.DefaultActionText(entry, info.item), self, pick, nil)
    if not entry.action then
        actions:setOptionChecked(default, true)
    end
    if info.item then
        self:mirror(actions, info.nodes, pick, Mod.Match(info.leaves, entry.action))
    else
        local missing = actions:addOption(Mod.txt("CarryToPick", Mod.SlotName(entry)), nil, nil)
        missing.notAvailable = true
    end
end

function Bar:addStepMenu(stepMenu, player, slot, info, index, count)
    local step = info.entry
    self:addActionMenu(stepMenu, info, function(_, node)
        Mod.SetStepAction(player, slot, step, node and Mod.RecordFromLeaf(node) or nil)
    end)
    local changeOption = stepMenu:addOption(Mod.txt("ChangeItem"), nil, nil)
    local change = stepMenu:getNew(stepMenu)
    stepMenu:addSubMenu(changeOption, change)
    self:fillItemPicker(change, function(_, picked)
        Mod.SetStepItem(player, slot, step, picked)
    end)
    local follow = stepMenu:addOption(Mod.txt("StepFollow"), player, Mod.SetStepAlone, slot, step, not step.alone)
    addTooltip(follow, Mod.txt("StepFollowTooltip"))
    if not step.alone then
        stepMenu:setOptionChecked(follow, true)
    end
    if step.action then
        follow.notAvailable = true
    end
    if index > 1 then
        stepMenu:addOption(Mod.txt("MoveEarlier"), player, Mod.MoveStep, slot, step, -1)
    end
    if index < count then
        stepMenu:addOption(Mod.txt("MoveLater"), player, Mod.MoveStep, slot, step, 1)
    end
    stepMenu:addOption(Mod.txt("RemoveStep"), player, Mod.RemoveStep, slot, step)
end

function Bar:addStepsMenu(context, player, slot, stepInfos)
    local stepsOption = context:addOption(Mod.txt("Steps"), nil, nil)
    addTooltip(stepsOption, Mod.txt("StepsTooltip"))
    local stepsMenu = context:getNew(context)
    context:addSubMenu(stepsOption, stepsMenu)
    local count = #stepInfos
    for i, info in ipairs(stepInfos) do
        local step = info.entry
        local name = info.item and info.item:getDisplayName() or Mod.SlotName(step)
        if step.action then
            name = name .. ": " .. Mod.Label(step.action)
        end
        local stepOption = stepsMenu:addOption(string.format("%d. ", i) .. name, nil, nil)
        if info.item then
            stepOption.itemForTexture = info.item
        end
        local stepMenu = stepsMenu:getNew(stepsMenu)
        stepsMenu:addSubMenu(stepOption, stepMenu)
        self:addStepMenu(stepMenu, player, slot, info, i, count)
    end
    local addOption = stepsMenu:addOption(Mod.txt("AddStep"), nil, nil)
    if count >= Mod.MAX_STEPS then
        addOption.notAvailable = true
        addTooltip(addOption, Mod.txt("StepsFull", string.format("%d", Mod.MAX_STEPS)))
        return
    end
    local add = stepsMenu:getNew(stepsMenu)
    stepsMenu:addSubMenu(addOption, add)
    self:fillItemPicker(add, function(_, picked)
        Mod.AddStep(player, slot, picked)
    end)
end

function Bar:showSlotMenu(slot)
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    local info = menuEntry(player, slot)
    local stepInfos = {}
    for i, step in ipairs(Mod.Steps(slot)) do
        stepInfos[i] = menuEntry(player, step)
    end
    local context = ISContextMenu.get(0, getMouseX(), getMouseY())

    self:addActionMenu(context, info, function(bar, node)
        bar:onPickAction(slot, node)
    end)

    local changeOption = context:addOption(Mod.txt("ChangeItem"), nil, nil)
    local change = context:getNew(context)
    context:addSubMenu(changeOption, change)
    self:fillItemPicker(change, function(bar, picked)
        bar:onChangeItem(slot, picked)
    end)

    self:addStepsMenu(context, player, slot, stepInfos)

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
    Mod.Dock.Set(Mod.settings, "custom", nil)
    self:defaultPosition()
    self:rememberPosition()
    Mod.SaveSettings()
end

function Bar:addSettings(context)
    local option = context:addOption(Mod.txt("Settings"), nil, nil)
    local sub = context:getNew(context)
    context:addSubMenu(option, sub)
    self:fillSettings(sub)
end

function Bar:showSettingsMenu()
    local context = ISContextMenu.get(0, getMouseX(), getMouseY())
    self:fillSettings(context)
end

function Mod.SetHidden(hidden)
    Mod.settings.hidden = hidden == true
    Mod.SaveSettings()
end

function Bar:fillSettings(sub)
    local s = Mod.settings
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
    sub:addOption(Mod.txt("ResetPosition"), self, Bar.resetPosition)
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

function Mod.GameHotbarShown()
    local hotbar = getPlayerHotbar(0)
    return hotbar ~= nil and hotbar:isVisible()
end

function Bar:applyVisible(show)
    if self:getIsVisible() == show then
        return
    end
    if not show then
        self.pressedIcon = nil
        self:endBarDrag()
    end
    self:setVisible(show)
    if not show and self.toolRender then
        self.toolRender:setVisible(false)
    end
end

local function onTick()
    local bar = Mod.bar
    if not bar then
        return
    end
    local player = getSpecificPlayer(0)
    local show = player ~= nil and not player:isDead() and not Mod.settings.hidden and Mod.GameHotbarShown()
    bar:applyVisible(show)
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
