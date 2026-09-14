# ExtGuide installer manifest schema v1

An extension release publishes a versioned JSON manifest and a prebuilt ZIP archive. All URLs must be direct HTTPS asset URLs; ExtGuide does not use the GitHub API.

| Property | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | Yes | Must be `1`. |
| `displayName` | Yes | Name shown to the user. |
| `publisher` | Yes | Safe folder segment beneath Local Application Data. |
| `installFolderName` | Yes | Safe extension-specific folder segment. |
| `archiveUrl` | Yes | Direct HTTPS URL for the prebuilt ZIP. |
| `sha256` | One of | Inline 64-character hexadecimal SHA-256 digest. |
| `sha256Url` | One of | Direct HTTPS URL whose content contains the digest. |
| `extensionRoot` | Yes | Relative path inside the ZIP containing a valid Manifest V3 `manifest.json`. |

Remote configuration cannot choose an absolute destination. A custom base folder is accepted only after the user chooses it in the native folder dialog, and ExtGuide appends `installFolderName`.

Archives containing absolute paths, parent traversal, symbolic links, duplicate targets, corrupt content, or an invalid extension root are rejected before the stable installation is replaced.
