# profiles

Native Pi profiles for model, thinking, tools, prompt context, and delegation behavior.

## Commands

- `/profile` — select or manage profiles
- `/profile <name>` or `/profile use <name>` — activate a profile
- `/profile list`
- `/profile show <name>`
- `/profile create`
- `/profile edit <name>`
- `/profile delete <name>`
- `/profile default <name>` — default for new/profile-free sessions

Definitions live in `~/.pi/agent/profiles.json`. The active profile is stored as a branch-aware custom session entry, so every session remembers its own selection and `/tree` restores the profile at that branch.

`direct` profiles work themselves. `supervisor` profiles retain their configured tools and decide whether direct work or delegation is optimal. A supervisor's `defaultDelegate` supplies defaults for delegated tasks that omit model, thinking, or tools; explicit task choices remain allowed. Delegated workers receive the selected direct profile's instructions and a required concise verification report.

The footer uses Pi's `ctx.ui.setStatus()` API. With the installed Claude-style footer, the active profile appears on its extension-status line.

Changes made through `/profile` are written atomically. Run `/reload` after installing the extension; later CRUD and profile switches apply immediately.
