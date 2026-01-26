-- SmartCollectionSync.lua
-- Main entry point for the Smart Collection Sync plugin

local LrTasks = import "LrTasks"
local LrApplicationView = import "LrApplicationView"

local SyncEngine = require "SyncEngine"
local ConfigDialog = require "ConfigDialog"
local ProgressDialog = require "ProgressDialog"
local Preferences = require "Preferences"

local SmartCollectionSync = {}

-- Show configuration dialog
function SmartCollectionSync.showConfig()
    local result = ConfigDialog.showDialog()

    -- Restart background sync if settings changed
    if Preferences.get("autoSyncEnabled") then
        SmartCollectionSync.startBackgroundSync()
    else
        SmartCollectionSync.stopBackgroundSync()
    end

    -- If user clicked "Sync Now" button in dialog
    if result == "other" then
        SmartCollectionSync.syncNow()
    end
end

-- Manual sync with progress dialog
function SmartCollectionSync.syncNow()
    LrTasks.startAsyncTask(function()
        local selectedIds = Preferences.getSelectedIds()
        local destSetName = Preferences.get("destinationSetName")

        local progress = ProgressDialog.create("Syncing Smart Collections")

        if #selectedIds == 0 then
            progress:update("Cleaning up...", 0, 1)
        end

        SyncEngine.runFullSync(selectedIds, destSetName,
            function(name, current, total)
                progress:update("Syncing: " .. name, current, total)
                return not progress:isCanceled()
            end)

        progress:done()
        Preferences.set("lastSyncTime", os.time())
    end)
end

-- Start background sync task
function SmartCollectionSync.startBackgroundSync()
    -- Just start a new task - the while loop will handle duplicates gracefully
    -- since they all check the same autoSyncEnabled flag
    LrTasks.startAsyncTask(function()
        while Preferences.get("autoSyncEnabled") do
            local selectedIds = Preferences.getSelectedIds()
            local destSetName = Preferences.get("destinationSetName")
            local interval = Preferences.get("syncInterval") or 30

            -- Check if we should skip sync in Develop module
            local currentModule = LrApplicationView.getCurrentModuleName()
            local inDevelop = (currentModule == "develop")
            local noSyncInDevelop = Preferences.get("noSyncInDevelop")
            local skipSync = inDevelop and noSyncInDevelop

            if #selectedIds > 0 and not skipSync then
                pcall(function()
                    SyncEngine.runFullSync(selectedIds, destSetName, nil)
                    Preferences.set("lastSyncTime", os.time())
                end)
            end

            LrTasks.sleep(interval)
        end
    end)
end

-- Stop background sync
function SmartCollectionSync.stopBackgroundSync()
    Preferences.set("autoSyncEnabled", false)
    -- Task will exit on next loop iteration when it checks autoSyncEnabled
end

-- Plugin initialization (called on LrInitPlugin)
function SmartCollectionSync.init()
    if Preferences.get("autoSyncEnabled") then
        SmartCollectionSync.startBackgroundSync()
    end
end

-- Plugin shutdown (called on LrShutdownPlugin)
function SmartCollectionSync.shutdown()
    SmartCollectionSync.stopBackgroundSync()
end

return SmartCollectionSync
