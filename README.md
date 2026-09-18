# Dotfiles

Personal macOS configuration managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

Clone the repository and run `make` to choose the setup phases:

```bash
git clone https://github.com/genkio/dotfiles ~/dotfiles && cd ~/dotfiles && make
```

## Update an existing installation

Run `make update` to keep an already-provisioned machine current. This command runs `scripts/update.sh`.

To preview the changes, use `make update DRY_RUN=1`, which passes `--dry-run` to the script.

## Read warnings and errors

In a terminal, warnings and errors appear in color with the prefixes `SETUP_WARN:` and `SETUP_ERROR:`.

To save the output and find problems later, use:

```sh
make 2>&1 | tee setup.log
grep SETUP_ setup.log        # warnings + errors
grep SETUP_WARN setup.log    # non-fatal only
grep SETUP_ERROR setup.log   # fatal only
```

Warnings and errors go to stderr, so `2>&1` includes them in the log. Output sent through a pipe has no color codes.

To show only warnings and errors as they occur, run `make 2>&1 | grep SETUP_`. This hides normal progress output.
