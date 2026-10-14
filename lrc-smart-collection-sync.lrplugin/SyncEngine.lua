local LrApplication = import "LrApplication"
local LrTasks = import "LrTasks"

local SyncEngine = {}

-- Batch size for photo operations to avoid long catalog locks
local BATCH_SIZE = 100

-- Auto-sync skips smart collections bigger than this. The SDK has no cheap
-- way to count or detect changes, so every pass loads every photo; on large
-- collections that is too slow to repeat in the background.
SyncEngine.LARGE_COLLECTION_SIZE = 10000

-- size is the photo count from the last sync, or nil if never synced
function SyncEngine.isTooLargeForAutoSync(size)
    return size ~= nil and size > SyncEngine.LARGE_COLLECTION_SIZE
end

-- Helper: recursively find all smart collections in a collection set
local function findSmartCollectionsInSet(collectionSet, results)
    -- Check child collections
    local collections = collectionSet:getChildCollections()
    for _, coll in ipairs(collections) do
        if coll:isSmartCollection() then
            table.insert(results, coll)
        end
    end

    -- Recurse into child collection sets
    local childSets = collectionSet:getChildCollectionSets()
    for _, childSet in ipairs(childSets) do
        findSmartCollectionsInSet(childSet, results)
    end
end

-- Get all smart collections from catalog
function SyncEngine.getAllSmartCollections()
    local catalog = LrApplication.activeCatalog()
    local results = {}

    -- Check root-level collections (this can be slow on large catalogs)
    local rootCollections = catalog:getChildCollections()
    for _, coll in ipairs(rootCollections) do
        if coll:isSmartCollection() then
            table.insert(results, coll)
        end
    end

    -- Check all collection sets recursively
    local rootSets = catalog:getChildCollectionSets()
    for _, collSet in ipairs(rootSets) do
        findSmartCollectionsInSet(collSet, results)
    end

    return results
end

-- Find or create the destination collection set
function SyncEngine.getOrCreateDestinationSet(setName)
    local catalog = LrApplication.activeCatalog()
    local collectionSets = catalog:getChildCollectionSets()

    for _, set in ipairs(collectionSets) do
        if set:getName() == setName then
            return set
        end
    end

    -- Create new set
    local newSet
    catalog:withWriteAccessDo("Create destination set", function()
        newSet = catalog:createCollectionSet(setName, nil, true)
    end, { timeout = 10, asynchronous = true })
    return newSet
end

-- Find or create mirror collection for a smart collection
function SyncEngine.getOrCreateMirror(smartColl, destSet)
    local mirrorName = smartColl:getName()
    local children = destSet:getChildCollections()

    for _, coll in ipairs(children) do
        if coll:getName() == mirrorName then
            return coll
        end
    end

    -- Create new mirror
    local catalog = LrApplication.activeCatalog()
    local newColl
    catalog:withWriteAccessDo("Create mirror collection", function()
        newColl = catalog:createCollection(mirrorName, destSet, true)
    end, { timeout = 10, asynchronous = true })
    return newColl
end

-- Sync a single smart collection to its mirror
-- Returns {added = count, removed = count, size = photos in smart collection}
function SyncEngine.syncCollection(smartColl, mirrorColl)
    local catalog = LrApplication.activeCatalog()

    local smartPhotos = smartColl:getPhotos() or {}
    local mirrorPhotos = mirrorColl:getPhotos() or {}

    -- Build lookup set of mirror photos using photo objects directly as keys
    local mirrorSet = {}
    for _, photo in ipairs(mirrorPhotos) do
        mirrorSet[photo] = true
    end

    -- Find photos to add (in smart but not in mirror)
    local toAdd = {}
    for _, photo in ipairs(smartPhotos) do
        if not mirrorSet[photo] then
            table.insert(toAdd, photo)
        end
    end

    -- Build lookup set of smart photos
    local smartSet = {}
    for _, photo in ipairs(smartPhotos) do
        smartSet[photo] = true
    end

    -- Find photos to remove (in mirror but not in smart)
    local toRemove = {}
    for _, photo in ipairs(mirrorPhotos) do
        if not smartSet[photo] then
            table.insert(toRemove, photo)
        end
    end

    -- Apply changes in batches to avoid long catalog locks
    if #toAdd > 0 then
        for i = 1, #toAdd, BATCH_SIZE do
            local batch = {}
            for j = i, math.min(i + BATCH_SIZE - 1, #toAdd) do
                table.insert(batch, toAdd[j])
            end
            catalog:withWriteAccessDo("Add photos to mirror", function()
                mirrorColl:addPhotos(batch)
            end, { timeout = 30, asynchronous = true })
            if i + BATCH_SIZE <= #toAdd then
                LrTasks.yield()
            end
        end
    end

    if #toRemove > 0 then
        for i = 1, #toRemove, BATCH_SIZE do
            local batch = {}
            for j = i, math.min(i + BATCH_SIZE - 1, #toRemove) do
                table.insert(batch, toRemove[j])
            end
            catalog:withWriteAccessDo("Remove photos from mirror", function()
                mirrorColl:removePhotos(batch)
            end, { timeout = 30, asynchronous = true })
            if i + BATCH_SIZE <= #toRemove then
                LrTasks.yield()
            end
        end
    end

    return { added = #toAdd, removed = #toRemove, size = #smartPhotos }
end

-- Run full sync for all selected collections
-- progressCallback receives (collectionName, currentIndex, totalCount) and
-- may return false to stop before the next collection.
-- shouldSync (optional) receives tostring(localIdentifier); collections it
-- returns false for are skipped without loading their photos.
-- results.sizes holds the size of every collection synced in this run.
function SyncEngine.runFullSync(selectedIds, destSetName, progressCallback, shouldSync)
    local destSet = SyncEngine.getOrCreateDestinationSet(destSetName)
    local allSmartColls = SyncEngine.getAllSmartCollections()

    local results = {
        totalAdded = 0,
        totalRemoved = 0,
        collectionsProcessed = 0,
        sizes = {},
    }

    -- Build lookup of selected IDs for O(1) checks
    -- Convert all IDs to strings for consistent comparison
    local selectedLookup = {}
    for _, id in ipairs(selectedIds) do
        selectedLookup[tostring(id)] = true
    end

    -- Count total selected for progress
    local total = 0
    for _ in pairs(selectedLookup) do
        total = total + 1
    end

    local current = 0

    -- Process each selected smart collection
    for _, smartColl in ipairs(allSmartColls) do
        local id = tostring(smartColl.localIdentifier)
        if selectedLookup[id] then
            current = current + 1

            if progressCallback and progressCallback(smartColl:getName(), current, total) == false then
                return results
            end

            if not shouldSync or shouldSync(id) then
                local mirror = SyncEngine.getOrCreateMirror(smartColl, destSet)
                local result = SyncEngine.syncCollection(smartColl, mirror)

                results.totalAdded = results.totalAdded + result.added
                results.totalRemoved = results.totalRemoved + result.removed
                results.sizes[id] = result.size
                results.collectionsProcessed = results.collectionsProcessed + 1

                -- Yield between collections to keep Lightroom responsive
                LrTasks.yield()
            end
        end
    end

    -- Clean up orphaned mirrors (smart collection was deleted)
    SyncEngine.cleanupOrphanedMirrors(selectedIds, destSet, allSmartColls)

    return results
end

-- Remove mirror collections for deleted smart collections
function SyncEngine.cleanupOrphanedMirrors(selectedIds, destSet, allSmartColls)
    local catalog = LrApplication.activeCatalog()

    -- Build lookup of selected IDs (convert to strings for consistent comparison)
    local selectedLookup = {}
    for _, id in ipairs(selectedIds) do
        selectedLookup[tostring(id)] = true
    end

    -- Build set of valid smart collection names (only from selected collections)
    local validNames = {}
    for _, sc in ipairs(allSmartColls) do
        if selectedLookup[tostring(sc.localIdentifier)] then
            validNames[sc:getName()] = true
        end
    end

    -- Check mirror collections and delete orphans
    local mirrors = destSet:getChildCollections()
    for _, mirror in ipairs(mirrors) do
        if not validNames[mirror:getName()] then
            catalog:withWriteAccessDo("Remove orphaned mirror", function()
                mirror:delete()
            end, { timeout = 10, asynchronous = true })
        end
    end
end

return SyncEngine
