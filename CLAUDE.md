# CLAUDE.md

## Device

The launcher runs on a phone in Termux. `CLAUDE.local.md` holds the ssh command for the
current phone. It stays out of git because this repo is public. Below, `phone` stands for
that command.

## Reaching the phone

Today `phone` goes over Tailscale. Banking apps on the phone refuse to run while any VPN is
up, and Tailscale is a VPN on Android, so the user turns it off to bank. While it is off,
`phone` times out. Ask the user to turn Tailscale back on, and wait until `tailscale status`
no longer lists the phone as offline.

Keep "Use Tailscale DNS" off in the phone's Tailscale app. With it on, Termux could not
resolve any public name, and `git pull` failed with `Could not resolve host: github.com`.

The org sync does not need Tailscale. teamtype reaches its peer through iroh relays on port
443.

sshd on the phone accepts keys only. `PasswordAuthentication no` and
`KbdInteractiveAuthentication no` are appended to `$PREFIX/etc/ssh/sshd_config`, and the
file as it was before is in `sshd_config.bak`. To restart sshd without dropping your own
session, kill only the listener in `$PREFIX/var/run/sshd.pid`, then run `sshd`.

### Cloudflare Tunnel (unfinished)

The plan is to reach the phone through a Cloudflare Tunnel, which runs as an ordinary
process and is not a VPN, so banking keeps working:

```
desktop ssh -> cloudflared access (ProxyCommand) -> Cloudflare -> cloudflared on the phone -> sshd :8022
```

Status: `cloudflared` 2026.11.2 is installed in Termux, and this machine has 2026.10.2.
`cloudflared tunnel login` on the phone ended with `Failed to fetch resource` and wrote no
`~/.cloudflared/cert.pem`. A named tunnel needs a domain on Cloudflare, and the user has not
named one yet.

Remaining steps, with `<host>` for the chosen hostname:

1. On the phone, in the `claude` tmux session: `cloudflared tunnel login`, then
   `cloudflared tunnel create phone`, `cloudflared tunnel route dns phone <host>`, and keep
   `termux-wake-lock; cloudflared tunnel run --url ssh://localhost:8022 phone` running.
   Without the wake lock, Android stops it when the screen goes off.
2. On this machine, add to `~/.ssh/config`:
   ```
   Host phone
     HostName <host>
     User <user>
     ProxyCommand cloudflared access ssh --hostname %h
   ```
   Then make `CLAUDE.local.md` say `ssh phone`.
3. The user adds a Cloudflare Access application for `<host>` in the dashboard, allowing
   only their own account. Without it, anyone who knows the hostname reaches sshd.
4. With Tailscale off on the phone, check that `ssh phone true` works.

The hostname, tunnel ID, and `~/.cloudflared/*.json` credentials stay out of this repo.

Run nvim, the launcher, the sync daemon, and anything else that stays open or
needs input inside a tmux session named `claude`. The session keeps running when
SSH drops, and `capture-pane` prints its screen.

```sh
# Start the session, or reuse it if it exists.
phone 'tmux has-session -t claude 2>/dev/null || tmux new-session -d -s claude'

# Type a command into the session.
phone "tmux send-keys -t claude 'nvim' Enter"

# Print the screen.
phone 'tmux capture-pane -p -t claude'
```

Leave the session running when you finish, so the user can check the result with
`tmux attach -t claude`. Tell them it is still open. Kill it only when you need
a fresh start, such as before relaunching nvim with changed config, and
recreate it right away.

`send-keys` returns before the command finishes. Wait for the prompt to come
back before you read the screen.

Commands that finish on their own, such as `ls`, `cat`, or `git status`, can run
over plain `ssh`.

## Keeping the phone in sync

The phone's `~/.config/nvim` is a clone of this repo. Change files here, run
`tests/tui.sh`, commit, and push to `origin main`. Then update the phone:

```sh
phone 'git -C ~/.config/nvim pull --ff-only'
```

Copying a file over with `scp` to try it out is fine. Before you pull, check that the
phone has no uncommitted changes, with `git -C ~/.config/nvim status --short`, so the two
histories never split.

## Moving to a new phone

The old phone was a Pixel 5a running Termux from F-Droid, with `com.termux.styling`.

1. The user installs Termux and Tailscale on the new phone. Then, in Termux:
   ```sh
   pkg update && pkg upgrade
   pkg install openssh tmux neovim git clang termux-am-socket aapt cloudflared
   passwd
   sshd
   whoami
   ```
   They give you the `whoami` user and the phone's Tailscale `100.x` address. sshd listens
   on port 8022. Once your key is installed in step 2, turn off password login as described
   in "Reaching the phone", and have them turn off "Use Tailscale DNS".
2. Write `ssh -p 8022 <user>@<address>` into `CLAUDE.local.md`. Install this machine's key
   with `ssh-copy-id -p 8022 <user>@<address>`, so later commands need no password.
3. Clone the config:
   ```sh
   phone 'git clone https://github.com/Iodize13/termux-launcher.nvim ~/.config/nvim'
   ```
4. Install teamtype into `$PREFIX/bin`. The old phone ran teamtype 0.9.3, the same version
   as this machine. Nobody recorded how that binary was built. Termux has a `rust` package,
   so building it in Termux with cargo is the likely route, but nobody has tested it.
5. Join the org sync. On this machine the daemon runs as the systemd user unit in
   `desktop/teamtype-org.service`. Stop it with `systemctl --user stop teamtype-org`, run
   `teamtype share` in `~/org`, which prints a join code, and start the unit again once the
   phone has joined. On the phone, run `mkdir -p ~/org`, then `teamtype join <code> --directory ~/org`
   inside the `claude` tmux session. That writes `~/org/.teamtype/config`, and from then on
   the launcher starts the daemon itself. The join code is a secret, so keep it out of
   every file in this repo.
6. Start the launcher with `nvim` in the `claude` session. The first start clones lazy.nvim
   and the plugins, and compiles orgmode's tree-sitter grammar. Check that the agenda and
   the app list show up, then tap a notes button and save a note.

The old phone also had files that live in no repo. You can only bring them over if they
were backed up first:

- `~/bin/termdeck`, a separate launcher binary
- `~/bin/termux-wal`, which turns a pywal palette into Termux colours
- `~/.termux`, which holds `background.png`, `colors.properties`, `font.ttf`, and `termux.properties`
