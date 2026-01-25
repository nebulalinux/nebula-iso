#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALLER_DIR="$ROOT_DIR/nebula-installer"
ISO_DIR="$ROOT_DIR/nebula-iso"
BIN_SRC="$INSTALLER_DIR/target/release/nebula"
BIN_DEST="$ISO_DIR/airootfs/usr/bin/nebula-installer"
SDDM_THEME_SRC="$ROOT_DIR/packages/nebula-sddm"
SDDM_THEME_DEST="$ISO_DIR/airootfs/usr/share/sddm/themes/nebula-sddm"
PLYMOUTH_LUKS_SRC="$ROOT_DIR/packages/nebula-luks"
PLYMOUTH_LUKS_DEST="$ISO_DIR/airootfs/usr/share/plymouth/themes/nebula-luks"
PLYMOUTH_SPLASH_SRC="$ROOT_DIR/packages/nebula-splash"
PLYMOUTH_SPLASH_DEST="$ISO_DIR/airootfs/usr/share/plymouth/themes/nebula-splash"
GRUB_THEME_SRC="$ROOT_DIR/packages/nebula-vimix-grub/theme"
GRUB_THEME_DEST="$ISO_DIR/grub/themes/nebula-vimix-grub"
GRUB_THEME_DEST_ROOTFS="$ISO_DIR/airootfs/usr/share/grub/themes/nebula-vimix-grub"
LOCAL_PKG_BUILDER="$ROOT_DIR/nebula-pkgs/build-local.sh"
NEBULA_GPG_SRC="$ROOT_DIR/nebula-repo.gpg"
NEBULA_GPG_DEST="$ISO_DIR/airootfs/usr/share/nebula/nebula-repo.gpg"
VERSION_FILE="$ISO_DIR/VERSION"
OS_RELEASE_PATH="$ISO_DIR/airootfs/etc/os-release"
OFFLINE_LIST="$ISO_DIR/build/offline-packages.txt"
OFFLINE_RESOLVED="$ISO_DIR/build/offline-packages.resolved.txt"
OFFLINE_REPO="$ISO_DIR/airootfs/opt/nebula-repo"
OFFLINE_LOCAL="$ISO_DIR/offline-local"
OFFLINE_EXCLUDE=""
NEBULA_GPG_SRC_OFFLINE="$OFFLINE_REPO/nebula-repo.gpg"
PACMAN_OFFLINE_CONF="$(mktemp)"
PACMAN_CONF_PATH="$ISO_DIR/pacman.conf"
PACMAN_CONF_BACKUP=""
MIRRORLIST_NEBULA="/etc/pacman.d/mirrorlist-nebula"
ISO_MIRRORLIST_NEBULA="$ISO_DIR/airootfs/etc/pacman.d/mirrorlist-nebula"
OWNER_USER="${SUDO_USER:-$(id -un)}"
OWNER_GROUP="$(id -gn "$OWNER_USER" 2>/dev/null || echo "$OWNER_USER")"
ENV_FILE="$ROOT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [[ -f "$VERSION_FILE" ]]; then
  VERSION=$(head -n 1 "$VERSION_FILE" | tr -d '[:space:]')
else
  echo "Error: Missing ISO version file at $VERSION_FILE" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  echo "Error: ISO version file is empty: $VERSION_FILE" >&2
  exit 1
fi

cleanup() {
  rm -f "$PACMAN_OFFLINE_CONF"
  if [[ -n "$OFFLINE_EXCLUDE" ]]; then
    rm -f "$OFFLINE_EXCLUDE"
  fi
  if [[ -n "$PACMAN_CONF_BACKUP" && -f "$PACMAN_CONF_BACKUP" ]]; then
    mv -f "$PACMAN_CONF_BACKUP" "$PACMAN_CONF_PATH"
  fi
  if [[ -f "$PACMAN_CONF_PATH" ]]; then
    chown "$OWNER_USER:$OWNER_GROUP" "$PACMAN_CONF_PATH" || true
  fi
}
trap cleanup EXIT

if [[ -n "${NEBULA_BUILD_JOBS:-}" ]]; then
  cargo build --release -j "$NEBULA_BUILD_JOBS" --manifest-path "$INSTALLER_DIR/Cargo.toml"
else
  cargo build --release --manifest-path "$INSTALLER_DIR/Cargo.toml"
fi

if [[ "${NEBULA_SKIP_LOCAL_PKG_BUILD:-0}" != "1" && -x "$LOCAL_PKG_BUILDER" ]]; then
  "$LOCAL_PKG_BUILDER" nebula-vimix-grub || \
    echo "Warning: Failed to build local nebula-vimix-grub package." >&2
  "$LOCAL_PKG_BUILDER" nebula-luks || \
    echo "Warning: Failed to build local nebula-luks package." >&2
  "$LOCAL_PKG_BUILDER" nebula-splash || \
    echo "Warning: Failed to build local nebula-splash package." >&2
fi
install -Dm755 "$BIN_SRC" "$BIN_DEST"
mkdir -p "$(dirname "$NEBULA_GPG_DEST")"
if [[ -f "$NEBULA_GPG_SRC" ]]; then
  install -Dm644 "$NEBULA_GPG_SRC" "$NEBULA_GPG_DEST"
elif [[ -f "$NEBULA_GPG_SRC_OFFLINE" ]]; then
  install -Dm644 "$NEBULA_GPG_SRC_OFFLINE" "$NEBULA_GPG_DEST"
elif command -v curl >/dev/null 2>&1; then
  if ! curl -fsSL https://pkgs.nebulalinux.com/nebula-repo.gpg -o "$NEBULA_GPG_DEST"; then
    echo "Warning: Failed to download nebula-repo.gpg key." >&2
    rm -f "$NEBULA_GPG_DEST"
  fi
else
  echo "Warning: curl not found; skipping nebula-repo.gpg key download." >&2
fi
if [[ -d "$SDDM_THEME_SRC" ]]; then
  mkdir -p "$(dirname "$SDDM_THEME_DEST")"
  rm -rf "$SDDM_THEME_DEST"
  cp -a "$SDDM_THEME_SRC" "$SDDM_THEME_DEST"
else
  echo "Warning: SDDM theme not found at $SDDM_THEME_SRC" >&2
fi

if [[ -d "$PLYMOUTH_LUKS_SRC" ]]; then
  mkdir -p "$(dirname "$PLYMOUTH_LUKS_DEST")"
  rm -rf "$PLYMOUTH_LUKS_DEST"
  cp -a "$PLYMOUTH_LUKS_SRC" "$PLYMOUTH_LUKS_DEST"
else
  echo "Warning: Plymouth LUKS theme not found at $PLYMOUTH_LUKS_SRC" >&2
fi

if [[ -d "$PLYMOUTH_SPLASH_SRC" ]]; then
  mkdir -p "$(dirname "$PLYMOUTH_SPLASH_DEST")"
  rm -rf "$PLYMOUTH_SPLASH_DEST"
  cp -a "$PLYMOUTH_SPLASH_SRC" "$PLYMOUTH_SPLASH_DEST"
else
  echo "Warning: Plymouth splash theme not found at $PLYMOUTH_SPLASH_SRC" >&2
fi

if [[ -d "$GRUB_THEME_SRC" ]]; then
  mkdir -p "$(dirname "$GRUB_THEME_DEST")"
  rm -rf "$GRUB_THEME_DEST"
  cp -a "$GRUB_THEME_SRC" "$GRUB_THEME_DEST"

  mkdir -p "$(dirname "$GRUB_THEME_DEST_ROOTFS")"
  rm -rf "$GRUB_THEME_DEST_ROOTFS"
  cp -a "$GRUB_THEME_SRC" "$GRUB_THEME_DEST_ROOTFS"
else
  echo "Warning: GRUB theme not found at $GRUB_THEME_SRC" >&2
fi

if [[ -f "$MIRRORLIST_NEBULA" ]]; then
  mkdir -p "$(dirname "$ISO_MIRRORLIST_NEBULA")"
  cp -f "$MIRRORLIST_NEBULA" "$ISO_MIRRORLIST_NEBULA"
else
  echo "Warning: $MIRRORLIST_NEBULA not found; falling back to default mirrorlist." >&2
fi

mkdir -p "$ISO_DIR/airootfs/etc"
cat > "$OS_RELEASE_PATH" <<EOF
NAME=Nebula
PRETTY_NAME="Nebula ${VERSION}"
ID=nebula
ID_LIKE=arch
VERSION_ID=${VERSION}
VERSION="${VERSION}"
EOF

WORK_DIR="$ISO_DIR/work"
OUT_DIR="$ISO_DIR/out"

rm -rf "$WORK_DIR" "$OUT_DIR"

if [[ -f "$OFFLINE_RESOLVED" ]]; then
  OFFLINE_LIST="$OFFLINE_RESOLVED"
fi

if [[ "${NEBULA_SKIP_OFFLINE_REPO:-0}" == "1" ]]; then
  echo "Skipping offline repo build (NEBULA_SKIP_OFFLINE_REPO=1)"
elif [[ -f "$OFFLINE_LIST" ]] || [[ -d "$OFFLINE_LOCAL" ]]; then
  mkdir -p "$OFFLINE_REPO"
  if [[ -f "$OFFLINE_LIST" ]]; then
    mapfile -t OFFLINE_PACKAGES < <(grep -Ev '^[[:space:]]*(#|$)' "$OFFLINE_LIST")
  else
    OFFLINE_PACKAGES=()
  fi
  if [[ ${#OFFLINE_PACKAGES[@]} -gt 0 ]]; then
    cat > "$PACMAN_OFFLINE_CONF" <<'EOF'
[options]
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5
Architecture = auto

[core]
Include = /etc/pacman.d/mirrorlist-nebula

[extra]
Include = /etc/pacman.d/mirrorlist-nebula

[multilib]
Include = /etc/pacman.d/mirrorlist-nebula

[nebula]
SigLevel = Required DatabaseOptional
Server = https://pkgs.nebulalinux.com/stable/$arch
EOF
    if [[ -f "$PACMAN_CONF_PATH" ]]; then
      PACMAN_CONF_BACKUP="$(mktemp)"
      cp -f "$PACMAN_CONF_PATH" "$PACMAN_CONF_BACKUP"
      sed -i "s|file:///opt/nebula-repo|file://$OFFLINE_REPO|g" "$PACMAN_CONF_PATH"
    fi
  fi

  if [[ -d "$OFFLINE_LOCAL" ]]; then
    shopt -s nullglob
    OFFLINE_EXCLUDE="$(mktemp)"
    for pkg in "$OFFLINE_LOCAL"/*.pkg.tar.zst; do
      if command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$pkg" -O .PKGINFO 2>/dev/null | awk -F ' = ' '/^pkgname = / {print $2; exit}' \
          >> "$OFFLINE_EXCLUDE" || true
      fi
    done
    for pkg in "$OFFLINE_LOCAL"/*.pkg.tar.zst; do
      cp -f "$pkg" "$OFFLINE_REPO/"
    done
    shopt -u nullglob
  fi

  if [[ ${#OFFLINE_PACKAGES[@]} -gt 0 ]]; then
    if [[ -n "$OFFLINE_EXCLUDE" && -s "$OFFLINE_EXCLUDE" ]]; then
      mapfile -t OFFLINE_PACKAGES < <(printf '%s\n' "${OFFLINE_PACKAGES[@]}" | grep -vxFf "$OFFLINE_EXCLUDE")
    fi
    if [[ ${#OFFLINE_PACKAGES[@]} -gt 0 ]]; then
      pacman -Syw --noconfirm --cachedir "$OFFLINE_REPO" --config "$PACMAN_OFFLINE_CONF" \
        "${OFFLINE_PACKAGES[@]}"
    fi
  fi

  if compgen -G "$OFFLINE_REPO/*.pkg.tar.zst" > /dev/null; then
    repo-add "$OFFLINE_REPO/nebula-offline.db.tar.gz" "$OFFLINE_REPO"/*.pkg.tar.zst
    if ! compgen -G "$OFFLINE_REPO/linux-firmware-*.pkg.tar.zst" > /dev/null; then
      echo "Warning: linux-firmware not found in offline repo." >&2
    fi
  fi
fi

if [[ -n "${NEBULA_BUILD_JOBS:-}" ]]; then
  export NEBULA_BUILD_JOBS
  export XZ_OPT="--threads=${NEBULA_BUILD_JOBS}"
  export ZSTD_NBTHREADS="${NEBULA_BUILD_JOBS}"
  echo "Exporting NEBULA_BUILD_JOBS=${NEBULA_BUILD_JOBS} for mkarchiso"
  echo "Exporting XZ_OPT=${XZ_OPT}"
  echo "Exporting ZSTD_NBTHREADS=${ZSTD_NBTHREADS}"
fi

mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$ISO_DIR"

if [[ -f "$PACMAN_CONF_PATH" ]]; then
  chown "$OWNER_USER:$OWNER_GROUP" "$PACMAN_CONF_PATH"
fi

rm -rf "$GRUB_THEME_DEST" "$GRUB_THEME_DEST_ROOTFS"
rm -rf "$SDDM_THEME_DEST"
rm -rf "$PLYMOUTH_LUKS_DEST" "$PLYMOUTH_SPLASH_DEST"
