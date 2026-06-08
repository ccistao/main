--!strict
-- Tet2_clean.lua
-- Clean connectivity/proof file created from ChatGPT GitHub connector.
-- This file intentionally contains only safe structure: services, state, logger, and GUI toggle.

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local State = {
    Enabled = false,
    StatusLabel = nil :: TextLabel?,
}

local function log(message: string)
    print("[TET2-CLEAN] " .. tostring(message))
end

local function setStatus(message: string)
    if State.StatusLabel then
        State.StatusLabel.Text = "Status: " .. message
    end
    log(message)
end

local function createGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Tet2CleanGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 210, 0, 95)
    frame.Position = UDim2.new(0.5, -105, 0, 24)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 24)
    title.Position = UDim2.new(0, 8, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "TET2 CLEAN"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

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

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 20)
    status.Position = UDim2.new(0, 8, 0, 66)
    status.BackgroundTransparency = 1
    status.Text = "Status: Ready"
    status.TextColor3 = Color3.fromRGB(150, 220, 150)
    status.TextSize = 10
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    State.StatusLabel = status

    toggle.MouseButton1Click:Connect(function()
        State.Enabled = not State.Enabled

        if State.Enabled then
            toggle.BackgroundColor3 = Color3.fromRGB(55, 170, 80)
            toggle.Text = "ON"
            setStatus("Enabled")
        else
            toggle.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
            toggle.Text = "OFF"
            setStatus("Disabled")
        end
    end)
end

createGui()
setStatus("Loaded")
