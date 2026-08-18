local M = {}

local get_project_root = function()
  local file_dir = vim.fn.expand("%:p:h")
  local git_root = vim.fn.finddir(".git", file_dir .. ";")
  local project_root_dir = vim.fn.fnamemodify(git_root, ":h")

  local abs_project_root_dir = vim.fn.fnamemodify(project_root_dir, ":p")
  -- remove extra / at the end
  abs_project_root_dir = abs_project_root_dir:gsub("/$", "")

  if abs_project_root_dir == "" then
    return file_dir
  end
  if abs_project_root_dir == nil then
    return file_dir
  end

  return abs_project_root_dir
end

local function exec(command)
  local project_root = get_project_root()
  command = string.format("cd %s && %s", project_root, command)
  local output = vim.fn.system(command)
  local table = vim.split(output, "\n")
  return table[#table - 1]
end

local parse_git_url = function()
  local url = exec("git config --get remote.origin.url")

  local _ = nil
  local domain = nil
  local org = nil
  local repo = nil

  if url.find(url, "^git@") ~= nil then
    _, _, domain, org, repo = string.find(url, "git@(.*):(.*)/(.*)")
  else
    _, _, domain, org, repo = string.find(url, "http.*://(.*)/(.*)/(.*)")
  end

  repo = repo:gsub(".git$", "")

  return domain, org, repo
end

M.get_github_link = function()
  local domain, org, repo = parse_git_url()
  local branch = exec("git branch --show-current")
  local file_path = vim.api.nvim_buf_get_name(0)
  local cwd = get_project_root()

  local r_path = file_path:gsub(cwd .. "/", "")
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))

  local link = string.format("https://%s/%s/%s/blob/%s/%s#L%s", domain, org, repo, branch, r_path, row)
  return link
end

local _invoke_code_action = function(widget, buf)
  local action = "dart.assist.flutter.wrap." .. widget
  local seen = false
  buf.code_action({
    filter = function(ca)
      if seen then return false end

      if ca.command.arguments[1].action == action then
        seen = true
        return true
      end

      return false
    end,
    apply = true,
  })
end

M.code_action_wrapper = function(widget, buf)
  return function()
    _invoke_code_action(widget, buf)
  end
end

return M
