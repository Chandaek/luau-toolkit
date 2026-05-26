local TagNil = 0
local TagFalse = 1
local TagTrue = 2
local TagNumber = 3
local TagString = 4

local TierHot = 0
local TierCold = 1
local TierPinned = 2

local function IsPrimitive(Value: any): (boolean)
	local T = type(Value)
	return T == "nil" or T == "boolean" or T == "number" or T == "string"
end

local function EncodedSize(Value: any): (number)
	local T = type(Value)
	if T == "nil" or T == "boolean" then return 1 end
	if T == "number" then return 9 end
	if T == "string" then return 5 + #Value end
	return 0
end

local function Encode(Buf: buffer, Offset: number, Value: any): (number)
	local T = type(Value)
	if T == "nil" then
		buffer.writeu8(Buf, Offset, TagNil)
		return Offset + 1
	elseif T == "boolean" then
		buffer.writeu8(Buf, Offset, Value and TagTrue or TagFalse)
		return Offset + 1
	elseif T == "number" then
		buffer.writeu8(Buf, Offset, TagNumber)
		buffer.writef64(Buf, Offset + 1, Value)
		return Offset + 9
	elseif T == "string" then
		local Len = #Value
		buffer.writeu8(Buf, Offset, TagString)
		buffer.writeu32(Buf, Offset + 1, Len)
		buffer.writestring(Buf, Offset + 5, Value)
		return Offset + 5 + Len
	end
	error(`[SecureStorage] Unencodable type: {T}`)
end

local function Decode(Buf: buffer, Offset: number): (any, number)
	local Tag = buffer.readu8(Buf, Offset)
	if Tag == TagNil then return nil, Offset + 1 end
	if Tag == TagFalse then return false, Offset + 1 end
	if Tag == TagTrue then return true, Offset + 1 end
	if Tag == TagNumber then return buffer.readf64(Buf, Offset + 1), Offset + 9 end
	if Tag == TagString then
		local Len = buffer.readu32(Buf, Offset + 1)
		return buffer.readstring(Buf, Offset + 5, Len), Offset + 5 + Len
	end
	error(`[SecureStorage] Unknown tag: {Tag}`)
end

export type StorageConfiguration = {
	DataMigration: boolean?,
	BufferMigrationRequest: number?,
	BufferMigrationResetTime: number?,
	BufferDefaultBudget: number?,
	BufferBudgetAllocation: ("Auto" | "Manual")?,
	StoreToBufferOnSet: boolean?,
	TableMigrationTime: number?,
	MaxBudget: number?,
	CompactionThreshold: number?,
	FlushInterval: number?,
	SmartShrink: boolean?,
	ShrinkHeadroom: number?,
}

local SecureStorage = {}

function SecureStorage._EnsureCapacity(self, Need: number): ()
	local Cap = buffer.len(self._coldBuffer)
	if self._writeHead + Need <= Cap then return end
	if self._config.BufferBudgetAllocation == "Manual" then
		error("[SecureStorage] Buffer full. Call :Expand() or switch BufferBudgetAllocation to Auto.")
	end
	local Expansion = math.max(self._config.BufferDefaultBudget, Need)
	local Max = self._config.MaxBudget
	if Max > 0 then
		local Remaining = Max - Cap
		if Remaining <= 0 then
			error("[SecureStorage] MaxBudget reached.")
		end
		Expansion = math.min(Expansion, Remaining)
		if Expansion < Need then
			error("[SecureStorage] Cannot expand: MaxBudget too restrictive.")
		end
	end
	local New = buffer.create(Cap + Expansion)
	buffer.copy(New, 0, self._coldBuffer, 0, self._writeHead)
	self._coldBuffer = New
end

function SecureStorage._Compact(self): ()
	local ActualUsed = self._writeHead - self._freeBytes
	local NewCapacity
	
	if self._config.SmartShrink then
		local PotentialMigration = 0
		for Key, Tier in pairs(self._tier) do
			if Tier == TierHot then
				PotentialMigration += EncodedSize(self._hotStore[Key])
			end
		end
		local Target = math.ceil((ActualUsed + PotentialMigration) * (1 + self._config.ShrinkHeadroom))
		NewCapacity = math.max(self._config.BufferDefaultBudget, Target)
	else
		NewCapacity = ActualUsed + self._config.BufferDefaultBudget
	end
	
	local New = buffer.create(NewCapacity)
	local Head = 0
	for Key, Offset in pairs(self._coldIndex) do
		local Size = self._coldSize[Key]
		buffer.copy(New, Head, self._coldBuffer, Offset, Size)
		self._coldIndex[Key] = Head
		Head += Size
	end
	self._coldBuffer = New
	self._writeHead = Head
	self._freeBytes = 0
end

function SecureStorage._MoveToBuffer(self, Key: string): ()
	local Value = self._hotStore[Key]
	local Size = EncodedSize(Value)
	SecureStorage._EnsureCapacity(self, Size)
	Encode(self._coldBuffer, self._writeHead, Value)
	self._coldIndex[Key] = self._writeHead
	self._coldSize[Key] = Size
	self._writeHead += Size
	self._hotStore[Key] = nil
	self._tier[Key] = TierCold
end

function SecureStorage._MoveToTable(self, Key: string): ()
	local Value = Decode(self._coldBuffer, self._coldIndex[Key])
	self._hotStore[Key] = Value
	self._freeBytes += self._coldSize[Key]
	self._coldIndex[Key] = nil
	self._coldSize[Key] = nil
	self._tier[Key] = TierHot
	self._accessCount[Key] = 0
end

function SecureStorage._TrackAccess(self, Key: string): ()
	local Now = os.clock()
	local Last = self._lastAccess[Key]
	if Last and (Now - Last) >= self._config.BufferMigrationResetTime then
		self._accessCount[Key] = 1
	else
		self._accessCount[Key] = (self._accessCount[Key] or 0) + 1
	end
	self._lastAccess[Key] = Now
end

function SecureStorage._CheckCompaction(self): ()
	local Cap = buffer.len(self._coldBuffer)
	if Cap > 0 and self._freeBytes / Cap >= self._config.CompactionThreshold then
		SecureStorage._Compact(self)
	end
end

function SecureStorage:Set(Key: string, Value: any): ()
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	if Value == nil then
		SecureStorage.Delete(self, Key)
		return
	end
	local ExistingTier = self._tier[Key]
	if ExistingTier == TierCold then
		self._freeBytes += self._coldSize[Key]
		self._coldIndex[Key] = nil
		self._coldSize[Key] = nil
	end
	
	if self._config.StoreToBufferOnSet and IsPrimitive(Value) then
		local Size = EncodedSize(Value)
		SecureStorage._EnsureCapacity(self, Size)
		Encode(self._coldBuffer, self._writeHead, Value)
		self._coldIndex[Key] = self._writeHead
		self._coldSize[Key] = Size
		self._writeHead += Size
		self._tier[Key] = TierCold
		self._hotStore[Key] = nil
	else
		self._hotStore[Key] = Value
		self._tier[Key] = IsPrimitive(Value) and TierHot or TierPinned
	end
	
	SecureStorage._TrackAccess(self, Key)
	SecureStorage._CheckCompaction(self)
end

function SecureStorage:Get(Key: string): (any)
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	local Tier = self._tier[Key]
	if Tier == nil then return nil end
	SecureStorage._TrackAccess(self, Key)
	if Tier ~= TierCold then
		return self._hotStore[Key]
	end
	local Value = Decode(self._coldBuffer, self._coldIndex[Key])
	if self._config.DataMigration and (self._accessCount[Key] or 0) >= self._config.BufferMigrationRequest then
		SecureStorage._MoveToTable(self, Key)
	end
	return Value
end

function SecureStorage:Delete(Key: string): ()
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	local Tier = self._tier[Key]
	if Tier == nil then return end
	if Tier == TierCold then
		self._freeBytes += self._coldSize[Key]
		self._coldIndex[Key] = nil
		self._coldSize[Key] = nil
	else
		self._hotStore[Key] = nil
	end
	self._tier[Key] = nil
	self._accessCount[Key] = nil
	self._lastAccess[Key] = nil
end

function SecureStorage:Has(Key: string): (boolean)
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	return self._tier[Key] ~= nil
end

function SecureStorage:Keys(): ({string})
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	local Result = {}
	for Key in pairs(self._tier) do
		table.insert(Result, Key)
	end
	return Result
end

function SecureStorage:Expand(Budget: number?): ()
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	local Amount = Budget or self._config.BufferDefaultBudget
	local New = buffer.create(buffer.len(self._coldBuffer) + Amount)
	buffer.copy(New, 0, self._coldBuffer, 0, self._writeHead)
	self._coldBuffer = New
end

function SecureStorage:Flush(): ()
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	if not self._config.DataMigration then return end
	local Now = os.clock()
	local MigrationTime = self._config.TableMigrationTime
	for Key, Tier in pairs(self._tier) do
		if Tier == TierHot then
			local Last = self._lastAccess[Key]
			if Last and (Now - Last) >= MigrationTime then
				SecureStorage._MoveToBuffer(self, Key)
			end
		end
	end
	SecureStorage._CheckCompaction(self)
end

function SecureStorage:Compact(): ()
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	SecureStorage._Compact(self)
end

function SecureStorage:Stats(): ({
	HotCount: number,
	ColdCount: number,
	PinnedCount: number,
	BufferUsed: number,
	BufferCapacity: number,
	FragmentationBytes: number,
	})
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	local HotCount, ColdCount, PinnedCount = 0, 0, 0
	for _, Tier in pairs(self._tier) do
		if Tier == TierHot then HotCount += 1
		elseif Tier == TierCold then ColdCount += 1
		else PinnedCount += 1
		end
	end
	local Cache = self._statsCache
	Cache.HotCount = HotCount
	Cache.ColdCount = ColdCount
	Cache.PinnedCount = PinnedCount
	Cache.BufferUsed = self._writeHead - self._freeBytes
	Cache.BufferCapacity = buffer.len(self._coldBuffer)
	Cache.FragmentationBytes = self._freeBytes
	return Cache
end

function SecureStorage:Export(IncludeConfig: boolean?, Kill: boolean?): ({[string]: any}, StorageConfiguration?)
	if not self.Alive then error("[SecureStorage] Storage is dead.") end
	local Data = {}
	for Key, Tier in pairs(self._tier) do
		if Tier == TierCold then
			Data[Key] = Decode(self._coldBuffer, self._coldIndex[Key])
		else
			Data[Key] = self._hotStore[Key]
		end
	end
	local Config = if IncludeConfig then self._rawConfig else nil
	if Kill then
		SecureStorage.Destroy(self)
	end
	return Data, Config
end

function SecureStorage:Destroy(): ()
	if not self.Alive then return end
	self.Alive = false
	table.clear(self._hotStore)
	table.clear(self._coldIndex)
	table.clear(self._coldSize)
	table.clear(self._tier)
	table.clear(self._accessCount)
	table.clear(self._lastAccess)
	setmetatable(self, nil)
	table.freeze(self)
end

export type SecureStorage = {
	Alive: boolean,
	Set: (self: SecureStorage, Key: string, Value: any) -> (),
	Get: (self: SecureStorage, Key: string) -> (any),
	Delete: (self: SecureStorage, Key: string) -> (),
	Has: (self: SecureStorage, Key: string) -> (boolean),
	Keys: (self: SecureStorage) -> ({string}),
	Expand: (self: SecureStorage, Budget: number?) -> (),
	Flush: (self: SecureStorage) -> (),
	Compact: (self: SecureStorage) -> (),
	Stats: (self: SecureStorage) -> ({
		HotCount: number,
		ColdCount: number,
		PinnedCount: number,
		BufferUsed: number,
		BufferCapacity: number,
		FragmentationBytes: number,
	}),
	Export: (self: SecureStorage, IncludeConfig: boolean?, Kill: boolean?) -> ({[string]: any}, StorageConfiguration?),
	Destroy: (self: SecureStorage) -> (),
}

local function ScheduleAutoFlush(Storage): ()
	task.delay(Storage._config.FlushInterval, function()
		if not Storage.Alive then return end
		SecureStorage.Flush(Storage)
		ScheduleAutoFlush(Storage)
	end)
end

local SecureStorageImpl = {}
SecureStorageImpl.__index = SecureStorage

function SecureStorageImpl.new(StorageConfiguration: StorageConfiguration): (SecureStorage)
	local Cfg = StorageConfiguration or {}

	local RawConfig = {}
	for Key, Value in pairs(Cfg) do
		RawConfig[Key] = Value
	end
	
	local Config = table.freeze({
		DataMigration = if Cfg.DataMigration ~= nil then Cfg.DataMigration else true,
		BufferMigrationRequest = Cfg.BufferMigrationRequest or 3,
		BufferMigrationResetTime = Cfg.BufferMigrationResetTime or 5,
		BufferDefaultBudget = Cfg.BufferDefaultBudget or 500,
		BufferBudgetAllocation = Cfg.BufferBudgetAllocation or "Manual",
		StoreToBufferOnSet = if Cfg.StoreToBufferOnSet ~= nil then Cfg.StoreToBufferOnSet else false,
		TableMigrationTime = Cfg.TableMigrationTime or 30,
		MaxBudget = Cfg.MaxBudget or 0,
		CompactionThreshold = Cfg.CompactionThreshold or 0.4,
		FlushInterval = Cfg.FlushInterval or 0,
		SmartShrink = if Cfg.SmartShrink ~= nil then Cfg.SmartShrink else true,
		ShrinkHeadroom = Cfg.ShrinkHeadroom or 0.1,
	})
	
	local self = setmetatable({}, SecureStorageImpl)
	self.Alive = true
	self._config = Config
	self._rawConfig = table.freeze(RawConfig)
	self._hotStore = {}
	self._coldBuffer = buffer.create(Config.BufferDefaultBudget)
	self._coldIndex = {}
	self._coldSize = {}
	self._tier = {}
	self._accessCount = {}
	self._lastAccess = {}
	self._writeHead = 0
	self._freeBytes = 0
	self._statsCache = {
		HotCount = 0,
		ColdCount = 0,
		PinnedCount = 0,
		BufferUsed = 0,
		BufferCapacity = 0,
		FragmentationBytes = 0,
	}
	
	if Config.DataMigration and Config.FlushInterval > 0 then
		ScheduleAutoFlush(self)
	end
	return self
end

return SecureStorageImpl :: {
	new: (StorageConfiguration: StorageConfiguration) -> (SecureStorage),
}
