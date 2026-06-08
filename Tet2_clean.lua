--!strict
-- Tet2_clean.lua
-- Clean Roblox client controller skeleton.
-- Focus: readable state, round watching, GUI, character refs, and cleanup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Config = {
    TickRate = 0.25,
    GuiTitle = "TET2 CLEAN",
    LogPrefix = "[TET2-CLEAN]",
}

local Phase = {
    Idle = "IDLE",
    Waiting = "WAITING",
    Starting = "STARTING",
    Playing = "PLAYING",
    Exit = "EXIT",
    Finished = "FINISHED",
}

local State = {
    Enabled = false,
    RoundId = 0,
    Phase = Phase.Idle,
    Busy = false,
    Moving = false,
    CurrentTarget = nil :: Instance?,
    CurrentTrigger = nil :: BasePart?,
    StatusLabel = nil :: TextLabel?,
    PhaseLabel = nil :: TextLabel?,
    RoundLabel = nil :: TextLabel?,
    Connections = {} :: {RBXScriptConnection},
}

local Character = {
    Model = nil :: Model?,
    Humanoid = nil :: Humanoid?,
    Root = nil :: BasePart?,
}

local function log(message: string)
    print(Config.LogPrefix .. " " .. tostring(message))
end

local function addConnection(connection: RBXScriptConnection)
    table.insert(State.Connections, connection)
end

local function disconnectAll()
    for _, connection in ipairs(State.Connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(State.Connections)
end

local function setStatus(message: string)
    if State.StatusLabel then
        State.StatusLabel.Text = "Status: " .. message
    end
    log(message)
end

local function renderState()
    if State.PhaseLabel then
        State.PhaseLabel.Text = "Phase: " .. State.Phase
    end
    if State.RoundLabel then
        State.RoundLabel.Text = "Round: " .. tostring(State.RoundId)
    end
end

local function setPhase(phase: string)
    if State.Phase == phase then
        return
    end
    State.Phase = phase
    renderState()
    setStatus("Phase changed to " .. phase)
end

local function resetActionState()
    State.Busy = false
    State.Moving = false
    State.CurrentTarget = nil
    State.CurrentTrigger = nil
end

local function refreshCharacter(): boolean
    local character = LocalPlayer.Character
    if not character then
        character = LocalPlayer.CharacterAdded:Wait()
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        Character.Model = nil
        Character.Humanoid = nil
        Character.Root = nil
        return false
    end

    Character.Model = character
    Character.Humanoid = humanoid
    Character.Root = root
    return true
end

local function bindCharacterLifecycle()
    refreshCharacter()
    addConnection(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        if refreshCharacter() then
            setStatus("Character refreshed")
        else
            setStatus("Character refresh failed")
        end
    end))
end

local function getGameStatusText(): string
    local gameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
    if gameStatus and gameStatus:IsA("StringValue") then
        return string.upper(gameStatus.Value)
    end

    local ok, text = pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        local screenGui = playerGui and playerGui:FindFirstChild("ScreenGui")
        local infoFrame = screenGui and screenGui:FindFirstChild("GameInfoFrame")
        local statusBox = infoFrame and infoFrame:FindFirstChild("GameStatusBox")
        if statusBox and statusBox:IsA("TextLabel") then
            return string.upper(statusBox.Text)
        end
        return ""
    end)

    if ok and typeof(text) == "string" then
        return text
    end
    return ""
end

local function isRoundStarting(): boolean
    local text = getGameStatusText()
    return text:find("HEAD START") ~= nil or text:find("START") ~= nil
end

local function isRoundFinished(): boolean
    local text = getGameStatusText()
    return text:find("GAME OVER") ~= nil
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
        or text:find("PLAY") ~= nil
end

local function isExitPhase(): boolean
    local text = getGameStatusText()
    return text:find("FIND") ~= nil and text:find("EXIT") ~= nil
end

local function getTempStats(player: Player): Instance?
    return player:FindFirstChild("TempPlayerStatsModule")
end

local function isSelfBeast(): boolean
    local stats = getTempStats(LocalPlayer)
    local flag = stats and stats:FindFirstChild("IsBeast")
    return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

local function hasEscaped(): boolean
    local stats = getTempStats(LocalPlayer)
    local flag = stats and stats:FindFirstChild("Escaped")
    return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

local function listMapModels(keyword: string): {Model}
    local result = {}
    local currentMap = ReplicatedStorage:FindFirstChild("CurrentMap")
    local map = currentMap and currentMap:IsA("ObjectValue") and currentMap.Value or nil
    if not map then
        return result
    end

    local needle = string.lower(keyword)
    for _, item in ipairs(map:GetDescendants()) do
        if item:IsA("Model") and string.find(string.lower(item.Name), needle, 1, true) then
            table.insert(result, item)
        end
    end
    return result
end

local Controller = {}

function Controller.onRoundStart()
    State.RoundId += 1
    resetActionState()
    renderState()
    setStatus("Round started")
end

function Controller.onRoundFinish()
    resetActionState()
    setPhase(Phase.Finished)
    setStatus("Round finished")
end

function Controller.onSurvivorTick()
    local computers = listMapModels("computer")
    setStatus("Survivor tick | computers found: " .. tostring(#computers))
end

function Controller.onExitTick()
    local exits = listMapModels("exit")
    setStatus("Exit tick | exits found: " .. tostring(#exits))
end

function Controller.onBeastTick()
    setStatus("Beast tick | role detected")
end

local function waitForRound(): boolean
    setPhase(Phase.Waiting)
    while State.Enabled do
        if isRoundStarting() or isRoundActive() then
            return true
        end
        task.wait(Config.TickRate)
    end
    return false
end

local function runRound()
    Controller.onRoundStart()
    setPhase(Phase.Playing)

    while State.Enabled and isRoundActive() do
        if hasEscaped() then
            setPhase(Phase.Finished)
            break
        end

        if isExitPhase() then
            setPhase(Phase.Exit)
            Controller.onExitTick()
        elseif isSelfBeast() then
            setPhase(Phase.Playing)
            Controller.onBeastTick()
        else
            setPhase(Phase.Playing)
            Controller.onSurvivorTick()
        end

        task.wait(Config.TickRate)
    end

    Controller.onRoundFinish()
end

local function mainLoop()
    while true do
        if not State.Enabled then
            setPhase(Phase.Idle)
            resetActionState()
            task.wait(0.5)
            continue
        end

        local ready = waitForRound()
        if ready and State.Enabled then
            runRound()
        end

        task.wait(Config.TickRate)
    end
end

local function makeLabel(parent: Instance, text: string, y: number): TextLabel
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -16, 0, 18)
    label.Position = UDim2.new(0, 8, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(190, 220, 190)
    label.TextSize = 11
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function createGui()
    local oldGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("Tet2CleanGUI")
    if oldGui then
        oldGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Tet2CleanGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 230, 0, 140)
    frame.Position = UDim2.new(0.5, -115, 0, 24)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = makeLabel(frame, Config.GuiTitle, 6)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(1, -16, 0, 30)
    toggle.Position = UDim2.new(0, 8, 0, 32)
    toggle.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
    toggle.Text = "OFF"
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.TextSize = 14
    toggle.Font = Enum.Font.GothamBold
    toggle.BorderSizePixel = 0
    toggle.Parent = frame

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 7)
    toggleCorner.Parent = toggle

    State.StatusLabel = makeLabel(frame, "Status: Ready", 68)
    State.PhaseLabel = makeLabel(frame, "Phase: IDLE", 88)
    State.RoundLabel = makeLabel(frame, "Round: 0", 108)

    toggle.MouseButton1Click:Connect(function()
        State.Enabled = not State.Enabled
        if State.Enabled then
            toggle.BackgroundColor3 = Color3.fromRGB(55, 170, 80)
            toggle.Text = "ON"
            setStatus("Enabled")
        else
            toggle.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
            toggle.Text = "OFF"
            resetActionState()
            setStatus("Disabled")
        end
        renderState()
    end)

    local dragging = false
    local dragStart: Vector3? = nil
    local startPos: UDim2? = nil

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and dragStart and startPos and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

bindCharacterLifecycle()
createGui()
addConnection(RunService.Heartbeat:Connect(function()
    if State.Enabled then
        refreshCharacter()
    end
end))
task.spawn(mainLoop)

setStatus("Loaded")