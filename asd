if not game:IsLoaded() then game.Loaded:Wait() end

local MIN_GEN_VALUE = 1

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local SAVE_KEY_PRIO = "PriorityPanel_Settings_" .. LocalPlayer.UserId

pcall(function()
    if LocalPlayer.PlayerGui:FindFirstChild("PriorityPanel") then
        LocalPlayer.PlayerGui.PriorityPanel:Destroy()
    end
end)

if getgenv().PrioritySystem then
    pcall(function() getgenv().PrioritySystem.Disable() end)
end

getgenv().PrioritySystem = {
    Selected = nil,
    SelectedModel = nil,
    SelectedUID = nil,
    SelectedData = nil,
    ESPHighlight = nil,
    ESPBillboard = nil,
    ESPLinePart = nil,
    AutoSelect = true,
    Active = true,
    AutoOpenOnLoad = true,
    GuiScale = 50,
    MainPos = nil,
    OpenPos = nil,
}
local PS = getgenv().PrioritySystem

local isInteractingWithSlider = false

local DEFAULT_PRIORITY_ORDER = {
    "Headless Horseman",
    "Strawberry Elephant",
    "Meowl",
    "Skibidi Toilet",
    "Elefanto Frigo",
    "Signore Carapace",
    "Arcadragon",
    "La Supreme Combinasion",
    "Dragon Gingerini",
    "Dragon Cannelloni",
    "Foxini Laternini",
    "La Casa Boo",
    "Reinito Sleighito",
    "Griffin",
    "Bunny and Eggy",
    "Fragrama and Chocrama",
    "Digi Narwhal",
    "Fishino Clownino",
    "Rosey and Teddy",
    "Love Love Bear",
    "Ketupat Bros",
    "Cooki and Milki",
    "Gingerat Gerat",
    "Spooky and Pumpky",
    "Cerberus",
    "Festive 67",
    "Los Hotspotsitos",
    "La Food Combinasion",
    "Cash or Card",
    "Popcuru and Fizzuru",
    "Tirilikalika Tirilikalako",
    "Celestial Pegasus",
    "Fortunu and Cashuru",
    "Capitano Moby",
    "Popuru and Fizzuru",
    "Burguro And Fryuro",
    "La Secret Combinasion",
    "Garama and Madundung",
    "Cloverat Clapat",
    "Lavadorito Spinito",
    "Ketchuru and Musturu",
    "Tictac Sahur",
    "Ketupat Kepat",
    "Tang Tang Keletang"
}

local PRIORITY_ORDER = {}
local PRIORITY_RANK = {}

local function SetPriorityOrder(list)
    PRIORITY_ORDER = {}
    for i, v in ipairs(list) do
        PRIORITY_ORDER[i] = v
    end
    PRIORITY_RANK = {}
    for i, name in ipairs(PRIORITY_ORDER) do
        PRIORITY_RANK[name] = i
    end
end

SetPriorityOrder(DEFAULT_PRIORITY_ORDER)

local function SavePanelSettings()
    pcall(function()
        if writefile then
            writefile(SAVE_KEY_PRIO .. ".json", HttpService:JSONEncode({
                AutoOpenOnLoad = PS.AutoOpenOnLoad,
                GuiScale = PS.GuiScale,
                PriorityOrder = PRIORITY_ORDER,
                MainPos = PS.MainPos and {ScaleX = PS.MainPos.X.Scale, OffsetX = PS.MainPos.X.Offset, ScaleY = PS.MainPos.Y.Scale, OffsetY = PS.MainPos.Y.Offset} or nil,
                OpenPos = PS.OpenPos and {ScaleX = PS.OpenPos.X.Scale, OffsetX = PS.OpenPos.X.Offset, ScaleY = PS.OpenPos.Y.Scale, OffsetY = PS.OpenPos.Y.Offset} or nil,
            }))
        end
    end)
end

local function LoadPanelSettings()
    pcall(function()
        if readfile and isfile and isfile(SAVE_KEY_PRIO .. ".json") then
            local d = HttpService:JSONDecode(readfile(SAVE_KEY_PRIO .. ".json"))
            if d.AutoOpenOnLoad ~= nil then PS.AutoOpenOnLoad = d.AutoOpenOnLoad end
            if d.GuiScale ~= nil then PS.GuiScale = d.GuiScale end
            if type(d.PriorityOrder) == "table" and #d.PriorityOrder > 0 then
                SetPriorityOrder(d.PriorityOrder)
            end
            if d.MainPos and d.MainPos.ScaleX and d.MainPos.OffsetX and d.MainPos.ScaleY and d.MainPos.OffsetY then
                PS.MainPos = UDim2.new(d.MainPos.ScaleX, d.MainPos.OffsetX, d.MainPos.ScaleY, d.MainPos.OffsetY)
            end
            if d.OpenPos and d.OpenPos.ScaleX and d.OpenPos.OffsetX and d.OpenPos.ScaleY and d.OpenPos.OffsetY then
                PS.OpenPos = UDim2.new(d.OpenPos.ScaleX, d.OpenPos.OffsetX, d.OpenPos.ScaleY, d.OpenPos.OffsetY)
            end
        end
    end)
end

LoadPanelSettings()
if #PRIORITY_ORDER == 0 then SetPriorityOrder(DEFAULT_PRIORITY_ORDER) end

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Datas = ReplicatedStorage:WaitForChild("Datas")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Synchronizer = require(Packages:WaitForChild("Synchronizer"))
local AnimalsData = require(Datas:WaitForChild("Animals"))
local AnimalsShared = require(Shared:WaitForChild("Animals"))

local allAnimalsCache = {}
local lastAnimalHash = {}
local ScreenGui, Main, ScrollFrame, SelectedLabel, EntryButtons, ConfigWindow, PriorityScroll = nil, nil, nil, nil, nil, nil, nil
local OpenButton

local function Format(n)
    if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
    if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

local function isMyBase(plotName)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end
    local channel = Synchronizer:Get(plot.Name)
    if channel then
        local owner = channel:Get("Owner")
        if owner then
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "table" and owner.UserId then
                return owner.UserId == LocalPlayer.UserId
            end
        end
    end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") then
            return yourBase.Enabled == true
        end
    end
    return false
end

local function isInFusingMachine(plot, slot)
    local slotNum = tonumber(slot)
    if not slotNum then return false end
    local channel = Synchronizer:Get(plot.Name)
    if not channel then return false end
    local fusingData = channel:Get("FusingMachine")
    if fusingData then
        if fusingData.Input1 == slotNum then return true end
        if fusingData.Input2 == slotNum then return true end
        if fusingData.Output == slotNum then return true end
        if type(fusingData.Inputs) == "table" then
            for _, inputSlot in pairs(fusingData.Inputs) do
                if inputSlot == slotNum then return true end
            end
        end
    end
    return false
end

local function getAnimalModel(plotName, slot)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if podiums then
        local podium = podiums:FindFirstChild(tostring(slot))
        if podium then
            for _, child in pairs(podium:GetChildren()) do
                if child:IsA("Model") then
                    local root = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
                    if root then return child, root.Position end
                end
            end
            for _, child in pairs(podium:GetDescendants()) do
                if child:IsA("Model") then
                    local root = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
                    if root then return child, root.Position end
                end
            end
            local podiumPos = podium:GetPivot().Position
            return nil, podiumPos
        end
    end
    return nil, nil
end

local function getWorldPosition(plotName, slot)
    local _, pos = getAnimalModel(plotName, slot)
    if pos then return pos end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(tostring(slot))
    if podium then return podium:GetPivot().Position end
    return nil
end

local function RemoveESP()
    if PS.ESPHighlight then pcall(function() PS.ESPHighlight:Destroy() end) PS.ESPHighlight = nil end
    if PS.ESPBillboard then pcall(function() PS.ESPBillboard:Destroy() end) PS.ESPBillboard = nil end
    if PS.ESPLinePart then pcall(function() PS.ESPLinePart:Destroy() end) PS.ESPLinePart = nil end
end

local function CreateESP(model, data)
    RemoveESP()
    if not model then return end
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "PriorityHighlight"
    highlight.Adornee = model
    highlight.FillTransparency = 0.8
    highlight.OutlineTransparency = 0
    if data.priorityRank ~= math.huge then
        highlight.FillColor = Color3.fromRGB(255, 100, 255)
        highlight.OutlineColor = Color3.fromRGB(255, 150, 255)
    else
        highlight.FillColor = Color3.fromRGB(255, 200, 50)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 100)
    end
    highlight.Parent = CoreGui
    PS.ESPHighlight = highlight

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PriorityESP"
    billboard.Adornee = root
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = CoreGui
    PS.ESPBillboard = billboard

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = data.name
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextColor3 = data.priorityRank ~= math.huge and Color3.fromRGB(255, 150, 255) or Color3.fromRGB(255, 220, 100)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextScaled = true
    nameLabel.Parent = billboard

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(1, 0, 0.5, 0)
    valueLabel.Position = UDim2.new(0, 0, 0.5, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = "$" .. Format(data.genValue) .. "/s"
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    valueLabel.TextStrokeTransparency = 0
    valueLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    valueLabel.TextScaled = true
    valueLabel.Parent = billboard

    local char = LocalPlayer.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if not hrp then return end

    local line = Instance.new("Part")
    line.Name = "PriorityLine"
    line.Anchored = true
    line.CanCollide = false
    line.CanQuery = false
    line.CanTouch = false
    line.Material = Enum.Material.Neon
    line.Color = Color3.fromRGB(0, 0, 0)
    line.Transparency = 0.15
    line.Size = Vector3.new(0.25, 0.25, 1)
    line.Parent = Workspace
    PS.ESPLinePart = line

    local thisData = data
    task.spawn(function()
        while PS.ESPLinePart == line and PS.SelectedData == thisData and line.Parent do
            local currentChar = LocalPlayer.Character
            local currentHRP = currentChar and (currentChar:FindFirstChild("HumanoidRootPart") or currentChar.PrimaryPart)
            if not currentHRP or not root or not root.Parent then
                line.Transparency = 1
            else
                local a = currentHRP.Position
                local b = root.Position
                local mid = (a + b) / 2
                local dist = (a - b).Magnitude
                line.Size = Vector3.new(0.25, 0.25, dist)
                line.CFrame = CFrame.lookAt(mid, b)
                line.Transparency = 0.15
            end
            task.wait(0.03)
        end
        if line and line.Parent then pcall(function() line:Destroy() end) end
        if PS.ESPLinePart == line then PS.ESPLinePart = nil end
    end)
end

local function getAnimalHash(animalList)
    if not animalList then return "" end
    local hash = ""
    for slot, data in pairs(animalList) do
        if type(data) == "table" and data.Index then
            hash = hash .. tostring(slot) .. tostring(data.Index) .. tostring(data.Mutation or "")
        end
    end
    return hash
end

local function scanAllPlots()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    local newCache = {}
    for _, plot in ipairs(plots:GetChildren()) do
        pcall(function()
            local plotUID = plot.Name
            if isMyBase(plotUID) then return end
            local channel = Synchronizer:Get(plotUID)
            if not channel then return end
            local owner = channel:Get("Owner")
            if not owner then return end
            local ownerName
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                ownerName = owner.Name
                if not Players:FindFirstChild(ownerName) then return end
            elseif typeof(owner) == "table" then
                ownerName = owner.Name or "Unknown"
                if not Players:FindFirstChild(ownerName) then return end
            else return end
            local animalList = channel:Get("AnimalList")
            if not animalList then return end
            lastAnimalHash[plotUID] = getAnimalHash(animalList)
            for slot, animalData in pairs(animalList) do
                if type(animalData) == "table" then
                    if isInFusingMachine(plot, slot) then continue end
                    local animalName = animalData.Index
                    local animalInfo = AnimalsData[animalName]
                    if not animalInfo then continue end
                    local displayName = animalInfo.DisplayName or animalName
                    local mutation = animalData.Mutation or "None"
                    local genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
                    if genValue < MIN_GEN_VALUE then continue end
                    local model, worldPos = getAnimalModel(plot.Name, slot)
                    if not worldPos then worldPos = getWorldPosition(plot.Name, slot) end
                    local rank = PRIORITY_RANK[displayName] or PRIORITY_RANK[animalName]
                    local uid = plot.Name .. "_" .. tostring(slot)
                    table.insert(newCache, {
                        name = displayName, index = animalName, genValue = genValue,
                        mutation = mutation, owner = ownerName, plot = plot.Name,
                        slot = tostring(slot), uid = uid, worldPosition = worldPos,
                        priorityRank = rank or math.huge, model = model,
                    })
                end
            end
        end)
    end
    table.sort(newCache, function(a, b)
        if a.priorityRank ~= b.priorityRank then return a.priorityRank < b.priorityRank end
        return a.genValue > b.genValue
    end)
    allAnimalsCache = newCache
    if PS.SelectedUID then
        local found = false
        for _, data in ipairs(allAnimalsCache) do
            if data.uid == PS.SelectedUID then
                PS.SelectedData = data
                PS.SelectedModel = data.model
                found = true
                break
            end
        end
        if not found and not PS.AutoSelect then
            PS.AutoSelect = true
            PS.SelectedUID = nil
            PS.SelectedData = nil
            PS.SelectedModel = nil
            RemoveESP()
        end
    end
end

EntryButtons = {}

local function UpdateEntryVisual(entry, isSelected)
    if isSelected then
        entry.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        local dot = entry:FindFirstChild("SelectDot")
        if dot then dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255) end
    else
        entry.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
        local dot = entry:FindFirstChild("SelectDot")
        if dot then dot.BackgroundColor3 = Color3.fromRGB(50, 50, 55) end
    end
end

local function UpdateSelection(data)
    PS.Selected = true
    PS.SelectedModel = data.model
    PS.SelectedUID = data.uid
    PS.SelectedData = data
end

local function ClearSelection()
    PS.Selected = nil
    PS.SelectedModel = nil
    PS.SelectedUID = nil
    PS.SelectedData = nil
    RemoveESP()
end

local function SelectTarget(data, manual)
    if manual and PS.SelectedUID == data.uid then
        ClearSelection()
        PS.AutoSelect = true
        if SelectedLabel then
            SelectedLabel.Text = "Auto-selecting best..."
            SelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
        end
        for _, entry in pairs(EntryButtons) do UpdateEntryVisual(entry, false) end
        return
    end
    if manual then PS.AutoSelect = false end
    local model, pos = getAnimalModel(data.plot, data.slot)
    data.model = model
    if pos then data.worldPosition = pos end
    UpdateSelection(data)
    local autoText = PS.AutoSelect and "[AUTO] " or ""
    if SelectedLabel then
        local rankText = data.priorityRank ~= math.huge and ("#" .. tostring(data.priorityRank) .. " ") or ""
        SelectedLabel.Text = autoText .. rankText .. data.name .. " ($" .. Format(data.genValue) .. "/s)"
        SelectedLabel.TextColor3 = data.priorityRank ~= math.huge and Color3.fromRGB(255, 150, 255) or Color3.fromRGB(255, 220, 100)
    end
    for _, entry in pairs(EntryButtons) do
        UpdateEntryVisual(entry, entry:GetAttribute("UID") == data.uid)
    end
    if model and model.Parent then CreateESP(model, data) else RemoveESP() end
end

local function AutoSelectBest()
    if not PS.AutoSelect then return end
    if #allAnimalsCache == 0 then
        ClearSelection()
        if SelectedLabel then
            SelectedLabel.Text = "No brainrots found"
            SelectedLabel.TextColor3 = Color3.fromRGB(100, 100, 110)
        end
        return
    end
    local best = allAnimalsCache[1]
    if PS.SelectedUID ~= best.uid then
        SelectTarget(best, false)
    else
        local model, pos = getAnimalModel(best.plot, best.slot)
        best.model = model
        if pos then best.worldPosition = pos end
        PS.SelectedModel = model
        PS.SelectedData = best
        if model and model.Parent then
            if PS.ESPHighlight then
                PS.ESPHighlight.Adornee = model
            else
                CreateESP(model, best)
            end
            local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if root and PS.ESPBillboard then
                PS.ESPBillboard.Adornee = root
            end
        end
    end
end

local function RefreshList()
    scanAllPlots()
    if PS.AutoSelect then
        AutoSelectBest()
    elseif PS.SelectedUID then
        local found = false
        for _, data in ipairs(allAnimalsCache) do
            if data.uid == PS.SelectedUID then
                found = true
                local model, pos = getAnimalModel(data.plot, data.slot)
                data.model = model
                if pos then data.worldPosition = pos end
                PS.SelectedModel = model
                PS.SelectedData = data
                if model and model.Parent then
                    if PS.ESPHighlight then
                        PS.ESPHighlight.Adornee = model
                    else
                        CreateESP(model, data)
                    end
                    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                    if root and PS.ESPBillboard then
                        PS.ESPBillboard.Adornee = root
                    end
                end
                break
            end
        end
        if not found then
            PS.AutoSelect = true
            ClearSelection()
            AutoSelectBest()
        end
    end

    local existingUIDs = {}
    for _, data in ipairs(allAnimalsCache) do existingUIDs[data.uid] = true end
    for i = #EntryButtons, 1, -1 do
        local entry = EntryButtons[i]
        if not entry.Parent then
            table.remove(EntryButtons, i)
        else
            local uid = entry:GetAttribute("UID")
            if not existingUIDs[uid] then
                entry:Destroy()
                table.remove(EntryButtons, i)
            end
        end
    end

    local existingEntries = {}
    for _, entry in pairs(EntryButtons) do
        existingEntries[entry:GetAttribute("UID")] = entry
    end

    local count = math.min(#allAnimalsCache, 20)
    for i = 1, count do
        local data = allAnimalsCache[i]
        local existingEntry = existingEntries[data.uid]
        if existingEntry then
            existingEntry.LayoutOrder = i
            local rank = existingEntry:FindFirstChild("RankLabel")
            if rank then
                if data.priorityRank ~= math.huge then
                    rank.Text = "#" .. tostring(data.priorityRank)
                    rank.TextColor3 = Color3.fromRGB(255, 150, 255)
                else
                    rank.Text = "#" .. i
                    rank.TextColor3 = Color3.fromRGB(80, 80, 90)
                end
            end
            local nameLabel = existingEntry:FindFirstChild("NameLabel")
            if nameLabel then
                nameLabel.Text = data.name
                nameLabel.TextColor3 = data.priorityRank ~= math.huge and Color3.fromRGB(255, 150, 255) or Color3.fromRGB(210, 210, 215)
            end
            local valueLabel = existingEntry:FindFirstChild("ValueLabel")
            if valueLabel then
                valueLabel.Text = "$" .. Format(data.genValue) .. "/s"
            end
            UpdateEntryVisual(existingEntry, PS.SelectedUID == data.uid)
        else
            local entry = Instance.new("Frame")
            entry.Size = UDim2.new(1, 0, 0, 44)
            entry.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
            entry.BorderSizePixel = 0
            entry.LayoutOrder = i
            entry.Parent = ScrollFrame
            entry:SetAttribute("UID", data.uid)
            Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 6)

            local rank = Instance.new("TextLabel")
            rank.Name = "RankLabel"
            rank.Size = UDim2.new(0, 40, 1, 0)
            rank.Position = UDim2.new(0, 6, 0, 0)
            rank.BackgroundTransparency = 1
            rank.Font = Enum.Font.GothamBold
            rank.TextSize = 11
            if data.priorityRank ~= math.huge then
                rank.Text = "#" .. tostring(data.priorityRank)
                rank.TextColor3 = Color3.fromRGB(255, 150, 255)
            else
                rank.Text = "#" .. i
                rank.TextColor3 = Color3.fromRGB(80, 80, 90)
            end
            rank.Parent = entry

            local petName = Instance.new("TextLabel")
            petName.Name = "NameLabel"
            petName.Size = UDim2.new(0, 120, 0, 20)
            petName.Position = UDim2.new(0, 48, 0, 4)
            petName.BackgroundTransparency = 1
            petName.Text = data.name
            petName.TextColor3 = data.priorityRank ~= math.huge and Color3.fromRGB(255, 150, 255) or Color3.fromRGB(210, 210, 215)
            petName.Font = Enum.Font.GothamBold
            petName.TextSize = 11
            petName.TextXAlignment = Enum.TextXAlignment.Left
            petName.TextTruncate = Enum.TextTruncate.AtEnd
            petName.Parent = entry

            local vLabel = Instance.new("TextLabel")
            vLabel.Name = "ValueLabel"
            vLabel.Size = UDim2.new(0, 90, 0, 16)
            vLabel.Position = UDim2.new(0, 48, 0, 24)
            vLabel.BackgroundTransparency = 1
            vLabel.Text = "$" .. Format(data.genValue) .. "/s"
            vLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
            vLabel.Font = Enum.Font.Gotham
            vLabel.TextSize = 10
            vLabel.TextXAlignment = Enum.TextXAlignment.Left
            vLabel.Parent = entry

            local ownerLabel = Instance.new("TextLabel")
            ownerLabel.Size = UDim2.new(0, 80, 0, 16)
            ownerLabel.Position = UDim2.new(0, 138, 0, 24)
            ownerLabel.BackgroundTransparency = 1
            ownerLabel.Text = "by " .. data.owner
            ownerLabel.TextColor3 = Color3.fromRGB(80, 80, 90)
            ownerLabel.Font = Enum.Font.Gotham
            ownerLabel.TextSize = 9
            ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
            ownerLabel.TextTruncate = Enum.TextTruncate.AtEnd
            ownerLabel.Parent = entry

            local selectDot = Instance.new("Frame")
            selectDot.Name = "SelectDot"
            selectDot.Size = UDim2.new(0, 12, 0, 12)
            selectDot.Position = UDim2.new(1, -22, 0.5, -6)
            selectDot.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
            selectDot.BorderSizePixel = 0
            selectDot.Parent = entry
            Instance.new("UICorner", selectDot).CornerRadius = UDim.new(1, 0)

            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.Parent = entry

            local capturedUID = data.uid
            btn.MouseButton1Click:Connect(function()
                for _, d in ipairs(allAnimalsCache) do
                    if d.uid == capturedUID then
                        SelectTarget(d, true)
                        break
                    end
                end
            end)

            btn.MouseEnter:Connect(function()
                if PS.SelectedUID ~= entry:GetAttribute("UID") then
                    TweenService:Create(entry, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(28, 28, 32)}):Play()
                end
            end)
            btn.MouseLeave:Connect(function()
                if PS.SelectedUID ~= entry:GetAttribute("UID") then
                    TweenService:Create(entry, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(20, 20, 24)}):Play()
                end
            end)

            table.insert(EntryButtons, entry)
            if PS.SelectedUID == data.uid then UpdateEntryVisual(entry, true) end
        end
    end
    if ScrollFrame then
        ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, count * 50)
    end
end

local parent = LocalPlayer:WaitForChild("PlayerGui")
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PriorityPanel"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = parent

local GlobalUIScale = Instance.new("UIScale")
GlobalUIScale.Name = "GlobalScale"
GlobalUIScale.Scale = 0.5 + (1.5 - 0.5) * ((PS.GuiScale - 20) / (100 - 20))
GlobalUIScale.Parent = ScreenGui

Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 280, 0, 440)
Main.Position = PS.MainPos or UDim2.new(1, -570, 0, 50)
Main.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)
local mainStroke = Instance.new("UIStroke", Main)
mainStroke.Color = Color3.fromRGB(60, 60, 60)
mainStroke.Thickness = 1

OpenButton = Instance.new("TextButton")
OpenButton.Name = "OpenButton"
OpenButton.Size = UDim2.new(0, 150, 0, 32)
OpenButton.Position = PS.OpenPos or UDim2.new(1, -570, 0, 50)
OpenButton.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
OpenButton.BorderSizePixel = 0
OpenButton.Text = "Open Priority List"
OpenButton.TextColor3 = Color3.fromRGB(200, 200, 200)
OpenButton.Font = Enum.Font.GothamBold
OpenButton.TextSize = 12
OpenButton.AutoButtonColor = false
OpenButton.Visible = false
OpenButton.Parent = ScreenGui
Instance.new("UICorner", OpenButton).CornerRadius = UDim.new(0, 8)
local openStroke2 = Instance.new("UIStroke", OpenButton)
openStroke2.Color = Color3.fromRGB(60, 60, 60)
openStroke2.Thickness = 1

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
            PS.OpenPos = OpenButton.Position
            SavePanelSettings()
        end
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        openDragging = false
    end
end)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 36)
Title.Position = UDim2.new(0, 14, 0, 4)
Title.BackgroundTransparency = 1
Title.Text = "Priority List"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local CloseBtn = Instance.new("TextButton", Main)
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -32, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.AutoButtonColor = false
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(60,30,30), TextColor3=Color3.fromRGB(255,120,120)}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(20,20,20), TextColor3=Color3.fromRGB(200,200,200)}):Play()
end)
CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    updateOpenButtonVisibility()
end)

local Divider = Instance.new("Frame")
Divider.Size = UDim2.new(0.9, 0, 0, 1)
Divider.Position = UDim2.new(0.05, 0, 0, 40)
Divider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
Divider.BorderSizePixel = 0
Divider.Parent = Main

ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(0.9, 0, 0, 230)
ScrollFrame.Position = UDim2.new(0.05, 0, 0, 50)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 4
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = Main

local ListLayout = Instance.new("UIListLayout")
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 6)
ListLayout.Parent = ScrollFrame

local SelectedInfo = Instance.new("Frame")
SelectedInfo.Size = UDim2.new(0.9, 0, 0, 32)
SelectedInfo.Position = UDim2.new(0.05, 0, 0, 288)
SelectedInfo.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
SelectedInfo.BorderSizePixel = 0
SelectedInfo.Parent = Main
Instance.new("UICorner", SelectedInfo).CornerRadius = UDim.new(0, 6)

SelectedLabel = Instance.new("TextLabel")
SelectedLabel.Size = UDim2.new(1, -10, 1, 0)
SelectedLabel.Position = UDim2.new(0, 10, 0, 0)
SelectedLabel.BackgroundTransparency = 1
SelectedLabel.Text = "Auto-selecting best..."
SelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
SelectedLabel.Font = Enum.Font.Gotham
SelectedLabel.TextSize = 11
SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
SelectedLabel.Parent = SelectedInfo

local SettingsDiv = Instance.new("Frame", Main)
SettingsDiv.Size = UDim2.new(0.9, 0, 0, 1)
SettingsDiv.Position = UDim2.new(0.05, 0, 0, 330)
SettingsDiv.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
SettingsDiv.BorderSizePixel = 0

local SettingsLabel = Instance.new("TextLabel", Main)
SettingsLabel.Size = UDim2.new(0.9, 0, 0, 20)
SettingsLabel.Position = UDim2.new(0.05, 0, 0, 337)
SettingsLabel.BackgroundTransparency = 1
SettingsLabel.Text = "Settings"
SettingsLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
SettingsLabel.Font = Enum.Font.GothamBold
SettingsLabel.TextSize = 11
SettingsLabel.TextXAlignment = Enum.TextXAlignment.Left

local ConfigFrame = Instance.new("Frame", Main)
ConfigFrame.Size = UDim2.new(0.9, 0, 0, 30)
ConfigFrame.Position = UDim2.new(0.05, 0, 0, 360)
ConfigFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
ConfigFrame.BorderSizePixel = 0
Instance.new("UICorner", ConfigFrame).CornerRadius = UDim.new(0, 6)

local ConfigLabel = Instance.new("TextLabel", ConfigFrame)
ConfigLabel.Size = UDim2.new(1, 0, 1, 0)
ConfigLabel.BackgroundTransparency = 1
ConfigLabel.Text = "Configure"
ConfigLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
ConfigLabel.Font = Enum.Font.GothamBold
ConfigLabel.TextSize = 12
ConfigLabel.TextXAlignment = Enum.TextXAlignment.Left
ConfigLabel.Position = UDim2.new(0, 12, 0, 0)

local ConfigButton = Instance.new("TextButton", ConfigFrame)
ConfigButton.Size = UDim2.new(1, 0, 1, 0)
ConfigButton.BackgroundTransparency = 1
ConfigButton.Text = ""

local GuiScaleFrame = Instance.new("Frame", Main)
GuiScaleFrame.Size = UDim2.new(0.9, 0, 0, 36)
GuiScaleFrame.Position = UDim2.new(0.05, 0, 0, 395)
GuiScaleFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
GuiScaleFrame.BorderSizePixel = 0
Instance.new("UICorner", GuiScaleFrame).CornerRadius = UDim.new(0, 6)

local GuiScaleLabel = Instance.new("TextLabel", GuiScaleFrame)
GuiScaleLabel.Size = UDim2.new(0, 65, 1, 0)
GuiScaleLabel.Position = UDim2.new(0, 10, 0, 0)
GuiScaleLabel.BackgroundTransparency = 1
GuiScaleLabel.Text = "GUI Scale"
GuiScaleLabel.Font = Enum.Font.Gotham
GuiScaleLabel.TextSize = 11
GuiScaleLabel.TextXAlignment = Enum.TextXAlignment.Left
GuiScaleLabel.TextColor3 = Color3.fromRGB(180, 180, 190)

local GuiScaleBar = Instance.new("Frame", GuiScaleFrame)
GuiScaleBar.Size = UDim2.new(0, 95, 0, 5)
GuiScaleBar.Position = UDim2.new(0, 80, 0.5, -2)
GuiScaleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
GuiScaleBar.BorderSizePixel = 0
Instance.new("UICorner", GuiScaleBar).CornerRadius = UDim.new(1, 0)

local GuiScaleFill = Instance.new("Frame", GuiScaleBar)
GuiScaleFill.Size = UDim2.new(0, 0, 1, 0)
GuiScaleFill.BackgroundColor3 = Color3.fromRGB(215, 215, 225)
GuiScaleFill.BorderSizePixel = 0
Instance.new("UICorner", GuiScaleFill).CornerRadius = UDim.new(1, 0)

local GuiScaleKnob = Instance.new("Frame", GuiScaleBar)
GuiScaleKnob.Size = UDim2.new(0, 10, 0, 10)
GuiScaleKnob.Position = UDim2.new(0, -5, 0.5, -5)
GuiScaleKnob.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
GuiScaleKnob.BorderSizePixel = 0
Instance.new("UICorner", GuiScaleKnob).CornerRadius = UDim.new(1, 0)

local GuiScaleValueBG = Instance.new("Frame", GuiScaleFrame)
GuiScaleValueBG.Size = UDim2.new(0, 45, 0, 18)
GuiScaleValueBG.Position = UDim2.new(1, -52, 0.5, -9)
GuiScaleValueBG.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
GuiScaleValueBG.BorderSizePixel = 0
Instance.new("UICorner", GuiScaleValueBG).CornerRadius = UDim.new(0, 4)

local GuiScaleInput = Instance.new("TextBox", GuiScaleValueBG)
GuiScaleInput.Size = UDim2.new(1, 0, 1, 0)
GuiScaleInput.BackgroundTransparency = 1
GuiScaleInput.Text = tostring(PS.GuiScale) .. "%"
GuiScaleInput.Font = Enum.Font.GothamBold
GuiScaleInput.TextSize = 10
GuiScaleInput.TextColor3 = Color3.fromRGB(220, 220, 230)
GuiScaleInput.TextXAlignment = Enum.TextXAlignment.Center
GuiScaleInput.ClearTextOnFocus = false
GuiScaleInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)

local guiScaleDragging = false

local function setGuiScaleFromAlpha(a, instant)
    a = math.clamp(a, 0, 1)
    local value = math.floor(20 + (100 - 20) * a + 0.5)
    PS.GuiScale = value
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
    local scale = 0.5 + (1.5 - 0.5) * ((value - 20) / (100 - 20))
    if instant then
        GlobalUIScale.Scale = scale
    else
        TweenService:Create(GlobalUIScale, TweenInfo.new(0.15), {Scale = scale}):Play()
    end
    SavePanelSettings()
end

local function updateGuiScaleFromX(px)
    local absPos = GuiScaleBar.AbsolutePosition.X
    local sizeX = GuiScaleBar.AbsoluteSize.X
    if sizeX <= 0 then return end
    setGuiScaleFromAlpha((px - absPos) / sizeX, false)
end

GuiScaleInput.FocusLost:Connect(function()
    local txt = GuiScaleInput.Text:gsub("%%", "")
    local num = tonumber(txt)
    if num then
        num = math.clamp(math.floor(num + 0.5), 20, 100)
        PS.GuiScale = num
        setGuiScaleFromAlpha((num - 20) / (100 - 20), false)
    else
        GuiScaleInput.Text = tostring(PS.GuiScale) .. "%"
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
    setGuiScaleFromAlpha((PS.GuiScale - 20) / (100 - 20), true)
end)

task.defer(function()
    if not PS.AutoOpenOnLoad then
        Main.Visible = false
        OpenButton.Visible = true
    else
        Main.Visible = true
        OpenButton.Visible = false
    end
end)

local draggingMain, dragStartMain, startPosMain = false, nil, nil
Main.InputBegan:Connect(function(i)
    if isInteractingWithSlider then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        draggingMain = true
        dragStartMain = i.Position
        startPosMain = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if draggingMain and not isInteractingWithSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartMain
        Main.Position = UDim2.new(startPosMain.X.Scale, startPosMain.X.Offset + delta.X, startPosMain.Y.Scale, startPosMain.Y.Offset + delta.Y)
        PS.MainPos = Main.Position
        SavePanelSettings()
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        draggingMain = false
    end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.RightControl then
        Main.Visible = not Main.Visible
        updateOpenButtonVisibility()
    end
end)

local function RefreshPriorityListUI()
    if not PriorityScroll then return end
    for _, child in ipairs(PriorityScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for i, name in ipairs(PRIORITY_ORDER) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        row.Parent = PriorityScroll
        row:SetAttribute("Index", i)
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local nameLabel = Instance.new("TextLabel", row)
        nameLabel.Size = UDim2.new(1, -100, 1, 0)
        nameLabel.Position = UDim2.new(0, 10, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = name
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 13
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextColor3 = Color3.fromRGB(230, 230, 235)

        local upBtn = Instance.new("TextButton", row)
        upBtn.Size = UDim2.new(0, 24, 0, 24)
        upBtn.Position = UDim2.new(1, -78, 0.5, -12)
        upBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        upBtn.BorderSizePixel = 0
        upBtn.Text = "▲"
        upBtn.Font = Enum.Font.GothamBold
        upBtn.TextSize = 12
        upBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
        upBtn.AutoButtonColor = false
        Instance.new("UICorner", upBtn).CornerRadius = UDim.new(0, 5)

        local downBtn = Instance.new("TextButton", row)
        downBtn.Size = UDim2.new(0, 24, 0, 24)
        downBtn.Position = UDim2.new(1, -50, 0.5, -12)
        downBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        downBtn.BorderSizePixel = 0
        downBtn.Text = "▼"
        downBtn.Font = Enum.Font.GothamBold
        downBtn.TextSize = 12
        downBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
        downBtn.AutoButtonColor = false
        Instance.new("UICorner", downBtn).CornerRadius = UDim.new(0, 5)

        local delBtn = Instance.new("TextButton", row)
        delBtn.Size = UDim2.new(0, 24, 0, 24)
        delBtn.Position = UDim2.new(1, -22, 0.5, -12)
        delBtn.BackgroundColor3 = Color3.fromRGB(70, 30, 30)
        delBtn.BorderSizePixel = 0
        delBtn.Text = "X"
        delBtn.Font = Enum.Font.GothamBold
        delBtn.TextSize = 12
        delBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
        delBtn.AutoButtonColor = false
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 5)

        upBtn.MouseButton1Click:Connect(function()
            local idx = row:GetAttribute("Index")
            if idx and idx > 1 then
                PRIORITY_ORDER[idx], PRIORITY_ORDER[idx - 1] = PRIORITY_ORDER[idx - 1], PRIORITY_ORDER[idx]
                SetPriorityOrder(PRIORITY_ORDER)
                SavePanelSettings()
                RefreshPriorityListUI()
                RefreshList()
            end
        end)

        downBtn.MouseButton1Click:Connect(function()
            local idx = row:GetAttribute("Index")
            if idx and idx < #PRIORITY_ORDER then
                PRIORITY_ORDER[idx], PRIORITY_ORDER[idx + 1] = PRIORITY_ORDER[idx + 1], PRIORITY_ORDER[idx]
                SetPriorityOrder(PRIORITY_ORDER)
                SavePanelSettings()
                RefreshPriorityListUI()
                RefreshList()
            end
        end)

        delBtn.MouseButton1Click:Connect(function()
            local idx = row:GetAttribute("Index")
            if idx then
                table.remove(PRIORITY_ORDER, idx)
                SetPriorityOrder(PRIORITY_ORDER)
                SavePanelSettings()
                RefreshPriorityListUI()
                RefreshList()
            end
        end)
    end
    local h = #PRIORITY_ORDER * 38
    PriorityScroll.CanvasSize = UDim2.new(0, 0, 0, h)
end

local function ShowConfigWindow()
    if ConfigWindow and ConfigWindow.Parent then
        ConfigWindow.Visible = true
        RefreshPriorityListUI()
        return
    end
    ConfigWindow = Instance.new("Frame")
    ConfigWindow.Name = "PriorityConfig"
    ConfigWindow.Size = UDim2.new(0, 340, 0, 420)
    ConfigWindow.AnchorPoint = Vector2.new(0.5, 0.5)
    ConfigWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
    ConfigWindow.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    ConfigWindow.BorderSizePixel = 0
    ConfigWindow.Parent = ScreenGui
    Instance.new("UICorner", ConfigWindow).CornerRadius = UDim.new(0, 10)
    local cStroke = Instance.new("UIStroke", ConfigWindow)
    cStroke.Color = Color3.fromRGB(60, 60, 60)
    cStroke.Thickness = 1

    local TopBar = Instance.new("Frame", ConfigWindow)
    TopBar.Size = UDim2.new(1, 0, 0, 40)
    TopBar.BackgroundTransparency = 1

    local CfgTitle = Instance.new("TextLabel", TopBar)
    CfgTitle.Size = UDim2.new(1, -40, 1, 0)
    CfgTitle.Position = UDim2.new(0, 14, 0, 0)
    CfgTitle.BackgroundTransparency = 1
    CfgTitle.Text = "Brainrot Priority"
    CfgTitle.Font = Enum.Font.GothamBold
    CfgTitle.TextSize = 16
    CfgTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    CfgTitle.TextXAlignment = Enum.TextXAlignment.Left

    local CfgClose = Instance.new("TextButton", TopBar)
    CfgClose.Size = UDim2.new(0, 24, 0, 24)
    CfgClose.Position = UDim2.new(1, -30, 0.5, -12)
    CfgClose.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    CfgClose.BorderSizePixel = 0
    CfgClose.Text = "X"
    CfgClose.Font = Enum.Font.GothamBold
    CfgClose.TextSize = 16
    CfgClose.TextColor3 = Color3.fromRGB(220, 220, 220)
    CfgClose.AutoButtonColor = false
    Instance.new("UICorner", CfgClose).CornerRadius = UDim.new(0, 6)
    CfgClose.MouseButton1Click:Connect(function() ConfigWindow.Visible = false end)

    local AddFrame = Instance.new("Frame", ConfigWindow)
    AddFrame.Size = UDim2.new(0.9, 0, 0, 34)
    AddFrame.Position = UDim2.new(0.05, 0, 0, 52)
    AddFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    AddFrame.BorderSizePixel = 0
    Instance.new("UICorner", AddFrame).CornerRadius = UDim.new(0, 6)

    local AddBox = Instance.new("TextBox", AddFrame)
    AddBox.Size = UDim2.new(1, -60, 1, 0)
    AddBox.Position = UDim2.new(0, 10, 0, 0)
    AddBox.BackgroundTransparency = 1
    AddBox.PlaceholderText = "Add Brainrot"
    AddBox.Font = Enum.Font.Gotham
    AddBox.TextSize = 12
    AddBox.Text = ""
    AddBox.TextColor3 = Color3.fromRGB(230, 230, 230)
    AddBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
    AddBox.TextXAlignment = Enum.TextXAlignment.Left
    AddBox.ClearTextOnFocus = false

    local AddBtn = Instance.new("TextButton", AddFrame)
    AddBtn.Size = UDim2.new(0, 40, 0, 24)
    AddBtn.Position = UDim2.new(1, -48, 0.5, -12)
    AddBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    AddBtn.BorderSizePixel = 0
    AddBtn.Text = "ADD"
    AddBtn.Font = Enum.Font.GothamBold
    AddBtn.TextSize = 11
    AddBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
    AddBtn.AutoButtonColor = false
    Instance.new("UICorner", AddBtn).CornerRadius = UDim.new(0, 5)

    PriorityScroll = Instance.new("ScrollingFrame", ConfigWindow)
    PriorityScroll.Size = UDim2.new(0.9, 0, 0, 320)
    PriorityScroll.Position = UDim2.new(0.05, 0, 0, 96)
    PriorityScroll.BackgroundTransparency = 1
    PriorityScroll.BorderSizePixel = 0
    PriorityScroll.ScrollBarThickness = 4
    PriorityScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    local prLayout = Instance.new("UIListLayout", PriorityScroll)
    prLayout.SortOrder = Enum.SortOrder.LayoutOrder
    prLayout.Padding = UDim.new(0, 6)

    local cfgDragging, cfgDragStart, cfgStartPos = false, nil, nil
    TopBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            cfgDragging = true
            cfgDragStart = i.Position
            cfgStartPos = ConfigWindow.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if cfgDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - cfgDragStart
            ConfigWindow.Position = UDim2.new(cfgStartPos.X.Scale, cfgStartPos.X.Offset + delta.X, cfgStartPos.Y.Scale, cfgStartPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            cfgDragging = false
        end
    end)

    local function TryAdd()
        local txt = AddBox.Text
        txt = txt:gsub("^%s*(.-)%s*$", "%1")
        if txt == "" then return end
        for _, v in ipairs(PRIORITY_ORDER) do
            if v == txt then return end
        end
        table.insert(PRIORITY_ORDER, txt)
        SetPriorityOrder(PRIORITY_ORDER)
        SavePanelSettings()
        RefreshPriorityListUI()
        RefreshList()
        AddBox.Text = ""
    end

    AddBtn.MouseButton1Click:Connect(TryAdd)
    AddBox.FocusLost:Connect(function(enter) if enter then TryAdd() end end)

    ConfigWindow.Visible = true
    RefreshPriorityListUI()
end

ConfigButton.MouseButton1Click:Connect(ShowConfigWindow)

function PS.Disable()
    PS.Active = false
    RemoveESP()
    if ScreenGui then ScreenGui:Destroy() end
end

function PS.GetSelected()
    return PS.SelectedData
end

function PS.GetSelectedModel()
    if PS.SelectedData then
        local model = getAnimalModel(PS.SelectedData.plot, PS.SelectedData.slot)
        if model then
            PS.SelectedModel = model
            PS.SelectedData.model = model
        end
    end
    return PS.SelectedModel
end

function PS.GetWorldPosition()
    if PS.SelectedData then
        local _, pos = getAnimalModel(PS.SelectedData.plot, PS.SelectedData.slot)
        if pos then
            PS.SelectedData.worldPosition = pos
            return pos
        end
        if PS.SelectedData.worldPosition then return PS.SelectedData.worldPosition end
    end
    return nil
end

function PS.GetPlotName()
    if PS.SelectedData then return PS.SelectedData.plot end
    return nil
end

function PS.GetSlot()
    if PS.SelectedData then return PS.SelectedData.slot end
    return nil
end

function PS.GetOwner()
    if PS.SelectedData then return PS.SelectedData.owner end
    return nil
end

RefreshList()

task.spawn(function()
    while PS.Active and ScreenGui and ScreenGui.Parent do
        task.wait(0.2)
        pcall(RefreshList)
    end
end)
