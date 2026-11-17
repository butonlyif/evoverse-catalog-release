////////////////////////////////////////////////////////////////////////////////
// arp.c - ARP 请求→应答（G3）
// 帧内 ARP 净荷偏移（相对帧头 14B）：
//   [0..1] htype  [2..3] ptype  [4] hlen  [5] plen  [6..7] oper
//   [8..13] sha   [14..17] spa  [18..23] tha  [24..27] tpa
////////////////////////////////////////////////////////////////////////////////
#include "arp.h"
#include "net_config.h"
#include "eth_frame.h"

#define ARP_OPER_REQ 1
#define ARP_OPER_REP 2

int arp_process(u8 *f, int len)
{
	int i;
	u16 oper;
	u32 tpa;

	if (len < 42) return 0;                        //14 ETH + 28 ARP
	if (eth_type_get(f) != 0x0806) return 0;
	if (f[14] != 0 || f[15] != 1) return 0;        //htype=1 (Ethernet)
	if (f[16] != 0x08 || f[17] != 0x00) return 0;  //ptype=IPv4
	if (f[18] != 6 || f[19] != 4) return 0;        //hlen=6 / plen=4
	oper = (u16)(((u16)f[20] << 8) | f[21]);
	if (oper != ARP_OPER_REQ) return 0;
	tpa = ((u32)f[38] << 24) | ((u32)f[39] << 16) | ((u32)f[40] << 8) | f[41];
	if (tpa != g_net_cfg.local_ip) return 0;       //不是问本板 → 不理

	//L2：dst=请求者（对称交换后 f[0..5] 即请求者 MAC），src=本板
	for (i = 0; i < 6; i++) { u8 t = f[i]; f[i] = f[6+i]; f[6+i] = t; }
	for (i = 0; i < 6; i++) f[6+i] = g_net_cfg.local_mac[i];
	//ARP 净荷：oper=2 应答；sha=本板；spa=本板 IP；tha=请求者；tpa=请求者 IP（不变）
	f[20] = 0; f[21] = ARP_OPER_REP;
	for (i = 0; i < 6; i++) f[32+i] = f[i];                      //tha=请求者 MAC
	for (i = 0; i < 6; i++) f[22+i] = g_net_cfg.local_mac[i];    //sha=本板
	f[28] = (u8)(g_net_cfg.local_ip >> 24);
	f[29] = (u8)(g_net_cfg.local_ip >> 16);
	f[30] = (u8)(g_net_cfg.local_ip >> 8);
	f[31] = (u8) g_net_cfg.local_ip;
	return 42;
}
