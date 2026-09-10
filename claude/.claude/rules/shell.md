Shell tool is zsh. Two gotchas that cost hours:

- An unquoted `$VAR` is NOT word-split. `H="python3 x.py"; $H run` fails and
  `env $ENVL cmd` passes one argument. Spell commands out; use `$(...)` inline
  or `${=VAR}` when a split is really wanted.
- Never store a command in a variable inside a loop; write the command.
