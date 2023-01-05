--[[
    Rooted Dirt Farm which uses a saw to clear trees.

- The turtle starts facing the location where moss will be placed.
- The turtle will drop rooted dirt below it after each cycle.
- The turtle will replenish its resources (bonemeal, moss, azaleas) via inventories:
    bonemeal: left
    moss: behind
    azaleas: right
]]

local is = require("itemscript")
local ms = require("movescript")

-- Runs one complete cycle of the farm; that is, plant moss, plant the azalea, bonemeal it, activate the saw, then harvest the dirt.
local function doCycle()
    -- Place the moss and azalea.
    is.select("minecraft:moss_block")
    ms.run("PU")
    is.select("minecraft:azalea")
    ms.run("P")
    -- Bonemeal the azalea until we have a tree.
    local blockData = nil
    repeat
        is.select("minecraft:bone_meal")
        ms.run("P")
        _, blockData = turtle.inspect()
    until blockData ~= nil and blockData.name == "minecraft:oak_log"
    -- Activate the saw until the tree is removed.
    redstone.setOutput("right", true)
    while turtle.detect() do
        os.sleep(0.25)
    end
    redstone.setOutput("right", false)
    ms.run("DDg")
    is.dropAllDown("minecraft:rooted_dirt")
end

-- Ensures that we've got enough items for a farm cycle, and if not, tries to fetch the items or wait for user intervention.
local function ensureItemsForCycle()
    local requiredItems = {
        ["minecraft:moss_block"] = 1,
        ["minecraft:azalea"] = 1,
        ["minecraft:bone_meal"] = 10
    }
    local replenishThreshold = 48
    for name, requiredCount in pairs(requiredItems) do
        local actualCount = is.totalCount(name)
        if actualCount <= requiredCount then
            local action1, action2 = nil, nil
            if name == "minecraft:bone_meal" then
                action1 = "L"
                action2 = "R"
            elseif name == "minecraft:moss_block" then
                action1 = "LL"
                action2 = "RR"
            elseif name == "minecraft:azalea" then
                action1 = "R"
                action2 = "L"
            end
            ms.run(action1)
            is.select(name)
            local attempts = 0
            while actualCount < replenishThreshold do
                turtle.suck(64 - actualCount)
                actualCount = is.totalCount(name)
                attempts = attempts + 1
                if attempts > 10 then
                    print("Error: Not enough " .. name .. " available. Please add more and press enter.")
                    io.read()
                    attempts = 0
                end
            end
            ms.run(action2)
        end
    end
end

while true do
    ensureItemsForCycle()
    doCycle()
end