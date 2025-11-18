local utils = require("sage.base.utils")

local Pack = {}
Pack.__index = Pack

function Pack.new(spec, stage)
	local self = setmetatable({}, Pack)
	local src = spec.src or spec[1]
	local name = spec.name or utils.extract_name(src)
	local priority = spec.priority or 100
	local config = spec.config
	local before = spec.before
	local after = spec.after
	local build = spec.build
	local depends = spec.depends
	local version = spec.version
	local on = spec.on
	local prefix = "https://github.com/"
	local disabled = spec.enabled ~= nil and spec.enabled == false
	local stage = self:determine_stage(spec)
	local beg_status = "idle"

	self.enabled = not disabled
	self.stage = stage
	self.status = beg_status
	self.priority = priority
	
    self.loaded = false
	self.installed = false
	self.failed = false
	
    self.path = ""
	self.active = ""
	self.rev = ""
	
    self.branches = {}
	self.tags = {}
	self.times = { install_duration = 0, config_duration = 0 }
	
    self.specs = {}
	self.specs["user"] = spec
	self.specs["normalize"] = {}

	self.specs.normalize.src = prefix .. src
	self.specs.normalize.name = name
	self.specs.normalize.version = version
	self.specs.normalize.data = {}
	self.specs.normalize.data.stage = stage
	self.specs.normalize.data.source = src
	self.specs.normalize.data.depends = depends
	self.specs.normalize.data.before = before
	self.specs.normalize.data.config = config
	self.specs.normalize.data.after = after
	self.specs.normalize.data.on = on
	self.specs.normalize.data.build = build

	return self
end

function Pack:set_stage(stage)
	self.stage = stage
	return self
end

function Pack:get_stage()
	return self.stage
end

function Pack:determine_stage(spec)
	if utils.is_not_enabled(spec) then
		return "disabled"
	end

	local on = spec.on
	if
		on ~= nil
		and (
			on.before ~= nil
			or on.after ~= nil
			or on.events ~= nil
			or on.event ~= nil
			or on.fts ~= nil
			or on.ft ~= nil
			or on.cmds ~= nil
			or on.cmd ~= nil
			or on.keys ~= nil
		)
	then
		return "lazy"
	end

	if on ~= nil and on.stage == "now" then
		return "now"
	end

	return "later"
end

function Pack:set_status(status)
	local curr_status = self.status
	if curr_status ~= status then
		self.status = status
		return true, self.status
	end
	return false, self.status
end

function Pack:get_status()
	return self.status
end

return Pack
