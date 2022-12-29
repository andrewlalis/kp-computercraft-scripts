--[[
    Quantum Beacon

A script that runs on computers connected to an AE quantum ring to ping their
status back to a central computer.
]]

local SEND_CHANNEL = 100
local RECEIVE_CHANNEL = 101
local NODE_NAME = "TMP"
local TRANSMIT_INTERVAL = 15

local function getPeripheralOrWait(name)
    local p = nil
    repeat
        p = peripheral.find(name)
        if p == nil then
            print("Error: Couldn't find an attached peripheral with name \"" .. name .. "\". Attach one please.")
            os.pullEvent("peripheral")
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

while true do
    local modem = getPeripheralOrWait("modem")
    local meBridge = getPeripheralOrWait("meBridge")
    local packet = {
        node = NODE_NAME,
        date = os.date("*t"),
        online = meSystemConnected(meBridge)
    }
    modem.transmit(SEND_CHANNEL, RECEIVE_CHANNEL, packet)
    os.sleep(TRANSMIT_INTERVAL)
end
