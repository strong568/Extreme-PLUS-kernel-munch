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
    echo "Usage: $0 <device_name> [ksu|noroot] [hyperos|aosp|both] [ksu_provider]"
    exit 1
fi

DEVICE_NAME="$1"
DEFCONFIG="${DEVICE_NAME}_defconfig"
ENABLE_KSU=0

if [ "$2" == "ksu" ] || [ "$2" == "true" ] || [ "$2" == "1" ]; then
    ENABLE_KSU=1
fi

TARGET_OS="${3:-both}"
TARGET_OS=$(echo "$TARGET_OS" | tr '[:upper:]' '[:lower:]')
case "$TARGET_OS" in
    hyperos|miui) TARGET_OS="hyperos" ;;
    aosp) TARGET_OS="aosp" ;;
    *) TARGET_OS="both" ;;
esac

KSU_PROVIDER="${4:-midori01/KernelSU}"

# Rút gọn tên KSU Engine
KSU_SHORT_NAME="KSU"
case "${KSU_PROVIDER}" in
    "midori01/KernelSU"|"Midori-SU/KernelSU") KSU_SHORT_NAME="MidoriSU" ;;
    "ReSukiSU/ReSukiSU")                     KSU_SHORT_NAME="ReSukiSU" ;;
    "Baka-SU/BakaSU")                        KSU_SHORT_NAME="BakaSU" ;;
    "SukiSU-Ultra/SukiSU-Ultra")             KSU_SHORT_NAME="SukiSU-Ultra" ;;
    "KernelSU-Next/KernelSU-Next")           KSU_SHORT_NAME="KSU-Next" ;;
    "KOWX712/KernelSU")                      KSU_SHORT_NAME="KowSU" ;;
    "rsuntk/KernelSU")                       KSU_SHORT_NAME="rsuntkKSU" ;;
    "backslashxx/KernelSU")                  KSU_SHORT_NAME="backslashxxKSU" ;;
    "tiann/KernelSU")                        KSU_SHORT_NAME="OfficialKSU" ;;
    *)                                       KSU_SHORT_NAME="KSU" ;;
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
[ "$TOTAL_CORES" -gt 4 ] && TOTAL_CORES=4

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 EXTREME++ BMW Edition Build Engine Initiated!"
echo "   Device: POCO F4 (munch / SM8250-AC)"
echo "   Root Mode: $([ "$ENABLE_KSU" -eq 1 ] && echo "${KSU_PROVIDER} Multi-Manager + SuSFS" || echo 'Pure Clean Base')"
echo "   Target Mode: ${TARGET_OS}"
echo "   System Cores Allocated: ${TOTAL_CORES}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ------------------------------------------
# 1. Base Cleanup & Custom Defconfig Tunables
# ------------------------------------------
echo "[*] Cleaning previous temporary outputs..."
rm -rf out out_hyperos out_aosp anykernel anykernel_* EXTREME++*.zip
find . -type f \( -name "dtbo.img" -o -name "Image" -o -name "Image.gz" \) -delete

rm -rf include/config include/generated arch/arm64/include/generated

# XÓA TRIỆT ĐỂ -Werror TRÊN TẤT CẢ DRIVER STAGING VÀ WI-FI
find drivers/staging -type f \( -name "Makefile" -o -name "Kbuild" \) -exec sed -i 's/-Werror//g' {} + 2>/dev/null || true

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
# 3. Dynamic KernelSU Provider Setup
# ------------------------------------------
SUSFS_VERSION="v2.3.0"

if [ "$ENABLE_KSU" -eq 1 ]; then
    echo "[*] Injecting selected KernelSU: ${KSU_PROVIDER}..."
    case "${KSU_PROVIDER}" in
        "midori01/KernelSU"|"Midori-SU/KernelSU")
            curl -fLSs "https://raw.githubusercontent.com/midori01/KernelSU/main/kernel/setup.sh" | bash -s -- main
            ;;
        "ReSukiSU/ReSukiSU")
            curl -fLSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s -- v4.2.0-rc3
            ;;
        "Baka-SU/BakaSU")
            curl -fLSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/refs/heads/main/kernel/setup.sh" | bash -s -- main
            ;;
        "tiann/KernelSU")
            curl -fLSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s -- main
            ;;
        "SukiSU-Ultra/SukiSU-Ultra")
            curl -fLSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s -- main || \
            curl -fLSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s -- main
            ;;
        "backslashxx/KernelSU")
            curl -fLSs "https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh" | bash -s -- master
            ;;
        "KernelSU-Next/KernelSU-Next")
            curl -fLSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s -- next
            ;;
        "KOWX712/KernelSU")
            curl -fLSs "https://raw.githubusercontent.com/KOWX712/KernelSU/main/kernel/setup.sh" | bash -s -- main
            ;;
        "rsuntk/KernelSU")
            curl -fLSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s -- main
            ;;
        *)
            curl -fLSs "https://raw.githubusercontent.com/midori01/KernelSU/main/kernel/setup.sh" | bash -s -- main
            ;;
    esac

    DETECTED_SUSFS=""
    if [ -f "include/linux/susfs.h" ]; then
        DETECTED_SUSFS=$(grep -m1 -E "SUSFS_VERSION[[:space:]]+\"v[0-9]" include/linux/susfs.h | grep -oE "v[0-9]+\.[0-9]+(\.[0-9]+)?" || true)
    fi
    if [ -z "$DETECTED_SUSFS" ] && [ -f "fs/susfs.c" ]; then
        DETECTED_SUSFS=$(grep -m1 -E "SUSFS_VERSION[[:space:]]+\"v[0-9]" fs/susfs.c | grep -oE "v[0-9]+\.[0-9]+(\.[0-9]+)?" || true)
    fi
    if [ -z "$DETECTED_SUSFS" ]; then
        DETECTED_SUSFS=$(grep -rohE --include="*.h" --include="*.c" "SUSFS_VERSION.*\"v[0-9][^\"]*\"" drivers/kernelsu/ fs/susfs/ include/linux/ 2>/dev/null | grep -oE "v[0-9]+\.[0-9]+(\.[0-9]+)?" | head -n 1 || true)
    fi

    if [ -n "$DETECTED_SUSFS" ]; then
        SUSFS_VERSION="$DETECTED_SUSFS"
    fi
    echo "🔎 [SuSFS Scanner] Detected SuSFS Version: ${SUSFS_VERSION}"

    if [ -f "drivers/kernelsu/Kconfig" ]; then
        sed -i 's/default KSU_TRACEPOINT_HOOK/default KSU_SUSFS/' drivers/kernelsu/Kconfig 2>/dev/null || true
    fi

    python3 -c '
import os, glob

ksu_dir = "drivers/kernelsu"
if os.path.isdir(ksu_dir):
    has_sys_read = False
    has_init_rc = False
    for root, _, files in os.walk(ksu_dir):
        for f in files:
            if f.endswith(".c"):
                try:
                    with open(os.path.join(root, f), "r", errors="ignore") as fp:
                        txt = fp.read()
                        if "ksu_handle_sys_read" in txt:
                            has_sys_read = True
                        if "ksu_is_init_rc_hook_enabled" in txt:
                            has_init_rc = True
                except:
                    pass

    missing_stubs = []
    if not has_sys_read:
        missing_stubs.append("""
#include <linux/types.h>
int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr) {
    return 0;
}
""")
    if not has_init_rc:
        missing_stubs.append("""
#include <linux/types.h>
bool ksu_is_init_rc_hook_enabled = false;
""")

    if missing_stubs:
        stub_file = os.path.join(ksu_dir, "ksu_compat_stub.c")
        with open(stub_file, "w") as fp:
            fp.write("// Auto-generated compatibility stubs\n" + "\n".join(missing_stubs))
        
        mk_file = os.path.join(ksu_dir, "Makefile")
        if os.path.exists(mk_file):
            with open(mk_file, "r") as fp:
                mk_content = fp.read()
            if "ksu_compat_stub.o" not in mk_content:
                with open(mk_file, "a") as fp:
                    fp.write("\nobj-y += ksu_compat_stub.o\n")
        print("✅ Added missing KSU symbol stubs (ksu_handle_sys_read / ksu_is_init_rc_hook_enabled)")
' 2>/dev/null || true

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
    hook_replacement = """// Universal Multi-Manager Fallback
    if (check_v2_signature(path, signature_index))
        return true;
    char pkg_buf[128];
    if (get_pkg_from_apk_path(pkg_buf, path) == 0) {
        if (!strcmp(pkg_buf, "me.weishu.kernelsu") ||
            !strcmp(pkg_buf, "org.resukisu.resukisu") ||
            !strcmp(pkg_buf, "org.bakasu.bakasu") ||
            !strcmp(pkg_buf, "com.sukisu.ultra") ||
            !strcmp(pkg_buf, "com.kowx712.supermanager") ||
            !strcmp(pkg_buf, "com.midori.kernelsu") ||
            !strcmp(pkg_buf, "com.resukisu")) {
            pr_info("EXTREME+: Manager recognized: %s\\n", pkg_buf);
            *signature_index = 0;
            return true;
        }
    }
    return false;"""
    if hook_target in content and "pkg_buf" not in content:
        content = content.replace(hook_target, hook_replacement)
        with open(apk_sign_path, "w") as f:
            f.write(content)
        print("✅ Patched " + apk_sign_path + " with multi-manager validation")
' 2>/dev/null || true

    echo "CONFIG_KSU=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_KSU_SUSFS=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_KSU_MULTI_MANAGER_SUPPORT=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_THREAD_INFO_IN_TASK=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "[+] KernelSU setup finished."
else
    echo "[*] Ensuring Pure Clean Kernel Base..."
    sed -i '/CONFIG_KSU/d' "arch/arm64/configs/${DEFCONFIG}" 2>/dev/null || true
fi

# ------------------------------------------
# 4. Native FakeDreamer Adreno 650 Undervolt & Speed Bins
# ------------------------------------------
echo "[*] Applying Native FakeDreamer GPU Undervolt & Speed Bins..."
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
"""

gov_def = """config CPU_FREQ_GOV_EXTREME_PLUS
\tbool "\x27extreme+\x27 cpufreq policy governor"
\tdepends on CPU_FREQ && SMP
\tselect CPU_FREQ_GOV_ATTR_SET
\tselect IRQ_WORK
"""

if "CPU_FREQ_GOV_EXTREME_PLUS" not in text:
    text = text.replace("config CPU_FREQ_DEFAULT_GOV_SCHEDUTIL", gov_choice + "\nconfig CPU_FREQ_DEFAULT_GOV_SCHEDUTIL")
    text = text.replace("config CPU_FREQ_GOV_SCHEDUTIL", gov_def + "\nconfig CPU_FREQ_GOV_SCHEDUTIL")
    with open(path_kconfig, "w") as f:
        f.write(text)
' 2>/dev/null || true

# ------------------------------------------
# 6. Apply Performance, EAS, Charging & VM Patches
# ------------------------------------------
[ -f "apply-cpu-cap.py" ] && python3 apply-cpu-cap.py 3187200 || true
[ -f "apply-fastcharge-bypass.py" ] && python3 apply-fastcharge-bypass.py || true
[ -f "apply-bootloader-spoof.py" ] && python3 apply-bootloader-spoof.py . || true
[ -f "apply-eas-tuning.py" ] && python3 apply-eas-tuning.py arch/arm64/boot/dts/vendor/qcom/kona.dtsi || true

if [ -f "kernel/sched/cpufreq_schedutil.c" ]; then
    sed -i 's/tunables->up_rate_limit_us = CONFIG_SCHEDUTIL_UP_RATE_LIMIT;/tunables->up_rate_limit_us = 0;/' kernel/sched/cpufreq_schedutil.c
fi

if [ -f "fs/dcache.c" ]; then
    sed -i 's/int sysctl_vfs_cache_pressure __read_mostly = [0-9]*;/int sysctl_vfs_cache_pressure __read_mostly = 50;/' fs/dcache.c
fi

# ------------------------------------------
# 7. Clone AnyKernel3 Base Template
# ------------------------------------------
echo "[*] Cloning AnyKernel3 template..."
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
    local OS_UPPER=$(echo "$OS" | tr '[:lower:]' '[:upper:]')
    local OUT_DIR="${KERNEL_DIR}/out_${OS}"
    local MAKE_OPTS=(
        O="${OUT_DIR}"
        ARCH="${ARCH}"
        SUBARCH="${SUBARCH}"
        LLVM=1
        LLVM_IAS=1
        CC="ccache clang"
        HOSTCC="ccache clang"
        HOSTCFLAGS="-w"
        HOSTCXXFLAGS="-w"
        CROSS_COMPILE="${CROSS_COMPILE}"
        CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
        KCFLAGS="-w -Wno-error"
        CFLAGS_KERNEL="-w"
    )

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔨 Compiling for ${DEVICE_NAME} (Target: ${OS_UPPER})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"
    rm -rf include/config include/generated arch/arm64/include/generated

    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" "${DEFCONFIG}"

    # Cấu hình .config
    scripts/config --file "${OUT_DIR}/.config" -e BBG
    scripts/config --file "${OUT_DIR}/.config" \
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
        --set-str QCOM_ADRENO_DEFAULT_GOVERNOR "msm-adreno-tz"

    scripts/config --file "${OUT_DIR}/.config" \
        -e ZRAM \
        -e CRYPTO_ZSTD \
        -e ZSTD_COMPRESS \
        -e ZSTD_DECOMPRESS \
        -e ZRAM_DEF_COMP_ZSTD \
        -d ZRAM_DEF_COMP_LZ4 \
        --set-str ZRAM_DEF_COMP "zstd"

    scripts/config --file "${OUT_DIR}/.config" \
        -e CPU_FREQ_GOV_SCHEDUTIL \
        -e CPU_FREQ_GOV_EXTREME_PLUS \
        -e CPU_FREQ_DEFAULT_GOV_EXTREME_PLUS \
        -d CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
        --set-str CPU_FREQ_DEFAULT_GOV "extreme+"

    scripts/config --file "${OUT_DIR}/.config" \
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

    if [ "$ENABLE_KSU" -eq 1 ]; then
        scripts/config --file "${OUT_DIR}/.config" \
            -e KSU \
            -e KSU_SUSFS \
            -d KSU_TRACEPOINT_HOOK \
            -d KSU_MANUAL_HOOK \
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
        scripts/config --file "${OUT_DIR}/.config" -d KSU -d KSU_SUSFS
        sed -i '/CONFIG_KSU/d' "${OUT_DIR}/.config" 2>/dev/null || true
    fi

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

    echo "[*] Compiling DTBs & Images for ${OS_UPPER}..."
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" dtbs dtbo.img dtb
    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" Image

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
ui_print " Flash EXTREME++ BMW Edition (${OS_UPPER})";
dump_boot;
write_boot;
block=vendor_boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=0;
reset_ak;
dump_boot;
write_boot;
EOF

    local DATE_TAG="$(date +'%d%b%Y_%H%M')"
    local ZIP_NAME
    if [ "$ENABLE_KSU" -eq 1 ]; then
        ZIP_NAME="${ZIP_BASE}_${KSU_SHORT_NAME}_SUSFS_${SUSFS_VERSION}_${DATE_TAG}.zip"
    else
        ZIP_NAME="${ZIP_BASE}_NoRoot_${DATE_TAG}.zip"
    fi

    (
        cd "${AK_DIR}"
        zip -r9 "../${ZIP_NAME}" ./* -x .gitignore out/ ./*.zip > /dev/null
    )
    echo "[+] =========================================================="
    echo "[+] SUCCESS! Package ready: ${ZIP_NAME}"
    echo "[+] =========================================================="
}

if [ "$TARGET_OS" == "hyperos" ] || [ "$TARGET_OS" == "both" ]; then
    build_target_os "hyperos"
fi

if [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ]; then
    build_target_os "aosp"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 ALL BUILDS COMPLETED SUCCESSFULLY!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
