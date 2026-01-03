{ lib, stdenvNoCC, pkgs }:

# Package for OpenSSH server setup in initramfs
# This includes the OpenSSH binaries, configuration, passwd/group files, and necessary setup

let
  openssh = pkgs.openssh;
in

stdenvNoCC.mkDerivation {
  name = "openssh-initramfs";
  
  buildCommand = ''
    mkdir -p $out/{bin,sbin,libexec,etc/ssh,var/empty/sshd,root/.ssh}
    
    # Copy OpenSSH binaries
    if [ -d ${openssh}/bin ]; then
      cp -r ${openssh}/bin/* $out/bin/ 2>/dev/null || true
    fi
    if [ -d ${openssh}/sbin ]; then
      cp -r ${openssh}/sbin/* $out/sbin/ 2>/dev/null || true
    fi
    if [ -d ${openssh}/libexec ]; then
      cp -r ${openssh}/libexec/* $out/libexec/ 2>/dev/null || true
    fi
    
    # Ensure sshd is in sbin
    if [ -f $out/bin/sshd ] && [ ! -f $out/sbin/sshd ]; then
      mv $out/bin/sshd $out/sbin/sshd
    fi
    
    # Create SSH configuration
    cat > $out/etc/ssh/sshd_config <<'EOF'
# Listen on IPv4 only (Asterinas doesn't support IPv6)
AddressFamily inet
# Bind to specific IP (0.0.0.0 may not work on Asterinas)
ListenAddress 10.0.2.15
Port 22
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PidFile /var/run/sshd.pid
# Disable features that may not work on Asterinas
UseDns no
UsePAM no
LogLevel DEBUG3
EOF
    
    # Create passwd file with sshd user
    cat > $out/etc/passwd <<'EOF'
root:x:0:0:root:/:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
sshd:x:74:74:Privilege-separated SSH:/var/empty/sshd:/usr/sbin/nologin
EOF
    
    # Create group file with sshd group
    cat > $out/etc/group <<'EOF'
root:x:0:
nogroup:x:65534:
sshd:x:74:
EOF
    
    # Create sshd home directory for privilege separation
    chmod 711 $out/var/empty/sshd
    
    # Create empty authorized_keys file
    touch $out/root/.ssh/authorized_keys
    chmod 700 $out/root/.ssh
    chmod 600 $out/root/.ssh/authorized_keys
    
    # Get OpenSSH nix store path for symlink creation
    OPENSSH_STORE_PATH=$(nix-store -q ${openssh} 2>/dev/null || echo "")
    if [ -n "$OPENSSH_STORE_PATH" ]; then
      echo "$OPENSSH_STORE_PATH" > $out/nix-store-path
    fi
  '';
  
  passthru = {
    inherit openssh;
  };
}

