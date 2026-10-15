# rFabric Linux packages

apt and dnf repository for the rFabric CLI (`rfabric`), robot agent (`rfabric-agent`) and remote (`rfabric-remote`), served at <https://linux.rfabric.io> by GitHub Pages.

## Install

The installers add this repository and install the package:

```bash
curl -fsSL https://get.rfabric.io/cli.sh | sh      # CLI
curl -fsSL https://get.rfabric.io/agent.sh | sh    # robot agent
```

- Release candidates: `curl -fsSL https://get.rfabric.io/cli.sh | RFABRIC_CHANNEL=rc sh`.
- Upgrades: `sudo apt-get upgrade` / `sudo dnf upgrade`.
- `rfabric-remote`: `sudo apt-get install rfabric-remote` / `sudo dnf install rfabric-remote` once an installer has added the repository.
- Signing key: <https://linux.rfabric.io/rfabric.asc>.

## How it is published

The repository is built, never edited by hand:

1. A release of `rfabric/cli` or `rfabric/agent` attaches its `.deb` and `.rpm` packages to the GitHub Release, then its `linux` job sends `repository_dispatch` `release-published` here.
2. `.github/workflows/publish.yml` runs `build.sh`: it downloads the packages of the newest 3 stable and 2 release-candidate releases of each repo, writes the apt suites `stable` and `rc` and the dnf repositories `rpm/stable` and `rpm/rc`, and signs them with the `PACKAGE_SIGNING_KEY` secret.
3. The site deploys to GitHub Pages. A deleted GitHub Release leaves the repository at the next run; `gh workflow run publish.yml --repo rfabric/linux` rebuilds on demand.
