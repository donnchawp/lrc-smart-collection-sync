-- tests/test_SyncEngine.lua
-- Unit tests for SyncEngine.lua
-- Tests derived from spec.md requirements:
--   - Sync algorithm: add photos in smart but not in regular, remove photos in regular but not in smart
--   - Mirror collections placed in dedicated collection set
--   - Mirror collections use same name as source smart collections
--   - When smart collection deleted, mirror collection is also deleted
--   - All mirrored collections placed in a dedicated collection set

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

-- Mock photo objects
local function createMockPhoto(id)
    return { localIdentifier = id }
end

-- Mock collection that tracks photos
local function createMockCollection(name, photos, isSmart)
    photos = photos or {}
    isSmart = isSmart ~= false  -- default to true for backwards compatibility
    local coll = {
        _name = name,
        _photos = {},
        _deleted = false,
        _isSmart = isSmart,
    }
    -- Initialize photos
    for _, p in ipairs(photos) do
        coll._photos[p.localIdentifier] = p
    end

    function coll:getName()
        return self._name
    end

    function coll:getPhotos()
        local result = {}
        for _, photo in pairs(self._photos) do
            table.insert(result, photo)
        end
        return result
    end

    function coll:addPhotos(photosToAdd)
        for _, photo in ipairs(photosToAdd) do
            self._photos[photo.localIdentifier] = photo
        end
    end

    function coll:removePhotos(photosToRemove)
        for _, photo in ipairs(photosToRemove) do
            self._photos[photo.localIdentifier] = nil
        end
    end

    function coll:delete()
        self._deleted = true
    end

    function coll:isSmartCollection()
        return self._isSmart
    end

    coll.localIdentifier = name .. "_id"

    return coll
end

-- Mock collection set
local function createMockCollectionSet(name)
    local set = {
        _name = name,
        _children = {},
        _childSets = {},
    }

    function set:getName()
        return self._name
    end

    function set:getChildCollections()
        local result = {}
        for _, coll in pairs(self._children) do
            if not coll._deleted then
                table.insert(result, coll)
            end
        end
        return result
    end

    function set:getChildCollectionSets()
        return self._childSets
    end

    function set:addChild(coll)
        self._children[coll:getName()] = coll
    end

    return set
end

-- Global state for mocks
local mockCatalog = {}
local mockSmartCollections = {}
local mockCollectionSets = {}
local writeAccessCalls = {}

-- Reset all mocks
local function resetMocks()
    mockSmartCollections = {}
    mockCollectionSets = {}
    writeAccessCalls = {}

    mockCatalog = {
        getSmartCollections = function()
            return mockSmartCollections
        end,
        getChildCollections = function()
            -- Return smart collections as root-level collections
            return mockSmartCollections
        end,
        getChildCollectionSets = function()
            return mockCollectionSets
        end,
        createCollectionSet = function(self, name, parent, returnExisting)
            local set = createMockCollectionSet(name)
            table.insert(mockCollectionSets, set)
            return set
        end,
        createCollection = function(self, name, parent, returnExisting)
            local coll = createMockCollection(name, {})
            if parent then
                parent:addChild(coll)
            end
            return coll
        end,
        withWriteAccessDo = function(self, description, func)
            table.insert(writeAccessCalls, description)
            return func()
        end,
    }
end

-- Mock Lightroom SDK imports
_G.import = function(name)
    if name == "LrApplication" then
        return {
            activeCatalog = function()
                return mockCatalog
            end
        }
    elseif name == "LrTasks" then
        return {
            sleep = function() end,
            startAsyncTask = function(func) func() end,
            yield = function() end,
        }
    end
    error("Unknown import: " .. name)
end

-- Load the module
resetMocks()
local pluginDir = "lrc-smart-collection-sync.lrplugin/"
local SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

-- ============================================
-- Test Suite: getAllSmartCollections
-- Spec: "Get all smart collections in the catalog"
-- ============================================

resetMocks()
SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

test("getAllSmartCollections returns empty list when no smart collections exist",
    (function()
        mockSmartCollections = {}
        local result = SyncEngine.getAllSmartCollections()
        return type(result) == "table" and #result == 0
    end)(),
    "Should return empty table")

test("getAllSmartCollections returns all smart collections",
    (function()
        local sc1 = createMockCollection("5 Star Photos", {})
        sc1.localIdentifier = 101
        local sc2 = createMockCollection("Recent Imports", {})
        sc2.localIdentifier = 102
        mockSmartCollections = {sc1, sc2}

        local result = SyncEngine.getAllSmartCollections()
        return #result == 2
    end)(),
    "Should return 2 smart collections")

-- ============================================
-- Test Suite: getOrCreateDestinationSet
-- Spec: "All mirrored collections placed in a dedicated collection set"
-- Spec: "Default name: Smart Collection Sync"
-- ============================================

resetMocks()
SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

test("getOrCreateDestinationSet creates new set when none exists",
    (function()
        mockCollectionSets = {}
        local set = SyncEngine.getOrCreateDestinationSet("Smart Collection Sync")
        return set ~= nil and set:getName() == "Smart Collection Sync"
    end)(),
    "Should create set with correct name")

test("getOrCreateDestinationSet returns existing set when found",
    (function()
        local existingSet = createMockCollectionSet("Smart Collection Sync")
        mockCollectionSets = {existingSet}
        local set = SyncEngine.getOrCreateDestinationSet("Smart Collection Sync")
        return set == existingSet
    end)(),
    "Should return existing set, not create new one")

test("getOrCreateDestinationSet uses custom name",
    (function()
        mockCollectionSets = {}
        local set = SyncEngine.getOrCreateDestinationSet("My Custom Sync Set")
        return set:getName() == "My Custom Sync Set"
    end)(),
    "Should use custom name")

-- ============================================
-- Test Suite: getOrCreateMirror
-- Spec: "Mirror collections use the same name as their source smart collections"
-- ============================================

resetMocks()
SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

test("getOrCreateMirror creates mirror with same name as smart collection",
    (function()
        local smartColl = createMockCollection("5 Star Photos", {})
        local destSet = createMockCollectionSet("Smart Collection Sync")
        local mirror = SyncEngine.getOrCreateMirror(smartColl, destSet)
        return mirror:getName() == "5 Star Photos"
    end)(),
    "Mirror should have same name as smart collection")

test("getOrCreateMirror returns existing mirror when found",
    (function()
        local smartColl = createMockCollection("5 Star Photos", {})
        local destSet = createMockCollectionSet("Smart Collection Sync")
        local existingMirror = createMockCollection("5 Star Photos", {})
        destSet:addChild(existingMirror)
        local mirror = SyncEngine.getOrCreateMirror(smartColl, destSet)
        return mirror == existingMirror
    end)(),
    "Should return existing mirror")

-- ============================================
-- Test Suite: syncCollection
-- Spec: "Add photos that are in smart but not in regular"
-- Spec: "Remove photos that are in regular but not in smart"
-- ============================================

resetMocks()
SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

test("syncCollection adds photos that are in smart but not in mirror",
    (function()
        local photo1 = createMockPhoto(1)
        local photo2 = createMockPhoto(2)
        local smartColl = createMockCollection("Test", {photo1, photo2})
        local mirrorColl = createMockCollection("Test", {})

        local result = SyncEngine.syncCollection(smartColl, mirrorColl)

        local mirrorPhotos = mirrorColl:getPhotos()
        return result.added == 2 and #mirrorPhotos == 2
    end)(),
    "Should add 2 photos to mirror")

test("syncCollection removes photos that are in mirror but not in smart",
    (function()
        local photo1 = createMockPhoto(1)
        local photo2 = createMockPhoto(2)
        local smartColl = createMockCollection("Test", {})
        local mirrorColl = createMockCollection("Test", {photo1, photo2})

        local result = SyncEngine.syncCollection(smartColl, mirrorColl)

        local mirrorPhotos = mirrorColl:getPhotos()
        return result.removed == 2 and #mirrorPhotos == 0
    end)(),
    "Should remove 2 photos from mirror")

test("syncCollection handles mixed add and remove",
    (function()
        local photo1 = createMockPhoto(1)
        local photo2 = createMockPhoto(2)
        local photo3 = createMockPhoto(3)
        -- Smart has photos 1 and 3
        local smartColl = createMockCollection("Test", {photo1, photo3})
        -- Mirror has photos 1 and 2
        local mirrorColl = createMockCollection("Test", {photo1, photo2})

        local result = SyncEngine.syncCollection(smartColl, mirrorColl)

        -- Should add photo 3, remove photo 2, keep photo 1
        local mirrorPhotos = mirrorColl:getPhotos()
        local hasPhoto1 = false
        local hasPhoto3 = false
        for _, p in ipairs(mirrorPhotos) do
            if p.localIdentifier == 1 then hasPhoto1 = true end
            if p.localIdentifier == 3 then hasPhoto3 = true end
        end
        return result.added == 1 and result.removed == 1 and hasPhoto1 and hasPhoto3 and #mirrorPhotos == 2
    end)(),
    "Should add photo 3, remove photo 2, keep photo 1")

test("syncCollection handles empty smart collection (removes all from mirror)",
    (function()
        local photo1 = createMockPhoto(1)
        local smartColl = createMockCollection("Test", {})
        local mirrorColl = createMockCollection("Test", {photo1})

        local result = SyncEngine.syncCollection(smartColl, mirrorColl)

        return result.added == 0 and result.removed == 1 and #mirrorColl:getPhotos() == 0
    end)(),
    "Empty smart collection should result in empty mirror")

test("syncCollection handles already synced collections (no changes)",
    (function()
        local photo1 = createMockPhoto(1)
        local photo2 = createMockPhoto(2)
        local smartColl = createMockCollection("Test", {photo1, photo2})
        local mirrorColl = createMockCollection("Test", {photo1, photo2})

        writeAccessCalls = {}
        local result = SyncEngine.syncCollection(smartColl, mirrorColl)

        -- No changes needed, so no write access should be requested
        return result.added == 0 and result.removed == 0
    end)(),
    "Already synced collections should have no changes")

-- ============================================
-- Test Suite: runFullSync
-- Spec: "For each selected smart collection... sync"
-- ============================================

resetMocks()
SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

test("runFullSync processes only selected collections",
    (function()
        local sc1 = createMockCollection("5 Star", {createMockPhoto(1)})
        sc1.localIdentifier = 101
        local sc2 = createMockCollection("Recent", {createMockPhoto(2)})
        sc2.localIdentifier = 102
        local sc3 = createMockCollection("Red Label", {createMockPhoto(3)})
        sc3.localIdentifier = 103
        mockSmartCollections = {sc1, sc2, sc3}

        -- Only select sc1 and sc3
        local results = SyncEngine.runFullSync({101, 103}, "Smart Collection Sync", nil)

        return results.collectionsProcessed == 2
    end)(),
    "Should process only 2 selected collections")

test("runFullSync calls progress callback correctly",
    (function()
        local sc1 = createMockCollection("5 Star", {createMockPhoto(1)})
        sc1.localIdentifier = 101
        local sc2 = createMockCollection("Recent", {createMockPhoto(2)})
        sc2.localIdentifier = 102
        mockSmartCollections = {sc1, sc2}

        local progressCalls = {}
        SyncEngine.runFullSync({101, 102}, "Smart Collection Sync",
            function(name, current, total)
                table.insert(progressCalls, {name = name, current = current, total = total})
            end)

        return #progressCalls == 2 and
               progressCalls[1].current == 1 and progressCalls[1].total == 2 and
               progressCalls[2].current == 2 and progressCalls[2].total == 2
    end)(),
    "Progress callback should be called for each collection")

test("runFullSync returns correct totals",
    (function()
        resetMocks()
        SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

        local sc1 = createMockCollection("5 Star", {createMockPhoto(1), createMockPhoto(2)})
        sc1.localIdentifier = 101
        local sc2 = createMockCollection("Recent", {createMockPhoto(3)})
        sc2.localIdentifier = 102
        mockSmartCollections = {sc1, sc2}

        local results = SyncEngine.runFullSync({101, 102}, "Smart Collection Sync", nil)

        -- Both are new syncs, so all photos should be added
        return results.totalAdded == 3 and results.totalRemoved == 0
    end)(),
    "Should return correct added/removed totals")

-- ============================================
-- Test Suite: runFullSync size limits
-- Auto-sync skips smart collections last seen with more than
-- LARGE_COLLECTION_SIZE photos, without loading their photos
-- ============================================

-- Wrap getPhotos so a test can tell whether a collection was loaded
local function trackLoads(coll)
    local getPhotos = coll.getPhotos
    coll._loads = 0
    function coll:getPhotos()
        self._loads = self._loads + 1
        return getPhotos(self)
    end
    return coll
end

test("LARGE_COLLECTION_SIZE is 10000",
    SyncEngine.LARGE_COLLECTION_SIZE == 10000,
    "Expected 10000, got " .. tostring(SyncEngine.LARGE_COLLECTION_SIZE))

test("runFullSync records the size of each synced collection",
    (function()
        resetMocks()
        SyncEngine = dofile(pluginDir .. "SyncEngine.lua")
        local sc1 = createMockCollection("5 Star", {createMockPhoto(1), createMockPhoto(2)})
        sc1.localIdentifier = 101
        mockSmartCollections = {sc1}

        local results = SyncEngine.runFullSync({101}, "Smart Collection Sync", nil)

        return results.sizes["101"] == 2
    end)(),
    "Should record size 2 for collection 101")

test("runFullSync skips collections shouldSync rejects, without loading them",
    (function()
        resetMocks()
        SyncEngine = dofile(pluginDir .. "SyncEngine.lua")
        local big = trackLoads(createMockCollection("Big", {createMockPhoto(1)}))
        big.localIdentifier = 101
        local small = trackLoads(createMockCollection("Small", {createMockPhoto(2)}))
        small.localIdentifier = 102
        mockSmartCollections = {big, small}

        local results = SyncEngine.runFullSync({101, 102}, "Smart Collection Sync", nil,
            function(id) return id ~= "101" end)

        return big._loads == 0 and small._loads == 1
            and results.sizes["101"] == nil and results.sizes["102"] == 1
    end)(),
    "Big should be skipped and not loaded; Small should sync")

test("isTooLargeForAutoSync is false for unknown sizes and sizes at the limit",
    SyncEngine.isTooLargeForAutoSync(nil) == false
        and SyncEngine.isTooLargeForAutoSync(SyncEngine.LARGE_COLLECTION_SIZE) == false,
    "Unknown and at-limit sizes should auto-sync")

test("isTooLargeForAutoSync is true over the limit",
    SyncEngine.isTooLargeForAutoSync(SyncEngine.LARGE_COLLECTION_SIZE + 1) == true,
    "Sizes over the limit should be skipped")

test("runFullSync stops when the progress callback returns false",
    (function()
        resetMocks()
        SyncEngine = dofile(pluginDir .. "SyncEngine.lua")
        local sc1 = trackLoads(createMockCollection("First", {createMockPhoto(1)}))
        sc1.localIdentifier = 101
        local sc2 = trackLoads(createMockCollection("Second", {createMockPhoto(2)}))
        sc2.localIdentifier = 102
        mockSmartCollections = {sc1, sc2}

        local calls = 0
        local results = SyncEngine.runFullSync({101, 102}, "Smart Collection Sync",
            function()
                calls = calls + 1
                return calls < 2 -- allow the first collection, stop before the second
            end)

        return sc1._loads == 1 and sc2._loads == 0 and results.collectionsProcessed == 1
    end)(),
    "Should stop before the second collection")

test("runFullSync skips orphan cleanup when stopped early",
    (function()
        resetMocks()
        SyncEngine = dofile(pluginDir .. "SyncEngine.lua")
        local sc = createMockCollection("Kept", {createMockPhoto(1)})
        sc.localIdentifier = 101
        mockSmartCollections = {sc}

        local destSet = createMockCollectionSet("Smart Collection Sync")
        local orphan = createMockCollection("Orphan", {}, false)
        destSet:addChild(orphan)
        mockCollectionSets = {destSet}

        SyncEngine.runFullSync({101}, "Smart Collection Sync", function() return false end)

        return orphan._deleted == false
    end)(),
    "A stopped pass should not delete mirrors")

-- ============================================
-- Test Suite: cleanupOrphanedMirrors
-- Spec: "When a smart collection is deleted → its mirror collection is also deleted"
-- ============================================

resetMocks()
SyncEngine = dofile(pluginDir .. "SyncEngine.lua")

test("cleanupOrphanedMirrors deletes orphaned mirrors",
    (function()
        -- Smart collection "5 Star" exists
        local sc1 = createMockCollection("5 Star", {})
        sc1.localIdentifier = 101
        mockSmartCollections = {sc1}

        -- But mirrors exist for "5 Star" and "Deleted Collection"
        local mirror1 = createMockCollection("5 Star", {})
        local mirror2 = createMockCollection("Deleted Collection", {})
        local destSet = createMockCollectionSet("Smart Collection Sync")
        destSet:addChild(mirror1)
        destSet:addChild(mirror2)

        SyncEngine.cleanupOrphanedMirrors({101}, destSet, mockSmartCollections)

        -- "Deleted Collection" mirror should be deleted
        return mirror2._deleted == true and mirror1._deleted == false
    end)(),
    "Should delete orphaned mirror but keep valid one")

test("cleanupOrphanedMirrors only considers selected collections",
    (function()
        -- Smart collections exist but only sc1 is selected
        local sc1 = createMockCollection("Selected", {})
        sc1.localIdentifier = 101
        local sc2 = createMockCollection("NotSelected", {})
        sc2.localIdentifier = 102
        mockSmartCollections = {sc1, sc2}

        -- Mirror exists for both
        local mirror1 = createMockCollection("Selected", {})
        local mirror2 = createMockCollection("NotSelected", {})
        local destSet = createMockCollectionSet("Smart Collection Sync")
        destSet:addChild(mirror1)
        destSet:addChild(mirror2)

        -- Only sc1 (101) is selected
        SyncEngine.cleanupOrphanedMirrors({101}, destSet, mockSmartCollections)

        -- "NotSelected" should be deleted because it's not in selectedIds
        return mirror2._deleted == true and mirror1._deleted == false
    end)(),
    "Should delete mirror for unselected collections")

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
