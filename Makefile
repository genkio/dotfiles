TARGETS := all bootstrap apps dev stow ssh gpg sublime tailscale

.PHONY: $(TARGETS)

# HOST/EMAIL/NAME are generic enough to collide with exported env vars, which
# make would import silently. Only honour explicit `make ssh VAR=...`.
cli = $(if $(filter command line,$(origin $(1))),$($(1)))

# `make ssh gitlab` -> --host gitlab. make also treats the bare word as a goal,
# so give it a no-op rule.
SSH_HOST := $(call cli,HOST)
ifeq (ssh,$(firstword $(MAKECMDGOALS)))
SSH_EXTRA_GOAL := $(filter-out $(TARGETS),$(word 2,$(MAKECMDGOALS)))
ifneq ($(SSH_EXTRA_GOAL),)
SSH_HOST := $(SSH_EXTRA_GOAL)
.PHONY: $(SSH_EXTRA_GOAL)
$(SSH_EXTRA_GOAL):
	@:
endif
endif

all:
	./scripts/opinionated-flow.sh --bootstrap-macos --include-all

bootstrap:
	./scripts/opinionated-flow.sh --bootstrap-macos

apps:
	./scripts/opinionated-flow.sh --include-apps

dev:
	./scripts/opinionated-flow.sh --include-dev

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
