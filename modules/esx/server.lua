local esx = {
    resource = 'es_extended',
    enabled = GetResourceState('es_extended') == 'started',
}

function esx.loadAdmins()
    if not esx.enabled then
        return {}
    end

    return MySQL.query.await("SELECT `identifier` FROM `users` WHERE `group` = 'admin'")
end

return esx
