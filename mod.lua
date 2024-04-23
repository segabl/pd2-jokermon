if not Jokermon then

	_G.Jokermon = {}

	dofile(ModPath .. "req/Joker.lua")
	dofile(ModPath .. "req/JokerPanel.lua")

	Jokermon.mod_instance = ModInstance
	Jokermon.mod_path = ModPath
	Jokermon.save_path = SavePath
	Jokermon.settings = {
		nuzlocke = false,
		temporary = false,
		vanilla = false,
		show_panels = true,
		panel_w = 200,
		panel_x_pos = 0.96,
		panel_y_pos = 0.65,
		panel_spacing = 12,
		panel_layout = 1,
		panel_x_align = 1,
		panel_y_align = 3,
		show_messages = true,
		spawn_mode = 1,
		sorting = 1,
		sorting_order = 1,
		keys = {
			menu = "m",
			spawn_joker = "j"
		}
	}
	Jokermon.MAX_JOKERS = 50
	Jokermon.jokers = {}
	Jokermon.panels = {}
	Jokermon._num_panels = 0
	Jokermon._queued_keys = {}
	Jokermon._queued_converts = {}
	Jokermon._unit_id_mappings = {}
	Jokermon._jokers_added = 0
	Jokermon._joker_index = 1
	Jokermon._joker_slot = World:make_slot_mask(16, 22)
	Jokermon._jokermon_key_press_t = 0
	Jokermon._jokermon_peers = {}
	Jokermon._modded_server = not Network:is_client()

	local unit_ids = Idstring("unit")

	function Jokermon:display_message(message, macros, force)
		if force or Jokermon.settings.show_messages then
			managers.chat:_receive_message(1, managers.localization:to_upper_text("Jokermon_menu_main_name"), managers.localization:text(message, macros), tweak_data.system_chat_color)
		end
	end

	local to_vec = Vector3()
	function Jokermon:send_or_retrieve_joker()
		local t = managers.player:player_timer():time()
		if self._jokermon_key_press_t + 0.5 > t then
			return
		end
		self._jokermon_key_press_t = t
		local viewport = managers.viewport
		if viewport:get_current_camera() then
			local from = viewport:get_current_camera_position()
			mvector3.set(to_vec, viewport:get_current_camera_rotation():y())
			mvector3.multiply(to_vec, 2000)
			mvector3.add(to_vec, from)
			local col = World:raycast("ray", from, to_vec, "slot_mask", Jokermon._joker_slot, "sphere_cast_radius", 50)
			if col and col.unit and col.unit:base()._jokermon_key then
				return self:retrieve_joker(col.unit)
			end
		end
		return self:send_out_joker()
	end

	function Jokermon:send_out_joker(num, skip_check)
		if not Utils:IsInHeist() then
			return
		end
		local player = managers.player:local_player()
		if not player or not skip_check and (not managers.player:has_category_upgrade("player", "convert_enemies") or managers.player:chk_minion_limit_reached()) then
			return
		end
		if #self.jokers == 0 then
			return
		end
		if not num and not self._modded_server then
			self:display_message("Jokermon_message_unmodded_server", nil, true)
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
		unit:base()._jokermon_retrieving = true
		if Network:is_server() then
			World:delete_unit(unit)
		else
			if not self._modded_server then
				self:display_message("Jokermon_message_unmodded_server", nil, true)
			end
			LuaNetworking:SendToPeer(1, "jokermon_retrieve", json.encode({ uid = unit:id() }))
		end
	end

	function Jokermon:get_unit_name(key)
		local ids_xml = ScriptSerializer:from_custom_xml(string.format("<table type=\"table\" id=\"@ID%s@\">", key))
		local ids = ids_xml and ids_xml.id
		if type_name(ids) == "Idstring" then
			return ids
		end
	end

	function Jokermon:spawn(joker, index, player_unit)
		if not alive(player_unit) then
			return
		end

		local ids = self:get_unit_name(joker.uname)
		if not ids then
			return
		end

		local is_local_player = player_unit == managers.player:local_player()

		if PackageManager:has(unit_ids, ids) then
			if is_local_player then
				table.insert(self._queued_keys, index)
			end

			-- If we are client, request spawn from server
			if Network:is_client() then
				LuaNetworking:SendToPeer(1, "jokermon_spawn", json.encode({ uname = joker.uname, name = joker.name, wname = joker.wname }))
				return true
			end

			-- Spawn unit as server
			local unit = World:spawn_unit(ids, player_unit:position() + Vector3(math.random(-50, 50), math.random(-50, 50), 0), player_unit:rotation())
			unit:movement():set_team({ id = "law1", foes = {}, friends = {} })
			unit:brain():set_active(false)
			unit:character_damage():set_invulnerable(true)
			unit:character_damage():set_immortal(true)
			unit:network():send("set_unit_invulnerable", true, true)

			-- Set weapon
			local weapon_name = joker.wname and self:get_unit_name(joker.wname)
			if weapon_name and PackageManager:has(unit_ids, weapon_name) then
				unit:base().default_weapon_name = function () return weapon_name end
			end

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
					if Keepers and Keepers.settings and Keepers.settings.send_my_joker_name then
						local peer_id = data.player_unit:network():peer():id()
						local my_joker = peer_id == (managers.network:session() and managers.network:session():local_peer():id())
						if my_joker and Keepers.settings.show_my_joker_name or not my_joker and Keepers.settings.show_other_jokers_names then
							Keepers.joker_names[peer_id] = data.joker.name
						end
					end
					data.unit:character_damage():set_invulnerable(false)
					data.unit:character_damage():set_immortal(false)
					data.unit:network():send("set_unit_invulnerable", false, false)
					data.unit:brain():set_active(true)
					data.unit:inventory():destroy_all_items()
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
		unit:base().joker_name = name
		HopLib:unit_info_manager():get_info(unit)._nickname = name

		local name_label_id = unit:unit_data().name_label_id
		local name_label = name_label_id and managers.hud:_get_name_label(name_label_id)
		if name_label and name_label.panel:child("text") then
			local peer_id = Keepers and unit:base().kpr_minion_owner_peer_id
			if peer_id and name_label.panel:child("text"):text() ~= "" then
				Keepers:destroy_label(unit)
				unit:base().kpr_minion_owner_peer_id = peer_id
				Keepers.joker_names[peer_id] = name
				Keepers:set_joker_label(unit)
			end
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

		local u_base = unit:base()
		local unit_shiny = u_base:has_shiny_effect()
		if data.shiny and not unit_shiny then
			u_base:add_shiny_effect()
		elseif not data.shiny and unit_shiny then
			u_base:remove_shiny_effect()
		end

		if sync then
			LuaNetworking:SendToPeers("jokermon_stats", json.encode({ uid = unit:id(), hp = data.hp, hp_ratio = data.hp_ratio, shiny = data.shiny }))
		end
	end

	local _sort_comp = {
		default = function (a, b) return a < b end,
		[2] = function (a, b) return a > b end
	}
	local _sort_val = {
		default = function (v) return v.order end,
		[1] = function (v) return v.catch_date end,
		[2] = function (v) return v.level end,
		[3] = function (v) return v.hp end,
		[4] = function (v) return v.hp * v.hp_ratio end,
		[5] = function (v) return v.hp_ratio end,
		[6] = function (v) return v.exp end,
		[7] = function (v) return v.level < Joker.MAX_LEVEL and v.exp_level_next - v.exp or math.huge end,
		[8] = function (v) return v:level_to_exp(100) end
	}
	function Jokermon:sort_jokers()
		local c = _sort_comp[self.settings.sorting_order] or _sort_comp.default
		local v = _sort_val[self.settings.sorting] or _sort_val.default
		local va, vb
		table.sort(self.jokers, function (a, b)
			va, vb = v(a), v(b)
			if va == vb then
				return c(a.catch_date, b.catch_date)
			end
			return c(va, vb)
		end)
	end

	function Jokermon:layout_panels(width_changed)
		local i = 0
		local x, y
		local x_pos, y_pos, spacing = self.settings.panel_x_pos, self.settings.panel_y_pos, self.settings.panel_spacing
		local x_align, y_align = self.settings.panel_x_align, self.settings.panel_y_align
		local horizontal_layout = self.settings.panel_layout ~= 1 and 1 or 0
		local vertical_layout = self.settings.panel_layout == 1 and 1 or 0
		local panel_w = self.settings.panel_w
		for _, panel in pairs(self.panels) do
			if width_changed then
				panel:set_width(panel_w)
			end
			if x_align == 2 and horizontal_layout == 1 then
				x = (panel._parent_panel:w() - panel_w * self._num_panels - spacing * (self._num_panels - 1)) * x_pos + (panel_w + spacing) * i
			else
				x = (panel._parent_panel:w() - panel_w) * x_pos + (panel_w + spacing) * i * horizontal_layout * (x_align == 3 and -1 or 1)
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
		local hud_panel = self.settings.show_panels and managers.hud:panel(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if not alive(hud_panel) then
			return
		end
		local joker = self.jokers[key]
		local panel = JokerPanel:new(hud_panel, self.settings.panel_w)
		panel:update_name(joker.name)
		panel:update_hp(joker.hp, joker.hp_ratio, true)
		panel:update_level(joker.level)
		panel:update_exp(joker:get_exp_ratio(), true)
		panel:update_kills(0)
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
					if not v.discard then
						table.insert(jokers, v:get_save_data())
					end
				end
				file:write(json.encode(jokers))
				file:close()
			end
		end
	end

	function Jokermon:load()
		local save_file = self.save_path .. "jokermon_settings.txt"
		local data = io.file_is_readable(save_file) and io.load_as_json(save_file)
		if data then
			for k, v in pairs(data) do
				self.settings[k] = v
			end
		end
		local jokers_file = self.save_path .. "jokermon.txt"
		local jokers = io.file_is_readable(jokers_file) and io.load_as_json(jokers_file)
		if jokers then
			self.jokers = {}
			for _, joker in pairs(jokers) do
				if joker.uname and joker.tweak then
					table.insert(self.jokers, Joker:new(nil, joker))
				else
					log(string.format("[Jokermon] Error: Joker \"%s\" is missing data and has been removed to prevent crashes!", joker.name or "Unknown"))
				end
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
		self.menu_accent_color = BeardLib.Options:GetValue("MenuColor"):with_alpha(0.75)
		self.menu_highlight_color = self.menu_accent_color:with_alpha(0.075)
		self.menu_grid_item_color = Color.black:with_alpha(0.5)

		self.menu = MenuUI:new({
			name = "JokermonMenu",
			layer = 1000,
			background_blur = true,
			animate_toggle = true,
			text_offset = 3,
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

		self._menu_w_left = menu_w / 3.5 - self.menu_padding
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
				if self.settings.spawn_mode > 1 and Utils:IsInHeist() and managers.groupai:state():enemy_weapons_hot() then
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
			on_callback = function (item)
				self:change_menu_setting(item)
				self.menu_vanilla:SetEnabled(not item:Value() and not self.menu_in_heist)
			end,
			value = self.settings.nuzlocke
		})
		self.menu_vanilla = base_settings:Toggle({
			name = "vanilla",
			text = "Jokermon_menu_vanilla",
			help = "Jokermon_menu_vanilla_desc",
			on_callback = function (item)
				self:change_menu_setting(item)
				self:refresh_joker_list()
			end,
			value = self.settings.vanilla
		})
		base_settings:Toggle({
			name = "temporary",
			text = "Jokermon_menu_temporary",
			help = "Jokermon_menu_temporary_desc",
			on_callback = function (item) self:change_menu_setting(item) end,
			value = self.settings.temporary
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
			position = { self.menu_padding, base_settings:Bottom() + self.menu_padding / 2 }
		})
		panel_settings:Toggle({
			name = "show_panels",
			text = "Jokermon_menu_show_panels",
			help = "Jokermon_menu_show_panels_desc",
			on_callback = function (item) self:change_menu_setting(item) end,
			value = self.settings.show_panels
		})
		panel_settings:Slider({
			name = "panel_w",
			text = "Jokermon_menu_panel_w",
			value = self.settings.panel_w,
			floats = 0,
			min = 160,
			max = 480,
			step = 8,
			on_callback = function (item)
				self:change_menu_setting(item)
				self:layout_panels(true)
			end
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

		local keybinds = menu:DivGroup({
			text = "Jokermon_menu_keybinds",
			size = self.menu_title_size,
			inherit_values = {
				size = self.menu_items_size
			},
			border_bottom = true,
			border_position_below_title = true,
			w = self._menu_w_left,
			position = { self.menu_padding, panel_settings:Bottom() + self.menu_padding / 2 }
		})
		keybinds:KeyBind({
			name = "menu",
			text = "Jokermon_menu_key_menu",
			help = "Jokermon_menu_key_menu_desc",
			value = self.settings.keys.menu,
			supports_mouse = true,
			on_callback = function (item)
				self:change_key_binding(item)
			end
		})
		keybinds:KeyBind({
			name = "spawn_joker",
			text = "Jokermon_menu_key_spawn_joker",
			help = "Jokermon_menu_key_spawn_joker_desc",
			value = self.settings.keys.spawn_joker,
			supports_mouse = true,
			on_callback = function (item)
				self:change_key_binding(item)
			end
		})

		local actions = menu:DivGroup({
			text = "Jokermon_menu_actions",
			size = self.menu_title_size,
			inherit_values = {
				size = self.menu_items_size
			},
			border_bottom = true,
			border_position_below_title = true,
			w = self._menu_w_left,
			position = { self.menu_padding, keybinds:Bottom() + self.menu_padding / 2 }
		})
		self.menu_heal_all_button = actions:Button({
			text = managers.localization:text("Jokermon_menu_action_heal_all", { COST = self:make_money_string(0) }),
			localized = false,
			enabled = false,
			on_callback = function (item)
				self:heal_all_jokers(false)
			end
		})
		self.menu_revive_all_button = actions:Button({
			text = managers.localization:text("Jokermon_menu_action_revive_all", { COST = self:make_money_string(0) }),
			localized = false,
			enabled = false,
			on_callback = function (item)
				self:heal_all_jokers(true)
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
		self.menu_joker_number_text = self.menu_management:Panel():text({
			text = "0 / 0",
			font = "fonts/font_large_mf",
			align = "right",
			y = self.menu_padding / 2,
			font_size = self.menu_title_size
		})
		local sorting = self.menu_management:ComboBox({
			name = "sorting",
			text = "Jokermon_menu_sorting",
			help = "Jokermon_menu_sorting_desc",
			items = { "Jokermon_menu_sorting_date", "Jokermon_menu_sorting_level", "Jokermon_menu_sorting_max_hp", "Jokermon_menu_sorting_hp", "Jokermon_menu_sorting_rel_hp", "Jokermon_menu_sorting_exp", "Jokermon_menu_sorting_exp_needed", "Jokermon_menu_sorting_total_exp", "Jokermon_menu_sorting_custom" },
			value = self.settings.sorting,
			free_typing = false,
			w = self.menu_management:W() * 0.5 - self.menu_padding,
			on_callback = function (item)
				self:change_menu_setting(item)
				self:sort_jokers()
				self:refresh_joker_list()
				self:save(true)
			end
		})
		local order = self.menu_management:ComboBox({
			name = "sorting_order",
			text = "Jokermon_menu_sorting_order",
			items = { "Jokermon_menu_sorting_order_asc", "Jokermon_menu_sorting_order_desc" },
			value = self.settings.sorting_order,
			free_typing = false,
			w = self.menu_management:W() * 0.5 - self.menu_padding,
			position = { sorting:Right() + self.menu_padding, sorting:Y() },
			on_callback = function (item)
				self:change_menu_setting(item)
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
			max_height = menu_h - self.menu_management:Y() - order:Bottom() - self.menu_padding * 4
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

	function Jokermon:make_money_string(price)
		return managers.money._cash_sign .. managers.money:add_decimal_marks_to_string(tostring(price))
	end

	function Jokermon:refresh_joker_list(check_state)
		if not self.menu then
			return
		end
		local in_heist = Utils:IsInHeist() or false
		if check_state and self.menu_in_heist == in_heist then
			return
		end

		self.menu_in_heist = in_heist
		self.menu_nuzlocke:SetEnabled(not self.menu_in_heist)
		self.menu_vanilla:SetEnabled(not self.menu_in_heist and not self.settings.nuzlocke)
		self.menu_management:SetEnabled(not self.menu_in_heist)
		self.menu_jokermon_list:ClearItems()
		self.menu_joker_number_text:set_text(string.format("%u / %u", #self.jokers, Jokermon.MAX_JOKERS))
		self.menu_heal_all_button:SetEnabled(false)
		self.menu_revive_all_button:SetEnabled(false)
		self.heal_all_price = 0
		self.revive_all_price = 0
		self.joker_list_coroutine = coroutine.create(function ()
			local sub_menu
			local t = os.clock()
			for i, joker in ipairs(self.jokers) do
				if not joker.discard then
					sub_menu = self.menu_jokermon_list:Holder({
						border_visible = true,
						w = self.menu_jokermon_list:W() / 2 - self.menu_padding,
						auto_height = true,
						background_color = self.menu_grid_item_color,
						offset = self.menu_padding / 2,
					}):Holder({
						auto_height = true,
						localized = false,
						inherit_values = {
							offset = 0,
							text_offset = { 0, self.menu_padding / 4 }
						}
					})
					self:fill_joker_panel(sub_menu, i, joker, true)
					if os.clock() - t > 1 / 30 then
						coroutine.yield()
						t = os.clock()
					end
				end
			end
			self.menu_heal_all_button:SetEnabled(not self.menu_in_heist and self.heal_all_price > 0 and managers.money:total() >= self.heal_all_price)
			self.menu_revive_all_button:SetEnabled(not self.menu_in_heist and self.revive_all_price > 0 and managers.money:total() >= self.revive_all_price)
		end)
	end

	function Jokermon:get_flavour_text(joker)
		joker:randomseed()
		return managers.localization:text("Jokermon_menu_flavour_" .. math.random(1, 36))
	end

	local floor = math.floor
	function Jokermon:fill_joker_panel(menu, i, joker, created)
		menu:ClearItems()
		joker:calculate_stats()
		local xp = menu:Button({
			text = tostring(joker.level),
			help = managers.localization:text("Jokermon_menu_exp", { EXP = joker.exp, TOTALEXP = joker:level_to_exp(Joker.MAX_LEVEL), MISSINGEXP = math.max(0, joker.exp_level_next - joker.exp) }),
			help_localized = false,
			text_align = "center",
			highlight_color = Color.transparent,
			w = 56,
			h = 56
		})
		xp.panel:bitmap({
			texture = "guis/textures/pd2/level_ring_small",
			alpha = 0.4,
			w = 56,
			h = 56,
			color = Color.black
		})
		xp.panel:bitmap({
			texture = "guis/textures/pd2/level_ring_small",
			render_template = "VertexColorTexturedRadial",
			blend_mode = "add",
			layer = 1,
			w = 56,
			h = 56,
			color = Color(joker:get_exp_ratio(), 1, 1)
		})

		local title = menu:TextBox({
			text = HopLib:name_provider():name_by_unit(nil, joker.uname) or "Unknown",
			help = "Jokermon_menu_nickname",
			fit_text = true,
			value = joker.name,
			focus_mode = true,
			on_callback = function (item)
				joker.name = item:Value()
				self:save(true)
			end,
			position = function (item) item:SetXY(xp:Right() + self.menu_padding / 2 + 12, xp:Y()) end
		})
		if joker.shiny then
			menu.panel:bitmap({
				texture = "guis/textures/pd2/crimenet_star",
				x = xp:Right(),
				y = title:Y() + title:H() / 2 - 8,
				w = 16,
				h = 16
			})
		end
		menu:Divider({
			size = self.menu_items_size - 4,
			text = joker:weapon_name() .. "\n" .. managers.localization:text("Jokermon_menu_hp", { HP = floor(joker.hp * joker.hp_ratio * 10), MAXHP = floor(joker.hp * 10), HPRATIO = floor(joker.hp_ratio * 100) }),
			position = function (item) item:SetLeftBottom(title:X(), xp:Bottom()) end
		})
		menu:NumberBox({
			text = "Jokermon_menu_order",
			help = "Jokermon_menu_order_desc",
			localized = true,
			fit_text = true,
			value = joker.order,
			floats = 0,
			focus_mode = true,
			control_slice = 0.7,
			position = function (item) item:SetLeftBottom(title:X() + title._textbox.panel:x(), xp:Bottom()) end,
			on_callback = function (item)
				joker.order = item:Value()
				self:save(true)
			end
		})
		local stats = menu:Divider({
			text = managers.localization:text("Jokermon_menu_catch_stats", {
				DATE = os.date("%B %d, %Y at %H:%M", joker.catch_date),
				OT = joker:original_owner_name(),
				LEVEL = joker.catch_level,
				HEIST = tweak_data.levels[joker.catch_heist] and managers.localization:text(tweak_data.levels[joker.catch_heist].name_id) or "Unknown",
				DIFFICULTY = managers.localization:to_upper_text(tweak_data.difficulty_name_ids[joker.catch_difficulty])
			}) .. "\n" .. managers.localization:text("Jokermon_menu_stats", { KILLS = joker.kills, SPECIAL_KILLS = joker.special_kills, DAMAGE = floor(joker.damage * 10) }) .. "\n" .. self:get_flavour_text(joker),
			size = self.menu_items_size - 4,
			foreground = Color.white:with_alpha(0.5)
		})
		local heal_price = joker:get_heal_price()
		local heal = menu:Button({
			text = managers.localization:text(joker.hp_ratio <= 0 and "Jokermon_menu_action_revive" or "Jokermon_menu_action_heal", { COST = self:make_money_string(heal_price) }),
			w = menu:W() / 2,
			text_align = "center",
			enabled = joker.hp_ratio < 1 and managers.money:total() >= heal_price,
			on_callback = function (item)
				managers.money:deduct_from_spending(heal_price)
				self.heal_all_price = self.heal_all_price - (joker.hp_ratio > 0 and heal_price or 0)
				self.revive_all_price = self.revive_all_price - (joker.hp_ratio <= 0 and heal_price or 0)
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

		if created then
			self.heal_all_price = self.heal_all_price + (joker.hp_ratio > 0 and heal_price or 0)
			self.revive_all_price = self.revive_all_price + (joker.hp_ratio <= 0 and heal_price or 0)
		else
			self.menu_heal_all_button:SetEnabled(not self.menu_in_heist and self.heal_all_price > 0 and managers.money:total() >= self.heal_all_price)
			self.menu_revive_all_button:SetEnabled(not self.menu_in_heist and self.revive_all_price > 0 and managers.money:total() >= self.revive_all_price)
		end
		self.menu_heal_all_button:SetText(managers.localization:text("Jokermon_menu_action_heal_all", { COST = self:make_money_string(self.heal_all_price) }))
		self.menu_revive_all_button:SetText(managers.localization:text("Jokermon_menu_action_revive_all", { COST = self:make_money_string(self.revive_all_price) }))
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

	function Jokermon:heal_all_jokers(revive)
		if revive then
			self.menu_revive_all_button:SetText(managers.localization:text("Jokermon_menu_action_revive_all", { COST = self:make_money_string(0) }))
		else
			self.menu_heal_all_button:SetText(managers.localization:text("Jokermon_menu_action_heal_all", { COST = self:make_money_string(0) }))
		end
		table.for_each_value(self.jokers, function (joker)
			if revive and joker.hp_ratio <= 0 or not revive and joker.hp_ratio > 0 then
				joker.hp_ratio = 1
			end
		end)
		managers.money:deduct_from_spending(revive and self.revive_all_price or self.heal_all_price)
		self:save(true)
		self:refresh_joker_list()
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
			Jokermon:refresh_joker_list(true)
			self.menu:Enable()
		elseif not enabled then
			self.menu:Disable()
		end
	end

	Hooks:Add("HopLibOnMinionAdded", "HopLibOnMinionAddedJokermon", function(unit, player_unit)
		if Jokermon._unit_id_mappings[unit:id()] then
			return
		end

		Jokermon._unit_id_mappings[unit:id()] = unit

		if player_unit ~= managers.player:local_player() then
			return
		end

		local joker
		local key = table.remove(Jokermon._queued_keys, 1)
		if key then
			-- Use existing Jokermon entry
			joker = Jokermon.jokers[key]
			joker:set_unit(unit)
			joker:calculate_stats()

			Jokermon:display_message("Jokermon_message_go", { NAME = joker.name })
			player_unit:sound_source():post_event("grenade_gas_npc_fire")
		else
			-- Create new Jokermon entry
			key = #Jokermon.jokers + 1
			joker = Joker:new(unit)
			joker.discard = Jokermon.settings.temporary and not unit:base():has_shiny_effect() or nil
			table.insert(Jokermon.jokers, joker)

			Jokermon._jokers_added = Jokermon._jokers_added + 1

			Jokermon:display_message("Jokermon_message_capture", { NAME = HopLib:unit_info_manager():get_info(unit):name(), LEVEL = joker.level })
		end

		Jokermon:set_unit_stats(unit, joker, true)
		Jokermon:setup_joker(key, unit)

	end)

	Hooks:Add("HopLibOnMinionRemoved", "HopLibOnMinionRemovedJokermon", function(unit)
		local key = unit:base()._jokermon_key
		local joker = Jokermon.jokers[key]
		if joker then
			joker:set_unit(nil)
			if unit:base()._jokermon_retrieving then
				Jokermon:display_message("Jokermon_message_retrieve", { NAME = joker.name })
			end
			Jokermon:remove_panel(key)
			if Jokermon.settings.spawn_mode ~= 1 then
				call_on_next_update(function () Jokermon:send_out_joker(1, true) end)
			end
			unit:base()._jokermon_key = nil
		end
		Jokermon._unit_id_mappings[unit:id()] = nil
	end)

	Hooks:Add("HopLibOnUnitDamaged", "HopLibOnUnitDamagedJokermon", function(unit, damage_info)
		local u_damage = unit:character_damage()
		local key = unit:base()._jokermon_key
		local joker = Jokermon.jokers[key]
		if joker and not u_damage._jokermon_dead then
			joker.hp_ratio = math.min(math.max(u_damage._health_ratio, 0), 1)
			local panel = Jokermon.panels[key]
			if panel then
				panel:update_hp(joker.hp, joker.hp_ratio)
			end
			if joker.hp_ratio <= 0 then
				unit:base()._jokermon_retrieving = false
				Jokermon:display_message(Jokermon.settings.nuzlocke and "Jokermon_message_die" or "Jokermon_message_faint", { NAME = joker.name })
				joker.discard = Jokermon.settings.nuzlocke or joker.discard
				Jokermon:remove_panel(key)
				u_damage._jokermon_dead = true
			end
		end
		local attacker_key = alive(damage_info.attacker_unit) and damage_info.attacker_unit:base()._jokermon_key
		if attacker_key then
			u_damage._jokermon_assists = u_damage._jokermon_assists or {}
			u_damage._jokermon_assists[attacker_key] = true
			local attacker_joker = Jokermon.jokers[attacker_key]
			if attacker_joker then
				attacker_joker.damage = attacker_joker.damage + damage_info.damage
			end
		end
	end)

	Hooks:Add("HopLibOnUnitDied", "HopLibOnUnitDiedJokermon", function(unit, damage_info)
		local u_damage = unit:character_damage()
		local attacker_key = alive(damage_info.attacker_unit) and damage_info.attacker_unit:base()._jokermon_key
		local attacker_joker = Jokermon.jokers[attacker_key]
		if not attacker_joker then
			return
		end

		if u_damage._jokermon_assists then
			for key, _ in pairs(u_damage._jokermon_assists) do
				local joker = Jokermon.jokers[key]
				local panel = Jokermon.panels[key]
				if joker and alive(joker.unit) then
					if joker:give_exp(u_damage._HEALTH_INIT) then
						Jokermon:set_unit_stats(joker.unit, joker, true)
						Jokermon:display_message("Jokermon_message_levelup", { NAME = joker.name, LEVEL = joker.level })
						if panel then
							panel:update_hp(joker.hp, joker.hp_ratio)
							panel:update_level(joker.level)
							panel:update_exp(joker:get_exp_ratio(), false, true)
						end
					elseif panel then
						panel:update_exp(joker:get_exp_ratio())
					end
				end
			end
		end

		local info = HopLib:unit_info_manager():get_info(unit)
		local cat = info and info:is_special() and "special_kills" or "kills"
		attacker_joker[cat] = attacker_joker[cat] + 1
		local panel = Jokermon.panels[attacker_key]
		if panel then
			info = HopLib:unit_info_manager():get_info(damage_info.attacker_unit)
			panel:update_kills(info and info:kills() or 0)
		end
	end)

	Hooks:Add("NetworkReceivedData", "NetworkReceivedDataJokermon", function(sender, id, data)
		if not id:match("^jokermon") then
			return
		end

		Jokermon._modded_server = Jokermon._modded_server or sender == 1

		if id == "jokermon_spawn" then
			data = json.decode(data)
			return data and Jokermon:spawn(data, nil, LuaNetworking:GetPeers()[sender]:unit())
		elseif id == "jokermon_stats" then
			data = json.decode(data)
			return data and Jokermon:set_unit_stats(Jokermon._unit_id_mappings[data.uid], data)
		elseif id == "jokermon_name" then
			data = json.decode(data)
			return data and Jokermon:set_joker_name(Jokermon._unit_id_mappings[data.uid], data.name)
		elseif id == "jokermon_retrieve" then
			data = json.decode(data)
			return data and Jokermon:retrieve_joker(Jokermon._unit_id_mappings[data.uid])
		end
	end)

	Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInitJokermon", function(loc)

		HopLib:load_localization(Jokermon.mod_path .. "loc/", loc)

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

	Hooks:Add("SetupPreUpdate", "SetupPreUpdateJokermon", function ()
		if Jokermon.joker_list_coroutine and not coroutine.resume(Jokermon.joker_list_coroutine) then
			Jokermon.joker_list_coroutine = nil
		end
	end)

end

HopLib:run_required(Jokermon.mod_path .. "lua/")
