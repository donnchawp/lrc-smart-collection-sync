-- MenuSyncNow.lua
-- Menu handler for "Sync Now" menu item

local LrTasks = import "LrTasks"

LrTasks.startAsyncTask(function()
    local SmartCollectionSync = require "SmartCollectionSync"
    SmartCollectionSync.syncNow()
end)
