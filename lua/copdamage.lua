local destroy_original = CopDamage.destroy
function CopDamage:destroy(...)
  local key = self._unit:base()._jokermon_key
  if key then
    local joker = Jokermon.settings.jokers[key]
    if joker then
      local info = HopLib:unit_info_manager():get_info(self._unit)
      joker.hp_ratio = self._health_ratio
      Jokermon:save()
      Jokermon:remove_panel(key)
      Jokermon.units[key] = nil
    end
  end
  return destroy_original(...)
end