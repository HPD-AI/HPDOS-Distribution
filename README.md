# HPDOS Distribution

This public repository distributes compiled HPDOS releases and installer
scripts. The HPDOS source repository is private and is not mirrored here.

Each HPDOS release contains a matching, self-contained TUI and backend for each
supported platform. A system .NET installation is not required.

## Install

### macOS and Linux

```sh
curl -fsSL https://raw.githubusercontent.com/HPD-AI/HPDOS-Distribution/main/install-hpdos.sh | sh
```

### Windows

```powershell
irm https://raw.githubusercontent.com/HPD-AI/HPDOS-Distribution/main/install-hpdos.ps1 | iex
```

The installers:

- select the current platform and architecture;
- download immutable assets from this repository's GitHub Releases;
- verify the published SHA-256 digest;
- install the TUI and its matching backend side by side;
- activate the installed version through a user-scoped `current` pointer.

The HPD OS Desktop installation manager will consume the same release assets.

## Repository contents

- `install-hpdos.sh` and `install-hpdos.ps1`: user-scoped installers.
- `uninstall-hpdos.sh` and `uninstall-hpdos.ps1`: uninstallers.
- `docs/release-contract.md`: public release naming and payload contract.
- `release-signing-public-key.txt`: pinned Ed25519 release verification key.
- GitHub Releases: immutable compiled HPDOS payloads and integrity metadata.

This repository must never contain HPD-OS product source, repository
credentials, signing private keys, or user data.

## Current trust status

The existing beta release contract verifies SHA-256 checksums downloaded from
the same GitHub Release. Signed release manifests remain required before the
Desktop installation manager treats the online feed as a production trust
root. Until then, the Desktop-embedded, fully hashed payload remains its
offline recovery source.

## Supported release assets

```text
hpdos-osx-arm64.tar.gz
hpdos-osx-x64.tar.gz
hpdos-linux-arm64.tar.gz
hpdos-linux-x64.tar.gz
hpdos-win-arm64.zip
hpdos-win-x64.zip
SHA256SUMS
```

Release tags use `hpdos-v<version>`.
