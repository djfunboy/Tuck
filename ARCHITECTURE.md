# Architecture

Tuck is one sandboxed macOS executable with two modes:

- **Normal launch** shows the setup window (how to connect an agent).
- **`Tuck --mcp`** is a local stdio [MCP](https://modelcontextprotocol.io) server that the agent's client launches. It exposes exactly one tool, `save_credential`. When that tool is called, it shows the secure popup.

```
┌────────────────────┐  stdio JSON-RPC   ┌──────────────────────┐   SwiftUI    ┌───────────────────┐
│ MCP client (agent) │ ────────────────► │ BoundedStdioTransport│ ───────────► │ Popup (SecureField│
│ Claude Code, Codex │  service, account │ → MCPService         │  request     │ + Save / Cancel)  │
│ CLI, any stdio MCP │  provider_url?    │ → PromptModel        │  metadata    │                   │
└─────────▲──────────┘                   └──────────────────────┘              └─────────┬─────────┘
          │ one status word                                                              │ person pastes
          │ saved · cancelled · timed_out · busy · restart_required                      ▼ and clicks Save
          │                                                                    ┌───────────────────┐
          └──────────────────────────────────────────────────────────────────  │ KeychainWriter    │
                                                                               │ SecItemAdd/Update │
                                                                               │ login Keychain    │
                                                                               └───────────────────┘
```

## Components

| File | Responsibility |
|---|---|
| `Sources/TuckApp.swift` | Entry point. Chooses setup mode or `--mcp` mode and sets the activation policy once, before launch. |
| `Sources/BoundedStdioTransport.swift` | Custom stdio transport for the MCP SDK. Enforces frame and queue limits, rejects batches, and revokes save permission when the connection fails. |
| `Sources/MCPService.swift` | Declares the `save_credential` tool and its strict JSON schema, then routes calls to `PromptModel`. |
| `Sources/CredentialRequest.swift` | Validates arguments (`MCPRequestValidator`), validates the optional provider link (`ProviderLink`), and defines the status values. |
| `Sources/PromptModel.swift` | Holds one request at a time and resolves it exactly once: saved, cancelled, timed out, busy or restart required. |
| `Sources/SavePermit.swift` | Makes sure a disconnect and the start of a Keychain write cannot race each other. |
| `Sources/KeychainWriter.swift` | Writes generic-password items through `SecItemAdd`, or `SecItemUpdate` after an explicit Replace. There are no read, delete or list calls. |
| `Sources/ExecutableIdentity.swift` | Detects an app bundle that was replaced while `--mcp` kept running. |
| `Sources/ReopenPolicy.swift` | Decides what a Dock or Finder reopen does when an agent-launched instance is already running. |
| `Sources/TuckApplication.swift` | Watches for a paste into the secure field and clears the clipboard afterwards. |
| `Sources/KeyRecognizer.swift`, `Sources/KeyFormats.swift` | Advisory, on-device key-format hints. `KeyFormats.swift` is generated (see `scripts/keyformats/`). |
| `Sources/TuckView.swift` | Setup window, popup, and the agent setup instructions. |

## Trust boundaries

**The agent is not trusted with the credential.** It can supply only three things:

| Argument | Rules |
|---|---|
| `service` | Required string, 1–200 characters |
| `account` | Required string, 1–200 characters |
| `provider_url` | Optional. HTTPS, path only, at most 2,048 bytes. It is shown only as a link the person may click |

The schema sets `additionalProperties: false`. Unknown arguments are rejected before any window opens, including anything that looks like a secret field. Error responses never echo the input.

**The response carries one status word.** It never carries the value, its length, or anything derived from it. There is no tool to read, list, export or delete a credential.

**The provider link is an untrusted suggestion.**
- `ProviderLink` rejects userinfo, queries, fragments, localhost and `.local` names (including trailing-dot forms), IP literals (IPv4, IPv6, IPv4-mapped), control characters, bidirectional overrides and non-HTTPS schemes.
- The popup shows only the hostname. Its help and accessibility text say the agent suggested it and Tuck has not verified it.
- The URL goes to the default browser only when the person clicks it. Tuck itself never makes a network request.

**macOS enforces the rest.**
- The only entitlement is the App Sandbox. There is no network client or server entitlement.
- Items go to the file-based login Keychain (`kSecUseDataProtectionKeychain = false`), so existing command-line tools can read them. No custom access control list is set: macOS applies its normal rules and may ask the person before another app reads an item.

## Limits and failure handling

| Behaviour | Value |
|---|---|
| Maximum inbound frame | 16 KiB. Larger input closes the session |
| Inbound queue | 8 frames. Overflow fails closed |
| JSON-RPC batches | Rejected before SDK dispatch |
| Request lifetime | 5 minutes, then `timed_out` |
| Concurrent requests per process | 1. A second request gets `busy` |
| Client disconnect or stdin EOF | The popup closes and nothing is saved. A write that has already started may complete |
| Output failure | Save permission is revoked and the receive stream closes |
| Logging | A no-op log handler; the SDK passes only method names and request IDs to it |
| App replaced while `--mcp` runs | `restart_required`, with no popup. Otherwise the write would fail with `errSecCSBadObjectFormat` (-67049) |
| Existing item | Updating it needs a second, explicit "Replace in Keychain" click |

The status list also includes `failed`, but no code path returns it today. A Keychain error is shown in the popup, and the request then ends as `cancelled` or `timed_out`. Either way the agent is never told `saved`.

## Clipboard

After a paste is actually inserted into the secure field, Tuck clears the current clipboard, but only if nothing new was copied in the meantime (the pasteboard change count is unchanged). The saved confirmation says "Clipboard cleared" only when that happened. Tuck does not watch the clipboard in the background, and it cannot remove copies that a clipboard-history app already kept.

## Memory

The secure field holds the value while the person types or pastes it. A short-lived `Data` buffer holds it during the Keychain call and is overwritten afterwards. Tuck does not claim to erase every copy the system or runtime might make.

## Agent guidance

The agent learns when to use Tuck from a skill file (`Resources/tuck/SKILL.md`), which the setup instructions install. The canonical copy is hosted at https://tuckaway.dev/skill/SKILL.md, so guidance can improve without an App Store release. The bundled copy is the offline fallback. The MCP `instructions` and the tool description stay short and stable, and point to the skill.

Tuck never installs or edits agent configuration itself. The person pastes the setup instructions into their agent.
