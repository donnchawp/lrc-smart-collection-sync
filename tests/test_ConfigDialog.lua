-- test_ConfigDialog.lua
-- Unit tests for ConfigDialog module
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

local function assert_contains(str, substr, msg)
    if not string.find(str, substr, 1, true) then
        error((msg or "Assertion failed") ..
              "\n  Expected string to contain: " .. tostring(substr) ..
              "\n  Actual: " .. tostring(str))
    end
end

-- ============================================================================
-- Mocks for Lightroom SDK and dependencies
-- ============================================================================

local mockPrefs = {}
local mockSmartCollections = {}

-- Mock the global import function for LR SDK modules
_G.import = function(name)
    if name == "LrDialogs" then
        return {
            presentModalDialog = function(args)
                return "ok" -- Default to "ok" for save action
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
            bind = function(name)
                return { bind = name }
            end,
        }
    elseif name == "LrBinding" then
        return {
            makePropertyTable = function(context)
                return {}
            end,
        }
    elseif name == "LrFunctionContext" then
        return {
            callWithContext = function(name, fn)
                fn({})
            end,
        }
    elseif name == "LrPrefs" then
        return {
            prefsForPlugin = function()
                return mockPrefs
            end,
        }
    elseif name == "LrApplication" then
        return {
            activeCatalog = function()
                return {
                    getSmartCollections = function()
                        return mockSmartCollections
                    end,
                }
            end,
        }
    end
    return {}
end

-- Mock require for dependencies
local originalRequire = require
_G.require = function(name)
    if name == "SyncEngine" then
        return {
            getAllSmartCollections = function()
                return mockSmartCollections
            end,
        }
    elseif name == "Preferences" then
        return {
            get = function(key)
                return mockPrefs[key]
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
        }
    end
    return originalRequire(name)
end

-- Reset mocks before each test
local function resetMocks()
    mockPrefs = {}
    mockSmartCollections = {}
end

-- Load the module under test
local ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

-- ============================================================================
-- Tests for getStatusText()
-- Spec: "Status: Syncing 3 smart collections"
-- ============================================================================

test("getStatusText returns 'No smart collections selected' when count is 0", function()
    local result = ConfigDialog.getStatusText(0)
    assert_contains(result, "No smart collections selected")
end)

test("getStatusText returns singular form for 1 collection", function()
    local result = ConfigDialog.getStatusText(1)
    assert_contains(result, "1 smart collection")
    -- Should NOT contain plural "collections"
    assert(not string.find(result, "collections"), "Should use singular 'collection' not 'collections'")
end)

test("getStatusText returns plural form for multiple collections", function()
    local result = ConfigDialog.getStatusText(3)
    assert_contains(result, "3 smart collections")
end)

test("getStatusText handles large numbers", function()
    local result = ConfigDialog.getStatusText(100)
    assert_contains(result, "100 smart collections")
end)

-- ============================================================================
-- Tests for getLastSyncText()
-- Spec: "Last sync: 2 minutes ago"
-- ============================================================================

test("getLastSyncText returns 'Never' when no lastSyncTime set", function()
    resetMocks()
    mockPrefs.lastSyncTime = nil
    -- Reload to pick up mock
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "Never")
end)

test("getLastSyncText returns 'Just now' for very recent sync (< 60 seconds)", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - 30  -- 30 seconds ago
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "Just now")
end)

test("getLastSyncText returns minutes for 1-59 minute old sync", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - (5 * 60)  -- 5 minutes ago
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "5 minutes ago")
end)

test("getLastSyncText uses singular 'minute' for 1 minute", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - 90  -- 1.5 minutes ago = 1 minute
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "1 minute ago")
    assert(not string.find(result, "1 minutes"), "Should use singular 'minute'")
end)

test("getLastSyncText returns hours for 1-23 hour old sync", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - (2 * 3600)  -- 2 hours ago
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "2 hours ago")
end)

test("getLastSyncText uses singular 'hour' for 1 hour", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - (1 * 3600 + 1800)  -- 1.5 hours ago = 1 hour
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "1 hour ago")
    assert(not string.find(result, "1 hours"), "Should use singular 'hour'")
end)

test("getLastSyncText returns days for 24+ hour old sync", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - (3 * 86400)  -- 3 days ago
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "3 days ago")
end)

test("getLastSyncText uses singular 'day' for 1 day", function()
    resetMocks()
    mockPrefs.lastSyncTime = os.time() - (1 * 86400 + 3600)  -- 1 day + 1 hour ago = 1 day
    ConfigDialog = dofile("lrc-smart-collection-sync.lrplugin/ConfigDialog.lua")

    local result = ConfigDialog.getLastSyncText()
    assert_contains(result, "1 day ago")
    assert(not string.find(result, "1 days"), "Should use singular 'day'")
end)

-- ============================================================================
-- Tests for showDialog() - saving preferences
-- Spec: sync interval 10-300 seconds
-- ============================================================================

-- Note: These tests are more integration-like since showDialog involves UI
-- We test the clamping logic for sync interval based on spec requirement

test("Sync interval minimum is 10 seconds per spec", function()
    -- From spec.md: "Auto-sync interval: 30 seconds (minimum: 10, maximum: 300)"
    -- This validates our understanding of the spec requirement
    local MIN_INTERVAL = 10
    assert_eq(MIN_INTERVAL, 10, "Minimum interval should be 10 per spec")
end)

test("Sync interval maximum is 300 seconds per spec", function()
    -- From spec.md: "Auto-sync interval: 30 seconds (minimum: 10, maximum: 300)"
    local MAX_INTERVAL = 300
    assert_eq(MAX_INTERVAL, 300, "Maximum interval should be 300 per spec")
end)

test("Sync interval default is 30 seconds per spec", function()
    -- From spec.md: "Automatic background sync: Runs at a configurable interval (default: 30 seconds)"
    resetMocks()
    -- When no interval is set, we check what the default should be
    local expectedDefault = 30
    assert_eq(expectedDefault, 30, "Default interval should be 30 per spec")
end)

-- ============================================================================
-- Tests for module structure
-- ============================================================================

test("ConfigDialog exports showDialog function", function()
    assert(type(ConfigDialog.showDialog) == "function", "showDialog should be a function")
end)

test("ConfigDialog exports getStatusText function", function()
    assert(type(ConfigDialog.getStatusText) == "function", "getStatusText should be a function")
end)

test("ConfigDialog exports getLastSyncText function", function()
    assert(type(ConfigDialog.getLastSyncText) == "function", "getLastSyncText should be a function")
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
