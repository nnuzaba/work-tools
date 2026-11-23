# work-tools

Personal tools, one folder each. Each tool's own notes live in its folder's CLAUDE.md.

## Landing work: merge to main, no PRs

Once a branch is committed, fast-forward it into `main` in the main checkout. A worktree can't check out `main`, and the main checkout is the first line of `git worktree list`:

```bash
git -C "$(git worktree list | head -1 | awk '{print $1}')" merge --ff-only <branch>
```

If the fast-forward fails because `main` moved, rebase the branch onto `main` and try again. Pushing `main` to origin is a separate step: ask before pushing.
