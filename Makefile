AGENTBOX := ./bin/agentbox
BOX ?=

.PHONY: up down shell-personal shell-work verify lint leaks

up:
	$(AGENTBOX) up $(BOX)

down:
	$(AGENTBOX) down $(BOX)

shell-personal:
	$(AGENTBOX) shell personal

shell-work:
	$(AGENTBOX) shell work

verify:
	$(AGENTBOX) verify personal
	$(AGENTBOX) verify work

lint:
	bash ./scripts/lint.sh

leaks:
	./scripts/check-leaks.sh
