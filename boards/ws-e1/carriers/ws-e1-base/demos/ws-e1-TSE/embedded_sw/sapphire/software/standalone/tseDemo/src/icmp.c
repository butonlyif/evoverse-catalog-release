////////////////////////////////////////////////////////////////////////////////
// icmp.c - ICMP echo request→reply（G4）
// 帧内偏移：IP 头 [14..33]（IHL=5），ICMP 段 [34..len)
//   IP:  [10..11] cksum  [22] ttl  [26..29] src  [30..33] dst
//   ICMP:[0] type  [1] code  [2..3] cksum  [4..5] id  [6..7] seq  [8..] data
////////////////////////////////////////////////////////////////////////////////
#include "icmp.h"
#include "net_config.h"
#include "eth_frame.h"

int icmp_process(u8 *f, int len)
{
	int i;
	u32 sip;
	u16 icmp_len, c;

	if (len < 42) return 0;                        //14 ETH + 20 IP + 8 ICMP 最小
	if (eth_type_get(f) != 0x0800) return 0;
	if (f[14] != 0x45) return 0;                   //IPv4、IHL=5（无选项头）
	if (f[23] != 1) return 0;                      //proto=ICMP
	if (f[34] != 8 || f[35] != 0) return 0;        //type=8 echo request
	{   //dst IP 必须是本板
		u32 dip = ((u32)f[30] << 24) | ((u32)f[31] << 16) | ((u32)f[32] << 8) | f[33];
		if (dip != g_net_cfg.local_ip) return 0;
	}
	sip = ((u32)f[26] << 24) | ((u32)f[27] << 16) | ((u32)f[28] << 8) | f[29];
	icmp_len = (u16)(len - 34);

	//L2：dst=请求者（对称交换），src=本板
	for (i = 0; i < 6; i++) { u8 t = f[i]; f[i] = f[6+i]; f[6+i] = t; }
	for (i = 0; i < 6; i++) f[6+i] = g_net_cfg.local_mac[i];
	//L3：src=本板，dst=请求者；TTL=64；重算 IP 头校验和
	f[22] = 64;
	f[26] = (u8)(g_net_cfg.local_ip >> 24);
	f[27] = (u8)(g_net_cfg.local_ip >> 16);
	f[28] = (u8)(g_net_cfg.local_ip >> 8);
	f[29] = (u8) g_net_cfg.local_ip;
	f[30] = (u8)(sip >> 24); f[31] = (u8)(sip >> 16);
	f[32] = (u8)(sip >> 8);  f[33] = (u8) sip;
	f[24] = 0; f[25] = 0;
	c = eth_ip_checksum(&f[14], 20);
	f[24] = (u8)(c >> 8); f[25] = (u8)c;
	//L4：type 8→0，载荷原样返回；ICMP 校验和对整段重算（无伪头）
	f[34] = 0;
	f[36] = 0; f[37] = 0;
	c = eth_ip_checksum(&f[34], icmp_len);
	f[36] = (u8)(c >> 8); f[37] = (u8)c;
	return len;
}
