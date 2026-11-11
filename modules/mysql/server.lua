local schemaReady = false

function EnsureQueueSchema()
    if schemaReady then
        return
    end

    MySQL.ready.await()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `queue_priority` (
        `identifier` varchar(40) DEFAULT NULL,
        `expires_on` timestamp NULL DEFAULT current_timestamp(),
        UNIQUE(`identifier`)
    )]])
    schemaReady = true
end
