#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/work/openwrt"
LEDE_REPO="${LEDE_REPO:-https://github.com/coolsnowwolf/lede.git}"
LEDE_REF="${LEDE_REF:-master}"
UA3F_REF="${UA3F_REF:-v3.7.0}"
OPENCLASH_REF="${OPENCLASH_REF:-master}"
PASSWALL_LUCI_REF="${PASSWALL_LUCI_REF:-main}"
PASSWALL_PACKAGES_REF="${PASSWALL_PACKAGES_REF:-main}"
ARGON_REF="${ARGON_REF:-v3.1.0}"
INCLUDE_MIHOMO_CORE="${INCLUDE_MIHOMO_CORE:-false}"

mkdir -p "$ROOT_DIR/work"
rm -rf "$BUILD_DIR" "$ROOT_DIR/work/OpenClash-src" "$ROOT_DIR/work/MentoHUST-src" "$ROOT_DIR/work/Argon-src"
git clone --depth 1 --branch "$LEDE_REF" "$LEDE_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"

# Hard guard: fail before compilation if this LEDE ref does not support NX30 Pro.
grep -q 'TARGET_DEVICES += h3c_magic-nx30-pro' target/linux/mediatek/image/filogic.mk || {
  echo 'ERROR: selected LEDE ref has no h3c_magic-nx30-pro device profile.' >&2
  exit 1
}

# Linux 6.12.114's refreshed patch stack uses netns_immutable, while the
# mac80211 backport compatibility patch still selects netns_local until 6.15.
# Raise the compatibility cutoff for 6.12.114+; leave older 6.12 kernels intact.
NETNS_PATCH="$BUILD_DIR/package/kernel/mac80211/patches/build/210-wireless_netns_local_backport.patch"
python3 - "$NETNS_PATCH" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"ERROR: expected mac80211 compatibility patch not found: {path}")
content = path.read_text(encoding="utf-8")
old = "#if LINUX_VERSION_IS_GEQ(6,15,0)"
count = content.count(old)
if count != 5:
    raise SystemExit(
        f"ERROR: expected 5 netns compatibility guards, found {count}; "
        "refusing to patch an unexpected upstream version."
    )
content = content.replace(old, "#if LINUX_VERSION_IS_GEQ(6,12,114)")
path.write_text(content, encoding="utf-8")
if content.count("#if LINUX_VERSION_IS_GEQ(6,12,114)") != 5:
    raise SystemExit("ERROR: failed to update all five netns compatibility guards.")
print("Patched mac80211 netns compatibility cutoff: kernel 6.12.114+ uses netns_immutable.")
PY

# Add the maintained PassWall package and LuCI feeds before feed metadata is updated.
python3 - "$BUILD_DIR/feeds.conf.default" "$PASSWALL_PACKAGES_REF" "$PASSWALL_LUCI_REF" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
packages_ref, luci_ref = sys.argv[2:4]
lines = path.read_text(encoding="utf-8").splitlines()
lines = [
    line for line in lines
    if not line.strip().startswith("src-git passwall_packages ")
    and not line.strip().startswith("src-git passwall_luci ")
]
prefix = [
    f"src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;{packages_ref}",
    f"src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;{luci_ref}",
]
path.write_text("\n".join(prefix + lines) + "\n", encoding="utf-8")
PY

./scripts/feeds update -a
./scripts/feeds install -a

# Stage MentoHUST's daemon and its separate LuCI application as two OpenWrt packages.
MENTOHUST_SRC_DIR="$ROOT_DIR/work/MentoHUST-src"
git clone --depth 1 https://github.com/sbwml/luci-app-mentohust.git "$MENTOHUST_SRC_DIR"
test -f "$MENTOHUST_SRC_DIR/mentohust/Makefile" || {
  echo 'ERROR: MentoHUST daemon package Makefile not found.' >&2
  exit 1
}
test -f "$MENTOHUST_SRC_DIR/luci-app-mentohust/Makefile" || {
  echo 'ERROR: MentoHUST LuCI package Makefile not found.' >&2
  exit 1
}
rm -rf package/mentohust package/luci-app-mentohust
cp -a "$MENTOHUST_SRC_DIR/mentohust" package/mentohust
cp -a "$MENTOHUST_SRC_DIR/luci-app-mentohust" package/luci-app-mentohust

# UA3F keeps its OpenWrt package Makefile under openwrt/ and Go sources at the repo root.
# Stage a proper top-level package directory, then fix source paths for OpenWrt's build system.
UA3F_SRC_DIR="$ROOT_DIR/work/UA3F-src"
rm -rf "$UA3F_SRC_DIR" package/UA3F
git clone --depth 1 --branch "$UA3F_REF" https://github.com/SunBK201/UA3F.git "$UA3F_SRC_DIR"
mkdir -p package/UA3F
cp "$UA3F_SRC_DIR"/go.mod "$UA3F_SRC_DIR"/go.sum "$UA3F_SRC_DIR"/main.go "$UA3F_SRC_DIR"/LICENSE package/UA3F/
cp -a "$UA3F_SRC_DIR"/cmd "$UA3F_SRC_DIR"/internal package/UA3F/
cp -a "$UA3F_SRC_DIR"/openwrt/files "$UA3F_SRC_DIR"/openwrt/htdocs "$UA3F_SRC_DIR"/openwrt/luasrc "$UA3F_SRC_DIR"/openwrt/po package/UA3F/
cp "$UA3F_SRC_DIR"/openwrt/Makefile package/UA3F/Makefile
python3 - "$BUILD_DIR/package/UA3F/Makefile" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
content = content.replace("PKG_NAME:=UA3F", "PKG_NAME:=ua3f")
content = content.replace(
    "$(CP) ../go.mod ../go.sum ../main.go ../cmd ../internal $(PKG_BUILD_DIR)",
    "$(CP) $(TOPDIR)/package/UA3F/go.mod $(TOPDIR)/package/UA3F/go.sum $(TOPDIR)/package/UA3F/main.go $(TOPDIR)/package/UA3F/cmd $(TOPDIR)/package/UA3F/internal $(PKG_BUILD_DIR)"
)
content = content.replace("po2lmo ./po/zh_cn/ua3f.po", "po2lmo $(TOPDIR)/package/UA3F/po/zh_cn/ua3f.po")
content = content.replace("./files/", "$(TOPDIR)/package/UA3F/files/")
content = content.replace("./luasrc/", "$(TOPDIR)/package/UA3F/luasrc/")
content = content.replace("./htdocs/", "$(TOPDIR)/package/UA3F/htdocs/")
if "../go.mod" in content or "./files/" in content or "./luasrc/" in content or "./htdocs/" in content:
    raise SystemExit("UA3F Makefile path normalization incomplete.")
path.write_text(content, encoding="utf-8")
PY

# Add the upstream OpenClash LuCI package to this fresh source tree.
git clone --depth 1 --branch "$OPENCLASH_REF" https://github.com/vernesong/OpenClash.git "$ROOT_DIR/work/OpenClash-src"
test -f "$ROOT_DIR/work/OpenClash-src/luci-app-openclash/Makefile" || {
  echo 'ERROR: OpenClash package Makefile not found in selected ref.' >&2
  exit 1
}
rm -rf package/luci-app-openclash
cp -a "$ROOT_DIR/work/OpenClash-src/luci-app-openclash" package/luci-app-openclash

# Pin the well-established Argon theme to the current stable upstream release.
ARGON_SRC_DIR="$ROOT_DIR/work/Argon-src"
git clone --depth 1 --branch "$ARGON_REF" https://github.com/jerrykuku/luci-theme-argon.git "$ARGON_SRC_DIR"
test -f "$ARGON_SRC_DIR/Makefile" || {
  echo 'ERROR: Argon theme Makefile not found.' >&2
  exit 1
}
rm -rf package/luci-theme-argon
cp -a "$ARGON_SRC_DIR" package/luci-theme-argon

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
  luci-app-passwall mentohust luci-app-mentohust libpcap \
  luci-proto-relay relayd iw kmod-nft-socket kmod-nft-nat \
  luci-theme-argon luci-app-argon-config \
  kmod-nf-reject kmod-nf-reject6 kmod-tun kmod-inet-diag; do
  if ! grep -qx "CONFIG_PACKAGE_${package}=y" .config; then
    echo "ERROR: required package ${package} is missing or was dropped by Kconfig." >&2
    exit 1
  fi
done

# Confirm the standalone SSR-Plus app and PassWall's optional SSR-libev engines stay disabled.
if grep -qx 'CONFIG_PACKAGE_luci-app-ssr-plus=y' .config; then
  echo 'ERROR: standalone luci-app-ssr-plus must not be enabled; use PassWall.' >&2
  exit 1
fi
if grep -qx 'CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=y' .config || \
   grep -qx 'CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Server=y' .config; then
  echo 'ERROR: PassWall SSR-libev engines should stay disabled for this build.' >&2
  exit 1
fi

# Install first-boot defaults and the self-recovery helper into the rootfs overlay.
mkdir -p files/etc/uci-defaults files/etc/init.d files/etc/config files/usr/sbin
cp "$ROOT_DIR/files/etc/uci-defaults/98-nx30pro-safe-services" files/etc/uci-defaults/
cp "$ROOT_DIR/files/etc/init.d/wifi-bridge-guard" files/etc/init.d/
cp "$ROOT_DIR/files/etc/config/wifi-bridge-guard" files/etc/config/
cp "$ROOT_DIR/files/usr/sbin/wifi-bridge-guard" files/usr/sbin/
chmod 0755 files/etc/uci-defaults/98-nx30pro-safe-services
chmod 0755 files/etc/init.d/wifi-bridge-guard files/usr/sbin/wifi-bridge-guard

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
SYSUPGRADE_IMAGE="$(find "$OUT" -maxdepth 1 -type f -name '*h3c*nx30*pro*sysupgrade.bin' -print -quit)"
if [[ -z "$SYSUPGRADE_IMAGE" ]]; then
  echo 'ERROR: build finished but the NX30 Pro sysupgrade image was not generated.' >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f\n' | sort || true
  exit 1
fi

# NX30 Pro has a 64 MiB UBI partition and IMAGE_SIZE=65536k.
# Check the actual kernel + SquashFS payload stored in the sysupgrade tar.
# Keep a 4 MiB safety margin; never publish an image that is too large for UBI.
TAR_PREFIX="sysupgrade-h3c_magic-nx30-pro"
KERNEL_BYTES="$(tar -xOf "$SYSUPGRADE_IMAGE" "$TAR_PREFIX/kernel" | wc -c | tr -d ' ')"
ROOTFS_BYTES="$(tar -xOf "$SYSUPGRADE_IMAGE" "$TAR_PREFIX/root" | wc -c | tr -d ' ')"
PAYLOAD_BYTES=$((KERNEL_BYTES + ROOTFS_BYTES))
MAX_PAYLOAD_BYTES=$((60 * 1024 * 1024))
echo "NX30PRO_KERNEL_BYTES=$KERNEL_BYTES"
echo "NX30PRO_ROOTFS_BYTES=$ROOTFS_BYTES"
echo "NX30PRO_KERNEL_PLUS_ROOTFS_BYTES=$PAYLOAD_BYTES"
echo "NX30PRO_MAX_SAFE_PAYLOAD_BYTES=$MAX_PAYLOAD_BYTES"
if (( PAYLOAD_BYTES > MAX_PAYLOAD_BYTES )); then
  echo "ERROR: NX30 Pro kernel + rootfs payload ($PAYLOAD_BYTES bytes) exceeds conservative 60 MiB limit for its 64 MiB UBI partition." >&2
  echo "Do not flash this image. Reduce optional packages or disable embedded Mihomo core." >&2
  exit 1
fi

cp .config "$OUT/build.config"
{
  echo "DEVICE_PROFILE=h3c_magic-nx30-pro"
  echo "LEDE_REPO=$LEDE_REPO"
  echo "LEDE_REF=$LEDE_REF"
  echo "LEDE_COMMIT=$(git rev-parse HEAD)"
  echo "UA3F_REF=$UA3F_REF"
  echo "UA3F_COMMIT=$(git -C "$UA3F_SRC_DIR" rev-parse HEAD)"
  echo "OPENCLASH_REF=$OPENCLASH_REF"
  echo "OPENCLASH_COMMIT=$(git -C "$ROOT_DIR/work/OpenClash-src" rev-parse HEAD)"
  echo "PASSWALL_LUCI_REF=$PASSWALL_LUCI_REF"
  echo "PASSWALL_LUCI_COMMIT=$(git -C "$BUILD_DIR/feeds/passwall_luci" rev-parse HEAD)"
  echo "PASSWALL_PACKAGES_REF=$PASSWALL_PACKAGES_REF"
  echo "PASSWALL_PACKAGES_COMMIT=$(git -C "$BUILD_DIR/feeds/passwall_packages" rev-parse HEAD)"
  echo "MENTOHUST_COMMIT=$(git -C "$MENTOHUST_SRC_DIR" rev-parse HEAD)"
  echo "ARGON_REF=$ARGON_REF"
  echo "ARGON_COMMIT=$(git -C "$ARGON_SRC_DIR" rev-parse HEAD)"
  echo "MAC80211_NETNS_COMPAT=6.12.114+:netns_immutable"
  echo "NX30PRO_KERNEL_BYTES=$KERNEL_BYTES"
  echo "NX30PRO_ROOTFS_BYTES=$ROOTFS_BYTES"
  echo "NX30PRO_KERNEL_PLUS_ROOTFS_BYTES=$PAYLOAD_BYTES"
  echo "NX30PRO_MAX_SAFE_PAYLOAD_BYTES=$MAX_PAYLOAD_BYTES"
  cat "$ROOT_DIR/work/CORE-INFO.txt"
} > "$OUT/BUILD-INFO.txt"

find "$OUT" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.itb' -o -name '*.img' -o -name '*.tar' \) -print0 |
  xargs -0 -r sha256sum > "$OUT/SHA256SUMS"
test -s "$OUT/SHA256SUMS" || { echo 'ERROR: no firmware image files found for checksumming.' >&2; exit 1; }

echo 'NX30 Pro build artifacts:'
find "$OUT" -maxdepth 1 -type f -printf '%f\n' | sort
