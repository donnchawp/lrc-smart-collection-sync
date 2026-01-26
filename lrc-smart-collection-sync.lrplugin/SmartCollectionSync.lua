-- SmartCollectionSync.lua
-- Main entry point for the Smart Collection Sync plugin

local LrTasks = import "LrTasks"
local LrApplicationView = import "LrApplicationView"

local SyncEngine = require "SyncEngine"
local ConfigDialog = require "ConfigDialog"
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

-- Manual sync
function SmartCollectionSync.syncNow()
    LrTasks.startAsyncTask(function()
        local selectedIds = Preferences.getSelectedIds()
        local destSetName = Preferences.get("destinationSetName")

        SyncEngine.runFullSync(selectedIds, destSetName, nil)
        Preferences.set("lastSyncTime", os.time())
    end)
end

-- Start background sync task
function SmartCollectionSync.startBackgroundSync()
    -- Use a preference flag to track if background sync is running
    -- (module-local variables don't persist reliably across reloads)
    if Preferences.get("_backgroundSyncRunning") then
        return -- Already running
    end

    Preferences.set("_backgroundSyncRunning", true)

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
                -- Wrap in pcall to prevent errors from breaking the loop
                pcall(function()
                    SyncEngine.runFullSync(selectedIds, destSetName, nil)
                    Preferences.set("lastSyncTime", os.time())
                end)
            end

            LrTasks.sleep(interval)
        end
        Preferences.set("_backgroundSyncRunning", false)
    end)
end

-- Stop background sync
function SmartCollectionSync.stopBackgroundSync()
    Preferences.set("autoSyncEnabled", false)
    Preferences.set("_backgroundSyncRunning", false)
    -- Task will exit on next loop iteration
end

-- Plugin initialization (called on LrInitPlugin)
function SmartCollectionSync.init()
    -- Clear stale flag from previous session/crash
    Preferences.set("_backgroundSyncRunning", false)

    if Preferences.get("autoSyncEnabled") then
        SmartCollectionSync.startBackgroundSync()
    end
end

-- Plugin shutdown (called on LrShutdownPlugin)
function SmartCollectionSync.shutdown()
    SmartCollectionSync.stopBackgroundSync()
end

return SmartCollectionSync
