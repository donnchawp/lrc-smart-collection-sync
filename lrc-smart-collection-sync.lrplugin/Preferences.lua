local LrPrefs = import "LrPrefs"

local Preferences = {}
local prefs = LrPrefs.prefsForPlugin()

-- Default values
local DEFAULTS = {
    selectedCollectionIds = {},
    destinationSetName = "Smart Collection Sync",
    syncInterval = 30,
    autoSyncEnabled = false,
    noSyncInDevelop = true,
    lastSyncTime = nil,
}

function Preferences.get(key)
    local value = prefs[key]
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

function Preferences.set(key, value)
    prefs[key] = value
end

function Preferences.getSelectedIds()
    return Preferences.get("selectedCollectionIds") or {}
end

function Preferences.setSelectedIds(ids)
    Preferences.set("selectedCollectionIds", ids)
end

-- Photo counts from earlier syncs, keyed by tostring(localIdentifier)
function Preferences.getCollectionSizes()
    return Preferences.get("collectionSizes") or {}
end

-- Merge newly measured sizes into the stored ones. Assigns a new table
-- because LrPrefs only saves values assigned to a top-level key.
function Preferences.recordCollectionSizes(sizes)
    local stored = {}
    for id, size in pairs(Preferences.getCollectionSizes()) do
        stored[id] = size
    end
    for id, size in pairs(sizes) do
        stored[id] = size
    end
    Preferences.set("collectionSizes", stored)
end

return Preferences
