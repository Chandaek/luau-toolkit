local _rng = Random.new()

local function _U32(Value: number): number
	return bit32.band(Value, 0xFFFFFFFF)
end

local function _HashBytes(Hash: number, Input: string): number
	for Index = 1, #Input do
		Hash = bit32.bxor(Hash, string.byte(Input, Index))
		Hash = _U32(Hash * 16777619)
	end
	return Hash
end

local function _HashNonce(Hash: number, Nonce: number): number
	local Low = _U32(Nonce)
	local High = _U32(math.floor(Nonce / 4294967296))

	Hash = _HashBytes(Hash, string.char(
		bit32.band(Low, 0xFF),
		bit32.band(bit32.rshift(Low, 8), 0xFF),
		bit32.band(bit32.rshift(Low, 16), 0xFF),
		bit32.band(bit32.rshift(Low, 24), 0xFF),
		bit32.band(High, 0xFF),
		bit32.band(bit32.rshift(High, 8), 0xFF),
		bit32.band(bit32.rshift(High, 16), 0xFF),
		bit32.band(bit32.rshift(High, 24), 0xFF)
	))

	return Hash
end

local function _SplitMix32Step(Seed: number): (number, number)
	Seed = _U32(Seed + 0x9E3779B9)

	local Output = Seed
	Output = _U32(bit32.bxor(Output, bit32.rshift(Output, 16)) * 0x85EBCA6B)
	Output = _U32(bit32.bxor(Output, bit32.rshift(Output, 13)) * 0xC2B2AE35)
	Output = bit32.bxor(Output, bit32.rshift(Output, 16))

	return Seed, Output
end

local function _SeedState(Key: string, Nonce: number): ({number})
	local Seed = 0x811C9DC5

	Seed = _HashBytes(Seed, Key)
	Seed = _HashNonce(Seed, Nonce)

	local Carrier = Seed
	local State = table.create(4)

	Carrier, State[1] = _SplitMix32Step(Carrier)
	Carrier, State[2] = _SplitMix32Step(Carrier)
	Carrier, State[3] = _SplitMix32Step(Carrier)
	Carrier, State[4] = _SplitMix32Step(Carrier)

	if State[1] == 0 then
		State[1] = 0xDEADBEEF
	end

	if State[2] == 0 then
		State[2] = 0xCAFEBABE
	end

	if State[3] == 0 then
		State[3] = 0xFEEDFACE
	end

	if State[4] == 0 then
		State[4] = 0xC0FFEE00
	end

	return State
end

local function _NextByte(State: {number}): number
	local T = State[4]

	T = bit32.bxor(T, bit32.lshift(T, 11))
	T = bit32.bxor(T, bit32.rshift(T, 8))

	State[4] = State[3]
	State[3] = State[2]
	State[2] = State[1]

	T = bit32.bxor(T, State[1])
	T = bit32.bxor(T, bit32.rshift(State[1], 19))

	State[1] = T

	return bit32.band(T, 0xFF)
end

type ClientEntry = {
	Key: string,
	Nonce: number,
}

local _clientEntries: {[Player]: ClientEntry} = {}

local _pendingRotation = false
local _rotationElapsed = 0

local Encryption = {}

function Encryption.GenerateKey(): string
	local Bytes = table.create(16)

	for Index = 1, 16 do
		Bytes[Index] = _rng:NextInteger(0, 255)
	end

	return string.char(table.unpack(Bytes))
end

function Encryption.Encrypt(Data: string, Key: string, Nonce: number): string
	local State = _SeedState(Key, Nonce)

	local Length = #Data
	local Output = table.create(Length)

	for Index = 1, Length do
		Output[Index] = bit32.bxor(
			string.byte(Data, Index),
			_NextByte(State)
		)
	end

	return string.char(table.unpack(Output))
end

function Encryption.Decrypt(Data: string, Key: string, Nonce: number): string
	return Encryption.Encrypt(Data, Key, Nonce)
end

function Encryption.HashName(UserId: number, TopicId: number, Key: string): string
	local Seed = tostring(UserId) .. "|" .. tostring(TopicId) .. Key
	return string.format("%08X", _HashBytes(0x811C9DC5, Seed))
end

function Encryption.RegisterClient(Player: Player, Key: string): ()
	_clientEntries[Player] = {
		Key = Key,
		Nonce = 0,
	}
end

function Encryption.GetClientKey(Player: Player): string?
	local Entry = _clientEntries[Player]
	return Entry and Entry.Key or nil
end

function Encryption.ConsumeNonce(Player: Player): number
	local Entry = _clientEntries[Player]

	if not Entry then
		return 0
	end

	Entry.Nonce += 1

	return Entry.Nonce
end

function Encryption.RemoveClient(Player: Player): ()
	_clientEntries[Player] = nil
end

function Encryption.RequestRotation(): ()
	_pendingRotation = true
	_rotationElapsed = 0
end

function Encryption.TickRotation(DeltaMs: number, CooldownMs: number): boolean
	if not _pendingRotation then
		return false
	end

	_rotationElapsed += DeltaMs

	if _rotationElapsed < CooldownMs then
		return false
	end

	_pendingRotation = false
	_rotationElapsed = 0

	return true
end

return Encryption
