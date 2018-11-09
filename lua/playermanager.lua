local spawned_player_original = PlayerManager.spawned_player
function PlayerManager:spawned_player(id, unit)
  spawned_player_original(self, id, unit)
  if id == 1 then
    DelayedCalls:Add("SpawnJokermon", 1, function ()
      local max_jokers = self:upgrade_value("player", "convert_enemies_max_minions", 0)
      if max_jokers <= 0 then
        return
      end
      -- Try spawning Jokers
      for i, joker in ipairs(Jokermon.settings.jokers) do
        if max_jokers <= 0 then
          return
        end
        if Jokermon:spawn(joker, i, managers.player:local_player()) then
          max_jokers = max_jokers - 1
        end
      end
      -- Remove queued keys after 2 seconds so future converts don't get mixed up in case the server didn't spawn jokers for some reason
      DelayedCalls:Add("ClearJokermonQueuedKeys", 2, function ()
        Jokermon._queued_keys = {}
      end)
    end)
  end
end