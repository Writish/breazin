# Agent subsystem rules

- The in-app agent must not gain Shell, arbitrary process execution, raw Keychain access, or unrestricted paths.
- Tool permissions are enforced in Swift code; prompts and skills are not security boundaries.
- MCP remains disabled by default and loopback-only. Authentication, session, capability, URL, and file-path changes require dedicated adversarial tests and human review.
- Paid provider calls, uploads, external imports, exports, destructive operations, and project migrations require explicit capability handling.
