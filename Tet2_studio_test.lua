--!strict
-- Tet2_studio_test.lua
-- Clean Studio test version for Roblox.
-- This file keeps the original idea organized, but removes unsafe client-forced actions.
-- It is meant for debugging state, UI, map detection, phase detection, and round flow in Roblox Studio.

-- =========================================================
-- Services
-- =========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- =========================================================
-- Config
-- =========================================================

local Config = {
    TickRate = 0.35,
    ScanRate = 1.00,
    LogPrefix = "[TET2-STUDIO]",
    GuiName = "Tet2StudioTestGUI",
    Title = "TET2 STUDIO TEST",

    ComputerKeyword = "computer",
    ComputerTriggerNames = {
        ComputerTrigger1 = true,
        ComputerTrigger2 = true,
        ComputerTrigger3 = true,
    },

    ExitModelName = "ExitDoor",
    ExitTriggerName = "ExitDoorTrigger",
    ExitAreaName = "ExitArea",

    PodModelName = "FreezePod",
    PodTriggerName = "PodTrigger",
    CapturedTorsoName = "CapturedTorso",
}

-- =========================================================
-- Small utilities
-- =========================================================

local function now(): string
    return os.date("%H:%M:%S")
end

local function log(message: string)
    print(Config.LogPrefix .. " " .. now() .. " | " .. tostring(message))
end

local function warnLog(message: string)
    warn(Config.LogPrefix .. " " .. now() .. " | " .. tostring(message))
end

local function upperText(value: any): string
    return string.upper(tostring(value or ""))
end

local function safeDisconnect(connection: RBXScriptConnection?)
    if connection and connection.Connected then
        connection:Disconnect()
    end
end

-- =========================================================
-- State
-- =========================================================

local Phase = {
    Idle = "IDLE",
    Waiting = "WAITING",
    HeadStart = "HEAD_START",
    Hacking = "HACKING",
    Exit = "EXIT",
    Finished = "FINISHED",
}

local State = {
    Enabled = false,
    RoundId = 0,
    Phase = Phase.Idle,

    IsMoving = false,
    IsBusy = false,
    IsSaving = false,

    CurrentComputerId = nil :: number?,
    CurrentComputer = nil :: Model?,
    CurrentTrigger = nil :: BasePart?,

    Computers = {} :: {any},
    Exits = {} :: {any},
    Pods = {} :: {any},

    HackedComputers = {} :: {[number]: boolean},
    SkippedComputers = {} :: {[number]: boolean},

    Connections = {} :: {RBXScriptConnection},
    LastScan = 0,

    ScreenGui = nil :: ScreenGui?,
    StatusLabel = nil :: TextLabel?,
    PhaseLabel = nil :: TextLabel?,
    RoundLabel = nil :: TextLabel?,
    CountsLabel = nil :: TextLabel?,
    RoleLabel = nil :: TextLabel?,
    DetailLabel = nil :: TextLabel?,
}

local Character = {
    Model = nil :: Model?,
    Humanoid = nil :: Humanoid?,
    Root = nil :: BasePart?,
}

local function addConnection(connection: RBXScriptConnection)
    table.insert(State.Connections, connection)
end

local function cleanupConnections()
    for _, connection in ipairs(State.Connections) do
        safeDisconnect(connection)
    end
    table.clear(State.Connections)
end

local function clearRoundState()
    State.IsMoving = false
    State.IsBusy = false
    State.IsSaving = false
    State.CurrentComputerId = nil
    State.CurrentComputer = nil
    State.CurrentTrigger = nil
    State.HackedComputers = {}
    State.SkippedComputers = {}
end

local function setStatus(message: string)
    if State.StatusLabel then
        State.StatusLabel.Text = "Status: " .. message
    end
    log(message)
end

local function setPhase(phase: string)
    if State.Phase == phase then
        return
    end

    State.Phase = phase
    if State.PhaseLabel then
        State.PhaseLabel.Text = "Phase: " .. phase
    end
    log("Phase -> " .. phase)
end

local function renderRound()
    if State.RoundLabel then
        State.RoundLabel.Text = "Round: " .. tostring(State.RoundId)
    end
end

local function renderCounts()
    if State.CountsLabel then
        State.CountsLabel.Text = string.format(
            "Map: %d PC | %d Exit | %d Pod",
            #State.Computers,
            #State.Exits,
            #State.Pods
        )
    end
end

local function renderDetail(message: string)
    if State.DetailLabel then
        State.DetailLabel.Text = message
    end
end

-- =========================================================
-- Character lifecycle
-- =========================================================

local function refreshCharacter(): boolean
    local character = LocalPlayer.Character
    if not character then
        character = LocalPlayer.CharacterAdded:Wait()
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    Character.Model = character
    Character.Humanoid = humanoid
    Character.Root = root :: BasePart?

    return humanoid ~= nil and root ~= nil
end

local function bindCharacterLifecycle()
    refreshCharacter()

    addConnection(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.4)
        if refreshCharacter() then
            setStatus("Character refreshed")
        else
            warnLog("Character refreshed but missing Humanoid/Root")
        end
    end))
end

-- =========================================================
-- Game status / role helpers
-- =========================================================

local function getStatusFromValue(): string
    local statusValue = ReplicatedStorage:FindFirstChild("GameStatus")
    if statusValue and statusValue:IsA("StringValue") then
        return upperText(statusValue.Value)
    end
    return ""
end

local function getStatusFromGui(): string
    local ok, value = pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        local screenGui = playerGui and playerGui:FindFirstChild("ScreenGui")
        local gameInfoFrame = screenGui and screenGui:FindFirstChild("GameInfoFrame")
        local statusBox = gameInfoFrame and gameInfoFrame:FindFirstChild("GameStatusBox")

        if statusBox and statusBox:IsA("TextLabel") then
            return upperText(statusBox.Text)
        end
        return ""
    end)

    if ok and typeof(value) == "string" then
        return value
    end
    return ""
end

local function getGameStatusText(): string
    local fromValue = getStatusFromValue()
    if fromValue ~= "" then
        return fromValue
    end
    return getStatusFromGui()
end

local function isRoundStarting(): boolean
    local text = getGameStatusText()
    return text:find("HEAD START") ~= nil or text:find("START") ~= nil
end

local function isExitPhase(): boolean
    local text = getGameStatusText()
    return (text:find("FIND") ~= nil and text:find("EXIT") ~= nil)
        or text:find("ESCAPE") ~= nil
end

local function isRoundFinished(): boolean
    local text = getGameStatusText()
    return text:find("GAME OVER") ~= nil
        or text:find("BEAST LEFT") ~= nil
        or text:find("FINISHED") ~= nil
        or text:find("KET THUC") ~= nil
        or text:find("TRO CHOI KET THUC") ~= nil
end

local function isRoundActive(): boolean
    local text = getGameStatusText()
    if text == "" or isRoundFinished() then
        return false
    end

    return text:find("HEAD START") ~= nil
        or text:find("HACK") ~= nil
        or text:find("FIND") ~= nil
        or text:find("ESCAPE") ~= nil
end

local function getTempStats(player: Player): Instance?
    return player:FindFirstChild("TempPlayerStatsModule")
end

local function isPlayerBeast(player: Player): boolean
    local stats = getTempStats(player)
    local flag = stats and stats:FindFirstChild("IsBeast")
    return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

local function isSelfBeast(): boolean
    return isPlayerBeast(LocalPlayer)
end

local function hasEscaped(): boolean
    local stats = getTempStats(LocalPlayer)
    local flag = stats and stats:FindFirstChild("Escaped")
    return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

local function getRoleText(): string
    if isSelfBeast() then
        return "Beast"
    end
    return "Survivor"
end

local function renderRole()
    if State.RoleLabel then
        State.RoleLabel.Text = "Role: " .. getRoleText()
    end
end

-- =========================================================
-- Map scanner
-- =========================================================

local function getCurrentMap(): Instance?
    local currentMap = ReplicatedStorage:FindFirstChild("CurrentMap")
    if currentMap and currentMap:IsA("ObjectValue") then
        return currentMap.Value
    end
    return nil
end

local function getModelKey(model: Instance): string
    return model:GetFullName()
end

local function collectComputerTriggers(model: Instance): {BasePart}
    local triggers = {}
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and Config.ComputerTriggerNames[descendant.Name] then
            table.insert(triggers, descendant)
        end
    end
    return triggers
end

local function isComputerComplete(computer: Model): boolean
    local screen = computer:FindFirstChild("Screen")
    if screen and screen:IsA("BasePart") then
        local color = screen.Color
        if color.G > color.R + 0.2 and color.G > color.B + 0.2 then
            return true
        end
    end

    for _, descendant in ipairs(computer:GetDescendants()) do
        if descendant:IsA("NumberValue") or descendant:IsA("IntValue") then
            if (descendant.Name == "ActionProgress" or descendant.Name == "Value") and descendant.Value >= 1 then
                return true
            end
        end
    end

    return false
end

local function scanComputers(map: Instance): {any}
    local found = {}
    local seen = {}

    for _, item in ipairs(map:GetDescendants()) do
        if item:IsA("Model") then
            local lowerName = string.lower(item.Name)
            if lowerName:find(Config.ComputerKeyword, 1, true) and not lowerName:find("prefab", 1, true) then
                local key = getModelKey(item)
                if not seen[key] then
                    seen[key] = true
                    local triggers = collectComputerTriggers(item)
                    table.insert(found, {
                        id = #found + 1,
                        model = item,
                        triggers = triggers,
                        complete = isComputerComplete(item),
                    })
                end
            end
        end
    end

    return found
end

local function scanExits(map: Instance): {any}
    local found = {}
    for _, item in ipairs(map:GetDescendants()) do
        if item:IsA("Model") and item.Name == Config.ExitModelName then
            local trigger = item:FindFirstChild(Config.ExitTriggerName, true)
            local area = item:FindFirstChild(Config.ExitAreaName, true)
            table.insert(found, {
                id = #found + 1,
                model = item,
                trigger = trigger,
                area = area,
            })
        end
    end
    return found
end

local function scanPods(map: Instance): {any}
    local found = {}
    for _, item in ipairs(map:GetDescendants()) do
        if item:IsA("Model") and item.Name == Config.PodModelName then
            local trigger = item:FindFirstChild(Config.PodTriggerName, true)
            local capturedTorso = item:FindFirstChild(Config.CapturedTorsoName, true)
            table.insert(found, {
                id = #found + 1,
                model = item,
                trigger = trigger,
                capturedTorso = capturedTorso,
                occupied = capturedTorso ~= nil and capturedTorso:IsA("ObjectValue") and capturedTorso.Value ~= nil,
            })
        end
    end
    return found
end

local function scanMap(force: boolean?)
    local t = os.clock()
    if not force and t - State.LastScan < Config.ScanRate then
        return
    end
    State.LastScan = t

    local map = getCurrentMap()
    if not map then
        State.Computers = {}
        State.Exits = {}
        State.Pods = {}
        renderCounts()
        renderDetail("No CurrentMap found")
        return
    end

    State.Computers = scanComputers(map)
    State.Exits = scanExits(map)
    State.Pods = scanPods(map)
    renderCounts()

    local completeCount = 0
    for _, pc in ipairs(State.Computers) do
        if pc.complete then
            completeCount += 1
        end
    end

    renderDetail(string.format(
        "Status: %s | Complete PC: %d/%d",
        getGameStatusText(),
        completeCount,
        #State.Computers
    ))
end

-- =========================================================
-- Clean action controller
-- =========================================================
-- These handlers intentionally do not force character movement or remote calls.
-- They only choose what the script would work on and display debug information.

local Controller = {}

function Controller.stopCurrentAction()
    State.IsBusy = false
    State.IsMoving = false
    State.IsSaving = false
    State.CurrentComputerId = nil
    State.CurrentComputer = nil
    State.CurrentTrigger = nil
end

function Controller.pickNextComputer(): any?
    for _, pc in ipairs(State.Computers) do
        if not pc.complete and not State.HackedComputers[pc.id] and not State.SkippedComputers[pc.id] then
            return pc
        end
    end
    return nil
end

function Controller.onSurvivorTick()
    scanMap(false)

    local pc = Controller.pickNextComputer()
    if not pc then
        setStatus("No available computer target")
        return
    end

    State.CurrentComputerId = pc.id
    State.CurrentComputer = pc.model
    State.CurrentTrigger = pc.triggers[1]

    setStatus(string.format(
        "Selected PC %d | triggers: %d | complete: %s",
        pc.id,
        #pc.triggers,
        tostring(pc.complete)
    ))
end

function Controller.onExitTick()
    scanMap(false)

    if #State.Exits == 0 then
        setStatus("Exit phase detected, but no exit found")
        return
    end

    local firstExit = State.Exits[1]
    setStatus("Exit phase | selected exit " .. tostring(firstExit.id))
end

function Controller.onBeastTick()
    scanMap(false)
    setStatus("Beast role detected | Studio-safe observer mode")
end

function Controller.onRoundStart()
    State.RoundId += 1
    clearRoundState()
    renderRound()
    scanMap(true)
    setStatus("Round started")
end

function Controller.onRoundEnd()
    Controller.stopCurrentAction()
    setPhase(Phase.Finished)
    setStatus("Round ended")
end

-- =========================================================
-- Main loop
-- =========================================================

local function waitForRound(): boolean
    setPhase(Phase.Waiting)
    setStatus("Waiting for round")

    while State.Enabled do
        renderRole()
        scanMap(false)

        if isRoundStarting() then
            setPhase(Phase.HeadStart)
            return true
        end

        if isRoundActive() then
            return true
        end

        task.wait(Config.TickRate)
    end

    return false
end

local function runRound()
    Controller.onRoundStart()

    while State.Enabled and isRoundActive() do
        renderRole()

        if hasEscaped() then
            setStatus("Escaped flag detected")
            break
        end

        if isExitPhase() then
            setPhase(Phase.Exit)
            Controller.onExitTick()
        elseif isSelfBeast() then
            setPhase(Phase.Hacking)
            Controller.onBeastTick()
        else
            setPhase(Phase.Hacking)
            Controller.onSurvivorTick()
        end

        task.wait(Config.TickRate)
    end

    Controller.onRoundEnd()
end

local mainLoopStarted = false
local function startMainLoop()
    if mainLoopStarted then
        return
    end
    mainLoopStarted = true

    task.spawn(function()
        while true do
            if not State.Enabled then
                setPhase(Phase.Idle)
                Controller.stopCurrentAction()
                task.wait(0.5)
                continue
            end

            local ready = waitForRound()
            if ready and State.Enabled then
                runRound()
            end

            task.wait(Config.TickRate)
        end
    end)
end

-- =========================================================
-- GUI
-- =========================================================

local function makeLabel(parent: Instance, text: string, y: number, height: number?): TextLabel
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -16, 0, height or 18)
    label.Position = UDim2.new(0, 8, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(190, 220, 190)
    label.TextSize = 11
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = parent
    return label
end

local function makeButton(parent: Instance, text: string, y: number): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -16, 0, 30)
    button.Position = UDim2.new(0, 8, 0, y)
    button.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
    button.Text = text
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 13
    button.Font = Enum.Font.GothamBold
    button.BorderSizePixel = 0
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = button

    return button
end

local function createGui()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local oldGui = playerGui:FindFirstChild(Config.GuiName)
    if oldGui then
        oldGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = Config.GuiName
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    State.ScreenGui = screenGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 250, 0, 205)
    frame.Position = UDim2.new(0.5, -125, 0, 24)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 10)
    frameCorner.Parent = frame

    local title = makeLabel(frame, Config.Title, 6)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold

    local toggleButton = makeButton(frame, "OFF", 32)
    toggleButton.BackgroundColor3 = Color3.fromRGB(180, 55, 55)

    local scanButton = makeButton(frame, "SCAN MAP", 66)
    scanButton.BackgroundColor3 = Color3.fromRGB(55, 95, 160)

    State.StatusLabel = makeLabel(frame, "Status: Ready", 102, 18)
    State.PhaseLabel = makeLabel(frame, "Phase: IDLE", 122, 18)
    State.RoundLabel = makeLabel(frame, "Round: 0", 142, 18)
    State.RoleLabel = makeLabel(frame, "Role: Unknown", 162, 18)
    State.CountsLabel = makeLabel(frame, "Map: 0 PC | 0 Exit | 0 Pod", 182, 18)

    local detailPanel = Instance.new("Frame")
    detailPanel.Size = UDim2.new(0, 250, 0, 75)
    detailPanel.Position = UDim2.new(0.5, -125, 0, 235)
    detailPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
    detailPanel.BorderSizePixel = 0
    detailPanel.Parent = screenGui

    local detailCorner = Instance.new("UICorner")
    detailCorner.CornerRadius = UDim.new(0, 10)
    detailCorner.Parent = detailPanel

    State.DetailLabel = makeLabel(detailPanel, "Detail: none", 8, 60)

    toggleButton.MouseButton1Click:Connect(function()
        State.Enabled = not State.Enabled

        if State.Enabled then
            toggleButton.Text = "ON"
            toggleButton.BackgroundColor3 = Color3.fromRGB(55, 170, 80)
            setStatus("Enabled")
        else
            toggleButton.Text = "OFF"
            toggleButton.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
            Controller.stopCurrentAction()
            setStatus("Disabled")
        end
    end)

    scanButton.MouseButton1Click:Connect(function()
        scanMap(true)
        setStatus("Manual scan complete")
    end)

    local dragging = false
    local dragStart: Vector3? = nil
    local startPos: UDim2? = nil

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging or not dragStart or not startPos then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            detailPanel.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y + 211
            )
        end
    end)
end

-- =========================================================
-- Debug export
-- =========================================================

local function printDebugSnapshot()
    local snapshot = {
        enabled = State.Enabled,
        roundId = State.RoundId,
        phase = State.Phase,
        role = getRoleText(),
        status = getGameStatusText(),
        computers = #State.Computers,
        exits = #State.Exits,
        pods = #State.Pods,
    }

    log("Snapshot: " .. HttpService:JSONEncode(snapshot))
end

-- =========================================================
-- Init
-- =========================================================

bindCharacterLifecycle()
createGui()
startMainLoop()
scanMap(true)
renderRound()
renderRole()
renderCounts()
setStatus("Loaded")

addConnection(RunService.Heartbeat:Connect(function()
    if State.Enabled then
        refreshCharacter()
    end
end))

task.spawn(function()
    while true do
        task.wait(10)
        if State.Enabled then
            printDebugSnapshot()
        end
    end
end)