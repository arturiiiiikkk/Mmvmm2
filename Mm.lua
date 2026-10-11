--[[
    artihub | Author: Artur
    Game: Murder Mystery 2 (Roblox)
    UI: WindUI  |  Menu key: Right Ctrl
    Works on any executor (optional: firetouchinterest, Drawing for tracers)
]]

print("[artihub] loading...")
pcall(function() if getgenv and getgenv().artihub_unload then getgenv().artihub_unload() end end)
local __ok, __err = xpcall(function()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local CoreGui
do
    local okH, hui = pcall(function() return (gethui and gethui()) or (get_hidden_gui and get_hidden_gui()) end)
    if okH and hui then
        CoreGui = hui
    else
        local okC = pcall(function()
            local f = Instance.new("Folder")
            f.Parent = game:GetService("CoreGui")
            f:Destroy()
        end)
        CoreGui = okC and game:GetService("CoreGui") or Players.LocalPlayer:WaitForChild("PlayerGui")
    end
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local AssetService = game:GetService("AssetService")
local Debris = game:GetService("Debris")

local lp = Players.LocalPlayer
local cam = Workspace.CurrentCamera
local mouse = lp:GetMouse()

---------------------------------------------------------------------
-- LIFECYCLE (everything is tracked so "Unload" can clean up)
---------------------------------------------------------------------
local running = true
local conns = {}
local function bind(signal, fn)
    local c = signal:Connect(fn)
    table.insert(conns, c)
    return c
end

bind(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    cam = Workspace.CurrentCamera
end)

---------------------------------------------------------------------
-- STATE / CONFIG
---------------------------------------------------------------------
local S = {
    espInnocent = false, espSheriff = false, espMurder = false, espNick = false, espGun = false,
    tracers = false, crosshair = false,
    silent = false, silentFov = false, fovSize = 150, hitChance = 100, predScale = 1, debug = false,
    autoShoot = false, autoShootRange = 250,
    killAura = false, auraRange = 12,
    wallbang = false,
    walkspeed = 16, jump = 50, speedGlitch = false, glitchPower = 2,
    noclip = false, infJump = false, bhop = false,
    fly = false, flySpeed = 60,
    spin = false, spinSpeed = 20, clickTp = false,
    antiFling = false, antiVoid = false,
    camFov = 70, useCamFov = false,
    hitsound = false, hitsoundId = "130456049552264",
    autoGrab = false, autoCoins = false, roleNotify = false,
    invisible = false,
    headless = false, korblox = false,
    drone = false, droneSpeed = 70, droneMode = "Fling", droneTarget = "Any",
    akAuto = false,
    accent = Color3.fromRGB(60, 140, 255),
    colors = {
        Innocent = Color3.fromRGB(80, 255, 120),
        Sheriff  = Color3.fromRGB(80, 160, 255),
        Murderer = Color3.fromRGB(255, 70, 70),
    },
}

local Prediction = {
    VerticalMultiplier = 1.72,
    HorizontalMultiplier = 1.84,
    PositionOffset = Vector3.new(-0.09, -0.10, 0),
    PredictionInterval = 0.062,
    SimulationTimer = 0.070,
    Gravity = 196.2,
}

local HITSOUNDS = {
    ["Among Us"] = "130456049552264",
    ["CoD"] = "77082587278347",
    ["Bubble"] = "119697580657161",
}
local AWP_MESH = "5181507328"

-- Paste the direct raw link of the 7yd7 emote script here (or in the Extra tab)
local EMOTE_URL = ""

local flinging, killing, grabbing = false, false, false
local invisSeat = nil
local defaultGravity = Workspace.Gravity
local savedCF = nil

---------------------------------------------------------------------
-- HELPERS
local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res > 0 then return res end
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        local ok2, r = pcall(function() return req({ Url = url, Method = "GET" }) end)
        if ok2 and r and (r.Body or r.body) then return r.Body or r.body end
    end
    error("HTTP GET failed: " .. tostring(url))
end
---------------------------------------------------------------------
local function char(p) return p and p.Character end
local function hrpOf(p) local c = char(p) return c and c:FindFirstChild("HumanoidRootPart") end
local function humOf(p) local c = char(p) return c and c:FindFirstChildOfClass("Humanoid") end
local function alive(p) local h = humOf(p) return h ~= nil and h.Health > 0 end

local function hasTool(p, name)
    local c, bp = char(p), p:FindFirstChild("Backpack")
    return (c and c:FindFirstChild(name)) or (bp and bp:FindFirstChild(name)) or nil
end

local function isGunTool(t)
    if not t or not t:IsA("Tool") then return false end
    local n = t.Name:lower()
    return n:find("gun", 1, true) ~= nil or n:find("revolver", 1, true) ~= nil or n:find("pistol", 1, true) ~= nil
end

local function getGun(p)
    local c, bp = char(p), p:FindFirstChild("Backpack")
    if c then for _, t in ipairs(c:GetChildren()) do if isGunTool(t) then return t end end end
    if bp then for _, t in ipairs(bp:GetChildren()) do if isGunTool(t) then return t end end end
    return nil
end

local function toNum(v, default)
    local n = tonumber(v)
    return n or default
end

local function hex(c)
    local function f(x) return math.clamp(math.floor(x * 255 + 0.5), 0, 255) end
    return string.format("#%02x%02x%02x", f(c.R), f(c.G), f(c.B))
end

local WindUI
local function dbg(text)
    if S.debug then
        pcall(function() WindUI:Notify({ Title = "artihub debug", Content = text, Duration = 2 }) end)
    end
end

---------------------------------------------------------------------
-- ROLES
-- Other players' Backpacks are NOT visible to the client, so the role data
-- pushed by the game is the main source; tools are only a fallback.
---------------------------------------------------------------------
local playerData = {}
local fetching = false

local function fetchPlayerData()
    if fetching then return end
    fetching = true
    task.spawn(function()
        pcall(function()
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            rf = rf and rf:FindFirstChild("Extras")
            rf = rf and rf:FindFirstChild("GetPlayerData")
            if rf and rf:IsA("RemoteFunction") then
                local d = rf:InvokeServer()
                if type(d) == "table" then playerData = d end
            end
        end)
        fetching = false
    end)
end

task.spawn(function()
    pcall(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        local gameplay = remotes and remotes:WaitForChild("Gameplay", 10)
        local ev = gameplay and gameplay:WaitForChild("PlayerDataChanged", 10)
        if ev then
            bind(ev.OnClientEvent, function(data)
                if type(data) == "table" then playerData = data end
            end)
        end
    end)
end)

task.spawn(function()
    while running do
        fetchPlayerData()
        task.wait(4)
    end
end)

local function getRole(p)
    local d = playerData[p.Name]
    local r = d and d.Role
    if r == "Murderer" then return "Murderer" end
    if r == "Sheriff" or r == "Hero" then return "Sheriff" end
    if hasTool(p, "Knife") then return "Murderer" end
    if hasTool(p, "Gun") then return "Sheriff" end
    return "Innocent"
end

local function findByRole(role)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and alive(p) and getRole(p) == role then return p end
    end
end

local function findPlayer(txt)
    txt = (txt or ""):lower()
    if txt == "" then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and (p.Name:lower():find(txt, 1, true) or p.DisplayName:lower():find(txt, 1, true)) then
            return p
        end
    end
end

local function nearestPlayer(role)
    local me = hrpOf(lp)
    if not me then return nil end
    local best, bd
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and alive(p) then
            local root = hrpOf(p)
            if root and (not role or getRole(p) == role) then
                local d = (root.Position - me.Position).Magnitude
                if not bd or d < bd then best, bd = p, d end
            end
        end
    end
    return best
end

local function randomRole(role)
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and alive(p) and hrpOf(p) and getRole(p) == role then table.insert(list, p) end
    end
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

---------------------------------------------------------------------
-- UI LIBRARY + THEMES
---------------------------------------------------------------------

local function MakeLite()
    local Lite = {}
    local gui = Instance.new("ScreenGui")
    gui.Name = "artihub_lite"
    gui.ResetOnSpawn = false
    gui.Parent = CoreGui
    local accent = Color3.fromRGB(60, 140, 255)
    local toggleKey = Enum.KeyCode.RightControl
    local PALETTE = {
        Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 220, 60),
        Color3.fromRGB(80, 255, 120), Color3.fromRGB(60, 220, 220), Color3.fromRGB(60, 140, 255),
        Color3.fromRGB(150, 110, 255), Color3.fromRGB(255, 110, 200), Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(150, 150, 150),
    }

    function Lite:AddTheme() end
    function Lite:SetTheme() end

    local noteHolder = Instance.new("Frame", gui)
    noteHolder.BackgroundTransparency = 1
    noteHolder.Size = UDim2.fromOffset(280, 400)
    noteHolder.Position = UDim2.new(1, -292, 0, 12)
    local noteLay = Instance.new("UIListLayout", noteHolder)
    noteLay.Padding = UDim.new(0, 6)

    function Lite:Notify(cfg)
        cfg = cfg or {}
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 0)
        l.AutomaticSize = Enum.AutomaticSize.Y
        l.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        l.TextColor3 = Color3.fromRGB(235, 235, 245)
        l.Font = Enum.Font.Gotham
        l.TextSize = 13
        l.TextWrapped = true
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = "  " .. tostring(cfg.Title or "artihub") .. ": " .. tostring(cfg.Content or "")
        Instance.new("UICorner", l).CornerRadius = UDim.new(0, 8)
        local st = Instance.new("UIStroke", l)
        st.Color = accent
        st.Thickness = 1
        l.Parent = noteHolder
        task.delay(cfg.Duration or 3, function() if l then l:Destroy() end end)
    end

    function Lite:CreateWindow(cfg)
        cfg = cfg or {}
        local Win = {}
        local main = Instance.new("Frame", gui)
        main.Size = UDim2.fromOffset(560, 380)
        main.Position = UDim2.new(0.5, -280, 0.5, -190)
        main.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
        main.Active = true
        main.Draggable = true
        Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
        local ms = Instance.new("UIStroke", main)
        ms.Color = accent
        ms.Thickness = 1.4

        local title = Instance.new("TextLabel", main)
        title.Size = UDim2.new(1, -20, 0, 30)
        title.Position = UDim2.fromOffset(46, 2)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 15
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextColor3 = Color3.fromRGB(235, 235, 245)
        title.Text = tostring(cfg.Title or "artihub") .. "  " .. tostring(cfg.Author or "")
        local lg = Instance.new("Frame", main)
        lg.Size = UDim2.fromOffset(28, 28)
        lg.Position = UDim2.fromOffset(10, 3)
        lg.BackgroundColor3 = Color3.new(1, 1, 1)
        lg.BorderSizePixel = 0
        Instance.new("UICorner", lg).CornerRadius = UDim.new(0, 8)
        local lgg = Instance.new("UIGradient", lg)
        lgg.Color = ColorSequence.new(accent, Color3.fromRGB(150, 110, 255))
        lgg.Rotation = 45
        local lgt = Instance.new("TextLabel", lg)
        lgt.Size = UDim2.fromScale(1, 1)
        lgt.BackgroundTransparency = 1
        lgt.Font = Enum.Font.GothamBlack
        lgt.TextSize = 17
        lgt.TextColor3 = Color3.new(1, 1, 1)
        lgt.Text = "A"

        local tabBar = Instance.new("ScrollingFrame", main)
        tabBar.Size = UDim2.new(0, 130, 1, -42)
        tabBar.Position = UDim2.fromOffset(8, 34)
        tabBar.BackgroundTransparency = 1
        tabBar.BorderSizePixel = 0
        tabBar.ScrollBarThickness = 2
        tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
        tabBar.CanvasSize = UDim2.new()
        local tl = Instance.new("UIListLayout", tabBar)
        tl.Padding = UDim.new(0, 4)

        local pages = Instance.new("Frame", main)
        pages.Size = UDim2.new(1, -154, 1, -42)
        pages.Position = UDim2.fromOffset(146, 34)
        pages.BackgroundTransparency = 1

        local tabs = {}
        local function selectTab(i)
            for idx, t in ipairs(tabs) do
                t.page.Visible = (idx == i)
                t.btn.BackgroundColor3 = (idx == i) and accent or Color3.fromRGB(30, 30, 40)
            end
        end

        bind(UIS.InputBegan, function(i, gp)
            if not gp and i.KeyCode == toggleKey then main.Visible = not main.Visible end
        end)

        function Win:SetToggleKey(k) toggleKey = k end
        function Win:Toggle() main.Visible = not main.Visible end
        function Win:Tag() end
        function Win:EditOpenButton() end
        function Win:SelectTab(i) selectTab(i) end
        function Win:Destroy() gui:Destroy() end

        function Win:Tab(tcfg)
            tcfg = tcfg or {}
            local page = Instance.new("ScrollingFrame", pages)
            page.Size = UDim2.fromScale(1, 1)
            page.BackgroundTransparency = 1
            page.BorderSizePixel = 0
            page.ScrollBarThickness = 3
            page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.CanvasSize = UDim2.new()
            page.Visible = false
            local pl = Instance.new("UIListLayout", page)
            pl.Padding = UDim.new(0, 6)

            local btn = Instance.new("TextButton", tabBar)
            btn.Size = UDim2.new(1, -4, 0, 28)
            btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 12
            btn.TextColor3 = Color3.fromRGB(235, 235, 245)
            btn.Text = tostring(tcfg.Title or "Tab")
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
            table.insert(tabs, { btn = btn, page = page })
            local myIndex = #tabs
            btn.MouseButton1Click:Connect(function() selectTab(myIndex) end)
            if myIndex == 1 then selectTab(1) end

            local T = {}
            local function row(titleText)
                local r = Instance.new("Frame", page)
                r.Size = UDim2.new(1, -8, 0, 34)
                r.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
                Instance.new("UICorner", r).CornerRadius = UDim.new(0, 8)
                local l = Instance.new("TextLabel", r)
                l.Size = UDim2.new(1, -150, 1, 0)
                l.Position = UDim2.fromOffset(10, 0)
                l.BackgroundTransparency = 1
                l.Font = Enum.Font.Gotham
                l.TextSize = 12
                l.TextXAlignment = Enum.TextXAlignment.Left
                l.TextColor3 = Color3.fromRGB(235, 235, 245)
                l.TextTruncate = Enum.TextTruncate.AtEnd
                l.Text = tostring(titleText or "")
                return r
            end
            local function ctl(r, w)
                local b = Instance.new("TextButton", r)
                b.Size = UDim2.fromOffset(w, 24)
                b.Position = UDim2.new(1, -(w + 8), 0.5, -12)
                b.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
                b.Font = Enum.Font.GothamBold
                b.TextSize = 11
                b.TextColor3 = Color3.fromRGB(235, 235, 245)
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
                return b
            end

            function T:Toggle(c)
                local state = c.Value and true or false
                local r = row(c.Title)
                local b = ctl(r, 64)
                local function paint()
                    b.Text = state and "ON" or "OFF"
                    b.BackgroundColor3 = state and accent or Color3.fromRGB(38, 38, 52)
                end
                paint()
                b.MouseButton1Click:Connect(function()
                    state = not state
                    paint()
                    if c.Callback then pcall(c.Callback, state) end
                end)
                return { Set = function(_, v) state = v and true or false; paint() end }
            end

            function T:Button(c)
                local b = Instance.new("TextButton", page)
                b.Size = UDim2.new(1, -8, 0, 32)
                b.BackgroundColor3 = Color3.fromRGB(34, 34, 48)
                b.Font = Enum.Font.GothamBold
                b.TextSize = 12
                b.TextColor3 = Color3.fromRGB(235, 235, 245)
                b.Text = tostring(c.Title or "")
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
                b.MouseButton1Click:Connect(function() if c.Callback then pcall(c.Callback) end end)
                return b
            end

            function T:Input(c)
                local r = row(c.Title)
                local tb = Instance.new("TextBox", r)
                tb.Size = UDim2.fromOffset(130, 24)
                tb.Position = UDim2.new(1, -138, 0.5, -12)
                tb.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
                tb.Font = Enum.Font.Gotham
                tb.TextSize = 11
                tb.TextColor3 = Color3.fromRGB(235, 235, 245)
                tb.PlaceholderText = tostring(c.Placeholder or "")
                tb.PlaceholderColor3 = Color3.fromRGB(130, 130, 145)
                tb.Text = tostring(c.Value or "")
                tb.ClearTextOnFocus = false
                Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 6)
                tb.FocusLost:Connect(function() if c.Callback then pcall(c.Callback, tb.Text) end end)
                return tb
            end

            function T:Dropdown(c)
                local values = c.Values or {}
                local idx = 1
                for i, v in ipairs(values) do if v == c.Value then idx = i end end
                local r = row(c.Title)
                local b = ctl(r, 140)
                local function paint() b.Text = tostring(values[idx] or "-") end
                paint()
                b.MouseButton1Click:Connect(function()
                    if #values == 0 then return end
                    idx = idx % #values + 1
                    paint()
                    if c.Callback then pcall(c.Callback, values[idx]) end
                end)
                return { Refresh = function(_, nv) values = nv or {}; idx = 1; paint() end }
            end

            function T:Colorpicker(c)
                local r = row(c.Title)
                local b = ctl(r, 60)
                local pi = 0
                b.Text = ""
                b.BackgroundColor3 = c.Default or Color3.new(1, 1, 1)
                b.MouseButton1Click:Connect(function()
                    pi = pi % #PALETTE + 1
                    b.BackgroundColor3 = PALETTE[pi]
                    if c.Callback then pcall(c.Callback, PALETTE[pi]) end
                end)
                return b
            end

            function T:Keybind(c)
                local keycode = c.Value
                if type(keycode) == "string" then
                    local okK, kc = pcall(function() return Enum.KeyCode[keycode] end)
                    keycode = okK and kc or nil
                end
                local r = row(c.Title)
                local b = ctl(r, 64)
                local listening = false
                b.Text = keycode and keycode.Name or "None"
                b.MouseButton1Click:Connect(function()
                    listening = true
                    b.Text = "..."
                end)
                bind(UIS.InputBegan, function(i, gp)
                    if listening and i.UserInputType == Enum.UserInputType.Keyboard then
                        keycode = i.KeyCode
                        b.Text = keycode.Name
                        listening = false
                        return
                    end
                    if not gp and not listening and keycode and i.KeyCode == keycode then
                        if c.Callback then pcall(c.Callback, keycode.Name) end
                    end
                end)
                return b
            end

            return T
        end

        return Win
    end

    return Lite
end

do
    local urls = {
        "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
    }
    for _, u in ipairs(urls) do
        local okL, lib = pcall(function() return loadstring(httpGet(u))() end)
        if okL and type(lib) == "table" and lib.CreateWindow then
            WindUI = lib
            break
        end
    end
end
if not WindUI then
    warn("[artihub] WindUI could not be loaded, using the built-in lite menu.")
    WindUI = MakeLite()
end

local THEMES = {
    Dark = { accent = Color3.fromRGB(150, 150, 255), bg = Color3.fromRGB(12, 12, 15), dialog = Color3.fromRGB(20, 20, 24), button = Color3.fromRGB(32, 32, 38), text = Color3.fromRGB(240, 240, 245), place = Color3.fromRGB(140, 140, 150) },
    White = { accent = Color3.fromRGB(70, 110, 230), bg = Color3.fromRGB(246, 246, 250), dialog = Color3.fromRGB(255, 255, 255), button = Color3.fromRGB(230, 230, 238), text = Color3.fromRGB(25, 25, 32), place = Color3.fromRGB(110, 110, 125) },
    Red = { accent = Color3.fromRGB(235, 60, 60), bg = Color3.fromRGB(14, 12, 12), dialog = Color3.fromRGB(24, 18, 18), button = Color3.fromRGB(40, 28, 28), text = Color3.fromRGB(245, 240, 240), place = Color3.fromRGB(150, 130, 130) },
    Yellow = { accent = Color3.fromRGB(245, 200, 50), bg = Color3.fromRGB(14, 14, 10), dialog = Color3.fromRGB(24, 24, 16), button = Color3.fromRGB(40, 40, 26), text = Color3.fromRGB(245, 245, 235), place = Color3.fromRGB(150, 150, 125) },
    Blue = { accent = Color3.fromRGB(60, 140, 255), bg = Color3.fromRGB(11, 13, 18), dialog = Color3.fromRGB(18, 21, 28), button = Color3.fromRGB(30, 36, 48), text = Color3.fromRGB(235, 240, 250), place = Color3.fromRGB(125, 135, 155) },
}
for name, t in pairs(THEMES) do
    pcall(function()
        WindUI:AddTheme({
            Name = "Arti" .. name,
            Accent = t.accent,
            Dialog = t.dialog,
            Outline = t.accent,
            Text = t.text,
            Placeholder = t.place,
            Background = t.bg,
            Button = t.button,
            Icon = t.accent,
        })
    end)
end

local windowCfg = {
    Title = "artihub",
    Author = "by Artur",
    Folder = "artihub",
    Size = UDim2.fromOffset(600, 450),
    Theme = "ArtiBlue",
    Transparent = true,
}
local Window
do
    local cfg = {}
    for k, v in pairs(windowCfg) do cfg[k] = v end
    cfg.Icon = "crosshair"
    local ok, w = pcall(function() return WindUI:CreateWindow(cfg) end)
    if ok and w then
        Window = w
    else
        local ok2, w2 = pcall(function() return WindUI:CreateWindow(windowCfg) end)
        if ok2 and w2 then
            Window = w2
        else
            WindUI = MakeLite()
            Window = WindUI:CreateWindow(windowCfg)
        end
    end
end
pcall(function() Window:SetToggleKey(Enum.KeyCode.RightControl) end)
pcall(function()
    Window:EditOpenButton({
        Title = "artihub",
        Icon = "crosshair",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
        Color = ColorSequence.new(Color3.fromRGB(60, 140, 255), Color3.fromRGB(150, 110, 255)),
        Enabled = true,
        Draggable = true,
    })
end)

pcall(function() Window:Tag({ Title = "v6", Color = Color3.fromRGB(60, 140, 255) }) end)

local UIReg = { vals = {}, cbs = {}, elems = {}, kinds = {} }
local RECORD = { Toggle = true, Input = true, Dropdown = true, Colorpicker = true }

local function tab(title)
    local okT, t = pcall(function() return Window:Tab({ Title = title }) end)
    if not okT or t == nil then t = {} end
    return setmetatable({}, { __index = function(_, k)
        return function(_, cfg)
            local fn = t[k]
            if type(fn) ~= "function" then return nil end
            local key
            if RECORD[k] and type(cfg) == "table" and cfg.Title then
                key = title .. "/" .. tostring(cfg.Title)
                UIReg.vals[key] = (k == "Colorpicker") and cfg.Default or cfg.Value
                UIReg.kinds[key] = k
                local orig = cfg.Callback
                UIReg.cbs[key] = orig
                cfg.Callback = function(v)
                    UIReg.vals[key] = v
                    if orig then return orig(v) end
                end
            end
            local ok2, res = pcall(fn, t, cfg)
            if not ok2 then warn("[artihub] " .. tostring(k) .. ": " .. tostring(res)) end
            if key then UIReg.elems[key] = res end
            return res
        end
    end })
end
local function notify(text)
    pcall(function() WindUI:Notify({ Title = "artihub", Content = text, Duration = 3 }) end)
end

---------------------------------------------------------------------
-- ESP (Highlight chams, nametag with distance, gun drop). 2x per second.
---------------------------------------------------------------------
local espObjects = {}
local roleCache = {}
local gunDropHl

local function clearEsp(p)
    local o = espObjects[p]
    if o then
        if o.hl then o.hl:Destroy() end
        if o.tag then o.tag:Destroy() end
        espObjects[p] = nil
    end
end

local function makeTag(c)
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromOffset(140, 20)
    gui.StudsOffset = Vector3.new(0, 3.2, 0)
    gui.AlwaysOnTop = true
    local t = Instance.new("TextLabel", gui)
    t.Size = UDim2.fromScale(1, 1)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextStrokeTransparency = 0.4
    gui.Adornee = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
    gui.Parent = CoreGui
    return gui, t
end

local function updateEsp()
    local myRoot = hrpOf(lp)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local c = char(p)
            if c and alive(p) then
                local role = getRole(p)
                roleCache[p] = role
                local wantChams = (role == "Innocent" and S.espInnocent)
                    or (role == "Sheriff" and S.espSheriff)
                    or (role == "Murderer" and S.espMurder)
                local o = espObjects[p]

                if wantChams then
                    if not o or not o.hl or o.hl.Parent == nil or o.hl.Adornee ~= c then
                        clearEsp(p)
                        local hl = Instance.new("Highlight")
                        hl.FillTransparency = 0.5
                        hl.OutlineTransparency = 0
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Adornee = c
                        hl.Parent = CoreGui
                        o = { hl = hl }
                        espObjects[p] = o
                    end
                    o.hl.FillColor = S.colors[role]
                    o.hl.OutlineColor = S.colors[role]
                elseif o and o.hl then
                    o.hl:Destroy(); o.hl = nil
                end

                o = espObjects[p]
                if S.espNick then
                    if not o then o = {}; espObjects[p] = o end
                    if not o.tag or o.tag.Parent == nil or o.tag.Adornee == nil then
                        if o.tag then o.tag:Destroy() end
                        local gui, label = makeTag(c)
                        o.tag, o.label = gui, label
                    end
                    local root = hrpOf(p)
                    local dist = (root and myRoot) and math.floor((root.Position - myRoot.Position).Magnitude) or 0
                    o.label.Text = string.format("%s [%d]", p.DisplayName, dist)
                    o.label.TextColor3 = S.colors[role]
                elseif o and o.tag then
                    o.tag:Destroy(); o.tag = nil
                end
            else
                roleCache[p] = nil
                clearEsp(p)
            end
        end
    end

    local drop = Workspace:FindFirstChild("GunDrop", true)
    if S.espGun and drop then
        if not gunDropHl or gunDropHl.Adornee ~= drop then
            if gunDropHl then gunDropHl:Destroy() end
            gunDropHl = Instance.new("Highlight")
            gunDropHl.FillColor = Color3.fromRGB(255, 220, 60)
            gunDropHl.OutlineColor = Color3.fromRGB(255, 220, 60)
            gunDropHl.FillTransparency = 0.4
            gunDropHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            gunDropHl.Adornee = drop
            gunDropHl.Parent = CoreGui
        end
    elseif gunDropHl then
        gunDropHl:Destroy(); gunDropHl = nil
    end
end

task.spawn(function()
    while running and task.wait(0.5) do pcall(updateEsp) end
end)
bind(Players.PlayerRemoving, function(p) clearEsp(p); roleCache[p] = nil end)

---------------------------------------------------------------------
-- OVERLAY: FOV circle + crosshair (plain GUI, works on every executor), tracers (Drawing if present)
---------------------------------------------------------------------
local themeHooks = {}

local function makeDraggable(handle, target, onClick, onMove)
    local dragging, dStart, sPos, moved = false, nil, nil, false
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dStart, sPos = i.Position, target.Position
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dStart
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
                if onMove then onMove() end
            end
        end
    end)
    bind(UIS.InputEnded, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            if not moved and onClick then onClick() end
        end
    end)
end

local hasDrawing = pcall(function() local l = Drawing.new("Line"); (l.Remove or l.Destroy)(l) end)
local overlayGui, destroyOverlay, aimOrigin
do -- @block
local tracerLines = {}

overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "artihub_overlay"
overlayGui.ResetOnSpawn = false
overlayGui.IgnoreGuiInset = true
overlayGui.DisplayOrder = 5
pcall(function() overlayGui.Parent = CoreGui end)
if not overlayGui.Parent then overlayGui.Parent = lp:WaitForChild("PlayerGui") end

local fov = Instance.new("Frame", overlayGui)
fov.AnchorPoint = Vector2.new(0.5, 0.5)
fov.BackgroundTransparency = 1
fov.Visible = false
Instance.new("UICorner", fov).CornerRadius = UDim.new(1, 0)
local fovStroke = Instance.new("UIStroke", fov)
fovStroke.Thickness = 1.5
fovStroke.Color = Color3.new(1, 1, 1)

local crossParts = {}
local crossDef = {
    { UDim2.new(0.5, -8, 0.5, 0), UDim2.fromOffset(8, 2) },
    { UDim2.new(0.5, 8, 0.5, 0), UDim2.fromOffset(8, 2) },
    { UDim2.new(0.5, 0, 0.5, -8), UDim2.fromOffset(2, 8) },
    { UDim2.new(0.5, 0, 0.5, 8), UDim2.fromOffset(2, 8) },
}
for i = 1, 4 do
    local f = Instance.new("Frame", overlayGui)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BackgroundColor3 = Color3.new(1, 1, 1)
    f.BorderSizePixel = 0
    f.Position = crossDef[i][1]
    f.Size = crossDef[i][2]
    f.Visible = false
    crossParts[i] = f
end

function aimOrigin()
    if UIS.TouchEnabled and not UIS.MouseEnabled then
        local vp = cam.ViewportSize
        return Vector2.new(vp.X / 2, vp.Y / 2)
    end
    return UIS:GetMouseLocation()
end

bind(RunService.RenderStepped, function()
    local showFov = S.silent and S.silentFov
    fov.Visible = showFov and true or false
    if showFov then
        local o = aimOrigin()
        fov.Size = UDim2.fromOffset(S.fovSize * 2, S.fovSize * 2)
        fov.Position = UDim2.fromOffset(o.X, o.Y)
    end
    for i = 1, 4 do crossParts[i].Visible = S.crosshair and true or false end

    if hasDrawing then
        for _, l in pairs(tracerLines) do l.Visible = false end
        if S.tracers then
            local vp = cam.ViewportSize
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp then
                    local root = hrpOf(p)
                    if root and alive(p) then
                        local sp, on = cam:WorldToViewportPoint(root.Position)
                        if on then
                            local l = tracerLines[p]
                            if not l then
                                l = Drawing.new("Line")
                                l.Thickness = 1.5
                                tracerLines[p] = l
                            end
                            l.From = Vector2.new(vp.X / 2, vp.Y)
                            l.To = Vector2.new(sp.X, sp.Y)
                            l.Color = S.colors[roleCache[p] or "Innocent"]
                            l.Visible = true
                        end
                    end
                end
            end
        end
    end
end)

bind(Players.PlayerRemoving, function(p)
    local l = tracerLines[p]
    if l then pcall(function() (l.Remove or l.Destroy)(l) end); tracerLines[p] = nil end
end)

function destroyOverlay()
    for _, l in pairs(tracerLines) do pcall(function() (l.Remove or l.Destroy)(l) end) end
    tracerLines = {}
    pcall(function() overlayGui:Destroy() end)
end
end -- @endblock

---------------------------------------------------------------------
-- PING / VELOCITY TRACKING (for prediction)
---------------------------------------------------------------------
local getPrediction
do -- @block
local pingHistory, estimatedPing = {}, 0.05
task.spawn(function()
    while running do
        local cur = 0.05
        pcall(function() cur = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000 end)
        table.insert(pingHistory, 1, cur)
        while #pingHistory > 10 do table.remove(pingHistory) end
        local sum = 0
        for _, v in ipairs(pingHistory) do sum += v end
        estimatedPing = #pingHistory > 0 and (sum / #pingHistory) or 0.05
        task.wait(0.05)
    end
end)

local velHistory = {}
bind(RunService.Heartbeat, function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local root = hrpOf(p)
            if root then
                local h = velHistory[p]
                if not h then h = {}; velHistory[p] = h end
                table.insert(h, 1, root.AssemblyLinearVelocity)
                while #h > 5 do table.remove(h) end
            end
        end
    end
end)
bind(Players.PlayerRemoving, function(p) velHistory[p] = nil end)

local function filteredVelocity(p, raw)
    local h = velHistory[p]
    if not h or #h == 0 then return raw end
    local sum = Vector3.zero
    for _, v in ipairs(h) do sum += v end
    return sum / #h
end

function getPrediction(target)
    local root, hum = hrpOf(target), humOf(target)
    if not root or not hum or hum.Health <= 0 then return nil end

    local vel = filteredVelocity(target, root.AssemblyLinearVelocity)
    local dt = math.min(Prediction.PredictionInterval + estimatedPing, Prediction.SimulationTimer) * S.predScale

    local hv = Vector3.new(vel.X, 0, vel.Z) * Prediction.HorizontalMultiplier
    local pos = root.Position + hv * dt
    local y = root.Position.Y + vel.Y * Prediction.VerticalMultiplier * dt

    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
        y = y - 0.5 * Prediction.Gravity * dt * dt
    end
    return Vector3.new(pos.X, y, pos.Z) + Prediction.PositionOffset
end

end -- @endblock

---------------------------------------------------------------------
-- SILENT AIM (hooks the gun's Activated event, no global metamethod hooks)
---------------------------------------------------------------------
local function getAimTarget()
    local m = findByRole("Murderer")
    if not m then dbg("Silent aim: murderer not found"); return nil end
    local root = hrpOf(m)
    if not root then return nil end
    if S.silentFov then
        local sp, on = cam:WorldToViewportPoint(root.Position)
        if not on then dbg("Silent aim: murderer off screen"); return nil end
        if (Vector2.new(sp.X, sp.Y) - aimOrigin()).Magnitude > S.fovSize then
            dbg("Silent aim: murderer outside FOV")
            return nil
        end
    end
    return m
end

local function shoot(gun, target)
    if not gun or not target then return false end
    local c = char(lp)
    if not c then return false end
    local hand = c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm") or c.PrimaryPart
    if not hand then return false end
    local pred = getPrediction(target)
    if not pred then return false end

    local remote = gun:FindFirstChild("Shoot")
    if remote and remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer(CFrame.new(hand.Position), CFrame.new(pred)) end)
        return true
    end

    local beam = gun:FindFirstChild("KnifeLocal")
    local rf = beam and beam:FindFirstChild("CreateBeam") and beam.CreateBeam:FindFirstChild("RemoteFunction")
    if rf then
        pcall(function() rf:InvokeServer(1, pred, "AH2") end)
        return true
    end
    dbg("Silent aim: gun has no Shoot remote")
    return false
end

local aimConns = {}
do -- @block
local function setupGun(tool)
    if not isGunTool(tool) or aimConns[tool] then return end
    aimConns[tool] = tool.Activated:Connect(function()
        if not S.silent then return end
        if math.random(1, 100) > S.hitChance then return end
        local target = getAimTarget()
        if target then shoot(tool, target) end
    end)
end

local function cleanupGun(tool)
    local c = aimConns[tool]
    if c then c:Disconnect(); aimConns[tool] = nil end
end

local function watchContainer(cont)
    for _, t in ipairs(cont:GetChildren()) do setupGun(t) end
    bind(cont.ChildAdded, setupGun)
end

local function hookCharacter(c)
    watchContainer(c)
    bind(c.ChildRemoved, function(t)
        local bp = lp:FindFirstChildOfClass("Backpack")
        if not (bp and t:IsDescendantOf(bp)) and t.Parent ~= c then cleanupGun(t) end
    end)
end

task.spawn(function()
    local bp = lp:WaitForChild("Backpack", 10)
    if bp then watchContainer(bp) end
    bind(lp.CharacterAdded, function()
        local b = lp:FindFirstChildOfClass("Backpack")
        if b then watchContainer(b) end
    end)
end)
if lp.Character then hookCharacter(lp.Character) end
bind(lp.CharacterAdded, hookCharacter)

end -- @endblock

local function equip(tool)
    local h = humOf(lp)
    if h and tool and tool.Parent ~= char(lp) then
        h:EquipTool(tool)
        task.wait(0.15)
    end
end

local function shootMurderer()
    local gun = getGun(lp)
    local m = findByRole("Murderer")
    if not gun or not m then notify("No gun or no murderer found."); return end
    equip(gun)
    shoot(gun, m)
end

task.spawn(function()
    while running do
        task.wait(0.3)
        if S.autoShoot then
            pcall(function()
                local gun = getGun(lp)
                local m = findByRole("Murderer")
                local me, root = hrpOf(lp), m and hrpOf(m)
                if not gun or not m or not me or not root or not alive(lp) then return end
                if (root.Position - me.Position).Magnitude > S.autoShootRange then return end
                if not S.wallbang then
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = { char(lp), char(m) }
                    if Workspace:Raycast(me.Position, root.Position - me.Position, params) then return end
                end
                equip(gun)
                shoot(gun, m)
            end)
        end
    end
end)

---------------------------------------------------------------------
-- WALLBANG (map parts stop blocking raycasts on your side)
---------------------------------------------------------------------
local setWallbang
do -- @block
local wbParts, wbConn = {}, nil

local function wbApply(v)
    if not v:IsA("BasePart") or not v.CanQuery or wbParts[v] ~= nil then return end
    local model = v:FindFirstAncestorOfClass("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then return end
    if v:FindFirstAncestorOfClass("Tool") or v:FindFirstAncestorOfClass("Accessory") then return end
    if v:IsDescendantOf(cam) then return end
    wbParts[v] = true
    v.CanQuery = false
end

function setWallbang(on)
    S.wallbang = on
    if wbConn then wbConn:Disconnect(); wbConn = nil end
    if on then
        task.spawn(function()
            local n = 0
            for _, v in ipairs(Workspace:GetDescendants()) do
                if not S.wallbang then break end
                wbApply(v)
                n += 1
                if n % 400 == 0 then task.wait() end
            end
        end)
        wbConn = Workspace.DescendantAdded:Connect(function(v)
            if S.wallbang then task.defer(wbApply, v) end
        end)
    else
        for v in pairs(wbParts) do
            if v and v.Parent then pcall(function() v.CanQuery = true end) end
        end
        wbParts = {}
    end
end

end -- @endblock

---------------------------------------------------------------------
-- TELEPORTS
---------------------------------------------------------------------
local function tpTo(cf)
    local h = hrpOf(lp)
    if h and cf then
        h.CFrame = cf
        h.AssemblyLinearVelocity = Vector3.zero
    end
end

local function pointIn(model)
    if not model then return nil end
    local spawns = model:FindFirstChild("Spawns", true)
    if spawns then
        local kids = spawns:GetChildren()
        if #kids > 0 then
            local s = kids[math.random(#kids)]
            if s:IsA("BasePart") then return s.CFrame + Vector3.new(0, 4, 0) end
        end
    end
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok then return cf + Vector3.new(0, 5, 0) end
    return nil
end

local function getMap()
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") and m.Name ~= "Lobby" and not Players:GetPlayerFromCharacter(m)
            and (m:FindFirstChild("Spawns") or m:FindFirstChild("CoinContainer")) then
            return m
        end
    end
end

local function tpMap()
    local cf = pointIn(getMap())
    if cf then tpTo(cf) else notify("Map not found (round not started?).") end
end

local function tpLobby()
    local cf = pointIn(Workspace:FindFirstChild("Lobby"))
    if cf then tpTo(cf) else notify("Lobby not found.") end
end

local function tpPlayer(p)
    local t = p and hrpOf(p)
    if t then tpTo(t.CFrame * CFrame.new(0, 0, 3)) else notify("Player not found.") end
end

local function tpRandom()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and alive(p) and hrpOf(p) then table.insert(list, p) end
    end
    if #list == 0 then notify("Nobody to teleport to."); return end
    tpPlayer(list[math.random(#list)])
end

local function tpGunDrop()
    local drop = Workspace:FindFirstChild("GunDrop", true)
    if drop then tpTo(drop.CFrame + Vector3.new(0, 3, 0)) else notify("No dropped gun right now.") end
end

local function savePos()
    local h = hrpOf(lp)
    if h then savedCF = h.CFrame; notify("Position saved.") end
end
local function loadPos()
    if savedCF then tpTo(savedCF) else notify("No saved position.") end
end

local function serverHop()
    notify("Searching for a server...")
    local ok, body = pcall(function()
        return httpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
    end)
    if not ok then notify("Could not load the server list."); return end
    local okj, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not okj or not data or not data.data then notify("Bad server list."); return end
    local options = {}
    for _, sv in ipairs(data.data) do
        if sv.id ~= game.JobId and sv.playing and sv.maxPlayers and sv.playing < sv.maxPlayers - 1 then
            table.insert(options, sv.id)
        end
    end
    if #options == 0 then notify("No free servers found."); return end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, options[math.random(#options)], lp)
end

---------------------------------------------------------------------
-- MOVEMENT / MISC
---------------------------------------------------------------------
local lastSafe
bind(RunService.Heartbeat, function(dt)
    local h, hrp = humOf(lp), hrpOf(lp)
    if not h or not hrp then return end

    if S.walkspeed ~= 16 and not S.drone then h.WalkSpeed = S.walkspeed end
    if S.jump ~= 50 and not S.drone then
        h.UseJumpPower = true
        h.JumpPower = S.jump
    end
    if S.speedGlitch and h.MoveDirection.Magnitude > 0 then
        hrp.CFrame = hrp.CFrame + h.MoveDirection * S.glitchPower * dt * 10
    end
    if S.spin and not S.fly then
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(S.spinSpeed), 0)
    end
    if S.bhop and UIS:IsKeyDown(Enum.KeyCode.Space) and h.FloorMaterial ~= Enum.Material.Air then
        h:ChangeState(Enum.HumanoidStateType.Jumping)
    end

    if S.antiVoid and not flinging and not killing and not invisSeat then
        if hrp.Position.Y > -50 then
            lastSafe = hrp.CFrame
        elseif hrp.Position.Y < -150 and lastSafe then
            hrp.CFrame = lastSafe
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end
end)

bind(RunService.Stepped, function()
    if S.noclip or S.fly then
        local c = char(lp)
        if c then
            for _, v in ipairs(c:GetDescendants()) do
                if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
            end
        end
    end
    if S.antiFling then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character then
                for _, v in ipairs(p.Character:GetChildren()) do
                    if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
                end
            end
        end
    end
end)

bind(RunService.RenderStepped, function()
    if S.useCamFov and not S.drone then cam.FieldOfView = S.camFov end
end)

bind(UIS.JumpRequest, function()
    local hrp, h = hrpOf(lp), humOf(lp)
    if not hrp or not h then return end
    if S.infJump then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

bind(UIS.InputBegan, function(i, gp)
    if gp or not S.clickTp then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        local hit = mouse.Hit
        if hit then tpTo(CFrame.new(hit.Position + Vector3.new(0, 3, 0))) end
    end
end)

-- FLY
local setFly
do -- @block
local flyBV, flyBG, flyConn
function setFly(on)
    S.fly = on
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    local hrp, h = hrpOf(lp), humOf(lp)
    if h then h.PlatformStand = false end
    if not on or not hrp or not h then return end

    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = hrp
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    flyBG.P = 9e4
    flyBG.CFrame = hrp.CFrame
    flyBG.Parent = hrp
    h.PlatformStand = true

    flyConn = RunService.RenderStepped:Connect(function()
        local hh = humOf(lp)
        if not hh or not flyBV or not flyBG then return end
        local lv = cam.CFrame:VectorToObjectSpace(hh.MoveDirection)
        local dir = cam.CFrame.RightVector * lv.X + cam.CFrame.LookVector * (-lv.Z)
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0, 1, 0) end
        flyBV.Velocity = dir * S.flySpeed
        flyBG.CFrame = cam.CFrame
    end)
end
bind(lp.CharacterAdded, function()
    S.fly = false
    if flyConn then flyConn:Disconnect() end
    flyConn, flyBV, flyBG = nil, nil, nil
end)

end -- @endblock

bind(lp.Idled, function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

local setFullbright
do -- @block
local lightBackup
function setFullbright(on)
    if on then
        if lightBackup then return end
        lightBackup = {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
        }
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e6
        Lighting.Ambient = Color3.fromRGB(190, 190, 190)
        Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
    elseif lightBackup then
        for k, v in pairs(lightBackup) do Lighting[k] = v end
        lightBackup = nil
    end
end

end -- @endblock

local function fpsBoost()
    pcall(function() Lighting.GlobalShadows = false end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") then
            v.Enabled = false
        end
    end
    notify("FPS boost applied.")
end

local function spectate(p)
    local h = p and humOf(p)
    if h then cam.CameraSubject = h else notify("Player not found.") end
end
local function unspectate()
    local h = humOf(lp)
    if h then cam.CameraSubject = h end
end

---------------------------------------------------------------------
-- GUN GRAB / AUTO GRAB / AUTO COINS
---------------------------------------------------------------------
local function grabGun(silentMode)
    if grabbing then return end
    local drop = Workspace:FindFirstChild("GunDrop", true)
    local hrp = hrpOf(lp)
    if not drop or not hrp then
        if not silentMode then notify("No dropped gun right now.") end
        return
    end
    grabbing = true
    local home = hrp.CFrame
    hrp.CFrame = drop.CFrame
    pcall(function()
        firetouchinterest(hrp, drop, 0)
        firetouchinterest(hrp, drop, 1)
    end)
    task.wait(0.35)
    if hrpOf(lp) then hrpOf(lp).CFrame = home end
    grabbing = false
end

task.spawn(function()
    while running and task.wait(0.4) do
        if S.autoGrab and alive(lp) and not hasTool(lp, "Gun") and not hasTool(lp, "Knife") then
            pcall(grabGun, true)
        end
    end
end)

local coinTries = {}
task.spawn(function()
    while running and task.wait(0.2) do
        if S.autoCoins and alive(lp) and not killing and not flinging and not grabbing and not S.drone then
            pcall(function()
                local map = getMap()
                local cc = map and map:FindFirstChild("CoinContainer")
                local me = hrpOf(lp)
                if not cc or not me then return end
                local best, bd
                for _, coin in ipairs(cc:GetChildren()) do
                    if coin:IsA("BasePart") and (coinTries[coin] or 0) < 3 then
                        local d = (coin.Position - me.Position).Magnitude
                        if not bd or d < bd then best, bd = coin, d end
                    end
                end
                if best then
                    coinTries[best] = (coinTries[best] or 0) + 1
                    me.CFrame = best.CFrame
                    pcall(function()
                        firetouchinterest(me, best, 0)
                        firetouchinterest(me, best, 1)
                    end)
                    task.wait(0.12)
                end
            end)
        end
    end
end)

---------------------------------------------------------------------
-- KNIFE: kill one / kill all / kill aura (murderer)
---------------------------------------------------------------------
local function stab(knife, p)
    local thrp, tc = hrpOf(p), char(p)
    if not thrp or not tc then return end
    pcall(function() knife:Activate() end)
    for _, d in ipairs(knife:GetDescendants()) do
        if d:IsA("RemoteEvent") and (d.Name == "Stab" or d.Name == "HandleTouched") then
            pcall(function()
                if d.Name == "Stab" then d:FireServer("Slash") else d:FireServer(thrp) end
            end)
        end
    end
    local handle = knife:FindFirstChild("Handle")
    if handle then
        for _, part in ipairs({ thrp, tc:FindFirstChild("Head"), tc:FindFirstChild("UpperTorso") or tc:FindFirstChild("Torso") }) do
            pcall(function()
                firetouchinterest(handle, part, 0)
                firetouchinterest(handle, part, 1)
            end)
        end
    end
end

local function killOne(knife, p)
    for _ = 1, 15 do
        if not alive(p) then break end
        local me, thrp = hrpOf(lp), hrpOf(p)
        if not me or not thrp then break end
        me.CFrame = thrp.CFrame * CFrame.new(0, 0, 1.5)
        me.AssemblyLinearVelocity = Vector3.zero
        stab(knife, p)
        task.wait(0.1)
    end
end

local function killTargets(list)
    if killing then return end
    local knife = hasTool(lp, "Knife")
    local hrp = hrpOf(lp)
    if not knife or not hrp then notify("You are not the murderer."); return end
    killing = true
    local home = hrp.CFrame
    equip(knife)
    for _, p in ipairs(list) do
        if p and p ~= lp and alive(p) then killOne(knife, p) end
    end
    if hrpOf(lp) then hrpOf(lp).CFrame = home end
    killing = false
end

local function killAll() killTargets(Players:GetPlayers()) end
local function killSheriff()
    local s = findByRole("Sheriff")
    if s then killTargets({ s }) else notify("No sheriff alive.") end
end
local function killNearest()
    local p = nearestPlayer()
    if p then killTargets({ p }) else notify("Nobody nearby.") end
end

task.spawn(function()
    while running do
        task.wait(0.12)
        if S.killAura and not killing then
            pcall(function()
                local knife = hasTool(lp, "Knife")
                local me = hrpOf(lp)
                if not knife or not me or not alive(lp) then return end
                for _, p in ipairs(Players:GetPlayers()) do
                    local root = (p ~= lp) and hrpOf(p)
                    if root and alive(p) and (root.Position - me.Position).Magnitude <= S.auraRange then
                        if knife.Parent ~= char(lp) then humOf(lp):EquipTool(knife) end
                        stab(knife, p)
                    end
                end
            end)
        end
    end
end)

---------------------------------------------------------------------
-- FLING (returns you to where you were, zeroes velocity so you survive)
---------------------------------------------------------------------
local function fling(target)
    if flinging then return end
    if not target or target == lp then notify("Player not found."); return end
    local hrp, h = hrpOf(lp), humOf(lp)
    if not hrp or not h or not hrpOf(target) then return end
    flinging = true

    local home = hrp.CFrame
    pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
    for _, v in ipairs(char(lp):GetDescendants()) do
        if v:IsA("BasePart") then
            v.CustomPhysicalProperties = PhysicalProperties.new(math.huge, 0.3, 0.5)
            v.CanCollide = false
        end
    end
    local bav = Instance.new("BodyAngularVelocity")
    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bav.P = math.huge
    bav.AngularVelocity = Vector3.new(0, 9e5, 0)
    bav.Parent = hrp

    local start = tick()
    local conn = RunService.Heartbeat:Connect(function()
        local t, me = hrpOf(target), hrpOf(lp)
        if t and me then
            me.CFrame = t.CFrame + t.AssemblyLinearVelocity * 0.1
            me.AssemblyLinearVelocity = Vector3.new(9e5, 9e5, 9e5)
        end
    end)

    while tick() - start < 2.5 do
        local t = hrpOf(target)
        if not t or t.AssemblyLinearVelocity.Magnitude > 500 or t.Position.Y < -200 then break end
        task.wait()
    end

    conn:Disconnect()
    bav:Destroy()
    local c2 = char(lp)
    if c2 then
        for _, v in ipairs(c2:GetDescendants()) do
            if v:IsA("BasePart") then v.CustomPhysicalProperties = nil end
        end
    end
    for _ = 1, 20 do
        local me = hrpOf(lp)
        if me then
            me.AssemblyLinearVelocity = Vector3.zero
            me.AssemblyAngularVelocity = Vector3.zero
            me.CFrame = home
        end
        RunService.Heartbeat:Wait()
    end
    pcall(function()
        local hh = humOf(lp)
        if hh then hh:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end
    end)
    flinging = false
end

local function flingAll()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and alive(p) and running then
            fling(p)
            task.wait(0.3)
        end
    end
end

---------------------------------------------------------------------
-- INVISIBLE (seat trick)
---------------------------------------------------------------------
local function setInvisible(on)
    S.invisible = on
    local c, hrp = char(lp), hrpOf(lp)
    if not c or not hrp then return end
    if on then
        if invisSeat then return end
        local torso = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
        if not torso then return end
        local saved = hrp.CFrame
        local void = Vector3.new(-25.95, 84, 3537.55)
        hrp.CFrame = CFrame.new(void)
        task.wait(0.2)
        local seat = Instance.new("Seat")
        seat.Name = "artihub_seat"
        seat.Transparency = 1
        seat.CanCollide = false
        seat.CanTouch = false
        seat.Anchored = false
        seat.Massless = true
        seat.CFrame = CFrame.new(void)
        seat.Parent = Workspace
        local weld = Instance.new("Weld")
        weld.Part0 = seat
        weld.Part1 = torso
        weld.Parent = seat
        task.wait(0.1)
        seat.CFrame = saved
        invisSeat = seat
        for _, v in ipairs(c:GetDescendants()) do
            if (v:IsA("BasePart") or v:IsA("Decal")) and v.Name ~= "HumanoidRootPart" then
                v.Transparency = 0.5
            end
        end
    else
        if invisSeat then
            local now = hrp.CFrame
            invisSeat:Destroy(); invisSeat = nil
            task.wait()
            if hrpOf(lp) then hrpOf(lp).CFrame = now end
        end
        for _, v in ipairs(c:GetDescendants()) do
            if (v:IsA("BasePart") or v:IsA("Decal")) and v.Name ~= "HumanoidRootPart" then
                v.Transparency = 0
            end
        end
    end
end
bind(lp.CharacterAdded, function() invisSeat = nil; S.invisible = false end)

---------------------------------------------------------------------
-- LOOK STATE: avatar copy, bundles, emotes (client side, re-applied after respawn)
---------------------------------------------------------------------
local Look = {
    avatarUid = nil,       -- full avatar copy
    fields = {},           -- bundle fields (body parts + animations)
    emotes = {},           -- name -> asset id
}

local BUNDLE_FIELDS = {
    "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Face",
    "IdleAnimation", "WalkAnimation", "RunAnimation", "JumpAnimation",
    "FallAnimation", "ClimbAnimation", "SwimAnimation", "MoodAnimation",
}

local function resolveUserId(input)
    input = (tostring(input or "")):gsub("%s+", "")
    if input == "" then return nil end
    local n = tonumber(input)
    if n then return n end
    local p = findPlayer(input)
    if p then return p.UserId end
    local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, input)
    if ok then return id end
    return nil
end

local function reapplyLook()
    local h = humOf(lp)
    if not h then return end
    if Look.avatarUid then
        local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, Look.avatarUid)
        if ok and desc then pcall(function() h:ApplyDescription(desc) end) end
    end
    if next(Look.fields) ~= nil or next(Look.emotes) ~= nil then
        local ok, cur = pcall(function() return h:GetAppliedDescription() end)
        if ok and cur then
            for f, v in pairs(Look.fields) do pcall(function() cur[f] = v end) end
            for n, id in pairs(Look.emotes) do pcall(function() cur:AddEmote(n, id) end) end
            pcall(function() h:ApplyDescription(cur) end)
        end
    end
end

local function applyAvatar(input)
    local uid = resolveUserId(input)
    if not uid then notify("User not found."); return end
    Look.avatarUid = uid
    Look.fields = {}
    reapplyLook()
    notify("Avatar applied (only you see it).")
end

local function resetAvatar()
    Look.avatarUid = lp.UserId
    Look.fields = {}
    Look.emotes = {}
    reapplyLook()
    Look.avatarUid = nil
    notify("Avatar reset.")
end

local function applyBundle(bundleId)
    local ok, details = pcall(AssetService.GetBundleDetailsAsync, AssetService, bundleId)
    if not ok or not details then notify("Could not load the bundle."); return end
    local outfitId
    for _, item in ipairs(details.Items or {}) do
        if item.Type == "UserOutfit" then outfitId = item.Id break end
    end
    if not outfitId then notify("This bundle has no outfit."); return end
    local ok2, bdesc = pcall(Players.GetHumanoidDescriptionFromOutfitId, Players, outfitId)
    if not ok2 or not bdesc then notify("Could not read the bundle."); return end
    for _, f in ipairs(BUNDLE_FIELDS) do
        local okf, v = pcall(function() return bdesc[f] end)
        if okf and v ~= nil and v ~= 0 then Look.fields[f] = v end
    end
    reapplyLook()
    notify("Bundle applied: " .. tostring(details.Name or bundleId))
end

local function applyEmote(name, assetId)
    local clean = (name or "emote"):gsub("[^%w]", "")
    if clean == "" then clean = "emote" .. tostring(assetId) end
    Look.emotes[clean] = assetId
    reapplyLook()
    local h = humOf(lp)
    if h then
        task.wait(0.2)
        local ok = pcall(function() h:PlayEmote(clean) end)
        if not ok then notify("Emote could not play.") end
    end
end

local function playEmote(name)
    local h = humOf(lp)
    if not h then return end
    local ok = pcall(function() h:PlayEmote(name) end)
    if not ok then notify("Emote failed.") end
end

local korbloxBackup = {}
local function applyHeadless(on)
    S.headless = on
    local c = char(lp)
    local head = c and c:FindFirstChild("Head")
    if not head then return end
    head.Transparency = on and 1 or 0
    local face = head:FindFirstChildOfClass("Decal")
    if face then face.Transparency = on and 1 or 0 end
end

local function applyKorblox(on)
    S.korblox = on
    local c = char(lp)
    if not c then return end
    local ul, ll, ft = c:FindFirstChild("RightUpperLeg"), c:FindFirstChild("RightLowerLeg"), c:FindFirstChild("RightFoot")
    if not (ul and ll and ft) then notify("Korblox needs an R15 character."); return end
    if on then
        korbloxBackup = {}
        for _, part in ipairs({ ul, ll, ft }) do
            korbloxBackup[part.Name] = { mesh = part.MeshId, tex = part.TextureID, tr = part.Transparency }
        end
        local ok = pcall(function()
            ul.MeshId = "rbxassetid://902942096"
            ul.TextureID = "rbxassetid://902843398"
            ll.MeshId = "rbxassetid://902942093"
            ll.Transparency = 1
            ft.MeshId = "rbxassetid://902942089"
            ft.Transparency = 1
        end)
        if not ok then notify("Executor can't edit MeshId.") end
    else
        for _, part in ipairs({ ul, ll, ft }) do
            local b = korbloxBackup[part.Name]
            if b then
                pcall(function()
                    part.MeshId = b.mesh
                    part.TextureID = b.tex
                    part.Transparency = b.tr
                end)
            end
        end
        korbloxBackup = {}
    end
end

-- after every respawn (new round) put the look back
bind(lp.CharacterAdded, function(c)
    task.spawn(function()
        pcall(function() lp.CharacterAppearanceLoaded:Wait() end)
        task.wait(1)
        if not running then return end
        reapplyLook()
        task.wait(0.5)
        if S.headless then applyHeadless(true) end
        if S.korblox then applyKorblox(true) end
    end)
end)

---------------------------------------------------------------------
-- HITSOUND (plays when the murderer dies and you hold the gun)
---------------------------------------------------------------------
do -- @block
local watched = {}
local function playHit()
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. S.hitsoundId
    s.Volume = 2
    s.Parent = Workspace
    s:Play()
    Debris:AddItem(s, 4)
end

task.spawn(function()
    while running and task.wait(0.5) do
        if S.hitsound then
            local m = findByRole("Murderer")
            local h = m and humOf(m)
            if h and not watched[h] then
                watched[h] = true
                h.Died:Connect(function()
                    if S.hitsound and getGun(lp) then playHit() end
                end)
            end
        end
    end
end)

end -- @endblock

---------------------------------------------------------------------
-- ROLE NOTIFIER
---------------------------------------------------------------------
do -- @block
local lastRoleKey = ""
task.spawn(function()
    while running and task.wait(1) do
        if S.roleNotify then
            pcall(function()
                local m, s = findByRole("Murderer"), findByRole("Sheriff")
                local me = getRole(lp)
                local key = (m and m.Name or "") .. "|" .. (s and s.Name or "") .. "|" .. me
                if key ~= lastRoleKey and (m or s or me ~= "Innocent") then
                    lastRoleKey = key
                    local parts = {}
                    if me ~= "Innocent" then table.insert(parts, "You: " .. me) end
                    if m then table.insert(parts, "Murderer: " .. m.DisplayName) end
                    if s then table.insert(parts, "Sheriff: " .. s.DisplayName) end
                    notify(table.concat(parts, "  |  "))
                end
            end)
        end
    end
end)

end -- @endblock

---------------------------------------------------------------------
-- SKINCHANGER (client side): skins from the game files / custom mesh + recolor
---------------------------------------------------------------------
local WeaponLook, scanned, refreshLooks, scanSkins, skinNames
do -- @block
WeaponLook = {
    Gun = { src = nil, custom = nil, color = nil, mat = nil, flat = true },
    Knife = { src = nil, custom = nil, color = nil, mat = nil, flat = true },
}
scanned = { Gun = {}, Knife = {} }

local function assetUrl(id)
    id = tostring(id or "")
    if id == "" then return "" end
    if id:find("rbxassetid://", 1, true) or id:find("http", 1, true) then return id end
    return "rbxassetid://" .. id
end

local function clearLook(tool)
    for _, v in ipairs(tool:GetDescendants()) do
        if v:GetAttribute("ArtiSkin") then v:Destroy() end
    end
    for _, v in ipairs(tool:GetDescendants()) do
        if v:IsA("BasePart") then
            local tr = v:GetAttribute("ArtiTr")
            if tr ~= nil then v.Transparency = tr; v:SetAttribute("ArtiTr", nil) end
            local col = v:GetAttribute("ArtiColor")
            if col ~= nil then v.Color = col; v:SetAttribute("ArtiColor", nil) end
            local mat = v:GetAttribute("ArtiMat")
            if mat ~= nil then pcall(function() v.Material = Enum.Material[mat] end); v:SetAttribute("ArtiMat", nil) end
            local tex = v:GetAttribute("ArtiTex")
            if tex ~= nil then pcall(function() v.TextureID = tex end); v:SetAttribute("ArtiTex", nil) end
        elseif v:IsA("SpecialMesh") then
            local tex = v:GetAttribute("ArtiTex")
            if tex ~= nil then v.TextureId = tex; v:SetAttribute("ArtiTex", nil) end
        end
    end
end

local function applyLook(tool, kind)
    local cfg = WeaponLook[kind]
    if not cfg then return end
    clearLook(tool)
    local handle = tool:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return end

    local hasModel = cfg.src ~= nil or cfg.custom ~= nil
    if hasModel then
        for _, v in ipairs(tool:GetDescendants()) do
            if v:IsA("BasePart") then
                v:SetAttribute("ArtiTr", v.Transparency)
                v.Transparency = 1
            end
        end
    end

    if cfg.src and cfg.src.Parent then
        local src = cfg.src
        local sHandle = src:FindFirstChild("Handle")
        if sHandle and sHandle:IsA("BasePart") then
            local myGrip = tool:IsA("Tool") and tool.Grip or CFrame.new()
            local sGrip = src:IsA("Tool") and src.Grip or CFrame.new()
            local base = myGrip * sGrip:Inverse()
            for _, part in ipairs(src:GetDescendants()) do
                if part:IsA("BasePart") then
                    local ok, c = pcall(function() return part:Clone() end)
                    if ok and c then
                        for _, d in ipairs(c:GetDescendants()) do
                            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
                                or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Sound") then
                                d:Destroy()
                            end
                        end
                        c.Anchored = false
                        c.CanCollide = false
                        c.CanQuery = false
                        c.CanTouch = false
                        c.Massless = true
                        c.Transparency = part.Transparency
                        c.Name = "ArtiSkin_" .. part.Name
                        c:SetAttribute("ArtiSkin", true)
                        local w = Instance.new("Weld")
                        w.Part0 = handle
                        w.Part1 = c
                        w.C0 = base * sHandle.CFrame:ToObjectSpace(part.CFrame)
                        w.C1 = CFrame.new()
                        w.Parent = c
                        c.Parent = tool
                    end
                end
            end
        end
    elseif cfg.custom then
        local cu = cfg.custom
        local p = Instance.new("Part")
        p.Name = "ArtiSkin_Custom"
        p.Size = Vector3.new(1, 1, 1)
        p.Transparency = 0
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        local m = Instance.new("SpecialMesh", p)
        m.MeshType = Enum.MeshType.FileMesh
        m.MeshId = assetUrl(cu.mesh)
        m.TextureId = assetUrl(cu.tex)
        m.Scale = Vector3.new(cu.scale, cu.scale, cu.scale)
        p:SetAttribute("ArtiSkin", true)
        local w = Instance.new("Weld")
        w.Part0 = handle
        w.Part1 = p
        w.C0 = CFrame.Angles(0, math.rad(cu.rot or 0), 0)
        w.C1 = CFrame.new()
        w.Parent = p
        p.Parent = tool
    end

    if cfg.color or cfg.mat then
        for _, v in ipairs(tool:GetDescendants()) do
            if v:IsA("BasePart") and v.Transparency < 1 then
                if v:GetAttribute("ArtiColor") == nil then v:SetAttribute("ArtiColor", v.Color) end
                if v:GetAttribute("ArtiMat") == nil then v:SetAttribute("ArtiMat", v.Material.Name) end
                if cfg.color then v.Color = cfg.color end
                if cfg.mat then pcall(function() v.Material = Enum.Material[cfg.mat] end) end
                if cfg.flat and cfg.color then
                    if v:IsA("MeshPart") and v:GetAttribute("ArtiTex") == nil then
                        v:SetAttribute("ArtiTex", v.TextureID)
                        pcall(function() v.TextureID = "" end)
                    end
                    for _, mm in ipairs(v:GetChildren()) do
                        if mm:IsA("SpecialMesh") and mm:GetAttribute("ArtiTex") == nil then
                            mm:SetAttribute("ArtiTex", mm.TextureId)
                            mm.TextureId = ""
                        end
                    end
                end
            end
        end
    end
end

local function kindOf(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    if tool.Name == "Knife" then return "Knife" end
    if isGunTool(tool) then return "Gun" end
    return nil
end

local function lookActive(kind)
    local c = WeaponLook[kind]
    return c.src or c.custom or c.color or c.mat
end

function refreshLooks()
    local list = {}
    local c, bp = char(lp), lp:FindFirstChildOfClass("Backpack")
    if c then for _, t in ipairs(c:GetChildren()) do table.insert(list, t) end end
    if bp then for _, t in ipairs(bp:GetChildren()) do table.insert(list, t) end end
    for _, t in ipairs(list) do
        local k = kindOf(t)
        if k then pcall(applyLook, t, k) end
    end
end

local function onToolAdded(tool)
    local k = kindOf(tool)
    if not k then return end
    task.wait(0.15)
    if lookActive(k) then pcall(applyLook, tool, k) end
end

local function watchLooks(cont)
    for _, t in ipairs(cont:GetChildren()) do task.spawn(onToolAdded, t) end
    bind(cont.ChildAdded, function(t) task.spawn(onToolAdded, t) end)
end

task.spawn(function()
    local bp = lp:WaitForChild("Backpack", 10)
    if bp then watchLooks(bp) end
    if lp.Character then watchLooks(lp.Character) end
    bind(lp.CharacterAdded, function(c)
        watchLooks(c)
        local b = lp:FindFirstChildOfClass("Backpack")
        if b then watchLooks(b) end
    end)
end)

function scanSkins()
    scanned = { Gun = {}, Knife = {} }
    local count = 0
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if (d:IsA("Tool") or d:IsA("Model")) then
            local h = d:FindFirstChild("Handle")
            if h and h:IsA("BasePart") then
                local path = d:GetFullName():lower()
                local kind
                if d:FindFirstChild("Stab") or path:find("knife", 1, true) or path:find("blade", 1, true) then
                    kind = "Knife"
                elseif d:FindFirstChild("Shoot") or path:find("gun", 1, true) or path:find("revolver", 1, true) or path:find("pistol", 1, true) then
                    kind = "Gun"
                end
                if kind then
                    local name, n = d.Name, 1
                    while scanned[kind][name] do n += 1; name = d.Name .. " #" .. n end
                    scanned[kind][name] = d
                    count += 1
                    if count >= 400 then break end
                end
            end
        end
    end
    return count
end

function skinNames(kind)
    local names = {}
    for n in pairs(scanned[kind]) do table.insert(names, n) end
    table.sort(names)
    table.insert(names, 1, "None")
    return names
end

end -- @endblock

---------------------------------------------------------------------
-- AURAS (a few neon parts that follow you, one update loop, no particles) + GLOW
---------------------------------------------------------------------
local setAura, setGlow, setGlowColor
do -- @block
local auraName = "None"
local auraFolder, auraConn, auraLight
local auraList = {}
local glowHl, glowLight, glowConn
S.glowColor = S.glowColor or Color3.fromRGB(120, 170, 255)

local function mk(shape, size, color, transp, mat)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Massless = true
    p.Material = mat or Enum.Material.Neon
    p.Color = color
    p.Transparency = transp or 0
    p.Shape = shape or Enum.PartType.Block
    p.Size = size
    p.Parent = auraFolder
    return p
end

-- cylinders have their axis on X: this turns them into flat rings / vertical columns
local function ringCF(cf, y)
    return cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
end

local CYL, BALL, BLOCK = Enum.PartType.Cylinder, Enum.PartType.Ball, Enum.PartType.Block
local B = {}

B.angel = function(add)
    local gold, white = Color3.fromRGB(255, 232, 150), Color3.fromRGB(255, 255, 255)
    local halo = mk(CYL, Vector3.new(0.1, 1.9, 1.9), gold, 0.1)
    add(function(t, cf) halo.CFrame = ringCF(cf, 3.2 + math.sin(t * 2) * 0.12) end)
    local halo2 = mk(CYL, Vector3.new(0.05, 2.4, 2.4), white, 0.65)
    add(function(t, cf) halo2.CFrame = ringCF(cf, 3.2 + math.sin(t * 2) * 0.12) end)
    for _, side in ipairs({ -1, 1 }) do
        for i = 1, 6 do
            local len = 3.8 - i * 0.38
            local f = mk(BLOCK, Vector3.new(len, 0.1, 0.55), white, 0.25 + i * 0.07)
            add(function(t, cf)
                local flap = math.sin(t * 2.6) * 0.16
                local ang = side * (0.25 + (i - 1) * 0.2 + flap)
                f.CFrame = cf * CFrame.new(side * 0.55, 1.1 - (i - 1) * 0.22, 0.75)
                    * CFrame.Angles(0, -side * 0.35, ang) * CFrame.new(side * len / 2, 0, 0)
            end)
        end
    end
    return Color3.fromRGB(255, 240, 190)
end

B.wind = function(add)
    local c1, c2 = Color3.fromRGB(200, 240, 255), Color3.fromRGB(140, 200, 235)
    for i = 1, 2 do
        local ring = mk(CYL, Vector3.new(0.06, 4, 4), c1, 0.7 + i * 0.05)
        add(function(t, cf)
            local s = 3.6 + i * 0.7 + math.sin(t * 2 + i * 2) * 0.25
            ring.Size = Vector3.new(0.06, s, s)
            ring.CFrame = ringCF(cf, -2.4 + i * 1.7 + math.sin(t * 1.4 + i) * 0.2)
        end)
    end
    for k = 1, 8 do
        local s = mk(BLOCK, Vector3.new(0.1, 0.1, 1.5), (k % 2 == 0) and c1 or c2, 0.25)
        add(function(t, cf)
            local a = t * 2.4 + k * (math.pi * 2 / 8)
            local y = ((t * 0.7 + k / 8) % 1) * 5 - 2.4
            local r = 2.3 + math.sin(t + k) * 0.2
            local pos = cf * Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
            local tangent = cf:VectorToWorldSpace(Vector3.new(-math.sin(a), 0.25, math.cos(a)))
            s.CFrame = CFrame.lookAt(pos, pos + tangent)
        end)
    end
    return c1
end

B.starlight = function(add)
    local bubble = mk(BALL, Vector3.new(6.4, 6.4, 6.4), Color3.fromRGB(110, 150, 255), 0.88, Enum.Material.ForceField)
    add(function(t, cf) bubble.CFrame = cf end)
    local cols = { Color3.fromRGB(255, 255, 170), Color3.fromRGB(160, 200, 255), Color3.fromRGB(255, 255, 255) }
    for k = 1, 9 do
        local st = mk(BALL, Vector3.new(0.4, 0.4, 0.4), cols[k % 3 + 1], 0.05)
        add(function(t, cf)
            local a = t * (0.9 + (k % 3) * 0.35) + k * 0.7
            local r = 2.4 + (k % 4) * 0.35
            local y = math.sin(a * 1.7 + k) * 1.8
            local s = 0.3 + 0.2 * (0.5 + 0.5 * math.sin(t * 5 + k))
            st.Size = Vector3.new(s, s, s)
            st.CFrame = cf * CFrame.new(math.cos(a) * r, y, math.sin(a) * r)
        end)
    end
    return Color3.fromRGB(170, 200, 255)
end

B.heavenly = function(add)
    local gold, white = Color3.fromRGB(255, 215, 110), Color3.fromRGB(255, 250, 220)
    local col = mk(CYL, Vector3.new(7.5, 4.4, 4.4), gold, 0.88)
    add(function(t, cf)
        local s = 4.2 + math.sin(t * 1.6) * 0.25
        col.Size = Vector3.new(7.5, s, s)
        col.CFrame = ringCF(cf, 0.2)
    end)
    local halo = mk(CYL, Vector3.new(0.1, 2.1, 2.1), white, 0.05)
    add(function(t, cf) halo.CFrame = ringCF(cf, 3.4 + math.sin(t * 2) * 0.1) end)
    local base = mk(CYL, Vector3.new(0.05, 4, 4), gold, 0.6)
    add(function(t, cf)
        local k = (t * 0.6) % 1
        local s = 2 + k * 5
        base.Size = Vector3.new(0.05, s, s)
        base.Transparency = 0.35 + k * 0.65
        base.CFrame = ringCF(cf, -2.9)
    end)
    for k = 1, 6 do
        local m = mk(BALL, Vector3.new(0.3, 0.3, 0.3), white, 0.1)
        add(function(t, cf)
            local p = (t * 0.45 + k / 6) % 1
            local a = k * 1.05 + t * 0.8
            m.CFrame = cf * CFrame.new(math.cos(a) * 1.7, -2.8 + p * 6, math.sin(a) * 1.7)
            m.Transparency = 0.1 + p * 0.8
        end)
    end
    return gold
end

B["nebula black purple"] = function(add)
    local black, purple, violet = Color3.fromRGB(8, 0, 14), Color3.fromRGB(150, 60, 255), Color3.fromRGB(95, 30, 180)
    local shell = mk(BALL, Vector3.new(5.6, 5.6, 5.6), black, 0.62, Enum.Material.SmoothPlastic)
    add(function(t, cf)
        local s = 5.6 + math.sin(t * 1.8) * 0.25
        shell.Size = Vector3.new(s, s, s)
        shell.CFrame = cf
    end)
    local core = mk(BALL, Vector3.new(4.6, 4.6, 4.6), violet, 0.82)
    add(function(t, cf)
        local s = 4.6 + math.sin(t * 2.6 + 1) * 0.3
        core.Size = Vector3.new(s, s, s)
        core.CFrame = cf
    end)
    for k = 1, 14 do
        local u = k / 14
        local orb = mk(BALL, Vector3.new(0.5, 0.5, 0.5), black:Lerp(purple, u), 0.1 + u * 0.5)
        add(function(t, cf)
            local a = t * 1.3 + k * 0.62
            local r = 1.3 + u * 1.5
            local s = 0.55 - u * 0.25
            orb.Size = Vector3.new(s, s, s)
            orb.CFrame = cf * CFrame.new(math.cos(a) * r, -2.4 + u * 5, math.sin(a) * r)
        end)
    end
    return purple
end

local function stopAura()
    if auraConn then auraConn:Disconnect(); auraConn = nil end
    if auraFolder then auraFolder:Destroy(); auraFolder = nil end
    if auraLight then auraLight:Destroy(); auraLight = nil end
    auraList = {}
end

function setAura(name)
    stopAura()
    auraName = name or "None"
    local build = B[auraName]
    local root = hrpOf(lp)
    if not build or not root then return end
    auraFolder = Instance.new("Folder")
    auraFolder.Name = "artihub_aura"
    auraFolder.Parent = Workspace
    local lightColor = build(function(fn) table.insert(auraList, fn) end)
    auraLight = Instance.new("PointLight")
    auraLight.Range = 12
    auraLight.Brightness = 1.4
    auraLight.Color = lightColor or Color3.new(1, 1, 1)
    auraLight.Parent = root
    auraConn = RunService.RenderStepped:Connect(function()
        local r = hrpOf(lp)
        if not r then return end
        local look = r.CFrame.LookVector
        local cf = CFrame.new(r.Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
        local t = os.clock()
        for _, fn in ipairs(auraList) do fn(t, cf) end
    end)
end

local function stopGlow()
    if glowConn then glowConn:Disconnect(); glowConn = nil end
    if glowHl then glowHl:Destroy(); glowHl = nil end
    if glowLight then glowLight:Destroy(); glowLight = nil end
end

function setGlow(on)
    S.glow = on and true or false
    stopGlow()
    if not on then return end
    local c, root = char(lp), hrpOf(lp)
    if not c or not root then return end
    glowHl = Instance.new("Highlight")
    glowHl.Adornee = c
    glowHl.DepthMode = Enum.HighlightDepthMode.Occluded
    glowHl.FillColor = S.glowColor
    glowHl.OutlineColor = S.glowColor
    glowHl.FillTransparency = 0.7
    glowHl.OutlineTransparency = 0.1
    glowHl.Parent = CoreGui
    glowLight = Instance.new("PointLight")
    glowLight.Range = 11
    glowLight.Color = S.glowColor
    glowLight.Brightness = 1.6
    glowLight.Parent = root
    glowConn = RunService.RenderStepped:Connect(function()
        if not glowHl or not glowLight then return end
        local k = 0.5 + 0.5 * math.sin(os.clock() * 2.4)
        local col = S.glowColor
        if S.glowRainbow then col = Color3.fromHSV((os.clock() * 0.15) % 1, 0.65, 1) end
        glowHl.FillColor = col
        glowHl.OutlineColor = col
        glowHl.FillTransparency = 0.8 - 0.2 * k
        glowHl.OutlineTransparency = 0.05 + 0.3 * (1 - k)
        glowLight.Color = col
        glowLight.Brightness = 1.1 + 1.1 * k
    end)
end

function setGlowColor(c) S.glowColor = c end

bind(lp.CharacterAdded, function()
    task.wait(1.2)
    if auraName ~= "None" then setAura(auraName) end
    if S.glow then setGlow(true) end
end)
end -- @endblock

---------------------------------------------------------------------
-- MEMES: FPV drone (PC: mouse + WASD + Space/Shift, phone: stick + drag to look + UP/DOWN buttons)
---------------------------------------------------------------------
local stopDrone, startDrone, toggleDrone
do -- @block
local droneModel, droneConn, touchConn, hud, hudLabel
local parts, marks = {}, {}
local yaw, pitch, pos, vel, roll = 0, 0, Vector3.zero, Vector3.zero, 0
local busy = false
local holdUp, holdDown = false, false
local saved = nil
local lastMark = 0

local function targetOk(p)
    if S.droneTarget == "Any" then return true end
    local r = getRole(p)
    if S.droneTarget == "Murderer" then return r == "Murderer" end
    if S.droneTarget == "Sheriff" then return r == "Sheriff" end
    if S.droneTarget == "Innocents" then return r == "Innocent" end
    return true
end

local function addPart(size, color, off, mat, spin, shape)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Size = size
    p.Color = color
    p.Material = mat or Enum.Material.Metal
    if shape then p.Shape = shape end
    p.Parent = droneModel
    local e = { p = p, off = off }
    if spin then e.spin, e.phase, e.dir = true, spin[1], spin[2] end
    table.insert(parts, e)
    return p
end

local function buildDrone()
    droneModel = Instance.new("Folder")
    droneModel.Name = "artihub_drone"
    droneModel.Parent = Workspace
    parts = {}
    local dark, mid = Color3.fromRGB(22, 22, 28), Color3.fromRGB(48, 48, 58)
    addPart(Vector3.new(1.3, 0.32, 1.9), dark, CFrame.new())
    addPart(Vector3.new(0.9, 0.24, 1.2), mid, CFrame.new(0, 0.26, 0.1))
    addPart(Vector3.new(0.36, 0.36, 0.36), Color3.fromRGB(10, 10, 14), CFrame.new(0, 0, -1.0), Enum.Material.Glass, nil, Enum.PartType.Ball)
    addPart(Vector3.new(0.18, 0.1, 0.18), Color3.fromRGB(255, 60, 60), CFrame.new(0.3, 0.42, 0.5), Enum.Material.Neon)
    local arms = { Vector3.new(1.2, 0, -0.95), Vector3.new(-1.2, 0, -0.95), Vector3.new(1.2, 0, 0.95), Vector3.new(-1.2, 0, 0.95) }
    for i, a in ipairs(arms) do
        addPart(Vector3.new(0.12, 0.1, a.Magnitude), mid, CFrame.lookAt(a / 2, a))
        addPart(Vector3.new(0.3, 0.22, 0.3), dark, CFrame.new(a))
        local dir = (i % 2 == 0) and -1 or 1
        addPart(Vector3.new(1.5, 0.03, 0.1), S.accent, CFrame.new(a + Vector3.new(0, 0.2, 0)), Enum.Material.Neon, { 0, dir })
        addPart(Vector3.new(1.5, 0.03, 0.1), S.accent, CFrame.new(a + Vector3.new(0, 0.2, 0)), Enum.Material.Neon, { math.pi / 2, dir })
    end
end

local function mkBtn(text, pos2, size)
    local b = Instance.new("TextButton", hud)
    b.Size = size
    b.Position = pos2
    b.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    b.BackgroundTransparency = 0.2
    b.AutoButtonColor = true
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = text
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
    local st = Instance.new("UIStroke", b)
    st.Color = S.accent
    st.Thickness = 1.5
    return b
end

local function buildHud()
    hud = Instance.new("ScreenGui")
    hud.Name = "artihub_drone_hud"
    hud.ResetOnSpawn = false
    hud.IgnoreGuiInset = true
    hud.DisplayOrder = 7
    pcall(function() hud.Parent = CoreGui end)
    if not hud.Parent then hud.Parent = lp:WaitForChild("PlayerGui") end

    hudLabel = Instance.new("TextLabel", hud)
    hudLabel.AnchorPoint = Vector2.new(0.5, 0)
    hudLabel.Position = UDim2.new(0.5, 0, 0, 10)
    hudLabel.Size = UDim2.fromOffset(320, 28)
    hudLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    hudLabel.BackgroundTransparency = 0.3
    hudLabel.Font = Enum.Font.GothamBold
    hudLabel.TextSize = 13
    hudLabel.TextColor3 = Color3.new(1, 1, 1)
    hudLabel.Text = "DRONE"
    Instance.new("UICorner", hudLabel).CornerRadius = UDim.new(0, 10)

    local ret = Instance.new("Frame", hud)
    ret.AnchorPoint = Vector2.new(0.5, 0.5)
    ret.Position = UDim2.fromScale(0.5, 0.5)
    ret.Size = UDim2.fromOffset(46, 46)
    ret.BackgroundTransparency = 1
    Instance.new("UICorner", ret).CornerRadius = UDim.new(1, 0)
    local rs = Instance.new("UIStroke", ret)
    rs.Color = Color3.fromRGB(255, 255, 255)
    rs.Thickness = 1.4
    rs.Transparency = 0.35

    local exitB = mkBtn("EXIT", UDim2.new(1, -88, 0, 10), UDim2.fromOffset(76, 34))
    exitB.MouseButton1Click:Connect(function() stopDrone() end)

    local upB = mkBtn("UP", UDim2.new(1, -92, 1, -200), UDim2.fromOffset(80, 58))
    local dnB = mkBtn("DOWN", UDim2.new(1, -92, 1, -134), UDim2.fromOffset(80, 58))
    upB.MouseButton1Down:Connect(function() holdUp = true end)
    upB.MouseButton1Up:Connect(function() holdUp = false end)
    upB.MouseLeave:Connect(function() holdUp = false end)
    dnB.MouseButton1Down:Connect(function() holdDown = true end)
    dnB.MouseButton1Up:Connect(function() holdDown = false end)
    dnB.MouseLeave:Connect(function() holdDown = false end)
end

function stopDrone()
    S.drone = false
    if droneConn then droneConn:Disconnect(); droneConn = nil end
    if touchConn then touchConn:Disconnect(); touchConn = nil end
    pcall(function() ContextActionService:UnbindAction("artihub_drone") end)
    pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.Default end)
    if droneModel then droneModel:Destroy(); droneModel = nil end
    if hud then hud:Destroy(); hud = nil end
    for _, m in pairs(marks) do pcall(function() m:Destroy() end) end
    marks = {}
    parts = {}
    holdUp, holdDown = false, false
    local h = humOf(lp)
    if h and saved then
        h.WalkSpeed = saved.ws
        h.UseJumpPower = saved.ujp
        h.JumpPower = saved.jp
        h.AutoRotate = saved.ar
    end
    saved = nil
    pcall(function()
        cam.CameraType = Enum.CameraType.Custom
        if h then cam.CameraSubject = h end
        cam.FieldOfView = S.useCamFov and S.camFov or 70
    end)
    busy = false
end

function startDrone()
    if S.drone then return end
    local hrp, h = hrpOf(lp), humOf(lp)
    if not hrp or not h or h.Health <= 0 then notify("You need to be alive."); return end
    S.drone = true
    saved = { ws = h.WalkSpeed, jp = h.JumpPower, ujp = h.UseJumpPower, ar = h.AutoRotate }
    h.WalkSpeed = 0
    h.UseJumpPower = true
    h.JumpPower = 0
    h.AutoRotate = false

    buildDrone()
    buildHud()
    pos = hrp.Position + Vector3.new(0, 7, 0)
    local look = cam.CFrame.LookVector
    yaw = math.atan2(-look.X, -look.Z)
    pitch = 0
    vel = Vector3.zero
    roll = 0
    lastMark = 0
    cam.CameraType = Enum.CameraType.Scriptable
    pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end)
    pcall(function()
        ContextActionService:BindActionAtPriority("artihub_drone", function()
            return Enum.ContextActionResult.Sink
        end, false, 3000,
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.E, Enum.KeyCode.Q)
    end)

    touchConn = UIS.InputChanged:Connect(function(i, gp)
        if gp then return end
        if i.UserInputType == Enum.UserInputType.Touch and i.Position.X > cam.ViewportSize.X * 0.4 then
            yaw -= i.Delta.X * 0.0045
            pitch = math.clamp(pitch - i.Delta.Y * 0.0045, -1.45, 1.45)
        end
    end)

    droneConn = RunService.RenderStepped:Connect(function(dt)
        local hh = humOf(lp)
        if not S.drone or not hh or hh.Health <= 0 then stopDrone(); return end

        if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then
            local d = UIS:GetMouseDelta()
            yaw -= d.X * 0.0032
            pitch = math.clamp(pitch - d.Y * 0.0032, -1.45, 1.45)
        end
        local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

        local x, y, z = 0, 0, 0
        if UIS:IsKeyDown(Enum.KeyCode.D) then x += 1 end
        if UIS:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
        if UIS:IsKeyDown(Enum.KeyCode.W) then z += 1 end
        if UIS:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
        if UIS:IsKeyDown(Enum.KeyCode.Space) or UIS:IsKeyDown(Enum.KeyCode.E) or holdUp then y += 1 end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.Q) or holdDown then y -= 1 end
        if UIS.TouchEnabled then
            local lv = CFrame.Angles(0, yaw, 0):VectorToObjectSpace(hh.MoveDirection)
            x += lv.X
            z += -lv.Z
        end
        local dir = rot.RightVector * x + rot.LookVector * z + Vector3.new(0, y, 0)
        if dir.Magnitude > 1 then dir = dir.Unit end
        vel = vel:Lerp(dir * S.droneSpeed, math.clamp(dt * 7, 0, 1))
        pos += vel * dt
        roll += ((-x * 0.3) - roll) * math.clamp(dt * 6, 0, 1)

        local cf = CFrame.new(pos) * rot
        local t = os.clock()
        for _, e in ipairs(parts) do
            if e.spin then
                e.p.CFrame = cf * e.off * CFrame.Angles(0, t * 60 * e.dir + e.phase, 0)
            else
                e.p.CFrame = cf * e.off
            end
        end
        cam.CFrame = cf * CFrame.new(0, 0.2, -1.1) * CFrame.Angles(0, 0, roll)
        cam.FieldOfView = 100

        -- target marks + HUD text (4x per second)
        if t - lastMark > 0.25 then
            lastMark = t
            local nearest, nd
            for _, p in ipairs(Players:GetPlayers()) do
                local mark = marks[p]
                if p ~= lp and alive(p) and targetOk(p) and char(p) then
                    if not mark or mark.Parent == nil or mark.Adornee ~= char(p) then
                        if mark then mark:Destroy() end
                        mark = Instance.new("Highlight")
                        mark.FillColor = Color3.fromRGB(255, 60, 60)
                        mark.OutlineColor = Color3.fromRGB(255, 255, 255)
                        mark.FillTransparency = 0.6
                        mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        mark.Adornee = char(p)
                        mark.Parent = CoreGui
                        marks[p] = mark
                    end
                    local root = hrpOf(p)
                    if root then
                        local d = (root.Position - pos).Magnitude
                        if not nd or d < nd then nearest, nd = p, d end
                    end
                elseif mark then
                    mark:Destroy()
                    marks[p] = nil
                end
            end
            if hudLabel and not busy then
                hudLabel.Text = string.format("DRONE  %s  |  %s  |  %s", S.droneMode, S.droneTarget,
                    nearest and (nearest.DisplayName .. "  " .. math.floor(nd) .. " studs") or "no target")
            end
        end

        -- hit check every frame
        if not busy then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and alive(p) and targetOk(p) then
                    local root = hrpOf(p)
                    if root and (root.Position - pos).Magnitude < 6 then
                        busy = true
                        if hudLabel then hudLabel.Text = "LOCKED: " .. p.DisplayName end
                        task.spawn(function()
                            if S.droneMode == "Kill" then killTargets({ p }) else fling(p) end
                            task.wait(0.35)
                            busy = false
                        end)
                        break
                    end
                end
            end
        end
    end)
end

function toggleDrone()
    if S.drone then stopDrone() else startDrone() end
end
bind(lp.CharacterAdded, function() if S.drone then stopDrone() end end)
end -- @endblock

---------------------------------------------------------------------
-- MEMES: AK47 (tap / click to shoot a player: he gets flung off the map)
---------------------------------------------------------------------
local giveAK, destroyAK
do -- @block
local akTool, akBusy, akQueue
S.akAssist = S.akAssist or 160
function destroyAK() if akTool then pcall(function() akTool:Destroy() end) end end

local function akTargetNow()
    local o = aimOrigin()
    if UIS.MouseEnabled then
        local t = mouse.Target
        if t then
            local m = t:FindFirstAncestorOfClass("Model")
            local p = m and Players:GetPlayerFromCharacter(m)
            if p and p ~= lp and alive(p) then return p end
        end
    end
    local best, bd
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and alive(p) then
            local root = hrpOf(p)
            if root then
                local sp, on = cam:WorldToViewportPoint(root.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - o).Magnitude
                    if d < S.akAssist and (not bd or d < bd) then best, bd = p, d end
                end
            end
        end
    end
    return best
end

local function effects(handle, targetRoot)
    local from = (handle.CFrame * CFrame.new(0, 0.12, S.akFlip and -2.4 or 2.4)).Position
    local to = targetRoot and targetRoot.Position or (from + cam.CFrame.LookVector * 80)
    local dist = math.max((to - from).Magnitude, 0.1)
    local tr = Instance.new("Part")
    tr.Anchored = true
    tr.CanCollide = false
    tr.CanQuery = false
    tr.CanTouch = false
    tr.CastShadow = false
    tr.Material = Enum.Material.Neon
    tr.Color = Color3.fromRGB(255, 205, 90)
    tr.Size = Vector3.new(0.07, 0.07, dist)
    tr.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
    tr.Parent = Workspace
    Debris:AddItem(tr, 0.07)
    local fl = Instance.new("Part")
    fl.Anchored = true
    fl.CanCollide = false
    fl.CanQuery = false
    fl.CanTouch = false
    fl.Shape = Enum.PartType.Ball
    fl.Material = Enum.Material.Neon
    fl.Color = Color3.fromRGB(255, 230, 140)
    fl.Size = Vector3.new(0.6, 0.6, 0.6)
    fl.CFrame = CFrame.new(from)
    fl.Parent = Workspace
    Debris:AddItem(fl, 0.05)
end

local function run(target)
    if akBusy then akQueue = target; return end
    akBusy = true
    local t = target
    while t and running do
        akQueue = nil
        if alive(t) and hrpOf(t) then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(255, 60, 60)
            hl.FillTransparency = 0.4
            hl.Adornee = char(t)
            hl.Parent = CoreGui
            Debris:AddItem(hl, 0.5)
            fling(t)
        end
        t = akQueue
    end
    akBusy = false
end

local function part(tool, handle, size, color, offset, mat, rot)
    local p = Instance.new("Part")
    p.Size = size
    p.Color = color
    p.Material = mat or Enum.Material.Metal
    p.CanCollide = false
    p.Massless = true
    local w = Instance.new("Weld")
    w.Part0 = handle
    w.Part1 = p
    w.C0 = CFrame.new(offset) * (rot or CFrame.new())
    w.Parent = p
    p.Parent = tool
    return p
end

function giveAK()
    local bp = lp:FindFirstChildOfClass("Backpack")
    if not bp then notify("No backpack yet."); return end
    destroyAK()

    local tool = Instance.new("Tool")
    tool.Name = "AK47"
    tool.ToolTip = "Shoot a player to fling him"
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    tool.GripPos = Vector3.new(0, -0.5, -0.4)
    if S.akFlip then
        tool.GripForward = Vector3.new(0, 0, 1)
        tool.GripRight = Vector3.new(-1, 0, 0)
        tool.GripUp = Vector3.new(0, 1, 0)
    end

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.3, 0.55, 1.3)
    handle.Color = Color3.fromRGB(32, 32, 38)
    handle.Material = Enum.Material.Metal
    handle.CanCollide = false
    handle.Parent = tool

    local steel, wood = Color3.fromRGB(26, 26, 30), Color3.fromRGB(120, 78, 44)
    part(tool, handle, Vector3.new(0.13, 0.13, 1.7), steel, Vector3.new(0, 0.12, 1.5))
    part(tool, handle, Vector3.new(0.09, 0.09, 1.0), steel, Vector3.new(0, 0.3, 1.1))
    part(tool, handle, Vector3.new(0.32, 0.3, 1.0), wood, Vector3.new(0, 0.02, 1.0), Enum.Material.Wood)
    part(tool, handle, Vector3.new(0.2, 0.2, 0.28), steel, Vector3.new(0, 0.12, 2.4))
    part(tool, handle, Vector3.new(0.06, 0.2, 0.06), steel, Vector3.new(0, 0.34, 2.2))
    part(tool, handle, Vector3.new(0.28, 0.14, 1.3), steel, Vector3.new(0, 0.34, -0.05))
    part(tool, handle, Vector3.new(0.22, 0.85, 0.38), steel, Vector3.new(0, -0.62, 0.35), nil, CFrame.Angles(math.rad(-12), 0, 0))
    part(tool, handle, Vector3.new(0.22, 0.5, 0.26), wood, Vector3.new(0, -0.5, -0.4), Enum.Material.Wood, CFrame.Angles(math.rad(18), 0, 0))
    part(tool, handle, Vector3.new(0.28, 0.5, 1.1), wood, Vector3.new(0, -0.05, -1.2), Enum.Material.Wood)
    part(tool, handle, Vector3.new(0.3, 0.6, 0.08), steel, Vector3.new(0, -0.05, -1.78))

    tool.Activated:Connect(function()
        local target = akTargetNow()
        local root = target and hrpOf(target)
        effects(handle, root)
        if target then task.spawn(run, target) end
    end)

    tool.Parent = bp
    akTool = tool
    local h = humOf(lp)
    if h then pcall(function() h:EquipTool(tool) end) end
    notify("AK47 equipped. Tap / click to shoot.")
end

bind(lp.CharacterAdded, function()
    if S.akAuto then
        task.wait(1.5)
        pcall(giveAK)
    end
end)
end -- @endblock

---------------------------------------------------------------------
-- WATERMARK (rotating gradient border, shimmer, pulsing logo, live fps graph, expandable panel)
---------------------------------------------------------------------
local wm, applyThemeVisuals
do -- @block
wm = Instance.new("ScreenGui")
wm.Name = "artihub_wm"
wm.ResetOnSpawn = false
wm.IgnoreGuiInset = true
wm.DisplayOrder = 10
pcall(function() wm.Parent = CoreGui end)
if not wm.Parent then wm.Parent = lp:WaitForChild("PlayerGui") end

local wmBg, wmText, wmSub = Color3.fromRGB(12, 12, 15), Color3.fromRGB(235, 235, 245), "#8b90a5"
local BAR_W, BAR_H, PANEL_H = 330, 48, 164

local bar = Instance.new("TextButton", wm)
bar.Size = UDim2.fromOffset(BAR_W, BAR_H)
bar.Position = UDim2.new(0.5, -BAR_W / 2, 0, -70)
bar.BackgroundColor3 = wmBg
bar.BackgroundTransparency = 0.1
bar.AutoButtonColor = false
bar.ClipsDescendants = true
bar.Text = ""
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 14)
local barStroke = Instance.new("UIStroke", bar)
barStroke.Thickness = 1.8
barStroke.Color = Color3.new(1, 1, 1)
local strokeGrad = Instance.new("UIGradient", barStroke)

local shimmer = Instance.new("Frame", bar)
shimmer.Size = UDim2.fromScale(1, 1)
shimmer.BackgroundColor3 = Color3.new(1, 1, 1)
shimmer.BorderSizePixel = 0
shimmer.ZIndex = 1
local shGrad = Instance.new("UIGradient", shimmer)
shGrad.Rotation = 20
shGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1),
    NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(0.6, 1),
    NumberSequenceKeypoint.new(1, 1),
})
shGrad.Offset = Vector2.new(-1, 0)

local logo = Instance.new("Frame", bar)
logo.Size = UDim2.fromOffset(34, 34)
logo.Position = UDim2.fromOffset(8, 7)
logo.BackgroundColor3 = Color3.new(1, 1, 1)
logo.BorderSizePixel = 0
logo.ZIndex = 3
Instance.new("UICorner", logo).CornerRadius = UDim.new(0, 10)
local logoGrad = Instance.new("UIGradient", logo)
local logoStroke = Instance.new("UIStroke", logo)
logoStroke.Thickness = 1.5
logoStroke.Color = Color3.new(1, 1, 1)
logoStroke.Transparency = 0.4
local logoText = Instance.new("TextLabel", logo)
logoText.Size = UDim2.fromScale(1, 1)
logoText.BackgroundTransparency = 1
logoText.Font = Enum.Font.GothamBlack
logoText.TextSize = 20
logoText.TextColor3 = Color3.new(1, 1, 1)
logoText.Text = "A"
logoText.ZIndex = 4

local barText = Instance.new("TextLabel", bar)
barText.Size = UDim2.new(1, -170, 1, -4)
barText.Position = UDim2.fromOffset(50, 2)
barText.BackgroundTransparency = 1
barText.RichText = true
barText.Font = Enum.Font.Gotham
barText.TextSize = 12
barText.TextColor3 = wmText
barText.TextXAlignment = Enum.TextXAlignment.Left
barText.TextYAlignment = Enum.TextYAlignment.Center
barText.ZIndex = 3
barText.Text = "artihub"

local dot = Instance.new("Frame", bar)
dot.Size = UDim2.fromOffset(8, 8)
dot.Position = UDim2.new(1, -104, 0.5, -4)
dot.BackgroundColor3 = Color3.fromRGB(88, 224, 122)
dot.BorderSizePixel = 0
dot.ZIndex = 3
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local spark = Instance.new("Frame", bar)
spark.Size = UDim2.fromOffset(66, 24)
spark.Position = UDim2.new(1, -82, 0.5, -12)
spark.BackgroundTransparency = 1
spark.ZIndex = 3
local sparkBars = {}
for i = 1, 12 do
    local b = Instance.new("Frame", spark)
    b.BorderSizePixel = 0
    b.BackgroundColor3 = Color3.fromRGB(88, 224, 122)
    b.Size = UDim2.fromOffset(4, 3)
    b.Position = UDim2.fromOffset(math.floor((i - 1) * 5.5), 21)
    b.ZIndex = 3
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 2)
    sparkBars[i] = b
end
local fpsHist = {}

local function setWmGradients()
    local a = S.accent
    local dark = Color3.new(a.R * 0.4, a.G * 0.4, a.B * 0.4)
    strokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, a),
        ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, a),
    })
    logoGrad.Color = ColorSequence.new(a, dark)
    shimmer.BackgroundColor3 = Color3.new(1, 1, 1)
end
setWmGradients()

TweenService:Create(strokeGrad, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()
TweenService:Create(logoGrad, TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()
TweenService:Create(logoStroke, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 3.2, Transparency = 0.8 }):Play()
TweenService:Create(dot, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.75 }):Play()
TweenService:Create(shGrad, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 1.4), { Offset = Vector2.new(1, 0) }):Play()

local panel = Instance.new("Frame", wm)
panel.Position = UDim2.new(0.5, -BAR_W / 2, 0, 66)
panel.Size = UDim2.fromOffset(BAR_W, 0)
panel.BackgroundColor3 = wmBg
panel.BackgroundTransparency = 0.08
panel.ClipsDescendants = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Thickness = 1.4
pStroke.Color = S.accent

local info = Instance.new("TextLabel", panel)
info.Size = UDim2.new(1, -28, 0, 96)
info.Position = UDim2.fromOffset(14, 8)
info.BackgroundTransparency = 1
info.RichText = true
info.Font = Enum.Font.Gotham
info.TextSize = 13
info.LineHeight = 1.12
info.TextColor3 = wmText
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.Text = ""

local function makeMeter(y, name)
    local lab = Instance.new("TextLabel", panel)
    lab.Size = UDim2.fromOffset(46, 14)
    lab.Position = UDim2.fromOffset(14, y)
    lab.BackgroundTransparency = 1
    lab.Font = Enum.Font.GothamBold
    lab.TextSize = 11
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.TextColor3 = wmText
    lab.Text = name
    local track = Instance.new("Frame", panel)
    track.Size = UDim2.new(1, -86, 0, 8)
    track.Position = UDim2.fromOffset(64, y + 3)
    track.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
    track.BackgroundTransparency = 0.3
    track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local fill = Instance.new("Frame", track)
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(88, 224, 122)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    return fill, lab
end
local pingFill, pingLab = makeMeter(112, "PING")
local fpsFill, fpsLab = makeMeter(134, "FPS")

local panelOpen = false
local function placePanel()
    local p = bar.Position
    panel.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + BAR_H + 6)
end
local function togglePanel()
    panelOpen = not panelOpen
    placePanel()
    TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, panelOpen and Enum.EasingDirection.Out or Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(BAR_W, panelOpen and PANEL_H or 0)
    }):Play()
end
makeDraggable(bar, bar, togglePanel, placePanel)

-- intro slide-in
TweenService:Create(bar, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Position = UDim2.new(0.5, -BAR_W / 2, 0, 8)
}):Play()
task.delay(0.9, placePanel)

local function pingColor(p) return p < 80 and "#58e07a" or (p < 150 and "#f2c94c" or "#ef5350") end
local function fpsColor(f) return f >= 50 and "#58e07a" or (f >= 30 and "#f2c94c" or "#ef5350") end
local function col3(p) return p < 80 and Color3.fromRGB(88, 224, 122) or (p < 150 and Color3.fromRGB(242, 201, 76) or Color3.fromRGB(239, 83, 80)) end
local function fcol3(f) return f >= 50 and Color3.fromRGB(88, 224, 122) or (f >= 30 and Color3.fromRGB(242, 201, 76) or Color3.fromRGB(239, 83, 80)) end

local frames, lastT, sessionStart = 0, tick(), tick()
bind(RunService.RenderStepped, function() frames += 1 end)
task.spawn(function()
    while running and task.wait(0.5) do
        local now = tick()
        local fps = math.floor(frames / (now - lastT) + 0.5)
        frames, lastT = 0, now
        local ping = 0
        pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
        local acc = hex(S.accent)

        barText.Text = string.format(
            '<font color="%s"><b>artihub</b></font> <font color="%s">by Artur</font>\n<font color="%s">%d ms</font> <font color="%s">|</font> <font color="%s">%d fps</font> <font color="%s">|</font> <font color="%s">%s</font>',
            acc, wmSub, pingColor(ping), ping, wmSub, fpsColor(fps), fps, wmSub, wmSub, os.date("%H:%M"))

        table.insert(fpsHist, fps)
        while #fpsHist > 12 do table.remove(fpsHist, 1) end
        for i = 1, 12 do
            local v = fpsHist[i - (12 - #fpsHist)]
            local b = sparkBars[i]
            if v then
                local h = math.clamp(math.floor(v / 60 * 22), 3, 22)
                b.BackgroundColor3 = fcol3(v)
                TweenService:Create(b, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Size = UDim2.fromOffset(4, h), Position = UDim2.fromOffset(math.floor((i - 1) * 5.5), 24 - h),
                }):Play()
            end
        end

        if panelOpen then
            local secs = math.floor(now - sessionStart)
            local m, s = findByRole("Murderer"), findByRole("Sheriff")
            info.Text = string.format(
                '<font color="%s"><b>Role</b></font>   %s\n<font color="%s"><b>Murderer</b></font>   %s\n<font color="%s"><b>Sheriff</b></font>   %s\n<font color="%s"><b>Players</b></font>   %d\n<font color="%s"><b>Session</b></font>   %02d:%02d',
                acc, getRole(lp),
                acc, m and m.DisplayName or "-",
                acc, s and s.DisplayName or "-",
                acc, #Players:GetPlayers(),
                acc, math.floor(secs / 60), secs % 60)
            pingFill.BackgroundColor3 = col3(ping)
            fpsFill.BackgroundColor3 = fcol3(fps)
            TweenService:Create(pingFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(ping / 250, 0.03, 1), 1) }):Play()
            TweenService:Create(fpsFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(fps / 60, 0.03, 1), 1) }):Play()
        end
    end
end)

function applyThemeVisuals(name)
    local t = THEMES[name]
    if not t then return end
    S.accent = t.accent
    local light = (name == "White")
    wmBg = light and Color3.fromRGB(246, 246, 250) or Color3.fromRGB(12, 12, 15)
    wmText = light and Color3.fromRGB(25, 25, 32) or Color3.fromRGB(235, 235, 245)
    wmSub = light and "#6b7080" or "#8b90a5"
    bar.BackgroundColor3, panel.BackgroundColor3 = wmBg, wmBg
    barText.TextColor3, info.TextColor3 = wmText, wmText
    pingLab.TextColor3, fpsLab.TextColor3 = wmText, wmText
    pStroke.Color = t.accent
    setWmGradients()
    pcall(function() WindUI:SetTheme("Arti" .. name) end)
    for _, fn in ipairs(themeHooks) do pcall(fn, t.accent, light) end
end
end -- @endblock

---------------------------------------------------------------------
-- BUNDLE & EMOTE BROWSER (icons from the Roblox catalog, click to apply)
---------------------------------------------------------------------
local buildBrowser, destroyBrowser
do -- @block
local browserGui, browserGrid, browserStatus, browserSearchBox, browserMore
function destroyBrowser() if browserGui then pcall(function() browserGui:Destroy() end) end end
local browserMode = "Bundles"
local browserPages = nil
local browserCount = 0

local function clearGrid()
    browserCount = 0
    if browserGrid then
        for _, v in ipairs(browserGrid:GetChildren()) do
            if v:IsA("Frame") then v:Destroy() end
        end
    end
end

local function addCell(item)
    if not browserGrid then return end
    browserCount += 1
    local cell = Instance.new("Frame")
    cell.Size = UDim2.fromOffset(98, 124)
    cell.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
    cell.BorderSizePixel = 0
    cell.LayoutOrder = browserCount
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 8)

    local isBundle = (browserMode == "Bundles")
    local img = Instance.new("ImageButton", cell)
    img.Size = UDim2.fromOffset(86, 86)
    img.Position = UDim2.fromOffset(6, 6)
    img.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    img.AutoButtonColor = true
    img.Image = string.format("rbxthumb://type=%s&id=%d&w=150&h=150", isBundle and "BundleThumbnail" or "Asset", item.Id)
    Instance.new("UICorner", img).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel", cell)
    label.Size = UDim2.new(1, -8, 0, 28)
    label.Position = UDim2.fromOffset(4, 94)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextColor3 = Color3.fromRGB(225, 225, 235)
    label.TextWrapped = true
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Text = tostring(item.Name or item.Id)

    img.MouseButton1Click:Connect(function()
        if browserStatus then browserStatus.Text = "Applying " .. tostring(item.Name) .. "..." end
        task.spawn(function()
            if isBundle then applyBundle(item.Id) else applyEmote(item.Name, item.Id) end
            if browserStatus then browserStatus.Text = "Applied: " .. tostring(item.Name) end
        end)
    end)
    cell.Parent = browserGrid
end

local function browserSearch(append)
    if not append then
        clearGrid()
        browserPages = nil
    end
    if browserStatus then browserStatus.Text = "Loading..." end

    local keyword = browserSearchBox and browserSearchBox.Text or ""
    if keyword:gsub("%s", "") == "" then keyword = (browserMode == "Bundles") and "animation" or "emote" end

    task.spawn(function()
        local ok, items = pcall(function()
            if append and browserPages then
                if browserPages.IsFinished then return {} end
                browserPages:AdvanceToNextPageAsync()
                return browserPages:GetCurrentPage()
            end
            local params = CatalogSearchParams.new()
            params.SearchKeyword = keyword
            params.SortType = Enum.CatalogSortType.Relevance
            params.Limit = 30
            if browserMode == "Bundles" then
                params.BundleTypes = { Enum.BundleType.BodyParts, Enum.BundleType.Animations }
            else
                params.AssetTypes = { Enum.AvatarAssetType.EmoteAnimation }
            end
            browserPages = AvatarEditorService:SearchCatalog(params)
            return browserPages:GetCurrentPage()
        end)
        if not ok or type(items) ~= "table" then
            if browserStatus then browserStatus.Text = "Catalog search failed (not allowed here?)." end
            return
        end
        for _, it in ipairs(items) do
            if it.Id then addCell(it) end
        end
        if browserStatus then
            browserStatus.Text = string.format("%s: %d shown for \"%s\"", browserMode, browserCount, keyword)
        end
    end)
end

function buildBrowser()
    if browserGui then browserGui.Enabled = not browserGui.Enabled; return end
    browserGui = Instance.new("ScreenGui")
    browserGui.Name = "artihub_browser"
    browserGui.ResetOnSpawn = false
    pcall(function() browserGui.Parent = CoreGui end)
    if not browserGui.Parent then browserGui.Parent = lp:WaitForChild("PlayerGui") end

    local f = Instance.new("Frame", browserGui)
    f.Size = UDim2.fromOffset(360, 470)
    f.Position = UDim2.new(0.5, -180, 0.5, -235)
    f.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    f.BackgroundTransparency = 0.03
    f.Active = true
    f.Draggable = true
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
    local st = Instance.new("UIStroke", f)
    st.Color = S.accent
    st.Thickness = 1.4

    local title = Instance.new("TextLabel", f)
    title.Size = UDim2.new(1, -50, 0, 30)
    title.Position = UDim2.fromOffset(14, 4)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextColor3 = Color3.fromRGB(235, 235, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Bundles & Emotes"

    local close = Instance.new("TextButton", f)
    close.Size = UDim2.fromOffset(28, 24)
    close.Position = UDim2.new(1, -36, 0, 7)
    close.BackgroundTransparency = 1
    close.Font = Enum.Font.GothamBold
    close.TextSize = 14
    close.TextColor3 = Color3.fromRGB(200, 200, 210)
    close.Text = "X"
    close.MouseButton1Click:Connect(function() browserGui.Enabled = false end)

    local function modeBtn(text, x, mode)
        local b = Instance.new("TextButton", f)
        b.Size = UDim2.fromOffset(80, 26)
        b.Position = UDim2.fromOffset(x, 38)
        b.BackgroundColor3 = S.accent
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Text = text
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b.MouseButton1Click:Connect(function()
            browserMode = mode
            browserSearch(false)
        end)
        return b
    end
    modeBtn("Bundles", 14, "Bundles")
    modeBtn("Emotes", 100, "Emotes")

    browserSearchBox = Instance.new("TextBox", f)
    browserSearchBox.Size = UDim2.new(1, -196, 0, 26)
    browserSearchBox.Position = UDim2.fromOffset(190, 38)
    browserSearchBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    browserSearchBox.Font = Enum.Font.Gotham
    browserSearchBox.TextSize = 12
    browserSearchBox.TextColor3 = Color3.fromRGB(235, 235, 245)
    browserSearchBox.PlaceholderText = "search... (press Enter)"
    browserSearchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 145)
    browserSearchBox.Text = ""
    browserSearchBox.ClearTextOnFocus = false
    Instance.new("UICorner", browserSearchBox).CornerRadius = UDim.new(0, 8)
    browserSearchBox.FocusLost:Connect(function(enter) if enter then browserSearch(false) end end)

    browserGrid = Instance.new("ScrollingFrame", f)
    browserGrid.Size = UDim2.new(1, -20, 1, -126)
    browserGrid.Position = UDim2.fromOffset(10, 72)
    browserGrid.BackgroundTransparency = 1
    browserGrid.BorderSizePixel = 0
    browserGrid.ScrollBarThickness = 3
    browserGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
    browserGrid.CanvasSize = UDim2.new()
    local grid = Instance.new("UIGridLayout", browserGrid)
    grid.CellSize = UDim2.fromOffset(98, 124)
    grid.CellPadding = UDim2.fromOffset(6, 6)
    grid.SortOrder = Enum.SortOrder.LayoutOrder

    browserStatus = Instance.new("TextLabel", f)
    browserStatus.Size = UDim2.new(1, -120, 0, 24)
    browserStatus.Position = UDim2.new(0, 14, 1, -30)
    browserStatus.BackgroundTransparency = 1
    browserStatus.Font = Enum.Font.Gotham
    browserStatus.TextSize = 11
    browserStatus.TextColor3 = Color3.fromRGB(150, 150, 165)
    browserStatus.TextXAlignment = Enum.TextXAlignment.Left
    browserStatus.Text = ""

    browserMore = Instance.new("TextButton", f)
    browserMore.Size = UDim2.fromOffset(90, 24)
    browserMore.Position = UDim2.new(1, -104, 1, -32)
    browserMore.BackgroundColor3 = Color3.fromRGB(34, 34, 46)
    browserMore.Font = Enum.Font.GothamBold
    browserMore.TextSize = 11
    browserMore.TextColor3 = Color3.fromRGB(235, 235, 245)
    browserMore.Text = "Load more"
    Instance.new("UICorner", browserMore).CornerRadius = UDim.new(0, 8)
    browserMore.MouseButton1Click:Connect(function() browserSearch(true) end)

    browserSearch(false)
end

end -- @endblock

---------------------------------------------------------------------
-- MOBILE QUICK BUTTONS + FLOATING ICON (opens / closes the menu)
---------------------------------------------------------------------
local rebuildQuick, destroyQuick, toggleWindow, destroyFab, setFabVisible
do -- @block
S.quick = { shoot = true, flingM = true, flingS = true, killall = true }
S.quickOn = UIS.TouchEnabled

local function flingRole(role)
    local p = findByRole(role)
    if not p then notify(role .. " not found."); return end
    fling(p)
end

local QUICK = {
    { key = "shoot", label = "Shoot murder", fn = function() task.spawn(shootMurderer) end },
    { key = "flingM", label = "Fling murder", fn = function() task.spawn(flingRole, "Murderer") end },
    { key = "flingS", label = "Fling sheriff", fn = function() task.spawn(flingRole, "Sheriff") end },
    { key = "killall", label = "Kill all", fn = function() task.spawn(killAll) end },
    { key = "grab", label = "Grab gun", fn = function() task.spawn(grabGun) end },
    { key = "drone", label = "Drone", fn = function() toggleDrone() end },
    { key = "ak", label = "AK47", fn = function() giveAK() end },
    { key = "invis", label = "Invisible", fn = function() task.spawn(setInvisible, not S.invisible) end },
    { key = "fly", label = "Fly", fn = function() setFly(not S.fly) end },
    { key = "noclip", label = "Noclip", fn = function()
        S.noclip = not S.noclip
        notify("Noclip " .. (S.noclip and "on" or "off"))
    end },
}

local gui, frame
local collapsed = false

function destroyQuick()
    if gui then pcall(function() gui:Destroy() end); gui = nil end
end

function rebuildQuick()
    destroyQuick()
    if not S.quickOn then return end
    gui = Instance.new("ScreenGui")
    gui.Name = "artihub_quick"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 8
    pcall(function() gui.Parent = CoreGui end)
    if not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

    frame = Instance.new("Frame", gui)
    frame.Size = UDim2.fromOffset(142, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.Position = UDim2.new(1, -158, 0.28, 0)
    frame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    frame.BackgroundTransparency = 0.18
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
    local st = Instance.new("UIStroke", frame)
    st.Color = S.accent
    st.Thickness = 1.5
    local pad = Instance.new("UIPadding", frame)
    pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
    local lay = Instance.new("UIListLayout", frame)
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder

    local header = Instance.new("TextButton", frame)
    header.Size = UDim2.new(1, 0, 0, 22)
    header.BackgroundTransparency = 1
    header.AutoButtonColor = false
    header.Font = Enum.Font.GothamBold
    header.TextSize = 12
    header.TextColor3 = Color3.fromRGB(235, 235, 245)
    header.Text = "artihub  (drag / tap)"
    header.LayoutOrder = 0

    local buttons = {}
    local order = 1
    for _, q in ipairs(QUICK) do
        if S.quick[q.key] then
            local b = Instance.new("TextButton", frame)
            b.Size = UDim2.new(1, 0, 0, 38)
            b.BackgroundColor3 = Color3.new(1, 1, 1)
            b.AutoButtonColor = false
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.TextColor3 = Color3.new(1, 1, 1)
            b.Text = q.label
            b.LayoutOrder = order
            order += 1
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
            local g = Instance.new("UIGradient", b)
            g.Rotation = 90
            g.Color = ColorSequence.new(S.accent, Color3.new(S.accent.R * 0.5, S.accent.G * 0.5, S.accent.B * 0.5))
            local sc = Instance.new("UIScale", b)
            b.MouseButton1Down:Connect(function()
                TweenService:Create(sc, TweenInfo.new(0.08), { Scale = 0.93 }):Play()
            end)
            local function release() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play() end
            b.MouseButton1Up:Connect(release)
            b.MouseLeave:Connect(release)
            b.MouseButton1Click:Connect(function() pcall(q.fn) end)
            b.Visible = not collapsed
            table.insert(buttons, b)
        end
    end

    makeDraggable(header, frame, function()
        collapsed = not collapsed
        for _, b in ipairs(buttons) do b.Visible = not collapsed end
    end)
end

-- floating icon: tap = open / close the menu, drag = move it
local fabGui, fabBtn
function destroyFab()
    if fabGui then pcall(function() fabGui:Destroy() end); fabGui = nil end
end

local guiOpen = true
function toggleWindow()
    local ok = pcall(function() Window:Toggle() end)
    if not ok then
        guiOpen = not guiOpen
        pcall(function() if guiOpen then Window:Open() else Window:Close() end end)
    end
end

local function buildFab()
    destroyFab()
    fabGui = Instance.new("ScreenGui")
    fabGui.Name = "artihub_fab"
    fabGui.ResetOnSpawn = false
    fabGui.IgnoreGuiInset = true
    fabGui.DisplayOrder = 9
    pcall(function() fabGui.Parent = CoreGui end)
    if not fabGui.Parent then fabGui.Parent = lp:WaitForChild("PlayerGui") end

    local fab = Instance.new("TextButton", fabGui)
    fab.Size = UDim2.fromOffset(54, 54)
    fab.Position = UDim2.new(0, 12, 0.5, -27)
    fab.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    fab.BackgroundTransparency = 0.05
    fab.AutoButtonColor = false
    fab.Text = ""
    Instance.new("UICorner", fab).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", fab)
    st.Thickness = 2.4
    st.Color = Color3.new(1, 1, 1)
    local sg = Instance.new("UIGradient", st)
    local function paint(a)
        sg.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, a),
        })
    end
    paint(S.accent)
    TweenService:Create(sg, TweenInfo.new(3.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()

    local letter = Instance.new("TextLabel", fab)
    letter.Size = UDim2.fromScale(1, 1)
    letter.BackgroundTransparency = 1
    letter.Font = Enum.Font.GothamBlack
    letter.TextSize = 26
    letter.TextColor3 = Color3.new(1, 1, 1)
    letter.Text = "A"
    local lg = Instance.new("UIGradient", letter)
    local function paintLetter(a) lg.Color = ColorSequence.new(Color3.new(1, 1, 1), a) end
    paintLetter(S.accent)
    lg.Rotation = 90

    local glow = Instance.new("Frame", fab)
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    glow.Position = UDim2.fromScale(0.5, 0.5)
    glow.Size = UDim2.new(1, 14, 1, 14)
    glow.BackgroundTransparency = 1
    glow.ZIndex = 0
    Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)
    local gs = Instance.new("UIStroke", glow)
    gs.Thickness = 2
    gs.Color = S.accent
    gs.Transparency = 0.3
    TweenService:Create(gs, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9, Thickness = 5 }):Play()

    makeDraggable(fab, fab, toggleWindow)
    fabBtn = { paint = paint, paintLetter = paintLetter, glow = gs }
end

function setFabVisible(on)
    if on then buildFab() else destroyFab() end
end

table.insert(themeHooks, function(a)
    if fabBtn then
        pcall(fabBtn.paint, a)
        pcall(fabBtn.paintLetter, a)
        pcall(function() fabBtn.glow.Color = a end)
    end
    if gui then rebuildQuick() end
end)

rebuildQuick()
buildFab()
end -- @endblock

---------------------------------------------------------------------
-- EXTRA SCRIPTS
---------------------------------------------------------------------
local function runUrl(url)
    if not url or url == "" then notify("Paste a script link first."); return end
    local ok, err = pcall(function() loadstring(httpGet(url))() end)
    if not ok then notify("Failed: " .. tostring(err):sub(1, 80)) end
end

local customUrl, emoteUrl = "", EMOTE_URL

---------------------------------------------------------------------
-- CONFIGS (save / load / delete / export / import / autoload)
-- saved: every toggle, input, dropdown and color picker (not binds, names or links)
---------------------------------------------------------------------
local cfgSave, cfgLoad, cfgDelete, cfgList, cfgExport, cfgImport, cfgSetAutoload, cfgRunAutoload
do -- @block
local DIR, INDEX, AUTO = "artihub/configs", "artihub/index.json", "artihub/autoload.txt"
local hasFS = (writefile ~= nil) and (readfile ~= nil) and (isfile ~= nil) and (makefolder ~= nil) and (isfolder ~= nil)
local mem = {}
local memAuto
pcall(function()
    if getgenv then
        getgenv().artihub_cfgs = getgenv().artihub_cfgs or {}
        mem = getgenv().artihub_cfgs
    end
end)
if hasFS then
    pcall(function()
        if not isfolder("artihub") then makefolder("artihub") end
        if not isfolder(DIR) then makefolder(DIR) end
    end)
end

local function clean(name)
    name = tostring(name or ""):gsub("[^%w_%- ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "default" end
    return name
end

local function excluded(key)
    local k = key:lower()
    if k:find("^configs/") then return true end
    if k:find("name", 1, true) or k:find("link", 1, true) or k:find("nick", 1, true) or k:find("avatar", 1, true) then return true end
    if k:find("invisible", 1, true) or k:find("drone (fpv)", 1, true) then return true end
    return false
end

local function enc(v)
    if typeof(v) == "Color3" then return { __c = { v.R, v.G, v.B } } end
    return v
end
local function dec(v)
    if type(v) == "table" and v.__c then return Color3.new(v.__c[1], v.__c[2], v.__c[3]) end
    return v
end

local function snapshot()
    local vals = {}
    for key, v in pairs(UIReg.vals) do
        if not excluded(key) and UIReg.kinds[key] then
            local tv = typeof(v)
            if tv == "boolean" or tv == "number" or tv == "string" or tv == "Color3" then
                vals[key] = enc(v)
            end
        end
    end
    return { version = 1, vals = vals }
end

local function readIndex()
    local list = {}
    if hasFS then
        pcall(function()
            if isfile(INDEX) then
                local d = HttpService:JSONDecode(readfile(INDEX))
                if type(d) == "table" then list = d end
            end
        end)
    end
    return list
end

local function writeIndex(list)
    if not hasFS then return end
    pcall(function() writefile(INDEX, HttpService:JSONEncode(list)) end)
end

function cfgList()
    local seen, out = {}, {}
    local function add(n)
        if n and n ~= "" and not seen[n] then seen[n] = true; table.insert(out, n) end
    end
    if hasFS and listfiles then
        pcall(function()
            for _, path in ipairs(listfiles(DIR)) do
                add(tostring(path):match("([^/\\]+)%.json$"))
            end
        end)
    end
    for _, n in ipairs(readIndex()) do
        local ok = false
        pcall(function() ok = isfile(DIR .. "/" .. n .. ".json") end)
        if ok then add(n) end
    end
    for n in pairs(mem) do add(n) end
    table.sort(out)
    return out
end

function cfgSave(name)
    name = clean(name)
    local json = HttpService:JSONEncode(snapshot())
    mem[name] = json
    if hasFS then
        local ok = pcall(function() writefile(DIR .. "/" .. name .. ".json", json) end)
        if ok then
            local idx = readIndex()
            local found = false
            for _, n in ipairs(idx) do if n == name then found = true end end
            if not found then table.insert(idx, name); writeIndex(idx) end
        end
    end
    notify("Config saved: " .. name .. (hasFS and "" or " (memory only, this executor has no file access)"))
    return name
end

local function applyData(data)
    if type(data) ~= "table" or type(data.vals) ~= "table" then return 0 end
    local n = 0
    for key, raw in pairs(data.vals) do
        if UIReg.kinds[key] and not excluded(key) then
            local val = dec(raw)
            UIReg.vals[key] = val
            local cb = UIReg.cbs[key]
            if cb then pcall(cb, val) end
            local el = UIReg.elems[key]
            if el then
                pcall(function()
                    if el.Set then el:Set(val) elseif el.Select then el:Select(val) end
                end)
            end
            n += 1
        end
    end
    return n
end

function cfgLoad(name)
    name = clean(name)
    local json = mem[name]
    if hasFS then
        pcall(function()
            local path = DIR .. "/" .. name .. ".json"
            if isfile(path) then json = readfile(path) end
        end)
    end
    if not json then notify("Config not found: " .. name); return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok then notify("Config is damaged: " .. name); return false end
    local n = applyData(data)
    notify("Config loaded: " .. name .. " (" .. n .. " settings)")
    return true
end

function cfgDelete(name)
    name = clean(name)
    mem[name] = nil
    if hasFS then
        pcall(function()
            local path = DIR .. "/" .. name .. ".json"
            if isfile(path) and delfile then delfile(path) end
        end)
        local idx = {}
        for _, n in ipairs(readIndex()) do if n ~= name then table.insert(idx, n) end end
        writeIndex(idx)
    end
    notify("Config deleted: " .. name)
end

function cfgExport()
    local json = HttpService:JSONEncode(snapshot())
    local ok = pcall(function() setclipboard(json) end)
    notify(ok and "Config copied to the clipboard." or "Clipboard is not supported by this executor.")
    return json
end

function cfgImport(text)
    local ok, data = pcall(function() return HttpService:JSONDecode(tostring(text or "")) end)
    if not ok or type(data) ~= "table" then notify("That is not a valid config."); return end
    local n = applyData(data)
    notify("Config imported (" .. n .. " settings).")
end

function cfgSetAutoload(name)
    if name == nil or name == "" then
        memAuto = nil
        if hasFS then pcall(function() if isfile(AUTO) and delfile then delfile(AUTO) end end) end
        pcall(function() if getgenv then getgenv().artihub_auto = nil end end)
        notify("Autoload cleared.")
        return
    end
    name = clean(name)
    memAuto = name
    pcall(function() if getgenv then getgenv().artihub_auto = name end end)
    if hasFS then pcall(function() writefile(AUTO, name) end) end
    notify("Autoload set: " .. name)
end

function cfgRunAutoload()
    local name = memAuto
    pcall(function() if not name and getgenv then name = getgenv().artihub_auto end end)
    if hasFS then
        pcall(function() if isfile(AUTO) then name = clean(readfile(AUTO)) end end)
    end
    if name then cfgLoad(name) end
end
end -- @endblock

---------------------------------------------------------------------
-- UNLOAD (disconnects everything and removes all GUIs)
---------------------------------------------------------------------
local function unload()
    running = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, c in pairs(aimConns) do pcall(function() c:Disconnect() end) end
    pcall(stopDrone)
    pcall(setFly, false)
    pcall(setWallbang, false)
    pcall(setFullbright, false)
    pcall(applyHeadless, false)
    pcall(applyKorblox, false)
    pcall(setAura, "None")
    if invisSeat then pcall(setInvisible, false) end
    for _, k in ipairs({ "Gun", "Knife" }) do
        WeaponLook[k].src, WeaponLook[k].custom, WeaponLook[k].color, WeaponLook[k].mat = nil, nil, nil, nil
    end
    pcall(refreshLooks)
    if destroyAK then pcall(destroyAK) end
    Workspace.Gravity = defaultGravity
    pcall(unspectate)
    for p in pairs(espObjects) do clearEsp(p) end
    if gunDropHl then gunDropHl:Destroy() end
    pcall(setGlow, false)
    if destroyOverlay then pcall(destroyOverlay) end
    if destroyQuick then pcall(destroyQuick) end
    if destroyFab then pcall(destroyFab) end
    pcall(function() wm:Destroy() end)
    if destroyBrowser then pcall(destroyBrowser) end
    pcall(function() Window:Destroy() end)
end

---------------------------------------------------------------------
-- TABS
---------------------------------------------------------------------
do -- @block
-- VISUALS
local Visuals = tab("Visuals")
Visuals:Toggle({ Title = "ESP Innocent", Value = false, Callback = function(v) S.espInnocent = v end })
Visuals:Toggle({ Title = "ESP Sheriff", Value = false, Callback = function(v) S.espSheriff = v end })
Visuals:Toggle({ Title = "ESP Murder", Value = false, Callback = function(v) S.espMurder = v end })
Visuals:Toggle({ Title = "ESP Nick (with distance)", Value = false, Callback = function(v) S.espNick = v end })
Visuals:Toggle({ Title = "ESP Dropped gun", Value = false, Callback = function(v) S.espGun = v end })
Visuals:Toggle({ Title = "Tracers", Value = false, Callback = function(v) S.tracers = v end })
Visuals:Toggle({ Title = "Crosshair", Value = false, Callback = function(v) S.crosshair = v end })
Visuals:Colorpicker({ Title = "Innocent color", Default = S.colors.Innocent, Callback = function(c) S.colors.Innocent = c end })
Visuals:Colorpicker({ Title = "Sheriff color", Default = S.colors.Sheriff, Callback = function(c) S.colors.Sheriff = c end })
Visuals:Colorpicker({ Title = "Murder color", Default = S.colors.Murderer, Callback = function(c) S.colors.Murderer = c end })
Visuals:Toggle({ Title = "Hitsound", Value = false, Callback = function(v) S.hitsound = v end })
Visuals:Dropdown({
    Title = "Hitsound type",
    Values = { "Among Us", "CoD", "Bubble" },
    Value = "Among Us",
    Callback = function(v) S.hitsoundId = HITSOUNDS[v] or S.hitsoundId end,
})
Visuals:Dropdown({
    Title = "Aura",
    Values = { "None", "angel", "wind", "starlight", "heavenly", "nebula black purple" },
    Value = "None",
    Callback = function(v) setAura(v) end,
})
Visuals:Toggle({ Title = "Glow (you)", Value = false, Callback = function(v) setGlow(v) end })
Visuals:Colorpicker({ Title = "Glow color", Default = S.glowColor, Callback = function(c) setGlowColor(c) end })
Visuals:Toggle({ Title = "Glow rainbow", Value = false, Callback = function(v) S.glowRainbow = v end })
Visuals:Toggle({ Title = "Fullbright", Value = false, Callback = setFullbright })
Visuals:Toggle({ Title = "Custom camera FOV", Value = false, Callback = function(v)
    S.useCamFov = v
    if not v then cam.FieldOfView = 70 end
end })
Visuals:Input({
    Title = "Camera FOV", Value = "70", Placeholder = "number",
    Callback = function(v) S.camFov = math.clamp(toNum(v, 70), 30, 120) end,
})
Visuals:Input({
    Title = "Max camera zoom", Value = "128", Placeholder = "number",
    Callback = function(v) lp.CameraMaxZoomDistance = math.clamp(toNum(v, 128), 5, 1000) end,
})
Visuals:Input({
    Title = "Time of day (0-24)", Value = "14", Placeholder = "number",
    Callback = function(v) Lighting.ClockTime = math.clamp(toNum(v, 14), 0, 24) end,
})

end -- @endblock

do -- @block
-- COMBAT
local Combat = tab("Combat")
Combat:Toggle({ Title = "Silent Aim", Value = false, Callback = function(v) S.silent = v end })
Combat:Toggle({ Title = "Silent Aim FOV", Value = false, Callback = function(v) S.silentFov = v end })
Combat:Input({
    Title = "FOV size", Value = "150", Placeholder = "number",
    Callback = function(v) S.fovSize = math.clamp(toNum(v, 150), 20, 800) end,
})
Combat:Input({
    Title = "Hit chance %", Value = "100", Placeholder = "0-100",
    Callback = function(v) S.hitChance = math.clamp(toNum(v, 100), 1, 100) end,
})
Combat:Input({
    Title = "Prediction strength", Value = "1", Placeholder = "0.5 - 2",
    Callback = function(v) S.predScale = math.clamp(toNum(v, 1), 0.2, 3) end,
})
Combat:Toggle({ Title = "Wallbang", Value = false, Callback = function(v) task.spawn(setWallbang, v) end })
Combat:Toggle({ Title = "Auto shoot murderer", Value = false, Callback = function(v) S.autoShoot = v end })
Combat:Input({
    Title = "Auto shoot range", Value = "250", Placeholder = "studs",
    Callback = function(v) S.autoShootRange = math.clamp(toNum(v, 250), 10, 1000) end,
})
Combat:Toggle({ Title = "Auto grab gun", Value = false, Callback = function(v) S.autoGrab = v end })
Combat:Button({ Title = "Grab dropped gun", Callback = function() task.spawn(grabGun) end })
Combat:Button({ Title = "Shoot murderer", Callback = function() task.spawn(shootMurderer) end })
Combat:Toggle({ Title = "Kill aura (murderer)", Value = false, Callback = function(v) S.killAura = v end })
Combat:Input({
    Title = "Kill aura range", Value = "12", Placeholder = "studs",
    Callback = function(v) S.auraRange = math.clamp(toNum(v, 12), 3, 60) end,
})
Combat:Toggle({ Title = "Debug messages (silent aim)", Value = false, Callback = function(v) S.debug = v end })

end -- @endblock

do -- @block
-- MOVEMENT
local Move = tab("Movement")
Move:Input({
    Title = "WalkSpeed", Value = "16", Placeholder = "number",
    Callback = function(v) S.walkspeed = math.clamp(toNum(v, 16), 1, 200) end,
})
Move:Input({
    Title = "JumpPower", Value = "50", Placeholder = "number",
    Callback = function(v) S.jump = math.clamp(toNum(v, 50), 1, 300) end,
})
Move:Input({
    Title = "Gravity", Value = tostring(math.floor(defaultGravity)), Placeholder = "number",
    Callback = function(v) Workspace.Gravity = math.clamp(toNum(v, defaultGravity), 0, 400) end,
})
Move:Toggle({ Title = "Fly", Value = false, Callback = function(v) setFly(v) end })
Move:Input({
    Title = "Fly speed", Value = "60", Placeholder = "number",
    Callback = function(v) S.flySpeed = math.clamp(toNum(v, 60), 5, 300) end,
})
Move:Toggle({ Title = "Speed glitch", Value = false, Callback = function(v) S.speedGlitch = v end })
Move:Input({
    Title = "Speed glitch power", Value = "2", Placeholder = "number",
    Callback = function(v) S.glitchPower = math.clamp(toNum(v, 2), 0.1, 10) end,
})
Move:Toggle({ Title = "Noclip", Value = false, Callback = function(v) S.noclip = v end })
Move:Toggle({ Title = "Infinite jump", Value = false, Callback = function(v) S.infJump = v end })
Move:Toggle({ Title = "Bunny hop (hold Space)", Value = false, Callback = function(v) S.bhop = v end })
Move:Toggle({ Title = "Spin", Value = false, Callback = function(v) S.spin = v end })
Move:Input({
    Title = "Spin speed", Value = "20", Placeholder = "number",
    Callback = function(v) S.spinSpeed = math.clamp(toNum(v, 20), 1, 90) end,
})
Move:Toggle({ Title = "Ctrl + click teleport", Value = false, Callback = function(v) S.clickTp = v end })
Move:Toggle({ Title = "Anti fling", Value = false, Callback = function(v) S.antiFling = v end })
Move:Toggle({ Title = "Anti void", Value = false, Callback = function(v) S.antiVoid = v end })

end -- @endblock

do -- @block
-- TELEPORT
local TP = tab("Teleport")
TP:Button({ Title = "Teleport map", Callback = tpMap })
TP:Button({ Title = "Teleport lobby", Callback = tpLobby })
TP:Button({ Title = "Teleport sheriff", Callback = function() tpPlayer(findByRole("Sheriff")) end })
TP:Button({ Title = "Teleport murder", Callback = function() tpPlayer(findByRole("Murderer")) end })
TP:Button({ Title = "Teleport random player", Callback = tpRandom })
TP:Button({ Title = "Teleport to dropped gun", Callback = tpGunDrop })
local tpName = ""
TP:Input({
    Title = "Player name", Value = "", Placeholder = "type a name",
    Callback = function(v) tpName = v end,
})
TP:Button({ Title = "Teleport to player", Callback = function() tpPlayer(findPlayer(tpName)) end })
TP:Button({ Title = "Spectate player", Callback = function() spectate(findPlayer(tpName)) end })
TP:Button({ Title = "Stop spectating", Callback = unspectate })
TP:Button({ Title = "Save position", Callback = savePos })
TP:Button({ Title = "Load position", Callback = loadPos })

end -- @endblock

do -- @block
-- MEMES
local Memes = tab("Memes")
Memes:Toggle({ Title = "Drone (FPV)", Value = false, Callback = function(v)
    if v then startDrone() else stopDrone() end
end })
Memes:Dropdown({
    Title = "Drone mode",
    Values = { "Fling", "Kill" },
    Value = "Fling",
    Callback = function(v) S.droneMode = v end,
})
Memes:Dropdown({
    Title = "Drone target",
    Values = { "Any", "Murderer", "Sheriff", "Innocents" },
    Value = "Any",
    Callback = function(v) S.droneTarget = v end,
})
Memes:Input({
    Title = "Drone speed", Value = "70", Placeholder = "number",
    Callback = function(v) S.droneSpeed = math.clamp(toNum(v, 70), 10, 300) end,
})
Memes:Button({ Title = "Give AK47 (fling gun)", Callback = giveAK })
Memes:Toggle({ Title = "AK47: flip direction (if it points backwards)", Value = false, Callback = function(v) S.akFlip = v end })
Memes:Input({
    Title = "AK47 aim assist (pixels)", Value = "160", Placeholder = "number",
    Callback = function(v) S.akAssist = math.clamp(toNum(v, 160), 30, 600) end,
})
Memes:Toggle({ Title = "Auto give AK47 after respawn", Value = false, Callback = function(v) S.akAuto = v end })
Memes:Button({ Title = "Kill nearest (murderer)", Callback = function() task.spawn(killNearest) end })
Memes:Button({ Title = "Kill sheriff (murderer)", Callback = function() task.spawn(killSheriff) end })
Memes:Button({ Title = "Kill all (murderer)", Callback = function() task.spawn(killAll) end })
local killName = ""
Memes:Input({
    Title = "Kill player name", Value = "", Placeholder = "type a name",
    Callback = function(v) killName = v end,
})
Memes:Button({ Title = "Kill player (murderer)", Callback = function()
    local p = findPlayer(killName)
    if p then task.spawn(killTargets, { p }) else notify("Player not found.") end
end })
Memes:Button({ Title = "Fling innocent", Callback = function() task.spawn(fling, randomRole("Innocent")) end })
Memes:Button({ Title = "Fling sheriff", Callback = function() task.spawn(fling, findByRole("Sheriff")) end })
Memes:Button({ Title = "Fling murder", Callback = function() task.spawn(fling, findByRole("Murderer")) end })
Memes:Button({ Title = "Fling nearest", Callback = function() task.spawn(fling, nearestPlayer()) end })
local flingName = ""
Memes:Input({
    Title = "Fling player name", Value = "", Placeholder = "type a name",
    Callback = function(v) flingName = v end,
})
Memes:Button({ Title = "Fling other", Callback = function() task.spawn(fling, findPlayer(flingName)) end })
Memes:Button({ Title = "Fling all", Callback = function() task.spawn(flingAll) end })

end -- @endblock

do -- @block
-- FUN
local Fun = tab("Fun")
Fun:Toggle({ Title = "Invisible", Value = false, Callback = function(v) task.spawn(setInvisible, v) end })
local emoteName = "dance"
Fun:Dropdown({
    Title = "Default emote",
    Values = { "dance", "dance2", "dance3", "cheer", "laugh", "point", "wave" },
    Value = "dance",
    Callback = function(v) emoteName = v end,
})
Fun:Button({ Title = "Play emote", Callback = function() playEmote(emoteName) end })
Fun:Button({ Title = "Respawn", Callback = function()
    local h = humOf(lp)
    if h then h.Health = 0 end
end })

end -- @endblock

do -- @block
-- AVATAR
local Avatar = tab("Avatar")
Avatar:Toggle({ Title = "Fake headless", Value = false, Callback = function(v) applyHeadless(v) end })
Avatar:Toggle({ Title = "Fake korblox", Value = false, Callback = function(v) applyKorblox(v) end })
local avatarName = ""
Avatar:Input({
    Title = "Avatar (nick or user id)", Value = "", Placeholder = "any Roblox username",
    Callback = function(v) avatarName = v end,
})
Avatar:Button({ Title = "Apply avatar (No FE)", Callback = function() task.spawn(applyAvatar, avatarName) end })
Avatar:Button({ Title = "Reset my avatar", Callback = function() task.spawn(resetAvatar) end })

end -- @endblock

do -- @block
-- BUNDLE & EMOTE
local BE = tab("Bundle&Emote")
BE:Button({ Title = "Open bundle & emote browser", Callback = buildBrowser })
BE:Button({ Title = "Clear applied bundles & emotes", Callback = function()
    Look.fields = {}
    Look.emotes = {}
    Look.avatarUid = lp.UserId
    task.spawn(function() reapplyLook(); Look.avatarUid = nil end)
    notify("Cleared.")
end })

end -- @endblock

do -- @block
-- SKINCHANGER
local Skin = tab("Skinchanger")
local okScan, foundCount = pcall(scanSkins)
foundCount = okScan and foundCount or 0
if foundCount > 0 then notify(foundCount .. " weapon skins found.") end

local gunDropdown = Skin:Dropdown({
    Title = "Gun skin",
    Values = skinNames("Gun"),
    Value = "None",
    Callback = function(v)
        WeaponLook.Gun.src = scanned.Gun[v]
        if v == "None" then WeaponLook.Gun.src = nil end
        if WeaponLook.Gun.src then WeaponLook.Gun.custom = nil end
        refreshLooks()
    end,
})
local knifeDropdown = Skin:Dropdown({
    Title = "Knife skin",
    Values = skinNames("Knife"),
    Value = "None",
    Callback = function(v)
        WeaponLook.Knife.src = scanned.Knife[v]
        if v == "None" then WeaponLook.Knife.src = nil end
        if WeaponLook.Knife.src then WeaponLook.Knife.custom = nil end
        refreshLooks()
    end,
})
Skin:Button({ Title = "Rescan skins in game files", Callback = function()
    local n = scanSkins()
    pcall(function() gunDropdown:Refresh(skinNames("Gun")) end)
    pcall(function() knifeDropdown:Refresh(skinNames("Knife")) end)
    notify(n > 0 and (n .. " skins found.") or "No skins found in ReplicatedStorage.")
end })

local matValues = { "Default", "SmoothPlastic", "Neon", "Metal", "ForceField", "Glass", "Foil" }
for _, kind in ipairs({ "Gun", "Knife" }) do
    local cfg = WeaponLook[kind]
    local customCfg = { mesh = "", tex = "", scale = 1, rot = 0 }
    Skin:Colorpicker({
        Title = kind .. " color", Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) cfg.color = c; refreshLooks() end,
    })
    Skin:Dropdown({
        Title = kind .. " material", Values = matValues, Value = "Default",
        Callback = function(v) cfg.mat = (v ~= "Default") and v or nil; refreshLooks() end,
    })
    Skin:Toggle({
        Title = kind .. " flat paint (remove texture)", Value = true,
        Callback = function(v) cfg.flat = v; refreshLooks() end,
    })
    Skin:Input({ Title = kind .. " custom mesh id", Value = "", Placeholder = "asset id",
        Callback = function(v) customCfg.mesh = v end })
    Skin:Input({ Title = kind .. " custom texture id", Value = "", Placeholder = "asset id (optional)",
        Callback = function(v) customCfg.tex = v end })
    Skin:Input({ Title = kind .. " custom scale", Value = "1", Placeholder = "number",
        Callback = function(v) customCfg.scale = math.clamp(toNum(v, 1), 0.05, 50) end })
    Skin:Input({ Title = kind .. " custom rotation Y", Value = "0", Placeholder = "degrees",
        Callback = function(v) customCfg.rot = toNum(v, 0) end })
    Skin:Button({ Title = "Apply custom " .. kind:lower() .. " mesh", Callback = function()
        if customCfg.mesh == "" then notify("Enter a mesh id first."); return end
        cfg.src = nil
        cfg.custom = { mesh = customCfg.mesh, tex = customCfg.tex, scale = customCfg.scale, rot = customCfg.rot }
        refreshLooks()
    end })
    Skin:Button({ Title = "Reset " .. kind:lower() .. " look", Callback = function()
        cfg.src, cfg.custom, cfg.color, cfg.mat = nil, nil, nil, nil
        refreshLooks()
        notify(kind .. " reset.")
    end })
end
Skin:Button({ Title = "Gun preset: AWP", Callback = function()
    WeaponLook.Gun.src = nil
    WeaponLook.Gun.custom = { mesh = AWP_MESH, tex = "", scale = 1, rot = 0 }
    refreshLooks()
end })

end -- @endblock

do -- @block
-- MISC
local Misc = tab("Misc")
Misc:Toggle({ Title = "Auto collect coins", Value = false, Callback = function(v)
    S.autoCoins = v
    if v then coinTries = {} end
end })
Misc:Toggle({ Title = "Role notifier", Value = false, Callback = function(v) S.roleNotify = v end })
for _, e in ipairs({ { "grab", "Grab gun" }, { "drone", "Drone" }, { "ak", "AK47" }, { "invis", "Invisible" }, { "fly", "Fly" }, { "noclip", "Noclip" } }) do
    Misc:Toggle({ Title = "Quick button: " .. e[2], Value = false, Callback = function(v)
        S.quick[e[1]] = v
        rebuildQuick()
    end })
end
Misc:Button({ Title = "FPS boost", Callback = fpsBoost })
Misc:Button({ Title = "Server hop", Callback = function() task.spawn(serverHop) end })
Misc:Button({ Title = "Rejoin server", Callback = function() TeleportService:Teleport(game.PlaceId, lp) end })
Misc:Button({ Title = "Copy JobId", Callback = function()
    local ok = pcall(function() setclipboard(game.JobId) end)
    notify(ok and "JobId copied." or "Clipboard not supported.")
end })

end -- @endblock

do -- @block
-- EXTRA
local Extra = tab("Extra")
Extra:Button({ Title = "Infinite Yield", Callback = function()
    runUrl("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source")
end })
Extra:Input({
    Title = "7yd7 emote script link", Value = EMOTE_URL, Placeholder = "paste raw link",
    Callback = function(v) emoteUrl = v end,
})
Extra:Button({ Title = "7yd7 emote script", Callback = function() runUrl(emoteUrl) end })
Extra:Input({
    Title = "Custom script link", Value = "", Placeholder = "paste raw link",
    Callback = function(v) customUrl = v end,
})
Extra:Button({ Title = "Run custom script", Callback = function() runUrl(customUrl) end })

end -- @endblock

do -- @block
-- BINDS
local Binds = tab("Binds")
Binds:Keybind({ Title = "Silent aim", Value = "Z", Callback = function() S.silent = not S.silent end })
Binds:Keybind({ Title = "Invisible", Value = "X", Callback = function() task.spawn(setInvisible, not S.invisible) end })
Binds:Keybind({ Title = "Kill all", Value = "K", Callback = function() task.spawn(killAll) end })
Binds:Keybind({ Title = "Kill aura", Value = "J", Callback = function() S.killAura = not S.killAura end })
Binds:Keybind({ Title = "Auto shoot", Value = "H", Callback = function() S.autoShoot = not S.autoShoot end })
Binds:Keybind({ Title = "Wallbang", Value = "V", Callback = function() task.spawn(setWallbang, not S.wallbang) end })
Binds:Keybind({ Title = "Noclip", Value = "N", Callback = function() S.noclip = not S.noclip end })
Binds:Keybind({ Title = "Fly", Value = "F", Callback = function() setFly(not S.fly) end })
Binds:Keybind({ Title = "Drone", Value = "T", Callback = toggleDrone })
Binds:Keybind({ Title = "Give AK47", Value = "U", Callback = giveAK })
Binds:Keybind({ Title = "Shoot murderer", Value = "B", Callback = function() task.spawn(shootMurderer) end })
Binds:Keybind({ Title = "Grab gun", Value = "G", Callback = function() task.spawn(grabGun) end })
Binds:Keybind({ Title = "Teleport map", Value = "M", Callback = tpMap })
Binds:Keybind({ Title = "Teleport lobby", Value = "L", Callback = tpLobby })
Binds:Keybind({ Title = "Save position", Value = "P", Callback = savePos })
Binds:Keybind({ Title = "Load position", Value = "O", Callback = loadPos })

end -- @endblock

do -- @block
-- CONFIGS
local Configs = tab("Configs")
local cfgName, cfgSel, cfgImportText = "default", nil, ""
local dd
local function listForUi()
    local l = cfgList()
    if #l == 0 then l = { "default" } end
    return l
end
local function refreshList()
    local l = listForUi()
    if dd then pcall(function() dd:Refresh(l) end) end
    return l
end
Configs:Input({ Title = "Config name", Value = "default", Placeholder = "name", Callback = function(v) cfgName = v end })
Configs:Button({ Title = "Save config", Callback = function()
    cfgSave(cfgName)
    refreshList()
end })
local first = listForUi()
cfgSel = first[1]
dd = Configs:Dropdown({ Title = "Saved configs", Values = first, Value = first[1], Callback = function(v) cfgSel = v end })
Configs:Button({ Title = "Load selected config", Callback = function() cfgLoad(cfgSel or cfgName) end })
Configs:Button({ Title = "Delete selected config", Callback = function()
    cfgDelete(cfgSel or cfgName)
    local l = refreshList()
    cfgSel = l[1]
end })
Configs:Button({ Title = "Refresh list", Callback = refreshList })
Configs:Button({ Title = "Set selected as autoload", Callback = function() cfgSetAutoload(cfgSel or cfgName) end })
Configs:Button({ Title = "Clear autoload", Callback = function() cfgSetAutoload(nil) end })
Configs:Button({ Title = "Export config to clipboard", Callback = cfgExport })
Configs:Input({ Title = "Import config (paste text)", Value = "", Placeholder = "paste exported text", Callback = function(v) cfgImportText = v end })
Configs:Button({ Title = "Import pasted config", Callback = function() cfgImport(cfgImportText) end })
end -- @endblock

do -- @block
-- SETTING
local Setting = tab("Setting")
Setting:Dropdown({
    Title = "Theme",
    Values = { "Dark", "White", "Red", "Yellow", "Blue" },
    Value = "Blue",
    Callback = function(v) applyThemeVisuals(v) end,
})
Setting:Toggle({ Title = "Watermark", Value = true, Callback = function(v) wm.Enabled = v end })
Setting:Toggle({ Title = "Mobile quick buttons", Value = S.quickOn, Callback = function(v)
    S.quickOn = v
    rebuildQuick()
end })
Setting:Toggle({ Title = "Floating icon", Value = true, Callback = function(v) setFabVisible(v) end })
Setting:Button({ Title = "Unload artihub", Callback = function() task.spawn(unload) end })

end -- @endblock

pcall(function() if getgenv then getgenv().artihub_unload = unload end end)
pcall(function() Window:SelectTab(1) end)
task.delay(2, function() pcall(cfgRunAutoload) end)
applyThemeVisuals("Blue")
if not firetouchinterest then notify("Your executor has no firetouchinterest: gun grab, coins and knife kills may not work.") end
if not hasDrawing then notify("No Drawing library: tracers are disabled (everything else works).") end
notify("artihub loaded. Right Ctrl toggles the menu.")

end, function(e) return debug.traceback(tostring(e), 2) end)

if not __ok then
    warn("[artihub] failed to start:\n" .. tostring(__err))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "artihub", Text = "Failed to start, see the console (F9).", Duration = 8,
        })
    end)
end
