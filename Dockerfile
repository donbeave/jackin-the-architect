FROM projectjackin/construct:trixie

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# CAVEMAN_VERSION must be a release tag from
# https://github.com/JuliusBrussee/caveman/releases — never `main`,
# never a raw commit SHA. The `skills` CLI's shallow git-clone fetch
# resolves tags but not arbitrary SHAs.
ARG RUST_VERSION=1.95.0
ARG NODE_VERSION=24.15.0
ARG BUN_VERSION=1.3.13
ARG JUST_VERSION=1.50.0
ARG OPENTOFU_VERSION=1.11.6
ARG CAVEMAN_VERSION=1.8.2

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

# Per-tool RUNs are deliberate: bumping one ARG only invalidates that
# tool's layer. Trips hadolint DL3059; the cache reuse is worth it.
#
# Rust dev tools share the Rust RUN — rustup components and the
# cargo-installed binaries are toolchain-specific. `. ~/.profile`
# activates mise so `rustup` and `cargo` resolve via its shims.
RUN mise install "rust@${RUST_VERSION}" && \
    mise use -g --pin "rust@${RUST_VERSION}" && \
    . ~/.profile && \
    rustup component add clippy rustfmt rust-analyzer && \
    cargo install --locked cargo-nextest cargo-watch

RUN mise install "node@${NODE_VERSION}" && \
    mise use -g --pin "node@${NODE_VERSION}"

RUN mise install "bun@${BUN_VERSION}" && \
    mise use -g --pin "bun@${BUN_VERSION}"

RUN mise install "just@${JUST_VERSION}" && \
    mise use -g --pin "just@${JUST_VERSION}"

RUN mise install "opentofu@${OPENTOFU_VERSION}" && \
    mise use -g --pin "opentofu@${OPENTOFU_VERSION}"

# Caveman ≥1.8.0 uses a unified Node installer (bin/install.js) dispatched
# from install.sh at the repo root. The old hooks/install.sh path is gone.
# v1.8.0 also adds native opencode plugin support (no separate npx-skills step).
#
# Agent CLIs are not present at image-build time (jackin injects them
# per-container), so auto-detection would find nothing. `--only` forces
# install for each agent regardless. `--no-mcp-shrink` disables the MCP
# server that needs a running agent CLI. Init defaults to off. The trailing
# `test -f` lines are layer-presence smoke checks — they catch the
# silent-empty-install failure mode that has bitten this build before.
RUN . ~/.profile && \
    mkdir -p "${HOME}/.claude" "${HOME}/.codex" && \
    curl -fsSL "https://raw.githubusercontent.com/JuliusBrussee/caveman/v${CAVEMAN_VERSION}/install.sh" | bash -s -- --only claude --only codex --only amp --only opencode --no-mcp-shrink && \
    test -f "${HOME}/.claude/hooks/caveman-statusline.sh" && \
    test -f "${HOME}/.claude/hooks/caveman-activate.js" && \
    test -f "${HOME}/.claude/hooks/caveman-mode-tracker.js" && \
    test -f "${HOME}/.config/opencode/plugins/caveman/plugin.js" && \
    cd "${HOME}" && \
    echo "[caveman] installing codex profile" && \
    npx -y skills add "JuliusBrussee/caveman#v${CAVEMAN_VERSION}" -a codex --yes --global && \
    echo "[caveman] installing amp profile" && \
    npx -y skills add "JuliusBrussee/caveman#v${CAVEMAN_VERSION}" -a amp --yes --global && \
    test -f "${HOME}/.agents/skills/caveman/SKILL.md"
