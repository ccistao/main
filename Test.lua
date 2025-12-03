-- Auto Hack PC Script for Flee the Facility
-- FIXED V2: Force Anti-Cheat Delay

local player = game.Players.LocalPlayer
local Players = game:GetService("Players")
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local Replicated = game:GetService("ReplicatedStorage")
-- Settings
local scriptEnabled = false
local hackExtraPC = false
local hackDelay = 4
local waitBeforeHack = 1
local ANTI_CHEAT_DELAY = 8
local currentPC = nil
local isHacking = false
local hackedPCs = {}
local beast = nil
local foundBeast = false
local skipCurrentPC = false
local hidePlatform = nil
local statusLabel = nil

local function log(message)
    print("[AUTO HACK] " .. tostring(message))
end

local function updateStatus(status)
    if statusLabel then
        statusLabel.Text = "Status: " .. tostring(status)
    end
    log("📊 " .. tostring(status))
end

-- Beast detection
local function isBeast(plr)
    if not plr then return false end
    local s = plr:FindFirstChild("TempPlayerStatsModule")
    return s and s:FindFirstChild("IsBeast") and s.IsBeast.Value
end

local function findBeast()
    task.spawn(function()
        while true do
            if not scriptEnabled then
                updateStatus("Script TẮT")
                task.wait(0.1)
            else                          
                task.wait(0.1)
                if foundBeast then
                    if not beast or not Players:FindFirstChild(beast.Name) or not isBeast(beast) then
                        beast, foundBeast = nil, false
                    end
                end

                if not foundBeast then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if isBeast(p) then
                            beast, foundBeast = p, true
                            log("👹 Beast: " .. beast.Name)
                            break
                        end
                    end
                end
            end   
        end
    end)
end
local function isBeastNearby()
    if not foundBeast or not beast or not beast.Character then return false end
    local beastRoot = beast.Character:FindFirstChild("HumanoidRootPart")
    if not beastRoot or not rootPart then return false end
    return (rootPart.Position - beastRoot.Position).Magnitude <= 20
end

local function createHidePlatform()
    if hidePlatform then pcall(function() hidePlatform:Destroy() end) end
    local platform = Instance.new("Part")
    platform.Size = Vector3.new(10, 1, 10)
    platform.Position = Vector3.new(50, 70, 50)
    platform.Anchored = true
    platform.Transparency = 1
    platform.CanCollide = true
    platform.Parent = workspace
    hidePlatform = platform
    return platform
end

local function escapeBeast()
    updateStatus("🚨 Trốn Beast!")
    if not hidePlatform then createHidePlatform() end
    rootPart.CFrame = CFrame.new(50, 71, 50)
    task.wait(9)
    skipCurrentPC = true
end

-- THAY THẾ: spawn block dùng ActionBox (an toàn, không block)
spawn(function()
    if not scriptEnabled then return end
    local playerGui = player:WaitForChild("PlayerGui")
    -- Thay vì chờ tên chung "ScreenGui", ta quan sát khi AutoHackGUI xuất hiện hoặc ChildAdded
    local function bindToScreenGui(screenGui)
        if not screenGui then return end
        local actionBox = screenGui:FindFirstChild("ActionBox")
        if actionBox then
            actionBox:GetPropertyChangedSignal("Visible"):Connect(function()
                if scriptEnabled and actionBox.Visible and isHacking and currentPC then
                    -- guard: đảm bảo RemoteEvent tồn tại
                    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvent")
                    if remote and remote.FireServer then
                        pcall(function()
                            remote:FireServer("Input", "Action", true)
                        end)
                    end
                end
            end)
        else
            -- nếu chưa có ActionBox, lắng nghe ChildAdded để bind khi nó xuất hiện
            screenGui.ChildAdded:Connect(function(child)
                if child.Name == "ActionBox" then
                    child:GetPropertyChangedSignal("Visible"):Connect(function()
                        if scriptEnabled and child.Visible and isHacking and currentPC then
                            local remote = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvent")
                            if remote and remote.FireServer then
                                pcall(function()
                                    remote:FireServer("Input", "Action", true)
                                end)
                            end
                        end
                    end)
                end
            end)
        end
    end

    -- Nếu AutoHackGUI đã có (do createGUI được gọi sau), tìm nó; nếu chưa có, lắng nghe ChildAdded
    local existing = playerGui:FindFirstChild("AutoHackGUI")
    if existing then
        bindToScreenGui(existing)
    else
        playerGui.ChildAdded:Connect(function(child)
            if child.Name == "AutoHackGUI" then
                bindToScreenGui(child)
            end
        end)
    end
end)

local function waitForGameActive()
    updateStatus("⏳ Chờ game chuẩn bị...")

    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local Replicated = game:GetService("ReplicatedStorage")

    -- Lấy GameStatusBox
    local statusBox = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
                         :WaitForChild("GameInfoFrame"):WaitForChild("GameStatusBox")

    if not statusBox or not statusBox:IsA("TextLabel") then
        updateStatus("❌ Không tìm thấy GameStatusBox!")
        return false
    end

    -- Flag IsGameActive
    local isActiveFlag = Replicated:WaitForChild("IsGameActive", 10)

    -- Loop chờ
    while true do
        task.wait(0.1)

        -- Điều kiện 1: HEAD START xuất hiện
        if statusBox.Text and statusBox.Text:upper():find("15 SEC HEAD START") then
            updateStatus("✓ HEAD START xuất hiện... chờ PC load...")
            task.wait(2) -- ⏳ thêm delay giúp map load PC hoàn toàn
            updateStatus("✓ Game bắt đầu! Chạy script...")
            return true
        end

        -- Điều kiện 2: isActiveFlag = true
        if isActiveFlag and isActiveFlag.Value == true then
            updateStatus("✓ Game Active! Chờ PC load...")
            task.wait(2) -- bảo đảm PC đã spawn đủ
            updateStatus("✓ Bắt đầu chạy script...")
            return true
        end
    end
end

-- ⚡ HÀM KIỂM TRA PC HỢP LỆ + CÒN HACK ĐƯỢC
local function isHackablePC(pc)
    if not pc or not pc.Parent then return false end

    -- Name check
    local name = tostring(pc.Name):lower()
    if name:find("prefab") or name:find("dev") or name:find("test") then
        return false
    end

    -- Trigger check
    local hasTrigger = false
    for _, child in ipairs(pc:GetChildren()) do
        if child and child:IsA("BasePart") and child.Name:match("ComputerTrigger") then
            hasTrigger = true
            break
        end
    end
    if not hasTrigger then return false end

    -- Progress check an toàn
    local progress = 0
    local ok, result = pcall(function()
        progress = getPCProgress({computer = pc})
    end)
    if not ok then
        progress = 0
    end

    if progress >= 1 then
        return false
    end

    return true
end
-- ⚡ TIẾN TRÌNH PC (progress)
local function getPCProgress(pcData)
    if not pcData or not pcData.computer then
        return 0
    end

    local pc = pcData.computer
    if not pc or not pc.Parent then
        return 0
    end

    -- Screen progress
    local screen = pc:FindFirstChild("Screen")
    if screen and screen:IsA("BasePart") then
        local c = screen.Color
        if c and c.G and c.R and c.B then
            if c.G > c.R + 0.2 and c.G > c.B + 0.2 then
                return 1
            end
        end
    end

    -- ActionProgress values
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

-- ⚡ LẤY PROGRESS BẢN THÂN NGƯỜI CHƠI
local function getPlayerActionProgress()
    local stats = player:FindFirstChild("TempPlayerStatsModule")
    if not stats then return 0 end

    local p = stats:FindFirstChild("ActionProgress")
    if p and (p:IsA("IntValue") or p:IsA("NumberValue")) then
        return p.Value
    end
    return 0
end


-- ⚡ PC DONE?
local function isPCDone(pcData)
    return getPCProgress(pcData) >= 1
end


-- ⚡ PLAYER KHÁC ĐANG HACK TRÊN TRIGGER NÀY?
local function isTriggerBeingHacked(trigger)
    if not trigger then return false end

    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other.Character then
            local root = other.Character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - trigger.Position).Magnitude <= 10 then
                return true
            end
        end
    end
    return false
end


-- ⚡ CHỌN TRIGGER KHẢ DỤNG NHẤT
local function getAvailableTrigger(pcData)
    if not pcData or not pcData.triggers then return nil end

    for i, trigger in ipairs(pcData.triggers) do
        if not isTriggerBeingHacked(trigger) then
            return trigger
        end
    end

    return nil
end


-- ⚡ TÌM TẤT CẢ PC + TRIGGER VÀ GỘP DỮ LIỆU
local function findAllPCs()
    local found = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        -- Chỉ xét Model
        if obj:IsA("Model") then
            
            local nameLower = obj.Name:lower()
            local isNamedPC = (
                nameLower:find("computer") or 
                nameLower:find("computertable")
            )

            local triggers = {}

            -- Tìm tất cả ComputerTrigger
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("BasePart") and child.Name:match("^ComputerTrigger%d+$") then
                    table.insert(triggers, child)
                end
            end

            -- Nếu có trigger → chắc chắn là PC
            if #triggers > 0 then
                table.insert(found, {
                    computer = obj,
                    triggers = triggers
                })
            
            -- Nếu KHÔNG có trigger nhưng tên chắc chắn là PC → bỏ qua (map lỗi)
            elseif isNamedPC then
                warn("[PC] Model có tên giống PC nhưng không có trigger:", obj.Name)
            end
        end
    end

    return found
end

-- ===== GLOBAL isFindExitPhase() =====
local function isFindExitPhase()
    local statusFolder = Replicated:FindFirstChild("FTF_Status")
    if not statusFolder then return false end

    local phase = statusFolder:FindFirstChild("Phase")
    if not phase then return false end

    return tostring(phase.Value):lower():find("exit") ~= nil
end

local function antiCheatDelay()
    log("🛡️ =================================")
    log("🛡️ ANTI-CHEAT DELAY BẮT ĐẦU")
    log("🛡️ =================================")
    updateStatus("🛡️ Anti-cheat: TP lên trời...")
    
    if not hidePlatform then
        createHidePlatform()
    end
    
    -- FORCE TP NGAY LẬP TỨC
    for i = 1, 3 do
        rootPart.CFrame = CFrame.new(50, 71, 50)
        task.wait(0.2)
    end
    
    log("✓ Đã TP lên (50, 71, 50)")
    
    for i = ANTI_CHEAT_DELAY, 1, -1 do
        if not scriptEnabled then break end
        updateStatus("⏳ Chờ " .. i .. "s...")
        log("⏳ Chờ " .. i .. "s...")
        task.wait(1)
    end
    
    updateStatus("✓ Delay xong!")
    log("✓ Anti-cheat delay hoàn tất!")
    log("🛡️ =================================")
end

-- AUTO PERFECT MINIGAME (NEVER FAIL)
local neverfailtoggle = true

task.spawn(function()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local args = {...}

        if getnamecallmethod() == "FireServer" 
            and args[1] == "SetPlayerMinigameResult"
            and neverfailtoggle then
            
            args[2] = true  -- luôn perfect
            return old(self, unpack(args))
        end

        return old(self, ...)
    end)
end)

local RunService = game:GetService("RunService")
local delayAfterHack = 9
local SAFE_POS = Vector3.new(50, 71, 50)

local jumpTimer = 0
local jumpInterval = 4
local canAutoJump = false
local currentTrigger = nil

RunService.Heartbeat:Connect(function(dt)
    local char = player.Character
    if not char then return end

    humanoid = char:FindFirstChild("Humanoid")
    rootPart = char:FindFirstChild("HumanoidRootPart")

    if canAutoJump and humanoid and rootPart and currentTrigger then
        jumpTimer += dt

        if jumpTimer >= jumpInterval then
            pcall(function()
                local backPos = rootPart.CFrame.Position - (rootPart.CFrame.LookVector * 5)

                rootPart.CFrame = CFrame.new(backPos)
            end)

            task.wait(0.07)

            pcall(function()
                rootPart.CFrame = currentTrigger.CFrame + Vector3.new(0, 0.5, 0)
            end)
            jumpTimer = 0
        end
    end
end)

local function hackPC(pcData)
    if not pcData or not pcData.computer then
        updateStatus("❌ pcData rỗng – bỏ qua")
        return false
    end

    local chosenTrigger = getAvailableTrigger(pcData)
    if not chosenTrigger then
        updateStatus("⏭️ Không có trigger trống, skip PC " .. tostring(pcData.id))
        return false
    end
   
    if chosenTrigger and rootPart then
        rootPart.CFrame = chosenTrigger.CFrame + Vector3.new(0, 0.5, 0)
        currentTrigger = chosenTrigger
        task.wait(0.1)
        canAutoJump = true -- bật auto jump khi TP tới PC
    end
    
    isHacking = true
    currentPC = pcData
    updateStatus("🔵 Đang hack PC " .. tostring(pcData.computer and pcData.computer.Name or "Unknown"))

    pcall(function()
        local hackRemote = Replicated:FindFirstChild("RemoteEvent")
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

    while isHacking and scriptEnabled do
    task.wait(0.15)

    if isBeastNearby() then
        updateStatus("🚨 Beast gần! Trốn...")
        isHacking = false
        currentPC = nil
        canAutoJump = false
        escapeBeast()
        task.wait(0.2)
        allPCs = findAllPCs()
        return false
    end

    -- 🆕 Nếu có người hack chung → tắt auto jump
    if isTriggerBeingHacked(currentTrigger) then
        if canAutoJump then
            updateStatus("👥 Có người hack chung – tắt auto jump")
        end
        canAutoJump = false
    end
    
    if not pcData.computer or not pcData.computer.Parent then
        updateStatus("❌ PC biến mất – dừng hack")
        break
    end

    pcall(function()
        local remote = Replicated:FindFirstChild("RemoteEvent")
        if remote then
            remote:FireServer("Input", "Action", true)
        end
    end)

        local progress = getPlayerActionProgress()
        
        if progress == lastProgress then
            stuckCount = stuckCount + 1
            if stuckCount > 10 then
                updateStatus("⚠️ Stuck! Re-trigger...")

                -- auto jump vẫn chạy ở luồng riêng nên không cần ChangeState ở đây
                pcall(function()
                    local r = Replicated:FindFirstChild("RemoteEvent")
                    if r then
                        r:FireServer("Input", "Action", true)
                    end
                end)
                
                stuckCount = 0
            end
        else
            stuckCount = 0
        end

        if pcData.computer:FindFirstChild("SkillCheckActive")
            and pcData.computer.SkillCheckActive.Value then
            updateStatus("⚠️ Skill check! Auto perfect")
            pcall(function()
                local hr = Replicated:FindFirstChild("RemoteEvent")
                if hr then
                    hr:FireServer("SkillCheck", true)
                end
            end)
        end

        -- Lấy screen PC
        local screen = pcData.computer:FindFirstChild("Screen")

        -- Check 1: dựa vào màu xanh lá
        local doneByColor = false
        if screen and screen:IsA("BasePart") then
            local c = screen.Color
            if c.G > c.R + 0.2 and c.G > c.B + 0.2 then
                doneByColor = true
            end
        end

        -- Check 2: dựa vào progress value >=0.999
        if doneByColor or progress >= 0.999 then
            updateStatus("✔️ Hack xong PC " .. tostring(pcData.id))
            hackedPCs[pcData.id] = true
            allPCs = findAllPCs()

            isHacking = false
            currentPC = nil
            canAutoJump = false

            pcall(function()
                local char = player.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChild("Humanoid")
                    if hrp and hum then
                        local safePos = Vector3.new(50, 73, 50) -- tọa độ mới

                        -- Freeze nhân vật
                        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
                        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

                        -- Teleport 1 lần
                        char:PivotTo(CFrame.new(safePos))

                        -- Chờ ổn định physics
                        task.wait(0.05)

                        -- Unfreeze
                        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
                    end
                end
            end)

            updateStatus("⏳ Chờ " .. delayAfterHack .. "s tránh anti-cheat")
            task.wait(delayAfterHack)
            return true
        end

        lastProgress = progress
    end

    isHacking = false
    currentPC = nil
    canAutoJump = false
    return false
end
    
local function autoExitUnified()
    local lastExitUsed = nil

    local function findExit()
        local exits = {}
        local mapFolder = Replicated:FindFirstChild("CurrentMap")
        local map = mapFolder and mapFolder.Value
        if not map then return exits end

        for _, obj in ipairs(map:GetDescendants()) do
            if obj:IsA("Model") and obj.Name == "ExitDoor" then
                local doorTrigger = obj:FindFirstChild("ExitDoorTrigger")
                local exitArea = obj:FindFirstChild("ExitArea") or doorTrigger

                if exitArea then
                    table.insert(exits, {
                        model = obj,
                        trigger = doorTrigger or nil,
                        area = exitArea
                    })
                end
            end
        end
        return exits
    end

    local function canGoExit()
        local gameStatus = Replicated:FindFirstChild("GameStatus")
        local status = gameStatus and gameStatus.Value or ""
        status = tostring(status):upper()
        return status:find("EXIT") ~= nil
    end

    local function openExit(exitData)
        local trig = exitData.trigger
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if trig and root then
            pcall(function()
                firetouchinterest(root, trig, 0)
                task.wait(0.1)
                firetouchinterest(root, trig, 1)
            end)
        end
    end

    local function escapeExit(exitData)
        local area = exitData.area
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if area and root then
            pcall(function()
                root.CFrame = area.CFrame + Vector3.new(0, 2, 0)
            end)
        end
    end

    while task.wait(0.3) do
        if canGoExit() then
            local exits = findExit()
            if #exits > 0 then
                for _, exitData in ipairs(exits) do
                    if exitData ~= lastExitUsed then
                        if exitData.trigger then
                            openExit(exitData)
                            task.wait(10.5) -- chờ cửa mở
                        end
                        escapeExit(exitData)
                        lastExitUsed = exitData
                        task.wait(1)
                    end
                end
            else
                task.wait(0.5) -- chưa load exit, chờ
            end
        else
            task.wait(0.5) -- chưa tới phase exit, chờ
        end
    end
end

task.spawn(autoExitUnified)

local function mainLoop()
    log("🚀 AUTO HACK ĐANG CHẠY!")

    while true do
        if not scriptEnabled then
            updateStatus("Script TẮT")
            task.wait(0.5)
        else
            updateStatus("⏳ Đợi game...")

            if not waitForGameActive() then
                task.wait(10)
            else
                hackedPCs = {}
                updateStatus("🆕 Game mới!")
                log("═══════════════════════════════")
                log("🆕 GAME MỚI BẮT ĐẦU")
                log("═══════════════════════════════")
                log("Hack Extra PC: " .. (hackExtraPC and "BẬT" or "TẮT"))
                log("Anti-cheat delay: " .. ANTI_CHEAT_DELAY .. "s")

                updateStatus("🔍 Tìm PC...")
                local allPCs = findAllPCs()

                if #allPCs == 0 then
                    updateStatus("⚠️ Không có PC")
                    log("⚠️ Không tìm thấy PC!")
                    task.wait(3)
                else
                    updateStatus("Tìm thấy " .. #allPCs .. " PC")
                    log("✓ Tìm thấy " .. #allPCs .. " PC(s)")

                    for idx, pcData in ipairs(allPCs) do
                        if not scriptEnabled then break end

                        log("")
                        log("╔═══════════════════════════════╗")
                        log("║  PC " .. idx .. "/" .. #allPCs)
                        log("╚═══════════════════════════════╝")

                        if isFindExitPhase() then
                            if hackExtraPC then
                                log("⚠️ Find Exit! Nhưng Extra PC BẬT")
                            else
                                log("⚠️ Find Exit! Dừng hack")
                                break
                            end
                        end

                        hackPC(pcData)
                    end

                    log("═══════════════════════════════")
                    log("✅ HOÀN TẤT TẤT CẢ PC")
                    log("═══════════════════════════════")
                end

                if hackExtraPC then
                    task.wait(2)
                end

                updateStatus("⏳ Đợi Find Exit...")
                log("Đợi Find Exit...")
                local waitStart = tick()

                repeat
                    task.wait(0.5)
                until isFindExitPhase() or (tick() - waitStart > 30)

                if isFindExitPhase() then
                    updateStatus("✓ Find Exit!")
                    log("✓ Phát hiện Find Exit!")
                    task.wait(1)
                    -- spawn để chạy song song, tránh block
                    task.spawn(autoExitUnified)
                end

                updateStatus("🎉 Round hoàn tất!")
                log("🎉 ROUND HOÀN TẤT!")
            end
        end
    end
end

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
    
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 8)
    uiCorner.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 25)
    title.BackgroundTransparency = 1
    title.Text = "AUTO HACK PC"
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
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = toggleButton
    
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
    
    local checkCorner = Instance.new("UICorner")
    checkCorner.CornerRadius = UDim.new(0, 3)
    checkCorner.Parent = checkbox
    
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
            log("✓ AUTO HACK: BẬT")
        else
            toggleButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
            toggleButton.Text = "TẮT"
            log("✗ AUTO HACK: TẮT")
        end
    end)
    
    checkButton.MouseButton1Click:Connect(function()
        hackExtraPC = not hackExtraPC
        if hackExtraPC then
            checkmark.Visible = true
            checkbox.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
            checkbox.BorderColor3 = Color3.fromRGB(255, 80, 80)
            checkLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
            log("✓ HACK EXTRA PC: BẬT")
        else
            checkmark.Visible = false
            checkbox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            checkbox.BorderColor3 = Color3.fromRGB(120, 120, 120)
            checkLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
            log("✗ HACK EXTRA PC: TẮT")
        end
    end)
    
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos
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
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

log("═══════════════════════════════════════")
log("AUTO HACK PC - FLEE THE FACILITY")
log("═══════════════════════════════════════")
log("✓ Anti-cheat delay: " .. ANTI_CHEAT_DELAY .. "s")
log("✓ Force TP sau mỗi PC")
createGUI()
findBeast()
task.spawn(mainLoop)
log("✓ Script loaded!")
