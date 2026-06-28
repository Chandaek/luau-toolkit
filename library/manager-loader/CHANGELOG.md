# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-06-26

**STATUS:** $\color{LightGreen}\texttt{Active}$

### Added

- `ManagerLoader` class for bootstrapping and managing manager instances
- `Bootstrap()` method to load and initialize manager modules from a root instance
- `GetManager()` method to retrieve loaded managers by name
- `OnManagerLoaded` event signal for manager lifecycle notifications
- Utility modules for connector, module, and manager loading support
