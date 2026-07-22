# Breazin FAQ

## What is the current status?

Breazin is in active product-foundation development. The repository can be built locally, but no public production release is implied by the source tree or update feeds.

## Which macOS version is required?

The current package targets macOS 26 and Apple Silicon.

## Can Breazin open older projects?

Yes. New projects use `.breazin`; the document registration and loader retain read compatibility for legacy `.palmier` projects.

## Is the local MCP server exposed by default?

No. It is disabled by default and binds only to loopback when explicitly enabled. Development, staging, and production use different service names and ports.

## Are cloud AI features fully independent from the upstream service?

Not yet. Some generation and account flows still use a legacy backend adapter. That dependency is isolated and documented so it can be replaced by Breazin-owned or user-provided providers without another product-wide rename.

## Where should bugs be reported?

Use [GitHub Issues](https://github.com/Writish/breazin/issues). Do not include tokens, project media, credentials, or private logs.
