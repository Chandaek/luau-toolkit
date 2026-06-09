<div align="center">

# ⚠️ PacketStreamService [DEPRECATED]

<p>
<strong>This library is deprecated and will no longer be maintained or supported.</strong>
</p>

<p>
A Luau network service for Roblox that centralizes packet delivery through rate-limited, batched, binary-encoded transmission with encryption, delta streaming, persistent replication via Roblox instances, and intelligent stream mode switching.
</p>

</div>

---

# ⚠️ Deprecation Notice

**PacketStreamService is no longer maintained or supported by the author.** This code is provided as-is for historical and reference purposes only. No updates, bug fixes, or assistance will be provided.

If you are currently using this library, please consider:
- Forking the repository to maintain your own version
- Migrating to alternative networking solutions
- Reviewing the code thoroughly before continued use

---

# Overview

PacketStreamService operates as both a global singleton and a factory. The singleton manages a shared global stream. The factory produces independent `PacketStreamer` instances, each with their own remotes, queues, and configuration.

| Layer | Description |
|---|---|
| **PacketStreamService** | Global singleton. Shared remotes, one rate-limited dispatch loop, encryption per player. |
| **PacketStreamer** | Independent instance from `.new()`. Isolated remotes, queues, and configuration. |
| **Codec** | Binary buffer encoder and decoder for all packet data and persistent state sync. |
| **Encryption** | Per-client xorshift128+ stream cipher with random key delivery and batched key rotation. |
| **PingProtocol** | Bidirectional acknowledgment layer over `UnreliableRemoteEvent` for smart packet confirmation and retry. |
| **FlagSchema** | Compact bitfield ping flags with studio-locked schema, security validation, and guard listeners. |

---

# How It Works

**Dispatch** happens on `RunService.Heartbeat` at every `StreamInterval` milliseconds, subject to a token-bucket `RateLimit`. All outbound entries across all topics accumulate in a queue and flush together.

**Encoding** uses a typed binary buffer: booleans cost 1 byte, integers up to 32-bit cost 5 bytes, doubles cost 9 bytes, strings carry a 4-byte length prefix, and tables encode recursively. Topic labels themselves are not encoded.

**Encryption** applies to all instancing-mode transmissions. On player join, the server generates a 16-byte cryptographically random key and delivers it privately via `SendTo`. All subsequent instancing packets are encrypted with xorshift128+.

**Persistent state** lives as Roblox `Folder` instances with `Attribute`-backed primitive fields and recursive sub-folders for nested tables. Roblox replicates only changed attributes automatically at the engine level.

**StreamingPacket** delivers a continuous per-player data stream each `StreamInterval`. In instancing mode, data writes to an attribute on the player's private folder under `St_{name}/{userId}/`.

**PingFlags** pack all boolean flags into a minimal bitfield appended to every unreliable ping. Schema definition is locked once set and cannot be modified at runtime. Changes to flag values fire all registered `OnFlagChange` listeners.

---

# Structure

```
PacketStreamService (ModuleScript)
├── Codec           (ModuleScript)
├── Encryption      (ModuleScript)
├── PingProtocol    (ModuleScript)
└── FlagSchema      (ModuleScript)
```

Sibling dependencies:
```
Common/
└── EventEmitter
Library/
├── PacketStreamService/
├── SecureStorage
```

---

# Singleton

## `PacketStreamService.Configure(config: PacketStreamServiceConfiguration): ()`

Initializes the singleton. Must be called before any other method. Can only be called once.

---

## `PacketStreamService.new(name: string, config: PacketStreamerConfiguration?): PacketStreamer`

Creates an independent `PacketStreamer` with its own remotes and queues. Requires `AllowIndependentStream = true`.

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `name` | `string` | Unique name for this streamer. Used to create its remote and instancing folders. |
| `config` | `PacketStreamerConfiguration?` | Optional configuration. Inherits from service config if `IndependentInheritance` is enabled. |

---

# Methods — Both Sides

## `:On(eventName: string, callback: (...any) -> ()): EventConnection`

Subscribes to an event. Returns a connection with `.Connected` and `:Disconnect()`.

---

## `:Once(eventName: string, callback: (...any) -> ()): EventConnection`

Subscribes to an event and automatically disconnects after the first fire.

---

## `:Wait(eventName: string): ...any`

Yields until the named event fires and returns its arguments.

---

## `:GetFlag(flagName: string): boolean`

Returns the current value of a defined ping flag.

---

## `:Stats(): StatsResult`

Returns a reused cached table of runtime statistics. Do not hold a reference between calls.

### Returns

```lua
{
    IsInstancing = false,
    RateBucket   = 60,
    OutboundTotal = 0,
    PersistentTopics = 0,
    ActiveStreams = 0,
}
```

---

# Methods — Server Only

## `:SendTo(player: Player, topic: string, data: any, mode: SendMode?): ()`

Sends a one-time packet to a specific player.

| Parameter | Type | Description |
|---|---|---|
| `player` | `Player` | Target player. |
| `topic` | `string` | Topic name. Registered automatically on first use. |
| `data` | `any` | Payload. Tables, primitives, and nested structures supported. |
| `mode` | `SendMode?` | `"Normal"` or `"Instancing"`. Falls back to `DefaultSendMode` if omitted. |

When `mode` is `"Instancing"`, the packet is written as an encrypted `StringValue` in the instancing folder and delivered via Roblox instance replication. Lacks privacy from other client scripts.

---

## `:Broadcast(topic: string, data: any): ()`

Queues a one-time packet for all players. Dispatched via the normal remote batch on the next tick.

---

## `:SetPersistent(topic: string, state: {[string]: any}): ()`

Creates or updates a persistent public data topic. State is synced to a `Folder` in `ReplicatedStorage`. Roblox replicates changed attributes automatically at the engine level. Late-joining players will receive the most current state.

Nested tables become sub-folders. Flat primitives become Attributes.

---

## `:RemovePersistent(topic: string): ()`

Destroys the persistent topic folder. Clients receive the `PersistentRemoved` event.

---

## `:StartStream(player: Player, topic: string, initialData: any, mode: SendMode?): StreamHandle?`

Begins a continuous per-player stream updated every `StreamInterval`. Returns a `StreamHandle` only when `AllowManualStreamControl` is enabled.

### StreamHandle

| Method | Description |
|---|---|
| `Handle.Update(data)` | Immediately pushes a new value, bypassing the interval. |
| `Handle.Stop()` | Stops the stream and sends a final stop signal to the client via remote. |
| `Handle.SetMode(mode)` | Switches between `"Normal"` and `"Instancing"` for this stream at runtime. |

---

## `:SetFlag(flagName: string, value: boolean): ()`

Updates a ping flag value. Triggers the security listener before applying. Fires `OnFlagChange` listeners on both sides via the next ping.

---

## `:SetDefaultMode(target: "SendTo" | "StartStream", mode: SendMode): ()`

Sets the default transmission mode for `SendTo` or `StartStream` when no explicit mode is passed.

---

## `:DefinePingFlags(flags: {[string]: boolean}): ()`

Defines the ping flag schema. Keys are flag names, values are defaults. Can only be called once. Must be called before `RunService:IsRunning()`.

```lua
PacketStreamService.DefinePingFlags({
    IsServerReady  = false,
    IsTestRunning  = false,
    IsMaintenanceMode = false,
})
```

---

## `:AddSecurityListener(listener: (flagName: string, value: boolean) -> (nil?, string?)): ()`

Registers a first-pass security validator for flag changes. Must be added before `RunService:IsRunning()`. Only one listener is allowed.

On server start, each flag is fake-pushed through the listener to verify it always returns `(nil, string)`. Listener is disabled with a warning if validation fails.

Return `nil, "reason"` to block the change. Blocked changes warn if no guard listeners are registered, or forward to all guard listeners.

---

## `:AddGuardListener(listener: (flagName: string, value: boolean, reason: string) -> ()): ()`

Registers a secondary listener that fires when the security listener blocks a flag change. Multiple guard listeners are allowed and all fire in registration order.

---

## `:OnFlagChange(listener: (flagName: string, value: boolean) -> ()): ()`

Registers a listener that fires on both sides whenever a flag value changes.

---

# Methods — Client Only

## `:Send(topic: string, data: any): ()`

Sends a one-time packet to the server. Requires `AllowClientStreaming = true`.

---

## `:RequestState(topic: string): {[string]: any}?`

Invokes the server via `RemoteFunction` and returns the current persistent state for a topic. Yields until resolved.

---

# Events

Events are fired via the internal `EventEmitter`. All topic-specific events fire twice — once as `"TopicName"` and once under the general category event.

| Event | Side | Arguments | Description |
|---|---|---|---|
| `"Packet"` | Both | `(player?, topic, data)` | General ephemeral packet received. Server includes `player`. |
| `"PersistentPacket"` | Client | `(topic, state)` | Persistent state received or updated. |
| `"PersistentRemoved"` | Client | `(topic)` | Persistent topic folder destroyed on server. |
| `"StreamingPacket"` | Client | `(topic, data)` | Streaming update received from server. |
| `"StreamStop"` | Client | `(topic)` | Server signaled this stream has stopped. |
| `"StreamMode"` | Both | `("Instancing" \| "Normal")` | Auto-instancing threshold crossed. |
| `"StreamModeChanged"` | Server | `(player, topic, mode)` | Stream mode manually changed via handle. |
| `"RateLimited"` | Both | none | Rate bucket exhausted this tick. |
| `"PacketDropped"` | Both | `(player?, packetId)` | Ping retry count exceeded. |
| `"Ping"` | Client | `(latencyMs)` | Round-trip ping time in milliseconds. Requires `ConnectionPing`. |
| `"ClientKeyAck"` | Server | `(player)` | Client acknowledged encryption key delivery. |

---

# Configuration

## `PacketStreamServiceConfiguration`

```lua
type PacketStreamServiceConfiguration = {
    InstancingStream: boolean?,
    AutoInstancingStream: number?,
    PersistentStreamInterval: number?,
    AllowIndependentStream: boolean?,
    IndependentInheritance: boolean?,
    StreamInterval: number?,
    RateLimit: number?,
    ConnectionPing: boolean?,
    MaxQueueSize: number?,
    DebugMode: boolean?,
    UseSecureStorage: boolean?,
    PingInterval: number?,
    MaxRetryCount: number?,
    DeadPacketWarn: number?,
    KeyRotationCooldown: number?,
    AllowClientStreaming: boolean?,
    AllowManualStreamControl: boolean?,
    DefaultSendMode: SendMode?,
    DefaultStreamMode: SendMode?,
}
```

## `PacketStreamerConfiguration`

Same fields excluding `AllowIndependentStream`, `IndependentInheritance`, and `AllowClientStreaming`.

---

# Configuration Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `InstancingStream` | `boolean?` | `true` | Enables instancing-mode delivery capability. |
| `AutoInstancingStream` | `number?` | `50` | Server frame time threshold in ms to auto-switch to instancing mode. `0` disables. |
| `PersistentStreamInterval` | `number?` | `10` | Cooldown in ms between persistent state syncs. `0` syncs on every tick. |
| `AllowIndependentStream` | `boolean?` | `true` | Allows creation of independent `PacketStreamer` instances. |
| `IndependentInheritance` | `boolean?` | `true` | Independent streamers inherit service config as defaults. |
| `StreamInterval` | `number?` | `16.67` | Dispatch interval in ms. `0` disables interval-gating. |
| `RateLimit` | `number?` | `60` | Maximum dispatches per second via token bucket. |
| `ConnectionPing` | `boolean?` | `false` | Enables unreliable ping protocol for acknowledgment and latency tracking. |
| `MaxQueueSize` | `number?` | `1000` | Maximum entries per outbound queue before rate-limiting fires. |
| `DebugMode` | `boolean?` | `false` | Reserved for internal diagnostic output. |
| `UseSecureStorage` | `boolean?` | `false` | Uses `SecureStorage` for internal data. Warns if dependency is missing. |
| `PingInterval` | `number?` | `100` | Unreliable ping tick interval in ms. |
| `MaxRetryCount` | `number?` | `10` | Maximum packet retry attempts before `PacketDropped` fires. `0` retries indefinitely and warns. |
| `DeadPacketWarn` | `number?` | `5` | Retry count before a dead-packet warning is emitted. `0` disables. |
| `KeyRotationCooldown` | `number?` | `3000` | Cooldown in ms before encryption keys are rotated after a player join or leave. |
| `AllowClientStreaming` | `boolean?` | `false` | Allows clients to send packets to the server via `Send`. |
| `AllowManualStreamControl` | `boolean?` | `false` | `StartStream` returns a `StreamHandle` for manual control when enabled. |
| `DefaultSendMode` | `SendMode?` | `"Normal"` | Default mode for `SendTo` when no explicit mode is passed. |
| `DefaultStreamMode` | `SendMode?` | `"Normal"` | Default mode for `StartStream` when no explicit mode is passed. |

---

# Example

```lua
-- Server
local PacketStreamService = require(game:GetService("ReplicatedStorage").Library.PacketStreamService)

PacketStreamService.Configure({
    ConnectionPing = true,
    AllowClientStreaming = true,
    AllowManualStreamControl = true,
    StreamInterval = 16.67,
    RateLimit = 60,
    MaxRetryCount = 5,
    DeadPacketWarn = 3,
})

PacketStreamService.DefinePingFlags({
    IsServerReady = false,
    IsMaintenanceMode = false,
})

PacketStreamService.SetPersistent("ServerState", {
    MapName = "Highlands",
    PlayerCount = 0,
    TimeOfDay = 14,
})

Players.PlayerAdded:Connect(function(Player)
    PacketStreamService.SendTo(Player, "Welcome", { Message = "Hello!" })

    local Handle = PacketStreamService.StartStream(Player, "PlayerHealth", { Health = 100 })
    if Handle then
        task.delay(5, function()
            Handle.Update({ Health = 80 })
        end)
    end
end)

PacketStreamService.On("Packet", function(Player, Topic, Data)
    print(Player.Name, "sent", Topic, Data)
end)
```

```lua
-- Client
local PacketStreamService = require(game:GetService("ReplicatedStorage").Library.PacketStreamService)

PacketStreamService.On("Packet", function(Topic, Data)
    print("Received:", Topic, Data)
end)

PacketStreamService.On("PersistentPacket", function(Topic, State)
    print("Persistent:", Topic, State)
end)

PacketStreamService.On("StreamingPacket", function(Topic, Data)
    print("Stream update:", Topic, Data)
end)

PacketStreamService.Send("PlayerAction", { Action = "Jump" })
```

---
