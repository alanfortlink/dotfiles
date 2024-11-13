require("blackjack").setup({
  card_style = "small",
  suit_style = "white",
  keybindings = {
    ["next"] = "j",
    ["finish"] = "k",
    ["quit"] = "q",
  }
})

vim.keymap.set("n", "<localleader>pb", ":BlackJackNewGame<CR>", { noremap = true })
