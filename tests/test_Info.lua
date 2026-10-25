-- tests/test_Info.lua
-- Unit tests for Info.lua (plugin manifest)
-- Tests are derived from spec.md requirements, not from reading the implementation

-- Load the Info.lua file (it returns a table)
local pluginDir = "lrc-smart-collection-sync.lrplugin/"
package.path = package.path .. ";" .. pluginDir .. "?.lua"

local Info = dofile(pluginDir .. "Info.lua")

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

-- Test: Plugin must have a name (spec: "Smart Collection Sync")
test("Plugin has name",
    Info.LrPluginName ~= nil and Info.LrPluginName ~= "",
    "LrPluginName is missing or empty")

test("Plugin name is Smart Collection Sync",
    Info.LrPluginName == "Smart Collection Sync",
    "Expected 'Smart Collection Sync', got '" .. tostring(Info.LrPluginName) .. "'")

-- Test: Plugin must have a toolkit identifier
test("Plugin has toolkit identifier",
    Info.LrToolkitIdentifier ~= nil and Info.LrToolkitIdentifier ~= "",
    "LrToolkitIdentifier is missing or empty")

-- Test: Plugin must define SDK version requirements
test("Plugin defines SDK version",
    Info.LrSdkVersion ~= nil,
    "LrSdkVersion is missing")

test("SDK version is a number",
    type(Info.LrSdkVersion) == "number",
    "LrSdkVersion should be a number")

-- Test: Plugin must define menu items (spec: File > Plug-in Extras menu)
test("Plugin defines export menu items",
    Info.LrExportMenuItems ~= nil and type(Info.LrExportMenuItems) == "table",
    "LrExportMenuItems is missing or not a table")

-- Test: Must have "Smart Collection Sync..." menu item (spec: opens config dialog)
local hasConfigMenuItem = false
local hasyncNowMenuItem = false
if Info.LrExportMenuItems then
    for _, item in ipairs(Info.LrExportMenuItems) do
        if item.title == "Smart Collection Sync..." then
            hasConfigMenuItem = true
        end
        if item.title == "Sync Now" then
            hasyncNowMenuItem = true
        end
    end
end

test("Has 'Smart Collection Sync...' menu item",
    hasConfigMenuItem,
    "Missing menu item 'Smart Collection Sync...'")

-- Test: Must have "Sync Now" menu item (spec: manual trigger)
test("Has 'Sync Now' menu item",
    hasyncNowMenuItem,
    "Missing menu item 'Sync Now'")

-- Test: Menu items must reference a file
if Info.LrExportMenuItems then
    for _, item in ipairs(Info.LrExportMenuItems) do
        test("Menu item '" .. item.title .. "' has file reference",
            item.file ~= nil and item.file ~= "",
            "Menu item missing file reference")
    end
end

-- Test: Plugin must have version info
test("Plugin has VERSION",
    Info.VERSION ~= nil and type(Info.VERSION) == "table",
    "VERSION is missing or not a table")

-- Test: Plugin should define init/shutdown for background task management (spec: auto-sync resumes after restart)
test("Plugin defines LrInitPlugin",
    Info.LrInitPlugin ~= nil,
    "LrInitPlugin is missing (needed for auto-sync resume)")

test("Plugin defines LrShutdownPlugin",
    Info.LrShutdownPlugin ~= nil,
    "LrShutdownPlugin is missing (needed for cleanup)")

-- Summary
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
