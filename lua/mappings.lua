local utils = require('utils')

local nmap = utils.nmap

nmap('<C-h>', '<C-w>h')
nmap('<C-j>', '<C-w>j')
nmap('<C-k>', '<C-w>k')
nmap('<C-l>', '<C-w>l')

nmap('<C-M-h>', '3<C-w><')
nmap('<C-M-l>', '3<C-w>>')
nmap('<C-M-k>', '1<C-w>-')
nmap('<C-M-j>', '1<C-w>+')

nmap('<leader>M', '<C-w>_<C-w><Bar> ')
nmap('<leader>m', '<C-w>=')

nmap('<leader>t', ':tabnew<CR>')
nmap('<leader>n', ':new<CR>')
nmap('<leader>v', ':vnew<CR>')
nmap('<leader>q', ':q<CR>')
nmap('<leader>Q', ':q!<CR>')

nmap('<leader>1', '1gt')
nmap('<leader>2', '2gt')
nmap('<leader>3', '3gt')
nmap('<leader>4', '4gt')
nmap('<leader>5', '5gt')

nmap('gh', ':GitGutterNextHunk<CR>')
nmap('gH', ':GitGutterPrevHunk<CR>')

local telescope = require('telescope.builtin')

nmap('<leader>f', function() telescope.find_files({ hidden = false }) end)
nmap('<leader>F', function() telescope.find_files({ hidden = true }) end)
nmap('<leader>g', telescope.live_grep)

nmap('<localleader>r', telescope.lsp_references)
nmap('<localleader>c', telescope.commands)
nmap('<localleader>d', telescope.lsp_definitions)
nmap('<localleader>t', telescope.lsp_type_definitions)
nmap('<localleader>/', ':noh<CR>')
nmap('<localleader>u', ':UndotreeShow<CR>:UndotreeFocus<CR>')
nmap('<localleader>U', ':UndotreeHide<CR>')

-- Save / Restore a session.
nmap('<localleader>s1', ':mks! .session1.vim<CR>')
nmap('<localleader>s2', ':mks! .session2.vim<CR>')

nmap('<localleader>l1', ':so .session1.vim<CR>')
nmap('<localleader>l2', ':so .session2.vim<CR>')

nmap('<bslash><bslash>', ':NERDTreeToggle<CR>')

nmap('<localleader>gl', function() 
    print(utils.get_github_link())
end)

require('lualine').setup({
    options = {
        icons_enabled = true,
        theme = 'auto',
        component_separators = { left = '', right = '' },
        section_separators = { left = '', right = '' },
        disabled_filetypes = {},
        always_divide_middle = true,
        globalstatus = false,
    },
    sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = { 'filename' },
        lualine_x = { 'filesize', 'encoding', 'filetype' },
        lualine_y = { 'progress' },
        lualine_z = { 'location' }
    },
    tabline = {},
    extensions = {}
})
