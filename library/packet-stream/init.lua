local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local EventEmitter = (function()
	local Ok, Result = pcall(require, "../Common/EventEmitter")
	if not Ok or not Result then
		warn("[PacketStream] Dependency not found: EventEmitter (../Common/EventEmitter)")
		return nil
	end
	return Result
end)()

local SecureStorage = (function()
	local Ok, Result = pcall(require, "./SecureStorage")
	if not Ok or not Result then
		return nil
	end
	return Result
end)()

local Codec = require("@self/Codec")
local Encryption = require("@self/Encryption")
local PingProtocol = require("@self/PingProtocol")
local FlagSchema = require("@self/FlagSchema")

assert(EventEmitter, "[PacketStream] Cannot start without EventEmitter")

local IsServer = RunService:IsServer()

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

local RootFolderName = "_PacketStream"

export type SendMode = "Normal" | "Instancing"
export type StreamHandle = {
	Update: (Data: any) -> (),
	Stop: () -> (),
	SetMode: (Mode: SendMode) -> (),
}

export type EventConnection = {
	Connected: boolean,
	Disconnect: (self: EventConnection) -> (),
}

export type PacketStreamerConfiguration = {
	InstancingStream: boolean?,
	AutoInstancingStream: number?,
	PersistentStreamInterval: number?,
	StreamInterval: number?,
	RateLimit: number?,
	ConnectionPing: boolean?,
	MaxQueueSize: number?,
	DebugMode: boolean?,
	UseSecureStorage: boolean?,
	PingInterval: number?,
	MaxRetryCount: number?,
	DeadPacketWarn: number?,
	KeyRotationCooldown: number?,
	AllowManualStreamControl: boolean?,
	DefaultSendMode: SendMode?,
	DefaultStreamMode: SendMode?,
}

export type PacketStreamServiceConfiguration = {
	InstancingStream: boolean?,
	AutoInstancingStream: number?,
	PersistentStreamInterval: number?,
	AllowIndependentStream: boolean?,
	IndependentInheritance: boolean?,
	StreamInterval: number?,
	RateLimit: number?,
	ConnectionPing: boolean?,
	MaxQueueSize: number?,
	DebugMode: boolean?,
	UseSecureStorage: boolean?,
	PingInterval: number?,
	MaxRetryCount: number?,
	DeadPacketWarn: number?,
	KeyRotationCooldown: number?,
	AllowClientStreaming: boolean?,
	AllowManualStreamControl: boolean?,
	DefaultSendMode: SendMode?,
	DefaultStreamMode: SendMode?,
}

type ResolvedStreamerConfig = {
	InstancingStream: boolean,
	AutoInstancingStream: number,
	PersistentStreamInterval: number,
	StreamInterval: number,
	RateLimit: number,
	ConnectionPing: boolean,
	MaxQueueSize: number,
	DebugMode: boolean,
	UseSecureStorage: boolean,
	PingInterval: number,
	MaxRetryCount: number,
	DeadPacketWarn: number,
	KeyRotationCooldown: number,
	AllowManualStreamControl: boolean,
	DefaultSendMode: SendMode,
	DefaultStreamMode: SendMode,
}

type ResolvedServiceConfig = {
	InstancingStream: boolean,
	AutoInstancingStream: number,
	PersistentStreamInterval: number,
	AllowIndependentStream: boolean,
	IndependentInheritance: boolean,
	StreamInterval: number,
	RateLimit: number,
	ConnectionPing: boolean,
	MaxQueueSize: number,
	DebugMode: boolean,
	UseSecureStorage: boolean,
	PingInterval: number,
	MaxRetryCount: number,
	DeadPacketWarn: number,
	KeyRotationCooldown: number,
	AllowClientStreaming: boolean,
	AllowManualStreamControl: boolean,
	DefaultSendMode: SendMode,
	DefaultStreamMode: SendMode,
}

local StreamerDefaults: ResolvedStreamerConfig = {
	InstancingStream = true,
	AutoInstancingStream = 50,
	PersistentStreamInterval = 10,
	StreamInterval = 16.67,
	RateLimit = 60,
	ConnectionPing = false,
	MaxQueueSize = 1000,
	DebugMode = false,
	UseSecureStorage = false,
	PingInterval = 100,
	MaxRetryCount = 10,
	DeadPacketWarn = 5,
	KeyRotationCooldown = 3000,
	AllowManualStreamControl = false,
	DefaultSendMode = SendModeNormal,
	DefaultStreamMode = SendModeNormal,
}

local ServiceDefaults: ResolvedServiceConfig = {
	InstancingStream = true,
	AutoInstancingStream = 50,
	PersistentStreamInterval = 10,
	AllowIndependentStream = true,
	IndependentInheritance = true,
	StreamInterval = 16.67,
	RateLimit = 60,
	ConnectionPing = false,
	MaxQueueSize = 1000,
	DebugMode = false,
	UseSecureStorage = false,
	PingInterval = 100,
	MaxRetryCount = 10,
	DeadPacketWarn = 5,
	KeyRotationCooldown = 3000,
	AllowClientStreaming = false,
	AllowManualStreamControl = false,
	DefaultSendMode = SendModeNormal,
	DefaultStreamMode = SendModeNormal,
}

type QueueEntry = {
	PacketType: number,
	TopicId: number,
	PacketId: number,
	Data: any,
}

type StreamingEntry = {
	TopicId: number,
	Data: any,
	Mode: SendMode,
	PingProtocol: any,
}

type PersistentEntry = {
	Folder: Folder,
	LastState: {[string]: any},
}

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

local function _GetOrCreateChild(Parent: Instance, Name: string, ClassName: string): Instance
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

local function _ResolveStreamerConfig(UserConfig: PacketStreamerConfiguration?, Fallback: ResolvedStreamerConfig): (ResolvedStreamerConfig)
	local Cfg = UserConfig or {}
	local Resolved = table.freeze({
		InstancingStream = if Cfg.InstancingStream ~= nil then Cfg.InstancingStream else Fallback.InstancingStream,
		AutoInstancingStream = if Cfg.AutoInstancingStream ~= nil then Cfg.AutoInstancingStream else Fallback.AutoInstancingStream,
		PersistentStreamInterval = if Cfg.PersistentStreamInterval ~= nil then Cfg.PersistentStreamInterval else Fallback.PersistentStreamInterval,
		StreamInterval = if Cfg.StreamInterval ~= nil then Cfg.StreamInterval else Fallback.StreamInterval,
		RateLimit = if Cfg.RateLimit ~= nil then Cfg.RateLimit else Fallback.RateLimit,
		ConnectionPing = if Cfg.ConnectionPing ~= nil then Cfg.ConnectionPing else Fallback.ConnectionPing,
		MaxQueueSize = if Cfg.MaxQueueSize ~= nil then Cfg.MaxQueueSize else Fallback.MaxQueueSize,
		DebugMode = if Cfg.DebugMode ~= nil then Cfg.DebugMode else Fallback.DebugMode,
		UseSecureStorage = if Cfg.UseSecureStorage ~= nil then Cfg.UseSecureStorage else Fallback.UseSecureStorage,
		PingInterval = if Cfg.PingInterval ~= nil then Cfg.PingInterval else Fallback.PingInterval,
		MaxRetryCount = if Cfg.MaxRetryCount ~= nil then Cfg.MaxRetryCount else Fallback.MaxRetryCount,
		DeadPacketWarn = if Cfg.DeadPacketWarn ~= nil then Cfg.DeadPacketWarn else Fallback.DeadPacketWarn,
		KeyRotationCooldown = if Cfg.KeyRotationCooldown ~= nil then Cfg.KeyRotationCooldown else Fallback.KeyRotationCooldown,
		AllowManualStreamControl = if Cfg.AllowManualStreamControl ~= nil then Cfg.AllowManualStreamControl else Fallback.AllowManualStreamControl,
		DefaultSendMode = if Cfg.DefaultSendMode ~= nil then Cfg.DefaultSendMode else Fallback.DefaultSendMode,
		DefaultStreamMode = if Cfg.DefaultStreamMode ~= nil then Cfg.DefaultStreamMode else Fallback.DefaultStreamMode,
	})
	if Resolved.UseSecureStorage and not SecureStorage then
		warn("[PacketStream] UseSecureStorage is true but SecureStorage dependency was not found")
	end
	return Resolved
end

local function _FnvHash(Name: string): (number)
	local Hash = 2166136261
	for Index = 1, #Name do
		Hash = bit32.bxor(Hash, string.byte(Name, Index))
		Hash = bit32.band(Hash * 16777619, 0xFFFFFFFF)
	end
	return Hash
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

local function _ComputeDelta(Current: {[string]: any}, Previous: {[string]: any}?): ({[string]: any}?)
	if not Previous then return Current end
	local Delta: {[string]: any} = {}
	local HasChange = false
	for Key, Value in pairs(Current) do
		if Previous[Key] ~= Value then
			Delta[Key] = Value
			HasChange = true
		end
	end
	for Key in pairs(Previous) do
		if Current[Key] == nil then
			Delta[Key] = nil
			HasChange = true
		end
	end
	if not HasChange then return nil end
	return Delta
end

local function _ApplyDelta(State: {[string]: any}, Delta: {[string]: any}): ({[string]: any})
	local New = table.clone(State)
	for Key, Value in pairs(Delta) do
		New[Key] = Value
	end
	return New
end

local function _EncryptForPlayer(Data: string, Player: Player, TopicId: number): (string)
	local Key = Encryption.GetClientKey(Player)
	if not Key then return Data end
	local Nonce = Encryption.ConsumeNonce(Player)
	return Encryption.Encrypt(Data, Key, Nonce)
end

local function _InstanceWrite(Folder: Folder, InstanceName: string, Data: any, EncryptKey: string?, EncryptNonce: number?): ()
	local Buf = Codec.EncodeValue(Data)
	local Raw = Codec.BufferToString(Buf)
	if EncryptKey and EncryptNonce then
		Raw = Encryption.Encrypt(Raw, EncryptKey, EncryptNonce)
	end
	local Container = Folder:FindFirstChild(InstanceName)
	if Container and Container:IsA("StringValue") then
		(Container :: StringValue).Value = Raw
	else
		if Container then Container:Destroy() end
		local New = Instance.new("StringValue")
		New.Name = InstanceName
		New.Value = Raw
		New.Parent = Folder
	end
end

local PacketStreamer = {}
PacketStreamer.__index = PacketStreamer

function PacketStreamer._Init(self, Name: string, Config: ResolvedStreamerConfig): ()
	local Root = _GetRootFolder()
	local StreamFolder: Folder

	if IsServer then
		StreamFolder = Instance.new("Folder") :: Folder
		StreamFolder.Name = "S_" .. Name
		StreamFolder.Parent = Root
	else
		StreamFolder = Root:WaitForChild("S_" .. Name) :: Folder
	end

	self._config = Config
	self._name = Name
	self._emitter = EventEmitter.new()
	self._registry = _CreateTopicRegistry()
	self._flagSchema = FlagSchema.new()
	self._folder = StreamFolder
	self._isInstancing = false
	self._isDestroyed = false
	self._elapsed = 0
	self._persistentElapsed = 0
	self._rotationElapsed = 0
	self._pendingRotation = false
	self._rateBucket = Config.RateLimit
	self._defaultSendMode = Config.DefaultSendMode
	self._defaultStreamMode = Config.DefaultStreamMode
	self._statsCache = {
		IsInstancing = false,
		RateBucket = 0,
		OutboundTotal = 0,
		PersistentTopics = 0,
		ActiveStreams = 0,
	}

	self._remoteEvent = _GetOrCreateChild(StreamFolder, "Event", "RemoteEvent") :: RemoteEvent
	self._remoteFunction = _GetOrCreateChild(StreamFolder, "Function", "RemoteFunction") :: RemoteFunction

	self._storage = nil
	if Config.UseSecureStorage and SecureStorage then
		self._storage = SecureStorage.new({})
	end

	if IsServer then
		self._outboundQueues = {} :: {[Player]: {QueueEntry}}
		self._broadcastQueue = {} :: {QueueEntry}
		self._persistentEntries = {} :: {[number]: PersistentEntry}
		self._streamingEntries = {} :: {[Player]: {[number]: StreamingEntry}}
		self._clientKeys = {} :: {[Player]: string}
		self._pingProtocols = {} :: {[Player]: any}

		local InstancingFolder = _GetOrCreateChild(Root, "I_" .. Name, "Folder") :: Folder
		self._instancingFolder = InstancingFolder

		local StreamingFolder = _GetOrCreateChild(Root, "St_" .. Name, "Folder") :: Folder
		self._streamingRootFolder = StreamingFolder

		local PersistentFolder = _GetOrCreateChild(Root, "P_" .. Name, "Folder") :: Folder
		self._persistentFolder = PersistentFolder

		self._remoteEvent.OnServerEvent:Connect(function(Player: Player, Buf: buffer)
			PacketStreamer._ReceiveServer(self, Player, Buf)
		end)

		self._remoteFunction.OnServerInvoke = function(_Player: Player, TopicName: string): ({[string]: any}?)
			local TopicId = self._registry.Resolve(TopicName)
			if not TopicId then return nil end
			local Entry = self._persistentEntries[TopicId]
			if not Entry then return nil end
			return Codec.ReadStateFromFolder(Entry.Folder)
		end

		if Config.ConnectionPing then
			local UnreliableRemote = _GetOrCreateChild(StreamFolder, "Ping", "UnreliableRemoteEvent") :: UnreliableRemoteEvent
			self._unreliableRemote = UnreliableRemote
			UnreliableRemote.OnServerEvent:Connect(function(Player: Player, Buf: buffer)
				PacketStreamer._ReceiveServerPing(self, Player, Buf)
			end)
		end

		Players.PlayerAdded:Connect(function(Player: Player)
			PacketStreamer._OnPlayerAdded(self, Player)
		end)

		Players.PlayerRemoving:Connect(function(Player: Player)
			PacketStreamer._OnPlayerRemoving(self, Player)
		end)
	else
		self._clientQueue = {} :: {QueueEntry}
		self._serverPingProtocol = PingProtocol.new({
			PingInterval = Config.PingInterval,
			MaxRetryCount = Config.MaxRetryCount,
			DeadPacketWarn = Config.DeadPacketWarn,
		})
		self._clientKey = nil :: string?
		self._myStreamingFolder = nil :: Folder?

		self._remoteEvent.OnClientEvent:Connect(function(Buf: buffer)
			PacketStreamer._ReceiveClient(self, Buf)
		end)

		if Config.ConnectionPing then
			local UnreliableRemote = StreamFolder:WaitForChild("Ping") :: UnreliableRemoteEvent
			self._unreliableRemote = UnreliableRemote
			UnreliableRemote.OnClientEvent:Connect(function(Buf: buffer)
				PacketStreamer._ReceiveClientPing(self, Buf)
			end)
		end

		if Config.InstancingStream then
			PacketStreamer._ListenInstancing(self)
		end

		PacketStreamer._ListenStreaming(self)
	end

	self._heartbeatConnection = RunService.Heartbeat:Connect(function(DeltaTime: number)
		PacketStreamer._OnHeartbeat(self, DeltaTime)
	end)
end

function PacketStreamer._OnPlayerAdded(self, Player: Player): ()
	local Key = Encryption.GenerateKey()
	self._clientKeys[Player] = Key
	Encryption.RegisterClient(Player, Key)

	self._pingProtocols[Player] = PingProtocol.new({
		PingInterval = self._config.PingInterval,
		MaxRetryCount = self._config.MaxRetryCount,
		DeadPacketWarn = self._config.DeadPacketWarn,
	})

	local PlayerStreamFolder = Instance.new("Folder")
	PlayerStreamFolder.Name = tostring(Player.UserId)
	PlayerStreamFolder:SetAttribute("Owner", Player.UserId)
	PlayerStreamFolder.Parent = self._streamingRootFolder

	if not self._outboundQueues[Player] then
		self._outboundQueues[Player] = {}
	end

	table.insert(self._outboundQueues[Player], {
		PacketType = PacketTypeKeyDelivery,
		TopicId = 0,
		PacketId = 0,
		Data = Key,
	})

	for TopicId, Entry in pairs(self._persistentEntries) do
		local TopicName = self._registry.ResolveName(TopicId)
		if TopicName then
			local CurrentState = Codec.ReadStateFromFolder(Entry.Folder)
			table.insert(self._outboundQueues[Player], {
				PacketType = PacketTypePersistentFull,
				TopicId = TopicId,
				PacketId = 0,
				Data = CurrentState,
			})
		end
	end
end

function PacketStreamer._OnPlayerRemoving(self, Player: Player): ()
	self._outboundQueues[Player] = nil
	self._streamingEntries[Player] = nil
	self._pingProtocols[Player] = nil
	self._clientKeys[Player] = nil
	Encryption.RemoveClient(Player)

	local PlayerFolder = self._streamingRootFolder:FindFirstChild(tostring(Player.UserId))
	if PlayerFolder then
		PlayerFolder:Destroy()
	end
end

function PacketStreamer._ListenInstancing(self): ()
	local Root = _GetRootFolder()
	local InstancingFolder = Root:WaitForChild("I_" .. self._name) :: Folder
	local LocalUserId = Players.LocalPlayer.UserId

	InstancingFolder.ChildAdded:Connect(function(Child: Instance)
		if not Child:IsA("StringValue") then return end
		local Separator = string.find(Child.Name, "|")
		if not Separator then return end
		local TargetUserId = tonumber(string.sub(Child.Name, 1, Separator - 1))
		local TopicId = tonumber(string.sub(Child.Name, Separator + 1))
		if not TargetUserId or not TopicId then return end
		if TargetUserId ~= 0 and TargetUserId ~= LocalUserId then return end

		local Raw = (Child :: StringValue).Value
		local Buf = Codec.StringToBuffer(Raw)
		local Data = Codec.DecodeValue(Buf)
		local TopicName = self._registry.ResolveName(TopicId)
		if not TopicName then return end

		self._emitter:Fire("Packet", TopicName, Data)
		self._emitter:Fire(TopicName, Data)
	end)
end

function PacketStreamer._ListenStreaming(self): ()
	local Root = _GetRootFolder()
	local StreamingRoot = Root:WaitForChild("St_" .. self._name) :: Folder

	StreamingRoot.ChildAdded:Connect(function(PlayerFolder: Instance)
		if not PlayerFolder:IsA("Folder") then return end
		local OwnerUserId = PlayerFolder:GetAttribute("Owner")
		if OwnerUserId ~= Players.LocalPlayer.UserId then return end

		self._myStreamingFolder = PlayerFolder :: Folder

		PlayerFolder.AttributeChanged:Connect(function(AttributeName: string)
			local Value = PlayerFolder:GetAttribute(AttributeName)
			if type(Value) ~= "string" then return end

			local Decrypted = Value
			if self._clientKey then
				Decrypted = Encryption.Decrypt(Value, self._clientKey, 0)
			end

			local Buf = Codec.StringToBuffer(Decrypted)
			local TopicId = tonumber(AttributeName)
			if not TopicId then return end
			local Data = Codec.DecodeValue(Buf)
			local TopicName = self._registry.ResolveName(TopicId)
			if not TopicName then return end

			self._emitter:Fire("StreamingPacket", TopicName, Data)
			self._emitter:Fire(TopicName, Data)
		end)
	end)

	local PersistentRoot = Root:WaitForChild("P_" .. self._name) :: Folder

	PersistentRoot.ChildAdded:Connect(function(TopicFolder: Instance)
		if not TopicFolder:IsA("Folder") then return end
		local TopicId = tonumber(TopicFolder.Name)
		if not TopicId then return end

		local function _OnChange()
			local State = Codec.ReadStateFromFolder(TopicFolder :: Folder)
			local TopicName = self._registry.ResolveName(TopicId)
			if not TopicName then return end
			self._emitter:Fire("PersistentPacket", TopicName, State)
			self._emitter:Fire(TopicName, State)
		end

		TopicFolder.AttributeChanged:Connect(_OnChange)
		TopicFolder.ChildAdded:Connect(_OnChange)
		TopicFolder.ChildRemoved:Connect(_OnChange)
	end)

	PersistentRoot.ChildRemoved:Connect(function(TopicFolder: Instance)
		local TopicId = tonumber(TopicFolder.Name)
		if not TopicId then return end
		local TopicName = self._registry.ResolveName(TopicId)
		if not TopicName then return end
		self._emitter:Fire("PersistentRemoved", TopicName)
	end)
end

function PacketStreamer._ReceiveServer(self, Player: Player, Buf: buffer): ()
	for _, Entry in Codec.DecodeBatch(Buf) do
		local TopicName = self._registry.ResolveName(Entry.TopicId)
		if Entry.PacketType == PacketTypeKeyAck then
			self._emitter:Fire("ClientKeyAck", Player)
			continue
		end
		if not TopicName then continue end
		self._emitter:Fire("Packet", Player, TopicName, Entry.Data)
		self._emitter:Fire(TopicName, Player, Entry.Data)
	end
end

function PacketStreamer._ReceiveClient(self, Buf: buffer): ()
	for _, Entry in Codec.DecodeBatch(Buf) do
		if Entry.PacketType == PacketTypeKeyDelivery then
			self._clientKey = Entry.Data :: string
			self._remoteEvent:FireServer(Codec.EncodeBatch({
				{
					PacketType = PacketTypeKeyAck,
					TopicId = 0,
					PacketId = 0,
					Data = true,
				},
			}))
			continue
		end

		local TopicName = self._registry.ResolveName(Entry.TopicId)
		if not TopicName then continue end

		if Entry.PacketType == PacketTypePersistentFull then
			self._emitter:Fire("PersistentPacket", TopicName, Entry.Data)
			self._emitter:Fire(TopicName, Entry.Data)
		elseif Entry.PacketType == PacketTypeStreamStop then
			self._emitter:Fire("StreamStop", TopicName)
		else
			self._emitter:Fire("Packet", TopicName, Entry.Data)
			self._emitter:Fire(TopicName, Entry.Data)
		end
	end
end

function PacketStreamer._ReceiveServerPing(self, Player: Player, Buf: buffer): ()
	local AckEntries, FlagBytes = PingProtocol.DecodePing(Buf)
	local Protocol = self._pingProtocols[Player]
	if not Protocol then return end

	if FlagBytes ~= "" then
		self._flagSchema:Unpack(FlagBytes)
	end

	Protocol:ReceiveAcks(AckEntries,
		function(PacketId: number, Data: any)
			if not self._outboundQueues[Player] then
				self._outboundQueues[Player] = {}
			end
			table.insert(self._outboundQueues[Player], {
				PacketType = PacketTypeEphemeral,
				TopicId = 0,
				PacketId = PacketId,
				Data = Data,
			})
		end,
		function(PacketId: number)
			self._emitter:Fire("PacketDropped", Player, PacketId)
		end
	)
end

function PacketStreamer._ReceiveClientPing(self, Buf: buffer): ()
	local AckEntries, FlagBytes = PingProtocol.DecodePing(Buf)
	if FlagBytes ~= "" then
		self._flagSchema:Unpack(FlagBytes)
	end
	self._serverPingProtocol:ReceiveAcks(AckEntries,
		function(PacketId: number, Data: any)
			table.insert(self._clientQueue, {
				PacketType = PacketTypeEphemeral,
				TopicId = 0,
				PacketId = PacketId,
				Data = Data,
			})
		end,
		function(PacketId: number)
			self._emitter:Fire("PacketDropped", PacketId)
		end
	)
end

function PacketStreamer._FireInstancing(self, Player: Player, TopicId: number, Data: any, Encrypt: boolean): ()
	local InstanceName = tostring(Player.UserId) .. "|" .. tostring(TopicId)
	if Encrypt then
		local Key = self._clientKeys[Player]
		if Key then
			local Nonce = Encryption.ConsumeNonce(Player)
			local Buf = Codec.EncodeValue(Data)
			local Raw = Codec.BufferToString(Buf)
			local Encrypted = Encryption.Encrypt(Raw, Key, Nonce)
			local Container = Instance.new("StringValue")
			Container.Name = InstanceName
			Container.Value = Encrypted
			Container.Parent = self._instancingFolder
			Debris:AddItem(Container, 2)
			return
		end
	end
	local Buf = Codec.EncodeValue(Data)
	local Raw = Codec.BufferToString(Buf)
	local Container = Instance.new("StringValue")
	Container.Name = InstanceName
	Container.Value = Raw
	Container.Parent = self._instancingFolder
	Debris:AddItem(Container, 2)
end

function PacketStreamer._FlushStreamingEntries(self): ()
	for Player, TopicMap in pairs(self._streamingEntries) do
		local PlayerFolder = self._streamingRootFolder:FindFirstChild(tostring(Player.UserId))
		if not PlayerFolder then continue end

		for TopicId, Entry in pairs(TopicMap) do
			local Buf = Codec.EncodeValue(Entry.Data)
			local Raw = Codec.BufferToString(Buf)

			if Entry.Mode == SendModeInstancing then
				local Key = self._clientKeys[Player]
				if Key then
					Raw = Encryption.Encrypt(Raw, Key, Encryption.ConsumeNonce(Player))
				end
				PlayerFolder:SetAttribute(tostring(TopicId), Raw)
			else
				if not self._outboundQueues[Player] then
					self._outboundQueues[Player] = {}
				end
				table.insert(self._outboundQueues[Player], {
					PacketType = PacketTypeStreamUpdate,
					TopicId = TopicId,
					PacketId = 0,
					Data = Entry.Data,
				})
			end
		end
	end
end

function PacketStreamer._FlushServer(self): ()
	local BroadcastBatch = self._broadcastQueue
	self._broadcastQueue = {}

	for _, Player in Players:GetPlayers() do
		local PlayerBatch = self._outboundQueues[Player]
		self._outboundQueues[Player] = {}

		local Merged: {QueueEntry} = {}
		for _, Entry in BroadcastBatch do
			table.insert(Merged, Entry)
		end
		if PlayerBatch then
			for _, Entry in PlayerBatch do
				table.insert(Merged, Entry)
			end
		end

		if #Merged == 0 then continue end

		local Instancing: {QueueEntry} = {}
		local Normal: {QueueEntry} = {}
		for _, Entry in Merged do
			if Entry.PacketType == PacketTypeKeyDelivery then
				table.insert(Normal, Entry)
			else
				local UseInstancing = self._isInstancing
				if UseInstancing then
					table.insert(Instancing, Entry)
				else
					table.insert(Normal, Entry)
				end
			end
		end

		if #Normal > 0 then
			self._remoteEvent:FireClient(Player, Codec.EncodeBatch(Normal))
		end

		for _, Entry in Instancing do
			PacketStreamer._FireInstancing(self, Player, Entry.TopicId, Entry.Data, true)
		end
	end
end

function PacketStreamer._FlushClient(self): ()
	if #self._clientQueue == 0 then return end
	local Batch = self._clientQueue
	self._clientQueue = {}
	self._remoteEvent:FireServer(Codec.EncodeBatch(Batch))
end

function PacketStreamer._TickPings(self, DeltaMs: number): ()
	if not self._config.ConnectionPing then return end
	if not self._unreliableRemote then return end

	if IsServer then
		local FlagBytes = self._flagSchema:IsLocked() and self._flagSchema:Pack() or ""
		for _, Player in Players:GetPlayers() do
			local Protocol = self._pingProtocols[Player]
			if not Protocol then continue end
			local Acks = Protocol:Tick(DeltaMs,
				function(_PacketId: number, _Data: any) end,
				function(PacketId: number)
					self._emitter:Fire("PacketDropped", Player, PacketId)
				end
			)
			local Buf = PingProtocol.EncodePing(Acks, FlagBytes)
			self._unreliableRemote:FireClient(Player, Buf)
		end
	else
		local FlagBytes = self._flagSchema:IsLocked() and self._flagSchema:Pack() or ""
		local Acks = self._serverPingProtocol:Tick(DeltaMs,
			function(_PacketId: number, _Data: any) end,
			function(PacketId: number)
				self._emitter:Fire("PacketDropped", PacketId)
			end
		)
		local Buf = PingProtocol.EncodePing(Acks, FlagBytes)
		self._unreliableRemote:FireServer(Buf)
	end
end

function PacketStreamer._CheckRotation(self, DeltaMs: number): ()
	if not self._pendingRotation then return end
	self._rotationElapsed += DeltaMs
	if self._rotationElapsed < self._config.KeyRotationCooldown then return end
	self._pendingRotation = false
	self._rotationElapsed = 0

	for _, Player in Players:GetPlayers() do
		local NewKey = Encryption.GenerateKey()
		self._clientKeys[Player] = NewKey
		Encryption.RegisterClient(Player, NewKey)

		if not self._outboundQueues[Player] then
			self._outboundQueues[Player] = {}
		end
		table.insert(self._outboundQueues[Player], {
			PacketType = PacketTypeKeyDelivery,
			TopicId = 0,
			PacketId = 0,
			Data = NewKey,
		})
	end
end

function PacketStreamer._OnHeartbeat(self, DeltaTime: number): ()
	if self._isDestroyed then return end

	local FrameMs = DeltaTime * 1000
	local Config = self._config

	if Config.AutoInstancingStream > 0 and IsServer then
		local ShouldInstance = FrameMs > Config.AutoInstancingStream
		if ShouldInstance ~= self._isInstancing then
			self._isInstancing = ShouldInstance
			self._emitter:Fire("StreamMode", ShouldInstance and "Instancing" or "Normal")
		end
	end

	self._rateBucket = math.min(Config.RateLimit, self._rateBucket + Config.RateLimit * DeltaTime)
	self._elapsed += FrameMs

	PacketStreamer._TickPings(self, FrameMs)

	if Config.StreamInterval > 0 and self._elapsed < Config.StreamInterval then return end
	self._elapsed = 0

	if self._rateBucket < 1 then
		self._emitter:Fire("RateLimited")
		return
	end
	self._rateBucket -= 1

	if IsServer then
		self._persistentElapsed += FrameMs
		if Config.PersistentStreamInterval == 0 or self._persistentElapsed >= Config.PersistentStreamInterval then
			self._persistentElapsed = 0
		end
		PacketStreamer._FlushStreamingEntries(self)
		PacketStreamer._FlushServer(self)
		PacketStreamer._CheckRotation(self, FrameMs)
	else
		PacketStreamer._FlushClient(self)
	end
end

function PacketStreamer:On(EventName: string, Callback: (...any) -> ()): (EventConnection)
	return self._emitter:Connect(EventName, Callback)
end

function PacketStreamer:Once(EventName: string, Callback: (...any) -> ()): (EventConnection)
	return self._emitter:Once(EventName, Callback)
end

function PacketStreamer:Wait(EventName: string): (...any)
	return self._emitter:Wait(EventName)
end

function PacketStreamer:DefinePingFlags(Flags: {[string]: boolean}): ()
	self._flagSchema:Define(Flags)
end

function PacketStreamer:AddSecurityListener(Listener: (FlagName: string, Value: boolean) -> (nil?, string?)): ()
	self._flagSchema:AddSecurityListener(Listener)
end

function PacketStreamer:AddGuardListener(Listener: (FlagName: string, Value: boolean, Reason: string) -> ()): ()
	self._flagSchema:AddGuardListener(Listener)
end

function PacketStreamer:OnFlagChange(Listener: (FlagName: string, Value: boolean) -> ()): ()
	self._flagSchema:OnChange(Listener)
end

function PacketStreamer:SetFlag(FlagName: string, Value: boolean): ()
	self._flagSchema:SetFlag(FlagName, Value)
end

function PacketStreamer:GetFlag(FlagName: string): (boolean)
	return self._flagSchema:GetFlag(FlagName)
end

function PacketStreamer:SetDefaultMode(Target: "SendTo" | "StartStream", Mode: SendMode): ()
	if Target == "SendTo" then
		self._defaultSendMode = Mode
	else
		self._defaultStreamMode = Mode
	end
end

function PacketStreamer:SendTo(Player: Player, Topic: string, Data: any, Mode: SendMode?): ()
	assert(IsServer, "[PacketStream] SendTo is server-only")
	local UseMode = Mode or self._defaultSendMode
	local TopicId = self._registry.Register(Topic)

	if UseMode == SendModeInstancing then
		PacketStreamer._FireInstancing(self, Player, TopicId, Data, true)
		return
	end

	if not self._outboundQueues[Player] then
		self._outboundQueues[Player] = {}
	end
	local Queue = self._outboundQueues[Player]
	if #Queue >= self._config.MaxQueueSize then
		self._emitter:Fire("RateLimited")
		return
	end
	table.insert(Queue, {
		PacketType = PacketTypeEphemeral,
		TopicId = TopicId,
		PacketId = 0,
		Data = Data,
	})
end

function PacketStreamer:Broadcast(Topic: string, Data: any): ()
	assert(IsServer, "[PacketStream] Broadcast is server-only")
	local TopicId = self._registry.Register(Topic)
	if #self._broadcastQueue >= self._config.MaxQueueSize then
		self._emitter:Fire("RateLimited")
		return
	end
	table.insert(self._broadcastQueue, {
		PacketType = PacketTypeEphemeral,
		TopicId = TopicId,
		PacketId = 0,
		Data = Data,
	})
end

function PacketStreamer:SetPersistent(Topic: string, State: {[string]: any}): ()
	assert(IsServer, "[PacketStream] SetPersistent is server-only")
	local TopicId = self._registry.Register(Topic)
	local Existing = self._persistentEntries[TopicId]

	if Existing then
		local OldState = Codec.ReadStateFromFolder(Existing.Folder)
		Codec.SyncStateToFolder(Existing.Folder, State, OldState)
		Existing.LastState = State
	else
		local TopicFolder = Instance.new("Folder")
		TopicFolder.Name = tostring(TopicId)
		TopicFolder.Parent = self._persistentFolder
		Codec.SyncStateToFolder(TopicFolder, State, nil)
		self._persistentEntries[TopicId] = {
			Folder = TopicFolder,
			LastState = State,
		}
	end
end

function PacketStreamer:RemovePersistent(Topic: string): ()
	assert(IsServer, "[PacketStream] RemovePersistent is server-only")
	local TopicId = self._registry.Resolve(Topic)
	if not TopicId then return end
	local Entry = self._persistentEntries[TopicId]
	if not Entry then return end
	Entry.Folder:Destroy()
	self._persistentEntries[TopicId] = nil
end

function PacketStreamer:StartStream(Player: Player, Topic: string, InitialData: any, Mode: SendMode?): (StreamHandle?)
	assert(IsServer, "[PacketStream] StartStream is server-only")
	local UseMode = Mode or self._defaultStreamMode
	local TopicId = self._registry.Register(Topic)

	if not self._streamingEntries[Player] then
		self._streamingEntries[Player] = {}
	end

	local Entry: StreamingEntry = {
		TopicId = TopicId,
		Data = InitialData,
		Mode = UseMode,
		PingProtocol = self._pingProtocols[Player],
	}
	self._streamingEntries[Player][TopicId] = Entry

	if not self._config.AllowManualStreamControl then
		return nil
	end

	local Handle = {}

	function Handle.Update(Data: any): ()
		Entry.Data = Data
		local Buf = Codec.EncodeValue(Data)
		local Raw = Codec.BufferToString(Buf)

		if Entry.Mode == SendModeInstancing then
			local PlayerFolder = self._streamingRootFolder:FindFirstChild(tostring(Player.UserId))
			if PlayerFolder then
				local Key = self._clientKeys[Player]
				if Key then
					Raw = Encryption.Encrypt(Raw, Key, Encryption.ConsumeNonce(Player))
				end
				PlayerFolder:SetAttribute(tostring(TopicId), Raw)
			end
		else
			if not self._outboundQueues[Player] then
				self._outboundQueues[Player] = {}
			end
			table.insert(self._outboundQueues[Player], {
				PacketType = PacketTypeStreamUpdate,
				TopicId = TopicId,
				PacketId = 0,
				Data = Data,
			})
		end
	end

	function Handle.Stop(): ()
		if self._streamingEntries[Player] then
			self._streamingEntries[Player][TopicId] = nil
		end
		if not self._outboundQueues[Player] then
			self._outboundQueues[Player] = {}
		end
		table.insert(self._outboundQueues[Player], {
			PacketType = PacketTypeStreamStop,
			TopicId = TopicId,
			PacketId = 0,
			Data = nil,
		})
	end

	function Handle.SetMode(NewMode: SendMode): ()
		Entry.Mode = NewMode
		self._emitter:Fire("StreamModeChanged", Player, Topic, NewMode)
	end

	return Handle
end

function PacketStreamer:Send(Topic: string, Data: any): ()
	assert(not IsServer, "[PacketStream] Send is client-only")
	local TopicId = self._registry.Register(Topic)
	if #self._clientQueue >= self._config.MaxQueueSize then
		self._emitter:Fire("RateLimited")
		return
	end
	table.insert(self._clientQueue, {
		PacketType = PacketTypeEphemeral,
		TopicId = TopicId,
		PacketId = 0,
		Data = Data,
	})
end

function PacketStreamer:RequestState(Topic: string): ({[string]: any}?)
	assert(not IsServer, "[PacketStream] RequestState is client-only")
	return self._remoteFunction:InvokeServer(Topic)
end

function PacketStreamer:Stats(): ({
	IsInstancing: boolean,
	RateBucket: number,
	OutboundTotal: number,
	PersistentTopics: number,
	ActiveStreams: number,
})
	local OutboundTotal = 0
	if self._outboundQueues then
		for _, Queue in pairs(self._outboundQueues) do
			OutboundTotal += #Queue
		end
	end
	if self._broadcastQueue then
		OutboundTotal += #self._broadcastQueue
	end
	local PersistentTopics = 0
	if self._persistentEntries then
		for _ in pairs(self._persistentEntries) do
			PersistentTopics += 1
		end
	end
	local ActiveStreams = 0
	if self._streamingEntries then
		for _, TopicMap in pairs(self._streamingEntries) do
			for _ in pairs(TopicMap) do
				ActiveStreams += 1
			end
		end
	end
	local Cache = self._statsCache
	Cache.IsInstancing = self._isInstancing
	Cache.RateBucket = self._rateBucket
	Cache.OutboundTotal = OutboundTotal
	Cache.PersistentTopics = PersistentTopics
	Cache.ActiveStreams = ActiveStreams
	return Cache
end

function PacketStreamer:Destroy(): ()
	if self._isDestroyed then return end
	self._isDestroyed = true
	self._heartbeatConnection:Disconnect()
	self._emitter:Destroy()
	if IsServer and self._folder then
		self._folder:Destroy()
	end
	if self._outboundQueues then table.clear(self._outboundQueues) end
	if self._persistentEntries then table.clear(self._persistentEntries) end
	if self._streamingEntries then table.clear(self._streamingEntries) end
	if self._storage then self._storage:Destroy() end
	setmetatable(self, nil)
	table.freeze(self)
end

local _serviceConfig: ResolvedServiceConfig
local _serviceEmitter: any
local _serviceRegistry: any
local _serviceFlagSchema: any
local _serviceRemoteEvent: RemoteEvent
local _serviceRemoteFunction: RemoteFunction
local _serviceUnreliableRemote: UnreliableRemoteEvent?
local _serviceOutboundQueues: {[Player]: {QueueEntry}} = {}
local _serviceBroadcastQueue: {QueueEntry} = {}
local _serviceClientQueue: {QueueEntry} = {}
local _servicePersistentEntries: {[number]: PersistentEntry} = {}
local _serviceStreamingEntries: {[Player]: {[number]: StreamingEntry}} = {}
local _serviceClientKeys: {[Player]: string} = {}
local _servicePingProtocols: {[Player]: any} = {}
local _serviceServerPingProtocol: any
local _serviceRateBucket: number = 0
local _serviceElapsed: number = 0
local _serviceIsInstancing: boolean = false
local _servicePersistentFolder: Folder
local _serviceStreamingRootFolder: Folder
local _serviceInstancingFolder: Folder
local _serviceDefaultSendMode: SendMode = SendModeNormal
local _serviceDefaultStreamMode: SendMode = SendModeNormal
local _serviceInitialized: boolean = false
local _serviceStorage: any = nil
local _serviceStatsCache = {
	IsInstancing = false,
	RateBucket = 0,
	OutboundTotal = 0,
	PersistentTopics = 0,
	ActiveStreams = 0,
}

local PacketStreamService = {}
PacketStreamService.__index = PacketStreamer

local function _EnsureInitialized(): ()
	assert(_serviceInitialized, "[PacketStream] PacketStreamService.Configure must be called before use")
end

local function _ServiceFlushStreamingEntries(): ()
	for Player, TopicMap in pairs(_serviceStreamingEntries) do
		local PlayerFolder = _serviceStreamingRootFolder:FindFirstChild(tostring(Player.UserId))
		if not PlayerFolder then continue end
		for TopicId, Entry in pairs(TopicMap) do
			local Buf = Codec.EncodeValue(Entry.Data)
			local Raw = Codec.BufferToString(Buf)
			if Entry.Mode == SendModeInstancing then
				local Key = _serviceClientKeys[Player]
				if Key then
					Raw = Encryption.Encrypt(Raw, Key, Encryption.ConsumeNonce(Player))
				end
				PlayerFolder:SetAttribute(tostring(TopicId), Raw)
			else
				if not _serviceOutboundQueues[Player] then
					_serviceOutboundQueues[Player] = {}
				end
				table.insert(_serviceOutboundQueues[Player], {
					PacketType = PacketTypeStreamUpdate,
					TopicId = TopicId,
					PacketId = 0,
					Data = Entry.Data,
				})
			end
		end
	end
end

local function _ServiceFlushServer(): ()
	local BroadcastBatch = _serviceBroadcastQueue
	_serviceBroadcastQueue = {}

	for _, Player in Players:GetPlayers() do
		local PlayerBatch = _serviceOutboundQueues[Player]
		_serviceOutboundQueues[Player] = {}

		local Merged: {QueueEntry} = {}
		for _, Entry in BroadcastBatch do
			table.insert(Merged, Entry)
		end
		if PlayerBatch then
			for _, Entry in PlayerBatch do
				table.insert(Merged, Entry)
			end
		end

		if #Merged == 0 then continue end

		local Instancing: {QueueEntry} = {}
		local Normal: {QueueEntry} = {}
		for _, Entry in Merged do
			if Entry.PacketType == PacketTypeKeyDelivery then
				table.insert(Normal, Entry)
			elseif _serviceIsInstancing then
				table.insert(Instancing, Entry)
			else
				table.insert(Normal, Entry)
			end
		end

		if #Normal > 0 then
			_serviceRemoteEvent:FireClient(Player, Codec.EncodeBatch(Normal))
		end

		for _, Entry in Instancing do
			local InstanceName = tostring(Player.UserId) .. "|" .. tostring(Entry.TopicId)
			local Key = _serviceClientKeys[Player]
			local Buf = Codec.EncodeValue(Entry.Data)
			local Raw = Codec.BufferToString(Buf)
			if Key then
				Raw = Encryption.Encrypt(Raw, Key, Encryption.ConsumeNonce(Player))
			end
			local Container = Instance.new("StringValue")
			Container.Name = InstanceName
			Container.Value = Raw
			Container.Parent = _serviceInstancingFolder
			Debris:AddItem(Container, 2)
		end
	end
end

local function _ServiceFlushClient(): ()
	if #_serviceClientQueue == 0 then return end
	local Batch = _serviceClientQueue
	_serviceClientQueue = {}
	_serviceRemoteEvent:FireServer(Codec.EncodeBatch(Batch))
end

local function _ServiceTickPings(DeltaMs: number): ()
	if not _serviceConfig.ConnectionPing then return end
	if not _serviceUnreliableRemote then return end

	if IsServer then
		local FlagBytes = _serviceFlagSchema:IsLocked() and _serviceFlagSchema:Pack() or ""
		for _, Player in Players:GetPlayers() do
			local Protocol = _servicePingProtocols[Player]
			if not Protocol then continue end
			local Acks = Protocol:Tick(DeltaMs,
				function(_PacketId: number, _Data: any) end,
				function(PacketId: number)
					_serviceEmitter:Fire("PacketDropped", Player, PacketId)
				end
			)
			local Buf = PingProtocol.EncodePing(Acks, FlagBytes)
			_serviceUnreliableRemote:FireClient(Player, Buf)
		end
	else
		local FlagBytes = _serviceFlagSchema:IsLocked() and _serviceFlagSchema:Pack() or ""
		local Acks = _serviceServerPingProtocol:Tick(DeltaMs,
			function(_PacketId: number, _Data: any) end,
			function(PacketId: number)
				_serviceEmitter:Fire("PacketDropped", PacketId)
			end
		)
		local Buf = PingProtocol.EncodePing(Acks, FlagBytes)
		_serviceUnreliableRemote:FireServer(Buf)
	end
end

local function _ServiceOnHeartbeat(DeltaTime: number): ()
	local FrameMs = DeltaTime * 1000
	local Config = _serviceConfig

	if Config.AutoInstancingStream > 0 and IsServer then
		local ShouldInstance = FrameMs > Config.AutoInstancingStream
		if ShouldInstance ~= _serviceIsInstancing then
			_serviceIsInstancing = ShouldInstance
			_serviceEmitter:Fire("StreamMode", ShouldInstance and "Instancing" or "Normal")
		end
	end

	_serviceRateBucket = math.min(Config.RateLimit, _serviceRateBucket + Config.RateLimit * DeltaTime)
	_serviceElapsed += FrameMs

	_ServiceTickPings(FrameMs)

	if Config.StreamInterval > 0 and _serviceElapsed < Config.StreamInterval then return end
	_serviceElapsed = 0

	if _serviceRateBucket < 1 then
		_serviceEmitter:Fire("RateLimited")
		return
	end
	_serviceRateBucket -= 1

	if IsServer then
		_ServiceFlushStreamingEntries()
		_ServiceFlushServer()

		if Encryption.TickRotation(FrameMs, Config.KeyRotationCooldown) then
			for _, Player in Players:GetPlayers() do
				local NewKey = Encryption.GenerateKey()
				_serviceClientKeys[Player] = NewKey
				Encryption.RegisterClient(Player, NewKey)
				if not _serviceOutboundQueues[Player] then
					_serviceOutboundQueues[Player] = {}
				end
				table.insert(_serviceOutboundQueues[Player], {
					PacketType = PacketTypeKeyDelivery,
					TopicId = 0,
					PacketId = 0,
					Data = NewKey,
				})
			end
		end
	else
		_ServiceFlushClient()
	end
end

local function _ServiceOnPlayerAdded(Player: Player): ()
	local Key = Encryption.GenerateKey()
	_serviceClientKeys[Player] = Key
	Encryption.RegisterClient(Player, Key)

	_servicePingProtocols[Player] = PingProtocol.new({
		PingInterval = _serviceConfig.PingInterval,
		MaxRetryCount = _serviceConfig.MaxRetryCount,
		DeadPacketWarn = _serviceConfig.DeadPacketWarn,
	})

	local PlayerStreamFolder = Instance.new("Folder")
	PlayerStreamFolder.Name = tostring(Player.UserId)
	PlayerStreamFolder:SetAttribute("Owner", Player.UserId)
	PlayerStreamFolder.Parent = _serviceStreamingRootFolder

	if not _serviceOutboundQueues[Player] then
		_serviceOutboundQueues[Player] = {}
	end

	table.insert(_serviceOutboundQueues[Player], {
		PacketType = PacketTypeKeyDelivery,
		TopicId = 0,
		PacketId = 0,
		Data = Key,
	})

	for TopicId, Entry in pairs(_servicePersistentEntries) do
		local CurrentState = Codec.ReadStateFromFolder(Entry.Folder)
		table.insert(_serviceOutboundQueues[Player], {
			PacketType = PacketTypePersistentFull,
			TopicId = TopicId,
			PacketId = 0,
			Data = CurrentState,
		})
	end

	Encryption.RequestRotation()
end

local function _ServiceOnPlayerRemoving(Player: Player): ()
	_serviceOutboundQueues[Player] = nil
	_serviceStreamingEntries[Player] = nil
	_servicePingProtocols[Player] = nil
	_serviceClientKeys[Player] = nil
	Encryption.RemoveClient(Player)

	local PlayerFolder = _serviceStreamingRootFolder:FindFirstChild(tostring(Player.UserId))
	if PlayerFolder then
		PlayerFolder:Destroy()
	end

	Encryption.RequestRotation()
end

local function _ServiceReceiveServer(Player: Player, Buf: buffer): ()
	for _, Entry in Codec.DecodeBatch(Buf) do
		if Entry.PacketType == PacketTypeKeyAck then
			_serviceEmitter:Fire("ClientKeyAck", Player)
			continue
		end
		local TopicName = _serviceRegistry.ResolveName(Entry.TopicId)
		if not TopicName then continue end
		_serviceEmitter:Fire("Packet", Player, TopicName, Entry.Data)
		_serviceEmitter:Fire(TopicName, Player, Entry.Data)
	end
end

local function _ServiceReceiveClient(Buf: buffer): ()
	for _, Entry in Codec.DecodeBatch(Buf) do
		if Entry.PacketType == PacketTypeKeyDelivery then
			_serviceEmitter:Fire("KeyReceived")
			continue
		end
		local TopicName = _serviceRegistry.ResolveName(Entry.TopicId)
		if not TopicName then continue end
		if Entry.PacketType == PacketTypePersistentFull then
			_serviceEmitter:Fire("PersistentPacket", TopicName, Entry.Data)
			_serviceEmitter:Fire(TopicName, Entry.Data)
		elseif Entry.PacketType == PacketTypeStreamStop then
			_serviceEmitter:Fire("StreamStop", TopicName)
		else
			_serviceEmitter:Fire("Packet", TopicName, Entry.Data)
			_serviceEmitter:Fire(TopicName, Entry.Data)
		end
	end
end

local function _ServiceReceiveServerPing(Player: Player, Buf: buffer): ()
	local AckEntries, FlagBytes = PingProtocol.DecodePing(Buf)
	local Protocol = _servicePingProtocols[Player]
	if not Protocol then return end
	if FlagBytes ~= "" then
		_serviceFlagSchema:Unpack(FlagBytes)
	end
	Protocol:ReceiveAcks(AckEntries,
		function(PacketId: number, Data: any)
			if not _serviceOutboundQueues[Player] then
				_serviceOutboundQueues[Player] = {}
			end
			table.insert(_serviceOutboundQueues[Player], {
				PacketType = PacketTypeEphemeral,
				TopicId = 0,
				PacketId = PacketId,
				Data = Data,
			})
		end,
		function(PacketId: number)
			_serviceEmitter:Fire("PacketDropped", Player, PacketId)
		end
	)
end

local function _ServiceReceiveClientPing(Buf: buffer): ()
	local AckEntries, FlagBytes = PingProtocol.DecodePing(Buf)
	if FlagBytes ~= "" then
		_serviceFlagSchema:Unpack(FlagBytes)
	end
	_serviceServerPingProtocol:ReceiveAcks(AckEntries,
		function(PacketId: number, Data: any)
			table.insert(_serviceClientQueue, {
				PacketType = PacketTypeEphemeral,
				TopicId = 0,
				PacketId = PacketId,
				Data = Data,
			})
		end,
		function(PacketId: number)
			_serviceEmitter:Fire("PacketDropped", PacketId)
		end
	)
end

function PacketStreamService.Configure(UserConfig: PacketStreamServiceConfiguration): ()
	assert(not _serviceInitialized, "[PacketStream] Configure must be called before first use")
	_serviceInitialized = true

	local Cfg = UserConfig or {}
	_serviceConfig = table.freeze({
		InstancingStream = if Cfg.InstancingStream ~= nil then Cfg.InstancingStream else ServiceDefaults.InstancingStream,
		AutoInstancingStream = if Cfg.AutoInstancingStream ~= nil then Cfg.AutoInstancingStream else ServiceDefaults.AutoInstancingStream,
		PersistentStreamInterval = if Cfg.PersistentStreamInterval ~= nil then Cfg.PersistentStreamInterval else ServiceDefaults.PersistentStreamInterval,
		AllowIndependentStream = if Cfg.AllowIndependentStream ~= nil then Cfg.AllowIndependentStream else ServiceDefaults.AllowIndependentStream,
		IndependentInheritance = if Cfg.IndependentInheritance ~= nil then Cfg.IndependentInheritance else ServiceDefaults.IndependentInheritance,
		StreamInterval = if Cfg.StreamInterval ~= nil then Cfg.StreamInterval else ServiceDefaults.StreamInterval,
		RateLimit = if Cfg.RateLimit ~= nil then Cfg.RateLimit else ServiceDefaults.RateLimit,
		ConnectionPing = if Cfg.ConnectionPing ~= nil then Cfg.ConnectionPing else ServiceDefaults.ConnectionPing,
		MaxQueueSize = if Cfg.MaxQueueSize ~= nil then Cfg.MaxQueueSize else ServiceDefaults.MaxQueueSize,
		DebugMode = if Cfg.DebugMode ~= nil then Cfg.DebugMode else ServiceDefaults.DebugMode,
		UseSecureStorage = if Cfg.UseSecureStorage ~= nil then Cfg.UseSecureStorage else ServiceDefaults.UseSecureStorage,
		PingInterval = if Cfg.PingInterval ~= nil then Cfg.PingInterval else ServiceDefaults.PingInterval,
		MaxRetryCount = if Cfg.MaxRetryCount ~= nil then Cfg.MaxRetryCount else ServiceDefaults.MaxRetryCount,
		DeadPacketWarn = if Cfg.DeadPacketWarn ~= nil then Cfg.DeadPacketWarn else ServiceDefaults.DeadPacketWarn,
		KeyRotationCooldown = if Cfg.KeyRotationCooldown ~= nil then Cfg.KeyRotationCooldown else ServiceDefaults.KeyRotationCooldown,
		AllowClientStreaming = if Cfg.AllowClientStreaming ~= nil then Cfg.AllowClientStreaming else ServiceDefaults.AllowClientStreaming,
		AllowManualStreamControl = if Cfg.AllowManualStreamControl ~= nil then Cfg.AllowManualStreamControl else ServiceDefaults.AllowManualStreamControl,
		DefaultSendMode = if Cfg.DefaultSendMode ~= nil then Cfg.DefaultSendMode else ServiceDefaults.DefaultSendMode,
		DefaultStreamMode = if Cfg.DefaultStreamMode ~= nil then Cfg.DefaultStreamMode else ServiceDefaults.DefaultStreamMode,
	})

	if _serviceConfig.UseSecureStorage and not SecureStorage then
		warn("[PacketStream] UseSecureStorage is true but SecureStorage dependency was not found")
	end

	_serviceEmitter = EventEmitter.new()
	_serviceRegistry = _CreateTopicRegistry()
	_serviceFlagSchema = FlagSchema.new()
	_serviceRateBucket = _serviceConfig.RateLimit
	_serviceDefaultSendMode = _serviceConfig.DefaultSendMode
	_serviceDefaultStreamMode = _serviceConfig.DefaultStreamMode

	if _serviceConfig.UseSecureStorage and SecureStorage then
		_serviceStorage = SecureStorage.new({})
	end

	local Root = _GetRootFolder()
	local ServiceFolder: Folder

	if IsServer then
		ServiceFolder = Instance.new("Folder") :: Folder
		ServiceFolder.Name = "S__Global"
		ServiceFolder.Parent = Root

		_servicePersistentFolder = _GetOrCreateChild(Root, "P__Global", "Folder") :: Folder
		_serviceStreamingRootFolder = _GetOrCreateChild(Root, "St__Global", "Folder") :: Folder
		_serviceInstancingFolder = _GetOrCreateChild(Root, "I__Global", "Folder") :: Folder
	else
		ServiceFolder = Root:WaitForChild("S__Global") :: Folder
		_servicePersistentFolder = Root:WaitForChild("P__Global") :: Folder
		_serviceStreamingRootFolder = Root:WaitForChild("St__Global") :: Folder
		_serviceInstancingFolder = Root:WaitForChild("I__Global") :: Folder
	end

	_serviceRemoteEvent = _GetOrCreateChild(ServiceFolder, "Event", "RemoteEvent") :: RemoteEvent
	_serviceRemoteFunction = _GetOrCreateChild(ServiceFolder, "Function", "RemoteFunction") :: RemoteFunction

	if IsServer then
		_serviceRemoteEvent.OnServerEvent:Connect(_ServiceReceiveServer)
		_serviceRemoteFunction.OnServerInvoke = function(_Player: Player, TopicName: string): ({[string]: any}?)
			local TopicId = _serviceRegistry.Resolve(TopicName)
			if not TopicId then return nil end
			local Entry = _servicePersistentEntries[TopicId]
			if not Entry then return nil end
			return Codec.ReadStateFromFolder(Entry.Folder)
		end

		if _serviceConfig.ConnectionPing then
			_serviceUnreliableRemote = _GetOrCreateChild(ServiceFolder, "Ping", "UnreliableRemoteEvent") :: UnreliableRemoteEvent
			_serviceUnreliableRemote.OnServerEvent:Connect(_ServiceReceiveServerPing)
		end

		Players.PlayerAdded:Connect(_ServiceOnPlayerAdded)
		Players.PlayerRemoving:Connect(_ServiceOnPlayerRemoving)
	else
		_serviceServerPingProtocol = PingProtocol.new({
			PingInterval = _serviceConfig.PingInterval,
			MaxRetryCount = _serviceConfig.MaxRetryCount,
			DeadPacketWarn = _serviceConfig.DeadPacketWarn,
		})

		_serviceRemoteEvent.OnClientEvent:Connect(_ServiceReceiveClient)

		if _serviceConfig.ConnectionPing then
			_serviceUnreliableRemote = ServiceFolder:WaitForChild("Ping") :: UnreliableRemoteEvent
			_serviceUnreliableRemote.OnClientEvent:Connect(_ServiceReceiveClientPing)
		end

		local LocalUserId = Players.LocalPlayer.UserId

		_serviceInstancingFolder.ChildAdded:Connect(function(Child: Instance)
			if not Child:IsA("StringValue") then return end
			local Separator = string.find(Child.Name, "|")
			if not Separator then return end
			local TargetUserId = tonumber(string.sub(Child.Name, 1, Separator - 1))
			local TopicId = tonumber(string.sub(Child.Name, Separator + 1))
			if not TargetUserId or not TopicId then return end
			if TargetUserId ~= LocalUserId then return end

			local Raw = (Child :: StringValue).Value
			local Buf = Codec.StringToBuffer(Raw)
			local Data = Codec.DecodeValue(Buf)
			local TopicName = _serviceRegistry.ResolveName(TopicId)
			if not TopicName then return end
			_serviceEmitter:Fire("Packet", TopicName, Data)
			_serviceEmitter:Fire(TopicName, Data)
		end)

		_serviceStreamingRootFolder.ChildAdded:Connect(function(PlayerFolder: Instance)
			if not PlayerFolder:IsA("Folder") then return end
			local OwnerUserId = PlayerFolder:GetAttribute("Owner")
			if OwnerUserId ~= LocalUserId then return end

			PlayerFolder.AttributeChanged:Connect(function(AttributeName: string)
				local Value = PlayerFolder:GetAttribute(AttributeName)
				if type(Value) ~= "string" then return end
				local TopicId = tonumber(AttributeName)
				if not TopicId then return end
				local Buf = Codec.StringToBuffer(Value)
				local Data = Codec.DecodeValue(Buf)
				local TopicName = _serviceRegistry.ResolveName(TopicId)
				if not TopicName then return end
				_serviceEmitter:Fire("StreamingPacket", TopicName, Data)
				_serviceEmitter:Fire(TopicName, Data)
			end)
		end)

		_servicePersistentFolder.ChildAdded:Connect(function(TopicFolder: Instance)
			if not TopicFolder:IsA("Folder") then return end
			local TopicId = tonumber(TopicFolder.Name)
			if not TopicId then return end

			local function _OnChange()
				local State = Codec.ReadStateFromFolder(TopicFolder :: Folder)
				local TopicName = _serviceRegistry.ResolveName(TopicId)
				if not TopicName then return end
				_serviceEmitter:Fire("PersistentPacket", TopicName, State)
				_serviceEmitter:Fire(TopicName, State)
			end

			TopicFolder.AttributeChanged:Connect(_OnChange)
			TopicFolder.ChildAdded:Connect(_OnChange)
			TopicFolder.ChildRemoved:Connect(_OnChange)
		end)

		_servicePersistentFolder.ChildRemoved:Connect(function(TopicFolder: Instance)
			local TopicId = tonumber(TopicFolder.Name)
			if not TopicId then return end
			local TopicName = _serviceRegistry.ResolveName(TopicId)
			if not TopicName then return end
			_serviceEmitter:Fire("PersistentRemoved", TopicName)
		end)
	end

	RunService.Heartbeat:Connect(_ServiceOnHeartbeat)
	_serviceFlagSchema:ValidateSecurity()
end

function PacketStreamService.On(EventName: string, Callback: (...any) -> ()): (EventConnection)
	_EnsureInitialized()
	return _serviceEmitter:Connect(EventName, Callback)
end

function PacketStreamService.Once(EventName: string, Callback: (...any) -> ()): (EventConnection)
	_EnsureInitialized()
	return _serviceEmitter:Once(EventName, Callback)
end

function PacketStreamService.Wait(EventName: string): (...any)
	_EnsureInitialized()
	return _serviceEmitter:Wait(EventName)
end

function PacketStreamService.DefinePingFlags(Flags: {[string]: boolean}): ()
	_EnsureInitialized()
	_serviceFlagSchema:Define(Flags)
end

function PacketStreamService.AddSecurityListener(Listener: (FlagName: string, Value: boolean) -> (nil?, string?)): ()
	_EnsureInitialized()
	_serviceFlagSchema:AddSecurityListener(Listener)
end

function PacketStreamService.AddGuardListener(Listener: (FlagName: string, Value: boolean, Reason: string) -> ()): ()
	_EnsureInitialized()
	_serviceFlagSchema:AddGuardListener(Listener)
end

function PacketStreamService.OnFlagChange(Listener: (FlagName: string, Value: boolean) -> ()): ()
	_EnsureInitialized()
	_serviceFlagSchema:OnChange(Listener)
end

function PacketStreamService.SetFlag(FlagName: string, Value: boolean): ()
	_EnsureInitialized()
	_serviceFlagSchema:SetFlag(FlagName, Value)
end

function PacketStreamService.GetFlag(FlagName: string): (boolean)
	_EnsureInitialized()
	return _serviceFlagSchema:GetFlag(FlagName)
end

function PacketStreamService.SetDefaultMode(Target: "SendTo" | "StartStream", Mode: SendMode): ()
	_EnsureInitialized()
	if Target == "SendTo" then
		_serviceDefaultSendMode = Mode
	else
		_serviceDefaultStreamMode = Mode
	end
end

function PacketStreamService.SendTo(Player: Player, Topic: string, Data: any, Mode: SendMode?): ()
	_EnsureInitialized()
	assert(IsServer, "[PacketStream] SendTo is server-only")
	local UseMode = Mode or _serviceDefaultSendMode
	local TopicId = _serviceRegistry.Register(Topic)

	if UseMode == SendModeInstancing then
		local Key = _serviceClientKeys[Player]
		local Buf = Codec.EncodeValue(Data)
		local Raw = Codec.BufferToString(Buf)
		if Key then
			Raw = Encryption.Encrypt(Raw, Key, Encryption.ConsumeNonce(Player))
		end
		local InstanceName = tostring(Player.UserId) .. "|" .. tostring(TopicId)
		local Container = Instance.new("StringValue")
		Container.Name = InstanceName
		Container.Value = Raw
		Container.Parent = _serviceInstancingFolder
		Debris:AddItem(Container, 2)
		return
	end

	if not _serviceOutboundQueues[Player] then
		_serviceOutboundQueues[Player] = {}
	end
	local Queue = _serviceOutboundQueues[Player]
	if #Queue >= _serviceConfig.MaxQueueSize then
		_serviceEmitter:Fire("RateLimited")
		return
	end
	table.insert(Queue, {
		PacketType = PacketTypeEphemeral,
		TopicId = TopicId,
		PacketId = 0,
		Data = Data,
	})
end

function PacketStreamService.Broadcast(Topic: string, Data: any): ()
	_EnsureInitialized()
	assert(IsServer, "[PacketStream] Broadcast is server-only")
	local TopicId = _serviceRegistry.Register(Topic)
	if #_serviceBroadcastQueue >= _serviceConfig.MaxQueueSize then
		_serviceEmitter:Fire("RateLimited")
		return
	end
	table.insert(_serviceBroadcastQueue, {
		PacketType = PacketTypeEphemeral,
		TopicId = TopicId,
		PacketId = 0,
		Data = Data,
	})
end

function PacketStreamService.SetPersistent(Topic: string, State: {[string]: any}): ()
	_EnsureInitialized()
	assert(IsServer, "[PacketStream] SetPersistent is server-only")
	local TopicId = _serviceRegistry.Register(Topic)
	local Existing = _servicePersistentEntries[TopicId]

	if Existing then
		local OldState = Codec.ReadStateFromFolder(Existing.Folder)
		Codec.SyncStateToFolder(Existing.Folder, State, OldState)
		Existing.LastState = State
	else
		local TopicFolder = Instance.new("Folder")
		TopicFolder.Name = tostring(TopicId)
		TopicFolder.Parent = _servicePersistentFolder
		Codec.SyncStateToFolder(TopicFolder, State, nil)
		_servicePersistentEntries[TopicId] = {
			Folder = TopicFolder,
			LastState = State,
		}
	end
end

function PacketStreamService.RemovePersistent(Topic: string): ()
	_EnsureInitialized()
	assert(IsServer, "[PacketStream] RemovePersistent is server-only")
	local TopicId = _serviceRegistry.Resolve(Topic)
	if not TopicId then return end
	local Entry = _servicePersistentEntries[TopicId]
	if not Entry then return end
	Entry.Folder:Destroy()
	_servicePersistentEntries[TopicId] = nil
end

function PacketStreamService.StartStream(Player: Player, Topic: string, InitialData: any, Mode: SendMode?): (StreamHandle?)
	_EnsureInitialized()
	assert(IsServer, "[PacketStream] StartStream is server-only")
	local UseMode = Mode or _serviceDefaultStreamMode
	local TopicId = _serviceRegistry.Register(Topic)

	if not _serviceStreamingEntries[Player] then
		_serviceStreamingEntries[Player] = {}
	end

	local Entry: StreamingEntry = {
		TopicId = TopicId,
		Data = InitialData,
		Mode = UseMode,
		PingProtocol = _servicePingProtocols[Player],
	}
	_serviceStreamingEntries[Player][TopicId] = Entry

	if not _serviceConfig.AllowManualStreamControl then
		return nil
	end

	local Handle = {}

	function Handle.Update(Data: any): ()
		Entry.Data = Data
		local Buf = Codec.EncodeValue(Data)
		local Raw = Codec.BufferToString(Buf)

		if Entry.Mode == SendModeInstancing then
			local PlayerFolder = _serviceStreamingRootFolder:FindFirstChild(tostring(Player.UserId))
			if PlayerFolder then
				local Key = _serviceClientKeys[Player]
				if Key then
					Raw = Encryption.Encrypt(Raw, Key, Encryption.ConsumeNonce(Player))
				end
				PlayerFolder:SetAttribute(tostring(TopicId), Raw)
			end
		else
			if not _serviceOutboundQueues[Player] then
				_serviceOutboundQueues[Player] = {}
			end
			table.insert(_serviceOutboundQueues[Player], {
				PacketType = PacketTypeStreamUpdate,
				TopicId = TopicId,
				PacketId = 0,
				Data = Data,
			})
		end
	end

	function Handle.Stop(): ()
		if _serviceStreamingEntries[Player] then
			_serviceStreamingEntries[Player][TopicId] = nil
		end
		if not _serviceOutboundQueues[Player] then
			_serviceOutboundQueues[Player] = {}
		end
		table.insert(_serviceOutboundQueues[Player], {
			PacketType = PacketTypeStreamStop,
			TopicId = TopicId,
			PacketId = 0,
			Data = nil,
		})
	end

	function Handle.SetMode(NewMode: SendMode): ()
		Entry.Mode = NewMode
		_serviceEmitter:Fire("StreamModeChanged", Player, Topic, NewMode)
	end

	return Handle
end

function PacketStreamService.Send(Topic: string, Data: any): ()
	_EnsureInitialized()
	assert(not IsServer, "[PacketStream] Send is client-only")
	if not _serviceConfig.AllowClientStreaming then
		warn("[PacketStream] AllowClientStreaming is disabled")
		return
	end
	local TopicId = _serviceRegistry.Register(Topic)
	if #_serviceClientQueue >= _serviceConfig.MaxQueueSize then
		_serviceEmitter:Fire("RateLimited")
		return
	end
	table.insert(_serviceClientQueue, {
		PacketType = PacketTypeEphemeral,
		TopicId = TopicId,
		PacketId = 0,
		Data = Data,
	})
end

function PacketStreamService.RequestState(Topic: string): ({[string]: any}?)
	_EnsureInitialized()
	assert(not IsServer, "[PacketStream] RequestState is client-only")
	return _serviceRemoteFunction:InvokeServer(Topic)
end

function PacketStreamService.Stats(): ({
	IsInstancing: boolean,
	RateBucket: number,
	OutboundTotal: number,
	PersistentTopics: number,
	ActiveStreams: number,
})
	_EnsureInitialized()
	local OutboundTotal = 0
	for _, Queue in pairs(_serviceOutboundQueues) do
		OutboundTotal += #Queue
	end
	OutboundTotal += #_serviceBroadcastQueue
	local PersistentTopics = 0
	for _ in pairs(_servicePersistentEntries) do
		PersistentTopics += 1
	end
	local ActiveStreams = 0
	for _, TopicMap in pairs(_serviceStreamingEntries) do
		for _ in pairs(TopicMap) do
			ActiveStreams += 1
		end
	end
	_serviceStatsCache.IsInstancing = _serviceIsInstancing
	_serviceStatsCache.RateBucket = _serviceRateBucket
	_serviceStatsCache.OutboundTotal = OutboundTotal
	_serviceStatsCache.PersistentTopics = PersistentTopics
	_serviceStatsCache.ActiveStreams = ActiveStreams
	return _serviceStatsCache
end

function PacketStreamService.new(Name: string, UserConfig: PacketStreamerConfiguration?): (PacketStreamer)
	_EnsureInitialized()
	assert(_serviceConfig.AllowIndependentStream, "[PacketStream] AllowIndependentStream is disabled")

	local Fallback: ResolvedStreamerConfig
	if _serviceConfig.IndependentInheritance then
		Fallback = {
			InstancingStream = _serviceConfig.InstancingStream,
			AutoInstancingStream = _serviceConfig.AutoInstancingStream,
			PersistentStreamInterval = _serviceConfig.PersistentStreamInterval,
			StreamInterval = _serviceConfig.StreamInterval,
			RateLimit = _serviceConfig.RateLimit,
			ConnectionPing = _serviceConfig.ConnectionPing,
			MaxQueueSize = _serviceConfig.MaxQueueSize,
			DebugMode = _serviceConfig.DebugMode,
			UseSecureStorage = _serviceConfig.UseSecureStorage,
			PingInterval = _serviceConfig.PingInterval,
			MaxRetryCount = _serviceConfig.MaxRetryCount,
			DeadPacketWarn = _serviceConfig.DeadPacketWarn,
			KeyRotationCooldown = _serviceConfig.KeyRotationCooldown,
			AllowManualStreamControl = _serviceConfig.AllowManualStreamControl,
			DefaultSendMode = _serviceConfig.DefaultSendMode,
			DefaultStreamMode = _serviceConfig.DefaultStreamMode,
		}
	else
		Fallback = StreamerDefaults
	end

	local ResolvedConfig = _ResolveStreamerConfig(UserConfig, Fallback)
	local self = setmetatable({}, PacketStreamService)
	self._statsCache = {
		IsInstancing = false,
		RateBucket = 0,
		OutboundTotal = 0,
		PersistentTopics = 0,
		ActiveStreams = 0,
	}
	PacketStreamer._Init(self, Name, ResolvedConfig)
	return self :: any
end

export type PacketStreamer = {
	On: (self: PacketStreamer, EventName: string, Callback: (...any) -> ()) -> (EventConnection),
	Once: (self: PacketStreamer, EventName: string, Callback: (...any) -> ()) -> (EventConnection),
	Wait: (self: PacketStreamer, EventName: string) -> (...any),
	DefinePingFlags: (self: PacketStreamer, Flags: {[string]: boolean}) -> (),
	AddSecurityListener: (self: PacketStreamer, Listener: (FlagName: string, Value: boolean) -> (nil?, string?)) -> (),
	AddGuardListener: (self: PacketStreamer, Listener: (FlagName: string, Value: boolean, Reason: string) -> ()) -> (),
	OnFlagChange: (self: PacketStreamer, Listener: (FlagName: string, Value: boolean) -> ()) -> (),
	SetFlag: (self: PacketStreamer, FlagName: string, Value: boolean) -> (),
	GetFlag: (self: PacketStreamer, FlagName: string) -> (boolean),
	SetDefaultMode: (self: PacketStreamer, Target: "SendTo" | "StartStream", Mode: SendMode) -> (),
	SendTo: (self: PacketStreamer, Player: Player, Topic: string, Data: any, Mode: SendMode?) -> (),
	Broadcast: (self: PacketStreamer, Topic: string, Data: any) -> (),
	SetPersistent: (self: PacketStreamer, Topic: string, State: {[string]: any}) -> (),
	RemovePersistent: (self: PacketStreamer, Topic: string) -> (),
	StartStream: (self: PacketStreamer, Player: Player, Topic: string, InitialData: any, Mode: SendMode?) -> (StreamHandle?),
	Send: (self: PacketStreamer, Topic: string, Data: any) -> (),
	RequestState: (self: PacketStreamer, Topic: string) -> ({[string]: any}?),
	Stats: (self: PacketStreamer) -> ({
		IsInstancing: boolean,
		RateBucket: number,
		OutboundTotal: number,
		PersistentTopics: number,
		ActiveStreams: number,
	}),
	Destroy: (self: PacketStreamer) -> (),
}

export type PacketStreamService = {
	Configure: (Config: PacketStreamServiceConfiguration) -> (),
	On: (EventName: string, Callback: (...any) -> ()) -> (EventConnection),
	Once: (EventName: string, Callback: (...any) -> ()) -> (EventConnection),
	Wait: (EventName: string) -> (...any),
	DefinePingFlags: (Flags: {[string]: boolean}) -> (),
	AddSecurityListener: (Listener: (FlagName: string, Value: boolean) -> (nil?, string?)) -> (),
	AddGuardListener: (Listener: (FlagName: string, Value: boolean, Reason: string) -> ()) -> (),
	OnFlagChange: (Listener: (FlagName: string, Value: boolean) -> ()) -> (),
	SetFlag: (FlagName: string, Value: boolean) -> (),
	GetFlag: (FlagName: string) -> (boolean),
	SetDefaultMode: (Target: "SendTo" | "StartStream", Mode: SendMode) -> (),
	SendTo: (Player: Player, Topic: string, Data: any, Mode: SendMode?) -> (),
	Broadcast: (Topic: string, Data: any) -> (),
	SetPersistent: (Topic: string, State: {[string]: any}) -> (),
	RemovePersistent: (Topic: string) -> (),
	StartStream: (Player: Player, Topic: string, InitialData: any, Mode: SendMode?) -> (StreamHandle?),
	Send: (Topic: string, Data: any) -> (),
	RequestState: (Topic: string) -> ({[string]: any}?),
	Stats: () -> ({
		IsInstancing: boolean,
		RateBucket: number,
		OutboundTotal: number,
		PersistentTopics: number,
		ActiveStreams: number,
	}),
	new: (Name: string, Config: PacketStreamerConfiguration?) -> (PacketStreamer),
}

return PacketStreamService :: PacketStreamService
