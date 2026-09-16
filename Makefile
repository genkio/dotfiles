TARGETS := menu all bootstrap macos core apps dev touchid update stow ssh gpg sublime tailscale

FLOW := ./scripts/opinionated-flow.sh

.PHONY: $(TARGETS)

# A bare `make` used to mean `all`, which is the one choice nobody makes twice.
# It opens the phase picker instead; Enter with nothing touched still runs all
# six, so the old reflex lands in the same place.
.DEFAULT_GOAL := menu

# HOST/EMAIL/NAME are generic enough to collide with exported env vars, which
# make would import silently. Only honour explicit `make ssh VAR=...`.
cli = $(if $(filter command line,$(origin $(1))),$($(1)))

# `make ssh gitlab` -> --host gitlab, `make macos neo` -> --name neo. make also
# treats the bare word as a goal, so give it a no-op rule. Only these targets
# take one, so a stray word after any other target still fails as a typo.
ARG_TARGETS := ssh macos all bootstrap menu
ifneq (,$(filter $(firstword $(MAKECMDGOALS)),$(ARG_TARGETS)))
EXTRA_GOAL := $(filter-out $(TARGETS),$(word 2,$(MAKECMDGOALS)))
ifneq ($(EXTRA_GOAL),)
.PHONY: $(EXTRA_GOAL)
$(EXTRA_GOAL):
	@:
endif
endif

SSH_HOST := $(call cli,HOST)
ifeq (ssh,$(firstword $(MAKECMDGOALS)))
SSH_HOST := $(if $(EXTRA_GOAL),$(EXTRA_GOAL),$(SSH_HOST))
else
MACOS_NAME := $(if $(EXTRA_GOAL),$(EXTRA_GOAL),$(call cli,NAME))
endif
NAME_ARG := $(if $(MACOS_NAME),--name '$(MACOS_NAME)')

# Checkbox list of the phases, then one run with whatever is ticked. @ because
# the recipe line is noise above an interactive menu. Falls back to printing the
# target names when there is no terminal to prompt on.
menu:
	@./scripts/pick-phases.sh $(NAME_ARG)

# One process, so the password is asked for once. Phase order is fixed inside
# the script: touchid has to follow the last sudo of the whole run.
all:
	$(FLOW) --phase macos --phase core --phase apps --phase dev --phase touchid $(NAME_ARG)

# Run this one first on a new machine: it turns off the macOS auto-update that
# would otherwise eat the uplink, enables Remote Login, and prints the local IP
# so the slower phases can be driven over ssh. `make macos neo` also renames the
# machine, which is worth doing here because the .local address it prints at the
# end is derived from that name.
macos:
	$(FLOW) --phase macos $(NAME_ARG)

# Brewfile.base, the stowed core packages, TPM plugins and the git seed.
core:
	$(FLOW) --phase core

# GUI casks, hammerspoon, aerospace, sketchybar, and Sublime's headless
# Package Control setup. Wants `macos` to have run: the tiling gaps assume the
# menu bar is auto-hidden, which that phase does.
apps:
	$(FLOW) --phase apps

# The long one: Brewfile.dev, mise toolchains and the coding agents.
dev:
	$(FLOW) --phase dev

# Separate target because pam_tid makes sudo want a fingerprint, which no
# scripted sudo can answer - so it has to follow every other phase.
touchid:
	$(FLOW) --phase touchid

# A usable machine, minus the GUI apps and the dev toolchain. No tailscale:
# `make tailscale` owns that, daemon and all.
bootstrap:
	$(FLOW) --phase macos --phase core --phase touchid $(NAME_ARG)

update:
	./scripts/update.sh $(if $(call cli,DRY_RUN),--dry-run)

stow:
	./scripts/restow.sh

ssh:
	./scripts/generate-ssh-key.sh \
		$(if $(SSH_HOST),--host $(SSH_HOST)) \
		$(if $(call cli,EMAIL),--email '$(call cli,EMAIL)') \
		$(if $(call cli,NAME),--name '$(call cli,NAME)')

gpg:
	./scripts/generate-gpg-key.sh

# Installs the formula, starts the root daemon and logs in. Out of `make all`
# on purpose: the login needs a browser, and nothing should put a machine on the
# tailnet without being asked.
tailscale:
	./scripts/tailscale-up.sh

sublime:
	./scripts/setup-sublime.sh
