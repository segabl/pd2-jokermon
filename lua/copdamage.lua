local destroy_original = CopDamage.destroy
function CopDamage:destroy(...)
  local u_key = self._unit:base()._jokermon_key
  local jokermon = u_key and Jokermon.settings.jokers[u_key]
  if jokermon then
    local info = HopLib:unit_info_manager():get_info(self._unit)
    jokermon.hp = self._health
    Jokermon:save()
  end
  return destroy_original(...)
end