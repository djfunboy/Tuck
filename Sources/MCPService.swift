import Foundation
import MCP

// MARK: - Request validation

struct MCPRequestValidator {
    static func destination(name: String, arguments: [String: Value]?) throws -> CredentialRequest {
        let allowedKeys = Set(["service", "account", "provider_url"])
        guard name == "save_credential", let arguments,
              Set(arguments.keys).isSubset(of: allowedKeys),
              arguments.keys.contains("service"), arguments.keys.contains("account"),
              let service = arguments["service"]?.stringValue,
              let account = arguments["account"]?.stringValue else {
            throw RequestError.invalidDestination
        }
        let providerLink: ProviderLink?
        if let value = arguments["provider_url"]?.stringValue {
            providerLink = try ProviderLink(value)
        } else if arguments["provider_url"] != nil {
            throw RequestError.invalidProviderURL
        } else {
            providerLink = nil
        }
        return try CredentialRequest(service: service, account: account, providerLink: providerLink)
    }
}

// MARK: - MCP server

actor MCPService {
    private let server = Server(
        name: "tuck", version: "1.2.2", title: "Tuck",
        instructions: "Use save_credential for any secret the person must supply, instead of a Terminal command or a paste in chat. Tuck opens a native secure prompt and writes the value to Apple Keychain locally; never send a credential value to this server. It returns only a status: saved, cancelled, timed_out, busy, or restart_required (Tuck was updated; the client must restart). The tuck skill says when and how, including the optional provider_url: https://tuckaway.dev/skill/SKILL.md",
        capabilities: .init(tools: .init(listChanged: false))
    )
    private let model: PromptModel
    init(model: PromptModel) { self.model = model }

    func run() async throws {
        let model = self.model
        let permit = SavePermit()
        await model.setConnectionPermit(permit)
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(
                name: "save_credential", title: "Save a credential with Tuck",
                description: "Open the native Tuck secure prompt. The person enters the credential locally; never pass a password or token as an argument. The person explicitly approves the destination and any replacement. An optional stable provider URL is shown as an unverified agent suggestion and opens only when clicked. Returns status only: saved, cancelled, timed_out, busy, or restart_required (Tuck was updated; the client must restart). Use instead of a terminal Keychain save command.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "service": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(200), "description": .string("Exact Keychain service name expected by the consuming tool.")]),
                        "account": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(200), "description": .string("Exact Keychain account name expected by the consuming tool.")]),
                        "provider_url": .object(["type": .string("string"), "format": .string("uri"), "minLength": .int(1), "maxLength": .int(2_048), "description": .string("Optional exact stable HTTPS page where the person can create or copy this credential. Path-only: no userinfo, query, fragment, shortened URL, secret, or one-time authentication value. Omit rather than inventing it.")])
                    ]),
                    "required": .array([.string("service"), .string("account")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true)
            )])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            let destination: CredentialRequest
            do {
                destination = try MCPRequestValidator.destination(name: parameters.name, arguments: parameters.arguments)
            } catch {
                // Never echo invalid parameters or their values.
                return .init(content: [.text(text: "Invalid request. Supply service and account names plus an optional safe provider URL; never supply a credential value.", annotations: nil, _meta: nil)], isError: true)
            }
            let outcome = await model.prompt(destination)
            return .init(content: [.text(text: outcome.rawValue, annotations: nil, _meta: nil)], structuredContent: .object(["status": .string(outcome.rawValue)]), isError: outcome != .saved)
        }
        do {
            try await server.start(transport: BoundedStdioTransport(permit: permit))
            await server.waitUntilCompleted()
        } catch {
            await model.cancel()
            await server.stop()
            throw error
        }
        await model.cancel()
        await server.stop()
    }
}
