# Audio: WineASIO und PipeWire

Ohne ASIO-Treiber stellt Wine FL Studio nur zwei Eingänge über WASAPI zur Verfügung. Mit [WineASIO](https://github.com/wineasio/wineasio) und PipeWires JACK-Schnittstelle sind alle Kanäle eines Interfaces nutzbar.

## Einrichtung

```bash
sudo pacman -S wineasio
bash scripts/07-setup-wineasio.sh
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Das Skript registriert WineASIO im Prefix, setzt Ein-/Ausgangszahl und Buffergröße und legt `~/.config/pipewire/pipewire.conf.d/10-sample-rate.conf` an (44,1 kHz).

In FL: *Options → Audio Settings → Device → WineASIO*. Input-Monitoring im Mixer deaktivieren, um Rückkopplungen zu vermeiden.

## Wiedergabe zu langsam oder zu schnell (Tonhöhe korrekt)

**Symptom:** Ein Sample von 3 s braucht z. B. 12 s, oder läuft viel zu schnell; die Tonhöhe stimmt. Betrifft Projekt und Browser-Vorschau, der Faktor kann sich zwischen Starts ändern.

**Ursache:** WineASIO arbeitet mit fester Buffergröße und meldet sie FL. Weicht das PipeWire-Quantum davon ab, läuft FL um genau dieses Verhältnis falsch:

- Interface erzwingt größeres Quantum (z. B. `period-size = 2048`) → 2048 / 512 = 4× zu langsam
- FL zieht das Quantum nach einer Neuverhandlung nach unten (z. B. 128) → 4× zu schnell
- Stehen 44,1 und 48 kHz in `allowed-rates`, wechselt zusätzlich die Rate

**Diagnose:**

```bash
pw-top -b -n 4                                  # RATE/QUANT am Treiber-Node
grep -i buffersize "$WINEPREFIX/user.reg"       # WineASIO-Buffer
```

Gleiche Tonhöhe → Quantum/Buffer-Mismatch. Veränderte Tonhöhe → echtes Sample-Rate- oder Clock-Problem.

**Lösung:** Rate und Quantum hart fixieren. Ein bloßer `max-quantum`-Deckel genügt nicht.

```bash
cat > ~/.config/pipewire/pipewire.conf.d/20-wineasio-quantum.conf << 'EOF'
# force-quantum muss der WineASIO-Buffergröße entsprechen
context.properties = {
    default.clock.rate          = 44100
    default.clock.quantum       = 512
    default.clock.force-rate    = 44100
    default.clock.force-quantum = 512
}
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Ohne Neustart testen (Wert `0` hebt auf):

```bash
pw-metadata -n settings 0 clock.force-quantum 512
pw-metadata -n settings 0 clock.force-rate    44100
```

## Webcam-Mikrofon auf FL-Eingang 1

WineASIO verbindet bei `Connect to hardware = 1` alle physischen JACK-Capture-Ports – auch USB-Webcam-Mikrofone. Diese landen zusätzlich auf `FL64:in_1`, werden mit dem Interface-Signal summiert und, wenn sie nur 48 kHz beherrschen, in den 44,1-kHz-Graphen resampelt. Im Journal erscheint dann:

```
spa.alsa: hw:N,0c: follower delay:… resample:1, resync
```

**Variante A – WirePlumber-Regel:** dem Gerät `node.physical` entziehen.

```bash
cat > ~/.config/wireplumber/wireplumber.conf.d/51-webcam-not-physical.conf << 'EOF'
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_input.usb-046d_Brio_100.*" } ]
    actions = { update-props = { node.physical = false } }
  }
]
EOF
systemctl --user restart wireplumber
```

Nachteil: Bei manchen Geräten (z. B. Logitech Brio) verschwindet das Mikrofon damit auch aus der Geräteauswahl anderer Anwendungen.

**Variante B – im Launcher trennen:** Nach dem Start alle Quellen von `FL64:in_*` lösen, die nicht vom Audio-Interface kommen.

```bash
IN="alsa_input.usb-<Interface>.pro-input-0"
pw-link -l \
  | awk -v keep="${IN}:" '/^[^ ]/ {port = ($1 ~ /^FL64:in_/) ? $1 : ""; next}
                          port != "" && $1 == "|<-" && index($2, keep) != 1 {print $2, port}' \
  | while read -r src dst; do pw-link -d "$src" "$dst"; done
```

## Feste Verdrahtung mehrerer Ausgänge

Mit dem PipeWire-Profil *Pro Audio* lassen sich FL-Ausgänge gezielt auf Interface-Kanäle legen (z. B. Out 3/4 als Sidechain-Trigger für Hardware). `pw-jack` verbindet beim Start oft nur Out 1/2; ein Block im Launcher wartet auf die FL-Ports und setzt die Links mit `pw-link`. Interface-Profil vorher setzen:

```bash
wpctl set-profile <device-id> <pro-audio-index>
```
