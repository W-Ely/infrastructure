.PHONY: clean help test
.DEFAULT_GOAL := help
# This is a self documenting make file.  ## Comments after the command are the help options.
help:
	  @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean:  ## Clean build
	  rm -f .test

.test:
	echo "This is a makefile"
	touch .test

test: .test  ## Run tests
