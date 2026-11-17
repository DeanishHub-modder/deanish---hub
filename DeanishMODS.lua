-- ============================================
--  Deanish HUB
--  Owner  : Deanish
--  Coder  : Deanish
--  Game   : Survive the Apocalypse
--  Exec   : Delta
--  Build  : v0.1
--  Note   : Use on alt. No warranty.
-- ============================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
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
local infJump = false
local hungerFound = false
local now = os.clock

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[DeanishHUB] " .. tostring(err)) end
    return ok
end

local function nameMatches(n, list)
    n = tostring(n):lower()
    for _, b in ipairs(list or {}) do if n:find(b, 1, true) then return true end end
    return false
end

local function isItem(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    for _, b in ipairs(blacklist) do if n:find(b, 1, true) then return false end end
    if #whitelist > 0 then
        for _, w in ipairs(whitelist) do if n:find(w, 1, true) then return true end end
        return false
    end
    for _, k in ipairs(keywords) do if n:find(k, 1, true) then return true end end
    return false
end

local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function partOf(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function readyToTry(obj)
    local t = lastTry[obj]
    if t and (now() - t) < cfg.cooldown then return false end
    lastTry[obj] = now()
    return true
end

local function cleanup()
    local cutoff = now() - 60
    for obj, t in pairs(lastTry) do
        if not obj or not obj.Parent or t < cutoff then
            lastTry[obj] = nil
        end
    end
end

local function collectItems(hrp)
    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isItem(obj) then
            local p = partOf(obj)
            if p and p.Position then
                local d = (p.Position - hrp.Position).Magnitude
                if d <= cfg.range then
                    table.insert(list, {obj = p, dist = d})
                end
            end
        end
    end
    if cfg.nearestFirst then
        table.sort(list, function(a,b) return a.dist < b.dist end)
    end
    return list
end

local function touchDrag(hrp)
    for _, e in ipairs(collectItems(hrp)) do
        if readyToTry(e.obj) then
            safe(function()
                firetouchinterest(hrp, e.obj, 0)
                task.wait(0.02)
                firetouchinterest(hrp, e.obj, 1)
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
            safe(function()
                hrp.CFrame = CFrame.new(e.obj.Position + Vector3.new(0,3,0))
            end)
            task.wait(cfg.teleportDelay)
            safe(function()
                firetouchinterest(hrp, e.obj, 0)
                task.wait(0.02)
                firetouchinterest(hrp, e.obj, 1)
            end)
            done += 1
            picked += 1
        end
    end
end

local function promptDrag(hrp)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled and readyToTry(obj) then
            local p = partOf(obj.Parent)
            if p and p.Position and (p.Position - hrp.Position).Magnitude <= cfg.range then
                safe(function()
                    obj:InputHoldBegin()
                    task.wait((obj.HoldDuration or 0)+0.05)
                    obj:InputHoldEnd()
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
                if obj.Name:lower():find(rn:lower(), 1, true) and readyToTry(obj) then
                    safe(function() obj:FireServer() end)
                    break
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
            if p and p.Position then
                local d = (p.Position - hrp.Position).Magnitude
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    if not best then return end
    safe(function() hrp.CFrame = CFrame.new(best.Position + Vector3.new(0,3,0)) end)
    task.wait(0.15)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local p = partOf(obj.Parent)
            if p and p.Position and (p.Position - best.Position).Magnitude < 15 then
                safe(function()
                    obj:InputHoldBegin()
                    task.wait((obj.HoldDuration or 0)+0.05)
                    obj:InputHoldEnd()
                end)
                sorted += 1
            end
        end
    end
end

local function findInBackpack(kw)
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and nameMatches(t.Name, kw) then return t end
        end
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
    hungerFound = false
    local char = LP.Character
    if not char then return 100 end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("IntValue") or v:IsA("NumberValue") then
            local n = v.Name:lower()
            if n:find("hunger", 1, true) or n:find("food", 1, true) then
                hungerFound = true
                return v.Value
            end
        end
    end
    return 100
end

local function useFood()
    local tool = findInBackpack(foodKeywords)
    if not tool then return end
    safe(function()
        tool.Parent = LP.Character
        tool:Activate()
    end)
    eaten += 1
end

local function useHeal()
    local tool = findInBackpack({"bandage","medkit","med","heal","potion"})
    if not tool then return end
    safe(function()
        tool.Parent = LP.Character
        tool:Activate()
    end)
    healed += 1
end

local function autoRepair(hrp)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) and nameMatches(obj.Name, repairKeywords) then
            local p = partOf(obj)
            if p and p.Position and (p.Position - hrp.Position).Magnitude <= cfg.repairRange then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health < hum.MaxHealth * (cfg.repairThreshold/100) then
                    safe(function() hrp.CFrame = CFrame.new(p.Position + Vector3.new(0,3,0)) end)
                    task.wait(0.1)
                    for _, pr in ipairs(workspace:GetDescendants()) do
                        if pr:IsA("ProximityPrompt") and pr.Enabled then
                            local pp = partOf(pr.Parent)
                            if pp and pp.Position and (pp.Position - p.Position).Magnitude < 12 then
                                safe(function()
                                    pr:InputHoldBegin()
                                    task.wait((pr.HoldDuration or 0)+0.05)
                                    pr:InputHoldEnd()
                                end)
                                repaired += 1
                                return
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

-- ============ INFINITE JUMP ============
UserInputService.JumpRequest:Connect(function()
    if not infJump then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        safe(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end)

-- ============ PRESET ============
local PRESET_FILE = "DeanishHUB_config.json"
local hasFS = (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function")

local function savePreset()
    if not hasFS then return false end
    local data = {}
    for k, v in pairs(cfg) do
        if type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
            data[k] = v
        end
    end
    return safe(function()
        writefile(PRESET_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadPreset()
    if not hasFS then return false end
    local ok = safe(function()
        if not isfile(PRESET_FILE) then return end
        local data = HttpService:JSONDecode(readfile(PRESET_FILE))
        if type(data) ~= "table" then return end
        for k, v in pairs(data) do
            if cfg[k] ~= nil then cfg[k] = v end
        end
    end)
    return ok
end

safe(loadPreset)

-- ============ LOOPS ============
task.spawn(function()
    while task.wait(cfg.interval) do
        if panic or not cfg.enabled then continue end
        local hrp = getRoot()
        if hrp then
            if cfg.mode == "touch" or cfg.mode == "both" then safe(touchDrag, hrp) end
            if cfg.mode == "teleport" or cfg.mode == "both" then safe(teleportDrag, hrp) end
            if cfg.usePrompt then safe(promptDrag, hrp) end
            if cfg.useRemote then safe(remoteDrag) end
        end
    end
end)

task.spawn(function()
    while task.wait(15) do
        if not panic and cfg.enabled and cfg.sortToStorage then
            local hrp = getRoot()
            if hrp then safe(sortToStorage, hrp) end
        end
    end
end)

task.spawn(function()
    while task.wait(2) do
        if not panic and cfg.enabled then
            if cfg.autoEat and getHunger() < cfg.eatThreshold and hungerFound then
                safe(useFood)
            end
            if cfg.autoHeal then
                local char = LP.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health < hum.MaxHealth * (cfg.healThreshold/100) then
                    safe(useHeal)
                end
            end
            if cfg.autoRepair then
                local hrp = getRoot()
                if hrp then safe(autoRepair, hrp) end
            end
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if not panic and cfg.enabled and cfg.stateGuard then
            safe(stateGuard)
        end
    end
end)

task.spawn(function()
    while task.wait(5) do
        local hrp = getRoot()
        scanned = hrp and #collectItems(hrp) or 0
        safe(cleanup)
    end
end)

-- ============ PANIC KEY ============
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        panic = true
        cfg.enabled = false
        cfg.autoEat = false
        cfg.autoHeal = false
        cfg.autoRepair = false
        cfg.sortToStorage = false
        cfg.stateGuard = false
        infJump = false
        if gui and main then
            main.Visible = true
        end
    end
end)

-- ============ GUI v0.1 ============
local gui = Instance.new("ScreenGui")
gui.Name = "DeanishHUB"
gui.ResetOnSpawn = false
local parentOk = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not parentOk or not gui.Parent then
    gui.Parent = LP:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 280, 0, 380)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(60, 60, 80)
stroke.Thickness = 1

local header = Instance.new("Frame", main)
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Deanish HUB  ·  v0.1"
title.TextColor3 = Color3.fromRGB(120, 255, 160)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", header)
minBtn.Size = UDim2.new(0, 26, 0, 26)
minBtn.Position = UDim2.new(1, -34, 0, 7)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local body = Instance.new("ScrollingFrame", main)
body.Size = UDim2.new(1, -16, 1, -100)
body.Position = UDim2.new(0, 8, 0, 46)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
body.CanvasSize = UDim2.new(0, 0, 0, 320)
pcall(function() body.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

local layout = Instance.new("UIListLayout", body)
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function section(name)
    local l = Instance.new("TextLabel", body)
    l.Size = UDim2.new(1, 0, 0, 18)
    l.BackgroundTransparency = 1
    l.Text = "  " .. name
    l.TextColor3 = Color3.fromRGB(140, 140, 160)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    return l
end

local function row()
    local f = Instance.new("Frame", body)
    f.Size = UDim2.new(1, 0, 0, 26)
    f.BackgroundTransparency = 1
    local h = Instance.new("UIListLayout", f)
    h.FillDirection = Enum.FillDirection.Horizontal
    h.Padding = UDim.new(0, 4)
    h.SortOrder = Enum.SortOrder.LayoutOrder
    return f
end

local function btn(parent, text, on, w)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(w or 0.5, -2, 1, 0)
    b.BackgroundColor3 = on and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(40, 40, 52)
    b.TextColor3 = on and Color3.fromRGB(230, 255, 235) or Color3.fromRGB(180, 180, 190)
    b.Font = Enum.Font.Gotham
    b.TextSize = 11
    b.Text = text
    b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

section("FARM")
local r1 = row()
local toggle    = btn(r1, "FARM: OFF", false, 1)
toggle.Font = Enum.Font.GothamBold
local r2 = row()
local modeBtn   = btn(r2, "Mode: touch", false)
local nearBtn   = btn(r2, "Nearest: ON", true)
local r3 = row()
local promptBtn = btn(r3, "Prompt: ON", true)
local remoteBtn = btn(r3, "Remote: OFF", false)

section("SURVIVAL")
local r4 = row()
local eatBtn    = btn(r4, "Eat: OFF", false)
local healBtn   = btn(r4, "Heal: OFF", false)
local r5 = row()
local repairBtn = btn(r5, "Repair: OFF", false)
local guardBtn  = btn(r5, "Guard: OFF", false)
local r6 = row()
local sortBtn   = btn(r6, "Sort: OFF", false)
local jumpBtn   = btn(r6, "InfJump: OFF", false)

section("PRESET")
local r7 = row()
local saveBtn   = btn(r7, "Save", false)
local loadBtn   = btn(r7, "Load", false)

local info = Instance.new("TextLabel", main)
info.Size = UDim2.new(1, -16, 0, 46)
info.Position = UDim2.new(0, 8, 1, -50)
info.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
info.TextColor3 = Color3.fromRGB(150, 150, 170)
info.Font = Enum.Font.Code
info.TextSize = 10
info.TextXAlignment = Enum.TextXAlignment.Left
info.Text = "  picked 0 · scanned 0 · sorted 0\n  eaten 0 · healed 0 · repaired 0\n  [RightShift = PANIC]"
Instance.new("UICorner", info).CornerRadius = UDim.new(0, 6)

task.spawn(function()
    while task.wait(0.5) do
        info.Text = string.format(
            "  picked %d · scanned %d · sorted %d\n  eaten %d · healed %d · repaired %d\n  [RightShift = PANIC]",
            picked, scanned, sorted, eaten, healed, repaired)
    end
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    info.Visible = not minimized
    main.Size = minimized and UDim2.new(0, 280, 0, 42) or UDim2.new(0, 280, 0, 380)
    minBtn.Text = minimized and "+" or "—"
end)

local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local function flip(b, label, key)
    cfg[key] = not cfg[key]
    b.Text = label .. ": " .. (cfg[key] and "ON" or "OFF")
    b.BackgroundColor3 = cfg[key] and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(40, 40, 52)
    b.TextColor3 = cfg[key] and Color3.fromRGB(230, 255, 235) or Color3.fromRGB(180, 180, 190)
end

local function sync(b, label, val)
    b.Text = label .. ": " .. (val and "ON"
