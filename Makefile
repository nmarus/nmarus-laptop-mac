.DEFAULT_GOAL := help
PLAYBOOK := site.yml
TAGS ?=
EXTRA ?=

ifneq ($(TAGS),)
TAG_ARGS := --tags "$(TAGS)"
endif

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Install prerequisites on a fresh machine
	./scripts/bootstrap.sh

.PHONY: install
install: ## Install/refresh pinned Galaxy collections
	ansible-galaxy install -r requirements.yml --force

.PHONY: lint
lint: ## Lint the playbook and roles
	ansible-lint

.PHONY: test
test: ## Run every pre-commit hook against the whole tree
	pre-commit run --all-files

.PHONY: check
check: ## Dry run: show what would change without changing it
	ansible-playbook $(PLAYBOOK) --check --diff $(TAG_ARGS) $(EXTRA)

.PHONY: apply
apply: ## Apply the configuration to this machine
	ansible-playbook $(PLAYBOOK) --diff $(TAG_ARGS) $(EXTRA)

.PHONY: apply-sudo
apply-sudo: ## Apply, prompting for the sudo password
	ansible-playbook $(PLAYBOOK) --diff --ask-become-pass $(TAG_ARGS) $(EXTRA)

.PHONY: update
update: ## Update Homebrew and upgrade everything installed
	brew update
	brew upgrade ansible
	ansible-playbook $(PLAYBOOK) --diff --tags homebrew,mas \
	  -e homebrew_update=true -e homebrew_upgrade_all=true -e mas_upgrade_all=true

.PHONY: facts
facts: ## Dump the gathered facts for this machine
	ansible localhost -m ansible.builtin.setup
