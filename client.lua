CreateThread(function()
	while true do
		Wait(0)
		if NetworkIsSessionStarted() then
			TriggerServerEvent("mz_queue:playerConnected")
			return
		end
	end
end)
