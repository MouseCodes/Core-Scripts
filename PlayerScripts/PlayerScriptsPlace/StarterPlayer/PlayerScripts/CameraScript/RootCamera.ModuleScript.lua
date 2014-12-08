local UserInputService = game:GetService('UserInputService')
local PlayersService = game:GetService('Players')

local CameraScript = script.Parent
local ShiftLockController = require(CameraScript:WaitForChild('ShiftLockController'))

local function clamp(low, high, num)
	if low <= high then
		return math.min(high, math.max(low, num))
	end
	print("Trying to clamp when low:", low , "is larger than high:" , high , "returning input value.")
	return num
end

local function findFirstChildByType(parent, type)
	for _, child in pairs(parent:GetChildren()) do
		if child.ClassName == type then -- :IsA
			return child
		end
	end
end

local humanoidCache = {}
local function findPlayerHumanoid(player)
	local character = player and player.Character
	if character then
		local resultHumanoid = humanoidCache[player]
		if resultHumanoid and resultHumanoid.Parent == character then
			return resultHumanoid
		else
			humanoidCache[player] = nil -- Bust Old Cache
			for _, child in pairs(character:GetChildren()) do
				if child:IsA('Humanoid') then
					humanoidCache[player] = child
					return child
				end
			end
		end
	end
end

local MIN_Y = math.rad(-80)
local MAX_Y = math.rad(80)

local function CreateCamera()
	local this = {}
	
	this.ShiftLock = false
	local pinchZoomSpeed = 20
	local isFirstPerson = false

	function this:GetShiftLock()
		return ShiftLockController:IsShiftLocked()
	end
	
	function this:GetHumanoid()
		local player = PlayersService.LocalPlayer
		return findPlayerHumanoid(player)
	end
	
	function this:GetHumanoidRootPart()
		local humanoid = this:GetHumanoid()
		return humanoid and humanoid.Torso
	end
	
	function this:GetSubjectPosition()
		local result = nil
		local humanoidRootPart = self:GetHumanoidRootPart()
		local humanoid = self:GetHumanoid()
		if humanoidRootPart then
			result = humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
			if humanoid and humanoid:IsA('Humanoid') then
				result = result + humanoid.CameraOffset
			end
		end
		return result
	end

	function this:ResetCameraLook()
		local camera = workspace.CurrentCamera
		if camera then
			self.cameraLook = camera and camera.CoordinateFrame.lookVector
		end
	end

	function this:GetCameraLook()
		if self.cameraLook == nil then
			self.cameraLook = workspace.CurrentCamera and workspace.CurrentCamera.CoordinateFrame.lookVector or Vector3.new(0,0,1)
		end
		return self.cameraLook
	end

	function this:GetCameraZoom()
		if this.currentZoom == nil then
			local player = PlayersService.LocalPlayer
			this.currentZoom = player and clamp(player.CameraMinZoomDistance, player.CameraMaxZoomDistance, 10) or 10
		end
		return this.currentZoom
	end
	
	function this:GetCameraActualZoom()
		local camera = workspace.CurrentCamera
		if camera then
			return (camera.CoordinateFrame.p - camera.Focus.p).magnitude
		end
	end
	
	function this:ViewSizeX()
		local result = 1024
		local player = PlayersService.LocalPlayer
		local mouse = player and player:GetMouse()
		if mouse then
			result = mouse.ViewSizeX
		end
		return result
	end
	
	function this:ViewSizeY()
		local result = 768
		local player = PlayersService.LocalPlayer
		local mouse = player and player:GetMouse()
		if mouse then
			result = mouse.ViewSizeY
		end
		return result
	end
	
	function this:ScreenTranslationToAngle(translationVector)
		local screenX = this:ViewSizeX()
		local screenY = this:ViewSizeY()
		-- moving your finger across the screen should be a full rotation
		local xTheta = (translationVector.x / screenX) * math.pi*2
		local yTheta = (translationVector.y / screenY) * math.pi
		return Vector2.new(xTheta, yTheta)
	end
	
	function this:RotateCamera(startLook, xyRotateVector)		
		-- Could cache these values so we don't have to recalc them all the time
		local startCFrame = CFrame.new(Vector3.new(), startLook)
		local startVertical = math.asin(startLook.y)
		local yTheta = clamp(-MAX_Y + startVertical, -MIN_Y + startVertical, xyRotateVector.y)
		self.cameraLook = (CFrame.Angles(0, -xyRotateVector.x, 0) * startCFrame * CFrame.Angles(-yTheta,0,0)).lookVector
		return this:GetCameraLook()
	end
	
	function this:IsInFirstPerson()
		return isFirstPerson
	end
	
	function this:ZoomCamera(desiredZoom)
		local player = PlayersService.LocalPlayer
		if player then
			if player.CameraMode == Enum.CameraMode.LockFirstPerson then
				this.currentZoom = 0
			else
				this.currentZoom = clamp(player.CameraMinZoomDistance, player.CameraMaxZoomDistance, desiredZoom)
			end
		end
		-- set mouse behavior
		if self:GetCameraZoom() < 2 then
			isFirstPerson = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		else
			isFirstPerson = false
			if not self:GetShiftLock() then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
		return self:GetCameraZoom()
	end
	
	local function rk4Integrator(position, velocity, t)
		local direction = velocity < 0 and -1 or 1
		local function acceleration(p, v)
			local accel = direction * math.max(1, (p / 3.3) + 0.5)
			return accel
		end
		
		local p1 = position
		local v1 = velocity
		local a1 = acceleration(p1, v1)
		local p2 = p1 + v1 * (t / 2)
		local v2 = v1 + a1 * (t / 2)
		local a2 = acceleration(p2, v2)
		local p3 = p1 + v2 * (t / 2)
		local v3 = v1 + a2 * (t / 2)
		local a3 = acceleration(p3, v3)
		local p4 = p1 + v3 * t
		local v4 = v1 + a3 * t
		local a4 = acceleration(p4, v4)
		
		local positionResult = position + (v1 + 2 * v2 + 2 * v3 + v4) * (t / 6)
		local velocityResult = velocity + (a1 + 2 * a2 + 2 * a3 + a4) * (t / 6)
		return positionResult, velocityResult
	end
	
	function this:ZoomCameraBy(zoomScale)
		local zoom = this:GetCameraActualZoom()
		if zoom then
			-- Can break into more steps to get more accurate integration
			zoom = rk4Integrator(zoom, zoomScale, 1)
			self:ZoomCamera(zoom)
		end
		return self:GetCameraZoom()
	end
	
	function this:ZoomCameraFixedBy(zoomIncrement)
		return self:ZoomCamera(self:GetCameraZoom() + zoomIncrement)
	end	
	
	function this:Update()
	end


	local startPos = nil
	local lastPos = nil
	local panBeginLook = nil
	
	if UserInputService.TouchEnabled then

		local fingerTouches = {}
		local NumUnsunkTouches = 0
		
		UserInputService.InputBegan:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.Touch then
				fingerTouches[input] = processed
				if not processed then			
					NumUnsunkTouches = NumUnsunkTouches + 1
				end
			end
		end)
		
		local StartingDiff = nil
		local pinchBeginZoom = nil
		UserInputService.InputChanged:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.Touch then
				if fingerTouches[input] == nil then
					fingerTouches[input] = processed
					if not processed then			
						NumUnsunkTouches = NumUnsunkTouches + 1
					end
				end
				
				if NumUnsunkTouches == 1 then
					if fingerTouches[input] == false then
						panBeginLook = panBeginLook or this:GetCameraLook()
						startPos = startPos or input.Position
						lastPos = lastPos or startPos					
						this.UserPanningTheCamera = true
						
						local totalTrans = input.Position - startPos
						lastPos = input.Position
						this:RotateCamera(panBeginLook, this:ScreenTranslationToAngle(totalTrans))
					end
				else
					panBeginLook = nil
					startPos = nil
					lastPos = nil				
					this.UserPanningTheCamera = false
				end
				if NumUnsunkTouches == 2 then
					local unsunkTouches = {}
					for touch, wasSunk in pairs(fingerTouches) do
						if not wasSunk then
							table.insert(unsunkTouches, touch)
						end
					end
					if #unsunkTouches == 2 then
						local difference = (unsunkTouches[1].Position - unsunkTouches[2].Position).magnitude
						if StartingDiff and pinchBeginZoom then
							local scale = difference / math.max(0.01, StartingDiff)
							local clampedScale = clamp(0.1, 10, scale)
							this:ZoomCamera(pinchBeginZoom / clampedScale)
						else
							StartingDiff = difference
							pinchBeginZoom = this:GetCameraZoom()
						end
					end
				else
					StartingDiff = nil
					pinchBeginZoom = nil
				end
			end
		end)
		
		UserInputService.InputEnded:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.Touch then
				if fingerTouches[input] == false then
					if NumUnsunkTouches == 1 then
						panBeginLook = nil
						startPos = nil
						lastPos = nil
						this.UserPanningTheCamera = false
					elseif NumUnsunkTouches == 2 then
						StartingDiff = nil
						pinchBeginZoom = nil
					end
				end
				
				if fingerTouches[input] ~= nil and fingerTouches[input] == false then
					NumUnsunkTouches = NumUnsunkTouches - 1
				end
				fingerTouches[input] = nil
			end
		end)
		
	elseif UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then -- Keyboard

		UserInputService.InputBegan:connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Check if they are in first-person
				if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				end
				panBeginLook = this:GetCameraLook()
				startPos = input.Position
				lastPos = startPos
				this.UserPanningTheCamera = true
			elseif input.KeyCode == Enum.KeyCode.I then
				this:ZoomCameraBy(-5)
			elseif input.KeyCode == Enum.KeyCode.O then
				this:ZoomCameraBy(5)
			end
			if panBeginLook == nil then
				if input.KeyCode == Enum.KeyCode.Left then
					this.TurningLeft = true
				elseif input.KeyCode == Enum.KeyCode.Right then
					this.TurningRight = true
				elseif input.KeyCode == Enum.KeyCode.Comma then
					this:RotateCamera(this:GetCameraLook(), Vector2.new(math.rad(30),0))
				elseif input.KeyCode == Enum.KeyCode.Period then
					this:RotateCamera(this:GetCameraLook(), Vector2.new(math.rad(-30),0))
				elseif input.KeyCode == Enum.KeyCode.PageUp then
				--elseif input.KeyCode == Enum.KeyCode.Home then
					this:RotateCamera(this:GetCameraLook(), Vector2.new(0,math.rad(15)))
				elseif input.KeyCode == Enum.KeyCode.PageDown then
				--elseif input.KeyCode == Enum.KeyCode.End then
					this:RotateCamera(this:GetCameraLook(), Vector2.new(0,math.rad(-15)))
				end
			end
		end)
		
		UserInputService.InputChanged:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if startPos and lastPos and panBeginLook then
					--local currPos = input.Position
					local currPos = lastPos + input.Delta
					local totalTrans = currPos - startPos
					lastPos = currPos
					-- NOTE: we probably should not add the delta if we are already maxed out on the rotation angle.
					this:RotateCamera(panBeginLook, this:ScreenTranslationToAngle(totalTrans))
				elseif this:IsInFirstPerson() or this:GetShiftLock() then
					this:RotateCamera(this:GetCameraLook(), this:ScreenTranslationToAngle(input.Delta))
				end
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				if not processed then
					this:ZoomCameraBy(clamp(-1, 1, -input.Position.Z) * 1.4)
				end
			end
		end)
		
		UserInputService.InputEnded:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Check if they are in first-person
				if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
				
				panBeginLook = nil
				startPos = nil
				lastPos = nil
				this.UserPanningTheCamera = false
			elseif input.KeyCode == Enum.KeyCode.Left then
				this.TurningLeft = false
			elseif input.KeyCode == Enum.KeyCode.Right then
				this.TurningRight = false
			end
		end)
	end
	
	local function OnPlayerAdded(player)
		player.Changed:connect(function(prop)
			if prop == "CameraMode" then
				 this:ZoomCameraBy(0)
			end
		end)
		
		local function OnCharacterAdded(newCharacter)
			this:ZoomCamera(10)
			local humanoid = findPlayerHumanoid(player)
			local start = tick()
			while tick() - start < 0.3 and (humanoid == nil or humanoid.Torso == nil) do
				wait()
				humanoid = findPlayerHumanoid(player)
			end
			if humanoid and humanoid.Torso and player.Character == newCharacter then
				this.cameraLook = (humanoid.Torso.CFrame.lookVector - Vector3.new(0,0.7,0)).unit
				-- reset old camera info so follow cam doesn't rotate us
				this.LastCameraTransform = nil
			end
		end
		
		player.CharacterAdded:connect(OnCharacterAdded)
		if player.Character then
			spawn(function() OnCharacterAdded(player.Character) end)
		end
	end
	if PlayersService.LocalPlayer then
		OnPlayerAdded(PlayersService.LocalPlayer)
	end
	PlayersService.ChildAdded:connect(function(child)
		if child and PlayersService.LocalPlayer == child then
			OnPlayerAdded(PlayersService.LocalPlayer)
		end 
	end)
		
	return this
end

return CreateCamera
