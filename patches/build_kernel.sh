#!/bin/bash
# ==========================================
# EXTREME++ HyperOS Kernel Build Script
# Maintainer: PandeyJI-9
# Device: POCO F4 (munch) | Target: HyperOS ONLY
# ==========================================

set -e
trap 'echo "❌ [ERROR] Script failed on line $LINENO"; exit 1' ERR

if [ -z "$1" ]; then
    echo "[!] Error: No device specified."
    exit 1
fi

DEVICE_NAME="$1"
DEFCONFIG="${DEVICE_NAME}_defconfig"
ENABLE_KSU=0

if [ "$2" == "ksu" ] || [ "$2" == "true" ] || [ "$2" == "1" ]; then
    ENABLE_KSU=1
fi

KERNEL_DIR="$(pwd)"
OUT_DIR="${KERNEL_DIR}/out"
TOOLCHAIN_BIN="$HOME/zyc-clang/bin"

export PATH="${TOOLCHAIN_BIN}:${PATH}"
export ARCH="arm64"
export SUBARCH="arm64"
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
export CCACHE_EXEC=$(command -v ccache)
export USE_CCACHE=1

# ------------------------------------------
# 🚀 SYSTEM CORES SETUP (Full Speed)
# ------------------------------------------
TOTAL_CORES=$(nproc --all)
echo "[*] System Cores: ${TOTAL_CORES} | Running at FULL SPEED!"
echo "[*] Cleaning previous builds..."
rm -rf "${OUT_DIR}" anykernel
mkdir -p "${OUT_DIR}"
find . -type f \( -name "dtbo.img" -o -name "Image" -o -name "Image.gz" \) -delete

# ------------------------------------------
# 1. Custom Kernel Name Configuration
# ------------------------------------------
echo "[*] Setting Custom Kernel Name to -EXTREME++GAMING_Hyperos..."
rm -f localversion*
sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-EXTREME++GAMING_Hyperos"/' "arch/arm64/configs/${DEFCONFIG}"
grep -q "CONFIG_LOCALVERSION=" "arch/arm64/configs/${DEFCONFIG}" || echo 'CONFIG_LOCALVERSION="-EXTREME++GAMING_Hyperos"' >> "arch/arm64/configs/${DEFCONFIG}"
sed -i 's/^EXTRAVERSION =.*/EXTRAVERSION =/' Makefile

# ZRAM ZSTD, EXTREME+ Governor & GPU Devfreq defconfig tunables
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
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_DEFAULT_GOV="schedutil"
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
# 3. KernelSU (Multi-Manager: SukiSU-Ultra / KernelSU-Next / KowSU / ReSukiSU with SuSFS) Setup
# ------------------------------------------
if [ "$ENABLE_KSU" -eq 1 ]; then
    KSU_FLAVOR="${KSU_FLAVOR:-resukisu}"
    echo "[*] Injecting KernelSU Multi-Manager Source (Selected Flavor: ${KSU_FLAVOR})..."

    case "${KSU_FLAVOR,,}" in
        sukisu|sukisu-ultra)
            echo "[*] Fetching SukiSU-Ultra (SukiSU-Ultra/SukiSU-Ultra)..."
            curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash - || \
            curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s -- v4.2.0-rc3
            ;;
        next|ksu-next|kernelsu-next)
            echo "[*] Fetching KernelSU-Next (KernelSU-Next/KernelSU-Next)..."
            curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash - || \
            curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s -- v4.2.0-rc3
            ;;
        kowsu|kowx|kowx712)
            echo "[*] Fetching KowSU (KOWX712/KernelSU)..."
            curl -LSs "https://raw.githubusercontent.com/KOWX712/KernelSU/main/kernel/setup.sh" | bash - || \
            curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s -- v4.2.0-rc3
            ;;
        *)
            echo "[*] Fetching ReSukiSU / RKSU Multi-Manager (v4.2.0-rc3)..."
            curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s -- v4.2.0-rc3
            ;;
    esac

    # Force KSU_SUSFS as default choice in drivers/kernelsu/Kconfig
    if [ -f "drivers/kernelsu/Kconfig" ]; then
        sed -i 's/default KSU_TRACEPOINT_HOOK/default KSU_SUSFS/' drivers/kernelsu/Kconfig
        echo "[+] Default hook set to KSU_SUSFS in drivers/kernelsu/Kconfig"
    fi

    # Multi-Manager Support & Universal Fallback Key Injection (SukiSU-Ultra, KSU-Next, KowSU, ReSukiSU, BakaSU)
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
    hook_replacement = """// Bulletproof Fallback: check known manager package names (SukiSU, Next, KowSU, ReSukiSU, BakaSU, Official)
    if (check_v2_signature(path, signature_index))
        return true;
    char pkg_buf[128];
    if (get_pkg_from_apk_path(pkg_buf, path) == 0) {
        if (!strcmp(pkg_buf, "me.weishu.kernelsu") ||
            !strcmp(pkg_buf, "org.resukisu.resukisu") ||
            !strcmp(pkg_buf, "org.bakasu.bakasu") ||
            !strcmp(pkg_buf, "com.sukisu.ultra") ||
            !strcmp(pkg_buf, "com.sukisu.sukisu") ||
            !strcmp(pkg_buf, "com.rifsxd.ksunext") ||
            !strcmp(pkg_buf, "me.bmax.apatch") ||
            !strcmp(pkg_buf, "com.kowx712.supermanager") ||
            !strcmp(pkg_buf, "me.kowx712.kernelsu") ||
            !strcmp(pkg_buf, "com.resukisu") ||
            strstr(pkg_buf, "sukisu") != NULL ||
            strstr(pkg_buf, "ksunext") != NULL ||
            strstr(pkg_buf, "kowx") != NULL ||
            strstr(pkg_buf, "kernelsu") != NULL) {
            pr_info("PROJECT EXTREME+: Manager recognized by universal multi-manager package filter: %s\\n", pkg_buf);
            *signature_index = 0;
            return true;
        }
    }
    return false;"""
    if hook_target in content and "pkg_buf" not in content:
        content = content.replace(hook_target, hook_replacement)
        with open(apk_sign_path, "w") as f:
            f.write(content)
        print("✅ Patched " + apk_sign_path + " with universal multi-manager verification (SukiSU-Ultra + KSU-Next + KowSU)")
    else:
        print("ℹ️ " + apk_sign_path + " already patched or target signature pattern handled")
' 2>/dev/null || true

    echo "CONFIG_KSU=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_KSU_SUSFS=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_KSU_MULTI_MANAGER_SUPPORT=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "CONFIG_THREAD_INFO_IN_TASK=y" >> "arch/arm64/configs/${DEFCONFIG}"
    echo "[+] Multi-Manager KernelSU (SukiSU-Ultra + KSU-Next + KowSU) Non-GKI setup finished."
else
    echo "[*] Ensuring Pure Clean Kernel Base (Zero embedded root hooks)..."
    sed -i '/CONFIG_KSU/d' "arch/arm64/configs/${DEFCONFIG}" 2>/dev/null || true
fi

# ------------------------------------------
# 4. 100% Pure FakeDreamer Adreno 650 Undervolt & Frequency Table
# ------------------------------------------
echo "[*] Applying 100% Native FakeDreamer GPU Undervolt (150MHz - 670MHz) & Speed Bins..."

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
# 4b. Inject Custom EXTREME+ Governor
# ------------------------------------------
echo "[*] Injecting Custom EXTREME+ Governor into kernel/sched/..."
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
\t  Use the "extreme+" CPUFreq governor by default. Zero latency,
\t  anti-100% prime choke, active frame pacing floor for sustained hardcore gaming.
"""

gov_def = """config CPU_FREQ_GOV_EXTREME_PLUS
\tbool "\x27extreme+\x27 cpufreq policy governor"
\tdepends on CPU_FREQ && SMP
\tselect CPU_FREQ_GOV_ATTR_SET
\tselect IRQ_WORK
\thelp
\t  EXTREME+ governor based on scheduler utilization with active task
\t  frame pacing floor, zero latency up-scaling, and 60ms decay window.
"""

if "CPU_FREQ_GOV_EXTREME_PLUS" not in text:
    text = text.replace("config CPU_FREQ_DEFAULT_GOV_SCHEDUTIL", gov_choice + "\nconfig CPU_FREQ_DEFAULT_GOV_SCHEDUTIL")
    text = text.replace("config CPU_FREQ_GOV_SCHEDUTIL", gov_def + "\nconfig CPU_FREQ_GOV_SCHEDUTIL")
    with open(path_kconfig, "w") as f:
        f.write(text)
    print("✅ Injected EXTREME+ governor definitions into drivers/cpufreq/Kconfig")
else:
    print("ℹ️ EXTREME+ governor already in drivers/cpufreq/Kconfig")
'

# ------------------------------------------
# 5. Display Panel DTS Configuration
# ------------------------------------------
echo "[*] Preserving 100% Native AstideLabs Display & Panel DTS (prevents black screen)..."

# ------------------------------------------
# 6. Safe PD / PPS Fast Charging & Thermal DTS Stepping
# ------------------------------------------
if [ -f "apply-fastcharge-bypass.py" ]; then
    python3 apply-fastcharge-bypass.py
fi

if [ -f "apply-bootloader-spoof.py" ]; then
    python3 apply-bootloader-spoof.py . || true
fi

if [ -f "apply-eas-tuning.py" ]; then
    python3 apply-eas-tuning.py arch/arm64/boot/dts/vendor/qcom/kona.dtsi || echo "⚠️ EAS tuning failed, continuing..."
fi

if [ -f "apply-vmscan-critical.py" ]; then
    python3 apply-vmscan-critical.py mm/vmscan.c || echo "⚠️ vmscan patch skipped"
fi

# ------------------------------------------
# 7. Compile Environment Setup
# ------------------------------------------
MAKE_OPTS=(
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

echo "[*] Generating Defconfig (${DEFCONFIG})..."
make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" "${DEFCONFIG}"

# ------------------------------------------
# 8. Full HyperOS / MIUI Config Injection
# ------------------------------------------
echo "[*] Injecting Full HyperOS / MIUI Subsystem Configs..."

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

scripts/config --file "${OUT_DIR}/.config" -e BBG
scripts/config --file "${OUT_DIR}/.config" --set-str LOCALVERSION "-EXTREME++GAMING_Hyperos"

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
    --set-val SCHEDUTIL_UP_RATE_LIMIT 0 \
    -e CPU_FREQ_GOV_EXTREME_PLUS \
    -d CPU_FREQ_DEFAULT_GOV_EXTREME_PLUS \
    -e CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
    --set-str CPU_FREQ_DEFAULT_GOV "schedutil"

if [ -f "kernel/sched/cpufreq_schedutil.c" ]; then
    sed -i 's/tunables->up_rate_limit_us = CONFIG_SCHEDUTIL_UP_RATE_LIMIT;/tunables->up_rate_limit_us = 0;/' kernel/sched/cpufreq_schedutil.c
fi

if [ -f "fs/dcache.c" ]; then
    sed -i 's/int sysctl_vfs_cache_pressure __read_mostly = [0-9]*;/int sysctl_vfs_cache_pressure __read_mostly = 50;/' fs/dcache.c
fi

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
    scripts/config --file "${OUT_DIR}/.config" \
        -d KSU \
        -d KSU_SUSFS \
        -d KSU_TRACEPOINT_HOOK \
        -d KSU_MANUAL_HOOK
    sed -i '/CONFIG_KSU/d' "${OUT_DIR}/.config" 2>/dev/null || true
fi

make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" olddefconfig

# ------------------------------------------
# 9. Multi-Variant Architecture & AnyKernel3 Preparation
# ------------------------------------------
TARGET_VARIANT="${3:-all}"
VARIANTS_TO_BUILD=()
case "${TARGET_VARIANT,,}" in
    battery|2.5ghz|2.5|2.4ghz|2.4)
        VARIANTS_TO_BUILD=("Battery")
        ;;
    bal-gaming|bal_gaming|balanced|2.8ghz|2.8)
        VARIANTS_TO_BUILD=("Bal-Gaming")
        ;;
    gaming|3.2ghz|3.2)
        VARIANTS_TO_BUILD=("Gaming")
        ;;
    all|both|*)
        VARIANTS_TO_BUILD=("Battery" "Bal-Gaming" "Gaming")
        ;;
esac

make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" dtbs dtbo.img dtb

# ------------------------------------------
# 10. AnyKernel3 Setup
# ------------------------------------------
if ! git clone --depth=1 https://github.com/re-noroi/anykernel3-test -b munch anykernel; then
    git clone --depth=1 https://github.com/AstideLabs/AnyKernel3 -b kona anykernel
fi
rm -rf anykernel/.git

if [ -f "${OUT_DIR}/arch/arm64/boot/dtb" ]; then
    cp "${OUT_DIR}/arch/arm64/boot/dtb" anykernel/dtb
elif [ -f "${OUT_DIR}/arch/arm64/boot/dtb.img" ]; then
    cp "${OUT_DIR}/arch/arm64/boot/dtb.img" anykernel/dtb
else
    cat ${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/*.dtb > anykernel/dtb
fi

cat > anykernel/00-extreme-performance.sh << 'EOF'
#!/system/bin/sh
(
for queue in /sys/block/*/queue; do
    [ -d "$queue" ] && echo 2048 > "$queue/read_ahead_kb" 2>/dev/null || true
done
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done
sleep 15
for rp in resetprop /data/adb/ksu/bin/ksud /data/adb/ksud; do
    if command -v resetprop >/dev/null 2>&1; then
        resetprop -n ro.boot.verifiedbootstate green 2>/dev/null || true
        resetprop -n ro.boot.vbmeta.device_state locked 2>/dev/null || true
        resetprop -n ro.boot.flash.locked 1 2>/dev/null || true
        resetprop -n ro.boot.bootloader.locked 1 2>/dev/null || true
        resetprop -n sys.oem_unlock_allowed 0 2>/dev/null || true
        resetprop -n ro.secureboot.lockstate locked 2>/dev/null || true
        break
    elif [ -x /data/adb/ksu/bin/ksud ]; then
        /data/adb/ksu/bin/ksud resetprop -n ro.boot.verifiedbootstate green 2>/dev/null || true
        /data/adb/ksu/bin/ksud resetprop -n ro.boot.vbmeta.device_state locked 2>/dev/null || true
        break
    fi
done
) &
EOF
chmod 755 anykernel/00-extreme-performance.sh

DATE_TAG="$(date +'%d%b%Y_%H%M')"

for VARIANT in "${VARIANTS_TO_BUILD[@]}"; do
    case "$VARIANT" in
        Battery)
            FREQ="2419200"
            LOCALVER="-Extreme++Battery-by-PandeyJi"
            TITLE="Extreme++Battery by PandeyJi | POCO F4 (munch)"
            ZIP_BASE="EXTREME++Battery"
            ;;
        Bal-Gaming)
            FREQ="2841600"
            LOCALVER="-Extreme++Bal-Gaming-by-PandeyJi"
            TITLE="Extreme++Bal-Gaming by PandeyJi | POCO F4 (munch)"
            ZIP_BASE="EXTREME++Bal-Gaming"
            ;;
        Gaming)
            FREQ="3187200"
            LOCALVER="-Extreme++Gaming-by-PandeyJi"
            TITLE="Extreme++Gaming by PandeyJi | POCO F4 (munch)"
            ZIP_BASE="EXTREME++Gaming"
            ;;
    esac

    if [ -f "apply-cpu-cap.py" ]; then
        python3 apply-cpu-cap.py "${FREQ}"
    fi

    scripts/config --file "${OUT_DIR}/.config" --set-str LOCALVERSION "${LOCALVER}"
    rm -f "${OUT_DIR}/include/config/kernel.release"
    make "${MAKE_OPTS[@]}" olddefconfig

    make -j"${TOTAL_CORES}" "${MAKE_OPTS[@]}" Image
    cp "${OUT_DIR}/arch/arm64/boot/Image" anykernel/Image

    cat > anykernel/anykernel.sh << EOF
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
ui_print "  -> Flashing ${TITLE} (boot)...";
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

    if [ "$ENABLE_KSU" -eq 1 ]; then
        ZIP_NAME="${ZIP_BASE}_${DATE_TAG}.zip"
    else
        ZIP_NAME="${ZIP_BASE}_NoRoot_${DATE_TAG}.zip"
    fi

    (
        cd anykernel
        zip -r9 "../${ZIP_NAME}" ./* -x .gitignore out/ ./*.zip > /dev/null
    )
done
exit 0
