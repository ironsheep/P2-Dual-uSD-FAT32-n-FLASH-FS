# Derived dev image for P2-Dual-uSD-FAT32-n-FLASH-FS.
#
# Bakes the network-heavy installs that previously ran in postCreateCommand on
# EVERY container create (pnut-ts compiler + Claude CLI) into cached layers, so
# rebuilds are cheap and offline.
#
# NOTE: pnut-ts binary baked here is linux-arm64 (Apple Silicon host). Re-point
# the COPY/zip name if building on an x64 host.
#
# No apt packages are installed: the base image already provides unzip/curl, and
# image-tools-mcp no longer needs libtesseract5 at runtime (removed 2026-07-04).
FROM mcr.microsoft.com/devcontainers/javascript-node:24-bookworm

# --- pnut-ts compiler (was: unzip + cp in postCreateCommand) -----------------
COPY pnut-ts-linux-arm64-015500.zip /tmp/pnut-ts.zip
RUN cd /tmp \
    && unzip -o pnut-ts.zip \
    && cp /tmp/pnut-ts-linux-arm64-015500/pnut_ts/pnut-ts /usr/local/bin/pnut-ts \
    && chmod +x /usr/local/bin/pnut-ts \
    && rm -rf /tmp/pnut-ts.zip /tmp/pnut-ts-linux-arm64-015500

# --- Claude CLI (was: curl | bash in postCreateCommand) ----------------------
# Installed as the `node` user so it lands in /home/node/.local/bin.
USER node
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && grep -q '\.local/bin' ~/.bashrc 2>/dev/null \
       || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
USER root
