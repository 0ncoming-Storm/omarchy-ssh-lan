# SSH LAN browser for Omarchy

A Quickshell panel and bar widget for Omarchy that finds SSH servers on your
network and opens them in a terminal with one click. Scans are done with nmap
against IPv4 CIDR ranges you configure; found hosts are remembered, so opening
the panel afterwards only pings them instead of re-scanning the whole network.

## Features

- **Remembered hosts, instant open** — after the first scan, opening the panel
  just pings known hosts (8 at a time, 1 s each) to see which are still alive.
- **Full scans on demand** — press **Rescan** (or `r`) to run a fresh nmap scan
  of your configured ranges at any time.
- **IPv4 CIDR ranges** (`/16`–`/32`), entered in the gear menu.
- **Scans only TCP port 22**.
- **Reverse-DNS names** autofill as display names; editable per host.
- **Per-host settings** — display name, username, and SSH port. The username
  defaults to your current Linux user and the port to 22.
- **Connect** buttons open a new Omarchy terminal.
- **First-connection `ssh-copy-id` offer** so later logins use your key.
- **In-panel log viewer** — latest 200 lines, newest first, with a timestamped
  log on disk.

## Requirements

- OpenSSH (`ssh`), bash, nmap
- `ping` (from iputils, part of a standard Arch install)

No passwords are stored anywhere: SSH prompts for them normally in the
terminal, or you use a key once `ssh-copy-id` has run.

## Install

```bash
omarchy plugin add https://github.com/0ncoming-Storm/omarchy-ssh-lan.git --enable
```

Manual install: clone the repository into
`~/.config/omarchy/plugins/omarchy-ssh-lan/`, then run `omarchy plugin validate`
and `omarchy-shell shell rescanPlugins`.

## Quick start

1. Click the SSH LAN icon in the bar.
2. The first time, the button reads **Scan** — click it (or just open the panel;
   with no known hosts it scans automatically). You need at least one configured
   range first.
3. Click the gear in the panel header and enter your ranges:

   ```text
   192.168.1.0/24
   10.20.0.0/24
   100.92.146.107/32
   ```

4. Back in the list, click **Connect** next to a host, or use its gear to set a
   display name, username, or non-default port.

Subsequent opens skip the scan and just ping the hosts you've discovered.
Hosts that stop answering are hidden until they come back or you **Rescan**.

> Hosts that block ICMP pings won't appear from the ping check — run a
> **Rescan** for those; the full scan probes TCP 22 directly.

## Keyboard shortcuts

While the panel is open:

| Key | Action |
| --- | --- |
| `↑` / `↓` / `j` / `k` | Move the cursor |
| `Enter` | Connect to the selected host |
| `r` | Full rescan |
| `p` | Edit the selected host's settings |
| `Esc` | Close the panel |

Right-clicking the bar icon also triggers a full rescan.

## Logs and security

- Scan and host-check activity is logged to
  `~/.cache/omarchy-ssh-lan/scan.log` (700/600 permissions). The panel shows the
  latest 200 lines, newest first, via **gear → View scan log**.
- Host settings are kept in `~/.config/omarchy/shell.json` under the plugin's
  settings; nothing is written to command-line arguments or the log.
- Scan only networks you own or are authorized to test. Plugins run
  unsandboxed inside the long-lived Omarchy shell process.

## Removing

```bash
omarchy plugin remove 0ncoming-Storm.ssh-lan
```

The command disables the plugin before removing it. Your settings in
`shell.json` are not deleted automatically.