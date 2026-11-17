#!/bin/sh
# Drives the real TUI in tmux with stubbed Android commands.
# Usage: tests/tui.sh
# lazy.nvim clones itself and orgmode unless LAZY_DIR or ORGMODE_DIR name a local checkout to copy.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
session="launcher-test-$$"
trap 'tmux kill-session -t "$session" 2>/dev/null || true; rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/config" "$tmp/org" "$tmp/data/nvim/lazy"
ln -s "$repo" "$tmp/config/nvim"
# lazy.nvim does not count a symlink as an installed plugin.
if [ -n "${LAZY_DIR:-}" ]; then cp -R "$LAZY_DIR" "$tmp/data/nvim/lazy/lazy.nvim"; fi
if [ -n "${ORGMODE_DIR:-}" ]; then cp -R "$ORGMODE_DIR" "$tmp/data/nvim/lazy/orgmode"; fi

cat >"$tmp/bin/termux-am" <<EOF
#!/bin/sh
echo "\$*" >>"$tmp/launched"
EOF
cat >"$tmp/bin/cmd" <<'EOF'
#!/bin/sh
cat <<'OUT'
priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
  org.mozilla.firefox/.App
priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
  com.android.camera/.Camera
priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
  org.fdroid.fdroid/.views.main.MainActivity
priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
  com.termux/.app.TermuxActivity
priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
  com.example.determinism/.Main
OUT
EOF
cat >"$tmp/bin/pm" <<'EOF'
#!/bin/sh
for last; do :; done
echo "package:/apk/$last"
EOF
cat >"$tmp/bin/aapt" <<'EOF'
#!/bin/sh
case $3 in
  /apk/com.termux) echo "application-label:'Termux'" ;;
  /apk/com.example.determinism) echo "application-label:'Clock'" ;;
esac
EOF
chmod +x "$tmp/bin/termux-am" "$tmp/bin/cmd" "$tmp/bin/pm" "$tmp/bin/aapt"
printf '* TODO water the plants\n  SCHEDULED: <%s>\n' "$(date +%Y-%m-%d)" >"$tmp/org/todo.org"

export PATH="$tmp/bin:$PATH" ORG_DIR="$tmp/org" XDG_CONFIG_HOME="$tmp/config" \
  XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"

# The first start installs the plugins, and orgmode compiles its tree-sitter grammar
# and reports it with a hit-enter prompt.
nvim --headless "+Lazy! install" -c 'lua vim.wait(120000, function() return pcall(vim.treesitter.language.inspect, "org") end)' -c 'qa!' 2>/dev/null

tmux new-session -d -s "$session" -x 50 -y 24 nvim

screen() { tmux capture-pane -p -t "$session"; }
keys() { tmux send-keys -t "$session" "$@"; }
tap() { tmux send-keys -t "$session" -l "$(printf '\033[<0;%d;%dM\033[<0;%d;%dm' "$1" "$2" "$1" "$2")"; }

bar() { screen | grep -n "⌂" | cut -d: -f1; }

failed=0
expect() {
  what=$1
  shift
  i=0
  until "$@" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 100 ]; then
      echo "FAIL: $what"
      screen | sed 's/^/    | /'
      failed=1
      return
    fi
    sleep 0.1
  done
  echo "ok: $what"
  if [ -n "${SHOW:-}" ]; then screen | sed "s/^/    | /"; fi
}
on_screen() { screen | grep -q -- "$1"; }
not_on_screen() { ! on_screen "$1"; }

expect "home shows the org agenda" on_screen "water the plants"
height=$(tmux display -p -t "$session" '#{pane_height}')
expect "buttons are three rows tall at the bottom" test "$(bar)" = "$((height - 1))"
expect "app list was built on first run" grep -q firefox "$tmp/cache/nvim/launcher-apps.tsv"

keys f i r e
expect "typing shows fuzzy results" on_screen "org.mozilla.firefox"
expect "results replace the agenda" not_on_screen "water the plants"
keys Enter
expect "Enter launches the top match through termux-am" grep -qx "start -n org.mozilla.firefox/.App" "$tmp/launched"
expect "launching returns to the agenda" on_screen "water the plants"

keys o r g
expect "two org.* apps listed" on_screen "org.fdroid.fdroid"
expect "best match sits directly above the prompt" sh -c "tmux capture-pane -p -t $session | grep -B2 '> org' | head -n 1 | grep -q 'org\.'"
row=$(screen | grep -n "org.fdroid.fdroid" | cut -d: -f1)
tap 10 "$row"
expect "tapping a result launches it" grep -qx "start -n org.fdroid.fdroid/.views.main.MainActivity" "$tmp/launched"

tap 25 "$height"
expect "tapping the star shows the inbox file" not_on_screen "water the plants"
keys b u y Space m i l k Enter
button_colors() {
  tmux capture-pane -e -p -t "$session" | tail -n 3 | sed 's/ *$//' |
    grep -o '48;2;[0-9;]*m' | sort | uniq -c | tr -s ' ' | cut -d' ' -f2 | tr '\n' ' '
}
expect "the active button is one solid colour on all three rows, the other is transparent" \
  test "$(button_colors)" = "3 "
expect "the main window has no background" sh -c \
  "! tmux capture-pane -e -p -t $session | head -n 10 | grep -q '48;2;'"
expect "Enter in note mode appends a headline" grep -qx "\* buy milk" "$tmp/org/inbox.org"
expect "the saved note is visible" on_screen "buy milk"
keys c a m
sleep 0.3
expect "typing in note mode does not search" not_on_screen "com.android.camera"

tap 30 "$((height - 2))"
expect "tapping the top row of the note button works too" on_screen "com.android.camera"

tap 45 "$height"
keys Enter
expect "the second note button writes to its own file" grep -qx "\* cam" "$tmp/org/note.org"
expect "the first notes file is left alone" sh -c "! grep -q cam '$tmp/org/inbox.org'"
tap 45 "$height"
expect "tapping the active note button returns to search" on_screen "water the plants"

keys Escape t e r m
expect "package-only match is listed" on_screen "Clock"
expect "a label match outranks a package-name match" sh -c "tmux capture-pane -p -t $session | grep -B2 '> term' | head -n 1 | grep -q 'Termux'"

tap 5 "$height"
expect "tapping home returns to the agenda" on_screen "water the plants"

exit "$failed"
