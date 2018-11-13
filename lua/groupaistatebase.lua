local unregister_criminal_original = GroupAIStateBase.unregister_criminal
function GroupAIStateBase:unregister_criminal(unit, ...)
  -- Manually delete minions so they are saved properly instead of being killed
  local player_key = unit:key()
  local record = self._criminals[player_key]
  if self._is_server and record.minions then
    for minion_key, minion_data in pairs(clone(record.minions)) do
      World:delete_unit(minion_data.unit)
    end
  end
  return unregister_criminal_original(self, unit, ...)
end