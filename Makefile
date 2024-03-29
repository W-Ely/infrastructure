.PHONY: clean dev env help lock test deploy-users validate-cloudformation

script-directory := scripts
cloudformation-directory := cloudformation
script-files := $(shell find $(script-directory) -name '*.py' -not \( -path '*__pycache__*' \))
cloudformation-files := $(shell find $(cloudformation-directory) -name '*.yml')
deploy-role ?= admin
assume-role := pipenv run python ./scripts/aws_assume_role.py --role $(deploy-role) --mfa

# This is a self documenting make file.  ## Comments after the command are the help
# options.
help:  ## List available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean:  ## Clean build
	rm -f .test
	rm -f .env
	rm -f .dev

.env: ./scripts/check_system.sh
	./scripts/check_system.sh
	which pipenv || pip3 install pipenv
	touch .env

.lock: .env Pipfile
	pipenv lock -v --clear
	@touch .lock

.dev: .lock Makefile
	pipenv sync --dev
	@touch .dev

.test: .env $(cloudformation-files)
	$(MAKE) validate-cloudformation cf-file=domain-names.yaml
	$(MAKE) validate-cloudformation cf-file=templates/zone-private.yaml
	$(MAKE) validate-cloudformation cf-file=templates/zone-public.yaml
	$(MAKE) validate-cloudformation cf-file=templates/vpc-2azs.yaml
	$(MAKE) validate-cloudformation cf-file=templates/vpc-endpoint-s3.yaml
	$(MAKE) validate-cloudformation cf-file=boundaries.yml
	$(MAKE) validate-cloudformation cf-file=service-linked-roles.yml
	$(MAKE) validate-cloudformation cf-file=users.yml
	$(MAKE) validate-cloudformation cf-file=budgets.yml
	$(MAKE) validate-cloudformation cf-file=persistence.yml
	$(MAKE) validate-cloudformation cf-file=roles.yml
	touch .test

.lint: .dev
	echo "black:"
	pipenv run black --safe -v $(script-files)
	echo "pylint:"
	pipenv run pylint $(script-files)
	echo "pycodestyle:"
	pipenv run pycodestyle $(script-files) \
	    --ignore=E203,E402,E711,E712,W503,W405,E231,E501 \
	    --max-line-length=88
	@touch .lint

env: .env ## Check and set up environment

dev: .dev ## Install dependencies (useful for dev editor linting, not used for run/test/etc)

lock: .lock  ## Relock python depends

test: .test  ## Run tests

lint: .lint ## Run lint

cf-file ?=
validate-cloudformation: .dev
	$(assume-role) aws cloudformation validate-template \
			--no-cli-pager \
			--template-body file://./cloudformation/${cf-file}

.PHONY: deploy-boundaries
deploy-boundaries: .dev .test
	$(assume-role) aws cloudformation deploy \
		--stack-name boundaries \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/boundaries.yml

.PHONY: deploy-roles
deploy-roles: .dev .test
	$(assume-role) aws cloudformation deploy \
		--stack-name roles \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/roles.yml

.PHONY: deploy-users
deploy-users: .dev .test
	$(assume-role) aws cloudformation deploy \
		--stack-name users \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/users.yml

notification-email ?=
.PHONY: deploy-budgets
deploy-budgets: .dev .test
	$(assume-role) aws cloudformation deploy \
		--stack-name budgets \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/budgets.yml \
		--parameter-overrides \
			NotificationEmailAddress=$(notification-email)

# This domain was first registered with Route53, then the auto created zones were removed
# After creating Cloudformation deployed zones
domain-name := enigmatic.link
.PHONY: deploy-network
deploy-network: .dev .test
	# After registering a domain in Route53, one needs to delete the HostedZone and
	# recreate here with Cloudformation, the name servers in the registered
	# domain name then need to be fixed ;-/
	$(assume-role) aws cloudformation deploy \
		--stack-name vpc-2azs \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/templates/vpc-2azs.yaml
	$(assume-role) aws cloudformation deploy \
		--stack-name vpc-endpoint-s3 \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/templates/vpc-endpoint-s3.yaml \
		--parameter-overrides \
			ParentVPCStack=vpc-2azs
	$(assume-role) aws cloudformation deploy \
		--stack-name zone-public \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/templates/zone-public.yaml \
		--parameter-overrides \
			Name=$(domain-name)
	# Not yet in use
	# $(assume-role) aws cloudformation deploy \
	# 	--stack-name zone-private \
	# 	--no-fail-on-empty-changeset \
	# 	--capabilities CAPABILITY_NAMED_IAM \
	# 	--template-file cloudformation/templates/zone-private.yaml \
	# 	--parameter-overrides \
	# 		ParentVPCStack=vpc-2azs \
	# 		Name=int.$(domain-name)
	$(assume-role) aws cloudformation deploy \
		--stack-name domain-names \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/domain-names.yaml \
		--parameter-overrides \
			DomainName=$(domain-name)

.PHONY: deploy-persistance
deploy-persistance: .dev .test
	$(assume-role) aws cloudformation deploy \
		--stack-name persistance \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/persistence.yml

.PHONY: deploy-service-linked-roles
deploy-service-linked-roles: .dev .test
	$(assume-role) aws cloudformation deploy \
		--stack-name service-linked-roles \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file cloudformation/service-linked-roles.yml
