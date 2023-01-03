--[[
    Elevator Controller

A script for an all-in-one elevator with floor selection, sounds, doors, and
more.

Requires `pcm-reader.lua` installed as to be required with `require("pcm")`
]]

local pcm = require("pcm")

-- Load floors from elevator settings.
local FLOORS = {}
local floorsFile = io.open("floors.tbl", "r") or error("Missing floors.tbl")
FLOORS = textutils.unserialize(floorsFile:read("a"))
floorsFile:close()
table.sort(FLOORS, function(fA, fB) return fA.height < fB.height end)

local FLOORS_BY_LABEL = {}
for _, floor in pairs(FLOORS) do
    FLOORS_BY_LABEL[floor.label] = floor
end

local FLOOR_LABELS_ORDERED = {}
for _, floor in pairs(FLOORS) do
    table.insert(FLOOR_LABELS_ORDERED, floor.label)
end
table.sort(FLOOR_LABELS_ORDERED, function(lblA, lblB) return FLOORS_BY_LABEL[lblA].height < FLOORS_BY_LABEL[lblB].height end)

local settingsFile = io.open("settings.tbl", "r") or error("Missing settings.tbl")
local settings = textutils.unserialize(settingsFile:read("a"))

local SYSTEM_NAME = settings.systemName

local CONTROL_BASE_RPM = settings.control.baseRpm
local CONTROL_MAX_RPM = settings.control.maxRpm
local CONTROL_ANALOG_LEVEL_PER_RPM = settings.control.analogLevelPerRpm

local CONTROL_DIRECTION_UP = settings.control.directionUp
local CONTROL_DIRECTION_DOWN = settings.control.directionDown
local CONTROL_REDSTONE = settings.control.redstone

local CURRENT_STATE = {
    rpm = nil,
    direction = nil
}

local function openDoor(floor)
    peripheral.call(floor.redstone, "setOutput", "left", true)
end

local function closeDoor(floor)
    peripheral.call(floor.redstone, "setOutput", "left", false)
end

local function playChime(floor)
    local speaker = peripheral.wrap(floor.speaker)
    speaker.playNote("chime", 1, 18)
    os.sleep(0.1)
    speaker.playNote("chime", 1, 12)
end

-- Converts an RPM speed to a blocks-per-second speed.
local function rpmToBps(rpm)
    return (10 / 256) * rpm
end

-- Sets the RPM of the elevator winch, and returns the true rpm that the system operates at.
local function setRpm(rpm)
    if rpm == 0 then
        peripheral.call(CONTROL_REDSTONE, "setOutput", "left", true)
        return 0
    else
        local analogPower = 0
        local trueRpm = 16
        while trueRpm < rpm do
            analogPower = analogPower + CONTROL_ANALOG_LEVEL_PER_RPM
            trueRpm = trueRpm * 2
        end
        peripheral.call(CONTROL_REDSTONE, "setAnalogOutput", "right", analogPower)
        peripheral.call(CONTROL_REDSTONE, "setOutput", "left", false)
        return trueRpm
    end
end

-- Sets the speed of the elevator motion.
-- Positive numbers move the elevator up.
-- Zero sets the elevator as motionless.
-- Negative numbers move the elevator down.
-- The nearest possible RPM is used, via SPEEDS.
local function setSpeed(rpm)
    if rpm == 0 then
        if CURRENT_STATE.rpm ~= 0 then
            CURRENT_STATE.rpm = setRpm(0)
            -- print("Set RPM to " .. tostring(CURRENT_STATE.rpm))
        end
        return
    end
    
    if rpm > 0 then
        peripheral.call(CONTROL_REDSTONE, "setOutput", "top", CONTROL_DIRECTION_UP)
        CURRENT_STATE.direction = CONTROL_DIRECTION_UP
        -- print("Set winch to UP")
    elseif rpm < 0 then
        peripheral.call(CONTROL_REDSTONE, "setOutput", "top", CONTROL_DIRECTION_DOWN)
        CURRENT_STATE.direction = CONTROL_DIRECTION_DOWN
        -- print("Set winch to DOWN")
    end

    if math.abs(rpm) == CURRENT_STATE.rpm then return end
    CURRENT_STATE.rpm = setRpm(math.abs(rpm))
    -- print("Set RPM to " .. tostring(CURRENT_STATE.rpm))
end

local function isFloorContactActive(floor)
    return peripheral.call(floor.redstone, "getInput", "back")
end

-- Determines the label of the floor we're currently on.
-- We first check all known floors to see if the elevator is at one.
-- If that fails, the elevator is at an unknown position, so we move it as soon as possible to top.
local function determineCurrentFloorLabel()
    for _, floor in pairs(FLOORS) do
        local status = isFloorContactActive(floor)
        if status then return floor.label end
    end
    -- No floor found. Move the elevator to the top.
    print("Elevator at unknown position, moving to top.")
    local lastFloor = FLOORS[#FLOORS]
    setSpeed(256)
    local elapsedTime = 0
    while not isFloorContactActive(lastFloor) and elapsedTime < 10 do
        os.sleep(1)
        elapsedTime = elapsedTime + 1
    end
    setSpeed(0)
    if not isFloorContactActive(lastFloor) then
        print("Timed out. Moving down until we hit the top floor.")
        setSpeed(-1)
        while not isFloorContactActive(lastFloor) do
            -- Busy-wait until we hit the contact.
        end
        setSpeed(0)
    end
    return lastFloor.label
end

-- Computes a series of keyframes describing the linear motion of the elevator.
local function computeLinearMotion(distance)
    local preFrames = {}
    local postFrames = {}
    local intervalDuration = 0.25

    local distanceToCover = distance
    local rpmFactor = 1
    while rpmFactor * CONTROL_BASE_RPM < CONTROL_MAX_RPM do
        --print("Need to cover " .. distanceToCover .. " more meters.")
        local rpm = CONTROL_BASE_RPM * rpmFactor
        local potentialDistanceCovered = 2 * intervalDuration * rpmToBps(rpm)
        local nextRpmFactorDuration = (distanceToCover - potentialDistanceCovered) / rpmToBps(CONTROL_BASE_RPM * (rpmFactor + 1))
        --print("We'd cover " .. potentialDistanceCovered .. " by moving at " .. rpm .. " rpm for " .. intervalDuration .. " seconds twice.")
        if potentialDistanceCovered <= distanceToCover and nextRpmFactorDuration >= 2 then
            local frame = {
                rpm = rpm,
                duration = intervalDuration
            }
            table.insert(preFrames, frame)
            table.insert(postFrames, 1, frame)
            distanceToCover = distanceToCover - potentialDistanceCovered
            rpmFactor = rpmFactor * 2
        elseif nextRpmFactorDuration < 2 then
            break
        end
    end

    -- Cover the remaining distance with the next rpmFactor.
    local finalRpm = CONTROL_BASE_RPM * rpmFactor
    local finalDuration = distanceToCover / rpmToBps(finalRpm)
    local finalFrame = {
        rpm = finalRpm,
        duration = finalDuration
    }
    local frames = {}
    for _, frame in pairs(preFrames) do table.insert(frames, frame) end
    table.insert(frames, finalFrame)
    for _, frame in pairs(postFrames) do table.insert(frames, frame) end
    return frames
end

-- Moves the elevator from its current floor to the floor with the given label.
-- During this action, all user input is ignored.
local function goToFloor(floorLabel)
    print("Going to floor " .. floorLabel)
    local currentFloorLabel = determineCurrentFloorLabel()
    if currentFloorLabel == floorLabel then return end
    local currentFloor = FLOORS_BY_LABEL[currentFloorLabel]
    local targetFloor = FLOORS_BY_LABEL[floorLabel]
    local rpmDir = 1
    if targetFloor.height < currentFloor.height then
        rpmDir = -1
    end

    local distance = math.abs(targetFloor.height - currentFloor.height) - 1
    local motionKeyframes = computeLinearMotion(distance)
    --playChime(currentFloor)
    closeDoor(currentFloor)
    local audioFile = "audio/going-up.pcm"
    if rpmDir == -1 then audioFile = "audio/going-down.pcm" end
    local speaker = peripheral.wrap(currentFloor.speaker)
    pcm.playFile(speaker, audioFile)
    for _, frame in pairs(motionKeyframes) do
        local sleepTime = math.floor((frame.duration - 0.05) * 20) / 20 -- Make sure we round down to safely arrive before the detector.
        if frame.rpm == CONTROL_MAX_RPM then
            sleepTime = sleepTime - 0.05 -- For some reason at max RPM this is needed.
        end
        print("Running frame: rpm = " .. tostring(frame.rpm) .. ", dur = " .. tostring(sleepTime))
        setSpeed(rpmDir * frame.rpm)
        os.sleep(sleepTime)
    end

    -- On approach, slow down, wait for contact, then slowly align and stop.
    setSpeed(rpmDir * 1)
    print("Waiting for floor contact capture...")
    local waited = false
    while not isFloorContactActive(targetFloor) do
        waited = true
    end
    print("Contact made.")
    if waited then
        print("Aligning...")
        local alignmentDuration = 0.4 / rpmToBps(CONTROL_BASE_RPM)
        os.sleep(alignmentDuration)
    end
    setSpeed(0)
    print("Locked")

    playChime(targetFloor)
    openDoor(targetFloor)
end

local function initControls()
    print("Initializing control system.")
    setSpeed(0)
    local currentFloorLabel = determineCurrentFloorLabel()
    local currentFloor = FLOORS_BY_LABEL[currentFloorLabel]
    for _, floor in pairs(FLOORS) do
        openDoor(floor)
        os.sleep(0.05)
        closeDoor(floor)
    end
    openDoor(currentFloor)
    print("Control system initialized.")
end

--[[
    User Interface Section
]]

local function drawText(monitor, x, y, text, fg, bg)
    if fg ~= nil then
        monitor.setTextColor(fg)
    end
    if bg ~= nil then
        monitor.setBackgroundColor(bg)
    end
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function drawTextCentered(monitor, x, y, text, fg, bg)
    local w, h = monitor.getSize()
    drawText(monitor, x - (string.len(text) / 2), y, text, fg, bg)
end

local function clearLine(monitor, line, color)
    monitor.setBackgroundColor(color)
    monitor.setCursorPos(1, line)
    monitor.clearLine()
end

local function drawGui(floor, currentFloorLabel, destinationFloorLabel)
    local monitor = peripheral.wrap(floor.monitor)
    monitor.setTextScale(1)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local w, h = monitor.getSize()
    clearLine(monitor, 1, colors.blue)
    drawText(monitor, 1, 1, SYSTEM_NAME, colors.white, colors.blue)

    for i=1, #FLOOR_LABELS_ORDERED do
        local label = FLOOR_LABELS_ORDERED[#FLOOR_LABELS_ORDERED - i + 1]
        local floor = FLOORS_BY_LABEL[label]
        local bg = colors.lightGray
        if i % 2 == 0 then bg = colors.gray end
        local line = i + 1
        clearLine(monitor, line, bg)

        local labelBg = bg
        if label == currentFloorLabel and destinationFloorLabel == nil then
            labelBg = colors.green
        end
        if label == destinationFloorLabel then
            labelBg = colors.yellow
        end
        -- Format label with padding.
        label = " " .. label
        while string.len(label) < 3 do label = label .. " " end
        drawText(monitor, 1, line, label, colors.white, labelBg)

        drawText(monitor, 4, line, floor.name, colors.white, bg)
    end
end

local function drawCallMonitorGui(floor, currentFloorLabel, destinationFloorLabel)
    local monitor = peripheral.wrap(floor.callMonitor)
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(colors.white)
    monitor.clear()

    local w, h = monitor.getSize()
    if destinationFloorLabel == floor.label then
        drawTextCentered(monitor, w/2, h/2, "Arriving", colors.green, colors.white)
    elseif destinationFloorLabel ~= nil then
        drawTextCentered(monitor, w/2, h/2, "In transit", colors.yellow, colors.white)
    elseif floor.label == currentFloorLabel then
        drawTextCentered(monitor, w/2, h/2, "Available", colors.green, colors.white)
    else
        drawTextCentered(monitor, w/2, h/2, "Call", colors.blue, colors.white)
    end
end

local function renderMonitors(currentFloorLabel, destinationFloorLabel)
    for _, floor in pairs(FLOORS) do
        drawGui(floor, currentFloorLabel, destinationFloorLabel)
        drawCallMonitorGui(floor, currentFloorLabel, destinationFloorLabel)
    end
end

local function initUserInterface()
    local currentFloorLabel = determineCurrentFloorLabel()
    renderMonitors(currentFloorLabel, nil)
end

local function listenForInput()
    local event, peripheralId, x, y = os.pullEvent("monitor_touch")
    for _, floor in pairs(FLOORS) do
        if floor.monitor == peripheralId then
            if y > 1 and y <= #FLOORS + 1 then
                local floorIndex = #FLOOR_LABELS_ORDERED - (y - 1) + 1
                local label = FLOOR_LABELS_ORDERED[floorIndex]
                print("y = " .. tostring(y) .. ", floorIndex = " .. floorIndex .. ", label = " .. label)
                local currentFloorLabel = determineCurrentFloorLabel()
                if label ~= currentFloorLabel then
                    renderMonitors(currentFloorLabel, label)
                    goToFloor(label)
                    renderMonitors(label, nil)
                end
            end
            return
        elseif floor.callMonitor == peripheralId then
            local currentFloorLabel = determineCurrentFloorLabel()
            if floor.label ~= currentFloorLabel then
                renderMonitors(currentFloorLabel, floor.label)
                goToFloor(floor.label)
                renderMonitors(floor.label, nil)
            end
            return
        end
    end
end

--[[
    Main Script Area.
]]

initControls()
initUserInterface()
while true do
    listenForInput()
end