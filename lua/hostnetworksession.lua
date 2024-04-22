Hooks:PostHook(HostNetworkSession, "on_peer_sync_complete", "on_peer_sync_complete_jokermon", function (self, peer, peer_id)
	if self._local_peer ~= peer then
		LuaNetworking:SendToPeer(peer_id, "Jokermon", tostring(Jokermon.mod_instance:GetVersion()))
	end
end)
