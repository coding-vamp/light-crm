# Security policy

## Supported versions

The current `main` development line is supported on a best-effort basis. No published release has been established by this implementation. Once releases exist, maintainers should document the supported release range here; older snapshots are not guaranteed security fixes.

## Private vulnerability reports

The intended route is **GitHub private vulnerability reporting**: the repository's Security tab → Report a vulnerability. Enabling that feature is a required publication step for the repository owner. No security email address or other private contact has been established here.

If private reporting is not yet enabled, request that it be enabled without posting exploit details, client information, database files, attachments, or credentials in a public issue. Do not assume a private report can be submitted until the repository advertises the facility.

A useful private report includes the affected commit/version, OS/Xcode version, minimal reproduction using fictional data, impact, and any proposed fix. Do not send real CRM backups.

## Storage and trust boundaries

The app has no login, backend, analytics, or cloud sync, and requests no network-client entitlement. User-selected websites/email links open external applications. Document imports copy regular files into application-managed storage; original files are not modified. Opening a document invokes its default application and should only be done for files you trust.

Data and backups are **not encrypted by the app**. Local-only storage does not prevent access by an account or process with permission to read those files. macOS account security, FileVault, and backup-destination protections are independent safeguards.

Restore validates the format, metadata, relationships, paths, files, and checksums before a safety export and staged database replacement. Paths cannot traverse outside the managed directory, and symlinks/aliases are rejected. SHA-256 checksums detect accidental corruption; they do not authenticate a maliciously modified backup. Import backups from trusted sources only. Do not concurrently modify a package while it is being imported.

App sandbox settings and user-selected file access remain enabled. Unsigned development builds are not signed/notarized release artifacts. No distribution or security audit is implied by a successful local build.
