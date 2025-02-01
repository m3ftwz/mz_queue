require 'modules.mysql.server'
require 'modules.queue.server'
require 'modules.connection.server'
require 'modules.commands.server'

if GetConvar('mz_queue:versioncheck', 'true') == 'true' then
	lib.versionCheck('m3ftwz/mz_queue')
end

local hardcap = GetResourceState('hardcap')
if hardcap ~= 'missing' and (hardcap == 'started' or hardcap == 'starting') then
	StopResource("hardcap")
	print("[^6QUEUE^0]: ^1hardcap^0 resource was stopped due to incompatibility issues.")
end

AddEventHandler("onResourceStarting", function(resource)
	if resource == "hardcap" then
		CancelEvent()
		print("[^6QUEUE^0]: ^1hardcap^0 resource was stopped due to incompatibility issues with the queue system")
		return
	end
end)

lib.cron.new('0 * * * *', function()
	SetPrioritiesLists()
	print("[^6QUEUE^0]:^2 Successfully auto-refreshed priorities queues^0")
end)

SetTimeout(5000, function()
	SetPrioritiesLists()
end)
