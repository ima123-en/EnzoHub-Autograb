if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local AnimalsData = {}
local okA, resA = pcall(function()
    return require(ReplicatedStorage:WaitForChild("Datas"):WaitForChild("Animals"))
end)
if okA then AnimalsData = resA end

local allAnimalsCache = {}
local PromptMemoryCache = {}
local InternalStealCache = {}
local LastTargetUID = nil

local AUTO_STEAL_PROX_RADIUS = 1000
local PRIORITY_STEAL_RADIUS = 60
local IsStealingInternal = false
local StealProgressInternal = 0
local CurrentStealTargetInternal = nil

local autoStealEnabled = false
local stealConnection = nil

local function getHRP()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso"))
end

local function isMyBase(plotName)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") then
            return yourBase.Enabled == true
        end
    end
    return false
end

local function scanSinglePlot(plot)
    if not plot or not plot:IsA("Model") then return end
    if isMyBase(plot.Name) then return end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return end
    for _, podium in ipairs(podiums:GetChildren()) do
        if podium:IsA("Model") and podium:FindFirstChild("Base") then
            local animalName = "Unknown"
            local spawn = podium.Base:FindFirstChild("Spawn")
            if spawn then
                for _, child in ipairs(spawn:GetChildren()) do
                    if child:IsA("Model") and child.Name ~= "PromptAttachment" then
                        animalName = child.Name
                        local animalInfo = AnimalsData[animalName]
                        if animalInfo and animalInfo.DisplayName then
                            animalName = animalInfo.DisplayName
                        end
                        break
                    end
                end
            end
            local uid = plot.Name .. "_" .. podium.Name
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].uid == uid then
                    table.remove(allAnimalsCache, i)
                end
            end
            table.insert(allAnimalsCache, {
                name = animalName,
                plot = plot.Name,
                slot = podium.Name,
                worldPosition = podium:GetPivot().Position,
                uid = uid,
            })
        end
    end
end

local function initializeScanner()
    task.wait(2)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:IsA("Model") then
            scanSinglePlot(plot)
        end
    end
    plots.ChildAdded:Connect(function(plot)
        if plot:IsA("Model") then
            task.wait(0.5)
            scanSinglePlot(plot)
        end
    end)
    plots.ChildRemoved:Connect(function(plot)
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == plot.Name then
                table.remove(allAnimalsCache, i)
            end
        end
    end)
    local function watchPlot(plot)
        if not plot or not plot:IsA("Model") then return end
        local podiums = plot:WaitForChild("AnimalPodiums", 5)
        if not podiums then return end
        podiums.ChildAdded:Connect(function(podium)
            task.wait(0.3)
            scanSinglePlot(plot)
        end)
        podiums.ChildRemoved:Connect(function(podium)
            local uid = plot.Name .. "_" .. podium.Name
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].uid == uid then
                    table.remove(allAnimalsCache, i)
                    PromptMemoryCache[uid] = nil
                end
            end
        end)
        for _, podium in ipairs(podiums:GetChildren()) do
            if podium:IsA("Model") and podium:FindFirstChild("Base") then
                local spawnFolder = podium.Base:FindFirstChild("Spawn")
                if spawnFolder then
                    spawnFolder.ChildAdded:Connect(function()
                        task.wait(0.1)
                        scanSinglePlot(plot)
                    end)
                    spawnFolder.ChildRemoved:Connect(function()
                        task.wait(0.1)
                        scanSinglePlot(plot)
                    end)
                end
            end
        end
    end
    for _, plot in ipairs(plots:GetChildren()) do
        task.spawn(watchPlot, plot)
    end
    plots.ChildAdded:Connect(function(plot)
        task.spawn(watchPlot, plot)
    end)
end

local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cachedPrompt = PromptMemoryCache[animalData.uid]
    if cachedPrompt and cachedPrompt.Parent then
        cachedPrompt.Enabled = true -- Bypass, falls deaktiviert
        return cachedPrompt
    end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    local base = podium:FindFirstChild("Base")
    if not base then return nil end
    local spawn = base:FindFirstChild("Spawn")
    if not spawn then return nil end
    local attach = spawn:FindFirstChild("PromptAttachment")
    if not attach then return nil end
    for _, p in ipairs(attach:GetChildren()) do
        if p:IsA("ProximityPrompt") then
            p.Enabled = true -- Force Enable Bypass
            PromptMemoryCache[animalData.uid] = p
            return p
        end
    end
    return nil
end

local function shouldSteal(animalData)
    if not animalData or not animalData.worldPosition then return false end
    local hrp = getHRP()
    if not hrp then return false end
    local dist = (hrp.Position - animalData.worldPosition).Magnitude
    return dist <= AUTO_STEAL_PROX_RADIUS
end

local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then
        return
    end
    local data = {holdCallbacks = {}, triggerCallbacks = {}, ready = true}
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1) == "table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function) == "function" then
                table.insert(data.holdCallbacks, conn.Function)
            end
        end
    end
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2) == "table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function) == "function" then
                table.insert(data.triggerCallbacks, conn.Function)
            end
        end
    end
    if (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0) then
        InternalStealCache[prompt] = data
    end
end

local function executeInternalStealAsync(prompt, animalData, durationOverride)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then return false end
    data.ready = false
    IsStealingInternal = true
    StealProgressInternal = 0
    CurrentStealTargetInternal = animalData
    task.spawn(function()
        if prompt then prompt.Enabled = true end -- Force Enable
        for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
        local startTime = tick()
        local duration = (prompt.HoldDuration and prompt.HoldDuration > 0) and prompt.HoldDuration or (durationOverride or 1.0)
        while tick() - startTime < duration do
            local elapsed = tick() - startTime
            StealProgressInternal = math.clamp(elapsed / duration, 0, 1)
            task.wait()
            if not prompt or not prompt.Parent then break end
            if not prompt.Enabled then prompt.Enabled = true end -- Anti-Interruption Bypass
        end
        StealProgressInternal = 1
        for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
        data.ready = true
        IsStealingInternal = false
        StealProgressInternal = 0
        CurrentStealTargetInternal = nil
    end)
    return true
end

local function attemptSteal(prompt, animalData, durationOverride)
    if not prompt or not prompt.Parent then return false end
    prompt.Enabled = true -- Sicherstellen, dass sie an ist
    buildStealCallbacks(prompt)
    if not InternalStealCache[prompt] then
        return false
    end
    return executeInternalStealAsync(prompt, animalData, durationOverride)
end

local function getNearestAnimal()
    local hrp = getHRP()
    if not hrp then return nil end
    local nearest, minDist = nil, math.huge
    for _, animalData in ipairs(allAnimalsCache) do
        if not isMyBase(animalData.plot) and animalData.worldPosition then
            local dist = (hrp.Position - animalData.worldPosition).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = animalData
            end
        end
    end
    return nearest
end

local function startAutoSteal(durationOverride)
    if stealConnection then stealConnection:Disconnect() end
    autoStealEnabled = true
    stealConnection = RunService.Heartbeat:Connect(function()
        if not autoStealEnabled or IsStealingInternal then return end
        local target = getNearestAnimal()
        if not target or not shouldSteal(target) then return end
        if LastTargetUID ~= target.uid then LastTargetUID = target.uid end
        local prompt = PromptMemoryCache[target.uid]
        if not prompt or not prompt.Parent then
            prompt = findProximityPromptForAnimal(target)
        end
        if prompt then
            attemptSteal(prompt, target, durationOverride)
        end
    end)
end

local function stopAutoSteal()
    autoStealEnabled = false
    if stealConnection then stealConnection:Disconnect() stealConnection = nil end
    IsStealingInternal = false
    StealProgressInternal = 0
    CurrentStealTargetInternal = nil
end

task.spawn(initializeScanner)

getgenv().LuminaAutoSteal = {
    AllAnimalsCache = allAnimalsCache,
    PromptMemoryCache = PromptMemoryCache,
    InternalStealCache = InternalStealCache,
    IsStealing = function() return IsStealingInternal end,
    StealProgress = function() return StealProgressInternal end,
    CurrentTarget = function() return CurrentStealTargetInternal end,
    Start = function() startAutoSteal(1.0) end,
    Stop = stopAutoSteal,
    GetNearestAnimal = getNearestAnimal,
    ShouldSteal = shouldSteal,
    FindPrompt = findProximityPromptForAnimal,
    AttemptSteal = attemptSteal
}

local SAVE_KEY = "AutoGrab_Settings_" .. LocalPlayer.UserId
local isInteractingWithSlider = false

pcall(function()
    if LocalPlayer.PlayerGui:FindFirstChild("AutoGrabPanel") then
        LocalPlayer.PlayerGui:FindFirstChild("AutoGrabPanel"):Destroy()
    end
end)

if getgenv().AutoGrabSystem then
    pcall(function() getgenv().AutoGrabSystem.Disable() end)
end

getgenv().AutoGrabSystem = {
    Active = true,
    Mode = "Highest",
    IsStealing = false,
    StealProgress = 0,
    CurrentPetName = "",
    StealDuration = 1.0,
    StealCount = 0,
    Running = true,
    GuiScale = 50,
    MainPos = {ScaleX = 1, ScaleY = 0.5, OffsetX = -285, OffsetY = -70}
}
local AG = getgenv().AutoGrabSystem

local function SaveSettings()
    pcall(function()
        if writefile then
            local data = {
                Mode = AG.Mode,
                GuiScale = AG.GuiScale,
                MainPos = AG.MainPos
            }
            writefile(SAVE_KEY .. ".json", HttpService:JSONEncode(data))
        end
    end)
end

local function LoadSettings()
    pcall(function()
        if readfile and isfile and isfile(SAVE_KEY .. ".json") then
            local data = HttpService:JSONDecode(readfile(SAVE_KEY .. ".json"))
            if data.Mode then AG.Mode = data.Mode end
            if data.GuiScale ~= nil then AG.GuiScale = data.GuiScale end
            if data.MainPos and type(data.MainPos) == "table" then
                AG.MainPos = {
                    ScaleX = tonumber(data.MainPos.ScaleX) or 1,
                    ScaleY = tonumber(data.MainPos.ScaleY) or 0.5,
                    OffsetX = tonumber(data.MainPos.OffsetX) or -285,
                    OffsetY = tonumber(data.MainPos.OffsetY) or -70
                }
            end
        end
    end)
end

LoadSettings()

local Database = {}
pcall(function()
    local m = require(ReplicatedStorage:WaitForChild("Datas"):WaitForChild("Animals"))
    for k, v in pairs(m) do
        if type(v) == "table" and v.Generation then
            Database[k] = v.Generation
            if v.DisplayName then Database[v.DisplayName] = v.Generation end
        end
    end
end)

local function findPromptInPodium(podium)
    if not podium then return nil, nil end
    local base = podium:FindFirstChild("Base")
    local spawn = base and base:FindFirstChild("Spawn")
    local attach = spawn and spawn:FindFirstChild("PromptAttachment")
    if attach then
        local p = attach:FindFirstChildOfClass("ProximityPrompt")
        if p then
            p.Enabled = true -- Bypass: Aktiviert die Prompt auf unserem Client, falls deaktiviert!
            return p, attach.WorldPosition
        end
    end
    local podiumCenter = podium:GetPivot().Position
    for _, d in pairs(podium:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            d.Enabled = true -- Bypass
            local pos = nil
            if d.Parent:IsA("Attachment") then
                pos = d.Parent.WorldPosition
            elseif d.Parent:IsA("BasePart") then
                pos = d.Parent.Position
            end
            if pos and (pos - podiumCenter).Magnitude < 3 then
                return d, pos
            end
        end
    end
    return nil, nil
end

local function getHighestAnimal()
    local hrp = getHRP()
    if not hrp then return nil end
    local bestAnimal = nil
    local maxGen = -1
    local minDist = math.huge

    for _, animalData in ipairs(allAnimalsCache) do
        if not isMyBase(animalData.plot) and animalData.worldPosition then
            local dist = (hrp.Position - animalData.worldPosition).Magnitude
            if dist <= AUTO_STEAL_PROX_RADIUS then
                local gen = Database[animalData.name] or 0
                if gen > maxGen then
                    maxGen = gen
                    bestAnimal = animalData
                    minDist = dist
                elseif gen == maxGen and dist < minDist then
                    bestAnimal = animalData
                    minDist = dist
                end
            end
        end
    end
    return bestAnimal
end

local function getPriorityTarget()
    local PS = getgenv().PrioritySystem
    if not PS or not PS.SelectedData then return nil end
    local d = PS.SelectedData
    if not d.plot or not d.slot then return nil end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(d.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(tostring(d.slot))
    if not podium then return nil end
    local prompt, pos = findPromptInPodium(podium)
    if not prompt or not pos then return nil end
    local hrp = getHRP()
    if not hrp then return nil end
    local dist = (hrp.Position - pos).Magnitude
    if dist > PRIORITY_STEAL_RADIUS then
        return nil
    end
    return {
        prompt = prompt,
        position = pos,
        petName = d.name or "?",
        petValue = d.genValue or 0,
        uid = d.plot .. "_" .. tostring(d.slot)
    }
end

local function getTarget()
    if AG.Mode == "Priority" then
        local prio = getPriorityTarget()
        if prio then
            return prio
        else
            -- FALLBACK: Wenn das Priority Tier gerade gestohlen wird/weg ist, 
            -- klauen wir stattdessen das nächste oder beste Tier, damit wir nicht dumm rumstehen!
            local fallback = getHighestAnimal() or getNearestAnimal()
            if fallback then
                local LAS = getgenv().LuminaAutoSteal
                local prompt = LAS and LAS.FindPrompt(fallback)
                if prompt then
                    return {
                        prompt = prompt,
                        position = fallback.worldPosition,
                        petName = fallback.name or "?",
                        petValue = Database[fallback.name] or 0,
                        uid = fallback.uid
                    }
                end
            end
        end
    elseif AG.Mode == "Highest" then
        local highest = getHighestAnimal()
        if highest then
            local LAS = getgenv().LuminaAutoSteal
            local prompt = LAS and LAS.FindPrompt(highest)
            if prompt then
                return {
                    prompt = prompt,
                    position = highest.worldPosition,
                    petName = highest.name or "?",
                    petValue = Database[highest.name] or 0,
                    uid = highest.uid
                }
            end
        end
    else
        local LAS = getgenv().LuminaAutoSteal
        if not LAS then return nil end
        local nearest = LAS.GetNearestAnimal()
        if not nearest then return nil end
        if not LAS.ShouldSteal(nearest) then return nil end
        local prompt = LAS.FindPrompt(nearest)
        if not prompt then return nil end
        return {
            prompt = prompt,
            position = nearest.worldPosition,
            petName = nearest.name or "?",
            petValue = Database[nearest.name] or 0,
            uid = nearest.uid
        }
    end
    return nil
end

local lastStealCount = 0
local function detectSteal()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        local count = 0
        for _, c in pairs(bp:GetChildren()) do
            if c:IsA("Tool") then count = count + 1 end
        end
        local char = LocalPlayer.Character
        if char then
            for _, c in pairs(char:GetChildren()) do
                if c:IsA("Tool") then count = count + 1 end
            end
        end
        if count > lastStealCount then
            lastStealCount = count
            return true
        end
        lastStealCount = count
    end
    return false
end

pcall(function()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, c in pairs(bp:GetChildren()) do
            if c:IsA("Tool") then lastStealCount = lastStealCount + 1 end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, c in pairs(char:GetChildren()) do
            if c:IsA("Tool") then lastStealCount = lastStealCount + 1 end
        end
    end
end)

local ragdollCooldown = false
local ragdollEndTime = 0

local function startRagdollCooldown()
    ragdollCooldown = true
    ragdollEndTime = tick() + 2
    local LAS = getgenv().LuminaAutoSteal
    if LAS then LAS.Stop() end
end

local function inRagdollCooldown()
    if not ragdollCooldown then return false end
    if tick() >= ragdollEndTime then
        ragdollCooldown = false
        return false
    end
    return true
end

local function setupRagdollListener()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Ragdoll then
            startRagdollCooldown()
        end
    end)
end

setupRagdollListener()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1)
    setupRagdollListener()
end)

local thread
thread = coroutine.create(function()
    while AG.Running do
        local ok, err = pcall(function()
            if inRagdollCooldown() then
                AG.IsStealing = false
                AG.CurrentPetName = ""
                AG.StealProgress = 0
                local LAS = getgenv().LuminaAutoSteal
                if LAS then LAS.Stop() end
                return
            end
            if not AG.Active then
                AG.IsStealing = false
                AG.CurrentPetName = ""
                AG.StealProgress = 0
                local LAS = getgenv().LuminaAutoSteal
                if LAS then LAS.Stop() end
                return
            end
            local LAS = getgenv().LuminaAutoSteal
            if not LAS then return end
            local target = getTarget()
            if not target or not target.prompt or not target.prompt.Parent then
                AG.IsStealing = false
                AG.CurrentPetName = ""
                LAS.Stop()
                return
            end
            LAS.Start()

            AG.IsStealing = true
            AG.CurrentPetName = target.petName
            AG.StealProgress = 0

            LAS.AttemptSteal(
                target.prompt,
                {uid = target.uid, worldPosition = target.position, name = target.petName},
                AG.StealDuration
            )

            local startTime = tick()
            local dur = target.prompt.HoldDuration and target.prompt.HoldDuration > 0 and target.prompt.HoldDuration or AG.StealDuration

            while tick() - startTime < (dur + 0.1) do
                if inRagdollCooldown() then
                    AG.IsStealing = false
                    AG.CurrentPetName = ""
                    AG.StealProgress = 0
                    LAS.Stop()
                    return
                end

                if not target.prompt or not target.prompt.Parent then
                    break
                end

                AG.StealProgress = math.clamp((tick() - startTime) / dur, 0, 1)

                if detectSteal() then
                    AG.StealCount = AG.StealCount + 1
                    AG.StealProgress = 1
                    break
                end

                task.wait(1/60)
            end

            if AG.StealProgress < 1 then
                AG.StealProgress = 1
                task.wait(0.1)
            end

            AG.IsStealing = false
            AG.CurrentPetName = ""
            AG.StealProgress = 0
        end)
        if not ok then warn("AutoGrab loop error:", err) end
        task.wait(0.1)
    end
end)
coroutine.resume(thread)

task.spawn(function()
    while AG.Running do
        task.wait(5)
        if coroutine.status(thread) == "dead" then
            thread = coroutine.create(function()
                while AG.Running do
                    local ok, err = pcall(function()
                        if inRagdollCooldown() then
                            AG.IsStealing = false
                            AG.CurrentPetName = ""
                            AG.StealProgress = 0
                            local LAS = getgenv().LuminaAutoSteal
                            if LAS then LAS.Stop() end
                            return
                        end
                        if not AG.Active then
                            AG.IsStealing = false
                            AG.CurrentPetName = ""
                            AG.StealProgress = 0
                            local LAS = getgenv().LuminaAutoSteal
                            if LAS then LAS.Stop() end
                            return
                        end
                        local LAS = getgenv().LuminaAutoSteal
                        if not LAS then return end
                        local target = getTarget()
                        if target and target.prompt and target.prompt.Parent then
                            LAS.Start()
                            AG.IsStealing = true
                            AG.CurrentPetName = target.petName

                            local st = tick()
                            local dur = target.prompt.HoldDuration and target.prompt.HoldDuration > 0 and target.prompt.HoldDuration or AG.StealDuration

                            LAS.AttemptSteal(
                                target.prompt,
                                {uid = target.uid, worldPosition = target.position, name = target.petName},
                                AG.StealDuration
                            )

                            while tick() - st < (dur + 0.1) do
                                if inRagdollCooldown() then
                                    AG.IsStealing = false
                                    AG.CurrentPetName = ""
                                    AG.StealProgress = 0
                                    LAS.Stop()
                                    return
                                end
                                if not target.prompt or not target.prompt.Parent then break end

                                AG.StealProgress = math.clamp((tick() - st) / dur, 0, 1)

                                if detectSteal() then
                                    AG.StealCount = AG.StealCount + 1
                                    AG.StealProgress = 1
                                    break
                                end
                                task.wait(1/60)
                            end

                            AG.IsStealing = false
                            AG.CurrentPetName = ""
                            AG.StealProgress = 0
                        end
                    end)
                    if not ok then warn("AutoGrab watchdog error:", err) end
                    task.wait(0.15)
                end
            end)
            coroutine.resume(thread)
        end
    end
end)

local gui = LocalPlayer:WaitForChild("PlayerGui")
local Screen = Instance.new("ScreenGui")
Screen.Name = "AutoGrabPanel"
Screen.ResetOnSpawn = false
Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Screen.Parent = gui
AG.ScreenGui = Screen

local GlobalUIScale = Instance.new("UIScale")
GlobalUIScale.Name = "GlobalScale"
GlobalUIScale.Scale = 0.3 + (1.0 - 0.3) * ((AG.GuiScale - 20) / (100 - 20))
GlobalUIScale.Parent = Screen

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 270, 0, 305)
Main.Position = UDim2.new(AG.MainPos.ScaleX, AG.MainPos.OffsetX, AG.MainPos.ScaleY, AG.MainPos.OffsetY)
Main.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
Main.BorderSizePixel = 0
Main.Parent = Screen
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", Main).Color = Color3.fromRGB(60, 60, 60)

local OpenButton = Instance.new("TextButton")
OpenButton.Name             = "OpenButton"
OpenButton.Size             = UDim2.new(0, 150, 0, 32)
OpenButton.Position         = UDim2.new(1, -165, 0.5, -70)
OpenButton.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
OpenButton.BorderSizePixel  = 0
OpenButton.Text             = "Open Auto Grab"
OpenButton.TextColor3       = Color3.fromRGB(220, 220, 220)
OpenButton.Font             = Enum.Font.GothamBold
OpenButton.TextSize         = 12
OpenButton.AutoButtonColor  = false
OpenButton.Visible          = false
OpenButton.Parent           = Screen
Instance.new("UICorner", OpenButton).CornerRadius = UDim.new(0, 8)
local openStroke = Instance.new("UIStroke", OpenButton)
openStroke.Color = Color3.fromRGB(60, 60, 60)
openStroke.Thickness = 1

OpenButton.MouseEnter:Connect(function()
    TweenService:Create(OpenButton, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(25, 25, 25)}):Play()
end)
OpenButton.MouseLeave:Connect(function()
    TweenService:Create(OpenButton, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(15, 15, 15)}):Play()
end)

local function updateOpenButtonVisibility()
    OpenButton.Visible = not Main.Visible
end

OpenButton.MouseButton1Click:Connect(function()
    Main.Visible = true
    OpenButton.Visible = false
end)

local openDragging, openDragStart, openStartPos
OpenButton.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        openDragging = true
        openDragStart = i.Position
        openStartPos = OpenButton.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if openDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - openDragStart
        if delta.Magnitude > 5 then
            OpenButton.Position = UDim2.new(openStartPos.X.Scale, openStartPos.X.Offset + delta.X, openStartPos.Y.Scale, openStartPos.Y.Offset + delta.Y)
        end
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        openDragging = false
    end
end)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -70, 0, 36)
Title.Position = UDim2.new(0, 14, 0, 4)
Title.BackgroundTransparency = 1
Title.Text = "Auto Grab"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size               = UDim2.new(0, 26, 0, 26)
CloseBtn.Position           = UDim2.new(1, -32, 0, 6)
CloseBtn.BackgroundColor3   = Color3.fromRGB(20, 20, 20)
CloseBtn.BorderSizePixel    = 0
CloseBtn.Text               = "X"
CloseBtn.TextColor3         = Color3.fromRGB(220, 220, 220)
CloseBtn.Font               = Enum.Font.GothamBold
CloseBtn.TextSize           = 16
CloseBtn.AutoButtonColor    = false
CloseBtn.Parent             = Main
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(60,30,30), TextColor3=Color3.fromRGB(255,120,120)}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(20,20,20), TextColor3=Color3.fromRGB(220,220,220)}):Play()
end)
CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    updateOpenButtonVisibility()
end)

local Count = Instance.new("TextLabel")
Count.Size = UDim2.new(0, 40, 0, 36)
Count.Position = UDim2.new(1, -72, 0, 4)
Count.BackgroundTransparency = 1
Count.Text = "0"
Count.TextColor3 = Color3.fromRGB(100, 200, 100)
Count.Font = Enum.Font.GothamBold
Count.TextSize = 14
Count.TextXAlignment = Enum.TextXAlignment.Right
Count.Parent = Main

local Div = Instance.new("Frame")
Div.Size = UDim2.new(0.9, 0, 0, 1)
Div.Position = UDim2.new(0.05, 0, 0, 40)
Div.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
Div.BorderSizePixel = 0
Div.Parent = Main

local function MakeBtn(name, y)
    local h = Instance.new("Frame")
    h.Size = UDim2.new(0.9, 0, 0, 36)
    h.Position = UDim2.new(0.05, 0, 0, y)
    h.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    h.BorderSizePixel = 0
    h.Parent = Main
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 8)

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.65, 0, 1, 0)
    l.Position = UDim2.new(0, 12, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = name
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(200, 200, 210)
    l.Parent = h

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 40, 0, 20)
    bg.Position = UDim2.new(1, -52, 0.5, -10)
    bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bg.BorderSizePixel = 0
    bg.Parent = h
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

    local c = Instance.new("Frame")
    c.Size = UDim2.new(0, 16, 0, 16)
    c.Position = UDim2.new(0, 2, 0.5, -8)
    c.BackgroundColor3 = Color3.fromRGB(120, 120, 130)
    c.BorderSizePixel = 0
    c.Parent = bg
    Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)

    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundTransparency = 1
    b.Text = ""
    b.Parent = h

    local function upd(on)
        local pos = on and UDim2.new(0, 22, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        local col = on and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(120, 120, 130)
        local bgc = on and Color3.fromRGB(70, 160, 90) or Color3.fromRGB(30, 30, 30)
        local tc = on and Color3.fromRGB(230, 230, 235) or Color3.fromRGB(200, 200, 210)
        TweenService:Create(c, TweenInfo.new(0.15), {Position = pos, BackgroundColor3 = col}):Play()
        TweenService:Create(bg, TweenInfo.new(0.15), {BackgroundColor3 = bgc}):Play()
        TweenService:Create(l, TweenInfo.new(0.15), {TextColor3 = tc}):Play()
    end

    return b, upd
end

local hBtn, hUpd = MakeBtn("Steal Highest", 50)
local pBtn, pUpd = MakeBtn("Steal Priority", 94)
local nBtn, nUpd = MakeBtn("Steal Nearest", 138)

local function updAll()
    hUpd(AG.Active and AG.Mode == "Highest")
    pUpd(AG.Active and AG.Mode == "Priority")
    nUpd(AG.Active and AG.Mode == "Nearest")
end

hBtn.MouseButton1Click:Connect(function()
    if AG.Mode == "Highest" then
        AG.Active = not AG.Active
    else
        AG.Mode = "Highest"
        AG.Active = true
    end
    updAll()
    SaveSettings()
end)

pBtn.MouseButton1Click:Connect(function()
    if AG.Mode == "Priority" then
        AG.Active = not AG.Active
    else
        AG.Mode = "Priority"
        AG.Active = true
    end
    updAll()
    SaveSettings()
end)

nBtn.MouseButton1Click:Connect(function()
    if AG.Mode == "Nearest" then
        AG.Active = not AG.Active
    else
        AG.Mode = "Nearest"
        AG.Active = true
    end
    updAll()
    SaveSettings()
end)

updAll()

local Bar = Instance.new("Frame")
Bar.Size = UDim2.new(0.9, 0, 0, 28)
Bar.Position = UDim2.new(0.05, 0, 0, 182)
Bar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
Bar.BorderSizePixel = 0
Bar.Parent = Main
Instance.new("UICorner", Bar).CornerRadius = UDim.new(0, 6)

local Fill = Instance.new("Frame")
Fill.Size = UDim2.new(0, 0, 1, 0)
Fill.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
Fill.BorderSizePixel = 0
Fill.Parent = Bar
Instance.new("UICorner", Fill).CornerRadius = UDim.new(0, 6)

local Dot = Instance.new("Frame")
Dot.Size = UDim2.new(0, 6, 0, 6)
Dot.Position = UDim2.new(0, 8, 0.5, -3)
Dot.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
Dot.BorderSizePixel = 0
Dot.Parent = Bar
Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(0, 120, 1, 0)
Status.Position = UDim2.new(0, 18, 0, 0)
Status.BackgroundTransparency = 1
Status.Text = "Idle"
Status.TextColor3 = Color3.fromRGB(100, 100, 110)
Status.Font = Enum.Font.Gotham
Status.TextSize = 10
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Bar

local PetName = Instance.new("TextLabel")
PetName.Size = UDim2.new(0, 90, 1, 0)
PetName.Position = UDim2.new(0, 115, 0, 0)
PetName.BackgroundTransparency = 1
PetName.Text = ""
PetName.TextColor3 = Color3.fromRGB(160, 160, 170)
PetName.Font = Enum.Font.GothamBold
PetName.TextSize = 9
PetName.TextXAlignment = Enum.TextXAlignment.Left
PetName.TextTruncate = Enum.TextTruncate.AtEnd
PetName.Parent = Bar

local Pct = Instance.new("TextLabel")
Pct.Size = UDim2.new(0, 40, 1, 0)
Pct.Position = UDim2.new(1, -40, 0, 0)
Pct.BackgroundTransparency = 1
Pct.Text = ""
Pct.TextColor3 = Color3.fromRGB(160, 160, 170)
Pct.Font = Enum.Font.GothamBold
Pct.TextSize = 10
Pct.TextXAlignment = Enum.TextXAlignment.Right
Pct.Parent = Bar

local SettingsDivider = Instance.new("Frame", Main)
SettingsDivider.Size             = UDim2.new(0.9, 0, 0, 1)
SettingsDivider.Position         = UDim2.new(0.05, 0, 0, 218)
SettingsDivider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
SettingsDivider.BorderSizePixel  = 0

local SettingsLabel = Instance.new("TextLabel")
SettingsLabel.Size               = UDim2.new(0.9, 0, 0, 20)
SettingsLabel.Position           = UDim2.new(0.05, 0, 0, 226)
SettingsLabel.BackgroundTransparency = 1
SettingsLabel.Text               = "Settings"
SettingsLabel.TextColor3         = Color3.fromRGB(160, 160, 170)
SettingsLabel.Font               = Enum.Font.GothamBold
SettingsLabel.TextSize           = 11
SettingsLabel.TextXAlignment     = Enum.TextXAlignment.Left
SettingsLabel.Parent             = Main

local GuiScaleFrame = Instance.new("Frame")
GuiScaleFrame.Size             = UDim2.new(0.9, 0, 0, 36)
GuiScaleFrame.Position         = UDim2.new(0.05, 0, 0, 249)
GuiScaleFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
GuiScaleFrame.BorderSizePixel  = 0
GuiScaleFrame.Parent           = Main
Instance.new("UICorner", GuiScaleFrame).CornerRadius = UDim.new(0, 6)

local GuiScaleLabel = Instance.new("TextLabel")
GuiScaleLabel.Size               = UDim2.new(0, 65, 1, 0)
GuiScaleLabel.Position           = UDim2.new(0, 10, 0, 0)
GuiScaleLabel.BackgroundTransparency = 1
GuiScaleLabel.Text               = "GUI Scale"
GuiScaleLabel.Font               = Enum.Font.Gotham
GuiScaleLabel.TextSize           = 11
GuiScaleLabel.TextXAlignment     = Enum.TextXAlignment.Left
GuiScaleLabel.TextColor3         = Color3.fromRGB(180, 180, 190)
GuiScaleLabel.Parent             = GuiScaleFrame

local GuiScaleBar = Instance.new("Frame")
GuiScaleBar.Size             = UDim2.new(0, 100, 0, 5)
GuiScaleBar.Position         = UDim2.new(0, 80, 0.5, -2)
GuiScaleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
GuiScaleBar.BorderSizePixel  = 0
GuiScaleBar.Parent           = GuiScaleFrame
Instance.new("UICorner", GuiScaleBar).CornerRadius = UDim.new(1, 0)

local GuiScaleFill = Instance.new("Frame")
GuiScaleFill.Size             = UDim2.new(0, 0, 1, 0)
GuiScaleFill.BackgroundColor3 = Color3.fromRGB(215, 215, 225)
GuiScaleFill.BorderSizePixel  = 0
GuiScaleFill.Parent           = GuiScaleBar
Instance.new("UICorner", GuiScaleFill).CornerRadius = UDim.new(1, 0)

local GuiScaleKnob = Instance.new("Frame")
GuiScaleKnob.Size             = UDim2.new(0, 10, 0, 10)
GuiScaleKnob.Position         = UDim2.new(0, -5, 0.5, -5)
GuiScaleKnob.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
GuiScaleKnob.BorderSizePixel  = 0
GuiScaleKnob.Parent           = GuiScaleBar
Instance.new("UICorner", GuiScaleKnob).CornerRadius = UDim.new(1, 0)

local GuiScaleValueBG = Instance.new("Frame")
GuiScaleValueBG.Size             = UDim2.new(0, 45, 0, 18)
GuiScaleValueBG.Position         = UDim2.new(1, -52, 0.5, -9)
GuiScaleValueBG.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
GuiScaleValueBG.BorderSizePixel  = 0
GuiScaleValueBG.Parent           = GuiScaleFrame
Instance.new("UICorner", GuiScaleValueBG).CornerRadius = UDim.new(0, 4)

local GuiScaleInput = Instance.new("TextBox")
GuiScaleInput.Size               = UDim2.new(1, 0, 1, 0)
GuiScaleInput.BackgroundTransparency = 1
GuiScaleInput.Text               = tostring(AG.GuiScale) .. "%"
GuiScaleInput.Font               = Enum.Font.GothamBold
GuiScaleInput.TextSize           = 10
GuiScaleInput.TextColor3         = Color3.fromRGB(220, 220, 230)
GuiScaleInput.TextXAlignment     = Enum.TextXAlignment.Center
GuiScaleInput.ClearTextOnFocus   = false
GuiScaleInput.PlaceholderColor3  = Color3.fromRGB(120, 120, 130)
GuiScaleInput.Parent             = GuiScaleValueBG

local guiScaleDragging = false

local function setGuiScaleFromAlpha(a, instant)
    a = math.clamp(a, 0, 1)
    local value = math.floor(20 + (100 - 20) * a + 0.5)
    AG.GuiScale = value
    if not GuiScaleInput:IsFocused() then
        GuiScaleInput.Text = tostring(value) .. "%"
    end
    local sizeX = GuiScaleBar.AbsoluteSize.X
    if sizeX <= 0 then return end
    local x = a * sizeX
    if instant then
        GuiScaleFill.Size = UDim2.new(0, x, 1, 0)
        GuiScaleKnob.Position = UDim2.new(0, x - 5, 0.5, -5)
    else
        TweenService:Create(GuiScaleFill, TweenInfo.new(0.1), {Size = UDim2.new(0, x, 1, 0)}):Play()
        TweenService:Create(GuiScaleKnob, TweenInfo.new(0.1), {Position = UDim2.new(0, x - 5, 0.5, -5)}):Play()
    end
    local scale = 0.3 + (1.0 - 0.3) * ((value - 20) / (100 - 20))
    if instant then
        GlobalUIScale.Scale = scale
    else
        TweenService:Create(GlobalUIScale, TweenInfo.new(0.15), {Scale = scale}):Play()
    end
    SaveSettings()
end

local function updateGuiScaleFromX(px)
    local absPos = GuiScaleBar.AbsolutePosition.X
    local sizeX = GuiScaleBar.AbsoluteSize.X
    if sizeX <= 0 then return end
    local alpha = (px - absPos) / sizeX
    setGuiScaleFromAlpha(alpha, false)
end

GuiScaleInput.FocusLost:Connect(function()
    local txt = GuiScaleInput.Text:gsub("%%", "")
    local num = tonumber(txt)
    if num then
        num = math.clamp(math.floor(num + 0.5), 20, 100)
        AG.GuiScale = num
        local alpha = (num - 20) / (100 - 20)
        setGuiScaleFromAlpha(alpha, false)
    else
        GuiScaleInput.Text = tostring(AG.GuiScale) .. "%"
    end
end)

GuiScaleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        guiScaleDragging = true
        isInteractingWithSlider = true
        updateGuiScaleFromX(input.Position.X)
    end
end)

GuiScaleKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        guiScaleDragging = true
        isInteractingWithSlider = true
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if guiScaleDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        updateGuiScaleFromX(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if guiScaleDragging then
            guiScaleDragging = false
            isInteractingWithSlider = false
        end
    end
end)

task.defer(function()
    local alpha = (AG.GuiScale - 20) / (100 - 20)
    setGuiScaleFromAlpha(alpha, true)
end)

task.defer(function()
    Main.Visible = true
    OpenButton.Visible = false
end)

task.spawn(function()
    while AG.Running and Screen and Screen.Parent do
        Count.Text = tostring(AG.StealCount)
        if inRagdollCooldown() then
            local remaining = math.max(0, ragdollEndTime - tick())
            Fill.Size = UDim2.new(0, 0, 1, 0)
            Fill.BackgroundColor3 = Color3.fromRGB(220, 200, 60)
            Pct.Text = ""
            Status.Text = string.format("Ragdolled Wait %.1fs", remaining)
            Status.TextColor3 = Color3.fromRGB(255, 225, 80)
            Dot.BackgroundColor3 = Color3.fromRGB(255, 225, 80)
            PetName.Text = ""
        elseif AG.IsStealing then
            local p = AG.StealProgress
            Fill.Size = UDim2.new(math.clamp(p, 0, 1), 0, 1, 0)
            Fill.BackgroundColor3 = p >= 0.99 and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(180, 180, 190)
            Pct.Text = math.floor(p * 100) .. "%"
            Status.Text = p >= 0.99 and "Got!" or "Grab"
            Status.TextColor3 = p >= 0.99 and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(180, 180, 190)
            Dot.BackgroundColor3 = Status.TextColor3
            PetName.Text = AG.CurrentPetName
        else
            local currentSize = Fill.Size.X.Scale
            if currentSize > 0.01 then
                Fill.Size = UDim2.new(math.max(0, currentSize - 0.05), 0, 1, 0)
            else
                Fill.Size = UDim2.new(0, 0, 1, 0)
            end
            Fill.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
            Pct.Text = ""
            if AG.Active then
                Status.Text = "Scan"
                Status.TextColor3 = Color3.fromRGB(120, 200, 120)
                Dot.BackgroundColor3 = Color3.fromRGB(120, 200, 120)
                PetName.Text = ""
            else
                Status.Text = "Idle"
                Status.TextColor3 = Color3.fromRGB(100, 100, 110)
                Dot.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
                PetName.Text = ""
            end
        end
        task.wait(1/60)
    end
end)

local drag, ds, sp
Main.InputBegan:Connect(function(i)
    if isInteractingWithSlider then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        drag = true
        ds = i.Position
        sp = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if drag and not isInteractingWithSlider and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - ds
        Main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        AG.MainPos = {ScaleX = Main.Position.X.Scale, ScaleY = Main.Position.Y.Scale, OffsetX = Main.Position.X.Offset, OffsetY = Main.Position.Y.Offset}
        SaveSettings()
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.RightControl then
            Main.Visible = not Main.Visible
            updateOpenButtonVisibility()
        end
    end
end)

function AG.Disable()
    AG.Active = false
    AG.Running = false
    SaveSettings()
    local LAS = getgenv().LuminaAutoSteal
    if LAS then LAS.Stop() end
    if AG.ScreenGui then AG.ScreenGui:Destroy() end
end
