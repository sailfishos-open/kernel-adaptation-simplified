#!/bin/bash

HERE=`pwd`
INSTALL_MOD_PATH="${INSTALL_MOD_PATH:-$HERE/buildroot/lib/modules/}"
TMPDIR="$HERE/tmp"
MKBOOTIMG="python3 $MKBOOTIMG_PATH/mkbootimg.py"
EXTRA_VENDOR_ARGS=""
DTB=$1
case "$DTB" in /*) ;; *) DTB="$HERE/$DTB" ;; esac
echo $?
echo $DTB

if [ $DEVICEINFO_RAMDISK_COMPRESSION == "gzip" ]; then
	COMPRESSION_CMD="gzip -9"
else
	COMPRESSION_CMD="lz4 -l -9"
fi

if [ -d "$HERE/overlay/vendor-ramdisk-overlay" ]; then
	VENDOR_RAMDISK="../ramdisk-vendor_boot.img"
	rm -rf "$TMPDIR/vendor-ramdisk"
	mkdir -p "$TMPDIR/vendor-ramdisk"
	cd "$TMPDIR/vendor-ramdisk"

	if [[ -f "$HERE/overlay/vendor-ramdisk-overlay/lib/modules/modules.load" && "$DEVICEINFO_KERNEL_DISABLE_MODULES" != "true" ]]; then
		item_in_array() { local item match="$1"; shift; for item; do [ "$item" = "$match" ] && return 0; done; return 1; }
		modules_dep="$(find "$INSTALL_MOD_PATH" -type f -name modules.dep)"
		modules="$(dirname "$modules_dep")" # e.g. ".../lib/modules/5.10.110-gb4d6c7a2f3a6"
		modules_len=${#modules} # e.g. 105
		all_modules="$(find "$modules" -type f -name "*.ko*")"
		module_files=("$modules/modules.alias" "$modules/modules.dep" "$modules/modules.softdep")
		set +x
		while read -r mod; do
			mod_path="$(echo -e "$all_modules" | grep "/$mod" || true)" # ".../kernel/.../mod.ko"
			if [ -z "$mod_path" ]; then
				echo "Missing the module file $mod included in modules.load"
				continue
			fi
			mod_path="${mod_path:$((modules_len+1))}" # drop absolute path prefix
			dep_paths="$(sed -n "s|^$mod_path: ||p" "$modules_dep")"
			for mod_file in $mod_path $dep_paths; do # e.g. "kernel/.../mod.ko"
				item_in_array "$modules/$mod_file" "${module_files[@]}" && continue # skip over already processed modules
				module_files+=("$modules/$mod_file")
			done
		done < <(cat "$HERE/overlay/vendor-ramdisk-overlay/lib/modules/modules.load"* | sort | uniq)
		set -x
		mkdir -p "$TMPDIR/vendor-ramdisk/lib/modules"
		cp "${module_files[@]}" "$TMPDIR/vendor-ramdisk/lib/modules"

		# rewrite modules.dep for GKI /lib/modules/*.ko structure
		set +x
		while read -r line; do
			printf '/lib/modules/%s:' "$(basename ${line%:*})"
			deps="${line#*:}"
			if [ "$deps" ]; then
				for m in $(basename -a $deps); do
					printf ' /lib/modules/%s' "$m"
				done
			fi
			echo
		done < "$modules/modules.dep" | tee "$TMPDIR/vendor-ramdisk/lib/modules/modules.dep"
		set -x
	fi

	cp -r "$HERE/overlay/vendor-ramdisk-overlay"/* "$TMPDIR/vendor-ramdisk"

	find . | cpio -o -H newc | $COMPRESSION_CMD > "$VENDOR_RAMDISK"

	EXTRA_VENDOR_ARGS+=" --base $DEVICEINFO_FLASH_OFFSET_BASE --kernel_offset $DEVICEINFO_FLASH_OFFSET_KERNEL --ramdisk_offset $DEVICEINFO_FLASH_OFFSET_RAMDISK --tags_offset $DEVICEINFO_FLASH_OFFSET_TAGS --pagesize $DEVICEINFO_FLASH_PAGESIZE --dtb $DTB --dtb_offset $DEVICEINFO_FLASH_OFFSET_DTB"

	if [ -n "$VENDOR_RAMDISK" ]; then
        VENDOR_RAMDISK_ARGS=()
        if [ "$DEVICEINFO_BOOTIMG_HEADER_VERSION" -eq 3 ]; then
            VENDOR_RAMDISK_ARGS=(--vendor_ramdisk "$VENDOR_RAMDISK")
        else #header version 4
            if [ "$DEVICEINFO_BOOTIMG_INCLUDE_RECOVERY" == "true" ] &&  [ -f "$HERE/ramdisk-recovery.img" ]; then
				VENDOR_RAMDISK_ARGS=(--ramdisk_type platform --ramdisk_name 'boot_ramdisk' --vendor_ramdisk_fragment "$VENDOR_RAMDISK" --ramdisk_type recovery --ramdisk_name 'recovery_ramdisk' --vendor_ramdisk_fragment "$HERE/ramdisk-recovery.img")
			else
				VENDOR_RAMDISK_ARGS=(--ramdisk_type platform --ramdisk_name 'boot_ramdisk' --vendor_ramdisk_fragment "$VENDOR_RAMDISK")
            fi
        fi
        $MKBOOTIMG "${VENDOR_RAMDISK_ARGS[@]}" --vendor_cmdline "$DEVICEINFO_KERNEL_CMDLINE" --header_version $DEVICEINFO_BOOTIMG_HEADER_VERSION --vendor_boot "vendor_boot.img" $EXTRA_VENDOR_ARGS
    fi
fi
