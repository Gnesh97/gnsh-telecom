fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'gnsh'
description 'Standalone server-authoritative GSM and telecom infrastructure'
version '0.1.0'

shared_scripts {
    'shared/config.lua',
    'shared/constants.lua',
    'shared/enums.lua',
    'shared/technologies.lua',
    'shared/feature_flags.lua',
    'shared/utils.lua',
    'shared/service_policy.lua',
    'locales/en.lua',
    'locales/tr.lua',
}

server_scripts {
    'server/towers/validation.lua',
    'server/towers/state.lua',
    'server/towers/registry.lua',
    'server/towers/spatial_index.lua',
    'server/network/signal.lua',
    'server/network/coverage.lua',
    'server/network/selection.lua',
    'server/network/capacity.lua',
    'server/network/services.lua',
    'server/network/connections.lua',
    'server/api.lua',
    'server/failures/types.lua',
    'server/failures/engine.lua',
    'server/failures/scheduler.lua',
    'server/logging.lua',
    'server/persistence/serializers.lua',
    'server/persistence/adapters/memory.lua',
    'server/persistence/adapters/oxmysql.lua',
    'server/persistence/repository.lua',
    'server/persistence/migrations.lua',
    'server/persistence/facade.lua',
    'server/security/txadmin.lua',
    'server/security/permissions.lua',
    'server/security/audit.lua',
    'server/debug.lua',
    'server/bootstrap.lua',
    'bridges/phones/generic.lua',
    'bridges/phones/lbphone.lua',
    'bridges/phones/npwd.lua',
    'bridges/phones/qs.lua',
    'bridges/phones/custom.lua',
}

client_scripts {
    'client/bootstrap.lua',
    'client/environment.lua',
    'client/state.lua',
    'client/debug.lua',
}
