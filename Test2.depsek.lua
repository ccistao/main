-- ==========================================================
-- SERVICES
-- ==========================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

-- ==========================================================
-- CONFIG
-- ==========================================================
local Config = {
    beastDangerDistance = 30,
    exitDangerDistance = 35,
    hackTick = 0.15,
    doorTimeout = 20,
    saveTimeout = 3,
    jumpInterval = 4,
    tweenSpeed = 35, -- studs/s
    maxPCAttempts = 3,
    maxSavesPerRound = 1,
}

-- ==========================================================
-- STATE (trung tâm)
-- ==========================================================
local State = {
    enabled = false,
    round = 0,
    phase = "Idle", -- "Idle", "HeadStart", "Hacking", "Exit", "Ended"
    isMoving = false,
    isHacking = false,
    isSaving = false,
    isBeast = false,
    gameOver = false,
    hasEscaped = false,
    foundBeast = false,
    skipCurrentPC = false,

    -- Player refs
    character = nil,
    humanoid = nil,
    rootPart = nil,

    -- PC tracking
    currentPC = nil,
    currentTrigger = nil,
    hackedPCs = {},
    skippedPCs = {},
    allPCs = {},

    -- Beast
    beast = nil,

    -- Save
    savesThisRound = 0,

    -- Movement lock
    movementLock = false,
}

-- ==========================================================
-- LOGGER
-- ==========================================================
local function log(msg)
    print("[FTF] " .. tostring(msg))
end

local function logState(msg)
    log("[STATE] " .. tostring(msg))
end

local function logError(msg)
    warn("[FTF-ERROR] " .. tostring(msg))
end
-- ==========================================================
-- GAME PHASE SYSTEM
-- ==========================================================
local GamePhase = {}

function GamePhase.get()
    -- Method 1: GameStatus
    local gs = ReplicatedStorage:FindFirstChild("GameStatus")
    if gs then
        local txt = tostring(gs.Value):upper()
        if txt ~= "" then
            if txt:find("GAME OVER") or txt:find("BEAST LEFT") or txt:find("KET THUC") then
                return "Ended"
            end
            if txt:find("HEAD START") then return "HeadStart" end
            if txt:find("FIND") and txt:find("EXIT") then return "Exit" end
            if txt:find("HACK") then return "Hacking" end
        end
    end

    -- Method 2: GameStatusBox (fallback)
    local ok, gsb = pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        local sg = pg and pg:FindFirstChild("ScreenGui")
        local gif = sg and sg:FindFirstChild("GameInfoFrame")
        return gif and gif:FindFirstChild("GameStatusBox")
    end)

    if ok and gsb and gsb.Text then
        local txt = gsb.Text:upper()
        if txt:find("FIND") and txt:find("EXIT") then return "Exit" end
        if txt:find("HACK") then return "Hacking" end
        if txt:find("15 SEC HEAD START") or txt:find("GIAY") then return "HeadStart" end
    end

    -- Method 3: Check Computers Left
    local cl = player:FindFirstChild("PlayerGui")
    if cl then
        local clText = cl:FindFirstChild("ComputersLeft")
        if clText and tonumber(clText.Text) and tonumber(clText.Text) > 0 then
            return "Hacking"
        end
    end

    return "Idle"
end

function GamePhase.isActive()
    local phase = GamePhase.get()
    return phase == "Hacking" or phase == "Exit" or phase == "HeadStart"
end

function GamePhase.isHacking()
    return GamePhase.get() == "Hacking"
end

function GamePhase.isExit()
    return GamePhase.get() == "Exit"
end

function GamePhase.isHeadStart()
    return GamePhase.get() == "HeadStart"
end

function GamePhase.isEnded()
    return GamePhase.get() == "Ended"
end

function GamePhase.waitForRoundStart(timeout)
    timeout = timeout or 300
    local elapsed = 0
    while elapsed < timeout do
        task.wait(0.5)
        elapsed = elapsed + 0.5
        local phase = GamePhase.get()
        if phase == "HeadStart" then
            task.wait(2)
            return true
        elseif phase == "Hacking" then
            return true
        end
    end
    return false
end
-- ==========================================================
-- CHARACTER SYSTEM
-- ==========================================================
local Character = {}
local player = Players.LocalPlayer

function Character.update()
    State.character = player.Character or player.CharacterAdded:Wait()
    State.humanoid = State.character:WaitForChild("Humanoid")
    State.rootPart = State.character:WaitForChild("HumanoidRootPart")
    return State.character
end

function Character.getRoot()
    if not State.rootPart or not State.rootPart.Parent then
        Character.update()
    end
    return State.rootPart
end

function Character.getHumanoid()
    if not State.humanoid or not State.humanoid.Parent then
        Character.update()
    end
    return State.humanoid
end

function Character.getStats()
    return player:FindFirstChild("TempPlayerStatsModule")
end

function Character.getCredits()
    local stats = player:FindFirstChild("SavedPlayerStatsModule")
    if stats then
        local c = stats:FindFirstChild("Credits")
        if c then return c.Value end
    end
    return nil
end

function Character.getActionProgress()
    local stats = Character.getStats()
    if not stats then return 0 end
    local p = stats:FindFirstChild("ActionProgress")
    if p and (p:IsA("IntValue") or p:IsA("NumberValue")) then
        return p.Value
    end
    return 0
end

function Character.isBeast()
    local stats = Character.getStats()
    if not stats then return false end
    local flag = stats:FindFirstChild("IsBeast")
    return flag and flag.Value == true
end

function Character.hasEscaped()
    local stats = Character.getStats()
    if not stats then return false end
    local flag = stats:FindFirstChild("Escaped")
    return flag and flag.Value == true
end
-- ==========================================================
-- MOVEMENT SYSTEM
-- ==========================================================
local Movement = {}
local connectionPool = {}

function Movement.addConnection(conn)
    table.insert(connectionPool, conn)
    return conn
end

function Movement.cleanup()
    for _, conn in ipairs(connectionPool) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connectionPool)
end

function Movement.moveTo(targetPos, speed)
    speed = speed or Config.tweenSpeed

    if State.movementLock then
        log("Movement locked, skipping")
        return false
    end

    local root = Character.getRoot()
    if not root then return false end

    State.movementLock = true
    State.isMoving = true

    -- Noclip
    local noclipActive = true
    local noclipConn = RunService.Stepped:Connect(function()
        if not noclipActive then return end
        local c = player.Character
        if not c then return end
        for _, part in pairs(c:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    Movement.addConnection(noclipConn)

    -- Freeze humanoid
    local hum = Character.getHumanoid()
    if hum then
        hum.PlatformStand = true
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end

    -- Move
    local STOP_DIST = math.max(0.5, speed * 0.05 * 0.8)
    local startPos = root.Position
    local diff = targetPos - startPos
    local totalDist = diff.Magnitude

    if totalDist > 0 then
        local steps = math.ceil(totalDist / (speed * 0.05))
        for i = 1, steps do
            task.wait(0.05)
            if not root or not root.Parent then break end
            local currentDiff = targetPos - root.Position
            if currentDiff.Magnitude <= STOP_DIST then
                root.CFrame = CFrame.new(targetPos)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                break
            end
            root.AssemblyLinearVelocity = currentDiff.Unit * speed
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end

    -- Final snap
    if root and root.Parent then
        root.CFrame = CFrame.new(targetPos)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    -- Disable noclip
    noclipActive = false
    noclipConn:Disconnect()

    -- Unfreeze
    if hum then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end

    State.isMoving = false
    State.movementLock = false

    return true
end

-- U-shape move (down -> across -> up)
function Movement.moveToTriggerU(trigger)
    local root = Character.getRoot()
    if not root then return false end

    local myPos = root.Position
    local targetPos = trigger.Position + Vector3.new(0, 0.5, 0)

    local posDown = Vector3.new(myPos.X, myPos.Y - 50, myPos.Z)
    local posAcross = Vector3.new(targetPos.X, myPos.Y - 50, targetPos.Z)
    local posUp = targetPos

    if not Movement.moveTo(posDown, Config.tweenSpeed) then return false end
    task.wait(0.05)
    if not Movement.moveTo(posAcross, math.max(10, Config.tweenSpeed * 0.7)) then return false end
    task.wait(0.05)
    if not Movement.moveTo(posUp, Config.tweenSpeed) then return false end

    return true
end

-- Straight move (dùng khi chuyển trigger trong cùng PC)
function Movement.moveToTriggerStraight(trigger)
    local targetPos = trigger.Position + Vector3.new(0, 0.5, 0)
    return Movement.moveTo(targetPos, Config.tweenSpeed)
end
-- ==========================================================
-- PC SYSTEM
-- ==========================================================
local PCSystem = {}

-- Tìm tất cả PC trên map
function PCSystem.findAll()
    local found = {}
    local map = ReplicatedStorage:FindFirstChild("CurrentMap")
    if not map or not map.Value then return found end
    map = map.Value

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

-- Kiểm tra PC đã hoàn thành chưa
function PCSystem.isCompleted(pcData)
    if not pcData or not pcData.computer then return false end

    -- Check by screen color
    local screen = pcData.computer:FindFirstChild("Screen")
    if screen and screen:IsA("BasePart") then
        local c = screen.Color
        if c.G > c.R + 0.2 and c.G > c.B + 0.2 then return true end
    end

    -- Check by progress values
    local maxValue = 0
    for _, v in ipairs(pcData.computer:GetDescendants()) do
        if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
            local val = tonumber(v.Value) or 0
            if (v.Name == "ActionProgress" or v.Name == "Value") and val > maxValue then
                maxValue = val
            end
        end
    end
    return maxValue >= 1
end

-- Tìm trigger còn trống
function PCSystem.findAvailableTrigger(pcData)
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
    return nil
end

-- Fire interact tại trigger
function PCSystem.fireInteract(trigger)
    local root = Character.getRoot()
    if not root or not trigger then return end

    pcall(function()
        firetouchinterest(root, trigger, 0)
        task.wait(0.1)
        firetouchinterest(root, trigger, 1)
    end)
    task.wait(0.2)

    pcall(function()
        local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
        if r then
            r:FireServer("Input", "Action", true)
            task.wait(0.1)
            r:FireServer("Input", "Action", true)
        end
    end)
end

-- Fire action liên tục trong thời gian nhất định
function PCSystem.spamAction(duration)
    duration = duration or 1
    local elapsed = 0
    while elapsed < duration do
        task.wait(0.1)
        elapsed = elapsed + 0.1
        pcall(function()
            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if r then r:FireServer("Input", "Action", true) end
        end)
    end
end

-- Hack một PC
function PCSystem.hack(pcData)
    if not pcData or not pcData.computer then return false end

    local pcId = tostring(pcData.id)
    local pcName = pcData.computer.Name or "Unknown"

    -- Check already done
    if PCSystem.isCompleted(pcData) then
        State.hackedPCs[pcData.id] = true
        log("PC" .. pcId .. ": already done, skip")
        return true
    end

    -- Check if in exit phase and not extra hack
    if GamePhase.isExit() and not State.hackExtraPC then
        log("PC" .. pcId .. ": Exit phase, skip")
        return false
    end

    -- Find usable trigger
    local chosenTrigger = nil
    local triggerIndex = 0

    for i, trigger in ipairs(pcData.triggers) do
        triggerIndex = i

        -- Move to trigger
        if triggerIndex == 1 then
            Movement.moveToTriggerU(trigger)
        else
            Movement.moveToTriggerStraight(trigger)
        end

        State.currentTrigger = trigger
        State.canAutoJump = true

        -- Fire interact
        PCSystem.fireInteract(trigger)

        -- Spam action
        PCSystem.spamAction(1)

        -- Check if progress increases
        local progressBefore = Character.getActionProgress()
        task.wait(0.2)
        local progressAfter = Character.getActionProgress()

        if progressAfter > progressBefore + 0.001 then
            chosenTrigger = trigger
            log("PC" .. pcId .. ": trigger " .. i .. " works")
            break
        else
            log("PC" .. pcId .. ": trigger " .. i .. " no response")
            State.canAutoJump = false
            State.currentTrigger = nil
        end
    end

    if not chosenTrigger then
        log("PC" .. pcId .. ": all triggers failed, skip")
        State.canAutoJump = false
        State.currentTrigger = nil
        return false
    end

    -- Start hacking
    State.isHacking = true
    State.currentPC = pcData
    State.currentTrigger = chosenTrigger

    local lastProgress = 0
    local stuckCount = 0
    local lastLoggedPct = -1

    while State.isHacking and State.enabled and not State.gameOver do
        task.wait(Config.hackTick)

        -- Check game phase
        if not GamePhase.isActive() then
            log("Game ended mid-hack, stopping")
            break
        end

        -- Check beast nearby
        if BeastController.isNearby(Config.beastDangerDistance) then
            log("Beast nearby, aborting PC" .. pcId)
            State.isHacking = false
            State.canAutoJump = false
            State.currentTrigger = nil
            State.currentPC = nil
            State.skipCurrentPC = true
            State.skippedPCs[pcData.id] = true
            return false
        end

        -- Fire action
        pcall(function()
            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if r then r:FireServer("Input", "Action", true) end
        end)

        -- Check progress
        local prog = Character.getActionProgress()

        -- Log every 10%
        local pct = math.floor(prog * 100)
        if pct ~= lastLoggedPct and pct % 10 == 0 and pct > 0 then
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

        -- Skill check handling
        if pcData.computer:FindFirstChild("SkillCheckActive")
            and pcData.computer.SkillCheckActive.Value then
            log("PC" .. pcId .. ": SkillCheck active")
            pcall(function()
                local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
                if r then r:FireServer("SkillCheck", true) end
            end)
        end

        -- Check completion
        if PCSystem.isCompleted(pcData) or prog >= 0.999 then
            log("PC" .. pcId .. ": DONE!")
            State.hackedPCs[pcData.id] = true
            State.canAutoJump = false
            State.currentTrigger = nil
            State.isHacking = false
            State.currentPC = nil
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

-- Process tất cả PC
function PCSystem.processAll()
    State.allPCs = PCSystem.findAll()
    if #State.allPCs == 0 then
        log("No PCs found")
        return false
    end

    local totalAttempts = 0
    local maxAttempts = #State.allPCs * Config.maxPCAttempts

    while totalAttempts < maxAttempts and State.enabled do
        if not GamePhase.isHacking() then break end

        local hasSkippedPC = false
        local allCompleted = true

        for _, pcData in ipairs(State.allPCs) do
            if not State.enabled then break end
            if not GamePhase.isHacking() then break end
            if GamePhase.isExit() and not State.hackExtraPC then break end

            -- Check beast
            if BeastController.isNearby(Config.beastDangerDistance) then
                log("Beast nearby, pausing PC loop")
                BeastController.waitForLeave(Config.exitDangerDistance)
                -- Reset skip list after beast leaves
                State.skippedPCs = {}
                allCompleted = false
                break
            end

            local pcId = pcData.id

            if State.hackedPCs[pcId] then
                -- Already done
            elseif State.skippedPCs[pcId] then
                hasSkippedPC = true
            else
                if PCSystem.isCompleted(pcData) then
                    State.hackedPCs[pcId] = true
                else
                    allCompleted = false
                    PCSystem.hack(pcData)
                end
            end
        end

        totalAttempts = totalAttempts + 1

        if allCompleted then
            log("All PCs done!")
            break
        end

        if hasSkippedPC then
            local remaining = 0
            for id, _ in pairs(State.skippedPCs) do
                if not State.hackedPCs[id] then remaining = remaining + 1 end
            end
            if remaining > 0 then
                task.wait(3)
            else
                break
            end
        end
    end

    return true
end
-- ==========================================================
-- BEAST CONTROLLER
-- ==========================================================
local BeastController = {}

function BeastController.isBeast(plr)
    if not plr then return false end
    local stats = plr:FindFirstChild("TempPlayerStatsModule")
    if not stats then return false end
    local flag = stats:FindFirstChild("IsBeast")
    return flag and flag.Value == true
end

function BeastController.find()
    for _, p in ipairs(Players:GetPlayers()) do
        if BeastController.isBeast(p) then
            State.beast = p
            State.foundBeast = true
            return p
        end
    end
    State.beast = nil
    State.foundBeast = false
    return nil
end

function BeastController.getDistance()
    local root = Character.getRoot()
    if not root or not State.foundBeast or not State.beast or not State.beast.Character then
        return math.huge
    end
    local br = State.beast.Character:FindFirstChild("HumanoidRootPart")
        or State.beast.Character:FindFirstChild("UpperTorso")
        or State.beast.Character:FindFirstChild("Torso")
    if not br then return math.huge end
    return (root.Position - br.Position).Magnitude
end

function BeastController.isNearby(distance)
    distance = distance or Config.beastDangerDistance
    return BeastController.getDistance() <= distance
end

function BeastController.waitForLeave(distance)
    distance = distance or Config.exitDangerDistance
    log("Waiting for beast to leave...")
    local elapsed = 0
    while State.enabled do
        if not BeastController.isNearby(distance) then
            log("Beast left!")
            return true
        end
        task.wait(0.5)
        elapsed = elapsed + 0.5
        if elapsed > 30 then
            log("Beast wait timeout")
            return false
        end
    end
    return false
end

-- ==========================================================
-- BEAST SURVIVOR LOGIC (survivor mode)
-- ==========================================================
local BeastSurvivor = {}

function BeastSurvivor.handleBeastNearby()
    if BeastController.isNearby(Config.beastDangerDistance) then
        log("Beast nearby! Moving to next PC...")
        State.skipCurrentPC = true
        if State.currentPC and State.currentPC.id then
            State.skippedPCs[State.currentPC.id] = true
        end
        State.isHacking = false
        State.canAutoJump = false
        State.currentPC = nil
        State.currentTrigger = nil
        return true
    end
    return false
end

-- ==========================================================
-- BEAST MODE LOGIC (beast player)
-- ==========================================================
local BeastMode = {}

function BeastMode.getHammerEvent()
    local char = player.Character
    local hammer = char and char:FindFirstChild("Hammer")
    return hammer and hammer:FindFirstChild("HammerEvent")
end

function BeastMode.getNearestSurvivor()
    local root = Character.getRoot()
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local torso = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if hum and torso then
                -- Check if captured
                local captured = false
                local map = ReplicatedStorage:FindFirstChild("CurrentMap")
                map = map and map.Value
                if map then
                    for _, v in ipairs(map:GetChildren()) do
                        if v.Name == "FreezePod" then
                            local ct = v:FindFirstChild("CapturedTorso", true)
                            if ct and ct.Value == torso then captured = true break end
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

function BeastMode.getNearestRagdoll()
    local root = Character.getRoot()
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

function BeastMode.getNearestEmptyCage()
    local root = Character.getRoot()
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

function BeastMode.runRound()
    log("Beast mode active")
    while State.enabled and Character.isBeast() and GamePhase.isActive() do
        task.wait(0.1)

        local remote = BeastMode.getHammerEvent()
        if not remote then continue end

        local root = Character.getRoot()
        if not root then continue end

        -- If has rope -> cage
        local ropeCheck = player.Character:FindFirstChild("RopeConstraint", true)
        if ropeCheck then
            local cage = BeastMode.getNearestEmptyCage()
            if not cage then
                log("No empty cage!")
                continue
            end
            local trigger = cage:FindFirstChild("PodTrigger", true)
            if not trigger then continue end

            local cageCenter = cage:GetModelCFrame().Position
            local dirIn = (cageCenter - trigger.Position)
            if dirIn.Magnitude > 0 then dirIn = dirIn.Unit * 3 else dirIn = Vector3.zero end
            local cagePos = Vector3.new(trigger.Position.X + dirIn.X, trigger.Position.Y, trigger.Position.Z + dirIn.Z)

            -- Move to cage
            Movement.moveTo(cagePos, Config.tweenSpeed)

            -- Interact
            local t = 0
            while t < 3 do
                pcall(function() firetouchinterest(root, trigger, 0) task.wait(0.03) firetouchinterest(root, trigger, 1) end)
                pcall(function() local r = ReplicatedStorage:FindFirstChild("RemoteEvent") if r then r:FireServer("Input", "Action", true) end end)
                local ct = cage:FindFirstChild("CapturedTorso", true)
                if ct and ct.Value ~= nil then break end
                task.wait(0.15)
                t = t + 0.18
            end
            continue
        end

        -- Find ragdoll -> rope
        local ragdollTarget = BeastMode.getNearestRagdoll()
        if ragdollTarget and ragdollTarget.Character then
            local torso = ragdollTarget.Character:FindFirstChild("UpperTorso") or ragdollTarget.Character:FindFirstChild("Torso")
            if torso then
                local dir = (root.Position - torso.Position)
                dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0,0,1)
                Movement.moveTo(torso.Position + dir * 1, Config.tweenSpeed)
                task.wait(0.03)
                local ropeTimer = 0
                while ropeTimer < 2 do
                    remote:FireServer("HammerTieUp", torso, torso.Position)
                    local rope = player.Character and player.Character:FindFirstChild("RopeConstraint", true)
                    if rope then break end
                    task.wait(0.15)
                    ropeTimer = ropeTimer + 0.15
                end
                continue
            end
        end

        -- Find survivor -> hit
        local target = BeastMode.getNearestSurvivor()
        if not target or not target.Character then
            task.wait(1)
            continue
        end
        local torso = target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Torso")
        if not torso then continue end
        local hum = target.Character:FindFirstChild("Humanoid")
        if hum and hum.PlatformStand then continue end

        local dir = (root.Position - torso.Position)
        dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0,0,1)
        Movement.moveTo(torso.Position + dir * 1, Config.tweenSpeed)
        task.wait(0.03)
        local hitTimer = 0
        while hitTimer < 2 do
            if not target.Character then break end
            local h = target.Character:FindFirstChild("Humanoid")
            if h and h.PlatformStand then break end
            remote:FireServer("HammerClick", true)
            task.wait(0.02)
            remote:FireServer("HammerHit", torso)
            task.wait(0.15)
            hitTimer = hitTimer + 0.17
        end
    end
end
-- ==========================================================
-- EXIT CONTROLLER
-- ==========================================================
local ExitController = {}
local lastExitUsed = nil

-- Tìm tất cả exit door
function ExitController.findAll()
    local exits = {}
    local map = ReplicatedStorage:FindFirstChild("CurrentMap")
    map = map and map.Value
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

-- Kiểm tra exit đã mở chưa
function ExitController.isOpened(exitData)
    local door = exitData.model:FindFirstChild("Door")
    if door and door:IsA("BasePart") then
        if door.Transparency > 0.5 then return true end
        if not door.CanCollide then return true end
    end
    return false
end

-- Tìm player khác đang mở exit
function ExitController.getPlayerOpening(exitData)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - exitData.trigger.Position).Magnitude <= 8 then
                return p
            end
        end
    end
    return nil
end

-- Lấy progress mở door của player
function ExitController.getOpenProgress(plr)
    local tps = plr:FindFirstChild("TempPlayerStatsModule")
    local ap = tps and tps:FindFirstChild("ActionProgress")
    return ap and ap.Value or 0
end

-- Đợi door mở
function ExitController.waitForOpen(exitData, timeoutSecs)
    timeoutSecs = timeoutSecs or Config.doorTimeout
    local waited = 0

    while waited < timeoutSecs do
        task.wait(0.2)
        waited = waited + 0.2

        if BeastController.isNearby(Config.exitDangerDistance) then
            log("Beast near door -> try other exit")
            return false, true -- beast interrupted
        end

        -- Check visual
        if ExitController.isOpened(exitData) then
            log("Door opened! (visual)")
            return true, false
        end

        -- Check progress
        local otherOpener = ExitController.getPlayerOpening(exitData)
        local prog = 0
        if otherOpener then
            prog = ExitController.getOpenProgress(otherOpener)
        else
            prog = Character.getActionProgress()
        end

        if prog >= 0.999 then
            log("Door opened! (progress=100%)")
            task.wait(0.3)
            return true, false
        end
    end

    return false, false -- timeout
end

-- Teleport to exit
function ExitController.teleportTo(exitData)
    local root = Character.getRoot()
    if not root or not exitData.area then return end
    root.CFrame = exitData.area.CFrame + Vector3.new(0, 2, 0)
end

-- Escape (full process)
function ExitController.escape(exitData)
    local root = Character.getRoot()
    if not root or not exitData.area then return end

    -- TP down để tránh door collision
    local myPos = root.Position
    root.CFrame = CFrame.new(myPos.X, myPos.Y - 80, myPos.Z)

    -- Freeze
    local hum = Character.getHumanoid()
    if hum then
        hum.PlatformStand = true
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end

    task.wait(1.5)

    -- TP vào exit area
    root.CFrame = exitData.area.CFrame + Vector3.new(0, 2, 0)
    task.wait(0.3)

    -- Unfreeze
    if hum then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end

    -- Wait for escape confirm
    local waitTime = 0
    while waitTime < 10 do
        task.wait(0.2)
        waitTime = waitTime + 0.2
        if Character.hasEscaped() then
            log("Escaped!")
            State.hasEscaped = true
            return
        end
    end
    State.hasEscaped = true
end

-- Start opening exit (self)
function ExitController.startOpening(exitData)
    local root = Character.getRoot()
    if not root then return false end

    -- Move to trigger
    local targetPos = exitData.trigger.Position + Vector3.new(0, 2.5, 0)
    Movement.moveTo(targetPos, Config.tweenSpeed)

    task.wait(0.5)

    -- Fire action
    pcall(function()
        local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
        if r then
            r:FireServer("Input", "Action", true)
        end
    end)
    return true
end

-- Main exit flow
function ExitController.run()
    if State.hasEscaped then return end

    while State.enabled and not State.hasEscaped do
        task.wait(0.2)

        if Character.hasEscaped() then
            State.hasEscaped = true
            log("Escaped!")
            break
        end

        if not GamePhase.isExit() then
            task.wait(0.3)
            continue
        end

        local exits = ExitController.findAll()
        if #exits == 0 then
            task.wait(0.5)
            continue
        end

        for _, exitData in ipairs(exits) do
            if not State.enabled or State.hasEscaped then break end

            if lastExitUsed and exitData.model == lastExitUsed then
                continue
            end

            if ExitController.isOpened(exitData) then
                log("Exit already open, going in")
                ExitController.escape(exitData)
                lastExitUsed = exitData.model
                break
            else
                if BeastController.isNearby(Config.exitDangerDistance) then
                    log("Beast near exit, try next")
                    task.wait(0.5)
                else
                    -- Check if someone else is opening
                    local otherOpener = ExitController.getPlayerOpening(exitData)
                    if otherOpener then
                        log("Other player opening door: " .. otherOpener.Name .. ", waiting...")
                        ExitController.teleportTo(exitData)
                        local opened, beastInterrupted = ExitController.waitForOpen(exitData, Config.doorTimeout)
                        if beastInterrupted then
                            log("Beast interrupted while waiting")
                        elseif opened then
                            ExitController.escape(exitData)
                            lastExitUsed = exitData.model
                            break
                        else
                            log("Door timeout waiting for other player")
                        end
                    else
                        -- Self open
                        local success = ExitController.startOpening(exitData)
                        if success then
                            -- Spam action while waiting
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
                            local opened, beastInterrupted = ExitController.waitForOpen(exitData, Config.doorTimeout)
                            firing = false
                            if beastInterrupted then
                                log("Beast interrupted")
                            elseif opened then
                                ExitController.escape(exitData)
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
    end
end
-- ==========================================================
-- SAVE CONTROLLER
-- ==========================================================
local SaveController = {}

function SaveController.findCagedPlayer()
    local map = ReplicatedStorage:FindFirstChild("CurrentMap")
    map = map and map.Value
    if not map then return nil, nil end

    local root = Character.getRoot()
    if not root then return nil, nil end

    for _, v in ipairs(map:GetChildren()) do
        if v.Name == "FreezePod" then
            local ct = v:FindFirstChild("CapturedTorso", true)
            local trigger = v:FindFirstChild("PodTrigger", true)
            if ct and ct.Value ~= nil and trigger then
                -- Find captured player
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= player and p.Character then
                        local torso = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
                        if torso and ct.Value == torso then
                            return p, v
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

function SaveController.performSave()
    if State.savesThisRound >= Config.maxSavesPerRound then
        return false
    end

    if State.isMoving then
        log("Save: movement locked, skipping")
        return false
    end

    local capturedPlayer, cage = SaveController.findCagedPlayer()
    if not capturedPlayer then return false end

    log("Saving: " .. capturedPlayer.Name)

    -- Save current state
    local savedCanJump = State.canAutoJump
    State.canAutoJump = false
    State.isSaving = true
    State.isMoving = true

    local trigger = cage:FindFirstChild("PodTrigger", true)
    if not trigger then
        State.isSaving = false
        State.isMoving = false
        return false
    end

    -- Calculate save position
    local cageCenter = cage:GetModelCFrame().Position
    local dirIn = (cageCenter - trigger.Position)
    if dirIn.Magnitude > 0 then dirIn = dirIn.Unit * 3 else dirIn = Vector3.zero end
    local savePos = Vector3.new(trigger.Position.X + dirIn.X, trigger.Position.Y, trigger.Position.Z + dirIn.Z)

    -- Move to cage
    Movement.moveTo(savePos, Config.tweenSpeed)

    -- Interact to save
    local root = Character.getRoot()
    local t = 0
    while t < Config.saveTimeout do
        pcall(function()
            firetouchinterest(root, trigger, 0)
            task.wait(0.03)
            firetouchinterest(root, trigger, 1)
        end)
        pcall(function()
            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if r then r:FireServer("Input", "Action", true) end
        end)

        -- Check if saved
        local ct = cage:FindFirstChild("CapturedTorso", true)
        if ct and ct.Value == nil then
            State.savesThisRound = State.savesThisRound + 1
            log("Saved! " .. capturedPlayer.Name .. " freed")
            break
        end
        task.wait(0.15)
        t = t + 0.18
    end

    -- Restore state
    State.canAutoJump = savedCanJump
    State.isSaving = false
    State.isMoving = false

    -- Return to previous position (if hacking)
    if State.isHacking and State.currentTrigger then
        Movement.moveTo(State.currentTrigger.Position + Vector3.new(0, 0.5, 0), Config.tweenSpeed)
        -- Re-fire interact
        pcall(function()
            firetouchinterest(root, State.currentTrigger, 0)
            task.wait(0.1)
            firetouchinterest(root, State.currentTrigger, 1)
        end)
        task.wait(0.2)
        pcall(function()
            local r = ReplicatedStorage:FindFirstChild("RemoteEvent")
            if r then r:FireServer("Input", "Action", true) end
        end)
    end

    return true
end

function SaveController.runLoop()
    while true do
        task.wait(0.3)
        if not State.enabled or Character.isBeast() then continue end
        if State.savesThisRound >= Config.maxSavesPerRound then continue end
        if State.isMoving then continue end
        if State.round == 0 or not GamePhase.isActive() then continue end

        SaveController.performSave()
    end
end
-- ==========================================================
-- GUI SYSTEM
-- ==========================================================
local GUI = {}
local statusLabel = nil
local scriptStartTime = tick()

function GUI.create()
    local TweenService = game:GetService("TweenService")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoHackGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

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
    gearBtn.Text = "⚙️"
    gearBtn.TextColor3 = Color3.new(1,1,1)
    gearBtn.TextSize = 13
    gearBtn.Font = Enum.Font.GothamBold
    gearBtn.BorderSizePixel = 0
    gearBtn.Parent = titleBar
    Instance.new("UICorner", gearBtn).CornerRadius = UDim.new(0, 6)

    -- Toggle button
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

    -- Status label
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

function GUI.create()
    local TweenService = game:GetService("TweenService")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoHackGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    -- ===== MAIN FRAME =====
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 220, 0, 130)
    frame.Position = UDim2.new(0.5, -110, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = false
    frame.Parent = screenGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = frame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "AUTO FARM FTF"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    -- Gear button
    local gearBtn = Instance.new("TextButton")
    gearBtn.Size = UDim2.new(0, 28, 0, 28)
    gearBtn.Position = UDim2.new(1, -32, 0, 2)
    gearBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    gearBtn.Text = "⚙️"
    gearBtn.TextColor3 = Color3.new(1,1,1)
    gearBtn.TextSize = 16
    gearBtn.Font = Enum.Font.GothamBold
    gearBtn.BorderSizePixel = 0
    gearBtn.Parent = titleBar
    Instance.new("UICorner", gearBtn).CornerRadius = UDim.new(0, 6)

    -- Toggle button
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(1, -16, 0, 34)
    toggleButton.Position = UDim2.new(0, 8, 0, 38)
    toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    toggleButton.Text = "OFF"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 14
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.BorderSizePixel = 0
    toggleButton.Parent = frame
    Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 7)

    -- Status label
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 14)
    status.Position = UDim2.new(0, 8, 0, 78)
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
    checkboxFrame.Position = UDim2.new(0, 8, 0, 96)
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

    -- ===== SETTINGS PANEL (ẩn hiện) =====
    local PANEL_H = 360
    local settingsPanel = Instance.new("Frame")
    settingsPanel.Size = UDim2.new(0, 240, 0, PANEL_H)
    settingsPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    settingsPanel.BorderSizePixel = 0
    settingsPanel.ClipsDescendants = true
    settingsPanel.Visible = false
    settingsPanel.Parent = screenGui
    Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 10)

    local settingsOpen = false

    -- Settings title
    local settingsTitle = Instance.new("TextLabel")
    settingsTitle.Size = UDim2.new(1, -10, 0, 30)
    settingsTitle.Position = UDim2.new(0, 5, 0, 5)
    settingsTitle.BackgroundTransparency = 1
    settingsTitle.Text = "⚙️ SETTINGS & STATS"
    settingsTitle.TextColor3 = Color3.fromRGB(200, 200, 255)
    settingsTitle.TextSize = 14
    settingsTitle.Font = Enum.Font.GothamBold
    settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
    settingsTitle.Parent = settingsPanel

    -- Stats labels
    local function makeLabel(yPos, text, color)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -10, 0, 18)
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

    local lblPlayer = makeLabel(35, "Player: " .. player.Name, Color3.fromRGB(255, 220, 100))
    local lblUptime = makeLabel(53, "Uptime: 00:00:00", Color3.fromRGB(150, 220, 255))
    local lblSvTime = makeLabel(71, "Server: --:--:--", Color3.fromRGB(150, 220, 255))
    local lblCredits = makeLabel(89, "Credits: ...", Color3.fromRGB(100, 255, 150))
    local lblCph = makeLabel(107, "C/h: ...", Color3.fromRGB(100, 255, 150))

    -- Divider
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -10, 0, 1)
    div.Position = UDim2.new(0, 5, 0, 130)
    div.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    div.BorderSizePixel = 0
    div.Parent = settingsPanel

    -- Webhook
    makeLabel(135, "Webhook URL:", Color3.fromRGB(180, 180, 255))

    local webhookInput = Instance.new("TextBox")
    webhookInput.Size = UDim2.new(1, -10, 0, 28)
    webhookInput.Position = UDim2.new(0, 5, 0, 153)
    webhookInput.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    webhookInput.BorderSizePixel = 0
    webhookInput.Text = ""
    webhookInput.PlaceholderText = "Paste Discord webhook URL..."
    webhookInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    webhookInput.TextColor3 = Color3.fromRGB(220, 220, 255)
    webhookInput.TextSize = 10
    webhookInput.Font = Enum.Font.Gotham
    webhookInput.ClearTextOnFocus = false
    webhookInput.Parent = settingsPanel
    Instance.new("UICorner", webhookInput).CornerRadius = UDim.new(0, 5)

    -- Interval slider
    local intervalLabel = makeLabel(186, "Every: 5 min", Color3.fromRGB(180, 180, 255))
    local intervalTrack = Instance.new("Frame")
    intervalTrack.Size = UDim2.new(1, -10, 0, 6)
    intervalTrack.Position = UDim2.new(0, 5, 0, 210)
    intervalTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
    intervalTrack.BorderSizePixel = 0
    intervalTrack.Parent = settingsPanel
    Instance.new("UICorner", intervalTrack).CornerRadius = UDim.new(1, 0)

    local intervalFill = Instance.new("Frame")
    intervalFill.Size = UDim2.new(4/59, 0, 1, 0)
    intervalFill.BackgroundColor3 = Color3.fromRGB(80, 80, 200)
    intervalFill.BorderSizePixel = 0
    intervalFill.Parent = intervalTrack
    Instance.new("UICorner", intervalFill).CornerRadius = UDim.new(1, 0)

    local intervalKnob = Instance.new("Frame")
    intervalKnob.Size = UDim2.new(0, 16, 0, 16)
    intervalKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    intervalKnob.Position = UDim2.new(4/59, 0, 0.5, 0)
    intervalKnob.BackgroundColor3 = Color3.fromRGB(140, 140, 255)
    intervalKnob.BorderSizePixel = 0
    intervalKnob.Parent = intervalTrack
    Instance.new("UICorner", intervalKnob).CornerRadius = UDim.new(1, 0)

    -- Speed slider
    local speedLabel = makeLabel(226, "Speed: 35 st/s", Color3.fromRGB(180, 255, 180))
    local speedTrack = Instance.new("Frame")
    speedTrack.Size = UDim2.new(1, -10, 0, 6)
    speedTrack.Position = UDim2.new(0, 5, 0, 250)
    speedTrack.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
    speedTrack.BorderSizePixel = 0
    speedTrack.Parent = settingsPanel
    Instance.new("UICorner", speedTrack).CornerRadius = UDim.new(1, 0)

    local speedFill = Instance.new("Frame")
    speedFill.Size = UDim2.new(25/90, 0, 1, 0)
    speedFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
    speedFill.BorderSizePixel = 0
    speedFill.Parent = speedTrack
    Instance.new("UICorner", speedFill).CornerRadius = UDim.new(1, 0)

    local speedKnob = Instance.new("Frame")
    speedKnob.Size = UDim2.new(0, 16, 0, 16)
    speedKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    speedKnob.Position = UDim2.new(25/90, 0, 0.5, 0)
    speedKnob.BackgroundColor3 = Color3.fromRGB(120, 255, 120)
    speedKnob.BorderSizePixel = 0
    speedKnob.Parent = speedTrack
    Instance.new("UICorner", speedKnob).CornerRadius = UDim.new(1, 0)

    -- Webhook status
    local webhookStatus = makeLabel(270, "", Color3.fromRGB(150, 255, 150))

    -- Test & Auto buttons
    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(0.48, -7, 0, 30)
    testBtn.Position = UDim2.new(0, 5, 0, 290)
    testBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
    testBtn.Text = "Test Webhook"
    testBtn.TextColor3 = Color3.new(1,1,1)
    testBtn.TextSize = 11
    testBtn.Font = Enum.Font.GothamBold
    testBtn.BorderSizePixel = 0
    testBtn.Parent = settingsPanel
    Instance.new("UICorner", testBtn).CornerRadius = UDim.new(0, 6)

    local autoBtn = Instance.new("TextButton")
    autoBtn.Size = UDim2.new(0.52, -8, 0, 30)
    autoBtn.Position = UDim2.new(0.48, 3, 0, 290)
    autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    autoBtn.Text = "Auto: OFF"
    autoBtn.TextColor3 = Color3.new(1,1,1)
    autoBtn.TextSize = 10
    autoBtn.Font = Enum.Font.GothamBold
    autoBtn.BorderSizePixel = 0
    autoBtn.Parent = settingsPanel
    Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 6)

    local autoSendEnabled = false
    local webhookUrl = ""
    local webhookInterval = 5
    local creditsAtStart = nil

    -- ===== FUNCTIONS =====
    local function getCredits()
        local stats = player:FindFirstChild("SavedPlayerStatsModule")
        if stats then
            local c = stats:FindFirstChild("Credits")
            if c then return c.Value end
        end
        return nil
    end

    local function formatUptime(secs)
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        local s = math.floor(secs % 60)
        return string.format("%02d:%02d:%02d", h, m, s)
    end

    local function sendWebhook(isTest)
        if webhookUrl == "" then
            webhookStatus.Text = "No webhook URL!"
            return
        end
        local uptime = formatUptime(tick() - scriptStartTime)
        local credits = getCredits()
        local deltaCredits = (credits and creditsAtStart) and (credits - creditsAtStart) or 0
        local cph = (tick() - scriptStartTime) > 60 and math.floor(deltaCredits / (tick() - scriptStartTime) * 3600) or 0

        local content = isTest and "**[FTF AUTO FARM] TEST**" or "**[FTF AUTO FARM] Webhook**"
        content = content .. "\nPlayer: **" .. player.Name .. "**"
        content = content .. "\nUptime: **" .. uptime .. "**"
        content = content .. "\nCredits: **" .. tostring(credits or "?") .. "C**"
        content = content .. "\nEarned: **+" .. tostring(deltaCredits) .. "C**"
        content = content .. "\nC/h: **" .. tostring(cph) .. "C**"

        pcall(function()
            local body = HttpService:JSONEncode({content = content})
            if request then
                request({
                    Url = webhookUrl,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = body
                })
            else
                HttpService:PostAsync(webhookUrl, body, Enum.HttpContentType.ApplicationJson)
            end
            webhookStatus.Text = isTest and "Test sent!" or "Sent!"
        end)
    end

    -- ===== SLIDER LOGIC =====
    local function setInterval(val)
        val = math.clamp(math.round(val), 1, 60)
        webhookInterval = val
        local pct = (val - 1) / 59
        intervalFill.Size = UDim2.new(pct, 0, 1, 0)
        intervalKnob.Position = UDim2.new(pct, 0, 0.5, 0)
        intervalLabel.Text = "Every: " .. val .. " min"
    end

    local function setSpeed(val)
        val = math.clamp(math.floor(val), 10, 100)
        Config.tweenSpeed = val
        local pct = (val - 10) / 90
        speedFill.Size = UDim2.new(pct, 0, 1, 0)
        speedKnob.Position = UDim2.new(pct, 0, 0.5, 0)
        speedLabel.Text = "Speed: " .. val .. " st/s"
        local warn = val > 60
        speedLabel.TextColor3 = warn and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(180, 255, 180)
        speedFill.BackgroundColor3 = warn and Color3.fromRGB(255, 140, 30) or Color3.fromRGB(80, 200, 80)
        speedKnob.BackgroundColor3 = warn and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(120, 255, 120)
    end

    -- Drag interval
    local intervalDragging = false
    intervalTrack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            intervalDragging = true
            local pct = math.clamp((input.Position.X - intervalTrack.AbsolutePosition.X) / intervalTrack.AbsoluteSize.X, 0, 1)
            setInterval(1 + pct * 59)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            intervalDragging = false
            speedDragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if intervalDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local pct = math.clamp((input.Position.X - intervalTrack.AbsolutePosition.X) / intervalTrack.AbsoluteSize.X, 0, 1)
            setInterval(1 + pct * 59)
        end
    end)

    -- Drag speed
    local speedDragging = false
    speedTrack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            speedDragging = true
            local pct = math.clamp((input.Position.X - speedTrack.AbsolutePosition.X) / speedTrack.AbsoluteSize.X, 0, 1)
            setSpeed(10 + pct * 90)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if speedDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local pct = math.clamp((input.Position.X - speedTrack.AbsolutePosition.X) / speedTrack.AbsoluteSize.X, 0, 1)
            setSpeed(10 + pct * 90)
        end
    end)

    -- ===== BUTTON EVENTS =====
    webhookInput:GetPropertyChangedSignal("Text"):Connect(function()
        webhookUrl = webhookInput.Text
    end)

    testBtn.MouseButton1Click:Connect(function()
        webhookStatus.Text = "Sending..."
        task.spawn(function() sendWebhook(true) end)
    end)

    autoBtn.MouseButton1Click:Connect(function()
        autoSendEnabled = not autoSendEnabled
        if autoSendEnabled then
            autoBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 50)
            autoBtn.Text = "Auto: ON"
            webhookStatus.Text = "Auto every " .. webhookInterval .. "m"
        else
            autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            autoBtn.Text = "Auto: OFF"
            webhookStatus.Text = "Auto off"
        end
    end)

    -- ===== AUTO WEBHOOK LOOP =====
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

    -- ===== STATS UPDATE LOOP =====
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
            lblUptime.Text = "Uptime: " .. formatUptime(elapsed)
            lblSvTime.Text = "Server: " .. os.date("%H:%M:%S")
            lblCredits.Text = "Credits: " .. tostring(credits or "?")
            lblCph.Text = "+" .. tostring(deltaCredits) .. "C  (" .. tostring(cph) .. "C/h)"
        end
    end)

    -- ===== TOGGLE SETTINGS =====
    local function toggleSettings()
        settingsOpen = not settingsOpen
        if settingsOpen then
            settingsPanel.Position = UDim2.new(0, 20, 0, 160)
            settingsPanel.Visible = true
            TweenService:Create(settingsPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 20, 0, 160)
            }):Play()
        else
            TweenService:Create(settingsPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                Position = UDim2.new(0, 20, 0, 160)
            }):Play()
            task.delay(0.25, function() settingsPanel.Visible = false end)
        end
    end

    gearBtn.MouseButton1Click:Connect(toggleSettings)

    -- ===== MAIN BUTTONS =====
    toggleButton.MouseButton1Click:Connect(function()
        State.enabled = not State.enabled
        if State.enabled then
            toggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
            toggleButton.Text = "ON"
            State.hasEscaped = false
            log("Script ON")
        else
            toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            toggleButton.Text = "OFF"
            log("Script OFF")
        end
    end)

    checkButton.MouseButton1Click:Connect(function()
        State.hackExtraPC = not State.hackExtraPC
        checkmark.Visible = State.hackExtraPC
        checkbox.BackgroundColor3 = State.hackExtraPC and Color3.fromRGB(80, 40, 40) or Color3.fromRGB(60, 60, 60)
        checkbox.BorderColor3 = State.hackExtraPC and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(120, 120, 120)
        checkLabel.TextColor3 = State.hackExtraPC and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(180, 180, 180)
    end)

    -- ===== DRAG =====
    local dragging, dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
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
-- ==========================================================
-- MAIN LOOP
-- ==========================================================
local MainLoop = {}

function MainLoop.resetRound()
    State.gameOver = false
    State.isHacking = false
    State.currentPC = nil
    State.currentTrigger = nil
    State.canAutoJump = false
    State.hasEscaped = false
    State.skipCurrentPC = false
    State.hackedPCs = {}
    State.skippedPCs = {}
    State.savesThisRound = 0
    State.isSaving = false
    State.isMoving = false
    State.movementLock = false
    State.foundBeast = false
    State.beast = nil
    State.allPCs = {}
    lastExitUsed = nil
    Character.update()
    GUI.updateStatus("Waiting for new round")
end

function MainLoop.runSurvivorRound()
    GUI.updateStatus("Hacking PCs...")
    PCSystem.processAll()

    -- Wait for exit phase
    if State.enabled and not State.gameOver then
        GUI.updateStatus("Waiting for Find Exit...")
        local waitStart = tick()
        repeat
            task.wait(0.5)
        until GamePhase.isExit() or (tick() - waitStart > 30) or not State.enabled
    end

    if State.enabled and GamePhase.isExit() then
        GUI.updateStatus("Auto Exit started!")
        ExitController.run()
    end
end

function MainLoop.run()
    while true do
        if not State.enabled then
            State.isHacking = false
            State.currentPC = nil
            State.canAutoJump = false
            State.hasEscaped = false
            task.wait(0.5)
            continue
        end

        -- Wait for round start
        if not GamePhase.waitForRoundStart() then
            log("waitForRoundStart failed, retry in 10s")
            task.wait(10)
            continue
        end

        State.round = State.round + 1
        MainLoop.resetRound()
        log("=== ROUND " .. State.round .. " START | Extra=" .. tostring(State.hackExtraPC) .. " ===")

        -- Check if beast
        if Character.isBeast() then
            GUI.updateStatus("Beast mode - auto running")
            BeastMode.runRound()
            continue
        end

        -- Survivor mode
        MainLoop.runSurvivorRound()

        log("=== ROUND " .. State.round .. " COMPLETE ===")
        task.wait(3)
    end
end
-- ==========================================================
-- INIT & START
-- ==========================================================
local function init()
    -- Update character references
    Character.update()

    -- Create GUI
    GUI.create()

    -- Anti AFK
    task.spawn(function()
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

    -- Beast finder loop
    task.spawn(function()
        while true do
            task.wait(0.5)
            if not State.enabled then continue end
            if not State.foundBeast then
                BeastController.find()
            else
                -- Check if beast still exists
                if not State.beast or not Players:FindFirstChild(State.beast.Name) or not BeastController.isBeast(State.beast) then
                    State.foundBeast = false
                    State.beast = nil
                    log("Beast lost")
                end
            end
        end
    end)

    -- Auto save loop
    task.spawn(function()
        SaveController.runLoop()
    end)

    -- Never fail hook
    task.spawn(function()
        local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent", 10)
        if not remoteEvent then return end
        while true do
            task.wait(0.1)
            if not State.enabled then continue end
            if GamePhase.isActive() then
                pcall(function()
                    remoteEvent:FireServer("SetPlayerMinigameResult", true)
                end)
            end
        end
    end)

    -- Start main loop
    task.spawn(function()
        MainLoop.run()
    end)

    -- Heartbeat jump handler
    RunService.Heartbeat:Connect(function(dt)
        if not State.enabled then return end
        if State.gameOver then
            State.canAutoJump = false
            return
        end
        if State.canAutoJump and State.humanoid and State.rootPart and State.currentTrigger then
            State.jumpTimer = State.jumpTimer + dt
            if State.jumpTimer >= Config.jumpInterval then
                pcall(function()
                    State.rootPart.CFrame = CFrame.new(State.rootPart.CFrame.Position + Vector3.new(0, 7, 0))
                end)
                task.wait(0.07)
                pcall(function()
                    State.rootPart.CFrame = State.currentTrigger.CFrame + Vector3.new(0, 0.5, 0)
                end)
                State.jumpTimer = 0
            end
        end
    end)

    log("Script initialized!")
    GUI.updateStatus("Ready - Press ON to start")
end

-- ==========================================================
-- START
-- ==========================================================
init()
