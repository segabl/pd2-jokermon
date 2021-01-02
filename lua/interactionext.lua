Hooks:PreHook(IntimitateInteractionExt, "interact", "interact_jokermon", function (self)
	if self.tweak_data == "hostage_convert"  then
		-- Remove queued keys in case the server didn't spawn all jokers for some reason
		Jokermon._queued_keys = {}
	end
end)

local _interact_blocked_original = IntimitateInteractionExt._interact_blocked
function IntimitateInteractionExt:_interact_blocked(player, ...)
	-- Refuse cop convert if nuzlocke mode is on and the max amount is reached or box is full
	if self.tweak_data == "hostage_convert" then
		if Jokermon.settings.nuzlocke and Jokermon._jokers_added >= managers.player:upgrade_value("player", "convert_enemies_max_minions", 0) then
			Jokermon:display_message("Jokermon_message_nuzlocke", nil, true)
			return true
		end
		if #Jokermon.jokers >= Jokermon.MAX_JOKERS and not Jokermon.settings.temporary then
			Jokermon:display_message("Jokermon_message_box_full", nil, true)
			return true
		end
	end
	return _interact_blocked_original(self, player, ...)
end
