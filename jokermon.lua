if not Jokermon then
  _G.Jokermon = {}
  
  dofile(ModPath .. "req/JokerPanel.lua")

  Jokermon.mod_path = ModPath
  Jokermon.save_path = SavePath
  Jokermon.settings = {
    jokers = {}
  }
  Jokermon.panels = {}
  Jokermon.units = {}
  Jokermon.queued_keys = {}
  
  getmetatable(Idstring()).construct = function(self, id)
    local xml = ScriptSerializer:from_custom_xml(string.format("<table type=\"table\" id=\"@ID%s@\">", id))
    return xml and xml.id
  end

  function Jokermon:spawn(joker, index, player_unit)
    if joker.hp_ratio > 0 then
      local ids = Idstring:construct(joker.uname)
      if ids and PackageManager:unit_data(ids) then
        if index then
          table.insert(self.queued_keys, index)
        end
        if Network:is_client() then
          LuaNetworking:SendToPeer(1, "request_joker_spawn", json.encode(joker))
          return true
        end
        player_unit = player_unit or managers.player:local_player()
        local unit = World:spawn_unit(ids, player_unit:position() + Vector3(math.random(-300, 300), math.random(-300, 300), 0), player_unit:rotation())
        unit:movement():set_team({ id = "law1", foes = {}, friends = {} })
        if Keepers then
          Keepers.joker_names[player_unit:network():peer():id()] = joker.name
        end
        managers.groupai:state():convert_hostage_to_criminal(unit, player_unit ~= managers.player:local_player() and player_unit)
        return true
      elseif index then
        managers.chat:_receive_message(1, "JOKERMON", joker.name .. " can't accompany you on this heist!", tweak_data.system_chat_color)
      end
    end
  end

  function Jokermon:get_base_stats(joker)
    return tweak_data.character[joker.tweak].jokermon_stats
  end

  function Jokermon:get_needed_exp(joker, level)
    local exp_rate = self:get_base_stats(joker).exp_rate
    return 10 * math.ceil(math.pow(math.min(level, 100), exp_rate))
  end

  function Jokermon:get_exp_ratio(joker)
    if joker.level >= 100 then
      return 1
    end
    local needed_current, needed_next = Jokermon:get_needed_exp(joker, joker.level), Jokermon:get_needed_exp(joker, joker.level + 1)
    return (joker.exp - needed_current) / (needed_next - needed_current)
  end

  function Jokermon:layout_panels()
    local y = 200
    for _, panel in pairs(Jokermon.panels) do
      panel:set_position(16, y)
      y = y + panel._panel:h() + 8
    end
  end

  function Jokermon:add_panel(key, joker)
    local panel = JokerPanel:new(managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2).panel)
    panel:update_name(joker.name)
    panel:update_hp(joker.hp, joker.hp_ratio, true)
    panel:update_level(joker.level)
    panel:update_exp(Jokermon:get_exp_ratio(joker), true)
    Jokermon.panels[key] = panel
    Jokermon:layout_panels()
  end

  function Jokermon:remove_panel(key)
    if Jokermon.panels[key] then
      Jokermon.panels[key]:remove()
      Jokermon.panels[key] = nil
      Jokermon:layout_panels()
    end
  end

  function Jokermon:set_unit_stats(unit, joker)
    if not alive(unit) then
      return
    end
    local u_damage = unit:character_damage()
    u_damage._HEALTH_INIT = joker.hp
    u_damage._health_ratio = joker.hp_ratio
    u_damage._health = u_damage._health_ratio * u_damage._HEALTH_INIT
    u_damage._HEALTH_INIT_PRECENT = u_damage._HEALTH_INIT / u_damage._HEALTH_GRANULARITY
  end

  function Jokermon:give_exp(key, exp)
    local joker = Jokermon.settings.jokers[key]
    if joker and joker.level < 100 then
      local panel = Jokermon.panels[key]
      joker.exp = joker.exp + exp
      local old_level = joker.level
      while joker.level < 100 and self:get_exp_ratio(joker) >= 1 do
        joker.level = joker.level + 1

        -- update stats
        joker.hp = joker.hp + self:get_base_stats(joker).base_hp * ((joker.level - 1) / 99)
        self:set_unit_stats(self.units[key], joker)
        
        if panel then
          panel:update_hp(joker.hp, joker.hp_ratio)
          panel:update_level(joker.level)
          panel:update_exp(0, true)
        end
      end
      if joker.level ~= old_level then
        managers.chat:_receive_message(1, "JOKERMON", joker.name .. " reached Lv." .. joker.level .. "!", tweak_data.system_chat_color)
      end
      if panel then
        panel:update_exp(Jokermon:get_exp_ratio(joker))
      end
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

      local key = Jokermon.queued_keys[1]
      
      if key then
        -- Use existing Jokermon entry
        table.remove(Jokermon.queued_keys, 1)

        local info = HopLib:unit_info_manager():get_info(unit)
        joker = Jokermon.settings.jokers[key]
        info._nickname = joker.name

        Jokermon:set_unit_stats(unit, joker)
      else
        -- Create new Jokermon entry
        key = #Jokermon.settings.jokers + 1
        joker = {
          tweak = unit:base()._tweak_table,
          uname = unit:name():key(),
          name = HopLib:unit_info_manager():get_info(unit):nickname(),
          hp = unit:character_damage()._HEALTH_INIT,
          hp_ratio = 1,
          level = math.floor(1 + math.random(20, 70) * (tweak_data:difficulty_to_index(Global.game_settings.difficulty) / #tweak_data.difficulties)),
          exp = 0
        }
        joker.exp = Jokermon:get_needed_exp(joker, joker.level)
        table.insert(Jokermon.settings.jokers, joker)
        Jokermon:save()
        managers.chat:_receive_message(1, "JOKERMON", "Captured \"" .. joker.name .. "\" Lv." .. joker.level .. "!", tweak_data.system_chat_color)
      end

      if joker then
        -- Save to units
        Jokermon.units[key] = unit
        unit:base()._jokermon_key = key
        -- Create panel
        Jokermon:add_panel(key, joker)
      end
    end

  end)

  Hooks:Add("HopLibOnUnitDamaged", "HopLibOnUnitDamagedJokermon", function(unit, damage_info)
    local key = unit:base()._jokermon_key
    local joker = key and Jokermon.settings.jokers[key]
    if joker then
      joker.hp_ratio = unit:character_damage()._health_ratio
      Jokermon.panels[key]:update_hp(joker.hp, joker.hp_ratio)
    end
  end)

  Hooks:Add("HopLibOnUnitDied", "HopLibOnUnitDiedJokermon", function(unit, damage_info)
    if alive(damage_info.attacker_unit) and damage_info.attacker_unit:base()._jokermon_key then
      Jokermon:give_exp(damage_info.attacker_unit:base()._jokermon_key, unit:character_damage()._HEALTH_INIT)
    end
  end)
  
  Hooks:Add("NetworkReceivedData", "NetworkReceivedDataJokermon", function(sender, id, data)
    if id == "request_joker_spawn" then
      local joker = json.decode(data)
      local player_unit = LuaNetworking:GetPeers()[sender]:unit()
      if alive(unit) then
        Jokermon:spawn(joker, nil, player_unit)
      end
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