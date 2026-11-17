////////////////////////////////////////////////////////////////////////////////
// YT8531H-CA (Motorcomm) PHY driver for TSE MDIO — based on Linux motorcomm.c
// Note: Efinix bsp_printf supports %d/%x/%s only — do not use %u.
////////////////////////////////////////////////////////////////////////////////
#pragma once

#include "bsp.h"
#include "userDef.h"
#include "efx_tse_mac.h"

/* PHY ID reg2/reg3: OUI 0x4F51, model 0xE91x (YT8531H = 0xE91B) */
#define YT8531_PHY_ID_HI            0x4F51u
#define YT8531_PHY_ID_LO_MASK       0xFFF0u
#define YT8531_PHY_ID_LO_EXPECT     0xE910u

#define YT8531_EXT_ADDR_REG         0x1Eu
#define YT8531_EXT_DATA_REG         0x1Fu
#define YT8531_EXT_REG_SPACE        0xA000u
#define YT8531_EXT_CHIP_CFG         0xA001u
#define YT8531_EXT_RGMII_CFG1       0xA003u
#define YT8531_EXT_SLEEP_CTRL       0x0027u
#define YT8531_EXT_CLK_GATING       0x000Cu
#define YT8531_RSSR_UTP_SPACE       0u

#define YT8531_CCR_RXC_DLY_EN       (1u << 8)
#define YT8531_ESC1R_SLEEP_SW       (1u << 15)
#define YT8531_CGR_RX_CLK_EN        (1u << 12)

#define YT8531_SSR_REG              0x11u
#define YT8531_SSR_LINK             (1u << 10)
#define YT8531_SSR_RESOLVED         (1u << 11)
#define YT8531_SSR_DUPLEX           (1u << 13)
#define YT8531_SSR_SPEED_MASK       (3u << 14)

/* peri.xml may add rgmii_rxc input delay. YT8531 needs rgmii-id for stable
 * 100M autoneg on this board; if rx_ok stays 0, rebuild bitstream with
 * peri rgmii_rxc delay=0 to avoid double RX delay. */
#ifndef YT8531_RGMII_DELAY_STEP
#define YT8531_RGMII_DELAY_STEP     13u
#endif

/* 0 = plain RGMII (use when peri rgmii_rxc delay=15). 1 = rgmii-id internal delay.
 * 11-06 板级判别：plain（PHY+FPGA 双端延迟全 0）时 MAC 连坏帧都收不到
 * （etherStatsPkts=0），而 PHY 残留的 rgmii-id 状态（chip=0x8130 cfg1=0x00F1）
 * 是 11-02 echo PASS 时的实测配置。当前 peri.xml rgmii_rxc delay=0，
 * 必须由 PHY 内部延迟提供采样窗口 → 默认 1。 */
#ifndef YT8531_USE_PHY_RGMII_ID
#define YT8531_USE_PHY_RGMII_ID     1
#endif

#ifndef ETH_FORCE_1000M_LINK
#define ETH_FORCE_1000M_LINK        0
#endif

#define YT8531_BMSR_LINK            (1u << 2)
#define YT8531_BMSR_REMOTE_FAULT    (1u << 4)
#define YT8531_BMSR_ANEG_COMPLETE   (1u << 5)

/* ws-e1 移植补丁：本工程无 efx_tse_userdef.h，速度码与 PHY 地址在此定义
 * （对齐 LOOPBACK 参考工程 efx_tse_userdef.h 的数值） */
#ifndef PHY_ADDR
#define PHY_ADDR                    0x0u
#endif
#ifndef TSE_Speed_1000Mhz
#define TSE_Speed_1000Mhz           0x04u
#define TSE_Speed_100Mhz            0x02u
#define TSE_Speed_10Mhz             0x01u
#endif

static u32 g_yt8531_phy_addr = PHY_ADDR;
static int g_yt8531_ext_ok = 0;

static void yt8531_mdio_wait(void)
{
    u32 i;

    bsp_uDelay(200);
    for (i = 0; i < 200u; i++) {
        if ((read_u32(TSEMAC_BASE + STATUS) & 1u) == 0u) {
            break;
        }
        bsp_uDelay(10);
    }
    bsp_uDelay(200);
}

static u32 yt8531_phy_rd_at(u32 phy_addr, u32 reg)
{
    write_u32(((phy_addr & 0x1fu) << 8) | (reg & 0x1fu), TSEMAC_BASE + REG_PHY_ADDR);
    write_u32(0x1u, TSEMAC_BASE + RD_WR_EN);
    yt8531_mdio_wait();
    return read_u32(TSEMAC_BASE + RD_DATA) & 0xFFFFu;
}

static void yt8531_phy_wr_at(u32 phy_addr, u32 reg, u32 data)
{
    write_u32(((phy_addr & 0x1fu) << 8) | (reg & 0x1fu), TSEMAC_BASE + REG_PHY_ADDR);
    write_u32(data & 0xFFFFu, TSEMAC_BASE + WR_DATA);
    write_u32(0x2u, TSEMAC_BASE + RD_WR_EN);
    yt8531_mdio_wait();
}

static u32 Phy_Rd(u32 RegAddr)
{
    u32 Value = yt8531_phy_rd_at(g_yt8531_phy_addr, RegAddr);
    if (DEBUG_PRINTF_EN == 1) {
        bsp_printf("Rd Phy Addr :%x \r\n", RegAddr);
        bsp_printf("Return Value :%x \r\n", Value);
    }
    return Value;
}

static void Phy_Wr(u32 RegAddr, u32 Data)
{
    yt8531_phy_wr_at(g_yt8531_phy_addr, RegAddr, Data);
    if (DEBUG_PRINTF_EN == 1) {
        bsp_printf("Wr Phy Addr :%x \r\n", RegAddr);
        bsp_printf("Wr Phy Data :%x \r\n", Data);
    }
}

/* After Phy_Rd so app code need not touch g_yt8531_phy_addr. */
static void yt8531_dump_mdio(void)
{
    u32 id1 = Phy_Rd(2) & 0xFFFFu;
    u32 id2 = Phy_Rd(3) & 0xFFFFu;
    u32 bmcr = Phy_Rd(0) & 0xFFFFu;
    u32 ssr = Phy_Rd(YT8531_SSR_REG) & 0xFFFFu;

    bsp_printf("PHY addr=%d ID=0x%x 0x%x BMCR=0x%x SSR=0x%x\r\n",
               (int)g_yt8531_phy_addr, (int)id1, (int)id2, bmcr, ssr);
}

static u32 yt8531_ext_read(u32 ext_addr)
{
    u32 val;

    yt8531_phy_wr_at(g_yt8531_phy_addr, YT8531_EXT_ADDR_REG, ext_addr);
    (void)yt8531_phy_rd_at(g_yt8531_phy_addr, YT8531_EXT_DATA_REG);
    val = yt8531_phy_rd_at(g_yt8531_phy_addr, YT8531_EXT_DATA_REG);
    return val;
}

static void yt8531_ext_write(u32 ext_addr, u32 data)
{
    yt8531_phy_wr_at(g_yt8531_phy_addr, YT8531_EXT_ADDR_REG, ext_addr);
    yt8531_phy_wr_at(g_yt8531_phy_addr, YT8531_EXT_DATA_REG, data);
}

static void yt8531_ext_modify(u32 ext_addr, u32 mask, u32 set)
{
    u32 val = yt8531_ext_read(ext_addr);

    val = (val & ~mask) | (set & mask);
    yt8531_ext_write(ext_addr, val);
}

/* BMSR link bit is latching-low: read twice for current state. */
static u32 yt8531_bmsr_read_current(void)
{
    (void)Phy_Rd(1);
    return Phy_Rd(1) & 0xFFFFu;
}

static void yt8531_select_utp_space(void)
{
    yt8531_ext_modify(YT8531_EXT_REG_SPACE, (1u << 1), YT8531_RSSR_UTP_SPACE);
}

static int yt8531_ext_access_ok(void)
{
    u32 bmcr = yt8531_phy_rd_at(g_yt8531_phy_addr, 0);
    u32 chip = yt8531_ext_read(YT8531_EXT_CHIP_CFG);
    u32 rgmii = yt8531_ext_read(YT8531_EXT_RGMII_CFG1);

    bsp_printf("PHY ext chip=0x%x rgmii=0x%x (BMCR=0x%x)\r\n",
               (int)chip, (int)rgmii, (int)bmcr);
    if (chip == bmcr || rgmii == bmcr) {
        bsp_printf("ERROR: ext MDIO broken (mirror BMCR)\r\n");
        bsp_printf("Use FPGA peri input delay only for RGMII RX\r\n");
        g_yt8531_ext_ok = 0;
        return 0;
    }
    g_yt8531_ext_ok = 1;
    return 1;
}

static int yt8531_is_valid_id(u32 id1, u32 id2)
{
    id1 &= 0xFFFFu;
    id2 &= 0xFFFFu;
    if (id1 != YT8531_PHY_ID_HI) {
        return 0;
    }
    if ((id2 & YT8531_PHY_ID_LO_MASK) != YT8531_PHY_ID_LO_EXPECT) {
        return 0;
    }
    return 1;
}

/* Scan MDIO 0..31; set g_yt8531_phy_addr on success */
static int yt8531_probe_phy_addr(void)
{
    u32 addr;
    u32 id1;
    u32 id2;

    id1 = yt8531_phy_rd_at(g_yt8531_phy_addr, 2);
    id2 = yt8531_phy_rd_at(g_yt8531_phy_addr, 3);
    if (yt8531_is_valid_id(id1, id2)) {
        bsp_printf("YT8531 at MDIO addr %d (ID=0x%x 0x%x)\r\n",
                   (int)g_yt8531_phy_addr, (int)id1, (int)id2);
        return 1;
    }

    for (addr = 0; addr < 32u; addr++) {
        if (addr == g_yt8531_phy_addr) {
            continue;
        }
        id1 = yt8531_phy_rd_at(addr, 2);
        id2 = yt8531_phy_rd_at(addr, 3);
        if (yt8531_is_valid_id(id1, id2)) {
            g_yt8531_phy_addr = addr;
            bsp_printf("YT8531 found at MDIO addr %d (ID=0x%x 0x%x)\r\n",
                       (int)addr, (int)id1, (int)id2);
            bsp_printf("Update PHY_ADDR to %d in efx_tse_userdef.h\r\n", (int)addr);
            return 1;
        }
    }
    return 0;
}

/* RGMII delay: default plain RGMII when FPGA peri already delays rxc. */
static void yt8531_rgmii_config(void)
{
    if (!g_yt8531_ext_ok) {
        bsp_printf("Skip PHY rgmii-id (ext MDIO N/A), tune FPGA peri delay\r\n");
        return;
    }
#if YT8531_USE_PHY_RGMII_ID
    /* 恢复 11-02 echo PASS 时代板级实测 PHY 状态：
     * CHIP_CFG bit8 RXC_DLY_EN=1（chip=0x8130）、RGMII_CFG1=0x00F1
     * （掩码 0x3C0F 内仅 RX 延迟字段 [3:0]=1，TX 字段=0）。
     * 11-06 板级判别依据见上方 USE_PHY_RGMII_ID 注释。 */
    u32 rgmii_val = YT8531_RGMII_DELAY_STEP & 0xFu;
    if (rgmii_val > 1u) rgmii_val = 1u;   //实测有效值为 step=1（cfg1=0xF1）
    yt8531_ext_modify(YT8531_EXT_CHIP_CFG, YT8531_CCR_RXC_DLY_EN, YT8531_CCR_RXC_DLY_EN);
    yt8531_ext_modify(YT8531_EXT_RGMII_CFG1, 0x3C0Fu, rgmii_val);
    bsp_printf("YT8531 rgmii-id cfg=0x%x chip=0x%x\r\n",
               (int)yt8531_ext_read(YT8531_EXT_RGMII_CFG1),
               (int)yt8531_ext_read(YT8531_EXT_CHIP_CFG));
#else
    yt8531_ext_modify(YT8531_EXT_CHIP_CFG, YT8531_CCR_RXC_DLY_EN, 0);
    yt8531_ext_modify(YT8531_EXT_RGMII_CFG1, 0x3C0Fu, 0);
    bsp_printf("YT8531 rgmii plain cfg=0x%x chip=0x%x\r\n",
               (int)yt8531_ext_read(YT8531_EXT_RGMII_CFG1),
               (int)yt8531_ext_read(YT8531_EXT_CHIP_CFG));
#endif
}

static void yt8531_enable_rxc_always(void)
{
    /* Linux motorcomm: clear CGR_RX_CLK_EN => keep RXC alive even with no cable */
    yt8531_ext_modify(YT8531_EXT_CLK_GATING, YT8531_CGR_RX_CLK_EN, 0);
}

#if ETH_FORCE_1000M_LINK
static void yt8531_force_1000m_autoneg(void)
{
    u32 bmcr;

    /* ANAR: IEEE802.3 selector only; 1000M in reg 9 */
    Phy_Wr(4, 0x0001u);
    Phy_Wr(9, 0x0200u);  /* 1000BASE-T full only */
    bmcr = Phy_Rd(0) & 0xFFFFu;
    bmcr |= 0x1000u;     /* autoneg enable */
    bmcr &= ~0x2040u;    /* clear speed force + isolate */
    Phy_Wr(0, bmcr);
    bsp_uDelay(10000);
    bmcr |= 0x0200u;     /* restart autoneg */
    Phy_Wr(0, bmcr);
    bsp_uDelay(100000);
    bsp_printf("PHY 1G AN BMCR=0x%x ANAR=0x%x ADV1G=0x%x\r\n",
               (int)(Phy_Rd(0) & 0xFFFFu),
               (int)(Phy_Rd(4) & 0xFFFFu),
               (int)(Phy_Rd(9) & 0xFFFFu));
}
#endif

static int yt8531_ssr_link_ready(u32 ssr)
{
    if ((ssr & (YT8531_SSR_LINK | YT8531_SSR_RESOLVED)) !=
        (YT8531_SSR_LINK | YT8531_SSR_RESOLVED)) {
        return 0;
    }
    if ((ssr & YT8531_SSR_SPEED_MASK) == 0u) {
        return 0;
    }
    return 1;
}

static int yt8531_link_is_real(u32 bmsr, u32 ssr)
{
    if (!yt8531_ssr_link_ready(ssr)) {
        return 0;
    }
    if (!(bmsr & YT8531_BMSR_LINK)) {
        return 0;
    }
    if (bmsr & YT8531_BMSR_REMOTE_FAULT) {
        return 0;
    }
    if (!(bmsr & YT8531_BMSR_ANEG_COMPLETE)) {
        return 0;
    }
    return 1;
}

static void yt8531_print_link_diag(u32 bmsr, u32 ssr)
{
    u32 anlpar = Phy_Rd(5) & 0xFFFFu;
    u32 stat1000 = Phy_Rd(10) & 0xFFFFu;

    bsp_printf("  ANLPAR=0x%x STAT1000=0x%x\r\n", (int)anlpar, (int)stat1000);
    if (bmsr & YT8531_BMSR_REMOTE_FAULT) {
        bsp_printf("  WARN: BMSR remote fault set\r\n");
    }
    if (yt8531_ssr_link_ready(ssr) && !(bmsr & YT8531_BMSR_LINK)) {
        bsp_printf("  WARN: SSR link but BMSR link=0\r\n");
    }
    if ((bmsr & YT8531_BMSR_LINK) && !yt8531_ssr_link_ready(ssr)) {
        bsp_printf("  WARN: BMSR link but SSR not resolved\r\n");
    }
    if (yt8531_ssr_link_ready(ssr) && (anlpar == 0u) && (stat1000 == 0u)) {
        bsp_printf("  WARN: no partner regs — cable/partner?\r\n");
    }
}

static void yt8531_restart_autoneg(void)
{
    u32 bmcr = Phy_Rd(0) & 0xFFFFu;

    bmcr |= 0x1000u;  /* AN enable */
    bmcr |= 0x0200u;  /* restart AN */
    Phy_Wr(0, bmcr);
    bsp_uDelay(100000);
    bsp_printf("PHY restart AN, BMCR=0x%x\r\n", (int)(Phy_Rd(0) & 0xFFFFu));
}

static void yt8531_post_link_rgmii(void)
{
    yt8531_rgmii_config();
    bsp_printf("YT8531 RGMII cfg re-applied after link\r\n");
}

static void yt8531_drv_init(void)
{
    u32 bmsr;
    u32 ssr;

    bsp_printf("yt8531_drv_init enter\r\n");
    if (!yt8531_probe_phy_addr()) {
        bsp_printf("ERROR: YT8531 not found on MDIO (check sw6/MDIO)\r\n");
        return;
    }

    bmsr = yt8531_bmsr_read_current();
    ssr = Phy_Rd(YT8531_SSR_REG) & 0xFFFFu;
    bsp_printf("PHY before init BMSR=0x%x SSR=0x%x BMCR=0x%x\r\n",
               bmsr, ssr, (int)(Phy_Rd(0) & 0xFFFFu));
    bsp_printf("Unplug cable now if testing; link LED must match BMSR bit2\r\n");

    yt8531_select_utp_space();
    if (!yt8531_ext_access_ok()) {
        bsp_printf("ERROR: MDIO ext reg access suspect\r\n");
    }

    yt8531_ext_modify(YT8531_EXT_SLEEP_CTRL, YT8531_ESC1R_SLEEP_SW, 0);
    yt8531_enable_rxc_always();
    yt8531_rgmii_config();

#if ETH_FORCE_1000M_LINK
    bsp_printf("Force 1000M autoneg (no P_27 gclk bypass)\r\n");
    yt8531_force_1000m_autoneg();
#else
    if (!yt8531_ssr_link_ready(ssr)) {
        bsp_printf("PHY no link yet, restart autoneg...\r\n");
        yt8531_restart_autoneg();
    } else {
        bsp_printf("PHY already linked, keep autoneg result\r\n");
    }
#endif
}

static u32 yt8531_speed_from_ssr(u32 ssr)
{
    switch (ssr & YT8531_SSR_SPEED_MASK) {
    case (2u << 14):
        return TSE_Speed_1000Mhz;
    case (1u << 14):
        return TSE_Speed_100Mhz;
    default:
        return TSE_Speed_10Mhz;
    }
}

static const char *yt8531_speed_mbps_str(u32 speed)
{
    if (speed == TSE_Speed_1000Mhz) {
        return "1000";
    }
    if (speed == TSE_Speed_100Mhz) {
        return "100";
    }
    return "10";
}

static int yt8531_drv_linkup(void)
{
    u32 ssr;
    u32 bmsr;
    u32 bmcr;
    u32 speed = TSE_Speed_100Mhz;
    u32 wait_ms = 0;
    int bmsr_link_seen = 0;

    bsp_printf("Waiting YT8531 link...\r\n");
    while (1) {
        bmcr = Phy_Rd(0) & 0xFFFFu;
        bmsr = yt8531_bmsr_read_current();
        ssr = Phy_Rd(YT8531_SSR_REG) & 0xFFFFu;

        if (bmsr & YT8531_BMSR_LINK) {
            bmsr_link_seen = 1;
        }

        if (yt8531_link_is_real(bmsr, ssr)) {
            speed = yt8531_speed_from_ssr(ssr);
#if ETH_FORCE_1000M_LINK
            if (speed != TSE_Speed_1000Mhz) {
                bsp_printf("WARN: SSR speed code=%d (want 4=1G)\r\n", (int)speed);
            }
#endif
            if (ssr & YT8531_SSR_DUPLEX) {
                bsp_printf("YT8531 linked: %sM full SSR=0x%x BMSR=0x%x\r\n",
                           yt8531_speed_mbps_str(speed), ssr, bmsr);
            } else {
                bsp_printf("YT8531 linked: %sM half SSR=0x%x BMSR=0x%x\r\n",
                           yt8531_speed_mbps_str(speed), ssr, bmsr);
            }
            yt8531_print_link_diag(bmsr, ssr);
            bsp_printf("If RJ45 LINK LED still off, no real L1 link\r\n");
            return (int)speed;
        }

        if ((wait_ms % 2000u) == 0u) {
            bsp_printf("  wait %dms BMSR=0x%x SSR=0x%x BMCR=0x%x%s\r\n",
                       (int)wait_ms, bmsr, ssr, bmcr,
                       bmsr_link_seen ? " (BMSR link)" : "");
            if (bmsr_link_seen && !(ssr & YT8531_SSR_RESOLVED)) {
                bsp_printf("  note: BMSR link but SSR not resolved yet\r\n");
            }
            if (yt8531_ssr_link_ready(ssr) && !yt8531_link_is_real(bmsr, ssr)) {
                bsp_printf("  note: SSR ok but link not real (check RF/BMSR)\r\n");
                yt8531_print_link_diag(bmsr, ssr);
            }
        }
        bsp_uDelay(100000);
        wait_ms += 100u;
    }
}
