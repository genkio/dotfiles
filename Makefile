TARGETS := menu all bootstrap macos core apps dev touchid update stow ssh gpg sublime tailscale

FLOW := ./scripts/opinionated-flow.sh

.PHONY: $(TARGETS)

.DEFAULT_GOAL := menu

cli = $(if $(filter command line,$(origin $(1))),$($(1)))

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

menu:
	@./scripts/pick-phases.sh $(NAME_ARG)

all:
	$(FLOW) --phase macos --phase core --phase apps --phase dev --phase touchid $(NAME_ARG)

macos:
	$(FLOW) --phase macos $(NAME_ARG)

core:
	$(FLOW) --phase core

apps:
	$(FLOW) --phase apps

dev:
	$(FLOW) --phase dev

touchid:
	$(FLOW) --phase touchid

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

tailscale:
	./scripts/tailscale-up.sh

sublime:
	./scripts/setup-sublime.sh
