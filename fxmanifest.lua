fx_version 'cerulean'
lua54 'yes'
game 'gta5'

name         'pickle_throwables'
version      '1.0.2'
description  'A multi-framework and standalone throwing script, great for football, soccer and other sports.'
author       'Pickle Mods'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'core/shared.lua',
    "locales/locale.lua",
    "locales/translations/*.lua",
    'modules/**/shared.lua',
}

server_scripts {
    'bridge/**/server.lua',
    'modules/**/server.lua',
}

client_scripts {
    'core/client.lua',
    'bridge/**/client.lua',
    'modules/**/client.lua',
}
