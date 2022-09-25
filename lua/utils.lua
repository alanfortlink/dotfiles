local M = {}

local function set_keymap(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, { noremap = true })
end

function M.nmap(lhs, rhs)
    set_keymap('n', lhs, rhs)
end

function M.vmap(lhs, rhs)
    set_keymap('v', lhs, rhs)
end

function M.imap(lhs, rhs)
    set_keymap('i', lhs, rhs)
end

function M.get_quickfix_bufnr()
    local all_buffers = vim.fn.getbufinfo()
    for _, buffer in ipairs(all_buffers) do
        local buftype = vim.api.nvim_buf_get_option(buffer.bufnr, "buftype")
        if buftype == "quickfix" then
            return buffer.bufnr
        end
    end
    return -1
end

local function exec(command)
    local output = vim.api.nvim_exec(command, true)
    local table = vim.split(output, '\n')
    return table[#table-1]
end

function M.get_github_link()
    -- github.com/<organization>/<repository>/blob/<branch_name>/<path_to_file>?plain=1
    local url = exec("!git config --get remote.origin.url | sed \"s/\\.git$//\" | sed \"s/^git@/https:\\/\\//\"")
    local branch = exec("!git branch --show-current")
    
    local file_path = vim.api.nvim_buf_get_name(0)
    local cwd = vim.fn.getcwd()

    local r_path = file_path:gsub(cwd .. "/", "")
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))

    local link = url .. "/blob/" .. branch .. "/" .. r_path .. "#L" .. row
    return link
end

return M
