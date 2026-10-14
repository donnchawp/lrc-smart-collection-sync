-- tests/test_Preferences.lua
-- Unit tests for Preferences.lua
-- Tests are derived from spec.md requirements:
--   - Configuration stored in plugin preferences (LrPrefs)
--   - Persists: selected smart collection IDs, collection set name, sync interval, auto-sync enabled state
--   - Default interval: 30 seconds
--   - Default destination set name: "Smart Collection Sync"
--   - Auto-sync disabled by default

local testsPassed = 0
local testsFailed = 0

local function test(name, condition, message)
    if condition then
        testsPassed = testsPassed + 1
        print("PASS: " .. name)
    else
        testsFailed = testsFailed + 1
        print("FAIL: " .. name .. " - " .. (message or ""))
    end
end

-- Mock storage for preferences
local mockPrefs = {}

-- Mock the LrPrefs SDK
_G.import = function(name)
    if name == "LrPrefs" then
        return {
            prefsForPlugin = function()
                return setmetatable({}, {
                    __index = function(_, key)
                        return mockPrefs[key]
                    end,
                    __newindex = function(_, key, value)
                        mockPrefs[key] = value
                    end
                })
            end
        }
    end
    error("Unknown import: " .. name)
end

-- Reset mock state before loading module
mockPrefs = {}

-- Load the module
local pluginDir = "lrc-smart-collection-sync.lrplugin/"
local Preferences = dofile(pluginDir .. "Preferences.lua")

-- ============================================
-- Test Suite: Default Values
-- Spec: "Default: 30 seconds", "Default name: Smart Collection Sync"
-- ============================================

-- Reset mock to simulate fresh install (no saved preferences)
mockPrefs = {}
-- Reload module to pick up fresh mock
Preferences = dofile(pluginDir .. "Preferences.lua")

test("Default syncInterval is 30 seconds",
    Preferences.get("syncInterval") == 30,
    "Expected 30, got " .. tostring(Preferences.get("syncInterval")))

test("Default destinationSetName is 'Smart Collection Sync'",
    Preferences.get("destinationSetName") == "Smart Collection Sync",
    "Expected 'Smart Collection Sync', got '" .. tostring(Preferences.get("destinationSetName")) .. "'")

test("Default autoSyncEnabled is false",
    Preferences.get("autoSyncEnabled") == false,
    "Expected false, got " .. tostring(Preferences.get("autoSyncEnabled")))

test("Default selectedCollectionIds is empty table",
    type(Preferences.getSelectedIds()) == "table" and #Preferences.getSelectedIds() == 0,
    "Expected empty table")

test("Default lastSyncTime is nil",
    Preferences.get("lastSyncTime") == nil,
    "Expected nil, got " .. tostring(Preferences.get("lastSyncTime")))

-- ============================================
-- Test Suite: Set and Get
-- Spec: "Settings are saved and persist across sessions"
-- ============================================

test("Can set and get syncInterval",
    (function()
        Preferences.set("syncInterval", 60)
        return Preferences.get("syncInterval") == 60
    end)(),
    "Value not persisted correctly")

test("Can set and get destinationSetName",
    (function()
        Preferences.set("destinationSetName", "My Synced Collections")
        return Preferences.get("destinationSetName") == "My Synced Collections"
    end)(),
    "Value not persisted correctly")

test("Can set and get autoSyncEnabled",
    (function()
        Preferences.set("autoSyncEnabled", true)
        return Preferences.get("autoSyncEnabled") == true
    end)(),
    "Value not persisted correctly")

test("Can set and get lastSyncTime",
    (function()
        local timestamp = 1700000000
        Preferences.set("lastSyncTime", timestamp)
        return Preferences.get("lastSyncTime") == timestamp
    end)(),
    "Value not persisted correctly")

-- ============================================
-- Test Suite: Selected Collection IDs
-- Spec: "User selects which smart collections to sync", "Selections persist"
-- ============================================

test("setSelectedIds stores IDs correctly",
    (function()
        local ids = {101, 202, 303}
        Preferences.setSelectedIds(ids)
        local retrieved = Preferences.getSelectedIds()
        return type(retrieved) == "table" and #retrieved == 3
    end)(),
    "IDs not stored correctly")

test("getSelectedIds returns stored IDs",
    (function()
        local ids = {111, 222}
        Preferences.setSelectedIds(ids)
        local retrieved = Preferences.getSelectedIds()
        return retrieved[1] == 111 and retrieved[2] == 222
    end)(),
    "IDs not retrieved correctly")

test("setSelectedIds with empty table",
    (function()
        Preferences.setSelectedIds({})
        local retrieved = Preferences.getSelectedIds()
        return type(retrieved) == "table" and #retrieved == 0
    end)(),
    "Empty table not handled correctly")

-- ============================================
-- Test Suite: Collection sizes
-- ============================================

test("getCollectionSizes defaults to an empty table",
    (function()
        mockPrefs.collectionSizes = nil
        local sizes = Preferences.getCollectionSizes()
        return type(sizes) == "table" and next(sizes) == nil
    end)(),
    "Expected empty table")

test("recordCollectionSizes merges new sizes into stored ones",
    (function()
        mockPrefs.collectionSizes = { ["1"] = 10, ["2"] = 20 }
        Preferences.recordCollectionSizes({ ["2"] = 25, ["3"] = 30 })
        local s = Preferences.getCollectionSizes()
        return s["1"] == 10 and s["2"] == 25 and s["3"] == 30
    end)(),
    "Sizes not merged correctly")

test("recordCollectionSizes assigns a new table so LrPrefs saves it",
    (function()
        local before = { ["1"] = 10 }
        mockPrefs.collectionSizes = before
        Preferences.recordCollectionSizes({ ["2"] = 20 })
        return mockPrefs.collectionSizes ~= before
    end)(),
    "Should assign a new table, not mutate the stored one")

-- ============================================
-- Test Suite: Values override defaults
-- ============================================

-- Reset and reload to test that stored values override defaults
mockPrefs = {
    syncInterval = 120,
    autoSyncEnabled = true,
}
Preferences = dofile(pluginDir .. "Preferences.lua")

test("Stored syncInterval overrides default",
    Preferences.get("syncInterval") == 120,
    "Expected 120, got " .. tostring(Preferences.get("syncInterval")))

test("Stored autoSyncEnabled overrides default",
    Preferences.get("autoSyncEnabled") == true,
    "Expected true, got " .. tostring(Preferences.get("autoSyncEnabled")))

-- ============================================
-- Summary
-- ============================================

print("")
print("==========================================")
print(string.format("Tests: %d passed, %d failed", testsPassed, testsFailed))
print("==========================================")

if testsFailed > 0 then
    os.exit(1)
else
    print("All tests passed!")
    os.exit(0)
end
