# Running ion-sfu on WSL for local group-call testing

This guide bootstraps a local [ion-sfu](https://github.com/ionorg/ion-sfu)
inside WSL2 so the Rainbow client's group-call code path
(`AppConfig.sfuUrl`) has something to talk to. No Docker required.

Once the SFU is up, set:

```dart
AppConfig(
  ...
  sfuUrl: Uri.parse('ws://localhost:7000/ws'),
)
```

and the "Group call" banner appears at the top of every bubble.

## Prerequisites

- WSL2 installed with an Ubuntu distro (`wsl --install -d Ubuntu-24.04`).
- **Go 1.22+** inside WSL. The system apt package is usually too old.
- The Flutter host on Windows can reach `localhost:<port>` on WSL2
  because WSL2 forwards `localhost` to the guest for TCP by default.
  For UDP (needed for WebRTC media) you either need a recent Windows
  build (Windows 11 24H2+ or `wslconfig` with `localhostForwarding`
  and `networkingMode=mirrored`) or you deploy ion-sfu directly on
  Windows through Go. See "UDP caveat" below.

## Install Go 1.22+ in WSL

Ubuntu's default `golang-go` package is often behind. Install upstream:

```bash
cd /tmp
GO_VERSION=1.22.6
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
go version   # → go version go1.22.6 linux/amd64
```

## Build ion-sfu

The `latest-jsonrpc` binary is what the Flutter client speaks to.

```bash
cd ~
git clone https://github.com/ionorg/ion-sfu.git
cd ion-sfu
go build -o ~/bin/ion-sfu-jsonrpc ./cmd/signal/json-rpc
```

## Config

The signaler reads a TOML file. Save this as `~/ion-sfu.toml`:

```toml
[sfu]
ballast = 0
withstats = false

[webrtc]
# ephemeral UDP ports used by ion-sfu for media
portrange = [5000, 5200]

[webrtc.iceserver]
# Match the client's AppConfig.iceServers.
urls = ["stun:stun.l.google.com:19302"]

[signal]
# JSON-RPC 2.0 WebSocket endpoint.
addr = "0.0.0.0:7000"

[log]
level = "info"
```

## Run

```bash
~/bin/ion-sfu-jsonrpc -c ~/ion-sfu.toml
# → INFO ... [signal] http server started at 0.0.0.0:7000
```

Point the client at it (dev config):

```dart
sfuUrl: Uri.parse('ws://localhost:7000/ws'),
```

Sanity check from the host (Windows PowerShell):

```powershell
Test-NetConnection localhost -Port 7000
# → TcpTestSucceeded : True
```

## UDP caveat

`localhost` port forwarding to WSL2 covers **TCP only** by default —
the signaling WebSocket works, but media (UDP `portrange = [5000, 5200]`
above) may not reach WSL from Windows. Options in order of preference:

1. **Windows 11 24H2 or newer** — enable `networkingMode=mirrored`
   in `%USERPROFILE%\.wslconfig`; both TCP and UDP forward.
   ```ini
   [wsl2]
   networkingMode=mirrored
   ```
2. **Explicit UDP forward** via `netsh interface portproxy` — verbose
   and not persistent across restarts.
3. **Run ion-sfu on Windows** — the Go build works natively on
   Windows too: `go build -o ion-sfu.exe .\cmd\signal\json-rpc\` from
   the repo checkout. No forwarding needed at the cost of an extra Go
   toolchain on the Windows side.

If the client sees the signaling `<enabled/>` but every session
times out on ICE, you're hitting the UDP-forwarding gap. Switch to
option 1 or 3.

## Verifying end-to-end

1. Start the stub (`chdir c:\www\dart\rainbow-stub; dart run bin/server.dart`)
   and ion-sfu (`~/bin/ion-sfu-jsonrpc -c ~/ion-sfu.toml`).
2. Launch two Flutter clients pointing at the stub with `sfuUrl` set.
3. Sign one as alice, one as bob. Both join the same bubble.
4. Alice taps the "Group call · Audio" (or "Video") button.
5. Bob sees a "Call in progress · started by alice — Join" chip in
   the bubble; tapping it enters the full-screen grid.
6. Watch the ion-sfu console: it logs `join` and `trickle` calls
   for each participant.

## Shutdown

```bash
# ion-sfu-jsonrpc runs in the foreground — Ctrl+C to stop.
```

State is in-memory; nothing to clean up.

## Follow-ups (not in this recipe)

- **TURN** — currently only STUN. Needed for cross-network calls.
  Install [coturn](https://github.com/coturn/coturn) on the same
  WSL guest and add its URL to `AppConfig.iceServers`.
- **TLS** — the JSON-RPC signaler serves `ws://`. Browsers reject
  mixed content, so a web-built client needs `wss://`. Front the
  binary with `caddy` or `nginx` doing TLS termination.
- **Systemd unit** — the launcher above is one-shot. For a persistent
  dev SFU, drop a `~/.config/systemd/user/ion-sfu.service` and
  `systemctl --user enable --now ion-sfu`.
