Joker = Joker or class()

function Joker:init(unit, data)
  self.tweak = data and data.tweak or unit:base()._tweak_table
  self.uname = data and data.uname or Network:is_server() and unit:name():key() or NameProvider.CLIENT_TO_SERVER_MAPPING[unit:name():key()]
  self.name = data and data.name or HopLib:unit_info_manager():get_info(unit):nickname()
  self.hp_ratio = data and data.hp_ratio or 1
  self.order = data and data.order or 0
  self.base_stats = tweak_data.character[self.tweak].jokermon_stats or {
    hp = 8,
    exp_rate = 2
  }
  local mul = (tweak_data:difficulty_to_index(Global.game_settings.difficulty) - 2) / (#tweak_data.difficulties - 2)
  local lvl = 1 + math.round(40 * mul + math.random() * 10 + math.random() * 20 * mul)
  self.exp = data and data.exp or self:level_to_exp(lvl)
  self.stats = {
    catch_level = data and data.stats and data.stats.catch_level or lvl,
    catch_date = data and data.stats and data.stats.catch_date or os.time(),
    catch_heist = data and data.stats and data.stats.catch_heist or managers.job:current_level_id(),
    catch_difficulty = data and data.stats and data.stats.catch_difficulty or Global.game_settings.difficulty,
    kills = data and data.stats and data.stats.kills or 0,
    special_kills = data and data.stats and data.stats.special_kills or 0,
    damage = data and data.stats and data.stats.damage or 0
  }
  self:calculate_stats()
  self:set_unit(unit)
end

function Joker:randomseed()
  math.randomseed(self.stats.catch_date)
  math.random()
  math.random()
  math.random()
end

function Joker:calculate_stats()
  self.level = self:exp_to_level(self.exp)
  self.exp_level = self:level_to_exp()
  self.exp_level_next = self:level_to_exp(self.level + 1)

  self:randomseed()
  local raised_levels = self.level - self.stats.catch_level
  self.hp = math.random() * self.base_stats.hp + self.base_stats.hp * (self.stats.catch_level * 0.1 + raised_levels * 0.15)
end

function Joker:exp_to_level(exp)
  return math.min(math.floor(math.pow((exp or self.exp) / 10, 1 / self.base_stats.exp_rate)), 100)
end

function Joker:level_to_exp(level)
  return 10 * math.ceil(math.pow(math.min(level or self.level, 100), self.base_stats.exp_rate))
end

function Joker:get_exp_ratio()
  if self.level >= 100 then
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
    local tweak = unit:base()._tweak_table
    local uname = Network:is_server() and unit:name():key() or NameProvider.CLIENT_TO_SERVER_MAPPING[unit:name():key()]
    if tweak ~= self.tweak or uname ~= self.uname then
      log(string.format("[Jokermon] Warning: Unit mismatch! Expected %s (%s), got %s (%s)!", tostring(NameProvider.UNIT_MAPPIGS[self.uname]), self.tweak, tostring(NameProvider.UNIT_MAPPIGS[uname]), tweak))
    end
  end
  self.unit = unit
end

function Joker:give_exp(exp)
  exp = math.ceil(exp)
  if self.level < 100 then
    local old_level = self.level
    self.exp = self.exp + exp
    self.level = self:exp_to_level()
    if self.level ~= old_level then
      self:calculate_stats()
      return true
    end
    if self.level >= 100 then
      self.exp = self:level_to_exp(self)
    end
  end
end

function Joker:get_save_data()
  return {
    tweak = self.tweak,
    uname = self.uname,
    name = self.name,
    hp_ratio = self.hp_ratio,
    exp = self.exp,
    stats = self.stats
  }
end