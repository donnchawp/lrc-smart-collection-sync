-- ShutdownPlugin.lua
-- Called when the plug-in is unloaded or reloaded through the Plug-in Manager

local SmartCollectionSync = require "SmartCollectionSync"
SmartCollectionSync.shutdown()
