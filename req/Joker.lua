Joker = Joker or class()

Joker.MAX_LEVEL = 100
Joker.OT_NAMES = {}
Joker.WEAPON_MAPPING = {}
Joker.WEAPON_ID_MAPPING = {
	beretta92 = "b92fs",
	c45 = "glock_17",
	raging_bull = "new_raging_bull",
	m4 = "new_m4",
	m4_yellow = "new_m4",
	ak47 = "ak74",
	mossberg = "huntsman",
	mp5 = "new_mp5",
	mp5_tactical = "new_mp5",
	mac11 = "mac10",
	m14_sniper_npc = "g3",
	ump = "schakal",
	scar_murky = "scar",
	rpk_lmg = "rpk",
	svd_snp = "siltstone",
	ak47_ass = "ak74",
	x_c45 = "x_g17",
	sg417 = "contraband",
	svdsil_snp = "siltstone",
	mini = "m134",
	heavy_zeal_sniper = "g3"
}
function Joker.find_player_weapon_id(npc_id)
	if Joker.WEAPON_ID_MAPPING[npc_id] then
		return Joker.WEAPON_ID_MAPPING[npc_id]
	end

	local w_tweak = tweak_data.weapon

	if w_tweak[npc_id] then
		Joker.WEAPON_ID_MAPPING[npc_id] = npc_id
		return npc_id
	end

	local stripped_id = npc_id:gsub("_lmg$", ""):gsub("_smg$", ""):gsub("_ass$", ""):gsub("_npc$", "")
	if w_tweak[stripped_id] then
		Joker.WEAPON_ID_MAPPING[npc_id] = stripped_id
		return stripped_id
	end

	return stripped_id
end

function Joker:init(unit, data)
	self.tweak = data and data.tweak or unit:base()._tweak_table
	self.uname = data and data.uname or Network:is_server() and unit:name():key() or HopLib:name_provider().CLIENT_TO_SERVER_MAPPING[unit:name():key()]
	self.name = data and data.name or HopLib:unit_info_manager():get_info(unit):nickname()
	self.hp_ratio = data and math.min(math.max(data.hp_ratio, 0), 1) or 1
	self.order = data and data.order or 0
	self.base_stats = tweak_data.character[self.tweak] and tweak_data.character[self.tweak].jokermon_stats or {
		hp = 8,
		exp_rate = 2
	}
	local mul = (tweak_data:difficulty_to_index(Global.game_settings.difficulty) - 2) / (#tweak_data.difficulties - 2)
	local lvl = 1 + math.round(40 * mul + math.random() * 10 + math.random() * 20 * mul)
	self.exp = data and data.exp or self:level_to_exp(lvl)
	self.catch_level = data and (data.catch_level or data.stats and data.stats.catch_level) or lvl
	self.catch_date = data and (data.catch_date or data.stats and data.stats.catch_date) or os.time()
	self.catch_heist = data and (data.catch_heist or data.stats and data.stats.catch_heist) or managers.job and managers.job:current_level_id()
	self.catch_difficulty = data and (data.catch_difficulty or data.stats and data.stats.catch_difficulty) or Global.game_settings.difficulty
	self.kills = data and (data.kills or data.stats and data.stats.kills) or 0
	self.special_kills = data and (data.special_kills or data.stats and data.stats.special_kills) or 0
	self.damage = data and (data.damage or data.stats and data.stats.damage) or 0
	self.shiny = not data and unit:base():has_shiny_effect() or data and data.shiny
	self.ot = data and data.ot or Steam:userid()

	self:fetch_owner_name()
	self:calculate_stats()
	self:set_unit(unit)
end

function Joker:randomseed()
	math.randomseed(self.catch_date)
	math.random()
	math.random()
	math.random()
end

function Joker:fetch_owner_name()
	if Joker.OT_NAMES[self.ot] then
		return
	end

	if self.ot == Steam:userid() then
		Joker.OT_NAMES[self.ot] = Steam:username()
		return
	end

	Joker.OT_NAMES[self.ot] = "pending"
	Steam:http_request("https://steamcommunity.com/profiles/" .. self.ot .. "/?xml=1", function (success, data)
		Joker.OT_NAMES[self.ot] = success and data:match("<steamID><!%[CDATA%[(.+)%]%]></steamID>") or "unknown"
	end)
end

function Joker:get_weapon_id()
	do return end -- Disabled for now (read_file is bugged)

	if Joker.WEAPON_MAPPING[self.uname] ~= nil then
		return Joker.WEAPON_MAPPING[self.uname]
	end

	Joker.WEAPON_MAPPING[self.uname] = false

	local data = blt.asset_db.read_file("#" .. self.uname, "unit", { optional = false })
	data = data and ScriptSerializer:from_custom_xml(data)
	if not data or not data.extensions then
		return Joker.WEAPON_MAPPING[self.uname]
	end

	for _, ext in pairs(data.extensions) do
		if ext.name == "base" then
			for _, var in pairs(ext) do
				if type(var) == "table" and var.name == "_default_weapon_id" then
					local w = Joker.find_player_weapon_id(var.value)
					Joker.WEAPON_MAPPING[self.uname] = tweak_data.weapon[w] and w or false
					break
				end
			end
			break
		end
	end

	return Joker.WEAPON_MAPPING[self.uname]
end

function Joker:calculate_stats()
	self.level = self:exp_to_level(self.exp)
	self.exp_level = self:level_to_exp()
	self.exp_level_next = self:level_to_exp(self.level + 1)
	self.exp = math.min(self.exp, self.exp_level_next)

	if Jokermon.settings.vanilla then
		self.hp = tweak_data.character[self.tweak] and tweak_data.character[self.tweak].HEALTH_INIT or 8
	else
		self:randomseed()
		local raised_levels = self.level - self.catch_level
		self.hp = math.random() * self.base_stats.hp + self.base_stats.hp * (self.catch_level * 0.1 + raised_levels * 0.15)
	end
end

function Joker:exp_to_level(exp)
	return math.min(math.floor(math.pow((exp or self.exp) / 10, 1 / self.base_stats.exp_rate)), Joker.MAX_LEVEL)
end

function Joker:level_to_exp(level)
	return 10 * math.ceil(math.pow(math.min(level or self.level, Joker.MAX_LEVEL), self.base_stats.exp_rate))
end

function Joker:get_exp_ratio()
	if self.level >= Joker.MAX_LEVEL then
		return 1
	end
	return (self.exp - self.exp_level) / (self.exp_level_next - self.exp_level)
end

function Joker:get_heal_price()
	local base_price = 10000
	return math.ceil((self.hp_ratio <= 0 and base_price * 2 or (1 - self.hp_ratio) * base_price) * self.level / 10)
end

function Joker:set_unit(unit)
	if unit then
		local u_base = unit:base()
		local tweak = u_base._tweak_table
		local uname = Network:is_server() and unit:name():key() or HopLib:name_provider().CLIENT_TO_SERVER_MAPPING[unit:name():key()]
		if tweak ~= self.tweak or uname ~= self.uname then
			log(string.format("[Jokermon] Warning: Unit mismatch! Expected %s (%s), got %s (%s)!", tostring(HopLib:name_provider().UNIT_MAPPIGS[self.uname]), self.tweak, tostring(HopLib:name_provider().UNIT_MAPPIGS[uname]), tweak))
		end
	end
	self.unit = unit
end

function Joker:give_exp(exp)
	exp = math.ceil(exp * (self.ot ~= Steam:userid() and 1.5 or 1))
	if self.level < Joker.MAX_LEVEL then
		local old_level = self.level
		self.exp = self.exp + exp
		self.level = self:exp_to_level()
		if self.level ~= old_level then
			self:calculate_stats()
			return true
		end
		if self.level >= Joker.MAX_LEVEL then
			self.exp = self:level_to_exp(self)
		end
	end
end

function Joker:original_owner_name()
	return Joker.OT_NAMES[self.ot] or self.ot
end

function Joker:get_save_data()
	return {
		tweak = self.tweak,
		uname = self.uname,
		name = self.name,
		hp_ratio = self.hp_ratio,
		exp = self.exp,
		catch_level = self.catch_level,
		catch_date = self.catch_date,
		catch_heist = self.catch_heist,
		catch_difficulty = self.catch_difficulty,
		kills = self.kills,
		special_kills = self.special_kills,
		damage = self.damage,
		shiny = self.shiny,
		ot = self.ot,
		order = self.order
	}
end
