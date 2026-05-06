#!/bin/bash
# Architect pre-launch hook. jackin's runtime entrypoint runs this
# script (via `[hooks].pre_launch` in jackin.role.toml) after the
# agent CLI is installed and plugins are bootstrapped, but before the
# agent itself launches.
#
# Why a runtime hook and not an image-build step: every command in
# here needs the claude CLI, and the claude CLI is injected per
# container by jackin's derived-image build (Agent::install_block in
# jackin's src/agent/mod.rs), not baked into the published architect
# image. Trying to run `claude mcp add …` at architect-image build
# time silently no-ops because the binary is not on PATH yet.
set -euo pipefail

log() {
    printf '[architect-pre-launch] %s\n' "$*"
}

# ── caveman-shrink MCP middleware proxy ───────────────────────────────
#
# caveman-shrink wraps another MCP server's stdio and caveman-compresses
# the responses before they reach the agent — used to cut the token
# cost of verbose MCP servers (filesystem, github, search, etc.). By
# itself the registration is a placeholder that spawns the upstream
# package; you wire it against a specific server later by editing the
# `mcpServers` entry to put the real upstream after the caveman-shrink
# arg list, e.g.:
#
#   {
#     "mcpServers": {
#       "fs-shrunk": {
#         "command": "npx",
#         "args": ["caveman-shrink", "npx",
#                  "@modelcontextprotocol/server-filesystem", "/path"]
#       }
#     }
#   }
#
# Reference: https://github.com/JuliusBrussee/caveman/tree/main/mcp-servers/caveman-shrink
register_caveman_shrink() {
    if ! command -v claude >/dev/null 2>&1; then
        log "claude CLI not on PATH — skipping caveman-shrink registration"
        return 0
    fi

    # Idempotent: skip on subsequent container starts. `claude mcp get`
    # exits non-zero if the entry doesn't exist; redirect to keep the
    # "no server found" message out of the launch banner.
    if claude mcp get caveman-shrink >/dev/null 2>&1; then
        return 0
    fi

    log "registering caveman-shrink MCP server"
    claude mcp add caveman-shrink -- npx -y caveman-shrink
}

register_caveman_shrink
