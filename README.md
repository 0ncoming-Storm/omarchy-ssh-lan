# SSH LAN browser for Omarchy

A Quickshell panel and bar widget for Omarchy that discovers SSH servers in
manually configured IPv4 CIDR ranges using nmap. It does not inspect routes,
interfaces, or Tailscale state automatically.

## Features

- Configure one or more IPv4 ranges from the gear button
- Scan only TCP port 22 in those ranges
- Reverse-DNS hostname autofill with editable per-host display names
- Per-host username, SSH port, and keyring-backed password settings
- Explicit **Connect** buttons that open a new Omarchy terminal
- First-connection `ssh-copy-id` offer
- Timestamped scan log with an in-panel viewer

## Install

```bash
omarchy plugin add https://github.com/YOUR_ACCOUNT/omarchy-ssh-lan.git --enable
```

Or install manually into `~/.config/omarchy/plugins/linuxinthebox.ssh-lan/`,
then run `omarchy plugin validate` and `omarchy-shell shell rescanPlugins`.

The plugin requires OpenSSH, bash, and nmap. Password saving requires
`secret-tool` from `libsecret`.

## Removal

```bash
omarchy plugin remove linuxinthebox.ssh-lan
```

The command disables the plugin before removing it. User settings in
`shell.json` and keyring entries are not deleted automatically.

## Configuration

Open the panel and click the gear in the header. Enter one IPv4 CIDR per line,
for example:

```text
192.168.1.0/24
10.20.0.0/24
100.92.146.107/32
```

Only `/16` through `/32` ranges are accepted. Split larger networks before
scanning them. Host settings are edited with the gear beside each discovered
host. The username defaults to the current Linux user and the port defaults to
22. Reverse-DNS names are used as initial display names when available.

## Logs and security

Scan logs are stored at `~/.cache/omarchy-ssh-lan/scan.log`, with the latest 200
lines available in the panel. Passwords are stored through Secret Service and
are never written to plugin settings, command-line arguments, or scan logs.

Scan only networks you own or are authorized to test. Plugins run unsandboxed
inside the long-lived Omarchy shell process.
