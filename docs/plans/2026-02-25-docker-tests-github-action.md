# Unified Docker Tests GitHub Action Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a unified GitHub Actions workflow for running docker tests on both x86_64 and aarch64 architectures with configurable parameters via manual trigger.

**Architecture:** Single GitHub Actions workflow file using matrix strategy to run parallel jobs on different architectures. Workflow dispatch inputs provide configurable parameters with sensible defaults. Environment variables are conditionally exported based on user input to preserve script defaults.

**Tech Stack:** GitHub Actions YAML, Bash scripting, Docker

---

### Task 1: Create the unified docker-tests workflow file

**Files:**
- Create: `.github/workflows/docker-tests.yml`

**Step 1: Create the workflow file with workflow_dispatch trigger and inputs**

Write the complete workflow YAML with all configurable inputs:

```yaml
name: Docker Tests (Unified)

on:
  workflow_dispatch:
    inputs:
      packagecloud_repo:
        description: 'PackageCloud repository'
        required: false
        default: 'fdio/release'
        type: string
      vpp_exact_version:
        description: 'Exact VPP version to install (leave empty for latest)'
        required: false
        default: ''
        type: string
      vpp_check_version:
        description: 'VPP version to check in show outputs'
        required: false
        default: ''
        type: string
      vpp_package_list_x86:
        description: 'Packagelist prefix for x86_64'
        required: false
        default: 'packagelists/default'
        type: string
      vpp_package_list_arm:
        description: 'Packagelist prefix for aarch64'
        required: false
        default: 'packagelists/arm-default'
        type: string

jobs:
  docker-test:
    strategy:
      matrix:
        architecture: [x86_64, aarch64]
        include:
          - architecture: x86_64
            runner: ubuntu-latest
            package_list: ${{ inputs.vpp_package_list_x86 }}
          - architecture: aarch64
            runner: ubuntu-24.04-arm
            package_list: ${{ inputs.vpp_package_list_arm }}
    runs-on: ${{ matrix.runner }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run docker tests
        run: |
          cd docker-tests
          [ -n "${{ inputs.packagecloud_repo }}" ] && export PACKAGECLOUD_REPO="${{ inputs.packagecloud_repo }}"
          [ -n "${{ inputs.vpp_exact_version }}" ] && export VPP_EXACT_VERSION="${{ inputs.vpp_exact_version }}"
          [ -n "${{ inputs.vpp_check_version }}" ] && export VPP_CHECK_VERSION="${{ inputs.vpp_check_version }}"
          export VPP_PACKAGE_LIST="${{ matrix.package_list }}"
          export UNATTENDED=y
          ./run-docker-test
```

**Step 2: Verify the YAML syntax**

Run: `yamllint .github/workflows/docker-tests.yml` (if available) or visually validate the YAML structure.
Expected: No syntax errors, proper indentation.

**Step 3: Commit the workflow file**

```bash
git add .github/workflows/docker-tests.yml
git commit -m "feat: add unified docker-tests workflow with manual trigger

- Supports both x86_64 and aarch64 architectures via matrix strategy
- Configurable parameters: packagecloud_repo, vpp_exact_version, vpp_check_version, packagelists
- Preserves existing test_x86_64.yml and test_aarch64.yml workflows

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Verify the workflow in GitHub Actions

**Files:**
- No file changes (verification task)

**Step 1: Push the workflow to GitHub**

```bash
git push origin master
```

**Step 2: Trigger the workflow manually from GitHub Actions UI**

1. Go to repository in GitHub
2. Click "Actions" tab
3. Select "Docker Tests (Unified)" workflow
4. Click "Run workflow"
5. Use default parameters (no overrides)

**Step 3: Monitor the workflow execution**

- Verify both x86_64 and aarch64 jobs start in parallel
- Verify correct packagelists are used (check job logs)
- Verify jobs complete successfully

**Step 4: Verify architecture-specific packagelist selection**

Check in the job logs that:
- x86_64 job shows: `VPP package list prefix (VPP_PACKAGE_LIST): packagelists/default`
- aarch64 job shows: `VPP package list prefix (VPP_PACKAGE_LIST): packagelists/arm-default`

---

### Task 3: Test parameter overrides

**Files:**
- No file changes (testing task)

**Step 1: Test with custom packagecloud_repo**

1. Go to GitHub Actions → "Docker Tests (Unified)"
2. Click "Run workflow"
3. Set `packagecloud_repo` to `fdio/2502`
4. Run workflow

**Step 2: Verify the parameter is passed correctly**

Check job logs for: `PACKAGECLOUD_REPO: fdio/2502`

**Step 3: Test with version overrides**

1. Run workflow again with:
   - `vpp_exact_version`: `25.02-release`
   - `vpp_check_version`: `25.02-release`

**Step 4: Verify version parameters work**

Check logs show both parameters are exported and used.

**Step 5: Test empty parameters (script defaults)**

1. Run workflow with all inputs at their default (empty) values
2. Verify script uses its own defaults (check log output)

---

### Task 4: Document usage in README

**Files:**
- Modify: `docker-tests/README.md`

**Step 1: Add documentation for the GitHub Action**

Add a new section to the README:

```markdown
## GitHub Actions Workflow

A unified GitHub Actions workflow is available for running docker tests manually with configurable parameters.

### Using the Workflow

1. Go to the **Actions** tab in the GitHub repository
2. Select **Docker Tests (Unified)** workflow
3. Click **Run workflow**
4. Configure optional parameters:
   - **packagecloud_repo**: PackageCloud repository (default: `fdio/release`)
   - **vpp_exact_version**: Exact VPP version to install (empty = latest)
   - **vpp_check_version**: VPP version to check in show outputs
   - **vpp_package_list_x86**: Packagelist prefix for x86_64 (default: `packagelists/default`)
   - **vpp_package_list_arm**: Packagelist prefix for aarch64 (default: `packagelists/arm-default`)
5. Click **Run workflow** to start tests on both architectures in parallel

### Architecture-Specific Defaults

- **x86_64** runs on `ubuntu-latest` with `packagelists/default`
- **aarch64** runs on `ubuntu-24.04-arm` with `packagelists/arm-default`

The existing `test_x86_64.yml` and `test_aarch64.yml` workflows remain unchanged for CI/PR automation.
```

**Step 2: Commit the documentation update**

```bash
git add docker-tests/README.md
git commit -m "docs: add GitHub Actions workflow usage documentation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Final verification and cleanup

**Files:**
- No file changes (verification task)

**Step 1: Verify all workflows coexist**

Check that all three workflows exist and are functional:
- `.github/workflows/test_x86_64.yml` (unchanged)
- `.github/workflows/test_aarch64.yml` (unchanged)
- `.github/workflows/docker-tests.yml` (new)

**Step 2: Test one final run with all parameters set**

Run the unified workflow with:
- `packagecloud_repo`: `fdio/release`
- `vpp_check_version`: `25.02-release`
- Other defaults

**Step 3: Push any final commits**

```bash
git push origin master
```

**Step 4: Verify CI still works on push/PR**

Create a test PR or push to verify existing workflows still trigger correctly.

---

## Implementation Notes

### Key Implementation Details

1. **Conditional variable export**: The `[ -n "..." ] && export` pattern ensures variables are only set when non-empty, preserving the script's default behavior.

2. **Architecture-specific packagelists**: The matrix `include` directive maps architecture to runner and packagelist, ensuring correct defaults.

3. **UNATTENDED mode**: Always set to `y` in CI to prevent the script from waiting for user input.

### Testing Strategy

- Start with default parameters (happy path)
- Test each parameter override individually
- Test with multiple parameters set
- Verify empty values use script defaults
- Confirm both architectures run in parallel

### Rollback Plan

If issues arise:
- Delete `.github/workflows/docker-tests.yml` to remove the new workflow
- Existing `test_x86_64.yml` and `test_aarch64.yml` remain untouched and functional
