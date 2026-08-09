# ADR 0001: Product identity and environment isolation

Status: Accepted — 2026-07-21

## Decision

Use English product name `Breazin`, lowercase code identifier `breazin`, and Chinese display name `呼息`. Maintain three identities:

| Environment | Display | Bundle ID | Scheme | Project UTI | MCP |
| --- | --- | --- | --- | --- | --- |
| development | 呼息 Dev | `com.writish.breazin.dev` | `breazin-dev` | `com.writish.breazin.project.dev` | `breazin-dev:19790` |
| staging | 呼息 Beta | `com.writish.breazin.beta` | `breazin-beta` | `com.writish.breazin.project.beta` | `breazin-beta:19791` |
| production | 呼息 | `com.writish.breazin` | `breazin` | `com.writish.breazin.project` | `breazin:19789` |

Each identity has separate UserDefaults, Keychain service, project directory, Application Support, caches, logs, skill directory, telemetry environment, and update feed. Development has no update feed. New documents use `.breazin`; legacy `.palmier` is read-compatible.

## Consequences

Dev, Beta, and Production can coexist without sharing mutable local state. Release promotion cannot mutate identity after compilation without re-running bundle verification. Product code gains one configuration dependency instead of scattered literals.
