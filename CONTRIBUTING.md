# Contributing

Thanks for helping FL Studio run better on Linux!

## Most useful right now

- **Test reports** from distributions and GPUs other than Arch + NVIDIA: open a ["Test report" issue](https://github.com/Sethtekk/fl-studio-wine-linux/issues/new/choose) with the output of `bash scripts/doctor.sh`. Good and bad results both help.
- **Plugin reports:** which plugins work, which freeze or crash (add them to [docs/plugins.md](docs/plugins.md)).
- **Translations** of the German documents in `docs/`.

## Bug reports

Please include the output of `bash scripts/doctor.sh` and, if FL misbehaves, the terminal output of `flstudio-wine`. For freezes: does the audio keep playing? Does it happen with one specific plugin?

## Pull requests

- Scripts are bash, run as the normal user, use `scripts/lib/common.sh` for output (`step`, `ok`, `warn`, `die`) and `as_root` for anything that needs root.
- Every script must stay safe to run twice.
- Never overwrite user files without a backup; never delete a Wine prefix without asking.
- `shellcheck -x -S warning install.sh uninstall.sh scripts/*.sh scripts/lib/common.sh` must pass (CI checks it).
- New distributions: add a branch to `scripts/01-install-wine.sh` and a section to `docs/installation.md`, and say how you tested it.
- Changes to the Wine patches: describe the root cause and how you verified the fix, like the existing documents in `patches/`.
