////////////////////////////////////////////////////////////////////////////////
// net_config.c - 网络配置单一事实来源（阶段2 / G5 UART 可配）
////////////////////////////////////////////////////////////////////////////////
#include "net_config.h"
#include "tseDemo.h"
#include "efx_tse_mac.h"    //MAC_ADDR_LO/HI 寄存器宏

volatile net_config_t g_net_cfg;

void net_config_init(void)
{
	g_net_cfg.local_ip     = SRC_IP;          // 10.0.0.8
	g_net_cfg.netmask      = 0xFFFFFF00u;     // 255.255.255.0
	g_net_cfg.gateway_ip   = 0x0A000001u;     // 10.0.0.1（预留）
	g_net_cfg.local_mac[0] = (u8)((SRC_MAC_H >> 8)  & 0xFF);   // ea
	g_net_cfg.local_mac[1] = (u8)( SRC_MAC_H        & 0xFF);   // e8
	g_net_cfg.local_mac[2] = (u8)((SRC_MAC_L >> 24) & 0xFF);   // 5e
	g_net_cfg.local_mac[3] = (u8)((SRC_MAC_L >> 16) & 0xFF);   // 00
	g_net_cfg.local_mac[4] = (u8)((SRC_MAC_L >> 8)  & 0xFF);   // 60
	g_net_cfg.local_mac[5] = (u8)( SRC_MAC_L        & 0xFF);   // c8
}

////////////////////////////////////////////////////////////////////////////////
// G5：生效同步 —— MAC 过滤寄存器 + pattern 源寄存器与 g_net_cfg 一致
////////////////////////////////////////////////////////////////////////////////
void net_config_apply(void)
{
	u32 h = ((u32)g_net_cfg.local_mac[0] << 8) | (u32)g_net_cfg.local_mac[1];
	u32 l = ((u32)g_net_cfg.local_mac[2] << 24) | ((u32)g_net_cfg.local_mac[3] << 16) |
	        ((u32)g_net_cfg.local_mac[4] << 8)  |  (u32)g_net_cfg.local_mac[5];
	//MAC 过滤寄存器（本板源 MAC）
	write_u32(h, (TSEMAC_BASE+MAC_ADDR_HI));
	write_u32(l, (TSEMAC_BASE+MAC_ADDR_LO));
	//pattern 源寄存器：pat_src_mac[47:32]=0x21c、[31:0]=0x218、pat_src_ip=0x224
	//（pat_dst_* 是对端目标，不随本板配置变）
	write_u32(h, (TSEMAC_CSR+0x21c));
	write_u32(l, (TSEMAC_CSR+0x218));
	write_u32(g_net_cfg.local_ip, (TSEMAC_CSR+0x224));
}

////////////////////////////////////////////////////////////////////////////////
// G5：解析与 setter（不依赖 libc，格式错误返回 -1）
////////////////////////////////////////////////////////////////////////////////
static int hexval(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

//点分十进制："10.0.0.9" → 0x0A000009；ok=0 表示格式错误
static u32 net_parse_ip(const char *s, int *ok)
{
	u32 ip = 0;
	int oct;
	*ok = 0;
	for (oct = 0; oct < 4; oct++) {
		int v = 0;
		int d = 0;
		while (*s >= '0' && *s <= '9') {
			v = v * 10 + (*s - '0');
			s++;
			d++;
			if (v > 255) return 0;
		}
		if (d == 0) return 0;
		ip = (ip << 8) | (u32)v;
		if (oct < 3) {
			if (*s != '.') return 0;
			s++;
		}
	}
	if (*s != '\0') return 0;
	*ok = 1;
	return ip;
}

//"ea:e8:5e:00:60:c9"（':' 或 '-' 分隔）→ 6 字节；成功 0
static int net_parse_mac(const char *s, u8 *m)
{
	int i;
	for (i = 0; i < 6; i++) {
		int hi;
		int lo;
		hi = hexval(*s++);
		lo = hexval(*s++);
		if (hi < 0 || lo < 0) return -1;
		m[i] = (u8)((hi << 4) | lo);
		if (i < 5) {
			if (*s != ':' && *s != '-') return -1;
			s++;
		}
	}
	return (*s == '\0') ? 0 : -1;
}

static const char *net_skip_sp(const char *s)
{
	while (*s == ' ') s++;
	return s;
}

int net_config_set_ip(const char *s)
{
	int ok;
	u32 ip;
	s = net_skip_sp(s);
	ip = net_parse_ip(s, &ok);
	if (!ok) return -1;
	g_net_cfg.local_ip = ip;
	net_config_apply();
	return 0;
}

int net_config_set_mac(const char *s)
{
	u8 m[6];
	int i;
	s = net_skip_sp(s);
	if (net_parse_mac(s, m) != 0) return -1;
	for (i = 0; i < 6; i++) g_net_cfg.local_mac[i] = m[i];
	net_config_apply();
	return 0;
}

int net_config_set_gw(const char *s)
{
	int ok;
	u32 ip;
	s = net_skip_sp(s);
	ip = net_parse_ip(s, &ok);
	if (!ok) return -1;
	g_net_cfg.gateway_ip = ip;
	return 0;
}

int net_config_set_mask(const char *s)
{
	int ok;
	u32 ip;
	s = net_skip_sp(s);
	ip = net_parse_ip(s, &ok);
	if (!ok) return -1;
	g_net_cfg.netmask = ip;
	return 0;
}

void net_config_show(void)
{
	bsp_printf("cfg: ip %d.%d.%d.%d mask %d.%d.%d.%d gw %d.%d.%d.%d mac %x:%x:%x:%x:%x:%x\r\n",
		(g_net_cfg.local_ip >> 24) & 0xff, (g_net_cfg.local_ip >> 16) & 0xff,
		(g_net_cfg.local_ip >> 8) & 0xff, g_net_cfg.local_ip & 0xff,
		(g_net_cfg.netmask >> 24) & 0xff, (g_net_cfg.netmask >> 16) & 0xff,
		(g_net_cfg.netmask >> 8) & 0xff, g_net_cfg.netmask & 0xff,
		(g_net_cfg.gateway_ip >> 24) & 0xff, (g_net_cfg.gateway_ip >> 16) & 0xff,
		(g_net_cfg.gateway_ip >> 8) & 0xff, g_net_cfg.gateway_ip & 0xff,
		g_net_cfg.local_mac[0], g_net_cfg.local_mac[1],
		g_net_cfg.local_mac[2], g_net_cfg.local_mac[3],
		g_net_cfg.local_mac[4], g_net_cfg.local_mac[5]);
}
