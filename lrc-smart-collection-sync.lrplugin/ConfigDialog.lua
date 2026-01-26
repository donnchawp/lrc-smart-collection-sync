local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrBinding = import "LrBinding"
local LrFunctionContext = import "LrFunctionContext"

local SyncEngine = require "SyncEngine"
local Preferences = require "Preferences"

local ConfigDialog = {}

-- Show the main configuration dialog
-- Returns: "ok" if saved, "other" if Sync Now clicked, "cancel" if canceled
function ConfigDialog.showDialog()
    local result = nil

    -- Show toast while loading (can be slow on large catalogs)
    LrDialogs.showBezel("Loading Smart Collections...")

    local smartColls = SyncEngine.getAllSmartCollections()
    local selectedIds = Preferences.getSelectedIds()

    LrFunctionContext.callWithContext("ConfigDialog", function(context)
        local f = LrView.osFactory()

        -- Build lookup table for selected IDs
        local selectedLookup = {}
        for _, id in ipairs(selectedIds) do
            selectedLookup[id] = true
        end

        -- Create property table for data binding
        local props = LrBinding.makePropertyTable(context)
        props.destSetName = Preferences.get("destinationSetName")
        props.syncInterval = Preferences.get("syncInterval")
        props.autoSyncEnabled = Preferences.get("autoSyncEnabled")
        props.noSyncInDevelop = Preferences.get("noSyncInDevelop")

        -- Create checkboxes for each smart collection
        local checkboxItems = {}
        for _, sc in ipairs(smartColls) do
            local id = sc.localIdentifier
            local propName = "sc_" .. tostring(id)

            -- Set initial selection state
            props[propName] = selectedLookup[id] == true

            table.insert(checkboxItems, f:checkbox {
                title = sc:getName(),
                value = LrView.bind(propName),
            })
        end

        -- Store smart collections for later use in button actions
        props._smartColls = smartColls

        -- Build the dialog contents
        local contents = f:column {
            spacing = f:control_spacing(),
            bind_to_object = props,

            f:static_text {
                title = "Select smart collections to sync:",
                font = "<system/bold>",
            },

            f:scrolled_view {
                width = 400,
                height = 200,
                f:column(checkboxItems),
            },

            f:row {
                f:push_button {
                    title = "Select All",
                    action = function()
                        for _, sc in ipairs(smartColls) do
                            props["sc_" .. tostring(sc.localIdentifier)] = true
                        end
                    end,
                },
                f:push_button {
                    title = "Select None",
                    action = function()
                        for _, sc in ipairs(smartColls) do
                            props["sc_" .. tostring(sc.localIdentifier)] = false
                        end
                    end,
                },
            },

            f:separator { fill_horizontal = 1 },

            f:row {
                f:static_text { title = "Destination collection set:" },
                f:edit_field {
                    value = LrView.bind("destSetName"),
                    width_in_chars = 30,
                },
            },

            f:row {
                f:static_text { title = "Auto-sync interval:" },
                f:edit_field {
                    value = LrView.bind("syncInterval"),
                    width_in_chars = 5,
                    min = 10,
                    max = 300,
                    precision = 0,
                },
                f:static_text { title = "seconds (10-300)" },
            },

            f:checkbox {
                title = "Enable auto-sync",
                value = LrView.bind("autoSyncEnabled"),
            },

            f:checkbox {
                title = "No sync while in Develop",
                value = LrView.bind("noSyncInDevelop"),
            },

            f:separator { fill_horizontal = 1 },

            f:row {
                f:static_text {
                    title = "Status: " .. ConfigDialog.getStatusText(#selectedIds),
                },
            },

            f:row {
                f:static_text {
                    title = ConfigDialog.getLastSyncText(),
                },
            },
        }

        -- Show the dialog
        result = LrDialogs.presentModalDialog {
            title = "Smart Collection Sync",
            contents = contents,
            actionVerb = "Save",
            otherVerb = "Sync Now",
        }

        -- Handle dialog result
        if result == "ok" or result == "other" then
            -- Gather selected IDs
            local newSelectedIds = {}
            for _, sc in ipairs(smartColls) do
                local id = sc.localIdentifier
                if props["sc_" .. tostring(id)] then
                    table.insert(newSelectedIds, id)
                end
            end

            -- Validate and clamp sync interval
            local interval = tonumber(props.syncInterval) or 30
            interval = math.max(10, math.min(300, interval))

            -- Save preferences
            Preferences.setSelectedIds(newSelectedIds)
            Preferences.set("destinationSetName", props.destSetName)
            Preferences.set("syncInterval", interval)
            Preferences.set("autoSyncEnabled", props.autoSyncEnabled)
            Preferences.set("noSyncInDevelop", props.noSyncInDevelop)
        end
    end)

    return result
end

-- Get status text based on selection count
function ConfigDialog.getStatusText(count)
    if count == 0 then
        return "No smart collections selected"
    elseif count == 1 then
        return "Syncing 1 smart collection"
    else
        return "Syncing " .. count .. " smart collections"
    end
end

-- Get last sync time text
function ConfigDialog.getLastSyncText()
    local lastSync = Preferences.get("lastSyncTime")
    if lastSync == nil then
        return "Last sync: Never"
    end

    local now = os.time()
    local diff = now - lastSync

    if diff < 60 then
        return "Last sync: Just now"
    elseif diff < 3600 then
        local minutes = math.floor(diff / 60)
        if minutes == 1 then
            return "Last sync: 1 minute ago"
        else
            return "Last sync: " .. minutes .. " minutes ago"
        end
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        if hours == 1 then
            return "Last sync: 1 hour ago"
        else
            return "Last sync: " .. hours .. " hours ago"
        end
    else
        local days = math.floor(diff / 86400)
        if days == 1 then
            return "Last sync: 1 day ago"
        else
            return "Last sync: " .. days .. " days ago"
        end
    end
end

return ConfigDialog
