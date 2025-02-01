Citizen.CreateThreadNow(function()
	local success = pcall(MySQL.scalar.await, 'SELECT 1 FROM queue_priority')

	if not success then
		MySQL.query([[CREATE TABLE `queue_priority` (
			`identifier` varchar(40) DEFAULT NULL,
			`expires_on` timestamp NULL DEFAULT current_timestamp(),
			UNIQUE(`identifier`)
		)]])
	end
end)
