vim.opt.background = "dark"

if not pcall(function() vim.cmd.colorscheme("onedark") end) then
  print("carbonfox not found!")
end

vim.opt.termguicolors = true

vim.cmd("highlight WinSeparator guibg=DarkGray")
vim.cmd("highlight WinSeparator guibg=DarkGray")
vim.cmd("hi NormalNC guibg=NONE ctermbg=NONE")
vim.cmd("hi Normal guibg=NONE ctermbg=NONE")
vim.cmd("hi EndOfBuffer guibg=NONE ctermbg=NONE")
