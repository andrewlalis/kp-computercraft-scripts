local pcm = {}

-- Reads a file containing signed 8-bit PCM audio data, and converts it into a list of buffers to play.
function pcm.readFile(filename)
    if not fs.exists(filename) then error("Audio file " .. filename .. " doesn't exist.") end
    if fs.isDir(filename) then error("Cannot read audio from directory: " .. filename) end
    local frames = {}
    local currentFrame = {}
    local currentFrameSampleCount = 0
    local file = fs.open(filename, "rb")
    while true do
        local n = file.read()
        if n == nil then break end
        if n > 127 then n = n - 256 end
        table.insert(currentFrame, n)
        currentFrameSampleCount = currentFrameSampleCount + 1
        if currentFrameSampleCount == (128 * 1024) then
            table.insert(frames, currentFrame)
            currentFrame = {}
            currentFrameSampleCount = 0
        end
    end
    file.close()
    if currentFrameSampleCount > 0 then
        table.insert(frames, currentFrame)
    end
    return frames
end

function pcm.playFrames(speaker, frames)
    for i = 1, #frames do
        while not speaker.playAudio(frames[i]) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

function pcm.playFile(speaker, filename)
    local frames = pcm.readFile(filename)
    pcm.playFrames(frames)
end

return pcm