# the-architect

`the-architect` is the jackin agent for developing [jackin](https://github.com/donbeave/jackin) itself.

It provides the Rust development environment needed to build and test the jackin CLI.

## Usage

```sh
jackin load the-architect
```

## Contract

- Final Dockerfile stage must literally be `FROM projectjackin/construct:trixie`
- Plugins are declared in `jackin.role.toml`

## Environment

- **Rust** (latest stable via mise) with clippy and rustfmt
- **cargo-nextest** — fast test runner
- **cargo-watch** — file watcher for continuous builds/tests
- **rust-best-practices** — Rust review, API design, testing, docs, Clippy/rustfmt, and maintainability guidance from `tailrocks/rust-best-practices`
- **Node.js** LTS (via mise)
- System build tools (`build-essential`, `libssl-dev`, `pkg-config`, `cmake`)

Shared shell/runtime tools come from `projectjackin/construct:trixie`.

## Plugin Trust

- `rust-best-practices@tailrocks-marketplace` is installed from `https://github.com/tailrocks/rust-best-practices.git` via `tailrocks/tailrocks-marketplace`. The plugin is source-readable, Apache-2.0 licensed, and scoped to Rust engineering guidance rather than executable runtime hooks.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
