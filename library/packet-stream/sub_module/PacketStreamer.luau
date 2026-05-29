local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Codec = require("@self/Codec")
local Encryption = require("@self/Encryption")
local PingProtocol = require("@self/PingProtocol")
local FlagSchema = require("@self/FlagSchema")
local Shared = require("@self/Shared")

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
	if not Ok or not Result then return nil end
	return Result
end)()

assert(EventEmitter, "[PacketStream] Cannot start without EventEmitter")

local IsServer = Shared.IsServer
local PacketTypeEphemeral = Shared.PacketTypeEphemeral
local PacketTypePersistentFull = Shared.PacketTypePersistentFull
local PacketTypeStreamUpdate = Shared.PacketTypeStreamUpdate
local PacketTypeStreamStop = Shared.PacketTypeStreamStop
local PacketTypeKeyDelivery = Shared.PacketTypeKeyDelivery
local PacketTypeKeyAck = Shared.PacketTypeKeyAck
local SendModeInstancing = Shared.SendModeInstancing
local _GetRootFolder = Shared.GetRootFolder
local _GetOrCreateChild = Shared.GetOrCreateChild
local _CreateTopicRegistry = Shared.CreateTopicRegistry

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

local PacketStreamer = {}
PacketStreamer.__index = PacketStreamer

-- ==========================================================
-- INTERNAL: LIFECYCLE
-- ==========================================================

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

-- ==========================================================
-- INTERNAL: PLAYER EVENTS
-- ==========================================================

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

-- ==========================================================
-- INTERNAL: CLIENT LISTENERS
-- ==========================================================

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

-- ==========================================================
-- INTERNAL: RECEIVE
-- ==========================================================

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

-- ==========================================================
-- INTERNAL: FLUSH
-- ==========================================================

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

-- ==========================================================
-- INTERNAL: TICK
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: EVENTS
-- ==========================================================

function PacketStreamer:On(EventName: string, Callback: (...any) -> ()): (EventConnection)
	return self._emitter:Connect(EventName, Callback)
end

function PacketStreamer:Once(EventName: string, Callback: (...any) -> ()): (EventConnection)
	return self._emitter:Once(EventName, Callback)
end

function PacketStreamer:Wait(EventName: string): (...any)
	return self._emitter:Wait(EventName)
end

-- ==========================================================
-- PUBLIC: FLAGS
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SERVER DISPATCH
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SERVER PERSISTENCE
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SERVER STREAM
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: CLIENT
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: MANAGEMENT
-- ==========================================================

function PacketStreamer:SetDefaultMode(Target: "SendTo" | "StartStream", Mode: SendMode): ()
	if Target == "SendTo" then
		self._defaultSendMode = Mode
	else
		self._defaultStreamMode = Mode
	end
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
	SendTo: (self: PacketStreamer, Player: Player, Topic: string, Data: any, Mode: SendMode?) -> (),
	Broadcast: (self: PacketStreamer, Topic: string, Data: any) -> (),
	SetPersistent: (self: PacketStreamer, Topic: string, State: {[string]: any}) -> (),
	RemovePersistent: (self: PacketStreamer, Topic: string) -> (),
	StartStream: (self: PacketStreamer, Player: Player, Topic: string, InitialData: any, Mode: SendMode?) -> (StreamHandle?),
	Send: (self: PacketStreamer, Topic: string, Data: any) -> (),
	RequestState: (self: PacketStreamer, Topic: string) -> ({[string]: any}?),
	SetDefaultMode: (self: PacketStreamer, Target: "SendTo" | "StartStream", Mode: SendMode) -> (),
	Stats: (self: PacketStreamer) -> ({
		IsInstancing: boolean,
		RateBucket: number,
		OutboundTotal: number,
		PersistentTopics: number,
		ActiveStreams: number,
	}),
	Destroy: (self: PacketStreamer) -> (),
}

return PacketStreamer