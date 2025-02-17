cache = ".luacheckcache"
-- https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
  "211/_.*",
  "212/_.*",
  "213/_.*",
}
include_files = { "*.luacheckrc", "lua/**/*.lua", "tests/**/*.lua" }
read_globals = { "vim" }
std = "luajit"

files["lua/tests/**/*.lua"] = {
  read_globals = { "assert" },
}

-- vim: set filetype=lua :
