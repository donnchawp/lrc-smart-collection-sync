-- ShutdownPlugin.lua
-- Called when plugin is unloaded

local SmartCollectionSync = require "SmartCollectionSync"
SmartCollectionSync.shutdown()
