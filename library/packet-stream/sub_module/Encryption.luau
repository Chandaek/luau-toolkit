local _rng = Random.new()

local function _FNVHash(Input: string): (number)
	local Hash = 2166136261
	for Index = 1, #Input do
		Hash = bit32.bxor(Hash, string.byte(Input, Index))
		Hash = bit32.band(Hash * 16777619, 0xFFFFFFFF)
	end
	return Hash
end

local function _SeedState(Key: string, Nonce: number): ({number})
	local S1 = string.unpack(">I4", Key, 1)
	local S2 = string.unpack(">I4", Key, 5)
	local S3 = string.unpack(">I4", Key, 9)
	local S4 = bit32.bxor(string.unpack(">I4", Key, 13), Nonce)
	return {S1, S2, S3, S4}
end

local function _NextByte(State: {number}): (number)
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

function Encryption.GenerateKey(): (string)
	local Bytes = table.create(16)
	for Index = 1, 16 do
		Bytes[Index] = _rng:NextInteger(0, 255)
	end
	return string.char(table.unpack(Bytes))
end

function Encryption.Encrypt(Data: string, Key: string, Nonce: number): (string)
	local State = _SeedState(Key, Nonce)
	local Length = #Data
	local Output = table.create(Length)
	for Index = 1, Length do
		Output[Index] = bit32.bxor(string.byte(Data, Index), _NextByte(State))
	end
	return string.char(table.unpack(Output))
end

function Encryption.Decrypt(Data: string, Key: string, Nonce: number): (string)
	return Encryption.Encrypt(Data, Key, Nonce)
end

function Encryption.HashName(UserId: number, TopicId: number, Key: string): (string)
	local Seed = tostring(UserId) .. "|" .. tostring(TopicId) .. Key
	return string.format("%08X", _FNVHash(Seed))
end

function Encryption.RegisterClient(Player: Player, Key: string): ()
	_clientEntries[Player] = {Key = Key, Nonce = 0}
end

function Encryption.GetClientKey(Player: Player): (string?)
	local Entry = _clientEntries[Player]
	return Entry and Entry.Key or nil
end

function Encryption.ConsumeNonce(Player: Player): (number)
	local Entry = _clientEntries[Player]
	if not Entry then return 0 end
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

function Encryption.TickRotation(DeltaMs: number, CooldownMs: number): (boolean)
	if not _pendingRotation then return false end
	_rotationElapsed += DeltaMs
	if _rotationElapsed < CooldownMs then return false end
	_pendingRotation = false
	_rotationElapsed = 0
	return true
end

return Encryption
