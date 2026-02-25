# Unified Docker Tests GitHub Action Design

**Date:** 2026-02-25

## Overview

Create a new unified GitHub Actions workflow for running docker tests on both x86_64 and aarch64 architectures with configurable parameters, while keeping the existing workflows unchanged for backward compatibility.

## File Organization

- **New:** `.github/workflows/docker-tests.yml` - Unified workflow with manual trigger and configurable parameters
- **Keep:** `.github/workflows/test_x86_64.yml` - Existing x86_64 CI (unchanged)
- **Keep:** `.github/workflows/test_aarch64.yml` - Existing aarch64 CI (unchanged)

## Workflow Trigger

Uses `workflow_dispatch` with the following configurable inputs:

| Input | Description | Default |
|-------|-------------|---------|
| `packagecloud_repo` | PackageCloud repository | `fdio/release` |
| `vpp_exact_version` | Exact VPP version to install (empty = latest) | `''` |
| `vpp_check_version` | VPP version to check in show outputs | `''` |
| `vpp_package_list_x86` | Packagelist prefix for x86_64 | `packagelists/default` |
| `vpp_package_list_arm` | Packagelist prefix for aarch64 | `packagelists/arm-default` |

## Matrix Strategy

Two parallel jobs:
- **x86_64**: runs on `ubuntu-latest`, uses `vpp_package_list_x86`
- **aarch64**: runs on `ubuntu-24.04-arm`, uses `vpp_package_list_arm`

## Job Steps

1. Checkout code with `actions/checkout@v4`
2. Set environment variables conditionally (only if non-empty inputs provided)
3. Run `docker-tests/run-docker-test` script with:
   - Conditional exports for `PACKAGECLOUD_REPO`, `VPP_EXACT_VERSION`, `VPP_CHECK_VERSION`
   - Architecture-specific `VPP_PACKAGE_LIST` (always set)
   - `UNATTENDED=y` (always set for CI)

## Parameter Handling

Variables are only exported if the user provides a non-empty value:

```bash
[ -n "${{ inputs.packagecloud_repo }}" ] && export PACKAGECLOUD_REPO="${{ inputs.packagecloud_repo }}"
```

This preserves the script's default behavior when no override is provided.

## Error Handling

Relies on GitHub Actions' native error handling:
- Non-zero exit codes from `run-docker-test` mark jobs as failed
- `set -eux` in script ensures immediate failure on any error
- Clear status per architecture in GitHub Actions UI

## Benefits

- Single entry point for manual testing with flexible parameters
- No disruption to existing CI/PR workflows
- Easy to extend with additional architectures in the future
- Clean separation of concerns (old workflows for automation, new for manual testing)
