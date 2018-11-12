if not Jokermon then
  _G.Jokermon = {}
  
  dofile(ModPath .. "req/JokerPanel.lua")

  Jokermon.mod_path = ModPath
  Jokermon.save_path = SavePath
  Jokermon.settings = {
    panel_x_pos = 0.03,
    panel_y_pos = 0.2,
    panel_spacing = 8,
    panel_layout = 1,
    panel_x_align = 1,
    panel_y_align = 1,
    show_messages = true
  }
  Jokermon.jokers = {}
  Jokermon.panels = {}
  Jokermon.units = {}
  Jokermon._num_panels = 0
  Jokermon._queued_keys = {}
  Jokermon._queued_converts = {}
  Jokermon._unit_id_mappings = {}

  function Jokermon:spawn(joker, index, player_unit)
    if not alive(player_unit) then
      return
    end
    local is_local_player = player_unit == managers.player:local_player()
    local xml = ScriptSerializer:from_custom_xml(string.format("<table type=\"table\" id=\"@ID%s@\">", joker.uname))
    local ids = xml and xml.id
    if ids and PackageManager:unit_data(ids) then
      if is_local_player then
        table.insert(self._queued_keys, index)
      end
      -- If we are client, request spawn from server
      if Network:is_client() then
        LuaNetworking:SendToPeer(1, "jokermon_request_spawn", json.encode({ uname = joker.uname, name = joker.name }))
        return true
      end
      local unit = World:spawn_unit(ids, player_unit:position() + Vector3(math.random(-300, 300), math.random(-300, 300), 0), player_unit:rotation())
      unit:movement():set_team({ id = "law1", foes = {}, friends = {} })
      -- Queue for conversion (to avoid issues when converting instantly after spawn)
      self:queue_unit_convert(unit, is_local_player, player_unit, joker)
      return true
    elseif is_local_player and self.settings.show_messages then
      managers.chat:_receive_message(1, "JOKERMON", joker.name .. " can't accompany you on this heist!", tweak_data.system_chat_color)
    end
  end

  function Jokermon:_convert_queued_units()
    for _, data in pairs(self._queued_converts) do
      if alive(data.unit) then
        if not alive(data.player_unit) then
          World:delete_unit(data.unit)
        else
          if Keepers then
            Keepers.joker_names[data.player_unit:network():peer():id()] = data.joker.name
          end
          managers.groupai:state():convert_hostage_to_criminal(data.unit, (not data.is_local_player) and data.player_unit)
        end
      end
    end
    self._queued_converts = {}
  end

  function Jokermon:queue_unit_convert(unit, is_local_player, player_unit, joker)
    table.insert(self._queued_converts, { 
      is_local_player = is_local_player,
      player_unit = player_unit,
      unit = unit,
      joker = joker
    })
    -- Convert all queued units after a short delay (Resets the delayed call if it already exists)
    DelayedCalls:Add("ConvertJokermon", 0.5, function ()
      Jokermon:_convert_queued_units()
    end)
  end

  function Jokermon:add_joker(joker)
    table.insert(self.jokers, joker)
    if self.settings.show_messages then
      managers.chat:_receive_message(1, "JOKERMON", "Captured \"" .. joker.name .. "\" Lv." .. joker.level .. "!", tweak_data.system_chat_color)
    end
    self:save(true)
  end

  function Jokermon:setup_joker(key, unit, joker)
    if not alive(unit) then
      return
    end
    -- correct nickname
    self:set_joker_name(unit, joker.name, true)
    -- Save to units
    self.units[key] = unit
    unit:base()._jokermon_key = key
    -- Create panel
    self:add_panel(key, joker)
  end

  function Jokermon:set_joker_name(unit, name, sync)
    if not alive(unit) then
      return
    end
    HopLib:unit_info_manager():get_info(unit)._nickname = name
    local peer_id = unit:base().kpr_minion_owner_peer_id
    if Keepers and peer_id then
      Keepers:DestroyLabel(unit)
      unit:base().kpr_minion_owner_peer_id = peer_id
      Keepers.joker_names[peer_id] = name
      Keepers:SetJokerLabel(unit)
    end
    if sync then
      LuaNetworking:SendToPeers("jokermon_name", json.encode({ uid = unit:id(), name = name }))
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
    local needed_current, needed_next = self:get_needed_exp(joker, joker.level), self:get_needed_exp(joker, joker.level + 1)
    return (joker.exp - needed_current) / (needed_next - needed_current)
  end

  function Jokermon:give_exp(key, exp)
    local joker = self.jokers[key]
    if joker and joker.level < 100 then
      local panel = self.panels[key]
      local old_level = joker.level
      joker.exp = joker.exp + exp
      while joker.level < 100 and self:get_exp_ratio(joker) >= 1 do
        -- update stats
        joker.level = joker.level + 1
        joker.hp = joker.hp + self:get_base_stats(joker).base_hp * ((joker.level - 1) / 99) * 0.25
      end
      if joker.level ~= old_level then
        self:set_unit_stats(self.units[key], joker, true)
        if panel then
          panel:update_hp(joker.hp, joker.hp_ratio)
          panel:update_level(joker.level)
          panel:update_exp(0, true)
        end
        if self.settings.show_messages then
          managers.chat:_receive_message(1, "JOKERMON", joker.name .. " reached Lv." .. joker.level .. "!", tweak_data.system_chat_color)
        end
      end
      if panel then
        panel:update_exp(self:get_exp_ratio(joker))
      end
    end
  end

  function Jokermon:set_unit_stats(unit, data, sync)
    if not alive(unit) then
      return
    end
    local u_damage = unit:character_damage()
    u_damage._HEALTH_INIT = data.hp
    u_damage._health_ratio = data.hp_ratio
    u_damage._health = u_damage._health_ratio * u_damage._HEALTH_INIT
    u_damage._HEALTH_INIT_PRECENT = u_damage._HEALTH_INIT / u_damage._HEALTH_GRANULARITY
    if sync then
      LuaNetworking:SendToPeers("jokermon_stats", json.encode({ uid = unit:id(), hp = data.hp, hp_ratio = data.hp_ratio }))
    end
  end

  function Jokermon:layout_panels()
    local i = 0
    local x, y
    local x_pos, y_pos, spacing = self.settings.panel_x_pos, self.settings.panel_y_pos, self.settings.panel_spacing
    local x_align, y_align = self.settings.panel_x_align, self.settings.panel_y_align
    local horizontal_layout = self.settings.panel_layout ~= 1 and 1 or 0
    local vertical_layout = self.settings.panel_layout == 1 and 1 or 0
    for _, panel in pairs(self.panels) do
      if x_align == 2 and horizontal_layout == 1 then
        x = (panel._parent_panel:w() - panel._panel:w() * self._num_panels - spacing * (self._num_panels - 1)) * x_pos + (panel._panel:w() + spacing) * i
      else
        x = (panel._parent_panel:w() - panel._panel:w()) * x_pos + (panel._panel:w() + spacing) * i * horizontal_layout * (x_align == 3 and -1 or 1)
      end
      if y_align == 2 and vertical_layout == 1 then
        y = (panel._parent_panel:h() - panel._panel:h() * self._num_panels - spacing * (self._num_panels - 1)) * y_pos + (panel._panel:h() + spacing) * i
      else
        y = (panel._parent_panel:h() - panel._panel:h()) * y_pos + (panel._panel:h() + spacing) * i * vertical_layout * (y_align == 3 and -1 or 1)
      end
      panel:set_position(x, y)
      i = i + 1
    end
  end

  function Jokermon:add_panel(key, joker)
    local hud = managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
    if not hud then
      return
    end
    local panel = JokerPanel:new(hud.panel)
    panel:update_name(joker.name)
    panel:update_hp(joker.hp, joker.hp_ratio, true)
    panel:update_level(joker.level)
    panel:update_exp(self:get_exp_ratio(joker), true)
    if not self.panels[key] then
      self._num_panels = self._num_panels + 1
    end
    self.panels[key] = panel
    self:layout_panels()
  end

  function Jokermon:remove_panel(key)
    if self.panels[key] then
      self.panels[key]:remove()
      self.panels[key] = nil
      self._num_panels = self._num_panels - 1
      self:layout_panels()
    end
  end

  function Jokermon:save(full_save)
    local file = io.open(self.save_path .. "jokermon_settings.txt", "w+")
    if file then
      file:write(json.encode(self.settings))
      file:close()
    end
    if full_save then
      file = io.open(self.save_path .. "jokermon.txt", "w+")
      if file then
        file:write(json.encode(self.jokers))
        file:close()
      end
    end
  end
  
  function Jokermon:load()
    local file = io.open(self.save_path .. "jokermon_settings.txt", "r")
    if file then
      local data = json.decode(file:read("*all"))
      file:close()
      for k, v in pairs(data) do
        self.settings[k] = v
      end
    end
    file = io.open(self.save_path .. "jokermon.txt", "r")
    if file then
      self.jokers = json.decode(file:read("*all"))
      file:close()
    end
  end

  Jokermon:load()
  
  Hooks:Add("HopLibOnMinionAdded", "HopLibOnMinionAddedJokermon", function(unit, player_unit)
    local uid = unit:id()
    Jokermon._unit_id_mappings[uid] = unit
    
    if player_unit ~= managers.player:local_player() then
      return
    end

    local key = Jokermon._queued_keys[1]
    if key then
      -- Use existing Jokermon entry
      local joker = Jokermon.jokers[key]
      Jokermon:set_unit_stats(unit, joker, true)
      Jokermon:setup_joker(key, unit, joker)
      table.remove(Jokermon._queued_keys, 1)
    else
      -- Create new Jokermon entry
      key = #Jokermon.jokers + 1
      local mul = (tweak_data:difficulty_to_index(Global.game_settings.difficulty) - 1) / (#tweak_data.difficulties - 1)
      local joker = {
        tweak = unit:base()._tweak_table,
        uname = unit:name():key(),
        name = HopLib:unit_info_manager():get_info(unit):nickname(),
        hp = unit:character_damage()._HEALTH_INIT,
        hp_ratio = 1,
        level = math.max(1, math.floor(40 * mul + math.random(0, 10 + 10 * mul))),
        exp = 0
      }
      joker.exp = Jokermon:get_needed_exp(joker, joker.level)

      if Network:is_server() then
        Jokermon:add_joker(joker)
        Jokermon:setup_joker(key, unit, joker)
      else
        local u_base = unit:base()
        u_base._jokermon_queued_key = key
        u_base._jokermon_queued_joker = joker
        LuaNetworking:SendToPeer(1, "jokermon_request_uname", json.encode(uid))
      end
    end

  end)

  Hooks:Add("HopLibOnMinionRemoved", "HopLibOnMinionRemovedJokermon", function(unit)
    local key = unit:base()._jokermon_key
    local joker = key and Jokermon.jokers[key]
    if joker then
      joker.hp_ratio = unit:character_damage()._health_ratio
      if joker.hp_ratio <= 0 and Jokermon.settings.show_messages then
        managers.chat:_receive_message(1, "JOKERMON", joker.name .. " fainted!", tweak_data.system_chat_color)
      end
      Jokermon:save(true)
      Jokermon:remove_panel(key)
      Jokermon.units[key] = nil
    end
    Jokermon._unit_id_mappings[unit:id()] = nil
  end)

  Hooks:Add("HopLibOnUnitDamaged", "HopLibOnUnitDamagedJokermon", function(unit, damage_info)
    local u_damage = unit:character_damage()
    local key = unit:base()._jokermon_key
    local joker = key and Jokermon.jokers[key]
    if joker then
      joker.hp_ratio = u_damage._health_ratio
      local panel = Jokermon.panels[key]
      if panel then
        panel:update_hp(joker.hp, joker.hp_ratio)
      end
    end
    local attacker_key = alive(damage_info.attacker_unit) and damage_info.attacker_unit:base()._jokermon_key
    if attacker_key then
      u_damage._jokermon_assists = u_damage._jokermon_assists or {}
      u_damage._jokermon_assists[attacker_key] = true
    end
    if u_damage:dead() and u_damage._jokermon_assists then
      for key, _ in pairs(u_damage._jokermon_assists) do
        Jokermon:give_exp(key, u_damage._HEALTH_INIT * (key == attacker_key and 1 or 0.5))
      end
    end
  end)

  Hooks:Add("NetworkReceivedData", "NetworkReceivedDataJokermon", function(sender, id, data)
    if id == "jokermon_request_spawn" then
      Jokermon:spawn(json.decode(data), nil, LuaNetworking:GetPeers()[sender]:unit())
    elseif id == "jokermon_request_uname" then
      local uid = json.decode(data)
      local unit = Jokermon._unit_id_mappings[uid]
      if alive(unit) then
        LuaNetworking:SendToPeer(sender, "jokermon_uname", json.encode({ uid = uid, uname = unit:name():key() }))
      end
    elseif id == "jokermon_uname" then
      data = json.decode(data)
      local unit = Jokermon._unit_id_mappings[data.uid]
      if alive(unit) then
        local u_base = unit:base()
        u_base._jokermon_queued_joker.uname = data.uname
        Jokermon:add_joker(u_base._jokermon_queued_joker)
        Jokermon:setup_joker(u_base._jokermon_queued_key, unit, u_base._jokermon_queued_joker)
      end
      Jokermon._queued_joker_data[data.uid] = nil
    elseif id == "jokermon_stats" then
      data = json.decode(data)
      Jokermon:set_unit_stats(Jokermon._unit_id_mappings[data.uid], data)
    elseif id == "jokermon_name" then
      data = json.decode(data)
      Jokermon:set_joker_name(Jokermon._unit_id_mappings[data.uid], data.name)
    end
  end)

  Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInitJokermon", function(loc)
    local language = "english"
    local system_language = HopLib:get_game_language()
    local blt_language = BLT.Localization:get_language().language

    local loc_path = Jokermon.mod_path .. "loc/"
    if io.file_is_readable(loc_path .. system_language .. ".txt") then
      language = system_language
    end
    if io.file_is_readable(loc_path .. blt_language .. ".txt") then
      language = blt_language
    end

    loc:load_localization_file(loc_path .. language .. ".txt")
    loc:load_localization_file(loc_path .. "english.txt", false)
  end)

  Hooks:Add("MenuManagerBuildCustomMenus", "MenuManagerBuildCustomMenusPlayerJokermon", function(menu_manager, nodes)

    local menu_id_main = "JokermonMenu"
    MenuHelper:NewMenu(menu_id_main)

    MenuCallbackHandler.Jokermon_toggle = function(self, item)
      Jokermon.settings[item:name()] = (item:value() == "on")
      Jokermon:layout_panels()
      Jokermon:save()
    end

    MenuCallbackHandler.Jokermon_value = function(self, item)
      Jokermon.settings[item:name()] = item:value()
      Jokermon:layout_panels()
      Jokermon:save()
    end

    MenuHelper:AddMultipleChoice({
      id = "panel_layout",
      title = "Jokermon_menu_panel_layout",
      callback = "Jokermon_value",
      value = Jokermon.settings.panel_layout,
      items = { "Jokermon_menu_panel_layout_vertical", "Jokermon_menu_panel_layout_horizontal" },
      menu_id = menu_id_main,
      priority = 99
    })

    MenuHelper:AddMultipleChoice({
      id = "panel_x_align",
      title = "Jokermon_menu_panel_x_align",
      callback = "Jokermon_value",
      value = Jokermon.settings.panel_x_align,
      items = { "Jokermon_menu_panel_align_left", "Jokermon_menu_panel_align_center", "Jokermon_menu_panel_align_right" },
      menu_id = menu_id_main,
      priority = 98
    })
    MenuHelper:AddMultipleChoice({
      id = "panel_y_align",
      title = "Jokermon_menu_panel_y_align",
      callback = "Jokermon_value",
      value = Jokermon.settings.panel_y_align,
      items = { "Jokermon_menu_panel_align_top", "Jokermon_menu_panel_align_center", "Jokermon_menu_panel_align_bottom" },
      menu_id = menu_id_main,
      priority = 97
    })

    MenuHelper:AddSlider({
      id = "panel_x_pos",
      title = "Jokermon_menu_panel_x_pos",
      callback = "Jokermon_value",
      value = Jokermon.settings.panel_x_pos,
      min = 0,
      max = 1,
      step = 0.01,
      show_value = true,
      menu_id = menu_id_main,
      priority = 96
    })
    MenuHelper:AddSlider({
      id = "panel_y_pos",
      title = "Jokermon_menu_panel_y_pos",
      callback = "Jokermon_value",
      value = Jokermon.settings.panel_y_pos,
      min = 0,
      max = 1,
      step = 0.01,
      show_value = true,
      menu_id = menu_id_main,
      priority = 95
    })
    MenuHelper:AddSlider({
      id = "panel_spacing",
      title = "Jokermon_menu_panel_spacing",
      callback = "Jokermon_value",
      value = Jokermon.settings.panel_spacing,
      min = 0,
      max = 256,
      step = 1,
      show_value = true,
      menu_id = menu_id_main,
      priority = 94
    })
    
    MenuHelper:AddDivider({
      id = "divider",
      size = 24,
      menu_id = menu_id_main,
      priority = 90
    })
    
    MenuHelper:AddToggle({
      id = "show_messages",
      title = "Jokermon_menu_show_messages",
      callback = "Jokermon_toggle",
      value = Jokermon.settings.show_messages,
      menu_id = menu_id_main,
      priority = 89
    })

    nodes[menu_id_main] = MenuHelper:BuildMenu(menu_id_main, { area_bg = "half" })
    MenuHelper:AddMenuItem(nodes["blt_options"], menu_id_main, "Jokermon_menu_main_name", "Jokermon_menu_main_desc")
  end)
  
end

if RequiredScript then

  local fname = Jokermon.mod_path .. "lua/" .. RequiredScript:gsub(".+/(.+)", "%1.lua")
  if io.file_is_readable(fname) then
    dofile(fname)
  end

end