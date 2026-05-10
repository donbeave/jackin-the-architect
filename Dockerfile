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
ARG CAVEMAN_VERSION=1.7.0

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

# Caveman install for all agents this image supports (claude + codex + amp).
# We bypass the root caveman `install.sh` because its per-agent detection
# probes (`command:claude`, `command:codex`, `command:amp`) fail at
# image-build time — every agent CLI is injected by the jackin runtime
# per-container, not baked into this image, so the root installer sees
# "nothing detected" and exits 0 with no files written. Calling each
# component installer directly skips detection and lands the files in
# the image layer. `--with-mcp-shrink` and `--with-init` stay disabled:
# the former needs the runtime claude CLI and is registered through
# `hooks/pre-launch.sh`, the latter writes per-repo IDE rule files into
# $PWD (=`/` at build time).
#
# `bash -e` forces fail-fast inside the upstream installer regardless
# of its own error-handling. `test -f` lines guard against the
# silent-empty-install failure mode that has bitten this build before.
#
# npx-skills side: Codex and Amp use caveman's AGENTS.md-style skills,
# not the Claude plugin marketplace. Both profiles write the universal
# `~/.agents/skills/caveman*` tree. `--yes` makes it non-interactive
# (build context has no TTY); `--global` selects home-scoped installs
# over `$PWD/.agents` (which would be `/.agents` at build time and
# EACCES anyway). `cd "${HOME}"` is defensive — `--global` honors
# `$HOME` regardless, but any future relative-path fallback in the
# skills CLI lands somewhere sensible instead of `/`.
#
# The `&&` chain is the real per-invocation gate: a non-zero exit from
# any `npx skills add` aborts the whole RUN and fails the build. The
# trailing `test -f .../caveman/SKILL.md` is a layer-presence smoke
# check, not a per-profile success marker — the caveman skill tree is
# shared across the codex and amp profiles, so its presence after both
# invocations cannot prove that the amp install specifically ran.
# Trust the npx exit code; do not weaken the chain with `|| true`
# or `;`.
RUN . ~/.profile && \
    mkdir -p "${HOME}/.claude" "${HOME}/.codex" && \
    curl -fsSL "https://raw.githubusercontent.com/JuliusBrussee/caveman/v${CAVEMAN_VERSION}/hooks/install.sh" | bash -e && \
    test -f "${HOME}/.claude/hooks/caveman-statusline.sh" && \
    test -f "${HOME}/.claude/hooks/caveman-activate.js" && \
    test -f "${HOME}/.claude/hooks/caveman-mode-tracker.js" && \
    cd "${HOME}" && \
    echo "[caveman] installing codex profile" && \
    npx -y skills add "JuliusBrussee/caveman#v${CAVEMAN_VERSION}" -a codex --yes --global && \
    echo "[caveman] installing amp profile" && \
    npx -y skills add "JuliusBrussee/caveman#v${CAVEMAN_VERSION}" -a amp --yes --global && \
    test -f "${HOME}/.agents/skills/caveman/SKILL.md"
