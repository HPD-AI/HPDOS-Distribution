# HPDOS public release contract

## Release identity

- Repository: `HPD-AI/HPDOS-Distribution`
- Tag: `hpdos-v<version>`
- Product: `hpdos`
- Payload: one matching TUI/backend pair

The private HPD-OS build workflow is the only release producer. Publishing
credentials must be scoped to releases in this repository and stored only in
protected CI configuration.

## Assets

Every release carries:

- one archive for each supported runtime identifier;
- `SHA256SUMS`;
- a release manifest and detached signature once signed-feed support opens.

Unix archives are `.tar.gz`; Windows archives are `.zip`.

Each extracted archive contains:

```text
hpdos                    # hpdos.exe on Windows
backend/
└── hpdos-backend        # hpdos-backend.exe on Windows
release.json
```

`release.json` contains the schema version, product, version, RID, TUI path,
and backend path. The TUI and backend are an atomic release unit.

## Immutability

Published version tags and assets are immutable. A failed release must publish
a new version rather than replacing an artifact consumers may have verified.
CI may replace assets only while repairing an unpublished/draft release.

## Channels

Installers currently discover releases by tag or newest `hpdos-v*` release.
Stable and prerelease channel manifests will replace ambiguous “latest”
selection before production automatic updates.

## Signature follow-up

The production online update contract must add:

- a bounded strict manifest;
- Ed25519 or an equivalently reviewed signature scheme;
- an offline release-signing private key or protected signing service;
- public-key pinning in Desktop and installers;
- explicit product, channel, version, RID, archive hash, extracted-file
  manifest hash, and rollback policy;
- key rotation and revocation rules.

Checksums from the same server detect transfer corruption but are not a
substitute for a signed manifest.
