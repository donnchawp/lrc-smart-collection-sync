-- test_SmartCollectionSync.lua
-- Unit tests for SmartCollectionSync module (main entry point)
-- Tests derived from spec.md requirements, not implementation

-- Test tracking
local tests_run = 0
local tests_passed = 0

local function test(name, fn)
    tests_run = tests_run + 1
    local ok, err = pcall(fn)
    if ok then
        tests_passed = tests_passed + 1
        print("✓ " .. name)
    else
        print("✗ " .. name)
        print("  Error: " .. tostring(err))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "Assertion failed") ..
              "\n  Expected: " .. tostring(expected) ..
              "\n  Actual:   " .. tostring(actual))
    end
end

local function assert_true(value, msg)
    if value ~= true then
        error((msg or "Assertion failed") ..
              "\n  Expected: true" ..
              "\n  Actual:   " .. tostring(value))
    end
end

local function assert_false(value, msg)
    if value ~= false then
        error((msg or "Assertion failed") ..
              "\n  Expected: false" ..
              "\n  Actual:   " .. tostring(value))
    end
end

-- ============================================================================
-- Mocks for Lightroom SDK and dependencies
-- ============================================================================

local mockPrefs = {}
local syncNowCalled = false
local backgroundSyncStarted = false
local dialogShown = false
local asyncTasksStarted = {}
local showConfigResult = "ok"
local syncCalls = {}
local syncResultSizes = {}
local onSleep = function() end
local progressCanceled = false
local onShowDialog = function() end
local recordedSizes = nil

-- Mock the global import function for LR SDK modules
_G.import = function(name)
    if name == "LrTasks" then
        return {
            startAsyncTask = function(fn)
                table.insert(asyncTasksStarted, fn)
                return {} -- task handle
            end,
            sleep = function(seconds) onSleep() end,
        }
    elseif name == "LrApplicationView" then
        return { getCurrentModuleName = function() return "library" end }
    elseif name == "LrDialogs" then
        return {
            message = function(title, msg, style) end,
            presentModalDialog = function(args)
                dialogShown = true
                return showConfigResult
            end,
        }
    elseif name == "LrPrefs" then
        return {
            prefsForPlugin = function()
                return mockPrefs
            end,
        }
    elseif name == "LrView" then
        return {
            osFactory = function()
                return {
                    control_spacing = function() return 10 end,
                    column = function(...) return {} end,
                    row = function(...) return {} end,
                    static_text = function(...) return {} end,
                    checkbox = function(...) return {} end,
                    edit_field = function(...) return {} end,
                    push_button = function(...) return {} end,
                    separator = function(...) return {} end,
                    scrolled_view = function(...) return {} end,
                }
            end,
            bind = function(name) return { bind = name } end,
        }
    elseif name == "LrBinding" then
        return { makePropertyTable = function(context) return {} end }
    elseif name == "LrFunctionContext" then
        return { callWithContext = function(name, fn) fn({}) end }
    elseif name == "LrApplication" then
        return {
            activeCatalog = function()
                return { getSmartCollections = function() return {} end }
            end,
        }
    elseif name == "LrProgressScope" then
        return function(args)
            return {
                setPortionComplete = function() end,
                setCaption = function() end,
                isCanceled = function() return false end,
                done = function() end,
            }
        end
    end
    return {}
end

-- Mock require for dependencies
local originalRequire = require
local realSyncEngine = dofile("lrc-smart-collection-sync.lrplugin/SyncEngine.lua")
_G.require = function(name)
    if name == "SyncEngine" then
        return {
            getAllSmartCollections = function() return {} end,
            isTooLargeForAutoSync = realSyncEngine.isTooLargeForAutoSync,
            runFullSync = function(selectedIds, destSetName, callback, shouldSync)
                table.insert(syncCalls, { callback = callback, shouldSync = shouldSync })
                return { totalAdded = 0, totalRemoved = 0, collectionsProcessed = 0,
                         sizes = syncResultSizes }
            end,
        }
    elseif name == "ConfigDialog" then
        return {
            showDialog = function()
                dialogShown = true
                onShowDialog()
                return showConfigResult
            end,
            getStatusText = function(count) return "Status" end,
            getLastSyncText = function() return "Never" end,
        }
    elseif name == "ProgressDialog" then
        return {
            create = function(title)
                return {
                    update = function(self, msg, current, total, added, removed) end,
                    isCanceled = function(self) return progressCanceled end,
                    done = function(self) end,
                }
            end,
        }
    elseif name == "Preferences" then
        return {
            get = function(key)
                local defaults = {
                    selectedCollectionIds = {},
                    destinationSetName = "Smart Collection Sync",
                    syncInterval = 30,
                    autoSyncEnabled = false,
                }
                if mockPrefs[key] ~= nil then
                    return mockPrefs[key]
                end
                return defaults[key]
            end,
            set = function(key, value)
                mockPrefs[key] = value
            end,
            getSelectedIds = function()
                return mockPrefs.selectedCollectionIds or {}
            end,
            setSelectedIds = function(ids)
                mockPrefs.selectedCollectionIds = ids
            end,
            getCollectionSizes = function()
                return mockPrefs.collectionSizes or {}
            end,
            recordCollectionSizes = function(sizes)
                recordedSizes = sizes
            end,
        }
    end
    return originalRequire(name)
end

-- Reset mocks before each test
local function resetMocks()
    mockPrefs = {}
    syncNowCalled = false
    backgroundSyncStarted = false
    dialogShown = false
    asyncTasksStarted = {}
    showConfigResult = "ok"
    syncCalls = {}
    syncResultSizes = {}
    onSleep = function() end
    progressCanceled = false
    onShowDialog = function() end
    recordedSizes = nil
end

-- Load the module under test
local SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

-- ============================================================================
-- Tests for Module Structure
-- Spec: Plugin should have menu commands and lifecycle functions
-- ============================================================================

test("SmartCollectionSync exports showConfig function", function()
    assert_eq(type(SmartCollectionSync.showConfig), "function")
end)

test("SmartCollectionSync exports syncNow function", function()
    assert_eq(type(SmartCollectionSync.syncNow), "function")
end)

test("SmartCollectionSync exports startBackgroundSync function", function()
    assert_eq(type(SmartCollectionSync.startBackgroundSync), "function")
end)

test("SmartCollectionSync exports stopBackgroundSync function", function()
    assert_eq(type(SmartCollectionSync.stopBackgroundSync), "function")
end)

test("SmartCollectionSync exports init function for plugin startup", function()
    assert_eq(type(SmartCollectionSync.init), "function")
end)

test("SmartCollectionSync exports shutdown function for plugin cleanup", function()
    assert_eq(type(SmartCollectionSync.shutdown), "function")
end)

-- ============================================================================
-- Tests for showConfig()
-- Spec: "Smart Collection Sync..." opens main configuration dialog
-- ============================================================================

test("showConfig opens the configuration dialog", function()
    resetMocks()
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")
    SmartCollectionSync.showConfig()
    assert_true(dialogShown, "Config dialog should be shown")
end)

-- ============================================================================
-- Tests for syncNow()
-- Spec: "Sync Now" triggers immediate sync with progress dialog
-- ============================================================================

test("syncNow starts an async task", function()
    resetMocks()
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")
    SmartCollectionSync.syncNow()
    assert_true(#asyncTasksStarted > 0, "Should start an async task for sync")
end)

-- ============================================================================
-- Tests for init()
-- Spec: "Auto-sync resumes after Lightroom restart (if was enabled)"
-- ============================================================================

test("init starts background sync if autoSyncEnabled is true", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    local initialTaskCount = #asyncTasksStarted
    SmartCollectionSync.init()
    assert_true(#asyncTasksStarted > initialTaskCount, "Should start background sync task on init")
end)

test("init does not start background sync if autoSyncEnabled is false", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = false
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    local initialTaskCount = #asyncTasksStarted
    SmartCollectionSync.init()
    assert_eq(#asyncTasksStarted, initialTaskCount, "Should not start background sync when disabled")
end)

-- ============================================================================
-- Tests for shutdown()
-- Spec: Plugin should clean up on shutdown
-- ============================================================================

test("shutdown stops the background task without turning auto-sync off", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    mockPrefs.selectedCollectionIds = { 101 }
    SmartCollectionSync.startBackgroundSync()
    SmartCollectionSync.shutdown()
    asyncTasksStarted[1]()

    assert_eq(#syncCalls, 0, "Loop should exit after shutdown")
    assert_true(mockPrefs.autoSyncEnabled, "Auto-sync setting must survive a restart")
end)

test("init after a plugin reload replaces the old loop instead of adding one", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    onSleep = function() mockPrefs.autoSyncEnabled = false end -- one pass only
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.init()          -- first load
    SmartCollectionSync.shutdown()      -- Plug-in Manager reload unloads...
    SmartCollectionSync.init()          -- ...and loads again
    assert_eq(#asyncTasksStarted, 2)

    asyncTasksStarted[1]()              -- old loop wakes up
    assert_eq(#syncCalls, 0, "Old loop should exit")
    asyncTasksStarted[2]()              -- new loop
    assert_eq(#syncCalls, 1, "New loop should sync")
end)

test("ShutdownApp stops the loop when Lightroom quits and calls done", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")
    package.loaded.SmartCollectionSync = SmartCollectionSync
    local app = dofile("lrc-smart-collection-sync.lrplugin/ShutdownApp.lua")
    package.loaded.SmartCollectionSync = nil

    SmartCollectionSync.startBackgroundSync()
    local doneCalled = false
    app.LrShutdownFunction(function() doneCalled = true end, function() return false end)
    asyncTasksStarted[1]()

    assert_true(doneCalled, "Should call doneFunction")
    assert_eq(#syncCalls, 0, "Loop should exit after quit")
end)

-- ============================================================================
-- Tests for showConfig() starting and stopping auto-sync
-- Only a change to the auto-sync setting starts or stops the loop
-- ============================================================================

test("showConfig does not start another loop when auto-sync stays on", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.showConfig()
    assert_eq(#asyncTasksStarted, 0)
end)

test("showConfig starts the loop when auto-sync is turned on", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = false
    onShowDialog = function() mockPrefs.autoSyncEnabled = true end
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.showConfig()
    assert_eq(#asyncTasksStarted, 1)
end)

-- ============================================================================
-- Tests for collection size limits
-- Auto-sync skips large collections; Sync Now syncs everything and
-- refreshes the recorded sizes
-- ============================================================================

test("background pass skips large collections and records sizes", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    mockPrefs.collectionSizes = { ["202"] = 50000 }
    syncResultSizes = { ["101"] = 12 }
    onSleep = function() mockPrefs.autoSyncEnabled = false end -- one pass only
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.startBackgroundSync()
    asyncTasksStarted[1]()

    assert_eq(#syncCalls, 1, "Should run one sync pass")
    assert_false(syncCalls[1].shouldSync("202"), "Background pass should skip large collections")
    assert_true(syncCalls[1].shouldSync("101"), "Unknown sizes should sync")
    assert_eq(recordedSizes, syncResultSizes, "Should record the sizes from the pass")
end)

test("background pass stops when shutdown is requested", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.startBackgroundSync()
    SmartCollectionSync.shutdown()
    asyncTasksStarted[1]()

    assert_eq(#syncCalls, 0, "Should not start a pass after shutdown")
end)

test("background pass progress callback returns false after shutdown", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    onSleep = function() mockPrefs.autoSyncEnabled = false end
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.startBackgroundSync()
    asyncTasksStarted[1]()

    local callback = syncCalls[1].callback
    mockPrefs.autoSyncEnabled = true
    assert_true(callback("x", 1, 1), "Should continue while running")
    SmartCollectionSync.shutdown()
    assert_false(callback("x", 1, 1), "Should stop once shutdown is requested")
end)

test("background pass progress callback returns false after auto-sync is turned off", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    onSleep = function() mockPrefs.autoSyncEnabled = false end
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.startBackgroundSync()
    asyncTasksStarted[1]()

    local callback = syncCalls[1].callback
    mockPrefs.autoSyncEnabled = false
    assert_false(callback("x", 1, 1), "Should stop once auto-sync is off")
end)

test("syncNow syncs large collections too and records sizes", function()
    resetMocks()
    mockPrefs.selectedCollectionIds = { 101 }
    mockPrefs.collectionSizes = { ["101"] = 50000 }
    syncResultSizes = { ["101"] = 9000 }
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.syncNow()
    asyncTasksStarted[1]()

    assert_eq(#syncCalls, 1)
    assert_eq(syncCalls[1].shouldSync, nil, "Sync Now should not skip large collections")
    assert_eq(recordedSizes, syncResultSizes, "Should record the refreshed sizes")
end)

test("syncNow progress callback returns false when Cancel is clicked", function()
    resetMocks()
    mockPrefs.selectedCollectionIds = { 101 }
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.syncNow()
    asyncTasksStarted[1]()

    local callback = syncCalls[1].callback
    assert_true(callback("x", 1, 1), "Should continue before Cancel")
    progressCanceled = true
    assert_false(callback("x", 1, 1), "Should stop after Cancel")
end)

-- ============================================================================
-- Tests for startBackgroundSync()
-- Spec: Background sync runs at configured interval
-- ============================================================================

test("startBackgroundSync creates an async task", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    local initialTaskCount = #asyncTasksStarted
    SmartCollectionSync.startBackgroundSync()
    assert_true(#asyncTasksStarted > initialTaskCount, "Should start async task")
end)

-- ============================================================================
-- Tests for stopBackgroundSync()
-- Spec: Sync can be paused without losing configuration
-- ============================================================================

test("stopBackgroundSync stops a running loop", function()
    resetMocks()
    mockPrefs.autoSyncEnabled = true
    mockPrefs.selectedCollectionIds = { 101 }
    SmartCollectionSync = dofile("lrc-smart-collection-sync.lrplugin/SmartCollectionSync.lua")

    SmartCollectionSync.startBackgroundSync()
    SmartCollectionSync.stopBackgroundSync()
    asyncTasksStarted[1]()
    assert_eq(#syncCalls, 0, "Loop should exit")
end)

-- ============================================================================
-- Summary
-- ============================================================================

print("")
print(string.format("Tests: %d/%d passed", tests_passed, tests_run))

if tests_passed == tests_run then
    print("All tests passed!")
    os.exit(0)
else
    print("Some tests failed!")
    os.exit(1)
end
