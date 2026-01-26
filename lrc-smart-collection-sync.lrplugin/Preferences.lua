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

return Preferences
