# xara im Docker-Container

(English version: [README.md](README.md))

## Überblick

Dieses Verzeichnis enthält alles, um xara (VARA-kompatibles Modem) als
Container zu betreiben. Es gibt zwei Varianten, ausgewählt über Compose-Profile:

| Profil           | Service           | Image             | Build-Arg            |
|------------------|-------------------|-------------------|----------------------|
| `unregistered`   | `xara`            | `xara:latest`     | `REGISTERED=false`   |
| `registered`     | `xara-registered` | `xara:registered` | `REGISTERED=true`    |

Beide Varianten verwenden dieselben Host-Ports (8300, 8301, 8100, 8080) und
dasselbe State-Volume: **es darf immer nur ein Profil laufen.**

## Voraussetzungen

- Docker Engine mit Compose-Plugin (`docker compose`)
- Soundkarte/Interface am Host (ALSA, oder PulseAudio/PipeWire)
- Auf dem Host muss `/dev/snd` existieren (Soundtreiber geladen), sonst
  scheitert `docker compose up` an der `devices:`-Zeile. Ohne Soundkarte
  (z. B. nur zum Testen) den Eintrag entfernen und `capture = null` /
  `playback = null` (ALSA-Nulldevice) in `xara.conf` setzen.
- Ggf. PTT-Gerät (CM108/AIOC über `/dev/hidrawN`, oder USB-Seriell für RTS/DTR)

## Konfiguration anlegen

```sh
cd docker
cp xara.conf.example xara.conf
$EDITOR xara.conf        # mindestens call, hf/fm, capture/playback
```

`xara.conf` wird read-only nach `/config/xara.conf` gemountet und ist per
`.gitignore` von Git ausgeschlossen. Nach Änderungen: `docker compose restart`.

Wichtig: Im Container müssen `addr = 0.0.0.0` und (für die Web-UI)
`ui-addr = 0.0.0.0` gesetzt sein, sonst sind die veröffentlichten Ports nicht
erreichbar. Die Beispieldatei enthält das bereits. Die Absicherung erfolgt über
die Port-Bindung in `docker-compose.yml` (standardmäßig nur `127.0.0.1`).

## Variante unregistriert vs. registriert

- **Unregistriert** (`xara:latest`): Standard, ohne erhöhte Geschwindigkeiten.
- **Registriert** (`xara:registered`): mit Cargo-Feature `registered` gebaut,
  der Entrypoint übergibt `--registered` automatisch. Bitte nur verwenden, wenn
  du eine registrierte VARA-Lizenz besitzt (siehe Haupt-README, Abschnitt
  "registered mode").

Den Schlüssel `registered` **nicht** in `xara.conf` eintragen: im
unregistrierten Image bricht xara dann mit "not built with registered
features" ab. (Beides gleichzeitig, Config und Kommandozeile, ist dagegen
kein Fehler.)

## Starten, Stoppen, Logs

Alle Befehle im Verzeichnis `docker/`:

```sh
# Starten (baut das Image bei Bedarf)
docker compose --profile unregistered up -d --build
docker compose --profile registered   up -d --build

# Logs
docker compose --profile unregistered logs -f

# Stoppen
docker compose --profile unregistered down
```

Vor einem Wechsel der Variante die laufende zuerst mit `down` stoppen. Der
State (Web-UI-Einstellungen, Token) liegt im Volume `xara-state` und bleibt bei
`down` erhalten (`down -v` löscht ihn).

## Web-UI und Token

Die UI läuft unter `http://127.0.0.1:8080/` (nur wenn `ui-port` gesetzt ist).
Ist `ui-control` aktiv, loggt xara beim Start die URL mit `?token=...`. Dort steht
wegen `ui-addr = 0.0.0.0` die Adresse `0.0.0.0`; im Browser stattdessen
`127.0.0.1` verwenden (`http://127.0.0.1:8080/?token=...`):

```sh
docker compose --profile unregistered logs | grep token
```

Das Token liegt außerdem (nur mit `ui-control`) im State-Volume als Datei `ui-token`:

```sh
docker compose --profile unregistered exec xara cat /state/ui-token
```

Greifst du über einen anderen Hostnamen als IP, `localhost` oder `*.local`
zu, trage ihn per `ui-host = NAME` ein, sonst antwortet die UI mit
"403 Host not allowed".

## Audio-Geräte auflisten

```sh
docker compose run --rm xara --list-devices --audio alsa
```

Die ausgegebenen Namen (z. B. `plughw:CARD=Device,DEV=0`) kommen als
`capture`/`playback` in `xara.conf`. (Ein explizit genannter Service aktiviert
sein Profil automatisch; für die registrierte Variante `xara-registered` statt
`xara` verwenden.) Die `xara.conf` muss dafür existieren, ggf. mit Platzhalterwerten.

Für PulseAudio/PipeWire in `docker-compose.yml` den Socket-Mount und
`PULSE_SERVER=unix:/run/pulse/native` aktivieren, `/dev/snd` entfernen,
`audio = pulse` setzen und `user: "${UID}:${GID}"` einkommentieren
(vorher `export UID GID`, falls die Shell sie nicht exportiert).

## PTT-Geräte durchreichen

In `docker-compose.yml` unter `devices:` die passende Zeile aktivieren:

```yaml
- /dev/hidraw0:/dev/hidraw0                 # cm108 / AIOC
- /dev/ttyUSB0:/dev/ttyUSB0                 # rts / dtr
- /dev/serial/by-id/usb-XXXX-if00:/dev/serial/by-id/usb-XXXX-if00
```

und in `xara.conf` `radio = on` plus `ptt = ...` setzen. Pfade
`/dev/serial/by-id/...` sind stabil, `hidrawN`/`ttyUSBN` können sich beim
Booten ändern.

Der Container-User `xara` (UID/GID 1000) ist in den Gruppen `audio`,
`dialout` und `plugdev`. Die numerischen GIDs auf dem Host können aber anders
sein, dann fehlt der Zugriff auf die Geräte ("Permission denied"). Abhilfe:
Host-GIDs ermitteln und in `group_add` numerisch eintragen:

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

## Sicherheitshinweise

- KISS-Port (8100) sowie Command-/Datenport (8300/8301) sind **nicht
  authentifiziert**. Jeder, der sie erreicht, kann senden.
- Mit `ui-control` darf jeder mit dem Token den Sender tasten.
- Daher sind alle Ports standardmäßig auf `127.0.0.1` gebunden. Für Zugriff
  aus dem LAN `127.0.0.1:` aus den `ports:`-Einträgen entfernen oder durch die
  LAN-IP des Hosts ersetzen, und nur in einem vertrauenswürdigen Netz tun
  (Firewall, VPN oder SSH-Tunnel bevorzugen).
- `addr = 0.0.0.0` in der Config betrifft nur das Container-Netz; die
  tatsächliche Erreichbarkeit bestimmt das Port-Mapping.

## xara-monitor ausführen

Ist `xara-monitor` das erste Argument, startet der Entrypoint den Monitor statt
xara. Er sendet nie. Das Audio-Gerät darf nicht gleichzeitig von xara belegt
sein, daher xara vorher stoppen:

```sh
docker compose --profile unregistered down
docker compose run --rm xara xara-monitor --audio alsa --capture plughw:CARD=Device,DEV=0
```

Mit Web-UI (`--ui-port 8080 --ui-addr 0.0.0.0`) zusätzlich `-p 127.0.0.1:8080:8080` angeben.

## Images ohne Compose bauen

Aus dem Repository-Root:

```sh
docker build -f docker/Dockerfile -t xara:latest .
docker build -f docker/Dockerfile --build-arg REGISTERED=true -t xara:registered .
```

Starten ohne Compose, Beispiel:

```sh
docker run -d --name xara --init --restart unless-stopped \
  --device /dev/snd --group-add audio \
  -v $PWD/docker/xara.conf:/config/xara.conf:ro -v xara-state:/state \
  -p 127.0.0.1:8300:8300 -p 127.0.0.1:8301:8301 -p 127.0.0.1:8100:8100 -p 127.0.0.1:8080:8080 \
  xara:latest
```
