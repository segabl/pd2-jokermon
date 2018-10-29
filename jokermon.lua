if not Jokermon then
  _G.Jokermon = {}
  
  Jokermon.mod_path = ModPath
  Jokermon.save_path = SavePath
  Jokermon.settings = {
    jokers = {}
  }
  
  getmetatable(Idstring()).construct = function(self, id)
    local xml = ScriptSerializer:from_custom_xml(string.format("<table type=\"table\" id=\"@ID%s@\">", id))
    return xml and xml.id
  end

  function Jokermon:spawn(i)
    local v = self.settings.jokers[i]
    if not v then
      return
    end
    if v.hp > 0 then
      local ids = Idstring:construct(v.uname)
      if ids and DB:has(Idstring("unit"), ids) and PackageManager:unit_data(ids) then
        -- TODO: If we are client, send spawn request to host instead
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
        log("[Jokermon] Can't load unit with key " .. v.uname)
      end
    end
  end

  function Jokermon:get_needed_exp(base_hp, level)
    return 20 * math.ceil(math.pow(level, 2 + base_hp / 16))
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
      if unit:base()._jokermon_key then
        -- Use existing Jokermon entry
        -- TODO: set name, skills, weapon etc
        local info = HopLib:unit_info_manager():get_info(unit)
        local joker = Jokermon.settings.jokers[unit:base()._jokermon_key]
        info._nickname = joker.name

        local f = (joker.level - 1) / 99

        local u_damage = unit:character_damage()
        u_damage._HEALTH_INIT = joker.hp_max
        u_damage._health = joker.hp
        u_damage._health_ratio = u_damage._health / u_damage._HEALTH_INIT
        u_damage._HEALTH_INIT_PRECENT = u_damage._HEALTH_INIT / u_damage._HEALTH_GRANULARITY
        
        -- TODO: Sync hp
      else
        -- Create new Jokermon entry
        local uname = unit:name():key()
        if uname then
          unit:base()._jokermon_key = #Jokermon.settings.jokers + 1
          table.insert(Jokermon.settings.jokers, {
            uname = uname,
            name = HopLib:unit_info_manager():get_info(unit):nickname(),
            hp_max = unit:character_damage()._HEALTH_INIT,
            hp = unit:character_damage()._HEALTH_INIT,
            level = 1,
            exp = 0
          })
          Jokermon:save()
        end
      end
    end

    Hooks:Add("HopLibOnUnitDied", "HopLibOnUnitDiedJokermon", function(unit, damage_info)
      if alive(damage_info.attacker_unit) and damage_info.attacker_unit:base()._jokermon_key then
        local joker = Jokermon.settings.jokers[damage_info.attacker_unit:base()._jokermon_key]
        joker.exp = joker.exp + unit:character_damage()._HEALTH_INIT
        managers.chat:_receive_message(1, "JOKERMON", joker.name .. " " .. joker.exp .. "/" .. Jokermon:get_needed_exp(joker.hp_max, joker.level + 1) .. "EXP", tweak_data.system_chat_color)
        while joker.exp >= Jokermon:get_needed_exp(joker.hp_max, joker.level + 1) do
          joker.level = joker.level + 1
          managers.chat:_receive_message(1, "JOKERMON", joker.name .. " reached level " .. joker.level .. "!", tweak_data.system_chat_color)
        end
      end
    end)
    
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