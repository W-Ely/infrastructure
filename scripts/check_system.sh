#!/bin/bash
# This script checks for the tools needed for this repo.

if ! command -v aws &> /dev/null
then
    echo "'aws' could not be found: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit
fi