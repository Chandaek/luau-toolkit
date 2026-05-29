local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IsServer = RunService:IsServer()

local RootFolderName = "_PacketStream"

local PacketTypeEphemeral = 0
local PacketTypePersistentFull = 1
local PacketTypeDelta = 2
local PacketTypeStreamStart = 3
local PacketTypeStreamUpdate = 4
local PacketTypeStreamStop = 5
local PacketTypeKeyDelivery = 6
local PacketTypeKeyAck = 7

local SendModeNormal = "Normal"
local SendModeInstancing = "Instancing"

local function _FnvHash(Name: string): (number)
	local Hash = 2166136261
	for Index = 1, #Name do
		Hash = bit32.bxor(Hash, string.byte(Name, Index))
		Hash = bit32.band(Hash * 16777619, 0xFFFFFFFF)
	end
	return Hash
end

local function _GetRootFolder(): (Folder)
	if IsServer then
		local Existing = ReplicatedStorage:FindFirstChild(RootFolderName)
		if Existing then return Existing :: Folder end
		local Folder = Instance.new("Folder")
		Folder.Name = RootFolderName
		Folder.Parent = ReplicatedStorage
		return Folder
	end
	return ReplicatedStorage:WaitForChild(RootFolderName) :: Folder
end

local function _GetOrCreateChild(Parent: Instance, Name: string, ClassName: string): (Instance)
	if IsServer then
		local Existing = Parent:FindFirstChild(Name)
		if Existing then return Existing end
		local Child = Instance.new(ClassName)
		Child.Name = Name
		Child.Parent = Parent
		return Child
	end
	return Parent:WaitForChild(Name)
end

local function _CreateTopicRegistry(): (any)
	local NameToId: {[string]: number} = {}
	local IdToName: {[number]: string} = {}
	return {
		Register = function(Name: string): (number)
			if NameToId[Name] then return NameToId[Name] end
			local Id = _FnvHash(Name)
			assert(not IdToName[Id], `[PacketStream] Topic hash collision: "{Name}" collides with "{IdToName[Id]}"`)
			NameToId[Name] = Id
			IdToName[Id] = Name
			return Id
		end,
		Resolve = function(Name: string): (number?)
			return NameToId[Name]
		end,
		ResolveName = function(Id: number): (string?)
			return IdToName[Id]
		end,
	}
end

return {
	IsServer = IsServer,
	RootFolderName = RootFolderName,
	PacketTypeEphemeral = PacketTypeEphemeral,
	PacketTypePersistentFull = PacketTypePersistentFull,
	PacketTypeDelta = PacketTypeDelta,
	PacketTypeStreamStart = PacketTypeStreamStart,
	PacketTypeStreamUpdate = PacketTypeStreamUpdate,
	PacketTypeStreamStop = PacketTypeStreamStop,
	PacketTypeKeyDelivery = PacketTypeKeyDelivery,
	PacketTypeKeyAck = PacketTypeKeyAck,
	SendModeNormal = SendModeNormal,
	SendModeInstancing = SendModeInstancing,
	GetRootFolder = _GetRootFolder,
	GetOrCreateChild = _GetOrCreateChild,
	CreateTopicRegistry = _CreateTopicRegistry,
}