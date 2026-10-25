return {
    LrSdkVersion = 10.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = "com.donncha.smartcollectionsync",
    LrPluginName = "Smart Collection Sync",
    LrPluginInfoUrl = "https://github.com/donnchawp/lrc-smart-collection-sync",

    LrAuthor = "Donncha O Caoimh",

    LrExportMenuItems = {
        {
            title = "Smart Collection Sync...",
            file = "MenuShowConfig.lua",
        },
        {
            title = "Sync Now",
            file = "MenuSyncNow.lua",
        },
    },

    LrForceInitPlugin = true,
    LrInitPlugin = "InitPlugin.lua",
    LrShutdownPlugin = "ShutdownPlugin.lua",

    VERSION = { major = 1, minor = 0, revision = 0, build = 1 },
}
