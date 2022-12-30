local CONTROL_BASE_RPM = 16
local CONTROL_MAX_RPM = 256

-- Converts an RPM speed to a blocks-per-second speed.
local function rpmToBps(rpm)
    return (10 / 256) * rpm
end

-- Computes a series of keyframes describing the linear motion of the elevator.
local function computeLinearMotion(distance)
    local preFrames = {}
    local postFrames = {}
    local intervalDuration = 0.5

    -- Linear motion calculation
    local v1Dist = 2 * intervalDuration * rpmToBps(CONTROL_BASE_RPM)
    local v2Dist = 2 * intervalDuration * rpmToBps(CONTROL_BASE_RPM * 2)
    local v3Dist = 2 * intervalDuration * rpmToBps(CONTROL_BASE_RPM * 4)
    local v4Dist = 2 * intervalDuration * rpmToBps(CONTROL_BASE_RPM * 8)

    local distanceToCover = distance
    local rpmFactor = 1
    while rpmFactor * CONTROL_BASE_RPM < CONTROL_MAX_RPM do
        print("Need to cover " .. distanceToCover .. " more meters.")
        local rpm = CONTROL_BASE_RPM * rpmFactor
        local potentialDistanceCovered = 2 * intervalDuration * rpmToBps(rpm)
        local nextRpmFactorDuration = (distanceToCover - potentialDistanceCovered) / rpmToBps(CONTROL_BASE_RPM * (rpmFactor + 1))
        print("We'd cover " .. potentialDistanceCovered .. " by moving at " .. rpm .. " rpm for " .. intervalDuration .. " seconds twice.")
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

local function printFrames(frames)
    for _, frame in pairs(frames) do
        print("Frame: rpm = " .. tostring(frame.rpm) .. ", duration = " .. tostring(frame.duration))
    end
end

local frames = computeLinearMotion(5)
printFrames(frames)
local dist = 0
for _, frame in pairs(frames) do
    dist = dist + rpmToBps(frame.rpm) * frame.duration
end
print(dist)

print(0.15 % 0.05 == 0)