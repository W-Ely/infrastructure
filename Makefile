.PHONY: clean dev env help lock test deploy-users validate-cloudformation

script-directory := scripts
cloudformation-directory := cloudformation
script-files := $(shell find $(script-directory) -name '*.py' -not \( -path '*__pycache__*' \))
cloudformation-files := $(shell find $(cloudformation-directory) -name '*.yml')
deploy-role ?= admin

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
	$(MAKE) validate-cloudformation cf-file=users.yml
	$(MAKE) validate-cloudformation cf-file=budgets.yml
	$(MAKE) validate-cloudformation cf-file=persistence.yml
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
	pipenv run python ./scripts/aws_assume_role.py --role $(deploy-role) --mfa \
		aws cloudformation validate-template \
			--no-cli-pager \
			--template-body file://./cloudformation/${cf-file}

deploy-users: .dev .test
	pipenv run python ./scripts/aws_assume_role.py --role $(deploy-role) --mfa \
	 	aws cloudformation deploy \
			--stack-name users \
			--no-fail-on-empty-changeset \
			--capabilities CAPABILITY_NAMED_IAM \
			--template-file cloudformation/users.yml

notification-email ?=
deploy-budgets: .dev .test
	pipenv run python ./scripts/aws_assume_role.py --role $(deploy-role) --mfa \
	 	aws cloudformation deploy \
			--stack-name budgets \
			--no-fail-on-empty-changeset \
			--capabilities CAPABILITY_NAMED_IAM \
			--template-file cloudformation/budgets.yml \
			--parameter-overrides \
				NotificationEmailAddress=$(notification-email)

deploy-persistance: .dev .test
	pipenv run python ./scripts/aws_assume_role.py --role $(deploy-role) --mfa \
	 	aws cloudformation deploy \
			--stack-name persistance \
			--no-fail-on-empty-changeset \
			--capabilities CAPABILITY_NAMED_IAM \
			--template-file cloudformation/persistence.yml
