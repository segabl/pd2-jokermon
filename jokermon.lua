if not Jokermon then
  _G.Jokermon = {}
  
  dofile(ModPath .. "req/JokerPanel.lua")

  Jokermon.mod_path = ModPath
  Jokermon.save_path = SavePath
  Jokermon.settings = {
    jokers = {}
  }
  Jokermon.panels = {}
  
  getmetatable(Idstring()).construct = function(self, id)
    local xml = ScriptSerializer:from_custom_xml(string.format("<table type=\"table\" id=\"@ID%s@\">", id))
    return xml and xml.id
  end

  function Jokermon:spawn(i)
    local v = self.settings.jokers[i]
    if not v then
      return
    end
    if v.hp_ratio > 0 then
      local ids = Idstring:construct(v.uname)
      if ids and PackageManager:unit_data(ids) then
        local player_unit = managers.player:local_player()
        local joker = World:spawn_unit(ids, player_unit:position() + Vector3(math.random(-300, 300), math.random(-300, 300), 0), player_unit:rotation())
        joker:movement():set_team({ id = "law1", foes = {}, friends = {} })
        joker:base()._jokermon_key = i
        if Keepers then
          Keepers.joker_names[player_unit:network():peer():id()] = v.name
        end
        managers.groupai:state():convert_hostage_to_criminal(joker, player_unit)
        return true
      else
        managers.chat:_receive_message(1, "JOKERMON", v.name .. " can't accompany you on this heist!", tweak_data.system_chat_color)
      end
    end
  end

  function Jokermon:get_needed_exp(hp, level)
    return hp + 20 * math.ceil(math.pow(math.min(level, 100), 2 + hp / 160))
  end

  function Jokermon:layout_panels()
    local y = 200
    for _, panel in pairs(Jokermon.panels) do
      panel:set_position(16, y)
      y = y + panel._panel:h()
    end
  end

  function Jokermon:give_exp(key, exp)
    local joker = Jokermon.settings.jokers[key]
    if joker and joker.level < 100 then
      local needed_current, needed_next = Jokermon:get_needed_exp(joker.hp, joker.level), Jokermon:get_needed_exp(joker.hp, joker.level + 1)
      joker.exp = joker.exp + exp
      while joker.level < 100 and joker.exp >= needed_next do
        -- TODO update stats
        joker.level = joker.level + 1
        managers.chat:_receive_message(1, "JOKERMON", joker.name .. " reached Lv." .. joker.level .. "!", tweak_data.system_chat_color)
        Jokermon.panels[key]:update_level(joker.level)
        Jokermon.panels[key]:update_exp(0, true)
        needed_current, needed_next = Jokermon:get_needed_exp(joker.hp, joker.level), Jokermon:get_needed_exp(joker.hp, joker.level + 1)
      end
      if joker.level == 100 then
        joker.exp = Jokermon:get_needed_exp(joker.hp, 100)
      end
      Jokermon.panels[key]:update_exp((joker.exp - needed_current) / (needed_next - needed_current))
    end
  end

  function Jokermon:save()
    local file = io.open(self.save_path .. "jokermon.txt", "w+")
    if file then
      file:write(json.encode(self.settings))
      file:close()
    end
  end
  
  function Jokermon:load()
    local file = io.open(self.save_path .. "jokermon.txt", "r")
    if file then
      local data = json.decode(file:read("*all"))
      file:close()
      for k, v in pairs(data) do
        self.settings[k] = v
      end
    end
  end
  
  Hooks:Add("HopLibOnEnemyConverted", "HopLibOnEnemyConvertedJokermon", function(unit, player_unit)
    if player_unit == managers.player:local_player() then
      local joker
      if unit:base()._jokermon_key then
        -- Use existing Jokermon entry
        local info = HopLib:unit_info_manager():get_info(unit)
        joker = Jokermon.settings.jokers[unit:base()._jokermon_key]
        info._nickname = joker.name

        local u_damage = unit:character_damage()
        u_damage._HEALTH_INIT = joker.hp
        u_damage._health_ratio = joker.hp_ratio
        u_damage._health = u_damage._health_ratio * u_damage._HEALTH_INIT
        u_damage._HEALTH_INIT_PRECENT = u_damage._HEALTH_INIT / u_damage._HEALTH_GRANULARITY

        local w_base = unit:inventory():equipped_unit():base()
        w_base._damage = joker.dmg
      else
        -- Create new Jokermon entry
        local uname = unit:name():key()
        if uname then
          unit:base()._jokermon_key = #Jokermon.settings.jokers + 1
          local name = HopLib:unit_info_manager():get_info(unit):nickname()
          local difficulty = Global.game_settings and Global.game_settings.difficulty or "normal"
          local level = 1--math.ceil(math.random(35, 50) * (tweak_data:difficulty_to_index(difficulty) / #tweak_data.difficulties))
          local hp = unit:character_damage()._HEALTH_INIT
          local w_base = unit:inventory():equipped_unit():base()
          joker = {
            uname = uname,
            name = name,
            hp = hp,
            hp_ratio = 1,
            dmg = w_base._damage,
            level = level,
            exp = Jokermon:get_needed_exp(hp, level)
          }
          table.insert(Jokermon.settings.jokers, joker)
          Jokermon:save()
          managers.chat:_receive_message(1, "JOKERMON", "Captured \"" .. name .. "\" Lv." .. level .. "!", tweak_data.system_chat_color)
        end
      end

      if joker then
        -- Create panel
        Jokermon.panels[unit:base()._jokermon_key] = JokerPanel:new(joker)
        Jokermon:layout_panels()
      end
    end

  end)

  Hooks:Add("HopLibOnUnitDamaged", "HopLibOnUnitDamagedJokermon", function(unit, damage_info)
    if unit:base()._jokermon_key then
      local key = unit:base()._jokermon_key
      Jokermon.panels[key]:update_hp(unit:character_damage()._health_ratio)
    end
  end)

  Hooks:Add("HopLibOnUnitDied", "HopLibOnUnitDiedJokermon", function(unit, damage_info)
    if unit:base()._jokermon_key then
      local key = unit:base()._jokermon_key
      local joker = Jokermon.settings.jokers[key]
      managers.chat:_receive_message(1, "JOKERMON", joker.name .. " fainted!", tweak_data.system_chat_color)
      Jokermon.panels[key]:remove()
      Jokermon.panels[key] = nil
      Jokermon:layout_panels()
    elseif alive(damage_info.attacker_unit) and damage_info.attacker_unit:base()._jokermon_key then
      Jokermon:give_exp(damage_info.attacker_unit:base()._jokermon_key, unit:character_damage()._HEALTH_INIT)
    end
  end)
    
  
  Hooks:Add("NetworkReceivedData", "NetworkReceivedDataJokermon", function(sender, id, data)
    if id == "request_joker_spawn" then
      data = json.decode(data)
    end
  end)
  
  Jokermon:load()
  
end

if RequiredScript then

  local fname = Jokermon.mod_path .. "lua/" .. RequiredScript:gsub(".+/(.+)", "%1.lua")
  if io.file_is_readable(fname) then
    dofile(fname)
  end

end