require("neorg").setup {
   load = {
     ["core.defaults"] = {},
     ["core.autocommands"] = {},
     ["core.integrations.treesitter"] = {},
     ["core.norg.concealer"] = {},
     ["core.norg.completion"] = { 
       config = {
         engine = "nvim-cmp"
       }
     },
  }
}

