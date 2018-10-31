local _set_converted_police_original = GroupAIStateBase._set_converted_police
function GroupAIStateBase:_set_converted_police(u_key, unit, ...)
  
  if not unit then
    local minion_unit = self._converted_police[u_key]

    if not minion_unit then
      return
    end

    local key = minion_unit:base()._jokermon_key
    local joker = key and Jokermon.settings.jokers[key]
    if joker then
      joker.hp_ratio = minion_unit:character_damage()._health_ratio
      if joker.hp_ratio <= 0 then
        managers.chat:_receive_message(1, "JOKERMON", joker.name .. " fainted!", tweak_data.system_chat_color)
      end
      Jokermon:save()
      Jokermon:remove_panel(key)
      Jokermon.units[key] = nil
    end
  end

  return _set_converted_police_original(self, u_key, unit, ...)
end