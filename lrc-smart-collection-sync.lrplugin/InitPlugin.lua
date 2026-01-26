-- InitPlugin.lua
-- Called when plugin is loaded (requires LrMetadataProvider to force load at startup)

local LrTasks = import "LrTasks"

LrTasks.startAsyncTask(function()
    LrTasks.sleep(2)  -- Wait for Lightroom to fully initialize
    local SmartCollectionSync = require "SmartCollectionSync"
    SmartCollectionSync.init()
end)
