#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/work/openwrt"
LEDE_REPO="${LEDE_REPO:-https://github.com/coolsnowwolf/lede.git}"
LEDE_REF="${LEDE_REF:-master}"
UA3F_REF="${UA3F_REF:-v3.7.0}"
PASSWALL_LUCI_REF="${PASSWALL_LUCI_REF:-main}"
PASSWALL_PACKAGES_REF="${PASSWALL_PACKAGES_REF:-main}"
ARGON_REF="${ARGON_REF:-v3.1.0}"
ESURFING_REF="${ESURFING_REF:-v2.2.1-r7}"
UU_REF="${UU_REF:-v2.2.2}"
ZIG_VERSION="${ZIG_VERSION:-0.13.0}"
DEVICE_PROFILE="${DEVICE_PROFILE:-h3c_magic-nx30-pro}"
DEVICE_CONFIG="$ROOT_DIR/configs/devices/$DEVICE_PROFILE.config"

mkdir -p "$ROOT_DIR/work"
rm -rf "$BUILD_DIR" "$ROOT_DIR/work/MentoHUST-src" "$ROOT_DIR/work/Argon-src" \
  "$ROOT_DIR/work/ESurfing-src" "$ROOT_DIR/work/Dogcom-src" "$ROOT_DIR/work/Dogcom-LuCI-src" "$ROOT_DIR/work/UU-src"
git clone --depth 1 --branch "$LEDE_REF" "$LEDE_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"

# Shared package choices; separate device profile holds target/flash/driver data.
case "$DEVICE_PROFILE" in
  h3c_magic-nx30-pro)
    TARGET_SUBDIR="mediatek/filogic"
    TARGET_PROFILE_LINE='CONFIG_TARGET_mediatek_filogic_DEVICE_h3c_magic-nx30-pro=y'
    SYSUPGRADE_GLOB='*h3c*nx30*pro*sysupgrade.bin'
    ;;
  *)
    echo "ERROR: unknown/unimplemented DEVICE_PROFILE=$DEVICE_PROFILE" >&2
    exit 1
    ;;
esac
test -f "$DEVICE_CONFIG" || { echo "ERROR: device config missing: $DEVICE_CONFIG" >&2; exit 1; }
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

# Stage the requested Dr.COM, ESurfing and UU client packages.
DOGCOM_SRC_DIR="$ROOT_DIR/work/Dogcom-src"
DOGCOM_LUCI_SRC_DIR="$ROOT_DIR/work/Dogcom-LuCI-src"
git clone --depth 1 https://github.com/mchome/openwrt-dogcom.git "$DOGCOM_SRC_DIR"
git clone --depth 1 https://github.com/mchome/luci-app-dogcom.git "$DOGCOM_LUCI_SRC_DIR"
test -f "$DOGCOM_SRC_DIR/Makefile" && test -f "$DOGCOM_LUCI_SRC_DIR/Makefile" || {
  echo 'ERROR: Dogcom core / LuCI package missing.' >&2; exit 1;
}
rm -rf package/openwrt-dogcom package/luci-app-dogcom
cp -a "$DOGCOM_SRC_DIR" package/openwrt-dogcom
cp -a "$DOGCOM_LUCI_SRC_DIR" package/luci-app-dogcom

ESURFING_SRC_DIR="$ROOT_DIR/work/ESurfing-src"
git clone --depth 1 --branch "$ESURFING_REF" https://github.com/BadGhost520/ESurfingClient-CVersion.git "$ESURFING_SRC_DIR"
bash "$ESURFING_SRC_DIR/scripts/sync-version.sh" 2.2.1-r7
test -f "$ESURFING_SRC_DIR/esurfingclient/Makefile" && test -f "$ESURFING_SRC_DIR/luci-app-esurfingclient/Makefile" || {
  echo 'ERROR: ESurfingClient OpenWrt packages missing.' >&2; exit 1;
}
rm -rf package/esurfingclient package/luci-app-esurfingclient
cp -a "$ESURFING_SRC_DIR/esurfingclient" package/esurfingclient
cp -a "$ESURFING_SRC_DIR/luci-app-esurfingclient" package/luci-app-esurfingclient

# ESurfingClient's static link needs curl's staging headers and libcurl.a.
# PKG_BUILD_DEPENDS names the source package (PKG_NAME=curl), not the binary
# library subpackage (libcurl).
sed -i 's/^PKG_BUILD_DEPENDS:=libcurl$/PKG_BUILD_DEPENDS:=curl/' package/esurfingclient/Makefile
grep -qx 'PKG_BUILD_DEPENDS:=curl' package/esurfingclient/Makefile || {
  echo 'ERROR: ESurfingClient curl build dependency normalization failed.' >&2
  exit 1
}

UU_SRC_DIR="$ROOT_DIR/work/UU-src"
git clone --depth 1 --branch "$UU_REF" https://github.com/xiaodoudou/luci-app-uugamebooster.git "$UU_SRC_DIR"
if ! command -v zig >/dev/null 2>&1 && [ ! -x "$HOME/zig/zig" ]; then
  echo "ERROR: Zig $ZIG_VERSION is required for UU architecture shims." >&2; exit 1;
fi
if [ -x "$HOME/zig/zig" ]; then export PATH="$HOME/zig:$PATH"; fi
sh "$UU_SRC_DIR/tools/build-preload.sh" "$UU_SRC_DIR/luci-app-uugamebooster/root/usr/lib/uuplugin"
test -s "$UU_SRC_DIR/luci-app-uugamebooster/root/usr/lib/uuplugin/uu-view-preload-aarch64.so" || {
  echo 'ERROR: UU aarch64 view-filter shim not generated.' >&2; exit 1;
}
rm -rf package/luci-app-uugamebooster
cp -a "$UU_SRC_DIR/luci-app-uugamebooster" package/luci-app-uugamebooster

# The LEDE Kconfig symbol is libstdcpp; ABI_VERSION=6 is only the runtime
# package ABI suffix and is not the source package name used by LUCI_DEPENDS.
sed -i 's/+libstdcpp6/+libstdcpp/g' package/luci-app-uugamebooster/Makefile
grep -q 'LUCI_DEPENDS:=.*+libstdcpp' package/luci-app-uugamebooster/Makefile || {
  echo 'ERROR: UU Game Booster libstdc++ dependency normalization failed.' >&2
  exit 1
}

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

# Pin the well-established Argon theme to the current stable upstream release.
ARGON_SRC_DIR="$ROOT_DIR/work/Argon-src"
git clone --depth 1 --branch "$ARGON_REF" https://github.com/jerrykuku/luci-theme-argon.git "$ARGON_SRC_DIR"
test -f "$ARGON_SRC_DIR/Makefile" || {
  echo 'ERROR: Argon theme Makefile not found.' >&2
  exit 1
}
rm -rf package/luci-theme-argon
cp -a "$ARGON_SRC_DIR" package/luci-theme-argon

cat "$ROOT_DIR/configs/packages.common.config" "$DEVICE_CONFIG" > .config
make defconfig

# Assert target profile survived Kconfig.
grep -qx "$TARGET_PROFILE_LINE" .config || {
  echo "ERROR: target profile $DEVICE_PROFILE was dropped by Kconfig." >&2
  exit 1
}
for package in \
  ua3f kmod-nft-queue kmod-nft-tproxy kmod-sched-bpf libubox-lua \
  kmod-nft-core kmod-nfnetlink-queue kmod-nf-tproxy kmod-nf-conntrack \
  kmod-nf-conntrack-netlink kmod-sched-core dnsmasq-full \
  luci-app-passwall mentohust luci-app-mentohust libpcap \
  dogcom luci-app-dogcom esurfingclient luci-app-esurfingclient libcurl \
  luci-app-uugamebooster wpad-openssl \
  luci-proto-relay relayd iw kmod-nft-socket kmod-nft-nat \
  luci-theme-argon luci-app-argon-config \
  luci-app-sqm sqm-scripts tc-tiny kmod-ifb kmod-sched-cake \
  kmod-nf-reject kmod-nf-reject6 kmod-tun kmod-ipt-nat unshare libstdcpp; do
  if ! grep -qx "CONFIG_PACKAGE_${package}=y" .config; then
    echo "ERROR: required package ${package} is missing or was dropped by Kconfig." >&2
    exit 1
  fi
done

# Assert the four PPP / PPPoE runtime layers used by FlashNet.
for ppp_package in ppp ppp-mod-pppoe kmod-ppp kmod-pppoe; do
  if ! grep -qx "CONFIG_PACKAGE_${ppp_package}=y" .config; then
    echo "ERROR: required FlashNet PPP package ${ppp_package} is missing." >&2
    exit 1
  fi
done

# Reject unrequested proxy frontends and unrelated acceleration apps.
for forbidden in luci-app-openclash luci-app-ssr-plus luci-app-turboacc luci-app-minieap; do
  if grep -qx "CONFIG_PACKAGE_${forbidden}=y" .config; then
    echo "ERROR: unrequested package ${forbidden} was selected." >&2
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
if grep -qx 'CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client=y' .config || \
   grep -qx 'CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs=y' .config || \
   grep -qx 'CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin=y' .config; then
  echo 'ERROR: optional PassWall Rust/obfs/plugin components must remain disabled to preserve flash space.' >&2
  exit 1
fi

# Install defaults, STA recovery helper, and user-supplied SQM Chinese resources.
mkdir -p files/etc/uci-defaults files/etc/init.d files/etc/config files/usr/sbin
cp "$ROOT_DIR/files/etc/uci-defaults/98-nx30pro-safe-services" files/etc/uci-defaults/
cp "$ROOT_DIR/files/etc/init.d/wifi-bridge-guard" files/etc/init.d/
cp "$ROOT_DIR/files/etc/config/wifi-bridge-guard" files/etc/config/
cp "$ROOT_DIR/files/usr/sbin/wifi-bridge-guard" files/usr/sbin/
tar -xzf "$ROOT_DIR/assets/sqm-i18n-data.tar.gz" -C files/
test -s files/usr/lib/lua/luci/i18n/sqm.zh-cn.lmo || {
  echo 'ERROR: SQM Chinese translation missing from rootfs overlay.' >&2; exit 1;
}
chmod 0755 files/etc/uci-defaults/98-nx30pro-safe-services
chmod 0755 files/etc/init.d/wifi-bridge-guard files/usr/sbin/wifi-bridge-guard

echo 'Disk before downloads:'
df -h .
make download -j"$(nproc)" V=s || make download -j1 V=s

echo 'Disk before compilation:'
df -h .
make -j"$(nproc)" V=s

OUT="$BUILD_DIR/bin/targets/$TARGET_SUBDIR"
test -d "$OUT" || { echo 'ERROR: expected target output directory not found.' >&2; exit 1; }
SYSUPGRADE_IMAGE="$(find "$OUT" -maxdepth 1 -type f -name "$SYSUPGRADE_GLOB" -print -quit)"
if [[ -z "$SYSUPGRADE_IMAGE" ]]; then
  echo 'ERROR: build finished but the $DEVICE_PROFILE sysupgrade image was not generated.' >&2
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
  echo "Do not flash this image. Reduce the selected package set and rebuild." >&2
  exit 1
fi

cp .config "$OUT/build.config"
{
  echo "DEVICE_PROFILE=$DEVICE_PROFILE"
  echo "LEDE_REPO=$LEDE_REPO"
  echo "LEDE_REF=$LEDE_REF"
  echo "LEDE_COMMIT=$(git rev-parse HEAD)"
  echo "UA3F_REF=$UA3F_REF"
  echo "UA3F_COMMIT=$(git -C "$UA3F_SRC_DIR" rev-parse HEAD)"
  echo "ESURFING_REF=$ESURFING_REF"
  echo "ESURFING_COMMIT=$(git -C "$ESURFING_SRC_DIR" rev-parse HEAD)"
  echo "DOGCOM_COMMIT=$(git -C "$DOGCOM_SRC_DIR" rev-parse HEAD)"
  echo "DOGCOM_LUCI_COMMIT=$(git -C "$DOGCOM_LUCI_SRC_DIR" rev-parse HEAD)"
  echo "UU_REF=$UU_REF"
  echo "UU_COMMIT=$(git -C "$UU_SRC_DIR" rev-parse HEAD)"
  echo "PASSWALL_LUCI_REF=$PASSWALL_LUCI_REF"
  echo "PASSWALL_LUCI_COMMIT=$(git -C "$BUILD_DIR/feeds/passwall_luci" rev-parse HEAD)"
  echo "PASSWALL_PACKAGES_REF=$PASSWALL_PACKAGES_REF"
  echo "PASSWALL_PACKAGES_COMMIT=$(git -C "$BUILD_DIR/feeds/passwall_packages" rev-parse HEAD)"
  echo "MENTOHUST_COMMIT=$(git -C "$MENTOHUST_SRC_DIR" rev-parse HEAD)"
  echo "ARGON_REF=$ARGON_REF"
  echo "ARGON_COMMIT=$(git -C "$ARGON_SRC_DIR" rev-parse HEAD)"
  echo "SQM_I18N_SOURCE=uploaded luci-i18n-sqm 1.1.3-1 (Architecture all)"
  echo "MAC80211_NETNS_COMPAT=6.12.114+:netns_immutable"
  echo "NX30PRO_KERNEL_BYTES=$KERNEL_BYTES"
  echo "NX30PRO_ROOTFS_BYTES=$ROOTFS_BYTES"
  echo "NX30PRO_KERNEL_PLUS_ROOTFS_BYTES=$PAYLOAD_BYTES"
  echo "NX30PRO_MAX_SAFE_PAYLOAD_BYTES=$MAX_PAYLOAD_BYTES"
} > "$OUT/BUILD-INFO.txt"

find "$OUT" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.itb' -o -name '*.img' -o -name '*.tar' \) -print0 |
  xargs -0 -r sha256sum > "$OUT/SHA256SUMS"
test -s "$OUT/SHA256SUMS" || { echo 'ERROR: no firmware image files found for checksumming.' >&2; exit 1; }

echo 'NX30 Pro build artifacts:'
find "$OUT" -maxdepth 1 -type f -printf '%f\n' | sort
