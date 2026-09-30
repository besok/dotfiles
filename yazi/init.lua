-- Plugin setup. Plugins themselves are installed by `ya pkg install` from
-- package.toml (install.sh runs it); plugins/ and flavors/ are gitignored.

-- Rounded border around the whole UI
require("full-border"):setup { type = ui.Border.ROUNDED }

-- Git status signs in the file list (fetchers registered in yazi.toml)
require("git"):setup()

-- l / Right: enter directory or open file; open all selected files at once
require("smart-enter"):setup { open_multi = true }
