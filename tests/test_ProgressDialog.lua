-- tests/test_ProgressDialog.lua
-- Unit tests for ProgressDialog.lua
-- Tests derived from spec.md requirements:
--   - Progress dialog shown during manual "Sync Now" operations
--   - Shows current smart collection being processed
--   - Progress bar with count (X of Y)
--   - Running totals of photos added/removed
--   - Cancel button to abort sync

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

-- ============================================
-- Mock Infrastructure
-- ============================================

-- Track calls to the progress scope for verification
local mockProgressScope = {}
local progressScopeCalls = {}

local function resetMocks()
    progressScopeCalls = {
        setPortionComplete = {},
        setCaption = {},
        isCanceled = {},
        done = {},
    }
    mockProgressScope = {
        _canceled = false,
        _done = false,
        _portion = 0,
        _total = 0,
        _caption = "",

        setPortionComplete = function(self, current, total)
            table.insert(progressScopeCalls.setPortionComplete, {current = current, total = total})
            self._portion = current
            self._total = total
        end,

        setCaption = function(self, caption)
            table.insert(progressScopeCalls.setCaption, caption)
            self._caption = caption
        end,

        isCanceled = function(self)
            table.insert(progressScopeCalls.isCanceled, true)
            return self._canceled
        end,

        done = function(self)
            table.insert(progressScopeCalls.done, true)
            self._done = true
        end,
    }
end

-- Mock Lightroom SDK imports
_G.import = function(name)
    if name == "LrProgressScope" then
        return function(args)
            -- Store the title that was passed
            mockProgressScope._title = args.title
            return mockProgressScope
        end
    end
    error("Unknown import: " .. name)
end

-- Load the module
resetMocks()
local pluginDir = "lrc-smart-collection-sync.lrplugin/"
local ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")

-- ============================================
-- Test Suite: Create Progress Dialog
-- Spec: "Progress dialog shown during manual 'Sync Now' operations"
-- ============================================

resetMocks()
ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")

test("create() returns a progress object",
    (function()
        local dialog = ProgressDialog.create("Test Title")
        return dialog ~= nil and type(dialog) == "table"
    end)(),
    "Should return a table")

test("create() passes title to LrProgressScope",
    (function()
        resetMocks()
        ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")
        local dialog = ProgressDialog.create("Syncing Smart Collections")
        return mockProgressScope._title == "Syncing Smart Collections"
    end)(),
    "Title should be passed to LrProgressScope")

-- ============================================
-- Test Suite: Update Progress
-- Spec: "Shows current smart collection being processed"
-- Spec: "Progress bar with count (X of Y)"
-- ============================================

resetMocks()
ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")

test("update() sets caption with collection name",
    (function()
        local dialog = ProgressDialog.create("Test")
        dialog:update("Syncing: Portfolio Candidates", 1, 3)
        return #progressScopeCalls.setCaption > 0 and
               progressScopeCalls.setCaption[1] == "Syncing: Portfolio Candidates"
    end)(),
    "Should set caption with collection name")

test("update() sets progress portion (X of Y)",
    (function()
        resetMocks()
        ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")
        local dialog = ProgressDialog.create("Test")
        dialog:update("Test Collection", 2, 5)
        return #progressScopeCalls.setPortionComplete > 0 and
               progressScopeCalls.setPortionComplete[1].current == 2 and
               progressScopeCalls.setPortionComplete[1].total == 5
    end)(),
    "Should set portion complete with current and total")

test("update() can be called multiple times",
    (function()
        resetMocks()
        ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")
        local dialog = ProgressDialog.create("Test")
        dialog:update("Collection 1", 1, 3)
        dialog:update("Collection 2", 2, 3)
        dialog:update("Collection 3", 3, 3)
        return #progressScopeCalls.setCaption == 3 and
               #progressScopeCalls.setPortionComplete == 3
    end)(),
    "Should be able to update multiple times")

-- ============================================
-- Test Suite: Cancel Button
-- Spec: "Cancel button to abort sync"
-- ============================================

resetMocks()
ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")

test("isCanceled() returns false when not canceled",
    (function()
        local dialog = ProgressDialog.create("Test")
        mockProgressScope._canceled = false
        return dialog:isCanceled() == false
    end)(),
    "Should return false when not canceled")

test("isCanceled() returns true when user clicks cancel",
    (function()
        resetMocks()
        ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")
        local dialog = ProgressDialog.create("Test")
        mockProgressScope._canceled = true
        return dialog:isCanceled() == true
    end)(),
    "Should return true when canceled")

test("update() respects cancellation",
    (function()
        resetMocks()
        ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")
        local dialog = ProgressDialog.create("Test")
        mockProgressScope._canceled = true
        local captionCountBefore = #progressScopeCalls.setCaption
        dialog:update("Should not update", 1, 1)
        -- When canceled, update should not set caption
        return #progressScopeCalls.setCaption == captionCountBefore
    end)(),
    "Should not update when canceled")

-- ============================================
-- Test Suite: Done
-- Spec: Progress dialog closes when sync completes
-- ============================================

resetMocks()
ProgressDialog = dofile(pluginDir .. "ProgressDialog.lua")

test("done() marks progress as complete",
    (function()
        local dialog = ProgressDialog.create("Test")
        dialog:done()
        return #progressScopeCalls.done > 0 and mockProgressScope._done == true
    end)(),
    "Should call done() on the progress scope")

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
