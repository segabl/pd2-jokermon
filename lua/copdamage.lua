local destroy_original = CopDamage.destroy
function CopDamage:destroy(...)
  local key = self._unit:base()._jokermon_key
  local joker = key and Jokermon.settings.jokers[key]
  if joker then
    local info = HopLib:unit_info_manager():get_info(self._unit)
    joker.hp_ratio = self._health_ratio
    Jokermon:save()
  end
  if Jokermon.panels[key] then
    Jokermon.panels[key]:remove()
    Jokermon.panels[key] = nil
    Jokermon:layout_panels()
  end
  return destroy_original(...)
end