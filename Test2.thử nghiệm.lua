local player = game.Players.LocalPlayer
local Players = game:GetService("Players")
local Replicated = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CurrentMap = ReplicatedStorage:WaitForChild("CurrentMap")
local RunService = game:GetService("RunService")

local Config = {
    beastDangerDistance = 30,
    exitDangerDistance = 35,
    hackTick = 0.15,
    doorTimeout = 20,
    saveTimeout = 3,
    jumpInterval = 4,
    tweenSpeed = 35,
}

local State = {
    enabled = true,
    gameOver = false,
    isMoving = false,
    isSaving = false,
    isHacking = false,
    currentPC = nil,
    currentTrigger = nil,
    beast = nil,
    foundBeast = false,
    hackedPCs = {},
    skippedPCs = {},
    hasEscaped = false,
    canAutoJump = false,
    jumpTimer = 0,
    firstMoveOfRound = true,
    roundsPlayed = 0,
}

local hackExtraPC = false
local character = nil
local humanoid = nil
local rootPart = nil
local allPCs = {}

local function updateCharacterReferences()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
end

local function resetGameState()
    State.isHacking = false
    State.currentPC = nil
    State.currentTrigger = nil
    State.canAutoJump = false
    State.jumpTimer = 0
    State.hackedPCs = {}
    State.skippedPCs = {}
    State.hasEscaped = false
    State.gameOver = false
    State.beast = nil
    State.foundBeast = false
    State.firstMoveOfRound = true
    State.isMoving = false
    updateCharacterReferences()
end

local function isBeast(plr)
    if not plr then return false end
    local stats = plr:FindFirstChild("TempPlayerStatsModule")
    if not stats then return false end
    local flag = stats:FindFirstChild("IsBeast")
    if not flag then return false end
    return flag.Value == true
end

local function hasPlayerEscaped()
    if not player then return false end
    local stats = player:FindFirstChild("TempPlayerStatsModule")
    if not stats then return false end
    local escapedFlag = stats:FindFirstChild("Escaped")
    if not escapedFlag then return false end
    return escapedFlag.Value == true
end

task.spawn(function()
    while true do
        task.wait(0.3)
        if not State.enabled then continue end
        if State.foundBeast then
            if not State.beast or not Players:FindFirstChild(State.beast.Name) or not isBeast(State.beast) then
                State.beast = nil
                State.foundBeast = false
                State.isHacking = false
                State.currentPC = nil
                State.canAutoJump = false
                State.hasEscaped = false
                State.gameOver = true
                State.isMoving = false
                State.currentTrigger = nil
                task.wait(1)
                local statusText = ""
                pcall(function()
                    local pg = player:FindFirstChild("PlayerGui")
                    local sg = pg and pg:FindFirstChild("ScreenGui")
                    local gif = sg and sg:FindFirstChild("GameInfoFrame")
                    local gsb = gif and gif:FindFirstChild("GameStatusBox")
                    if gsb then statusText = gsb.Text:upper() end
                end)
                if statusText == "" then
                    local gs = ReplicatedStorage:FindFirstChild("GameStatus")
                    if gs then statusText = tostring(gs.Value):upper() end
                end
                local gameStillActive = statusText:find("HACK") or statusText:find("HEAD START") or statusText:find("FIND")
                if gameStillActive and not statusText:find("BEAST") and not statusText:find("BEF") then
                    State.gameOver = false
                    resetGameState()
                end
            end
        else
            for _, p in ipairs(Players:GetPlayers()) do
                if isBeast(p) then
                    State.beast = p
                    State.foundBeast = true
                    break
                end
            end
            if not State.foundBeast then
                task.wait(5)
                local stillNoBeast = true
                for _, p in ipairs(Players:GetPlayers()) do
                    if isBeast(p) then stillNoBeast = false break end
                end
                if stillNoBeast then
                    State.gameOver = false
                end
            end
        end
    end
end)

local function isBeastNearby(distance)
    distance = distance or Config.beastDangerDistance
    if not State.foundBeast or not State.beast or not State.beast.Character then return false end
    local br = State.beast.Character:FindFirstChild("HumanoidRootPart") or State.beast.Character:FindFirstChild("UpperTorso") or State.beast.Character:FindFirstChild("Torso")
    local myRoot = rootPart or (player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("UpperTorso") or player.Character:FindFirstChild("Torso")))
    if not br or not myRoot then return false end
    return (myRoot.Position - br.Position).Magnitude <= distance
end

local function escapeBeast()
    State.isHacking = false
    State.canAutoJump = false
    if State.currentPC and State.currentPC.id then
        State.skippedPCs[State.currentPC.id] = true
    end
    State.currentPC = nil
    State.currentTrigger = nil
end

task.spawn(function()
    local playerGui = player:WaitForChild("PlayerGui")
    local function onActionBoxVisible(ab)
        ab:GetPropertyChangedSignal("Visible"):Connect(function()
            if ab.Visible and State.enabled and State.isHacking and State.currentPC then
                local remote = ReplicatedStorage:FindFirstChild("RemoteEvent")
                if remote and remote.FireServer then
                    pcall(function() remote:FireServer("Input", "Action", true) end)
                end
            end
        end)
    end
    local function bindToScreenGui(screenGui)
        if not screenGui then return end
        local actionBox = screenGui:FindFirstChild("ActionBox")
        if actionBox then
            onActionBoxVisible(actionBox)
        else
            screenGui.ChildAdded:Connect(function(child)
                if child.Name == "ActionBox" then
                    onActionBoxVisible(child)
                end
            end)
        end
    end
    local screenGui = playerGui:WaitForChild("ScreenGui")
    bindToScreenGui(screenGui)
end)

local function getPCProgress(pcData)
    if not pcData or not pcData.computer then return 0 end
    local pc = pcData.computer
    if not pc or not pc.Parent then return 0 end
    local screen = pc:FindFirstChild("Screen")
    if screen and screen:IsA("BasePart") then
        local c = screen.Color
        if c.G > c.R + 0.2 and c.G > c.B + 0.2 then return 1 end
    end
    local maxValue = 0
    for _, v in ipairs(pc:GetDescendants()) do
        if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
            local val = tonumber(v.Value) or 0
            if (v.Name == "ActionProgress" or v.Name == "Value") and val > maxValue then
                maxValue = val
            end
        end
    end
    return maxValue
end

local function getPlayerActionProgress()
    local stats = player:FindFirstChild("TempPlayerStatsModule")
    if not stats then return 0 end
    local p = stats:FindFirstChild("ActionProgress")
    if p and (p:IsA("IntValue") or p:IsA("NumberValue")) then return p.Value end
    return 0
end

local function findAllPCs()
    local found = {}
    local map = CurrentMap.Value
    if not map then return found end
    for _, obj in ipairs(map:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local nameLower = obj.Name:lower()
            if nameLower:find("computer") and not nameLower:find("prefab") then
                local triggers = {}
                for _, t in ipairs(obj:GetDescendants()) do
                    if t:IsA("BasePart") and (t.Name == "ComputerTrigger1" or t.Name == "ComputerTrigger2" or t.Name == "ComputerTrigger3") then
                        table.insert(triggers, t)
                    end
                end
                if #triggers == 3 then
                    table.insert(found, { computer = obj, triggers = triggers })
                end
            end
        end
    end
    for i, pc in ipairs(found) do pc.id = i end
    return found
end

local function isFindExitPhase()
    local found = false
    local gameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
    if gameStatus then
        local statusText = tostring(gameStatus.Value):upper()
        if statusText:find("FIND AN EXIT") or (statusText:find("FIND") and statusText:find("EXIT")) then
            found = true
        end
    end
    pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        local sg = pg and pg:FindFirstChild("ScreenGui")
        local gif = sg and sg:FindFirstChild("GameInfoFrame")
        local gsb = gif and gif:FindFirstChild("GameStatusBox")
        if gsb then
            local t = gsb.Text:upper()
            if t:find("FIND") and t:find("EXIT") then
                found = true
            end
        end
    end)
    return found
end

task.spawn(function()
    local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent", 10)
    if not remoteEvent then return end
    local function isInLobby()
        local gs = ReplicatedStorage:FindFirstChild("GameStatus")
        if not gs then return true end
        local txt = tostring(gs.Value):upper()
        return not (txt:find("HACK") or txt:find("HEAD START") or txt:find("FIND"))
    end
    while not isInLobby() do task.wait(1) end
    while isInLobby() do task.wait(1) end
    while true do
        task.wait(0.1)
        if not State.enabled then continue end
        pcall(function()
            remoteEvent:FireServer("SetPlayerMinigameResult", true)
        end)
    end
end)

local function isCoHacking()
    if not State.currentTrigger then return false end
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other.Character then
            local root = other.Character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - State.currentTrigger.Position).Magnitude <= 8 then
                local tps = other:FindFirstChild("TempPlayerStatsModule")
                local ap = tps and tps:FindFirstChild("ActionProgress")
                if ap and ap.Value > 0.01 then return true end
            end
        end
    end
    return false
end

RunService.Heartbeat:Connect(function(dt)
    if not player.Character then return end
    humanoid = player.Character:FindFirstChild("Humanoid")
    rootPart = player.Character:FindFirstChild("HumanoidRootPart")
    if State.gameOver then
        State.canAutoJump = false
        State.jumpTimer = 0
        return
    end
    if State.canAutoJump and humanoid and rootPart and State.currentTrigger then
        if isCoHacking() then
            State.jumpTimer = 0
            return
        end
        State.jumpTimer = State.jumpTimer + dt
        if State.jumpTimer >= Config.jumpInterval then
            pcall(function()
                rootPart.CFrame = CFrame.new(rootPart.CFrame.Position + Vector3.new(0, 7, 0))
            end)
            task.wait(0.07)
            pcall(function()
                if State.currentTrigger then
                    rootPart.CFrame = State.currentTrigger.CFrame + Vector3.new(0, 0.5, 0)
                end
            end)
            State.jumpTimer = 0
        end
    end
end)

local function isGameActive()
    local gs = ReplicatedStorage:FindFirstChild("GameStatus")
    if not gs then return false end
    local txt = tostring(gs.Value):upper()
    if txt == "" then return false end
    if txt:find("GAME OVER") or txt:find("BEAST LEFT") or txt:find("BEF LAI") or txt:find("KET THUC") or txt:find("TRO CHOI KET THUC") then
        return false
    end
    return true
end

local function moveToPos(targetPos, spd)
    local STOP_DIST = math.max(0.5, spd * 0.05 * 0.8)
    while true do
        task.wait(0.05)
        if State.isSaving then break end
        if not rootPart or not rootPart.Parent then break end
        local diff = targetPos - rootPart.Position
        if diff.Magnitude <= STOP_DIST then
            rootPart.CFrame = CFrame.new(targetPos)
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            break
        end
        rootPart.AssemblyLinearVelocity = diff.Unit * spd
        rootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

local function movementController(trigger, straightMove)
    if not rootPart or not player.Character then return end
    local hum = player.Character:FindFirstChild("Humanoid")
    if State.firstMoveOfRound and not straightMove then
        State.firstMoveOfRound = false
        rootPart.CFrame = trigger.CFrame + Vector3.new(0, 0.5, 0)
        task.wait(0.1)
        return
    end
    while State.isMoving do task.wait(0.1) end
    State.isMoving = true
    if hum then
        hum.PlatformStand = true
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end
    local noclipActive = true
    local noclipConn = RunService.Stepped:Connect(function()
        if not noclipActive or not player.Character then return end
        for _, part in pairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    if straightMove then
        local targetPos = Vector3.new(trigger.Position.X, trigger.Position.Y + 0.5, trigger.Position.Z)
        moveToPos(targetPos, Config.tweenSpeed)
    else
        local myPos = rootPart.Position
        local posDown = Vector3.new(myPos.X, myPos.Y - 50, myPos.Z)
        local posAcross = Vector3.new(trigger.Position.X, myPos.Y - 50, trigger.Position.Z)
        local posUp = Vector3.new(trigger.Position.X, trigger.Position.Y + 0.5, trigger.Position.Z)
        moveToPos(posDown, Config.tweenSpeed)
        task.wait(0.05)
        moveToPos(posAcross, math.max(10, Config.tweenSpeed * 0.7))
        task.wait(0.05)
        moveToPos(posUp, Config.tweenSpeed)
    end
    noclipActive = false
    noclipConn:Disconnect()
    if hum then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    State.isMoving = false
end

local function hackPC(pcData)
    if not pcData or not pcData.computer or not pcData.triggers or #pcData.triggers == 0 then return false end
    local screen = pcData.computer:FindFirstChild("Screen")
    if screen and screen:IsA("BasePart") then
        local c = screen.Color
        if c.G > c.R + 0.2 and c.G > c.B + 0.2 then
            State.hackedPCs[pcData.id] = true
            return true
        end
    end
    if getPCProgress(pcData) >= 1 then
        State.hackedPCs[pcData.id] = true
        return true
    end
    if isFindExitPhase() and not hackExtraPC then return false end
    local chosenTrigger = nil
    local isFirstTrigger = true
    for _, trigger in ipairs(pcData.triggers) do
        if State.isSaving then return false end
        movementController(trigger, not isFirstTrigger)
        isFirstTrigger = false
        if State.isSaving then
            State.isMoving = false
            return false
        end
        State.currentTrigger = trigger
        State.canAutoJump = true
        local progressBefore = getPlayerActionProgress()
        pcall(function()
            if trigger and rootPart then
                firetouchinterest(rootPart, trigger, 0)
                task.wait(0.1)
                firetouchinterest(rootPart, trigger, 1)
            end
        end)
        local spamTime = 0
        while spamTime < 1 do
            task.wait(0.1)
            spamTime = spamTime + 0.1
            pcall(function()
                local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                if r then r:FireServer("Input", "Action", true) end
            end)
        end
        if getPlayerActionProgress() > progressBefore + 0.001 then
            chosenTrigger = trigger
            break
        else
            State.canAutoJump = false
            State.currentTrigger = nil
        end
    end
    if not chosenTrigger then
        State.isMoving = false
        State.canAutoJump = false
        State.currentTrigger = nil
        return false
    end
    State.isHacking = true
    State.currentPC = pcData
    local lastProgress = 0
    local stuckCount = 0
    while State.isHacking and State.enabled and not State.gameOver do
        task.wait(Config.hackTick)
        if not isGameActive() then
            State.isHacking = false
            State.currentPC = nil
            State.canAutoJump = false
            State.currentTrigger = nil
            State.isMoving = false
            break
        end
        if isBeastNearby(Config.beastDangerDistance) and not State.isSaving then
            State.isHacking = false
            State.currentPC = nil
            State.canAutoJump = false
            if pcData.id then State.skippedPCs[pcData.id] = true end
            escapeBeast()
            return false
        end
        if not pcData.computer or not pcData.computer.Parent then break end
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if remote then remote:FireServer("Input", "Action", true) end
        end)
        local prog = getPlayerActionProgress()
        if prog == lastProgress then
            stuckCount = stuckCount + 1
            if stuckCount > 10 then
                pcall(function()
                    local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                    if r then r:FireServer("Input", "Action", true) end
                end)
                stuckCount = 0
            end
        else
            stuckCount = 0
        end
        if pcData.computer:FindFirstChild("SkillCheckActive") and pcData.computer.SkillCheckActive.Value then
            pcall(function()
                local hr = ReplicatedStorage:FindFirstChild("RemoteEvent")
                if hr then hr:FireServer("SkillCheck", true) end
            end)
        end
        local scr = pcData.computer:FindFirstChild("Screen")
        local doneByColor = false
        if scr and scr:IsA("BasePart") then
            local c = scr.Color
            if c.G > c.R + 0.2 and c.G > c.B + 0.2 then doneByColor = true end
        end
        if doneByColor or prog >= 0.999 then
            State.hackedPCs[pcData.id] = true
            State.canAutoJump = false
            State.currentTrigger = nil
            State.isHacking = false
            State.currentPC = nil
            allPCs = findAllPCs()
            return true
        end
        lastProgress = prog
    end
    State.isHacking = false
    State.currentPC = nil
    State.canAutoJump = false
    State.currentTrigger = nil
    return false
end

local function autoExitUnified()
    local lastExitUsed = nil
    local function findExit()
        local exits = {}
        local mapFolder = ReplicatedStorage:FindFirstChild("CurrentMap")
        local map = mapFolder and mapFolder.Value
        if not map then return exits end
        for _, obj in ipairs(map:GetDescendants()) do
            if obj:IsA("Model") and obj.Name == "ExitDoor" then
                local trig = obj:FindFirstChild("ExitDoorTrigger", true)
                local area = obj:FindFirstChild("ExitArea", true)
                if trig then
                    table.insert(exits, { model = obj, trigger = trig, area = area or trig })
                end
            end
        end
        return exits
    end
    local function canGoExit()
        local gameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
        if gameStatus then
            local statusText = tostring(gameStatus.Value):upper()
            if statusText:find("FIND") and (statusText:find("EXIT") or statusText:find("ESCAPE")) then
                return true
            end
        end
        return false
    end
    local function tpFront(trigger)
        if not player.Character then return end
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        root.CanCollide = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = CFrame.new(trigger.Position.X, trigger.Position.Y + 2.5, trigger.Position.Z)
        task.delay(0.5, function() if root then root.CanCollide = true end end)
    end
    local function isExitOpened(exitData)
        local door = exitData.model:FindFirstChild("Door")
        if door and door:IsA("BasePart") then
            if door.Transparency > 0.5 or not door.CanCollide then return true end
        end
        return false
    end
    local function getActionProgress(plr)
        local tps = plr:FindFirstChild("TempPlayerStatsModule")
        local ap = tps and tps:FindFirstChild("ActionProgress")
        return ap and ap.Value or 0
    end
    local function getPlayerOpeningDoor(trigger)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p.Character then
                local root = p.Character:FindFirstChild("HumanoidRootPart")
                if root and (root.Position - trigger.Position).Magnitude <= 8 then
                    return p
                end
            end
        end
        return nil
    end
    local function waitForDoorOpen(exitData, timeoutSecs)
        timeoutSecs = timeoutSecs or Config.doorTimeout
        local waited = 0
        local beastInterrupted = false
        while waited < timeoutSecs do
            task.wait(0.2)
            waited = waited + 0.2
            if isBeastNearby(Config.exitDangerDistance) then
                beastInterrupted = true
                break
            end
            if isExitOpened(exitData) then return true, false end
            local otherOpener = getPlayerOpeningDoor(exitData.trigger)
            local prog = otherOpener and getActionProgress(otherOpener) or getActionProgress(player)
            if prog >= 0.999 then
                task.wait(0.3)
                return true, false
            end
        end
        return false, beastInterrupted
    end
    local function escape(exitData)
        if not player.Character or not exitData.area then return end
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        local hum = player.Character:FindFirstChild("Humanoid")
        if not root then return end
        local myPos = root.Position
        root.CFrame = CFrame.new(myPos.X, myPos.Y - 80, myPos.Z)
        if hum then
            hum.PlatformStand = true
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end
        local freezeActive = true
        local freezeConn = RunService.Heartbeat:Connect(function()
            if not freezeActive or not root then return end
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end)
        task.wait(1.5)
        freezeActive = false
        freezeConn:Disconnect()
        if root then root.CFrame = exitData.area.CFrame + Vector3.new(0, 2, 0) end
        task.wait(0.3)
        if hum then
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        local waitTime = 0
        while waitTime < 10 do
            task.wait(0.2)
            waitTime = waitTime + 0.2
            if hasPlayerEscaped() then
                State.hasEscaped = true
                return
            end
        end
        State.hasEscaped = true
    end
    local function startOpening(trigger)
        if not player.Character then return false end
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        tpFront(trigger)
        task.wait(0.5)
        pcall(function()
            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if r then r:FireServer("Input", "Action", true) end
        end)
        return true
    end
    while State.enabled and not State.hasEscaped do
        task.wait(0.2)
        if hasPlayerEscaped() then
            State.hasEscaped = true
            break
        end
        if not canGoExit() then
            task.wait(0.3)
            continue
        end
        local exits = findExit()
        if #exits == 0 then
            task.wait(0.5)
            continue
        end
        for _, exitData in ipairs(exits) do
            if not State.enabled or State.hasEscaped then break end
            if lastExitUsed and exitData.model == lastExitUsed then continue end
            if isExitOpened(exitData) then
                escape(exitData)
                lastExitUsed = exitData.model
                break
            else
                if isBeastNearby(Config.exitDangerDistance) then
                    task.wait(0.5)
                else
                    local otherOpener = getPlayerOpeningDoor(exitData.trigger)
                    if otherOpener then
                        tpFront(exitData.trigger)
                        local opened, beastInterrupted = waitForDoorOpen(exitData, Config.doorTimeout)
                        if opened and not beastInterrupted then
                            escape(exitData)
                            lastExitUsed = exitData.model
                            break
                        end
                    else
                        tpFront(exitData.trigger)
                        task.wait(0.2)
                        if startOpening(exitData.trigger) then
                            local firing = true
                            task.spawn(function()
                                while firing do
                                    task.wait(0.15)
                                    pcall(function()
                                        local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                                        if r then r:FireServer("Input", "Action", true) end
                                    end)
                                end
                            end)
                            local opened, beastInterrupted = waitForDoorOpen(exitData, Config.doorTimeout)
                            firing = false
                            if opened and not beastInterrupted then
                                escape(exitData)
                                lastExitUsed = exitData.model
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function isSelfBeast()
    local stats = player:FindFirstChild("TempPlayerStatsModule")
    if not stats then return false end
    local flag = stats:FindFirstChild("IsBeast")
    return flag and flag.Value == true
end

local function getHammerEvent()
    local char = player.Character
    local hammer = char and char:FindFirstChild("Hammer")
    return hammer and hammer:FindFirstChild("HammerEvent")
end

local function getBeastNearestSurvivor()
    local char = player.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local torso = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if hum and torso then
                local captured = false
                local map = ReplicatedStorage:FindFirstChild("CurrentMap")
                map = map and map.Value
                if map then
                    for _, v in ipairs(map:GetChildren()) do
                        if v.Name == "FreezePod" then
                            local ct = v:FindFirstChild("CapturedTorso", true)
                            if ct and ct.Value == torso then
                                captured = true
                                break
                            end
                        end
                    end
                end
                if not captured then
                    local dist = (root.Position - torso.Position).Magnitude
                    if dist < nearestDist then
                        nearest = p
                        nearestDist = dist
                    end
                end
            end
        end
    end
    return nearest
end

local function getBeastNearestRagdoll()
    local char = player.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local torso = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if hum and torso and hum.PlatformStand then
                local dist = (root.Position - torso.Position).Magnitude
                if dist < nearestDist then
                    nearest = p
                    nearestDist = dist
                end
            end
        end
    end
    return nearest
end

local function getBeastNearestEmptyCage()
    local char = player.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local map = ReplicatedStorage:FindFirstChild("CurrentMap")
    map = map and map.Value
    if not map then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, v in ipairs(map:GetChildren()) do
        if v.Name == "FreezePod" then
            local ct = v:FindFirstChild("CapturedTorso", true)
            if ct and ct.Value == nil then
                local trigger = v:FindFirstChild("PodTrigger", true)
                if trigger then
                    local dist = (root.Position - trigger.Position).Magnitude
                    if dist < nearestDist then
                        nearest = v
                        nearestDist = dist
                    end
                end
            end
        end
    end
    return nearest
end

local function beastLoop()
    while true do
        task.wait(0.1)
        if not State.enabled or not isSelfBeast() then continue end
        if not isGameActive() then
            task.wait(1)
            continue
        end
        local remote = getHammerEvent()
        if not remote then continue end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local ropeCheck = player.Character:FindFirstChild("RopeConstraint", true)
        if ropeCheck then
            local cage = getBeastNearestEmptyCage()
            if cage then
                local trigger = cage:FindFirstChild("PodTrigger", true)
                if trigger then
                    local cageCenter = cage:GetModelCFrame().Position
                    local dirIn = (cageCenter - trigger.Position)
                    dirIn = dirIn.Magnitude > 0 and dirIn.Unit * 3 or Vector3.zero
                    local cagePos = Vector3.new(trigger.Position.X + dirIn.X, trigger.Position.Y, trigger.Position.Z + dirIn.Z)
                    local hum = player.Character:FindFirstChild("Humanoid")
                    if hum then
                        hum.PlatformStand = true
                        hum:ChangeState(Enum.HumanoidStateType.Physics)
                    end
                    local noclipActive = true
                    local noclipConn = RunService.Stepped:Connect(function()
                        if not noclipActive or not player.Character then return end
                        for _, part in pairs(player.Character:GetDescendants()) do
                            if part:IsA("BasePart") then part.CanCollide = false end
                        end
                    end)
                    root.CFrame = CFrame.new(cagePos)
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    task.wait(0.15)
                    local freezeActive = true
                    local freezeConn = RunService.Heartbeat:Connect(function()
                        if not freezeActive or not root then return end
                        pcall(function()
                            root.CFrame = CFrame.new(cagePos)
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                        end)
                    end)
                    local t = 0
                    while t < 3 do
                        pcall(function()
                            firetouchinterest(root, trigger, 0)
                            task.wait(0.03)
                            firetouchinterest(root, trigger, 1)
                        end)
                        pcall(function()
                            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                            if r then r:FireServer("Input", "Action", true) end
                        end)
                        local ct = cage:FindFirstChild("CapturedTorso", true)
                        if ct and ct.Value ~= nil then break end
                        task.wait(0.15)
                        t = t + 0.18
                    end
                    freezeActive = false
                    freezeConn:Disconnect()
                    noclipActive = false
                    noclipConn:Disconnect()
                    if hum then
                        hum.PlatformStand = false
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                    continue
                end
            end
        end
        local ragdollTarget = getBeastNearestRagdoll()
        if ragdollTarget and ragdollTarget.Character then
            local torso = ragdollTarget.Character:FindFirstChild("UpperTorso") or ragdollTarget.Character:FindFirstChild("Torso")
            if torso then
                local dir = (root.Position - torso.Position)
                if dir.Magnitude <= 30 then
                    pcall(function() remote:FireServer("Rope", torso) end)
                end
            end
        end
        local survivorTarget = getBeastNearestSurvivor()
        if survivorTarget and survivorTarget.Character then
            local torso = survivorTarget.Character:FindFirstChild("UpperTorso") or survivorTarget.Character:FindFirstChild("Torso")
            if torso then
                local dir = (root.Position - torso.Position)
                if dir.Magnitude <= 30 then
                    pcall(function() remote:FireServer("Hit", torso.Position) end)
                end
            end
        end
    end
end

local function waitForRoundStart()
    while State.enabled do
        local statusText = ""
        pcall(function()
            local pg = player:FindFirstChild("PlayerGui")
            local sg = pg and pg:FindFirstChild("ScreenGui")
            local gif = sg and sg:FindFirstChild("GameInfoFrame")
            local gsb = gif and gif:FindFirstChild("GameStatusBox")
            if gsb then statusText = gsb.Text:upper() end
        end)
        if statusText == "" then
            local gs = ReplicatedStorage:FindFirstChild("GameStatus")
            if gs then statusText = tostring(gs.Value):upper() end
        end
        if statusText:find("HEAD START") or statusText:find("HACK") or statusText:find("FIND") or statusText:find("GIAY") or statusText:find("BAT DAU") then
            task.wait(1)
            return true
        end
        task.wait(0.5)
    end
    return false
end

local function mainLoop()
    while true do
        task.wait(1)
        if not State.enabled then continue end
        waitForRoundStart()
        resetGameState()
        State.roundsPlayed = State.roundsPlayed + 1
        if isSelfBeast() then
            while isGameActive() and State.enabled and not State.gameOver do
                task.wait(0.5)
            end
        else
            allPCs = findAllPCs()
            while isGameActive() and State.enabled and not State.gameOver and not isFindExitPhase() do
                local targetPC = nil
                for _, pc in ipairs(allPCs) do
                    if not State.hackedPCs[pc.id] and not State.skippedPCs[pc.id] then
                        targetPC = pc
                        break
                    end
                end
                if not targetPC then
                    State.skippedPCs = {}
                    task.wait(1)
                    continue
                end
                hackPC(targetPC)
                task.wait(0.5)
            end
            if isFindExitPhase() and State.enabled and not State.gameOver then
                autoExitUnified()
            end
        end
    end
end

local function antiAFK()
    task.spawn(function()
        local VirtualUser = game:GetService("VirtualUser")
        player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        while true do
            task.wait(600)
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end)
end

updateCharacterReferences()
antiAFK()
task.spawn(mainLoop)
task.spawn(beastLoop)
