local PlayersService = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RootCameraCreator = require(script.Parent)

local ZERO_VECTOR = Vector3.new(0, 0, 0)
local UP_VECTOR = Vector3.new(0, 1, 0)
local XZ_VECTOR = Vector3.new(1,0,1)

local function clamp(low, high, num)
	if low <= high then
		return math.min(high, math.max(low, num))
	end
	print("Trying to clamp when low:", low , "is larger than high:" , high , "returning input value.")
	return num
end

local function IsFinite(num)
	return num == num and num ~= 1/0 and num ~= -1/0
end

local function IsFiniteVector3(vec3)
	return IsFinite(vec3.x) and IsFinite(vec3.y) and IsFinite(vec3.z)
end

-- May return NaN or inf or -inf
local function findAngleBetweenXZVectors(vec2, vec1)
	-- This is a way of finding the angle between the two vectors:
	return math.atan2(vec1.X*vec2.Z-vec1.Z*vec2.X, vec1.X*vec2.X + vec1.Z*vec2.Z)
end

-- May return NaN or inf or -inf
local function absoluteAngleBetween3dVectors(vec1, vec2)
	return math.acos(vec1:Dot(vec2) / (vec1.magnitude * vec2.magnitude))
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

local function CreateClassicCamera()
	local module = RootCameraCreator()

	local tweenAcceleration = math.rad(250)
	local tweenSpeed = math.rad(0)
	local tweenMaxSpeed = math.rad(250)
	
	local lastUpdate = tick()
	function module:Update()
		local now = tick()
		local userPanningTheCamera = (self.UserPanningTheCamera == true)
		
		if lastUpdate == nil or now - lastUpdate > 1 then
			module:ResetCameraLook()
			self.LastCameraTransform = nil
		end	
		
		if lastUpdate then
			-- Cap out the delta to 0.5 so we don't get some crazy things when we re-resume from
			local delta = math.min(0.5, now - lastUpdate)
			local angle = self.TurningLeft and -120 or 0
			angle = angle + (self.TurningRight and 120 or 0)			
			if angle ~= 0 then userPanningTheCamera = true end
			self:RotateCamera(self:GetCameraLook(), Vector2.new(math.rad(angle * delta), 0))
		end

		-- Reset tween speed if user is panning
		if userPanningTheCamera then
			tweenSpeed = 0
		end

		local camera = 	workspace.CurrentCamera
		local player = PlayersService.LocalPlayer
		local subjectPosition = self:GetSubjectPosition()
		
		if subjectPosition and player and camera then
			local zoom = self:GetCameraZoom()
			if zoom <= 0 then
				zoom = 0.1
			end
			
			if self:GetShiftLock() and not self:IsInFirstPerson() then
				local offset = ((self:GetCameraLook() * XZ_VECTOR):Cross(UP_VECTOR).unit * 1.75)
				-- Check for NaNs
				if IsFiniteVector3(offset) then
					subjectPosition = subjectPosition + offset
				end
				zoom = math.max(zoom, 5)
			else
				if self.LastCameraTransform and not userPanningTheCamera then
					local humanoid = findPlayerHumanoid(player)
					local cameraSubject = camera and camera.CameraSubject
					local isInVehicle = cameraSubject and cameraSubject:IsA('VehicleSeat')
					local isOnASkateboard = cameraSubject and cameraSubject:IsA('SkateboardPlatform')
					if (isInVehicle or isOnASkateboard) and lastUpdate and humanoid and humanoid.Torso then
						local forwardVector = humanoid.Torso.CFrame.lookVector
						if isOnASkateboard then
							forwardVector = cameraSubject.CFrame.lookVector
						end
						local timeDelta = (now - lastUpdate)
						
						tweenSpeed = clamp(0, tweenMaxSpeed, tweenSpeed + tweenAcceleration * timeDelta)

						local percent = clamp(0, 1, tweenSpeed * timeDelta)
						if self:IsInFirstPerson() then
							percent = 1
						end
						local y = findAngleBetweenXZVectors(forwardVector, self:GetCameraLook())
						-- Check for NaNs
						if IsFinite(y) then
							self:RotateCamera(self:GetCameraLook(), Vector3.new(y * percent, 0, 0))
						end
					end
				end
			end
			
			camera.Focus = CFrame.new(subjectPosition)
			camera.CoordinateFrame = CFrame.new(camera.Focus.p - (zoom * self:GetCameraLook()), camera.Focus.p)
			self.LastCameraTransform = camera.CoordinateFrame
		end
		
		lastUpdate = now
	end
	
	return module
end

return CreateClassicCamera
