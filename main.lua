local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if not isfolder("Roblox") then
	makefolder("Roblox")
end
if not isfolder("Roblox/boss-retry") then
	makefolder("Roblox/boss-retry")
end
local CONFIG_FILE_PATH = "Roblox/boss-retry/boss_config.json"
local CYCLE_CFG_PATH = "Roblox/boss-retry/acc_cycle_config.json"

local STALL_CHECK_INTERVAL = 5
local ANTI_AFK_INTERVAL = 30
local BOSS_COOLDOWN_SECONDS = 21600

local START_FLOOR = 3
local END_FLOOR = 25
local TOWER_ID = "light_fairy"
local antiAfkEnabled = false

local fightTowerEvent = ReplicatedStorage["shared/network@eventDefinitions"].fightBattleTowerWave
local fightBossEvent = ReplicatedStorage["shared/network@eventDefinitions"].fightStoryBoss
local setDefaultPartySlotEvent = ReplicatedStorage["shared/network@eventDefinitions"].setDefaultPartySlot
local rewardEvent = ReplicatedStorage["shared/network@eventDefinitions"].notifyRewards
local animationEvent = ReplicatedStorage["shared/network@eventDefinitions"].playBattleAnimation
local dispatchEvent = ReplicatedStorage["shared/network@eventDefinitions"].dispatch
local useItemEvent = ReplicatedStorage["shared/network@eventDefinitions"].useItem

local isRunning = false
local isBattling = false
local currentBattleType = "none"
local animationTurnCount = 0
local battleAttempts = 0
local currentFloor = START_FLOOR
local isBlockingRewards = false
local function rollMoons() end

local moons = {
	{ name = "full_moon",     display = "Full Moon",     tier = 1  },
	{ name = "harvest_moon",  display = "Harvest Moon",  tier = 2  },
	{ name = "snow_moon",     display = "Snow Moon",     tier = 3  },
	{ name = "blood_moon",    display = "Blood Moon",    tier = 4  },
	{ name = "wolf_moon",     display = "Wolf Moon",     tier = 5  },
	{ name = "blue_moon",     display = "Blue Moon",     tier = 6  },
	{ name = "eclipse_moon",  display = "Eclipse Moon",  tier = 7  },
	{ name = "monarch_moon",  display = "Monarch Moon",  tier = 8  },
	{ name = "tsukiyomi_moon",display = "Tsukiyomi Moon",tier = 9  },
	{ name = "inferno_moon",  display = "Inferno Moon",  tier = 10 },
	{ name = "abyss_moon",    display = "Abyss Moon",    tier = 11 }
}
local currentMoon = "None"
local targetMoon = "harvest_moon"
local targetMoonTier = 2
local moonRolling = false
local moonLooping = false
local moonTimeRemaining = 0
local rollCount = 0

local towers = {
	"watery_depths",
	"frozen_landscape",
	"stone_citadel",
	"inferno_depths",
	"lunar_eclipse",
	"light_fairy"
}
local towerCycleConfig = {}
local cycleTowersEnabled = false
local floorOptions = { 5, 10, 15, 20, 25 }

local function floorKey(n) return tostring(n) end

local function saveCycleConfig()
	if not towerCycleConfig then return end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(towerCycleConfig)
	end)
	if ok then
		writefile(CYCLE_CFG_PATH, json)
	else
		warn("CycleConfig: JSON encode failed.")
	end
end

local function loadCycleConfig()
	towerCycleConfig = {}

	if isfile(CYCLE_CFG_PATH) then
		local ok, raw = pcall(readfile, CYCLE_CFG_PATH)
		if ok and raw and raw ~= "" then
			local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
			if ok2 and type(data) == "table" then
				towerCycleConfig = data
			end
		end
	end

	for _, towerName in ipairs(towers) do
		local tcfg = towerCycleConfig[towerName]
		if type(tcfg) ~= "table" then
			tcfg = {}
			towerCycleConfig[towerName] = tcfg
		end
		if type(tcfg.enabled) ~= "boolean" then tcfg.enabled = false end

		local floors = tcfg.floors
		local newFloors = {}

		if type(floors) == "table" then
			local isArray = (#floors > 0)
			if isArray then
				for i, fnum in ipairs(floorOptions) do
					local src = floors[i]
					if type(src) == "table" then
						newFloors[floorKey(fnum)] = {
							enabled  = (src.enabled == true),
							teamSlot = tonumber(src.teamSlot) or 1
						}
					end
				end
			else
				for k, v in pairs(floors) do
					local key = tostring(k)
					local enabled = false
					local teamSlot = 1
					if type(v) == "table" then
						enabled = v.enabled == true
						teamSlot = tonumber(v.teamSlot) or 1
					end
					newFloors[key] = { enabled = enabled, teamSlot = teamSlot }
				end
			end
		end

		for _, fnum in ipairs(floorOptions) do
			local key = floorKey(fnum)
			if not newFloors[key] then
				newFloors[key] = { enabled = false, teamSlot = 1 }
			end
		end

		tcfg.floors = newFloors
	end

	saveCycleConfig()

	print("[CycleConfig] Normalized and loaded:")
	for _, t in ipairs(towers) do
		local f = towerCycleConfig[t] and towerCycleConfig[t].floors or {}
		local ok, encoded = pcall(function() return HttpService:JSONEncode(f) end)
		print(string.format("[CFG] %s floors: %s", t, ok and encoded or "<encode failed>"))
	end
end

local isBossFarming = false
local bossData = {
	[359] = "Bijuu Beast",
	[355] = "Awakened Galactic Tyrant",
	[392] = "King of Curses",
	[327] = "Combat Giant",
	[345] = "Awakened Pale Demon Lord",
	[320] = "Soul Queen",
	[478] = "Awakened Shadow Monarch",
	[297] = "Lord Of Eminence",
	[338] = "Celestial Sovereign",
	[373] = "Undead King",
	[383] = "Substitute Shinigami",
	[313] = "Quincy King"
}

local bossOrder = { 359, 355, 392, 327, 345, 320, 478, 297, 338, 373, 383, 313 }
local bossDifficulties = { "normal", "medium", "hard", "extreme", "nightmare", "celestial" }
local bossConfig = {}

coroutine.wrap(function()
	local keys = { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D }
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
end)()

loadCycleConfig()

for _, towerName in ipairs(towers) do
	local towerConfig = towerCycleConfig[towerName] or { enabled = false, floors = {} }
	towerCycleConfig[towerName] = towerConfig
	if towerConfig.enabled == nil then towerConfig.enabled = false end
	towerConfig.floors = towerConfig.floors or {}

	for _, floorNum in ipairs(floorOptions) do
		local key = floorKey(floorNum)
		local floorConfig = towerConfig.floors[key]
		if not floorConfig then
			towerConfig.floors[key] = { enabled = false, teamSlot = 1 }
		else
			if floorConfig.enabled == nil then floorConfig.enabled = false end
			if floorConfig.teamSlot == nil then floorConfig.teamSlot = 1 end
			floorConfig.teamSlot = tonumber(floorConfig.teamSlot) or 1
		end
	end
end

saveCycleConfig()

local function saveBossConfig()
	local success, encodedData = pcall(HttpService.JSONEncode, HttpService, bossConfig)
	if success then
		writefile(CONFIG_FILE_PATH, encodedData)
	else
		warn("Failed to encode boss configuration.")
	end
end

local function loadBossConfig()
	local defaultConfig = {}
	for id, name in pairs(bossData) do
		defaultConfig[tostring(id)] = { name = name, difficulties = {} }
		for _, diff in ipairs(bossDifficulties) do
			defaultConfig[tostring(id)].difficulties[diff] = { enabled = false, teamSlot = 1, cooldownEnd = 0 }
		end
	end
	if isfile(CONFIG_FILE_PATH) then
		local success, data = pcall(readfile, CONFIG_FILE_PATH)
		if success and data and data ~= "" then
			local decodedSuccess, loadedConfig = pcall(HttpService.JSONDecode, HttpService, data)
			if decodedSuccess then
				for id, bossInfo in pairs(defaultConfig) do
					if loadedConfig[id] then
						for diff, _ in pairs(bossInfo.difficulties) do
							if loadedConfig[id].difficulties and loadedConfig[id].difficulties[diff] then
								defaultConfig[id].difficulties[diff] = loadedConfig[id].difficulties[diff]
							end
						end
					end
				end
				bossConfig = defaultConfig
				return
			end
		end
	end
	bossConfig = defaultConfig
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LunarTowerFarm"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 480)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -240)
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
Title.Text = "ratware"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = Title

MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.new(0, 30, 0, 30)
MinimizeButton.Position = UDim2.new(1, -35, 0, 5)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
MinimizeButton.Text = "-"
MinimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeButton.TextSize = 20
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.Parent = MainFrame

local MinimizeCorner = Instance.new("UICorner")
MinimizeCorner.CornerRadius = UDim.new(0, 6)
MinimizeCorner.Parent = MinimizeButton

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -20, 0, 35)
TabBar.Position = UDim2.new(0, 10, 0, 45)
TabBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
TabBar.BackgroundTransparency = 1
TabBar.Parent = MainFrame

local function createTabButton(name, text, order)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0.32, 0, 1, 0)
	local xPos = (order - 1) * 0.34
	btn.Position = UDim2.new(xPos, 0, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(200, 200, 200)
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamMedium
	btn.BorderSizePixel = 0
	btn.Parent = TabBar
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 190))
	}
	gradient.Parent = btn
	
	return btn
end

local TowerTabButton = createTabButton("Tower", "Tower Farm", 1)
local BossTabButton = createTabButton("Boss", "Boss Farm", 2)
local MoonTabButton = createTabButton("Moon", "Moon Roller", 3)

local BaseFrame = Instance.new("Frame")
BaseFrame.Size = UDim2.new(1, 0, 1, -90) 
BaseFrame.Position = UDim2.new(0, 0, 0, 90)
BaseFrame.BackgroundTransparency = 1
BaseFrame.Parent = MainFrame

local TowerFrame = BaseFrame:Clone()
TowerFrame.Visible = true
TowerFrame.Parent = MainFrame

local BossFrame = BaseFrame:Clone()
BossFrame.Visible = false
BossFrame.Parent = MainFrame

local MoonFrame = BaseFrame:Clone()
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
AntiAfkLabel.Position = UDim2.new(0, 10, 0, 265) 
AntiAfkLabel.BackgroundTransparency = 1
AntiAfkLabel.Text = "Anti-AFK: Disabled"
AntiAfkLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
AntiAfkLabel.TextSize = 12
AntiAfkLabel.Font = Enum.Font.Gotham
AntiAfkLabel.TextXAlignment = Enum.TextXAlignment.Left
AntiAfkLabel.Parent = TowerFrame

local AntiAfkToggle = Instance.new("TextButton")
AntiAfkToggle.Size = UDim2.new(0, 60, 0, 20)
AntiAfkToggle.Position = UDim2.new(1, -70, 0, 265)
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
CycleTowerLabel.Position = UDim2.new(0, 10, 0, 290)
CycleTowerLabel.BackgroundTransparency = 1
CycleTowerLabel.Text = "Cycle Towers"
CycleTowerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
CycleTowerLabel.TextSize = 12
CycleTowerLabel.Font = Enum.Font.Gotham
CycleTowerLabel.TextXAlignment = Enum.TextXAlignment.Left
CycleTowerLabel.Parent = TowerFrame

local CycleTowerToggle = Instance.new("TextButton")
CycleTowerToggle.Size = UDim2.new(0, 60, 0, 20)
CycleTowerToggle.Position = UDim2.new(1, -70, 0, 290) 
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
ConfigCycleButton.Position = UDim2.new(0, 10, 0, 315) 
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

local BossStatusLabel = Instance.new("TextLabel")
BossStatusLabel.Size = UDim2.new(1, -20, 0, 20)
BossStatusLabel.Position = UDim2.new(0, 10, 0, 10)
BossStatusLabel.BackgroundTransparency = 1
BossStatusLabel.Text = "Status: Idle"
BossStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
BossStatusLabel.TextSize = 14
BossStatusLabel.Font = Enum.Font.Gotham
BossStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
BossStatusLabel.Parent = BossFrame

local BossCooldownTitle = Instance.new("TextLabel")
BossCooldownTitle.Size = UDim2.new(1, -20, 0, 20)
BossCooldownTitle.Position = UDim2.new(0, 10, 0, 40)
BossCooldownTitle.BackgroundTransparency = 1
BossCooldownTitle.Text = "Cooldowns:"
BossCooldownTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
BossCooldownTitle.TextSize = 12
BossCooldownTitle.Font = Enum.Font.Gotham
BossCooldownTitle.TextXAlignment = Enum.TextXAlignment.Left
BossCooldownTitle.Parent = BossFrame

local BossCooldownListFrame = Instance.new("ScrollingFrame")
BossCooldownListFrame.Size = UDim2.new(1, -20, 0, 235)
BossCooldownListFrame.Position = UDim2.new(0, 10, 0, 65)
BossCooldownListFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
BossCooldownListFrame.BorderSizePixel = 0
BossCooldownListFrame.ScrollBarThickness = 6
BossCooldownListFrame.Parent = BossFrame

local BossCooldownListCorner = Instance.new("UICorner")
BossCooldownListCorner.CornerRadius = UDim.new(0, 6)
BossCooldownListCorner.Parent = BossCooldownListFrame

local BossCooldownListLayout = Instance.new("UIListLayout")
BossCooldownListLayout.Padding = UDim.new(0, 5)
BossCooldownListLayout.SortOrder = Enum.SortOrder.LayoutOrder
BossCooldownListLayout.Parent = BossCooldownListFrame

local ConfigBossesButton = Instance.new("TextButton")
ConfigBossesButton.Size = UDim2.new(1, -20, 0, 30)
ConfigBossesButton.Position = UDim2.new(0, 10, 0, 310)
ConfigBossesButton.BackgroundColor3 = Color3.fromRGB(50, 100, 150)
ConfigBossesButton.Text = "Configure Bosses"
ConfigBossesButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ConfigBossesButton.TextSize = 13
ConfigBossesButton.Font = Enum.Font.GothamBold
ConfigBossesButton.Parent = BossFrame

local ConfigBossesCorner = Instance.new("UICorner")
ConfigBossesCorner.CornerRadius = UDim.new(0, 6)
ConfigBossesCorner.Parent = ConfigBossesButton

local BossStartButton = Instance.new("TextButton")
BossStartButton.Size = UDim2.new(0.5, -15, 0, 35)
BossStartButton.Position = UDim2.new(0, 10, 1, -45)
BossStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
BossStartButton.Text = "Start"
BossStartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
BossStartButton.TextSize = 14
BossStartButton.Font = Enum.Font.GothamBold
BossStartButton.Parent = BossFrame

local BossStartCorner = Instance.new("UICorner")
BossStartCorner.CornerRadius = UDim.new(0, 6)
BossStartCorner.Parent = BossStartButton

local BossStopButton = Instance.new("TextButton")
BossStopButton.Size = UDim2.new(0.5, -15, 0, 35)
BossStopButton.Position = UDim2.new(0.5, 5, 1, -45)
BossStopButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
BossStopButton.Text = "Stop"
BossStopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
BossStopButton.TextSize = 14
BossStopButton.Font = Enum.Font.GothamBold
BossStopButton.Parent = BossFrame

local BossStopCorner = Instance.new("UICorner")
BossStopCorner.CornerRadius = UDim.new(0, 6)
BossStopCorner.Parent = BossStopButton

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

local RaidMinionToggle = Instance.new("TextButton")
RaidMinionToggle.Size = UDim2.new(1, -20, 0, 30)
RaidMinionToggle.Position = UDim2.new(0, 10, 0, 260)
RaidMinionToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
RaidMinionToggle.Text = "RAID MINION: OFF"
RaidMinionToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
RaidMinionToggle.TextSize = 14
RaidMinionToggle.Font = Enum.Font.GothamBold
RaidMinionToggle.BorderSizePixel = 0
RaidMinionToggle.Parent = MoonFrame

local RaidMinionToggleCorner = Instance.new("UICorner")
RaidMinionToggleCorner.CornerRadius = UDim.new(0, 6)
RaidMinionToggleCorner.Parent = RaidMinionToggle

local BlockRewardsToggle = Instance.new("TextButton")
BlockRewardsToggle.Size = UDim2.new(1, -20, 0, 30)
BlockRewardsToggle.Position = UDim2.new(0, 10, 0, 300)
BlockRewardsToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
BlockRewardsToggle.Text = "BLOCK REWARDS: OFF"
BlockRewardsToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
BlockRewardsToggle.TextSize = 14
BlockRewardsToggle.Font = Enum.Font.GothamBold
BlockRewardsToggle.BorderSizePixel = 0
BlockRewardsToggle.Parent = MoonFrame

local BlockRewardsToggleCorner = Instance.new("UICorner")
BlockRewardsToggleCorner.CornerRadius = UDim.new(0, 6)
BlockRewardsToggleCorner.Parent = BlockRewardsToggle

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

local FloorTeamSlotFrame = Instance.new("Frame")
FloorTeamSlotFrame.Size = UDim2.new(0, 200, 0, 100)
FloorTeamSlotFrame.Position = UDim2.new(0.5, -100, 0.5, -50)
FloorTeamSlotFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
FloorTeamSlotFrame.BorderSizePixel = 0
FloorTeamSlotFrame.Visible = false
FloorTeamSlotFrame.ZIndex = 200
FloorTeamSlotFrame.Parent = ScreenGui

local FloorTeamSlotCorner = Instance.new("UICorner")
FloorTeamSlotCorner.CornerRadius = UDim.new(0, 8)
FloorTeamSlotCorner.Parent = FloorTeamSlotFrame

local FloorTeamSlotTitle = Instance.new("TextLabel")
FloorTeamSlotTitle.Size = UDim2.new(1, 0, 0, 30)
FloorTeamSlotTitle.BackgroundTransparency = 1
FloorTeamSlotTitle.Text = "Set Team Slot"
FloorTeamSlotTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
FloorTeamSlotTitle.Font = Enum.Font.GothamBold
FloorTeamSlotTitle.TextSize = 14
FloorTeamSlotTitle.ZIndex = 201
FloorTeamSlotTitle.Parent = FloorTeamSlotFrame

local FloorTeamSlotInput = Instance.new("TextBox")
FloorTeamSlotInput.Size = UDim2.new(0, 60, 0, 30)
FloorTeamSlotInput.Position = UDim2.new(0.5, -30, 0, 40)
FloorTeamSlotInput.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
FloorTeamSlotInput.Text = "1"
FloorTeamSlotInput.TextColor3 = Color3.fromRGB(255, 255, 255)
FloorTeamSlotInput.Font = Enum.Font.Gotham
FloorTeamSlotInput.TextSize = 14
FloorTeamSlotInput.PlaceholderText = "1-8"
FloorTeamSlotInput.ZIndex = 201
FloorTeamSlotInput.Parent = FloorTeamSlotFrame

local FloorTeamSlotInputCorner = Instance.new("UICorner")
FloorTeamSlotInputCorner.CornerRadius = UDim.new(0, 6)
FloorTeamSlotInputCorner.Parent = FloorTeamSlotInput

local FloorTeamSlotConfirm = Instance.new("TextButton")
FloorTeamSlotConfirm.Size = UDim2.new(0, 80, 0, 25)
FloorTeamSlotConfirm.Position = UDim2.new(0.5, -40, 1, -32)
FloorTeamSlotConfirm.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
FloorTeamSlotConfirm.Text = "OK"
FloorTeamSlotConfirm.TextColor3 = Color3.fromRGB(255, 255, 255)
FloorTeamSlotConfirm.Font = Enum.Font.GothamBold
FloorTeamSlotConfirm.TextSize = 12
FloorTeamSlotConfirm.ZIndex = 201
FloorTeamSlotConfirm.Parent = FloorTeamSlotFrame

local FloorTeamSlotConfirmCorner = Instance.new("UICorner")
FloorTeamSlotConfirmCorner.CornerRadius = UDim.new(0, 6)
FloorTeamSlotConfirmCorner.Parent = FloorTeamSlotConfirm

local currentFloorButton = nil
local currentFloorTower = nil
local currentFloorNumber = nil

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
	TowerNameLabel.Text = towerName:gsub("_"," "):upper()
	TowerNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TowerNameLabel.TextSize = 14
	TowerNameLabel.Font = Enum.Font.GothamBold
	TowerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	TowerNameLabel.ZIndex = 102
	TowerNameLabel.Parent = TowerConfigFrame

	local TowerEnableButton = Instance.new("TextButton")
	TowerEnableButton.Size = UDim2.new(0, 60, 0, 20)
	TowerEnableButton.Position = UDim2.new(1, -70, 0, 7.5)
	TowerEnableButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	TowerEnableButton.Text = (towerCycleConfig[towerName].enabled and "ON" or "OFF")
	if towerCycleConfig[towerName].enabled then
		TowerEnableButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
	end
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
		saveCycleConfig()
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

		local key = floorKey(floor)
		local floorConfig = towerCycleConfig[towerName].floors[key]
		if floorConfig.enabled then
			FloorButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
		end

		FloorButton.MouseButton1Click:Connect(function()
			floorConfig.enabled = not floorConfig.enabled
			if floorConfig.enabled then
				FloorButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
			else
				FloorButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
			end
			saveCycleConfig()
		end)

		FloorButton.MouseButton2Click:Connect(function()
			currentFloorButton = FloorButton
			currentFloorTower = towerName
			currentFloorNumber = floor
			FloorTeamSlotInput.Text = tostring(floorConfig.teamSlot or 1)
			FloorTeamSlotFrame.Visible = true
		end)
	end
end

CycleScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #towers * 100)

local BossConfigFrame = Instance.new("Frame")
BossConfigFrame.Size = UDim2.new(0, 420, 0, 500)
BossConfigFrame.Position = UDim2.new(0.5, -210, 0.5, -250)
BossConfigFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
BossConfigFrame.BorderSizePixel = 0
BossConfigFrame.Visible = false
BossConfigFrame.ZIndex = 100
BossConfigFrame.Parent = ScreenGui

local BossConfigCorner = Instance.new("UICorner")
BossConfigCorner.CornerRadius = UDim.new(0, 10)
BossConfigCorner.Parent = BossConfigFrame

local BossConfigTitle = Instance.new("TextLabel")
BossConfigTitle.Size = UDim2.new(1, 0, 0, 40)
BossConfigTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
BossConfigTitle.Text = "Configure Bosses"
BossConfigTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
BossConfigTitle.TextSize = 14
BossConfigTitle.Font = Enum.Font.GothamBold
BossConfigTitle.ZIndex = 101
BossConfigTitle.Parent = BossConfigFrame

local BossConfigTitleCorner = Instance.new("UICorner")
BossConfigTitleCorner.CornerRadius = UDim.new(0, 10)
BossConfigTitleCorner.Parent = BossConfigTitle

local CloseBossConfigButton = Instance.new("TextButton")
CloseBossConfigButton.Size = UDim2.new(0, 30, 0, 30)
CloseBossConfigButton.Position = UDim2.new(1, -35, 0, 5)
CloseBossConfigButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
CloseBossConfigButton.Text = "X"
CloseBossConfigButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBossConfigButton.TextSize = 16
CloseBossConfigButton.Font = Enum.Font.GothamBold
CloseBossConfigButton.ZIndex = 102
CloseBossConfigButton.Parent = BossConfigFrame

local CloseBossConfigCorner = Instance.new("UICorner")
CloseBossConfigCorner.CornerRadius = UDim.new(0, 6)
CloseBossConfigCorner.Parent = CloseBossConfigButton

local BossConfigScrollFrame = Instance.new("ScrollingFrame")
BossConfigScrollFrame.Size = UDim2.new(1, -20, 1, -50)
BossConfigScrollFrame.Position = UDim2.new(0, 10, 0, 50)
BossConfigScrollFrame.BackgroundTransparency = 1
BossConfigScrollFrame.BorderSizePixel = 0
BossConfigScrollFrame.ScrollBarThickness = 6
BossConfigScrollFrame.ZIndex = 101
BossConfigScrollFrame.Parent = BossConfigFrame

local BossConfigListLayout = Instance.new("UIListLayout")
BossConfigListLayout.Padding = UDim.new(0, 10)
BossConfigListLayout.SortOrder = Enum.SortOrder.LayoutOrder
BossConfigListLayout.Parent = BossConfigScrollFrame

local function populateBossConfigUI()
	for _, child in ipairs(BossConfigScrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	for index, id in ipairs(bossOrder) do
		local boss = bossConfig[tostring(id)]
		if boss then
			local BFrame = Instance.new("Frame")
			BFrame.Name = boss.name

			BFrame.Size = UDim2.new(1, 0, 0, 140) 
			BFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
			BFrame.LayoutOrder = index
			BFrame.ZIndex = 102
			BFrame.Parent = BossConfigScrollFrame

			local BFrameCorner = Instance.new("UICorner")
			BFrameCorner.CornerRadius = UDim.new(0, 8)
			BFrameCorner.Parent = BFrame
			
			local BStroke = Instance.new("UIStroke")
			BStroke.Color = Color3.fromRGB(60, 60, 70)
			BStroke.Thickness = 1
			BStroke.Parent = BFrame

			local BName = Instance.new("TextLabel")
			BName.Size = UDim2.new(1, -20, 0, 25)
			BName.Position = UDim2.new(0, 10, 0, 5)
			BName.BackgroundTransparency = 1
			BName.Text = boss.name:upper()
			BName.TextColor3 = Color3.fromRGB(255, 255, 255)
			BName.Font = Enum.Font.GothamBold
			BName.TextSize = 14
			BName.TextXAlignment = Enum.TextXAlignment.Left
			BName.ZIndex = 103
			BName.Parent = BFrame


			local GridContainer = Instance.new("Frame")
			GridContainer.Size = UDim2.new(1, -20, 1, -35)
			GridContainer.Position = UDim2.new(0, 10, 0, 30)
			GridContainer.BackgroundTransparency = 1
			GridContainer.ZIndex = 103
			GridContainer.Parent = BFrame

			local UIGrid = Instance.new("UIGridLayout")
			UIGrid.CellSize = UDim2.new(0.5, -5, 0, 30) 
			UIGrid.CellPadding = UDim2.new(0, 10, 0, 5)
			UIGrid.SortOrder = Enum.SortOrder.LayoutOrder
			UIGrid.Parent = GridContainer

			local displayOrder = {"normal", "extreme", "medium", "nightmare", "hard", "celestial"}

			for i, diff in ipairs(displayOrder) do
				local diffConfig = boss.difficulties[diff]

				local DFrame = Instance.new("Frame")
				DFrame.BackgroundTransparency = 1
				DFrame.ZIndex = 103
				DFrame.LayoutOrder = i
				DFrame.Parent = GridContainer

				local DLabel = Instance.new("TextLabel")
				DLabel.Size = UDim2.new(0, 60, 1, 0)
				DLabel.Position = UDim2.new(0, 0, 0, 0)
				DLabel.BackgroundTransparency = 1
				DLabel.Text = diff:sub(1,1):upper()..diff:sub(2)
				DLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
				DLabel.Font = Enum.Font.Gotham
				DLabel.TextSize = 11
				DLabel.TextXAlignment = Enum.TextXAlignment.Left
				DLabel.ZIndex = 104
				DLabel.Parent = DFrame

				local DToggle = Instance.new("TextButton")
				DToggle.Size = UDim2.new(0, 30, 0, 20)
				DToggle.Position = UDim2.new(0, 60, 0.5, -10)
				DToggle.Text = diffConfig.enabled and "ON" or "OFF"
				DToggle.BackgroundColor3 = diffConfig.enabled and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(80, 80, 90)
				DToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
				DToggle.Font = Enum.Font.GothamBold
				DToggle.TextSize = 10
				DToggle.ZIndex = 104
				DToggle.Parent = DFrame

				local DToggleCorner = Instance.new("UICorner")
				DToggleCorner.CornerRadius = UDim.new(0, 4)
				DToggleCorner.Parent = DToggle

				DToggle.MouseButton1Click:Connect(function()
					diffConfig.enabled = not diffConfig.enabled
					DToggle.Text = diffConfig.enabled and "ON" or "OFF"
					DToggle.BackgroundColor3 = diffConfig.enabled and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(80, 80, 90)
					saveBossConfig()
				end)

				local TeamInput = Instance.new("TextBox")
				TeamInput.Size = UDim2.new(0, 30, 0, 20)
				TeamInput.Position = UDim2.new(1, -30, 0.5, -10)
				TeamInput.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
				TeamInput.Text = tostring(diffConfig.teamSlot)
				TeamInput.TextColor3 = Color3.fromRGB(255, 255, 255)
				TeamInput.Font = Enum.Font.Gotham
				TeamInput.TextSize = 11
				TeamInput.PlaceholderText = "#"
				TeamInput.ClearTextOnFocus = false
				TeamInput.ZIndex = 104
				TeamInput.Parent = DFrame
				
				local TeamInputCorner = Instance.new("UICorner")
				TeamInputCorner.CornerRadius = UDim.new(0, 4)
				TeamInputCorner.Parent = TeamInput
				
				local TeamLabel = Instance.new("TextLabel")
				TeamLabel.Size = UDim2.new(0, 30, 1, 0)
				TeamLabel.Position = UDim2.new(1, -65, 0, 0)
				TeamLabel.BackgroundTransparency = 1
				TeamLabel.Text = "Slot:"
				TeamLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
				TeamLabel.Font = Enum.Font.Gotham
				TeamLabel.TextSize = 10
				TeamLabel.TextXAlignment = Enum.TextXAlignment.Right
				TeamLabel.ZIndex = 104
				TeamLabel.Parent = DFrame

				TeamInput.FocusLost:Connect(function(enterPressed)
					local num = tonumber(TeamInput.Text)
					if num and num >= 1 and num <= 8 then
						diffConfig.teamSlot = math.floor(num)
					end
					TeamInput.Text = tostring(diffConfig.teamSlot)
					saveBossConfig()
				end)
			end
		end
	end
	BossConfigScrollFrame.CanvasSize = UDim2.new(0, 0, 0, BossConfigListLayout.AbsoluteContentSize.Y + 20)
end

local isMinimized = false

local function makeDraggable(titleElement, frameElement)
	local state = {
		dragging = false,
		dragInput = nil,
		dragStart = Vector2.new(),
		startPos = UDim2.new()
	}
	titleElement.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.dragging = true
			state.dragStart = input.Position
			state.startPos = frameElement.Position
		end
	end)
	titleElement.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			state.dragInput = input
		end
	end)
	titleElement.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.dragging = false
		end
	end)
	return state
end

local mainDragState = makeDraggable(Title, MainFrame)
local cycleDragState = makeDraggable(CycleConfigTitle, CycleConfigFrame)
local bossDragState = makeDraggable(BossConfigTitle, BossConfigFrame)

game:GetService("UserInputService").InputChanged:Connect(function(input)
	if mainDragState.dragging and input == mainDragState.dragInput then
		local delta = input.Position - mainDragState.dragStart
		MainFrame.Position = UDim2.new(mainDragState.startPos.X.Scale, mainDragState.startPos.X.Offset + delta.X, mainDragState.startPos.Y.Scale, mainDragState.startPos.Y.Offset + delta.Y)
	end
	if cycleDragState.dragging and input == cycleDragState.dragInput then
		local delta = input.Position - cycleDragState.dragStart
		CycleConfigFrame.Position = UDim2.new(cycleDragState.startPos.X.Scale, cycleDragState.startPos.X.Offset + delta.X, cycleDragState.startPos.Y.Scale, cycleDragState.startPos.Y.Offset + delta.Y)
	end
	if bossDragState.dragging and input == bossDragState.dragInput then
		local delta = input.Position - bossDragState.dragStart
		BossConfigFrame.Position = UDim2.new(bossDragState.startPos.X.Scale, bossDragState.startPos.X.Offset + delta.X, bossDragState.startPos.Y.Scale, bossDragState.startPos.Y.Offset + delta.Y)
	end
end)

FloorTeamSlotConfirm.MouseButton1Click:Connect(function()
	local num = tonumber(FloorTeamSlotInput.Text)
	if num and num >= 1 and num <= 8 and currentFloorTower and currentFloorNumber then
		local fk = floorKey(currentFloorNumber)
		local floorConfig = towerCycleConfig[currentFloorTower].floors[fk]
		floorConfig.teamSlot = math.floor(num)
		saveCycleConfig()
		FloorTeamSlotFrame.Visible = false
	else
		FloorTeamSlotInput.Text = "1-8"
	end
end)

game:GetService("UserInputService").InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape and FloorTeamSlotFrame.Visible then
		FloorTeamSlotFrame.Visible = false
	end
end)

ConfigCycleButton.MouseButton1Click:Connect(function()
	CycleConfigFrame.Visible = true
end)

CloseCycleConfigButton.MouseButton1Click:Connect(function()
	CycleConfigFrame.Visible = false
	saveCycleConfig()
end)

ConfigBossesButton.MouseButton1Click:Connect(function()
	populateBossConfigUI()
	BossConfigFrame.Visible = true 
end)

CloseBossConfigButton.MouseButton1Click:Connect(function()
	BossConfigFrame.Visible = false
	saveBossConfig()
end)

local function setActiveTab(activeTab)
	local tabs = { Tower = TowerTabButton, Boss = BossTabButton, Moon = MoonTabButton }
	local frames = { Tower = TowerFrame, Boss = BossFrame, Moon = MoonFrame }
	for name, button in pairs(tabs) do
		local isActive = (name == activeTab)
		button.BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(35, 35, 45)
		button.TextColor3 = isActive and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 150)
		button.Font = isActive and Enum.Font.GothamBold or Enum.Font.GothamMedium
		
		button:TweenSize(UDim2.new(0.32, 0, 1, isActive and 2 or 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
		
		frames[name].Visible = isActive
	end
end

TowerTabButton.MouseButton1Click:Connect(function() setActiveTab("Tower") end)
BossTabButton.MouseButton1Click:Connect(function()  setActiveTab("Boss")  end)
MoonTabButton.MouseButton1Click:Connect(function()  setActiveTab("Moon")  end)

MinimizeButton.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	local targetSize = isMinimized and UDim2.new(0, 320, 0, 40) or UDim2.new(0, 320, 0, 480)
	TabBar.Visible = not isMinimized
	if not isMinimized then
		TowerFrame.Visible = (TowerTabButton.BackgroundColor3 == Color3.fromRGB(45, 45, 55))
		BossFrame.Visible  = (BossTabButton.BackgroundColor3 == Color3.fromRGB(45, 45, 55))
		MoonFrame.Visible  = (MoonTabButton.BackgroundColor3 == Color3.fromRGB(45, 45, 55))
	else
		TowerFrame.Visible, BossFrame.Visible, MoonFrame.Visible = false, false, false
	end
	MainFrame:TweenSize(targetSize, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
	MinimizeButton.Text = isMinimized and "+" or "-"
end)

AntiAfkToggle.MouseButton1Click:Connect(function()
	antiAfkEnabled = not antiAfkEnabled
	AntiAfkToggle.Text = antiAfkEnabled and "ON" or "OFF"
	AntiAfkToggle.BackgroundColor3 = antiAfkEnabled and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(150, 50, 50)
	AntiAfkLabel.Text = "Anti-AFK: " .. (antiAfkEnabled and "Active (30s)" or "Disabled")
	AntiAfkLabel.TextColor3 = antiAfkEnabled and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
end)

CycleTowerToggle.MouseButton1Click:Connect(function()
	cycleTowersEnabled = not cycleTowersEnabled
	CycleTowerToggle.Text = cycleTowersEnabled and "ON" or "OFF"
	CycleTowerToggle.BackgroundColor3 = cycleTowersEnabled and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(45, 45, 55)
	CycleTowerLabel.TextColor3 = cycleTowersEnabled and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 200, 200)
end)

LoopToggle.MouseButton1Click:Connect(function()
	moonLooping = not moonLooping
	LoopToggle.Text = "Loop: " .. (moonLooping and "ON" or "OFF")
	LoopToggle.BackgroundColor3 = moonLooping and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(45, 45, 55)
end)

BlockRewardsToggle.MouseButton1Click:Connect(function()
	isBlockingRewards = not isBlockingRewards
	BlockRewardsToggle.Text = isBlockingRewards and "BLOCK REWARDS: ON" or "BLOCK REWARDS: OFF"
	BlockRewardsToggle.BackgroundColor3 = isBlockingRewards and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(45, 45, 55)
end)

animationEvent.OnClientEvent:Connect(function()
	if isBattling then
		animationTurnCount = animationTurnCount + 1
		if currentBattleType == "tower" then
			TurnsLabel.Text = "Turns: " .. animationTurnCount
		end
	end
end)

rewardEvent.OnClientEvent:Connect(function(rewards)
	if not isBattling or (not isRunning and not isBossFarming) then
		return
	end
	if rewards and type(rewards) == "table" and #rewards > 0 then
		if currentBattleType == "tower" then
			isBattling = false
			StatusLabel.Text = "Status: Floor " .. currentFloor .. " COMPLETED!"
			StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			battleAttempts = 0
		elseif currentBattleType == "boss" then
			isBattling = false
		end
	end
end)

local function monitorBattle()
	while isBattling and (isRunning or isBossFarming) do
		local turnsBeforeWait = animationTurnCount
		if currentBattleType == "tower" then
			StatusLabel.Text = "Status: Battle in progress (Floor " .. currentFloor .. ")..."
		end
		wait(STALL_CHECK_INTERVAL)
		if isBattling and (isRunning or isBossFarming) then
			if animationTurnCount == turnsBeforeWait then
				if currentBattleType == "tower" then
					StatusLabel.Text = "Status: Stalled! Retrying floor " .. currentFloor .. "..."
					fightTowerEvent:FireServer(TOWER_ID, currentFloor)
				elseif currentBattleType == "boss" then
					isBattling = false
					BossStatusLabel.Text = "Status: Battle stalled! Stopping..."
					isBossFarming = false
					BossStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
				end
			end
		end
	end
end

local function towerFarmLoop()
	if cycleTowersEnabled then
		for _, towerName in ipairs(towers) do
			if not isRunning then break end
			local config = towerCycleConfig[towerName]
			if config.enabled then
				local floorsToRun = {}
				for _, fnum in ipairs(floorOptions) do
					local fc = config.floors[floorKey(fnum)]
					if fc and fc.enabled then
						table.insert(floorsToRun, { floor = fnum, teamSlot = fc.teamSlot or 1 })
					end
				end
				if #floorsToRun > 0 then
					TOWER_ID = towerName
					StatusLabel.Text = "Status: Cycling to " .. towerName:gsub("_", " ")
					wait(2)
					for _, floorData in ipairs(floorsToRun) do
						if not isRunning then break end
						currentFloor = floorData.floor
						StatusLabel.Text = "Status: Switching to Team " .. floorData.teamSlot
						setDefaultPartySlotEvent:FireServer("slot_" .. tostring(floorData.teamSlot))
						wait(1.5)
						FloorLabel.Text = "Current Floor: " .. currentFloor .. " (" .. TOWER_ID:gsub("_", " ") .. ")"
						battleAttempts = 0
						currentBattleType = "tower"
						animationTurnCount = 0
						isBattling = true
						fightTowerEvent:FireServer(TOWER_ID, floorData.floor)
						coroutine.wrap(monitorBattle)()
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
			StartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
		end
	else
		local startF = tonumber(StartFloorInput.Text) or 3
		local endF = tonumber(EndFloorInput.Text) or 25
		currentFloor = startF
		while isRunning and currentFloor <= endF do
			FloorLabel.Text = "Current Floor: " .. currentFloor
			currentBattleType = "tower"
			animationTurnCount = 0
			isBattling = true
			fightTowerEvent:FireServer(TOWER_ID, currentFloor)
			coroutine.wrap(monitorBattle)()
			while isBattling and isRunning do
				wait(1)
			end
			if isRunning then
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

local function bossFarmLoop()
	while isBossFarming do
		local foughtBoss = false
		local nextCooldown = math.huge
		for _, id in ipairs(bossOrder) do
			if not isBossFarming then break end
			local boss = bossConfig[tostring(id)]
			if boss then
				for _, diff in ipairs(bossDifficulties) do
					if not isBossFarming then break end
					local diffConfig = boss.difficulties[diff]
					if diffConfig.enabled then
						if os.time() >= diffConfig.cooldownEnd then
							BossStatusLabel.Text = string.format("Switching to Team %d...", diffConfig.teamSlot)
							setDefaultPartySlotEvent:FireServer("slot_" .. tostring(diffConfig.teamSlot))
							wait(1.5)
							BossStatusLabel.Text = string.format("Fighting %s (%s)...", boss.name, diff)
							currentBattleType = "boss"
							isBattling = true
							animationTurnCount = 0
							fightBossEvent:FireServer(id, diff)
							coroutine.wrap(monitorBattle)()
							while isBattling and isBossFarming do
								wait(1)
							end
							if not isBossFarming then break end
							diffConfig.cooldownEnd = os.time() + BOSS_COOLDOWN_SECONDS
							saveBossConfig()
							foughtBoss = true
							BossStatusLabel.Text = string.format("Defeated %s! Cooldown started.", boss.name)
							wait(2)
							break
						else
							if diffConfig.cooldownEnd < nextCooldown then
								nextCooldown = diffConfig.cooldownEnd
							end
						end
					end
				end
				if foughtBoss then break end
			end
		end
		if not isBossFarming then break end
		if not foughtBoss then
			if nextCooldown == math.huge then
				BossStatusLabel.Text = "Status: No bosses enabled. Stopping."
				isBossFarming = false
				BossStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
			else
				local waitTime = nextCooldown - os.time()
				if waitTime > 0 then
					BossStatusLabel.Text = string.format("Waiting for next cooldown... (~%d min)", math.ceil(waitTime / 60))
					wait(waitTime)
				end
			end
		end
	end
end

coroutine.wrap(function()
	local cooldownLabels = {}
	while true do
		wait(1)
		if BossFrame.Visible then
			local activeCooldowns = {}
			for id, boss in pairs(bossConfig) do
				for diff, diffConfig in pairs(boss.difficulties) do
					if diffConfig.cooldownEnd > os.time() then
						table.insert(activeCooldowns, { name = boss.name, diff = diff, endTime = diffConfig.cooldownEnd })
					end
				end
			end
			table.sort(activeCooldowns, function(a, b) return a.endTime < b.endTime end)
			for i = 1, math.max(#activeCooldowns, #cooldownLabels) do
				local cd = activeCooldowns[i]
				local label = cooldownLabels[i]
				if cd and not label then
					label = Instance.new("TextLabel")
					label.Size = UDim2.new(1, -10, 0, 20)
					label.BackgroundTransparency = 1
					label.TextColor3 = Color3.fromRGB(220, 220, 220)
					label.Font = Enum.Font.Gotham
					label.TextSize = 12
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.Parent = BossCooldownListFrame
					cooldownLabels[i] = label
				end
				if cd and label then
					label.Visible = true
					local remaining = cd.endTime - os.time()
					local hours = math.floor(remaining / 3600)
					local minutes = math.floor((remaining % 3600) / 60)
					label.Text = string.format("%s (%s): %02dh %02dm", cd.name, cd.diff:sub(1,1), hours, minutes)
				elseif label then
					label.Visible = false
				end
			end
			BossCooldownListFrame.CanvasSize = UDim2.fromOffset(0, BossCooldownListLayout.AbsoluteContentSize.Y)
		end
	end
end)()

StartButton.MouseButton1Click:Connect(function()
	if not isRunning then
		TOWER_ID = TowerDropdown.Text
		START_FLOOR = tonumber(StartFloorInput.Text) or 3
		END_FLOOR = tonumber(EndFloorInput.Text) or 25
		isRunning = true
		StartButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		coroutine.wrap(towerFarmLoop)()
	end
end)

StopButton.MouseButton1Click:Connect(function()
	isRunning = false
	isBattling = false
	StatusLabel.Text = "Status: Stopped"
	StartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
end)

BossStartButton.MouseButton1Click:Connect(function()
	if not isBossFarming then
		isBossFarming = true
		BossStatusLabel.Text = "Status: Starting boss farm..."
		BossStartButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		coroutine.wrap(bossFarmLoop)()
	end
end)

BossStopButton.MouseButton1Click:Connect(function()
	isBossFarming = false
	isBattling = false
	BossStatusLabel.Text = "Status: Stopped"
	BossStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
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

local function rollMoons()
	if moonRolling then return end
	moonRolling = true
	rollCount = 0
	RollCountLabel.Text = "Rolls Used: 0"
	MoonStatusLabel.Text = "Status: Rolling for " .. getMoonDisplay(targetMoon) .. "..."
	while moonRolling do
		local currentTier = getMoonTier(currentMoon)
		if currentTier >= targetMoonTier then
			if currentTier == targetMoonTier then
				MoonStatusLabel.Text = "Status: Target moon reached!"
			else
				MoonStatusLabel.Text = "Status: Higher tier moon! Stopping..."
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
	MoonStartButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
end)

local isRaidFarmingEnabled = false
local RAID_CONFIG = {
	MINION_NAMES = { "infernal_demon", "infernal" },
	SCAN_INTERVAL = 0.2,
	PENDING_COMBAT_TIMEOUT = 4.0,
	PROXIMITY_RANGE_OVERRIDE = 99999
}

local combatState = "IDLE"
local pendingStartTime = 0

local battleEndEvent = ReplicatedStorage["shared/network@eventDefinitions"].showBattleEndScreen

local raidMinionNameSet = {}
for _, name in ipairs(RAID_CONFIG.MINION_NAMES) do
	raidMinionNameSet[name] = true
end

animationEvent.OnClientEvent:Connect(function()
	if combatState == "PENDING" then
		combatState = "IN_COMBAT"
	end
end)

battleEndEvent.OnClientEvent:Connect(function()
	if combatState ~= "IDLE" then
		combatState = "IDLE"
	end
end)

RaidMinionToggle.MouseButton1Click:Connect(function()
	isRaidFarmingEnabled = not isRaidFarmingEnabled
	if isRaidFarmingEnabled then
		RaidMinionToggle.Text = "RAID MINION: ON"
		RaidMinionToggle.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
	else
		RaidMinionToggle.Text = "RAID MINION: OFF"
		RaidMinionToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
		combatState = "IDLE"
	end
end)

coroutine.wrap(function()
	while true do
		task.wait(RAID_CONFIG.SCAN_INTERVAL)
		if combatState == "IDLE" and isRaidFarmingEnabled then
			for _, model in ipairs(game:GetService("Workspace"):GetDescendants()) do
				if model:IsA("Model") and raidMinionNameSet[model.Name] then
					local prompt = model:FindFirstChildOfClass("ProximityPrompt")
					if prompt then
						local originalDistance = prompt.MaxActivationDistance
						prompt.MaxActivationDistance = RAID_CONFIG.PROXIMITY_RANGE_OVERRIDE
						fireproximityprompt(prompt)
						prompt.MaxActivationDistance = originalDistance
						combatState = "PENDING"
						pendingStartTime = os.clock()
						break
					end
				end
			end
		elseif combatState == "PENDING" then
			if os.clock() - pendingStartTime > RAID_CONFIG.PENDING_COMBAT_TIMEOUT then
				combatState = "IDLE"
			end
		end
	end
end)()

local function setupRewardBlocker()
	local success, err = pcall(function()
		local event = ReplicatedStorage:WaitForChild("shared/network@eventDefinitions", 20):WaitForChild("notifyRewards", 20)
		for _, connection in pairs(getconnections(event.OnClientEvent)) do
			local originalFunction = connection.Function
			connection:Disable()
			event.OnClientEvent:Connect(function(...)
				if not isBlockingRewards then
					originalFunction(...)
				end
			end)
		end
	end)
	if not success then
		warn("Reward Blocker: Failed to initialize. Error:", err)
	else
		print("Reward Blocker: Hooked successfully.")
	end
end

loadBossConfig()
populateBossConfigUI()
setActiveTab("Tower")
setupRewardBlocker()
