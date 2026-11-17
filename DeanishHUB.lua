-- ============================================
--  Deanish HUB
--  Owner  : dj (Deanish)
--  Coder  : HumanHelper
--  Game   : Survive the Apocalypse
--  Exec   : Delta
--  Build  : v5
--  Note   : Use on alt. No warranty.
-- ============================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local cfg = {
    enabled        = false,
    range          = 80,
    interval       = 0.35,
    mode           = "touch",
    usePrompt      = true,
    useRemote      = false,
    teleportDelay  = 0.08,
    cooldown       = 2.0,
    maxTeleports   = 6,
    sortToStorage  = false,
    storageRange   = 100,
    nearestFirst   = true,
    autoEat        = false,
    eatThreshold   = 40,
    autoHeal       = false,
    healThreshold  = 50,
    autoRepair     = false,
    repairThreshold= 60,
    repairRange    = 80,
    stateGuard     = false,
}

local whitelist = {}
local blacklist = {"crate","chest","box"}
local storageKeyword = {"chest","storage","container","locker","box","crate","deposit"}
local foodKeywords   = {"food","meat","water","can","bandage","medkit","apple","bread","berry","fish"}
local repairKeywords = {"wall","door","floor","foundation","structure","base","turret","generator"}
local keywords = {
    "wood","stone","iron","tree","rock","ore","crate","loot","chest",
    "weapon","gun","ammo","food","bandage","medkit","scrap","fuel",
    "supply","box","bag","can","water","meat","cloth","metal"
}

local lastTry = {}
local picked, scanned, sorted, eaten, healed, repaired = 0,0,0,0,0,0
local panic = false

local function nameMatches(n, list)
    n = n:lower()
    for _, b in ipairs(list or {}) do if n:find(b) then return true end end
    return false
end

local function isItem(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    for _, b in ipairs(blacklist) do if n:find(b) then return false end end
    if #whitelist > 0 then
        for _, w in ipairs(whitelist) do if n:find(w) then return true end end
        return false
    end
    for _, k in ipairs(keywords) do if n:find(k) then return true end end
    return false
end

local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function partOf(obj)
    return obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
end

local function readyToTry(obj)
    local t = lastTry[obj]
    if t and (tick() - t) < cfg.cooldown then return false end
    lastTry[obj] = tick()
    return true
end

local function collectItems(hrp)
    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isItem(obj) then
            local p = partOf(obj)
            if p then
                local d = (p.Position - hrp.Position).Magnitude
                if d <= cfg.range then table.insert(list, {obj = p, dist = d}) end
            end
        end
    end
    if cfg.nearestFirst then table.sort(list, function(a,b) return a.dist < b.dist end) end
    return list
end

local function touchDrag(hrp)
    for _, e in ipairs(collectItems(hrp)) do
        if readyToTry(e.obj) then
            pcall(function()
                firetouchinterest(hrp, e.obj, 0); task.wait(0.02); firetouchinterest(hrp, e.obj, 1)
            end)
            picked += 1
        end
    end
end

local function teleportDrag(hrp)
    local done = 0
    for _, e in ipairs(collectItems(hrp)) do
        if done >= cfg.maxTeleports then break end
        if readyToTry(e.obj) then
            pcall(function() hrp.CFrame = CFrame.new(e.obj.Position + Vector3.new(0,3,0)) end)
            task.wait(cfg.teleportDelay)
            pcall(function()
                firetouchinterest(hrp, e.obj, 0); task.wait(0.02); firetouchinterest(hrp, e.obj, 1)
            end)
            done += 1; picked += 1
        end
    end
end

local function promptDrag(hrp)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled and readyToTry(obj) then
            local p = partOf(obj.Parent)
            if p and (p.Position - hrp.Position).Magnitude <= cfg.range then
                pcall(function()
                    obj:InputHoldBegin(); task.wait((obj.HoldDuration or 0)+0.05); obj:InputHoldEnd()
                end)
                picked += 1
            end
        end
    end
end

local remoteNames = {"Pickup","Collect","Grab","Take","ItemPickup","GetItem","Interact"}
local function remoteDrag()
    local rs = game:GetService("ReplicatedStorage")
    for _, obj in ipairs(rs:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            for _, rn in ipairs(remoteNames) do
                if obj.Name:lower():find(rn:lower()) and readyToTry(obj) then
                    pcall(function() obj:FireServer() end); break
                end
            end
        end
    end
end

local function sortToStorage(hrp)
    local best, bestD = nil, cfg.storageRange
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) and nameMatches(obj.Name, storageKeyword) then
            local p = partOf(obj)
            if p then
                local d = (p.Position - hrp.Position).Magnitude
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    if not best then return end
    pcall(function() hrp.CFrame = CFrame.new(best.Position + Vector3.new(0,3,0)) end)
    task.wait(0.15)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local p = partOf(obj.Parent)
            if p and (p.Position - best.Position).Magnitude < 15 then
                pcall(function()
                    obj:InputHoldBegin(); task.wait((obj.HoldDuration or 0)+0.05); obj:InputHoldEnd()
                end)
                sorted += 1
            end
        end
    end
end

local function findInBackpack(kw)
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return nil end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and nameMatches(t.Name, kw) then return t end
    end
    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and nameMatches(t.Name, kw) then return t end
        end
    end
    return nil
end

local function getHunger()
    local char = LP.Character
    if not char then return 100 end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("IntValue") or v:IsA("NumberValue") then
            if v.Name:lower():find("hunger") or v.Name:lower():find("food") then
                return v.Value
            end
        end
    end
    return 100
end

local function useFood()
    local tool = findInBackpack(foodKeywords)
    if not tool then return end
    pcall(function() tool.Parent = LP.Character; tool:Activate() end)
    eaten += 1
end

local function useHeal()
    local tool = findInBackpack({"bandage","medkit","med","heal","potion"})
    if not tool then return end
    pcall(function() tool.Parent = LP.Character; tool:Activate() end)
    healed += 1
end

local function autoRepair(hrp)
    local repairedOne = false
    for _, obj in ipairs(workspace:GetDescendants()) do
        if repairedOne then break end
        if (obj:IsA("BasePart") or obj:IsA("Model")) and nameMatches(obj.Name, repairKeywords) then
            local p = partOf(obj)
            if p and (p.Position - hrp.Position).Magnitude <= cfg.repairRange then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health < hum.MaxHealth * (cfg.repairThreshold/100) then
                    pcall(function() hrp.CFrame = CFrame.new(p.Position + Vector3.new(0,3,0)) end)
                    task.wait(0.1)
                    for _, pr in ipairs(workspace:GetDescendants()) do
                        if pr:IsA("ProximityPrompt") and pr.Enabled then
                            local pp = partOf(pr.Parent)
                            if pp and (pp.Position - p.Position).Magnitude < 12 then
                                pcall(function()
                                    pr:InputHoldBegin(); task.wait((pr.HoldDuration or 0)+0.05); pr:InputHoldEnd()
                                end)
                                repaired += 1
                                repairedOne = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function stateGuard()
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if hum:GetState() == Enum.HumanoidStateType.Ragdoll then
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    if hum.WalkSpeed < 16 then hum.WalkSpeed = 16 end
end

-- ============ PRESET ============
local PRESET_FILE = "DeanishHUB_config.json"

local function savePreset()
    local data = {}
    for k, v in pairs(cfg) do
        if type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
            data[k] = v
        end
    end
    local ok = pcall(function()
        writefile(PRESET_FILE, game:GetService("HttpService"):JSONEncode(data))
    end)
    return ok
end

local function loadPreset()
    if not (isfile and isfile(PRESET_FILE)) then return false end
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(PRESET_FILE))
    end)
    if not ok or type(data) ~= "table" then return false end
    for k, v in pairs(data) do
        if cfg[k] ~= nil then cfg[k] = v end
    end
    return true
end

pcall(loadPreset)

-- ============ LOOPS ============
task.spawn(function()
    while task.wait(cfg.interval) do
        if panic or not cfg.enabled then continue end
        local hrp = getRoot(); if not hrp then continue end
        if cfg.mode == "touch" or cfg.mode == "both" then pcall(touchDrag, hrp) end
        if cfg.mode == "teleport" or cfg.mode == "both" then pcall(teleportDrag, hrp) end
        if cfg.usePrompt then pcall(promptDrag, hrp) end
        if cfg.useRemote then pcall(remoteDrag) end
    end
end)

task.spawn(function()
    while task.wait(15) do
        if panic or not (cfg.enabled and cfg.sortToStorage) then continue end
        local hrp = getRoot(); if hrp then pcall(sortToStorage, hrp) end
    end
end)

task.spawn(function()
    while task.wait(2) do
        if panic or not cfg.enabled then continue end
        if cfg.autoEat and getHunger() < cfg.eatThreshold then pcall(useFood) end
        if cfg.autoHeal then
            local char = LP.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health < hum.MaxHealth * (cfg.healThreshold/100) then pcall(useHeal) end
        end
        if cfg.autoRepair then
            local hrp = getRoot(); if hrp then pcall(autoRepair, hrp) end
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if panic or not (cfg.enabled and cfg.stateGuard) then continue end
        pcall(stateGuard)
    end
end)

task.spawn(function()
    while task.wait(5) do
        local hrp = getRoot(); scanned = hrp and #collectItems(hrp) or 0
    end
end)

-- ============ PANIC KEY ============
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        panic = true
        cfg.enabled = false
        cfg.autoEat = false; cfg.autoHeal = false; cfg.autoRepair = false
        cfg.sortToStorage = false; cfg.stateGuard = false
    end
end)

-- ============ GUI ============
local gui = Instance.new("ScreenGui", game:GetService("CoreGui"))
gui.Name = "DeanishHUB"

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 250, 0, 460)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", main)
title.Size = UDim2.new(1, 0, 0, 42)
title.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
title.Text = "Deanish HUB\nby dj  |  code: HumanHelper"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local function makeBtn(y, text, on)
    local b = Instance.new("TextButton", main)
    b.Size = UDim2.new(1, -16, 0, 26)
    b.Position = UDim2.new(0, 8, 0, y)
    b.BackgroundColor3 = on and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.Gotham
    b.TextSize = 12
    b.Text = text
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local toggle    = makeBtn(48,  "OFF", false); toggle.Font = Enum.Font.GothamBold
local modeBtn   = makeBtn(80,  "Mode: " .. cfg.mode, false)
local promptBtn = makeBtn(108, "ProximityPrompt: ON", true)
local remoteBtn = makeBtn(136, "Remote: OFF", false)
local sortBtn   = makeBtn(164, "Sort to Storage: OFF", false)
local nearBtn   = makeBtn(192, "Nearest First: ON", true)
local eatBtn    = makeBtn(220, "Auto Eat: OFF", false)
local healBtn   = makeBtn(248, "Auto Heal: OFF", false)
local repairBtn = makeBtn(276, "Auto Repair: OFF", false)
local guardBtn  = makeBtn(304, "State Guard: OFF", false)
local saveBtn   = makeBtn(332, "Save Preset", false)
local loadBtn   = makeBtn(360, "Load Preset", false)

local info = Instance.new("TextLabel", main)
info.Size = UDim2.new(1, -16, 0, 70)
info.Position = UDim2.new(0, 8, 0, 392)
info.BackgroundTransparency = 1
info.TextColor3 = Color3.fromRGB(180,180,180)
info.Font = Enum.Font.Gotham
info.TextSize = 10
info.TextXAlignment = Enum.TextXAlignment.Left
info.Text = "Picked: 0 | Scanned: 0 | Sorted: 0\nEaten: 0 | Healed: 0 | Repaired: 0\n[RightShift = PANIC]"

task.spawn(function()
    while task.wait(0.5) do
        info.Text = string.format(
            "Picked: %d | Scanned: %d | Sorted: %d\nEaten: %d | Healed: %d | Repaired: %d\n[RightShift = PANIC]",
            picked, scanned, sorted, eaten, healed, repaired)
    end
end)

toggle.MouseButton1Click:Connect(function()
    cfg.enabled = not cfg.enabled
    toggle.Text = cfg.enabled and "ON" or "OFF"
    toggle.BackgroundColor3 = cfg.enabled and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

modeBtn.MouseButton1Click:Connect(function()
    if cfg.mode == "touch" then cfg.mode = "teleport"
    elseif cfg.mode == "teleport" then cfg.mode = "both"
    else cfg.mode = "touch" end
    modeBtn.Text = "Mode: " .. cfg.mode
end)

promptBtn.MouseButton1Click:Connect(function()
    cfg.usePrompt = not cfg.usePrompt
    promptBtn.Text = "ProximityPrompt: " .. (cfg.usePrompt and "ON" or "OFF")
    promptBtn.BackgroundColor3 = cfg.usePrompt and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

remoteBtn.MouseButton1Click:Connect(function()
    cfg.useRemote = not cfg.useRemote
    remoteBtn.Text = "Remote: " .. (cfg.useRemote and "ON" or "OFF")
    remoteBtn.BackgroundColor3 = cfg.useRemote and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

sortBtn.MouseButton1Click:Connect(function()
    cfg.sortToStorage = not cfg.sortToStorage
    sortBtn.Text = "Sort to Storage: " .. (cfg.sortToStorage and "ON" or "OFF")
    sortBtn.BackgroundColor3 = cfg.sortToStorage and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

nearBtn.MouseButton1Click:Connect(function()
    cfg.nearestFirst = not cfg.nearestFirst
    nearBtn.Text = "Nearest First: " .. (cfg.nearestFirst and "ON" or "OFF")
    nearBtn.BackgroundColor3 = cfg.nearestFirst and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

eatBtn.MouseButton1Click:Connect(function()
    cfg.autoEat = not cfg.autoEat
    eatBtn.Text = "Auto Eat: " .. (cfg.autoEat and "ON" or "OFF")
    eatBtn.BackgroundColor3 = cfg.autoEat and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

healBtn.MouseButton1Click:Connect(function()
    cfg.autoHeal = not cfg.autoHeal
    healBtn.Text = "Auto Heal: " .. (cfg.autoHeal and "ON" or "OFF")
    healBtn.BackgroundColor3 = cfg.autoHeal and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

repairBtn.MouseButton1Click:Connect(function()
    cfg.autoRepair = not cfg.autoRepair
    repairBtn.Text = "Auto Repair: " .. (cfg.autoRepair and "ON" or "OFF")
    repairBtn.BackgroundColor3 = cfg.autoRepair and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

guardBtn.MouseButton1Click:Connect(function()
    cfg.stateGuard = not cfg.stateGuard
    guardBtn.Text = "State Guard: " .. (cfg.stateGuard and "ON" or "OFF")
    guardBtn.BackgroundColor3 = cfg.stateGuard and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
end)

saveBtn.MouseButton1Click:Connect(function()
    local ok = savePreset()
    saveBtn.Text = ok and "Saved!" or "Save Failed"
    task.wait(1.2)
    saveBtn.Text = "Save Preset"
end)

loadBtn.MouseButton1Click:Connect(function()
    local ok = loadPreset()
    loadBtn.Text = ok and "Loaded!" or "No Preset"
    toggle.Text = cfg.enabled and "ON" or "OFF"
    toggle.BackgroundColor3 = cfg.enabled and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    modeBtn.Text = "Mode: " .. cfg.mode
    promptBtn.Text = "ProximityPrompt: " .. (cfg.usePrompt and "ON" or "OFF")
    promptBtn.BackgroundColor3 = cfg.usePrompt and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    remoteBtn.Text = "Remote: " .. (cfg.useRemote and "ON" or "OFF")
    remoteBtn.BackgroundColor3 = cfg.useRemote and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    sortBtn.Text = "Sort to Storage: " .. (cfg.sortToStorage and "ON" or "OFF")
    sortBtn.BackgroundColor3 = cfg.sortToStorage and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    nearBtn.Text = "Nearest First: " .. (cfg.nearestFirst and "ON" or "OFF")
    nearBtn.BackgroundColor3 = cfg.nearestFirst and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    eatBtn.Text = "Auto Eat: " .. (cfg.autoEat and "ON" or "OFF")
    eatBtn.BackgroundColor3 = cfg.autoEat and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    healBtn.Text = "Auto Heal: " .. (cfg.autoHeal and "ON" or "OFF")
    healBtn.BackgroundColor3 = cfg.autoHeal and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    repairBtn.Text = "Auto Repair: " .. (cfg.autoRepair and "ON" or "OFF")
    repairBtn.BackgroundColor3 = cfg.autoRepair and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    guardBtn.Text = "State Guard: " .. (cfg.stateGuard and "ON" or "OFF")
    guardBtn.BackgroundColor3 = cfg.stateGuard and Color3.fromRGB(60,140,60) or Color3.fromRGB(50,50,60)
    task.wait(1.2)
    loadBtn.Text = "Load Preset"
end)
