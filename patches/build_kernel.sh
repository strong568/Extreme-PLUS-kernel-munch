#!/bin/bash
# ==============================================================================
# EXTREME++ BMW Edition Kernel Build Script
# Maintainer: PandeyJI-9
# Device: POCO F4 (munch) | Targets: HyperOS 4 / HyperOS & AOSP (Android 13–17)
# ==============================================================================

set -e
trap 'echo "❌ [ERROR] Script failed on line $LINENO"; exit 1' ERR

if [ -z "$1" ]; then
    echo "[!] Error: No device specified."
    echo "Usage: $0 <device_name> [ksu_susfs|ksu_no_susfs|noroot|all] [hyperos|aosp|both]"
    exit 1
fi

DEVICE_NAME="$1"
DEFCONFIG="${DEVICE_NAME}_defconfig"

ROOT_MODE="${2:-ksu_susfs}"
ROOT_MODE=$(echo "$ROOT_MODE" | tr '[:upper:]' '[:lower:]')
case "$ROOT_MODE" in
    ksu_susfs|susfs|root)
        ROOT_MODE="ksu_susfs"
        ;;
    ksu_no_susfs|nosusfs|ksu)
        ROOT_MODE="ksu_no_susfs"
        ;;
    noroot|clean|false|0)
        ROOT_MODE="noroot"
        ;;
    all|both)
        ROOT_MODE="all"
        ;;
    *)
        ROOT_MODE="ksu_susfs"
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
echo "🚀 EXTREME++ BMW Edition Build Engine Initiated!"
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

# ZRAM ZSTD, EXTREME+ Governor & GPU Devfreq base symbols
sed -i 's/CONFIG_ZRAM_DEF_COMP_LZ4=y/CONFIG_ZRAM_DEF_COMP_ZSTD=y/' "arch/arm64/configs/${DEFCONFIG}"
grep -q "CONFIG_CRYPTO_ZSTD=y" "arch/arm64/configs/${DEFCONFIG}" || cat >> "arch/arm64/configs/${DEFCONFIG}" << 'EOF'
CONFIG_CRYPTO_ZSTD=y
CONFIG_ZSTD_COMPRESS=y
CONFIG_ZSTD_DECOMPRESS=y
CONFIG_ZRAM_DEF_COMP_ZSTD=y
CONFIG_ZRAM_DEF_COMP="zstd"
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
# 2. Baseband & Network Guard
# ------------------------------------------
echo "[*] Injecting Baseband-guard Setup..."
if ! wget -qO- https://raw.githubusercontent.com/vc-teahouse/Baseband-guard/main/setup.sh | bash; then
    echo "❌ [ERROR] Baseband-guard download failed!"
    exit 1
fi

if ! grep -q "selinux,baseband_guard" security/Kconfig; then
    sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig
fi

# ------------------------------------------
# 3. KernelSU Source & Universal Patch Setup
# ------------------------------------------
setup_ksu_sources() {
    if [ ! -d "drivers/kernelsu" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚡ Injecting ReSukiSU / KowSU Multi-Manager & SuSFS v2.3.0 Source..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s -- v4.2.0-rc3

        # Bỏ qua kiểm tra Tracepoint Hook trên Non-GKI trong Kbuild
        if [ -f "drivers/kernelsu/Kbuild" ]; then
            sed -i '/TP hooks are incompatible with Non-GKI/d' drivers/kernelsu/Kbuild || true
            sed -i '/TP hooks are only supported on GKI 2.0 kernels/d' drivers/kernelsu/Kbuild || true
        fi

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
    hook_replacement = """// Bulletproof Fallback: check known manager package names
    if (check_v2_signature(path, signature_index))
        return true;
    char pkg_buf[128];
    if (get_pkg_from_apk_path(pkg_buf, path) == 0) {
        if (!strcmp(pkg_buf, "me.weishu.kernelsu") ||
            !strcmp(pkg_buf, "org.resukisu.resukisu") ||
            !strcmp(pkg_buf, "org.bakasu.bakasu") ||
            !strcmp(pkg_buf, "com.sukisu.ultra") ||
            !strcmp(pkg_buf, "com.kowx712.supermanager") ||
            !strcmp(pkg_buf, "com.resukisu")) {
            pr_info("PROJECT EXTREME+: Manager recognized by known package name: %s\\n", pkg_buf);
            *signature_index = 0;
            return true;
        }
    }
    return false;"""
    if hook_target in content and "pkg_buf" not in content:
        content = content.replace(hook_target, hook_replacement)
        with open(apk_sign_path, "w") as f:
            f.write(content)
        print("✅ Patched " + apk_sign_path + " with universal manager package verification")
' 2>/dev/null || true
    fi
}

# ------------------------------------------
# 4. Native FakeDreamer Adreno 650 Undervolt & Speed Bins
# ------------------------------------------
echo "[*] Applying Native FakeDreamer GPU Undervolt (150MHz - 670MHz) & Speed Bins..."
if [ -f "kona-v2-gpu.dtsi" ]; then
    cp -f kona-v2-gpu.dtsi arch/arm64/boot/dts/vendor/qcom/kona-v2-gpu.dtsi
fi

cat > arch/arm64/boot/dts/vendor/qcom/kona-v2.1-gpu.dtsi << 'EOF'
&msm_gpu {
	qcom,chipid = <0x06050002>;
};
EOF

# ------------------------------------------
# 5. Inject Custom EXTREME+ Governor
# ------------------------------------------
echo "[*] Injecting Custom EXTREME+ Governor into kernel/sched/..."
if [ -f "cpufreq_extreme_plus.c" ]; then
    cp -f cpufreq_extreme_plus.c kernel/sched/cpufreq_extreme_plus.c
fi

if ! grep -q "cpufreq_extreme_plus.o" kernel/sched/Makefile; then
    echo 'obj-$(CONFIG_CPU_FREQ_GOV_EXTREME_PLUS) += cpufreq_extreme_plus.o' >> kernel/sched/Makefile
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
\tselect CPU_FREQ_GOV_ATTR_SET
\tselect IRQ_WORK
\thelp
\t  EXTREME+ governor based on scheduler utilization.
"""

if "CPU_FREQ_GOV_EXTREME_PLUS" not in text:
    text = text.replace("config CPU_FREQ_DEFAULT_GOV_SCHEDUTIL", gov_choice + "\nconfig CPU_FREQ_DEFAULT_GOV_SCHEDUTIL")
    text = text.replace("config CPU_FREQ_GOV_SCHEDUTIL", gov_def + "\nconfig CPU_FREQ_GOV_SCHEDUTIL")
    with open(path_kconfig, "w") as f:
        f.write(text)
'

# ------------------------------------------
# 6. Apply Performance, EAS, Charging & VM Patches
# ------------------------------------------
[ -f "apply-cpu-cap.py" ] && python3 apply-cpu-cap.py 3187200
[ -f "apply-fastcharge-bypass.py" ] && python3 apply-fastcharge-bypass.py
[ -f "apply-bootloader-spoof.py" ] && python3 apply-bootloader-spoof.py . || true
[ -f "apply-eas-tuning.py" ] && python3 apply-eas-tuning.py arch/arm64/boot/dts/vendor/qcom/kona.dtsi || true
[ -f "apply-vmscan-critical.py" ] && python3 apply-vmscan-critical.py mm/vmscan.c || true
[ -f "apply-millet-compat.py" ] && python3 apply-millet-compat.py . || true

if [ -f "kernel/sched/cpufreq_schedutil.c" ]; then
    sed -i 's/tunables->up_rate_limit_us = CONFIG_SCHEDUTIL_UP_RATE_LIMIT;/tunables->up_rate_limit_us = 0;/' kernel/sched/cpufreq_schedutil.c
fi

if [ -f "fs/dcache.c" ]; then
    sed -i 's/int sysctl_vfs_cache_pressure __read_mostly = [0-9]*;/int sysctl_vfs_cache_pressure __read_mostly = 50;/' fs/dcache.c
fi

# ------------------------------------------
# 7. AnyKernel3 Template
# ------------------------------------------
echo "[*] Cloning AnyKernel3 base template..."
rm -rf anykernel_template
if ! git clone --depth=1 https://github.com/re-noroi/anykernel3-test -b munch anykernel_template; then
    git clone --depth=1 https://github.com/AstideLabs/AnyKernel3 -b kona anykernel_template
fi
rm -rf anykernel_template/.git

# ==============================================================================
# MODULAR BUILD FUNCTION
# ==============================================================================
build_target_os() {
    local OS="$1"
    local ENABLE_KSU="${2:-0}"
    local ENABLE_SUSFS="${3:-0}"
    local OS_UPPER=$(echo "$OS" | tr '[:lower:]' '[:upper:]')
    
    local ROOT_LABEL="Pure Clean Base"
    local FILE_SUFFIX="NoRoot"
    if [ "$ENABLE_KSU" -eq 1 ]; then
        if [ "$ENABLE_SUSFS" -eq 1 ]; then
            ROOT_LABEL="KowSU + SuSFS v2.3.0"
            FILE_SUFFIX="KSU_SuSFS"
        else
            ROOT_LABEL="KowSU (No SuSFS)"
            FILE_SUFFIX="KSU_NoSuSFS"
        fi
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
        KCFLAGS="-Wno-error"
        KCPPFLAGS="-Wno-error"
    )

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔨 Starting Compilation: ${DEVICE_NAME} (OS: ${OS_UPPER} | Mode: ${ROOT_LABEL})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"

    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" "${DEFCONFIG}"

    # General Hardware & Scheduler Flags
    scripts/config --file "${OUT_DIR}/.config" \
        -e BBG \
        -e PM_DEVFREQ \
        -e DEVFREQ_GOV_SIMPLE_ONDEMAND \
        -e DEVFREQ_GOV_PERFORMANCE \
        -e DEVFREQ_GOV_POWERSAVE \
        -e DEVFREQ_GOV_USERSPACE \
        -e DEVFREQ_GOV_PASSIVE \
        -e DEVFREQ_GOV_QCOM_ADRENO_TZ \
        -e DEVFREQ_GOV_QCOM_GPUBW_MON \
        -e QCOM_KGSL \
        -e QCOM_KGSL_IOMMU \
        --set-str QCOM_ADRENO_DEFAULT_GOVERNOR "msm-adreno-tz" \
        -e ZRAM \
        -e CRYPTO_ZSTD \
        -e ZSTD_COMPRESS \
        -e ZSTD_DECOMPRESS \
        -e ZRAM_DEF_COMP_ZSTD \
        -d ZRAM_DEF_COMP_LZ4 \
        --set-str ZRAM_DEF_COMP "zstd" \
        -e CPU_FREQ_GOV_SCHEDUTIL \
        -e CPU_FREQ_GOV_EXTREME_PLUS \
        -e CPU_FREQ_DEFAULT_GOV_EXTREME_PLUS \
        -d CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
        --set-str CPU_FREQ_DEFAULT_GOV "extreme+" \
        -e TCP_CONG_BBR \
        -e DEFAULT_BBR \
        --set-str DEFAULT_TCP_CONG "bbr" \
        -e NET_SCH_FQ \
        -e NET_SCH_FQ_CODEL \
        -d TASK_IO_ACCOUNTING \
        -d BLK_DEV_IO_TRACE \
        -d SCHEDSTATS \
        -d PROVE_LOCKING \
        -d LOCKDEP \
        -d LOCK_STAT \
        -d DEBUG_KMEMLEAK \
        -d DEBUG_PREEMPT

    # Root Configuration (KSU + SuSFS vs KSU No SuSFS vs Noroot)
    if [ "$ENABLE_KSU" -eq 1 ]; then
        if [ "$ENABLE_SUSFS" -eq 1 ]; then
            echo "[*] Injecting KowSU + SuSFS v2.3.0 Config..."
            scripts/config --file "${OUT_DIR}/.config" \
                -e KSU \
                -e KSU_SUSFS \
                -d KSU_TRACEPOINT_HOOK \
                -e KSU_MANUAL_HOOK \
                -e KSU_MULTI_MANAGER_SUPPORT \
                -e THREAD_INFO_IN_TASK \
                -e KSU_SUSFS_SUS_PATH \
                -e KSU_SUSFS_SUS_MOUNT \
                -e KSU_SUSFS_SUS_KSTAT \
                -e KSU_SUSFS_SPOOF_UNAME \
                -e KSU_SUSFS_ENABLE_LOG \
                -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
                -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
                -e KSU_SUSFS_OPEN_REDIRECT \
                -e KSU_SUSFS_SUS_MAP \
                -d KSU_DISABLE_MANAGER \
                -d KSU_DISABLE_POLICY
        else
            echo "[*] Injecting KowSU (No SuSFS) Config..."
            scripts/config --file "${OUT_DIR}/.config" \
                -e KSU \
                -d KSU_SUSFS \
                -d KSU_TRACEPOINT_HOOK \
                -e KSU_MANUAL_HOOK \
                -e KSU_MULTI_MANAGER_SUPPORT \
                -d KSU_DISABLE_MANAGER \
                -d KSU_DISABLE_POLICY
            sed -i '/CONFIG_KSU_SUSFS/d' "${OUT_DIR}/.config" 2>/dev/null || true
        fi
    else
        echo "[*] Disabling embedded KSU for Pure Clean Kernel..."
        scripts/config --file "${OUT_DIR}/.config" \
            -d KSU \
            -d KSU_SUSFS \
            -d KSU_TRACEPOINT_HOOK \
            -d KSU_MANUAL_HOOK \
            -d KSU_MULTI_MANAGER_SUPPORT
        sed -i '/CONFIG_KSU/d' "${OUT_DIR}/.config" 2>/dev/null || true
    fi

    # OS Subsystems
    local LOCALVER
    local TITLE
    local ZIP_BASE

    if [ "$OS" == "hyperos" ]; then
        LOCALVER="-Extreme++Gaming-HyperOS-BMW"
        TITLE="Extreme++Gaming BMW Edition [HyperOS] | POCO F4 (munch)"
        ZIP_BASE="EXTREME++Gaming_BMW_Edition_HyperOS"

        scripts/config --file "${OUT_DIR}/.config" \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK \
            -e SF_BINDER \
            -e OVERLAY_FS \
            -e MIGT \
            -e MIGT_ENERGY_MODEL \
            -e MIHW \
            -e PACKAGE_RUNTIME_INFO \
            -e BINDER_OPT \
            -e KPERFEVENTS \
            -e PERF_HUMANTASK \
            -d LTO_CLANG \
            -e LTO_NONE \
            -d SHADOW_CALL_STACK \
            -e XIAOMI_MIUI \
            -d MI_MEMORY_SYSFS \
            -e TASK_DELAY_ACCT \
            -e MIUI_ZRAM_MEMORY_TRACKING \
            -e PERF_HELPER \
            -e BOOTUP_RECLAIM \
            -e MI_RECLAIM \
            -e RTMM \
            -e MILLET_CGROUP \
            -e MILLET_SIG \
            -e MILLET_BINDER \
            -e MILLET_PKG \
            -e MILLET_BINDER_GKI \
            -e MILLET_CORE \
            -e MILLET_HS \
            -e BINDER_PRIO \
            -d REKERNEL \
            -d REKERNEL_NETWORK \
            -d LTO_CLANG_THIN -d CFI_CLANG
    else
        LOCALVER="-Extreme++Gaming-AOSP-BMW"
        TITLE="Extreme++Gaming BMW Edition [AOSP A16/A17] | POCO F4 (munch)"
        ZIP_BASE="EXTREME++Gaming_BMW_Edition_AOSP"

        scripts/config --file "${OUT_DIR}/.config" \
            --set-str STATIC_USERMODEHELPER_PATH "" \
            -d XIAOMI_MIUI \
            -d MIGT \
            -d MIGT_ENERGY_MODEL \
            -d MIHW \
            -d SF_BINDER \
            -d RTMM \
            -d BOOTUP_RECLAIM \
            -d MI_RECLAIM \
            -d PERF_HELPER \
            -d PERF_HUMANTASK \
            -d PERF_CRITICAL_RT_TASK \
            -d MILLET_CGROUP \
            -d MILLET_SIG \
            -d MILLET_BINDER \
            -d MILLET_PKG \
            -d MILLET_BINDER_GKI \
            -d MILLET_CORE \
            -d MILLET_HS \
            -d BINDER_PRIO \
            -d PACKAGE_RUNTIME_INFO \
            -d BINDER_OPT \
            -d MIUI_ZRAM_MEMORY_TRACKING \
            -d MI_MEMORY_SYSFS \
            -e OVERLAY_FS \
            -e REKERNEL \
            -e REKERNEL_NETWORK \
            -d LTO_CLANG \
            -e LTO_NONE \
            -d SHADOW_CALL_STACK \
            -d LTO_CLANG_THIN -d CFI_CLANG
    fi

    scripts/config --file "${OUT_DIR}/.config" --set-str LOCALVERSION "${LOCALVER}"
    rm -f "${OUT_DIR}/include/config/kernel.release"
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" olddefconfig

    echo "[*] Compiling DTBs & DTBO Image..."
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" dtbs dtbo.img dtb

    echo "[*] Compiling Image..."
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" Image

    if [ ! -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        echo "❌ [ERROR] Image compile failed for ${OS_UPPER}!"
        exit 1
    fi

    local AK_DIR="${KERNEL_DIR}/anykernel_${OS}"
    rm -rf "${AK_DIR}"
    cp -r anykernel_template "${AK_DIR}"

    cp "${OUT_DIR}/arch/arm64/boot/Image" "${AK_DIR}/Image"
    if [ -f "${OUT_DIR}/arch/arm64/boot/dtb" ]; then
        cp "${OUT_DIR}/arch/arm64/boot/dtb" "${AK_DIR}/dtb"
    elif [ -f "${OUT_DIR}/arch/arm64/boot/dtb.img" ]; then
        cp "${OUT_DIR}/arch/arm64/boot/dtb.img" "${AK_DIR}/dtb"
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
device.name2=POCO F4
supported.versions=13-17
'; }

block=boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=0;

. tools/ak3-core.sh;

ui_print " ";
ui_print " ══════════════════════════════════════════════";
ui_print "  🏎️  EDITION : BMW Gaming Edition (${OS_UPPER}) ";
ui_print "  👑  AUTHOR  : Extreme++ by @pandey_ji_8      ";
ui_print "  📱  DEVICE  : POCO F4 (munch) | ${OS_UPPER}  ";
ui_print "  ⚡  CLOCK   : 3.19 GHz Unlocked Monster Peak ";
ui_print "  🛡️  ROOT    : ${ROOT_LABEL} ";
ui_print " ══════════════════════════════════════════════";
ui_print " ";

dump_boot;
write_boot;

block=vendor_boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=0;

reset_ak;
dump_boot;
write_boot;

mount /data 2>/dev/null
if [ -d /data/adb ]; then
    rm -f /data/adb/service.d/00-extreme-performance.sh
    rm -f /data/adb/post-fs-data.d/00-extreme-props.sh
fi

ui_print "  🎉 Extreme++ Kernel (${OS_UPPER}) Flashed!  ";
ui_print " ══════════════════════════════════════════════";
EOF

    local DATE_TAG="$(date +'%d%b%Y_%H%M')"
    local ZIP_NAME="${ZIP_BASE}_${FILE_SUFFIX}_${DATE_TAG}.zip"

    (
        cd "${AK_DIR}"
        zip -r9 "../${ZIP_NAME}" ./* -x .gitignore out/ ./*.zip > /dev/null
    )
    echo "[+] SUCCESS! ${ZIP_NAME}"
}

# ------------------------------------------
# Trình điều phối Build theo OS và ROOT_MODE
# ------------------------------------------
run_build() {
    local OS_TARGET="$1"
    local KSU_FLAG="$2"
    local SUSFS_FLAG="$3"

    if [ "$OS_TARGET" == "hyperos" ] || [ "$OS_TARGET" == "both" ]; then
        build_target_os "hyperos" "$KSU_FLAG" "$SUSFS_FLAG"
    fi
    if [ "$OS_TARGET" == "aosp" ] || [ "$OS_TARGET" == "both" ]; then
        build_target_os "aosp" "$KSU_FLAG" "$SUSFS_FLAG"
    fi
}

case "$ROOT_MODE" in
    ksu_susfs)
        setup_ksu_sources
        run_build "$TARGET_OS" 1 1
        ;;
    ksu_no_susfs)
        setup_ksu_sources
        run_build "$TARGET_OS" 1 0
        ;;
    noroot)
        run_build "$TARGET_OS" 0 0
        ;;
    all)
        echo "🚀 COMPILING ALL 3 VARIANTS: NoRoot, KSU No-SuSFS, KSU+SuSFS..."
        # 1. No Root
        run_build "$TARGET_OS" 0 0
        
        # 2. Setup nguồn KSU
        setup_ksu_sources
        
        # 3. KSU No SuSFS
        run_build "$TARGET_OS" 1 0
        
        # 4. KSU + SuSFS
        run_build "$TARGET_OS" 1 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 ALL REQUESTED EXTREME++ BUILDS COMPLETED SUCCESSFULLY!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
