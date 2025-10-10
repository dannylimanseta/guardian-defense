std = "luajit"

globals = {
    "love",
}

-- Make CI green by relaxing style-only warnings
codes = true
max_line_length = false
unused_args = false

ignore = {
    -- whitespace & length
    "W611", "W612", "W631",
    -- unused/shadowed variables & args
    "W211", "W212", "W213", "W412", "W421", "W231",
}

exclude_files = {
    "assets/**",
    ".luarocks/**",
    ".github/**",
    "src/libs/**",
}


