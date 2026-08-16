Constants = {
    ResourceName = 'gnsh-telecom',
    ApiVersion = '1.0',
    LogEvent = {
        CONFIG_OK = 'CONFIG_OK',
        CONFIG_INVALID = 'CONFIG_INVALID',
        RESOURCE_STARTED = 'RESOURCE_STARTED',
        RESOURCE_STOPPED = 'RESOURCE_STOPPED',
    },
    Events = {
        POSITION_UPDATE = 'gnsh-telecom:server:updatePosition',
        CONNECTION_STATE = 'gnsh-telecom:client:connectionState',
        DEBUG_OVERLAY = 'gnsh-telecom:client:debugOverlay',
        DEBUG_MESSAGE = 'gnsh-telecom:client:debugMessage',
    },
    ApiEvents = {
        CONNECTION_CHANGED = 'gnsh-telecom:connectionChanged',
        SIGNAL_CHANGED = 'gnsh-telecom:signalChanged',
        SIGNAL_LEVEL_CHANGED = 'gnsh-telecom:signalLevelChanged',
        TOWER_CHANGED = 'gnsh-telecom:towerChanged',
        NETWORK_TYPE_CHANGED = 'gnsh-telecom:networkTypeChanged',
        SERVICE_CHANGED = 'gnsh-telecom:serviceChanged',
    },
}
