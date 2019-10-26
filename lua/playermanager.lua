local spawned_player_original = PlayerManager.spawned_player
function PlayerManager:spawned_player(id, unit)
  spawned_player_original(self, id, unit)
  if id == 1 and Jokermon.settings.spawn_mode ~= 1 then
    local max_count = self:upgrade_value("player", "convert_enemies_max_minions", 0)
    DelayedCalls:Add("SpawnJokermon", 0.25, function ()
      Jokermon:send_out_joker(max_count)
    end)
  end
end