# Review and push from a clean clone

Keep an independent host clone outside both workspace directories. Only that
clone may use your SSH/GPG keys, Git hooks and push credentials. Never run host
Git in a workspace after an agent has touched it: `.git/config` and hooks can
execute commands with your host permissions.

1. Before giving the repo to an agent, clone it on the host:

   ```bash
   git clone git@github.com:your-org/project.git workspaces/work/project
   git clone git@github.com:your-org/project.git ../project-review
   ```

2. Enter the work box and create the agent branch there:

   ```bash
   bin/agentbox shell work
   cd /workspace/project
   git switch -c ai/task
   claude
   # Or: codex
   ```

   Commit locally in the box. If Git needs an author, configure generic author
   metadata in that repo inside the box. Do not copy your host `.gitconfig`.

3. Back on the host, fetch into the clean clone:

   ```bash
   bin/agentbox fetch work project ai/task ../project-review
   ```

   The helper runs every Git command with `-C` pointing at the clean clone. It
   disables hooks/fsmonitor, uses file transport, skips submodules and checks
   fetched objects. It lists commits, changed files and risky executable/config
   paths, then prints shell-quoted review/push commands. It never pushes.

4. Review the full diff using the printed commands. Check package scripts,
   lockfiles, shell scripts, build files, CI, editor tasks and agent config before
   installing dependencies, running code or opening the fetched branch in an
   editor. Push manually from the clean clone after review.

   Fetching does not re-sign commits. To sign reviewed changes with your host
   key, create a new branch from `main` in the clean clone and cherry-pick the
   reviewed commits with `git cherry-pick -S`, then push that branch.

The helper requires a local `main` baseline and refuses fetching onto `main`.
Use a normal independent clone; source linked worktrees and `.git` symlinks are
refused. The clean clone must already be trusted. Keep Git updated: file
transport still parses untrusted Git objects and repository metadata.

Never open a workspace folder in a host editor's normal mode. In VS Code, use
**Dev Containers: Attach to Running Container** and open `/workspace` there;
the extension handles Docker from the host, without a socket mount in the box.
Treat anything placed in a box as readable by the agent and the model provider.
Never copy real `.env` files or production credentials into either workspace.
