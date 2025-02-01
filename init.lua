if not lib then
	return error('mz_queue requires the ox_lib resource.')
end

if lib.context == 'server' then
    return require 'server'
end

require 'client'
