<div align="center">

# Manager-Loader

<p>
Bootstraps and manages a hierarchical collection of Manager instances from ModuleScript children.
</p>

</div>

---

**STATUS:** $\color{LightGreen}\texttt{Active}$

**VERSION:** 1.0.0

This package is stable, maintained, and recommended for use.

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

# Overview

Manager-Loader provides a centralized system for discovering, loading, and managing Manager modules within a Roblox instance hierarchy. It automatically scans a root instance for ModuleScript children, validates them, sorts them by dependency order, and initializes each Manager instance.

| Component | Description |
|---|---|
| **ManagerLoader** | Main class managing the bootstrap and lifecycle of all managers. |
| **ModuleUtil** | Handles module loading, sorting, and dependency resolution. |
| **ConnectorUtil** | Wraps Events for manager lifecycle signals. |
| **ManagerUtil** | Scans instance hierarchies to find candidate Manager modules. |

---

# How It Works

1. **Initialization**: Create a new `ManagerLoader` instance with a root instance.
2. **Scanning**: The `Bootstrap()` method scans the root instance for ModuleScripts containing child ModuleScripts (manager definitions).
3. **Sorting**: Candidate managers are sorted by dependency order using `ModuleUtil.SortModules()`.
4. **Loading**: Each manager is loaded, instantiated via `.new()`, and its `:Load()` method is called.
5. **Registration**: Loaded managers are stored in an internal map and announced via the `OnManagerLoaded` signal.
6. **Retrieval**: Managers can be queried by name using `GetManager()`.

---

# API Documentation

## Constructor

### `ManagerLoader.new(Root: Instance): ManagerLoader`

Creates a new ManagerLoader instance.

| Parameter | Type | Description |
|---|---|---|
| `Root` | `Instance` | The root instance to scan for Manager modules. |

| Returns | Type | Description |
|---|---|---|
| `ManagerLoader` | `ManagerLoader` | A new loader instance. |

---

## Methods

### `:Bootstrap(): ()`

Scans the root instance, loads all Manager modules, instantiates them, and fires the `OnManagerLoaded` signal for each.

**Call this once after construction to initialize all managers.**

### `:GetManager(Name: string): (any?)`

Retrieves a previously loaded Manager by name.

| Parameter | Type | Description |
|---|---|---|
| `Name` | `string` | The name of the manager (ModuleScript name). |

| Returns | Type | Description |
|---|---|---|
| `Manager` | `any?` | The manager instance, or `nil` if not found. |

---

## Properties

### `OnManagerLoaded: ConnectorUtil`

Event signal fired when a manager is successfully loaded and initialized.

**Signal Parameters:**
- `managerName: string` — Name of the loaded manager.
- `managerInstance: any` — The manager instance.

---

# Examples

## Basic Usage

```lua
local ManagerLoader = require(path.to.ManagerLoader)

local loader = ManagerLoader.new(game.ServerScriptService:WaitForChild("Managers"))
loader:Bootstrap()

-- Listen for managers being loaded
loader.OnManagerLoaded:Connect(function(name, instance)
    print("Manager loaded:", name, instance)
end)

-- Retrieve a specific manager
local userManager = loader:GetManager("UserManager")
if userManager then
    userManager:DoSomething()
end
```

---

# Testing

Tests are located in `test/`. You can run test on the Studio as a Client or Server side.

---

# Known Limitations

- Managers must export a constructor function named `.new()` and a method named `:Load()`.
- Module sorting relies on presence/absence of child ModuleScripts; complex dependency graphs may require explicit ordering.
- No async or deferred loading; all managers are loaded synchronously during `Bootstrap()`.
