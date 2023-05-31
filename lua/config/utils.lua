P = function(v)
    print(vim.inspect(v))
end

local M = {}

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
    local table = vim.split(output, "\n")
    return table[#table-1]
end

local parse_git_url = function()
    package.preload["config.utils"] = nil
    package.loaded["config.utils"] = nil
    local url = exec("!git config --get remote.origin.url")

    local _ = nil
    local domain = nil
    local org = nil
    local repo = nil

    if url.find(url, "^git@") ~= nil then
        _, _, domain, org, repo = string.find(url, "git@(.*):(.*)/(.*)")
    else
        _, _, domain, org, repo = string.find(url, "http.*://(.*)/(.*)/(.*)")
    end

    return domain, org, repo
end

M.get_github_link = function()
    local domain, org, repo = parse_git_url()
    local branch = exec("!git branch --show-current")
    local file_path = vim.api.nvim_buf_get_name(0)
    local cwd = vim.fn.getcwd()

    local r_path = file_path:gsub(cwd .. "/", "")
    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))

    local link = string.format("https://%s/%s/%s/blob/%s/%s#L%s", domain, org, repo, branch, r_path, row)
    return link
end

return M
