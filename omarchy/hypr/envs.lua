-- Personal environment overrides (loaded after Omarchy defaults).

-- Omarchy's default/hypr/nvidia.lua picks NVD_BACKEND from GPU generation
-- alone: Turing+ gets "direct". But nvidia-vaapi-driver's direct backend needs
-- GSP firmware actually running, which is a runtime fact, not a hardware one.
-- (NVreg_EnableGpuFirmware=0 is honoured by the proprietary module but ignored
-- by the open one, so the modprobe flag is not a reliable signal either.)
-- The GPU Firmware line only carries a version when GSP is really up.
local gsp_running = o.shell_succeeds(
  "grep -hs '^GPU Firmware:' /proc/driver/nvidia/gpus/*/information | grep -q '[0-9]'"
)

if not gsp_running then
  hl.env("NVD_BACKEND", "egl")
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
end
