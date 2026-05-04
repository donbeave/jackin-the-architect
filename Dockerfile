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
