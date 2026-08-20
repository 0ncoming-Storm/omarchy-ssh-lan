# SSH LAN browser for Omarchy

A Quickshell panel and bar widget for Omarchy that discovers SSH servers in
manually configured IPv4 CIDR ranges using nmap. It does not inspect routes,
interfaces, or Tailscale state automatically.

## Features

- Configure one or more IPv4 ranges from the gear button
- Discovered hosts are remembered after each scan
- Opening the panel only pings remembered hosts to see which are still alive, instead of re-scanning the network
- Press **Rescan** (or `r`) for a full nmap scan of your ranges at any time
- Scan only TCP port 22 in those ranges
- Reverse-DNS hostname autofill with editable per-host display names
- Per-host username and SSH port settings
- Explicit **Connect** buttons that open a new Omarchy terminal
- First-connection `ssh-copy-id` offer
- Timestamped scan log (including host checks) with an in-panel viewer

## Install

```bash
omarchy plugin add https://github.com/0ncoming-Storm/omarchy-ssh-lan.git --enable
```

Or install manually into `~/.config/omarchy/plugins/linuxinthebox.ssh-lan/`,
then run `omarchy plugin validate` and `omarchy-shell shell rescanPlugins`.

The plugin requires OpenSSH, bash, and nmap.

## Removal

```bash
omarchy plugin remove linuxinthebox.ssh-lan
```

The command disables the plugin before removing it. User settings in
`shell.json` are not deleted automatically.

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

On the first open (when nothing has been discovered yet) the panel runs a full
nmap scan. After that, hosts found by a scan are stored in the plugin settings
under `knownHosts`, and opening the panel only pings those remembered addresses
(as a parallel, one-second probe each) to show which are alive. Hosts that stop
answering disappear from the list until they come back or you run a full
rescan. Note that hosts which block ICMP pings will not appear from the ping
check; use **Rescan** for them.

## Logs and security

Scan and host-check logs are stored at `~/.cache/omarchy-ssh-lan/scan.log`,
with the latest 200 lines available in the panel.

Scan only networks you own or are authorized to test. Plugins run unsandboxed
inside the long-lived Omarchy shell process.
