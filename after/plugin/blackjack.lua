require("blackjack").setup({
  card_style = "large",
  suit_style = "white",
  scores_path = "$HOME/.blackjack_scores.json",
})

vim.keymap.set("n", "<localleader>pb", ":BlackJackNewGame<CR>", { noremap = true })
