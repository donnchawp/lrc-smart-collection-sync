-- MenuShowConfig.lua
-- Menu handler for "Smart Collection Sync..." menu item

local LrTasks = import "LrTasks"

LrTasks.startAsyncTask(function()
    local SmartCollectionSync = require "SmartCollectionSync"
    SmartCollectionSync.showConfig()
end)
