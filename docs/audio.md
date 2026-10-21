# Audio: WineASIO and PipeWire

Without an ASIO driver, Wine only gives FL Studio two inputs via WASAPI. With [WineASIO](https://github.com/wineasio/wineasio) and PipeWire's JACK interface, every channel of your audio interface is available.

## Setup

```bash
bash scripts/07-setup-wineasio.sh     # installs/builds WineASIO itself if needed
# other values: ASIO_INPUTS=4 ASIO_OUTPUTS=4 ASIO_BUFFER=512 bash scripts/07-setup-wineasio.sh
```

The script installs WineASIO (Arch: AUR, otherwise built from source), registers it in the prefix and sets the number of inputs/outputs and the buffer size (default 16/16, 512 samples). The `flstudio-wine` launcher then starts FL through `pw-jack` and pins the PipeWire quantum to the buffer size (see below).

In FL: *Options → Audio Settings → Device → WineASIO*. Turn off input monitoring in the mixer to avoid feedback.

## Playback too slow or too fast (pitch is correct)

**Symptom:** A 3-second sample takes 12 seconds, for example, or plays far too fast; the pitch is right. This affects both the project and the browser preview, and the factor can change between starts.

**Cause:** WineASIO works with a fixed buffer size and reports it to FL. If the PipeWire quantum differs, FL runs off by exactly that ratio:

- The interface forces a larger quantum (e.g. `period-size = 2048`) → 2048 / 512 = 4× too slow
- After a renegotiation, FL pulls the quantum down (e.g. to 128) → 4× too fast
- If both 44.1 and 48 kHz are listed in `allowed-rates`, the rate can change as well

**Diagnosis:**

```bash
pw-top -b -n 4                                  # RATE/QUANT on the driver node
grep -i buffersize "$WINEPREFIX/user.reg"       # WineASIO buffer
```

Same pitch → quantum/buffer mismatch. Changed pitch → a real sample-rate or clock problem.

**Fix:** pin the rate and quantum at runtime - `flstudio-wine` does this automatically on start and resets it on exit. Just capping `max-quantum` is not enough, and PipeWire does **not** pick up `default.clock.force-*` from a config file (it only works at runtime).

By hand (`0` removes the setting):

```bash
pw-metadata -n settings 0 clock.force-quantum 512     # = WineASIO buffer size
pw-metadata -n settings 0 clock.force-rate    48000   # = current rate
```

## Webcam microphone on FL input 1

With `Connect to hardware = 1`, WineASIO connects every physical JACK capture port - including USB webcam microphones. Those end up on `FL64:in_1` as well, get summed with the interface signal and, if they only support 48 kHz, are resampled into the 44.1 kHz graph. The journal then shows:

```
spa.alsa: hw:N,0c: follower delay:… resample:1, resync
```

**Option A – WirePlumber rule:** take `node.physical` away from the device.

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

Downside: with some devices (e.g. the Logitech Brio) the microphone then also disappears from the device list of other applications.

**Option B – disconnect at start-up:** remove every link to `FL64:in_*` that doesn't come from the audio interface. Put this into `~/.config/fl-studio-wine/pre-start.sh` (see [fixed routing](#fixed-routing-for-several-outputs)), inside the background block after FL's ports exist.

```bash
IN="alsa_input.usb-<Interface>.pro-input-0"
pw-link -l \
  | awk -v keep="${IN}:" '/^[^ ]/ {port = ($1 ~ /^FL64:in_/) ? $1 : ""; next}
                          port != "" && $1 == "|<-" && index($2, keep) != 1 {print $2, port}' \
  | while read -r src dst; do pw-link -d "$src" "$dst"; done
```

## Fixed routing for several outputs

With the PipeWire *Pro Audio* profile you can route FL outputs to specific interface channels (e.g. outputs 3/4 as a sidechain trigger for outboard gear). On start-up `pw-jack` often only connects outputs 1/2, so the links have to be created once FL's ports exist.

Such setup-specific steps belong in `~/.config/fl-studio-wine/pre-start.sh`. The launcher sources this file right before it starts FL, and `git pull` never touches it. Example for a 4-in/4-out interface:

```bash
# ~/.config/fl-studio-wine/pre-start.sh
(
    OUT="alsa_output.usb-<Interface>.pro-output-0"
    IN="alsa_input.usb-<Interface>.pro-input-0"
    for i in $(seq 1 80); do                      # wait up to ~40 s for FL's ports
        pw-link -o 2>/dev/null | grep -qx 'FL64:out_4' && break
        sleep 0.5
    done
    for n in 1 2 3 4; do
        pw-link "FL64:out_$n" "${OUT}:playback_AUX$((n-1))" 2>/dev/null
        pw-link "${IN}:capture_AUX$((n-1))" "FL64:in_$n" 2>/dev/null
    done
) &
```

Set the interface profile first:

```bash
wpctl set-profile <device-id> <pro-audio-index>
```
