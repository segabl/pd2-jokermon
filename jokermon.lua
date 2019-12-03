if not Jokermon then
  _G.Jokermon = {}
  
  dofile(ModPath .. "req/Joker.lua")
  dofile(ModPath .. "req/JokerPanel.lua")

  Jokermon.mod_path = ModPath
  Jokermon.save_path = SavePath
  Jokermon.settings = {
    nuzlocke = false,
    show_panels = true,
    panel_x_pos = 0.03,
    panel_y_pos = 0.2,
    panel_spacing = 8,
    panel_layout = 1,
    panel_x_align = 1,
    panel_y_align = 1,
    show_messages = true,
    spawn_mode = 1,
    sorting = 1,
    sorting_order = 1,
    keys = {
      menu = "m",
      spawn_joker = "j"
    }
  }
  Jokermon.jokers = {}
  Jokermon.panels = {}
  Jokermon._num_panels = 0
  Jokermon._queued_keys = {}
  Jokermon._queued_converts = {}
  Jokermon._unit_id_mappings = {}
  Jokermon._jokers_added = 0
  Jokermon._joker_index = 1
  Jokermon._joker_slot = World:make_slot_mask(16)
  Jokermon._jokermon_key_press_t = 0
  Jokermon._max_jokers = 30

  function Jokermon:display_message(message, macros, force)
    if force or Jokermon.settings.show_messages then
      managers.chat:_receive_message(1, "JOKERMON", managers.localization:text(message, macros), tweak_data.system_chat_color)
    end
  end

  local to_vec = Vector3()
  function Jokermon:send_or_retrieve_joker()
    local t = managers.player:player_timer():time()
    if self._jokermon_key_press_t + 1 > t then
      return
    end
    self._jokermon_key_press_t = t
    local viewport = managers.viewport
    if viewport:get_current_camera() then
      local from = viewport:get_current_camera_position()
      mvector3.set(to_vec, viewport:get_current_camera_rotation():y())
      mvector3.multiply(to_vec, 1000)
      mvector3.add(to_vec, from)
      local col = World:raycast("ray", from, to_vec, "slot_mask", Jokermon._joker_slot)
      if col and col.unit and col.unit:base()._jokermon_key then
        return self:retrieve_joker(col.unit)
      end
    end
    return self:send_out_joker()
  end

  function Jokermon:send_out_joker(num, skip_check)
    local player = managers.player:local_player()
    if not player or not skip_check and (not managers.player:has_category_upgrade("player", "convert_enemies") or managers.player:chk_minion_limit_reached()) then
      return
    end
    if #self.jokers == 0 then
      return
    end
    local index, joker
    for i = self._joker_index, self._joker_index + #self.jokers do
      index = ((i - 1) % #self.jokers) + 1
      joker = self.jokers[index]
      if not alive(joker.unit) and joker.hp_ratio > 0 and not table.contains(self._queued_keys, index) and self:spawn(joker, index, player) then
        self._joker_index = index + 1
        break
      end
    end
    return num and num > 1 and self:send_out_joker(num - 1)
  end

  function Jokermon:retrieve_joker(unit)
    if not alive(unit) then
      return
    end
    if Network:is_server() then
      unit:brain():set_active(false)
      unit:base():set_slot(unit, 0)
    else
      LuaNetworking:SendToPeer(1, "jokermon_retrieve", json.encode({ uid = unit:id() }))
    end
  end

  function Jokermon:spawn(joker, index, player_unit)
    if not alive(player_unit) then
      return
    end
    local is_local_player = player_unit == managers.player:local_player()
    local xml = ScriptSerializer:from_custom_xml(string.format("<table type=\"table\" id=\"@ID%s@\">", joker.uname))
    local ids = xml and xml.id
    if ids and PackageManager:has(Idstring("unit"), ids) then
      if is_local_player then
        table.insert(self._queued_keys, index)
      end
      -- If we are client, request spawn from server
      if Network:is_client() then
        LuaNetworking:SendToPeer(1, "jokermon_spawn", json.encode({ uname = joker.uname, name = joker.name }))
        return true
      end
      local unit = World:spawn_unit(ids, player_unit:position() + Vector3(math.random(-50, 50), math.random(-50, 50), 0), player_unit:rotation())
      unit:movement():set_team({ id = "law1", foes = {}, friends = {} })
      -- Queue for conversion (to avoid issues when converting instantly after spawn)
      self:queue_unit_convert(unit, is_local_player, player_unit, joker)
      return true
    elseif is_local_player then
      self:display_message("Jokermon_message_no_company", { NAME = joker.name })
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
    DelayedCalls:Add("ConvertJokermon", 0.25, function ()
      Jokermon:_convert_queued_units()
    end)
  end

  function Jokermon:setup_joker(key, unit)
    if not alive(unit) then
      return
    end
    local joker = self.jokers[key]
    -- correct nickname
    self:set_joker_name(unit, joker.name, true)
    unit:base()._jokermon_key = key
    -- Create panel
    self:add_panel(key)
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

  local _sort_comp = {
    default = function (a, b) return a < b end,
    [2] = function (a, b) return a > b end
  }
  local _sort_val = {
    default = function (v) return v.order end,
    [1] = function (v) return v.stats.catch_date end,
    [2] = function (v) return v.level end,
    [3] = function (v) return v.hp end,
    [4] = function (v) return v.hp * v.hp_ratio end,
    [5] = function (v) return v.hp_ratio end,
    [6] = function (v) return v.exp end,
    [7] = function (v) return v.exp_level_next - v.exp end,
    [8] = function (v) return v:level_to_exp(100) end
  }
  function Jokermon:sort_jokers()
    local c = _sort_comp[self.settings.sorting_order] or _sort_comp.default
    local v = _sort_val[self.settings.sorting] or _sort_val.default
    local va, vb
    table.sort(self.jokers, function (a, b)
      va, vb = v(a), v(b)
      if va == vb then
        return c(a.order, b.order)
      end
      return c(va, vb)
    end)
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

  function Jokermon:add_panel(key)
    local hud = self.settings.show_panels and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
    if not hud then
      return
    end
    local joker = self.jokers[key]
    local panel = JokerPanel:new(hud.panel)
    panel:update_name(joker.name)
    panel:update_hp(joker.hp, joker.hp_ratio, true)
    panel:update_level(joker.level)
    panel:update_exp(joker:get_exp_ratio(), true)
    self.panels[key] = panel
    self._num_panels = self._num_panels + 1
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
        local jokers = {}
        for _, v in pairs(self.jokers) do
          if not self.settings.nuzlocke or v.hp_ratio > 0 then
            table.insert(jokers, v:get_save_data())
          end
        end
        file:write(json.encode(jokers))
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
      for k, v in pairs(self.jokers) do
        self.jokers[k] = Joker:new(nil, v)
      end
    end
    self:sort_jokers()
  end

  function Jokermon:check_create_menu()

    if self.menu then
      return
    end
  
    self.menu_title_size = 22
    self.menu_items_size = 18
    self.menu_padding = 16
    self.menu_background_color = Color.black:with_alpha(0.75)
    self.menu_accent_color = BeardLib.Options:GetValue("MenuColor"):with_alpha(0.75)--Color("0bce99"):with_alpha(0.75)
    self.menu_highlight_color = self.menu_accent_color:with_alpha(0.075)
    self.menu_grid_item_color = Color.black:with_alpha(0.5)
  
    self.menu = MenuUI:new({
      name = "JokermonMenu",
      layer = 1000,
      background_blur = true,
      animate_toggle = true,
      text_offset = self.menu_padding / 4,
      show_help_time = 0.5,
      border_size = 1,
      accent_color = self.menu_accent_color,
      highlight_color = self.menu_highlight_color,
      localized = true,
      use_default_close_key = true,
      disable_player_controls = true
    })
    
    local menu_w = self.menu._panel:w()
    local menu_h = self.menu._panel:h()
  
    self._menu_w_left = menu_w / 3 - self.menu_padding
    self._menu_w_right = menu_w - self._menu_w_left - self.menu_padding * 2
  
    local menu = self.menu:Menu({
      background_color = self.menu_background_color
    })
  
    local title = menu:DivGroup({
      text = "Jokermon_menu_main_name",
      size = 26,
      background_color = Color.transparent,
      position = { self.menu_padding, self.menu_padding }
    })
  
    local base_settings = menu:DivGroup({
      text = "Jokermon_menu_base_settings",
      size = self.menu_title_size,
      inherit_values = {
        size = self.menu_items_size
      },
      border_bottom = true,
      border_position_below_title = true,
      w = self._menu_w_left,
      position = { self.menu_padding, title:Bottom() }
    })
    base_settings:ComboBox({
      name = "spawn_mode",
      text = "Jokermon_menu_spawn_mode",
      help = "Jokermon_menu_spawn_mode_desc",
      items = { "Jokermon_menu_spawn_mode_manual", "Jokermon_menu_spawn_mode_automatic" },
      value = self.settings.spawn_mode,
      free_typing = false,
      on_callback = function (item)
        self:change_menu_setting(item)
        if self.settings.spawn_mode > 1 and Utils:IsInHeist() then
          self:send_out_joker(managers.player:upgrade_value("player", "convert_enemies_max_minions", 0))
        end
      end
    })
    base_settings:Toggle({
      name = "show_messages",
      text = "Jokermon_menu_show_messages",
      help = "Jokermon_menu_show_messages_desc",
      on_callback = function (item) self:change_menu_setting(item) end,
      value = self.settings.show_messages
    })
    self.menu_nuzlocke = base_settings:Toggle({
      name = "nuzlocke",
      text = "Jokermon_menu_nuzlocke",
      help = "Jokermon_menu_nuzlocke_desc",
      on_callback = function (item) self:change_menu_setting(item) end,
      value = self.settings.nuzlocke
    })
    base_settings:Divider({
      h = self.menu_padding * 2
    })
  
    local panel_settings = menu:DivGroup({
      text = "Jokermon_menu_panel_settings",
      size = self.menu_title_size,
      inherit_values = {
        size = self.menu_items_size,
        wheel_control = true
      },
      border_bottom = true,
      border_position_below_title = true,
      w = self._menu_w_left,
      position = { self.menu_padding, base_settings:Bottom() }
    })
    panel_settings:Toggle({
      name = "show_panels",
      text = "Jokermon_menu_show_panels",
      help = "Jokermon_menu_show_panels_desc",
      on_callback = function (item) self:change_menu_setting(item) end,
      value = self.settings.show_panels
    })
    panel_settings:ComboBox({
      name = "panel_layout",
      text = "Jokermon_menu_panel_layout",
      items = { "Jokermon_menu_panel_layout_vertical", "Jokermon_menu_panel_layout_horizontal" },
      value = self.settings.panel_layout,
      free_typing = false,
      on_callback = function (item)
        self:change_menu_setting(item)
        self:layout_panels()
      end
    })
    panel_settings:ComboBox({
      name = "panel_x_align",
      text = "Jokermon_menu_panel_x_align",
      items = { "Jokermon_menu_panel_align_left", "Jokermon_menu_panel_align_center", "Jokermon_menu_panel_align_right" },
      value = self.settings.panel_x_align,
      free_typing = false,
      on_callback = function (item)
        self:change_menu_setting(item)
        self:layout_panels()
      end
    })
    panel_settings:ComboBox({
      name = "panel_y_align",
      text = "Jokermon_menu_panel_y_align",
      items = { "Jokermon_menu_panel_align_top", "Jokermon_menu_panel_align_center", "Jokermon_menu_panel_align_bottom" },
      value = self.settings.panel_y_align,
      free_typing = false,
      on_callback = function (item)
        self:change_menu_setting(item)
        self:layout_panels()
      end
    })
    panel_settings:Slider({
      name = "panel_x_pos",
      text = "Jokermon_menu_panel_x_pos",
      value = self.settings.panel_x_pos,
      min = 0,
      max = 1,
      step = 0.01,
      on_callback = function (item)
        self:change_menu_setting(item)
        self:layout_panels()
      end
    })
    panel_settings:Slider({
      name = "panel_y_pos",
      text = "Jokermon_menu_panel_y_pos",
      value = self.settings.panel_y_pos,
      min = 0,
      max = 1,
      step = 0.01,
      on_callback = function (item)
        self:change_menu_setting(item)
        self:layout_panels()
      end
    })
    panel_settings:Slider({
      name = "panel_spacing",
      text = "Jokermon_menu_panel_spacing",
      value = self.settings.panel_spacing,
      min = 0,
      max = 256,
      step = 1,
      floats = 1,
      on_callback = function (item)
        self:change_menu_setting(item)
        self:layout_panels()
      end
    })
    panel_settings:Divider({
      h = self.menu_padding * 2
    })

    local keybinds = menu:DivGroup({
      text = "Jokermon_menu_keybinds",
      size = self.menu_title_size,
      inherit_values = {
        size = self.menu_items_size
      },
      border_bottom = true,
      border_position_below_title = true,
      w = self._menu_w_left,
      position = { self.menu_padding, panel_settings:Bottom() }
    })
    keybinds:KeyBind({
      name = "menu",
      text = "Jokermon_menu_key_menu",
      help = "Jokermon_menu_key_menu_desc",
      value = self.settings.keys.menu,
      on_callback = function (item)
        self:change_key_binding(item)
      end
    })
    keybinds:KeyBind({
      name = "spawn_joker",
      text = "Jokermon_menu_key_spawn_joker",
      help = "Jokermon_menu_key_spawn_joker_desc",
      value = self.settings.keys.spawn_joker,
      on_callback = function (item)
        self:change_key_binding(item)
      end
    })
  
    self.menu_management = menu:DivGroup({
      text = "Jokermon_menu_management",
      size = self.menu_title_size,
      inherit_values = {
        size = self.menu_items_size
      },
      enabled = not Utils:IsInHeist(),
      border_bottom = true,
      border_position_below_title = true,
      w = self._menu_w_right,
      position = { base_settings:Right() + self.menu_padding, title:Bottom() }
    })
    local sorting = self.menu_management:ComboBox({
      name = "sorting",
      text = "Jokermon_menu_sorting",
      help = "Jokermon_menu_sorting_desc",
      items = { "Jokermon_menu_sorting_date", "Jokermon_menu_sorting_level", "Jokermon_menu_sorting_max_hp", "Jokermon_menu_sorting_hp", "Jokermon_menu_sorting_rel_hp", "Jokermon_menu_sorting_exp", "Jokermon_menu_sorting_exp_needed", "Jokermon_menu_sorting_total_exp", "Jokermon_menu_sorting_custom" },
      value = self.settings.sorting,
      free_typing = false,
      w = self.menu_management:W() * 0.4 - self.menu_padding
    })
    local order = self.menu_management:ComboBox({
      name = "sorting_order",
      text = "Jokermon_menu_sorting_order",
      items = { "Jokermon_menu_sorting_order_asc", "Jokermon_menu_sorting_order_desc" },
      value = self.settings.sorting_order,
      free_typing = false,
      w = self.menu_management:W() * 0.4 - self.menu_padding,
      position = { sorting:Right() + self.menu_padding, sorting:Y() },
    })
    local apply_sorting = self.menu_management:Button({
      text = "Jokermon_menu_apply_sorting",
      text_align = "center",
      w = self.menu_management:W() * 0.2,
      position = { order:Right() + self.menu_padding, order:Y() },
      on_callback = function (item)
        self:change_menu_setting(sorting)
        self:change_menu_setting(order)
        self:sort_jokers()
        self:refresh_joker_list()
        self:save(true)
      end
    })

    self.menu_jokermon_list = self.menu_management:Menu({
      inherit_values = {
        size = self.menu_items_size
      },
      align_method = "grid",
      scrollbar = true,
      max_height = menu_h - self.menu_management:Y() - apply_sorting:Bottom() - self.menu_padding * 4
    })

    menu:Button({
      text = "menu_back",
      size = 24,
      size_by_text = true,
      highlight_color = Color.transparent,
      on_callback = function (item) self:set_menu_state(false) end,
      position = function (item) item:SetRightBottom(self.menu_management:Right(), self.menu_management:Y() - 4) end
    })
  end

  function Jokermon:refresh_joker_list()
    self.menu_nuzlocke:SetEnabled(not Utils:IsInHeist())
    self.menu_management:SetEnabled(not Utils:IsInHeist())
    self.menu_jokermon_list:ClearItems()
    local sub_menu, roll
    for i, joker in ipairs(self.jokers) do
      sub_menu = self.menu_jokermon_list:Holder({
        border_visible = true,
        w = self.menu_jokermon_list:W() / 2 - self.menu_padding * 2,
        auto_height = true,
        localized = false,
        background_color = self.menu_grid_item_color,
        offset = self.menu_padding,
        inherit_values = {
          offset = 0,
          text_offset = { self.menu_padding, self.menu_padding / 4 }
        }
      })
      self:fill_joker_panel(sub_menu, i, joker)
    end
  end

  function Jokermon:get_flavour_text(joker)
    joker:randomseed()
    return managers.localization:text("Jokermon_menu_flavour_" .. math.random(1, 36))
  end

  local floor = math.floor
  function Jokermon:fill_joker_panel(menu, i, joker)
    menu:ClearItems()
    menu:Divider({
      h = self.menu_padding / 2
    })
    local title = menu:Divider({
      text = string.format("%s (Lv.%u)", tostring(HopLib:name_provider():name_by_unit(nil, joker.uname) or "UNKNOWN"), joker.level),
      size = self.menu_items_size + 4
    })
    menu:Button({
      text = string.format("%u ", joker.stats.kills + joker.stats.special_kills),
      help = managers.localization:text("Jokermon_menu_stats", { KILLS = joker.stats.kills, SPECIAL_KILLS = joker.stats.special_kills, DAMAGE = floor(joker.stats.damage * 10) }),
      help_localized = false,
      size = self.menu_items_size + 4,
      size_by_text = true,
      highlight_color = Color.transparent,
      position = function (item) item:SetRightTop(menu:W(), title:Y()) end
    })
    menu:TextBox({
      text = "Jokermon_menu_nickname",
      localized = true,
      fit_text = true,
      value = joker.name,
      focus_mode = true,
      on_callback = function (item)
        joker.name = item:Value()
        self:save(true)
      end
    })
    menu:Divider({
      text = managers.localization:text("Jokermon_menu_hp_exp", { HP = floor(joker.hp * joker.hp_ratio * 10), MAXHP = floor(joker.hp * 10), HPRATIO = floor(joker.hp_ratio * 100), EXP = joker.exp, TOTALEXP = joker:level_to_exp(100), MISSINGEXP = math.max(0, joker.exp_level_next - joker.exp) })
    })
    menu:Divider({
      text = managers.localization:text("Jokermon_menu_catch_stats", {
        DATE = os.date("%b %d, %Y", joker.stats.catch_date),
        LEVEL = joker.stats.catch_level,
        HEIST = tweak_data.levels[joker.stats.catch_heist] and managers.localization:text(tweak_data.levels[joker.stats.catch_heist].name_id) or "UNKNOWN",
        DIFFICULTY = managers.localization:to_upper_text(tweak_data.difficulty_name_ids[joker.stats.catch_difficulty])
      }) .. "\n" .. self:get_flavour_text(joker),
      size = self.menu_items_size - 4,
      foreground = Color.white:with_alpha(0.5)
    })
    menu:NumberBox({
      text = "Jokermon_menu_order",
      help = "Jokermon_menu_order_desc",
      localized = true,
      fit_text = true,
      value = joker.order,
      floats = 0,
      size = self.menu_items_size - 4,
      focus_mode = true,
      on_callback = function (item)
        joker.order = item:Value()
        self:save(true)
      end
    })
    menu:Divider({
      h = self.menu_padding
    })
    local heal_price = joker:get_heal_price()
    local heal = menu:Button({
      text = string.format(managers.localization:text(joker.hp_ratio <= 0 and "Jokermon_menu_action_revive" or "Jokermon_menu_action_heal", { COST = managers.money._cash_sign .. managers.money:add_decimal_marks_to_string(tostring(heal_price)) })),
      w = menu:W() / 2,
      text_align = "center",
      enabled = joker.hp_ratio < 1 and managers.money:total() >= heal_price,
      on_callback = function (item)
        managers.money:deduct_from_spending(heal_price)
        joker.hp_ratio = 1
        self:save(true)
        self:fill_joker_panel(menu, i, joker)
      end
    })
    menu:Button({
      text = "Jokermon_menu_action_release",
      localized = true,
      w = menu:W() / 2,
      text_align = "center",
      position = function (item) item:SetRightTop(menu:W(), heal:Y()) end,
      on_callback = function (item)
        self:show_release_confirmation(i)
      end
    })
    menu:Divider({
      h = self.menu_padding / 2
    })
  end

  function Jokermon:show_release_confirmation(i)
    local diag = MenuDialog:new({
      accent_color = self.menu_accent_color,
      highlight_color = self.menu_highlight_color,
      background_color = self.menu_background_color,
      border_size = 1,
      offset = 0,
      text_offset = {self.menu_padding, self.menu_padding / 4},
      size = self.menu_items_size,
      items_size = self.menu_items_size
    })
    diag:Show({
      title = managers.localization:text("dialog_warning_title"),
      message = managers.localization:text("Jokermon_menu_confirm_release", { NAME = self.jokers[i].name }),
      w = self.menu._panel:w() / 2,
      yes = false,
      title_merge = {
        size = self.menu_title_size
      },
      create_items = function (menu)
        menu:Button({
          name = "JokermonYes",
          text = "dialog_yes",
          text_align = "right",
          localized = true,
          on_callback = function (item)
            diag:hide()
            table.remove(self.jokers, i)
            self:save(true)
            self:refresh_joker_list()
          end
        })
        menu:Button({
          name = "JokermonNo",
          text = "dialog_no",
          text_align = "right",
          localized = true,
          on_callback = function (item)
            diag:hide()
          end
        })
      end
    })
  end

  function Jokermon:change_menu_setting(item)
    self.settings[item:Name()] = item:Value()
    self:save()
  end

  function Jokermon:change_key_binding(item)
    self.settings.keys[item:Name()] = item:Value()
    BLT.Keybinds:get_keybind("jokermon_" .. item:Name()):SetKey(item:Value())
    self:save()
  end

  function Jokermon:set_menu_state(enabled)
    self:check_create_menu()
    if enabled and not self.menu:Enabled() then
      self:refresh_joker_list()
      self.menu:Enable()
    elseif not enabled then
      self.menu:Disable()
    end
  end
  
  Hooks:Add("HopLibOnMinionAdded", "HopLibOnMinionAddedJokermon", function(unit, player_unit)
    local uid = unit:id()
    Jokermon._unit_id_mappings[uid] = unit
    
    if player_unit ~= managers.player:local_player() then
      return
    end

    local key = Jokermon._queued_keys[1]
    local joker
    if key then
      -- Use existing Jokermon entry
      joker = Jokermon.jokers[key]
      joker:set_unit(unit)
      table.remove(Jokermon._queued_keys, 1)

      Jokermon:display_message("Jokermon_message_go", { NAME = joker.name })
      player_unit:sound_source():post_event("grenade_gas_npc_fire")
    else
      -- Create new Jokermon entry
      key = #Jokermon.jokers + 1
      joker = Joker:new(unit)
      table.insert(Jokermon.jokers, joker)

      Jokermon._jokers_added = Jokermon._jokers_added + 1

      Jokermon:display_message("Jokermon_message_capture", { NAME = HopLib:unit_info_manager():get_info(unit):name(), LEVEL = joker.level })
    end

    Jokermon:set_unit_stats(unit, joker, true)
    Jokermon:setup_joker(key, unit)

  end)

  Hooks:Add("HopLibOnMinionRemoved", "HopLibOnMinionRemovedJokermon", function(unit)
    local key = unit:base()._jokermon_key
    local joker = key and Jokermon.jokers[key]
    if joker then
      joker.hp_ratio = unit:character_damage()._health_ratio
      joker:set_unit(nil)
      if joker.hp_ratio <= 0 then
        Jokermon:display_message(Jokermon.settings.nuzlocke and "Jokermon_message_die" or "Jokermon_message_faint", { NAME = joker.name })
      else
        Jokermon:display_message("Jokermon_message_retrieve", { NAME = joker.name })
      end
      Jokermon:remove_panel(key)
      if Jokermon.settings.spawn_mode ~= 1 then
        Jokermon:send_out_joker(1, true)
      end
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
      local dmg = u_damage._jokermon_assists[attacker_key]
      u_damage._jokermon_assists[attacker_key] = dmg and dmg + damage_info.damage or damage_info.damage
      local attacker_joker = Jokermon.jokers[attacker_key]
      if attacker_joker then
        attacker_joker.stats.damage = attacker_joker.stats.damage + damage_info.damage
        if u_damage:dead() then
          local info = HopLib:unit_info_manager():get_info(unit)
          local cat = info and info:is_special() and "special_kills" or "kills"
          attacker_joker.stats[cat] = attacker_joker.stats[cat] + 1
        end
      end
    end
    if u_damage:dead() and u_damage._jokermon_assists then
      for key, dmg in pairs(u_damage._jokermon_assists) do
        -- Assists get exp based on the damage they did, kills get exp based on enemy hp
        joker = Jokermon.jokers[key]
        local panel = Jokermon.panels[key]
        if joker and joker:give_exp(key == attacker_key and math.max(u_damage._HEALTH_INIT, dmg) or dmg) then
          Jokermon:set_unit_stats(joker.unit, joker, true)
          if panel then
            panel:update_hp(joker.hp, joker.hp_ratio)
            panel:update_level(joker.level)
            panel:update_exp(0, true)
          end
          Jokermon:display_message("Jokermon_message_levelup", { NAME = joker.name, LEVEL = joker.level })
        end
        if joker and panel then
          panel:update_exp(joker:get_exp_ratio())
        end
      end
    end
  end)

  Hooks:Add("NetworkReceivedData", "NetworkReceivedDataJokermon", function(sender, id, data)
    if id == "jokermon_spawn" then
      Jokermon:spawn(json.decode(data), nil, LuaNetworking:GetPeers()[sender]:unit())
    elseif id == "jokermon_stats" then
      data = json.decode(data)
      Jokermon:set_unit_stats(Jokermon._unit_id_mappings[data.uid], data)
    elseif id == "jokermon_name" then
      data = json.decode(data)
      Jokermon:set_joker_name(Jokermon._unit_id_mappings[data.uid], data.name)
    elseif id == "jokermon_retrieve" then
      data = json.decode(data)
      Jokermon:retrieve_joker(Jokermon._unit_id_mappings[data.uid])
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

  Hooks:Add("MenuManagerPostInitialize", "MenuManagerPostInitializeJokermon", function(menu_manager, nodes)
  
    Jokermon:load()

    MenuCallbackHandler.Jokermon_open_menu = function ()
      Jokermon:set_menu_state(true)
    end

    MenuHelperPlus:AddButton({
      id = "JokermonMenu",
      title = "Jokermon_menu_main_name",
      desc = "Jokermon_menu_main_desc",
      node_name = "blt_options",
      callback = "Jokermon_open_menu"
    })

    local mod = BLT.Mods:GetMod(Jokermon.mod_path:gsub(".+/(.+)/$", "%1"))
    if not mod then
      log("[Jokermon] ERROR: Could not get mod object to register keybinds!")
      return
    end
    BLT.Keybinds:register_keybind(mod, { id = "jokermon_menu", allow_menu = true, allow_game = true, show_in_menu = false, callback = function()
      Jokermon:set_menu_state(true)
    end }):SetKey(Jokermon.settings.keys.menu)
    BLT.Keybinds:register_keybind(mod, { id = "jokermon_spawn_joker", allow_game = true, show_in_menu = false, callback = function()
      Jokermon:send_or_retrieve_joker()
    end }):SetKey(Jokermon.settings.keys.spawn_joker)
  
  end)
  
end

if RequiredScript then

  local fname = Jokermon.mod_path .. "lua/" .. RequiredScript:gsub(".+/(.+)", "%1.lua")
  if io.file_is_readable(fname) then
    dofile(fname)
  end

end