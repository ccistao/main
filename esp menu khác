local ui = loadstring(game:HttpGet("https://raw.githubusercontent.com/ghostofcelleron/Celeron/refs/heads/main/daff"))()

local win = ui:Create({
    Name = "Celeron's GUI (Flee The Facility)",
    ThemeColor = Color3.fromRGB(45, 11, 11),
    ThemeGradient = Color3.fromRGB(11, 22, 66),
    StartupSound = "rbxassetid://6958727243",
    ThemeFont = Enum.Font.GothamBold,
	ToggledSideBar = true
})

local maintab = win:Tab("Main")
local tpstab = win:Tab("Teleports")
local esptab = win:Tab("Visual")
local funtab = win:Tab("Misc")
local helptab = win:Tab("Info")

maintab:Label("Script Made By Celeron + Daffy!")
tpstab:Label("General Areas.")
esptab:Label("Visual Features.")
funtab:Label("Other Features.")
helptab:Label("GUI Controls Are Below, Script Credits Are At The Bottom!")
helptab:Label("Show / Hide GUI: Right Alt")

getgenv().lastSliderSet = nil
getgenv().humanoidConnection = nil

getgenv().applySpeed = function()
	if not getgenv().lastSliderSet then return end

	if (game:GetService("Players").LocalPlayer.Character or game:GetService("Players").LocalPlayer.CharacterAdded:Wait()):FindFirstChildOfClass("Humanoid") then
		if (game:GetService("Players").LocalPlayer.Character or game:GetService("Players").LocalPlayer.CharacterAdded:Wait()):FindFirstChildOfClass("Humanoid").WalkSpeed ~= getgenv().lastSliderSet then
			(game:GetService("Players").LocalPlayer.Character or game:GetService("Players").LocalPlayer.CharacterAdded:Wait()):FindFirstChildOfClass("Humanoid").WalkSpeed = getgenv().lastSliderSet
		end

		if getgenv().humanoidConnection then
			getgenv().humanoidConnection:Disconnect()
		end

		getgenv().humanoidConnection = (game:GetService("Players").LocalPlayer.Character or game:GetService("Players").LocalPlayer.CharacterAdded:Wait()):FindFirstChildOfClass("Humanoid"):GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if (game:GetService("Players").LocalPlayer.Character or game:GetService("Players").LocalPlayer.CharacterAdded:Wait()):FindFirstChildOfClass("Humanoid").WalkSpeed ~= getgenv().lastSliderSet then
				(game:GetService("Players").LocalPlayer.Character or game:GetService("Players").LocalPlayer.CharacterAdded:Wait()):FindFirstChildOfClass("Humanoid").WalkSpeed = getgenv().lastSliderSet
			end
		end)
	end
end

maintab:Textbox("Player Speed", function(v)
	getgenv().lastSliderSet = (v == 8) and 16 or v
	getgenv().applySpeed()
end)

maintab:Toggle("Automatic Hacking", "Hacking Is Always Successful Without Hitting Quick Time Events.", function()
_G.AutomaticHackingEnabled = not _G.AutomaticHackingEnabled

game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "Automatic Hacking";
    Text = _G.AutomaticHackingEnabled and "Enabled." or "Disabled.";
    Duration = 3;
})

while _G.AutomaticHackingEnabled do
    wait(0.1)
    local args = {
        "SetPlayerMinigameResult",
        true
    }
    game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
end
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local speaker = Players.LocalPlayer
local thirdPersonEnabled = false
local cameraLoop = nil

local function notify(title, text)
	StarterGui:SetCore("SendNotification", {
		Title = title,
		Text = text,
		Duration = 3
	})
end

maintab:Toggle("Always Allow Third Person", "Allows You To Go Third Person As The Beast.", function()
	thirdPersonEnabled = not thirdPersonEnabled

	if thirdPersonEnabled then
		notify("Always Allow Third Person", "Enabled.")
		speaker.CameraMode = Enum.CameraMode.Classic
		cameraLoop = RunService.RenderStepped:Connect(function()
			if speaker.CameraMode ~= Enum.CameraMode.Classic then
				speaker.CameraMode = Enum.CameraMode.Classic
			end
		end)
	else
		notify("Always Allow Third Person", "Disabled.")
		if cameraLoop then
			cameraLoop:Disconnect()
			cameraLoop = nil
		end
	end
end)

local lastClickTime = 0
local clickCooldown = 3

maintab:Button("Self Revive (Use In Freezer, Double Click To Confirm.)", "Use This As A Last Resort. You Cannot Hack Computers After Using.", function()
        local currentTime = tick()

        if currentTime - lastClickTime <= clickCooldown then
            local player = game:GetService("Players").LocalPlayer
            local character = player.Character

            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.Health = 0
                end
            end

            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Self Revive";
                Text = "You can no longer hack computers! You can still escape however.";
                Duration = 10;
            })
            lastClickTime = 0
        else
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Self Revive";
                Text = "Click again to confirm.";
                Duration = 3;
            })

            lastClickTime = currentTime
        end
    end)

maintab:Button("Join Mid-Game", "Teleports You To The Map, May Softlock Survivors By Hacking Computers.", function()
local player = game:GetService("Players").LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local function findOBSpawnPadInParent()
    for _, model in pairs(game.Workspace:GetChildren()) do
        if model:IsA("Model") then
            local computerTable = model:FindFirstChild("ComputerTable")
            if computerTable and computerTable:IsA("Model") then
                local spawnPad = model:FindFirstChild("OBSpawnPad")
                if spawnPad and spawnPad:IsA("BasePart") then
                    return spawnPad
                end
            end
        end
    end
    return nil
end

local targetSpawnPad = findOBSpawnPadInParent()

if targetSpawnPad then
    character:SetPrimaryPartCFrame(targetSpawnPad.CFrame + Vector3.new(0, 5, 0))
end
end)

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")

local playerESPEnabled = false

local function notify(title, text)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Duration = 3
    })
end

local function applyHighlight(player)
    if player == Players.LocalPlayer then return end
    local char = player.Character
    if not char or not char:IsA("Model") then return end

    local existingHighlight = CoreGui:FindFirstChild("ESP_" .. player.Name)

    if playerESPEnabled then
        if not existingHighlight then
            local highlight = Instance.new("Highlight")
            highlight.Name = "ESP_" .. player.Name
            highlight.Adornee = char
            highlight.FillColor = Color3.fromRGB(0, 255, 255)
            highlight.OutlineColor = Color3.new(1, 1, 1)
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = CoreGui
        end
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            humanoid.NameDisplayDistance = math.huge
        end
    else
        if existingHighlight then existingHighlight:Destroy() end
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
            humanoid.NameDisplayDistance = 100
        end
    end
end

esptab:Toggle("Player ESP", function()
    playerESPEnabled = not playerESPEnabled
    notify("Player ESP", playerESPEnabled and "Enabled." or "Disabled.")

    for _, player in ipairs(Players:GetPlayers()) do
        applyHighlight(player)
    end

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            if playerESPEnabled then
                task.wait(1)
                applyHighlight(player)
            end
        end)
    end)
end)


esptab:Toggle("Computer ESP", function()
	computerESPEnabled = not computerESPEnabled
	notify("Computer ESP", computerESPEnabled and "Enabled." or "Disabled.")

	for _, model in ipairs(Workspace:GetDescendants()) do
		if model:IsA("Model") and model.Name == "ComputerTable" then
			local highlight = model:FindFirstChild("ComputerESPHighlight")
			if computerESPEnabled then
				if not highlight then
					local screenColor = Color3.fromRGB(255, 255, 255)
					for _, part in ipairs(model:GetDescendants()) do
						if part:IsA("BasePart") and part.Name == "Screen" then
							screenColor = part.Color
							break
						end
					end
					local newHighlight = Instance.new("Highlight")
					newHighlight.Name = "ComputerESPHighlight"
					newHighlight.Adornee = model
					newHighlight.FillColor = screenColor
					newHighlight.OutlineColor = Color3.new(1, 1, 1)
					newHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					newHighlight.Parent = model
				end
			elseif highlight then
				highlight:Destroy()
			end
		end
	end
end)

esptab:Toggle("Exit ESP", function()
	exitESPEnabled = not exitESPEnabled
	notify("Exit-Door ESP", exitESPEnabled and "Enabled." or "Disabled.")

	for _, model in ipairs(Workspace:GetDescendants()) do
		if model:IsA("Model") and model.Name == "ExitDoor" then
			local highlight = model:FindFirstChild("ExitESPHighlight")
			if exitESPEnabled then
				if not highlight then
					local newHighlight = Instance.new("Highlight")
					newHighlight.Name = "ExitESPHighlight"

					if model.PrimaryPart then
						newHighlight.Adornee = model.PrimaryPart
					else
						newHighlight.Adornee = model
					end
					
					newHighlight.FillColor = Color3.new(1, 1, 0)
					newHighlight.OutlineTransparency = 1
					newHighlight.FillTransparency = 0.5
					newHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					newHighlight.Parent = model
				end
			elseif highlight then
				highlight:Destroy()
			end
		end
	end
end)

funtab:Button("FE Audio Control", function()
    loadstring(game:HttpGet("https://pastebin.com/raw/3dWP6BW4"))()
end)

tpstab:Button("Spawn", function()
    game.Players.LocalPlayer.Character:SetPrimaryPartCFrame(CFrame.new(111, 8, -414))
end)

tpstab:Button("Map Voting", function()
    game.Players.LocalPlayer.Character:SetPrimaryPartCFrame(CFrame.new(157, 4, -344))
end)

tpstab:Button("Cave", function()
    game.Players.LocalPlayer.Character:SetPrimaryPartCFrame(CFrame.new(279, -11, -366))
end)

tpstab:Button("Trading Servers (Min. Level 6)", function()
    game.Players.LocalPlayer.Character:SetPrimaryPartCFrame(CFrame.new(65, 4, -308))
end)

tpstab:Label("In-Game Areas.")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local function getRoot()
    return player.Character or player.CharacterAdded:Wait(), "HumanoidRootPart"
end

local function getOrderedModels(name)
    local models = {}
    local function scan(parent)
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("Model") and obj.Name == name then
                table.insert(models, obj)
            end
            if #obj:GetChildren() > 0 then
                scan(obj)
            end
        end
    end
    scan(Workspace)

    table.sort(models, function(a, b)
        local ao = a:GetAttribute("Order") or 0
        local bo = b:GetAttribute("Order") or 0
        return ao < bo
    end)

    return models
end

local function Teleport(model)
    if not model or not model.PrimaryPart then return end
    local char, rootName = getRoot()
    local root = char:WaitForChild(rootName)
    local front = model.PrimaryPart.CFrame.Position + model.PrimaryPart.CFrame.LookVector * 5
    root.CFrame = CFrame.new(front)
end

local computerIndex = 1
local exitIndex = 1
local freezerIndex = 1

tpstab:Button("Computer TP", function()
    local models = getOrderedModels("ComputerTable")
    if #models == 0 then return end
    local model = models[computerIndex]
    Teleport(model)
    computerIndex = computerIndex + 1
    if computerIndex > #models then computerIndex = 1 end
end)

tpstab:Button("Exit TP", function()
    local models = getOrderedModels("ExitDoor")
    if #models == 0 then return end
    local model = models[exitIndex]
    Teleport(model)
    exitIndex = exitIndex + 1
    if exitIndex > #models then exitIndex = 1 end
end)

tpstab:Button("Freezer TP", function()
    local models = getOrderedModels("FreezePod")
    if #models == 0 then return end
    local model = models[freezerIndex]
    Teleport(model)
    freezerIndex = freezerIndex + 1
    if freezerIndex > #models then freezerIndex = 1 end
end)

funtab:Button("Infinite Yield", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end)

helptab:Button("Copy Owner Discord Username", function()
local StarterGui = game:GetService("StarterGui")

StarterGui:SetCore("SendNotification", {
    Title = "Discord Username",
    Text = "Copied to your clipboard!",
    Duration = 3,
    Button1 = "alright fella",
})
setclipboard("ghostofcelleron")
end)

helptab:Button("Copy Discord Server Invite", function()
local StarterGui = game:GetService("StarterGui")

StarterGui:SetCore("SendNotification", {
    Title = "Discord Invite",
    Text = "Copied to your clipboard!",
    Duration = 3,
    Button1 = "alright fella",
})
setclipboard("https://discord.gg/8stFYxJv4R")
end)
