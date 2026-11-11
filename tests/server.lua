-- Run from the repository root: lua tests/server.lua (Lua 5.4).
local tests = {}
local function test(name, callback)
    tests[#tests + 1] = { name = name, callback = callback }
end

local function equal(actual, expected, message)
    assert(actual == expected, ('%s: expected %s, got %s'):format(message or 'value', tostring(expected), tostring(actual)))
end

local function rows(values)
    local result = {}
    for identifier in pairs(values) do
        result[#result + 1] = { identifier = identifier }
    end
    return result
end

local function server(options)
    options = options or {}
    local e = setmetatable({
        now = 0, tasks = {}, handlers = {}, commands = {}, loaded = {},
        ids = {}, pings = {}, accepted = {}, notifications = {}, logs = {}, queries = {},
        dbPriorities = options.priorities or {}, dbAdmins = options.admins or {},
        databaseReady = options.databaseReady ~= false,
        hasUsersTable = options.esx == true,
        resourceStates = { oxmysql = 'started', es_extended = options.esxState or (options.esx and 'started' or 'missing') },
        aceAdmins = {},
    }, { __index = _G })

    function e.step(task)
        e.source = task.started and 0 or task.source
        task.started = true
        local ok, delay = coroutine.resume(task.co)
        assert(ok, delay)
        if coroutine.status(task.co) == 'dead' then
            task.finished, task.result = true, delay
        else
            task.at = e.now + math.max(delay or 0, 1)
        end
    end

    function e.spawn(callback, playerSource)
        local task = { co = coroutine.create(callback), source = playerSource or 0, at = e.now }
        e.tasks[#e.tasks + 1] = task
        e.step(task)
        return task
    end

    function e.run(untilTime)
        while true do
            local nextTask
            for _, task in ipairs(e.tasks) do
                if not task.finished and task.at <= untilTime and (not nextTask or task.at < nextTask.at) then
                    nextTask = task
                end
            end
            if not nextTask then break end
            e.now = nextTask.at
            e.step(nextTask)
        end
        e.now = untilTime
    end

    function e.emit(name, playerSource, ...)
        local args = table.pack(...)
        return e.spawn(function()
            return e.handlers[name](table.unpack(args, 1, args.n))
        end, playerSource)
    end

    function e.connect(playerSource, license, name)
        e.ids[playerSource] = license and ('license:' .. license) or nil
        local d = {}
        d.defer = function() d.lastMethodAt = e.now end
        d.update = function() d.lastMethodAt = e.now end
        d.presentCard = function(card)
            equal(type(card), 'table', 'card payload')
            d.card, d.lastMethodAt = card, e.now
        end
        d.done = function(reason)
            assert(not d.finished, 'Deferral finalized twice')
            assert(e.now > d.lastMethodAt, 'done must wait a tick after prior deferral calls')
            d.finished, d.reason = true, reason
            if not reason then
                e.accepted[#e.accepted + 1] = { source = playerSource, license = license }
            end
        end
        e.emit('playerConnecting', playerSource, name or license or 'missing', function(reason)
            d.kickReason = reason
        end, d)
        return d
    end

    function e.occupy(playerSource, license)
        e.ids[playerSource] = 'license:' .. license
        e.emit('mz_queue:playerConnected', playerSource)
    end

    function e.drop(playerSource)
        e.pings[playerSource] = 0
        e.emit('playerDropped', playerSource)
    end

    function e.refresh()
        return e.spawn(function() return e.SetPrioritiesLists() end)
    end

    function e.command(name, args)
        return e.spawn(function() return e.commands[name](99, args) end)
    end

    e.Wait = function(ms) return coroutine.yield(ms) end
    e.CreateThread = function(callback) return e.spawn(callback) end
    e.Citizen = { CreateThreadNow = e.CreateThread }
    e.GetConvarInt = function() return options.maxclients or 1 end
    e.GetConvar = function(_, default) return default end
    e.GetResourceState = function(name) return e.resourceStates[name] or 'missing' end
    e.IsPlayerAceAllowed = function(id, permission)
        equal(permission, 'mz_queue.admin', 'admin ACE permission')
        return e.aceAdmins[id] == true
    end
    e.GetPlayerIdentifierByType = function(id) return e.ids[id] end
    e.GetPlayerPing = function(id)
        if e.pings[id] ~= nil then return e.pings[id] end
        return e.ids[id] and 50 or 0
    end
    e.GetPlayerName = function(id) return 'player' .. id end
    e.CancelEvent = function() e.cancelled = true end
    e.StopResource = function() end
    e.print = function() end
    e.AddEventHandler = function(name, callback) e.handlers[name] = callback end
    e.RegisterNetEvent = e.AddEventHandler
    e.TriggerClientEvent = function(_, playerSource, notification)
        notification.source = playerSource
        e.notifications[#e.notifications + 1] = notification
    end
    e.lib = {
        addCommand = function(name, _, callback) e.commands[name] = callback end,
        logger = function(_, _, message) e.logs[#e.logs + 1] = message end,
        versionCheck = function() end,
        cron = { new = function(_, callback) e.cron = callback end },
    }
    e.locale = function(key, ...)
        local formats = {
            queue_server_full = 'Hello %s, the server is full.',
            queue_position = 'Position %d of %d',
            commands_notif_queue_add = 'Priority for %d days: %s',
            commands_notif_queue_remove = 'Removed: %s',
            commands_notif_queue_remove_not_found = 'Not found: %s',
        }
        return formats[key] and formats[key]:format(...) or key
    end

    local function query(sql, params)
        e.queries[#e.queries + 1] = sql
        local result
        if sql:find('CREATE TABLE IF NOT EXISTS', 1, true) then
            e.schemaReady = true
            result = {}
        else
            assert(e.schemaReady, 'Query ran before schema initialization')
            if sql:find('SELECT', 1, true) then
                if sql:find('FROM `users`', 1, true) then
                    assert(e.hasUsersTable, 'Standalone database has no users table')
                end
                result = sql:find('queue_priority', 1, true) and rows(e.dbPriorities) or rows(e.dbAdmins)
            elseif sql:find('INSERT INTO', 1, true) then
                e.dbPriorities[params[1]] = true
                result = 1
            elseif params then
                result = e.dbPriorities[params[1]] and 1 or 0
                e.dbPriorities[params[1]] = nil
            else
                result = 0
            end
        end
        if e.dbHook then e.dbHook(sql, result) end
        return result
    end
    e.MySQL = {
        ready = { await = function() while not e.databaseReady do e.Wait(5) end end },
        query = { await = query }, update = { await = query }, insert = { await = query },
    }
    e.require = function(name)
        if not e.loaded[name] then
            e.loaded[name] = true
            e.loaded[name] = assert(loadfile(name:gsub('%.', '/') .. '.lua', 't', e))() or true
        end
        return e.loaded[name]
    end
    for _, name in ipairs({ 'mysql', 'queue', 'connection', 'events', 'commands' }) do
        e.require('modules.' .. name .. '.server')
    end
    if options.startup then
        e.require('server')
    elseif options.initialize ~= false then
        equal(e.refresh().result, true, 'initial refresh')
    end
    return e
end

test('missing identifiers are rejected or ignored safely', function()
    local e = server()
    local d = e.connect(2, nil)
    assert(d.kickReason and e.cancelled)
    e.emit('mz_queue:playerConnected', 3)
    e.emit('playerDropped', 3)
    local empty = e.connect(3, '')
    assert(empty.kickReason)
end)

test('startup waits for database readiness and creates the schema first', function()
    local e = server({ startup = true, databaseReady = false })
    local d = e.connect(2, 'joining')
    e.run(200)
    assert(not d.finished and not d.card and not e.schemaReady)
    e.databaseReady = true
    e.run(400)
    assert(e.schemaReady and d.finished and not d.reason)
end)

test('startup retries failed priority initialization', function()
    local e = server({ initialize = false })
    e.dbHook = function(sql) if sql:find('SELECT `identifier` FROM `queue_priority`', 1, true) then error('database unavailable') end end
    e.require('server')
    local d = e.connect(2, 'joining')
    e.run(200)
    assert(not d.finished)
    e.dbHook = nil
    e.run(1200)
    assert(d.finished and not d.reason)
end)

test('bare, license-prefixed, and character-prefixed admin identifiers work', function()
    local e = server({ esx = true, admins = { bare = true, ['license:prefixed'] = true, ['char1:multi'] = true } })
    e.occupy(1, 'occupied')
    local regular = e.connect(2, 'regular')
    e.connect(3, 'bare')
    e.connect(4, 'prefixed')
    e.connect(5, 'multi')
    e.run(60)
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'bare')
    for index, license in ipairs({ 'prefixed', 'multi', 'regular' }) do
        local previous = e.accepted[#e.accepted]
        e.occupy(previous.source, previous.license)
        e.drop(previous.source)
        e.run((index + 1) * 1000 + 100)
        equal(e.accepted[index + 1].license, license)
    end
    assert(regular.finished)
end)

test('dequeue reserves capacity before a new arrival can take it', function()
    local e = server()
    e.occupy(1, 'occupied')
    local queued = e.connect(2, 'queued')
    e.run(900)
    e.drop(1)
    e.run(960)
    local newcomer = e.connect(3, 'newcomer')
    e.run(1100)
    assert(queued.finished and not queued.reason)
    assert(not newcomer.finished and newcomer.card)
    equal(#e.accepted, 1)
end)

test('new arrivals cannot bypass an existing queue when capacity opens', function()
    local e = server()
    e.occupy(1, 'occupied')
    e.connect(2, 'first')
    e.run(100)
    e.drop(1)
    local newcomer = e.connect(3, 'newcomer')
    e.run(1100)
    equal(e.accepted[1].license, 'first')
    assert(not newcomer.finished)
end)

test('queue cards preserve names containing quotes, slashes, and newlines', function()
    local e = server()
    e.occupy(1, 'occupied')
    local name = 'A "quoted" \\ name\nwith a new line'
    local d = e.connect(2, 'quoted', name)
    e.run(60)
    equal(d.card.body[2].text, 'Hello ' .. name .. ', the server is full.')
end)

test('removing priority refreshes the queue and formats the success message', function()
    local e = server({ priorities = { target = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'first')
    e.connect(3, 'target')
    e.run(60)
    e.command('removepriority', { license = 'target' })
    equal(e.notifications[1].description, 'Removed: target')
    equal(e.notifications[1].type, nil)
    equal(e.dbPriorities.target, nil)
    equal(#e.logs, 1)
    e.command('removepriority', { license = 'target' })
    equal(e.notifications[2].type, 'error')
    equal(e.notifications[2].description, 'Not found: target')
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'first')
end)

test('granting priority reorders waiting players and preserves FIFO within tiers', function()
    local e = server({ priorities = { earlier = true, later = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'earlier')
    e.connect(4, 'promoted')
    e.connect(5, 'later')
    e.run(60)
    e.command('addpriority', { license = 'promoted', queue_timespan = 2 })
    equal(e.notifications[1].description, 'Priority for 2 days: promoted')
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'earlier')
    for index, license in ipairs({ 'promoted', 'later', 'regular' }) do
        local previous = e.accepted[#e.accepted]
        e.occupy(previous.source, previous.license)
        e.drop(previous.source)
        e.run((index + 1) * 1000 + 100)
        equal(e.accepted[index + 1].license, license)
    end
end)

test('priority durations must be positive whole days', function()
    local e = server()
    for _, days in ipairs({ -1, 0, 0.5, math.huge }) do
        e.command('addpriority', { license = 'target', queue_timespan = days })
        equal(e.dbPriorities.target, nil)
        equal(e.notifications[#e.notifications].type, 'error')
    end
end)

test('in-flight refresh keeps the previous complete priority lists active', function()
    local e = server({ priorities = { target = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'target')
    e.run(60)
    e.dbPriorities.target = nil
    e.dbHook = function(sql) if sql:find('SELECT `identifier` FROM `queue_priority`', 1, true) then e.Wait(2000) end end
    local refresh = e.refresh()
    e.drop(1)
    e.run(1100)
    assert(not refresh.finished)
    equal(e.accepted[1].license, 'target')
    e.run(2100)
    equal(refresh.result, true)
end)

test('failed refresh retains previously loaded priorities', function()
    local e = server({ priorities = { target = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'target')
    e.run(60)
    e.dbPriorities.target = nil
    e.dbHook = function(sql) if sql:find('SELECT `identifier` FROM `queue_priority`', 1, true) then error('query failed') end end
    equal(e.refresh().result, false)
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'target')
end)

test('older overlapping refreshes cannot overwrite newer results', function()
    local e = server({ priorities = { target = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'target')
    e.run(60)
    local delayed = false
    e.dbHook = function(sql)
        if not delayed and sql:find('SELECT `identifier` FROM `queue_priority`', 1, true) then
            delayed = true
            e.Wait(500)
        end
    end
    local older = e.refresh()
    e.dbPriorities.target = nil
    equal(e.refresh().result, true)
    e.run(600)
    equal(older.result, false)
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'regular')
end)

test('admin promotion applies immediately and survives stale SQL refreshes', function()
    local e = server({ esx = true })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'promoted')
    e.run(60)
    e.emit('esx:setGroup', 0, 3, 'admin', 'user')
    equal(e.refresh().result, true)
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'promoted')
end)

test('admin demotion is not reverted by an unsaved database role', function()
    local e = server({ esx = true, admins = { ['char1:demoted'] = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'demoted')
    e.run(60)
    e.emit('esx:setGroup', 0, 3, 'user', 'admin')
    equal(e.refresh().result, true)
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'regular')
end)

test('role changes during a refresh survive publication of its database snapshot', function()
    local e = server({ esx = true })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'promoted')
    e.run(60)
    e.dbHook = function(sql) if sql:find('FROM `users`', 1, true) then e.Wait(200) end end
    local refresh = e.refresh()
    e.emit('esx:setGroup', 0, 3, 'admin', 'user')
    e.run(300)
    equal(refresh.result, true)
    e.drop(1)
    e.run(1100)
    equal(e.accepted[1].license, 'promoted')
end)

test('a rejected duplicate cannot remove the original queued connection', function()
    local e = server()
    e.occupy(1, 'occupied')
    local original = e.connect(2, 'same')
    local duplicate = e.connect(3, 'same')
    e.run(60)
    assert(duplicate.finished and duplicate.reason)
    e.drop(3)
    e.drop(1)
    e.run(1100)
    assert(original.finished and not original.reason)
    equal(#e.accepted, 1)
end)

test('disconnect cleanup uses the cached license when identifiers disappear', function()
    local e = server()
    e.occupy(1, 'occupied')
    e.ids[1] = nil
    e.drop(1)
    local d = e.connect(2, 'newcomer')
    e.run(100)
    assert(d.finished and not d.reason)
end)

local function countESXQueries(e)
    local count = 0
    for _, sql in ipairs(e.queries) do
        if sql:find('FROM `users`', 1, true) then
            count = count + 1
        end
    end
    return count
end

local function assertAdmissionOrder(e, expected)
    e.drop(1)
    for index, license in ipairs(expected) do
        e.run(index * 1000 + 100)
        equal(e.accepted[index].license, license, 'admission ' .. index)
        e.occupy(e.accepted[index].source, license)
        e.drop(e.accepted[index].source)
    end
end

test('standalone startup and priority commands never require an ESX users table', function()
    local e = server({ startup = true })
    local d = e.connect(2, 'standalone')
    e.run(100)
    assert(d.finished and not d.reason)
    e.command('addpriority', { license = 'target', queue_timespan = 7 })
    equal(e.dbPriorities.target, true)
    e.command('removepriority', { license = 'target' })
    equal(e.dbPriorities.target, nil)
    equal(countESXQueries(e), 0)
end)

test('installed but stopped or starting ESX does not enable admin lookups', function()
    for _, state in ipairs({ 'stopped', 'starting' }) do
        local e = server({ esx = true, esxState = state, admins = { formerAdmin = true } })
        e.occupy(1, 'occupied')
        e.connect(2, 'regular')
        e.connect(3, 'formerAdmin')
        e.run(60)
        equal(countESXQueries(e), 0)
        assertAdmissionOrder(e, { 'regular', 'formerAdmin' })
    end
end)

test('standalone servers ignore ESX role events', function()
    local e = server()
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'later')
    e.run(60)
    e.emit('esx:setGroup', 0, 3, 'admin', 'user')
    assertAdmissionOrder(e, { 'regular', 'later' })
    equal(countESXQueries(e), 0)
end)

test('standalone ACE admins join ahead of paid priorities and regular players', function()
    local e = server({ priorities = { paid = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'paid')
    e.aceAdmins[4] = true
    e.connect(4, 'aceAdmin')
    e.run(60)
    assertAdmissionOrder(e, { 'aceAdmin', 'paid', 'regular' })
    equal(countESXQueries(e), 0)
end)

test('granting ACE admin priority updates players already waiting', function()
    local e = server({ priorities = { paid = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'paid')
    local promoted = e.connect(4, 'promoted')
    e.run(60)
    e.aceAdmins[4] = true
    e.run(1100)
    equal(promoted.card.body[3].text, 'queue_first_position')
    e.drop(1)
    e.run(2100)
    equal(e.accepted[1].license, 'promoted')
end)

test('revoking ACE admin priority restores arrival order within the regular tier', function()
    local e = server()
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.aceAdmins[3] = true
    e.connect(3, 'demoted')
    e.run(60)
    e.aceAdmins[3] = nil
    assertAdmissionOrder(e, { 'regular', 'demoted' })
end)

test('ESX can start after the queue and enable admin priority without a queue restart', function()
    local e = server({ priorities = { paid = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'paid')
    e.connect(4, 'esxAdmin')
    e.run(60)
    equal(countESXQueries(e), 0)
    e.hasUsersTable = true
    e.dbAdmins['char1:esxAdmin'] = true
    e.resourceStates.es_extended = 'started'
    equal(e.emit('onResourceStart', 0, 'es_extended').result, nil)
    equal(countESXQueries(e), 1)
    assertAdmissionOrder(e, { 'esxAdmin', 'paid', 'regular' })
end)

test('stopping ESX clears its roles while keeping ACE admins and paid priorities', function()
    local e = server({ esx = true, admins = { esxAdmin = true }, priorities = { paid = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'esxAdmin')
    e.aceAdmins[4] = true
    e.connect(4, 'aceAdmin')
    e.connect(5, 'paid')
    e.run(60)
    local queriesBeforeStop = countESXQueries(e)
    e.resourceStates.es_extended = 'stopped'
    e.emit('onResourceStop', 0, 'es_extended')
    equal(e.refresh().result, true)
    equal(countESXQueries(e), queriesBeforeStop)
    assertAdmissionOrder(e, { 'aceAdmin', 'paid', 'regular', 'esxAdmin' })
end)

test('stopping ESX invalidates admin data from an in-flight refresh', function()
    local e = server({ esx = true, admins = { esxAdmin = true } })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'esxAdmin')
    e.run(60)
    e.dbHook = function(sql) if sql:find('FROM `users`', 1, true) then e.Wait(200) end end
    local refresh = e.refresh()
    e.resourceStates.es_extended = 'stopped'
    e.emit('onResourceStop', 0, 'es_extended')
    e.run(300)
    equal(refresh.result, false)
    assertAdmissionOrder(e, { 'regular', 'esxAdmin' })
end)

test('stopping ESX during a priority update still applies the saved priority', function()
    local e = server({ esx = true })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'promoted')
    e.run(60)
    local delayed = false
    e.dbHook = function(sql)
        if not delayed and sql:find('SELECT `identifier` FROM `queue_priority`', 1, true) then
            delayed = true
            e.Wait(200)
        end
    end
    local update = e.command('addpriority', { license = 'promoted', queue_timespan = 7 })
    assert(not update.finished)
    e.resourceStates.es_extended = 'stopped'
    e.hasUsersTable = false
    e.emit('onResourceStop', 0, 'es_extended')
    e.run(300)
    assert(update.finished)
    assertAdmissionOrder(e, { 'promoted', 'regular' })
end)

test('ESX restart reloads roles without reviving stale live overrides', function()
    local e = server({ esx = true })
    e.occupy(1, 'occupied')
    e.connect(2, 'regular')
    e.connect(3, 'unsavedAdmin')
    e.run(60)
    e.emit('esx:setGroup', 0, 3, 'admin', 'user')
    e.resourceStates.es_extended = 'stopped'
    e.emit('onResourceStop', 0, 'es_extended')
    e.resourceStates.es_extended = 'started'
    e.emit('onResourceStart', 0, 'es_extended')
    assertAdmissionOrder(e, { 'regular', 'unsavedAdmin' })
end)

local failures = 0
for _, entry in ipairs(tests) do
    local ok, message = pcall(entry.callback)
    if ok then
        print('PASS ' .. entry.name)
    else
        failures = failures + 1
        io.stderr:write('FAIL ' .. entry.name .. '\n' .. tostring(message) .. '\n')
    end
end
print(('%d tests, %d failures'):format(#tests, failures))
os.exit(failures == 0 and 0 or 1)
