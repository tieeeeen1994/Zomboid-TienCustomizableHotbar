require "Hotbar/ISHotbar"
require "TienCustomizableHotbar_Bar"

local Mod = TienCustomizableHotbar

local Game = {}
Mod.GameHotbar = Game

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local DRAG_THRESHOLD = 6

local installed = false

local function isOurs(hotbar)
    return hotbar ~= nil and hotbar.playerNum == 0
end

function Game.Place(hotbar)
    if not isOurs(hotbar) then
        return
    end
    local s = Mod.settings
    local drag = hotbar.tchDrag
    local x, y
    if drag and drag.moved then
        x = drag.x + getMouseX() - drag.mx
        y = drag.y + getMouseY() - drag.my
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

local function isOnSlot(hotbar, x, y)
    local top = hotbar.margins + 1
    if y < top or y >= top + hotbar.slotHeight then
        return false
    end
    local offset = x - (hotbar.margins + 1)
    if offset < 0 then
        return false
    end
    local step = hotbar.slotWidth + hotbar.slotPad
    local index = math.floor(offset / step) + 1
    return index <= #hotbar.availableSlot and offset - (index - 1) * step < hotbar.slotWidth
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
        hotbar:setCapture(true)
    end
end

local function endDrag(hotbar)
    local drag = hotbar.tchDrag
    if drag and drag.moved then
        hotbar:setCapture(false)
        Game.Place(hotbar)
        hotbar.tchDrag = nil
        Game.Save(hotbar)
        return true
    end
    hotbar.tchDrag = nil
    return false
end

function Game.SetLocked(_, locked)
    Mod.settings.gameLocked = locked
    Mod.SaveSettings()
end

function Game.Reset()
    local s = Mod.settings
    s.gameX = nil
    s.gameY = nil
    Mod.SaveSettings()
    local hotbar = getPlayerHotbar(0)
    if hotbar then
        hotbar:setSizeAndPosition()
    end
end

function Game.AddOptions(menu)
    local locked = Mod.settings.gameLocked
    local lock = menu:addOption(Mod.txt("GameLock"), nil, Game.SetLocked, not locked)
    if locked then
        menu:setOptionChecked(lock, true)
    end
    menu:addOption(Mod.txt("GameReset"), nil, Game.Reset)
end

local function install()
    if installed then
        return
    end
    installed = true

    local innerRender = ISHotbar.render
    function ISHotbar:render()
        innerRender(self)
        if isOurs(self) and not Mod.settings.gameLocked then
            Mod.DrawGrip(self, self.margins + 1, false)
        end
    end

    local innerSize = ISHotbar.setSizeAndPosition
    function ISHotbar:setSizeAndPosition()
        innerSize(self)
        Game.Place(self)
    end

    local innerDown = ISHotbar.onMouseDown
    function ISHotbar:onMouseDown(x, y)
        if isOurs(self) and not Mod.settings.gameLocked then
            self.tchDrag = { mx = getMouseX(), my = getMouseY(), x = self:getX(), y = self:getY(), moved = false }
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
        if self.tchDrag and self.tchDrag.moved then
            Game.Place(self)
        end
    end

    local innerUp = ISHotbar.onMouseUp
    function ISHotbar:onMouseUp(x, y)
        if endDrag(self) then
            return true
        end
        if innerUp then
            return innerUp(self, x, y)
        end
    end

    local innerUpOutside = ISHotbar.onMouseUpOutside
    function ISHotbar:onMouseUpOutside(x, y)
        if endDrag(self) then
            return true
        end
        if innerUpOutside then
            return innerUpOutside(self, x, y)
        end
    end

    local innerRight = ISHotbar.onRightMouseUp
    function ISHotbar:onRightMouseUp(x, y)
        if isOurs(self) and not isOnSlot(self, x, y) then
            local context = ISContextMenu.get(0, getMouseX(), getMouseY())
            Game.AddOptions(context)
            return true
        end
        if innerRight then
            return innerRight(self, x, y)
        end
    end
end

Events.OnGameStart.Add(install)
