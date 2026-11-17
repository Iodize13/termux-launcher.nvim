# nvim launcher for Termux

An nvim config that turns a Termux session into a touch-driven app launcher.

- The home screen is the org agenda for `~/org`.
- Typing runs a fuzzy search over installed apps. The prompt sits at the bottom next to the keyboard, and results grow upward with the best match directly above it.
- Enter or a tap starts the app with `termux-am start -n <package/activity>`.
- Tapping the star swaps the prompt from search to note. Enter then appends a headline to `~/org/inbox.org`. The pencil does the same for `~/org/note.org`.
- In note mode a row of chips sits above the prompt. The first is `TODO`, which is on by default. The rest are the tags listed in `init.lua`. Tapping a chip toggles it, so `buy milk` with `Shopping` tapped saves as `* TODO buy milk :Shopping:`.

## Install

```sh
pkg install neovim git clang termux-am-socket aapt
git clone https://github.com/Iodize13/termux-launcher.nvim ~/.config/nvim
nvim
```

The first start clones [lazy.nvim](https://github.com/folke/lazy.nvim), which installs nvim-orgmode, and orgmode compiles its tree-sitter grammar, which needs `clang`. Plugins live in `~/.local/share/nvim/lazy`. `:Lazy` updates them.

`aapt` is optional. With it the app list shows real labels. Without it the list shows package names.

## Sync

The config loads [teamtype-nvim](https://github.com/teamtype/teamtype-nvim). When `teamtype` is installed and `~/org/.teamtype/config` names a peer, the launcher starts `teamtype join` for `~/org` and stops it on exit, so the directory syncs with other devices in real time. Otherwise the plugin does nothing.

## Use

| Input | Effect |
| --- | --- |
| type | search apps, or write a note in note mode |
| Enter | launch the selected app, or save the note |
| tap a result | launch it |
| Up, Down, Ctrl-p, Ctrl-n | move the selection up or down the list |
| tap a note button | write to that file, or go back to search when it is already active. The typed text stays |
| tap a chip | toggle `TODO` or a tag on the next note. Saving resets them |
| Tab | step through search and each notes file |
| tap the house, or Esc | back to the agenda |
| double tap an agenda line | open that headline |

`:LauncherRefresh` rebuilds the app list after you install or remove an app. The list is cached in `~/.cache/nvim/launcher-apps.tsv`, one `label<TAB>package/activity` per line, and you can edit it by hand.

## Configure

`init.lua` calls `require("launcher").setup({...})`. The defaults are at the top of `lua/launcher/init.lua`.

| Option | Default | Meaning |
| --- | --- | --- |
| `notes` | `~/org/note.org` with `✎` | list of `{ file, icon }`. Each entry gets a button after the house |
| `todo` | `"TODO"` | keyword new notes start with. `false` drops the chip |
| `tags` | every tag in the orgmode files | list of tags offered as chips, or a function returning one |
| `note` | headline plus inactive timestamp | function from the typed text and `{ todo, tags }` to the lines to append |
| `spacing` | `1` | blank rows between results, for larger tap targets |
| `button_rows` | `3` | height of the home and note buttons, which share the screen width evenly |
| `launch_cmd` | `termux-am start -n`, or `am start -n` if `termux-am` is missing | argv prefix for launching |
| `refresh_cmd` | `bin/launcher-apps` | command that prints the app list |
| `home` | orgmode agenda | function that fills the main window |
| `colors` | `home`, `todo`, and a `cycle` list of Diagnostic groups | highlight groups whose foreground tints the buttons and chips. Notes buttons and tags take `cycle` in order, and a notes entry can set its own `color` |
| `icons` | `>`, `⌂` | search prompt and home button glyphs |

Set `ORG_DIR` to use a directory other than `~/org`.

## Test

```sh
tests/tui.sh
```

The first start in the test clones lazy.nvim and orgmode. Set `LAZY_DIR` or `ORGMODE_DIR` to a local checkout to copy that instead.

The script runs the real TUI inside tmux, sends keys and mouse taps, and stubs `termux-am` and `cmd`. It does not run on Android, so it does not cover `bin/launcher-apps` against a real package manager or the launch latency.
