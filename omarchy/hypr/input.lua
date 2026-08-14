-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input

hl.config({
  input = {
    -- us + brcustom, switch with Left Alt + Right Alt.
    kb_layout = "us,brcustom",
    kb_options = "caps:escape,grp:alts_toggle",

    repeat_rate = 40,
    repeat_delay = 250,

    numlock_by_default = true,

    -- Mouse: natural (inverse) scrolling + slower scroll speed.
    natural_scroll = true,
    scroll_factor = 0.4,

    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.15,
    },
  },
})
