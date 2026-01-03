#!/bin/sh

# SPDX-License-Identifier: MPL-2.0

# Don't use set -e here, we want to see all errors
set +e

echo "=== Testing SSH daemon ==="

# Check if sshd exists
if [ ! -f /usr/sbin/sshd ]; then
    echo "Error: sshd not found at /usr/sbin/sshd"
    exit 1
fi

# Create necessary directories
mkdir -p /var/empty
mkdir -p /var/run
mkdir -p /etc/ssh

# Generate host keys if they don't exist
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH host keys..."
    /usr/bin/ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" -q
    echo "Generated RSA host key"
fi

if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
    /usr/bin/ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N "" -q
    echo "Generated ECDSA host key"
fi

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    /usr/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
    echo "Generated ED25519 host key"
fi

# Display network information
echo ""
echo "=== Network Information ==="
ifconfig 2>/dev/null || ip addr 2>/dev/null || echo "Network tools not available"
echo ""

# Start sshd in foreground with debug output
echo "=== Starting SSH daemon ==="
echo "SSH daemon will listen on port 22"
echo "Default VM IP: 10.0.2.15 (QEMU user networking)"
echo ""
echo "To connect from host:"
echo "  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@10.0.2.15"
echo ""
echo "Note: Password authentication may not work. Use key-based auth or test without password."
echo ""

# Test sshd configuration first
echo "Testing sshd configuration..."
/usr/sbin/sshd -t -f /etc/ssh/sshd_config 2>&1
CONFIG_TEST_RESULT=$?
if [ $CONFIG_TEST_RESULT -ne 0 ]; then
    echo "Warning: sshd configuration test returned error code $CONFIG_TEST_RESULT"
    echo "Continuing anyway to see what happens..."
else
    echo "sshd configuration is valid"
fi
echo ""

# Verify sshd-session exists and is executable
if [ ! -f /usr/libexec/sshd-session ]; then
    echo "Error: sshd-session not found at /usr/libexec/sshd-session"
    exit 1
fi
if [ ! -x /usr/libexec/sshd-session ]; then
    echo "Warning: sshd-session is not executable, fixing permissions..."
    chmod +x /usr/libexec/sshd-session
fi

# Verify all libexec files are executable
chmod +x /usr/libexec/* 2>/dev/null || true

# Create symlink for nix store path that sshd expects
# sshd binary has hardcoded nix store paths, so we need to find and create symlinks
# Extract the path from sshd binary using strings command
NIX_OPENSSH_PATH=$(strings /usr/sbin/sshd 2>/dev/null | grep -E "^/nix/store/[^/]+-openssh.*/libexec/sshd-session$" | head -1 | sed 's|/libexec/sshd-session$||')
if [ -z "$NIX_OPENSSH_PATH" ]; then
    # Fallback: try to find any openssh path in /nix/store
    NIX_OPENSSH_PATH=$(find /nix/store -maxdepth 1 -type d -name "*-openssh*" 2>/dev/null | head -1)
fi

if [ -n "$NIX_OPENSSH_PATH" ] && [ ! -d "$NIX_OPENSSH_PATH/libexec" ]; then
    echo "Creating nix store symlink for openssh..."
    echo "Detected OpenSSH path: $NIX_OPENSSH_PATH"
    mkdir -p "$NIX_OPENSSH_PATH"
    ln -sfn /usr/libexec "$NIX_OPENSSH_PATH/libexec"
    echo "Symlink created: $NIX_OPENSSH_PATH/libexec -> /usr/libexec"
    ls -la "$NIX_OPENSSH_PATH/libexec/sshd-session" || echo "Warning: symlink verification failed"
elif [ -z "$NIX_OPENSSH_PATH" ]; then
    echo "Warning: Could not detect OpenSSH nix store path, sshd may fail to find sshd-session"
fi

# Disable seccomp sandbox (Asterinas doesn't support seccomp)
# OpenSSH doesn't have a config option for this, but we can try to disable it
# via environment variable or by patching the behavior
export SSH_SANDBOX_DISABLE=1 2>/dev/null || true

# Start sshd in foreground mode with maximum debug output
# -D: Don't detach (run in foreground)
# -d: Debug mode (can be used multiple times for more verbosity)
# -e: Write debug logs to stderr
# -f: Use specified config file
# Note: seccomp sandbox may fail on Asterinas, but sshd should continue
echo "Starting sshd with debug output..."
echo "Note: If seccomp sandbox fails, sshd may still work without it"
exec /usr/sbin/sshd -D -ddd -e -f /etc/ssh/sshd_config

