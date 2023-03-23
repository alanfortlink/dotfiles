local jobs = {}

local function append_to_quickfix(_, data, title)
    vim.fn.setqflist({}, "a", {
        title = title or "Make",
        lines = vim.list_extend({}, data),
    })
    vim.cmd([[doautocmd QuickFixCmdPost]])
end

local function run_make(target)
    -- Empty the quickfix list
    vim.fn.setqflist({}, "r")

    -- Print the command being executed
    local begin_message = "make " .. target
    print(begin_message)
    append_to_quickfix(nil, { begin_message })

    -- Create a job that runs the command
    jobs[#jobs + 1] = vim.fn.jobstart({ "make", target }, {
        on_stdout = append_to_quickfix,
        on_stderr = append_to_quickfix,
        on_exit = function(_, rc)
            local end_message = "Finished with rc=" .. tostring(rc)
            print(end_message)
            append_to_quickfix(nil, { end_message }, "Make (rc=" .. tostring(rc) .. ")")
        end,
    })
end

local function stop_jobs()
    -- Stops all the running jobs
    for _, job in ipairs(jobs) do
        vim.fn.jobstop(job)
    end
    jobs = {}
end

vim.keymap.set("n", "<localleader>jb", function() run_make("build") end)
vim.keymap.set("n", "<localleader>jr", function() run_make("run") end)
vim.keymap.set("n", "<localleader>jt", function() run_make("test") end)
vim.keymap.set("n", "<localleader>jq", function() stop_jobs() end)

vim.keymap.set("n", "<localleader>q", ":cclose<CR>")
vim.keymap.set("n", "<localleader>Q", ":copen<CR>")
