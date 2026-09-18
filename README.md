# Dotfiles

macOS only. Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Opinionated flow

Clone the repo yourself, then run the phase you want. The script operates on its
own checkout and never clones:

```bash
git clone https://github.com/genkio/dotfiles ~/dotfiles && cd ~/dotfiles && make
```

## Routine maintenance

`make update` (`scripts/update.sh`, `--dry-run` via `make update DRY_RUN=1`) keeps an already-provisioned machine current.

### Spotting warnings and errors

Run in the foreground and `SETUP_WARN:` / `SETUP_ERROR:` lines are colored automatically, so no piping is needed to see them go by.

To keep a copy for later, tee to a log (color is dropped when output is not a terminal, so the file stays clean), then grep by prefix:

```sh
make 2>&1 | tee setup.log
grep SETUP_ setup.log        # warnings + errors
grep SETUP_WARN setup.log    # non-fatal only
grep SETUP_ERROR setup.log   # fatal only
```

Warnings and errors go to stderr, hence the `2>&1`. To watch only the problems scroll by live (hides normal progress), pipe straight to grep: `make 2>&1 | grep SETUP_`.
