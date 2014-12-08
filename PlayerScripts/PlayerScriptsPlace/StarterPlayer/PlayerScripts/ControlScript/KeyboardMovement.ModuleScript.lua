--[[
	// FileName: ComputerMovementKeyboardMovement
	// Written by: jeditkacheff
	// Description: Implements movement controls for keyboard devices
--]]
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')
local StarterPlayer = game:GetService('StarterPlayer')
local Settings = UserSettings()
local GameSettings = Settings.GameSettings

local KeyboardMovement = {}

while not Players.LocalPlayer do
	wait()
end
local LocalPlayer = Players.LocalPlayer
local CachedHumanoid = nil
local RenderSteppedCon = nil

--[[ Local Functions ]]--
local function getHumanoid()
	local character = LocalPlayer and LocalPlayer.Character
	if character then
		if CachedHumanoid and CachedHumanoid.Parent == character then
			return CachedHumanoid
		else
			CachedHumanoid = nil
			for _,child in pairs(character:GetChildren()) do
				if child:IsA('Humanoid') then
					CachedHumanoid = child
					return CachedHumanoid
				end
			end
		end
	end
end

--[[ Public API ]]--
function KeyboardMovement:Enable()
	if not UserInputService.KeyboardEnabled then
		return
	end
	
	local forwardValue  = 0
	local backwardValue = 0
	local leftValue = 0
	local rightValue = 0
	
	local isJumping = false
	local moveFunc = LocalPlayer.Move
	
	local function isFirstPersonOrShiftLocked()
		-- Mouse behavior is being set by the camera script. So be warned that if you
		-- modify that script or implement a new camera, this may not work.
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			return true
		end
	end
	
	local moveForwardFunc = function(actionName, inputState, inputObject)
		if inputState == Enum.UserInputState.Begin then
			forwardValue = -1
		elseif inputState == Enum.UserInputState.End then
			forwardValue = 0
		end
	end
	
	local moveBackwardFunc = function(actionName, inputState, inputObject)	
		if inputState == Enum.UserInputState.Begin then
			backwardValue = 1
		elseif inputState == Enum.UserInputState.End then
			backwardValue = 0
		end
	end
	
	local moveLeftFunc = function(actionName, inputState, inputObject)	
		if inputState == Enum.UserInputState.Begin then
			leftValue = -1
		elseif inputState == Enum.UserInputState.End then
			leftValue = 0
		end
	end
	
	local moveRightFunc = function(actionName, inputState, inputObject)	
		if inputState == Enum.UserInputState.Begin then
			rightValue = 1
		elseif inputState == Enum.UserInputState.End then
			rightValue = 0
		end
	end
	
	local jumpFunc = function(actionName, inputState, inputObject)
		isJumping = inputState == Enum.UserInputState.Begin
	end
	
	-- enable jumping from seat on backspace
	local jumpFromSeat = function(actionName, inputState, inputObject)
		local humanoid = getHumanoid()
		if humanoid and humanoid.Sit then
			humanoid.Jump = inputState == Enum.UserInputState.Begin
		end
	end
	
	-- TODO: remove up and down arrows, these seem unnecessary
	ContextActionService:BindActionToInputTypes("forwardMovement", moveForwardFunc, false, Enum.PlayerActions.CharacterForward, Enum.KeyCode.Up)
	ContextActionService:BindActionToInputTypes("backwardMovement", moveBackwardFunc, false, Enum.PlayerActions.CharacterBackward, Enum.KeyCode.Down)
	ContextActionService:BindActionToInputTypes("leftMovement", moveLeftFunc, false, Enum.PlayerActions.CharacterLeft)
	ContextActionService:BindActionToInputTypes("rightMovement", moveRightFunc, false, Enum.PlayerActions.CharacterRight)
	ContextActionService:BindActionToInputTypes("jumpAction", jumpFunc, false, Enum.PlayerActions.CharacterJump)
	ContextActionService:BindActionToInputTypes("jumpFromSeat", jumpFromSeat, false, Enum.KeyCode.Backspace)
	-- TODO: make sure we check key state before binding to check if key is already down
	
	RenderSteppedCon = RunService.RenderStepped:connect(function()
		if LocalPlayer and LocalPlayer.Character then
			local humanoid = getHumanoid()
			if isFirstPersonOrShiftLocked() then
				local rootPart = humanoid.Torso
				if humanoid and not humanoid.Sit and not humanoid.PlatformStand and humanoid:GetState() ~= Enum.HumanoidStateType.Swimming and rootPart then
					humanoid.AutoRotate = false
					local desiredLook = game.Workspace.CurrentCamera.CoordinateFrame.lookVector
					desiredLook = Vector3.new(desiredLook.x, 0, desiredLook.z)
					rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + desiredLook)
				end
			else
				if humanoid then
					humanoid.AutoRotate = true
				end
			end
			
			if humanoid and not humanoid.PlatformStand and isJumping then
				humanoid.Jump = isJumping
			end
			
			moveFunc(LocalPlayer, Vector3.new(leftValue + rightValue,0,forwardValue + backwardValue), true)
		end
	end)
end

function KeyboardMovement:Disable()
	ContextActionService:UnbindAction("forwardMovement")
	ContextActionService:UnbindAction("backwardMovement")
	ContextActionService:UnbindAction("leftMovement")
	ContextActionService:UnbindAction("rightMovement")
	ContextActionService:UnbindAction("jumpAction")
	ContextActionService:UnbindAction("jumpFromSeat")
	
	if RenderSteppedCon then
		RenderSteppedCon:disconnect()
		RenderSteppedCon = nil
	end
	
	if LocalPlayer then
		LocalPlayer:Move(Vector3.new(0,0,0), true)
	end
end

return KeyboardMovement
