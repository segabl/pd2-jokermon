Hooks:PreHook(GroupAIStateBase, "unregister_criminal", "unregister_criminal_jokermon", function (self, unit)
	-- Manually delete minions so they are saved properly instead of being killed
	local record = self._criminals[unit:key()]
	if self._is_server and record.minions then
		for _, minion_data in pairs(record.minions) do
			World:delete_unit(minion_data.unit)
		end
		record.minions = nil
	end
end)

Hooks:PostHook(GroupAIStateBase, "on_enemy_weapons_hot", "on_enemy_weapons_hot_jokermon", function (self)
	if Jokermon.settings.spawn_mode ~= 1 then
		Jokermon:send_out_joker(managers.player:upgrade_value("player", "convert_enemies_max_minions", 0))
	end
end)
