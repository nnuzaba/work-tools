# work-tools

Small tools for day-to-day work on GitHub and macOS. Each one lives in its own folder.

- [gh-img-resize](gh-img-resize/): Chrome extension to resize images in GitHub comments and PR descriptions.
- [pr-watch](pr-watch/): macOS menu bar app that shows your PRs and alerts on activity you care about.
- [taskfloat](taskfloat/): floating, always-on-top macOS task timer.

## Requirements

- **gh-img-resize:** Chrome (or another Chromium browser). Nothing else.
- **pr-watch and taskfloat:** macOS 14 or later, and Apple's Command Line Tools (`xcode-select --install`). Full Xcode is not needed.
- **pr-watch also needs** the [GitHub CLI](https://cli.github.com/), logged in with `gh auth login`. It uses that login, so there's no token to set up. [terminal-notifier](https://github.com/julienXX/terminal-notifier) is optional: with it, clicking an alert opens the PR.

## gh-img-resize

1. Open `chrome://extensions` and turn on Developer mode.
2. Click **Load unpacked** and pick the `gh-img-resize` folder.

See [gh-img-resize/README.md](gh-img-resize/README.md) for how it works.

## pr-watch

```bash
pr-watch/scripts/bundle.sh --install
open ~/Applications/PRWatch.app
```

This installs `~/Applications/PRWatch.app`. Keep it there: the app's "Open at login" setting is tied to that path.

Settings are optional. To change them, copy the example and edit it:

```bash
mkdir -p ~/.config/pr-watch && cp pr-watch/config.example ~/.config/pr-watch/config
```

If `gh` isn't installed through Homebrew, set `gh_path` in that file. The app is started from Finder, so it can't see your shell's `PATH`.

## taskfloat

```bash
taskfloat/build.sh
open taskfloat/TaskFloat.app
```

Tasks are saved in `~/Library/Application Support/TaskFloat/`, so rebuilding or restarting keeps them. To start it at login, add `TaskFloat.app` in System Settings → General → Login Items.

Optional shell shortcut to rebuild and restart it (put it in `~/.zshrc` and fix the path):

```bash
tf() {
  ~/path/to/work-tools/taskfloat/build.sh || return
  pkill -x TaskFloat; sleep 1
  open ~/path/to/work-tools/taskfloat/TaskFloat.app
}
```

## License

[MIT](LICENSE)
