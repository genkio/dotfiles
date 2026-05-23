.PHONY: all bootstrap apps dev ssh gpg

all:
	./scripts/opinionated-flow.sh --bootstrap-macos --include-all

bootstrap:
	./scripts/opinionated-flow.sh --bootstrap-macos

apps:
	./scripts/opinionated-flow.sh --include-apps

dev:
	./scripts/opinionated-flow.sh --include-dev

ssh:
	./scripts/generate-ssh-key.sh

gpg:
	./scripts/generate-gpg-key.sh
