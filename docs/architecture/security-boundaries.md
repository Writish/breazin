# Security boundaries

## Desktop client

- Provider keys are stored in an environment-specific Keychain service. Models, prompts, tool results, logs, telemetry, and feedback must never receive raw keys or Authorization headers.
- Development telemetry is off. Staging and production require explicit build-time values and separate projects.
- MCP is off by default and binds only to loopback. The present transport does not yet satisfy the planned pairing-token and capability-grant contract, so it must not be exposed through LAN, tunnels, or reverse proxies.
- The in-app agent has no shell or arbitrary process tool. File import/export and paid provider calls remain high-impact actions and require capability enforcement in code, not only prompt instructions.
- URL import must remain HTTPS-only and reject loopback, private, link-local, metadata, redirect, size, and timeout abuse before MCP is considered production-safe.

## External control plane

The future feedback service owns GitHub App credentials, object-storage credentials, rate limiting, attachment expiry, and issue creation. The desktop app must never contain a GitHub PAT or GitHub App private key. Feedback text is untrusted data and cannot directly trigger a write-capable repair agent.

## Release boundary

Signing identity, provisioning profile, notarization profile, Sparkle private key, and production telemetry configuration are CI environment secrets. Production publication requires a protected environment and human approval. Local ad-hoc builds are never labeled production-ready.
