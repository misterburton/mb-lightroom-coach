return {
  LrSdkVersion = 12.0,
  LrSdkMinimumVersion = 12.0,
  
  LrToolkitIdentifier = 'com.misterburton.lightroomcoach',
  LrPluginName = LOC "$$$/LightroomCoach/PluginName=Lightroom Coach",
  
  LrPluginInfoProvider = 'Prefs.lua',
  
  LrExportMenuItems = {
    {
      title = LOC "$$$/LightroomCoach/MenuTitle=Lightroom Coach",
      file = "PluginInit.lua",
    },
  },
  
  VERSION = { major = 2, minor = 2, revision = 0, build = 0 },
  
  -- NOTE: For update checking, also update CURRENT_VERSION in ChatDialog.lua
}