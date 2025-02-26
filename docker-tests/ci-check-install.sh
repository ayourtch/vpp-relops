#!/bin/sh
set -eux
#
# This file is executed from github actions (aarch64 and x86_64) to check the install on the default packagelist (x86_64) or default-arm (aarch64).
# If you override VPP_PACKAGE_LIST, it will be attempted on both platforms - which is probably not what you want.

PACKAGECLOUD_REPO=fdio/2502 VPP_EXACT_VERSION=25.02-release ./run-docker-test
