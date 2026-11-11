/***************************************************************************//**
* \file cy_fx3g2_bsp.c
* \version 1.0
*
* Implements the BSP level start-up code for the FX3G2 device.
*
*******************************************************************************
* \copyright
* (c) (2024), Cypress Semiconductor Corporation (an Infineon company) or
* an affiliate of Cypress Semiconductor Corporation.
*
* SPDX-License-Identifier: Apache-2.0
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*******************************************************************************/

#include "cy_pdl.h"
#include "cy_fx3g2_bsp.h"
#include <string.h>

#if defined(__cplusplus)
extern "C" {
#endif

/*******************************************************************************
 * Function name: fx3g2_clk_init
 ****************************************************************************//**
 *
 * Configure the device level clocks required for FX10 device operation.
 *
 * Clock configuration details:
 *
 * CLK_PATH #1: IMO (8 MHz) --> PLL0 (150 MHz) --> clk_hf0 --> clk_fast
 *                                             |           |
 *                                             |           --> clk_peri (75 MHz) --> clk_slow
 *                                             |
 *                                             --> clk_hf1 (37.5 MHz) --> clk_smif
 *                                             |
 *                                             --> clk_hf4 (150 MHz) --> clk_lvds
 *
 * CLK_PATH #2: IMO (8 MHz) --> PLL1 (48 MHz) ----> clk_hf2 --> clk_usbfs
 *
 * CLK_PATH #0: IMO (8 MHz) --> FLL (24.576 MHz) --> clk_hf3 --> clk_pdm (3.072 MHz)
 *
 * CLK_PATH #3: ECO (24 MHz) --> USBHS PLL Reference
 *******************************************************************************/
void fx3g2_clk_init (void)
{
    cy_stc_pll_manual_config_t pll0_cfg;
    cy_stc_pll_manual_config_t pll1_cfg;
    cy_stc_fll_manual_config_t fll_cfg;

    /* Configure PLL0 to generate 150 MHz clock, enable it and
     * wait for it to lock.
     */
    pll0_cfg.feedbackDiv  = 75u;
    pll0_cfg.referenceDiv = 2u;
    pll0_cfg.outputDiv    = 2u;
    pll0_cfg.lfMode       = false;      /* VCO frequency is 300 MHz. */
    pll0_cfg.outputMode   = CY_SYSCLK_FLLPLL_OUTPUT_AUTO;
    Cy_SysClk_PllManualConfigure(1, &pll0_cfg);
    Cy_SysClk_PllEnable(1, 0);
    while (!Cy_SysClk_PllLocked(1));

    /* Select PLL0 output as clk_hf0. */
    Cy_SysLib_SetWaitStates(false, 150UL);
    Cy_SysClk_ClkHfSetSource(0, CY_SYSCLK_CLKHF_IN_CLKPATH1);
    Cy_SysClk_ClkFastSetDivider(0U);

    /* clk_peri is (clk_fast / 2) or 75 MHz. clk_slow has same frequency as clk_peri. */
    Cy_SysClk_ClkPeriSetDivider(1);
    Cy_SysClk_ClkSlowSetDivider(0);

    /* Update modified frequency with the PDL. */
    SystemCoreClockUpdate();

    /* clk_hf1 configuration. */
    Cy_SysClk_ClkHfDisable(1);
    Cy_SysClk_ClkHfSetSource(1, CY_SYSCLK_CLKHF_IN_CLKPATH0);
    Cy_SysClk_ClkHfSetDivider(1, CY_SYSCLK_CLKHF_DIVIDE_BY_2);
    Cy_SysClk_ClkHfEnable(1);

    /* clk_hf4 configuration. */
    Cy_SysClk_ClkHfDisable(4);
    Cy_SysClk_ClkHfSetSource(4, CY_SYSCLK_CLKHF_IN_CLKPATH1);
    Cy_SysClk_ClkHfSetDivider(4, CY_SYSCLK_CLKHF_NO_DIVIDE);
    Cy_SysClk_ClkHfEnable(4);

    /* Configure PLL1 to generate 48 MHz clock, enable it and
     * wait for it to lock.
     */
    pll1_cfg.feedbackDiv  = 48u;
    pll1_cfg.referenceDiv = 2u;
    pll1_cfg.outputDiv    = 4u;
    pll1_cfg.lfMode       = true;      /* VCO frequency is 192 MHz. */
    pll1_cfg.outputMode   = CY_SYSCLK_FLLPLL_OUTPUT_AUTO;
    Cy_SysClk_PllManualConfigure(2, &pll1_cfg);
    Cy_SysClk_PllEnable(2, 0);
    while (!Cy_SysClk_PllLocked(2));

    /* Select PLL1 output as source for clk_hf2 and enable it. */
    Cy_SysClk_ClkHfDisable(2);
    Cy_SysClk_ClkHfSetSource(2, CY_SYSCLK_CLKHF_IN_CLKPATH2);
    Cy_SysClk_ClkHfSetDivider(2, CY_SYSCLK_CLKHF_NO_DIVIDE);
    Cy_SysClk_ClkHfEnable(2);

    /* FLL configuration to generate 24.576 MHz clock for PDM/TDM operation. */
    fll_cfg.fllMult          = 498UL;
    fll_cfg.refDiv           = 81U;
    fll_cfg.ccoRange         = CY_SYSCLK_FLL_CCO_RANGE0;        /* CCO frequency is 49.1 MHz. */
    fll_cfg.enableOutputDiv  = true;
    fll_cfg.lockTolerance    = 6U;
    fll_cfg.igain            = 8U;
    fll_cfg.pgain            = 7U;
    fll_cfg.settlingCount    = 8U;
    fll_cfg.outputMode       = CY_SYSCLK_FLLPLL_OUTPUT_AUTO;
    fll_cfg.cco_Freq         = 108U;
    Cy_SysClk_FllDisable();
    Cy_SysClk_FllManualConfigure(&fll_cfg);
    Cy_SysClk_FllEnable(0);
    while (!Cy_SysClk_FllLocked());

    /* Select FLL output as source for clk_hf3 and enable it. */
    Cy_SysClk_ClkHfDisable(3);
    Cy_SysClk_ClkHfSetSource(3, CY_SYSCLK_CLKHF_IN_CLKPATH0);
    Cy_SysClk_ClkHfSetDivider(3, CY_SYSCLK_CLKHF_NO_DIVIDE);
    Cy_SysClk_ClkHfEnable(3);
}

/*******************************************************************************
 * Function name: Cy_Fx3G2_InitPeripheralClocks
 ****************************************************************************//**
 *
 * Function used to enable clocks to different peripherals on the FX10 device.
 *
 * \param adcClkEnable
 * Whether to enable clock to the ADC in the USBSS block.
 *
 * \param usbfsClkEnable
 * Whether to enable bus reset detect clock input to the USBFS block.
 *
 *******************************************************************************/
void Cy_Fx3G2_InitPeripheralClocks (
        bool adcClkEnable,
        bool usbfsClkEnable)
{
    if (adcClkEnable) {
        /* Divide PERI clock at 75 MHz by 75 to get 1 MHz clock using 16-bit divider #1. */
        Cy_SysClk_PeriphSetDivider(CY_SYSCLK_DIV_16_BIT, 1, 74);
        Cy_SysClk_PeriphEnableDivider(CY_SYSCLK_DIV_16_BIT, 1);
        Cy_SysLib_DelayUs(10U);
        Cy_SysClk_PeriphAssignDivider(PCLK_LVDS2USB32SS_CLOCK_SAR, CY_SYSCLK_DIV_16_BIT, 1);
    }

    if (usbfsClkEnable) {
        /* Divide PERI clock at 75 MHz by 750 to get 100 KHz clock using 16-bit divider #2. */
        Cy_SysClk_PeriphSetDivider(CY_SYSCLK_DIV_16_BIT, 2, 749);
        Cy_SysClk_PeriphEnableDivider(CY_SYSCLK_DIV_16_BIT, 2);
        Cy_SysLib_DelayUs(10U);
        Cy_SysClk_PeriphAssignDivider(PCLK_USB_CLOCK_DEV_BRS, CY_SYSCLK_DIV_16_BIT, 2);
    }
}

/*******************************************************************************
 * Function name: Cy_Fx3G2_ConfigureIOs
 ****************************************************************************//**
 *
 * Function used to configure common GPIOs used across all FX10 applications.
 * The following pins are configured in strong drive mode:
 *  P0.0, P0.1   : Used for debug status indication during USB link bring-up
 *  P11.0, P11.1 : Chip level Digital Design For Test pins used for debugging.
 *  P9.2, P9.3   : USB Design For Test GPIOs used for debugging.
 *
 * \param dftEnable
 * Whether the Design For Test pins should be configured for debug function.
 *
 *******************************************************************************/
void Cy_Fx3G2_ConfigureIOs (
        bool dftEnable)
{
    cy_stc_gpio_pin_config_t pinCfg;

    /* Clear the structure to start with. */
    memset ((void *)&pinCfg, 0, sizeof(pinCfg));

    /* Configure P0.0 and P0.1 as General Purpose Output pins
     * with strong output drivers enabled.
     */
    pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
    pinCfg.hsiom     = P0_0_GPIO;
    Cy_GPIO_Pin_Init(P0_0_PORT, P0_0_PIN, &pinCfg);
    pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
    pinCfg.hsiom     = P0_1_GPIO;
    Cy_GPIO_Pin_Init(P0_1_PORT, P0_1_PIN, &pinCfg);

    if (dftEnable) {
        /* Choose chip level DDFT function for P11.0 and P11.1 pins
         * and enable output drivers.
         */
        pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
        pinCfg.hsiom     = P11_0_SRSS_DDFT_PIN_IN0;
        Cy_GPIO_Pin_Init(P11_0_PORT, P11_0_PIN, &pinCfg);
        pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
        pinCfg.hsiom     = P11_1_SRSS_DDFT_PIN_IN1;
        Cy_GPIO_Pin_Init(P11_1_PORT, P11_1_PIN, &pinCfg);

        /* Choose HBWSS GPIO DFT function for P9.2 and P9.3 pins and
         * enable output drivers.
         */
        pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
        pinCfg.hsiom     = P9_2_LVDS2USB32SS_USB32_GPIO_DDFT_O0;
        Cy_GPIO_Pin_Init(P9_2_PORT, P9_2_PIN, &pinCfg);
        pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
        pinCfg.hsiom     = P9_3_LVDS2USB32SS_USB32_GPIO_DDFT_O1;
        Cy_GPIO_Pin_Init(P9_3_PORT, P9_3_PIN, &pinCfg);

        /* Route the DDFT outputs from the High BandWidth SubSystem to
         * the chip level pins.
         */
        SRSS_TST_DDFT_FAST_CTL_REG = 0x00000C0BUL;
        SRSS_TST_DDFT_SLOW_CTL_REG = 0xC0008080UL;
    }
}

/*******************************************************************************
 * Function name: Cy_Fx3G2_SelectDFTFunctions
 ****************************************************************************//**
 *
 * Function used to select the Design-For-Test debug functions which are to
 * be driven on to the P11.0 (K7), P11.1 (K8), P9.2 (J7) and P9.3 (J8) pins
 * of the EZ-USB FX device. The Cy_Fx3G2_ConfigureIOs function must have
 * been called with dftEnable parameter set to true for these options to take
 * effect.
 *
 * \param dft0_func
 * Select the debug function to be driven on the P11.0 (K7) pin. Any USB/LVDS function
 * is supported.
 * \param dft1_func
 * Select the debug function to be driven on the P11.1 (K8) pin. Any USB/LVDS function
 * is supported.
 * \param usbdft0_func
 * Select the debug function to be driven on the P9.2 (J7) pin. Only USB functions
 * are supported.
 * \param usbdft1_func
 * Select the debug function to be driven on the P9.3 (J8) pin. Only USB functions
 * are supported.
 *
 * \return
 * true if DFT configuration is done, false in case of error.
 *******************************************************************************/
bool Cy_Fx3G2_SelectDFTFunctions (
        uint32_t dft0_func,
        uint32_t dft1_func,
        uint32_t usbdft0_func,
        uint32_t usbdft1_func)
{
    uint32_t mainSel = 0;
    uint32_t usbSel  = 0, usbGpioSel = 0;
    uint32_t phySel  = 0, phyRxSel = 0;
    uint32_t lvdsSel = 0;

    if (dft0_func != CY_FX_DBG_FUNC_NONE) {
        if (dft0_func >= CY_FX_DBG_FUNC_SIP_LNK0_TRAINING_DONE) {
            mainSel |= 0x0002UL;
            lvdsSel = ((dft0_func - 0x1000UL) & 0x0FFFUL);
        } else {
            if (dft0_func >= CY_FX_DBG_FUNC_USBSS_EG_SCK0_ACTIVE) {
                usbSel |= ((dft0_func - 0x0200UL) & 0x00FFUL);
            } else {
                if (dft0_func >= CY_FX_DBG_FUNC_USBPHY1_RXEQ_TRAINING) {
                    if (dft0_func >= CY_FX_DBG_FUNC_USBPHY1_RX_LFPSDET_OUT) {
                        phySel   |= 0x0028UL;
                        phyRxSel |= (0x8000UL | ((dft0_func - 0x0180UL) & 0x000FUL));
                    } else {
                        phySel |= ((dft0_func - 0x0100UL) & 0x3FUL);
                    }
                } else {
                    if (dft0_func >= CY_FX_DBG_FUNC_USBPHY0_RX_LFPSDET_OUT) {
                        phySel   |= 0x0028UL;
                        phyRxSel |= (0x8000UL | ((dft0_func - 0x0080UL) & 0x000FUL));
                    } else {
                        phySel |= (dft0_func & 0x3FUL);
                    }
                }
            }
        }
    }

    if (dft1_func != CY_FX_DBG_FUNC_NONE) {
        if (dft1_func >= CY_FX_DBG_FUNC_SIP_LNK0_TRAINING_DONE) {
            mainSel |= 0x0300UL;
            lvdsSel |= (((dft1_func - 0x1000UL) & 0x0FFFUL) << 15U);
        } else {
            mainSel |= 0x0100UL;

            if (dft1_func >= CY_FX_DBG_FUNC_USBSS_EG_SCK0_ACTIVE) {
                usbSel |= (((dft1_func - 0x0200UL) & 0x00FFUL) << 8U);
            } else {
                usbSel |= 0x0100UL;
                if (dft1_func >= CY_FX_DBG_FUNC_USBPHY1_RXEQ_TRAINING) {
                    if (dft1_func >= CY_FX_DBG_FUNC_USBPHY1_RX_LFPSDET_OUT) {
                        phySel   |= 0x2900UL;
                        phyRxSel |= (0x8000UL | (((dft1_func - 0x0180UL) & 0x000FUL) << 8U));
                    } else {
                        phySel |= (((dft1_func - 0x0100UL) & 0x3FUL) << 8U);
                    }
                } else {
                    if (dft1_func >= CY_FX_DBG_FUNC_USBPHY0_RX_LFPSDET_OUT) {
                        phySel   |= 0x2900UL;
                        phyRxSel |= (0x8000UL | (((dft1_func - 0x0080UL) & 0x000FUL) << 8U));
                    } else {
                        phySel |= ((dft1_func & 0x3FUL) << 8U);
                    }
                }
            }
        }
    }

    if ((usbdft0_func != CY_FX_DBG_FUNC_NONE) && (usbdft0_func < CY_FX_DBG_FUNC_SIP_LNK0_TRAINING_DONE)) {
        if (usbdft0_func >= CY_FX_DBG_FUNC_USBSS_EG_SCK0_ACTIVE) {
            usbGpioSel |= ((usbdft0_func - 0x0200UL) & 0x00FFUL);
        } else {
            if ((phySel & 0x00FFUL) != 0) {
                /* Too many USB PHY signals requested. Cannot route. */
                return false;
            } else {
                if (usbdft0_func >= CY_FX_DBG_FUNC_USBPHY1_RXEQ_TRAINING) {
                    if (usbdft0_func >= CY_FX_DBG_FUNC_USBPHY1_RX_LFPSDET_OUT) {
                        phySel   |= 0x0028UL;
                        phyRxSel |= (0x8000UL | ((usbdft0_func - 0x0180UL) & 0x000FUL));
                    } else {
                        phySel |= ((usbdft0_func - 0x0100UL) & 0x3FUL);
                    }
                } else {
                    if (usbdft0_func >= CY_FX_DBG_FUNC_USBPHY0_RX_LFPSDET_OUT) {
                        phySel   |= 0x0028UL;
                        phyRxSel |= (0x8000UL | ((usbdft0_func - 0x0080UL) & 0x000FUL));
                    } else {
                        phySel |= (usbdft0_func & 0x3FUL);
                    }
                }
            }
        }
    }

    if ((usbdft1_func != CY_FX_DBG_FUNC_NONE) && (usbdft1_func < CY_FX_DBG_FUNC_SIP_LNK0_TRAINING_DONE)) {
        if (usbdft1_func >= CY_FX_DBG_FUNC_USBSS_EG_SCK0_ACTIVE) {
            usbGpioSel |= (((usbdft1_func - 0x0200UL) & 0x00FFUL) << 8U);
        } else {
            if ((phySel & 0xFF00UL) != 0) {
                /* Too many USB PHY signals requested. Cannot route. */
                return false;
            } else {
                usbGpioSel |= 0x0100UL;
                if (usbdft1_func >= CY_FX_DBG_FUNC_USBPHY1_RXEQ_TRAINING) {
                    if (usbdft1_func >= CY_FX_DBG_FUNC_USBPHY1_RX_LFPSDET_OUT) {
                        phySel   |= 0x2900UL;
                        phyRxSel |= (0x8000UL | (((usbdft1_func - 0x0180UL) & 0x000FUL) << 8U));
                    } else {
                        phySel |= (((usbdft1_func - 0x0100UL) & 0x3FUL) << 8U);
                    }
                } else {
                    if (usbdft1_func >= CY_FX_DBG_FUNC_USBPHY0_RX_LFPSDET_OUT) {
                        phySel   |= 0x2900UL;
                        phyRxSel |= (0x8000UL | (((usbdft1_func - 0x0080UL) & 0x000FUL) << 8U));
                    } else {
                        phySel |= ((usbdft1_func & 0x3FUL) << 8U);
                    }
                }
            }
        }
    }

    /* Apply the DDFT settings. */
    MAIN_REG->DDFT_MUX                          = mainSel;
    USB32DEV->USB32DEV_MAIN.DDFT_MUX            = usbSel;
    USB32DEV->USB32DEV_MAIN.GPIO_DDFT_MUX       = usbGpioSel;
    LVDSSS_LVDS->DDFT_MUX_SEL                   = lvdsSel;

    USB32DEV->USB32DEV_PHYSS.USB40PHY[0].USB40PHY_TOP.PHYSS_DDFT_MUX_SEL = phySel;
    USB32DEV->USB32DEV_PHYSS.USB40PHY[1].USB40PHY_TOP.PHYSS_DDFT_MUX_SEL = phySel;
    USB32DEV->USB32DEV_PHYSS.USB40PHY[0].USB40PHY_RX.RX_DTEST_CFG        = phyRxSel;
    USB32DEV->USB32DEV_PHYSS.USB40PHY[1].USB40PHY_RX.RX_DTEST_CFG        = phyRxSel;

    return true;
}

/*******************************************************************************
 * Function name: Cy_Fx3G2_OnResetInit
 ****************************************************************************//**
 *
 * This function performs initialization that is required to enable scatter
 * loading of data into the High BandWidth RAM during device boot-up. The FX10
 * device comes up with the High BandWidth RAM disabled and hence any attempt
 * to read/write the RAM will cause the processor to hang. The RAM needs to
 * be enabled with default clock settings to allow scatter loading to work.
 * This function needs to be called from Cy_OnResetUser.
 *
 *******************************************************************************/
void
Cy_Fx3G2_OnResetInit (
        void)
{
    /* Enable clk_hf4 with IMO as input. */
    SRSS->CLK_ROOT_SELECT[4] = SRSS_CLK_ROOT_SELECT_ENABLE_Msk;

    /* Enable LVDS2USB32SS IP and select clk_hf[4] as clock input. */
    MAIN_REG->CTRL = (
            MAIN_REG_CTRL_IP_ENABLED_Msk |
            (1UL << MAIN_REG_CTRL_NUM_FAST_AHB_STALL_CYCLES_Pos) |
            (1UL << MAIN_REG_CTRL_NUM_SLOW_AHB_STALL_CYCLES_Pos) |
            (3UL << MAIN_REG_CTRL_DMA_SRC_SEL_Pos));
}

/*******************************************************************************
 * Function name: Cy_Fx3G2_MemSetDword
 ****************************************************************************//**
 *
 * Initialize a memory buffer with the specified 4-byte value.
 *
 * \param pBuffer
 * Pointer to buffer to be initialized.
 *
 * \param value
 * Value to initialize the memory buffer with.
 *
 * \param byteCount
 * Size of the buffer in bytes.
 *
 *******************************************************************************/
void
Cy_Fx3G2_MemSetDword (
        uint32_t *pBuffer,
        uint32_t value,
        uint32_t byteCount)
{
    uint32_t index;

    if ((pBuffer != NULL) && (byteCount > 0)) {
        for (index = 0; index < (byteCount / 4); index++) {
            pBuffer[index] = value;
        }

        switch (byteCount & 0x03) {
            case 3:
                pBuffer[index] = (pBuffer[index] & 0xFF000000UL) | (value & 0x00FFFFFFUL);
                break;

            case 2:
                pBuffer[index] = (pBuffer[index] & 0xFFFF0000UL) | (value & 0x0000FFFFUL);
                break;

            case 1:
                pBuffer[index] = (pBuffer[index] & 0xFFFFFF00UL) | (value & 0x000000FFUL);
                break;

            default:
                break;
        }
    }
}

/*******************************************************************************
 * Function name: Cy_Fx3G2_MemCpyDword
 ****************************************************************************//**
 *
 * Copy data from source to destination buffer using 4-byte words.
 *
 * \param pDst
 * Pointer to destination buffer.
 *
 * \param pSrc
 * Pointer to source buffer.
 *
 * \param byteCount
 * Size of the buffer in bytes.
 *
 *******************************************************************************/
void
Cy_Fx3G2_MemCpyDword (
        uint32_t *pDst,
        const uint32_t *pSrc,
        uint32_t byteCount)
{
    uint32_t index;

    if ((pDst != NULL) && (pSrc != NULL) && (byteCount > 0)) {
        for (index = 0; index < (byteCount / 4); index++) {
            pDst[index] = pSrc[index];
        }

        switch (byteCount & 0x03) {
            case 3:
                pDst[index] = (pDst[index] & 0xFF000000UL) | (pSrc[index] & 0x00FFFFFFUL);
                break;

            case 2:
                pDst[index] = (pDst[index] & 0xFFFF0000UL) | (pSrc[index] & 0x0000FFFFUL);
                break;

            case 1:
                pDst[index] = (pDst[index] & 0xFFFFFF00UL) | (pSrc[index] & 0x000000FFUL);
                break;

            default:
                break;
        }
    }
}

#if defined(__cplusplus)
}
#endif

/*[]*/

