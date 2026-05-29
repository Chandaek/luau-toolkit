local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Codec = require("@self/Codec")
local Encryption = require("@self/Encryption")
local PingProtocol = require("@self/PingProtocol")
local FlagSchema = require("@self/FlagSchema")
local Shared = require("@self/Shared")
local PacketStreamer = require("@self/PacketStreamer")

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
local SendModeNormal = Shared.SendModeNormal
local SendModeInstancing = Shared.SendModeInstancing
local _GetRootFolder = Shared.GetRootFolder
local _GetOrCreateChild = Shared.GetOrCreateChild
local _CreateTopicRegistry = Shared.CreateTopicRegistry

export type SendMode = PacketStreamer.SendMode
export type StreamHandle = PacketStreamer.StreamHandle
export type EventConnection = PacketStreamer.EventConnection
export type PacketStreamerConfiguration = PacketStreamer.PacketStreamerConfiguration

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

-- ==========================================================
-- SERVICE STATE
-- ==========================================================

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

-- ==========================================================
-- SERVICE INTERNAL: FLUSH
-- ==========================================================

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

-- ==========================================================
-- SERVICE INTERNAL: TICK
-- ==========================================================

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

-- ==========================================================
-- SERVICE INTERNAL: PLAYER EVENTS
-- ==========================================================

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

-- ==========================================================
-- SERVICE INTERNAL: RECEIVE
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SETUP
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: EVENTS
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: FLAGS
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SERVER DISPATCH
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SERVER PERSISTENCE
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: SERVER STREAM
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: CLIENT
-- ==========================================================

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

-- ==========================================================
-- PUBLIC: MANAGEMENT
-- ==========================================================

function PacketStreamService.SetDefaultMode(Target: "SendTo" | "StartStream", Mode: SendMode): ()
	_EnsureInitialized()
	if Target == "SendTo" then
		_serviceDefaultSendMode = Mode
	else
		_serviceDefaultStreamMode = Mode
	end
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

-- ==========================================================
-- PUBLIC: FACTORY
-- ==========================================================

function PacketStreamService.new(Name: string, UserConfig: PacketStreamerConfiguration?): (PacketStreamer.PacketStreamer)
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
	SendTo: (Player: Player, Topic: string, Data: any, Mode: SendMode?) -> (),
	Broadcast: (Topic: string, Data: any) -> (),
	SetPersistent: (Topic: string, State: {[string]: any}) -> (),
	RemovePersistent: (Topic: string) -> (),
	StartStream: (Player: Player, Topic: string, InitialData: any, Mode: SendMode?) -> (StreamHandle?),
	Send: (Topic: string, Data: any) -> (),
	RequestState: (Topic: string) -> ({[string]: any}?),
	SetDefaultMode: (Target: "SendTo" | "StartStream", Mode: SendMode) -> (),
	Stats: () -> ({
		IsInstancing: boolean,
		RateBucket: number,
		OutboundTotal: number,
		PersistentTopics: number,
		ActiveStreams: number,
	}),
	new: (Name: string, Config: PacketStreamerConfiguration?) -> (PacketStreamer.PacketStreamer),
}

return PacketStreamService :: PacketStreamService
