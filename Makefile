.PHONY: clean env help test validate-cloudformation

# This is a self documenting make file.  ## Comments after the command are the help options.
help:  ## List available commands
	  @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

env:  # Check and set up environment
	  ./scripts/check_system.sh

clean:  ## Clean build
	  rm -f .test

.test: env
	  $(MAKE) validate-cloudformation cf-file=cloudformation/users.yml
	  touch .test

test: .test  ## Run tests

cf-file ?=
validate-cloudformation: env
	  aws cloudformation validate-template --template-body file://./${cf-file}

deploy-users: env .test
	  aws cloudformation deploy \
        --stack-name users \
        --no-fail-on-empty-changeset \
        --capabilities CAPABILITY_NAMED_IAM \
				--template-file cloudformation/users.yml
