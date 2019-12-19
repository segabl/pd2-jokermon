local change_state_original = GameStateMachine.change_state
function GameStateMachine:change_state(state, ...)
  -- Save Jokermon on a state change from ingame to not ingame
  if self:current_state_name():match("^ingame") and not state:name():match("^ingame") then
    Jokermon:sort_jokers()
    Jokermon:save(true)
  end
  return change_state_original(self, state, ...)
end