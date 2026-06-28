<div align="center">

# Project Protocol V1

<p>
Repository standards for `luau-toolkit`: naming, organization, package metadata, module structure, style, testing, versioning, and contribution guidance.
</p>

</div>

---

# Overview

This document defines repository-wide conventions and a shared status model for packages in this workspace. Use it to keep package lifecycles, naming, and structure consistent.

---

# STATUS

Each package or major component **must** declare a `STATUS` to communicate its lifecycle and maintenance expectations. Use one of the following canonical values:

| Status | Color | Meaning |
|---|---|---|
| $\color{LightGrey}\texttt{Not-Started}$ | $\color{LightGrey}\texttt{Grey}$ | Work has not begun; no implementation exists. |
| $\color{LightYellow}\texttt{In-Progress}$ | $\color{LightYellow}\texttt{Yellow}$ | Active development is ongoing; API may change. |
| $\color{LightBlue}\texttt{Stand-By}$ | $\color{LightBlue}\texttt{Blue}$ | Implementation exists but no active development; maintenance only. |
| $\color{LightGreen}\texttt{Active}$ | $\color{LightGreen}\texttt{Green}$ | Stable, maintained, and recommended for use. |
| $\color{DarkOrange}\texttt{Deprecated}$ | $\color{DarkOrange}\texttt{Orange}$ | Deprecated — avoid new usage; migration advised. |

## STATUS Indicator Requirement

Every package **must** include a STATUS indicator in its `README.md`:

- Place the `STATUS` value prominently in the top section (after the centered header).
- Use the corresponding color from the table above for visual clarity.
- For $\color{LightGrey}\texttt{Not-Started}$ or $\color{LightYellow}\texttt{In-Progress}$, include a brief note on expected timeline or scope.

## STATUS Templates

Copy and paste the appropriate template into your package `README.md` immediately after the centered header.

### Not-Started

```markdown
---

**STATUS:** $\color{LightGrey}\texttt{Not-Started}$

This package has not yet begun implementation.

**Expected Timeline:** [Add timeline or scope]

---
```

### In-Progress

```markdown
---

**STATUS:** $\color{LightYellow}\texttt{In-Progress}$

This package is under active development. API and implementation may change.

**Current Focus:** [Describe current development focus]

**Expected Stability:** [Add expected date or milestone]

---
```

### Stand-By

```markdown
---

**STATUS:** $\color{LightBlue}\texttt{Stand-By}$

This package is implemented but not actively developed. Maintenance only.

---
```

### Active

```markdown
---

**STATUS:** $\color{LightGreen}\texttt{Active}$

This package is stable, maintained, and recommended for use.

---
```

### Deprecated

```markdown
<div align="center">

# ⚠️ [PackageName] [DEPRECATED]

<p>
<strong>This library is deprecated and will no longer be maintained or supported.</strong>
</p>

<p>
[Brief description of the package.]
</p>

</div>

---

# ⚠️ Deprecation Notice

**[PackageName] is no longer maintained or supported by the author.**

This code is provided as-is for historical and reference purposes only. No updates, or bug fixes will be provided.

If you are currently using this library, please consider:
- Forking the repository to maintain your own version
- Migrating to alternative solutions
- Reviewing the code thoroughly before continued use

**STATUS:** $\color{DarkOrange}\texttt{Deprecated}$

---
```

---

# Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Package / Directories | `kebab-case` | `secure-storage` |
| Luau Filename | `PascalCase` | `PacketStreamer.luau` |
| Module Entry Filename | `init.luau` | `init.luau` |
| Constant Variable | `UPPER_CASE` | `DEFAULT_TIMEOUT` |
| Variable | `PascalCase` | `MyVariable` |
| Private Function | `camelCase` | `setupHandler` |
| Private Method | `_PascalCase` | `_Initialize` |
| Public Method | `PascalCase` | `Process` |
| Private Property | `_camelCase` | `_internalState` |
| Public Property | `PascalCase` | `CurrentStatus` |
| Code Comment | `camelCase` | `-- initializePacket` |
| Section Name | `--- PascalCase ---` | `--- PacketHandling ---` |

---

# Repository Organization

- Root layout: keep lightweight shared modules under `common/`, larger systems under `library/`, and self-contained packages at top-level if needed.

## Required Package Structure

Each package **must** include:

- `init.luau` — Package entry point; should export the main public API.
- `README.md` — Describing package API, usage, `STATUS`, and purpose.
- `source/` — Directory containing all source files and implementation modules.
- `test/` — Directory containing test files and test runners.
- `test-result/` — Directory containing test output and results files.
- `CHANGELOG.md` — Version history and release notes.

### Example Structure

```
package-name/
├── init.luau
├── README.md
├── CHANGELOG.md
├── source/
│   ├── MainModule.luau
│   ├── Helpers/
│   │   └── UtilityModule.luau
│   └── ...
├── test/
│   ├── test-1.luau
│   ├── test-2.luau
│   └── ...
└── test-result/
    ├── test-1-result.txt
    ├── test-2-result.txt
    └── ...
```

---

# Module Structure

- Modules should return a single table (namespace) or constructor function.
- Keep public API surface small and documented in tand Formatting
he package `README.md`.

---

# Style 
- Indentation: tab size 4.
- Line endings: LF.
- No trailing whitespace.
- Use concise, descriptive identifiers with no abbreviations; avoid single-letter names unless in tight scopes.
- Comments: prefer short top-level comments describing module purpose and any non-obvious behaviors.
zz
---

# Code Standards

## Naming

- All identifiers must be concise and contain no abbreviations.
- Use full descriptive names (e.g., `maximumRetries` not `maxRetries`).

## Singleton Pattern

- Public singletons or module implementations must include `Impl` suffix to signify implementation (e.g., `PacketStreamerImpl`).

## Member Organization

Variables and functions within a module are organized by **group**, then alphabetically within each group.

### Ordering Groups (in order):

1. **Action Methods** — Methods that perform actions (alphabetically sorted).
2. **Information Methods** — Getter/query methods, readonly accessors (alphabetically sorted).
3. **Lifecycle Methods** — Constructor, Destroy, and cleanup methods (in that order at the end).

### Module Requiring

Require must use string require in place of instance with exception of certain case (recursive requiring).

### Special Section

*.luau File must have the section --- Main --- as the last section.

### Variable and Function Placement

- Group all module-level variables by category (e.g., constants, state, factories).
- Within each group, sort alphabetically.
- Public functions follow the same grouping: Action → Information → Lifecycle.
- Private functions follow the same pattern and are placed before or alongside their public equivalents.

### Example

```luau
-- Constants
local DEFAULT_TIMEOUT = 5000
local DEFAULT_RETRIES = 3

-- State variables
local _activeConnections = {}
local _internalConfig = {}

-- Action methods (public)
function Module:Connect()
  -- ...
end

function Module:Disconnect()
  -- ...
end

-- Action methods (private)
function Module._handleError()
  -- ...
end

-- Information methods (public)
function Module:GetStatus()
  -- ...
end

function Module:IsConnected()
  -- ...
end

-- Information methods (private)
function Module._queryConnectionState()
  -- ...
end

-- Lifecycle methods
function Module:new()
  -- Constructor
end

function Module:Destroy()
  -- Destructor
end
```

---

# Package Metadata & Versioning

- Use semantic versioning for releases (MAJOR.MINOR.PATCH).
- Document version and `STATUS` prominently in each package `README.md`.

---

# Testing & CI

- Place tests in `test/` inside each package. Tests should be runnable with the chosen test runner or instructions in the package `README.md`.
- Document how to run tests in the root `README.md` if a standard runner is used.

---

# README Standards

Each package `README.md` should follow a consistent structure and format to ensure clarity, discoverability, and maintainability.

## Layout

All package READMEs follow this structure (in order):

1. **Centered Header** (centered div with title and description)
2. **STATUS Section** (with STATUS and version information)
3. **Deprecation Notice** (if `STATUS: Deprecated`)
4. **Overview** (architecture, use case, tier/layer tables)
5. **How It Works** (high-level explanation of behavior and flow)
6. **Structure** (file hierarchy, optional for simple packages)
7. **API Documentation** (Constructor, Properties, Methods sections)
8. **Examples** (code usage examples)
9. **Testing** (instructions to run tests)
10. **Dependencies** (external dependencies or sibling packages)
11. **Known Limitations** (optional: edge cases, performance notes)

### Centered Header

```markdown
<div align="center">

# MyLibrary

<p>
Short, single-sentence description of the library.
</p>

</div>
```

### STATUS Section

Every package `README.md` **must** include a STATUS section immediately after the centered header. Use the pre-made templates from the [STATUS Templates](#status-templates) section above — copy and paste the appropriate template and fill in any bracketed placeholders.

- Place the STATUS section before the `# Overview` section.
- For `Deprecated` packages, use the special centered header template that includes the warning emoji and `[DEPRECATED]` suffix.
- For other statuses, use the standard template with clear status messaging.

### Versioning Section

Every package `README.md` **must** include version information in the STATUS section:

- **Current Version**: Display the current semantic version (MAJOR.MINOR.PATCH) from `CHANGELOG.md`.
- **If version does not exist yet**: Use placeholder `0.0.1` and note that versioning will begin when the first stable release is ready.
- Include the version in the format: `**VERSION:** 0.0.1`
- For `In-Progress` packages, note that the API is unstable and subject to change.

#### Example

```markdown
---

**STATUS:** $\color{LightYellow}\texttt{In-Progress}$

**VERSION:** 0.0.1 (Pre-release)

This package is under active development. API and implementation may change.

**Expected Stability:** [Add expected date or milestone]

---
```

For released packages:

```markdown
---

**STATUS:** $\color{LightGreen}\texttt{Active}$

**VERSION:** 1.2.3

This package is stable, maintained, and recommended for use.

See [CHANGELOG.md](CHANGELOG.md) for release history.

---
```

### Overview Section

Use tables to explain architecture, tiers, or components:

```markdown
# Overview

MyLibrary operates with three layers:

| Layer | Description |
|---|---|
| **ServiceA** | Global singleton managing X. |
| **ServiceB** | Independent instance from `.new()`. |
| **Codec** | Binary encoder/decoder. |
```

### How It Works Section

Explain core behavior and lifecycle:

```markdown
# How It Works

**Dispatch** happens on every frame, subject to rate limits.

**Encoding** uses typed binary buffers.

**Persistence** uses Roblox attributes.
```

### Structure Section

Show file hierarchy for complex packages:

```markdown
# Structure

MyLibrary (ModuleScript)
├── CodecModule     (ModuleScript)
├── EncryptionModule (ModuleScript)
└── Helpers         (ModuleScript)

Sibling dependencies:

Common/
└── EventEmitter
```

### API Documentation

Document public interface with method signatures and parameter tables:

```markdown
# Constructor

## `MyLibrary.new(name: string, config: Configuration?): MyLibrary`

Creates a new instance.

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `name` | `string` | Unique name. |
| `config` | `Configuration?` | Optional settings. |

### Returns

| Type | Description |
|---|---|
| `MyLibrary` | A new instance. |

---

# Properties

## `Status: string`

Current status of the instance. Read-only after construction.

---

# Methods

## `:Update(value: any): ()`

Updates internal state.

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `value` | `any` | New value. |
```

### Code Examples

Provide concrete, runnable examples:

```markdown
# Examples

## Basic Usage

```lua
local MyLib = require(path.to.MyLibrary)
local instance = MyLib.new("MyInstance")

instance:Update(42)
print(instance:GetValue()) -- 42
```
```

### Testing Section

Reference test directory and running instructions:

```markdown
# Testing

Tests are located in `test/`. Run tests with:

```bash
luau test/example.luau
```
```

### Dependencies Section

List required or sibling modules:

```markdown
# Dependencies

- `common/EventEmitter` — Event emitting utilities
- (Optional) `Roblox networking APIs` if used in Roblox context
```

### Known Limitations (Optional)

Document constraints or edge cases:

```markdown
# Known Limitations

- Buffers are not supported on Luau <0.5xx.
- Serialization of userdata is not implemented.
- Maximum nesting depth is 32 levels.
```

## Naming Conventions for Sections

- Use PascalCase for main headers (e.g., `# Properties`, `# Methods`).
- Use camelCase for subsection headers in parameter/return documentation.

## Markdown Formatting

- Use `| ---|---|` for all documentation tables.
- Use backticks for code symbols: `MyLibrary`, `:Update()`, etc.
- Use fenced code blocks with language tags: `` ```lua ``, `` ```markdown ``.
- Use **bold** for emphasis on key terms.
- Use `---` to separate major sections.

---

# Contribution Guidelines

- Open a PR with a clear title and description of changes.
- Keep commits small and focused; reference related issues if available.
- Include or update tests for bug fixes and features.
- When changing `STATUS`, mention the change in the PR description and rationale.

---

# Communication

- Report breaking changes in the package `README.md` and bump major version accordingly.
- For `Deprecated` packages, add migration notes and a planned removal timeline.

---

# Examples

- Add `STATUS: In-Progress` near the top of `README.md` for `packet-stream` while it is being implemented.
- Include version and status badges in package `README.md` for at-a-glance clarity.

---

Follow these conventions to keep the toolkit consistent and maintainable.
