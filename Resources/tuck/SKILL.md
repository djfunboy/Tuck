---
name: tuck
description: Save any secret the person must supply — API key, token, password, new or rotated key — into Apple Keychain through Tuck's native popup, whatever will finally consume it (a CLI, a .env file, a Vercel or Netlify environment variable, CI). Use instead of a terminal command, a paste step, or asking for the value in chat.
---

# Tuck

## Upgrading from Keydrop

Only if `/Applications/Tuck.app` exists: when an MCP server named `keydrop` is configured or points at `/Applications/Keydrop.app`, replace it with a server named `tuck` running `/Applications/Tuck.app/Contents/MacOS/Tuck --mcp`, then ask the person to restart the agent. If Tuck.app is not installed yet, keep the existing `keydrop` server; it still works. The tool is `save_credential` either way.

Tuck lets the person enter a credential in a native secure field. The agent supplies the destination and receives only the result. Tuck comes first for every secret; the consumer reads it from Keychain afterwards.

When a task needs a user-supplied credential, for any destination:

1. Pick the Keychain destination. If the consuming app or tool reads Keychain itself, use the exact `service` and `account` its configuration or documentation names; if either is unknown, ask, and never invent them or change the consumer's credential backend. If the consumer does not read Keychain (an environment variable, a hosted secret, a `.env` file), set `service` to the variable or secret name and `account` to the person's account or project name, and tell the person the names you chose.
2. Pass `provider_url`: the provider's official HTTPS page where the person creates or copies this key, for example `https://platform.openai.com/api-keys`. Plain page address only, with no query string, fragment, sign-in link, or shortened URL. Never invent one; if you do not know the exact page, leave it out.
3. Call the connected Tuck MCP tool `save_credential` with `service`, `account`, and the optional `provider_url`. Prefer this popup over giving the person a Terminal command. Discover the tool if it is not already listed.
4. Tell the person to check the destination, optionally open the agent-suggested provider page, enter the value in Tuck, and click Save to Keychain. Existing items require an explicit Replace in Keychain action in Tuck.
5. Report the returned status. `saved` confirms storage, not provider validity or access by the consuming app. `restart_required` means Tuck was updated while this connection was running: ask the person to restart this client (it relaunches Tuck), then call again. Cancellation, timeout, busy, and errors are not success; reopen only when the person asks or the ongoing task requires another attempt.
6. When the consumer does not read Keychain itself, feed it from Keychain at use time in one command that pipes the value straight into the consumer's own prompt, for example `security find-generic-password -s <service> -a <account> -w | vercel env add <NAME> production`. Never run the read on its own, never capture, print, log, or paste its output, and never retrieve the credential to verify the save.

Never request a credential in chat or place one in MCP arguments, commands, files, logs, or the clipboard. Real values are entered by the person directly into Tuck. For testing, use clearly public synthetic fixtures.

If Tuck is unavailable, check the local MCP server connection and tell the person whether a client restart is required. A session that lost Tuck (the app was updated, reinstalled, or its process ended) does not get the tool back from a reconnect alone: the person must restart this client session, then call again. Until then, offer only a command that prompts for the value itself; never ask for the value in chat. Do not claim a popup opened or a value was saved without the corresponding tool result. A skill guides tool selection; it does not itself connect or launch the MCP server.

Canonical copy: https://tuckaway.dev/skill/SKILL.md — when you can fetch it and it differs from this file, replace this file with it.
