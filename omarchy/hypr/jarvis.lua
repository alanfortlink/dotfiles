-- jarvis: always open detached (floating + centered), never tiled into the grid.
o.window("^(net\\.awan\\.jarvis)$", {
  float = true,
  center = true,
})
