JokerPanel = class()

local hp_color = {
  normal = Color(0.5, 1, 0.5),
  low = Color(1, 1, 0.5),
  critical = Color(1, 0.5, 0.5)
}

local function hp_ratio_to_color(hp_ratio)
  return hp_ratio <= 0.15 and hp_color.critical or hp_ratio <= 0.5 and hp_color.low or hp_color.normal
end

function JokerPanel:init(joker)
  self._parent_panel = managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2).panel
  self._panel = self._parent_panel:panel({
    w = 256,
    h = 48,
    layer = 10
  })

  self._panel:rect({
    name = "bg",
    color = Color.black:with_alpha(0.2),
    w = self._panel:w(),
    h = self._panel:h(),
    layer = -10000
  })

  local name_text = self._panel:text({
    name = "name",
    text = joker.name,
    font = tweak_data.menu.pd2_medium_font,
    font_size = 16,
    color = Color.white,
    x = 4,
    y = 4
  })

  self._lvl_text = self._panel:text({
    name = "level",
    text = "Lv.1",
    font = tweak_data.menu.pd2_medium_font,
    font_size = 16,
    color = Color.white,
    y = 4
  })
  self:update_level(joker.level)

  local hp_bg = self._panel:rect({
    name = "hp_bg",
    color = Color.black:with_alpha(0.3),
    w = self._panel:w() - 8,
    h = 12,
    x = 4,
    y = 24,
    layer = -100
  })
  self._hp_bar = self._panel:rect({
    name = "hp",
    color = hp_color.normal,
    w = hp_bg:w(),
    h = hp_bg:h(),
    x = hp_bg:x(),
    y = hp_bg:y(),
    layer = -10
  })
  self._hp_text = self._panel:text({
    name = "hp_text",
    text = "1/1",
    font = tweak_data.menu.small_font,
    font_size = 9,
    align = "center",
    w = hp_bg:w(),
    h = hp_bg:h(),
    x = hp_bg:x(),
    y = hp_bg:y()
  })
  local _, _, _, h = self._hp_text:text_rect()
  self._hp_text:set_h(h)
  self._hp_text:set_center_y(hp_bg:y() + hp_bg:h() / 2)
  self:update_hp(joker.hp, joker.hp_ratio, true)

  local exp_bg = self._panel:rect({
    name = "exp_bg",
    color = Color.black:with_alpha(0.3),
    w = self._panel:w() - 8,
    h = 4,
    x = 4,
    y = 40,
    layer = -100
  })
  self._exp_bar = self._panel:rect({
    name = "exp",
    color = Color(0.5, 1, 1),
    w = exp_bg:w(),
    h = exp_bg:h(),
    x = exp_bg:x(),
    y = exp_bg:y(),
    layer = -10
  })
  local needed_current, needed_next = Jokermon:get_needed_exp(joker, joker.level), Jokermon:get_needed_exp(joker, joker.level + 1)
  self:update_exp(joker.level == 100 and 1 or (joker.exp - needed_current) / (needed_next - needed_current), true)
end

function JokerPanel:set_position(x, y)
  self._panel:set_position(x, y)
end

function JokerPanel:update_level(level)
  self._lvl_text:set_text("Lv." .. level)
  local _, _, w, h = self._lvl_text:text_rect()
  self._lvl_text:set_size(w, h)
  self._lvl_text:set_right(self._panel:w() - 4)
end

function JokerPanel:update_hp(hp, hp_ratio, instant)
  self._hp_bar:stop()
  hp_ratio = math.max(0, math.min(1, hp_ratio))
  local max_w = (self._panel:w() - 8)
  if instant then
    self._hp_bar:set_color(hp_ratio_to_color(hp_ratio))
    self._hp_bar:set_w(max_w * hp_ratio)
    self._hp_text:set_text(math.ceil(hp * hp_ratio * 10) .. "/" .. math.ceil(hp * 10))
  else
    local start = self._hp_bar:w() / max_w
    self._hp_bar:animate(function ()
      over(0.25, function (p)
        local f = math.lerp(start, hp_ratio, p)
        self._hp_bar:set_color(hp_ratio_to_color(f))
        self._hp_bar:set_w(max_w * f)
        self._hp_text:set_text(math.ceil(hp * f * 10) .. "/" .. math.ceil(hp * 10))
      end)
    end)
  end
end

function JokerPanel:update_exp(exp_ratio, instant)
  self._exp_bar:stop()
  exp_ratio = math.max(0, math.min(1, exp_ratio))
  local max_w = (self._panel:w() - 8)
  if instant then
    self._exp_bar:set_w(max_w * exp_ratio)
  else
    local start = self._exp_bar:w() / max_w
    self._exp_bar:animate(function ()
      over(0.5, function (p)
        local f = math.lerp(start, exp_ratio, p)
        self._exp_bar:set_w(max_w * f)
      end)
    end)
  end
end

function JokerPanel:remove()
  self._hp_bar:stop()
  self._exp_bar:stop()
  self._parent_panel:remove(self._panel)
end