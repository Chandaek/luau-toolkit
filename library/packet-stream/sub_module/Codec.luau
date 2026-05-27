local TagNil = 0
local TagFalse = 1
local TagTrue = 2
local TagInteger = 3
local TagFloat = 4
local TagString = 5
local TagTable = 6

local function _ValueSize(Value: any): (number)
	local T = type(Value)
	if T == "nil" or T == "boolean" then return 1 end
	if T == "number" then
		if Value == math.floor(Value) and Value >= -2147483648 and Value <= 2147483647 then
			return 5
		end
		return 9
	end
	if T == "string" then return 5 + #Value end
	if T == "table" then
		local Size = 3
		for Key, Val in pairs(Value) do
			Size += _ValueSize(Key) + _ValueSize(Val)
		end
		return Size
	end
	return 1
end

local function _WriteValue(Buf: buffer, Offset: number, Value: any): (number)
	local T = type(Value)
	if T == "nil" then
		buffer.writeu8(Buf, Offset, TagNil)
		return Offset + 1
	elseif T == "boolean" then
		buffer.writeu8(Buf, Offset, Value and TagTrue or TagFalse)
		return Offset + 1
	elseif T == "number" then
		if Value == math.floor(Value) and Value >= -2147483648 and Value <= 2147483647 then
			buffer.writeu8(Buf, Offset, TagInteger)
			buffer.writei32(Buf, Offset + 1, Value)
			return Offset + 5
		end
		buffer.writeu8(Buf, Offset, TagFloat)
		buffer.writef64(Buf, Offset + 1, Value)
		return Offset + 9
	elseif T == "string" then
		local Len = #Value
		buffer.writeu8(Buf, Offset, TagString)
		buffer.writeu32(Buf, Offset + 1, Len)
		buffer.writestring(Buf, Offset + 5, Value)
		return Offset + 5 + Len
	elseif T == "table" then
		local Count = 0
		for _ in pairs(Value) do
			Count += 1
		end
		buffer.writeu8(Buf, Offset, TagTable)
		buffer.writeu16(Buf, Offset + 1, Count)
		local Position = Offset + 3
		for Key, Val in pairs(Value) do
			Position = _WriteValue(Buf, Position, Key)
			Position = _WriteValue(Buf, Position, Val)
		end
		return Position
	end
	buffer.writeu8(Buf, Offset, TagNil)
	return Offset + 1
end

local function _ReadValue(Buf: buffer, Offset: number): (any, number)
	local Tag = buffer.readu8(Buf, Offset)
	if Tag == TagNil then return nil, Offset + 1 end
	if Tag == TagFalse then return false, Offset + 1 end
	if Tag == TagTrue then return true, Offset + 1 end
	if Tag == TagInteger then return buffer.readi32(Buf, Offset + 1), Offset + 5 end
	if Tag == TagFloat then return buffer.readf64(Buf, Offset + 1), Offset + 9 end
	if Tag == TagString then
		local Len = buffer.readu32(Buf, Offset + 1)
		return buffer.readstring(Buf, Offset + 5, Len), Offset + 5 + Len
	end
	if Tag == TagTable then
		local Count = buffer.readu16(Buf, Offset + 1)
		local Result = {}
		local Position = Offset + 3
		for _ = 1, Count do
			local Key, Next1 = _ReadValue(Buf, Position)
			local Val, Next2 = _ReadValue(Buf, Next1)
			Result[Key] = Val
			Position = Next2
		end
		return Result, Position
	end
	error(`[PacketStream:Codec] Unknown tag: {Tag}`)
end

-- BatchEntry header layout (7 bytes):
-- [0]     u8  PacketType
-- [1..4]  u32 TopicId    <-- widened from u8 so now it support hash-based IDs
-- [5..6]  u16 PacketId
-- [7+]    var Data

type BatchEntry = {
	PacketType: number,
	TopicId: number,
	PacketId: number,
	Data: any,
}

local Codec = {}

function Codec.EncodeBatch(Entries: {BatchEntry}): (buffer)
	local TotalSize = 2
	for _, Entry in Entries do
		TotalSize += 7 + _ValueSize(Entry.Data)
	end
	local Buf = buffer.create(TotalSize)
	buffer.writeu16(Buf, 0, #Entries)
	local Offset = 2
	for _, Entry in Entries do
		buffer.writeu8(Buf, Offset, Entry.PacketType)
		buffer.writeu32(Buf, Offset + 1, Entry.TopicId)
		buffer.writeu16(Buf, Offset + 5, Entry.PacketId)
		Offset = _WriteValue(Buf, Offset + 7, Entry.Data)
	end
	return Buf
end

function Codec.DecodeBatch(Buf: buffer): ({BatchEntry})
	local Count = buffer.readu16(Buf, 0)
	local Entries = table.create(Count)
	local Offset = 2
	for Index = 1, Count do
		local PacketType = buffer.readu8(Buf, Offset)
		local TopicId = buffer.readu32(Buf, Offset + 1)
		local PacketId = buffer.readu16(Buf, Offset + 5)
		local Data, Next = _ReadValue(Buf, Offset + 7)
		Entries[Index] = {
			PacketType = PacketType,
			TopicId = TopicId,
			PacketId = PacketId,
			Data = Data,
		}
		Offset = Next
	end
	return Entries
end

function Codec.EncodeValue(Value: any): (buffer)
	local Size = _ValueSize(Value)
	local Buf = buffer.create(Size)
	_WriteValue(Buf, 0, Value)
	return Buf
end

function Codec.DecodeValue(Buf: buffer): (any)
	local Value = _ReadValue(Buf, 0)
	return Value
end

function Codec.BufferToString(Buf: buffer): (string)
	return buffer.readstring(Buf, 0, buffer.len(Buf))
end

function Codec.StringToBuffer(Str: string): (buffer)
	local Buf = buffer.create(#Str)
	buffer.writestring(Buf, 0, Str)
	return Buf
end

function Codec.SyncStateToFolder(Folder: Folder, NewState: {[string]: any}, OldState: {[string]: any}?): ()
	local Old = OldState or {}

	for Key, OldValue in pairs(Old) do
		if NewState[Key] == nil then
			if type(OldValue) == "table" then
				local Child = Folder:FindFirstChild(Key)
				if Child then
					Child:Destroy()
				end
			else
				Folder:SetAttribute(Key, nil)
			end
		end
	end

	for Key, Value in pairs(NewState) do
		if type(Value) == "table" then
			local OldValue = Old[Key]
			local Sub = Folder:FindFirstChild(Key)
			if not Sub or not Sub:IsA("Folder") then
				if Sub then
					Sub:Destroy()
				end
				local NewSub = Instance.new("Folder")
				NewSub.Name = Key
				NewSub.Parent = Folder
				Codec.SyncStateToFolder(NewSub :: Folder, Value, nil)
			else
				Codec.SyncStateToFolder(
					Sub :: Folder,
					Value,
					type(OldValue) == "table" and OldValue or nil
				)
			end
		else
			Folder:SetAttribute(Key, Value)
		end
	end
end

function Codec.ReadStateFromFolder(Folder: Folder): ({[string]: any})
	local State: {[string]: any} = {}

	for AttrName, AttrValue in pairs(Folder:GetAttributes()) do
		State[AttrName] = AttrValue
	end

	for _, Child in Folder:GetChildren() do
		if Child:IsA("Folder") then
			State[Child.Name] = Codec.ReadStateFromFolder(Child :: Folder)
		end
	end

	return State
end

return Codec
