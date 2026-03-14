local player = game.Players.LocalPlayer
local Players = game:GetService("Players")
local Replicated = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CurrentMap = ReplicatedStorage:WaitForChild("CurrentMap")
local RunService = game:GetService("RunService")

local scriptEnabled = false
local hackExtraPC = false
local gameOver = false

local currentTrigger = nil
local currentPC = nil
local skippedPCs = {}
local isHacking = false
local hackedPCs = {}
local beast = nil
local foundBeast = false
local skipCurrentPC = false
local hasEscaped = false
local canAutoJump = false
local jumpTimer = 0

local hidePlatform = nil
local statusLabel = nil

local ANTI_CHEAT_DELAY = 10
local delayAfterHack = 10
local jumpInterval = 4
local SAFE_POS = Vector3.new(50, 73, 50)

local roundsPlayed = 0

local character = nil
local humanoid = nil
local rootPart = nil

local allPCs = {}

local currentActionProgress = 0
local actionProgressConnection = nil

-- ==================== LOG ====================
local function log(msg)
    print("[FTF] " .. tostring(msg))
end

local function updateStatus(status)
    if statusLabel then
        statusLabel.Text = "Status: " .. tostring(status)
    end
    log(tostring(status))
end

-- ==================== CHAR REFS ====================
local function updateCharacterReferences()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
end

-- ==================== HIDE PLATFORM ====================
local function createHidePlatform()
    if hidePlatform then pcall(function() hidePlatform:Destroy() end) end
    local platform = Instance.new("Part")
    platform.Size = Vector3.new(30, 5, 30)
    platform.Position = Vector3.new(50, 70, 50)
    platform.Anchored = true
    platform.Transparency = 0.4
    platform.CanCollide = true
    platform.Parent = workspace
    hidePlatform = platform
end

-- ==================== ACTION PROGRESS TRACKING ====================
local function setupActionProgressTracking()
    if actionProgressConnection then
        pcall(function() actionProgressConnection:Disconnect() end)
        actionProgressConnection = nil
    end

    local function hookActionProgress()
        pcall(function()
            local tps = player:FindFirstChild("TempPlayerStatsModule")
            if not tps then
                return
            end
            local ap = tps:FindFirstChild("ActionProgress")
            if not ap or not ap:IsA("NumberValue") then
                return
            end
            actionProgressConnection = ap:GetPropertyChangedSignal("Value"):Connect(function()
                pcall(function() currentActionProgress = ap.Value or 0 end)
            end)
        end)
    end

    task.spawn(function()
        task.wait(2)
        hookActionProgress()
    end)

    player.ChildAdded:Connect(function(child)
        if child.Name == "TempPlayerStatsModule" then
            task.wait(0.5)
            hookActionProgress()
        end
    end)
end

-- ==================== RESET ====================
local function resetGameState()
    log("Reset state (round=" .. roundsPlayed .. ")")
    isHacking = false
    currentPC = nil
    currentTrigger = nil
    canAutoJump = false
    skipCurrentPC = false
    jumpTimer = 0
    currentActionProgress = 0
    hackedPCs = {}
    skippedPCs = {}
    hasEscaped = false
    gameOver = false
    beast = nil
    foundBeast = false

    if hidePlatform then
        pcall(function() hidePlatform:Destroy() end)
        hidePlatform = nil
    end
    createHidePlatform()
    updateCharacterReferences()
    updateStatus("Waiting for new game")
end

-- ==================== BEAST ====================
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

local beastTrackerRunning = false
local function findBeast()
    if beastTrackerRunning then return end
    beastTrackerRunning = true

    task.spawn(function()
        while true do
            task.wait(0.3)

            if not scriptEnabled then continue end

            if foundBeast then
                if not beast or not Players:FindFirstChild(beast.Name) or not isBeast(beast) then
                    log("Beast lost")
                    beast = nil
                    foundBeast = false
                    isHacking = false
                    currentPC = nil
                    canAutoJump = false
                    hasEscaped = false
                    gameOver = true

                    task.wait(3)
                    local gs = ReplicatedStorage:FindFirstChild("GameStatus")
                    local txt = gs and tostring(gs.Value):upper() or ""
                    if txt:find("HACK") or txt:find("HEAD START") or txt:find("FIND") then
                        log("Game still active -> reset")
                        gameOver = false
                        resetGameState()
                    else
                        log("Game over/lobby -> skip reset")
                    end
                end
            else
                for _, p in ipairs(Players:GetPlayers()) do
                    if isBeast(p) then
                        beast = p
                        foundBeast = true
                        log("Beast found: " .. p.Name)
                        break
                    end
                end

                if not foundBeast then
                    task.wait(5)
                    local stillNoBeast = true
                    for _, p in ipairs(Players:GetPlayers()) do
                        if isBeast(p) then stillNoBeast = false break end
                    end
                    if stillNoBeast then
                        local gs = ReplicatedStorage:FindFirstChild("GameStatus")
                        local txt = gs and tostring(gs.Value):upper() or ""
                        if txt:find("HACK") or txt:find("HEAD START") or txt:find("FIND") then
                            log("No beast after 5s, game active -> reset")
                            resetGameState()
                        else
                            log("No beast after 5s, game over -> skip reset")
                        end
                    end
                end
            end
        end
    end)
end

local function isBeastNearby(distance)
    distance = distance or 23
    if not foundBeast or not beast or not beast.Character then return false end
    local br = beast.Character:FindFirstChild("HumanoidRootPart")
        or beast.Character:FindFirstChild("UpperTorso")
        or beast.Character:FindFirstChild("Torso")
    local myRoot = rootPart
        or (player.Character and (
            player.Character:FindFirstChild("HumanoidRootPart")
            or player.Character:FindFirstChild("UpperTorso")
            or player.Character:FindFirstChild("Torso")))
    if not br or not myRoot then return false end
    local dist = (myRoot.Position - br.Position).Magnitude
    if dist <= distance then
        log("Beast nearby! dist=" .. math.floor(dist))
    end
    return dist <= distance
end

local function escapeBeast()
    updateStatus("Hiding from Beast!")
    pcall(function()
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local hum = char:FindFirstChild("Humanoid")
        if hum and hum.Sit then hum.Sit = false task.wait(0.1) end
        root.CFrame = CFrame.new(SAFE_POS)
    end)
    updateStatus("Hiding 10s...")
    task.wait(10)
    -- Clear skip list so skipped PCs get retried
    skippedPCs = {}
end

-- ==================== WAIT FOR GAME ====================
local function waitForGameActive()
    updateStatus("Waiting for game...")
    local timeout = 300
    local elapsed = 0
    local lastLogTime = 0

    while elapsed < timeout do
        task.wait(0.5)
        elapsed = elapsed + 0.5

        -- Heartbeat log every 30s
        if elapsed - lastLogTime >= 30 then
            lastLogTime = elapsed
        end

        -- Check GameStatusBox
        local ok, result = pcall(function()
            local pg = player:FindFirstChild("PlayerGui")
            if not pg then return nil end
            local sg = pg:FindFirstChild("ScreenGui")
            if not sg then return nil end
            local gif = sg:FindFirstChild("GameInfoFrame")
            if not gif then return nil end
            return gif:FindFirstChild("GameStatusBox")
        end)

        if ok and result and result.Text then
            local txt = result.Text:upper()
            if txt:find("15 SEC HEAD START") or txt:find("HEAD START") then
                task.wait(2)
                return true
            end
        end

        -- Fallback: GameStatus in ReplicatedStorage
        local gs = ReplicatedStorage:FindFirstChild("GameStatus")
        if gs then
            local txt = tostring(gs.Value):upper()
            if txt:find("HEAD START") or txt:find("HACK") then
                task.wait(1)
                return true
            end
        end
    end
    return false
end

-- ==================== ACTION BOX HOOK ====================
spawn(function()
    local playerGui = player:WaitForChild("PlayerGui")
    local function onActionBoxVisible(ab)
        ab:GetPropertyChangedSignal("Visible"):Connect(function()
            if ab.Visible then
                -- Only fire when hacking PC and script is ON
                if scriptEnabled and isHacking and currentPC then
                    local remote = ReplicatedStorage:FindFirstChild("RemoteEvent")
                    if remote and remote.FireServer then
                        pcall(function() remote:FireServer("Input", "Action", true) end)
                    end
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

-- ==================== PC UTILITIES ====================
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

local function getAvailableTrigger(pcData)
    if not pcData or not pcData.triggers then return nil end

    for _, trigger in ipairs(pcData.triggers) do
        local occupied = false
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player and other.Character then
                local root = other.Character:FindFirstChild("HumanoidRootPart")
                if root and (root.Position - trigger.Position).Magnitude <= 5 then
                    occupied = true
                    break
                end
            end
        end
        if not occupied then return trigger end
    end

    return nil -- all 3 triggers occupied -> skip PC
end

local function findAllPCs()
    local found = {}
    local map = CurrentMap.Value
    if not map then
        return found
    end
    for _, obj in ipairs(map:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local nameLower = obj.Name:lower()
            if nameLower:find("computer") and not nameLower:find("prefab") then
                local triggers = {}
                for _, t in ipairs(obj:GetDescendants()) do
                    if t:IsA("BasePart") then
                        if t.Name == "ComputerTrigger1"
                        or t.Name == "ComputerTrigger2"
                        or t.Name == "ComputerTrigger3" then
                            table.insert(triggers, t)
                        end
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
    local gameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
    if gameStatus then
        local statusText = tostring(gameStatus.Value):upper()
        if statusText:find("FIND") and statusText:find("EXIT") then
            return true
        end
    end
    return false
end

-- ==================== NEVER FAIL HOOK ====================
-- ==================== NEVER FAIL ====================
task.spawn(function()
    local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent", 10)
    if not remoteEvent then log("NeverFail: RemoteEvent not found") return end

    -- Only run from lobby/start of round, not mid-game
    local function isInLobby()
        local gs = ReplicatedStorage:FindFirstChild("GameStatus")
        if not gs then return true end
        local txt = tostring(gs.Value):upper()
        return not (txt:find("HACK") or txt:find("HEAD START") or txt:find("FIND"))
    end

    -- Wait for lobby first
    while not isInLobby() do task.wait(1) end
    log("NeverFail: waiting for round...")
    while isInLobby() do task.wait(1) end

    while true do
        task.wait(0.1)
        if not scriptEnabled then continue end
        pcall(function()
            remoteEvent:FireServer("SetPlayerMinigameResult", true)
        end)
    end
end)

-- ==================== HEARTBEAT ====================
RunService.Heartbeat:Connect(function(dt)
    local char = player.Character
    if not char then return end
    humanoid = char:FindFirstChild("Humanoid")
    rootPart = char:FindFirstChild("HumanoidRootPart")
    if canAutoJump and humanoid and rootPart and currentTrigger then
        jumpTimer += dt
        if jumpTimer >= jumpInterval then
            pcall(function()
                rootPart.CFrame = CFrame.new(rootPart.CFrame.Position + Vector3.new(0, 7, 0))
            end)
            task.wait(0.07)
            pcall(function()
                rootPart.CFrame = currentTrigger.CFrame + Vector3.new(0, 0.5, 0)
            end)
            jumpTimer = 0
        end
    end
end)

-- ==================== HACK PC ====================
local function hackPC(pcData)
    if not pcData or not pcData.computer or not pcData.triggers or #pcData.triggers == 0 then
        log("hackPC: invalid pcData")
        return false
    end

    local pcId = tostring(pcData.id)
    local pcName = pcData.computer.Name or "Unknown"

    local chosenTrigger = getAvailableTrigger(pcData)
    if not chosenTrigger then
        return false
    end
    if chosenTrigger and rootPart then
        rootPart.CFrame = chosenTrigger.CFrame + Vector3.new(0, 0.5, 0)
        currentTrigger = chosenTrigger
        task.wait(0.1)
        canAutoJump = true
    end

    isHacking = true
    currentPC = pcData
    updateStatus("Hacking PC " .. pcId)

    local progress = getPCProgress(pcData)
    local skipAnti = (progress >= 1)
    if skipAnti then
    else
        task.wait(0.2)
    end

    -- Initial fire
    pcall(function()
        local hackRemote = ReplicatedStorage:FindFirstChild("RemoteEvent")
        if hackRemote then
            hackRemote:FireServer("Input", "Action", true)
            task.wait(0.1)
            hackRemote:FireServer("Input", "Action", true)
        end
    end)

    pcall(function()
        if chosenTrigger and rootPart then
            firetouchinterest(rootPart, chosenTrigger, 0)
            task.wait(0.05)
            firetouchinterest(rootPart, chosenTrigger, 1)
        end
    end)

    local lastProgress = 0
    local stuckCount = 0
    local lastLoggedPct = -1

    while isHacking and scriptEnabled and not gameOver do
        task.wait(0.15)

        -- Beast check
        if isBeastNearby() then
            isHacking = false
            currentPC = nil
            canAutoJump = false
            skipCurrentPC = true
            if pcData.id then
                skippedPCs[pcData.id] = true
                log("PC" .. pcId .. ": skip (beast nearby)")
            end
            escapeBeast()
            return false
        end

        if not pcData.computer or not pcData.computer.Parent then
            log("PC" .. pcId .. ": disappeared!")
            break
        end

        -- Fire action
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if remote then remote:FireServer("Input", "Action", true) end
        end)

        local prog = getPlayerActionProgress()

        -- Log every 10%
        local pct = math.floor(prog * 100)
        if pct ~= lastLoggedPct and pct % 10 == 0 and pct > 0 then
            log("PC" .. pcId .. " progress: " .. pct .. "%")
            lastLoggedPct = pct
        end

        -- Stuck detection
        if prog == lastProgress then
            stuckCount = stuckCount + 1
            if stuckCount > 10 then
                log("PC" .. pcId .. ": stuck at " .. math.floor(prog*100) .. "%, retry")
                pcall(function()
                    local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                    if r then r:FireServer("Input", "Action", true) end
                end)
                stuckCount = 0
            end
        else
            stuckCount = 0
        end

        -- Skill check
        if pcData.computer:FindFirstChild("SkillCheckActive")
            and pcData.computer.SkillCheckActive.Value then
            log("PC" .. pcId .. ": SkillCheck active, firing")
            pcall(function()
                local hr = ReplicatedStorage:FindFirstChild("RemoteEvent")
                if hr then hr:FireServer("SkillCheck", true) end
            end)
        end

        -- Done check
        local screen = pcData.computer:FindFirstChild("Screen")
        local doneByColor = false
        if screen and screen:IsA("BasePart") then
            local c = screen.Color
            if c.G > c.R + 0.2 and c.G > c.B + 0.2 then doneByColor = true end
        end

        if doneByColor or prog >= 0.999 then
            log("PC" .. pcId .. ": DONE!")
            updateStatus("Done PC " .. pcId)
            hackedPCs[pcData.id] = true

            -- Check last PC BEFORE refreshing allPCs
            local remaining = 0
            for _, pc in ipairs(allPCs) do
                if not hackedPCs[pc.id] then remaining += 1 end
            end
            local isLastPC = (remaining == 0)

            allPCs = findAllPCs()
            isHacking = false
            currentPC = nil
            canAutoJump = false
            currentTrigger = nil

            pcall(function()
                local char = player.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp then char:PivotTo(CFrame.new(SAFE_POS)) end
                end
            end)

            if skipAnti or isLastPC then
                if isLastPC then log("Last PC -> skip delay, go exit!") end
                return true
            end

            updateStatus("Anti-cheat " .. delayAfterHack .. "s...")
            task.wait(delayAfterHack)
            return true
        end

        lastProgress = prog
    end

    log("PC" .. pcId .. ": loop ended (done=" .. tostring(hackedPCs[pcData.id]) .. ")")
    isHacking = false
    currentPC = nil
    canAutoJump = false
    currentTrigger = nil
    return false
end

-- ==================== AUTO EXIT ====================
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
        log("findExit: " .. #exits .. " exit(s) found")
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
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        root.CanCollide = false
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        root.CFrame = CFrame.new(trigger.Position.X, trigger.Position.Y + 2.5, trigger.Position.Z)
        task.delay(0.5, function() if root then root.CanCollide = true end end)
    end

    local function isExitOpened(exitData)
        -- Method 1: transparency
        local door = exitData.model:FindFirstChild("Door")
        if door and door:IsA("BasePart") then
            if door.Transparency > 0.5 then return true end
        end
        -- Method 2: CanCollide off
        if door and door:IsA("BasePart") then
            if not door.CanCollide then return true end
        end
        return false
    end

    -- Detect door open via ActionProgress
    local function waitForDoorOpen(exitData, timeoutSecs)
        timeoutSecs = timeoutSecs or 20
        local waited = 0
        local beastInterrupted = false

        while waited < timeoutSecs do
            task.wait(0.2)
            waited = waited + 0.2

            if isBeastNearby(40) then
                log("Beast near door -> try other exit")
                beastInterrupted = true
                break
            end

            -- Check own ActionProgress
            local tps = player:FindFirstChild("TempPlayerStatsModule")
            local ap = tps and tps:FindFirstChild("ActionProgress")
            local prog = ap and ap.Value or 0
            local pct = math.floor(prog * 100)
            if pct > 0 and pct % 10 == 0 then
                log("Door progress: " .. pct .. "%")
            end
            if prog >= 0.999 then
                log("Door opened! (progress=100%)")
                task.wait(0.5)
                return true, false
            end

            -- Fallback: check visual
            if isExitOpened(exitData) then
                log("Door opened! (visual)")
                return true, false
            end
        end

        return false, beastInterrupted
    end

    local function escape(exitData)
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root or not exitData.area then
            log("escape: no root or area")
            return
        end
        root.CFrame = CFrame.new(50, 73, 50)
        task.wait(3)
        root.CFrame = exitData.area.CFrame + Vector3.new(0, 2, 0)
        task.wait(1.5)

        local waitTime = 0
        while waitTime < 10 do
            task.wait(0.2)
            waitTime = waitTime + 0.2
            if hasPlayerEscaped() then
                log("Escaped!")
                hasEscaped = true
                return
            end
        end
        log("Escape timeout")
        hasEscaped = true
    end

    local function startOpening(trigger)
        local char = player.Character
        if not char then return false end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        tpFront(trigger)
        task.wait(0.5)
        pcall(function()
            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if r then
                r:FireServer("Input", "Action", true)
            end
        end)
        return true
    end

    while scriptEnabled and not hasEscaped do
        task.wait(0.2)

        if hasPlayerEscaped() then
            hasEscaped = true
            log("Escaped!")
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
            if not scriptEnabled or hasEscaped then break end

            if lastExitUsed and exitData.model == lastExitUsed then
                continue
            end

            if isExitOpened(exitData) then
                log("Exit already open, going in")
                pcall(function()
                    local char = player.Character
                    if char then
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if hrp then hrp.CFrame = CFrame.new(50, 73, 50) end
                    end
                end)
                task.wait(3)
                escape(exitData)
                lastExitUsed = exitData.model
                break
            else
                if isBeastNearby(40) then
                    log("Beast near exit, try next")
                    task.wait(0.5)
                else
                    tpFront(exitData.trigger)
                    task.wait(0.2)
                    local success = startOpening(exitData.trigger)
                    if success then
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
                        local opened, beastInterrupted = waitForDoorOpen(exitData, 20)
                        firing = false
                        if beastInterrupted then
                            log("Beast interrupted")
                        elseif opened then
                            escape(exitData)
                            lastExitUsed = exitData.model
                            break
                        else
                            log("Door timeout, try next")
                        end
                    end
                end
            end
        end
    end

    log("autoExitUnified done | hasEscaped=" .. tostring(hasEscaped))
end

-- ==================== MAIN LOOP ====================
local function mainLoop()

    while true do
        if not scriptEnabled then
            isHacking = false
            currentPC = nil
            canAutoJump = false
            hasEscaped = false
            task.wait(0.5)
            continue
        end

        if not waitForGameActive() then
            log("waitForGameActive failed, retry in 10s")
            task.wait(10)
            continue
        end

        roundsPlayed = roundsPlayed + 1
        resetGameState()
        log("=== ROUND " .. roundsPlayed .. " START | Extra=" .. tostring(hackExtraPC) .. " ===")

        allPCs = findAllPCs()

        if #allPCs == 0 then
            updateStatus("No PCs found")
            task.wait(3)
            continue
        end

        updateStatus("Found " .. #allPCs .. " PC(s)")

        local totalAttempts = 0
        local maxAttempts = #allPCs * 3

        while totalAttempts < maxAttempts and scriptEnabled do
            local hasSkippedPC = false
            local allCompleted = true

            for idx, pcData in ipairs(allPCs) do
                if not scriptEnabled then break end

                if isBeastNearby(23) then
                    escapeBeast()
                    skipCurrentPC = true
                else
                    skipCurrentPC = false
                end

                if isFindExitPhase() then
                    if hackExtraPC then
                    else
                        log("Find Exit phase, stop hacking PCs")
                        break
                    end
                end

                local pcId = pcData.id

                if hackedPCs[pcId] then
                    -- silent skip
                elseif skippedPCs[pcId] then
                    log("PC" .. pcId .. " in skip list")
                    hasSkippedPC = true
                else
                    local progress = getPCProgress(pcData)
                    if progress >= 1 then
                        log("PC" .. pcId .. " already done")
                        hackedPCs[pcId] = true
                    else
                        allCompleted = false
                        hackPC(pcData)
                    end
                end
            end

            totalAttempts = totalAttempts + 1

            if allCompleted then
                log("All PCs done!")
                break
            end

            if hasSkippedPC then
                local remainingCount = 0
                for id, _ in pairs(skippedPCs) do
                    if not hackedPCs[id] then remainingCount += 1 end
                end
                log("Skipped PCs remaining: " .. remainingCount)
                if remainingCount > 0 then
                    task.wait(3)
                else
                    break
                end
            end
        end

        if hackExtraPC then task.wait(2) end

        -- Wait for Find Exit
        updateStatus("Waiting for Find Exit...")
        log("Waiting for Find Exit phase...")
        local waitStart = tick()
        repeat task.wait(0.5) until isFindExitPhase() or (tick() - waitStart > 30) or not scriptEnabled

        if not scriptEnabled then continue end

        if isFindExitPhase() then
            log("Find Exit detected!")
            updateStatus("Auto Exit started!")
            autoExitUnified()
            log("=== ROUND " .. roundsPlayed .. " COMPLETE ===")
            task.wait(3)
        else
            log("Find Exit not detected after 30s, continuing")
        end
    end
end

-- ==================== GUI ====================
local function createGUI()
    local TweenService = game:GetService("TweenService")
    local HttpService = game:GetService("HttpService")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoHackGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local scriptStartTime = tick()
    local webhookUrl = ""
    local webhookInterval = 5 -- minutes
    local creditsAtStart = nil
    local creditHistory = {} -- {time, credits}

    local function getCredits()
        local stats = player:FindFirstChild("SavedPlayerStatsModule")
        if stats then
            local c = stats:FindFirstChild("Credits")
            if c then return c.Value end
        end
        return nil
    end

    local function getServerTime()
        return os.date("%H:%M:%S")
    end

    local function formatUptime(secs)
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        local s = math.floor(secs % 60)
        return string.format("%02d:%02d:%02d", h, m, s)
    end

    -- ===== MAIN FRAME =====
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 115)
    frame.Position = UDim2.new(0.5, -100, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = false
    frame.Parent = screenGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 28)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = frame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -36, 1, 0)
    title.Position = UDim2.new(0, 8, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "AUTO FARM FTF"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 12
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    -- Gear button
    local gearBtn = Instance.new("TextButton")
    gearBtn.Size = UDim2.new(0, 24, 0, 24)
    gearBtn.Position = UDim2.new(1, -27, 0, 2)
    gearBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    gearBtn.Text = "⚙"
    gearBtn.TextColor3 = Color3.new(1,1,1)
    gearBtn.TextSize = 13
    gearBtn.Font = Enum.Font.GothamBold
    gearBtn.BorderSizePixel = 0
    gearBtn.Parent = titleBar
    Instance.new("UICorner", gearBtn).CornerRadius = UDim.new(0, 6)

    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(1, -16, 0, 32)
    toggleButton.Position = UDim2.new(0, 8, 0, 32)
    toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    toggleButton.Text = "OFF"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 14
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.BorderSizePixel = 0
    toggleButton.Parent = frame
    Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 7)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 14)
    status.Position = UDim2.new(0, 8, 0, 68)
    status.BackgroundTransparency = 1
    status.Text = "Status: Waiting..."
    status.TextColor3 = Color3.fromRGB(150, 220, 150)
    status.TextSize = 10
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextWrapped = true
    status.Parent = frame
    statusLabel = status

    -- Extra PC checkbox
    local checkboxFrame = Instance.new("Frame")
    checkboxFrame.Size = UDim2.new(1, -16, 0, 18)
    checkboxFrame.Position = UDim2.new(0, 8, 0, 86)
    checkboxFrame.BackgroundTransparency = 1
    checkboxFrame.Parent = frame

    local checkbox = Instance.new("Frame")
    checkbox.Size = UDim2.new(0, 14, 0, 14)
    checkbox.Position = UDim2.new(0, 0, 0.5, -7)
    checkbox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    checkbox.BorderSizePixel = 1
    checkbox.BorderColor3 = Color3.fromRGB(120, 120, 120)
    checkbox.Parent = checkboxFrame
    Instance.new("UICorner", checkbox).CornerRadius = UDim.new(0, 3)

    local checkmark = Instance.new("TextLabel")
    checkmark.Size = UDim2.new(1,0,1,0)
    checkmark.BackgroundTransparency = 1
    checkmark.Text = "✓"
    checkmark.TextColor3 = Color3.fromRGB(255, 80, 80)
    checkmark.TextSize = 12
    checkmark.Font = Enum.Font.GothamBold
    checkmark.Visible = false
    checkmark.Parent = checkbox

    local checkLabel = Instance.new("TextLabel")
    checkLabel.Size = UDim2.new(1, -18, 1, 0)
    checkLabel.Position = UDim2.new(0, 18, 0, 0)
    checkLabel.BackgroundTransparency = 1
    checkLabel.Text = "Hack Extra PC"
    checkLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    checkLabel.TextSize = 10
    checkLabel.Font = Enum.Font.Gotham
    checkLabel.TextXAlignment = Enum.TextXAlignment.Left
    checkLabel.Parent = checkboxFrame

    local checkButton = Instance.new("TextButton")
    checkButton.Size = UDim2.new(1,0,1,0)
    checkButton.BackgroundTransparency = 1
    checkButton.Text = ""
    checkButton.Parent = checkboxFrame

    -- ===== SETTINGS PANEL (slide up/down) =====
    local PANEL_H = 261
    local settingsPanel = Instance.new("Frame")
    settingsPanel.Size = UDim2.new(0, 220, 0, PANEL_H)
    settingsPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    settingsPanel.BorderSizePixel = 0
    settingsPanel.ClipsDescendants = true
    settingsPanel.Visible = false
    settingsPanel.Parent = screenGui
    Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 10)

    local settingsOpen = false
    local function getSettingsPanelPos()
        local frameAbsPos = frame.AbsolutePosition
        local frameAbsSize = frame.AbsoluteSize
        local screenSize = screenGui.AbsoluteSize
        local panelX = (frameAbsPos.X + frameAbsSize.X + 5) / screenSize.X
        local panelY = frameAbsPos.Y / screenSize.Y
        return panelX, panelY
    end

    local function toggleSettings()
        settingsOpen = not settingsOpen
        local panelX, panelY = getSettingsPanelPos()
        local screenSize = screenGui.AbsoluteSize
        local hiddenY = (frame.AbsolutePosition.Y - PANEL_H) / screenSize.Y -- above frame frame

        if settingsOpen then
            settingsPanel.Position = UDim2.new(panelX, 0, hiddenY, 0) -- start from above
            settingsPanel.Visible = true
            TweenService:Create(settingsPanel,
                TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.new(panelX, 0, panelY, 0) -- slide down
            }):Play()
        else
            TweenService:Create(settingsPanel,
                TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                Position = UDim2.new(panelX, 0, hiddenY, 0) -- slide up
            }):Play()
            task.delay(0.25, function() settingsPanel.Visible = false end)
        end
    end

    local settingsTitle = Instance.new("TextLabel")
    settingsTitle.Size = UDim2.new(1, -10, 0, 26)
    settingsTitle.Position = UDim2.new(0, 5, 0, 2)
    settingsTitle.BackgroundTransparency = 1
    settingsTitle.Text = "⚙ SETTINGS & STATS"
    settingsTitle.TextColor3 = Color3.fromRGB(200, 200, 255)
    settingsTitle.TextSize = 12
    settingsTitle.Font = Enum.Font.GothamBold
    settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
    settingsTitle.Parent = settingsPanel

    local function makeLabel(yPos, text, color)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -10, 0, 17)
        lbl.Position = UDim2.new(0, 5, 0, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = color or Color3.fromRGB(200, 200, 200)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = settingsPanel
        return lbl
    end

    local lblPlayer  = makeLabel(28,  "👤 " .. player.Name,         Color3.fromRGB(255, 220, 100))
    local lblUptime  = makeLabel(46,  "⏱ Uptime: 00:00:00",         Color3.fromRGB(150, 220, 255))
    local lblSvTime  = makeLabel(64,  "🕐 Server: --:--:--",         Color3.fromRGB(150, 220, 255))
    local lblCredits = makeLabel(82,  "💰 Credits: ...",             Color3.fromRGB(100, 255, 150))
    local lblCph     = makeLabel(100, "📈 C/h: ...",                 Color3.fromRGB(100, 255, 150))

    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -10, 0, 1)
    div.Position = UDim2.new(0, 5, 0, 122)
    div.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    div.BorderSizePixel = 0
    div.Parent = settingsPanel

    makeLabel(128, "🔗 Webhook URL:", Color3.fromRGB(180, 180, 255))

    local webhookInput = Instance.new("TextBox")
    webhookInput.Size = UDim2.new(1, -10, 0, 26)
    webhookInput.Position = UDim2.new(0, 5, 0, 146)
    webhookInput.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    webhookInput.BorderSizePixel = 0
    webhookInput.Text = ""
    webhookInput.PlaceholderText = "Paste Discord webhook URL..."
    webhookInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    webhookInput.TextColor3 = Color3.fromRGB(220, 220, 255)
    webhookInput.TextSize = 9
    webhookInput.Font = Enum.Font.Gotham
    webhookInput.ClearTextOnFocus = false
    webhookInput.Parent = settingsPanel
    Instance.new("UICorner", webhookInput).CornerRadius = UDim.new(0, 5)

    webhookInput:GetPropertyChangedSignal("Text"):Connect(function()
        webhookUrl = webhookInput.Text
    end)

    -- Label + input on same row
    local intervalHeaderFrame = Instance.new("Frame")
    intervalHeaderFrame.Size = UDim2.new(1, -10, 0, 18)
    intervalHeaderFrame.Position = UDim2.new(0, 5, 0, 178)
    intervalHeaderFrame.BackgroundTransparency = 1
    intervalHeaderFrame.Parent = settingsPanel

    local intervalLabel = Instance.new("TextLabel")
    intervalLabel.Size = UDim2.new(1, -42, 1, 0)
    intervalLabel.BackgroundTransparency = 1
    intervalLabel.Text = "⏰ Every: " .. webhookInterval .. " min"
    intervalLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
    intervalLabel.TextSize = 11
    intervalLabel.Font = Enum.Font.Gotham
    intervalLabel.TextXAlignment = Enum.TextXAlignment.Left
    intervalLabel.Parent = intervalHeaderFrame

    local intervalInput = Instance.new("TextBox")
    intervalInput.Size = UDim2.new(0, 38, 1, 0)
    intervalInput.Position = UDim2.new(1, -38, 0, 0)
    intervalInput.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    intervalInput.BorderSizePixel = 0
    intervalInput.Text = tostring(webhookInterval)
    intervalInput.TextColor3 = Color3.fromRGB(220, 220, 255)
    intervalInput.TextSize = 11
    intervalInput.Font = Enum.Font.GothamBold
    intervalInput.TextXAlignment = Enum.TextXAlignment.Center
    intervalInput.ClearTextOnFocus = false
    intervalInput.Parent = intervalHeaderFrame
    Instance.new("UICorner", intervalInput).CornerRadius = UDim.new(0, 4)

    -- Slider track
    local sliderTrack = Instance.new("Frame")
    sliderTrack.Size = UDim2.new(1, -10, 0, 6)
    sliderTrack.Position = UDim2.new(0, 5, 0, 202)
    sliderTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
    sliderTrack.BorderSizePixel = 0
    sliderTrack.Parent = settingsPanel
    Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1, 0)

    local sliderFill = Instance.new("Frame")
    sliderFill.Size = UDim2.new((webhookInterval - 1) / 59, 0, 1, 0)
    sliderFill.BackgroundColor3 = Color3.fromRGB(80, 80, 200)
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderTrack
    Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)

    local sliderKnob = Instance.new("Frame")
    sliderKnob.Size = UDim2.new(0, 16, 0, 16)
    sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    sliderKnob.Position = UDim2.new((webhookInterval - 1) / 59, 0, 0.5, 0)
    sliderKnob.BackgroundColor3 = Color3.fromRGB(140, 140, 255)
    sliderKnob.BorderSizePixel = 0
    sliderKnob.ZIndex = 2
    sliderKnob.Parent = sliderTrack
    Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(1, 0)

    local function setInterval(val)
        val = math.clamp(math.round(val), 1, 60)
        webhookInterval = val
        local pct = (val - 1) / 59
        sliderFill.Size = UDim2.new(pct, 0, 1, 0)
        sliderKnob.Position = UDim2.new(pct, 0, 0.5, 0)
        intervalLabel.Text = "⏰ Every: " .. val .. " min"
        intervalInput.Text = tostring(val)
    end

    -- Drag slider - supports mouse and touch
    local UIS2 = game:GetService("UserInputService")
    local sliderDragging = false
    sliderKnob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            sliderDragging = true
        end
    end)
    sliderTrack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            sliderDragging = true
            local trackAbsPos = sliderTrack.AbsolutePosition.X
            local trackAbsSize = sliderTrack.AbsoluteSize.X
            local inputX = input.Position.X
            local pct = math.clamp((inputX - trackAbsPos) / trackAbsSize, 0, 1)
            setInterval(1 + pct * 59)
        end
    end)
    UIS2.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            sliderDragging = false
        end
    end)
    UIS2.InputChanged:Connect(function(input)
        if sliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local trackAbsPos = sliderTrack.AbsolutePosition.X
            local trackAbsSize = sliderTrack.AbsoluteSize.X
            local pct = math.clamp((input.Position.X - trackAbsPos) / trackAbsSize, 0, 1)
            setInterval(1 + pct * 59)
        end
    end)

    -- Text input sync
    intervalInput.FocusLost:Connect(function()
        local v = tonumber(intervalInput.Text)
        if v then setInterval(v) end
    end)

    -- 2 buttons: Test and Auto Send
    local autoSendEnabled = false

    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(0.48, -7, 0, 28)
    testBtn.Position = UDim2.new(0, 5, 0, 216)
    testBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
    testBtn.Text = "📡 Test"
    testBtn.TextColor3 = Color3.new(1,1,1)
    testBtn.TextSize = 11
    testBtn.Font = Enum.Font.GothamBold
    testBtn.BorderSizePixel = 0
    testBtn.Parent = settingsPanel
    Instance.new("UICorner", testBtn).CornerRadius = UDim.new(0, 6)

    local autoBtn = Instance.new("TextButton")
    autoBtn.Size = UDim2.new(0.52, -8, 0, 28)
    autoBtn.Position = UDim2.new(0.48, 3, 0, 216)
    autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    autoBtn.Text = "🔔 Auto: OFF"
    autoBtn.TextColor3 = Color3.new(1,1,1)
    autoBtn.TextSize = 10
    autoBtn.Font = Enum.Font.GothamBold
    autoBtn.BorderSizePixel = 0
    autoBtn.Parent = settingsPanel
    Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 6)

    local lblWebhookStatus = makeLabel(249, "", Color3.fromRGB(150, 255, 150))

    local function sendWebhook(isTest)
        if webhookUrl == "" then
            lblWebhookStatus.Text = "❌ No webhook URL!"
            return
        end
        local uptime = formatUptime(tick() - scriptStartTime)
        local credits = getCredits()
        local elapsed = tick() - scriptStartTime
        local deltaCredits = (credits and creditsAtStart) and (credits - creditsAtStart) or 0
        local cph = elapsed > 60 and math.floor(deltaCredits / elapsed * 3600) or 0

        local content = isTest
            and "🧪 **[FTF AUTO HACK] TEST**"
            or "📊 **[FTF AUTO HACK] Webhook**"
        content = content .. "\n👤 Player: **" .. player.Name .. "**"
        content = content .. "\n⏱ Uptime: **" .. uptime .. "**"
        content = content .. "\n💰 Credits: **" .. tostring(credits or "?") .. "C**"
        content = content .. "\n📈 Earned: **+" .. tostring(deltaCredits) .. "C** since start"
        content = content .. "\n⚡ C/h: **" .. tostring(cph) .. "C**"
        content = content .. "\n🕐 Server: **" .. getServerTime() .. "**"

        pcall(function()
            local body = game:GetService("HttpService"):JSONEncode({content = content})
            if request then
                request({
                    Url = webhookUrl,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = body
                })
            else
                game:GetService("HttpService"):PostAsync(webhookUrl, body, Enum.HttpContentType.ApplicationJson)
            end
            lblWebhookStatus.Text = isTest and "✅ Test sent!" or "✅ Sent!"
        end)
    end

    testBtn.MouseButton1Click:Connect(function()
        lblWebhookStatus.Text = "📡 Sending..."
        task.spawn(function() sendWebhook(true) end)
    end)

    autoBtn.MouseButton1Click:Connect(function()
        autoSendEnabled = not autoSendEnabled
        if autoSendEnabled then
            autoBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 50)
            autoBtn.Text = "🔔 Auto Send Webhook: ON"
            lblWebhookStatus.Text = "✅ Will send every " .. webhookInterval .. "m"
        else
            autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            autoBtn.Text = "🔔 Auto Send Webhook: OFF"
            lblWebhookStatus.Text = "🔕 Auto send off"
        end
    end)

    -- Auto webhook loop
    task.spawn(function()
        while true do
            task.wait(1)
            if not autoSendEnabled or webhookUrl == "" then continue end
            local elapsed = tick() - scriptStartTime
            if elapsed > 0 and elapsed % (webhookInterval * 60) < 1.5 then
                task.spawn(function() sendWebhook(false) end)
            end
        end
    end)

    -- Update stats loop
    task.spawn(function()
        task.wait(2)
        creditsAtStart = getCredits()
        while true do
            task.wait(1)
            if not settingsOpen then continue end
            local credits = getCredits()
            local elapsed = tick() - scriptStartTime
            local deltaCredits = (credits and creditsAtStart) and (credits - creditsAtStart) or 0
            local cph = elapsed > 60 and math.floor(deltaCredits / elapsed * 3600) or 0
            lblUptime.Text = "⏱ Uptime: " .. formatUptime(elapsed)
            lblSvTime.Text = "🕐 Server: " .. getServerTime()
            lblCredits.Text = "💰 Credits: " .. tostring(credits or "?")
            lblCph.Text = "📈 +" .. tostring(deltaCredits) .. "C  (" .. tostring(cph) .. "C/h)"
        end
    end)

    -- ===== BUTTONS =====
    toggleButton.MouseButton1Click:Connect(function()
        scriptEnabled = not scriptEnabled
        if scriptEnabled then
            toggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
            toggleButton.Text = "ON"
            hasEscaped = false
            log("Script ON")
        else
            toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            toggleButton.Text = "OFF"
            log("Script OFF")
        end
    end)

    checkButton.MouseButton1Click:Connect(function()
        hackExtraPC = not hackExtraPC
        checkmark.Visible = hackExtraPC
        checkbox.BackgroundColor3 = hackExtraPC and Color3.fromRGB(80, 40, 40) or Color3.fromRGB(60, 60, 60)
        checkbox.BorderColor3 = hackExtraPC and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(120, 120, 120)
        checkLabel.TextColor3 = hackExtraPC and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(180, 180, 180)
    end)

    gearBtn.MouseButton1Click:Connect(toggleSettings)

    -- Drag
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true dragStart = input.Position startPos = frame.Position
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            -- Follow settings panel if open
            if settingsOpen then
                local panelX, panelY = getSettingsPanelPos()
                settingsPanel.Position = UDim2.new(panelX, 0, panelY, 0)
            end
        end
    end)
end

-- ==================== ANTI AFK ====================
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

-- ==================== INIT ====================
updateCharacterReferences()
createHidePlatform()
createGUI()
antiAFK()
setupActionProgressTracking()
findBeast()
task.spawn(mainLoop)
