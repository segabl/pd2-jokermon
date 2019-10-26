local spawned_player_original = PlayerManager.spawned_player
function PlayerManager:spawned_player(id, unit)
  spawned_player_original(self, id, unit)
  if id == 1 and Jokermon.settings.spawn_mode ~= 1 then
    DelayedCalls:Add("SpawnJokermon", 0.25, function ()
      local max_jokers = self:upgrade_value("player", "convert_enemies_max_minions", 0)
      if max_jokers <= 0 then
        return
      end
      for i=1, max_jokers do
        Jokermon:send_out_joker()
      end
    end)
  end
end