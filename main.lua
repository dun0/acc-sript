local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STALL_CHECK_INTERVAL = 5
local ANTI_AFK_INTERVAL = 30

local START_FLOOR = 3
local END_FLOOR = 25
local TOWER_ID = "light_fairy"

-- Anti-AFK is now disabled by default
local antiAfkEnabled = false

local function antiAfk()
    local keys = {Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D}
    
    while true do
        wait(ANTI_AFK_INTERVAL)
        
        if antiAfkEnabled then
            local randomKey = keys[math.random(1, #keys)]
            VirtualUser:CaptureController()
            VirtualUser:Button1Down(Vector2.new())
            game:GetService("VirtualInputManager"):SendKeyEvent(true, randomKey, false, game)
            wait(0.1)
            game:GetService("VirtualInputManager"):SendKeyEvent(false, randomKey, false, game)
            VirtualUser:Button1Up(Vector2.new())
        end
    end
end

coroutine.wrap(antiAfk)()

local fightEvent = ReplicatedStorage["shared/network@eventDefinitions"].fightBattleTowerWave
local rewardEvent = ReplicatedStorage["shared/network@eventDefinitions"].notifyRewards
local animationEvent = ReplicatedStorage["shared/network@eventDefinitions"].playBattleAnimation
local dispatchEvent = ReplicatedStorage["shared/network@eventDefinitions"].dispatch
local useItemEvent = ReplicatedStorage["shared/network@eventDefinitions"].useItem

local currentFloor = START_FLOOR
local isRunning = false
local isBattling = false
local animationTurnCount = 0
local battleAttempts = 0

local moons = {
    {name = "full_moon", display = "Full Moon", tier = 1},
    {name = "harvest_moon", display = "Harvest Moon", tier = 2},
    {name = "snow_moon", display = "Snow Moon", tier = 3},
    {name = "blood_moon", display = "Blood Moon", tier = 4},
    {name = "wolf_moon", display = "Wolf Moon", tier = 5},
    {name = "blue_moon", display = "Blue Moon", tier = 6},
    {name = "eclipse_moon", display = "Eclipse Moon", tier = 7},
    {name = "monarch_moon", display = "Monarch Moon", tier = 8},
    {name = "tsukiyomi_moon", display = "Tsukiyomi Moon", tier = 9},
    {name = "inferno_moon", display = "Inferno Moon", tier = 10},
    {name = "abyss_moon", display = "Abyss Moon", tier = 11}
}

local currentMoon = "None"
local targetMoon = "harvest_moon"
local targetMoonTier = 2
local moonRolling = false
local moonLooping = false
local moonTimeRemaining = 0
local rollCount = 0

local towers = {
    "battle_tower",
    "watery_depths", 
    "frozen_landscape",
    "stone_citadel",
    "inferno_depths",
    "lunar_eclipse",
    "light_fairy"
}

local towerCycleConfig = {}
local cycleTowersEnabled = false
local floorOptions = {5, 10, 15, 20, 25}

for i, towerName in ipairs(towers) do
    towerCycleConfig[towerName] = {
        enabled = false,
        floors = {}
    }
    for _, floorNum in ipairs(floorOptions) do
        towerCycleConfig[towerName].floors[floorNum] = false
    end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LunarTowerFarm"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 480) -- MODIFIED: Increased height
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -240) -- MODIFIED: Adjusted position for new height
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
Title.BorderSizePixel = 0
Title.Text = "boss retry"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = Title

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.new(0, 30, 0, 30)
MinimizeButton.Position = UDim2.new(1, -35, 0, 5)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
MinimizeButton.Text = "-"
MinimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeButton.TextSize = 20
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.BorderSizePixel = 0
MinimizeButton.Parent = MainFrame

local MinimizeCorner = Instance.new("UICorner")
MinimizeCorner.CornerRadius = UDim.new(0, 6)
MinimizeCorner.Parent = MinimizeButton

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, 0, 0, 35)
TabBar.Position = UDim2.new(0, 0, 0, 40)
TabBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local TowerTabButton = Instance.new("TextButton")
TowerTabButton.Size = UDim2.new(0.5, -2, 1, 0)
TowerTabButton.Position = UDim2.new(0, 0, 0, 0)
TowerTabButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
TowerTabButton.Text = "Tower Farm"
TowerTabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
TowerTabButton.TextSize = 14
TowerTabButton.Font = Enum.Font.GothamBold
TowerTabButton.BorderSizePixel = 0
TowerTabButton.Parent = TabBar

local MoonTabButton = Instance.new("TextButton")
MoonTabButton.Size = UDim2.new(0.5, -2, 1, 0)
MoonTabButton.Position = UDim2.new(0.5, 2, 0, 0)
MoonTabButton.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
MoonTabButton.Text = "Moon Roller"
MoonTabButton.TextColor3 = Color3.fromRGB(200, 200, 200)
MoonTabButton.TextSize = 14
MoonTabButton.Font = Enum.Font.Gotham
MoonTabButton.BorderSizePixel = 0
MoonTabButton.Parent = TabBar

local TowerFrame = Instance.new("Frame")
TowerFrame.Size = UDim2.new(1, 0, 1, -75)
TowerFrame.Position = UDim2.new(0, 0, 0, 75)
TowerFrame.BackgroundTransparency = 1
TowerFrame.Visible = true
TowerFrame.Parent = MainFrame

local MoonFrame = Instance.new("Frame")
MoonFrame.Size = UDim2.new(1, 0, 1, -75)
MoonFrame.Position = UDim2.new(0, 0, 0, 75)
MoonFrame.BackgroundTransparency = 1
MoonFrame.Visible = false
MoonFrame.Parent = MainFrame

local TowerLabel = Instance.new("TextLabel")
TowerLabel.Size = UDim2.new(1, -20, 0, 20)
TowerLabel.Position = UDim2.new(0, 10, 0, 10)
TowerLabel.BackgroundTransparency = 1
TowerLabel.Text = "Tower:"
TowerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TowerLabel.TextSize = 12
TowerLabel.Font = Enum.Font.Gotham
TowerLabel.TextXAlignment = Enum.TextXAlignment.Left
TowerLabel.Parent = TowerFrame

local TowerDropdown = Instance.new("TextButton")
TowerDropdown.Size = UDim2.new(1, -20, 0, 30)
TowerDropdown.Position = UDim2.new(0, 10, 0, 30)
TowerDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
TowerDropdown.BorderSizePixel = 0
TowerDropdown.Text = "light_fairy"
TowerDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
TowerDropdown.TextSize = 14
TowerDropdown.Font = Enum.Font.Gotham
TowerDropdown.TextXAlignment = Enum.TextXAlignment.Left
TowerDropdown.Parent = TowerFrame

local TowerDropdownPadding = Instance.new("UIPadding")
TowerDropdownPadding.PaddingLeft = UDim.new(0, 10)
TowerDropdownPadding.Parent = TowerDropdown

local TowerDropdownCorner = Instance.new("UICorner")
TowerDropdownCorner.CornerRadius = UDim.new(0, 6)
TowerDropdownCorner.Parent = TowerDropdown

local DropdownArrow = Instance.new("TextLabel")
DropdownArrow.Size = UDim2.new(0, 30, 1, 0)
DropdownArrow.Position = UDim2.new(1, -30, 0, 0)
DropdownArrow.BackgroundTransparency = 1
DropdownArrow.Text = "▼"
DropdownArrow.TextColor3 = Color3.fromRGB(200, 200, 200)
DropdownArrow.TextSize = 12
DropdownArrow.Font = Enum.Font.Gotham
DropdownArrow.Parent = TowerDropdown

local DropdownMenu = Instance.new("Frame")
DropdownMenu.Size = UDim2.new(1, -20, 0, 0)
DropdownMenu.Position = UDim2.new(0, 10, 0, 62)
DropdownMenu.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
DropdownMenu.BorderSizePixel = 0
DropdownMenu.ClipsDescendants = true
DropdownMenu.Visible = false
DropdownMenu.Parent = TowerFrame
DropdownMenu.ZIndex = 10

local DropdownMenuCorner = Instance.new("UICorner")
DropdownMenuCorner.CornerRadius = UDim.new(0, 6)
DropdownMenuCorner.Parent = DropdownMenu

local DropdownList = Instance.new("UIListLayout")
DropdownList.SortOrder = Enum.SortOrder.LayoutOrder
DropdownList.Parent = DropdownMenu

local dropdownOpen = false

for i, towerName in ipairs(towers) do
    local TowerOption = Instance.new("TextButton")
    TowerOption.Size = UDim2.new(1, 0, 0, 30)
    TowerOption.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    TowerOption.BorderSizePixel = 0
    TowerOption.Text = towerName
    TowerOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    TowerOption.TextSize = 14
    TowerOption.Font = Enum.Font.Gotham
    TowerOption.TextXAlignment = Enum.TextXAlignment.Left
    TowerOption.Parent = DropdownMenu
    TowerOption.ZIndex = 10
    
    local OptionPadding = Instance.new("UIPadding")
    OptionPadding.PaddingLeft = UDim.new(0, 10)
    OptionPadding.Parent = TowerOption
    
    TowerOption.MouseEnter:Connect(function()
        TowerOption.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
    end)
    
    TowerOption.MouseLeave:Connect(function()
        TowerOption.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end)
    
    TowerOption.MouseButton1Click:Connect(function()
        TowerDropdown.Text = towerName
        DropdownMenu.Visible = false
        dropdownOpen = false
        DropdownArrow.Text = "▼"
    end)
end

TowerDropdown.MouseButton1Click:Connect(function()
    dropdownOpen = not dropdownOpen
    DropdownMenu.Visible = dropdownOpen
    
    if dropdownOpen then
        DropdownMenu:TweenSize(UDim2.new(1, -20, 0, #towers * 30), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
        DropdownArrow.Text = "▲"
    else
        DropdownMenu:TweenSize(UDim2.new(1, -20, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true, function()
            DropdownMenu.Visible = false
        end)
        DropdownArrow.Text = "▼"
    end
end)

local StartFloorLabel = Instance.new("TextLabel")
StartFloorLabel.Size = UDim2.new(0.5, -15, 0, 20)
StartFloorLabel.Position = UDim2.new(0, 10, 0, 70)
StartFloorLabel.BackgroundTransparency = 1
StartFloorLabel.Text = "Start Floor:"
StartFloorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StartFloorLabel.TextSize = 12
StartFloorLabel.Font = Enum.Font.Gotham
StartFloorLabel.TextXAlignment = Enum.TextXAlignment.Left
StartFloorLabel.Parent = TowerFrame

local StartFloorInput = Instance.new("TextBox")
StartFloorInput.Size = UDim2.new(0.5, -15, 0, 30)
StartFloorInput.Position = UDim2.new(0, 10, 0, 90)
StartFloorInput.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
StartFloorInput.BorderSizePixel = 0
StartFloorInput.Text = "3"
StartFloorInput.TextColor3 = Color3.fromRGB(255, 255, 255)
StartFloorInput.TextSize = 14
StartFloorInput.Font = Enum.Font.Gotham
StartFloorInput.PlaceholderText = "3"
StartFloorInput.Parent = TowerFrame

local StartFloorInputCorner = Instance.new("UICorner")
StartFloorInputCorner.CornerRadius = UDim.new(0, 6)
StartFloorInputCorner.Parent = StartFloorInput

local EndFloorLabel = Instance.new("TextLabel")
EndFloorLabel.Size = UDim2.new(0.5, -15, 0, 20)
EndFloorLabel.Position = UDim2.new(0.5, 5, 0, 70)
EndFloorLabel.BackgroundTransparency = 1
EndFloorLabel.Text = "End Floor:"
EndFloorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
EndFloorLabel.TextSize = 12
EndFloorLabel.Font = Enum.Font.Gotham
EndFloorLabel.TextXAlignment = Enum.TextXAlignment.Left
EndFloorLabel.Parent = TowerFrame

local EndFloorInput = Instance.new("TextBox")
EndFloorInput.Size = UDim2.new(0.5, -15, 0, 30)
EndFloorInput.Position = UDim2.new(0.5, 5, 0, 90)
EndFloorInput.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
EndFloorInput.BorderSizePixel = 0
EndFloorInput.Text = "25"
EndFloorInput.TextColor3 = Color3.fromRGB(255, 255, 255)
EndFloorInput.TextSize = 14
EndFloorInput.Font = Enum.Font.Gotham
EndFloorInput.PlaceholderText = "25"
EndFloorInput.Parent = TowerFrame

local EndFloorInputCorner = Instance.new("UICorner")
EndFloorInputCorner.CornerRadius = UDim.new(0, 6)
EndFloorInputCorner.Parent = EndFloorInput

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 30)
StatusLabel.Position = UDim2.new(0, 10, 0, 130)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.TextSize = 14
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = TowerFrame

local FloorLabel = Instance.new("TextLabel")
FloorLabel.Size = UDim2.new(1, -20, 0, 30)
FloorLabel.Position = UDim2.new(0, 10, 0, 165)
FloorLabel.BackgroundTransparency = 1
FloorLabel.Text = "Current Floor: 3"
FloorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
FloorLabel.TextSize = 14
FloorLabel.Font = Enum.Font.Gotham
FloorLabel.TextXAlignment = Enum.TextXAlignment.Left
FloorLabel.Parent = TowerFrame

local TurnsLabel = Instance.new("TextLabel")
TurnsLabel.Size = UDim2.new(1, -20, 0, 30)
TurnsLabel.Position = UDim2.new(0, 10, 0, 200)
TurnsLabel.BackgroundTransparency = 1
TurnsLabel.Text = "Turns: 0"
TurnsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TurnsLabel.TextSize = 14
TurnsLabel.Font = Enum.Font.Gotham
TurnsLabel.TextXAlignment = Enum.TextXAlignment.Left
TurnsLabel.Parent = TowerFrame

local AttemptsLabel = Instance.new("TextLabel")
AttemptsLabel.Size = UDim2.new(1, -20, 0, 30)
AttemptsLabel.Position = UDim2.new(0, 10, 0, 235)
AttemptsLabel.BackgroundTransparency = 1
AttemptsLabel.Text = "Attempts: 0"
AttemptsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
AttemptsLabel.TextSize = 14
AttemptsLabel.Font = Enum.Font.Gotham
AttemptsLabel.TextXAlignment = Enum.TextXAlignment.Left
AttemptsLabel.Parent = TowerFrame

local AntiAfkLabel = Instance.new("TextLabel")
AntiAfkLabel.Size = UDim2.new(1, -80, 0, 20)
AntiAfkLabel.Position = UDim2.new(0, 10, 0, 270)
AntiAfkLabel.BackgroundTransparency = 1
AntiAfkLabel.Text = "Anti-AFK: Disabled"
AntiAfkLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
AntiAfkLabel.TextSize = 12
AntiAfkLabel.Font = Enum.Font.Gotham
AntiAfkLabel.TextXAlignment = Enum.TextXAlignment.Left
AntiAfkLabel.Parent = TowerFrame

local AntiAfkToggle = Instance.new("TextButton")
AntiAfkToggle.Size = UDim2.new(0, 60, 0, 20)
AntiAfkToggle.Position = UDim2.new(1, -70, 0, 270)
AntiAfkToggle.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
AntiAfkToggle.Text = "OFF"
AntiAfkToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
AntiAfkToggle.TextSize = 12
AntiAfkToggle.Font = Enum.Font.GothamBold
AntiAfkToggle.BorderSizePixel = 0
AntiAfkToggle.Parent = TowerFrame

local AntiAfkToggleCorner = Instance.new("UICorner")
AntiAfkToggleCorner.CornerRadius = UDim.new(0, 4)
AntiAfkToggleCorner.Parent = AntiAfkToggle

local CycleTowerLabel = Instance.new("TextLabel")
CycleTowerLabel.Size = UDim2.new(1, -80, 0, 20)
CycleTowerLabel.Position = UDim2.new(0, 10, 0, 300)
CycleTowerLabel.BackgroundTransparency = 1
CycleTowerLabel.Text = "Cycle Towers"
CycleTowerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
CycleTowerLabel.TextSize = 12
CycleTowerLabel.Font = Enum.Font.Gotham
CycleTowerLabel.TextXAlignment = Enum.TextXAlignment.Left
CycleTowerLabel.Parent = TowerFrame

local CycleTowerToggle = Instance.new("TextButton")
CycleTowerToggle.Size = UDim2.new(0, 60, 0, 20)
CycleTowerToggle.Position = UDim2.new(1, -70, 0, 300)
CycleTowerToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
CycleTowerToggle.Text = "OFF"
CycleTowerToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
CycleTowerToggle.TextSize = 12
CycleTowerToggle.Font = Enum.Font.GothamBold
CycleTowerToggle.BorderSizePixel = 0
CycleTowerToggle.Parent = TowerFrame

local CycleTowerToggleCorner = Instance.new("UICorner")
CycleTowerToggleCorner.CornerRadius = UDim.new(0, 4)
CycleTowerToggleCorner.Parent = CycleTowerToggle

local ConfigCycleButton = Instance.new("TextButton")
ConfigCycleButton.Size = UDim2.new(1, -20, 0, 25)
ConfigCycleButton.Position = UDim2.new(0, 10, 0, 330) -- MODIFIED: Repositioned to avoid overlap
ConfigCycleButton.BackgroundColor3 = Color3.fromRGB(50, 100, 150)
ConfigCycleButton.Text = "Configure Tower Cycle"
ConfigCycleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ConfigCycleButton.TextSize = 12
ConfigCycleButton.Font = Enum.Font.GothamBold
ConfigCycleButton.BorderSizePixel = 0
ConfigCycleButton.Parent = TowerFrame

local ConfigCycleButtonCorner = Instance.new("UICorner")
ConfigCycleButtonCorner.CornerRadius = UDim.new(0, 6)
ConfigCycleButtonCorner.Parent = ConfigCycleButton

local StartButton = Instance.new("TextButton")
StartButton.Size = UDim2.new(0.5, -15, 0, 35)
StartButton.Position = UDim2.new(0, 10, 1, -45)
StartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
StartButton.Text = "Start"
StartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StartButton.TextSize = 14
StartButton.Font = Enum.Font.GothamBold
StartButton.BorderSizePixel = 0
StartButton.Parent = TowerFrame

local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 6)
StartCorner.Parent = StartButton

local StopButton = Instance.new("TextButton")
StopButton.Size = UDim2.new(0.5, -15, 0, 35)
StopButton.Position = UDim2.new(0.5, 5, 1, -45)
StopButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
StopButton.Text = "Stop"
StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StopButton.TextSize = 14
StopButton.Font = Enum.Font.GothamBold
StopButton.BorderSizePixel = 0
StopButton.Parent = TowerFrame

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 6)
StopCorner.Parent = StopButton

local CycleConfigFrame = Instance.new("Frame")
CycleConfigFrame.Size = UDim2.new(0, 380, 0, 400)
CycleConfigFrame.Position = UDim2.new(0.5, -190, 0.5, -200)
CycleConfigFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
CycleConfigFrame.BorderSizePixel = 0
CycleConfigFrame.Visible = false
CycleConfigFrame.ZIndex = 100
CycleConfigFrame.Parent = ScreenGui

local CycleConfigCorner = Instance.new("UICorner")
CycleConfigCorner.CornerRadius = UDim.new(0, 10)
CycleConfigCorner.Parent = CycleConfigFrame

local CycleConfigTitle = Instance.new("TextLabel")
CycleConfigTitle.Size = UDim2.new(1, 0, 0, 40)
CycleConfigTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
CycleConfigTitle.BorderSizePixel = 0
CycleConfigTitle.Text = "Configure Tower Cycle"
CycleConfigTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
CycleConfigTitle.TextSize = 14
CycleConfigTitle.Font = Enum.Font.GothamBold
CycleConfigTitle.ZIndex = 101
CycleConfigTitle.Parent = CycleConfigFrame

local CycleConfigTitleCorner = Instance.new("UICorner")
CycleConfigTitleCorner.CornerRadius = UDim.new(0, 10)
CycleConfigTitleCorner.Parent = CycleConfigTitle

local CloseCycleConfigButton = Instance.new("TextButton")
CloseCycleConfigButton.Size = UDim2.new(0, 30, 0, 30)
CloseCycleConfigButton.Position = UDim2.new(1, -35, 0, 5)
CloseCycleConfigButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
CloseCycleConfigButton.Text = "X"
CloseCycleConfigButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseCycleConfigButton.TextSize = 16
CloseCycleConfigButton.Font = Enum.Font.GothamBold
CloseCycleConfigButton.BorderSizePixel = 0
CloseCycleConfigButton.ZIndex = 102
CloseCycleConfigButton.Parent = CycleConfigFrame

local CloseCycleConfigCorner = Instance.new("UICorner")
CloseCycleConfigCorner.CornerRadius = UDim.new(0, 6)
CloseCycleConfigCorner.Parent = CloseCycleConfigButton

local CycleScrollFrame = Instance.new("ScrollingFrame")
CycleScrollFrame.Size = UDim2.new(1, -20, 1, -50)
CycleScrollFrame.Position = UDim2.new(0, 10, 0, 50)
CycleScrollFrame.BackgroundTransparency = 1
CycleScrollFrame.BorderSizePixel = 0
CycleScrollFrame.ScrollBarThickness = 6
CycleScrollFrame.ZIndex = 101
CycleScrollFrame.Parent = CycleConfigFrame

local CycleListLayout = Instance.new("UIListLayout")
CycleListLayout.SortOrder = Enum.SortOrder.LayoutOrder
CycleListLayout.Padding = UDim.new(0, 10)
CycleListLayout.Parent = CycleScrollFrame

for i, towerName in ipairs(towers) do
    local TowerConfigFrame = Instance.new("Frame")
    TowerConfigFrame.Size = UDim2.new(1, 0, 0, 90)
    TowerConfigFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    TowerConfigFrame.BorderSizePixel = 0
    TowerConfigFrame.ZIndex = 101
    TowerConfigFrame.Parent = CycleScrollFrame
    
    local TowerConfigCorner = Instance.new("UICorner")
    TowerConfigCorner.CornerRadius = UDim.new(0, 6)
    TowerConfigCorner.Parent = TowerConfigFrame
    
    local TowerNameLabel = Instance.new("TextLabel")
    TowerNameLabel.Size = UDim2.new(1, -85, 0, 25)
    TowerNameLabel.Position = UDim2.new(0, 10, 0, 5)
    TowerNameLabel.BackgroundTransparency = 1
    TowerNameLabel.Text = towerName:gsub("_", " "):upper()
    TowerNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    TowerNameLabel.TextSize = 14
    TowerNameLabel.Font = Enum.Font.GothamBold
    TowerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    TowerNameLabel.ZIndex = 102
    TowerNameLabel.Parent = TowerConfigFrame
    
    local TowerEnableButton = Instance.new("TextButton")
    TowerEnableButton.Size = UDim2.new(0, 60, 0, 20)
    TowerEnableButton.Position = UDim2.new(1, -70, 0, 7.5)
    TowerEnableButton.BackgroundColor3 = Color3.fromRGB(45,45,55)
    TowerEnableButton.Text = "OFF"
    TowerEnableButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    TowerEnableButton.TextSize = 12
    TowerEnableButton.Font = Enum.Font.GothamBold
    TowerEnableButton.BorderSizePixel = 0
    TowerEnableButton.ZIndex = 102
    TowerEnableButton.Parent = TowerConfigFrame

    local TowerEnableCorner = Instance.new("UICorner")
    TowerEnableCorner.CornerRadius = UDim.new(0, 4)
    TowerEnableCorner.Parent = TowerEnableButton
    
    TowerEnableButton.MouseButton1Click:Connect(function()
        local config = towerCycleConfig[towerName]
        config.enabled = not config.enabled
        if config.enabled then
            TowerEnableButton.Text = "ON"
            TowerEnableButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        else
            TowerEnableButton.Text = "OFF"
            TowerEnableButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        end
    end)
    
    local FloorSelectLabel = Instance.new("TextLabel")
    FloorSelectLabel.Size = UDim2.new(1, -10, 0, 20)
    FloorSelectLabel.Position = UDim2.new(0, 10, 0, 35)
    FloorSelectLabel.BackgroundTransparency = 1
    FloorSelectLabel.Text = "Select floors to farm:"
    FloorSelectLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    FloorSelectLabel.TextSize = 12
    FloorSelectLabel.Font = Enum.Font.Gotham
    FloorSelectLabel.TextXAlignment = Enum.TextXAlignment.Left
    FloorSelectLabel.ZIndex = 102
    FloorSelectLabel.Parent = TowerConfigFrame
    
    for j, floor in ipairs(floorOptions) do
        local FloorButton = Instance.new("TextButton")
        FloorButton.Size = UDim2.new(0, 50, 0, 25)
        FloorButton.Position = UDim2.new(0, 10 + (j - 1) * 60, 0, 58)
        FloorButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        FloorButton.Text = tostring(floor)
        FloorButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        FloorButton.TextSize = 11
        FloorButton.Font = Enum.Font.GothamBold
        FloorButton.BorderSizePixel = 0
        FloorButton.ZIndex = 102
        FloorButton.Parent = TowerConfigFrame
        
        local FloorButtonCorner = Instance.new("UICorner")
        FloorButtonCorner.CornerRadius = UDim.new(0, 4)
        FloorButtonCorner.Parent = FloorButton
        
        FloorButton.MouseButton1Click:Connect(function()
            local floorConfig = towerCycleConfig[towerName].floors
            floorConfig[floor] = not floorConfig[floor]
            
            if floorConfig[floor] then
                FloorButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            else
                FloorButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
        end)
    end
end

CycleScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #towers * 100)

local CurrentMoonLabel = Instance.new("TextLabel")
CurrentMoonLabel.Size = UDim2.new(1, -20, 0, 30)
CurrentMoonLabel.Position = UDim2.new(0, 10, 0, 10)
CurrentMoonLabel.BackgroundTransparency = 1
CurrentMoonLabel.Text = "Current Moon: None"
CurrentMoonLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
CurrentMoonLabel.TextSize = 14
CurrentMoonLabel.Font = Enum.Font.Gotham
CurrentMoonLabel.TextXAlignment = Enum.TextXAlignment.Left
CurrentMoonLabel.Parent = MoonFrame

local MoonTimerLabel = Instance.new("TextLabel")
MoonTimerLabel.Size = UDim2.new(1, -20, 0, 30)
MoonTimerLabel.Position = UDim2.new(0, 10, 0, 45)
MoonTimerLabel.BackgroundTransparency = 1
MoonTimerLabel.Text = "Time Remaining: 0s"
MoonTimerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
MoonTimerLabel.TextSize = 14
MoonTimerLabel.Font = Enum.Font.Gotham
MoonTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
MoonTimerLabel.Parent = MoonFrame

local TargetMoonLabel = Instance.new("TextLabel")
TargetMoonLabel.Size = UDim2.new(1, -20, 0, 20)
TargetMoonLabel.Position = UDim2.new(0, 10, 0, 85)
TargetMoonLabel.BackgroundTransparency = 1
TargetMoonLabel.Text = "Target Moon:"
TargetMoonLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TargetMoonLabel.TextSize = 12
TargetMoonLabel.Font = Enum.Font.Gotham
TargetMoonLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetMoonLabel.Parent = MoonFrame

local MoonDropdown = Instance.new("TextButton")
MoonDropdown.Size = UDim2.new(1, -20, 0, 30)
MoonDropdown.Position = UDim2.new(0, 10, 0, 105)
MoonDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
MoonDropdown.BorderSizePixel = 0
MoonDropdown.Text = "Harvest Moon"
MoonDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
MoonDropdown.TextSize = 14
MoonDropdown.Font = Enum.Font.Gotham
MoonDropdown.TextXAlignment = Enum.TextXAlignment.Left
MoonDropdown.Parent = MoonFrame

local MoonDropdownPadding = Instance.new("UIPadding")
MoonDropdownPadding.PaddingLeft = UDim.new(0, 10)
MoonDropdownPadding.Parent = MoonDropdown

local MoonDropdownCorner = Instance.new("UICorner")
MoonDropdownCorner.CornerRadius = UDim.new(0, 6)
MoonDropdownCorner.Parent = MoonDropdown

local MoonDropdownArrow = Instance.new("TextLabel")
MoonDropdownArrow.Size = UDim2.new(0, 30, 1, 0)
MoonDropdownArrow.Position = UDim2.new(1, -30, 0, 0)
MoonDropdownArrow.BackgroundTransparency = 1
MoonDropdownArrow.Text = "▼"
MoonDropdownArrow.TextColor3 = Color3.fromRGB(200, 200, 200)
MoonDropdownArrow.TextSize = 12
MoonDropdownArrow.Font = Enum.Font.Gotham
MoonDropdownArrow.Parent = MoonDropdown

local MoonDropdownMenu = Instance.new("Frame")
MoonDropdownMenu.Size = UDim2.new(1, -20, 0, 0)
MoonDropdownMenu.Position = UDim2.new(0, 10, 0, 137)
MoonDropdownMenu.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
MoonDropdownMenu.BorderSizePixel = 0
MoonDropdownMenu.ClipsDescendants = true
MoonDropdownMenu.Visible = false
MoonDropdownMenu.Parent = MoonFrame
MoonDropdownMenu.ZIndex = 10

local MoonDropdownMenuCorner = Instance.new("UICorner")
MoonDropdownMenuCorner.CornerRadius = UDim.new(0, 6)
MoonDropdownMenuCorner.Parent = MoonDropdownMenu

local MoonDropdownList = Instance.new("UIListLayout")
MoonDropdownList.SortOrder = Enum.SortOrder.LayoutOrder
MoonDropdownList.Parent = MoonDropdownMenu

local moonDropdownOpen = false

for i, moon in ipairs(moons) do
    local MoonOption = Instance.new("TextButton")
    MoonOption.Size = UDim2.new(1, 0, 0, 30)
    MoonOption.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    MoonOption.BorderSizePixel = 0
    MoonOption.Text = moon.display
    MoonOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    MoonOption.TextSize = 14
    MoonOption.Font = Enum.Font.Gotham
    MoonOption.TextXAlignment = Enum.TextXAlignment.Left
    MoonOption.Parent = MoonDropdownMenu
    MoonOption.ZIndex = 10
    
    local MoonOptionPadding = Instance.new("UIPadding")
    MoonOptionPadding.PaddingLeft = UDim.new(0, 10)
    MoonOptionPadding.Parent = MoonOption
    
    MoonOption.MouseEnter:Connect(function()
        MoonOption.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
    end)
    
    MoonOption.MouseLeave:Connect(function()
        MoonOption.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end)
    
    MoonOption.MouseButton1Click:Connect(function()
        MoonDropdown.Text = moon.display
        targetMoon = moon.name
        targetMoonTier = moon.tier
        MoonDropdownMenu.Visible = false
        moonDropdownOpen = false
        MoonDropdownArrow.Text = "▼"
    end)
end

MoonDropdown.MouseButton1Click:Connect(function()
    moonDropdownOpen = not moonDropdownOpen
    MoonDropdownMenu.Visible = moonDropdownOpen
    
    if moonDropdownOpen then
        MoonDropdownMenu:TweenSize(UDim2.new(1, -20, 0, #moons * 30), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
        MoonDropdownArrow.Text = "▲"
    else
        MoonDropdownMenu:TweenSize(UDim2.new(1, -20, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true, function()
            MoonDropdownMenu.Visible = false
        end)
        MoonDropdownArrow.Text = "▼"
    end
end)

local MoonStatusLabel = Instance.new("TextLabel")
MoonStatusLabel.Size = UDim2.new(1, -20, 0, 30)
MoonStatusLabel.Position = UDim2.new(0, 10, 0, 145)
MoonStatusLabel.BackgroundTransparency = 1
MoonStatusLabel.Text = "Status: Idle"
MoonStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
MoonStatusLabel.TextSize = 14
MoonStatusLabel.Font = Enum.Font.Gotham
MoonStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
MoonStatusLabel.Parent = MoonFrame

local RollCountLabel = Instance.new("TextLabel")
RollCountLabel.Size = UDim2.new(1, -20, 0, 30)
RollCountLabel.Position = UDim2.new(0, 10, 0, 180)
RollCountLabel.BackgroundTransparency = 1
RollCountLabel.Text = "Rolls Used: 0"
RollCountLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
RollCountLabel.TextSize = 14
RollCountLabel.Font = Enum.Font.Gotham
RollCountLabel.TextXAlignment = Enum.TextXAlignment.Left
RollCountLabel.Parent = MoonFrame

local LoopToggle = Instance.new("TextButton")
LoopToggle.Size = UDim2.new(1, -20, 0, 30)
LoopToggle.Position = UDim2.new(0, 10, 0, 220)
LoopToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
LoopToggle.Text = "Loop: OFF"
LoopToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
LoopToggle.TextSize = 14
LoopToggle.Font = Enum.Font.GothamBold
LoopToggle.BorderSizePixel = 0
LoopToggle.Parent = MoonFrame

local LoopToggleCorner = Instance.new("UICorner")
LoopToggleCorner.CornerRadius = UDim.new(0, 6)
LoopToggleCorner.Parent = LoopToggle

local MoonStartButton = Instance.new("TextButton")
MoonStartButton.Size = UDim2.new(0.5, -15, 0, 35)
MoonStartButton.Position = UDim2.new(0, 10, 1, -45)
MoonStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
MoonStartButton.Text = "Start Rolling"
MoonStartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MoonStartButton.TextSize = 14
MoonStartButton.Font = Enum.Font.GothamBold
MoonStartButton.BorderSizePixel = 0
MoonStartButton.Parent = MoonFrame

local MoonStartCorner = Instance.new("UICorner")
MoonStartCorner.CornerRadius = UDim.new(0, 6)
MoonStartCorner.Parent = MoonStartButton

local MoonStopButton = Instance.new("TextButton")
MoonStopButton.Size = UDim2.new(0.5, -15, 0, 35)
MoonStopButton.Position = UDim2.new(0.5, 5, 1, -45)
MoonStopButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
MoonStopButton.Text = "Stop"
MoonStopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MoonStopButton.TextSize = 14
MoonStopButton.Font = Enum.Font.GothamBold
MoonStopButton.BorderSizePixel = 0
MoonStopButton.Parent = MoonFrame

local MoonStopCorner = Instance.new("UICorner")
MoonStopCorner.CornerRadius = UDim.new(0, 6)
MoonStopCorner.Parent = MoonStopButton

-- MODIFIED: Added variables and logic for dragging UI elements
local dragging, dragInput, dragStart, startPos
local cycleConfigDragging, cycleConfigDragInput, cycleConfigDragStart, cycleConfigStartPos
local isMinimized = false

local function updateDrag(input)
    local delta = input.Position - dragStart
    MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

local function updateCycleConfigDrag(input)
    local delta = input.Position - cycleConfigDragStart
    CycleConfigFrame.Position = UDim2.new(cycleConfigStartPos.X.Scale, cycleConfigStartPos.X.Offset + delta.X, cycleConfigStartPos.Y.Scale, cycleConfigStartPos.Y.Offset + delta.Y)
end

Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)

Title.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

Title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- ADDED: Input handlers for the Cycle Config Frame title
CycleConfigTitle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        cycleConfigDragging = true
        cycleConfigDragStart = input.Position
        cycleConfigStartPos = CycleConfigFrame.Position
    end
end)

CycleConfigTitle.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        cycleConfigDragInput = input
    end
end)

CycleConfigTitle.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        cycleConfigDragging = false
    end
end)


game:GetService("UserInputService").InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        updateDrag(input)
    end
    -- ADDED: Check for cycle config dragging
    if cycleConfigDragging and input == cycleConfigDragInput then
        updateCycleConfigDrag(input)
    end
end)

ConfigCycleButton.MouseButton1Click:Connect(function()
    CycleConfigFrame.Visible = true
end)

CloseCycleConfigButton.MouseButton1Click:Connect(function()
    CycleConfigFrame.Visible = false
end)

CycleTowerToggle.MouseButton1Click:Connect(function()
    cycleTowersEnabled = not cycleTowersEnabled
    
    if cycleTowersEnabled then
        CycleTowerToggle.Text = "ON"
        CycleTowerToggle.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        CycleTowerLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    else
        CycleTowerToggle.Text = "OFF"
        CycleTowerToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        CycleTowerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    end
end)

TowerTabButton.MouseButton1Click:Connect(function()
    TowerFrame.Visible = true
    MoonFrame.Visible = false
    TowerTabButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    TowerTabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    TowerTabButton.Font = Enum.Font.GothamBold
    MoonTabButton.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    MoonTabButton.TextColor3 = Color3.fromRGB(200, 200, 200)
    MoonTabButton.Font = Enum.Font.Gotham
end)

MoonTabButton.MouseButton1Click:Connect(function()
    TowerFrame.Visible = false
    MoonFrame.Visible = true
    MoonTabButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    MoonTabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    MoonTabButton.Font = Enum.Font.GothamBold
    TowerTabButton.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    TowerTabButton.TextColor3 = Color3.fromRGB(200, 200, 200)
    TowerTabButton.Font = Enum.Font.Gotham
end)

MinimizeButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    
    if isMinimized then
        TabBar.Visible = false
        TowerFrame.Visible = false
        MoonFrame.Visible = false
        
        MainFrame:TweenSize(UDim2.new(0, 320, 0, 40), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        MinimizeButton.Text = "+"
    else
        TabBar.Visible = true
        if TowerTabButton.BackgroundColor3 == Color3.fromRGB(45, 45, 55) then
            TowerFrame.Visible = true
        else
            MoonFrame.Visible = true
        end
        
        MainFrame:TweenSize(UDim2.new(0, 320, 0, 480), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true) -- MODIFIED: Use new height
        MinimizeButton.Text = "-"
    end
end)

AntiAfkToggle.MouseButton1Click:Connect(function()
    antiAfkEnabled = not antiAfkEnabled
    
    if antiAfkEnabled then
        AntiAfkToggle.Text = "ON"
        AntiAfkToggle.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        AntiAfkLabel.Text = "Anti-AFK: Active (30s)"
        AntiAfkLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    else
        AntiAfkToggle.Text = "OFF"
        AntiAfkToggle.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        AntiAfkLabel.Text = "Anti-AFK: Disabled"
        AntiAfkLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
    end
end)

LoopToggle.MouseButton1Click:Connect(function()
    moonLooping = not moonLooping
    
    if moonLooping then
        LoopToggle.Text = "Loop: ON"
        LoopToggle.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    else
        LoopToggle.Text = "Loop: OFF"
        LoopToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end
end)

local function getMoonTier(moonName)
    for _, moon in ipairs(moons) do
        if moon.name == moonName then
            return moon.tier
        end
    end
    return 0
end

local function getMoonDisplay(moonName)
    for _, moon in ipairs(moons) do
        if moon.name == moonName then
            return moon.display
        end
    end
    return moonName
end

dispatchEvent.OnClientEvent:Connect(function(data)
    if data and type(data) == "table" then
        for _, event in ipairs(data) do
            if event.name == "moonCycleChanged" and event.arguments and event.arguments[1] then
                local newMoon = event.arguments[1]
                
                if newMoon == "none" then
                    currentMoon = "None"
                    CurrentMoonLabel.Text = "Current Moon: None"
                    moonTimeRemaining = 0
                    
                    if moonLooping and not moonRolling then
                        wait(2)
                        MoonStatusLabel.Text = "Status: Moon expired, rerolling..."
                        MoonStatusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
                        coroutine.wrap(rollMoons)()
                    end
                else
                    currentMoon = newMoon
                    CurrentMoonLabel.Text = "Current Moon: " .. getMoonDisplay(currentMoon)
                    
                    if event.arguments[2] then
                        moonTimeRemaining = 180
                    end
                end
            end
        end
    end
end)

coroutine.wrap(function()
    while true do
        wait(1)
        if moonTimeRemaining > 0 then
            moonTimeRemaining = moonTimeRemaining - 1
            local minutes = math.floor(moonTimeRemaining / 60)
            local seconds = moonTimeRemaining % 60
            MoonTimerLabel.Text = string.format("Time Remaining: %dm %ds", minutes, seconds)
        else
            MoonTimerLabel.Text = "Time Remaining: 0s"
        end
    end
end)()

function rollMoons()
    if moonRolling then return end
    
    moonRolling = true
    rollCount = 0
    RollCountLabel.Text = "Rolls Used: 0"
    MoonStatusLabel.Text = "Status: Rolling for " .. getMoonDisplay(targetMoon) .. "..."
    MoonStatusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    
    while moonRolling do
        local currentTier = getMoonTier(currentMoon)
        
        if currentTier >= targetMoonTier then
            if currentTier == targetMoonTier then
                MoonStatusLabel.Text = "Status: Target moon reached!"
                MoonStatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            else
                MoonStatusLabel.Text = "Status: Higher tier moon! Stopping..."
                MoonStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
            moonRolling = false
            break
        end
        
        pcall(function()
            useItemEvent:FireServer("moon_cycle_reroll_potion", 1)
        end)
        
        rollCount = rollCount + 1
        RollCountLabel.Text = "Rolls Used: " .. rollCount
        
        wait(0.01)
    end
    
    if not moonRolling then
        MoonStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    end
end

MoonStartButton.MouseButton1Click:Connect(function()
    if not moonRolling then
        MoonStartButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        coroutine.wrap(rollMoons)()
    end
end)

MoonStopButton.MouseButton1Click:Connect(function()
    moonRolling = false
    MoonStatusLabel.Text = "Status: Stopped"
    MoonStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    MoonStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
end)

local animationConnection
animationConnection = animationEvent.OnClientEvent:Connect(function()
    if isBattling then
        animationTurnCount = animationTurnCount + 1
        TurnsLabel.Text = "Turns: " .. animationTurnCount
    end
end)

local function startBattle(floor)
    isBattling = true
    animationTurnCount = 0
    StatusLabel.Text = "Status: Starting floor " .. floor .. "..."
    battleAttempts = battleAttempts + 1
    AttemptsLabel.Text = "Attempts: " .. battleAttempts
    TurnsLabel.Text = "Turns: 0"
    
    pcall(function()
        fightEvent:FireServer(TOWER_ID, floor)
    end)
    wait(2)
end

local function monitorBattle()
    while isBattling and isRunning do
        local turnsBeforeWait = animationTurnCount
        StatusLabel.Text = "Status: Battle in progress (Floor " .. currentFloor .. ")..."
        
        wait(STALL_CHECK_INTERVAL)
        
        if isBattling and isRunning then
            if animationTurnCount == turnsBeforeWait then
                StatusLabel.Text = "Status: Stalled! Retrying floor " .. currentFloor .. "..."
                startBattle(currentFloor)
            end
        end
    end
end

local function farmLoop()
    if cycleTowersEnabled then
        for _, towerName in ipairs(towers) do
            if not isRunning then break end

            local config = towerCycleConfig[towerName]
            if config.enabled then
                local floorsToRun = {}
                for floor, enabled in pairs(config.floors) do
                    if enabled then
                        table.insert(floorsToRun, floor)
                    end
                end
                table.sort(floorsToRun)

                if #floorsToRun > 0 then
                    TOWER_ID = towerName
                    StatusLabel.Text = "Status: Cycling to " .. towerName:gsub("_", " ")
                    StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
                    wait(2)

                    for _, floor in ipairs(floorsToRun) do
                        if not isRunning then break end
                        
                        currentFloor = floor
                        FloorLabel.Text = "Current Floor: " .. currentFloor .. " (" .. TOWER_ID:gsub("_", " ") .. ")"
                        
                        battleAttempts = 0
                        startBattle(currentFloor)
                        
                        local monitorThread = coroutine.wrap(monitorBattle)
                        monitorThread()
                        
                        while isBattling and isRunning do
                            wait(1)
                        end
                        
                        if not isRunning then break end
                        
                        wait(2)
                    end
                end
            end
        end
        
        if isRunning then
            isRunning = false
            StatusLabel.Text = "Status: Cycle complete!"
            StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            StartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        end
    else
        local startF = tonumber(StartFloorInput.Text) or 3
        local endF = tonumber(EndFloorInput.Text) or 25
        currentFloor = startF
        
        while isRunning and currentFloor <= endF do
            FloorLabel.Text = "Current Floor: " .. currentFloor
            
            startBattle(currentFloor)
            
            local monitorThread = coroutine.wrap(monitorBattle)
            monitorThread()
            
            while isBattling and isRunning do
                wait(1)
            end
            
            if isRunning then
                isBattling = false
                if currentFloor < endF then
                    currentFloor = currentFloor + 1
                    battleAttempts = 0
                else
                    isRunning = false
                    StatusLabel.Text = "Status: All floors completed!"
                    StartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
                end
            end
            
            if not isRunning then break end
            
            wait(2)
        end
    end
end

local rewardConnection
rewardConnection = rewardEvent.OnClientEvent:Connect(function(rewards)
    if not isBattling or not isRunning then return end
    
    if rewards and type(rewards) == "table" and #rewards > 0 then
        isBattling = false
        StatusLabel.Text = "Status: Floor " .. currentFloor .. " COMPLETED!"
        StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        battleAttempts = 0
    end
end)

StartButton.MouseButton1Click:Connect(function()
    if not isRunning then
        if not cycleTowersEnabled then
            TOWER_ID = TowerDropdown.Text
            START_FLOOR = tonumber(StartFloorInput.Text) or 3
            END_FLOOR = tonumber(EndFloorInput.Text) or 25
            
            if TOWER_ID == "" then
                StatusLabel.Text = "Status: Select a tower!"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                return
            end
            
            if START_FLOOR > END_FLOOR then
                StatusLabel.Text = "Status: Start floor must be <= End floor!"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                return
            end
            
            currentFloor = START_FLOOR
        end
        
        isRunning = true
        battleAttempts = 0
        animationTurnCount = 0
        StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        StartButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        coroutine.wrap(farmLoop)()
    end
end)

StopButton.MouseButton1Click:Connect(function()
    isRunning = false
    isBattling = false
    StatusLabel.Text = "Status: Stopped"
    StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    StartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
end)
