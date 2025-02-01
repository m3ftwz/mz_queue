lib.addCommand('addpriority', {
    help = locale('commands_queue_add'),
    params = {
        {
            name = 'license',
            type = 'string',
            help = locale('commands_params_license'),
		},
        {
            name = 'queue_timespan',
			type = 'number',
            help = locale('commands_params_queue_timespan'),
        }
    },
    restricted = 'group.admin'
}, function(source, args)
	if args.queue_timespan > 0 then
		MySQL.insert.await('INSERT INTO `queue_priority` (`identifier`, `expires_on`) VALUES (?, NOW() + INTERVAL ? DAY) ON DUPLICATE KEY UPDATE `expires_on` = VALUES(`expires_on`)',
			{ args.license, args.queue_timespan }
		)

		if source ~= 0 then
			TriggerClientEvent('ox_lib:notify', source, { description = locale('commands_notif_queue_add', args.queue_timespan, args.license) })
		end

		SetPrioritiesLists()

		local name = source ~= 0 and GetPlayerName(source) or 'console'
		lib.logger(source, 'admin', ('%s added queue priority to %s for %d day(s)'):format(name, args.license, args.queue_timespan))
	else
		if source ~= 0 then
			TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = locale('commands_notif_queue_add_invalid_timespan') })
		end
	end
end)

lib.addCommand('removepriority', {
    help = locale('commands_queue_remove'),
    params = {
        {
            name = 'license',
            type = 'string',
            help = locale('commands_params_license'),
		}
    },
    restricted = 'group.admin'
}, function(source, args)
	local result = MySQL.query.await('DELETE FROM `queue_priority` WHERE `identifier` = ?', { args.license })
	if result and #result > 0 then
		if source ~= 0 then
			TriggerClientEvent('ox_lib:notify', source, { description = locale('commands_notif_queue_remove', timespan, args.license) })
		end

		SetPrioritiesLists()

		local name = source ~= 0 and GetPlayerName(source) or 'console'
		lib.logger(source, 'admin', ('%s removed queue priority from %s'):format(name, args.license))
	else
		if source ~= 0 then
			TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = locale('commands_notif_queue_remove_not_found', args.license) })
		end
	end
end)
