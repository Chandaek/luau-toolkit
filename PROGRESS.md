# Progress Tracker

This file tracks progress for the root repository and each library package under the root.
Use it to keep a consistent overview of STATUS, goals, notes, and next actions for each library.

---

## Root Repository

- NAME: luau-toolkit
- PATH: `.`
- STATUS: $\color{LightYellow}\texttt{In-Progress}$
- FOCUS: repository-level coordination, shared conventions, and root-level documentation
- NOTES:
  - Each library should have a TODO.md file
  - Tracks progress for each library in this repo
  - Use this file when updating or reviewing library package STATUS
- NEXT:
  - Work on In-Progress STATUS library
  - Initialize and Implement Not-Started STATUS libraries

---

## Fabric

- PATH: `library/fabric`
- STATUS: $\color{LightYellow}\texttt{In-Progress}$
- FOCUS: Fabric package implementation and integration
- NOTES:
  - Thread Identification System and Manipulation
  - ThreadMaster lifecycle work is underway
  - All required directories and files created
- NEXT:
  - Add an environment variable for each ThreadMaster
  - Handle garbage collection for the ThreadMaster resolver
  - Complete init.luau implementation
  - Implement source modules
  - Add API documentation to README.md

---

## Manager-Loader

- PATH: `library/manager-loader`
- STATUS: $\color{LightGreen}\texttt{Active}$
- VERSION: `1.0.0`
- FOCUS: Manager bootstrap, dependency resolution, and lifecycle management
- NOTES:
  - Stable, maintained, and recommended for use
  - Automatically discovers, sorts, loads, and registers Manager modules
  - Provides lifecycle notifications through `OnManagerLoaded`
  - Synchronous bootstrap process
- NEXT:
  - Implement and document `test-1.luau`
  - Expand test coverage for dependency ordering and manager validation

---

## Packet-Stream

- PATH: `library/packet-stream`
- STATUS: $\color{DarkOrange}\texttt{Deprecated}$
- FOCUS: Packet streaming, encoding, encryption, and protocol support
- NOTES:
  - No longer maintained or supported
  - Provided as-is for historical reference
- NEXT:
  - No active development
  - Migration guidance in README.md

---

## Scheduler

- PATH: `library/scheduler`
- STATUS: $\color{LightGrey}\texttt{Not-Started}$
- FOCUS: Scheduling utilities and runtime task management
- NOTES:
  - Implementation not yet begun
  - Placeholder structure created
- NEXT:
  - Begin scheduler implementation
  - Design and document API

---

## Secure-Storage

- PATH: `library/secure-storage`
- STATUS: $\color{LightBlue}\texttt{Stand-By}$
- FOCUS: Compacted storage with almost minimal footprint
- NOTES:
  - Implemented with tier-based memory optimization
  - Test coverage exists in `test/test-1.luau`
  - Currently in maintenance mode
- NEXT:
  - Reimplement the whole library

---

## Watch-Guard

- PATH: `library/watch-guard`
- STATUS: $\color{LightGrey}\texttt{Not-Started}$
- FOCUS: Filesystem/watch guard features and safety checks
- NOTES:
  - Implementation not yet begun
  - Placeholder structure created
- NEXT:
  - Begin watch guard implementation
  - Design and document API

---

## NOTES

- Update each section as work progresses.
- Replace placeholder STATUSes with real values.
- Keep the file concise and easy to scan for current library health.
