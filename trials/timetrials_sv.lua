-- Filename to store scores
local scoreFileName = "./scores.json"
local driftScoreFileName = "./drift_scores.json"

-- Colors for printing scores
local color_finish = {238, 198, 78}
local color_highscore = {238, 78, 118}

local function saveScores(fileName, scores)
    local file = io.open(fileName, "w+")
    if file then
        local contents = json.encode(scores)
        file:write(contents)
        io.close( file )
        return true
    else
        return false
    end
end

local function loadScores(fileName)
    local myTable = {}
    local file = io.open(fileName, "r")
    if file then
        local contents = file:read("*a")
        if contents and contents ~= "" then
            local decoded = json.decode(contents)
            if type(decoded) == "table" then
                myTable = decoded
            end
        end
        io.close( file )
        return myTable
    end
    return {}
end

local function getPrimaryIdentifier(playerId)
    local identifiers = GetPlayerIdentifiers(playerId)
    for _, identifier in ipairs(identifiers) do
        if string.find(identifier, "license:") then
            return identifier
        end
    end
    return identifiers[1] or ("player:" .. tostring(playerId))
end

-- Create thread to send scores to clients every 5s
Citizen.CreateThread(function()
    while (true) do
        Citizen.Wait(5000)
        TriggerClientEvent('raceReceiveScores', -1, loadScores(scoreFileName))
        TriggerClientEvent('driftReceiveScores', -1, loadScores(driftScoreFileName))
    end
end)

-- Save score and send chat message when player finishes
RegisterServerEvent('racePlayerFinished')
AddEventHandler('racePlayerFinished', function(source, message, title, newScore)
    -- Get top car score for this race
    local msgAppend = ""
    local msgSource = source
    local msgColor = color_finish
    local allScores = loadScores(scoreFileName)
    local raceScores = allScores[title]
    if raceScores ~= nil then
        -- Compare top score and update if new one is faster
        local carName = newScore.car
        local topScore = raceScores[carName]
        if topScore == nil or newScore.time < topScore.time then
            -- Set new high score
            topScore = newScore
            
            -- Set message parameters to send to all players for high score
            msgSource = -1
            msgAppend = " (fastest)"
            msgColor = color_highscore
        end
        raceScores[carName] = topScore
    else
        -- No scores for this race, create struct and set new high score
        raceScores = {}
        raceScores[newScore.car] = newScore
        
        -- Set message parameters to send to all players for high score
        msgSource = -1
        msgAppend = " (fastest)"
        msgColor = color_highscore
    end
    
    -- Save and store scores back to file
    allScores[title] = raceScores
    saveScores(scoreFileName, allScores)
    
    -- Trigger message to all players
    TriggerClientEvent('chatMessage', -1, "[RACE]", msgColor, message .. msgAppend)
end)

RegisterServerEvent('driftSubmitScore')
AddEventHandler('driftSubmitScore', function(raceId, scorePayload)
    local playerId = source
    if type(raceId) ~= "string" or type(scorePayload) ~= "table" then
        return
    end
    local allScores = loadScores(driftScoreFileName)
    local leaderboardKey = "leaderboard_drift_" .. raceId
    local leaderboard = allScores[leaderboardKey] or {}
    local identifier = getPrimaryIdentifier(playerId)
    local existing = leaderboard[identifier]
    if not existing or (scorePayload.bestScore or 0) > (existing.bestScore or 0) then
        leaderboard[identifier] = scorePayload
        allScores[leaderboardKey] = leaderboard
        saveScores(driftScoreFileName, allScores)
    end
    TriggerClientEvent('driftScoreSaved', playerId, true)
end)

RegisterServerEvent('driftRequestScores')
AddEventHandler('driftRequestScores', function()
    TriggerClientEvent('driftReceiveScores', source, loadScores(driftScoreFileName))
end)
