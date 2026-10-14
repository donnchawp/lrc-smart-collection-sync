-- SmartCollectionSync.lua
-- Main entry point for the Smart Collection Sync plugin

local LrTasks = import "LrTasks"
local LrDialogs = import "LrDialogs"
local LrApplicationView = import "LrApplicationView"

local SyncEngine = require "SyncEngine"
local ConfigDialog = require "ConfigDialog"
local ProgressDialog = require "ProgressDialog"
local Preferences = require "Preferences"

local SmartCollectionSync = {}

-- Merge sizes measured in a sync into the stored sizes. Assign a new table:
-- LrPrefs only saves values assigned to a top-level key.
local function recordSizes(sizes)
    local stored = {}
    for id, size in pairs(Preferences.get("collectionSizes") or {}) do
        stored[id] = size
    end
    for id, size in pairs(sizes or {}) do
        stored[id] = size
    end
    Preferences.set("collectionSizes", stored)
end

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

        local results = SyncEngine.runFullSync(selectedIds, destSetName,
            function(name, current, total)
                progress:update("Syncing: " .. name, current, total)
                return not progress:isCanceled()
            end)

        progress:done()

        -- Sync Now syncs large collections too, so it refreshes their sizes
        recordSizes(results.sizes)
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

    local function stopRequested()
        return Preferences.get("_stopRequested") == true
    end

    LrTasks.startAsyncTask(function()
        while Preferences.get("autoSyncEnabled") and not stopRequested() do
            local selectedIds = Preferences.getSelectedIds()
            local destSetName = Preferences.get("destinationSetName")
            local interval = Preferences.get("syncInterval") or 30

            -- Check if we should skip sync in Develop module
            local currentModule = LrApplicationView.getCurrentModuleName()
            local inDevelop = (currentModule == "develop")
            local noSyncInDevelop = Preferences.get("noSyncInDevelop")
            local skipSync = inDevelop and noSyncInDevelop

            if #selectedIds > 0 and not skipSync then
                local results = SyncEngine.runFullSync(selectedIds, destSetName,
                    function() return not stopRequested() end,
                    { skipLarge = true, knownSizes = Preferences.get("collectionSizes") })
                recordSizes(results.sizes)
                Preferences.set("lastSyncTime", os.time())
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
    -- Clear stale flags from previous session/crash
    Preferences.set("_backgroundSyncRunning", false)
    Preferences.set("_stopRequested", false)

    if Preferences.get("autoSyncEnabled") then
        SmartCollectionSync.startBackgroundSync()
    end
end

-- Plugin shutdown (called on LrShutdownPlugin)
-- Stops a running pass at the next collection so quitting isn't held up.
-- Leaves autoSyncEnabled alone so auto-sync resumes on the next launch.
function SmartCollectionSync.shutdown()
    Preferences.set("_stopRequested", true)
end

return SmartCollectionSync
