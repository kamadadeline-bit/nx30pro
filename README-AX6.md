# Redmi AX6 - Campus SY profile

This is an independent device profile for Xiaomi/Redmi AX6 (Qualcomm IPQ8074, qualcommax/ipq807x). It reuses the Campus SY common package set but does not reuse the NX30 Pro target, DTS, wireless driver or flash layout.

## Image formats

The upstream Coolsnowwolf LEDE image recipe defines Redmi AX6 by inheriting the Xiaomi AX3600 UBI layout:

- Native U-Boot image: `factory.ubi` (the image begins with the UBI header magic `UBI#`).
- OpenWrt upgrade image: `sysupgrade.bin`.

The supplied known-good AX6 image is 81,920,000 bytes and begins with `UBI#`. The build checks that the newly generated factory UBI does not exceed that reference size, and that the sysupgrade kernel + rootfs payload remains below the same conservative ceiling.

For convenience, the workflow also emits `redmi_ax6-campus-factory.bin`. It is a byte-for-byte copy of the native `factory.ubi`, not a repacked or converted image. The native `.ubi` file is retained and should be treated as the primary U-Boot image. Never flash the stock MIBIB or U-Boot backup files as firmware.

## Build

The dedicated workflow is `.github/workflows/build-ax6.yml`. It runs one build job only, with concurrency protection to avoid overlapping compiles. It uses:

- `DEVICE_PROFILE=redmi_ax6`
- `qualcommax/ipq807x`
- `CONFIG_TARGET_qualcommax_ipq807x_DEVICE_redmi_ax6=y`

The build validates the target profile, checks the sysupgrade archive contains kernel and root members, validates the UBI magic and size, and writes SHA256 checksums for the firmware outputs.

## Important

The factory image is structurally checked against the known-good UBI sample, but this does not prove every bootloader build accepts every image. Keep the original known-good image and stock backups available for recovery. Do not flash until the workflow completes successfully and the output checks pass.
