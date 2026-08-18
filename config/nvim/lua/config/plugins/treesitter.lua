return {
  { -- Highlight, edit, and navigate code (main branch — actively maintained rewrite)
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false, -- main branch does not support lazy-loading
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter').setup()

      -- Parsers to keep installed. `:TSInstall <lang>` adds more on demand.
      -- (auto_install is gone in the main branch — see the FileType autocmd below.)
      require('nvim-treesitter').install({
        'bash', 'c', 'cpp', 'css', 'dart', 'diff', 'gdscript', 'git_config',
        'gitcommit', 'go', 'html', 'hyprlang', 'json', 'jsonc', 'lua', 'luadoc',
        'markdown', 'markdown_inline', 'python', 'query', 'regex', 'ssh_config',
        'toml', 'vim', 'vimdoc', 'yaml',
      })

      -- Highlighting is no longer a "module" — start the native treesitter
      -- highlighter per buffer. Missing parsers are fetched in the background
      -- (replacing the old auto_install); they apply on the next open.
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter-start', { clear = true }),
        callback = function(args)
          local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
          if not lang then return end
          if pcall(vim.treesitter.start, args.buf, lang) then return end
          pcall(function()
            local nt = require('nvim-treesitter')
            if vim.tbl_contains(nt.get_available(), lang) then nt.install({ lang }) end
          end)
        end,
      })

      -- Indentation: built-in is used (cindent for C/C++, runtime indent/*.vim
      -- elsewhere). The main branch ships only an experimental treesitter
      -- indentexpr; opt in per buffer with:
      --   vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  },

  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    lazy = false,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('nvim-treesitter-textobjects').setup({
        select = {
          lookahead = true,
          selection_modes = {
            ['@parameter.outer'] = 'v', -- charwise
            ['@function.outer'] = 'V', -- linewise
            ['@class.outer'] = '<c-v>', -- blockwise
          },
          include_surrounding_whitespace = false,
        },
        move = {
          set_jumps = true, -- add movements to the jumplist
        },
      })

      local select = require('nvim-treesitter-textobjects.select')
      local move = require('nvim-treesitter-textobjects.move')

      -- Select textobjects (visual / operator-pending)
      local select_maps = {
        ['al'] = '@loop.outer',
        ['il'] = '@loop.inner',
        ['af'] = '@function.outer',
        ['if'] = '@function.inner',
        ['as'] = '@selector',
        ['is'] = '@selector',
        ['ac'] = '@comment.outer',
        ['ic'] = '@comment.inner',
        ['ip'] = '@parameter.inner',
        ['ap'] = '@parameter.outer',
      }
      for lhs, cap in pairs(select_maps) do
        vim.keymap.set({ 'x', 'o' }, lhs, function()
          select.select_textobject(cap, 'textobjects')
        end)
      end

      -- Movement
      local move_maps = {
        goto_next_start = { [']m'] = '@function.outer', [']o'] = '@loop.outer', [']p'] = '@parameter.inner' },
        goto_next_end = { [']f'] = '@function.inner', [']F'] = '@function.outer', [']['] = '@class.outer' },
        goto_previous_start = { ['[f'] = '@function.inner', ['[F'] = '@function.outer', ['[p'] = '@parameter.inner' },
        goto_previous_end = { ['[M'] = '@function.outer', ['[]'] = '@class.outer' },
      }
      for fn, maps in pairs(move_maps) do
        for lhs, cap in pairs(maps) do
          vim.keymap.set({ 'n', 'x', 'o' }, lhs, function()
            move[fn](cap, 'textobjects')
          end)
        end
      end

      -- Scope / fold movement (non-default query groups)
      vim.keymap.set({ 'n', 'x', 'o' }, ']s', function()
        move.goto_next_start('@local.scope', 'locals')
      end)
      vim.keymap.set({ 'n', 'x', 'o' }, ']z', function()
        move.goto_next_start('@fold', 'folds')
      end)
    end,
  },
}
