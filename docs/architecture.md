# Architecture And Protocol

## Component boundaries

```text
Quickshell/QML presentation  -- JSONL request/event contract --  dockyardd
                                                               |
                  dockyard CLI -- offline core or socket ---- |
                                                               |
       profile TOML + files -- planner/storage -- snapshots/journals
                                                               |
                         compositor and desktop-entry adapters
```

The Julia package is the policy boundary:

- Domain types represent profiles, pins, dotfile entries, plans, snapshots,
  and transaction results.
- Config validates TOML and expands approved variables.
- Storage hashes, atomically serializes, copies symlinks without dereferencing,
  and verifies snapshots.
- Reconcile classifies drift and coordinates mutation phases.
- Apps scans desktop entries and returns scored resolution evidence.
- Protocol implements the versioned JSONL envelope.
- Daemon owns the per-user Unix socket and dispatches requests.
- CLI provides stable human and JSON output.

QML owns layout, animation, pointer/keyboard interaction, and accessibility
labels. It must not become a second persistence model or write profile TOML.

## Mutation ownership

The profile TOML and repository file tree are authoritative. Runtime revision and
request-id state is repository-namespaced under XDG state. A successful pin,
unpin, or reorder writes the profile atomically and increments its revision.
Repeated request IDs return the stored result without another write.

Dotfile mutations use a separate transaction journal and do not modify live
targets until the snapshot is complete and all staged entries are ready.

## JSONL envelopes

Each message is one JSON object followed by a newline. `v` is currently `1`.

Request:

```json
{"v":1,"id":"request-1","method":"pins.reorder","params":{"from":3,"to":1,"if_revision":42}}
```

Response:

```json
{"v":1,"id":"request-1","ok":true,"result":{"revision":43}}
```

Errors use the same request ID and contain a structured error object. The
current daemon methods are `status`, `plan`, `pins.pin`, `pins.unpin`, and
`pins.reorder`. The event envelope is reserved for the future state projection:

```json
{"v":1,"event":"state.changed","revision":43,"topics":["pins"]}
```

Messages are bounded to 1 MiB. The socket path is
`$XDG_RUNTIME_DIR/dockyard/dockyard.sock` by default, and the daemon rejects
paths longer than the Unix-domain socket limit used by the implementation.

## Application identity

Resolution is inspectable and scored:

| Evidence | Score |
| --- | ---: |
| Exact desktop-file ID | 100 |
| User-defined alias | 95 |
| Exact `StartupWMClass` | 90 |
| Normalized app ID to filename | 80 |
| Executable basename | 60 |

Ties are returned as ambiguous candidates. Missing desktop entries remain valid
portable pins and are represented as missing rather than deleted.

## Runtime lifecycle

The daemon performs journal recovery before accepting clients, then listens for
one request per connection. The current implementation has the socket and
dispatch skeleton; serialized mutation queues, profile watchers, state event
subscriptions, peer credential validation, and compositor reconnect handling
remain on the roadmap.
