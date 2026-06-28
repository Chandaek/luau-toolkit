--- Type ---

export type Template = {}

--- Main ---

local Template = {}

local TemplateImpl = {}
TemplateImpl.__index = Template

function TemplateImpl.new(): (Template)
	local self = setmetatable({}, TemplateImpl)
	return self
end

return TemplateImpl :: {
	new: () -> (Template)
}