-- ShutdownApp.lua
-- Called when Lightroom Classic quits (LrShutdownPlugin only runs when the
-- plug-in is unloaded through the Plug-in Manager)

local SmartCollectionSync = require "SmartCollectionSync"

return {
    LrShutdownFunction = function(doneFunction, progressFunction)
        SmartCollectionSync.shutdown()
        doneFunction()
    end,
}
