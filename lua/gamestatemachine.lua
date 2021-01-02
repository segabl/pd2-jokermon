Hooks:PreHook(GameStateMachine, "change_state", "change_state_jokermon", function (self, state)
	if self:current_state_name():match("^ingame") and not state:name():match("^ingame") then
		Jokermon:sort_jokers()
		Jokermon:save(true)
	end
end)
