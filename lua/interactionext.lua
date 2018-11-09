local interact_original = IntimitateInteractionExt.interact
function IntimitateInteractionExt:interact(player, ...)
  if self.tweak_data == "hostage_convert"  then
    -- Remove queued keys in case the server didn't spawn all jokers for some reason
    Jokermon._queued_keys = {}
  end
  return interact_original(self, player, ...)
end