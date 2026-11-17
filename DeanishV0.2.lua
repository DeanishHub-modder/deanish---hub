-- ============================================
--  Deanish HUB
--  Owner  : Deanish
--  Coder  : Deanish
--  Game   : Survive the Apocalypse
--  Exec   : Delta
--  Build  : v0.2
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
    cooldown       = 2.0,
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
    killAura       = false,
    auraRange      = 35,
    auraInterval   = 0.15,
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

local fireRates = {0.05, 0.10, 0.15, 0.25, 0.50}
local fireRateIdx = 3
cfg.auraInterval = fireRates[fireRateIdx]

local lastTry = {}
local picked, scanned, sorted, eaten, healed, repaired, auraKills = 0,0,0,0,0,0,0
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

local function isEnemy(model)
    if not model or not model:IsA("Model") then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local plr = Players:GetPlayerFromCharacter(model)
    if plr == LP then return false end
    if plr and plr.Team and LP.Team and plr.Team == LP.Team then return false end
    return true
end

local function killAura(hrp)
    local char = LP.Character
    if not char then return end
    local tool = char:FindFirstChildWhichIsA("Tool")
    if tool and not tool.Parent then tool = nil end
    local target = nil
    local bestD = cfg.auraRange
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and isEnemy(model) then
            local enemyHrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
            if enemyHrp and enemyHrp.Position then
                local d = (enemyHrp.Position - hrp.Position).Magnitude
                if d <= bestD then
                    target = enemyHrp
                    bestD = d
                end
            end
        end
    end
    if not target then return end
    if tool then
        safe(function()
            tool:Activate()
            firetouchinterest(hrp, target, 0)
            task.wait(0.03)
            firetouchinterest(hrp, target, 1)
        end)
    else
        safe(function()
            firetouchinterest(hrp, target, 0)
            task.wait(0.03)
            firetouchinterest(hrp, target, 1)
        end)
    end
    auraKills += 1
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
    if not tool or not tool.Parent then return end
    safe(function()
        tool.Parent = LP.Character
        tool:Activate()
    end)
    eaten += 1
end

local function useHeal()
    local tool = findInBackpack({"bandage","medkit","med","heal","potion"})
    if not tool or not tool.Parent then return end
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

UserInputService.JumpRequest:Connect(function()
    if not infJump then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        safe(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end)

task.spawn(function()
    while task.wait(cfg.interval) do
        if panic or not cfg.enabled then continue end
        local hrp = getRoot()
        if hrp then
            if cfg.mode == "touch" then safe(touchDrag, hrp) end
            if cfg.usePrompt then safe(promptDrag, hrp) end
            if cfg.useRemote then safe(remoteDrag) end
        end
    end
end)

task.spawn(function()
    while task.wait(cfg.auraInterval) do
        if panic or not cfg.killAura then continue end
        local hrp = getRoot()
        if hrp then safe(killAura, hrp) end
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
        cfg.killAura = false
        infJump = false
    end
end)

-- ============ GUI v0.2 ============
local gui = Instance.new("ScreenGui")
gui.Name = "DeanishHUB"
gui.ResetOnSpawn = false
local parentOk = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not parentOk or not gui.Parent then
    gui.Parent = LP:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 280, 0, 420)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.ClipsDescendants = true
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
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Deanish HUB  ·  v0.2"
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
body.Size = UDim2.new(1, -16, 1, -110)
body.Position = UDim2.new(0, 8, 0, 46)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
body.CanvasSize = UDim2.new(0, 0, 0, 360)
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
local nearBtn   = btn(r2, "Nearest: ON", true)
local promptBtn = btn(r2, "Prompt: ON", true)
local r3 = row()
local remoteBtn = btn(r3, "Remote: OFF", false)
local sortBtn   = btn(r3, "Sort: OFF", false)

section("SURVIVAL")
local r4 = row()
local eatBtn    = btn(r4, "Eat: OFF", false)
local healBtn   = btn(r4, "Heal: OFF", false)
local r5 = row()
local repairBtn = btn(r5, "Repair: OFF", false)
local guardBtn  = btn(r5, "Guard: OFF", false)
local r6 = row()
local jumpBtn   = btn(r6, "InfJump: OFF", false)

section("COMBAT")
local r7 = row()
local auraBtn   = btn(r7, "KillAura: OFF", false, 1)
auraBtn.Font = Enum.Font.GothamBold
local r8 = row()
local rateBtn   = btn(r8, "Rate: 0.15s", false, 1)

local info = Instance.new("TextLabel", main)
info.Size = UDim2.new(1, -16, 0, 50)
info.Position = UDim2.new(0, 8, 1, -56)
info.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
info.TextColor3 = Color3.fromRGB(150, 150, 170)
info.Font = Enum.Font.Code
info.TextSize = 10
info.TextXAlignment = Enum.TextXAlignment.Left
info.Text = "  picked 0 · scanned 0 · sorted 0\n  eaten 0 · healed 0 · repaired 0\n  aura 0 · rate 0.15s · [RShift=PANIC]"
Instance.new("UICorner", info).CornerRadius = UDim.new(0, 6)

task.spawn(function()
    while task.wait(0.5) do
        info.Text = string.format(
            "  picked %d · scanned %d · sorted %d\n  eaten %d · healed %d · repaired %d\n  aura %d · rate %.2fs · [RShift=PANIC]",
            picked, scanned, sorted, eaten, healed, repaired, auraKills, cfg.auraInterval)
    end
end)

-- resize handle
local resize = Instance.new("TextButton", main)
resize.Size = UDim2.new(0, 16, 0, 16)
resize.Position = UDim2.new(1, -18, 1, -18)
resize.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
resize.Text = "◢"
resize.TextColor3 = Color3.fromRGB(180, 180, 200)
resize.TextSize = 10
resize.Font = Enum.Font.GothamBold
resize.AutoButtonColor = false
resize.ZIndex = 10
Instance.new("UICorner", resize).CornerRadius = UDim.new(0, 3)

local resizing, resizeStart, startSize
local restoreSize = main.Size
resize.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        resizing = true
        resizeStart = input.Position
        startSize = main.Size
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - resizeStart
        local newX = math.clamp(startSize.X.Offset + delta.X, 200, 600)
        local newY = math.clamp(startSize.Y.Offset + delta.Y, 200, 700)
        main.Size = UDim2.new(0, newX, 0, newY)
        restoreSize = main.Size
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        resizing = false
    end
end)

-- minimize
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        restoreSize = main.Size
        body.Visible = false
        info.Visible = false
        resize.Visible = false
        main.Size = UDim2.new(0, 280, 0, 42)
    else
        body.Visible = true
        info.Visible = true
        resize.Visible = true
        main.Size = restoreSize
    end
    minBtn.Text = minimized and "+" or "—"
end)

-- drag
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

toggle.MouseButton1Click:Connect(function()
    cfg.enabled = not cfg.enabled
    toggle.Text = cfg.enabled and "FARM: ON" or "FARM: OFF"
    toggle.BackgroundColor3 = cfg.enabled and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(40, 40, 52)
    toggle.TextColor3 = cfg.enabled and Color3.fromRGB(230, 255, 235) or Color3.fromRGB(180, 180, 190)
end)

nearBtn.MouseButton1Click:Connect(function() flip(nearBtn, "Nearest", "nearestFirst") end)
promptBtn.MouseButton1Click:Connect(function() flip(promptBtn, "Prompt", "usePrompt") end)
remoteBtn.MouseButton1Click:Connect(function() flip(remoteBtn, "Remote", "useRemote") end)
sortBtn.MouseButton1Click:Connect(function() flip(sortBtn, "Sort", "sortToStorage") end)
eatBtn.MouseButton1Click:Connect(function() flip(eatBtn, "Eat", "autoEat") end)
healBtn.MouseButton1Click:Connect(function() flip(healBtn, "Heal", "autoHeal") end)
repairBtn.MouseButton1Click:Connect(function() flip(repairBtn, "Repair", "autoRepair") end)
guardBtn.MouseButton1Click:Connect(function() flip(guardBtn, "Guard", "stateGuard") end)

jumpBtn.MouseButton1Click:Connect(function()
    infJump = not infJump
    jumpBtn.Text = infJump and "InfJump: ON" or "InfJump: OFF"
    jumpBtn.BackgroundColor3 = infJump and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(40, 40, 52)
    jumpBtn.TextColor3 = infJump and Color3.fromRGB(230, 255, 235) or Color3.fromRGB(180, 180, 190)
end)

auraBtn.MouseButton1Click:Connect(function()
    cfg.killAura = not cfg.killAura
    auraBtn.Text = cfg.killAura and "KillAura: ON" or "KillAura: OFF"
    auraBtn.BackgroundColor3 = cfg.killAura and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(40, 40, 52)
    auraBtn.TextColor3 = cfg.killAura and Color3.fromRGB(230, 255, 235) or Color3.fromRGB(180, 180, 190)
end)

rateBtn.MouseButton1Click:Connect(function()
    fireRateIdx = fireRateIdx + 1
    if fireRateIdx > #fireRates then fireRateIdx = 1 end
    cfg.auraInterval = fireRates[fireRateIdx]
    rateBtn.Text = string.format("Rate: %.2fs", cfg.auraInterval)
end)
