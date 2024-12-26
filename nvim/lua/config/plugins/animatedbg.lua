return {
  dir = '/home/alan/repos/animatedbg.nvim',
  dev = true,
  config = function ()
    require("animatedbg-nvim").setup({})
  end
}

--return {
--  'alanfortlink/animatedbg.nvim',
--  config = function()
--    require("animatedbg-nvim").setup({
--      fps = 60   -- default
--    })
--  end
--}
