TF      := terraform -chdir=terraform
SSH_KEY ?= $(HOME)/.ssh/dktest_ed25519

.PHONY: help keygen init plan apply configure verify up destroy ssh fmt lint

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

keygen: ## Create a dedicated SSH key for the nodes (if missing)
	@test -f $(SSH_KEY) || ssh-keygen -t ed25519 -N '' -C dktest -f $(SSH_KEY)

init: ## terraform init + Ansible collections
	$(TF) init
	cd ansible && ansible-galaxy collection install -r requirements.yml

plan: ## terraform plan
	$(TF) plan

apply: keygen ## Provision AWS infrastructure
	$(TF) apply

configure: ## Install and secure Elasticsearch with Ansible
	cd ansible && ansible-playbook playbooks/site.yml

verify: ## Prove the cluster works and is secure
	./scripts/verify.sh

up: init apply configure verify ## Everything, end to end

destroy: ## Tear everything down (stop free-tier usage)
	$(TF) destroy

ssh: ## SSH to node N (default 1): make ssh N=2
	ssh -i $(SSH_KEY) ubuntu@$$($(TF) output -json nodes | jq -r '.[$(or $(N),1)-1].public_ip')

fmt: ## Format code
	$(TF) fmt -recursive

lint: ## Static checks
	$(TF) validate
	cd ansible && ansible-playbook playbooks/site.yml --syntax-check
	shellcheck scripts/*.sh || true
