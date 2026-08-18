-- LayoutRR: window layout save/restore, compositor-side (Hyprland Lua API).
-- Requirements + usage: ~/.config/hypr/layout.md
--
--   LayoutRR.save({ file? })                 snapshot mapped windows + per-monitor
--                                            state -> layout-data.lua (v2), regen
--                                            splash rules -> layout-rules.lua
--   LayoutRR.restore({ force?, dry_run?,     adopt existing windows, launch the
--                      file?, boot? })       missing ones into a hidden staging
--                                            workspace, then rebuild each
--                                            workspace's dwindle tree from the
--                                            saved geometry, verify, report.
--
-- Entry points: CTRL+ALT+L -> save (bindings.lua); ~/.local/bin/layout-save,
-- ~/.local/bin/layout-boot (hyprctl dispatch shims); boot via hyprland.start.
-- User knobs: ~/.config/hypr/layout-overrides.lua (never regenerated).
-- Logs: ~/.local/state/layout-rr/{save,restore}.log (+ restore.prev.log,
--       restore.dry.log for --dry-run, restore.skipped.log for guard/error exits).
-- Escape hatch: `layout-boot --reset` (LayoutRR.reset) forgets a run and
-- moves windows out of the staging workspace.
--
-- Testing (never against the boot spec):
--   layout-save --file /tmp/x.lua && layout-boot --dry-run --file /tmp/x.lua
--   layout-boot --file /tmp/x.lua        # adopts everything, should be a no-op
--
-- Facts this code relies on (probed on Hyprland 0.56.2):
--   * hl.exec_cmd(cmd, rules) applies rules by PID; tag="+x" shows up in
--     w.tags as "x*"; workspace="special:foo silent" files the window without
--     showing the special. window.open fires after rules are applied.
--   * `hyprctl reload` wipes ALL Lua state: globals, timers, subscriptions.
--     A restore in flight when the config reloads is simply abandoned (see
--     layout.md N2); nothing can survive it, so nothing tries to.
--   * hl.on() returns a subscription with :remove(); hl.timer() returns a
--     handle with :set_enabled(false).

local HOME = os.getenv("HOME") or ""
local CFG = HOME .. "/.config/hypr"
local PATHS = {
  spec = CFG .. "/layout-data.lua",
  rules = CFG .. "/layout-rules.lua",
  overrides = CFG .. "/layout-overrides.lua",
  state = HOME .. "/.local/state/layout-rr",
}
PATHS.restore_log = PATHS.state .. "/restore.log"
PATHS.restore_prev = PATHS.state .. "/restore.prev.log"
PATHS.save_log = PATHS.state .. "/save.log"

local STAGING = "special:layoutrr"
local TAG_PREFIX = "layoutrr-"

LayoutRR = LayoutRR or {}
LayoutRR.paths = PATHS

-- ------------------------------------------------------------- helpers ----

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

-- Written to layout-overrides.lua when that file is missing (S6). Keep in
-- sync with the DEFAULTS above; the file is never regenerated once present.
local OVERRIDES_TEMPLATE = [==[
-- LayoutRR user overrides. This file is YOURS: hand-edit freely, it is never
-- regenerated. It is re-read on every save/restore, no `hyprctl reload`
-- needed. Anything left out falls back to the defaults in layout.lua.
--
-- Placeholders in commands: {url} -> urls[<workspace>] for that row.
return {
  -- class -> launch command. Classes not listed here are resolved as:
  --   chrome-web.<domain>__-Default  -> omarchy-launch-webapp https://<domain>/
  --   <class>.desktop exists          -> gtk-launch <class>
  --   otherwise                       -> <class> (run as a command)
  commands = {
    -- --gtk-single-instance=false: a fresh process per window, so Hyprland's
    -- per-PID exec rules (tag + staging workspace) can attach to it.
    ["com.mitchellh.ghostty"] = "ghostty --gtk-single-instance=false",
    ["org.telegram.desktop"] = "telegram-desktop",
    ["chrome-web.whatsapp.com__-Default"] = "omarchy-launch-webapp https://web.whatsapp.com/",
    ["chromium"] = "chromium --new-window",
    ["org.omarchy.agent"] = "omarchy agent",
    ["localsend"] = "gtk-launch localsend",
    ["org.localsend.localsend_app"] = "gtk-launch localsend",
    ["google-chrome"] = "google-chrome-stable --new-window {url}",
    ["steam"] = "steam",
    ["discord"] = "discord",
  },

  -- Classes whose launch command hands the window off to an already-running
  -- process (so Hyprland's per-PID exec rules can't tag/file the window).
  -- These are launched strictly one at a time and claimed as "first new
  -- window of that class since the launch".
  no_pid_rules = {
    ["google-chrome"] = true,
    ["chromium"] = true,
  },

  -- Saved class -> class the app maps with today (app-id changed after an update).
  aliases = {
    ["localsend"] = "org.localsend.localsend_app",
  },

  -- workspace -> URL substituted for {url} (google-chrome slots). Workspaces
  -- without an entry get an empty {url} (blank window).
  urls = {
    ["2"] = "https://youtube.com",
    ["special:scratchpad"] = "https://claude.ai/code",
    ["special:scratch2"] = "https://mail.google.com",
  },

  -- Splash-screen apps: they map a loader window first, so they are placed by
  -- the static rules in layout-rules.lua (regenerated on save) instead of by
  -- the restore engine. Launched, but never claimed/placed/verified.
  splashy = {
    steam = true,
    discord = true,
  },

  -- Classes never saved nor restored: exact class names (`["foo"] = true`)
  -- or Lua patterns given as list entries. Steam games map as
  -- steam_app_<id>: they can't be relaunched, so keep them out of the spec.
  ignore = { "^steam_app_%d+$" },

  timeouts = {
    monitors = 15000,   -- ms to wait for the monitors named in the spec
    window = 30000,     -- ms per launched window before it's marked FAILED
    total = 120000,     -- ms hard cap for the whole run
    resize_passes = 6,  -- measure-and-correct passes per workspace
    step = 60,          -- ms between compositor steps inside a workspace
  },
  tolerance_px = 4,
}
]==]

-- Defaults = the template itself, so a broken/missing overrides file still
-- launches apps with the right commands.
local DEFAULTS = load(OVERRIDES_TEMPLATE)()

local function load_overrides()
  if not file_exists(PATHS.overrides) then
    local f = io.open(PATHS.overrides, "w")
    if f then f:write(OVERRIDES_TEMPLATE); f:close() end
  end
  local cfg = {}
  for k, v in pairs(DEFAULTS) do
    if type(v) == "table" then
      cfg[k] = {}
      for kk, vv in pairs(v) do cfg[k][kk] = vv end
    else
      cfg[k] = v
    end
  end
  local ok, user = pcall(dofile, PATHS.overrides)
  if ok and type(user) == "table" then
    for k, v in pairs(user) do
      if type(v) == "table" and type(cfg[k]) == "table" then
        for kk, vv in pairs(v) do
          if type(kk) == "number" then
            local dup = false
            for _, x in ipairs(cfg[k]) do if x == vv then dup = true end end
            if not dup then table.insert(cfg[k], vv) end
          else
            cfg[k][kk] = vv
          end
        end
      else
        cfg[k] = v
      end
    end
  end
  if not ok then
    cfg._overrides_error = tostring(user)
    if not LayoutRR._overrides_notified then
      LayoutRR._overrides_notified = true
      hl.exec_cmd("notify-send -a omarchy-action -u critical layout " .. o.shell_quote("layout-overrides.lua is broken, using defaults: " .. tostring(user)))
    end
  end
  return cfg
end

-- app_name "omarchy-action" is omarchy-shell's DND-bypass allowlist: these are
-- user-action confirmations, so they show even with Do Not Disturb on.
local function notify(urgency, msg)
  hl.exec_cmd("notify-send -a omarchy-action -u " .. urgency .. " layout " .. o.shell_quote(msg))
end

local function vec(v)
  if type(v) ~= "table" then return 0, 0 end
  return math.floor(v.x or v[1] or 0), math.floor(v.y or v[2] or 0)
end

local function ensure_state_dir()
  os.execute("mkdir -p " .. o.shell_quote(PATHS.state))
end

-- Logger writing timestamped lines to a file (opened per line: cheap, and a
-- crash never loses buffered output).
-- wall-clock seconds with sub-second resolution (os.clock is CPU time)
local function now()
  local f = io.open("/proc/uptime", "r")
  if f then
    local s = f:read("*l"); f:close()
    local v = s and tonumber(s:match("^(%S+)"))
    if v then return v end
  end
  return os.time()
end

-- Logger. Until L.commit(path) is called lines are buffered in memory; commit
-- decides the file (so a dry run or a guard skip never rotates the log of the
-- previous real run). Lines are then appended one by one (a crash never loses
-- buffered output). Files above `cap` bytes are truncated on open.
local function make_logger(cap)
  ensure_state_dir()
  local t0 = now()
  local L = { t0 = t0, buf = {}, path = nil }
  local function write(line)
    local f = io.open(L.path, "a")
    if f then f:write(line); f:close() end
  end
  function L.log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local line = string.format("%s +%6.2fs  %s\n", os.date("%H:%M:%S"), now() - t0, msg)
    if L.path then write(line) else L.buf[#L.buf + 1] = line end
  end
  function L.commit(path, rotate_to)
    if L.path then return end
    if rotate_to and file_exists(path) then os.rename(path, rotate_to) end
    if cap and file_exists(path) then
      local f = io.open(path, "r")
      local size = f and f:seek("end") or 0
      if f then f:close() end
      if size > cap then os.remove(path) end
    end
    L.path = path
    for _, line in ipairs(L.buf) do write(line) end
    L.buf = {}
  end
  return L
end

local function is_special(ws) return ws:match("^special:") ~= nil end
local function special_name(ws) return ws:match("^special:(.+)$") end

local function has_tag(w, tag)
  if type(w.tags) ~= "table" then return false end
  for _, t in ipairs(w.tags) do
    if t == tag or t == tag .. "*" then return true end
  end
  return false
end

local function cmd_exists(cmd)
  local bin = cmd:match("^%s*(%S+)")
  if not bin then return false end
  if bin:find("/") then return file_exists(bin) end
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    if file_exists(dir .. "/" .. bin) then return true end
  end
  return false
end

local function resolve_cmd(cfg, class, ws)
  local cmd = cfg.commands[class]
  if not cmd then
    local domain = class:match("^chrome%-web%.(.+)__%-Default$")
    if domain then
      cmd = "omarchy-launch-webapp https://" .. domain .. "/"
    elseif file_exists(HOME .. "/.local/share/applications/" .. class .. ".desktop")
        or file_exists("/usr/share/applications/" .. class .. ".desktop") then
      cmd = "gtk-launch " .. class
    else
      cmd = class
    end
  end
  local url = cfg.urls[ws] or ""
  cmd = cmd:gsub("{url}", function() return url end) -- fn: '%' in URLs is literal
  return (cmd:gsub("%s+$", ""))
end

-- ignore = { ["exact.class"] = true, "^lua_pattern$", ... }
local function is_ignored(cfg, class)
  if not class or class == "" then return false end
  local ig = cfg.ignore or {}
  if ig[class] then return true end
  for _, pat in ipairs(ig) do
    if type(pat) == "string" and class:match(pat) then return true end
  end
  return false
end

local function class_matches(cfg, saved, actual)
  return actual == saved or actual == cfg.aliases[saved]
end

-- ---------------------------------------------------------------- save ----

local function load_spec(path)
  local ok, spec = pcall(dofile, path)
  if not ok or type(spec) ~= "table" then return nil, tostring(spec) end
  if spec.version == nil then -- v1: plain array of rows
    spec = { version = 1, monitors = {}, windows = spec }
  end
  if type(spec.windows) ~= "table" or #spec.windows == 0 then return nil, "empty spec" end
  return spec
end

function LayoutRR.save(opts)
  opts = opts or {}
  local cfg = load_overrides()
  local L = make_logger(512 * 1024)
  L.commit(PATHS.save_log)
  local out = opts.file or PATHS.spec
  L.log("save -> %s", out)
  if cfg._overrides_error then L.log("overrides error (using defaults): %s", cfg._overrides_error) end

  local rows = {}
  local focused_addr = hl.get_active_window() and hl.get_active_window().address
  for _, w in ipairs(hl.get_windows()) do
    if w.mapped and not w.hidden and is_ignored(cfg, w.class) then
      L.log("  ignored %s (matches `ignore` in layout-overrides.lua)", w.class)
    end
    if w.mapped and not w.hidden and w.workspace and w.workspace.name ~= ""
        and w.class ~= "" and not is_ignored(cfg, w.class) and w.workspace.name ~= STAGING then
      local x, y = vec(w.at)
      local sw, sh = vec(w.size)
      rows[#rows + 1] = {
        class = w.class, initial_class = w.initial_class or "", title = w.title or "",
        ws = w.workspace.name, mon = w.monitor and w.monitor.name or "",
        floating = w.floating and true or false, pinned = w.pinned and true or false,
        fullscreen = tonumber(w.fullscreen) or 0,
        x = x, y = y, w = sw, h = sh, pid = tonumber(w.pid) or 0,
        _addr = w.address,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.ws ~= b.ws then return a.ws < b.ws end
    if a.x ~= b.x then return a.x < b.x end
    if a.y ~= b.y then return a.y < b.y end
    return a.class < b.class
  end)
  local focused = nil
  for i, r in ipairs(rows) do if r._addr == focused_addr then focused = i end end

  local mons = {}
  local focused_mon = hl.get_active_monitor() and hl.get_active_monitor().name
  for _, m in ipairs(hl.get_monitors()) do
    local aw = m.active_workspace
    local asw = m.active_special_workspace
    mons[#mons + 1] = {
      name = m.name,
      active = aw and aw.name or "",
      special = (asw and asw.name ~= "" and asw.name ~= STAGING) and asw.name or nil,
      focused = (m.name == focused_mon),
    }
  end
  table.sort(mons, function(a, b) return a.name < b.name end)

  local stranded = 0
  for _, w in ipairs(hl.get_windows()) do
    if w.mapped and w.workspace and w.workspace.name == STAGING then stranded = stranded + 1 end
  end
  if stranded > 0 then
    L.log("WARNING: %d window(s) stranded in %s (not saved) -- run `layout-boot --reset` / move them out", stranded, STAGING)
    notify("normal", string.format("layout: %d window(s) stranded in %s, not saved", stranded, STAGING))
  end

  if #rows == 0 then
    L.log("nothing to save")
    notify("critical", "layout: no windows to save")
    return false
  end

  if file_exists(out) then os.rename(out, out .. ".bak") end
  local f = io.open(out, "w")
  if not f then
    notify("critical", "layout: cannot write " .. out)
    return false
  end
  f:write("-- AUTO-GENERATED by LayoutRR.save() -- do not edit by hand.\n")
  f:write("-- Knobs live in layout-overrides.lua. Previous version: <this file>.bak\n")
  f:write("return {\n  version = 2,\n  monitors = {\n")
  for _, m in ipairs(mons) do
    f:write(string.format("    { name = %q, active = %q, special = %s, focused = %s },\n",
      m.name, m.active, m.special and string.format("%q", m.special) or "nil", tostring(m.focused)))
  end
  f:write("  },\n")
  f:write(string.format("  focused = %s,\n", focused and tostring(focused) or "nil"))
  f:write("  windows = {\n")
  for _, r in ipairs(rows) do
    -- no title/pid: they change between otherwise identical saves (N4)
    f:write(string.format(
      "    { class = %q, ws = %q, mon = %q, floating = %s, pinned = %s, fullscreen = %d, x = %d, y = %d, w = %d, h = %d, initial_class = %q },\n",
      r.class, r.ws, r.mon, tostring(r.floating), tostring(r.pinned), r.fullscreen,
      r.x, r.y, r.w, r.h, r.initial_class))
  end
  f:write("  },\n}\n")
  f:close()

  -- static rules for splash-screen apps (only for the real spec)
  if not opts.file then
    local rf = io.open(PATHS.rules, "w")
    if rf then
      rf:write("-- AUTO-GENERATED by LayoutRR.save() -- do not edit by hand.\n")
      rf:write("-- Splash-screen apps (see `splashy` in layout-overrides.lua) are placed by a\n")
      rf:write("-- static rule because they map a loader window first, which defeats\n")
      rf:write("-- timing-based placement. Anchored class match, so Steam *games* are unaffected.\n\n")
      for _, r in ipairs(rows) do
        if cfg.splashy[r.class] then
          rf:write(string.format('o.window("^(%s)$", { workspace = %q })\n', r.class, r.ws .. " silent"))
          if r.floating then
            rf:write(string.format('o.window("^(%s)$", { float = true, size = "%d %d" })\n', r.class, r.w, r.h))
          end
        end
      end
      rf:close()
    end
  end

  local nws = {}
  local wsc = 0
  for _, r in ipairs(rows) do if not nws[r.ws] then nws[r.ws] = true; wsc = wsc + 1 end end
  for _, r in ipairs(rows) do
    L.log("  %-38s ws=%-18s mon=%-8s %s %4dx%-4d @ %d,%d", r.class, r.ws, r.mon,
      r.floating and "float" or "tile ", r.w, r.h, r.x, r.y)
  end
  L.log("saved %d windows, %d workspaces, focused=%s", #rows, wsc, tostring(focused))
  notify("low", string.format("saved %d windows (%d workspaces)", #rows, wsc))
  return true
end

-- --------------------------------------------------- dwindle tree model ----
-- Recursively partition saved rectangles by a straight cut that leaves every
-- rect entirely on one side. Leaves are rows. Node = { dir = "H"|"V", a, b,
-- rep } where `rep` is the first leaf (used as insertion anchor).

local function build_tree(rows, tol)
  if #rows == 1 then return { leaf = rows[1], rep = rows[1] } end
  local function try(dir)
    local best
    for _, r in ipairs(rows) do
      local cut = (dir == "H") and (r.x + r.w) or (r.y + r.h)
      local a, b = {}, {}
      local okcut = true
      for _, s in ipairs(rows) do
        local lo = (dir == "H") and s.x or s.y
        local hi = lo + ((dir == "H") and s.w or s.h)
        if hi <= cut + tol then a[#a + 1] = s
        elseif lo >= cut - tol then b[#b + 1] = s
        else okcut = false; break end
      end
      if okcut and #a > 0 and #b > 0 then
        -- prefer the cut closest to the middle to keep trees balanced-ish;
        -- any valid cut reproduces the geometry.
        if not best or math.abs(#a - #b) < math.abs(#best.a - #best.b) then
          best = { a = a, b = b }
        end
      end
    end
    return best
  end
  local cut = try("H")
  local dir = "H"
  if not cut then cut = try("V"); dir = "V" end
  if not cut then
    -- degenerate geometry (overlaps / bad save): fall back to a chain
    local first, rest = rows[1], {}
    for i = 2, #rows do rest[#rest + 1] = rows[i] end
    cut = { a = { first }, b = rest }
    dir = math.abs(rest[1].x - first.x) >= math.abs(rest[1].y - first.y) and "H" or "V"
  end
  local A = build_tree(cut.a, tol)
  local B = build_tree(cut.b, tol)
  return { dir = dir, a = A, b = B, rep = A.rep }
end

-- bounding box of a subtree in saved coordinates
local function bbox(node)
  if node.leaf then
    local r = node.leaf
    return r.x, r.y, r.x + r.w, r.y + r.h
  end
  local ax0, ay0, ax1, ay1 = bbox(node.a)
  local bx0, by0, bx1, by1 = bbox(node.b)
  return math.min(ax0, bx0), math.min(ay0, by0), math.max(ax1, bx1), math.max(ay1, by1)
end

-- ------------------------------------------------------------- restore ----

function LayoutRR.restore(opts)
  opts = opts or {}
  if LayoutRR._run then
    notify("normal", "layout: restore already running")
    return false
  end

  local cfg = load_overrides()
  ensure_state_dir()
  local L = make_logger(512 * 1024) -- cap applies to dry/skipped logs; restore.log rotates
  local log = L.log
  local T = cfg.timeouts

  local run = {
    subs = {}, timers = {}, finished = false, opened_specials = {}, dry = opts.dry_run and true or false,
    boot = opts.boot and true or false, id = tostring(os.time() % 100000),
  }
  LayoutRR._run = run
  local finalize, check_progress -- forward (defined in phases B/C)

  -- --- lifecycle -----------------------------------------------------------
  -- Any Lua error inside a timer/event callback: log it, run the end-state
  -- pass (closes specials, restores focus) if that hasn't happened yet, and
  -- always finish() -- a run can never wedge or leave the desktop half-done.
  local function on_error(where, err)
    log("ERROR in %s: %s", where, tostring(err))
    run.error = run.error or tostring(err)
    run.finish_reason = "error"
    if finalize and not run.finalized then
      local ok, e2 = pcall(finalize)
      if not ok then log("ERROR in finalize after error: %s", tostring(e2)) end
    end
    if not run.finalized or run.error then run.finish() end
  end
  local function add_timer(ms, fn)
    local t
    t = hl.timer(function()
      if run.finished then return end
      local ok, err = pcall(fn)
      if not ok then on_error("timer", err) end
    end, { timeout = math.max(1, math.floor(ms)), type = "oneshot" })
    run.timers[#run.timers + 1] = t
    return t
  end
  local function subscribe(ev, fn)
    local s = hl.on(ev, function(...)
      if run.finished then return end
      local ok, err = pcall(fn, ...)
      if not ok then on_error(ev .. " handler", err) end
    end)
    run.subs[#run.subs + 1] = s
  end
  local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("ERROR: %s", tostring(err)) end
    return ok
  end

  function run.finish()
    if run.finished then return end
    run.finished = true
    if not L.path then L.commit(PATHS.state .. "/restore.skipped.log") end
    for _, s in ipairs(run.subs) do pcall(function() s:remove() end) end
    for _, t in ipairs(run.timers) do pcall(function() t:set_enabled(false) end) end
    LayoutRR._run = nil
    if run.error then notify("critical", "layout error: " .. run.error .. " (see restore.log)") end
    log("finished (%s)", tostring(run.finish_reason or "ok"))
  end

  -- Everything below runs inside pcall so a throw (bad spec row, API change)
  -- can never leave LayoutRR._run set (R1/R18).
  local body_ok, body_res = pcall(function()
  local spec, err = load_spec(opts.file or PATHS.spec)
  if not spec then
    log("no usable spec: %s", tostring(err))
    notify("critical", "layout: no layout saved (" .. tostring(err) .. ")")
    run.finish_reason = "no spec"
    run.finish()
    return false
  end
  log("restore start id=%s file=%s boot=%s dry_run=%s force=%s spec v%s (%d windows)",
    run.id, opts.file or PATHS.spec, tostring(run.boot), tostring(run.dry), tostring(opts.force),
    tostring(spec.version), #spec.windows)
  if cfg._overrides_error then log("overrides error (using defaults): %s", cfg._overrides_error) end

  -- --- rows ----------------------------------------------------------------
  -- row fields added at runtime: idx, kind (adopt|launch|static|ignored),
  -- addr (claimed window address), state (pending|claimed|failed|missing|static),
  -- cmd, tag, launched_at
  local rows = {}
  for i, r in ipairs(spec.windows) do
    local row = {}
    for k, v in pairs(r) do row[k] = v end
    row.idx = i
    row.state = "pending"
    if is_ignored(cfg, row.class) then
      row.kind, row.state = "ignored", "ignored"
    elseif cfg.splashy[row.class] then
      row.kind, row.state = "static", "static"
    end
    rows[#rows + 1] = row
  end

  -- --- boot guard ----------------------------------------------------------
  if run.boot and not opts.force then
    local specclasses = {}
    for _, r in ipairs(rows) do if r.kind ~= "static" and r.kind ~= "ignored" then specclasses[r.class] = true end end
    for _, w in ipairs(hl.get_windows()) do
      local hit = false
      if w.mapped then
        for c in pairs(specclasses) do if class_matches(cfg, c, w.class) then hit = true end end
      end
      if hit then
        log("boot guard: %s already open -> session not fresh, skipping", w.class)
        notify("normal", "layout: session not fresh (" .. w.class .. " open); restore skipped")
        run.finish_reason = "boot guard"
        run.finish()
        return false
      end
    end
  end

  -- --- workspaces order ----------------------------------------------------
  local order, by_ws = {}, {}
  for _, r in ipairs(rows) do
    if r.kind ~= "static" and r.kind ~= "ignored" then
      if not by_ws[r.ws] then by_ws[r.ws] = { rows = {}, ws = r.ws, mon = r.mon, placed = false }; order[#order + 1] = r.ws end
      table.insert(by_ws[r.ws].rows, r)
    end
  end
  table.sort(order, function(a, b)
    local sa, sb = is_special(a) and 1 or 0, is_special(b) and 1 or 0
    if sa ~= sb then return sa < sb end
    return a < b
  end)

  -- monitor fallback
  local function monitor_for(name)
    if name and name ~= "" and hl.get_monitor(name) then return name end
    local m = hl.get_active_monitor()
    return m and m.name or ""
  end

  -- --- adoption plan -------------------------------------------------------
  local claimed = {} -- addr -> row
  local function plan()
    local unclaimed = {}
    for _, w in ipairs(hl.get_windows()) do
      if w.mapped and not w.hidden then unclaimed[#unclaimed + 1] = w end
    end
    -- pass 1: only windows already on the row's workspace (closest geometry
    -- first); pass 2: anything left of that class anywhere. Two passes so a
    -- row can never steal a window that another row has sitting in place.
    for pass = 1, 2 do
      for _, r in ipairs(rows) do
        if r.state == "pending" and not r.addr then
          local cands = {}
          for _, w in ipairs(unclaimed) do
            local same_ws = w.workspace and w.workspace.name == r.ws
            if not claimed[w.address] and class_matches(cfg, r.class, w.class) and (pass == 2 or same_ws) then
              cands[#cands + 1] = w
            end
          end
          table.sort(cands, function(a, b)
            local ax, ay = vec(a.at)
            local bx, by = vec(b.at)
            local da = math.abs(ax - r.x) + math.abs(ay - r.y)
            local db = math.abs(bx - r.x) + math.abs(by - r.y)
            if da ~= db then return da < db end
            return a.address < b.address
          end)
          if cands[1] then
            r.kind, r.state, r.addr = "adopt", "claimed", cands[1].address
            claimed[cands[1].address] = r
          end
        end
      end
    end
    for _, r in ipairs(rows) do
      if r.state == "pending" and not r.addr then
        r.kind = "launch"
        r.cmd = resolve_cmd(cfg, r.class, r.ws)
        r.sequential = cfg.no_pid_rules[r.class] and true or false
        if not cmd_exists(r.cmd) then r.state = "missing" end
      end
    end
  end
  plan()

  log("plan:")
  local n_launch, n_adopt = 0, 0
  for _, r in ipairs(rows) do
    local how = r.kind
    if r.kind == "adopt" then how = "adopt " .. r.addr; n_adopt = n_adopt + 1
    elseif r.kind == "launch" then
      how = (r.state == "missing" and "MISSING_APP " or (r.sequential and "launch(seq) " or "launch ")) .. r.cmd
      if r.state ~= "missing" then n_launch = n_launch + 1 end
    end
    log("  #%-2d %-38s ws=%-18s mon=%-8s%s %s", r.idx, r.class, r.ws, r.mon,
      (r.mon ~= "" and not hl.get_monitor(r.mon)) and "(absent->" .. monitor_for(r.mon) .. ")" or "", how)
  end
  log("plan: %d adopt, %d launch", n_adopt, n_launch)

  if run.dry then
    L.commit(PATHS.state .. "/restore.dry.log")
    notify("low", string.format("layout dry-run: %d adopt, %d launch (see restore.dry.log)", n_adopt, n_launch))
    run.finish_reason = "dry run"
    run.finish()
    return true
  end
  L.commit(PATHS.restore_log, PATHS.restore_prev) -- a real run: rotate the previous one
  if run.boot then notify("low", "restoring layout…") end

  -- =========================================================================
  -- Phase A: acquire windows (adopt done; launch the rest, event-driven)
  -- =========================================================================
  local acquisition_done = false
  local placement_busy = false
  local seq_queue = {}   -- sequential-launch rows in spec order
  local seq_current = nil
  local snapshot = {}    -- addresses existing when the current sequential launch fired

  local function claim(row, w, how)
    row.state, row.addr = "claimed", w.address
    claimed[w.address] = row
    log("claimed #%d %s -> %s (%s) ws=%s", row.idx, row.class, w.address, how,
      w.workspace and w.workspace.name or "?")
    -- keep it out of sight until placement (R8)
    if not (w.workspace and w.workspace.name == STAGING) then
      hl.dispatch(hl.dsp.window.move({ workspace = STAGING, follow = false, window = w }))
    end
    if seq_current == row then
      seq_current = nil
    end
  end

  local function fail_row(row, why)
    if row.state ~= "pending" then return end
    row.state = "failed"
    log("FAILED #%d %s: %s", row.idx, row.class, why)
    if seq_current == row then seq_current = nil end
  end

  -- A window of the row's class that showed up since plan() (monitor wait,
  -- an app opening a second toplevel, Chrome restoring extra windows) is
  -- adopted instead of launching a duplicate (R5/G2).
  local dying = {} -- addresses seen in window.close: never (re)claim them
  local function adopt_now(row)
    for _, w in ipairs(hl.get_windows()) do
      if w.mapped and not w.hidden and not claimed[w.address] and not dying[w.address]
          and class_matches(cfg, row.class, w.class) then
        claim(row, w, "late-adopt")
        return true
      end
    end
    return false
  end

  local launch_rules_str = 'tag=+<tag> workspace="' .. STAGING .. ' silent" no_initial_focus'
  local function launch_next_sequential()
    if seq_current or run.finished then return end
    local row = table.remove(seq_queue, 1)
    while row and row.state ~= "pending" do row = table.remove(seq_queue, 1) end
    if not row then return end
    if adopt_now(row) then
      check_progress()
      return launch_next_sequential()
    end
    seq_current = row
    snapshot = {}
    for _, w in ipairs(hl.get_windows()) do snapshot[w.address] = true end
    row.launched_at = now()
    log("launch(seq) #%d %s: %s  [rules: %s]", row.idx, row.class, row.cmd, launch_rules_str)
    hl.exec_cmd(row.cmd, { tag = "+" .. row.tag, workspace = STAGING .. " silent", no_initial_focus = true })
    add_timer(T.window, function()
      if row.state == "pending" then
        fail_row(row, "timeout after " .. T.window .. "ms")
        launch_next_sequential()
        check_progress()
      end
    end)
  end

  -- launch (or queue) one pending row; used at start and when a claimed
  -- window disappears before placement (#15)
  local function launch_row(r)
    r.tag = TAG_PREFIX .. run.id .. "-" .. r.idx
    if r.sequential then
      seq_queue[#seq_queue + 1] = r
      return
    end
    if adopt_now(r) then return end
    r.launched_at = now()
    log("launch #%d %s: %s  [rules: %s]", r.idx, r.class, r.cmd, launch_rules_str)
    hl.exec_cmd(r.cmd, { tag = "+" .. r.tag, workspace = STAGING .. " silent", no_initial_focus = true })
    add_timer(T.window, function()
      if r.state == "pending" then
        fail_row(r, "timeout after " .. T.window .. "ms")
        check_progress()
      end
    end)
  end

  -- try to match an unclaimed mapped window against pending rows
  local function consider(w, why)
    if not w or not w.mapped or claimed[w.address] or dying[w.address] then return end
    -- 1) exact tag from a PID-rule launch
    for _, r in ipairs(rows) do
      if r.state == "pending" and r.kind == "launch" and r.tag and has_tag(w, r.tag) then
        claim(r, w, "tag " .. why)
        launch_next_sequential()
        check_progress()
        return
      end
    end
    -- 2) the sequential launch in flight: first new window of that class
    if seq_current and seq_current.state == "pending" and not snapshot[w.address]
        and class_matches(cfg, seq_current.class, w.class) then
      claim(seq_current, w, "seq-new " .. why)
      launch_next_sequential()
      check_progress()
      return
    end
    -- 3) a parallel launch whose PID rule didn't stick: class match, oldest first
    for _, r in ipairs(rows) do
      if r.state == "pending" and r.kind == "launch" and not r.sequential and r.launched_at
          and class_matches(cfg, r.class, w.class) then
        claim(r, w, "class-fallback " .. why)
        check_progress()
        return
      end
    end
  end

  subscribe("window.open", function(w) consider(w, "window.open") end)
  subscribe("window.class", function(w) consider(w, "window.class") end)
  -- low-frequency sweep for missed events / windows mapped later
  local function sweep()
    if acquisition_done then return end
    for _, w in ipairs(hl.get_windows()) do consider(w, "sweep") end
    add_timer(1000, sweep)
  end

  local function start_launches()
    for _, r in ipairs(rows) do
      if r.kind == "static" then
        local okc, cmd = pcall(resolve_cmd, cfg, r.class, r.ws)
        if not okc then cmd = "" end
        if cmd_exists(cmd) then
          local already = false
          for _, w in ipairs(hl.get_windows()) do if w.mapped and class_matches(cfg, r.class, w.class) then already = true end end
          if not already then
            log("launch(static) #%d %s: %s", r.idx, r.class, cmd)
            hl.exec_cmd(cmd)
          else
            log("static #%d %s already running", r.idx, r.class)
          end
        else
          log("static #%d %s: command not found (%s)", r.idx, r.class, cmd)
        end
      elseif r.kind == "launch" and r.state == "pending" then
        local ok, err = pcall(launch_row, r)
        if not ok then fail_row(r, "launch error: " .. tostring(err)) end
      end
    end
    launch_next_sequential()
    add_timer(1000, sweep)
  end

  -- a claimed window that closes before its workspace is placed: give the
  -- row another chance (the real window may still be coming, or relaunch)
  subscribe("window.close", function(w)
    if not w then return end
    dying[w.address] = true
    local row = claimed[w.address]
    if not row or row.state ~= "claimed" then return end
    local entry = by_ws[row.ws]
    if entry and (entry.placed or entry.placing) then return end
    log("window %s of #%d %s closed before placement -> pending again", w.address, row.idx, row.class)
    claimed[w.address] = nil
    row.addr, row.state, row.kind = nil, "pending", "launch"
    row.cmd = row.cmd or resolve_cmd(cfg, row.class, row.ws)
    row.sequential = cfg.no_pid_rules[row.class] and true or false
    if not cmd_exists(row.cmd) then row.state = "missing"; return check_progress() end
    local ok, err = pcall(launch_row, row)
    if not ok then fail_row(row, "launch error: " .. tostring(err)) end
    launch_next_sequential()
  end)

  -- =========================================================================
  -- Phase B: place workspaces (sequential, each as soon as it's resolved)
  -- =========================================================================
  local function ws_resolved(entry)
    for _, r in ipairs(entry.rows) do if r.state == "pending" then return false end end
    return true
  end

  local function live(row)
    if not row.addr then return nil end
    local w = hl.get_window("address:" .. row.addr)
    if w and w.mapped then return w end
    return nil
  end

  -- geometry check for one row against its live window
  local function row_ok(row, w)
    if not w then return false, "no window" end
    if not (w.workspace and w.workspace.name == row.ws) then return false, "ws=" .. tostring(w.workspace and w.workspace.name) end
    if (w.floating and true or false) ~= (row.floating and true or false) then return false, "floating=" .. tostring(w.floating) end
    if (tonumber(w.fullscreen) or 0) ~= (row.fullscreen or 0) then return false, "fullscreen=" .. tostring(w.fullscreen) end
    local x, y = vec(w.at)
    local sw, sh = vec(w.size)
    local tol = cfg.tolerance_px
    if math.abs(x - row.x) > tol or math.abs(y - row.y) > tol or math.abs(sw - row.w) > tol or math.abs(sh - row.h) > tol then
      return false, string.format("geom %dx%d@%d,%d want %dx%d@%d,%d", sw, sh, x, y, row.w, row.h, row.x, row.y)
    end
    return true
  end

  local function ws_windows(ws)
    local out = {}
    for _, w in ipairs(hl.get_windows()) do
      if w.mapped and w.workspace and w.workspace.name == ws then out[#out + 1] = w end
    end
    return out
  end

  local function show_ws(ws, mon)
    mon = monitor_for(mon)
    if mon ~= "" then hl.dispatch(hl.dsp.focus({ monitor = mon })) end
    if is_special(ws) then
      local m = hl.get_monitor(mon) or hl.get_active_monitor()
      local active = m and m.active_special_workspace
      if not (active and active.name == ws) then
        hl.dispatch(hl.dsp.workspace.toggle_special(special_name(ws)))
        run.opened_specials[ws] = m and m.name or mon
      end
    else
      local existing = hl.get_workspace(ws)
      if existing and existing.monitor and mon ~= "" and existing.monitor.name ~= mon then
        hl.dispatch(hl.dsp.workspace.move({ workspace = ws, monitor = mon }))
      end
      hl.dispatch(hl.dsp.focus({ workspace = ws }))
    end
  end

  local function hide_special(ws, mon)
    if not is_special(ws) then return end
    local m = hl.get_monitor(monitor_for(mon)) or hl.get_active_monitor()
    local active = m and m.active_special_workspace
    if active and active.name == ws then
      if m then hl.dispatch(hl.dsp.focus({ monitor = m.name })) end
      hl.dispatch(hl.dsp.workspace.toggle_special(special_name(ws)))
    end
    run.opened_specials[ws] = nil
  end

  local function orient_of(ax, ay, bx, by)
    return math.abs(bx - ax) >= math.abs(by - ay) and "H" or "V"
  end

  -- fullscreen int: 0 none, 1 maximized, 2 fullscreen, 3 both. `unset` must
  -- name the mode that is active (a plain unset only clears "fullscreen").
  local function set_fs(w, want)
    local have = tonumber(w.fullscreen) or 0
    if have == want then return false end
    if have ~= 0 then
      if have & 1 == 1 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = w })) end
      if have & 2 == 2 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = w })) end
    end
    if want ~= 0 then
      if want & 1 == 1 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = w })) end
      if want & 2 == 2 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set", window = w })) end
    end
    return true
  end

  -- Build the dwindle tree by insertion. `steps` is a list of closures run
  -- with a small delay between them so the compositor settles in between.
  local function place_ws(entry, done)
    local ws, mon = entry.ws, entry.mon
    local tiled, floating, extras = {}, {}, {}
    for _, r in ipairs(entry.rows) do
      if r.state == "claimed" and live(r) then
        if r.floating then floating[#floating + 1] = r else tiled[#tiled + 1] = r end
      end
    end
    -- windows on this workspace that are not ours: extras (unclaimed, not
    -- splashy/ignored) get parked and returned; windows claimed by rows of
    -- OTHER workspaces get parked (their own placement fetches them);
    -- splashy/ignored windows are left alone.
    local foreign = {}
    for _, w in ipairs(ws_windows(ws)) do
      local owner = claimed[w.address]
      if owner and owner.ws ~= ws then
        foreign[#foreign + 1] = w
      elseif not owner and not cfg.splashy[w.class] and not is_ignored(cfg, w.class) then
        extras[#extras + 1] = w
      end
    end

    -- already perfect? then don't touch it (no flicker on re-runs)
    local all_ok = (#extras == 0 and #foreign == 0)
    if all_ok then
      for _, r in ipairs(entry.rows) do
        if r.state == "claimed" and not row_ok(r, live(r)) then all_ok = false; break end
      end
    end
    if all_ok then
      log("ws %s: already matches spec, skipping placement", ws)
      entry.placed = true
      return done()
    end
    if #tiled + #floating == 0 then
      log("ws %s: nothing to place", ws)
      entry.placed = true
      return done()
    end

    log("ws %s (mon %s): placing %d tiled, %d floating; %d extra + %d foreign window(s) parked",
      ws, monitor_for(mon), #tiled, #floating, #extras, #foreign)

    local steps = {}
    local function step(fn) steps[#steps + 1] = fn end
    local function run_steps(i)
      if run.finished or run.finalized then return end
      if i > #steps then return done() end
      local ok, err = pcall(steps[i])
      if not ok then log("ERROR in place step %d: %s", i, tostring(err)) end
      add_timer(T.step, function() run_steps(i + 1) end)
    end

    -- 1. park our rows, extras and foreign windows in staging
    step(function()
      for _, r in ipairs(entry.rows) do
        local w = live(r)
        if w then hl.dispatch(hl.dsp.window.move({ workspace = STAGING, follow = false, window = w })) end
      end
      for _, list in ipairs({ extras, foreign }) do
        for _, w in ipairs(list) do
          local lw = hl.get_window("address:" .. w.address)
          if lw then hl.dispatch(hl.dsp.window.move({ workspace = STAGING, follow = false, window = lw })) end
        end
      end
      -- normalise state according to spec while parked: apps sometimes map
      -- maximized/fullscreen (client request) or floating; the spec wins.
      for _, r in ipairs(entry.rows) do
        local w = live(r)
        if w then set_fs(w, 0) end
      end
      for _, r in ipairs(tiled) do
        local w = live(r)
        if w and w.floating then hl.dispatch(hl.dsp.window.float({ action = "unset", window = w })) end
      end
      for _, r in ipairs(floating) do
        local w = live(r)
        if w and not w.floating then hl.dispatch(hl.dsp.window.float({ action = "set", window = w })) end
      end
    end)
    step(function() show_ws(ws, mon) end)

    -- 2. dwindle tree
    if #tiled > 0 then
      local tree = build_tree(tiled, cfg.tolerance_px)
      local function insert(row)
        local w = live(row)
        if not w then return end
        hl.dispatch(hl.dsp.window.move({ workspace = ws, follow = true, window = w }))
        hl.dispatch(hl.dsp.focus({ window = w }))
      end
      local function focus(row)
        local w = live(row)
        if w then hl.dispatch(hl.dsp.focus({ window = w })) end
      end
      step(function() insert(tree.rep) end)
      local function emit(node)
        if node.leaf then return end
        local A, B = node.a, node.b
        -- insert B.rep next to A.rep (A.rep is focused and occupies node area)
        step(function() focus(A.rep); insert(B.rep) end)
        step(function()
          local wa, wb = live(A.rep), live(B.rep)
          if not (wa and wb) then return end
          local ax, ay = vec(wa.at)
          local bx, by = vec(wb.at)
          local want = node.dir
          local have = orient_of(ax, ay, bx, by)
          if want ~= have then
            hl.dispatch(hl.dsp.focus({ window = wb }))
            hl.dispatch(hl.dsp.layout("togglesplit"))
            log("  togglesplit #%d/#%d (%s->%s)", A.rep.idx, B.rep.idx, have, want)
          end
        end)
        step(function()
          local wa, wb = live(A.rep), live(B.rep)
          if not (wa and wb) then return end
          local ax, ay = vec(wa.at)
          local bx, by = vec(wb.at)
          -- B must be right/below A; swap if the layout put it on the other side
          local wrong = (node.dir == "H" and bx < ax) or (node.dir == "V" and by < ay)
          if wrong then
            hl.dispatch(hl.dsp.focus({ window = wb }))
            hl.dispatch(hl.dsp.window.swap({ direction = node.dir == "H" and "l" or "u" }))
            log("  swapped #%d/#%d", A.rep.idx, B.rep.idx)
          end
          -- split ratio of this node: fraction taken by subtree A
          local ax0, ay0, ax1, ay1 = bbox(A)
          local bx0, by0, bx1, by1 = bbox(B)
          local total = (node.dir == "H") and (bx1 - ax0) or (by1 - ay0)
          local part = (node.dir == "H") and (ax1 - ax0) or (ay1 - ay0)
          if total > 0 then
            local ratio = math.max(0.1, math.min(1.9, 2 * part / total))
            hl.dispatch(hl.dsp.focus({ window = wb }))
            -- Hyprland 0.56's lua `layout` dispatcher parses splitratio's arg as a
            -- delta only; "exact" errors with `failed to parse "exact" as a delta`.
            -- Drive the node to the 0.1 minimum (deltas clamp), then add the rest.
            hl.dispatch(hl.dsp.layout("splitratio -10"))
            hl.dispatch(hl.dsp.layout(string.format("splitratio %.4f", ratio - 0.1)))
          end
        end)
        emit(A)
        emit(B)
      end
      emit(tree)
    end

    -- 3. floating windows
    for _, r in ipairs(floating) do
      step(function()
        local w = live(r)
        if not w then return end
        hl.dispatch(hl.dsp.window.move({ workspace = ws, follow = true, window = w }))
        if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "set", window = w })) end
        hl.dispatch(hl.dsp.window.move({ x = r.x, y = r.y, relative = false, window = w }))
        hl.dispatch(hl.dsp.window.resize({ x = r.w, y = r.h, relative = false, window = w }))
        if r.pinned then hl.dispatch(hl.dsp.window.pin({ action = "set", window = w })) end
      end)
    end

    -- 4. measure-and-correct sizes (tiled), bounded passes
    for pass = 1, T.resize_passes do
      step(function()
        if entry._sizes_ok then return end
        local dirty = false
        for _, r in ipairs(tiled) do
          local w = live(r)
          if w then
            if set_fs(w, 0) then dirty = true end
            local sw, sh = vec(w.size)
            if math.abs(sw - r.w) > cfg.tolerance_px or math.abs(sh - r.h) > cfg.tolerance_px then
              hl.dispatch(hl.dsp.window.resize({ x = r.w, y = r.h, relative = false, window = w }))
              dirty = true
            end
          end
        end
        if not dirty then entry._sizes_ok = true; log("  sizes ok after %d pass(es)", pass - 1) end
      end)
    end

    -- 5. fullscreen last, extras back, hide special
    step(function()
      for _, r in ipairs(entry.rows) do
        local w = live(r)
        if w then set_fs(w, r.fullscreen or 0) end
      end
      for _, w in ipairs(extras) do
        local lw = hl.get_window("address:" .. w.address)
        if lw then
          hl.dispatch(hl.dsp.window.move({ workspace = ws, follow = false, window = lw }))
          log("  extra window %s (%s) returned to %s (not in spec)", w.address, w.class, ws)
        end
      end
      hide_special(ws, mon)
      entry.placed = true
    end)

    run_steps(1)
  end

  local function next_ready_ws()
    for _, ws in ipairs(order) do
      local e = by_ws[ws]
      if not e.placed and not e.placing and ws_resolved(e) then return e end
    end
    return nil
  end

  local function all_placed()
    for _, ws in ipairs(order) do if not by_ws[ws].placed then return false end end
    return true
  end

  check_progress = function()
    if run.finished or run.finalized or placement_busy then return end
    if all_placed() then return finalize() end
    local e = next_ready_ws()
    if not e then return end
    placement_busy = true
    e.placing = true
    place_ws(e, function()
      placement_busy = false
      e.placing = false
      e.placed = true
      add_timer(T.step, check_progress)
    end)
  end

  -- =========================================================================
  -- Phase C: end state + verification
  -- =========================================================================
  finalize = function()
    if run.finished then return end
    if run.finalized then return end
    run.finalized = true
    acquisition_done = true

    -- leftover staged windows -> saved active workspace of the focused monitor
    local land = nil
    for _, m in ipairs(spec.monitors or {}) do if m.focused then land = m end end
    land = land or (spec.monitors or {})[1]
    local land_ws = land and land.active ~= "" and land.active or order[1] or "1"
    for _, w in ipairs(ws_windows(STAGING)) do
      log("leftover in staging: %s (%s) -> %s", w.address, w.class, land_ws)
      hl.dispatch(hl.dsp.window.move({ workspace = land_ws, follow = false, window = w }))
    end

    -- per-monitor end state (R14). Only dispatch what actually differs, so a
    -- no-op run doesn't touch focus at all (e.g. a fullscreen game keeps it).
    for _, m in ipairs(spec.monitors or {}) do
      local mon = hl.get_monitor(m.name)
      if mon then
        local aw = mon.active_workspace
        local awname = aw and aw.name or ""
        local cur = mon.active_special_workspace
        local curname = cur and cur.name or nil
        if curname == "" then curname = nil end
        local want_ws = (m.active and m.active ~= "" and not is_special(m.active)) and m.active or nil
        local ws_change = want_ws and awname ~= want_ws
        local sp_change = (m.special and curname ~= m.special) or (not m.special and curname)
        if ws_change or sp_change then
          hl.dispatch(hl.dsp.focus({ monitor = m.name }))
          if ws_change then hl.dispatch(hl.dsp.focus({ workspace = want_ws })) end
          if m.special and curname ~= m.special then
            hl.dispatch(hl.dsp.workspace.toggle_special(special_name(m.special)))
          elseif not m.special and curname then
            hl.dispatch(hl.dsp.workspace.toggle_special(special_name(curname)))
          end
          log("end state %s: ws %s -> %s, special %s -> %s", m.name, awname, tostring(want_ws or awname), tostring(curname), tostring(m.special))
        end
      end
    end
    -- if the spec has no monitor info (v1), just make sure no special is left open
    if not spec.monitors or #spec.monitors == 0 then
      for _, mon in ipairs(hl.get_monitors()) do
        local cur = mon.active_special_workspace
        if cur and cur.name ~= "" then
          hl.dispatch(hl.dsp.focus({ monitor = mon.name }))
          hl.dispatch(hl.dsp.workspace.toggle_special(special_name(cur.name)))
        end
      end
    end
    local fr = spec.focused and rows[spec.focused]
    local fw = fr and live(fr)
    if not fw and land and land.active ~= "" then
      for _, w in ipairs(ws_windows(land.active)) do if not w.floating then fw = w; break end end
    end
    local active = hl.get_active_window()
    if fw and not (active and active.address == fw.address) then
      if land and hl.get_monitor(land.name) then hl.dispatch(hl.dsp.focus({ monitor = land.name })) end
      hl.dispatch(hl.dsp.focus({ window = fw }))
      log("end state: focus -> %s (%s)", fw.address, fw.class)
    elseif land and hl.get_monitor(land.name) then
      local am = hl.get_active_monitor()
      if not (am and am.name == land.name) then hl.dispatch(hl.dsp.focus({ monitor = land.name })) end
    end

    -- verification (after a beat so the last dispatches settle)
    add_timer(150, function()
      local ok_n, total = 0, 0
      local problems = {}
      log("verification:")
      for _, r in ipairs(rows) do
        local status, detail
        if r.state == "static" then status = "STATIC"
        elseif r.state == "ignored" then status = "IGNORED"
        elseif r.state == "missing" then status = "MISSING_APP"; detail = r.cmd
        elseif r.state == "failed" then status = "FAILED"
        else
          local good, why = row_ok(r, live(r))
          status = good and "OK" or "MISMATCH"
          detail = why
        end
        if status ~= "STATIC" and status ~= "IGNORED" then
          total = total + 1
          if status == "OK" then ok_n = ok_n + 1 else problems[#problems + 1] = r.class end
        end
        log("  #%-2d %-11s %-38s ws=%-18s %s", r.idx, status, r.class, r.ws, detail or "")
      end
      local msg = string.format("restored %d/%d", ok_n, total)
      if ok_n == total then
        notify("low", msg)
      else
        local seen, uniq = {}, {}
        for _, c in ipairs(problems) do if not seen[c] then seen[c] = true; uniq[#uniq + 1] = c end end
        notify("normal", msg .. " — " .. table.concat(uniq, ", ") .. " (see restore.log)")
      end
      log("%s in %.1fs", msg, now() - run.t0)
      run.finish_reason = msg
      run.finish()
    end)
  end

  -- =========================================================================
  -- Kick-off: wait for monitors, then acquire, then place as they resolve
  -- =========================================================================
  run.t0 = now()
  add_timer(T.total, function()
    if not run.finalized then
      log("TOTAL TIMEOUT after %dms", T.total)
      for _, r in ipairs(rows) do if r.state == "pending" then fail_row(r, "total timeout") end end
      finalize()
    end
  end)

  local wanted = {}
  for _, r in ipairs(rows) do if r.mon and r.mon ~= "" then wanted[r.mon] = true end end
  local waited = 0
  local function wait_monitors()
    local missing = {}
    for name in pairs(wanted) do if not hl.get_monitor(name) then missing[#missing + 1] = name end end
    if #missing == 0 or waited >= T.monitors then
      if #missing > 0 then log("monitors still missing after %dms: %s (falling back to focused monitor)", waited, table.concat(missing, ",")) end
      log("monitors ready (%dms)", waited)
      -- windows that appeared while waiting are picked up by adopt_now()
      -- right before each launch
      safe(start_launches)
      check_progress()
    else
      waited = waited + 500
      add_timer(500, wait_monitors)
    end
  end
  wait_monitors()
  return true
  end) -- body pcall
  if not body_ok then
    on_error("restore body", body_res)
    return false
  end
  return body_res
end

-- Escape hatch: forget a run (subscriptions/timers disabled) so restore can
-- be called again. `layout-boot --reset`.
function LayoutRR.reset()
  local run = LayoutRR._run
  if run then
    run.finish_reason = "reset"
    pcall(run.finish)
    -- finalize-lite: close any special the run opened and left open
    for ws, mon in pairs(run.opened_specials or {}) do
      pcall(function()
        local m = hl.get_monitor(mon) or hl.get_active_monitor()
        local active = m and m.active_special_workspace
        if active and active.name == ws then
          hl.dispatch(hl.dsp.focus({ monitor = m.name }))
          hl.dispatch(hl.dsp.workspace.toggle_special(special_name(ws)))
        end
      end)
    end
  end
  LayoutRR._run = nil
  local n = LayoutRR.rescue_staging()
  -- late-mapping windows of the abandoned run: sweep once more
  hl.timer(function() if not LayoutRR._run then pcall(LayoutRR.rescue_staging) end end,
    { timeout = 5000, type = "oneshot" })
  notify("low", (run and "layout: run reset" or "layout: no run in flight") .. (n > 0 and (", " .. n .. " window(s) unstaged") or ""))
  return true
end

-- Rescue windows stranded in the staging workspace by a config reload that
-- killed a run in flight (reload wipes Lua state, see header). Runs on every
-- module evaluation, i.e. at boot and after each reload; a run can't be active
-- at that point. Also exposed for `layout-boot --reset`.
function LayoutRR.rescue_staging()
  local n = 0
  for _, w in ipairs(hl.get_windows()) do
    if w.mapped and w.workspace and w.workspace.name == STAGING then
      local m = w.monitor or hl.get_active_monitor()
      local target = m and m.active_workspace and m.active_workspace.name
      if not target or target == "" or target == STAGING then target = "1" end
      hl.dispatch(hl.dsp.window.move({ workspace = target, follow = false, window = w }))
      n = n + 1
    end
  end
  if n > 0 then notify("normal", string.format("layout: moved %d window(s) out of %s (interrupted restore)", n, STAGING)) end
  return n
end
hl.timer(function()
  if not LayoutRR._run then pcall(LayoutRR.rescue_staging) end
end, { timeout = 1500, type = "oneshot" })
-- ... and windows that map into staging with no run in flight (launched by a
-- run that was since abandoned/reset): unstage them immediately.
hl.on("window.open", function(w)
  if LayoutRR._run or not w or not w.workspace or w.workspace.name ~= STAGING then return end
  pcall(function()
    local m = w.monitor or hl.get_active_monitor()
    local target = m and m.active_workspace and m.active_workspace.name
    if not target or target == "" or target == STAGING then target = "1" end
    hl.dispatch(hl.dsp.window.move({ workspace = target, follow = false, window = w }))
    notify("normal", "layout: " .. w.class .. " mapped in " .. STAGING .. " with no restore running, moved to " .. target)
  end)
end)

-- Boot: restore once the session is up. hyprland.start fires once per
-- session (not on reload), so this cannot double-trigger.
hl.on("hyprland.start", function()
  hl.timer(function()
    local ok, err = pcall(LayoutRR.restore, { boot = true })
    if not ok then notify("critical", "layout boot error: " .. tostring(err)) end
  end, { timeout = 500, type = "oneshot" }) -- monitor wait (R3) happens inside restore
end)
