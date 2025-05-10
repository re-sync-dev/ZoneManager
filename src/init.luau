--[==[

	[ZoneManager.luau]:
		Simple and straight forward zone management module

	[Author(s)]:
		- Vyon (https://github.com/Vyon)

--]==]

-- Services:
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Modules:
local Packages = script:FindFirstChild("Packages") or script.Parent
local Signal = require(Packages.Signal)

-- Types:
-- 	Private:
type Connection<U...> = {
	Connected: boolean,

	Disconnect: (self: Connection<U...>) -> (),
	Reconnect: (self: Connection<U...>) -> (),
}

type Signal<T...> = {
	RBXScriptConnection: RBXScriptConnection?,

	Connect: <U...>(self: Signal<T...>, fn: (T...) -> (), U...) -> Connection<U...>,
	Once: <U...>(self: Signal<T...>, fn: (T...) -> (), U...) -> Connection<U...>,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

--[=[

	@within ZoneManager
	@type ZoneRef BasePart | Model

]=]
type ZoneRef = BasePart | Model

-- 	Public:
--[=[

	@within ZoneManager
	@interface ZoneInfo
	.Active boolean,
	.Name string,
	.Ref ZoneRef,
	.Occupants { Player }

]=]
export type ZoneInfo = {
	Active: boolean,
	Name: string,
	Ref: ZoneRef,
	Occupants: { Player },
}

export type ZoneManager = {
	CheckRate: number,
	Zones: { [ZoneRef]: ZoneInfo },

	OnEntered: Signal<(Player, ZoneInfo)>,
	OnExited: Signal<(Player, ZoneInfo)>,

	Register: (self: ZoneManager, ZoneRef: ZoneRef) -> ZoneInfo,
	Deregister: (self: ZoneManager, ZoneRef: ZoneRef) -> (),

	GetZoneFromPlayer: (self: ZoneManager, Player: Player) -> ZoneInfo?,
}

-- Functions:
--[=[

	@within ZoneManager
	@function InBounds
	@param Ref BasePart | Model
	@param Position Vector3
	@return boolean
	@ignore
		
	Determines whether the provided position is within the Zone's bounding box

]=]
local function InBounds(Ref: BasePart | Model, Position: Vector3)
	local Origin, Size

	if Ref:IsA("Model") then
		Origin, Size = Ref:GetBoundingBox()
	else
		Origin, Size = Ref.CFrame, Ref.Size
	end

	-- NOTE: We take a cframe based approach in case the object's pivot
	-- is rotated
	local LocalPosition = Origin:PointToObjectSpace(Position)

	return math.abs(LocalPosition.X) <= Size.X / 2
		and math.abs(LocalPosition.Y) <= Size.Y / 2
		and math.abs(LocalPosition.Z) <= Size.Z / 2
end

-- Main Module:
--[=[

	@class ZoneManager

]=]
local ZoneManager = {} :: ZoneManager

--[=[

	@within ZoneManager
	@prop CheckRate number

	The rate in which zones are checked

]=]
ZoneManager.CheckRate = 0.1

--[=[

	@within ZoneManager
	@prop Zones {[ZoneRef]: ZoneInfo}

	Table of all currently active zones

]=]
ZoneManager.Zones = {}

--[=[

	@within ZoneManager
	@prop OnEntered Signal<(Player, ZoneInfo)>

	Fires when a player enters a zone

	Example:
	```lua
	ZoneManager.OnEntered:Connect(function(Player: Player, Zone: ZoneInfo)
		if Zone.Name == "ForbiddenZone" then
			Player:Kick("You entered the forbidden zone 🤯")
		end
	end)
	```

]=]
ZoneManager.OnEntered = Signal.new()

--[=[

	@within ZoneManager
	@prop OnEntered Signal<(Player, ZoneInfo)>

	Fires when a player exits a zone

	Example:
	```lua
	ZoneManager.OnExited:Connect(function(Player: Player, Zone: ZoneInfo)
		if Zone.Name == "SafeZone" then
			Player:SetAttribute("Safe", false)
		end
	end)
	```

]=]
ZoneManager.OnExited = Signal.new()

--[=[

	@within ZoneManager
	@method Register
	@param ZoneRef ZoneRef

	Creates a 'ZoneInfo' object and pushes the object to the cache aka ZoneManager.Zones.
	This method is called automatically for zones registered using the [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tag 'Zone'

]=]
function ZoneManager:Register(ZoneRef: ZoneRef)
	-- Param sanitization:
	assert(typeof(ZoneRef) == "Instance" and (ZoneRef:IsA("BasePart") or ZoneRef:IsA("Model")))

	-- Has the zone already been registered?
	if self.Zones[ZoneRef] then
		warn(`[ZoneManager]:`, ZoneRef, "has already been registered")

		return self.Zones[ZoneRef]
	end

	local Options = {
		Alias = nil :: string?,
	}

	do -- Get and validate attribute option(s):
		local Alias = ZoneRef:GetAttribute("Alias") :: string?

		if Alias and typeof(Alias) ~= "string" then
			warn(`[ZoneManager]: Invalid zone attribute 'Alias' ({Alias}) found for:`, ZoneRef)
			Options.Alias = nil
		end
	end

	local Info: ZoneInfo = {
		Active = true,
		Name = Options.Alias or ZoneRef.Name,
		Ref = ZoneRef,
		Occupants = {},
	}

	self.Zones[ZoneRef] = Info

	return self.Zones[ZoneRef]
end

--[=[

	@within ZoneManager
	@method Deregister
	@param ZoneRef ZoneRef

	Removes the provided ZoneRef from the cache and also cleans the ZoneInfo object

]=]
function ZoneManager:Deregister(ZoneRef: ZoneRef)
	-- Param sanitization:
	assert(typeof(ZoneRef) == "Instance" and (ZoneRef:IsA("BasePart") or ZoneRef:IsA("Model")))

	-- Has the zone not been registered?
	if not self.Zones[ZoneRef] then
		warn(`[ZoneManager]:`, ZoneRef, "has not been registered")

		return
	end

	local Info = self.Zones[ZoneRef]

	self.Zones[ZoneRef] = nil --> Dereference zone info

	Info.Active = false --> Prevent the zone from updating whilst being de-registered
	Info.Ref = nil --> Dereference zone instance

	table.clear(Info.Occupants) --> Clear references to players in the zone
	table.clear(Info) --> Clear keys & values from the 'ZoneInfo' object
end

--[=[

	@within ZoneManager
	@method GetZoneFromPlayer
	@param Player Player
	@return ZoneInfo?

	Attempts to get the zone the player is currently in

]=]
function ZoneManager:GetZoneFromPlayer(Player: Player)
	-- Param sanitization:
	assert(typeof(Player) == "Instance" and Player:IsA("Player"))

	local Result

	-- Iterate over cached zones:
	for _, Info in self.Zones do
		-- Is the zone inactive?
		if not Info.Active then
			continue
		end

		-- Is the player not an occupant of the zone?
		if not table.find(Info.Occupants, Player) then
			continue
		end

		-- Set the function result and exit the loop:
		Result = Info
		break
	end

	return Result
end

-- Init:
for _, ZoneRef in CollectionService:GetTagged("Zone") do
	ZoneManager:Register(ZoneRef)
end

-- Connections:
CollectionService:GetInstanceAddedSignal("Zone"):Connect(function(ZoneRef: ZoneRef)
	ZoneManager:Register(ZoneRef)
end)

CollectionService:GetInstanceRemovedSignal("Zone"):Connect(function(ZoneRef: ZoneRef)
	ZoneManager:Deregister(ZoneRef)
end)

-- Check zones for activity:
task.defer(function()
	while RunService:IsRunning() do
		-- Begin looping over zones:
		for ZoneRef, Info in ZoneManager.Zones do
			-- Is the zone inactive?
			if not Info.Active then
				continue
			end

			-- Is the zone not a descendent of the workspace?
			if not ZoneRef:IsDescendantOf(workspace) then
				continue
			end

			-- Check if the players are within the zone bounds:
			for _, Player in Players:GetPlayers() do
				local Character = Player.Character

				-- Is the character not within in the workspace?
				if not Character or not Character:IsDescendantOf(workspace) then
					continue
				end

				-- Get the player's current location:
				local Location = Character:GetPivot()

				-- Is the player's character is within the zone's boundaries?
				if InBounds(ZoneRef, Location.Position) then
					-- If the player is not already an occupant:
					if table.find(Info.Occupants, Player) == nil then
						table.insert(Info.Occupants, Player)

						ZoneManager.OnEntered:Fire(Player, Info)
					end

				-- Was the player in the list of occupants last check?
				elseif table.find(Info.Occupants, Player) ~= nil then
					local Index = table.find(Info.Occupants, Player)

					if Index then
						table.remove(Info.Occupants, Index)
					end

					ZoneManager.OnExited:Fire(Player, Info)
				end
			end
		end

		task.wait(ZoneManager.CheckRate)
	end
end)

return ZoneManager
