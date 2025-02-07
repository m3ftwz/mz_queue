AddEventHandler('esx:setGroup', function(source, group, lastGroup)
    if not source or (group ~= 'admin' and lastGroup ~= 'admin') then
        return
    end

    SetPrioritiesLists()
end)
