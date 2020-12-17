Hooks:PostHook(PlayerManager, "spawned_player", "spawned_player_jokermon", function (self, id, unit)
  if id == 1 and Jokermon.settings.spawn_mode ~= 1 then
    local max_count = self:upgrade_value("player", "convert_enemies_max_minions", 0)
    DelayedCalls:Add("SpawnJokermon", 0.25, function ()
      Jokermon:send_out_joker(max_count)
    end)
  end
end)
