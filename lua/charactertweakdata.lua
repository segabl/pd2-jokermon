local init_original = CharacterTweakData.init
function CharacterTweakData:init(...)
  init_original(self, ...)

  for k, v in pairs(self) do
    if type(v) == "table" and v.HEALTH_INIT and v.weapon then
      v.jokermon_stats = {
        base_hp = v.HEALTH_INIT,
        exp_rate = 1.5 + v.HEALTH_INIT / 16
      }
    end
  end
end