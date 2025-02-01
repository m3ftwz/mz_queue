fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'
name 'mz_queue'
author 'm3ftwz'
version '0.1.0'
repository 'https://github.com/m3ftwz/mz_queue'
description 'A simple and efficient queue system for FiveM servers with real-time priorities handling.'

dependencies {
	'oxmysql',
	'ox_lib',
}

ox_lib 'locale'

shared_script '@ox_lib/init.lua'

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'init.lua',
}

client_scripts 'init.lua'

files {
	'client.lua',
	'locales/*.json',
}
