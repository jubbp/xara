# xara in a Docker container

(Deutsche Version: [README.de.md](README.de.md))

## Overview

This directory contains everything needed to run xara (the VARA-compatible
modem) as a container. There are two variants, selected via Compose profiles:

| Profile          | Service           | Image             | Build arg            |
|------------------|-------------------|-------------------|----------------------|
| `unregistered`   | `xara`            | `xara:latest`     | `REGISTERED=false`   |
| `registered`     | `xara-registered` | `xara:registered` | `REGISTERED=true`    |

Both variants use the same host ports (8300, 8301, 8100, 8080) and the same
state volume: **only run one profile at a time.**

## Requirements

- Docker Engine with the Compose plugin (`docker compose`)
- a sound card/interface on the host (ALSA, or PulseAudio/PipeWire)
- `/dev/snd` must exist on the host (sound driver loaded), otherwise
  `docker compose up` fails on the `devices:` entry. Without a sound card
  (e.g. just for testing), remove that entry and set `capture = null` /
  `playback = null` (ALSA null device) in `xara.conf`.
- optionally a PTT device (CM108/AIOC via `/dev/hidrawN`, or USB serial for
  RTS/DTR)

## Create the configuration

```sh
cd docker
cp xara.conf.example xara.conf
$EDITOR xara.conf        # at least call, hf/fm, capture/playback
```

`xara.conf` is mounted read-only at `/config/xara.conf` and is excluded from
git via `.gitignore`. After changes: `docker compose restart`.

Important: inside the container, `addr = 0.0.0.0` and (for the web UI)
`ui-addr = 0.0.0.0` must be set, otherwise the published ports are not
reachable. The example file already does this. Access is restricted by the
port bindings in `docker-compose.yml` (only `127.0.0.1` by default).

## Unregistered vs. registered

- **Unregistered** (`xara:latest`): the default, without the higher speeds.
- **Registered** (`xara:registered`): built with the cargo feature
  `registered`; the entrypoint passes `--registered` automatically. Only use
  this if you own a registered copy of VARA (see the main README, section
  "registered mode").

Do **not** put the `registered` key into `xara.conf`: in the unregistered
image xara then aborts with "not built with registered features". (In the
registered image, having it in both the config and on the command line is
not an error.)

## Start, stop, logs

All commands are run from the `docker/` directory:

```sh
# start (builds the image if needed)
docker compose --profile unregistered up -d --build
docker compose --profile registered   up -d --build

# logs
docker compose --profile unregistered logs -f

# stop
docker compose --profile unregistered down
```

Before switching variants, stop the running one with `down` first. The state
(web UI settings, token) lives in the `xara-state` volume and survives `down`
(`down -v` deletes it).

## Web UI and token

The UI is served at `http://127.0.0.1:8080/` (only if `ui-port` is set). With
`ui-control` enabled, xara logs the URL including `?token=...` at startup.
Because of `ui-addr = 0.0.0.0` the logged address is `0.0.0.0`; use
`127.0.0.1` in the browser instead (`http://127.0.0.1:8080/?token=...`):

```sh
docker compose --profile unregistered logs | grep token
```

The token is also stored (only with `ui-control`) in the state volume as the
file `ui-token`:

```sh
docker compose --profile unregistered exec xara cat /state/ui-token
```

If you access the UI via a hostname other than an IP, `localhost` or
`*.local`, add it with `ui-host = NAME`, otherwise the UI responds with
"403 Host not allowed".

## Listing audio devices

```sh
docker compose run --rm xara --list-devices --audio alsa
```

Put the printed names (e.g. `plughw:CARD=Device,DEV=0`) into `xara.conf` as
`capture`/`playback`. (Naming a service explicitly activates its profile; for
the registered variant use `xara-registered` instead of `xara`.) `xara.conf`
must exist for this, with placeholder values if necessary.

For PulseAudio/PipeWire, enable the socket mount and
`PULSE_SERVER=unix:/run/pulse/native` in `docker-compose.yml`, remove
`/dev/snd`, set `audio = pulse` and uncomment `user: "${UID}:${GID}"`
(run `export UID GID` first if your shell doesn't export them).

## Passing through PTT devices

Enable the matching line under `devices:` in `docker-compose.yml`:

```yaml
- /dev/hidraw0:/dev/hidraw0                 # cm108 / AIOC
- /dev/ttyUSB0:/dev/ttyUSB0                 # rts / dtr
- /dev/serial/by-id/usb-XXXX-if00:/dev/serial/by-id/usb-XXXX-if00
```

and set `radio = on` plus `ptt = ...` in `xara.conf`. Paths under
`/dev/serial/by-id/...` are stable; `hidrawN`/`ttyUSBN` may change between
boots.

The container user `xara` (UID/GID 1000) is a member of the groups `audio`,
`dialout` and `plugdev`. The numeric GIDs on the host may differ, though, in
which case device access fails ("Permission denied"). Fix: look up the host
GIDs and add them numerically under `group_add`:

```sh
getent group audio dialout plugdev
ls -ln /dev/snd/ /dev/hidraw0
```

```yaml
group_add:
  - "29"     # audio
  - "20"     # dialout
  - "46"     # plugdev
```

## Security notes

- The KISS port (8100) and the command/data ports (8300/8301) are **not
  authenticated**. Anyone who can reach them can transmit.
- With `ui-control`, anyone holding the token can key the transmitter.
- That's why all ports are bound to `127.0.0.1` by default. For LAN access,
  remove `127.0.0.1:` from the `ports:` entries or replace it with the host's
  LAN IP, and only do so on a trusted network (prefer a firewall, VPN or SSH
  tunnel).
- `addr = 0.0.0.0` in the config only affects the container network; actual
  reachability is determined by the port mapping.

## Running xara-monitor

If `xara-monitor` is the first argument, the entrypoint runs the monitor
instead of xara. It never transmits. The audio device must not be in use by
xara at the same time, so stop xara first:

```sh
docker compose --profile unregistered down
docker compose run --rm xara xara-monitor --audio alsa --capture plughw:CARD=Device,DEV=0
```

For the web UI (`--ui-port 8080 --ui-addr 0.0.0.0`) also pass
`-p 127.0.0.1:8080:8080`.

## Building images without Compose

From the repository root:

```sh
docker build -f docker/Dockerfile -t xara:latest .
docker build -f docker/Dockerfile --build-arg REGISTERED=true -t xara:registered .
```

Running without Compose, for example:

```sh
docker run -d --name xara --init --restart unless-stopped \
  --device /dev/snd --group-add audio \
  -v $PWD/docker/xara.conf:/config/xara.conf:ro -v xara-state:/state \
  -p 127.0.0.1:8300:8300 -p 127.0.0.1:8301:8301 -p 127.0.0.1:8100:8100 -p 127.0.0.1:8080:8080 \
  xara:latest
```
