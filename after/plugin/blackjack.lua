require("blackjack").setup({
  card_style = "small",
  suit_style = "white",
  keybindings = {
    ["next"] = "8",
    ["finish"] = "9",
    ["quit"] = "0",
  }
})

vim.keymap.set("n", "<localleader>pb", ":BlackJackNewGame<CR>", { noremap = true })
