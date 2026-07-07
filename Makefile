.PHONY: all bootstrap apps dev stow ssh gpg sublime

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
	./scripts/generate-ssh-key.sh

gpg:
	./scripts/generate-gpg-key.sh

sublime:
	./scripts/setup-sublime.sh
