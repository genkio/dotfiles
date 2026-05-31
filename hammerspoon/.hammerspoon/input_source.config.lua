return {
  -- Source aliases keep the app map readable. Values are macOS input source IDs.
  sources = {
    us = "com.apple.keylayout.ABC",
    cn = "com.apple.inputmethod.SCIM.ITABC",
    jp = "com.apple.inputmethod.Japanese",
  },

  -- Keys are app names from Hammerspoon. Bundle IDs also work when needed.
  apps = {
    Ghostty = "us",
    Terminal = "us",
    WeChat = "cn",
  },
}
