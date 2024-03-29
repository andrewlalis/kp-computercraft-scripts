--[[
    Quantum Beacon

A script that runs on computers connected to an AE quantum ring to ping their
status back to a central computer.
]]

local SEND_CHANNEL = 100
local RECEIVE_CHANNEL = 101
local NODE_NAME = "TMP"
local TRANSMIT_INTERVAL = 15

local function drawScreen(online)
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("Quantum Beacon")

    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, 3)
    term.write("Node:")
    term.setCursorPos(1, 5)
    term.write("Channel:")
    term.setCursorPos(1, 7)
    term.write("Transmit Interval:")
    term.setCursorPos(1, 9)
    term.write("Online Status:")

    term.setTextColor(colors.white)
    term.setCursorPos(20, 3)
    term.write(NODE_NAME)
    term.setCursorPos(20, 5)
    term.write(tostring(SEND_CHANNEL))
    term.setCursorPos(20, 7)
    term.write(tostring(TRANSMIT_INTERVAL))
    local str = nil
    if online then
        str = "Online"
        term.setTextColor(colors.lime)
    else
        str = "Offline"
        term.setTextColor(colors.red)
    end
    term.setCursorPos(20, 9)
    term.write(str)
end

local function clearMessageLine()
    local _, h = term.getSize()
    term.setBackgroundColor(colors.gray)
    for i = 0, 3 do
        term.setCursorPos(1, h - i)
        term.clearLine()
    end
end

local function showError(msg)
    clearMessageLine()
    local _, h = term.getSize()
    term.setCursorPos(1, h - 2)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.red)
    write(msg)
end

local function showMessage(msg)
    clearMessageLine()
    local _, h = term.getSize()
    term.setCursorPos(1, h - 2)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.lightBlue)
    write(msg)
end

local function getPeripheralOrWait(name)
    local p = nil
    repeat
        p = peripheral.find(name)
        if p == nil then
            showError("Error: Couldn't find an attached peripheral with name \"" .. name .. "\". Please attach one.")
            os.pullEvent("peripheral")
            if p ~= nil then
                showMessage("Peripheral \"" .. name .. "\" connected. Resuming operations shortly.")
                os.sleep(3)
            end
        end
    until p ~= nil
    return p
end

-- We consider a foreign quantum link to be connected if we detect crafting
-- CPUs on the network, since subnetworks shouldn't ever have these.
local function meSystemConnected(meBridge)
    local craftingCpus = meBridge.getCraftingCPUs()
    return craftingCpus ~= nil and #craftingCpus > 0
end



drawScreen(false)
local lastOnlineStatus = false

while true do
    local modem = getPeripheralOrWait("modem")
    local meBridge = getPeripheralOrWait("meBridge")
    local packet = {
        node = NODE_NAME,
        date = os.date("*t"),
        online = meSystemConnected(meBridge)
    }
    modem.transmit(SEND_CHANNEL, RECEIVE_CHANNEL, packet)
    drawScreen(packet.online)
    if lastOnlineStatus == true and packet.online == false then
        showError("The quantum link just went offline.")
        os.sleep(3)
    else
        os.sleep(TRANSMIT_INTERVAL)
    end
    lastOnlineStatus = packet.online
end
