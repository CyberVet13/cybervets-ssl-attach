# Changelog

All notable changes to this project will be documented in this file.

## [1.0.2] - 2026-02-25

### Added

- **release-create.ps1** – `-Version` parameter to create releases for any version; resolves notes from `RELEASE_NOTES_${tag}.md` or CHANGELOG section

## [1.0.1] - 2026-02-24

### Fixed

- **Release workflow** – Dynamic release notes from `RELEASE_NOTES_${TAG}.md` or CHANGELOG section; no longer hardcoded to v1.0.0
- **Validate workflow** – Include `release-create.ps1` in CI syntax validation
- **Pester tests** – Fix single-parse-error detection (`@($errs).Count` instead of `$errs.Count`)
- **release-create.ps1** – Guard against null `Response` in exception handler (network errors, timeouts)

## [1.0.0] - 2026-02-23

### Added

- **CyberVets-SSL-Attach.ps1** – Main script for attaching ACM certificates to CloudFront or ALB
  - Interactive and parameter-driven modes
  - Pre-flight checks (AWS CLI, credentials)
  - ACM certificate discovery with exact/wildcard matching, newest-by-expiry selection
  - Optional `-CertificateArn` to skip discovery
  - CloudFront: SNI-only, TLSv1.2_2021, redirect-to-https on all behaviors
  - CloudFront: Merge root + www into existing aliases (preserves other aliases)
  - ALB: Certificate attachment, AAAA records for dual-stack
  - Route 53: A/AAAA ALIAS records for root and www
  - `-WhatIf` dry-run support
  - `-Verbose` for troubleshooting
- **push-to-github.ps1** – Helper for pushing with Personal Access Token
  - Credential helper (no token in command line)
  - Push to `main` branch
- **GitHub Actions** – PowerShell syntax validation on push/PR
- **Pester tests** – Script load, parameters, CloudFront alias merge logic
- **README** – Usage, parameters, examples, testing
- **LICENSE** – MIT

### Changed

- **Merge-CloudFrontAliases** – Cross-platform implementation (hashtable dedup) for consistent behavior on Windows and Linux

### Security

- Credential helper for PAT (avoids token in process args/history)
- CloudFront alias merge (no longer overwrites existing aliases)
