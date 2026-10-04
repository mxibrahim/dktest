TF      := terraform -chdir=terraform
SSH_KEY ?= $(HOME)/.ssh/dktest_ed25519

.PHONY: help keygen init plan apply configure verify up destroy ssh tunnel untunnel fmt lint

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

keygen: ## Create a dedicated SSH key for the nodes (if missing)
	@test -f $(SSH_KEY) || ssh-keygen -t ed25519 -N '' -C dktest -f $(SSH_KEY)

init: ## terraform init + Ansible collections (+ check SSM plugin)
	@command -v session-manager-plugin >/dev/null || { echo "Install the AWS Session Manager plugin: brew install --cask session-manager-plugin"; exit 1; }
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

ssh: ## Shell on node N via SSM, no SSH/port needed: make ssh N=2
	aws ssm start-session --region $$($(TF) output -raw region) \
	  --target $$($(TF) output -json nodes | jq -r '.[$(or $(N),1)-1].instance_id')

tunnel: ## SOCKS5 proxy into the VPC on 127.0.0.1:1080 (curl -x socks5h://127.0.0.1:1080 ...)
	./scripts/tunnel.sh start

untunnel: ## Close the SOCKS5 proxy
	./scripts/tunnel.sh stop

fmt: ## Format code
	$(TF) fmt -recursive

lint: ## Static checks
	$(TF) validate
	cd ansible && ansible-playbook playbooks/site.yml --syntax-check
	shellcheck scripts/*.sh || true
