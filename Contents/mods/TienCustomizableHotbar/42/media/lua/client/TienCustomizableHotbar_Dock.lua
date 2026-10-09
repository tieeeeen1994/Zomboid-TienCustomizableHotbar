require "TienCustomizableHotbar_Core"

local Mod = TienCustomizableHotbar

local Dock = {}
Mod.Dock = Dock

Dock.SNAP = 16
Dock.SIDES = { above = true, below = true, left = true, right = true }
Dock.ALIGNS = { start = true, ["end"] = true, center = true, offset = true }

local ALIGN_ORDER = { "start", "end", "center" }

function Dock.Rect(element)
    if not element then
        return nil
    end
    return { x = element:getX(), y = element:getY(), w = element:getWidth(), h = element:getHeight() }
end

function Dock.Get(settings, prefix)
    local side = settings[prefix .. "Dock"]
    if not Dock.SIDES[side] then
        return nil
    end
    local align = settings[prefix .. "Align"]
    if not Dock.ALIGNS[align] then
        align = "center"
    end
    return { side = side, align = align, offset = tonumber(settings[prefix .. "Offset"]) or 0 }
end

function Dock.Set(settings, prefix, dock)
    if dock then
        settings[prefix .. "Dock"] = dock.side
        settings[prefix .. "Align"] = dock.align
        settings[prefix .. "Offset"] = dock.offset
    else
        settings[prefix .. "Dock"] = nil
        settings[prefix .. "Align"] = nil
        settings[prefix .. "Offset"] = nil
    end
end

local function cross(start, length, size, align, offset)
    if align == "start" then
        return start
    elseif align == "end" then
        return start + length - size
    elseif align == "center" then
        return start + (length - size) / 2
    end
    return start + (offset or 0)
end

function Dock.Position(w, h, other, dock)
    if dock.side == "above" or dock.side == "below" then
        local y = dock.side == "above" and (other.y - h) or (other.y + other.h)
        return cross(other.x, other.w, w, dock.align, dock.offset), y
    end
    local x = dock.side == "left" and (other.x - w) or (other.x + other.w)
    return x, cross(other.y, other.h, h, dock.align, dock.offset)
end

local function bestAlign(pos, start, length, size)
    local best, bestDist = nil, Dock.SNAP + 1
    for _, align in ipairs(ALIGN_ORDER) do
        local dist = math.abs(pos - cross(start, length, size, align))
        if dist < bestDist then
            best, bestDist = align, dist
        end
    end
    if best then
        return best, 0, bestDist
    end
    return "offset", math.floor(pos - start + 0.5), Dock.SNAP
end

function Dock.Snap(x, y, w, h, other)
    if not other or isShiftKeyDown() then
        return x, y, nil
    end
    local best, bestScore = nil, nil
    local function try(side, mainDist, overlaps)
        if not overlaps or mainDist > Dock.SNAP then
            return
        end
        local align, offset, alignDist
        if side == "above" or side == "below" then
            align, offset, alignDist = bestAlign(x, other.x, other.w, w)
        else
            align, offset, alignDist = bestAlign(y, other.y, other.h, h)
        end
        local score = mainDist + alignDist
        if not best or score < bestScore then
            best = { side = side, align = align, offset = offset }
            bestScore = score
        end
    end
    local xOverlap = x < other.x + other.w and x + w > other.x
    local yOverlap = y < other.y + other.h and y + h > other.y
    try("above", math.abs(y + h - other.y), xOverlap)
    try("below", math.abs(y - (other.y + other.h)), xOverlap)
    try("left", math.abs(x + w - other.x), yOverlap)
    try("right", math.abs(x - (other.x + other.w)), yOverlap)
    if not best then
        return x, y, nil
    end
    local nx, ny = Dock.Position(w, h, other, best)
    return nx, ny, best
end
