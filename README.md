# kernel-adaptation-simplified

Device-agnostic RPM packaging for Halium kernel adaptations (SailfishOS).
Builds the kernel, modules, boot.img and optionally vendor_boot.img/dtbo.img
from a device spec that only defines macros.

Add it to a device repo as a submodule at `kernel-adaptation-simplified/`:

    git submodule add https://github.com/HelloVolla/kernel-adaptation-simplified kernel-adaptation-simplified

## Device repo layout

    rpm/kernel-adaptation-<device>.spec   macros + %include of the .inc
    linux/                                kernel source (submodule)
    ramdisk-overlay/                      optional, appended to the unified boot ramdisk
    halium-boot-ramdisk.img               optional, replaces the unified boot ramdisk
    patches/apply-patches.sh + *.patch    optional, enabled with %apply_patches
    overlay/vendor-ramdisk-overlay/       optional, for vendor_boot builds
    <extra>_defconfig / *.config          config fragments referenced by the spec

Build, locally or from a CI workflow:

    source kernel-adaptation-simplified/setup-env.sh
    rpmbuild --build-in-place --define 'debug_package %{nil}' --bb rpm/kernel-adaptation-<device>.spec --buildroot=$PWD/buildroot

## Spec macros

Required:

    device                          device codename, e.g. halium-algiz
    kernel_arch                     arm / arm64
    makeopts                        e.g. LLVM=1 LLVM_IAS=1
    kcflags                         e.g. "KCFLAGS="
    clangtriple / crosscompile / crosscompile32 / hostldflags
    defconfig                       make config target(s)
    deviceinfo_dtb                  dtb path under boot/dts/
    deviceinfo_kernel_cmdline
    deviceinfo_bootimg_header_version
    deviceinfo_bootimg_os_version / deviceinfo_bootimg_os_patch_level
    deviceinfo_flash_pagesize + deviceinfo_flash_offset_* (header <= 2)
    deviceinfo_flash_offset_dtb     header 2
    Version / Release

Optional (with defaults):

    rpm_device                      defaults to %{device}
    kernel_config                   config make targets, defaults to %{defconfig}
    kernel_image                    kernel binary name, defaults to Image.gz
    ramdisk                         prebuilt boot ramdisk file, skips the unified one
    ramdisk_directory               directory packed as the whole boot ramdisk, skips the unified one
    bootimg_name                    name of the boot image installed into /boot, defaults to boot.img
    source_directory                defaults to linux
    device_target_cpu               forces the rpm target arch, e.g. aarch64
    extra_config                    fragment copied into arch/<arch>/configs before make
    apply_patches                   run patches/apply-patches.sh
    build_Image / build_modules     default 1
    build_dtboimage                 needs deviceinfo_dtbo
    build_vendor_boot               header >= 3, needs overlay/vendor-ramdisk-overlay
    devicetrees                     extra dtbs to install into /boot
    deviceinfo_ramdisk_compression  gzip / lz4 (vendor_boot)
    deviceinfo_kernel_disable_modules  skip modules in the vendor ramdisk
    deviceinfo_flash_offset_second  defaults to 0x00000000
    deviceinfo_bootimg_partition_size  adds the avb hash footer when set
    deviceinfo_bootimg_append_vbmeta   defaults to false, appends ./vbmeta.img
    deviceinfo_append_dtb           true appends the dtb to the kernel image (header 0/1)
    deviceinfo_bootimg_prebuilt_dtb dtb file in the device repo used instead of deviceinfo_dtb
    deviceinfo_bootimg_has_init_boot_partition  true puts the ramdisk into init_boot.img (header >= 3)
    deviceinfo_init_boot_partition_size  defaults to 8388608
    deviceinfo_bootimg_qcdt / deviceinfo_halium_version / deviceinfo_rootfs_image_sector_size  passed to mkvendorboot.sh
    deviceinfo_bootimg_include_recovery  passed to mkvendorboot.sh to add a recovery initrd (set to true) 
                                    - ramdisk-recovery.img to be supplied by the device kernel package
    crossbuild                      OBS cross toolchain instead of makeopts/clang

Put device-specific build dependencies in the device spec. For example, a
device that sets `DTC_EXT=dtc` in `makeopts` to use the host dtc instead of the
one in the kernel tree needs `BuildRequires: dtc` in its own spec.

Boot images are signed with `./rsa4096_boot.pem` from the device repo root when
present.

## Boot ramdisk

`setup-env.sh` downloads the unified halium boot ramdisk (the dynparts release
of halium/initramfs-tools-halium) and exports it as `HALIUM_RAMDISK`. Device
specific content stays in the device repo: a `ramdisk-overlay/` directory is
packed as cpio and appended to the unified ramdisk (recompressed to
`deviceinfo_ramdisk_compression` when set), a committed
`halium-boot-ramdisk.img` replaces the unified base entirely, and the
`ramdisk` macro points at a fully prebuilt image. Devices that carry their
whole initramfs as a directory set `ramdisk_directory`, which is packed as
gzipped cpio and used as is.

## Bundled tools

`mkbootimg.py`, `mkdtboimg.py`, `avbtool` (python2), `mkvendorboot.sh` and the
GKI certification scripts under `gki/`. `setup-env.sh` fetches the android
prebuilt toolchains and exports `MKBOOTIMG_PATH`/`AVB_PATH`; when those are not
set the .inc falls back to the bundled copies.
