local player = game.Players.LocalPlayer
local Players = game:GetService("Players")
local Replicated = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CurrentMap = ReplicatedStorage:WaitForChild("CurrentMap")
local RunService = game:GetService("RunService")

local scriptEnabled = false
local hackExtraPC = false
local autointeracttoggle = true
local neverfailtoggle = true
local gameOver = false -- true khi beast out hoặc game kết thúc

local currentTrigger = nil
local currentPC = nil
local skippedPCs = {}
local isHacking = false
local hackedPCs = {}
local beast = nil
local pcLabels = {}
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
    log("Char refs updated")
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
                log("ActionProgress hook: TempPlayerStatsModule not found")
                return
            end
            local ap = tps:FindFirstChild("ActionProgress")
            if not ap or not ap:IsA("NumberValue") then
                log("ActionProgress hook: value not found")
                return
            end
            actionProgressConnection = ap:GetPropertyChangedSignal("Value"):Connect(function()
                pcall(function() currentActionProgress = ap.Value or 0 end)
            end)
            log("ActionProgress hooked OK")
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
    log("Reset game state (round=" .. roundsPlayed .. ")")
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
    autointeracttoggle = true

    if hidePlatform then
        pcall(function() hidePlatform:Destroy() end)
        hidePlatform = nil
    end
    createHidePlatform()
    updateCharacterReferences()
    updateStatus("Chờ game mới")
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
    log("Beast tracker started")

    task.spawn(function()
        while true do
            task.wait(0.3)

            if foundBeast then
                if not beast or not Players:FindFirstChild(beast.Name) or not isBeast(beast) then
                    log("Beast lost")
                    beast = nil
                    foundBeast = false
                    isHacking = false
                    currentPC = nil
                    canAutoJump = false
                    hasEscaped = false
                    gameOver = true -- dừng hackPC loop ngay

                    task.wait(3)
                    local gs = ReplicatedStorage:FindFirstChild("GameStatus")
                    local txt = gs and tostring(gs.Value):upper() or ""
                    if txt:find("HACK") or txt:find("HEAD START") or txt:find("FIND") then
                        log("Game still active → reset")
                        gameOver = false
                        resetGameState()
                    else
                        log("Game over/lobby → skip reset, wait for next round")
                    end
                end
            else
                for _, p in ipairs(Players:GetPlayers()) do
                    if isBeast(p) then
                        if p == player then
                            log("Mình là Beast → hop server!")
                            pcall(function()
                                game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
                            end)
                            return
                        end
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
                            log("No beast after 5s, game active → reset")
                            resetGameState()
                        else
                            log("No beast after 5s, game over → skip reset")
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
    updateStatus("Trốn Beast!")
    pcall(function()
        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local hum = char:FindFirstChild("Humanoid")
        if hum and hum.Sit then hum.Sit = false task.wait(0.1) end
        root.CFrame = CFrame.new(SAFE_POS)
    end)
    log("TP safe pos, waiting 10s")
    updateStatus("Ẩn náu 10s...")
    task.wait(10)
    -- Clear skip list để thử lại các PC bị skip do beast
    skippedPCs = {}
    log("Resume after beast escape, cleared skip list")
end

-- ==================== WAIT FOR GAME ====================
local function waitForGameActive()
    updateStatus("Chờ game bắt đầu...")
    local timeout = 300
    local elapsed = 0
    local lastLogTime = 0

    while elapsed < timeout do
        task.wait(0.5)
        elapsed = elapsed + 0.5

        -- Heartbeat log mỗi 30s
        if elapsed - lastLogTime >= 30 then
            log("Still waiting for game... " .. math.floor(elapsed) .. "s")
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
                log("HEAD START detected via GameStatusBox")
                task.wait(2)
                return true
            end
        end

        -- Fallback: GameStatus in ReplicatedStorage
        local gs = ReplicatedStorage:FindFirstChild("GameStatus")
        if gs then
            local txt = tostring(gs.Value):upper()
            -- Log giá trị GameStatus để debug (mỗi 5s thôi)
            if elapsed % 5 < 0.5 then
                log("GameStatus = \"" .. txt .. "\"")
            end
            if txt:find("HEAD START") or txt:find("HACK") then
                log("Game active via GameStatus: " .. txt)
                task.wait(1)
                return true
            end
        end
    end

    log("Timeout waitForGameActive")
    return false
end

-- ==================== ACTION BOX HOOK ====================
spawn(function()
    local playerGui = player:WaitForChild("PlayerGui")
    local function onActionBoxVisible(ab)
        ab:GetPropertyChangedSignal("Visible"):Connect(function()
            if ab.Visible then
                if (scriptEnabled and isHacking and currentPC) or autointeracttoggle then
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
    log("ActionBox hook bound")
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

    return nil -- cả 3 trigger đều có người → skip PC này
end

local function findAllPCs()
    local found = {}
    local map = CurrentMap.Value
    if not map then
        log("findAllPCs: map not found")
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
    log("Found " .. #found .. " PC(s)")
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
task.spawn(function()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local args = {...}
        if getnamecallmethod() == "FireServer"
            and args[1] == "SetPlayerMinigameResult"
            and neverfailtoggle then
            args[2] = true
            return old(self, unpack(args))
        end
        return old(self, ...)
    end)
    log("NeverFail hook active")
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
    log("hackPC start: PC" .. pcId .. " (" .. pcName .. ")")

    local chosenTrigger = getAvailableTrigger(pcData)
    if not chosenTrigger then
        log("PC" .. pcId .. ": no trigger found, skip")
        return false
    end

    log("PC" .. pcId .. ": TP to " .. chosenTrigger.Name)
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
        log("PC" .. pcId .. ": already done, skip anti-cheat delay")
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

        -- Log progress mỗi 10%
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
            updateStatus("Hack xong PC " .. pcId)
            hackedPCs[pcData.id] = true
            allPCs = findAllPCs()
            isHacking = false
            currentPC = nil
            canAutoJump = false
            currentTrigger = nil

            pcall(function()
                local char = player.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        char:PivotTo(CFrame.new(SAFE_POS))
                        log("TP to safe pos")
                    end
                end
            end)

            if skipAnti then
                log("Skip anti-cheat delay (PC was already done)")
                return true
            end

            -- Kiểm tra còn PC nào chưa hack không
            -- Nếu đây là PC cuối thì skip delay để tp exit luôn
            local remaining = 0
            for _, pc in ipairs(allPCs) do
                if not hackedPCs[pc.id] then remaining += 1 end
            end
            if remaining == 0 then
                log("Last PC done → skip anti-cheat delay, go exit!")
                return true
            end

            log("Anti-cheat delay: " .. delayAfterHack .. "s")
            updateStatus("Anti-cheat delay " .. delayAfterHack .. "s...")
            task.wait(delayAfterHack)
            return true
        end

        lastProgress = prog
    end

    log("PC" .. pcId .. ": hackPC loop ended (done=" .. tostring(hackedPCs[pcData.id]) .. ")")
    isHacking = false
    currentPC = nil
    canAutoJump = false
    currentTrigger = nil
    return false
end

-- ==================== ESP ====================
local function getPCPart(pc)
    local scr = pc:FindFirstChild("Screen")
    if scr and scr:IsA("BasePart") then return scr end
    for _, d in ipairs(pc:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
end

local function showPCPercent(pc, percent)
    if not pc then return end
    percent = math.clamp(math.floor(percent * 100 + 0.5), 0, 100)
    local part = getPCPart(pc)
    if not part then return end
    local bb = pcLabels[pc]
    if not bb then
        bb = Instance.new("BillboardGui")
        bb.Name = "PCProgressBB"
        bb.Size = UDim2.new(0, 60, 0, 25)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = part
        bb.Parent = part
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.Font = Enum.Font.GothamBold
        tl.TextScaled = true
        tl.TextColor3 = Color3.new(1, 1, 1)
        tl.Parent = bb
        pcLabels[pc] = bb
    end
    bb.TextLabel.Text = percent >= 100 and "DONE" or (percent .. "%")
    if percent >= 100 then bb.TextLabel.TextColor3 = Color3.new(0, 1, 0) end
end

local function hookProgress(plr)
    task.spawn(function()
        local tps = plr:WaitForChild("TempPlayerStatsModule", 15)
        if not tps then return end
        local ap = tps:WaitForChild("ActionProgress", 15)
        local anim = tps:WaitForChild("CurrentAnimation", 15)
        if not ap or not anim then return end
        ap:GetPropertyChangedSignal("Value"):Connect(function()
            if anim.Value ~= "Typing" then return end
            local char = plr.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local mapVal = Replicated:FindFirstChild("CurrentMap")
            local map = mapVal and mapVal.Value
            if not map then return end
            local nearestPC, dist = nil, 35
            for _, d in ipairs(map:GetDescendants()) do
                if d.Name == "ComputerTable" then
                    local part = getPCPart(d)
                    if part then
                        local mag = (part.Position - hrp.Position).Magnitude
                        if mag < dist then dist = mag nearestPC = d end
                    end
                end
            end
            if nearestPC then showPCPercent(nearestPC, ap.Value) end
        end)
    end)
end

if Players.LocalPlayer then hookProgress(Players.LocalPlayer) end

task.spawn(function()
    while true do
        task.wait(1)
        local mapVal = Replicated:FindFirstChild("CurrentMap")
        local map = mapVal and mapVal.Value
        if not map then continue end
        for _, d in ipairs(map:GetDescendants()) do
            if d.Name == "ComputerTable" then
                if not pcLabels[d] then showPCPercent(d, 0) end
                local scr = d:FindFirstChild("Screen")
                if scr and scr:IsA("BasePart") then
                    scr:GetPropertyChangedSignal("Color"):Connect(function()
                        if scr.Color.G > scr.Color.R + 0.2 and scr.Color.G > scr.Color.B + 0.2 then
                            showPCPercent(d, 1)
                        end
                    end)
                end
            end
        end
    end
end)

-- ==================== AUTO EXIT ====================
local function autoExitUnified()
    log("autoExitUnified start")
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
        -- Cách 1: check transparency
        local door = exitData.model:FindFirstChild("Door")
        if door and door:IsA("BasePart") then
            if door.Transparency > 0.5 then return true end
        end
        -- Cách 2: check CanCollide = false (cửa mở thường tắt collision)
        if door and door:IsA("BasePart") then
            if not door.CanCollide then return true end
        end
        return false
    end

    -- Track position để detect animation cửa đang mở
    local function waitForDoorOpen(exitData, timeoutSecs)
        timeoutSecs = timeoutSecs or 20
        local waited = 0
        local beastInterrupted = false

        while waited < timeoutSecs do
            task.wait(0.2)
            waited = waited + 0.2

            if isBeastNearby(40) then
                log("Beast came while waiting door → try other exit")
                beastInterrupted = true
                break
            end

            -- Check ActionProgress của bản thân
            local tps = player:FindFirstChild("TempPlayerStatsModule")
            local ap = tps and tps:FindFirstChild("ActionProgress")
            local prog = ap and ap.Value or 0
            local pct = math.floor(prog * 100)
            if pct > 0 and pct % 10 == 0 then
                log("Door progress: " .. pct .. "%")
            end
            if prog >= 0.999 then
                log("Door opened! (ActionProgress=100%)")
                task.wait(0.5)
                return true, false
            end

            -- Fallback: check visual
            if isExitOpened(exitData) then
                log("Door opened! (visual check)")
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
        log("TP safe before escape")
        root.CFrame = CFrame.new(50, 73, 50)
        task.wait(3)
        log("TP into ExitArea")
        autointeracttoggle = false
        root.CFrame = exitData.area.CFrame + Vector3.new(0, 2, 0)
        task.wait(1.5)

        local waitTime = 0
        while waitTime < 10 do
            task.wait(0.2)
            waitTime = waitTime + 0.2
            if hasPlayerEscaped() then
                log("Escaped confirmed by game!")
                hasEscaped = true
                return
            end
        end
        log("Escape timeout, assuming done")
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
                log("Fired RemoteEvent Action for exit")
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
                log("Skip already-used exit")
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
                    log("Opening exit...")
                    tpFront(exitData.trigger)
                    task.wait(0.2)
                    local success = startOpening(exitData.trigger)
                    if success then
                        log("Waiting for door to open...")
                        -- Tiếp tục fire action trong lúc chờ
                        task.spawn(function()
                            while not hasEscaped do
                                task.wait(0.15)
                                pcall(function()
                                    local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                                    if r then r:FireServer("Input", "Action", true) end
                                end)
                            end
                        end)
                        local opened, beastInterrupted = waitForDoorOpen(exitData, 20)
                        if beastInterrupted then
                            log("Beast interrupted, try other exit")
                        elseif opened then
                            log("Door opened! Escaping...")
                            escape(exitData)
                            lastExitUsed = exitData.model
                            break
                        else
                            log("Door didn't open after 20s, try next exit")
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
    log("mainLoop started")

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
            log("No PCs found, wait 3s")
            updateStatus("Không có PC")
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
                        log("Find Exit phase but Extra ON, continue")
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
                        log("PC" .. pcId .. " already done (color)")
                        hackedPCs[pcId] = true
                    else
                        allCompleted = false
                        hackPC(pcData)
                    end
                end
            end

            totalAttempts = totalAttempts + 1
            log("Attempt " .. totalAttempts .. "/" .. maxAttempts)

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

        -- Đợi Find Exit
        updateStatus("Đợi Find Exit...")
        log("Waiting for Find Exit phase...")
        local waitStart = tick()
        repeat task.wait(0.5) until isFindExitPhase() or (tick() - waitStart > 30) or not scriptEnabled

        if not scriptEnabled then continue end

        if isFindExitPhase() then
            log("Find Exit detected!")
            updateStatus("Auto Exit bắt đầu!")
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
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoHackGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 120)
    frame.Position = UDim2.new(0.5, -100, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 255, 255)
    frame.Parent = screenGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 25)
    title.BackgroundTransparency = 1
    title.Text = "AUTO HACK FTF"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 160, 0, 35)
    toggleButton.Position = UDim2.new(0.5, -80, 0, 30)
    toggleButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    toggleButton.Text = "TẮT"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 16
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.Parent = frame
    Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 6)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -10, 0, 18)
    status.Position = UDim2.new(0, 5, 0, 70)
    status.BackgroundTransparency = 1
    status.Text = "Status: Chờ bật..."
    status.TextColor3 = Color3.fromRGB(150, 220, 150)
    status.TextSize = 10
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextWrapped = true
    status.Parent = frame
    statusLabel = status

    local checkboxFrame = Instance.new("Frame")
    checkboxFrame.Size = UDim2.new(0, 160, 0, 20)
    checkboxFrame.Position = UDim2.new(0.5, -80, 0, 95)
    checkboxFrame.BackgroundTransparency = 1
    checkboxFrame.Parent = frame

    local checkbox = Instance.new("Frame")
    checkbox.Size = UDim2.new(0, 16, 0, 16)
    checkbox.Position = UDim2.new(0, 0, 0.5, -8)
    checkbox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    checkbox.BorderSizePixel = 1
    checkbox.BorderColor3 = Color3.fromRGB(120, 120, 120)
    checkbox.Parent = checkboxFrame
    Instance.new("UICorner", checkbox).CornerRadius = UDim.new(0, 3)

    local checkmark = Instance.new("TextLabel")
    checkmark.Size = UDim2.new(1, 0, 1, 0)
    checkmark.BackgroundTransparency = 1
    checkmark.Text = "✓"
    checkmark.TextColor3 = Color3.fromRGB(255, 80, 80)
    checkmark.TextSize = 14
    checkmark.Font = Enum.Font.GothamBold
    checkmark.Visible = false
    checkmark.Parent = checkbox

    local checkLabel = Instance.new("TextLabel")
    checkLabel.Size = UDim2.new(1, -20, 1, 0)
    checkLabel.Position = UDim2.new(0, 22, 0, 0)
    checkLabel.BackgroundTransparency = 1
    checkLabel.Text = "Hack Extra PC"
    checkLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    checkLabel.TextSize = 11
    checkLabel.Font = Enum.Font.Gotham
    checkLabel.TextXAlignment = Enum.TextXAlignment.Left
    checkLabel.Parent = checkboxFrame

    local checkButton = Instance.new("TextButton")
    checkButton.Size = UDim2.new(1, 0, 1, 0)
    checkButton.BackgroundTransparency = 1
    checkButton.Text = ""
    checkButton.Parent = checkboxFrame

    toggleButton.MouseButton1Click:Connect(function()
        scriptEnabled = not scriptEnabled
        if scriptEnabled then
            toggleButton.BackgroundColor3 = Color3.fromRGB(50, 220, 50)
            toggleButton.Text = "BẬT"
            hasEscaped = false
            log("Script ON")
        else
            toggleButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
            toggleButton.Text = "TẮT"
            log("Script OFF")
        end
    end)

    checkButton.MouseButton1Click:Connect(function()
        hackExtraPC = not hackExtraPC
        if hackExtraPC then
            checkmark.Visible = true
            checkbox.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
            checkbox.BorderColor3 = Color3.fromRGB(255, 80, 80)
            checkLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
            log("Extra PC ON")
        else
            checkmark.Visible = false
            checkbox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            checkbox.BorderColor3 = Color3.fromRGB(120, 120, 120)
            checkLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
            log("Extra PC OFF")
        end
    end)

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
            log("Anti-AFK triggered")
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
log("=== AUTO HACK FTF LOADED ===")
updateCharacterReferences()
createHidePlatform()
createGUI()
antiAFK()
setupActionProgressTracking()
findBeast()
task.spawn(mainLoop)
log("Ready!")
