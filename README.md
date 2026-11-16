# nvim launcher for Termux

An nvim config that turns a Termux session into a touch-driven app launcher.

- The home screen is the org agenda for `~/org`.
- Typing runs a fuzzy search over installed apps. The prompt sits at the bottom next to the keyboard, and results grow upward with the best match directly above it.
- Enter or a tap starts the app with `termux-am start -n <package/activity>`.
- Tapping the pencil swaps the prompt from search to note. Enter then appends a headline to `~/org/inbox.org`.

## Install

```sh
pkg install neovim git clang termux-am-socket aapt
git clone https://github.com/Iodize13/nvim ~/.config/nvim
nvim
```

The first start asks to install nvim-orgmode through `vim.pack` (nvim 0.12 or newer) and compiles its tree-sitter grammar, which needs `clang`. If orgmode is already on the runtimepath, the config uses that copy.

`aapt` is optional. With it the app list shows real labels. Without it the list shows package names.

## Use

| Input | Effect |
| --- | --- |
| type | search apps, or write a note in note mode |
| Enter | launch the selected app, or save the note |
| tap a result | launch it |
| Up, Down, Ctrl-p, Ctrl-n | move the selection up or down the list |
| tap the pencil, or Tab | swap search and note, keeping the typed text |
| tap the house, or Esc | back to the agenda |
| double tap an agenda line | open that headline |

`:LauncherRefresh` rebuilds the app list after you install or remove an app. The list is cached in `~/.cache/nvim/launcher-apps.tsv`, one `label<TAB>package/activity` per line, and you can edit it by hand.

## Configure

`init.lua` calls `require("launcher").setup({...})`. The defaults are at the top of `lua/launcher/init.lua`.

| Option | Default | Meaning |
| --- | --- | --- |
| `notes_file` | `$ORG_DIR/inbox.org` | where notes go |
| `note` | headline plus inactive timestamp | function from the typed text to the lines to append |
| `spacing` | `1` | blank rows between results, for larger tap targets |
| `launch_cmd` | `termux-am start -n`, or `am start -n` if `termux-am` is missing | argv prefix for launching |
| `refresh_cmd` | `bin/launcher-apps` | command that prints the app list |
| `home` | orgmode agenda | function that fills the main window |
| `icons` | `>`, `✎`, `⌂` | prompt and button glyphs |

Set `ORG_DIR` to use a directory other than `~/org`.

## Test

```sh
ORGMODE_DIR=/path/to/nvim-orgmode tests/tui.sh
```

The script runs the real TUI inside tmux, sends keys and mouse taps, and stubs `termux-am` and `cmd`. It does not run on Android, so it does not cover `bin/launcher-apps` against a real package manager or the launch latency.
