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

-- Each background loop runs only while the stored generation is its own.
-- Starting or stopping takes a new generation, so any older loop (including
-- one left over from before a Plug-in Manager reload) exits at its next check.
-- Stored in prefs because module state doesn't survive a reload.
local function newGeneration()
    local generation = (Preferences.get("_loopGeneration") or 0) + 1
    Preferences.set("_loopGeneration", generation)
    return generation
end

-- Show configuration dialog
function SmartCollectionSync.showConfig()
    local wasEnabled = Preferences.get("autoSyncEnabled")
    local result = ConfigDialog.showDialog()

    -- A running loop reads the new settings on its next pass, so only a
    -- change to the auto-sync setting needs a start or stop
    local isEnabled = Preferences.get("autoSyncEnabled")
    if isEnabled and not wasEnabled then
        SmartCollectionSync.startBackgroundSync()
    elseif wasEnabled and not isEnabled then
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
        Preferences.recordCollectionSizes(results.sizes)
        Preferences.set("lastSyncTime", os.time())
    end)
end

-- Start background sync task
function SmartCollectionSync.startBackgroundSync()
    local generation = newGeneration()

    -- Checked before each pass and before each collection, so turning
    -- auto-sync off or reloading stops a pass that is already running
    local function shouldContinue()
        return Preferences.get("autoSyncEnabled")
            and Preferences.get("_loopGeneration") == generation
    end

    local function notTooLarge(id)
        return not SyncEngine.isTooLargeForAutoSync(Preferences.getCollectionSizes()[id])
    end

    LrTasks.startAsyncTask(function()
        while shouldContinue() do
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
                    shouldContinue, notTooLarge)
                Preferences.recordCollectionSizes(results.sizes)
                Preferences.set("lastSyncTime", os.time())
            end

            LrTasks.sleep(interval)
        end
    end)
end

-- Stop background sync; the loop exits at its next check
function SmartCollectionSync.stopBackgroundSync()
    newGeneration()
end

-- Plugin initialization (called on LrInitPlugin)
function SmartCollectionSync.init()
    if Preferences.get("autoSyncEnabled") then
        SmartCollectionSync.startBackgroundSync()
    end
end

-- Called when the plug-in is unloaded or reloaded (LrShutdownPlugin). Stops
-- a running pass at the next collection. Leaves autoSyncEnabled alone so
-- auto-sync resumes after a reload. No LrShutdownApp hook: tasks die at quit
-- anyway.
function SmartCollectionSync.shutdown()
    SmartCollectionSync.stopBackgroundSync()
end

return SmartCollectionSync
