////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2013-2026 Efinix Inc. All rights reserved.
////////////////////////////////////////////////////////////////////////////////
#pragma once
//============================================================================
// YT8531H-CA (Motorcomm) PHY driver for TSEMAC 7.3 MDIO
// - MDIO addr auto-detect by PHY ID (fallback to PHY_ADDR)
// - Extended registers via reg 0x1E (addr) / 0x1F (data)
// - RGMII: RX delay 13 steps (~1.95ns), TX delay 0 (FPGA PLL 90deg provides ~2ns)
// - Disable sleep / RXC always-on / UTP_TO_RGMII mode / SyncE off
// Register model: Linux mainline motorcomm.c
//============================================================================
#include "bsp.h"
#include "userDef.h"
#include "tseDemo.h"

// MDIO CSR registers (TSEMAC)
#define DIVIDER_PRE   0x0100
#define RD_WR_EN      0x0104
#define REG_PHY_ADDR  0x0108
#define WR_DATA       0x010C
#define RD_DATA       0x0110

// YT8531 extended registers
#define YT8531_RGMII_CONFIG1   0xA003   // RX delay bits13:10 (150ps/step)
#define YT8531_SLEEP_CTRL1     0x0027   // bit15: sleep mode
#define YT8531_CLOCK_GATING    0x000C   // bit12: RXC gating
#define YT8531_CHIP_CFG        0xA001   // bits2:0 chip mode (0 = UTP_TO_RGMII)
#define YT8531_SYNCE           0xA012   // bit6: SyncE
#define YT8531_SSR             0x0011   // soft status: bit10 link, bit11 resolved,
                                        // bit13 duplex, bits15:14 speed(2=1000M)

#define YT8531_PHY_ID1         0x4F51
#define YT8531_PHY_ID2         0xE91B
#define YT8531_RX_DELAY_STEPS  13

static u32 yt_mdio_addr = 0x0;          // updated by yt8531_detect()

/************************** MDIO basic access ***************************/
static void Phy_Wr_At(u32 PhyAddr, u32 RegAddr, u32 Data)
{
	write_u32(((PhyAddr & 0x1f) << 8) | (RegAddr & 0x1f), (TSEMAC_BASE+REG_PHY_ADDR));
	write_u32(Data, (TSEMAC_BASE+WR_DATA));
	write_u32(0x2, (TSEMAC_BASE+RD_WR_EN));     //trigger write
	bsp_uDelay(300);   //MDIO frame ~300us @250kHz MDC
}

static u32 Phy_Rd_At(u32 PhyAddr, u32 RegAddr)
{
	u32 v;
	write_u32(((PhyAddr & 0x1f) << 8) | (RegAddr & 0x1f), (TSEMAC_BASE+REG_PHY_ADDR));
	write_u32(0x1, (TSEMAC_BASE+RD_WR_EN));     //trigger read
	bsp_uDelay(300);   //MDIO frame ~300us @250kHz MDC
	v = read_u32((TSEMAC_BASE+RD_DATA));
	return v;
}

static void Phy_Wr(u32 RegAddr, u32 Data)  { Phy_Wr_At(yt_mdio_addr, RegAddr, Data); }
static u32  Phy_Rd(u32 RegAddr)            { return Phy_Rd_At(yt_mdio_addr, RegAddr); }

/************************** YT8531 extended registers ***************************/
static void yt8531_ExtWr(u32 ext_addr, u32 data)
{
	Phy_Wr(0x1E, ext_addr);
	Phy_Wr(0x1F, data);
}

static u32 yt8531_ExtRd(u32 ext_addr)
{
	Phy_Wr(0x1E, ext_addr);
	return Phy_Rd(0x1F);
}

static u32 yt8531_ExtModify(u32 ext_addr, u32 mask, u32 set)
{
	u32 v = yt8531_ExtRd(ext_addr);
	v = (v & ~mask) | set;
	yt8531_ExtWr(ext_addr, v);
	return v;
}

/************************** YT8531 detect / init ***************************/
// Scan MDIO addr 0..31 for YT8531 ID; fallback to PHY_ADDR if not found
static u32 yt8531_detect()
{
	for (u32 a = 0; a < 32; a++) {
		u32 id1 = Phy_Rd_At(a, 2);
		u32 id2 = Phy_Rd_At(a, 3);
		if ((id1 == YT8531_PHY_ID1) && (id2 == YT8531_PHY_ID2)) {
			yt_mdio_addr = a;
			bsp_printf("Info : YT8531 found at MDIO addr %d\r\n", a);
			return a;
		}
	}
	bsp_printf("Warn : YT8531 ID not found, fallback MDIO addr %d\r\n", yt_mdio_addr);
	return yt_mdio_addr;
}

// RGMII timing / power / mode configuration
static void yt8531_rgmii_init()
{
	//BISECT ROUND 1: all writes disabled - verify soft-reset-only restores 1G
	// RX delay 13 steps, TX delay 0 (FPGA PLL 90deg already provides ~2ns)
	// NOTE: read-modify-write only touches delay bits - whole-register write
	//       would wipe the other default config bits of 0xA003!
	//yt8531_ExtModify(YT8531_RGMII_CONFIG1, (0xFu << 10), (YT8531_RX_DELAY_STEPS << 10));
	// disable PHY sleep
	//yt8531_ExtModify(YT8531_SLEEP_CTRL1, (1u << 15), 0);
	// RXC clock always on: clear gating bit (bit12=1 enables auto-sleep gating!)
	//yt8531_ExtModify(YT8531_CLOCK_GATING, (1u << 12), 0);
	// chip mode: UTP_TO_RGMII (bits2:0 = 0)
	//yt8531_ExtModify(YT8531_CHIP_CFG, 0x7, 0x0);
	// SyncE off
	//yt8531_ExtModify(YT8531_SYNCE, (1u << 6), 0);
	////mode switch needs settle time before the follow-up soft reset
	//bsp_uDelay(150 * 1000);
	bsp_print("BISECT1: rgmii writes disabled\r\n");
}

/*******************************************************************************
* PhyNormalInit: detect + reset + ANEG restart + RGMII cfg + wait link (20s max)
* return MAC speed code: 4=1000M, 2=100M, 1=10M
*******************************************************************************/
static u32 PhyNormalInit()
{
	u32 speed = 4;
	int t;
	u32 ssr = 0;

	yt8531_detect();

	//IMPORTANT: NO BMCR soft reset here.
	//YT8531 BMCR soft reset (0x8000) breaks the 1G DSP: link falls back to
	//10M and the data path dies until a HARD reset (power cycle).
	//After power-on the strap defaults (incl. RX delay 13) are already
	//correct - we just wait for the link the PHY negotiates on its own.

	//wait link up (SSR bit10), 30s timeout, report negotiated speed
	for (t = 0; t < 300; t++) {
		ssr = Phy_Rd(YT8531_SSR);
		if (ssr & (1u << 10)) {
			u32 s = (ssr >> 14) & 0x3;
			speed = (s == 2) ? 4 : ((s == 1) ? 2 : 1);
			bsp_printf("Info : Link up. SSR=%08x speed_code=%d\r\n", ssr, s);
			return speed;
		}
		bsp_uDelay(100 * 1000);
	}
	bsp_print("Warn : Link not up within timeout, assume 1000M\r\n");
	return speed;
}

/************************** Loopback init (TEST_MODE=1) ***************************/
static void PhyLoopInit(u32 speed)
{
	if (speed == 4)       Phy_Wr(0x0, 0x4140);   //1000M loopback
	else if (speed == 2)  Phy_Wr(0x0, 0x6100);   //100M loopback
	else                  Phy_Wr(0x0, 0x4100);   //10M loopback
}
