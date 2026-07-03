<div align="center">

# Fabric

<p>
A thread orchestration library for Luau that provides reusable `ThreadMaster` instances, scoped data, global environment values, and safe coroutine execution.
</p>

</div>

---

**STATUS:** $\color{LightGreen}\texttt{Active}$

**VERSION:** 1.0.1

This package is stable, maintained, and recommended for use.

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

# Overview

Fabric manages isolated execution contexts using thread-bound `ThreadMaster` objects.

- Creates or reuses a dedicated runner coroutine per master.
- Provides per-master private and public scopes.
- Provides a global Fabric scope shared across all masters.
- Resolves thread identifiers and master instances from any coroutine context.

---

# How It Works

Fabric is a thread manager with environmental variable for each ThreadMaster.

1. Call `Fabric:Bind(Identifier, ThreadConfig)` to create or reuse a `ThreadMaster`.
2. Fabric allocates a dedicated runner coroutine and stores master state in internal registries.
3. Use `ThreadMaster:Run(...)` to execute actions safely in the bound runner.
4. Scope values are stored and resolved by visibility: `Global`, `Public`, or `Private`.
5. Call `ThreadMaster:Destroy()` to recycle the master and clear internal state.

---

# API Documentation

## `:Bind(Identifier, ThreadConfig)`

Creates or reuses a `ThreadMaster` instance for the given identifier.

| Parameter | Type | Description |
|---|---|---|
| `Identifier` | `string?` | Optional name for the master. Defaults to `Fabric_Default_<n>`. |
| `ThreadConfig` | `table` | Configuration object containing `Name`. |

| Returns | Type | Description |
|---|---|---|
| `ThreadMaster` | `ThreadMaster` | The bound master instance. |

---

## `:Determine(GetChoice, Thread?)`

Resolves Fabric metadata for the current or specified thread.

| Parameter | Type | Description |
|---|---|---|
| `GetChoice` | `DeterminableChoice` | What to resolve. |
| `Thread` | `thread?` | Optional thread to query. |

| Returns | Type | Description |
|---|---|---|
| `Union?` | `Union` | The requested metadata value or `nil`. |

---

## `:GetPublicScope(Master, Key)`

Returns the public scope value for the provided `ThreadMaster` and key.

---

## `:GetGScopeValue(Key)`

Returns a value from the Fabric-level global scope.

---

## `:SetGScopeValue(Key, Value)`

Sets a Fabric-level global scope value.

---

# ThreadMaster API

A `ThreadMaster` is created by `Fabric:Bind(...)`.

## `:Run(ProcessName?, Action, ...)`

Executes `Action(self, ...)` in the bound runner coroutine.

| Parameter | Type | Description |
|---|---|---|
| `ProcessName` | `string?` | Optional label for the runner callback. |
| `Action` | `function` | Callback invoked with the master instance. |
| `...` | `any` | Additional arguments forwarded to the callback. |

Returns the values returned by `Action`.

---

## `:GetScopeValue(Key)`

Returns the value associated with `Key` in the master scope.
Falls back to Fabric global scope when the key is not found.

---

## `:SetScopeValue(Key, Value, Visibility)`

Stores a value with the requested visibility.

| Visibility | Behavior |
|---|---|
| `Global` | Sets a global Fabric scope value. |
| `Private` | Sets a private value for this master only. |
| otherwise | Sets a public value for this master. |

---

## `:Destroy()`

Recycles the master into Fabric and clears internal state.

---

# Example

```lua
local Fabric = require(script.Parent.init)

local fabric = Fabric
local master = fabric:Bind("PlayerThread", { Name = "PlayerLoop" })

master:SetScopeValue("Score", 0, "Public")
master:SetScopeValue("Version", "1.0", "Global")

local version, newScore = master:Run("Update", function(self, delta)
    local version = self:GetScopeValue("Version")
    local score = self:GetScopeValue("Score")
    self:SetScopeValue("Score", score + delta, "Public")
    return version, score + delta
end, 5)

print(version, newScore)

master:Destroy()
```

---

# Testing

Tests are located in `test/`.

However currently there has been no test done yet.

---

# Dependencies

- `common/Resolver`

---

# Known Limitations

- `ThreadMaster` instances are recycled when destroyed and there is no safeguard for method; do not rely on internal state after `Destroy()`.
