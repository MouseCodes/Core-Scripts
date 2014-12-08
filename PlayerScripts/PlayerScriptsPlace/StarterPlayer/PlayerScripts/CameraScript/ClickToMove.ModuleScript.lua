local UIS = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local DebrisService = game:GetService('Debris')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Player = PlayerService.localPlayer
local MyMouse = Player:GetMouse()


local DirectPathEnabled = false
local SHOW_PATH = false

local RayCastIgnoreList = workspace.FindPartOnRayWithIgnoreList
local GetPartsTouchingExtents = workspace.FindPartsInRegion3

-- Bindable for when we want touch emergency controls
-- TODO: Click to move should probably have it's own gui touch controls
-- to manage this.
local BindableEvent_OnFailStateChanged = nil
if UIS.TouchEnabled then
	BindableEvent_OnFailStateChanged = Instance.new('BindableEvent')
	BindableEvent_OnFailStateChanged.Name = "OnClickToMoveFailStateChange"
	local CameraScript = script.Parent
	local PlayerScripts = CameraScript.Parent
	BindableEvent_OnFailStateChanged.Parent = PlayerScripts
end


--------------------------UTIL LIBRARY-------------------------------
local Utility = {}
do
	local Signal = {}

	function Signal.Create()
		local sig = {}
		
		local mSignaler = Instance.new('BindableEvent')
		
		local mArgData = nil
		local mArgDataCount = nil
		
		function sig:fire(...)
			mArgData = {...}
			mArgDataCount = select('#', ...)
			mSignaler:Fire()
		end
		
		function sig:connect(f)
			if not f then error("connect(nil)", 2) end
			return mSignaler.Event:connect(function()
				f(unpack(mArgData, 1, mArgDataCount))
			end)
		end
		
		function sig:wait()
			mSignaler.Event:wait()
			assert(mArgData, "Missing arg data, likely due to :TweenSize/Position corrupting threadrefs.")
			return unpack(mArgData, 1, mArgDataCount)
		end
		
		return sig
	end
	Utility.Signal = Signal
	
	function Utility.Create(instanceType)
		return function(data)
			local obj = Instance.new(instanceType)
			for k, v in pairs(data) do
				if type(k) == 'number' then
					v.Parent = obj
				else
					obj[k] = v
				end
			end
			return obj
		end
	end
	
	local function clamp(low, high, num)
		return math.max(math.min(high, num), low)
	end
	Utility.Clamp = clamp
	
	local function ViewSizeX()
		local x = MyMouse and MyMouse.ViewSizeX or 0
		local y = MyMouse and MyMouse.ViewSizeY or 0
		if x == 0 then
			return 1024
		else
			if x > y then
				return x
			else
				return y
			end
		end
	end
	Utility.ViewSizeX = ViewSizeX
	
	local function ViewSizeY()
		local x = MyMouse and MyMouse.ViewSizeX or 0
		local y = MyMouse and MyMouse.ViewSizeY or 0
		if y == 0 then
			return 768
		else
			if x > y then
				return y
			else
				return x
			end
		end
	end
	Utility.ViewSizeY = ViewSizeY
	
	local function AspectRatio()
		return ViewSizeX() / ViewSizeY()
	end
	Utility.AspectRatio = AspectRatio
	
	local function FindChacterAncestor(part)
		if part then
			local humanoid = part:FindFirstChild("Humanoid")
			if humanoid then
				return part, humanoid
			else
				return FindChacterAncestor(part.Parent)
			end
		end
	end
	Utility.FindChacterAncestor = FindChacterAncestor
	
	local function GetUnitRay(x, y, viewWidth, viewHeight, camera)
		if not (x or y or viewWidth or viewHeight or camera) then
			print("GetUnitRay: Missing arguement; returning nil")
			return
		end
		
		local function getImagePlaneDepth()
			local imagePlaneDepth = 1.0 / (2.0 * math.tan(math.rad(camera.FieldOfView) / 2.0));
			return imagePlaneDepth * viewHeight;
		end
		
		local screenWidth  = viewWidth;
		local screenHeight = viewHeight;
	
		x = clamp(0, screenWidth, x)
		y = clamp(0, screenHeight, y)
	
		local origin = camera.CoordinateFrame.p
	
		local cx = screenWidth  / 2.0;
		local cy = screenHeight / 2.0;
	  
		local direction = Vector3.new((x - cx), -(y - cy), -(getImagePlaneDepth()));
	
		direction = camera.CoordinateFrame:vectorToWorldSpace(direction);
	
		-- Normalize the direction (we didn't do it before)
		direction = direction.unit;
	
		return Ray.new(origin, direction);
	end
	Utility.GetUnitRay = GetUnitRay
	
	local RayCastIgnoreList = workspace.FindPartOnRayWithIgnoreList
	local function Raycast(ray, ignoreNonCollidable, ignoreList)
		local ignoreList = ignoreList or {}
		local hitPart, hitPos = RayCastIgnoreList(workspace, ray, ignoreList)
		if hitPart then
			if ignoreNonCollidable and hitPart.CanCollide == false then
				table.insert(ignoreList, hitPart)
				return Raycast(ray, ignoreNonCollidable, ignoreList)
			end
			return hitPart, hitPos
		end
		return nil, nil
	end
	Utility.Raycast = Raycast
	
	
	Utility.Round = function(num, roundToNearest)
		roundToNearest = roundToNearest or 1
		return math.floor((num + roundToNearest/2) / roundToNearest) * roundToNearest
	end
	
	local function AveragePoints(positions)
		local avgPos = Vector2.new(0,0)
		if #positions > 0 then
			for i = 1, #positions do
				avgPos = avgPos + positions[i]
			end
			avgPos = avgPos / #positions
		end
		return avgPos
	end
	Utility.AveragePoints = AveragePoints
	
	local function FuzzyEquals(numa, numb)
		return numa + 0.1 > numb and numa - 0.1 < numb
	end
	Utility.FuzzyEquals = FuzzyEquals
	
	local LastInput = 0
	UIS.InputBegan:connect(function(inputObject, wasSunk)
		if not wasSunk then
			if inputObject.UserInputType == Enum.UserInputType.Touch or
					inputObject.UserInputType == Enum.UserInputType.MouseButton1 or
					inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
				LastInput = tick()
			end
		end
	end)
	Utility.GetLastInput = function()
		return LastInput
	end
end
---------------------------------------------------------

local Signal = Utility.Signal
local Create = Utility.Create

--------------------------CHARACTER CONTROL-------------------------------
local function CreateController()
	local this = {}

	this.TorsoLookPoint = nil
	
	function this:SetTorsoLookPoint(point)
		local character = Player.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.AutoRotate = false
		end
		this.TorsoLookPoint = point
		self:UpdateTorso()
		delay(2,
			function()
			-- this isnt technically correct for detecting if this is the last issue to the setTorso function
			if this.TorsoLookPoint == point then
				this.TorsoLookPoint = nil
				if humanoid then
					humanoid.AutoRotate = true
				end
			end
		end)
	end
	
	function this:UpdateTorso(point)
		if this.TorsoLookPoint then
			point = this.TorsoLookPoint
		else
			return
		end
		
		local character = Player.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		local torso = humanoid and humanoid.Torso
		if torso then
			local lookVec = (point - torso.CFrame.p).unit
			local squashedLookVec = Vector3.new(lookVec.X, 0, lookVec.Z).unit
			torso.CFrame = CFrame.new(torso.CFrame.p, torso.CFrame.p + squashedLookVec)
		end
	end
	
	return this
end

local CharacterControl = CreateController()
-----------------------------------------------------------------------

--------------------------PC AUTO JUMPER-------------------------------

local function GetCharacter()
	return Player and Player.Character
end

local function GetHumanoid()
	local character = GetCharacter()
	return character and character:FindFirstChild("Humanoid")
end

local function GetTorso()
	local humanoid = GetHumanoid()
	return humanoid and humanoid.Torso
end

local function IsPartAHumanoid(part)
	return part and part.Parent and (part.Parent:FindFirstChild('Humanoid') ~= nil)
end

local function doAutoJump()
	local character = GetCharacter()
	if (character == nil) then
		return;
	end
	
	local humanoid = GetHumanoid()
	if (humanoid == nil) then
		return;
	end

	local rayLength = 1.5; 
	-- This is how high a ROBLOXian jumps from the mid point of his torso 
	local jumpHeight = 7.0; 

	local torso = GetTorso()
	if (torso == nil) then
		return; 
	end

	local torsoCFrame = torso.CFrame;
	local torsoLookVector = torsoCFrame.lookVector; 
	local torsoPos = torsoCFrame.p; 

	local torsoRay = Ray.new(torsoPos + Vector3.new(0, -torso.Size.Y/2, 0), torsoLookVector * rayLength); 
	local jumpRay = Ray.new(torsoPos + Vector3.new(0, jumpHeight - torso.Size.Y, 0), torsoLookVector * rayLength); 
		
	local hitPart, _ = RayCastIgnoreList(workspace, torsoRay, {character}, false)
	local jumpHitPart, _ = RayCastIgnoreList(workspace, jumpRay, {character}, false)

	if (hitPart and jumpHitPart == nil and hitPart.CanCollide == true) then
		if not IsPartAHumanoid(hitPart) then -- NOTE: this code is not in the C++ impl, but an improvement from my lua version
			humanoid.Jump = true;
		end
	end
end

-- Some constants
-- Nyquist rate = 6 samples per stud, use slightly more so we're not integer stud aligned
local function sampleSpacing() return 1.0 / 7.0; end
local function lowLadderSearch() return 2.7 end		-- tweaked - not, should take leg length into account!
local function ladderSearchDistance() return 1.0; end --  1.5x search depth
local function searchDepth() return 0.7 end			-- studs from the middle of leg to the max depth to search for a rung or step

local function findPrimitiveInLadderZone(adorn)
    
	local torsoBody = GetTorso()

	local cf = torsoBody.CFrame

	local bottom = -lowLadderSearch();
	local top = 0.0;
	local radius = 0.5 * ladderSearchDistance();
	local center = cf.p + (cf.lookVector * ladderSearchDistance() * 0.5);
	local minimum = Vector3.new(-radius, bottom, -radius);
	local maximum = Vector3.new(radius, top, radius);
	
	--Extents extents(center + minimum, center + maximum);
	local extents = Region3.new(center + minimum, center + maximum);

	local foundParts = GetPartsTouchingExtents(workspace, extents, nil, 100)
	
	local character = GetCharacter()
	for i = 0, #foundParts do
		local foundPart = foundParts[i];
		if (not foundPart:isDescendantOf(character)) then
			return true;
		end
	end
	return false;
end

local function enableAutoJump()
	-- TODO: impl state checks
	return true
end

local function getAutoJump()
	return true
end

local function vec3IsZero(vec3)
	return vec3.magnitude < 0.05
end

-- NOTE: This function is radically different from the engine's implementation
local function calcDesiredWalkVelocity()
	-- TEMP
	return Vector3.new(1,1,1)
end

local function preStepSimulatorSide(dt)
	local facingLadder = false;

	if (not facingLadder and getAutoJump() and enableAutoJump()) then
		local desiredWalkVelocity = calcDesiredWalkVelocity();
		if (not vec3IsZero(desiredWalkVelocity)) then
			doAutoJump(); 
		end
	end
end

local function AutoJumper()
	local this = {}
	local running = false
	local runRoutine = nil
	
	function this:Run()
		running = true
		local thisRoutine = nil
		thisRoutine = coroutine.create(function()
			while running and thisRoutine == runRoutine do
				this:Step()
				wait()
			end
		end)
		runRoutine = thisRoutine
		coroutine.resume(thisRoutine)
	end
	
	function this:Stop()
		running = false
	end
	
	function this:Step()
		preStepSimulatorSide()
	end
	
	return this
end

-----------------------------------------------------------------------------

---------------------------------CFRAME INTERPOLATOR-------------------------

local function CFrameInterpolator(c0, c1) -- (CFrame from, CFrame to) -> (float theta, (float fraction -> CFrame between))
	-- Optimized CFrame interpolator module ~ by Stravant
	-- Based off of code by Treyreynolds posted on the Roblox Developer Forum
	
	local fromAxisAngle = CFrame.fromAxisAngle
	local components = CFrame.new().components
	local inverse = CFrame.new().inverse
	local v3 = Vector3.new
	local acos = math.acos
	local sqrt = math.sqrt
	local invroot2 = 1/math.sqrt(2)
	
	-- The expanded matrix
	local _, _, _, xx, yx, zx, 
	               xy, yy, zy, 
	               xz, yz, zz = components(inverse(c0)*c1)
	
	-- The cos-theta of the axisAngles from 
	local cosTheta = (xx + yy + zz - 1)/2
	
	-- Rotation axis
	local rotationAxis = v3(yz-zy, zx-xz, xy-yx)
	
	-- The position to tween through
	local positionDelta = (c1.p - c0.p)
		
	-- Theta
	local theta;			
		
	-- Catch degenerate cases
	if cosTheta >= 0.999 then
		-- Case same rotation, just return an interpolator over the positions
		return 0, function(t)
			return c0 + positionDelta*t
		end	
	elseif cosTheta <= -0.999 then
		-- Case exactly opposite rotations, disambiguate
		theta = math.pi
		xx = (xx + 1) / 2
		yy = (yy + 1) / 2
		zz = (zz + 1) / 2
		if xx > yy and xx > zz then
			if xx < 0.001 then
				rotationAxis = v3(0, invroot2, invroot2)
			else
				local x = sqrt(xx)
				xy = (xy + yx) / 4
				xz = (xz + zx) / 4
				rotationAxis = v3(x, xy/x, xz/x)
			end
		elseif yy > zz then
			if yy < 0.001 then
				rotationAxis = v3(invroot2, 0, invroot2)
			else
				local y = sqrt(yy)
				xy = (xy + yx) / 4
				yz = (yz + zy) / 4
				rotationAxis = v3(xy/y, y, yz/y)
			end	
		else
			if zz < 0.001 then
				rotationAxis = v3(invroot2, invroot2, 0)
			else
				local z = sqrt(zz)
				xz = (xz + zx) / 4
				yz = (yz + zy) / 4
				rotationAxis = v3(xz/z, yz/z, z)
			end
		end
	else
		-- Normal case, get theta from cosTheta
		theta = acos(cosTheta)
	end
	
	-- Return the interpolator
	return theta, function(t)
		return c0*fromAxisAngle(rotationAxis, theta*t) + positionDelta*t
	end
end
-----------------------------------------------------------------------------

-------------------------------------CAMERA------------------------------------
local e = 2.718281828459
local function SCurve(t)
	return 1/(1 + e^(-t*1.5))
end

-- t = current time; b = start value; c = change in value; d = duration
local function easeInOutQuad(t, b, c, d)
	if t >= d then return b + c end
	t = t/(d/2);
	if (t < 1) then return c/2*t*t + b end
	t = t-1;
	return -c/2 * (t*(t-2) - 1) + b;
end

local function easeOutQuad(t, b, c, d)
	if t >= d then return b + c end
	t  = t/ d;
	return -c * t*(t-2) + b;
end

local function easeOutSine(t, b, c, d)
	if t >= d then return b + c end
	return c * math.sin(t/d * (math.pi/2)) + b;
end

local function linear(t, b, c, d)
	if t >= d then return b + c end
	return c * t/d + b;
end

local function CreateCamera()
	local this = {}
	

	local currentZoom = 10
	local desiredZoom = currentZoom
	local maxZoom = 40
	local minZoom = 0.5
	local cameraLook = workspace.CurrentCamera.CoordinateFrame.lookVector

	local pinchZoomSpeed = 17
	
	this.ZoomSetStart = currentZoom
	this.ZoomSetTime = nil
	this.On = false
	
	local function UpdateTorso()
		if not this.On then return end
		local character = Player.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		local torso = humanoid and humanoid.Torso
		local camera = workspace.CurrentCamera
		if torso and camera then
			local lookVec = camera.CoordinateFrame.lookVector
			local squashedLookVec = Vector3.new(lookVec.X, 0, lookVec.Z).unit
			torso.CFrame = CFrame.new(torso.CFrame.p, torso.CFrame.p + squashedLookVec)
		end
	end
	
	local function GetHead()
		local character = Player.Character
		local head = character and character:FindFirstChild("Head")
		return head
	end
	
	function this:Stop()
		this.On = false
	end
	
	function this:Start()
		this.On = true
		currentZoom = (workspace.CurrentCamera.CoordinateFrame.p - workspace.CurrentCamera.Focus.p).magnitude
		desiredZoom = currentZoom
		cameraLook = workspace.CurrentCamera.CoordinateFrame.lookVector
		--workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	end
	
	function this:LookAtPreserveHeight(newLookAtPt)
		local camera = 	workspace.CurrentCamera
		
		local focus = camera.Focus.p
					
		local cameraCFrame = camera.CoordinateFrame
		local mag = Vector3.new(cameraCFrame.lookVector.x, 0, cameraCFrame.lookVector.z).magnitude
		local newLook = (Vector3.new(newLookAtPt.x, focus.y, newLookAtPt.z) - focus).unit * mag
		local flippedLook = newLook + Vector3.new(0, cameraCFrame.lookVector.y, 0)
		
		local distance = currentZoom-- (focus - camera.CoordinateFrame.p).magnitude
		
		local newCamPos = focus - flippedLook.unit * distance
		local rotatedCFrame = CFrame.new(newCamPos, newCamPos + flippedLook)
		return rotatedCFrame
	end
	
	function this:GetCameraLook()
		return cameraLook
	end
	
	local CurrentCameraTween = nil
	function this:TweenCameraLook(desiredCFrame, speed)

		local finished = Signal.Create()
		
		local camera = workspace.CurrentCamera
		local startCFrame = camera.CoordinateFrame - camera.CoordinateFrame.p
		-- remove position from the equation
		local endCFrame = desiredCFrame - desiredCFrame.p
		
		local maxTheta = math.pi
		local minTheta = 0
		
		local theta, interper = CFrameInterpolator(startCFrame, endCFrame)
		theta = Utility.Clamp(minTheta, maxTheta, theta)
		-- Pivot the x around half the range (math.pi)
		local duration = 0.65 * SCurve(theta - math.pi/4) + 0.15 -- theta / speed
		if speed then
			duration = theta / speed
		end
		
		local thisTween = nil
		thisTween = coroutine.create(function()
			local start = tick()
			local finish = start + duration
			
			local function updateCamera()
				if not this.On then return end
				local currTime = tick() - start			
				--local alpha = math.min(1, currTime / duration)
				local alpha = Utility.Clamp(0, 1, easeOutSine(currTime, 0, 1, duration))
				local newCFrame = interper(alpha)
				
				local focus = camera.Focus.p or (camera.CoordinateFrame.p + camera.CoordinateFrame.lookVector)
				local distance = (focus - camera.CoordinateFrame.p).magnitude
				newCFrame = newCFrame + focus - (newCFrame.lookVector * distance)
				
				cameraLook = newCFrame.lookVector
				

				--camera.CoordinateFrame = newCFrame
				--UpdateTorso()
			end
			
			while CurrentCameraTween == thisTween and finish > tick() do
				updateCamera()			
				RunService.RenderStepped:wait()
			end
			if CurrentCameraTween == thisTween then
				updateCamera()
				finished:fire(true)
			end
			finished:fire(false)
		end)
			
		CurrentCameraTween = thisTween
		local success, errorMsg = coroutine.resume(thisTween)
		if not success then
			print("TweenCameraLook:" , errorMsg)
		end
		return finished, duration
	end
	
	local LastZoomInput = 0
	
	MyMouse.WheelForward:connect(function()
		if not this.On then return end
		LastZoomInput = tick()
		local newZoom;
		if desiredZoom > currentZoom then -- in this case we are trying to counter a zoom-in; so use current-zoom rather than desired
			newZoom = Utility.Clamp(minZoom, maxZoom, currentZoom - 5)
		else
			newZoom = Utility.Clamp(minZoom, maxZoom, desiredZoom - 5)
		end
		
		if newZoom ~= desiredZoom and newZoom ~= currentZoom then			
			this.ZoomSetStart = currentZoom
			this.ZoomSetTime = tick()
			desiredZoom = newZoom
		end
	end)
	
	MyMouse.WheelBackward:connect(function()
		if not this.On then return end
		LastZoomInput = tick()
		local newZoom;
		if desiredZoom < currentZoom then -- in this case we are trying to counter a zoom-in; so use current-zoom rather than desired
			newZoom = Utility.Clamp(minZoom, maxZoom, currentZoom + 5)
		else
			newZoom = Utility.Clamp(minZoom, maxZoom, desiredZoom + 5)
		end
		if newZoom ~= desiredZoom and newZoom ~= currentZoom then			
			this.ZoomSetStart = currentZoom
			this.ZoomSetTime = tick()
			desiredZoom = newZoom
		end
	end)
	
	local MIN_Y = math.rad(-70)
	local MAX_Y = math.rad(70)
	
	local function RotateCamera(startLook, totalTrans)
		if not this.On then return end
		local screenX = Utility.ViewSizeX()
		local screenY = Utility.ViewSizeY()
		-- moving your finger across the screen should be a full rotation
		local xTheta = (totalTrans.x / screenX) * math.pi*2
		local yTheta = (totalTrans.y / screenY) * math.pi
		
		-- Could cache these values so we don't have to recalc them all the time
		local startCFrame = CFrame.new(Vector3.new(), startLook)
		local startVertical = math.asin(startLook.y)

		yTheta = Utility.Clamp(-MAX_Y + startVertical, -MIN_Y + startVertical, yTheta)
		cameraLook = (CFrame.Angles(0,-xTheta,0) * startCFrame * CFrame.Angles(-yTheta,0,0)).lookVector
		return cameraLook
	end
	
	if UIS.TouchEnabled then
		local pinchBeginZoom = nil
		UIS.TouchPinch:connect(function(touchPositions, scale, velocity, state, sunk)
			if not this.On then return end
			if not sunk then
				LastZoomInput = tick()
				---if state == Enum.UserInputState.Begin then
				if pinchBeginZoom == nil then
					desiredZoom = currentZoom -- Cancels all existing zooms when we get a new zoom
					pinchBeginZoom = currentZoom
				else
					if pinchBeginZoom and scale ~= 0 then
						currentZoom = Utility.Clamp(minZoom, maxZoom, pinchBeginZoom + ((1 - scale) * pinchZoomSpeed)) --(maxZoom - minZoom)))
					end 
				end
			end	
			if state == Enum.UserInputState.End then
				pinchBeginZoom = nil
			end
		end)
		
		local panBeginLook = nil
		local lastTotalTrans = Vector2.new()
		local singleTouchTrans = Vector2.new()
		UIS.TouchPan:connect(function(touchPositions, totalTrans, velocity, state, sunk)	
			if not this.On then return end
			if not sunk then
				if #touchPositions == 1 then
					local delta = totalTrans - lastTotalTrans
					singleTouchTrans = singleTouchTrans + delta
					if panBeginLook == nil then
						panBeginLook = cameraLook
					end
					if singleTouchTrans.magnitude > 5 then
						CurrentCameraTween = nil
						
						--RotateCamera(panBeginLook, singleTouchTrans)
						RotateCamera(cameraLook, delta)
					end
				end
			end
			lastTotalTrans = totalTrans
			if state == Enum.UserInputState.End then
				panBeginLook = nil
				lastTotalTrans = Vector2.new()
				singleTouchTrans = Vector2.new()
			end
		end)
	else
		local function ScreenTranslationToAngle(translationVector)
			local screenX = Utility.ViewSizeX()
			local screenY = Utility.ViewSizeY()
			-- moving your finger across the screen should be a full rotation
			local xTheta = (translationVector.x / screenX) * math.pi*2
			local yTheta = (translationVector.y / screenY) * math.pi
			return Vector2.new(xTheta, yTheta)
		end
		
		local startPos = nil
		local lastPos = nil
		local panBeginLook = nil
		UIS.InputBegan:connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Check if they are in first-person
				if UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
					UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				end
				panBeginLook = this:GetCameraLook()
				startPos = input.Position
				lastPos = startPos
				this.UserPanningTheCamera = true
			end
		end)
			
		UIS.InputChanged:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if startPos and lastPos and panBeginLook then
					--local currPos = input.Position
					local currPos = lastPos + input.Delta
					local totalTrans = currPos - startPos
					
					lastPos = currPos
					-- We really should be tracking if it ever passed this threshold to go into the rotate mode.
					-- That way when we come back to the point we started at we don't lose control of the camera.
					if totalTrans.magnitude > 5 then
						RotateCamera(panBeginLook, totalTrans)
					end
				end
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				if not processed then
					--this:ZoomCameraBy(clamp(-1, 1, -input.Position.Z) * 1.4)
				end
			end
		end)
		
		UIS.InputEnded:connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Check if they are in first-person
				if UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
					UIS.MouseBehavior = Enum.MouseBehavior.Default
				end
				
				panBeginLook = nil
				startPos = nil
				lastPos = nil
				this.UserPanningTheCamera = false
			end
		end)
	end
	
	--local selBox = Instance.new("SelectionBox")
	--selBox.Parent = Player.PlayerGui
	
	local TimeBeforePullOut = 0.8
	local PulloutDuration = 0.7
	
	local UtilityRaycast = Utility.Raycast
	local LastOccludedTime = tick()
	local LastOcclusionDistance = currentZoom
	local OnRenderStepped = RunService.RenderStepped:connect(function()
		if not this.On then return end
		if currentZoom ~= desiredZoom and this.ZoomSetTime then
			local elapsedTime = (tick() - this.ZoomSetTime)
			local duration = math.abs(desiredZoom - this.ZoomSetStart) / 60
			-- I am not really happy with linear but if we use an easing function I need to smoothly be able to update the ease when the desired value changes.
			currentZoom = linear(elapsedTime, this.ZoomSetStart, desiredZoom - this.ZoomSetStart, duration)
		else
			this.ZoomSetTime = nil
		end
		
		local camera = 	workspace.CurrentCamera
		--camera.CameraType = "Scriptable"

		
		local head = GetHead()
		if head then
			camera.Focus = CFrame.new(head.CFrame.p)
			
			local maxZoomOut = currentZoom
			-- TODO: change this to ignore invisible
			local hitPart, hitPos = UtilityRaycast(Ray.new(camera.Focus.p - cameraLook, -cameraLook * currentZoom), true, {Player.Character})			
			
			if hitPart and hitPos then
				LastOccludedTime = tick()
				local occlusionDist = (hitPos - camera.Focus.p).magnitude
				--if (LastOcclusionDistance == nil or occlusionDist <= LastOcclusionDistance + 0.5) then
					LastOcclusionDistance = occlusionDist
				--end
				maxZoomOut = math.max(0.5, LastOcclusionDistance - 0.5)
				--selBox.Adornee = hitPart
				--print("Hit" , hitPart:GetFullName() , " , so max zoom out is now:" , maxZoomOut)
			else
				--selBox.Adornee = nil
				local wasLastZoomRecent = (LastOccludedTime and LastZoomInput >= LastOccludedTime) or (LastZoomInput + TimeBeforePullOut + PulloutDuration >= tick())
				
				if wasLastZoomRecent then
					-- let maxZoomOut stay at currentZoom
					--LastOcclusionDistance = nil
					--LastOccludedTime = nil
				elseif LastOccludedTime and LastOcclusionDistance then
					if (LastOccludedTime and LastOccludedTime + TimeBeforePullOut + PulloutDuration < tick())  then
						-- let maxZoomOut stay at currentZoom
						LastOcclusionDistance = nil
						LastOccludedTime = nil
					elseif LastOccludedTime + TimeBeforePullOut < tick() then
						--start tween back out
						local t = tick() - LastOccludedTime - TimeBeforePullOut
						maxZoomOut = easeInOutQuad(t, LastOcclusionDistance, currentZoom - LastOcclusionDistance, PulloutDuration)
						--print("Maxzoomout:" , maxZoomOut , "Time:" , t , "startval:" , LastOcclusionDistance , "change:" , currentZoom - LastOcclusionDistance)
					else -- haven't started tween yet
						maxZoomOut = math.max(0.5, LastOcclusionDistance - 0.5)
					end
				end
			end
		
			
			camera.CoordinateFrame = CFrame.new(camera.Focus.p - maxZoomOut * cameraLook, camera.Focus.p)
		end
	end)
	
	return this
end

local CameraModule = nil
-------------------------------------------------------------------------


local function CreateDestinationIndicator(pos)
	local destinationGlobe = Create'Part'
	{
		Name = 'PathGlobe';
		TopSurface = 'Smooth';
		BottomSurface = 'Smooth';
		Shape = 'Ball';
		CanCollide = false;
		Size = Vector3.new(2,2,2);
		BrickColor = BrickColor.new('Institutional white');
		Transparency = 0;
		Anchored = true;
		CFrame = CFrame.new(pos);
	}
	return destinationGlobe
end

-----------------------------------PATHER--------------------------------------

local function Pather(character, point)
	local this = {}
	
	this.Cancelled = false
	this.Started = false
	
	this.Finished = Signal.Create()
	this.PathFailed = Signal.Create()
	this.PathStarted = Signal.Create()

	this.PathComputed = false
	
	function this:YieldUntilPointReached(character, point, timeout)
		timeout = timeout or 10000000
		
		local humanoid = character:FindFirstChild("Humanoid")
		local torso = humanoid and humanoid.Torso
		local start = tick()
		local lastMoveTo = start
		while torso and tick() - start < timeout and this.Cancelled == false do
			local diffVector = (point - torso.CFrame.p)
			local xzMagnitude = (diffVector * Vector3.new(1,0,1)).magnitude
			if xzMagnitude < 6 then 
				-- Jump if the path is telling is to go upwards
				if diffVector.Y >= 2 then
					humanoid.Jump = true
				end
			end
			-- The hard-coded number 2 here is from the engine's MoveTo implementation
			if xzMagnitude < 2 then
				return true
			end
			-- Keep on issuing the move command because it will automatically quit every so often.
			if tick() - lastMoveTo > 1.5 then
				humanoid:MoveTo(point)
				lastMoveTo = tick()
			end
			CharacterControl:UpdateTorso(point)
			wait()
		end
		return false
	end
	
	function this:Cancel()
		this.Cancelled = true
		local humanoid = character:FindFirstChild("Humanoid")
		local torso = humanoid and humanoid.Torso
		if humanoid and torso then
			humanoid:MoveTo(torso.CFrame.p)
		end
	end
	
	function this:CheckOcclusion(point1, point2, character, torsoRadius)
		--print("Point1" , point1 , "point2" , point2)
		local humanoid = character and character:FindFirstChild('Humanoid')
		local torso = humanoid and humanoid.Torso
		if torsoRadius == nil then
			torsoRadius = torso and Vector3.new(torso.Size.X/2,0,torso.Size.Z/2) or Vector3.new(1,0,1)
		end
		
		local diffVector = point2 - point1
		local directionVector = diffVector.unit
		
		local rightVector = Vector3.new(0,1,0):Cross(directionVector) * torsoRadius
		
		local rightPart, _ = Utility.Raycast(Ray.new(point1 + rightVector, diffVector + rightVector), true, {character})
		local hitPart, _ = Utility.Raycast(Ray.new(point1, diffVector), true, {character})
		local leftPart, _ = Utility.Raycast(Ray.new(point1 - rightVector, diffVector - rightVector), true, {character})
		
		if rightPart or hitPart or leftPart then
			return false
		end
		
		-- Make sure we have somewhere to stand on
		local midPt = (point2 + point1) / 2
		local studsBetweenSamples = 2
		for i = 1, math.floor(diffVector.magnitude/studsBetweenSamples) do
			local downPart, _ = Utility.Raycast(Ray.new(point1 + directionVector * i * studsBetweenSamples, Vector3.new(0,-7,0)), true, {character})
			if not downPart then
				return false
			end
		end
		
		return true
	end
	
	function this:SmoothPoints(pathToSmooth)
		local result = {}
		
		local humanoid = character:FindFirstChild('Humanoid')
		local torso = humanoid and humanoid.Torso
		for i = 1, #pathToSmooth do
			table.insert(result, pathToSmooth[i])
		end
		
		-- Backwards for safe-deletion
		for i = #result - 1, 1, -1 do
			if i + 1 <= #result then
				
				local nextPoint = result[i+1]				
				local thisPoint = result[i]
				
				local lastPoint = result[i-1]
				if lastPoint == nil then
					lastPoint = torso and Vector3.new(torso.CFrame.p.X, thisPoint.Y, torso.CFrame.p.Z)
				end
				
				if lastPoint and Utility.FuzzyEquals(thisPoint.Y, lastPoint.Y) and Utility.FuzzyEquals(thisPoint.Y, nextPoint.Y) then
					if this:CheckOcclusion(lastPoint, nextPoint, character) then
						table.remove(result, i)
						-- Move i back one to recursively-smooth
						i = i + 1
					end
				end
			end
		end
		
		return result
	end
	
	function this:CheckNeighboringCells(character)
		local pathablePoints = {}
		local torso = character and character:FindFirstChild("Humanoid") and character:FindFirstChild("Humanoid").Torso
		if torso then
			local torsoCFrame = torso.CFrame
			local torsoPos = torsoCFrame.p
			-- Minus and plus 2 is so we can get it into the cell-corner space and then translate it back into cell-center space
			local roundedPos = Vector3.new(Utility.Round(torsoPos.X-2,4)+2, Utility.Round(torsoPos.Y-2,4)+2, Utility.Round(torsoPos.Z-2,4)+2)
			local neighboringCells = {}
			for x = -4, 4, 8 do
				for z = -4, 4, 8 do
					table.insert(neighboringCells, roundedPos + Vector3.new(x,0,z))
				end
			end
			for _, testPoint in pairs(neighboringCells) do
				local pathable = this:CheckOcclusion(roundedPos, testPoint, character, Vector3.new(0,0,0))
				if pathable then
					table.insert(pathablePoints, testPoint)
				end
			end
		end
		return pathablePoints
	end
	
	function this:ComputeDirectPath()
		local humanoid = character:FindFirstChild("Humanoid")
		local torso = humanoid and humanoid.Torso
		if torso then
			local startPt = torso.CFrame.p
			local finishPt = point
			if (finishPt - startPt).magnitude < 150 then
				-- move back the destination by 2 studs or otherwise the pather will collide with the object we are trying to reach
				finishPt = finishPt - (finishPt - startPt).unit * 2
				if this:CheckOcclusion(startPt, finishPt, character, Vector3.new(0,0,0)) then
					local pathResult = {}
					pathResult.Status = Enum.PathStatus.Success
					function pathResult:GetPointCoordinates()
						return {finishPt}
					end
					return pathResult
				end
			end
		end
	end
	
	local function AllAxisInThreshhold(targetPt, otherPt, threshold)
		return math.abs(targetPt.X - otherPt.X) <= threshold and 
			math.abs(targetPt.Y - otherPt.Y) <= threshold and
			math.abs(targetPt.Z - otherPt.Z) <= threshold
	end
	
	function this:ComputePath()
		local smoothed = false
		local humanoid = character:FindFirstChild("Humanoid")
		local torso = humanoid and humanoid.Torso
		if torso then
			if this.PathComputed then return end
			this.PathComputed = true
			-- Will yield the script since it is an Async script (start, finish, maxDistance)
			-- Try to use the smooth function, but it may not exist yet :(
			local success = pcall(function()
				this.pathResult = PathfindingService:ComputeSmoothPathAsync(torso.CFrame.p, point, 400)
				smoothed = true
			end)
			if not success then
				this.pathResult = PathfindingService:ComputeRawPathAsync(torso.CFrame.p, point, 400)
				smoothed = false
			end
			this.pointList = this.pathResult and this.pathResult:GetPointCoordinates()
			local pathFound = false
			if this.pathResult.Status == Enum.PathStatus.FailFinishNotEmpty then
				-- Lets try again with a slightly set back start point; it is ok to do this again so the FailFinishNotEmpty uses little computation
				local diffVector = point - workspace.CurrentCamera.CoordinateFrame.p
				if diffVector.magnitude > 2 then
					local setBackPoint = point - (diffVector).unit * 2.1
					local success = pcall(function()
						this.pathResult = PathfindingService:ComputeSmoothPathAsync(torso.CFrame.p, setBackPoint, 400)
						smoothed = true
					end)
					if not success then
						this.pathResult = PathfindingService:ComputeRawPathAsync(torso.CFrame.p, setBackPoint, 400)
						smoothed = false
					end
					this.pointList = this.pathResult and this.pathResult:GetPointCoordinates()
					pathFound = true
				end
			end
			if this.pathResult.Status == Enum.PathStatus.ClosestNoPath and #this.pointList >= 1 and pathFound == false then
				local otherPt = this.pointList[#this.pointList]
				if AllAxisInThreshhold(point, otherPt, 4) and (torso.CFrame.p - point).magnitude > (otherPt - point).magnitude then
					local pathResult = {}
					pathResult.Status = Enum.PathStatus.Success
					function pathResult:GetPointCoordinates()
						return {this.pointList}
					end
					this.pathResult = pathResult
					pathFound = true
				end
			end
			if (this.pathResult.Status == Enum.PathStatus.FailStartNotEmpty or this.pathResult.Status == Enum.PathStatus.ClosestNoPath) and pathFound == false then
				local pathablePoints = this:CheckNeighboringCells(character)
				for _, otherStart in pairs(pathablePoints) do
					local pathResult;
					local success = pcall(function()
						pathResult = PathfindingService:ComputeSmoothPathAsync(otherStart, point, 400)
						smoothed = true
					end)
					if not success then
						pathResult = PathfindingService:ComputeRawPathAsync(otherStart, point, 400)
						smoothed = false
					end
					if pathResult and pathResult.Status == Enum.PathStatus.Success then
						this.pathResult = pathResult
						if this.pathResult then
							this.pointList = this.pathResult:GetPointCoordinates()
							table.insert(this.pointList, 1, otherStart)
						end
						break
					end
				end
			end
			if DirectPathEnabled then
				if this.pathResult.Status ~= Enum.PathStatus.Success then
					local directPathResult = this:ComputeDirectPath()
					if directPathResult and directPathResult.Status == Enum.PathStatus.Success then
						this.pathResult = directPathResult
						this.pointList = directPathResult:GetPointCoordinates()
					end
				end
			end
		end
		return smoothed
	end
	
	function this:IsValidPath()
		this:ComputePath()
		local pathStatus = this.pathResult.Status
		return pathStatus == Enum.PathStatus.Success
	end
	
	function this:GetPathStatus()
		this:ComputePath()
		return this.pathResult.Status
	end
		
	function this:Start()
		spawn(function()
			local humanoid = character:FindFirstChild("Humanoid")
			--humanoid.AutoRotate = false
			local torso = humanoid and humanoid.Torso
			if torso then		
				if this.Started then return end
				this.Started = true
				-- Will yield the script since it is an Async function script (start, finish, maxDistance)
				local smoothed = this:ComputePath()
				if this:IsValidPath() then
					this.PathStarted:fire()
					-- smooth out zig-zaggy paths
					local smoothPath = smoothed and this.pointList or this:SmoothPoints(this.pointList)
					for i, point in pairs(smoothPath) do
						if humanoid then
							if this.Cancelled then
								return
							end
							
							local wayPoint = nil
							if SHOW_PATH then
								wayPoint = CreateDestinationIndicator(point)
								wayPoint.BrickColor = BrickColor.new("New Yeller")
								wayPoint.Parent = workspace
							end
							
							humanoid:MoveTo(point)
														
							local distance = ((torso.CFrame.p - point) * Vector3.new(1,0,1)).magnitude
							local approxTime = 10
							if math.abs(humanoid.WalkSpeed) > 0 then
								approxTime = distance / math.abs(humanoid.WalkSpeed)
							end
							
							local yielding = true
							
							if i == 1 then
								--local rotatedCFrame = CameraModule:LookAtPreserveHeight(point)
								if CameraModule then
									local rotatedCFrame = CameraModule:LookAtPreserveHeight(smoothPath[#smoothPath])
									local finishedSignal, duration = CameraModule:TweenCameraLook(rotatedCFrame)
								end
								--CharacterControl:SetTorsoLookPoint(point)
							end
							---[[
							if (humanoid.Torso.CFrame.p - point).magnitude > 9 then
								spawn(function()
									while yielding and this.Cancelled == false do
										if CameraModule then
											local look = CameraModule:GetCameraLook()
											local squashedLook = (look * Vector3.new(1,0,1)).unit
											local direction = ((point - workspace.CurrentCamera.CoordinateFrame.p) * Vector3.new(1,0,1)).unit
											
											local theta = math.deg(math.acos(squashedLook:Dot(direction)))
											
											if tick() - Utility.GetLastInput() > 2 and theta > (workspace.CurrentCamera.FieldOfView / 2) then
												local rotatedCFrame = CameraModule:LookAtPreserveHeight(point)
												local finishedSignal, duration = CameraModule:TweenCameraLook(rotatedCFrame)
												--return
											end
										end
										wait(0.1)
									end
								end)
							end
							--]]
							local didReach = this:YieldUntilPointReached(character, point, approxTime * 3 + 1)
							
							yielding = false
							
							if SHOW_PATH then
								wayPoint:Destroy()
							end
							
							if not didReach then
								this.PathFailed:fire()
								return
							end
						end
					end
					
					this.Finished:fire()
					return
				end
			end
			this.PathFailed:fire()
		end)
	end
	
	return this
end

-------------------------------------------------------------------------

local function FlashRed(object)
	local origColor = object.BrickColor
	local redColor = BrickColor.new("Really red")
	local start = tick()
	local duration = 4
	spawn(function()
		while object and tick() - start < duration do
			object.BrickColor = origColor
			wait(0.13)
			if object then
				object.BrickColor = redColor
			end
			wait(0.13)
		end
	end)
end

local joystickWidth = 250
local joystickHeight = 250
local function IsInBottomLeft(pt)
	return pt.X <= joystickWidth and pt.Y > Utility.ViewSizeY() - joystickHeight
end

local function IsInBottomRight(pt)
	return pt.X >= Utility.ViewSizeX() - joystickWidth and pt.Y > Utility.ViewSizeY() - joystickHeight
end

local function CheckAlive(character)
	local humanoid = character and character:FindFirstChild('Humanoid')
	return humanoid ~= nil and humanoid.Health > 0
end

local function GetEquippedTool(character)
	if character ~= nil then
		for _, child in pairs(character:GetChildren()) do
			if child:IsA('Tool') then
				return child
			end
		end
	end	
end

local function ExploreWithRayCast(currentPoint, originDirection)
	local TestDistance = 40
	local TestVectors = {}
	do
		local forwardVector = originDirection;
		for i = 0, 15 do
			table.insert(TestVectors, CFrame.Angles(0, math.pi / 8 * i, 0) * forwardVector)
		end
	end
	
	local testResults = {}
	-- Heuristic should be something along the lines of distance and closeness to the traveling direction
	local function ExploreHeuristic()
		for _, testData in pairs(testResults) do
			local walkDirection = -1 * originDirection
			local directionCoeff = (walkDirection:Dot(testData['Vector']) + 1) / 2
			local distanceCoeff = testData['Distance'] / TestDistance
			testData["Value"] = directionCoeff * distanceCoeff
		end
	end
	
	for i, vec in pairs(TestVectors) do
		local hitPart, hitPos = Utility.Raycast(Ray.new(currentPoint, vec * TestDistance), true, {Player.Character})
		if hitPos then
			table.insert(testResults, {Vector = vec; Distance = (hitPos - currentPoint).magnitude})
		else
			table.insert(testResults, {Vector = vec; Distance = TestDistance})
		end
	end
	
	ExploreHeuristic()
	
	table.sort(testResults, function(a,b) return a["Value"] > b["Value"] end)
	
	return testResults	
end

local TapId = 1
local ExistingPather = nil
local ExistingIndicator = nil
local PathCompleteListener = nil
local PathFailedListener = nil

local function CleanupPath()
	if ExistingPather then
		ExistingPather:Cancel()
	end
	if PathCompleteListener then
		PathCompleteListener:disconnect()
		PathCompleteListener = nil
	end
	if PathFailedListener then
		PathFailedListener:disconnect()
		PathFailedListener = nil
	end
	if ExistingIndicator then
		DebrisService:AddItem(ExistingIndicator, 0)
		ExistingIndicator = nil
	end	
end


local AutoJumperInstance = nil
local ShootCount = 0
local FailCount = 0
local function OnTap(tapPositions)	
	-- Good to remember if this is the latest tap event
	TapId = TapId + 1
	local thisTapId = TapId
	
	
	local camera = workspace.CurrentCamera
	local character = Player.Character

	
	if not CheckAlive(character) then return end
	
	-- This is a path tap position
	if #tapPositions == 1 then
		-- Filter out inputs that are by the sticks.
		if UIS.ModalEnabled == false and (IsInBottomRight(tapPositions[1]) or IsInBottomLeft(tapPositions[1])) then return end
		if camera then
			local unitRay = Utility.GetUnitRay(tapPositions[1].x, tapPositions[1].y, MyMouse.ViewSizeX, MyMouse.ViewSizeY, camera)
			local ray = Ray.new(unitRay.Origin, unitRay.Direction*400)
			local hitPart, hitPt = Utility.Raycast(ray, true, {character})
			
			local hitChar, hitHumanoid = Utility.FindChacterAncestor(hitPart)
			local torso = character and character:FindFirstChild("Humanoid") and character:FindFirstChild("Humanoid").Torso
			local startPos = torso.CFrame.p
			if hitChar and hitHumanoid and hitHumanoid.Torso and (hitHumanoid.Torso.CFrame.p - torso.CFrame.p).magnitude < 7 then
				CleanupPath()
				
				character:FindFirstChild("Humanoid"):MoveTo(hitPt)
				
				ShootCount = ShootCount + 1
				local thisShoot = ShootCount
				-- Do shooot
				local currentWeapon = GetEquippedTool(character)
				if currentWeapon then
					currentWeapon:Activate()
					LastFired = tick()
				end
			elseif hitPt and character then
				local thisPather = Pather(character, hitPt)
				if thisPather:IsValidPath() then
					FailCount = 0
					-- TODO: Remove when bug in engine is fixed
					Player:Move(Vector3.new(1, 0, 0))
					Player:Move(Vector3.new(0, 0, 0))
					thisPather:Start()
					if BindableEvent_OnFailStateChanged then
						BindableEvent_OnFailStateChanged:Fire(false)
					end
--					if CameraModule then
--						CameraModule:Start()
--					end
					CleanupPath()
				
					local destinationGlobe = CreateDestinationIndicator(hitPt)
					destinationGlobe.Parent = camera
					
					ExistingPather = thisPather
					ExistingIndicator = destinationGlobe
									
					if AutoJumperInstance then
						AutoJumperInstance:Run()
					end
					
					PathCompleteListener = thisPather.Finished:connect(function()
						if AutoJumperInstance then
							AutoJumperInstance:Stop()
						end
						if destinationGlobe then
							if ExistingIndicator == destinationGlobe then
								ExistingIndicator = nil
							end
							DebrisService:AddItem(destinationGlobe, 0)
							destinationGlobe = nil
						end
						if hitChar then
							local humanoid = character:FindFirstChild("Humanoid")
							ShootCount = ShootCount + 1
							local thisShoot = ShootCount
							-- Do shoot
							local currentWeapon = GetEquippedTool(character)
							if currentWeapon then
								currentWeapon:Activate()
								LastFired = tick()
							end
							if humanoid then
								humanoid:MoveTo(hitPt)
							end
						end
						local finishPos = torso and torso.CFrame.p --hitPt
						if finishPos and startPos and tick() - Utility.GetLastInput() > 2 then
							local exploreResults = ExploreWithRayCast(finishPos, ((startPos - finishPos) * Vector3.new(1,0,1)).unit)
							-- Check for Nans etc..
							if exploreResults[1] and exploreResults[1]["Vector"] and exploreResults[1]["Vector"].magnitude >= 0.5 and exploreResults[1]["Distance"] > 3 then
								if CameraModule then
									local rotatedCFrame = CameraModule:LookAtPreserveHeight(finishPos + exploreResults[1]["Vector"] * exploreResults[1]["Distance"])
									local finishedSignal, duration = CameraModule:TweenCameraLook(rotatedCFrame)
								end
							end
						end
					end)
					PathFailedListener = thisPather.PathFailed:connect(function()
						if AutoJumperInstance then
							AutoJumperInstance:Stop()
						end
						if destinationGlobe then
							FlashRed(destinationGlobe)
							DebrisService:AddItem(destinationGlobe, 3)
						end
					end)
				else
					if hitPt then
						-- Feedback here for when we don't have a good path
						local failedGlobe = CreateDestinationIndicator(hitPt)
						FlashRed(failedGlobe)
						DebrisService:AddItem(failedGlobe, 1)
						failedGlobe.Parent = camera
						if ExistingIndicator == nil then
							FailCount = FailCount + 1
							if FailCount >= 3 then
								if BindableEvent_OnFailStateChanged then
									BindableEvent_OnFailStateChanged:Fire(true)
								end
--								if CameraModule then
--									CameraModule:Stop()
--								end
								workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
								CleanupPath()
							end
						end
					end
				end
			else
				-- no hit pt
			end
		end
	elseif #tapPositions >= 2 then
		if camera then
			ShootCount = ShootCount + 1
			local thisShoot = ShootCount
			-- Do shoot
			local avgPoint = Utility.AveragePoints(tapPositions)
			local unitRay = Utility.GetUnitRay(avgPoint.x, avgPoint.y, MyMouse.ViewSizeX, MyMouse.ViewSizeY, camera)
			local currentWeapon = GetEquippedTool(character)
			if currentWeapon then
				currentWeapon:Activate()
				LastFired = tick()
			end
		end
	end
end

local function SetUpGestureRecognizers()
	local MAX_FINGERS = 11
	local InputHistory = {}
	
	local function FindInputObject(inputObject)
		for i = 1, #InputHistory do
			if InputHistory[i] == inputObject then
				return InputHistory[i], i
			end
		end
	end
	
	local function PopInput(inputObject)
		local _, i = FindInputObject(inputObject)
		if i then
			table.remove(InputHistory, i)
			return true
		end
		return false
	end
	
	local function PushInput(inputObject)
		-- Make sure it isn't in the list already
		if FindInputObject(inputObject) then return false end
		
		if #InputHistory >= MAX_FINGERS then
			-- Pop old dead inputs when we maxxed out
			for i = 1, #InputHistory do
				if InputHistory[i].UserInputState == Enum.UserInputState.End then
					table.remove(InputHistory, i)
					break
				end
			end
		end
		if #InputHistory >= MAX_FINGERS then
			print("No more room for input; failing to add input")
			for i = 1, #InputHistory do
				print(tostring(i) .. ":" .. tostring(inputObject.UserInputState))
			end
			
			return false
		end
		
		
		local startPos = Instance.new("Vector3Value")
		startPos.Value = inputObject.Position -- Vector3.new(inputObject.Position.X, inputObject.Position.Y, 0)
		startPos.Name = "StartPos" -- Have to use Vector3value because there is no vector2 value
		startPos.Parent = inputObject
		
		local startTime = Instance.new("NumberValue")
		startTime.Value = tick()
		startTime.Name = "StartTime"
		startTime.Parent = inputObject
		
		
		table.insert(InputHistory, inputObject)
		return true
	end
	
	
	UIS.InputBegan:connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.Touch then
			PushInput(inputObject)
			
			local wasInBottomLeft = IsInBottomLeft(inputObject.Position)
			local wasInBottomRight = IsInBottomRight(inputObject.Position)
			if wasInBottomRight or wasInBottomLeft then
				for i, otherInput in pairs(InputHistory) do
					local otherInputInLeft = IsInBottomLeft(otherInput.Position)
					local otherInputInRight = IsInBottomRight(otherInput.Position)
					if otherInput.UserInputState ~= Enum.UserInputState.End and ((wasInBottomLeft and otherInputInRight) or (wasInBottomRight and otherInputInLeft)) then
						-- TODO: Is this still a valid code path?
						UIS.ModalEnabled = false
						if CameraModule then
							CameraModule:Stop()
						end
						workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
					end
				end
			end
		end
	end)
	
	UIS.InputEnded:connect(function(inputObject)
		if inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		
		do
			local lookedUpObject = FindInputObject(inputObject)
			
			local endTime = Instance.new("NumberValue")
			endTime.Value = tick()
			endTime.Name = "EndTime"
			endTime.Parent = lookedUpObject
		end
	end)
end


local function CreateClickToMoveModule()
	local this = {}
	
	local LastStateChange = 0
	local LastState = Enum.HumanoidStateType.Running
	local LastMouseUpTime = 0
	
	local TapConn = nil
	local MouseUpConn = nil
	local MouseDownConn = nil
	local MouseButton2DownConn = nil
	local RotateConn = nil
	local MouseWheelBackwardConn = nil
	local MouseWheelForwardConn = nil
	local HumanoidDiedConn = nil
	local CharacterChildAddedConn = nil
	local KeyboardInputBeganConn = nil
	local OnCharacterAddedConn = nil
	
	local function disconnectEvent(event)
		if event then
			event:disconnect()
		end
	end
	
	local function DisconnectEvents()
		disconnectEvent(TapConn)
		disconnectEvent(MouseUpConn)
		disconnectEvent(MouseDownConn)
		disconnectEvent(MouseButton2DownConn)
		disconnectEvent(MouseWheelForwardConn)
		disconnectEvent(MouseWheelBackwardConn)
		disconnectEvent(RotateConn)
		disconnectEvent(HumanoidDiedConn)
		disconnectEvent(CharacterChildAddedConn)
		disconnectEvent(KeyboardInputBeganConn)
		disconnectEvent(OnCharacterAddedConn)
	end
	
	
	-- Setup the camera
	CameraModule = CreateCamera()

	local function OnCharacterAdded(character)
		DisconnectEvents()
		
		
		if UIS.TouchEnabled then -- Mobile	
			SetUpGestureRecognizers()
			
			TapConn = UIS.TouchTap:connect(function(touchPositions, sunk)				
				if not sunk then
					OnTap(touchPositions)
				end
			end)
			
			MouseUpConn = MyMouse.Button1Up:connect(function()
				LastMouseUpTime = tick()
			end)
			
			local function OnCharacterChildAdded(child)
				if child:IsA('Tool') then
					child.ManualActivationOnly = true
				elseif child:IsA('Humanoid') then
					disconnectEvent(HumanoidDiedConn)
					HumanoidDiedConn = child.Died:connect(function()
						DebrisService:AddItem(ExistingIndicator, 1)		
						if AutoJumperInstance then
							AutoJumperInstance:Stop()
							AutoJumperInstance = nil
						end
					end)
				end
			end
			
			CharacterChildAddedConn = character.ChildAdded:connect(function(child)
				OnCharacterChildAdded(child)
			end)
			for _, child in pairs(character:GetChildren()) do
				OnCharacterChildAdded(child)
			end
		else -- PC
			if AutoJumperInstance then
				AutoJumperInstance:Stop()
				AutoJumperInstance = nil
			end
			AutoJumperInstance = AutoJumper()
			-- PC simulation
			local mouse1Down = tick()
			local mouse1DownPos = Vector2.new()
			local mouse1Up = tick()
			local mouse2Down = tick()
			local mouse2DownPos = Vector2.new()
			local mouse2Up = tick()
			
			local movementKeys = {
				[Enum.KeyCode.W] = true;
				[Enum.KeyCode.A] = true;
				[Enum.KeyCode.S] = true;
				[Enum.KeyCode.D] = true;
				[Enum.KeyCode.Up] = true;
				[Enum.KeyCode.Down] = true;
			}
			
			KeyboardInputBeganConn = UIS.InputBegan:connect(function(inputObject, processed)
				if processed then return end
				if inputObject.UserInputType == Enum.UserInputType.Keyboard and movementKeys[inputObject.KeyCode] then
					 CleanupPath() -- Cancel path when you use the keyboard controls.
				end
			end)
			
			MouseDownConn = MyMouse.Button1Down:connect(function()
				mouse1Down = tick()
				mouse1DownPos = Vector2.new(MyMouse.X, MyMouse.Y)
			end)
			MouseButton2DownConn = MyMouse.Button2Down:connect(function()
				mouse2Down = tick()
				mouse2DownPos = Vector2.new(MyMouse.X, MyMouse.Y)
			end)
			MouseUpConn = MyMouse.Button2Up:connect(function()
				mouse2Up = tick()			
				local currPos = Vector2.new(MyMouse.X, MyMouse.Y)
				if mouse2Up - mouse2Down < 0.25 and (currPos - mouse2DownPos).magnitude < 5 then
					local positions = {currPos}
					OnTap(positions)
				end
			end)
			MouseWheelBackwardConn = MyMouse.WheelBackward:connect(function()
				Player.CameraMode = Enum.CameraMode.Classic
			end)
			MouseWheelForwardConn = MyMouse.WheelForward:connect(function()
				if (workspace.CurrentCamera.CoordinateFrame.p - workspace.CurrentCamera.Focus.p).magnitude < 0.8 then
					Player.CameraMode = Enum.CameraMode.LockFirstPerson
				end
			end)
		end
	end
	
	local Running = false
	
	function this:Stop()
		if Running then
			DisconnectEvents()
			CleanupPath()
			if AutoJumperInstance then
				AutoJumperInstance:Stop()
				AutoJumperInstance = nil
			end
			if CameraModule then
				CameraModule.On = false
			end
			Running = false
		end
	end
	
	function this:Start()
		if not Running then
			if Player.Character then -- retro-listen
				OnCharacterAdded(Player.Character)
			end
			OnCharacterAddedConn = Player.CharacterAdded:connect(OnCharacterAdded)
			if CameraModule then
				CameraModule.On = true
			end
			Running = true
		end
	end
	
	return this
end

return CreateClickToMoveModule
