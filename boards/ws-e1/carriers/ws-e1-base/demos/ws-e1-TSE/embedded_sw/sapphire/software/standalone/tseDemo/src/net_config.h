#pragma once
////////////////////////////////////////////////////////////////////////////////
// net_config.h - 网络配置单一事实来源（阶段2：G3 ARP / G4 ICMP / G5 可配 IP）
// 所有协议代码（ARP/ICMP/后续 UDP 服务）只读 g_net_cfg；
// G5 UART 命令行修改后需同步刷新 MAC 过滤寄存器与 pattern 寄存器（0x218/0x224/0x228）。
////////////////////////////////////////////////////////////////////////////////

#include "common.h"

typedef struct {
	u32 local_ip;        // 本板 IP（默认 10.0.0.8）
	u32 netmask;         // 默认 255.255.255.0（预留）
	u32 gateway_ip;      // 预留
	u8  local_mac[6];    // 本板 MAC（默认 ea:e8:5e:00:60:c8）
} net_config_t;

extern volatile net_config_t g_net_cfg;

//从 tseDemo.h 宏填充默认值（上电调用一次）
void net_config_init(void);

//G5 运行时配置（UART 命令行调用；字符串格式错误返回 -1，成功 0）
int  net_config_set_ip(const char *s);    //"10.0.0.9"
int  net_config_set_mac(const char *s);   //"ea:e8:5e:00:60:c9"（':' 或 '-' 分隔）
int  net_config_set_gw(const char *s);    //仅存储（预留）
int  net_config_set_mask(const char *s);  //仅存储（预留）
void net_config_show(void);

//生效同步：MAC 过滤寄存器（MAC_ADDR_LO/HI）+ pattern 源寄存器（0x218/0x21c/0x224）
//与 g_net_cfg 一致；ARP/ICMP/tick 帧直接读 g_net_cfg，改完即生效
void net_config_apply(void);
