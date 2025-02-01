local connectqueue = Queue()
local maxclients = GetConvarInt('sv_maxclients', 48)

local connectedclients, connectingclients = { count = 0 }, { count = 0 }
local priorities, admins = { count = 0 }, { count = 0 }

function RemoveFromConnectingClients(license)
	if connectingclients[license] then
		connectingclients[license] = nil
		connectingclients.count -= 1
	end
end

function RemoveFromPrioritiesLists(license)
	if admins[license] then
		admins[license] = nil
		admins.count -= 1
	end

	if priorities[license] then
		priorities[license] = nil
		priorities.count -= 1
	end
end

function SetPrioritiesLists()
	priorities.list, admins.list = {}, {}

	local Queries = {
		GET_PRIORITIES = "SELECT `identifier` FROM `queue_priority`",
		GET_ADMINS = "SELECT `identifier` FROM `users` WHERE `group` = 'admin'",
		DELETE_EXPIRED_PRIORITIES = "DELETE FROM `queue_priority` WHERE expires_on < NOW()"
	}

	MySQL.query.await(Queries['DELETE_EXPIRED_PRIORITIES'])

	local priorities_query = MySQL.query.await(Queries['GET_PRIORITIES'])
	if priorities_query then
		for i = 1, #priorities_query do
			priorities.list[priorities_query[i].identifier] = true
		end
	end

	local admins_query = MySQL.query.await(Queries['GET_ADMINS'])
	if admins_query then
		for i = 1, #admins_query do
			local license = admins_query[i].identifier
			admins.list[string.sub(license, string.find(license, ':') + 1, #license)] = true
		end
	end
end

function QueueCard(deferrals, name, position, size)
	local queuemessage = position == 1 and "queue_first_position" or "queue_position"
	deferrals.presentCard([==[{
		"type": "AdaptiveCard",
		"$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
		"version": "1.5",
		"body": [
			{
				"type": "TextBlock",
				"text": "]==] .. locale("queue_title") .. [==[",
				"wrap": true,
				"fontType": "Default",
				"style": "heading",
				"size": "ExtraLarge"
			},
			{
				"type": "TextBlock",
				"text": "]==] .. locale("queue_server_full", name) .. [==[",
				"wrap": true,
				"size": "Medium"
			},
			{
				"type": "TextBlock",
				"text": "]==] .. locale(queuemessage, position, size) .. [==[",
				"wrap": true,
				"size": "Medium"
			},
			{
				"type": "TextBlock",
				"text": "]==] .. locale("queue_tired_of_waiting", GetConvar('discord', 'https://discord.gg/')) .. [==[",
				"wrap": true,
				"spacing": "Medium"
			}
			]
	}]==])
end

Citizen.CreateThreadNow(function()
	while true do
		for k, player in pairs(connectingclients) do
			if k ~= 'count' then
				if GetPlayerPing(player.source) == 0 then
					connectingclients[k] = nil
					connectingclients.count -= 1
				end
			end
		end

		if connectqueue:getSize() > 0 and connectedclients.count + connectingclients.count < maxclients then
			local player = connectqueue:connect()
			RemoveFromPrioritiesLists(player.license)
		end

		Wait(1000)
	end
end)

AddEventHandler("playerConnecting", function (name, setKickReason, deferrals)
	local license = GetPlayerIdentifierByType(source, 'license'):gsub('license:', '')

	if not license then
		CancelEvent()
        setKickReason("Invalid license, please restart FiveM and retry.")
		return
	end

	local player = {
		source = source,
		name = name,
		license = license,
		timeout = 0,
	}

	deferrals.defer()

	Wait(50)

	deferrals.update('Handshaking with the server...')

	if not connectingclients[player.license] then
		if connectedclients.count + connectingclients.count >= maxclients then
			if admins.list[player.license] then
				if not admins[player.license] then
					admins[player.license] = true
					admins.count += 1
				end
				connectqueue:insert(player, admins.count)
				print(("[^6QUEUE^0]: %s^0 queued at position #%d (admin)"):format(player.name, admins.count))
			elseif priorities.list[player.license] then
				if not priorities[player.license] then
					priorities[player.license] = true
					priorities.count += 1
				end
				connectqueue:insert(player, admins.count + priorities.count)
				print(("[^6QUEUE^0]: %s^0 queued at position #%d (priority)"):format(player.name, admins.count + priorities.count))
			else
				connectqueue:insert(player)
				print(("[^6QUEUE^0]: %s^0 queued at position #%d"):format(player.name, connectqueue:getSize()))
			end

			while connectqueue:getPosition(player) do
				if GetPlayerPing(player.source) == 0 then
					connectqueue:remove(player)
					RemoveFromPrioritiesLists(player.license)
					print(("[^6QUEUE^0]: %s^0 removed from queue: connection lost"):format(player.name))
					deferrals.done("Connection lost")
					return
				end

				QueueCard(deferrals, name, connectqueue:getPosition(player), connectqueue:getSize())

				Wait(500)
			end
		end
		connectingclients.count += 1
	end
	connectingclients[player.license] = player

	Wait(0)

	deferrals.done()

	print(("[^6QUEUE^0]: %s^0 joined the server"):format(player.name))
end)

RegisterNetEvent("mz_queue:playerConnected", function()
	local license = GetPlayerIdentifierByType(source, 'license'):gsub('license:', '')

	if not connectedclients[license] then
		connectedclients[license] = true
		connectedclients.count += 1
	end

	RemoveFromConnectingClients(license)
end)

AddEventHandler("playerDropped", function()
	local license = GetPlayerIdentifierByType(source, 'license'):gsub('license:', '')

	if connectedclients[license] then
		connectedclients[license] = nil
		connectedclients.count -= 1
	end

	RemoveFromConnectingClients(license)
end)
