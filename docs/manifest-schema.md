# ExtGuide installer manifest schema v1

An extension release publishes a versioned JSON manifest and a prebuilt ZIP archive. All URLs must be direct HTTPS asset URLs; ExtGuide does not use the GitHub API.

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

Custom destinations are remembered per Windows user. If a chosen location is protected, ExtGuide may ask the user to approve a scoped Windows UAC prompt. Only the validated archive writer is elevated; downloads, Chrome discovery, and guidance continue without elevation.
