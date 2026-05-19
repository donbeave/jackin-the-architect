FROM projectjackin/construct:0.2-trixie@sha256:b6f6ada39797ef32033edb061d473423643df36b1041ca4770b85581a2c7739e

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Baked in by CI from the version tag in the FROM line above so jackin can
# detect published-image staleness at launch time.
ARG CONSTRUCT_VERSION=unknown
LABEL jackin.construct_version=${CONSTRUCT_VERSION}

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
RUN --mount=type=secret,id=github_token,uid=1000,required=false \
    GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true) \
    mise install "rust@${RUST_VERSION}" && \
    mise use -g --pin "rust@${RUST_VERSION}" && \
    . ~/.profile && \
    rustup component add clippy rustfmt rust-analyzer && \
    cargo install --locked cargo-nextest cargo-watch lychee

RUN --mount=type=secret,id=github_token,uid=1000,required=false \
    GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true) \
    mise install "node@${NODE_VERSION}" && \
    mise use -g --pin "node@${NODE_VERSION}"

RUN --mount=type=secret,id=github_token,uid=1000,required=false \
    GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true) \
    mise install "bun@${BUN_VERSION}" && \
    mise use -g --pin "bun@${BUN_VERSION}"

RUN --mount=type=secret,id=github_token,uid=1000,required=false \
    GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true) \
    mise install "just@${JUST_VERSION}" && \
    mise use -g --pin "just@${JUST_VERSION}"

RUN --mount=type=secret,id=github_token,uid=1000,required=false \
    GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true) \
    mise install "opentofu@${OPENTOFU_VERSION}" && \
    mise use -g --pin "opentofu@${OPENTOFU_VERSION}"

# Caveman ≥1.8.0 native opencode plugin needs repoRoot (a local clone);
# curl-pipe can't do it. Shallow-clone at the pinned tag, run bin/install.js.
#
# Agent CLIs aren't on PATH at build time (jackin injects them per-container),
# so auto-detection finds nothing — `--only` forces each target. `--no-mcp-shrink`
# skips registration that needs the claude CLI; preflight.sh re-runs it at
# container start.
#
# Codex and Amp skip the unified installer: it dispatches `skills add ... --yes
# --all` without `--global`, and `--yes` suppresses the scope prompt so the CLI
# defaults to project scope. At build time cwd is `/`, which `USER agent` can't
# write, and the silent failure doesn't fail the overall installer (it only
# exits non-zero when *every* detected agent fails). Explicit `--global` writes
# the canonical tree at `${HOME}/.agents/skills/caveman/`, which is the path
# `hooks/preflight.sh::verify_codex_caveman_skills` checks. The trailing
# `test -f` is the smoke check that catches a future regression.
RUN . ~/.profile && \
    mkdir -p "${HOME}/.claude" "${HOME}/.codex" && \
    git clone --depth 1 --branch "v${CAVEMAN_VERSION}" https://github.com/JuliusBrussee/caveman.git /tmp/caveman && \
    node /tmp/caveman/bin/install.js --only claude --only opencode --no-mcp-shrink && \
    test -f "${HOME}/.claude/hooks/caveman-statusline.sh" && \
    test -f "${HOME}/.claude/hooks/caveman-activate.js" && \
    test -f "${HOME}/.claude/hooks/caveman-mode-tracker.js" && \
    test -f "${HOME}/.config/opencode/plugins/caveman/plugin.js" && \
    cd "${HOME}" && \
    npx -y skills add "JuliusBrussee/caveman#v${CAVEMAN_VERSION}" -a codex --yes --global && \
    npx -y skills add "JuliusBrussee/caveman#v${CAVEMAN_VERSION}" -a amp --yes --global && \
    test -f "${HOME}/.agents/skills/caveman/SKILL.md" && \
    rm -rf /tmp/caveman

# ARG ROLE_GIT_SHA is declared here (after all tool layers) so that a
# per-commit SHA change does not invalidate the expensive tool cache layers above.
ARG ROLE_GIT_SHA=unknown
LABEL jackin.role_git_sha=${ROLE_GIT_SHA}