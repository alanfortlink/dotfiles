require("blackjack").setup({
  card_style = "mini",
  suit_style = "white",
})

vim.keymap.set("n", "<localleader>pb", ":BlackJackNewGame<CR>", { noremap = true })
