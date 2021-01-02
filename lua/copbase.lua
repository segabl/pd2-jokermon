local ids_effect = Idstring("effect")
local shiny_effect = Idstring("effects/shiny")
HopLib:load_assets({
	{ ext = ids_effect, path = shiny_effect, file = ModPath .. "assets/effects/shiny.effect" }
})

function CopBase:add_shiny_effect()
	if self:has_shiny_effect() then
		return
	end
	managers.dyn_resource:load(ids_effect, shiny_effect, DynamicResourceManager.DYN_RESOURCES_PACKAGE)
	self._shiny_effect = World:effect_manager():spawn({
		effect = shiny_effect,
		parent = self._unit:get_object(Idstring("Hips")),
	})
end

function CopBase:has_shiny_effect()
	return self._shiny_effect and true
end

function CopBase:remove_shiny_effect()
	if self:has_shiny_effect() then
		World:effect_manager():kill(self._shiny_effect)
	end
end

Hooks:PostHook(CopBase, "_chk_spawn_gear", "_chk_spawn_gear_jokermon", function (self)

	math.randomseed(math.round(managers.game_play_central:get_heist_timer()) + self._unit:id() * 100)
	math.random()
	math.random()
	math.random()
	if math.random() < 1 / 512 and managers.enemy:is_enemy(self._unit) then
		self:add_shiny_effect()
	end

end)

Hooks:PreHook(CopBase, "destroy", "destroy_jokermon", CopBase.remove_shiny_effect)
