local esx = require 'modules.esx.server'

AddEventHandler('esx:setGroup', function(source, group, lastGroup)
    if not esx.enabled or not source or (group ~= 'admin' and lastGroup ~= 'admin') then
        return
    end

    SetQueueAdmin(source, group == 'admin')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == esx.resource then
        esx.enabled = true
        SetPrioritiesLists()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == esx.resource then
        esx.enabled = false
        ResetQueueAdmins()
    end
end)
