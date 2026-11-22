// SPDX-License-Identifier: GPL-2.0-only
/*
 * paniccast: on panic, broadcast the tail of the kernel log as UDP packets
 * straight through a network device's ndo_start_xmit (no stack, no IRQs).
 * Debug aid for phones without UART/pstore: the USB NCM gadget hands full
 * NTBs to the controller at once, so the host still receives them.
 */
#include <linux/module.h>
#include <linux/kmsg_dump.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/skbuff.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include <linux/delay.h>
#include <linux/inet.h>
#include <net/ip.h>

static char ifname[IFNAMSIZ] = "usb0";
module_param_string(ifname, ifname, sizeof(ifname), 0444);
static char src[20] = "172.16.43.1";
module_param_string(src, src, sizeof(src), 0444);
static char dst[20] = "172.16.43.255";
module_param_string(dst, dst, sizeof(dst), 0444);
static int port = 6666;
module_param(port, int, 0444);
static int passes = 4;
module_param(passes, int, 0444);

static struct net_device *ndev;
static char logbuf[48 * 1024];
#define CHUNK 1000

static int send_chunk(const char *p, int len, u32 off, u32 total)
{
	struct sk_buff *skb;
	struct ethhdr *eth;
	struct iphdr *ip;
	struct udphdr *udp;
	__be32 *hdr;
	int plen = len + 8;

	skb = alloc_skb(LL_MAX_HEADER + sizeof(*ip) + sizeof(*udp) + plen + 64, GFP_ATOMIC);
	if (!skb)
		return -ENOMEM;
	skb_reserve(skb, LL_MAX_HEADER + sizeof(*ip) + sizeof(*udp));
	hdr = skb_put(skb, plen);
	hdr[0] = htonl(off);
	hdr[1] = htonl(total);
	memcpy(hdr + 2, p, len);

	udp = skb_push(skb, sizeof(*udp));
	udp->source = htons(port);
	udp->dest = htons(port);
	udp->len = htons(sizeof(*udp) + plen);
	udp->check = 0;

	ip = skb_push(skb, sizeof(*ip));
	memset(ip, 0, sizeof(*ip));
	ip->version = 4;
	ip->ihl = 5;
	ip->ttl = 64;
	ip->protocol = IPPROTO_UDP;
	ip->tot_len = htons(sizeof(*ip) + sizeof(*udp) + plen);
	ip->saddr = in_aton(src);
	ip->daddr = in_aton(dst);
	ip->check = ip_fast_csum((unsigned char *)ip, ip->ihl);

	eth = skb_push(skb, ETH_HLEN);
	eth_broadcast_addr(eth->h_dest);
	ether_addr_copy(eth->h_source, ndev->dev_addr);
	eth->h_proto = htons(ETH_P_IP);

	skb->dev = ndev;
	skb->protocol = htons(ETH_P_IP);
	skb_reset_mac_header(skb);
	skb_set_network_header(skb, ETH_HLEN);

	if (ndev->netdev_ops->ndo_start_xmit(skb, ndev) != NETDEV_TX_OK) {
		kfree_skb(skb);
		return -EBUSY;
	}
	return 0;
}

static void cast(const char *buf, size_t len)
{
	int pass;
	size_t off;

	for (pass = 0; pass < passes; pass++) {
		for (off = 0; off < len; off += CHUNK) {
			if (send_chunk(buf + off, min_t(size_t, CHUNK, len - off), off, len))
				return;
		}
		mdelay(20);
	}
}

static void paniccast_dump(struct kmsg_dumper *dumper, struct kmsg_dump_detail *detail)
{
	struct kmsg_dump_iter iter;
	size_t len = 0;

	if (!ndev)
		return;
	kmsg_dump_rewind(&iter);
	kmsg_dump_get_buffer(&iter, true, logbuf, sizeof(logbuf), &len);
	cast(logbuf, len);
	mdelay(300);
}

static struct kmsg_dumper dumper = {
	.dump = paniccast_dump,
	.max_reason = KMSG_DUMP_PANIC,
};

static int test_set(const char *val, const struct kernel_param *kp)
{
	static const char msg[] = "paniccast test packet\n";
	int i;

	for (i = 0; i < 40; i++)
		send_chunk(msg, sizeof(msg) - 1, 0, sizeof(msg) - 1);
	return 0;
}
static const struct kernel_param_ops test_ops = { .set = test_set };
module_param_cb(test, &test_ops, NULL, 0200);

static int __init paniccast_init(void)
{
	ndev = dev_get_by_name(&init_net, ifname);
	if (!ndev)
		return -ENODEV;
	return kmsg_dump_register(&dumper);
}

static void __exit paniccast_exit(void)
{
	kmsg_dump_unregister(&dumper);
	dev_put(ndev);
}
module_init(paniccast_init);
module_exit(paniccast_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Broadcast the kernel log tail over a netdev on panic");
