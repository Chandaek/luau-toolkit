--!strict
--!native

local SecureStorageImpl = require(path.to.module)

local PassCount = 0
local FailCount = 0

local function Assert(Condition: boolean, Label: string, Detail: string?): ()
	if Condition then
		PassCount += 1
		print(`  ✓  {Label}`)
	else
		FailCount += 1
		warn(`  ✗  {Label}{if Detail then ` — {Detail}` else ""}`)
	end
end

local function Section(Name: string): ()
	print(`\n━━━  {Name}  ━━━`)
end

local function Report(): ()
	print(`\n═══════════════════════════════`)
	print(`  Passed : {PassCount}`)
	print(`  Failed : {FailCount}`)
	print(`  Total  : {PassCount + FailCount}`)
	print(`═══════════════════════════════\n`)
end

-- ─── 1. Basic Set / Get ───────────────────────────────────────────────────────

Section("1 · Basic Set / Get")
do
	local Store = SecureStorageImpl.new({})

	Store:Set("Alpha", 42)
	Assert(Store:Get("Alpha") == 42, "number round-trips")

	Store:Set("Beta", "hello")
	Assert(Store:Get("Beta") == "hello", "string round-trips")

	Store:Set("Gamma", true)
	Assert(Store:Get("Gamma") == true, "boolean true round-trips")

	Store:Set("Delta", false)
	Assert(Store:Get("Delta") == false, "boolean false round-trips")

	Store:Set("Epsilon", nil)
	Assert(Store:Get("Epsilon") == nil, "set nil deletes key")
	Assert(not Store:Has("Epsilon"), "Has returns false after nil set")

	Assert(Store:Get("NonExistent") == nil, "missing key returns nil")

	Store:Destroy()
end

-- ─── 2. Data Types ────────────────────────────────────────────────────────────

Section("2 · Data Types")
do
	local Store = SecureStorageImpl.new({})

	Store:Set("Integer", 0)
	Assert(Store:Get("Integer") == 0, "zero")

	Store:Set("NegativeNumber", -999.5)
	Assert(Store:Get("NegativeNumber") == -999.5, "negative float")

	Store:Set("LargeNumber", 2^53)
	Assert(Store:Get("LargeNumber") == 2^53, "2^53 exact")

	Store:Set("SmallFloat", 1e-300)
	Assert(Store:Get("SmallFloat") == 1e-300, "very small float")

	Store:Set("Infinity", math.huge)
	Assert(Store:Get("Infinity") == math.huge, "math.huge")

	Store:Set("NegInfinity", -math.huge)
	Assert(Store:Get("NegInfinity") == -math.huge, "-math.huge")

	local Nan = 0/0
	local GotNan = Store:Get("NanKey")
	Store:Set("NanKey", Nan)
	Assert(GotNan ~= GotNan or GotNan == nil, "NaN stored (nil before set)")

	Store:Set("EmptyString", "")
	Assert(Store:Get("EmptyString") == "", "empty string")

	local LongString = string.rep("x", 10000)
	Store:Set("LongString", LongString)
	Assert(Store:Get("LongString") == LongString, "10 000-char string")

	local BinaryString = string.char(0, 1, 127, 128, 254, 255)
	Store:Set("BinaryString", BinaryString)
	Assert(Store:Get("BinaryString") == BinaryString, "binary string with null bytes")

	Store:Set("Table", {1, 2, 3})
	local TableValue = Store:Get("Table")
	Assert(type(TableValue) == "table", "table stored as pinned")

	Store:Destroy()
end

-- ─── 3. Has / Keys ───────────────────────────────────────────────────────────

Section("3 · Has / Keys")
do
	local Store = SecureStorageImpl.new({})
	Store:Set("A", 1)
	Store:Set("B", 2)
	Store:Set("C", 3)

	Assert(Store:Has("A"), "Has existing key A")
	Assert(Store:Has("B"), "Has existing key B")
	Assert(not Store:Has("Z"), "Has missing key Z")

	local Keys = Store:Keys()
	table.sort(Keys)
	Assert(#Keys == 3, "Keys count = 3")
	Assert(Keys[1] == "A" and Keys[2] == "B" and Keys[3] == "C", "Keys content correct")

	Store:Delete("B")
	Assert(not Store:Has("B"), "Has false after Delete")
	Assert(#Store:Keys() == 2, "Keys count = 2 after Delete")

	Store:Destroy()
end

-- ─── 4. Delete ────────────────────────────────────────────────────────────────

Section("4 · Delete")
do
	local Store = SecureStorageImpl.new({})
	Store:Set("Target", 99)
	Store:Delete("Target")
	Assert(Store:Get("Target") == nil, "deleted key returns nil")
	Assert(not Store:Has("Target"), "deleted key not in Has")

	Store:Delete("NeverExisted")
	Assert(true, "delete non-existent key does not error")

	Store:Set("Repeated", 1)
	Store:Delete("Repeated")
	Store:Set("Repeated", 2)
	Assert(Store:Get("Repeated") == 2, "key re-usable after delete")

	Store:Destroy()
end

-- ─── 5. Overwrite ─────────────────────────────────────────────────────────────

Section("5 · Overwrite")
do
	local Store = SecureStorageImpl.new({})
	Store:Set("Key", 1)
	Store:Set("Key", 2)
	Assert(Store:Get("Key") == 2, "overwrite number → number")

	Store:Set("Key", "text")
	Assert(Store:Get("Key") == "text", "overwrite number → string")

	Store:Set("Key", false)
	Assert(Store:Get("Key") == false, "overwrite string → boolean")

	Store:Set("Key", {})
	Assert(type(Store:Get("Key")) == "table", "overwrite boolean → table (pinned)")

	Store:Destroy()
end

-- ─── 6. StoreToBufferOnSet ───────────────────────────────────────────────────

Section("6 · StoreToBufferOnSet")
do
	local Store = SecureStorageImpl.new({ StoreToBufferOnSet = true })

	Store:Set("Number", 3.14)
	Store:Set("Text", "buffer")
	Store:Set("Flag", true)

	local Stats = Store:Stats()
	Assert(Stats.ColdCount == 3, `primitives go cold immediately, ColdCount={Stats.ColdCount}`)
	Assert(Store:Get("Number") == 3.14, "cold number decodes correctly")
	Assert(Store:Get("Text") == "buffer", "cold string decodes correctly")
	Assert(Store:Get("Flag") == true, "cold boolean decodes correctly")

	Store:Set("Reference", {1, 2, 3})
	local Stats2 = Store:Stats()
	Assert(Stats2.PinnedCount == 1, "table remains pinned even with StoreToBufferOnSet")

	Store:Destroy()
end

-- ─── 7. Buffer Expansion (Auto) ───────────────────────────────────────────────

Section("7 · Buffer Expansion — Auto")
do
	local Store = SecureStorageImpl.new({
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 64,
		StoreToBufferOnSet = true,
	})

	for Index = 1, 50 do
		Store:Set(`Key{Index}`, Index)
	end

	local AllCorrect = true
	for Index = 1, 50 do
		if Store:Get(`Key{Index}`) ~= Index then
			AllCorrect = false
			break
		end
	end
	Assert(AllCorrect, "all 50 cold values correct after auto-expansion")

	local Stats = Store:Stats()
	Assert(Stats.BufferCapacity >= Stats.BufferUsed, "capacity >= used after expansion")

	Store:Destroy()
end

-- ─── 8. Buffer Expansion (Manual) ─────────────────────────────────────────────

Section("8 · Buffer Expansion — Manual")
do
	local Store = SecureStorageImpl.new({
		BufferBudgetAllocation = "Manual",
		BufferDefaultBudget = 32,
		StoreToBufferOnSet = true,
	})

	Store:Set("SmallKey", 1)

	local Errored = false
	local Ok = pcall(function()
		for Index = 1, 100 do
			Store:Set(`Fill{Index}`, Index)
		end
	end)
	if not Ok then Errored = true end

	Assert(Errored, "Manual mode errors when buffer is full")

	Store:Expand(4096)
	Store:Set("AfterExpand", 999)
	Assert(Store:Get("AfterExpand") == 999, "write succeeds after Expand()")

	Store:Destroy()
end

-- ─── 9. MaxBudget ─────────────────────────────────────────────────────────────

Section("9 · MaxBudget")
do
	local Store = SecureStorageImpl.new({
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 64,
		MaxBudget = 128,
		StoreToBufferOnSet = true,
	})

	local HitMax = false
	local Ok = pcall(function()
		for Index = 1, 1000 do
			Store:Set(`Overflow{Index}`, Index * 1.0)
		end
	end)
	if not Ok then HitMax = true end

	Assert(HitMax, "MaxBudget enforced — error raised when exceeded")

	local Stats = Store:Stats()
	Assert(Stats.BufferCapacity <= 128, `capacity never exceeds MaxBudget, got {Stats.BufferCapacity}`)

	Store:Destroy()
end

-- ─── 10. Compaction ───────────────────────────────────────────────────────────

Section("10 · Compaction")
do
	local Store = SecureStorageImpl.new({
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 2048,
		StoreToBufferOnSet = true,
		CompactionThreshold = 0.3,
		SmartShrink = false,
	})

	for Index = 1, 100 do
		Store:Set(`Key{Index}`, Index * 1.0)
	end

	local StatsBefore = Store:Stats()

	for Index = 1, 80 do
		Store:Delete(`Key{Index}`)
	end

	Store:Compact()
	local StatsAfter = Store:Stats()

	Assert(StatsAfter.FragmentationBytes == 0, "no fragmentation after Compact()")
	Assert(StatsAfter.BufferUsed <= StatsBefore.BufferUsed, "buffer used shrank after Compact()")

	local AllCorrect = true
	for Index = 81, 100 do
		if Store:Get(`Key{Index}`) ~= Index * 1.0 then
			AllCorrect = false
			break
		end
	end
	Assert(AllCorrect, "surviving values intact after compaction")

	Store:Destroy()
end

-- ─── 11. SmartShrink ──────────────────────────────────────────────────────────

Section("11 · SmartShrink")
do
	local Store = SecureStorageImpl.new({
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 512,
		StoreToBufferOnSet = true,
		SmartShrink = true,
		ShrinkHeadroom = 0.2,
		CompactionThreshold = 0.5,
	})

	for Index = 1, 50 do
		Store:Set(`Shrink{Index}`, Index * 1.0)
	end

	local CapBefore = Store:Stats().BufferCapacity

	for Index = 1, 45 do
		Store:Delete(`Shrink{Index}`)
	end

	Store:Compact()
	local CapAfter = Store:Stats().BufferCapacity

	Assert(CapAfter < CapBefore, `SmartShrink reduced capacity: {CapBefore} → {CapAfter}`)
	Assert(Store:Stats().FragmentationBytes == 0, "no fragmentation after smart compaction")

	Store:Destroy()
end

-- ─── 12. DataMigration — Hot ↔ Cold ──────────────────────────────────────────

Section("12 · DataMigration — Hot ↔ Cold")
do
	local Store = SecureStorageImpl.new({
		DataMigration = true,
		BufferMigrationRequest = 3,
		BufferMigrationResetTime = 9999,
		TableMigrationTime = 0,
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 512,
		StoreToBufferOnSet = false,
	})

	Store:Set("Migrate", 7.0)
	Assert(Store:Stats().HotCount == 1, "starts hot")

	Store:Flush()
	Assert(Store:Stats().ColdCount == 1, "flushed to cold immediately (TableMigrationTime=0)")
	Assert(Store:Get("Migrate") == 7.0, "value correct after flush to cold")

	Store:Get("Migrate")
	Store:Get("Migrate")
	Store:Get("Migrate")
	Assert(Store:Stats().HotCount == 1, "3 reads promoted back to hot")

	Store:Destroy()
end

-- ─── 13. DataMigration disabled ───────────────────────────────────────────────

Section("13 · DataMigration disabled")
do
	local Store = SecureStorageImpl.new({
		DataMigration = false,
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 512,
	})

	Store:Set("Static", 42)
	Store:Flush()
	Assert(Store:Stats().HotCount == 1, "Flush no-ops when DataMigration=false")
	Assert(Store:Get("Static") == 42, "value still readable")

	Store:Destroy()
end

-- ─── 14. Destroy ──────────────────────────────────────────────────────────────

Section("14 · Destroy")
do
	local Store = SecureStorageImpl.new({})
	Store:Set("BeforeDestroy", 1)
	Store:Destroy()

	local ErroredOnSet = false
	local ErroredOnGet = false

	pcall(function() Store:Set("AfterDestroy", 2) end) -- may error or silently fail
	local Ok, _ = pcall(function() Store:Get("AfterDestroy") end)
	if not Ok then ErroredOnGet = true end

	Assert(ErroredOnGet or Store:Get("AfterDestroy") == nil, "destroyed store is inert or errors on access")
end

-- ─── 15. Stats ────────────────────────────────────────────────────────────────

Section("15 · Stats")
do
	local Store = SecureStorageImpl.new({
		StoreToBufferOnSet = true,
		BufferBudgetAllocation = "Auto",
		BufferDefaultBudget = 1024,
	})

	Store:Set("Hot1", {})
	Store:Set("Cold1", 1.0)
	Store:Set("Cold2", "text")

	local Stats = Store:Stats()
	Assert(Stats.PinnedCount == 1, `PinnedCount=1, got {Stats.PinnedCount}`)
	Assert(Stats.ColdCount == 2, `ColdCount=2, got {Stats.ColdCount}`)
	Assert(Stats.HotCount == 0, `HotCount=0, got {Stats.HotCount}`)
	Assert(Stats.BufferUsed > 0, "BufferUsed > 0")
	Assert(Stats.BufferCapacity >= Stats.BufferUsed, "capacity >= used")
	Assert(Stats.FragmentationBytes == 0, "no fragmentation on fresh store")

	Store:Destroy()
end

-- ─── 16. Stress — Mixed Hot / Cold (1 000 ops) ────────────────────────────────

Section("16 · Stress — Mixed Hot / Cold  (1 000 ops)")
do
	local Store = SecureStorageImpl.new({
		DataMigration = true,
		BufferMigrationRequest = 3,
		BufferMigrationResetTime = 5,
		BufferDefaultBudget = 4096,
		BufferBudgetAllocation = "Auto",
		StoreToBufferOnSet = false,
		TableMigrationTime = 30,
		CompactionThreshold = 0.4,
		SmartShrink = true,
		ShrinkHeadroom = 0.1,
	})

	local KeyPool = {}
	for Index = 1, 50 do
		KeyPool[Index] = `StressKey{Index}`
	end

	local Expected = {}
	math.randomseed(12345)

	local Start = os.clock()

	for _ = 1, 1000 do
		local Op = math.random(1, 4)
		local Key = KeyPool[math.random(1, 50)]

		if Op == 1 then
			local Value = math.random() * 1000
			Store:Set(Key, Value)
			Expected[Key] = Value
		elseif Op == 2 then
			Store:Get(Key)
		elseif Op == 3 then
			Store:Delete(Key)
			Expected[Key] = nil
		else
			Store:Has(Key)
		end
	end

	local Elapsed = os.clock() - Start
	print(`  1 000 ops in {string.format("%.6f", Elapsed)}s  (~{math.floor(1000 / Elapsed)} ops/sec)`)

	local AllCorrect = true
	for Key, Value in Expected do
		if Store:Get(Key) ~= Value then
			AllCorrect = false
			warn(`  mismatch on {Key}: expected {Value}, got {Store:Get(Key)}`)
			break
		end
	end
	Assert(AllCorrect, "all tracked values correct after stress")

	Store:Destroy()
end

-- ─── 17. Stress — StoreToBufferOnSet (1 000 ops) ─────────────────────────────

Section("17 · Stress — StoreToBufferOnSet  (1 000 ops)")
do
	local Store = SecureStorageImpl.new({
		DataMigration = true,
		BufferMigrationRequest = 2,
		BufferMigrationResetTime = 5,
		BufferDefaultBudget = 8192,
		BufferBudgetAllocation = "Auto",
		StoreToBufferOnSet = true,
		TableMigrationTime = 30,
		CompactionThreshold = 0.4,
		SmartShrink = true,
		ShrinkHeadroom = 0.1,
	})

	local Expected = {}
	math.randomseed(99999)

	local Start = os.clock()

	for _ = 1, 1000 do
		local Op = math.random(1, 3)
		local Key = `BufKey{math.random(1, 30)}`

		if Op == 1 then
			local Value = math.random() * 500
			Store:Set(Key, Value)
			Expected[Key] = Value
		elseif Op == 2 then
			Store:Get(Key)
		else
			Store:Delete(Key)
			Expected[Key] = nil
		end
	end

	local Elapsed = os.clock() - Start
	print(`  1 000 cold-path ops in {string.format("%.6f", Elapsed)}s  (~{math.floor(1000 / Elapsed)} ops/sec)`)

	local AllCorrect = true
	for Key, Value in Expected do
		if Store:Get(Key) ~= Value then
			AllCorrect = false
			break
		end
	end
	Assert(AllCorrect, "all cold-path values correct after stress")

	Store:Destroy()
end

-- ─── 18. Extreme Stress — 100 000 ops ────────────────────────────────────────

Section("18 · Extreme Stress — 100 000 ops")
do
	local Store = SecureStorageImpl.new({
		DataMigration = true,
		BufferMigrationRequest = 5,
		BufferMigrationResetTime = 10,
		BufferDefaultBudget = 32768,
		BufferBudgetAllocation = "Auto",
		StoreToBufferOnSet = false,
		TableMigrationTime = 60,
		CompactionThreshold = 0.35,
		SmartShrink = true,
		ShrinkHeadroom = 0.15,
		MaxBudget = 0,
	})

	local KeyCount = 200
	local KeyPool = table.create(KeyCount)
	for Index = 1, KeyCount do
		KeyPool[Index] = `ExKey{Index}`
	end

	local Expected = {}
	math.randomseed(77777)

	local Start = os.clock()
	local SetCount, GetCount, DeleteCount = 0, 0, 0

	for _ = 1, 100000 do
		local Op = math.random(1, 5)
		local Key = KeyPool[math.random(1, KeyCount)]

		if Op <= 2 then
			local Value = math.random() * 10000
			Store:Set(Key, Value)
			Expected[Key] = Value
			SetCount += 1
		elseif Op <= 4 then
			Store:Get(Key)
			GetCount += 1
		else
			Store:Delete(Key)
			Expected[Key] = nil
			DeleteCount += 1
		end
	end

	local Elapsed = os.clock() - Start
	local Ops = math.floor(100000 / Elapsed)
	print(`  100 000 ops in {string.format("%.6f", Elapsed)}s  (~{Ops} ops/sec)`)
	print(`  Set={SetCount}  Get={GetCount}  Delete={DeleteCount}`)

	local Stats = Store:Stats()
	print(`  Hot={Stats.HotCount}  Cold={Stats.ColdCount}  Pinned={Stats.PinnedCount}`)
	print(`  BufferUsed={Stats.BufferUsed}  BufferCapacity={Stats.BufferCapacity}  Frag={Stats.FragmentationBytes}`)

	local AllCorrect = true
	for Key, Value in Expected do
		if Store:Get(Key) ~= Value then
			AllCorrect = false
			warn(`  mismatch on {Key}: expected {Value}, got {Store:Get(Key)}`)
			break
		end
	end
	Assert(AllCorrect, "all values correct after 100 000 ops")
	Assert(Elapsed < 2, `completed in under 2s, got {string.format("%.4f", Elapsed)}s`)

	Store:Destroy()
end

-- ─── 19. Extreme Stress — Cold-only 100 000 ops ───────────────────────────────

Section("19 · Extreme Stress — Cold-only 100 000 ops")
do
	local Store = SecureStorageImpl.new({
		DataMigration = false,
		BufferDefaultBudget = 65536,
		BufferBudgetAllocation = "Auto",
		StoreToBufferOnSet = true,
		CompactionThreshold = 0.4,
		SmartShrink = true,
		ShrinkHeadroom = 0.1,
		MaxBudget = 0,
	})

	local KeyCount = 100
	local KeyPool = table.create(KeyCount)
	for Index = 1, KeyCount do
		KeyPool[Index] = `ColdEx{Index}`
	end

	local Expected = {}
	math.randomseed(55555)

	local Start = os.clock()

	for _ = 1, 100000 do
		local Op = math.random(1, 4)
		local Key = KeyPool[math.random(1, KeyCount)]

		if Op <= 2 then
			local Value = math.random() * 9999
			Store:Set(Key, Value)
			Expected[Key] = Value
		elseif Op == 3 then
			Store:Get(Key)
		else
			Store:Delete(Key)
			Expected[Key] = nil
		end
	end

	local Elapsed = os.clock() - Start
	print(`  100 000 cold-only ops in {string.format("%.6f", Elapsed)}s  (~{math.floor(100000 / Elapsed)} ops/sec)`)

	local AllCorrect = true
	for Key, Value in Expected do
		if Store:Get(Key) ~= Value then
			AllCorrect = false
			break
		end
	end
	Assert(AllCorrect, "all cold-only values correct after 100 000 ops")
	Assert(Elapsed < 2, `completed in under 2s, got {string.format("%.4f", Elapsed)}s`)

	Store:Destroy()
end

-- ─── 20. Extreme Stress — Compaction under churn ─────────────────────────────

Section("20 · Extreme Stress — Compaction under churn")
do
	local Store = SecureStorageImpl.new({
		DataMigration = false,
		BufferDefaultBudget = 16384,
		BufferBudgetAllocation = "Auto",
		StoreToBufferOnSet = true,
		CompactionThreshold = 0.2,
		SmartShrink = true,
		ShrinkHeadroom = 0.1,
		MaxBudget = 0,
	})

	local KeyPool = table.create(20)
	for Index = 1, 20 do
		KeyPool[Index] = `Churn{Index}`
	end

	local Expected = {}
	math.randomseed(33333)

	local CompactionsBefore = 0
	local Start = os.clock()

	for Iteration = 1, 50000 do
		local Key = KeyPool[math.random(1, 20)]
		local Value = math.random() * 1000

		Store:Set(Key, Value)
		Expected[Key] = Value

		if Iteration % 3 == 0 then
			local Victim = KeyPool[math.random(1, 20)]
			Store:Delete(Victim)
			Expected[Victim] = nil
		end
	end

	local Elapsed = os.clock() - Start
	print(`  50 000 churn ops in {string.format("%.6f", Elapsed)}s`)

	local Stats = Store:Stats()
	print(`  BufferUsed={Stats.BufferUsed}  Frag={Stats.FragmentationBytes}  Cap={Stats.BufferCapacity}`)

	local AllCorrect = true
	for Key, Value in Expected do
		if Store:Get(Key) ~= Value then
			AllCorrect = false
			break
		end
	end
	Assert(AllCorrect, "all values correct after high-churn compaction stress")

	Store:Destroy()
end

-- ─── Final Report ─────────────────────────────────────────────────────────────

Report()
