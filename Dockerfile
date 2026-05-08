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
#
# CAVEMAN_REF pins the upstream caveman repo to a specific commit so a
# `docker build --no-cache` can't pick up a hijacked `main`. Bump after
# auditing https://github.com/JuliusBrussee/caveman/commits/main .
ARG RUST_VERSION=1.95.0
ARG NODE_VERSION=lts
ARG OPENTOFU_VERSION=1.11.6
ARG CAVEMAN_REF=ef6050c5e1848b6880ff47c32ade1a608a64f85e

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
# Each tool gets its own RUN on purpose. Docker's layer cache is
# sequential (a busted layer invalidates everything downstream), but
# changing only a later tool (e.g. a future cargo crate) does NOT
# invalidate the earlier-RUN layers above it, and a `--no-cache`
# rebuild still reuses the apt-installed system packages above.
# Listing earlier-stable tools first (Rust → Node → OpenTofu →
# caveman) maximizes how many layers stay cached on the most common
# bumps. A merged single-RUN install would force every tool to
# reinstall on every bump.
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

# Caveman install for the agents this image supports (claude + codex).
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
# npx-skills side: Codex uses caveman's AGENTS.md-style skills, not the
# Claude plugin marketplace. The skills install writes the universal
# `~/.agents/skills/caveman*` tree. `--yes` makes it non-interactive
# (build context has no TTY); `--global` selects home-scoped installs
# over `$PWD/.agents` (which would be `/.agents` at build time and
# EACCES anyway). `cd ${HOME}` is defensive — `--global` honors `$HOME`
# regardless, but any future relative-path fallback in the skills CLI
# lands somewhere sensible instead of `/`. The `-a amp` profile is
# intentionally not installed because `jackin.role.toml` only declares
# `agents = ["claude", "codex"]`; installing amp skills would be dead
# weight in the layer.
#
# Two components from the root installer are intentionally NOT run here:
#   * `--with-mcp-shrink` — `claude mcp add …` needs the runtime-injected
#     claude CLI; we register caveman-shrink at runtime in
#     `scripts/pre-launch.sh` instead.
#   * `--with-init` — writes per-repo IDE rule files (AGENTS.md,
#     .clinerules/, .cursorrules, .github/copilot-instructions.md) into
#     `$PWD`. At build time `$PWD=/` so it would either EACCES or
#     pollute the image root with files the runtime workspace mount
#     hides anyway. Per-repo concern, not per-image.
#
# CAVEMAN_REF pins both the install.sh and the skills source ref to the
# same commit. `bash -e` forces fail-fast on the upstream installer
# regardless of its own error-handling. The trailing `test -f` lines
# fail the build if upstream changes a script and it silently stops
# writing files — the previous breakage (root installer exit 0 with
# empty `~/.claude/`) went undetected for a full release because
# nothing asserted the result.
RUN . ~/.profile && \
    mkdir -p "${HOME}/.claude" "${HOME}/.codex" && \
    curl -fsSL "https://raw.githubusercontent.com/JuliusBrussee/caveman/${CAVEMAN_REF}/hooks/install.sh" | bash -e && \
    test -f "${HOME}/.claude/hooks/caveman-statusline.sh" && \
    test -f "${HOME}/.claude/hooks/caveman-activate.js" && \
    test -f "${HOME}/.claude/hooks/caveman-mode-tracker.js" && \
    cd "${HOME}" && \
    npx -y skills add "JuliusBrussee/caveman#${CAVEMAN_REF}" -a codex --yes --global && \
    test -f "${HOME}/.agents/skills/caveman/SKILL.md"
