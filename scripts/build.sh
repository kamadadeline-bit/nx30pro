#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/work/openwrt"
LEDE_REPO="${LEDE_REPO:-https://github.com/coolsnowwolf/lede.git}"
LEDE_REF="${LEDE_REF:-master}"
UA3F_REF="${UA3F_REF:-v3.7.0}"
OPENCLASH_REF="${OPENCLASH_REF:-master}"
INCLUDE_MIHOMO_CORE="${INCLUDE_MIHOMO_CORE:-false}"

mkdir -p "$ROOT_DIR/work"
rm -rf "$BUILD_DIR" "$ROOT_DIR/work/OpenClash-src"
git clone --depth 1 --branch "$LEDE_REF" "$LEDE_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"

# Hard guard: fail before compilation if this LEDE ref does not support NX30 Pro.
grep -q 'TARGET_DEVICES += h3c_magic-nx30-pro' target/linux/mediatek/image/filogic.mk || {
  echo 'ERROR: selected LEDE ref has no h3c_magic-nx30-pro device profile.' >&2
  exit 1
}

./scripts/feeds update -a
./scripts/feeds install -a

# Pin UA3F to an official release tag by default; package lives under openwrt/.
git clone --depth 1 --branch "$UA3F_REF" https://github.com/SunBK201/UA3F.git package/UA3F

# Add the upstream OpenClash LuCI package to this fresh source tree.
git clone --depth 1 --branch "$OPENCLASH_REF" https://github.com/vernesong/OpenClash.git "$ROOT_DIR/work/OpenClash-src"
test -f "$ROOT_DIR/work/OpenClash-src/luci-app-openclash/Makefile" || {
  echo 'ERROR: OpenClash package Makefile not found in selected ref.' >&2
  exit 1
}
rm -rf package/luci-app-openclash
cp -a "$ROOT_DIR/work/OpenClash-src/luci-app-openclash" package/luci-app-openclash

cp "$ROOT_DIR/configs/packages.config" .config
make defconfig

# Assert the target profile and the requested modules actually survive Kconfig.
grep -qx 'CONFIG_TARGET_mediatek_filogic_DEVICE_h3c_magic-nx30-pro=y' .config || {
  echo 'ERROR: NX30 Pro profile was not selected after make defconfig.' >&2
  exit 1
}
for package in \
  ua3f kmod-nft-queue kmod-nft-tproxy kmod-sched-bpf libubox-lua \
  kmod-nft-core kmod-nfnetlink-queue kmod-nf-tproxy kmod-nf-conntrack \
  kmod-nf-conntrack-netlink kmod-sched-core luci-app-openclash dnsmasq-full \
  kmod-tun kmod-inet-diag; do
  if ! grep -qx "CONFIG_PACKAGE_${package}=y" .config; then
    echo "ERROR: required package ${package} is missing or was dropped by Kconfig." >&2
    exit 1
  fi
done

# Install safe first-boot defaults into the rootfs overlay.
mkdir -p files/etc/uci-defaults
cp "$ROOT_DIR/files/etc/uci-defaults/98-nx30pro-safe-services" files/etc/uci-defaults/

# Optionally preinstall a verified Mihomo Meta core. This does not fix runtime OOM.
if [[ "$INCLUDE_MIHOMO_CORE" == "true" ]]; then
  echo 'Fetching latest stable Mihomo ARM64 release asset...'
  RELEASE_JSON="$ROOT_DIR/work/mihomo-release.json"
  curl -fsSL --retry 3 https://api.github.com/repos/MetaCubeX/mihomo/releases/latest -o "$RELEASE_JSON"
  read -r ASSET_URL EXPECTED_DIGEST ASSET_NAME < <(python3 - "$RELEASE_JSON" <<'PY'
import json, re, sys
release = json.load(open(sys.argv[1], encoding="utf-8"))
assets = release.get("assets", [])
choices = [
    asset for asset in assets
    if re.fullmatch(r"mihomo-linux-arm64-v[^/]+\.gz", asset.get("name", ""))
]
if not choices:
    raise SystemExit("No stable mihomo-linux-arm64-v*.gz asset found in latest stable release")
asset = sorted(choices, key=lambda item: item["name"])[-1]
print(asset.get("browser_download_url", ""), asset.get("digest") or "", asset.get("name", ""))
PY
  )
  test -n "$ASSET_URL" || { echo 'ERROR: Mihomo asset URL is empty.' >&2; exit 1; }
  case "$EXPECTED_DIGEST" in
    sha256:*) EXPECTED_DIGEST="${EXPECTED_DIGEST#sha256:}" ;;
    *) echo 'ERROR: Mihomo asset has no GitHub SHA-256 digest; refusing to embed an unverified binary.' >&2; exit 1 ;;
  esac

  CORE_GZ="$ROOT_DIR/work/mihomo.gz"
  curl -fL --retry 3 "$ASSET_URL" -o "$CORE_GZ"
  ACTUAL_DIGEST="$(sha256sum "$CORE_GZ" | awk '{print $1}')"
  [[ "$ACTUAL_DIGEST" == "$EXPECTED_DIGEST" ]] || {
    echo 'ERROR: Mihomo SHA-256 mismatch.' >&2
    exit 1
  }
  gzip -t "$CORE_GZ"
  mkdir -p files/etc/openclash/core
  gzip -dc "$CORE_GZ" > files/etc/openclash/core/clash_meta
  chmod 0755 files/etc/openclash/core/clash_meta
  file files/etc/openclash/core/clash_meta | grep -q 'ARM aarch64' || {
    echo 'ERROR: Mihomo binary is not identified as ARM AArch64.' >&2
    exit 1
  }
  echo "Included Mihomo asset: $ASSET_NAME" > "$ROOT_DIR/work/CORE-INFO.txt"
else
  echo 'Mihomo core embedding disabled by workflow input.' > "$ROOT_DIR/work/CORE-INFO.txt"
fi

echo 'Disk before downloads:'
df -h .
make download -j"$(nproc)" V=s || make download -j1 V=s

echo 'Disk before compilation:'
df -h .
make -j"$(nproc)" V=s

OUT="$BUILD_DIR/bin/targets/mediatek/filogic"
test -d "$OUT" || { echo 'ERROR: expected target output directory not found.' >&2; exit 1; }
if ! find "$OUT" -maxdepth 1 -type f -name '*h3c*nx30*pro*sysupgrade.bin' | grep -q .; then
  echo 'ERROR: build finished but the NX30 Pro sysupgrade image was not generated.' >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f\n' | sort || true
  exit 1
fi

cp .config "$OUT/build.config"
{
  echo "DEVICE_PROFILE=h3c_magic-nx30-pro"
  echo "LEDE_REPO=$LEDE_REPO"
  echo "LEDE_REF=$LEDE_REF"
  echo "LEDE_COMMIT=$(git rev-parse HEAD)"
  echo "UA3F_REF=$UA3F_REF"
  echo "UA3F_COMMIT=$(git -C package/UA3F rev-parse HEAD)"
  echo "OPENCLASH_REF=$OPENCLASH_REF"
  echo "OPENCLASH_COMMIT=$(git -C "$ROOT_DIR/work/OpenClash-src" rev-parse HEAD)"
  cat "$ROOT_DIR/work/CORE-INFO.txt"
} > "$OUT/BUILD-INFO.txt"

find "$OUT" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.itb' -o -name '*.img' -o -name '*.tar' \) -print0 |
  xargs -0 -r sha256sum > "$OUT/SHA256SUMS"
test -s "$OUT/SHA256SUMS" || { echo 'ERROR: no firmware image files found for checksumming.' >&2; exit 1; }

echo 'NX30 Pro build artifacts:'
find "$OUT" -maxdepth 1 -type f -printf '%f\n' | sort
