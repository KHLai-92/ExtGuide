# ExtGuide installer manifest schema v1

An extension release publishes a versioned JSON manifest and a prebuilt ZIP archive. All URLs must be direct HTTPS asset URLs. The public `-ManifestUri` mode downloads these directly. The `-GitHubRepository OWNER/REPOSITORY` mode uses the signed-in GitHub CLI account and GitHub release asset API; the manifest, ZIP, and optional digest must belong to that same repository.

ExtGuide 1.3 adds a release dropdown for `-GitHubRepository` and public GitHub `releases/latest/download/installer-manifest.json` URLs. Published stable releases and pre-releases/betas are eligible if they contain an uploaded `installer-manifest.json` asset. Drafts and releases without this asset are omitted. Each selected manifest must reference assets from that same release. The installer pins `latest` aliases to the selected tag and rejects explicit URLs pointing to another release. Use tag-specific asset URLs when publishing manifests. A tag-specific `-ManifestUri` continues to bypass the dropdown; alternatively pass `-ReleaseTag` with `-GitHubRepository` or a public latest manifest URL.

For example, attach a manifest like the following to a published beta. Replace the repository, ZIP filename, checksum filename, and extension metadata with your own values. The Chrome extension version must be numeric; the beta identity comes from the selected release tag and ZIP, so do not use `1.1.0-beta.1` as `extensionVersion`.

```json
{
  "schemaVersion": 1,
  "displayName": "Sample Extension",
  "extensionVersion": "1.1.0",
  "publisher": "Example",
  "installFolderName": "SampleExtension",
  "archiveUrl": "https://github.com/YOUR-ORG/YOUR-EXTENSION/releases/download/v1.1.0-beta.1/extension-beta.zip",
  "sha256Url": "https://github.com/YOUR-ORG/YOUR-EXTENSION/releases/download/v1.1.0-beta.1/extension-beta.zip.sha256",
  "extensionRoot": "."
}
```

Keep `publisher`, `installFolderName`, `extensionRoot`, and any `integrationId` consistent with the existing integration so switching versions uses the existing location and receipt. Regenerate the digest if the ZIP changes. Future beta releases should publish their own manifest together with their ZIP and checksum.

| Property | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | Yes | Must be `1`. |
| `displayName` | Yes | Name shown to the user. |
| `integrationId` | No | Stable publisher-controlled identifier used to recognize updates even if display metadata changes. Recommended for new integrations. |
| `extensionVersion` | No | Version expected inside the archive's Chrome `manifest.json`. When present, ExtGuide rejects a mismatch. |
| `publisher` | Yes | Safe folder segment beneath Local Application Data. |
| `installFolderName` | Yes | Safe extension-specific folder segment. |
| `archiveUrl` | Yes | Direct HTTPS URL for the prebuilt ZIP. |
| `sha256` | One of | Inline 64-character hexadecimal SHA-256 digest. |
| `sha256Url` | One of | Direct HTTPS URL whose content contains the digest. |
| `extensionRoot` | Yes | Relative path inside the ZIP containing a valid Manifest V3 `manifest.json`. |

Remote configuration cannot choose an absolute destination. A custom base folder is accepted only after the user chooses it in the native folder dialog, and ExtGuide appends `installFolderName`.

Archives containing absolute paths, parent traversal, symbolic links, duplicate targets, corrupt content, or an invalid extension root are rejected before the stable installation is replaced.

After a successful installation, ExtGuide writes `.extguide-install.json` beside the extension root. The receipt binds the destination to `integrationId` (or the legacy `publisher|installFolderName` fallback), records the installed version and archive digest, and prevents a later run from replacing a different ExtGuide installation.

If the remembered destination still exists but its installed files were removed, ExtGuide treats an empty folder as a fresh installation and treats a matching receipt as a repairable installation. A non-empty folder without a matching receipt or extension manifest is never replaced automatically.

Custom destinations are remembered per Windows user. If a chosen location is protected, ExtGuide may ask the user to approve a scoped Windows UAC prompt. Only the validated archive writer is elevated; downloads, Chrome discovery, and guidance continue without elevation.
