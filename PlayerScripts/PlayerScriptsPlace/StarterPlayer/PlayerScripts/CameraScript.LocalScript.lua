local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local PlayersService = game:GetService('Players')

-- Issue with play solo? (F6)
while not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled do
	wait()
end

local RootCamera = script:WaitForChild('RootCamera')
local ClassicCamera = require(RootCamera:WaitForChild('ClassicCamera'))()
local FollowCamera = require(RootCamera:WaitForChild('FollowCamera'))()
local PopperCam = require(script:WaitForChild('PopperCam'))
local Invisicam = require(script:WaitForChild('Invisicam'))
local ClickToMove = require(script:WaitForChild('ClickToMove'))()
local StarterPlayer = game:GetService('StarterPlayer')

local GameSettings = UserSettings().GameSettings

local function IsTouch()
	return UserInputService.TouchEnabled
end

local function shouldUseCustomCamera()
	local player = PlayersService.LocalPlayer
	local currentCamera = workspace.CurrentCamera
	if player then
		if currentCamera == nil or (currentCamera and currentCamera.CameraType == Enum.CameraType.Custom) then
			return true, player, currentCamera
		end
	end
	return false, player, currentCamera
end

local function isClickToMoveOn()
	local customModeOn, player, currentCamera = shouldUseCustomCamera()
	if customModeOn then
		if IsTouch() then -- Touch
			if player.DevTouchMovementMode == Enum.DevTouchMovementMode.ClickToMove or
					(player.DevTouchMovementMode == Enum.DevTouchMovementMode.UserChoice and GameSettings.TouchMovementMode == Enum.TouchMovementMode.ClickToMove) then
				return true
			end
		else -- Computer
			if player.DevComputerMovementMode == Enum.DevComputerMovementMode.ClickToMove or
					(player.DevComputerMovementMode == Enum.DevComputerMovementMode.UserChoice and GameSettings.ComputerMovementMode == Enum.ComputerMovementMode.ClickToMove) then
				return true
			end
		end
	end
	return false	
end

local function getCurrentCameraMode()
	local customModeOn, player, currentCamera = shouldUseCustomCamera()
	if customModeOn then
		if IsTouch() then -- Touch (iPad, etc...)
			if isClickToMoveOn() then
				return Enum.DevTouchMovementMode.ClickToMove.Name
			elseif player.DevTouchCameraMode == Enum.DevTouchCameraMovementMode.UserChoice then
				local touchMovementMode = GameSettings.TouchCameraMovementMode
				if touchMovementMode == Enum.TouchCameraMovementMode.Default then
					return Enum.TouchCameraMovementMode.Classic.Name
				end
				return touchMovementMode.Name
			else
				return player.DevTouchCameraMode.Name
			end
		else -- Computer
			if isClickToMoveOn() then
				return Enum.DevComputerMovementMode.ClickToMove.Name
			elseif player.DevComputerCameraMode == Enum.DevComputerCameraMovementMode.UserChoice then
				local computerMovementMode = GameSettings.ComputerCameraMovementMode
				if computerMovementMode == Enum.ComputerCameraMovementMode.Default then
					return Enum.ComputerCameraMovementMode.Classic.Name
				end
				return computerMovementMode.Name
			else
				return player.DevComputerCameraMode.Name
			end
		end
	end
end

local function getCameraOcclusionMode()
	local customModeOn, player, currentCamera = shouldUseCustomCamera()
	if customModeOn then
		return player.DevCameraOcclusionMode
	end
end

local EnabledCamera = nil
local EnabledOcclusion = nil
local function OnCameraMovementModeChange(newCameraMode)
	if newCameraMode == Enum.DevComputerMovementMode.ClickToMove.Name then
		ClickToMove:Start()
		EnabledCamera = nil
	else
		if newCameraMode == Enum.ComputerCameraMovementMode.Classic.Name then
			EnabledCamera = ClassicCamera
		elseif newCameraMode == Enum.ComputerCameraMovementMode.Follow.Name then
			EnabledCamera = FollowCamera
		else -- They are disabling our special movement code
			EnabledCamera = nil
		end
		ClickToMove:Stop()
	end
	
	local newOcclusionMode = getCameraOcclusionMode()
	if EnabledOcclusion == Invisicam and newOcclusionMode ~= Enum.DevCameraOcclusionMode.Invisicam then
		Invisicam:Cleanup()
	end
	if newOcclusionMode == Enum.DevCameraOcclusionMode.Zoom then
		EnabledOcclusion = PopperCam
	elseif newOcclusionMode == Enum.DevCameraOcclusionMode.Invisicam then
		EnabledOcclusion = Invisicam
	else
		EnabledOcclusion = false
	end
end

local function FuzzyEquals(num1, num2)
	return num1 > num2 - 0.01 and num1 < num2 + 0.01
end

local CachedParts = {}
local TransparencyDirty = true
local LastTransparency = 0
local function ModifyCharacterTransparency()
	local currentCamera = workspace.CurrentCamera
	local player = PlayersService.LocalPlayer
	local character = player and player.Character
	if player and character and currentCamera then
		local distance = player:DistanceFromCharacter(currentCamera.CoordinateFrame.p)
		local transparency = math.max(0, math.min(1, (5 - distance) / 4))
		if TransparencyDirty or not FuzzyEquals(LastTransparency, transparency) then
			for child, _ in pairs(CachedParts) do
				child.LocalTransparencyModifier = transparency
			end
			TransparencyDirty = false
			LastTransparency = transparency
		end
	end
end


local function OnPlayerAdded(player)
	local currentCameraConn = nil
	local renderSteppedConn = nil
	
	local function OnNewCamera()
		OnCameraMovementModeChange(getCurrentCameraMode())
			
		local currentCamera = workspace.CurrentCamera
		if currentCamera then
			if currentCameraConn then
				currentCameraConn:disconnect()
				currentCameraConn = nil
			end
			currentCameraConn = currentCamera.Changed:connect(function(prop)
				if prop == 'CameraType' then
					OnCameraMovementModeChange(getCurrentCameraMode())
				end
			end)
		end
	end
	
	workspace.Changed:connect(function(prop)
		if prop == 'CurrentCamera' then
			OnNewCamera()
		end
	end)
	
	player.Changed:connect(function(prop)
		OnCameraMovementModeChange(getCurrentCameraMode())
	end)
	
	GameSettings.Changed:connect(function(prop)
		OnCameraMovementModeChange(getCurrentCameraMode())
	end)
	
	local function OnCharacterAdded(character)
		CachedParts = {}
		local function IsValidPartToModify(part)
			local function HasToolAncestor(object)
				if object.Parent == nil then return false end
				return object.Parent:IsA('Tool') or HasToolAncestor(object.Parent) 
			end
			
			if part:IsA('BasePart') then
				return not HasToolAncestor(part)
			end
			return false
		end
		local function CachePartsRecursive(object)
			if object then
				if IsValidPartToModify(object) then
					CachedParts[object] = true
					TransparencyDirty = true
				end
				for _, child in pairs(object:GetChildren()) do
					CachePartsRecursive(child)
				end
			end
		end
		-- TODO: this does not catch reparenting within the character:
		-- for example if a part that is already a member of the character is reparented to be the child of the tool
		-- it will still fade in and out with the character despite being part of a tool
		character.DescendantAdded:connect(function(object)
			if IsValidPartToModify(object) then
				CachedParts[object] = true
				TransparencyDirty = true
			end
		end)
		character.DescendantRemoving:connect(function(object)
			if CachedParts[object] then
				-- Reset the transparency when it is removed
				object.LocalTransparencyModifier = 0
				CachedParts[object] = nil
			end
		end)
		CachePartsRecursive(character)
	end
	
	player.CharacterRemoving:connect(function() CachedParts = {} end)
	player.CharacterAdded:connect(OnCharacterAdded)
	if player.Character then
		OnCharacterAdded(player.Character)
	end
	
	renderSteppedConn = RunService.RenderStepped:connect(function()
		if EnabledCamera then
			EnabledCamera:Update()	
		end
		if EnabledOcclusion then
			EnabledOcclusion:Update()
		end
		if shouldUseCustomCamera() then
			ModifyCharacterTransparency()
		end
	end)
	
	OnNewCamera()
	OnCameraMovementModeChange(getCurrentCameraMode())	
end

do
	while PlayersService.LocalPlayer == nil do wait() end
	OnPlayerAdded(PlayersService.LocalPlayer)
end
