#!/usr/bin/env python3
# ==============================================================================
# PROJECT EXTREME++ | Maintainer: PandeyJI-9
# Device: POCO F4 (munch) | Target: HyperOS 4 / HyperOS 2 / MIUI Universal
# Millet Dual-ABI & Multi-Protocol Netlink Compatibility Engine
# ==============================================================================
import sys
import os
import re

kernel_src = sys.argv[1] if len(sys.argv) > 1 else "."

# 1. Tìm tệp millet_core.c
candidates = [
    os.path.join(kernel_src, "drivers/mihw/millet/millet_core.c"),
    os.path.join(kernel_src, "drivers/millet/millet_core.c"),
    os.path.join(kernel_src, "drivers/mihw/millet_core.c"),
]

target_file = None
for c in candidates:
    if os.path.exists(c):
        target_file = os.path.abspath(c)
        break

if not target_file:
    drivers_dir = os.path.join(kernel_src, "drivers")
    if os.path.exists(drivers_dir):
        for root, dirs, files in os.walk(drivers_dir):
            if "millet_core.c" in files:
                target_file = os.path.abspath(os.path.join(root, "millet_core.c"))
                break

if not target_file:
    print("ℹ️ No millet_core.c found in kernel source. (AOSP or non-Xiaomi tree - skipping)")
    sys.exit(0)

print(f"🔍 Located target millet_core.c at: {target_file}")

with open(target_file, "r") as f:
    content = f.read()

if "/* EXTREME_MILLET_UNIVERSAL_COMPAT_V1 */" in content:
    print("ℹ️ millet_core.c is already patched with Extreme++ Universal Compatibility Engine.")
    sys.exit(0)

# 2. Chèn khai báo toàn cục lên đầu tệp (ngay sau dòng #include cuối cùng)
# Điều này đảm bảo millet_sendto_user() luôn nhìn thấy biến trước
header_defs = """
/* EXTREME_MILLET_UNIVERSAL_COMPAT_V1 */
#ifndef EXTREME_MILLET_MAX_SOCKS
#define EXTREME_MILLET_MAX_SOCKS 3
#endif
static struct sock *extreme_millet_socks[EXTREME_MILLET_MAX_SOCKS] = {NULL};
static const int extreme_millet_protocols[EXTREME_MILLET_MAX_SOCKS] = { 29, 30, 31 };
"""

last_include = content.rfind("#include")
if last_include != -1:
    end_include_line = content.find("\n", last_include)
    content = content[:end_include_line] + "\n" + header_defs + content[end_include_line:]
else:
    content = header_defs + "\n" + content

# 3. Patch hàm recv_handler
start_recv = content.find("static void recv_handler(struct sk_buff *skb)")
end_recv = content.find("static int millet_sock_show", start_recv)

if start_recv == -1 or end_recv == -1:
    print("⚠️ Could not locate recv_handler boundary in millet_core.c - skipping patch.")
    sys.exit(1)

new_recv_handler = """static void recv_handler(struct sk_buff *skb)
{
	struct nlmsghdr *nlh = NULL;
	uid_t uid = 0;
	int from = -1;
	enum MILLET_TYPE owner = O_TYPE;
	enum MSG_TYPE msg_type = O_MSG;
	unsigned long src_port = 0;
	unsigned long dst_port = 0;
	struct millet_userconf userconf_buf;
	struct millet_userconf *payload = &userconf_buf;
	bool is_hyperos_frame = false;

	if (!skb) {
		pr_err("millet: recv_handler skb is NULL!\\n");
		return;
	}

	uid = (*NETLINK_CREDS(skb)).uid.val;
	if (uid > 1000) {
		pr_err("millet: uid %d, permission denied\\n", uid);
		return;
	}

	if (millet_debug)
		pr_info("millet: kernel received netlink msg (len=%u)\\n", skb->len);

	if (unlikely(skb->len < NLMSG_SPACE(0))) {
		pr_err("millet: msg len is invalid\\n");
		return;
	}

	nlh = nlmsg_hdr(skb);
	if (!nlh)
		return;

	/* Dynamic Sender Port: If userspace left nlmsg_pid = 0, retrieve from NETLINK_CB */
	from = nlh->nlmsg_pid ? nlh->nlmsg_pid : NETLINK_CB(skb).portid;

	/* Track the active receiving socket for reverse unicast transmission */
	if (skb->sk)
		millet_sk.sock = skb->sk;

	memset(&userconf_buf, 0, sizeof(userconf_buf));

	/* Dual-ABI Netlink Frame Parser: HyperOS 4 / 2 (160 bytes) vs MIUI (96 bytes) */
	if (nlh->nlmsg_len >= NLMSG_SPACE(sizeof(struct millet_data))) {
		/* HyperOS 4 / 2 / Modern Xiaomi Netlink frame (160 bytes) */
		struct millet_data *d = (struct millet_data *) NLMSG_DATA(nlh);
		is_hyperos_frame = true;
		owner = d->owner;
		msg_type = d->msg_type;
		src_port = d->src_port;
		dst_port = d->dst_port;

		/* Map to legacy userconf for registered subsystem hooks (millet_pkg / binder) */
		userconf_buf.owner = owner;
		userconf_buf.msg_type = msg_type;
		userconf_buf.src_port = src_port;
		userconf_buf.dst_port = dst_port;
		memcpy(userconf_buf.pri, d->pri, sizeof(userconf_buf.pri));
		memcpy(&userconf_buf.mod, &d->mod, sizeof(userconf_buf.mod));
	} else if (nlh->nlmsg_len >= NLMSG_SPACE(sizeof(struct millet_userconf))) {
		/* Legacy MIUI Netlink frame (96 bytes) */
		struct millet_userconf *u = (struct millet_userconf *) NLMSG_DATA(nlh);
		owner = u->owner;
		msg_type = u->msg_type;
		src_port = u->src_port;
		dst_port = u->dst_port;
		memcpy(&userconf_buf, u, sizeof(userconf_buf));
	} else {
		pr_err("millet: invalid packet length %u (expected >= %lu or %lu)\\n",
		       nlh->nlmsg_len,
		       (unsigned long)NLMSG_SPACE(sizeof(struct millet_userconf)),
		       (unsigned long)NLMSG_SPACE(sizeof(struct millet_data)));
		return;
	}

	/* Validate module type */
	if (!TYPE_VALID(owner)) {
		pr_err("millet: mod %d is not valid!\\n", owner);
		return;
	}

	if (src_port != MILLET_USER_ID && src_port != 0 && src_port != (unsigned long)from) {
		if (millet_debug)
			pr_warn("millet: non-standard src_port 0x%lx from %d (len %u, is_hyperos=%d)\\n",
				src_port, from, nlh->nlmsg_len, is_hyperos_frame);
	}

	if (dst_port != MILLET_KERNEL_ID && dst_port != 0) {
		if (millet_debug)
			pr_warn("millet: non-standard dst_port 0x%lx from %d\\n", dst_port, from);
	}

	switch (msg_type) {
	case LOOPBACK_MSG:
	case MSG_TO_USER: {
		struct millet_data data;
		memset(&data, 0, sizeof(data));
		data.msg_type = msg_type;
		data.owner = owner;
		data.src_port = MILLET_KERNEL_ID;
		data.dst_port = MILLET_USER_ID;
		atomic_set(&millet_sk.mod[owner].port, from);
		if (millet_debug) {
			pr_info("millet: registered owner %d port %d (msg_type %d)\\n",
				owner, from, msg_type);
			dump_recv_msg(payload);
		}
		millet_sendto_user(current, &data, &millet_sk);
		break;
	}

	case MSG_TO_KERN: {
		atomic_set(&millet_sk.mod[owner].port, from);

		if (owner == HANDSHK_TYPE) {
			struct millet_data data;
			memset(&data, 0, sizeof(data));
			data.msg_type = MSG_TO_USER;
			data.owner = HANDSHK_TYPE;
			data.src_port = MILLET_KERNEL_ID;
			data.dst_port = MILLET_USER_ID;
			millet_sendto_user(current, &data, &millet_sk);
		} else if (millet_sk.mod[owner].recv_from) {
			millet_sk.mod[owner].recv_from(payload, sizeof(struct millet_userconf));
		}

		if (millet_debug)
			dump_recv_msg(payload);
		break;
	}

	default:
		atomic_set(&millet_sk.mod[owner].port, from);
		if (millet_debug)
			pr_info("millet: vendor msg_type %d for owner %d from %d\\n",
				msg_type, owner, from);
		break;
	}
}

"""

content = content[:start_recv] + new_recv_handler + content[end_recv:]

# 4. Patch millet_sendto_user kiểm tra dead port
target_sendto = "monitor_port = atomic_read(&sk->mod[monitor].port);"
replace_sendto = """monitor_port = atomic_read(&sk->mod[monitor].port);
	if (monitor_port <= 0) {
		kfree_skb(skb);
		return RET_ERR;
	}"""

if target_sendto in content and "if (monitor_port <= 0)" not in content:
    content = content.replace(target_sendto, replace_sendto, 1)

# Patch retry qua nhiều socket Netlink (chuẩn C90: đặt khai báo lên đầu block)
old_unicast_block = """	ret = nlmsg_unicast(sk->sock, skb, monitor_port);

	if (ret < 0) {
		if (millet_debug)
			pr_err("nlmsg_unicast failed! %s errno %d\\n",
				__func__, ret);
		return RET_ERR;
	}"""

new_unicast_block = """	ret = nlmsg_unicast(sk->sock, skb, monitor_port);

	if (ret < 0) {
		int pi;
		for (pi = 0; pi < EXTREME_MILLET_MAX_SOCKS; pi++) {
			if (extreme_millet_socks[pi] && extreme_millet_socks[pi] != sk->sock) {
				struct sk_buff *retry_skb = skb_clone(skb, GFP_ATOMIC);
				if (retry_skb) {
					int r = nlmsg_unicast(extreme_millet_socks[pi], retry_skb, monitor_port);
					if (r >= 0) {
						ret = r;
						sk->sock = extreme_millet_socks[pi];
						break;
					}
				}
			}
		}
	}

	if (ret < 0) {
		if (millet_debug)
			pr_err("nlmsg_unicast failed! %s errno %d\\n",
				__func__, ret);
		return RET_ERR;
	}"""

if old_unicast_block in content:
    content = content.replace(old_unicast_block, new_unicast_block, 1)

# 5. Patch millet_init để bind đồng thời các giao thức Netlink 29, 30, 31
old_init_block = """	pr_err("enter millet_init func!\\n");
	millet_sk.sock =
		netlink_kernel_create(&init_net, NETLINK_MILLET, &cfg);
	if (!millet_sk.sock) {
		pr_err("%s: create socket error!\\n", __func__);
		return ret;
	}"""

new_init_block = """	int i, bound_socks = 0;

	pr_info("millet: enter Extreme++ Universal Multi-Netlink init\\n");
	for (i = 0; i < EXTREME_MILLET_MAX_SOCKS; i++) {
		extreme_millet_socks[i] =
			netlink_kernel_create(&init_net, extreme_millet_protocols[i], &cfg);
		if (extreme_millet_socks[i]) {
			pr_info("millet: bound Netlink protocol %d successfully\\n",
				extreme_millet_protocols[i]);
			bound_socks++;
			if (!millet_sk.sock)
				millet_sk.sock = extreme_millet_socks[i];
		} else {
			pr_warn("millet: Netlink protocol %d busy or unavailable\\n",
				extreme_millet_protocols[i]);
		}
	}

	if (bound_socks == 0) {
		pr_err("%s: create socket error! All Netlink protocols (29/30/31) failed\\n", __func__);
		return ret;
	}"""

if old_init_block in content:
    content = content.replace(old_init_block, new_init_block, 1)

with open(target_file, "w") as f:
    f.write(content)

print(f"✅ Successfully patched {os.path.basename(target_file)} with Universal Dual-ABI & Multi-Netlink support!")

# 6. Cập nhật uapi/millet.h
uapi_candidates = [
    os.path.join(os.path.dirname(target_file), "uapi/millet.h"),
    os.path.join(kernel_src, "include/uapi/linux/millet.h"),
]

for uc in uapi_candidates:
    if os.path.exists(uc):
        with open(uc, "r") as uf:
            ucontent = uf.read()
        if "NETLINK_MILLET_HYPEROS" not in ucontent:
            pattern = r'#ifndef NETLINK_MILLET\s*#define NETLINK_MILLET\s+[0-9]+\s*#endif'
            new_def = """#ifndef NETLINK_MILLET
#define NETLINK_MILLET		29
#endif
#ifndef NETLINK_MILLET_LEGACY
#define NETLINK_MILLET_LEGACY	30
#endif
#ifndef NETLINK_MILLET_HYPEROS
#define NETLINK_MILLET_HYPEROS	31
#endif"""
            if re.search(pattern, ucontent):
                ucontent = re.sub(pattern, new_def, ucontent, count=1)
                with open(uc, "w") as uf:
                    uf.write(ucontent)
                print(f"✅ Updated {os.path.basename(uc)} with HyperOS Netlink protocol definitions.")
                break
				
