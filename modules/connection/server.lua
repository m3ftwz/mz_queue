local esx = require 'modules.esx.server'
local connectqueue = Queue()
local maxclients = GetConvarInt('sv_maxclients', 48)

local connectedclients, connectingclients = { count = 0 }, { count = 0 }
local queuedclients, licensesBySource = {}, {}
local priorities, admins, adminOverrides = {}, {}, {}
local prioritiesReady = false
local refreshVersion, arrivalOrder = 0, 0

local function normalizeIdentifier(identifier)
    if type(identifier) ~= 'string' or identifier == '' then
        return nil
    end

    local license = identifier:match('^[^:]+:(.*)$') or identifier
    return license ~= '' and license or nil
end

local function getQueueLicense(playerSource)
    return normalizeIdentifier(GetPlayerIdentifierByType(playerSource, 'license'))
end

local function getPriority(player)
    if player.aceAdmin or admins[player.license] then
        return 1
    end

    return priorities[player.license] and 2 or 3
end

local function sortQueue()
    for i = 1, #connectqueue do
        local player = connectqueue[i]
        player.aceAdmin = IsPlayerAceAllowed(player.source, 'mz_queue.admin')
    end

    table.sort(connectqueue, function(a, b)
        local aPriority, bPriority = getPriority(a), getPriority(b)
        if aPriority == bPriority then
            return a.order < b.order
        end

        return aPriority < bPriority
    end)
end

function RemoveFromConnectingClients(license)
    local player = connectingclients[license]
    if player then
        licensesBySource[player.source] = nil
        connectingclients[license] = nil
        connectingclients.count = connectingclients.count - 1
    end
end

local function reserveSlot(player)
    connectingclients[player.license] = player
    connectingclients.count = connectingclients.count + 1
end

function ResetQueueAdmins()
    -- Invalidate any refresh that is still loading data from a stopped ESX resource.
    refreshVersion = refreshVersion + 1
    admins, adminOverrides = {}, {}
    sortQueue()
end

function SetQueueAdmin(playerSource, isAdmin)
    local license = getQueueLicense(playerSource)
    if not license then
        return
    end

    -- Keep role changes authoritative until ESX has saved them to the database.
    adminOverrides[license] = isAdmin
    admins[license] = isAdmin or nil
    sortQueue()
end

function SetPrioritiesLists()
    refreshVersion = refreshVersion + 1
    local version = refreshVersion

    local success, newPriorities, newAdmins = pcall(function()
        EnsureQueueSchema()
        MySQL.update.await('DELETE FROM `queue_priority` WHERE `expires_on` < NOW()')

        local priorityRows = MySQL.query.await('SELECT `identifier` FROM `queue_priority`')
        local adminRows = esx.loadAdmins()
        assert(type(priorityRows) == 'table' and type(adminRows) == 'table', 'Could not load queue priorities')

        local loadedPriorities, loadedAdmins = {}, {}
        for i = 1, #priorityRows do
            local license = normalizeIdentifier(priorityRows[i].identifier)
            if license then
                loadedPriorities[license] = true
            end
        end

        for i = 1, #adminRows do
            local license = normalizeIdentifier(adminRows[i].identifier)
            if license then
                loadedAdmins[license] = true
            end
        end

        return loadedPriorities, loadedAdmins
    end)

    if not success then
        print(('^1[QUEUE]: Could not refresh priorities: %s^0'):format(newPriorities))
        return false
    end

    -- A slower refresh must not overwrite the result of a newer request.
    if version ~= refreshVersion then
        return false
    end

    for license, isAdmin in pairs(adminOverrides) do
        if (newAdmins[license] == true) == isAdmin then
            adminOverrides[license] = nil
        end
        newAdmins[license] = isAdmin or nil
    end

    priorities, admins = newPriorities, newAdmins
    prioritiesReady = true
    sortQueue()
    return true
end

function QueueCard(deferrals, name, position, size)
    local queuemessage = position == 1 and 'queue_first_position' or 'queue_position'
    deferrals.presentCard({
        type = 'AdaptiveCard',
        ['$schema'] = 'http://adaptivecards.io/schemas/adaptive-card.json',
        version = '1.5',
        body = {
            {
                type = 'TextBlock',
                text = locale('queue_title'),
                wrap = true,
                fontType = 'Default',
                style = 'heading',
                size = 'ExtraLarge',
            },
            {
                type = 'TextBlock',
                text = locale('queue_server_full', name),
                wrap = true,
                size = 'Medium',
            },
            {
                type = 'TextBlock',
                text = locale(queuemessage, position, size),
                wrap = true,
                size = 'Medium',
            },
            {
                type = 'TextBlock',
                text = locale('queue_tired_of_waiting', GetConvar('discord', 'https://discord.gg/')),
                wrap = true,
                spacing = 'Medium',
            },
        },
    })
end

Citizen.CreateThreadNow(function()
    while true do
        for license, player in pairs(connectingclients) do
            if license ~= 'count' and GetPlayerPing(player.source) == 0 then
                RemoveFromConnectingClients(license)
            end
        end

        if prioritiesReady and connectqueue:getSize() > 0 then
            -- ACE permissions can change while a player is waiting.
            sortQueue()
            if connectedclients.count + connectingclients.count < maxclients then
                local player = connectqueue:connect()
                queuedclients[player.license] = nil

                if GetPlayerPing(player.source) ~= 0 then
                    -- Reserve before the deferred connection resumes or another player arrives.
                    reserveSlot(player)
                end
            end
        end

        Wait(1000)
    end
end)

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local license = getQueueLicense(source)
    if not license then
        setKickReason('Invalid license, please restart FiveM and retry.')
        CancelEvent()
        return
    end

    arrivalOrder = arrivalOrder + 1
    local player = {
        source = source,
        name = name,
        license = license,
        order = arrivalOrder,
    }

    deferrals.defer()
    Wait(50)
    deferrals.update('Handshaking with the server...')
    Wait(0)

    if connectedclients[license] or connectingclients[license] or queuedclients[license] then
        deferrals.done('A connection with this license is already in progress.')
        return
    end

    -- Track pending connections too, including those waiting for initialization.
    queuedclients[license] = player
    licensesBySource[player.source] = license
    while not prioritiesReady do
        if GetPlayerPing(player.source) == 0 then
            queuedclients[license], licensesBySource[player.source] = nil, nil
            deferrals.done('Connection lost')
            return
        end
        Wait(100)
    end

    if GetPlayerPing(player.source) == 0 then
        queuedclients[license], licensesBySource[player.source] = nil, nil
        deferrals.done('Connection lost')
        return
    end

    if connectqueue:getSize() > 0 or connectedclients.count + connectingclients.count >= maxclients then
        connectqueue:insert(player)
        sortQueue()
        print(('[^6QUEUE^0]: %s^0 queued at position #%d'):format(player.name, connectqueue:getPosition(player)))

        while connectqueue:getPosition(player) do
            if GetPlayerPing(player.source) == 0 then
                connectqueue:remove(player)
                queuedclients[license], licensesBySource[player.source] = nil, nil
                print(('[^6QUEUE^0]: %s^0 removed from queue: connection lost'):format(player.name))
                deferrals.done('Connection lost')
                return
            end

            QueueCard(deferrals, name, connectqueue:getPosition(player), connectqueue:getSize())
            Wait(500)
        end
    else
        queuedclients[license] = nil
        reserveSlot(player)
    end

    Wait(0)
    if connectingclients[license] ~= player then
        licensesBySource[player.source] = nil
        deferrals.done('Connection lost')
        return
    end

    deferrals.done()
    print(('[^6QUEUE^0]: %s^0 joined the server'):format(player.name))
end)

RegisterNetEvent('mz_queue:playerConnected', function()
    local playerSource = source
    local license = getQueueLicense(playerSource)
    if not license then
        return
    end

    if not connectedclients[license] then
        connectedclients[license] = playerSource
        connectedclients.count = connectedclients.count + 1
    end

    RemoveFromConnectingClients(license)
    licensesBySource[playerSource] = license
end)

AddEventHandler('playerDropped', function()
    local playerSource = source
    local license = licensesBySource[playerSource] or getQueueLicense(playerSource)
    licensesBySource[playerSource] = nil
    if not license then
        return
    end

    if connectedclients[license] == playerSource then
        connectedclients[license] = nil
        connectedclients.count = connectedclients.count - 1
    end

    local queued = queuedclients[license]
    if queued and queued.source == playerSource then
        connectqueue:remove(queued)
        queuedclients[license] = nil
    end

    local connecting = connectingclients[license]
    if connecting and connecting.source == playerSource then
        RemoveFromConnectingClients(license)
    end
end)
