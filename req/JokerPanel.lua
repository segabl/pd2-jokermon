JokerPanel = class()

JokerPanel.COLORS = {
	exp = Color(0.5, 1, 1),
	hp_normal = Color(0.5, 1, 0.5),
	hp_low = Color(1, 1, 0.5),
	hp_critical = Color(1, 0.5, 0.5),
	text = Color.white,
	skull = Color.yellow
}

local function hp_ratio_to_color(hp_ratio)
	return hp_ratio <= 0.15 and JokerPanel.COLORS.hp_critical or hp_ratio <= 0.5 and JokerPanel.COLORS.hp_low or JokerPanel.COLORS.hp_normal
end

function JokerPanel:init(panel, w)
	self._padding = 8

	self._parent_panel = panel

	self._panel = HUDBGBox_create(self._parent_panel, {
		w = w,
		h = 52,
		layer = 50
	}, {})

	self._name_text = self._panel:text({
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = self.COLORS.text,
		x = self._padding,
		y = self._padding - 1
	})

	self._lvl_text = self._panel:text({
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = self.COLORS.text:with_alpha(0.75),
		x = self._padding,
		y = self._padding - 1
	})

	self._kills_text = self._panel:text({
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = self.COLORS.text,
		x = self._padding,
		y = self._padding - 1,
		w = self._panel:w() - self._padding * 2,
		align = "right",
		halign = "right"
	})

	self._hp_bar_bg = self._panel:rect({
		color = Color.black:with_alpha(0.3),
		w = self._panel:w() - self._padding * 2,
		h = 12,
		x = self._padding,
		y = 24,
		halign = "grow",
		layer = -10
	})
	self._hp_bar = self._panel:rect({
		color = self.COLORS.hp_normal,
		w = self._hp_bar_bg:w(),
		h = self._hp_bar_bg:h(),
		x = self._hp_bar_bg:x(),
		y = self._hp_bar_bg:y(),
		layer = -1
	})
	self._hp_bar_flash = self._panel:rect({
		w = 1,
		h = 12,
		alpha = 0
	})
	self._hp_text = self._panel:text({
		text = "",
		font = tweak_data.menu.small_font,
		font_size = 9,
		align = "center",
		vertical = "center",
		w = self._hp_bar_bg:w(),
		h = self._hp_bar_bg:h(),
		x = self._hp_bar_bg:x(),
		y = self._hp_bar_bg:y()
	})
	self._hp_ratio = 1

	self._exp_bar_bg = self._panel:rect({
		color = Color.black:with_alpha(0.3),
		w = self._panel:w() - self._padding * 2,
		h = 4,
		x = self._padding,
		y = 40,
		halign = "grow",
		layer = -10
	})
	self._exp_bar = self._panel:rect({
		color = self.COLORS.exp,
		w = self._exp_bar_bg:w(),
		h = self._exp_bar_bg:h(),
		x = self._exp_bar_bg:x(),
		y = self._exp_bar_bg:y(),
		layer = -1
	})
	self._exp_bar_flash = self._panel:rect({
		color = self.COLORS.exp,
		alpha = 0,
		w = self._exp_bar_bg:w(),
		h = self._exp_bar_bg:h(),
		x = self._exp_bar_bg:x(),
		y = self._exp_bar_bg:y()
	})
	self._exp_ratio = 0

end

function JokerPanel:set_width(w)
	local max_w = w - self._padding * 2
	self._panel:set_w(w)
	self._hp_bar_bg:set_w(max_w)
	self._hp_bar:set_w(self._hp_ratio * max_w)
	self._hp_text:set_w(max_w)
	self._exp_bar_bg:set_w(max_w)
	self._exp_bar:set_w(self._exp_ratio * max_w)
end

function JokerPanel:set_position(x, y)
	self._panel:set_position(x, y)
end

function JokerPanel:update_name(name)
	self._name_text:set_text(name)
end

function JokerPanel:update_level(level)
	self._lvl_text:set_text(tostring(level) .. " ")
	local _, _, w, _ = self._lvl_text:text_rect()
	self._name_text:set_x(self._lvl_text:left() + w)
end

function JokerPanel:update_kills(kills)
	kills = tostring(kills)
	self._kills_text:set_text(kills .. "")
	self._kills_text:set_range_color(utf8.len(kills), utf8.len(self._kills_text:text()), self.COLORS.skull)
end

function JokerPanel:update_hp(hp, hp_ratio, instant)
	self._hp_bar:stop()
	hp_ratio = math.max(0, math.min(1, hp_ratio))
	local max_w = self._panel:w() - self._padding * 2
	if instant then
		self._hp_bar:set_color(hp_ratio_to_color(hp_ratio))
		self._hp_bar:set_w(max_w * hp_ratio)
		self._hp_text:set_text(math.floor(hp * hp_ratio * 10) .. " / " .. math.floor(hp * 10))
	else
		local start = self._hp_ratio
		self._hp_bar:animate(function ()
			over(0.25, function (p)
				local f = math.lerp(start, hp_ratio, p)
				self._hp_bar:set_color(hp_ratio_to_color(f))
				self._hp_bar:set_w(max_w * f)
				self._hp_text:set_text(math.floor(hp * f * 10) .. " / " .. math.floor(hp * 10))
			end)
		end)
		if hp_ratio < start then
			self._hp_bar_flash:animate(function ()
				self._hp_bar_flash:set_w(math.max(max_w * (start - hp_ratio), 1))
				self._hp_bar_flash:set_right(self._hp_bar:x() + max_w * start)
				over(0.1, function (p)
					self._hp_bar_flash:set_h(12 + 16 * p)
					self._hp_bar_flash:set_alpha(1 - p)
					self._hp_bar_flash:set_center_y(self._hp_bar:center_y())
				end)
			end)
		end
	end
	self._hp_ratio = hp_ratio
end

function JokerPanel:update_exp(exp_ratio, instant, level_up)
	self._exp_bar:stop()
	exp_ratio = math.max(0, math.min(1, exp_ratio))
	local max_w = self._panel:w() - self._padding * 2
	if instant then
		self._exp_bar:set_w(max_w * exp_ratio)
	else
		local start = self._exp_ratio
		local full = level_up and 1 - start + exp_ratio or exp_ratio
		self._exp_bar:animate(function ()
			if level_up then
				over(0.5 * (1 - start) / full, function (p)
					local f = math.lerp(start, 1, p)
					self._exp_bar:set_w(max_w * f)
				end)
				self._exp_bar_flash:animate(function ()
					over(0.1, function (p)
						self._exp_bar_flash:set_size(self._exp_bar_bg:w() + p * 16, self._exp_bar_bg:h() + p * 16)
						self._exp_bar_flash:set_center(self._exp_bar_bg:center_x(), self._exp_bar_bg:center_y())
						self._exp_bar_flash:set_alpha(1 - p)
					end)
				end)
				start = 0
			end
			over(0.5 * exp_ratio / full, function (p)
				local f = math.lerp(start, exp_ratio, p)
				self._exp_bar:set_w(max_w * f)
			end)
		end)
	end
	self._exp_ratio = exp_ratio
end

function JokerPanel:remove()
	self._hp_bar:stop()
	self._hp_bar_flash:stop()
	self._exp_bar:stop()
	self._exp_bar_flash:stop()
	self._parent_panel:remove(self._panel)
end