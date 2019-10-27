local interact_original = IntimitateInteractionExt.interact
function IntimitateInteractionExt:interact(player, ...)
  if self.tweak_data == "hostage_convert"  then
    -- Remove queued keys in case the server didn't spawn all jokers for some reason
    Jokermon._queued_keys = {}
  end
  return interact_original(self, player, ...)
end

local _interact_blocked_original = IntimitateInteractionExt._interact_blocked
function IntimitateInteractionExt:_interact_blocked(player, ...)
  -- Refuse cop convert if nuzlocke mode is on and the max amount is reached or box is full
  if self.tweak_data == "hostage_convert" then
    if Jokermon.settings.nuzlocke and Jokermon._jokers_added >= managers.player:upgrade_value("player", "convert_enemies_max_minions", 0) then
      return true
    end
    if #Jokermon.jokers >= 30 then
      Jokermon:display_message(managers.localization:text("Jokermon_message_box_full"), true)
      return true
    end
  end
  return _interact_blocked_original(self, player, ...)
end