# Architecture overview

Breazin is a native SwiftPM macOS application. `Sources/Breazin` contains one executable target whose major boundaries are:

- `App`: lifecycle and the environment-selected product identity.
- `Project` and `Models`: document packages, timelines, media manifests, and compatibility.
- `Editor`, `Timeline`, `Preview`, `Export`: local editing and rendering.
- `Agent`: the local tool-use loop and MCP bridge. Tool execution is local; it is not a general shell agent.
- `Generation` and `Backend`: generation orchestration plus the legacy remote adapter that must be replaced through provider contracts.
- `Transcription`, `Search`, `Audio`, `Compositing`: local media capabilities.
- `Settings`, `Telemetry`, `Utilities`: UI configuration and shared infrastructure.

`AppConfiguration.current` is the single runtime source for bundle-derived storage, Keychain service, logs, project identity, update channel, and MCP identity. Build scripts inject the chosen environment into `Info.plist`; feature code must not read `BREAZIN_ENVIRONMENT` directly.

The GPL client and any future private feedback/control plane are separate repositories connected only through HTTP APIs. No private platform secret belongs in this repository or desktop application.
