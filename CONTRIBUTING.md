<div align="center">

# Contributing to luau-toolkit

<p>
Thank you for your interest in contributing to `luau-toolkit`. This document outlines how to contribute code, report issues, and participate in the project.
</p>

</div>

---

# Overview

This project welcomes contributions in the form of:

- Bug reports and issue discussions
- Code contributions (features, fixes, refactoring)
- Documentation improvements
- Test additions and test coverage improvements

All contributions must follow the standards and conventions outlined in [PROTOCOL.md](PROTOCOL.md).

---

# Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/luau-toolkit.git
   cd luau-toolkit
   ```
3. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
   Use descriptive branch names: `feature/add-encryption`, `fix/buffer-overflow`, `docs/readme-clarity`.

---

# Code Contributions

## Before You Start

- Read [PROTOCOL.md](PROTOCOL.md) completely to understand naming conventions, code standards, and package layout.
- Check the [PROGRESS.md](PROGRESS.md) file to see current status of each library.
- Look at existing code in `library/` to understand the project's style.

## Making Changes

### Code Standards

All code must adhere to [PROTOCOL.md](PROTOCOL.md):

- **Naming**: Use `kebab-case` for packages, `PascalCase` for files, `UPPER_CASE` for constants, `camelCase` for functions, `_PascalCase` for private methods.
- **Indentation**: 4 spaces (no tabs).
- **Line Endings**: LF only.
- **No Trailing Whitespace**.
- **No Abbreviations**: Use full names (`maximumRetries` not `maxRetries`).
- **Member Ordering**: Group by category (Action → Information → Lifecycle), then sort alphabetically within each group.

### Commit Messages

- Keep commits small and focused; one feature or fix per commit.
- Use clear, descriptive commit messages:
  ```
  Fix packet encoding buffer overflow in Codec

  - Prevent buffer overrun when encoding tables with many keys
  - Add bounds checking before write operations
  - Fixes issue #42
  ```
- Reference related issues in your commit messages: `Fixes #123`, `Relates to #456`.

### Testing

- Add or update tests for all new features and bug fixes.
- Place tests in the `test/` directory of the affected package.
- Document how to run tests in the package `README.md`.
- Ensure all tests pass before submitting a PR.

### Documentation

- Update the relevant `README.md` if your changes affect the public API.
- Follow [PROTOCOL.md README Standards](PROTOCOL.md#readme-standards) for documentation layout and format.
- Include usage examples for new features.
- Update [PROGRESS.md](PROGRESS.md) to reflect the status of affected libraries.

---

# Pull Requests

## Submitting a PR

1. **Push your branch** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Open a Pull Request** on GitHub with:
   - **Title**: Clear, concise description (e.g., `Add encryption support to PacketStreamer`)
   - **Description**: Explain what changed, why, and any related issues
   - **Checklist**:
     ```markdown
     - [ ] Code follows [PROTOCOL.md](PROTOCOL.md) standards
     - [ ] Tests added/updated
     - [ ] README updated (if applicable)
     - [ ] PROGRESS.md updated
     - [ ] Commit messages are clear and descriptive
     - [ ] No trailing whitespace or linting issues
     ```

## PR Review

- PRs will be reviewed for adherence to [PROTOCOL.md](PROTOCOL.md).
- Reviewers may request changes, clarifications, or improvements.
- Be responsive to feedback and update your PR accordingly.

## Merging

- PRs are merged into `main` once approved.
- Use "Squash and merge" for cleaner history if the PR has many small commits.
- Delete your branch after merging.

---

# Reporting Issues

## Bug Reports

When reporting a bug, include:

1. **Title**: Brief, clear description of the issue.
2. **Description**: Detailed explanation of the problem.
3. **Steps to Reproduce**: Exact steps to trigger the bug.
4. **Expected Behavior**: What should happen.
5. **Actual Behavior**: What actually happens.
6. **Environment**:
   - Luau version
   - OS and platform (Windows, macOS, Linux; Roblox Studio, standalone, etc.)
   - Any relevant package versions

### Example

```
Title: PacketStreamer crashes on empty buffer input

Description:
When PacketStreamer.Decode() is called with an empty buffer, it crashes instead of returning gracefully.

Steps to Reproduce:
1. Create a PacketStreamer instance
2. Call Decode() with an empty buffer
3. Observe the error

Expected: Return nil or an empty table
Actual: [Error traceback]

Environment:
- Luau 0.622
- Roblox Studio (latest)
```

## Feature Requests

1. **Title**: Concise description of the feature.
2. **Use Case**: Why this feature is needed.
3. **Proposed Solution**: Describe the feature or API.
4. **Alternatives**: Any alternative approaches considered.

---

# Status and Versioning

## STATUS Changes

When changing a package's `STATUS` (in [PROGRESS.md](PROGRESS.md) and the package `README.md`):

- Include the change in your PR description with rationale.
- Use the canonical STATUS values: `Not-Started`, `In-Progress`, `Stand-By`, `Active`, `Deprecated`.
- For `Deprecated` packages, include migration guidance and a planned removal timeline.

## Versioning

- Follow semantic versioning: `MAJOR.MINOR.PATCH`.
- Document version changes in package `README.md`.
- Include breaking changes in the PR description if applicable.

---

# Code Review Guidelines

- Be respectful and constructive in code review.
- Acknowledge good ideas and improvements.
- Provide clear rationale for suggested changes.
- Ask questions rather than making demands.

---

# Questions or Need Help?

- Check [PROTOCOL.md](PROTOCOL.md) and existing package `README.md` files for answers.
- Open a discussion issue if you need clarification on standards or conventions.
- Read the code in `library/` to see real-world examples.

---

Thank you for contributing to `luau-toolkit`!
