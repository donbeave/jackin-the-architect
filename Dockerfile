FROM projectjackin/construct:trixie

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pinned tool versions. Keep these at the top of the file so the diff for a
# bump is one line per tool, and so they are easy to grep / override at
# build time via `docker build --build-arg RUST_VERSION=...`.
#
# RUST_VERSION must stay in sync with:
#   - the `rust:<version>-trixie` pin in the construct base image
#     (jackin/docker/construct/Dockerfile)
#   - `rust-toolchain.toml` in the jackin/ repo
# so all three layers agree on the toolchain operators get at runtime.
ARG RUST_VERSION=1.95.0
ARG NODE_VERSION=lts
ARG OPENTOFU_VERSION=1.11.6

# Install system packages needed for Rust builds
RUN sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    openssl \
    pkg-config \
    cmake && \
    sudo apt-get autoremove -y && \
    sudo rm -rf /var/lib/apt/* \
               /var/cache/apt/* \
               /tmp/*

USER agent

ENV MISE_TRUSTED_CONFIG_PATHS=/workspace

# Toolchain installs (versions pinned via the ARGs at the top of the file).
#
# Each tool gets its own RUN on purpose. Docker's layer cache keys on
# the literal RUN command and the ARGs it references, so bumping (for
# example) RUST_VERSION via --build-arg invalidates only the Rust layer
# and leaves the cached Node and OpenTofu layers intact. A merged
# single-RUN install would force every tool to reinstall on every bump.
#
# This intentionally trips docker:S7031 / hadolint DL3059 ("merge
# consecutive RUN instructions"); the per-tool cache reuse is worth
# more here than the saved-layer-count the rule optimizes for.

# Rust toolchain + dev tools (kept together because the dev tools are
# rust-version-specific: rustup components and cargo-installed binaries
# are tied to the toolchain that just got pinned). The `. ~/.profile`
# activates mise so `rustup` and `cargo` resolve via its shims.
RUN mise install "rust@${RUST_VERSION}" && \
    mise use -g --pin "rust@${RUST_VERSION}" && \
    . ~/.profile && \
    rustup component add clippy rustfmt rust-analyzer && \
    cargo install --locked cargo-nextest cargo-watch

RUN mise install "node@${NODE_VERSION}" && \
    mise use -g --pin "node@${NODE_VERSION}"

RUN mise install "opentofu@${OPENTOFU_VERSION}" && \
    mise use -g --pin "opentofu@${OPENTOFU_VERSION}"

# Caveman install for both agents this image supports (claude + codex).
# We bypass the root caveman `install.sh` because its per-agent detection
# probes (`command:claude`, `command:codex`) fail at image-build time —
# both agent CLIs are injected by the jackin runtime per-container, not
# baked into this image, so the root installer sees "nothing detected"
# and exits 0 with no files written. Calling each component installer
# directly skips detection and lands the files in the image layer.
#
# Claude side: `hooks/install.sh` writes `~/.claude/hooks/{6 files}` and
# patches `~/.claude/settings.json` with SessionStart/UserPromptSubmit
# hooks + the statusline badge. The `caveman@caveman` plugin itself is
# already declared in `jackin.role.toml` and gets installed at runtime
# by jackin's `install-claude-plugins.sh`, so we don't repeat it here.
#
# Codex side: caveman ships as a set of AGENTS.md-style skills, not as a
# Claude plugin. `npx skills add … -a codex --global` writes them to
# `~/.agents/skills/caveman*`, which is the location the codex CLI looks
# up at runtime. `--yes` makes it non-interactive (build context has no
# TTY); `--global` selects `~/.agents/skills/` over `$PWD/.agents/`
# (which would be `/.agents` at build time and EACCES anyway). `cd
# /home/agent` is defensive — `--global` honors `$HOME` regardless, but
# any future relative-path fallback in the skills CLI lands somewhere
# sensible instead of `/`.
#
# Two components from the root installer are intentionally NOT run here:
#   * `--with-mcp-shrink` — `claude mcp add …` needs the runtime-injected
#     claude CLI; if we want this proxy it belongs in a runtime hook.
#   * `--with-init` — writes per-repo IDE rule files (AGENTS.md,
#     .clinerules/, .cursorrules, .github/copilot-instructions.md) into
#     `$PWD`. At build time `$PWD=/` so it would either EACCES or
#     pollute the image root with files the runtime workspace mount
#     hides anyway. Per-repo concern, not per-image.
#
# `test -f` / `test -d` lines fail the build if upstream changes a
# script and it silently stops writing files — the previous breakage
# (root installer exit 0 with empty `~/.claude/`) went undetected for a
# full release because nothing asserted the result.
RUN . ~/.profile && \
    mkdir -p /home/agent/.claude /home/agent/.codex && \
    curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/hooks/install.sh | bash && \
    test -f /home/agent/.claude/hooks/caveman-statusline.sh && \
    test -f /home/agent/.claude/hooks/caveman-activate.js && \
    test -f /home/agent/.claude/hooks/caveman-mode-tracker.js && \
    cd /home/agent && \
    npx -y skills add JuliusBrussee/caveman -a codex --yes --global && \
    test -d /home/agent/.agents/skills/caveman
