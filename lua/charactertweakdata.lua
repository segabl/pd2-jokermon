Hooks:PostHook(CharacterTweakData, "init", "init_jokermon", function (self)
	for k, v in pairs(self) do
		if type(v) == "table" and v.HEALTH_INIT and v.weapon then
			v.jokermon_stats = {
				hp = v.HEALTH_INIT,
				exp_rate = 1.8 + (v.HEALTH_INIT - 4) / 60
			}
		end
	end
end)
