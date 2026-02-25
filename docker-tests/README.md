This is a work-in-progress to automatically test the installability of the VPP
from the various repositories, to be run as part of the release process.

You will need to tweak and run run-docker-test script.
If it prints "ALL TESTS PASSED", this means VPP properly installs
according to your constraints in the tested environments.

You can supply the arguments to it via environment variables:

Select the PackageCloud repository:

PACKAGECLOUD_REPO=fdio/release  - select the repository

Select the method of install/check:

VPP_CHECK_VERSION=19.04-release - install default versions
of packages, check that the version in the running VPP is
this one.

OR:


VPP_EXACT_VERSION=19.01.2-release - install the specified
versions of packages, check that the version of the
running VPP matches.

VPP_PACKAGE_LIST=packagelists/default - the prefix for package
lists per-environment (ubuntu16, ubuntu18, centos)
to be installed. Other options are stable/1904, stable/1901, etc.


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

