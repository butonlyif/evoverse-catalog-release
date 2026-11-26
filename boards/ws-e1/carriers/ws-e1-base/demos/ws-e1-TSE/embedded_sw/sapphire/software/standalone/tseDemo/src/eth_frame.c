////////////////////////////////////////////////////////////////////////////////
// eth_frame.c - 以太网帧解析/校验和（阶段2）
////////////////////////////////////////////////////////////////////////////////
#include "eth_frame.h"

u16 eth_ip_checksum(const u8 *h, int len)
{
	u32 sum = 0;
	int i;
	for (i = 0; i + 1 < len; i += 2)
		sum += ((u16)h[i] << 8) | h[i+1];
	if (i < len) sum += (u16)h[i] << 8;
	while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
	return (u16)(~sum);
}

u16 eth_type_get(const u8 *f)
{
	return (u16)(((u16)f[12] << 8) | f[13]);
}
