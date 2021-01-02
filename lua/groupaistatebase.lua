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
