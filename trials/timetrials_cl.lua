-- Local parameters
local START_PROMPT_DISTANCE = 5.0              -- distance to prompt to start race
local DRAW_TEXT_DISTANCE = 100.0                -- distance to start rendering the race name text
local DRAW_SCORES_DISTANCE = 25.0               -- Distance to start rendering the race scores
local DRAW_SCORES_COUNT_MAX = 15                -- Maximum number of scores to draw above race title
local CHECKPOINT_Z_OFFSET = 5.00               -- checkpoint offset in z-axis
local RACING_HUD_COLOR = {238, 198, 78, 255}    -- color for racing HUD above map

-- State variables
local raceState = {
    cP = 1,
    index = 0 ,
    scores = nil,
    startTime = 0,
    blip = 0,
    checkpoint = 1
}

local raceProps = {}

local raceTypeBlips = {
    car = 315,
    boat = 316,
    air = 314
}

local raceTypeLabels = {
    car = "car",
    boat = "boat",
    air = "aircraft"
}

-- Array of colors to display scores, top to bottom and scores out of range will be white
local raceScoreColors = {
    {214, 175, 54, 255},
    {167, 167, 173, 255},
    {167, 112, 68, 255}
}

-- Create preRace thread
Citizen.CreateThread(function()
    preRace()
end)

-- Function that runs when a race is NOT active
function preRace()
    -- Initialize race state
    raceState.cP = 1
    raceState.index = 0 
    raceState.startTime = 0
    raceState.blip = nil
    raceState.checkpoint = nil
    
    -- While player is not racing
    while raceState.index == 0 do
        -- Update every frame
        Citizen.Wait(0)

        -- Get player
        local player = GetPlayerPed(-1)

        -- Teleport player to waypoint if active and button pressed
        if IsWaypointActive() and IsControlJustReleased(0, 182) then
            -- Teleport player to waypoint
            local waypoint = GetFirstBlipInfoId(8)
            if DoesBlipExist(waypoint) then 
                -- Teleport to location, wait 100ms to load then get ground coordinate
                local coords = GetBlipInfoIdCoord(waypoint)
                teleportToCoord(coords.x, coords.y, coords.z, 0)
                Citizen.Wait(100)
                local temp, zCoord = GetGroundZFor_3dCoord(coords.x, coords.y, 9999.9, 1)
                teleportToCoord(coords.x, coords.y, zCoord + 4.0, 0)
            end
        end

        -- Loop through all races
        for index, race in pairs(races) do
            if race.isEnabled then
                -- Draw map marker
                DrawMarker(1, race.start.x, race.start.y, race.start.z - 1, 0, 0, 0, 0, 0, 0, 3.0001, 3.0001, 1.5001, 255, 165, 0,165, 0, 0, 0,0)
                
                -- Check distance from map marker and draw text if close enough
                if GetDistanceBetweenCoords( race.start.x, race.start.y, race.start.z, GetEntityCoords(player)) < DRAW_TEXT_DISTANCE then
                    -- Draw race name
                    Draw3DText(race.start.x, race.start.y, race.start.z-0.600, race.title, RACING_HUD_COLOR, 4, 0.3, 0.3)
                end

                -- When close enough, draw scores
                if GetDistanceBetweenCoords( race.start.x, race.start.y, race.start.z, GetEntityCoords(player)) < DRAW_SCORES_DISTANCE then
                    -- If we've received updated scores, display them
                    if raceState.scores ~= nil then
                        -- Get scores for this race and sort them
                        raceScores = raceState.scores[race.title]
                        if raceScores ~= nil then
                            local sortedScores = {}
                            for k, v in pairs(raceScores) do
                                table.insert(sortedScores, { key = k, value = v })
                            end
                            table.sort(sortedScores, function(a,b) return a.value.time < b.value.time end)

                            -- Create new list with scores to draw
                            local count = 0
                            drawScores = {}
                            for k, v in pairs(sortedScores) do
                                if count < DRAW_SCORES_COUNT_MAX then
                                    count = count + 1
                                    table.insert(drawScores, v.value)
                                end
                            end

                            -- Initialize offset
                            local zOffset = 0
                            if (#drawScores > #raceScoreColors) then
                                zOffset = 0.450*(#raceScoreColors) + 0.300*(#drawScores - #raceScoreColors - 1)
                            else
                                zOffset = 0.450*(#drawScores - 1)
                            end

                            -- Print scores above title
                            for k, score in pairs(drawScores) do
                                -- Draw score text with color coding
                                if (k > #raceScoreColors) then
                                    -- Draw score in white, decrement offset
                                    Draw3DText(race.start.x, race.start.y, race.start.z+zOffset, string.format("%s %.2fs (%s)", score.car, (score.time/1000.0), score.player), {255,255,255,255}, 4, 0.13, 0.13)
                                    zOffset = zOffset - 0.300
                                else
                                    -- Draw score with color and larger text, decrement offset
                                    Draw3DText(race.start.x, race.start.y, race.start.z+zOffset, string.format("%s %.2fs (%s)", score.car, (score.time/1000.0), score.player), raceScoreColors[k], 4, 0.22, 0.22)
                                    zOffset = zOffset - 0.450
                                end
                            end
                        end
                    end
                end
                
                -- When close enough, prompt player
                if GetDistanceBetweenCoords( race.start.x, race.start.y, race.start.z, GetEntityCoords(player)) < START_PROMPT_DISTANCE then
                    helpMessage("Press ~INPUT_CONTEXT~ to Race and Press L to cancel!")
                    if (IsControlJustReleased(1, 51)) then
                        -- Set race index, clear scores and trigger event to start the race
                        raceState.index = index
                        raceState.scores = nil
                        TriggerEvent("raceCountdown")
                        break
                    end
                end
            end
        end
    end
end

local function getRaceType(race)
    if race and race.raceType then
        return race.raceType
    end
    return "car"
end

local function isVehicleAllowedForRace(vehicle, raceType)
    if not DoesEntityExist(vehicle) then
        return false
    end
    local model = GetEntityModel(vehicle)
    if raceType == "air" then
        return IsThisModelAPlane(model) or IsThisModelAHeli(model)
    end
    if raceType == "boat" then
        return IsThisModelABoat(model)
    end
    return IsThisModelACar(model) or IsThisModelABike(model) or IsThisModelAQuadbike(model)
end

local function applyStartBoost(vehicle)
    if DoesEntityExist(vehicle) then
        local currentSpeed = GetEntitySpeed(vehicle)
        SetVehicleForwardSpeed(vehicle, currentSpeed + 10.0)
    end
end

local function ensureModelLoaded(model)
    local modelHash = GetHashKey(model)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Citizen.Wait(0)
    end
    return modelHash
end

local function spawnRaceProp(model, coords, heading)
    local modelHash = ensureModelLoaded(model)
    local prop = CreateObject(modelHash, coords.x, coords.y, coords.z, false, false, false)
    if DoesEntityExist(prop) then
        SetEntityHeading(prop, heading or 0.0)
        FreezeEntityPosition(prop, true)
        table.insert(raceProps, prop)
    end
end

local function cleanupRaceProps()
    for _, prop in ipairs(raceProps) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end
    raceProps = {}
end

local function angleBetweenPoints(prev, current, next)
    if not prev or not next then
        return 180.0
    end
    local v1 = vector3(current.x - prev.x, current.y - prev.y, current.z - prev.z)
    local v2 = vector3(next.x - current.x, next.y - current.y, next.z - current.z)
    local dot = (v1.x * v2.x) + (v1.y * v2.y) + (v1.z * v2.z)
    local mag1 = math.sqrt((v1.x * v1.x) + (v1.y * v1.y) + (v1.z * v1.z))
    local mag2 = math.sqrt((v2.x * v2.x) + (v2.y * v2.y) + (v2.z * v2.z))
    if mag1 == 0 or mag2 == 0 then
        return 180.0
    end
    local cosTheta = dot / (mag1 * mag2)
    if cosTheta > 1 then
        cosTheta = 1
    elseif cosTheta < -1 then
        cosTheta = -1
    end
    return math.deg(math.acos(cosTheta))
end

local function resolvePropCoords(checkpoint)
    local groundSuccess, groundZ = GetGroundZFor_3dCoord(checkpoint.x, checkpoint.y, checkpoint.z + 1000.0, 0)
    if not groundSuccess then
        groundZ = checkpoint.z
    end
    local waterSuccess, waterZ = GetWaterHeight(checkpoint.x, checkpoint.y, checkpoint.z)
    if waterSuccess and waterZ > groundZ then
        return vector3(checkpoint.x, checkpoint.y, waterZ)
    end
    return vector3(checkpoint.x, checkpoint.y, groundZ)
end

local function resolvePropHeading(prev, checkpoint)
    if prev then
        local dirX = checkpoint.x - prev.x
        local dirY = checkpoint.y - prev.y
        if dirX ~= 0 or dirY ~= 0 then
            return GetHeadingFromVector_2d(dirX, dirY)
        end
    end
    return checkpoint.heading or 0.0
end

local function spawnAirCheckpointProps(race)
    if not race.checkpoints then
        return
    end
    for index = 2, #race.checkpoints do
        local checkpoint = race.checkpoints[index]
        local prev = race.checkpoints[index - 1]
        local next = race.checkpoints[index + 1]
        local angle = angleBetweenPoints(prev, checkpoint, next)
        local isFinalCheckpoint = index == #race.checkpoints
        local model = "ar_prop_ig_metv_cp_single"
        if isFinalCheckpoint or angle <= 45.0 then
            model = "ar_prop_ig_flow_cp_b"
        end
        local propCoords = resolvePropCoords(checkpoint)
        local propHeading = resolvePropHeading(prev, checkpoint)
        spawnRaceProp(model, propCoords, propHeading)
    end
end

local function spawnRacePropsForRace(race)
    cleanupRaceProps()
    if race.props then
        for _, prop in ipairs(race.props) do
            spawnRaceProp(prop.model, prop, prop.heading or 0.0)
        end
    end
    if getRaceType(race) == "air" then
        spawnAirCheckpointProps(race)
    end
end

local function createScaleform(scaleformName)
    local scaleform = RequestScaleformMovie(scaleformName)
    while not HasScaleformMovieLoaded(scaleform) do
        Citizen.Wait(0)
    end
    local scaleformTable = {}
    local t1 = {
        __index = function(_, indexed)
            return function(_, ...)
                local args = {...}
                local expectingReturn = args[1]
                table.remove(args, 1)
                BeginScaleformMovieMethod(scaleform, indexed)
                for _, v in pairs(args) do
                    if type(v) == "string" then
                        ScaleformMovieMethodAddParamTextureNameString(v)
                    elseif type(v) == "number" then
                        if math.type(v) == "float" then
                            ScaleformMovieMethodAddParamFloat(v)
                        else
                            ScaleformMovieMethodAddParamInt(v)
                        end
                    elseif type(v) == "boolean" then
                        ScaleformMovieMethodAddParamBool(v)
                    end
                end
                local value = EndScaleformMovieMethodReturn()
                if expectingReturn then
                    while not IsScaleformMovieMethodReturnValueReady(value) do
                        Citizen.Wait(0)
                    end
                    local returnString = GetScaleformMovieMethodReturnValueString(value)
                    local returnInt = GetScaleformMovieMethodReturnValueInt(value)
                    local returnBool = GetScaleformMovieMethodReturnValueBool(value)
                    EndScaleformMovieMethod()
                    if returnString ~= "" then
                        return returnString
                    end
                    if returnInt ~= 0 and not returnBool then
                        return returnInt
                    end
                    return returnBool
                end
            end
        end,
        __call = function(_, ms, r, g, b, a)
            local startScaleformTimer = GetGameTimer()
            CreateThread(function()
                repeat
                    Citizen.Wait(0)
                    DrawScaleformMovieFullscreen(scaleform, r or 255, g or 255, b or 255, a or 255)
                until GetGameTimer() - startScaleformTimer >= ms
            end)
        end
    }
    setmetatable(scaleformTable, t1)
    return scaleformTable
end

local function showRaceCountdown(time)
    local scaleform = createScaleform("COUNTDOWN")
    if time == 0 then
        scaleform:SET_MESSAGE(false, "GO")
    else
        scaleform:SET_MESSAGE(false, time)
    end
    scaleform(1000)
end

local function showBigRaceMessage(bigMessage, smallMessage, ms)
    local scaleform = createScaleform("mp_big_message_freemode")
    scaleform:SHOW_SHARD_WASTED_MP_MESSAGE(false, bigMessage or "", smallMessage or "")
    scaleform(ms or 2000)
end

local function runRaceCinematic(race, onFinish)
    local player = GetPlayerPed(-1)
    local vehicle = GetVehiclePedIsUsing(player)
    if not DoesEntityExist(vehicle) then
        return
    end
    local isMovingCamera = true
    local isCountdownActive = true
    CreateThread(function()
        while isMovingCamera do
            Citizen.Wait(0)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
        end
    end)
    CreateThread(function()
        while isCountdownActive do
            Citizen.Wait(0)
            DisableControlAction(2, 71, true)
            DisableControlAction(2, 72, true)
        end
    end)

    FreezeEntityPosition(vehicle, true)
    local forwardVector, rightVector, upVector = GetEntityMatrix(vehicle)
    local forwardCoords, rightCoords, upCoords = forwardVector * 5, rightVector * 3, upVector * 2
    local cam1 = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", (GetEntityCoords(vehicle) + forwardCoords + rightCoords + upCoords).xyz, (GetEntityRotation(vehicle) + vector3(-20, 0, -210)).xyz, GetGameplayCamFov() * 1.0)
    SetCamAffectsAiming(cam1, false)
    forwardCoords, rightCoords, upCoords = forwardVector * 3, rightVector * -1.5, upVector * 0.5
    local cam2 = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", (GetEntityCoords(vehicle) + forwardCoords + rightCoords + upCoords).xyz, (GetEntityRotation(vehicle) + vector3(-20, 0, -150)).xyz, GetGameplayCamFov() * 1.0)
    SetCamAffectsAiming(cam2, false)
    forwardCoords, rightCoords, upCoords = forwardVector * 0, rightVector * -2, upVector * 0
    local cam3 = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", (GetEntityCoords(vehicle) + forwardCoords + rightCoords + upCoords).xyz, (GetEntityRotation(vehicle) + vector3(0, 0, -100)).xyz, GetGameplayCamFov() * 1.0)
    SetCamAffectsAiming(cam3, false)
    SetCamActiveWithInterp(cam2, cam1, 3700)
    RenderScriptCams(true, false, 0, true, false)
    Citizen.Wait(3700)
    SetCamActive(cam3, true)
    RenderScriptCams(true, false, 0, true, false)
    SetGameplayCamRelativeRotation(GetEntityRotation(vehicle).xyz)
    SetGameplayCamRelativePitch(-10.0, 1.0)
    RenderScriptCams(false, true, 5000, false, false)
    Citizen.Wait(5000)
    isMovingCamera = false

    local lastSecond = GetGameTimer()
    local secondsElapsed = 3
    while secondsElapsed >= 0 do
        Citizen.Wait(0)
        local dif = GetGameTimer() - lastSecond
        if dif > 1000 then
            if secondsElapsed >= 1 then
                if secondsElapsed == 1 then
                    PlaySoundFrontend(-1, "Countdown_GO", "DLC_AW_Frontend_Sounds", true)
                end
                PlaySoundFrontend(-1, "Countdown_3", "DLC_AW_Frontend_Sounds", false)
            end
            lastSecond = GetGameTimer()
            showRaceCountdown(secondsElapsed)
            secondsElapsed = secondsElapsed - 1
        end
    end

    FreezeEntityPosition(vehicle, false)
    isCountdownActive = false
    applyStartBoost(vehicle)
    if onFinish then
        onFinish()
    end
end

-- Receive race scores from server and print
RegisterNetEvent("raceReceiveScores")
AddEventHandler("raceReceiveScores", function(scores)
    -- Save scores to state
    raceState.scores = scores
end)

-- Countdown race start with controls disabled
RegisterNetEvent("raceCountdown")
AddEventHandler("raceCountdown", function()
    -- Get race from index
    local race = races[raceState.index]

    local player = GetPlayerPed(-1)
    local vehicle = GetVehiclePedIsUsing(player)
    local raceType = getRaceType(race)
    if not IsPedInAnyVehicle(player, false) or not isVehicleAllowedForRace(vehicle, raceType) then
        showBigRaceMessage("~r~Wrong vehicle", ("Use a %s for this race."):format(raceTypeLabels[raceType] or raceType), 2500)
        raceState.index = 0
        return
    end
    
    -- Teleport player to start and set heading
    teleportToCoord(race.start.x, race.start.y, race.start.z + 4.0, race.start.heading)
    
    Citizen.CreateThread(function()
        runRaceCinematic(race, function()
            -- Enable acceleration/reverse once race starts
            EnableControlAction(2, 71, true)
            EnableControlAction(2, 72, true)

            -- Start race
            TriggerEvent("raceRaceActive")
        end)
    end)
end)

-- Main race function
RegisterNetEvent("raceRaceActive")
AddEventHandler("raceRaceActive", function()
    -- Get race from index
    local race = races[raceState.index]
    
    -- Start a new timer
    raceState.startTime = GetGameTimer()
    Citizen.CreateThread(function()
        spawnRacePropsForRace(race)
        -- Create first checkpoint
        checkpoint = CreateCheckpoint(race.checkpoints[raceState.cP].type, race.checkpoints[raceState.cP].x,  race.checkpoints[raceState.cP].y,  race.checkpoints[raceState.cP].z + CHECKPOINT_Z_OFFSET, race.checkpoints[raceState.cP].x,race.checkpoints[raceState.cP].y, race.checkpoints[raceState.cP].z, race.checkpointRadius, 204, 204, 1, math.ceil(255*race.checkpointTransparency), 0)
        raceState.blip = AddBlipForCoord(race.checkpoints[raceState.cP].x, race.checkpoints[raceState.cP].y, race.checkpoints[raceState.cP].z)
        
        -- Set waypoints if enabled
        if race.showWaypoints == true then
            SetNewWaypoint(race.checkpoints[raceState.cP+1].x, race.checkpoints[raceState.cP+1].y)
        end
        
        -- While player is racing, do stuff
        while raceState.index ~= 0 do 
            Citizen.Wait(1)
            
            -- Stop race when L is pressed, clear and reset everything
            if IsControlJustReleased(0, 182) and GetLastInputMethod(0) then
                -- Delete checkpoint and raceState.blip
                DeleteCheckpoint(checkpoint)
                RemoveBlip(raceState.blip)
                
                
                -- Clear racing index and break
                raceState.index = 0
                cleanupRaceProps()
                break
            end

            -- Draw checkpoint and time HUD above minimap
            local checkpointDist = math.floor(GetDistanceBetweenCoords(race.checkpoints[raceState.cP].x,  race.checkpoints[raceState.cP].y,  race.checkpoints[raceState.cP].z, GetEntityCoords(GetPlayerPed(-1))))
            DrawHudText(("%.3fs"):format((GetGameTimer() - raceState.startTime)/1000), RACING_HUD_COLOR, 0.015, 0.725, 0.7, 0.7)
            DrawHudText(string.format("Checkpoint %i / %i (%d m)", raceState.cP, #race.checkpoints, checkpointDist), RACING_HUD_COLOR, 0.015, 0.765, 0.5, 0.5)
            
            -- Check distance from checkpoint
            if GetDistanceBetweenCoords(race.checkpoints[raceState.cP].x,  race.checkpoints[raceState.cP].y,  race.checkpoints[raceState.cP].z, GetEntityCoords(GetPlayerPed(-1))) < race.checkpointRadius then
                -- Delete checkpoint and map raceState.blip, 
                DeleteCheckpoint(checkpoint)
                RemoveBlip(raceState.blip)
                
                -- Play checkpoint sound
                PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS")
                
                -- Check if at finish line
                if raceState.cP == #(race.checkpoints) then
                    -- Save time and play sound for finish line
                    local finishTime = (GetGameTimer() - raceState.startTime)
                    PlaySoundFrontend(-1, "ScreenFlash", "WastedSounds")
                    
                    -- Get vehicle name and create score
                    local aheadVehHash = GetEntityModel(GetVehiclePedIsUsing(GetPlayerPed(-1)))
                    local aheadVehNameText = GetLabelText(GetDisplayNameFromVehicleModel(aheadVehHash))
                    local score = {}
                    score.player = GetPlayerName(PlayerId())
                    score.time = finishTime
                    score.car = aheadVehNameText
                    
                    -- Send server event with score and message, move this to server eventually
                    message = string.format("Player " .. GetPlayerName(PlayerId()) .. " finished " .. race.title .. " using " .. aheadVehNameText .. " in " .. (finishTime / 1000) .. " s")
                    TriggerServerEvent('racePlayerFinished', GetPlayerName(PlayerId()), message, race.title, score)
                    
                    -- Clear racing index and break
                    raceState.index = 0
                    cleanupRaceProps()
                    break
                end

                -- Increment checkpoint counter and create next checkpoint
                raceState.cP = math.ceil(raceState.cP+1)
                if race.checkpoints[raceState.cP].type == 16 then
                    -- Create normal checkpoint
                    checkpoint = CreateCheckpoint(race.checkpoints[raceState.cP].type, race.checkpoints[raceState.cP].x,  race.checkpoints[raceState.cP].y,  race.checkpoints[raceState.cP].z + CHECKPOINT_Z_OFFSET, race.checkpoints[raceState.cP].x, race.checkpoints[raceState.cP].y, race.checkpoints[raceState.cP].z, race.checkpointRadius, 204, 204, 1, math.ceil(255*race.checkpointTransparency), 0)
                    raceState.blip = AddBlipForCoord(race.checkpoints[raceState.cP].x, race.checkpoints[raceState.cP].y, race.checkpoints[raceState.cP].z)
                    SetNewWaypoint(race.checkpoints[raceState.cP+1].x, race.checkpoints[raceState.cP+1].y)
                elseif race.checkpoints[raceState.cP].type == 4 then
                    -- Create finish line
                    checkpoint = CreateCheckpoint(race.checkpoints[raceState.cP].type, race.checkpoints[raceState.cP].x,  race.checkpoints[raceState.cP].y,  race.checkpoints[raceState.cP].z + 4.0, race.checkpoints[raceState.cP].x, race.checkpoints[raceState.cP].y, race.checkpoints[raceState.cP].z, race.checkpointRadius, 204, 204, 1, math.ceil(255*race.checkpointTransparency), 0)
                    raceState.blip = AddBlipForCoord(race.checkpoints[raceState.cP].x, race.checkpoints[raceState.cP].y, race.checkpoints[raceState.cP].z)
                    SetNewWaypoint(race.checkpoints[raceState.cP].x, race.checkpoints[raceState.cP].y)
                end
            end
        end
                
        -- Reset race
        cleanupRaceProps()
        preRace()
    end)
end)

-- Create map blips for all enabled tracks
Citizen.CreateThread(function()
    for _, race in pairs(races) do
        if race.isEnabled then
            race.blip = AddBlipForCoord(race.start.x, race.start.y, race.start.z)
            local raceType = getRaceType(race)
            local blipSprite = race.mapBlipId or raceTypeBlips[raceType] or 315
            SetBlipSprite(race.blip, blipSprite)
            SetBlipDisplay(race.blip, 4)
            SetBlipScale(race.blip, 1.0)
            SetBlipColour(race.blip, race.mapBlipColor)
            SetBlipAsShortRange(race.blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(race.title)
            EndTextCommandSetBlipName(race.blip)
        end
    end
end)

-- Utility function to teleport to coordinates
function teleportToCoord(x, y, z, heading)
    Citizen.Wait(1)
    local player = GetPlayerPed(-1)
    if IsPedInAnyVehicle(player, true) then
        SetEntityCoords(GetVehiclePedIsUsing(player), x, y, z)
        Citizen.Wait(100)
        SetEntityHeading(GetVehiclePedIsUsing(player), heading)
    else
        SetEntityCoords(player, x, y, z)
        Citizen.Wait(100)
        SetEntityHeading(player, heading)
    end
end

-- Utility function to display help message
function helpMessage(text, duration)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, duration or 5000)
end

-- Utility function to display 3D text
function Draw3DText(x,y,z,textInput,colour,fontId,scaleX,scaleY)
    local px,py,pz=table.unpack(GetGameplayCamCoords())
    local dist = GetDistanceBetweenCoords(px,py,pz, x,y,z, 1)
    local scale = (1/dist)*20
    local fov = (1/GetGameplayCamFov())*100
    local scale = scale*fov

    SetTextScale(scaleX*scale, scaleY*scale)
    SetTextFont(fontId)
    SetTextProportional(1)
    local colourr,colourg,colourb,coloura = table.unpack(colour)
    SetTextColour(colourr,colourg,colourb, coloura)
    SetTextDropshadow(2, 1, 1, 1, 255)
    SetTextEdge(3, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    SetTextCentre(1)
    AddTextComponentString(textInput)
    SetDrawOrigin(x,y,z+2, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

-- Utility function to display HUD text
function DrawHudText(text,colour,coordsx,coordsy,scalex,scaley)
    SetTextFont(4)
    SetTextProportional(7)
    SetTextScale(scalex, scaley)
    local colourr,colourg,colourb,coloura = table.unpack(colour)
    SetTextColour(colourr,colourg,colourb, coloura)
    SetTextDropshadow(0, 0, 0, 0, coloura)
    SetTextEdge(1, 0, 0, 0, coloura)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(coordsx,coordsy)
end
