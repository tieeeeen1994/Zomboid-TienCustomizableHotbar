require "Hotbar/ISHotbar"
require "TienCustomizableHotbar_Bar"

local Mod = TienCustomizableHotbar

local Game = {}
Mod.GameHotbar = Game

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local DRAG_THRESHOLD = 6
local MARKER = { r = 0.35, g = 0.75, b = 0.35 }
local SHIFT_FIRST = { "drawRect", "drawRectStatic", "drawRectBorder", "drawRectBorderStatic" }
local SHIFT_SECOND = { "drawText", "drawTextCentre", "drawTextRight", "drawTexture", "drawTextureScaled",
    "drawTextureScaledAspect", "drawTextureScaledUniform", "drawItemIcon", "drawScriptItemIcon" }
local ATTACH_ACTIONS = { ISAttachItemHotbar = true, ISDetachItemHotbar = true }

local M = Mod.Tools.Metrics(1)

local installed = false
local renderFailed = false

local function isOurs(hotbar)
    return hotbar ~= nil and hotbar.playerNum == 0
end

local function isLaidOut(hotbar)
    return isOurs(hotbar) and hotbar.tchShift ~= nil
end

local function slotLeft(hotbar)
    return (hotbar.tchShift or 0) + hotbar.margins + 1
end

local function slotX(hotbar, index)
    return slotLeft(hotbar) + (index - 1) * (hotbar.slotWidth + hotbar.slotPad)
end

function Game.Place(hotbar)
    if not isOurs(hotbar) then
        return
    end
    local s = Mod.settings
    local drag = hotbar.tchDrag
    local x, y
    local dock = Mod.Dock.Get(s, "game")
    if drag and drag.moved then
        x = drag.x + getMouseX() - drag.mx
        y = drag.y + getMouseY() - drag.my
        drag.pendingDock = nil
        local bar = Mod.bar
        if bar and bar:getIsVisible() and not Mod.Dock.Get(s, "custom") then
            x, y, drag.pendingDock = Mod.Dock.Snap(x, y, hotbar.width, hotbar.height, Mod.Dock.Rect(bar))
        end
    elseif dock and Mod.bar then
        if Mod.bar.moving then
            Mod.bar:dragUpdate()
        end
        x, y = Mod.Dock.Position(hotbar.width, hotbar.height, Mod.Dock.Rect(Mod.bar), dock)
    elseif s.gameX and s.gameY then
        x = s.gameX - hotbar.width / 2
        y = s.gameY
    else
        return
    end
    local left = getPlayerScreenLeft(0)
    local top = getPlayerScreenTop(0)
    local width = getPlayerScreenWidth(0)
    local height = getPlayerScreenHeight(0)
    x = math.max(left, math.min(x, left + width - hotbar.width))
    y = math.max(top + FONT_HGT_SMALL, math.min(y, top + height - hotbar.height))
    hotbar:setX(x)
    hotbar:setY(y)
end

function Game.Save(hotbar)
    local s = Mod.settings
    s.gameX = hotbar:getX() + hotbar.width / 2
    s.gameY = hotbar:getY()
    Mod.SaveSettings()
end

function Game.Icons(hotbar)
    if hotbar.tchIcons then
        return hotbar.tchIcons
    end
    hotbar.tchIcons = {
        {
            texture = function() return Mod.settings.gameLocked and "lock" or "unlock" end,
            tip = function() return Mod.txt(Mod.settings.gameLocked and "TipGameLocked" or "TipGameUnlocked") end,
            click = function() Game.SetLocked(nil, not Mod.settings.gameLocked) end,
        },
        {
            texture = function() return Mod.settings.gameSwap and "swap" or "insert" end,
            tip = function() return Mod.txt(Mod.settings.gameSwap and "TipSwap" or "TipInsert") end,
            click = function()
                Mod.settings.gameSwap = not Mod.settings.gameSwap
                Mod.SaveSettings()
            end,
        },
        {
            texture = function() return Mod.settings.hidden and "eyeoff" or "eye" end,
            alpha = function() return Mod.settings.hidden and 0.6 or 1 end,
            tip = function() return Mod.txt(Mod.settings.hidden and "TipShowBar" or "TipHideBar") end,
            click = function() Mod.SetHidden(not Mod.settings.hidden) end,
        },
        {
            texture = function() return "gear" end,
            tip = function() return Mod.txt("GameSettings") end,
            click = function() Game.ShowMenu() end,
        },
    }
    return hotbar.tchIcons
end

function Game.Layout(hotbar)
    local inner = hotbar.width
    local shift = M.grip
    local icons = Game.Icons(hotbar)
    local per, block = Mod.Tools.Block(M, #icons, hotbar.height)
    local tools = shift + inner - hotbar.margins - 1 + hotbar.slotPad
    Mod.Tools.Layout(icons, M, false, tools, hotbar.height, per)
    local full = tools + block + M.margin + 1
    hotbar.tchShift = shift
    hotbar.tchInner = inner
    hotbar.tchTools = tools
    hotbar:setWidth(full)
    hotbar:setX(hotbar:getX() - (full - inner) / 2)
end

function Game.Region(hotbar, x, y)
    if x < 0 or y < 0 or x >= hotbar.width or y >= hotbar.height then
        return nil
    end
    if x < slotLeft(hotbar) then
        return "handle"
    end
    if x >= hotbar.tchTools then
        return "tools"
    end
    return "slots"
end

local function isOnSlot(hotbar, x, y)
    local top = hotbar.margins + 1
    if y < top or y >= top + hotbar.slotHeight then
        return false
    end
    local offset = x - slotLeft(hotbar)
    if offset < 0 then
        return false
    end
    local step = hotbar.slotWidth + hotbar.slotPad
    local index = math.floor(offset / step) + 1
    return index <= #hotbar.availableSlot and offset - (index - 1) * step < hotbar.slotWidth
end

local function shiftedDraws(hotbar)
    if hotbar.tchShifted then
        return hotbar.tchShifted
    end
    local wrappers = {}
    for _, name in ipairs(SHIFT_FIRST) do
        local original = hotbar[name]
        if name == "drawRectBorderStatic" then
            wrappers[name] = function(self, x, y, w, h, ...)
                if x == 0 and y == 0 and w == self.width and h == self.height then
                    return
                end
                return original(self, x + self.tchShift, y, w, h, ...)
            end
        else
            wrappers[name] = function(self, x, ...)
                return original(self, x + self.tchShift, ...)
            end
        end
    end
    for _, name in ipairs(SHIFT_SECOND) do
        local original = hotbar[name]
        wrappers[name] = function(self, first, x, ...)
            return original(self, first, x + self.tchShift, ...)
        end
    end
    hotbar.tchShifted = wrappers
    return wrappers
end

local function beginShift(hotbar)
    local saved = { width = hotbar.width, own = {} }
    for name, wrapper in pairs(shiftedDraws(hotbar)) do
        saved.own[name] = rawget(hotbar, name) or false
        hotbar[name] = wrapper
    end
    hotbar.width = hotbar.tchInner
    return saved
end

local function endShift(hotbar, saved)
    for name, own in pairs(saved.own) do
        hotbar[name] = own or nil
    end
    hotbar.width = saved.width
end

function Game.Heal(hotbar)
    local chr = hotbar.chr
    if not chr or not hotbar.availableSlot then
        return
    end
    local indexOf = {}
    for i, slot in pairs(hotbar.availableSlot) do
        if slot.slotType then
            indexOf[slot.slotType] = i
        end
    end
    local items = {}
    local moved = false
    local inventory = chr:getInventory():getItems()
    for k = 0, inventory:size() - 1 do
        local item = inventory:get(k)
        local current = item:getAttachedSlot()
        if current > -1 then
            local slotType = item:getAttachedSlotType()
            local want = slotType and indexOf[slotType]
            if want and want ~= current and not items[want] then
                item:setAttachedSlot(want)
                syncItemFields(chr, item)
                current = want
                moved = true
            end
            items[current] = item
        end
    end
    if moved then
        hotbar.attachedItems = items
    end
end

local function attachPending(chr)
    local queue = ISTimedActionQueue.queues[chr]
    if not queue then
        return false
    end
    for _, action in ipairs(queue.queue) do
        if ATTACH_ACTIONS[action.Type] then
            return true
        end
    end
    return false
end

function Game.ApplyOrder(hotbar, order)
    local chr = hotbar.chr
    local slots, items = {}, {}
    for newIndex, oldIndex in ipairs(order) do
        local slot = hotbar.availableSlot[oldIndex]
        if not slot then
            return
        end
        slots[newIndex] = slot
    end
    for newIndex, oldIndex in ipairs(order) do
        local item = hotbar.attachedItems[oldIndex]
        if item then
            items[newIndex] = item
            if item:getAttachedSlot() ~= newIndex then
                item:setAttachedSlot(newIndex)
                syncItemFields(chr, item)
            end
        end
    end
    hotbar.availableSlot = slots
    hotbar.attachedItems = items
    hotbar:savePosition()
end

local function mouseIn(hotbar)
    local mx = getMouseX() - hotbar:getAbsoluteX()
    local my = getMouseY() - hotbar:getAbsoluteY()
    local margin = hotbar.slotHeight
    if mx < -margin or my < -margin or mx > hotbar.width + margin or my > hotbar.height + margin then
        return nil
    end
    return mx
end

function Game.InsertIndex(hotbar)
    local mx = mouseIn(hotbar)
    if not mx then
        return nil
    end
    local count = #hotbar.availableSlot
    for i = 1, count do
        if mx < slotX(hotbar, i) + hotbar.slotWidth / 2 then
            return i
        end
    end
    return count + 1
end

function Game.SwapIndex(hotbar)
    local mx = mouseIn(hotbar)
    if not mx then
        return nil
    end
    local count = #hotbar.availableSlot
    for i = 1, count do
        if mx < slotX(hotbar, i) + hotbar.slotWidth + hotbar.slotPad / 2 then
            return i
        end
    end
    return count
end

function Game.Drop(hotbar, from)
    local count = #hotbar.availableSlot
    if from < 1 or from > count or attachPending(hotbar.chr) then
        return
    end
    local order = {}
    for i = 1, count do
        order[i] = i
    end
    if Mod.settings.gameSwap then
        local target = Game.SwapIndex(hotbar)
        if not target or target == from then
            return
        end
        order[from], order[target] = target, from
    else
        local before = Game.InsertIndex(hotbar)
        if not before then
            return
        end
        local target = before
        if target > from then
            target = target - 1
        end
        if target == from then
            return
        end
        table.remove(order, from)
        table.insert(order, target, from)
    end
    Game.ApplyOrder(hotbar, order)
end

local Ghost = ISPanel:derive("TienCustomizableHotbarGameGhost")

function Ghost:new(hotbar, index)
    local o = ISPanel:new(getMouseX(), getMouseY(), hotbar.slotWidth, hotbar.slotHeight)
    setmetatable(o, self)
    self.__index = self
    o.hotbar = hotbar
    o.index = index
    o.background = false
    return o
end

function Ghost:prerender()
    self:setX(getMouseX() - self.width / 2)
    self:setY(getMouseY() - self.height / 2)
    local border = self.hotbar.borderColor
    self:drawRectStatic(0, 0, self.width, self.height, 0.5, 0, 0, 0)
    self:drawRectBorderStatic(0, 0, self.width, self.height, border.a, border.r, border.g, border.b)
    local slot = self.hotbar.availableSlot[self.index]
    local item = self.hotbar.attachedItems[self.index]
    local tex = item and item:getTexture() or (slot and slot.texture)
    if tex then
        local alpha = item and 0.9 or 0.25
        self:drawTexture(tex, (self.width - tex:getWidth()) / 2, (self.height - tex:getHeight()) / 2, alpha, 1, 1, 1)
    end
    if slot then
        local name = getTextOrNull("IGUI_HotbarAttachment_" .. slot.slotType) or slot.name or ""
        local width = getTextManager():MeasureStringX(UIFont.Small, name)
        self:drawRect((self.width - width) / 2 - 2, -FONT_HGT_SMALL, width + 4, FONT_HGT_SMALL, 0.6, 0, 0, 0)
        self:drawText(name, (self.width - width) / 2, -FONT_HGT_SMALL, 1, 1, 1, 1, UIFont.Small)
    end
end

local function checkDrag(hotbar)
    local drag = hotbar.tchDrag
    if not drag or drag.moved then
        return
    end
    if not isMouseButtonDown(0) then
        hotbar.tchDrag = nil
        return
    end
    if math.abs(getMouseX() - drag.mx) + math.abs(getMouseY() - drag.my) >= DRAG_THRESHOLD then
        drag.moved = true
        Mod.Dock.Set(Mod.settings, "game", nil)
        hotbar:setCapture(true)
    end
end

local function checkSlotDrag(hotbar)
    local drag = hotbar.tchSlotDrag
    if not drag or drag.moved then
        return
    end
    if not isMouseButtonDown(0) then
        hotbar.tchSlotDrag = nil
        return
    end
    if math.abs(getMouseX() - drag.mx) + math.abs(getMouseY() - drag.my) >= DRAG_THRESHOLD then
        drag.moved = true
        hotbar:setCapture(true)
        local ghost = Ghost:new(hotbar, drag.index)
        ghost:initialise()
        ghost:addToUIManager()
        ghost:setAlwaysOnTop(true)
        ghost:setWantMouseEvents(false)
        drag.ghost = ghost
    end
end

local function endDrag(hotbar)
    local drag = hotbar.tchDrag
    if not drag then
        return false
    end
    if drag.moved then
        hotbar:setCapture(false)
        Game.Place(hotbar)
        hotbar.tchDrag = nil
        if drag.pendingDock then
            Mod.Dock.Set(Mod.settings, "game", drag.pendingDock)
            Mod.Dock.Set(Mod.settings, "custom", nil)
        end
        Game.Save(hotbar)
        return true
    end
    hotbar.tchDrag = nil
    return true
end

local function endSlotDrag(hotbar)
    local drag = hotbar.tchSlotDrag
    if not drag then
        return false
    end
    hotbar.tchSlotDrag = nil
    if not drag.moved then
        return false
    end
    hotbar:setCapture(false)
    if drag.ghost then
        drag.ghost:removeFromUIManager()
    end
    Game.Drop(hotbar, drag.index)
    return true
end

local function drawDropMarker(hotbar)
    local drag = hotbar.tchSlotDrag
    if not drag or not drag.moved then
        return
    end
    local top = hotbar.margins + 1
    hotbar:drawRect(slotX(hotbar, drag.index), top, hotbar.slotWidth, hotbar.slotHeight, 0.6, 0, 0, 0)
    if Mod.settings.gameSwap then
        local target = Game.SwapIndex(hotbar)
        if target and target ~= drag.index then
            local x, w, h = slotX(hotbar, target), hotbar.slotWidth, hotbar.slotHeight
            hotbar:drawRect(x, top, w, h, 0.25, MARKER.r, MARKER.g, MARKER.b)
            hotbar:drawRectBorder(x - 2, top - 2, w + 4, h + 4, 1, MARKER.r, MARKER.g, MARKER.b)
            hotbar:drawRectBorder(x - 1, top - 1, w + 2, h + 2, 1, MARKER.r, MARKER.g, MARKER.b)
        end
        return
    end
    local before = Game.InsertIndex(hotbar)
    if not before then
        return
    end
    local x
    if before > #hotbar.availableSlot then
        x = slotX(hotbar, #hotbar.availableSlot) + hotbar.slotWidth + hotbar.slotPad / 2
    else
        x = slotX(hotbar, before) - hotbar.slotPad / 2
    end
    hotbar:drawRect(math.floor(x) - 1, 2, 2, hotbar.height - 4, 1, MARKER.r, MARKER.g, MARKER.b)
end

function Game.SetLocked(_, locked)
    Mod.settings.gameLocked = locked
    Mod.SaveSettings()
end

function Game.Reset()
    local s = Mod.settings
    s.gameX = nil
    s.gameY = nil
    Mod.Dock.Set(s, "game", nil)
    Mod.SaveSettings()
    local hotbar = getPlayerHotbar(0)
    if hotbar then
        hotbar:setSizeAndPosition()
    end
end

function Game.AddOptions(menu)
    menu:addOption(Mod.txt("GameReset"), nil, Game.Reset)
end

function Game.ShowMenu()
    local context = ISContextMenu.get(0, getMouseX(), getMouseY())
    Game.AddOptions(context)
end

local function install()
    if installed then
        return
    end
    installed = true

    local innerPrerender = ISHotbar.prerender
    function ISHotbar:prerender()
        if isOurs(self) then
            local drag = self.tchSlotDrag
            if drag and drag.moved and not isMouseButtonDown(0) then
                endSlotDrag(self)
            end
            Game.Place(self)
        end
        innerPrerender(self)
    end

    local innerRender = ISHotbar.render
    function ISHotbar:render()
        if not isLaidOut(self) then
            return innerRender(self)
        end
        local border = self.borderColor
        self:drawRectBorderStatic(0, 0, self.width, self.height, border.a, border.r, border.g, border.b)
        local saved = beginShift(self)
        local ok, err = pcall(innerRender, self)
        endShift(self, saved)
        if not ok and not renderFailed then
            renderFailed = true
            Mod.log(err)
        end
        if not Mod.settings.gameLocked then
            Mod.Tools.DrawGrip(self, slotLeft(self), false)
        end
        local icons = Game.Icons(self)
        Mod.Tools.Draw(self, icons)
        drawDropMarker(self)
        if not self.tchDrag and not self.tchSlotDrag then
            Mod.Tools.DrawTip(self, Mod.Tools.At(icons, self:getMouseX(), self:getMouseY()), false)
        end
    end

    local innerSize = ISHotbar.setSizeAndPosition
    function ISHotbar:setSizeAndPosition()
        innerSize(self)
        if isOurs(self) then
            Game.Layout(self)
        end
        Game.Place(self)
    end

    local innerIndex = ISHotbar.getSlotIndexAt
    function ISHotbar:getSlotIndexAt(x, y)
        if not isLaidOut(self) then
            return innerIndex(self, x, y)
        end
        if x < slotLeft(self) or x >= self.tchTools then
            return -1
        end
        local width = self.width
        self.width = self.tchInner
        local index = innerIndex(self, x - self.tchShift, y)
        self.width = width
        return index
    end

    local innerReload = ISHotbar.reloadIcons
    function ISHotbar:reloadIcons()
        innerReload(self)
        if isOurs(self) then
            Game.Heal(self)
        end
    end

    local innerDown = ISHotbar.onMouseDown
    function ISHotbar:onMouseDown(x, y)
        if isLaidOut(self) then
            self.tchIcon = nil
            local region = Game.Region(self, x, y)
            if region == "tools" then
                self.tchIcon = Mod.Tools.At(Game.Icons(self), x, y)
                return true
            elseif region == "handle" then
                if not Mod.settings.gameLocked then
                    self.tchDrag = { mx = getMouseX(), my = getMouseY(), x = self:getX(), y = self:getY(), moved = false }
                end
                return true
            elseif region == "slots" and not Mod.settings.gameLocked and not ISMouseDrag.dragging then
                local index = self:getSlotIndexAt(x, y)
                if index > 0 and self.availableSlot[index] and isOnSlot(self, x, y) then
                    self.tchSlotDrag = { index = index, mx = getMouseX(), my = getMouseY(), moved = false }
                end
            end
        end
        if innerDown then
            return innerDown(self, x, y)
        end
    end

    local innerMove = ISHotbar.onMouseMove
    function ISHotbar:onMouseMove(dx, dy)
        if innerMove then
            innerMove(self, dx, dy)
        end
        checkDrag(self)
        checkSlotDrag(self)
        if self.tchDrag and self.tchDrag.moved then
            Game.Place(self)
        end
    end

    local innerMoveOutside = ISHotbar.onMouseMoveOutside
    function ISHotbar:onMouseMoveOutside(dx, dy)
        if innerMoveOutside then
            innerMoveOutside(self, dx, dy)
        end
        checkDrag(self)
        checkSlotDrag(self)
        if self.tchDrag and self.tchDrag.moved then
            Game.Place(self)
        end
    end

    local innerUp = ISHotbar.onMouseUp
    function ISHotbar:onMouseUp(x, y)
        if endDrag(self) or endSlotDrag(self) then
            return true
        end
        if isLaidOut(self) then
            local icon = self.tchIcon
            self.tchIcon = nil
            local region = Game.Region(self, x, y)
            if region ~= "slots" then
                if icon and not ISMouseDrag.dragging and Mod.Tools.At(Game.Icons(self), x, y) == icon then
                    Mod.Tools.Click(icon)
                end
                return true
            end
        end
        if innerUp then
            return innerUp(self, x, y)
        end
    end

    local innerUpOutside = ISHotbar.onMouseUpOutside
    function ISHotbar:onMouseUpOutside(x, y)
        self.tchIcon = nil
        if endDrag(self) or endSlotDrag(self) then
            return true
        end
        if innerUpOutside then
            return innerUpOutside(self, x, y)
        end
    end

    local innerRight = ISHotbar.onRightMouseUp
    function ISHotbar:onRightMouseUp(x, y)
        if isOurs(self) and not isOnSlot(self, x, y) then
            Game.ShowMenu()
            return true
        end
        if innerRight then
            return innerRight(self, x, y)
        end
    end

    local hotbar = getPlayerHotbar(0)
    if hotbar then
        hotbar:reloadIcons()
        hotbar:setSizeAndPosition()
    end
end

Events.OnGameStart.Add(install)
