--[[
	// FileName: ShiftLockController
	// Written by: jmargh
	// Description: Manages the state of shift lock mode
	
	// Required by:
		RootCamera
--]]
local ContextActionService = game:GetService('ContextActionService')
local Players = game:GetService('Players')
local StarterPlayer = game:GetService('StarterPlayer')
local UserInputService = game:GetService('UserInputService')
-- Settings and GameSettings are read only
local Settings = UserSettings()	-- ignore warning
local GameSettings = Settings.GameSettings

local ShiftLockController = {}

--[[ Script Variables ]]--
while not Players.LocalPlayer do
	wait()
end
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local PlayerGui = LocalPlayer:WaitForChild('PlayerGui')
local ScreenGui = nil
local ShiftLockIcon = nil
local IsShiftLockMode = false
local IsShiftLocked = false
local IsActionBound = false

-- wrapping long conditional in function
local function isShiftLockMode()
	return LocalPlayer.DevEnableMouseLock and GameSettings.ControlMode == Enum.ControlMode.MouseLockSwitch and
			LocalPlayer.DevComputerMovementMode ~= Enum.DevComputerMovementMode.ClickToMove and
			GameSettings.ComputerMovementMode ~= Enum.ComputerMovementMode.ClickToMove and
			LocalPlayer.DevComputerMovementMode ~= Enum.DevComputerMovementMode.Scriptable
end

if not UserInputService.TouchEnabled then	-- TODO: Remove when safe on mobile
	IsShiftLockMode = isShiftLockMode()
end

--[[ Constants ]]--
local SHIFT_LOCK_OFF = 'rbxasset://textures/ui/mouseLock_off.png'
local SHIFT_LOCK_ON = 'rbxasset://textures/ui/mouseLock_on.png'
local SHIFT_LOCK_CURSOR = 'rbxasset://textures/MouseLockedCursor.png'

--[[ Local Functions ]]--
local function onShiftLockToggled()
	IsShiftLocked = not IsShiftLocked
	if IsShiftLocked then
		ShiftLockIcon.Image = SHIFT_LOCK_ON
		Mouse.Icon = SHIFT_LOCK_CURSOR
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		ShiftLockIcon.Image = SHIFT_LOCK_OFF
		Mouse.Icon = ""
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function initialize()
	if ScreenGui then
		ScreenGui:Destroy()
		ScreenGui = nil
	end
	ScreenGui = Instance.new('ScreenGui')
	ScreenGui.Name = "ControlGui"
	
	local frame = Instance.new('Frame')
	frame.Name = "BottomLeftControl"
	frame.Size = UDim2.new(0, 130, 0, 46)
	frame.Position = UDim2.new(0, 0, 1, -46)
	frame.BackgroundTransparency = 1
	frame.Parent = ScreenGui
	
	ShiftLockIcon = Instance.new('ImageButton')
	ShiftLockIcon.Name = "MouseLockLabel"
	ShiftLockIcon.Size = UDim2.new(0, 62, 0, 62)
	ShiftLockIcon.Position = UDim2.new(0, 2, 0, -65)
	ShiftLockIcon.BackgroundTransparency = 1
	ShiftLockIcon.Image = IsShiftLocked and SHIFT_LOCK_ON or SHIFT_LOCK_OFF
	ShiftLockIcon.Visible = IsShiftLockMode
	ShiftLockIcon.Parent = frame
	
	ShiftLockIcon.MouseButton1Click:connect(onShiftLockToggled)
	
	ScreenGui.Parent = PlayerGui
end

--[[ Public API ]]--
function ShiftLockController:IsShiftLocked()
	return IsShiftLockMode and IsShiftLocked
end

--[[ Input/Settings Changed Events ]]--
local mouseLockSwitchFunc = function(actionName, inputState, inputObject)
	if IsShiftLockMode and inputState == Enum.UserInputState.Begin then
		onShiftLockToggled()
	end
end

local function disableShiftLock()
	if ShiftLockIcon then ShiftLockIcon.Visible = false end
	IsShiftLockMode = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	Mouse.Icon = ""
	ContextActionService:UnbindAction("ToggleShiftLock")
	IsActionBound = false
end

local function enableShiftLock()
	IsShiftLockMode = isShiftLockMode()
	if IsShiftLockMode then
		if ShiftLockIcon then
			ShiftLockIcon.Visible = true
		end
		if IsShiftLocked then
			Mouse.Icon = SHIFT_LOCK_CURSOR
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if not IsActionBound then
			ContextActionService:BindActionToInputTypes("ToggleShiftLock", mouseLockSwitchFunc, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
			IsActionBound = true
		end
	end
end

-- NOTE: This will fire for ControlMode when the settings menu is closed. If ControlMode is
-- MouseLockSwitch on settings close, it will change the mode to Classic, then to ShiftLockSwitch.
-- This is a silly hack, but needed to raise an event when the settings menu closes.
GameSettings.Changed:connect(function(property)
	if property == 'ControlMode' then
		if GameSettings.ControlMode == Enum.ControlMode.MouseLockSwitch then
			enableShiftLock()
		else
			disableShiftLock()
		end
	elseif property == 'ComputerMovementMode' then
		if GameSettings.ComputerMovementMode == Enum.ComputerMovementMode.ClickToMove then
			disableShiftLock()
		else
			enableShiftLock()
		end
	end
end)

LocalPlayer.Changed:connect(function(property)
	if property == 'DevEnableMouseLock' then
		if LocalPlayer.DevEnableMouseLock then
			enableShiftLock()
		else
			disableShiftLock()
		end
	elseif property == 'DevComputerMovementMode' then
		if LocalPlayer.DevComputerMovementMode == Enum.DevComputerMovementMode.ClickToMove or
			LocalPlayer.DevComputerMovementMode == Enum.DevComputerMovementMode.Scriptable then
			--
			disableShiftLock()
		else
			enableShiftLock()
		end
	end
end)

LocalPlayer.CharacterAdded:connect(function(character)
	-- we need to recreate guis on character load
	if not UserInputService.TouchEnabled then
		initialize()
	end
end)

--[[ Initialization ]]--
if not UserInputService.TouchEnabled then -- TODO: Remove when safe!
	initialize()
	if isShiftLockMode() then
		ContextActionService:BindActionToInputTypes("ToggleShiftLock", mouseLockSwitchFunc, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
		IsActionBound = true
	end
end

return ShiftLockController
