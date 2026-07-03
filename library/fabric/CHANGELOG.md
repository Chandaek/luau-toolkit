# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-07-03

**STATUS:** $\color{LightGreen}\texttt{Active}$

### Added

- Added `ThreadMaster:RemoveScopeValue` support for removing scope values by key.
- Added `Fabric:RemoveGScopeValue` support ofr removing global scope values by key.

---

## [1.0.2] - 2026-07-03

### Fixed

- Logged `v1.0.2` fix for `ThreadMaster` guard clause updates and changelog entry completion.

---

## [1.0.1] - 2026-07-03

### Fixed

- Fixed `ThreadMaster:GetScopeValue` bug where the method returned a value from the wrong field.
- Corrected `Bind` identifier type handling.
- Changed `DeterminableChoice` to use `IsThread` rather than `Thread`.
- Added a safety railguard for `ThreadMaster` that validates the internal `fabric` field before use.
- Improved internal thread resolution and scope access safety.

---

## [1.0.0] - 2026-07-03

### Added

- Complete Fabric lifecycle support for `ThreadMaster` instances
- Environment variable support per `ThreadMaster`
- Global, public, and private scope APIs for Fabric and thread masters

---

## [0.0.1] - 2026-06-26

**STATUS:** $\color{LightYellow}\texttt{In-Progress}$

### Added

- Initial package structure and implementation scaffold
- Core module foundation for ongoing development
