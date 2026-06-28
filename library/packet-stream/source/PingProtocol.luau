local StatusDelivered = 0
local StatusMissing = 1
local StatusWillResend = 2
local StatusGot = 3
local StatusGotAck = 4

type PendingEntry = {
	Data: any,
	Retries: number,
	ElapsedMs: number,
	RetryAfterMs: number,
	SentAt: number,
	DeadWarned: boolean,
	State: number,
}

type AckEntry = {
	PacketId: number,
	Status: number,
}

type PingProtocolConfig = {
	PingInterval: number,
	MaxRetryCount: number,
	DeadPacketWarn: number,
	BackoffFactor: number?,
	MaxRetryInterval: number?,
	RttAlpha: number?,
	RttBetaJitter: number?,
}

type ResendCallback = (PacketId: number, Data: any) -> ()
type DropCallback = (PacketId: number) -> ()

local PingProtocol = {}
PingProtocol.__index = PingProtocol

function PingProtocol.new(Config: PingProtocolConfig): (any)
	local self = setmetatable({}, PingProtocol)
	self._config = table.freeze(table.clone(Config))
	self._outboundPending = {} :: {[number]: PendingEntry}
	self._inboundReceived = {} :: {[number]: boolean}
	self._outboundAcks = {} :: {AckEntry}
	self._elapsed = 0
	self._nextId = 0
	self._smoothedRtt = Config.PingInterval * 2
	self._rttVariance = Config.PingInterval
	self._backoffFactor = Config.BackoffFactor or 2.0
	self._maxRetryInterval = Config.MaxRetryInterval or 5000
	self._rttAlpha = Config.RttAlpha or 0.125
	self._rttBeta = Config.RttBetaJitter or 0.25
	return self
end

function PingProtocol._AllocateId(self): (number)
	local Id = self._nextId
	self._nextId = (self._nextId + 1) % 65536
	return Id
end

function PingProtocol._ComputeRto(self): (number)
	return math.min(
		self._smoothedRtt + math.max(1, 4 * self._rttVariance),
		self._maxRetryInterval
	)
end

function PingProtocol._UpdateRtt(self, SampleMs: number): ()
	local Error = math.abs(self._smoothedRtt - SampleMs)
	self._smoothedRtt = (1 - self._rttAlpha) * self._smoothedRtt + self._rttAlpha * SampleMs
	self._rttVariance = (1 - self._rttBeta) * self._rttVariance + self._rttBeta * Error
end

function PingProtocol.EncodePing(AckEntries: {AckEntry}, FlagBytes: string): (buffer)
	local AckCount = #AckEntries
	local FlagLength = #FlagBytes
	local Buf = buffer.create(1 + FlagLength + 2 + AckCount * 3)
	buffer.writeu8(Buf, 0, FlagLength)
	if FlagLength > 0 then
		buffer.writestring(Buf, 1, FlagBytes)
	end
	buffer.writeu16(Buf, 1 + FlagLength, AckCount)
	local Offset = 3 + FlagLength
	for _, Entry in AckEntries do
		buffer.writeu16(Buf, Offset, Entry.PacketId)
		buffer.writeu8(Buf, Offset + 2, Entry.Status)
		Offset += 3
	end
	return Buf
end

function PingProtocol.DecodePing(Buf: buffer): ({AckEntry}, string)
	local FlagLength = buffer.readu8(Buf, 0)
	local FlagBytes = FlagLength > 0 and buffer.readstring(Buf, 1, FlagLength) or ""
	local AckCount = buffer.readu16(Buf, 1 + FlagLength)
	local Entries = table.create(AckCount)
	local Offset = 3 + FlagLength
	for Index = 1, AckCount do
		Entries[Index] = {
			PacketId = buffer.readu16(Buf, Offset),
			Status = buffer.readu8(Buf, Offset + 2),
		}
		Offset += 3
	end
	return Entries, FlagBytes
end

function PingProtocol:TrackOutbound(Data: any): (number)
	local Id = PingProtocol._AllocateId(self)
	self._outboundPending[Id] = {
		Data = Data,
		Retries = 0,
		ElapsedMs = 0,
		RetryAfterMs = PingProtocol._ComputeRto(self),
		SentAt = os.clock(),
		DeadWarned = false,
		State = StatusDelivered,
	}
	table.insert(self._outboundAcks, {PacketId = Id, Status = StatusDelivered})
	return Id
end

function PingProtocol:MarkInboundReceived(PacketId: number): ()
	self._inboundReceived[PacketId] = true
end

function PingProtocol:ReceiveAcks(AckEntries: {AckEntry}, OnResend: ResendCallback, OnDrop: DropCallback): ()
	for _, Entry in AckEntries do
		local PacketId = Entry.PacketId
		local Status = Entry.Status

		if Status == StatusDelivered then
			if self._inboundReceived[PacketId] then
				self._inboundReceived[PacketId] = nil
				table.insert(self._outboundAcks, {PacketId = PacketId, Status = StatusGot})
			else
				table.insert(self._outboundAcks, {PacketId = PacketId, Status = StatusMissing})
			end
		elseif Status == StatusMissing then
			local Pending = self._outboundPending[PacketId]
			if Pending then
				Pending.State = StatusWillResend
				table.insert(self._outboundAcks, {PacketId = PacketId, Status = StatusWillResend})
				OnResend(PacketId, Pending.Data)
			end
		elseif Status == StatusWillResend then
			local Pending = self._outboundPending[PacketId]
			if Pending then
				Pending.State = StatusDelivered
				Pending.ElapsedMs = 0
			end
		elseif Status == StatusGot then
			local Pending = self._outboundPending[PacketId]
			if Pending then
				local SampleMs = (os.clock() - Pending.SentAt) * 1000
				PingProtocol._UpdateRtt(self, SampleMs)
			end
			self._outboundPending[PacketId] = nil
			table.insert(self._outboundAcks, {PacketId = PacketId, Status = StatusGotAck})
		elseif Status == StatusGotAck then
			self._inboundReceived[PacketId] = nil
		end
	end
end

function PingProtocol:Tick(DeltaMs: number, OnResend: ResendCallback, OnDrop: DropCallback): ({AckEntry})
	local Config = self._config
	local ToRemove = {}

	for PacketId, Pending in pairs(self._outboundPending) do
		Pending.ElapsedMs += DeltaMs
		if Pending.ElapsedMs < Pending.RetryAfterMs then continue end
		Pending.ElapsedMs = 0
		Pending.Retries += 1
		Pending.RetryAfterMs = math.min(
			Pending.RetryAfterMs * self._backoffFactor,
			self._maxRetryInterval
		)
		Pending.SentAt = os.clock()

		if Config.DeadPacketWarn > 0 and Pending.Retries >= Config.DeadPacketWarn and not Pending.DeadWarned then
			Pending.DeadWarned = true
			warn(`[PacketStream:PingProtocol] Packet {PacketId} retrying (attempt {Pending.Retries})`)
		end

		if Config.MaxRetryCount > 0 and Pending.Retries >= Config.MaxRetryCount then
			OnDrop(PacketId)
			table.insert(ToRemove, PacketId)
		else
			table.insert(self._outboundAcks, {PacketId = PacketId, Status = Pending.State})
		end
	end

	for _, PacketId in ToRemove do
		self._outboundPending[PacketId] = nil
	end

	self._elapsed += DeltaMs
	if self._elapsed < Config.PingInterval then
		return {}
	end
	self._elapsed = 0

	local Snapshot = self._outboundAcks
	self._outboundAcks = {}
	return Snapshot
end

function PingProtocol:GetSmoothedRtt(): (number)
	return self._smoothedRtt
end

function PingProtocol:GetRttVariance(): (number)
	return self._rttVariance
end

return PingProtocol
