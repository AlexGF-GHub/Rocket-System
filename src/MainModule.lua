--[[
	Rocket System III: MainModule
	Authors: Sublivion
	Created: April 12 2019
	
	https://github.com/Sublivion/Rocket-System-III
--]]

--[[
	MIT License

	Copyright (c) 2019 Anthony O'Brien (Sublivion)
	
	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
--]]


--[[
	DOCUMENTATION
	
	
	REQUIRE:
		
		rs = require(thisModule)
	
	
	CLASS ROCKET:
		
		CONSTRUCTOR:
		
			rs.Rocket.new(stage1, stage2, stage3, ...)
			
				ARGUMENTS:
					- stage: A table containing settings about each stage
				
				RETURNS:
					- Class 'rocket', consisting of:
						- All methods and properties
						
				DOES:
					- Creates a welded clone of the stages in Workspace
					- Creates a main part to hold body movers
					- Creates BodyMovers
		
		
		METHODS:
		
			Rocket:update()
					
				DOES:
					- Updates BodyMovers
					- Updates sound
		
		
			Rocket.stages.stageName:setThrottle(t)
			
				ARGUMENTS:
					- t: The desired throttle as a decimal - 0 to 1
			
				DOES:
					- Updates the stages' throttle
					- Notifies script that throttle is changed
			
			
			Rocket.stages.stageName:separate(separateFrom)
			
				ARGUMENTS:
					- separateFrom: The rocket class to separate from
			
				DOES:
					- Breaks joints attaching the stage to the main part
					- Creates new rocket for the separated stage
				
				RETURNS:
					- New rocket class for the separated stage
	
					
	NOTES:
	
		- Rocket System III uses SI units - as opposed to imperial units found in v1 and v2
--]]

-- Constants
SCALE = 0.28 -- studs/meters
GRAV = 6.673E-11
EARTH_MASS = 5.972E+24
EARTH_RADIUS = 6371E+3
DENSITY_ASL = 1.225
ATMOS_END = 100000
TEMPERATURE = 15
HUMIDITY = 0.75

-- Math functions
log = math.log
rad = math.rad
exp = math.exp
sin = math.sin
sqrt = math.sqrt
clamp = math.clamp
rabs = math.abs

-- Constructors
newInstance = Instance.new
V3 = Vector3.new


-- Functions

function getParts(m)
	local t = {}
	for i,v in pairs(m:GetDescendants()) do
		if v:IsA("BasePart") then table.insert(t,v) end
	end
	return t
end

function getModelCentre(model)
	local sX,sY,sZ
	local mX,mY,mZ
	for i, v in pairs(getParts(model)) do
		if v.Name ~= 'PrimaryPart' and v ~= model.PrimaryPart then
			local pos = v.CFrame.p
			sX = (not sX and pos.x) or (pos.x < sX and pos.x or sX)
			sY = (not sY and pos.y) or (pos.y < sY and pos.y or sY)
			sZ = (not sZ and pos.z) or (pos.z < sZ and pos.z or sZ)
			mX = (not mX and pos.x) or (pos.x > mX and pos.x or mX)
			mY = (not mY and pos.y) or (pos.y > mY and pos.y or mY)
			mZ = (not mZ and pos.z) or (pos.z > mZ and pos.z or mZ)
		end
	end
	
	return V3((sX+mX)/2,(sY+mY)/2,(sZ+mZ)/2)
end

function getDensity(h)
    local t=(h<11000 and TEMPERATURE-((56.46+TEMPERATURE)*(h/11000))) or (h<25000 and -56.46) or -131.21+.00299*h
    local kpa=(h<11000 and 101.29*(((t+273.1)/288.08)^5.256)) or (h<25000 and 22.65*exp(1.73-.000157*h)) or 2.488*(((t+273.1)/216.6)^-11.388)
	return ((kpa/(.2869*(t+273.1)))*(1+HUMIDITY)/(1+(461.5/286.9)*HUMIDITY)) * DENSITY_ASL
end

function getMass(container)
	local mass = 0
	for i, v in pairs(getParts(container)) do
		mass = mass + v:GetMass()
	end
	return mass
end

function getDrag(density, velocity, area, coefficient)
	return (velocity * abs(velocity) * density) / 2 * area * coefficient
end

function abs(x)
	return typeof(x) == 'number' and rabs(x) or 'vector3' and V3(rabs(x.x), rabs(x.y), rabs(x.z))
end


-- Private Class Stage
do
	Stage = {}
	Stage.__index = Stage
	
	-- Constructor
	
	function Stage.new(tab)
		local self = tab
		self.throttle = 0
		if not self.propellant or not self.mass then
			self.propellant = self.wetMass - self.dryMass
			self.mass = self.wetMass
		end
		setmetatable(self, Stage)
		return self
	end
	
	-- Methods
	
	function Stage:setThrottle(t)
		self.throttle = t
	end
	
	function Stage:separate(rocket)
		if rocket and rocket.model and rocket.model.PrimaryPart then
			self.model.PrimaryPart.StageConnector:Destroy()
			self.model.Parent = workspace
			rocket:removeStage(self.name)
		else
			warn('Argument 1 invalid or nil in method :separate()')
		end
		
		return Rocket.new(self)
	end
end


-- Public Class Rocket
do
	Rocket = {}
	Rocket.__index = Rocket
	
	-- Constructor
	
	function Rocket.new(...)
		local self = {}
		setmetatable(self, Rocket)
		
		-- Create model
		self.model = newInstance('Model')
		self.model.Name = 'Rocket System III'
		
		-- Create stages
		local stages = {...}
		self.stages = {}
		for i, v in pairs(stages) do
			if v.name and v.model and v.specificImpulseASL and v.specificImpulseVac 
			and v.wetMass and v.dryMass and v.burnRate and v.dragCoefficient then
				if v.model.PrimaryPart then
					if not self.stages[v.name] then
						local stage = Stage.new(v)
						self.stages[v.name] = stage
						stage.model.Parent = self.model
					else
						warn('A stage with the name', v.name, 'already exists.')
					end
				else
					warn('No PrimaryPart set for', v.name)
				end
			else
				warn('Incorrect stage configuration for', v.name and v.name or 'an unnamed stage')
			end
		end
		
		-- Create PrimaryPart
		self.model.PrimaryPart = newInstance('Part')
		self.model.PrimaryPart.Parent = self.model
		self.model.PrimaryPart.Name = 'PrimaryPart'
		self.model.PrimaryPart.CFrame = CFrame.new(getModelCentre(self.model))
		self.model.PrimaryPart.Transparency = 1
		self.model.PrimaryPart.CanCollide = false
		
		-- Create BodyMovers
		self.bodyVelocity = newInstance('BodyVelocity')
		self.bodyGyro = newInstance('BodyGyro')
		self.bodyVelocity.MaxForce = V3()
		self.bodyVelocity.P = 0
		self.bodyVelocity.Velocity = V3()
		self.bodyGyro.CFrame = self.model.PrimaryPart.CFrame
		self.bodyGyro.MaxTorque = V3()
		self.bodyGyro.P = 0
		self.bodyVelocity.Parent = self.model.PrimaryPart
		self.bodyGyro.Parent = self.model.PrimaryPart
		
		-- Create welds
		for _, stage in pairs(self.stages) do
			-- Weld parts
			for i, v in pairs(getParts(stage.model)) do
				if v ~= stage.model.PrimaryPart then
					v.Anchored = false
					local weld = newInstance('WeldConstraint')
					weld.Name = 'RocketWeld'
					weld.Part0 = stage.model.PrimaryPart
					weld.Part1 = v
					weld.Parent = stage.model.PrimaryPart
				end
			end
			-- Create stage connectors
			local weld = newInstance('WeldConstraint')
			weld.Name = 'StageConnector'
			weld.Part1 = stage.model.PrimaryPart
			weld.Part0 = self.model.PrimaryPart
			weld.Parent = stage.model.PrimaryPart
			stage.model.PrimaryPart.Anchored = false
		end
		
		-- Calculate mass
		self.robloxMass = getMass(self.model)
		
		-- Parent rocket
		self.model.Parent = workspace
		
		return self
	end
	
	-- Methods
	
	local dt = 0
	local lastTick = tick()
	function Rocket:update()
		-- Calculate delta time
		dt = tick() - lastTick
		lastTick = tick()
		
		-- Performance stats
		local velocity = self.model.PrimaryPart.Velocity * SCALE -- m/s
		local altitude = self.model.PrimaryPart.CFrame.y * SCALE -- m
		
		-- Update sound
		
		-- Update effects
		
		-- Calculate propellant and mass
		local mass = 0
		for i, v in pairs(self.stages) do
			v.propellant = clamp(v.propellant - v.burnRate * v.throttle * dt, 0, v.wetMass - v.dryMass)
			v.mass = v.dryMass + v.propellant
			mass = mass + v.mass
		end
		self.mass = mass
		
		-- The rocket equation
		local dv = 0
		for i, v in pairs(self.stages) do
			local specificImpulse = ((altitude * v.specificImpulseVac / ATMOS_END) + v.specificImpulseASL) * v.throttle
			dv = dv + (clamp(v.propellant, 0, 1) 
				    * (specificImpulse * log(v.wetMass / v.dryMass)))
				    / (v.mass / v.dryMass)
		end
		
		-- Calculate air density
		local density = altitude < ATMOS_END and getDensity(altitude) or 0
		
		-- Calculate drag (for y axis, only on highest or lowest stagedepending on direction)
		local drag = V3()
		local frontalStage, highestStage, lowestStage, highestHeight, lowestHeight
		for i, v in pairs(self.stages) do
			if not highestHeight or v.model.PrimaryPart.CFrame.y > highestHeight then
				highestStage = v
				highestHeight = v.model.PrimaryPart.CFrame.y
			end
			if not lowestHeight or v.model.PrimaryPart.CFrame.y < lowestHeight then
				lowestStage = v
				lowestHeight = v.model.PrimaryPart.CFrame.y
			end
			local eSize = v.model:GetExtentsSize() * SCALE
			local xArea, zArea = eSize.x * eSize.y, eSize.z * eSize.y
			drag = drag + getDrag(density, velocity, Vector3.new(xArea, 0, zArea), v.dragCoefficient)
		end
		frontalStage = velocity.y > 0 and highestStage or lowestStage
		local eSize = frontalStage.model:GetExtentsSize() * SCALE
		drag = V3(drag.x, getDrag(density, velocity.y, eSize.x * eSize.z, frontalStage.dragCoefficient.y), drag.z)
		
		-- Calculate gravity
		local orbitalSpeed = sqrt(GRAV * EARTH_MASS) / (EARTH_RADIUS + altitude)
		local horizontalSpeed = sqrt(velocity.x^2, velocity.z^2)
		local gravitationalAcceleration = ((GRAV * EARTH_MASS) / (EARTH_RADIUS + altitude)^2) * (horizontalSpeed - orbitalSpeed) / orbitalSpeed
		
		-- Update body velocity
		local acceleration = (self.model.PrimaryPart.CFrame.upVector * dv) - (drag / self.robloxMass) + V3(0, gravitationalAcceleration, 0)
		self.bodyVelocity.Velocity = self.bodyVelocity.Velocity + (acceleration / SCALE * dt)
		self.bodyVelocity.MaxForce = V3(0, workspace.Gravity * self.robloxMass, 0) + (acceleration * self.robloxMass * workspace.Gravity)
		self.bodyVelocity.P = self.bodyVelocity.Velocity.Magnitude * self.bodyVelocity.MaxForce.Magnitude
		
		-- Update body gyro
		self.bodyGyro.CFrame = self.bodyGyro.CFrame -- velocity.unit
		self.bodyGyro.MaxTorque = V3()
	end
	
	function Rocket:removeStage(stage)
		self.stages[stage] = nil
		self.model.PrimaryPart.CFrame = CFrame.new(getModelCentre(self.model))
		print(CFrame.new(getModelCentre(self.model)))
		self.robloxMass = getMass(self.model)
	end
end


-- Exports
return {Rocket = Rocket}
