require "TienCustomizableHotbar_Core"

local Mod = TienCustomizableHotbar

local Tools = {}
Mod.Tools = Tools

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local TEXTURE_DIR = "media/ui/TienCustomizableHotbar/"
local GRIP = 12
local ICON = 16
local GAP = 2
local MARGIN = 4

local textures = {}

function Tools.Texture(name)
    local tex = textures[name]
    if tex == nil then
        tex = getTexture(TEXTURE_DIR .. name .. ".png") or false
        textures[name] = tex
    end
    return tex or nil
end

function Tools.Metrics(scale)
    scale = scale or 1
    return {
        grip = math.floor(GRIP * scale + 0.5),
        icon = math.floor(ICON * scale + 0.5),
        gap = math.max(1, math.floor(GAP * scale + 0.5)),
        margin = math.max(2, math.floor(MARGIN * scale + 0.5)),
    }
end

function Tools.Block(m, count, cross)
    local per = math.floor((cross - 2 * m.margin + m.gap) / (m.icon + m.gap))
    per = math.max(1, math.min(per, count))
    local lines = math.ceil(count / per)
    return per, lines * m.icon + (lines - 1) * m.gap
end

function Tools.Layout(icons, m, vertical, along, cross, per)
    local span = per * m.icon + (per - 1) * m.gap
    local first = math.floor((cross - span) / 2)
    for k, icon in ipairs(icons) do
        local line = math.floor((k - 1) / per)
        local pos = (k - 1) % per
        local a = along + line * (m.icon + m.gap)
        local c = first + pos * (m.icon + m.gap)
        if vertical then
            icon.x, icon.y = c, a
        else
            icon.x, icon.y = a, c
        end
        icon.size = m.icon
    end
end

function Tools.At(icons, x, y)
    if not icons then
        return nil
    end
    for _, icon in ipairs(icons) do
        if icon.size and x >= icon.x and x < icon.x + icon.size and y >= icon.y and y < icon.y + icon.size then
            return icon
        end
    end
    return nil
end

function Tools.Draw(element, icons)
    local hovered = Tools.At(icons, element:getMouseX(), element:getMouseY())
    for _, icon in ipairs(icons) do
        if icon.size then
            if icon == hovered then
                element:drawRect(icon.x - 1, icon.y - 1, icon.size + 2, icon.size + 2, 0.25, 1, 1, 1)
            end
            local tex = Tools.Texture(icon.texture())
            if tex then
                local a = icon.alpha and icon.alpha() or 1
                element:drawTextureScaled(tex, icon.x, icon.y, icon.size, icon.size, a, 1, 1, 1)
            end
        end
    end
end

function Tools.DrawTip(element, icon, vertical)
    if not icon then
        return
    end
    local context = getPlayerContextMenu(0)
    if context and context:isAnyVisible() then
        return
    end
    local text = icon.tip()
    local width = getTextManager():MeasureStringX(UIFont.Small, text)
    local x, y
    if vertical then
        x = -width - 6
        y = icon.y + (icon.size - FONT_HGT_SMALL) / 2
        if element:getAbsoluteX() + x < 0 then
            x = element.width + 2
        end
    else
        x = icon.x + icon.size / 2 - width / 2
        y = -FONT_HGT_SMALL
        local absolute = element:getAbsoluteX() + x
        local screen = getCore():getScreenWidth()
        if absolute + width + 2 > screen then
            x = screen - width - 2 - element:getAbsoluteX()
        end
    end
    element:drawRect(x - 2, y, width + 4, FONT_HGT_SMALL, 0.6, 0, 0, 0)
    element:drawText(text, x, y, 1, 1, 1, 1, UIFont.Small)
end

function Tools.Click(icon)
    if not icon then
        return
    end
    getSoundManager():playUISound("UIActivateButton")
    icon.click()
end

function Tools.DrawGrip(element, length, vertical)
    local tex = getTexture("media/ui/circle.png")
    if not tex then
        return
    end
    local across = math.floor((length - 3) / 2)
    for i = 0, 2 do
        if vertical then
            element:drawTextureScaled(tex, element.width / 2 - 7 + i * 5, across, 3, 3, 0.8, 0.7, 0.7, 0.7)
        else
            element:drawTextureScaled(tex, across, element.height / 2 - 7 + i * 5, 3, 3, 0.8, 0.7, 0.7, 0.7)
        end
    end
end
