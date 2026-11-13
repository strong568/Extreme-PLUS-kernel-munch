#!/bin/bash
# ==============================================================================
# EXTREME++ BMW Edition Kernel Build Script (BakaSU + SuSFS v2.4 + NoMount)
# Maintainer: PandeyJI-9 & Customised
# Device: POCO F4 (munch) | Targets: HyperOS 4 / HyperOS & AOSP (Android 13–17)
# ==============================================================================

set -e
trap 'echo "❌ [ERROR] Script failed on line $LINENO"; exit 1' ERR

if [ -z "$1" ]; then
    echo "[!] Error: No device specified."
    echo "Usage: $0 <device_name> [bakasu|noroot|both] [hyperos|aosp|both]"
    exit 1
fi

DEVICE_NAME="$1"
DEFCONFIG="${DEVICE_NAME}_defconfig"

ROOT_MODE="${2:-bakasu}"
ROOT_MODE=$(echo "$ROOT_MODE" | tr '[:upper:]' '[:lower:]')
case "$ROOT_MODE" in
    bakasu|ksu_susfs|susfs|root|ksu|true|1)
        ROOT_MODE="bakasu"
        ;;
    noroot|clean|false|0)
        ROOT_MODE="noroot"
        ;;
    both)
        ROOT_MODE="both"
        ;;
    *)
        ROOT_MODE="bakasu"
        ;;
esac

TARGET_OS="${3:-both}"
TARGET_OS=$(echo "$TARGET_OS" | tr '[:upper:]' '[:lower:]')
case "$TARGET_OS" in
    hyperos|miui) TARGET_OS="hyperos" ;;
    aosp) TARGET_OS="aosp" ;;
    *) TARGET_OS="both" ;;
esac

KERNEL_DIR="$(pwd)"
TOOLCHAIN_BIN="$HOME/zyc-clang/bin"

export PATH="${TOOLCHAIN_BIN}:${PATH}"
export ARCH="arm64"
export SUBARCH="arm64"
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
export CCACHE_EXEC=$(command -v ccache)
export USE_CCACHE=1

TOTAL_CORES=$(nproc --all)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 EXTREME++ BMW Edition Build Engine Initiated (BakaSU + SuSFS 2.4 + NoMount)!"
echo "   Device: POCO F4 (munch / SM8250-AC)"
echo "   Root Mode: ${ROOT_MODE}"
echo "   Target Mode: ${TARGET_OS}"
echo "   System Cores: ${TOTAL_CORES} (Running at Full Speed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ------------------------------------------
# 1. Base Cleanup & Custom Defconfig Tunables
# ------------------------------------------
echo "[*] Cleaning previous temporary outputs..."
rm -rf out out_hyperos out_aosp anykernel anykernel_* EXTREME++*.zip
find . -type f \( -name "dtbo.img" -o -name "Image" -o -name "Image.gz" \) -delete

cat >> "arch/arm64/configs/${DEFCONFIG}" << 'EOF'
CONFIG_PM_DEVFREQ=y
CONFIG_DEVFREQ_GOV_QCOM_ADRENO_TZ=y
CONFIG_DEVFREQ_GOV_QCOM_GPUBW_MON=y
CONFIG_QCOM_ADRENO_DEFAULT_GOVERNOR="msm-adreno-tz"
CONFIG_QCOM_KGSL=y
CONFIG_CPU_FREQ_GOV_EXTREME_PLUS=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_DEFAULT_GOV_EXTREME_PLUS=y
CONFIG_CPU_FREQ_DEFAULT_GOV="extreme+"
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"
CONFIG_NET_SCH_FQ=y
CONFIG_NET_SCH_FQ_CODEL=y
EOF

# ------------------------------------------
# 3. KernelSU (BakaSU) + SuSFS v2.4 + NoMount Setup Function
# ------------------------------------------
inject_bakasu_susfs_nomount() {
    if [ -d "KernelSU" ] || [ -d "drivers/kernelsu" ]; then
        echo "[*] BakaSU source already present, skipping re-injection..."
        return 0
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ Injecting BakaSU, SuSFS v2.4 & NoMount Source..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 1. Tải và cài đặt BakaSU (tự động tích hợp SuSFS v2.4)[span_0](start_span)[span_0](end_span)
    curl -LSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" | bash

    # 2. Tải và cài đặt NoMount (nhánh master/dev tương thích)[span_1](start_span)[span_1](end_span)
    curl -LSs "https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh" | bash -s master

    # Bổ sung nhận diện manager phổ biến cho BakaSU trong apk_sign nếu có
    python3 -c '
import os

candidates = [
    "drivers/kernelsu/kernel/manager/apk_sign.c",
    "drivers/kernelsu/manager/apk_sign.c",
    "drivers/kernelsu/apk_sign.c",
]
apk_sign_path = next((p for p in candidates if os.path.exists(p)), None)
if apk_sign_path:
    with open(apk_sign_path, "r") as f:
        content = f.read()

    hook_target = "return check_v2_signature(path, signature_index);"
    hook_replacement = """    if (check_v2_signature(path, signature_index))
        return true;
    char pkg_buf[128];
    if (get_pkg_from_apk_path(pkg_buf, path) == 0) {
        if (!strcmp(pkg_buf, "org.bakasu.bakasu") ||
            !strcmp(pkg_buf, "me.weishu.kernelsu") ||
            !strcmp(pkg_buf, "com.sukisu.ultra")) {
            pr_info("PROJECT EXTREME+: Manager recognized: %s\\n", pkg_buf);
            *signature_index = 0;
            return true;
        }
    }
    return false;"""
    if hook_target in content and "pkg_buf" not in content:
        content = content.replace(hook_target, hook_replacement)
        with open(apk_sign_path, "w") as f:
            f.write(content)
        print("✅ Patched " + apk_sign_path + " with BakaSU manager verification")
' 2>/dev/null || true

    echo "CONFIG_KSU=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_KSU_SUSFS=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_NOMOUNT=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_THREAD_INFO_IN_TASK=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "[+] BakaSU + SuSFS v2.4 + NoMount setup finished."
}

# ------------------------------------------
# 4. Native FakeDreamer Adreno 650 Undervolt & Speed Bins
# ------------------------------------------
echo "[*] Applying Native FakeDreamer GPU Undervolt & Speed Bins..."
if [ -f "kona-v2-gpu.dtsi" ]; then
    cp -f kona-v2-gpu.dtsi arch/arm64/boot/dts/vendor/qcom/kona-v2-gpu.dtsi
    echo "[+] Copied FakeDreamer kona-v2-gpu.dtsi into kernel tree"
fi

cat > arch/arm64/boot/dts/vendor/qcom/kona-v2.1-gpu.dtsi << 'EOF'
&msm_gpu {
	qcom,chipid = <0x06050002>;
};
EOF
echo "[+] kona-v2.1-gpu.dtsi set to pure FakeDreamer chipid override"

# ------------------------------------------
# 5. Inject EXTREME+ Governor
# ------------------------------------------
echo "[*] Injecting stock-schedutil-based EXTREME+ Governor into kernel/sched/..."
if [ -f "cpufreq_extreme_plus.c" ]; then
    cp -f cpufreq_extreme_plus.c kernel/sched/cpufreq_extreme_plus.c
    echo "[+] Copied cpufreq_extreme_plus.c to kernel/sched/"
fi

if ! grep -q "cpufreq_extreme_plus.o" kernel/sched/Makefile; then
    echo 'obj-$(CONFIG_CPU_FREQ_GOV_EXTREME_PLUS) += cpufreq_extreme_plus.o' >> kernel/sched/Makefile
    echo "[+] Hooked cpufreq_extreme_plus.o into kernel/sched/Makefile"
fi

python3 -c '
path_kconfig = "drivers/cpufreq/Kconfig"
with open(path_kconfig, "r") as f:
    text = f.read()

gov_choice = """config CPU_FREQ_DEFAULT_GOV_EXTREME_PLUS
\tbool "extreme+"
\tdepends on SMP
\tselect CPU_FREQ_GOV_EXTREME_PLUS
\tselect CPU_FREQ_GOV_PERFORMANCE
\thelp
\t  Use the "extreme+" CPUFreq governor by default.
"""

gov_def = """config CPU_FREQ_GOV_EXTREME_PLUS
\tbool "\x27extreme+\x27 cpufreq policy governor"
\tdepends on CPU_FREQ && SMP
\tselect CPU_FREQ_GOV_SCHEDUTIL
\tselect CPU_FREQ_GOV_ATTR_SET
\tselect IRQ_WORK
\thelp
\t  Stock AstideLabs CAF/WALT schedutil algorithm with an EKM profile layer.
"""

if "CPU_FREQ_GOV_EXTREME_PLUS" not in text:
    text = text.replace("config CPU_FREQ_DEFAULT_GOV_SCHEDUTIL", gov_choice + "\nconfig CPU_FREQ_DEFAULT_GOV_SCHEDUTIL")
    text = text.replace("config CPU_FREQ_GOV_SCHEDUTIL", gov_def + "\nconfig CPU_FREQ_GOV_SCHEDUTIL")
    with open(path_kconfig, "w") as f:
        f.write(text)
    print("✅ Injected EXTREME+ governor definitions into drivers/cpufreq/Kconfig")
'

# ------------------------------------------
# 5b. ZRAM ZSTD level 3
# ------------------------------------------
echo "[*] Switching ZRAM to ZSTD level 3..."
if [ -f "apply-zram-zstd.py" ]; then
    python3 apply-zram-zstd.py
else
    echo "❌ [ERROR] apply-zram-zstd.py is missing."
    exit 1
fi

# ------------------------------------------
# 6. Apply Performance, EAS, Charging & VM Patches
# ------------------------------------------
[ -f "apply-cpu-cap.py" ] && python3 apply-cpu-cap.py 3187200
[ -f "apply-fastcharge-bypass.py" ] && python3 apply-fastcharge-bypass.py
[ -f "apply-bootloader-spoof.py" ] && python3 apply-bootloader-spoof.py . || true
[ -f "apply-eas-tuning.py" ] && python3 apply-eas-tuning.py arch/arm64/boot/dts/vendor/qcom/kona.dtsi || true
[ -f "apply-vmscan-critical.py" ] && python3 apply-vmscan-critical.py mm/vmscan.c || true
[ -f "apply-millet-compat.py" ] && python3 apply-millet-compat.py . || true

# Hardening fs/susfs.c against Clang warnings
if [ -f "fs/susfs.c" ]; then
    python3 -c '
with open("fs/susfs.c", "r") as f:
    c = f.read()
c = c.replace("size_t copied_size = 0;", "size_t copied_size __maybe_unused = 0;")
c = c.replace("char *buf_ptr = NULL;", "char *buf_ptr __maybe_unused = NULL;")
with open("fs/susfs.c", "w") as f:
    f.write(c)
' || true
fi

if [ -f "fs/Makefile" ] && ! grep -q "CFLAGS_susfs.o" fs/Makefile; then
    echo "CFLAGS_susfs.o += -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable" >> fs/Makefile
fi

# ------------------------------------------
# 7. Clone AnyKernel3 Base Template
# ------------------------------------------
echo "[*] Cloning clean AnyKernel3 base template..."
rm -rf anykernel_template
git clone --depth=1 https://github.com/AstideLabs/AnyKernel3 -b kona anykernel_template || \
git clone --depth=1 https://github.com/osm0sis/AnyKernel3 -b master anykernel_template
rm -rf anykernel_template/.git

# ==============================================================================
# MODULAR BUILD FUNCTION (HyperOS vs AOSP)
# ==============================================================================
build_target_os() {
    local OS="$1"
    local ENABLE_ROOT="${2:-0}"
    local OS_UPPER=$(echo "$OS" | tr '[:lower:]' '[:upper:]')
    local ROOT_LABEL="Pure Clean Base"
    local ROOT_BANNER="Pure Clean Base (No Root)"
    local ZIP_SUFFIX="NoRoot"

    if [ "$ENABLE_ROOT" == "1" ]; then
        ROOT_LABEL="BakaSU + SuSFS v2.4 + NoMount"
        ROOT_BANNER="BakaSU + SuSFS v2.4 + NoMount"
        ZIP_SUFFIX="BakaSU_SuSFS_NoMount"
    fi

    local OUT_DIR="${KERNEL_DIR}/out_${OS}"
    local MAKE_OPTS=(
        O="${OUT_DIR}"
        ARCH="${ARCH}"
        SUBARCH="${SUBARCH}"
        LLVM=1
        LLVM_IAS=1
        CC="ccache clang"
        HOSTCC="ccache clang"
        CROSS_COMPILE="${CROSS_COMPILE}"
        CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
    )

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔨 Starting Kernel Compilation for ${DEVICE_NAME} (Target: ${OS_UPPER} | ${ROOT_LABEL})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"

    echo "[*] Generating Defconfig (${DEFCONFIG}) for ${OS_UPPER}..."
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" "${DEFCONFIG}"

    # Cấu hình tính năng cơ bản & ZSTD ZRAM & BBRv3/BBR
    scripts/config --file "${OUT_DIR}/.config" -e BBG
    scripts/config --file "${OUT_DIR}/.config" \
        -e ZRAM -e CRYPTO_ZSTD -e ZSTD_COMMON -e ZSTD_COMPRESS -e ZSTD_DECOMPRESS -e ZRAM_DEF_COMP_ZSTD \
        -d ZRAM_DEF_COMP_LZO -d ZRAM_DEF_COMP_LZORLE -d ZRAM_DEF_COMP_LZ4
    scripts/config --file "${OUT_DIR}/.config" \
        -e CPU_FREQ_GOV_SCHEDUTIL -e CPU_FREQ_GOV_EXTREME_PLUS -e CPU_FREQ_DEFAULT_GOV_EXTREME_PLUS \
        --set-str CPU_FREQ_DEFAULT_GOV "extreme+"
    scripts/config --file "${OUT_DIR}/.config" \
        -e TCP_CONG_BBR -e DEFAULT_BBR --set-str DEFAULT_TCP_CONG "bbr" \
        -e NET_SCH_FQ -e NET_SCH_FQ_CODEL

    # Root Configuration (BakaSU + SuSFS v2.4 + NoMount)
    if [ "$ENABLE_ROOT" -eq 1 ]; then
        echo "[*] Injecting BakaSU + SuSFS v2.4 + NoMount Configuration into ${OS_UPPER} .config...[span_2](start_span)"[span_2](end_span)
        scripts/config --file "${OUT_DIR}/.config" \
            -e KSU \
            -e KSU_SUSFS \
            -e NOMOUNT \
            -e THREAD_INFO_IN_TASK \
            -e KSU_SUSFS_SUS_PATH \
            -e KSU_SUSFS_SUS_MOUNT \
            -e KSU_SUSFS_SUS_KSTAT \
            -e KSU_SUSFS_SPOOF_UNAME \
            -e KSU_SUSFS_ENABLE_LOG \
            -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
            -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
            -e KSU_SUSFS_OPEN_REDIRECT \
            -e KSU_SUSFS_SUS_MAP
    else
        echo "[*] Disabling KSU for Pure Clean Kernel (${OS_UPPER})..."
        scripts/config --file "${OUT_DIR}/.config" -d KSU -d KSU_SUSFS -d NOMOUNT
        sed -i '/CONFIG_KSU/d' "${OUT_DIR}/.config" 2>/dev/null || true
    fi

    # Target Subsystems (HyperOS vs AOSP)
    if [ "$OS" == "hyperos" ]; then
        LOCALVER="-Extreme++Gaming-HyperOS-BMW"
        TITLE="Extreme++Gaming BMW Edition [HyperOS] | POCO F4 (munch)"
        ZIP_BASE="EXTREME++Gaming_BMW_Edition_HyperOS"
        scripts/config --file "${OUT_DIR}/.config" \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK -e SF_BINDER -e OVERLAY_FS -e MIGT -e MIGT_ENERGY_MODEL -e MIHW \
            -e PACKAGE_RUNTIME_INFO -e BINDER_OPT -e KPERFEVENTS -e PERF_HUMANTASK -d LTO_CLANG -e LTO_NONE \
            -e XIAOMI_MIUI -e TASK_DELAY_ACCT -e MIUI_ZRAM_MEMORY_TRACKING -e PERF_HELPER -e BOOTUP_RECLAIM \
            -e MI_RECLAIM -e RTMM -e MILLET_CGROUP -e MILLET_SIG -e MILLET_BINDER -e MILLET_PKG -e MILLET_CORE
    else
        LOCALVER="-Extreme++Gaming-AOSP-BMW"
        TITLE="Extreme++Gaming BMW Edition [AOSP] | POCO F4 (munch)"
        ZIP_BASE="EXTREME++Gaming_BMW_Edition_AOSP"
        scripts/config --file "${OUT_DIR}/.config" \
            --set-str STATIC_USERMODEHELPER_PATH "" \
            -d XIAOMI_MIUI -d MIGT -d MIGT_ENERGY_MODEL -d MIHW -d SF_BINDER -d RTMM -d BOOTUP_RECLAIM \
            -e OVERLAY_FS -e REKERNEL -e REKERNEL_NETWORK -d LTO_CLANG -e LTO_NONE
    fi

    scripts/config --file "${OUT_DIR}/.config" --set-str LOCALVERSION "${LOCALVER}"
    rm -f "${OUT_DIR}/include/config/kernel.release"
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" olddefconfig

    # Biên dịch DTB, DTBO và Image
    echo "[*] Compiling ${OS_UPPER} Master DTB Table, DTBO & Kernel Image..."
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" dtbs dtbo.img dtb Image

    if [ ! -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        echo "❌ [ERROR] ${OS_UPPER} Master Kernel Image did NOT compile!"
        exit 1
    fi

    # Đóng gói AnyKernel3
    local AK_DIR="${KERNEL_DIR}/anykernel_${OS}"
    rm -rf "${AK_DIR}"
    cp -r anykernel_template "${AK_DIR}"

    cp "${OUT_DIR}/arch/arm64/boot/Image" "${AK_DIR}/Image"
    if [ -f "${OUT_DIR}/arch/arm64/boot/dtb" ]; then
        cp "${OUT_DIR}/arch/arm64/boot/dtb" "${AK_DIR}/dtb"
    else
        cat ${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/*.dtb > "${AK_DIR}/dtb"
    fi

    cat > "${AK_DIR}/anykernel.sh" << EOF
### AnyKernel3 Ramdisk Mod Script
## EXTREME++ ${OS_UPPER} Kernel for POCO F4 (munch) - BMW Edition

properties() { '
kernel.string=${TITLE}
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=munch
device.name2=munchin
device.name3=POCO F4
supported.versions=13-17
'; }

BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_BLOCK_DISPLAY=1;

. tools/ak3-core.sh;

ui_print " ";
ui_print " ══════════════════════════════════════════════";
ui_print "  🏎️  EDITION : BMW Gaming Edition (${OS_UPPER}) ";
ui_print "  🛡️  ROOT    : ${ROOT_BANNER} ";
ui_print " ══════════════════════════════════════════════";
ui_print " ";

dump_boot;
write_boot;
ui_print " ✅ Extreme++ Kernel (${OS_UPPER}) Flashed Successfully!";
EOF

    local DATE_TAG="$(date +'%d%b%Y_%H%M')"
    local ZIP_NAME="${ZIP_BASE}_${ZIP_SUFFIX}_${DATE_TAG}.zip"

    (
        cd "${AK_DIR}"
        zip -r9 "../${ZIP_NAME}" ./* -x .gitignore out/ ./*.zip > /dev/null
    )

    echo "[+] SUCCESS! ${OS_UPPER} package ready: ${ZIP_NAME}"
}

# ==============================================================================
# EXECUTE REQUESTED TARGET BUILDS
# ==============================================================================
if [ "$ROOT_MODE" == "noroot" ]; then
    echo "[*] Executing Pure Clean Non-Root Build..."
    sed -i '/CONFIG_KSU/d' "arch/arm64/configs/${DEFCONFIG}" 2>/dev/null || true
    [ "$TARGET_OS" == "hyperos" ] || [ "$TARGET_OS" == "both" ] && build_target_os "hyperos" 0
    [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ] && build_target_os "aosp" 0
elif [ "$ROOT_MODE" == "bakasu" ]; then
    echo "[*] Executing BakaSU + SuSFS v2.4 + NoMount Build..."
    inject_bakasu_susfs_nomount
    [ "$TARGET_OS" == "hyperos" ] || [ "$TARGET_OS" == "both" ] && build_target_os "hyperos" 1
    [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ] && build_target_os "aosp" 1
elif [ "$ROOT_MODE" == "both" ]; then
    echo "[*] DUAL BUILD REQUESTED: Compiling Pure Clean & BakaSU Variants!"
    sed -i '/CONFIG_KSU/d' "arch/arm64/configs/${DEFCONFIG}" 2>/dev/null || true
    [ "$TARGET_OS" == "hyperos" ] || [ "$TARGET_OS" == "both" ] && build_target_os "hyperos" 0
    [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ] && build_target_os "aosp" 0
    inject_bakasu_susfs_nomount
    [ "$TARGET_OS" == "hyperos" ] || [ "$TARGET_OS" == "both" ] && build_target_os "hyperos" 1
    [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ] && build_target_os "aosp" 1
fi

echo "🎉 ALL REQUESTED EXTREME++ BUILDS COMPLETED SUCCESSFULLY!"
exit 0
