/***************************************************************************//**
* \file cy_device.h
* \version 2.30
*
* This file specifies the structure for core and peripheral block HW base
* addresses, versions, and parameters.
*
********************************************************************************
* \copyright
* Copyright 2018-2022 Cypress Semiconductor Corporation
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

#ifndef CY_DEVICE_H_
#define CY_DEVICE_H_

#include <stdint.h>
#include <stddef.h>

#include "cy_device_headers.h"

/* Device descriptor type */
typedef struct
{
    /* Base HW addresses */
    uint32_t cpussBase;
    uint32_t flashcBase;
    uint32_t periBase;
    uint32_t udbBase;
    uint32_t protBase;
    uint32_t hsiomBase;
    uint32_t gpioBase;
    uint32_t passBase;
    uint32_t ipcBase;
    uint32_t cryptoBase;

    /* IP block versions: [7:4] major, [3:0] minor */
    uint8_t  cpussVersion;
    uint8_t  cryptoVersion;
    uint8_t  dwVersion;
    uint8_t  flashcVersion;
    uint8_t  gpioVersion;
    uint8_t  hsiomVersion;
    uint8_t  ipcVersion;
    uint8_t  periVersion;
    uint8_t  protVersion;
    uint8_t  srssVersion;

    /* Parameters */
    uint8_t  cpussIpcNr;
    uint8_t  cpussIpcIrqNr;
    uint8_t  cpussDw0ChNr;
    uint8_t  cpussDw1ChNr;
    uint8_t  cpussFlashPaSize;
    int16_t  cpussIpc0Irq;
    int16_t  cpussFmIrq;
    int16_t  cpussNotConnectedIrq;
    uint8_t  srssNumClkpath;
    uint8_t  srssNumPll;
    uint8_t  srssNumHfroot;
    uint8_t  srssIsPiloPresent;
    uint8_t  periClockNr;
    uint8_t  smifDeviceNr;
    uint8_t  sysPmSimoPresent;
    uint32_t protBusMasterMask;
    uint32_t cryptoMemSize;
    uint8_t  flashRwwRequired;
    uint8_t  flashPipeRequired;
    uint8_t  flashWriteDelay;
    uint8_t  flashProgramDelay;
    uint8_t  flashEraseDelay;
    uint8_t  flashCtlMainWs0Freq;
    uint8_t  flashCtlMainWs1Freq;
    uint8_t  flashCtlMainWs2Freq;
    uint8_t  flashCtlMainWs3Freq;
    uint8_t  flashCtlMainWs4Freq;
    uint8_t  tcpwmCC1Present;
    uint8_t  tcpwmAMCPresent;
    uint8_t  tcpwmSMCPrecent;

    /* Peripheral register offsets */

    /* DW registers */
    uint16_t dwChOffset;
    uint16_t dwChSize;
    uint8_t  dwChCtlPrioPos;
    uint8_t  dwChCtlPreemptablePos;
    uint8_t  dwStatusChIdxPos;
    uint32_t dwStatusChIdxMsk;

    /* PERI registers */
    uint16_t periTrCmdOffset;
    uint16_t periTrCmdGrSelMsk;
    uint16_t periTrGrOffset;
    uint16_t periTrGrSize;

    uint8_t  periDivCmdDivSelMsk;
    uint8_t  periDivCmdTypeSelPos;
    uint8_t  periDivCmdPaDivSelPos;
    uint8_t  periDivCmdPaTypeSelPos;

    uint16_t periDiv8CtlOffset;
    uint16_t periDiv16CtlOffset;
    uint16_t periDiv16_5CtlOffset;
    uint16_t periDiv24_5CtlOffset;

    /* GPIO registers */
    uint8_t  gpioPrtIntrCfgOffset;
    uint8_t  gpioPrtCfgOffset;
    uint8_t  gpioPrtCfgInOffset;
    uint8_t  gpioPrtCfgOutOffset;
    uint8_t  gpioPrtCfgSioOffset;

    /* CPUSS registers */
    uint32_t cpussCm0ClockCtlOffset;
    uint32_t cpussCm4ClockCtlOffset;
    uint32_t cpussCm4StatusOffset;
    uint32_t cpussCm0StatusOffset;
    uint32_t cpussCm4PwrCtlOffset;
    uint32_t cpussTrimRamCtlOffset;
    uint32_t cpussTrimRomCtlOffset;
    uint32_t cpussSysTickCtlOffset;
    uint16_t cpussCm0NmiCtlOffset;
    uint16_t cpussCm4NmiCtlOffset;
    uint16_t cpussRomCtl;
    uint16_t cpussRam0Ctl0;
    uint16_t cpussRam1Ctl0;
    uint16_t cpussRam2Ctl0;
    uint16_t cpussRam0PwrCtl;
    uint16_t cpussRam1PwrCtl;
    uint16_t cpussRam2PwrCtl;

    /* IPC registers */
    uint16_t ipcStructSize;
    uint32_t ipcLockStatusOffset;
} cy_stc_device_t;

/*******************************************************************************
*                   Global Variables
*******************************************************************************/

extern const cy_stc_device_t   cy_deviceIpBlockCfgFx3G2;
extern const cy_stc_device_t * cy_device;


/*******************************************************************************
*                   Function Prototypes
*******************************************************************************/

void Cy_PDL_Init(const cy_stc_device_t * device);

/*******************************************************************************
*               Generic Macro Definitions
*******************************************************************************/
#define GET_ALIAS_ADDRESS(addr)             (uint32_t)(addr)

/*******************************************************************************
*               Register Access Helper Macros
*******************************************************************************/
#define CY_DEVICE_CAT1E            /* Device Category */
#define CY_CRYPTO_V1                        (0x20U > cy_device->cryptoVersion) /* true if the mxcrypto version is 1.x */

#define CY_SRSS_V1_3                        (0x13U == cy_device->srssVersion)
#define CY_SRSS_MFO_PRESENT                 (CY_SRSS_V1_3)

#define CY_SRSS_PILO_PRESENT                 (1U == cy_device->srssIsPiloPresent)

#define CY_SRSS_NUM_CLKPATH                 ((uint32_t)(cy_device->srssNumClkpath))
#define CY_SRSS_NUM_PLL                     ((uint32_t)(cy_device->srssNumPll))
#define CY_SRSS_NUM_HFROOT                  ((uint32_t)(cy_device->srssNumHfroot))
#define CY_SRSS_PLL_PRESENT                 SRSS_NUM_PLL
#define CY_SRSS_PLL400M_PRESENT             0
#define CY_SRSS_DPLL_LP_PRESENT             0

#define SRSS_PWR_CTL                        (((SRSS_Type *) SRSS)->PWR_CTL)
#define SRSS_PWR_HIBERNATE                  (((SRSS_Type *) SRSS)->PWR_HIBERNATE)
#define SRSS_PWR_TRIM_PWRSYS_CTL            (((SRSS_Type *) SRSS)->PWR_TRIM_PWRSYS_CTL)
#define SRSS_PWR_BUCK_CTL                   (((SRSS_Type *) SRSS)->PWR_BUCK_CTL)
#define SRSS_PWR_BUCK_CTL2                  (((SRSS_Type *) SRSS)->PWR_BUCK_CTL2)
#define SRSS_PWR_TRIM_WAKE_CTL              (((SRSS_Type *) SRSS)->PWR_TRIM_WAKE_CTL)
#define SRSS_PWR_LVD_CTL                    (((SRSS_Type *) SRSS)->PWR_LVD_CTL)
#define SRSS_PWR_LVD_STATUS                 (((SRSS_Type *) SRSS)->PWR_LVD_STATUS)
#define SRSS_WDT_CTL                        (((SRSS_Type *) SRSS)->WDT_CTL)
#define SRSS_WDT_CNT                        (((SRSS_Type *) SRSS)->WDT_CNT)
#define SRSS_WDT_MATCH                      (((SRSS_Type *) SRSS)->WDT_MATCH)
#define SRSS_CLK_DSI_SELECT                 (((SRSS_Type *) SRSS)->CLK_DSI_SELECT)
#define SRSS_CLK_PATH_SELECT                (((SRSS_Type *) SRSS)->CLK_PATH_SELECT)
#define SRSS_CLK_ROOT_SELECT                (((SRSS_Type *) SRSS)->CLK_ROOT_SELECT)
#define SRSS_CLK_CSV_HF_LIMIT(clk)          (((SRSS_Type *) SRSS)->CLK_CSV[(clk)].HF_LIMIT)
#define SRSS_CLK_CSV_HF_CTL(clk)            (((SRSS_Type *) SRSS)->CLK_CSV[(clk)].HF_CTL)
#define SRSS_CLK_SELECT                     (((SRSS_Type *) SRSS)->CLK_SELECT)
#define SRSS_CLK_TIMER_CTL                  (((SRSS_Type *) SRSS)->CLK_TIMER_CTL)
#define SRSS_CLK_CSV_WCO_CTL                (((SRSS_Type *) SRSS)->CLK_CSV_WCO_CTL)
#define SRSS_CLK_ILO_CONFIG                 (((SRSS_Type *) SRSS)->CLK_ILO_CONFIG)
#define SRSS_CLK_OUTPUT_SLOW                (((SRSS_Type *) SRSS)->CLK_OUTPUT_SLOW)
#define SRSS_CLK_OUTPUT_FAST                (((SRSS_Type *) SRSS)->CLK_OUTPUT_FAST)
#define SRSS_CLK_CAL_CNT1                   (((SRSS_Type *) SRSS)->CLK_CAL_CNT1)
#define SRSS_CLK_CAL_CNT2                   (((SRSS_Type *) SRSS)->CLK_CAL_CNT2)
#define SRSS_CLK_ECO_CONFIG                 (((SRSS_Type *) SRSS)->CLK_ECO_CONFIG)
#define SRSS_CLK_ECO_STATUS                 (((SRSS_Type *) SRSS)->CLK_ECO_STATUS)
#define SRSS_CLK_PILO_CONFIG                (((SRSS_Type *) SRSS)->CLK_PILO_CONFIG)
#define SRSS_CLK_MF_SELECT                  (((SRSS_Type *) SRSS)->CLK_MF_SELECT)  /* for CY_SRSS_V1_3 only */
#define SRSS_CLK_MFO_CONFIG                 (((SRSS_Type *) SRSS)->CLK_MFO_CONFIG) /* for CY_SRSS_V1_3 only */
#define SRSS_CLK_FLL_CONFIG                 (((SRSS_Type *) SRSS)->CLK_FLL_CONFIG)
#define SRSS_CLK_FLL_CONFIG2                (((SRSS_Type *) SRSS)->CLK_FLL_CONFIG2)
#define SRSS_CLK_FLL_CONFIG3                (((SRSS_Type *) SRSS)->CLK_FLL_CONFIG3)
#define SRSS_CLK_FLL_CONFIG4                (((SRSS_Type *) SRSS)->CLK_FLL_CONFIG4)
#define SRSS_CLK_FLL_STATUS                 (((SRSS_Type *) SRSS)->CLK_FLL_STATUS)
#define SRSS_CLK_PLL_CONFIG                 (((SRSS_Type *) SRSS)->CLK_PLL_CONFIG)
#define SRSS_CLK_PLL_STATUS                 (((SRSS_Type *) SRSS)->CLK_PLL_STATUS)
#define SRSS_SRSS_INTR                      (((SRSS_Type *) SRSS)->SRSS_INTR)
#define SRSS_SRSS_INTR_SET                  (((SRSS_Type *) SRSS)->SRSS_INTR_SET)
#define SRSS_SRSS_INTR_CFG                  (((SRSS_Type *) SRSS)->SRSS_INTR_CFG)
#define SRSS_SRSS_INTR_MASK                 (((SRSS_Type *) SRSS)->SRSS_INTR_MASK)
#define SRSS_SRSS_INTR_MASKED               (((SRSS_Type *) SRSS)->SRSS_INTR_MASKED)
#define SRSS_CLK_TRIM_ILO_CTL               (((SRSS_Type *) SRSS)->CLK_TRIM_ILO_CTL)
#define SRSS_CLK_TRIM_ECO_CTL               (((SRSS_Type *) SRSS)->CLK_TRIM_ECO_CTL)

#define SRSS_RES_CAUSE                      (((SRSS_Type *) SRSS)->RES_CAUSE)
#define SRSS_RES_CAUSE2                     (((SRSS_Type *) SRSS)->RES_CAUSE2)

#define SRSS_TST_DDFT_SLOW_CTL_REG          (*(volatile uint32_t *) 0x40260108U)
#define SRSS_TST_DDFT_FAST_CTL_REG          (*(volatile uint32_t *) 0x40260104U)

#define SRSS_TST_DDFT_SLOW_CTL_MASK         (0x00001F1EU)
#define SRSS_TST_DDFT_FAST_CTL_MASK         (62U)

/*******************************************************************************
*                CRYPTO
*******************************************************************************/

/* The CRYPTO internal-memory buffer-size in 32-bit words. */
#define CY_CRYPTO_MEM_BUFF_SIZE_U32         (1024U)

typedef CRYPTO_Type CRYPTO_V2_Type;

#define CRYPTO_V2_LOAD0_FF_STATUS_USED5_Pos    CRYPTO_LOAD0_FF_STATUS_USED5_Pos
#define CRYPTO_V2_LOAD0_FF_STATUS_USED5_Msk    CRYPTO_LOAD0_FF_STATUS_USED5_Msk
#define CRYPTO_V2_LOAD0_FF_STATUS_BUSY_Pos     CRYPTO_LOAD0_FF_STATUS_BUSY_Pos
#define CRYPTO_V2_LOAD0_FF_STATUS_BUSY_Msk     CRYPTO_LOAD0_FF_STATUS_BUSY_Msk
#define CRYPTO_V2_LOAD1_FF_STATUS_USED5_Pos    CRYPTO_LOAD1_FF_STATUS_USED5_Pos
#define CRYPTO_V2_LOAD1_FF_STATUS_USED5_Msk    CRYPTO_LOAD1_FF_STATUS_USED5_Msk
#define CRYPTO_V2_LOAD1_FF_STATUS_BUSY_Pos     CRYPTO_LOAD1_FF_STATUS_BUSY_Pos
#define CRYPTO_V2_LOAD1_FF_STATUS_BUSY_Msk     CRYPTO_LOAD1_FF_STATUS_BUSY_Msk
#define CRYPTO_V2_STORE_FF_STATUS_USED5_Pos    CRYPTO_STORE_FF_STATUS_USED5_Pos
#define CRYPTO_V2_STORE_FF_STATUS_USED5_Msk    CRYPTO_STORE_FF_STATUS_USED5_Msk
#define CRYPTO_V2_STORE_FF_STATUS_BUSY_Pos     CRYPTO_STORE_FF_STATUS_BUSY_Pos
#define CRYPTO_V2_STORE_FF_STATUS_BUSY_Msk     CRYPTO_STORE_FF_STATUS_BUSY_Msk
#define CRYPTO_V2_CRC_CTL_DATA_REVERSE_Pos     CRYPTO_CRC_CTL_DATA_REVERSE_Pos
#define CRYPTO_V2_CRC_CTL_DATA_REVERSE_Msk     CRYPTO_CRC_CTL_DATA_REVERSE_Msk
#define CRYPTO_V2_CRC_CTL_REM_REVERSE_Pos      CRYPTO_CRC_CTL_REM_REVERSE_Pos
#define CRYPTO_V2_CRC_CTL_REM_REVERSE_Msk      CRYPTO_CRC_CTL_REM_REVERSE_Msk
#define CRYPTO_V2_CRC_DATA_CTL_DATA_XOR_Pos    CRYPTO_CRC_DATA_CTL_DATA_XOR_Pos
#define CRYPTO_V2_CRC_DATA_CTL_DATA_XOR_Msk    CRYPTO_CRC_DATA_CTL_DATA_XOR_Msk
#define CRYPTO_V2_CRC_POL_CTL_POLYNOMIAL_Pos   CRYPTO_CRC_POL_CTL_POLYNOMIAL_Pos
#define CRYPTO_V2_CRC_POL_CTL_POLYNOMIAL_Msk   CRYPTO_CRC_POL_CTL_POLYNOMIAL_Msk
#define CRYPTO_V2_CRC_REM_CTL_REM_XOR_Pos      CRYPTO_CRC_REM_CTL_REM_XOR_Pos
#define CRYPTO_V2_CRC_REM_CTL_REM_XOR_Msk      CRYPTO_CRC_REM_CTL_REM_XOR_Msk
#define CRYPTO_V2_RESULT_DATA_Pos              CRYPTO_RESULT_DATA_Pos
#define CRYPTO_V2_RESULT_DATA_Msk              CRYPTO_RESULT_DATA_Msk
#define CRYPTO_V2_CRC_REM_RESULT_REM_Msk       CRYPTO_CRC_REM_RESULT_REM_Msk
#define CRYPTO_V2_CRC_REM_RESULT_REM_Pos       CRYPTO_CRC_REM_RESULT_REM_Pos
#define CRYPTO_V2_VU_CTL2_MASK_Msk             CRYPTO_VU_CTL2_MASK_Msk
#define CRYPTO_V2_VU_CTL2_MASK_Pos             CRYPTO_VU_CTL2_MASK_Pos
#define CRYPTO_V2_VU_RF_DATA_DATA32_Pos        CRYPTO_VU_RF_DATA_DATA32_Pos
#define CRYPTO_V2_VU_RF_DATA_DATA32_Msk        CRYPTO_VU_RF_DATA_DATA32_Msk
#define CRYPTO_V2_CTL_ENABLED_Pos              CRYPTO_CTL_ENABLED_Pos
#define CRYPTO_V2_CTL_ENABLED_Msk              CRYPTO_CTL_ENABLED_Msk
#define CRYPTO_V2_CTL_ECC_EN_Pos               CRYPTO_CTL_ECC_EN_Pos
#define CRYPTO_V2_CTL_ECC_EN_Msk               CRYPTO_CTL_ECC_EN_Msk
#define CRYPTO_V2_INSTR_FF_CTL_BLOCK_Pos       CRYPTO_INSTR_FF_CTL_BLOCK_Pos
#define CRYPTO_V2_INSTR_FF_CTL_BLOCK_Msk       CRYPTO_INSTR_FF_CTL_BLOCK_Msk
#define CRYPTO_V2_INSTR_FF_CTL_CLEAR_Pos       CRYPTO_INSTR_FF_CTL_CLEAR_Pos
#define CRYPTO_V2_INSTR_FF_CTL_CLEAR_Msk       CRYPTO_INSTR_FF_CTL_CLEAR_Msk
#define CRYPTO_V2_INSTR_FF_CTL_EVENT_LEVEL_Pos CRYPTO_INSTR_FF_CTL_EVENT_LEVEL_Pos
#define CRYPTO_V2_INSTR_FF_CTL_EVENT_LEVEL_Msk CRYPTO_INSTR_FF_CTL_EVENT_LEVEL_Msk
#define CRYPTO_V2_PR_CMD_START_Pos             CRYPTO_PR_CMD_START_Pos
#define CRYPTO_V2_PR_CMD_START_Msk             CRYPTO_PR_CMD_START_Msk
#define CRYPTO_V2_STATUS_BUSY_Pos              CRYPTO_STATUS_BUSY_Pos
#define CRYPTO_V2_STATUS_BUSY_Msk              CRYPTO_STATUS_BUSY_Msk
#define CRYPTO_V2_PR_RESULT_DATA32_Pos         CRYPTO_PR_RESULT_DATA32_Pos
#define CRYPTO_V2_PR_RESULT_DATA32_Msk         CRYPTO_PR_RESULT_DATA32_Msk

/*******************************************************************************
*                CANFD
*******************************************************************************/

#define CANFD_CTL(base)                     (((CANFD_Type *)(base))->CTL)
#define CANFD_STATUS(base)                  (((CANFD_Type *)(base))->STATUS)
#define CANFD_NBTP(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.NBTP)
#define CANFD_IR(base, chan)                      (((CANFD_Type *)(base))->CH[chan].M_TTCAN.IR)
#define CANFD_IE(base, chan)                      (((CANFD_Type *)(base))->CH[chan].M_TTCAN.IE)
#define CANFD_ILS(base, chan)                     (((CANFD_Type *)(base))->CH[chan].M_TTCAN.ILS)
#define CANFD_ILE(base, chan)                     (((CANFD_Type *)(base))->CH[chan].M_TTCAN.ILE)
#define CANFD_CCCR(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.CCCR)
#define CANFD_SIDFC(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.SIDFC)
#define CANFD_XIDFC(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.XIDFC)
#define CANFD_XIDAM(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.XIDAM)
#define CANFD_RXESC(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXESC)
#define CANFD_RXF0C(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXF0C)
#define CANFD_RXF1C(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXF1C)
#define CANFD_RXFTOP_CTL(base, chan)              (((CANFD_Type *)(base))->CH[chan].RXFTOP_CTL)
#define CANFD_RXBC(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXBC)
#define CANFD_TXESC(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXESC)
#define CANFD_TXEFC(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXEFC)
#define CANFD_TXBC(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBC)
#define CANFD_DBTP(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.DBTP)
#define CANFD_TDCR(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TDCR)
#define CANFD_GFC(base, chan)                     (((CANFD_Type *)(base))->CH[chan].M_TTCAN.GFC)
#define CANFD_TXBRP(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBRP)
#define CANFD_TXBAR(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBAR)
#define CANFD_TXBCR(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBCR)
#define CANFD_TXBTO(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBTO)
#define CANFD_TXBCF(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBCF)
#define CANFD_TXBTIE(base, chan)                  (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBTIE)
#define CANFD_TXBCIE(base, chan)                  (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TXBCIE)
#define CANFD_NDAT1(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.NDAT1)
#define CANFD_NDAT2(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.NDAT2)
#define CANFD_RXF0S(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXF0S)
#define CANFD_RXFTOP0_DATA(base, chan)            (((CANFD_Type *)(base))->CH[chan].RXFTOP0_DATA)
#define CANFD_RXFTOP1_DATA(base, chan)            (((CANFD_Type *)(base))->CH[chan].RXFTOP1_DATA)
#define CANFD_RXF0A(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXF0A)
#define CANFD_RXF1S(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXF1S)
#define CANFD_RXF1A(base, chan)                   (((CANFD_Type *)(base))->CH[chan].M_TTCAN.RXF1A)
#define CANFD_PSR(base, chan)                     (((CANFD_Type *)(base))->CH[chan].M_TTCAN.PSR)
#define CANFD_TEST(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.TEST)
#define CANFD_CREL(base, chan)                    (((CANFD_Type *)(base))->CH[chan].M_TTCAN.CREL)

#define CY_CANFD_CHANNELS_NUM               (0x1UL)


/*******************************************************************************
*                FLASHC
*******************************************************************************/

#define FLASHC_FM_CTL_ANA_CTL0              (((FLASHC_Type *) cy_device->flashcBase)->FM_CTL.ANA_CTL0)
#define FLASHC_FM_CTL_BOOKMARK              (((FLASHC_Type *) cy_device->flashcBase)->FM_CTL.BOOKMARK)
#define FLASHC_FLASH_CMD                    (((FLASHC_Type *) cy_device->flashcBase)->FLASH_CMD)
#define FLASHC_FLASH_CTL                    (((FLASHC_Type *) cy_device->flashcBase)->FLASH_CTL)
#define FLASHC_BIST_DATA_0                  (((FLASHC_Type *) cy_device->flashcBase)->BIST_DATA[0U])
#define FLASHC_BIST_STATUS                  (((FLASHC_Type *) cy_device->flashcBase)->BIST_STATUS)

#define FLASHC_V2_FLASH_CTL_MAIN_WS_Pos         FLASHC_FLASH_CTL_MAIN_WS_Pos
#define FLASHC_V2_FLASH_CTL_MAIN_WS_Msk         FLASHC_FLASH_CTL_MAIN_WS_Msk
#define FLASHC_V2_FLASH_CTL_MAIN_MAP_Pos        FLASHC_FLASH_CTL_MAIN_MAP_Pos
#define FLASHC_V2_FLASH_CTL_MAIN_MAP_Msk        FLASHC_FLASH_CTL_MAIN_MAP_Msk
#define FLASHC_V2_FLASH_CTL_WORK_MAP_Pos        FLASHC_FLASH_CTL_WORK_MAP_Pos
#define FLASHC_V2_FLASH_CTL_WORK_MAP_Msk        FLASHC_FLASH_CTL_WORK_MAP_Msk
#define FLASHC_V2_FLASH_CTL_MAIN_BANK_MODE_Pos  FLASHC_FLASH_CTL_MAIN_BANK_MODE_Pos
#define FLASHC_V2_FLASH_CTL_MAIN_BANK_MODE_Msk  FLASHC_FLASH_CTL_MAIN_BANK_MODE_Msk
#define FLASHC_V2_FLASH_CTL_WORK_BANK_MODE_Pos  FLASHC_FLASH_CTL_WORK_BANK_MODE_Pos
#define FLASHC_V2_FLASH_CTL_WORK_BANK_MODE_Msk  FLASHC_FLASH_CTL_WORK_BANK_MODE_Msk
#define FLASHC_V2_FLASH_CTL_MAIN_ECC_EN_Pos     FLASHC_FLASH_CTL_MAIN_ECC_EN_Pos
#define FLASHC_V2_FLASH_CTL_MAIN_ECC_EN_Msk     FLASHC_FLASH_CTL_MAIN_ECC_EN_Msk
#define FLASHC_V2_FLASH_CTL_MAIN_ECC_INJ_EN_Pos FLASHC_FLASH_CTL_MAIN_ECC_INJ_EN_Pos
#define FLASHC_V2_FLASH_CTL_MAIN_ECC_INJ_EN_Msk FLASHC_FLASH_CTL_MAIN_ECC_INJ_EN_Msk
#define FLASHC_V2_FLASH_CTL_MAIN_ERR_SILENT_Pos FLASHC_FLASH_CTL_MAIN_ERR_SILENT_Pos
#define FLASHC_V2_FLASH_CTL_MAIN_ERR_SILENT_Msk FLASHC_FLASH_CTL_MAIN_ERR_SILENT_Msk
#define FLASHC_V2_FLASH_CTL_WORK_ECC_EN_Pos     FLASHC_FLASH_CTL_WORK_ECC_EN_Pos
#define FLASHC_V2_FLASH_CTL_WORK_ECC_EN_Msk     FLASHC_FLASH_CTL_WORK_ECC_EN_Msk
#define FLASHC_V2_FLASH_CTL_WORK_ECC_INJ_EN_Pos FLASHC_FLASH_CTL_WORK_ECC_INJ_EN_Pos
#define FLASHC_V2_FLASH_CTL_WORK_ECC_INJ_EN_Msk FLASHC_FLASH_CTL_WORK_ECC_INJ_EN_Msk
#define FLASHC_V2_FLASH_CTL_WORK_ERR_SILENT_Pos FLASHC_FLASH_CTL_WORK_ERR_SILENT_Pos
#define FLASHC_V2_FLASH_CTL_WORK_ERR_SILENT_Msk FLASHC_FLASH_CTL_WORK_ERR_SILENT_Msk


/*******************************************************************************
*                SFLASH
*******************************************************************************/

#define SFLASH_DIE_YEAR                     (((SFLASH_Type *) SFLASH)->DIE_YEAR)
#define SFLASH_DIE_MINOR                    (((SFLASH_Type *) SFLASH)->DIE_MINOR)
#define SFLASH_DIE_SORT                     (((SFLASH_Type *) SFLASH)->DIE_SORT)
#define SFLASH_DIE_Y                        (((SFLASH_Type *) SFLASH)->DIE_Y)
#define SFLASH_DIE_X                        (((SFLASH_Type *) SFLASH)->DIE_X)
#define SFLASH_DIE_WAFER                    (((SFLASH_Type *) SFLASH)->DIE_WAFER)
#define SFLASH_DIE_LOT(val)                 (((SFLASH_Type *) SFLASH)->DIE_LOT[(val)])
#define SFLASH_FAMILY_ID                    (((SFLASH_Type *) SFLASH)->FAMILY_ID)
#define SFLASH_SI_REVISION_ID               (((SFLASH_Type *) SFLASH)->SI_REVISION_ID)
#define SFLASH_PWR_TRIM_WAKE_CTL            (((SFLASH_Type *) SFLASH)->PWR_TRIM_WAKE_CTL)
#define SFLASH_LDO_0P9V_TRIM                (((SFLASH_Type *) SFLASH)->LDO_0P9V_TRIM)
#define SFLASH_LDO_1P1V_TRIM                (((SFLASH_Type *) SFLASH)->LDO_1P1V_TRIM)
#define SFLASH_BLE_DEVICE_ADDRESS           (((SFLASH_Type *) SFLASH)->BLE_DEVICE_ADDRESS)
#define SFLASH_SILICON_ID                   (((SFLASH_Type *) SFLASH)->SILICON_ID)
#define SFLASH_SINGLE_CORE                  (*(volatile uint8_t *) (SFLASH_BASE + 0xBU))


#define SFLASH_CPUSS_TRIM_ROM_CTL_LP        (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_ROM_CTL_LP)
#define SFLASH_CPUSS_TRIM_RAM_CTL_LP        (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_RAM_CTL_LP)
#define SFLASH_CPUSS_TRIM_ROM_CTL_ULP       (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_ROM_CTL_ULP)
#define SFLASH_CPUSS_TRIM_RAM_CTL_ULP       (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_RAM_CTL_ULP)
#define SFLASH_CPUSS_TRIM_ROM_CTL_HALF_LP   (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_ROM_CTL_HALF_LP)
#define SFLASH_CPUSS_TRIM_RAM_CTL_HALF_LP   (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_RAM_CTL_HALF_LP)
#define SFLASH_CPUSS_TRIM_ROM_CTL_HALF_ULP  (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_ROM_CTL_HALF_ULP)
#define SFLASH_CPUSS_TRIM_RAM_CTL_HALF_ULP  (((SFLASH_Type *) SFLASH)->CPUSS_TRIM_RAM_CTL_HALF_ULP)


#define SFLASH_CSD0_ADC_VREF0_TRIM          (((SFLASH_Type *) SFLASH)->CSDV2_CSD0_ADC_VREF0)
#define SFLASH_CSD0_ADC_VREF1_TRIM          (((SFLASH_Type *) SFLASH)->CSDV2_CSD0_ADC_VREF1)
#define SFLASH_CSD0_ADC_VREF2_TRIM          (((SFLASH_Type *) SFLASH)->CSDV2_CSD0_ADC_VREF2)


/*******************************************************************************
*                CPUSS
*******************************************************************************/

#define CY_CPUSS_V1                         (0x20U > cy_device->cpussVersion)

#define CY_CPUSS_NOT_CONNECTED_IRQN         ((uint32_t)(cy_device->cpussNotConnectedIrq))
#define CY_CPUSS_DISCONNECTED_IRQN          ((cy_en_intr_t)CY_CPUSS_NOT_CONNECTED_IRQN)
#define CY_CPUSS_UNCONNECTED_IRQN           ((IRQn_Type)CY_CPUSS_NOT_CONNECTED_IRQN)

#define CPUSS_CM0_CLOCK_CTL                 (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm0ClockCtlOffset))
#define CPUSS_CM4_CLOCK_CTL                 (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm4ClockCtlOffset))
#define CPUSS_CM4_STATUS                    (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm4StatusOffset))
#define CPUSS_CM0_STATUS                    (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm0StatusOffset))
#define CPUSS_CM4_PWR_CTL                   (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm4PwrCtlOffset))
#define CPUSS_TRIM_RAM_CTL                  (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussTrimRamCtlOffset))
#define CPUSS_TRIM_ROM_CTL                  (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussTrimRomCtlOffset))
#define CPUSS_SYSTICK_CTL                   (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussSysTickCtlOffset))

#define CPUSS_ROM_CTL                       (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRomCtl))
#define CPUSS_RAM0_CTL0                     (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRam0Ctl0))
#define CPUSS_RAM1_CTL0                     (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRam1Ctl0))
#define CPUSS_RAM2_CTL0                     (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRam2Ctl0))
#define CPUSS_RAM0_PWR_CTL(macroIdx)        (((volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRam0PwrCtl))[(macroIdx)])
#define CPUSS_RAM1_PWR_CTL                  (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRam1PwrCtl))
#define CPUSS_RAM2_PWR_CTL                  (*(volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussRam2PwrCtl))

#define CPUSS_CM0_NMI_CTL(nmi)              (((volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm0NmiCtlOffset))[(nmi)])
#define CPUSS_CM4_NMI_CTL(nmi)              (((volatile uint32_t *) (cy_device->cpussBase + cy_device->cpussCm4NmiCtlOffset))[(nmi)])

/* used in V1 code only */
#define CPUSS_CM0_INT_CTL                   ((volatile uint32_t *) &(((CPUSS_Type *)(cy_device->cpussBase))->CM0_SYSTEM_INT_CTL))

/* used in V2 code only */
#define CPUSS_CM0_SYSTEM_INT_CTL            (((CPUSS_Type *)(cy_device->cpussBase))->CM0_SYSTEM_INT_CTL)
#define CPUSS_CM0_INT_STATUS                ((volatile const uint32_t *) &(((CPUSS_Type *)(cy_device->cpussBase))->CM0_INT0_STATUS))

#define CPUSS_SRAM_COUNT                    (1u + CPUSS_RAMC1_PRESENT + CPUSS_RAMC2_PRESENT)

/* ARM core registers */
#define SYSTICK_CTRL                        (((SysTick_Type *)SysTick)->CTRL)
#define SYSTICK_LOAD                        (((SysTick_Type *)SysTick)->LOAD)
#define SYSTICK_VAL                         (((SysTick_Type *)SysTick)->VAL)
#define SCB_SCR                             (((SCB_Type *)SCB)->SCR)

#define CPUSS_V2_RAM0_PWR_MACRO_CTL_PWR_MODE_Pos CPUSS_RAM0_PWR_MACRO_CTL_PWR_MODE_Pos
#define CPUSS_V2_RAM0_PWR_MACRO_CTL_PWR_MODE_Msk CPUSS_RAM0_PWR_MACRO_CTL_PWR_MODE_Msk
#define CPUSS_V2_RAM0_PWR_MACRO_CTL_VECTKEYSTAT_Pos CPUSS_RAM0_PWR_MACRO_CTL_VECTKEYSTAT_Pos
#define CPUSS_V2_RAM0_PWR_MACRO_CTL_VECTKEYSTAT_Msk CPUSS_RAM0_PWR_MACRO_CTL_VECTKEYSTAT_Msk
#define CPUSS_V2_RAM1_PWR_CTL_PWR_MODE_Pos CPUSS_RAM1_PWR_CTL_PWR_MODE_Pos
#define CPUSS_V2_RAM1_PWR_CTL_PWR_MODE_Msk CPUSS_RAM1_PWR_CTL_PWR_MODE_Msk
#define CPUSS_V2_RAM1_PWR_CTL_VECTKEYSTAT_Pos CPUSS_RAM1_PWR_CTL_VECTKEYSTAT_Pos
#define CPUSS_V2_RAM1_PWR_CTL_VECTKEYSTAT_Msk CPUSS_RAM1_PWR_CTL_VECTKEYSTAT_Msk
#define CPUSS_V2_RAM2_PWR_CTL_PWR_MODE_Pos CPUSS_RAM2_PWR_CTL_PWR_MODE_Pos
#define CPUSS_V2_RAM2_PWR_CTL_PWR_MODE_Msk CPUSS_RAM2_PWR_CTL_PWR_MODE_Msk
#define CPUSS_V2_RAM2_PWR_CTL_VECTKEYSTAT_Pos CPUSS_RAM2_PWR_CTL_VECTKEYSTAT_Pos
#define CPUSS_V2_RAM2_PWR_CTL_VECTKEYSTAT_Msk CPUSS_RAM2_PWR_CTL_VECTKEYSTAT_Msk
#define CPUSS_V2_CM0_SYSTEM_INT_CTL_CPU_INT_IDX_Pos CPUSS_CM0_SYSTEM_INT_CTL_CPU_INT_IDX_Pos
#define CPUSS_V2_CM0_SYSTEM_INT_CTL_CPU_INT_IDX_Msk CPUSS_CM0_SYSTEM_INT_CTL_CPU_INT_IDX_Msk
#define CPUSS_V2_CM0_SYSTEM_INT_CTL_CPU_INT_VALID_Pos CPUSS_CM0_SYSTEM_INT_CTL_CPU_INT_VALID_Pos
#define CPUSS_V2_CM0_SYSTEM_INT_CTL_CPU_INT_VALID_Msk CPUSS_CM0_SYSTEM_INT_CTL_CPU_INT_VALID_Msk
#define CPUSS_V2_CM4_SYSTEM_INT_CTL_CPU_INT_IDX_Pos CPUSS_CM4_SYSTEM_INT_CTL_CPU_INT_IDX_Pos
#define CPUSS_V2_CM4_SYSTEM_INT_CTL_CPU_INT_IDX_Msk CPUSS_CM4_SYSTEM_INT_CTL_CPU_INT_IDX_Msk
#define CPUSS_V2_CM4_SYSTEM_INT_CTL_CPU_INT_VALID_Pos CPUSS_CM4_SYSTEM_INT_CTL_CPU_INT_VALID_Pos
#define CPUSS_V2_CM4_SYSTEM_INT_CTL_CPU_INT_VALID_Msk CPUSS_CM4_SYSTEM_INT_CTL_CPU_INT_VALID_Msk
#define CPUSS_V2_CM0_INT0_STATUS_SYSTEM_INT_IDX_Pos CPUSS_CM0_INT0_STATUS_SYSTEM_INT_IDX_Pos
#define CPUSS_V2_CM0_INT0_STATUS_SYSTEM_INT_IDX_Msk CPUSS_CM0_INT0_STATUS_SYSTEM_INT_IDX_Msk
#define CPUSS_V2_CM0_INT0_STATUS_SYSTEM_INT_VALID_Pos CPUSS_CM0_INT0_STATUS_SYSTEM_INT_VALID_Pos
#define CPUSS_V2_CM0_INT0_STATUS_SYSTEM_INT_VALID_Msk CPUSS_CM0_INT0_STATUS_SYSTEM_INT_VALID_Msk

#define CPUSS_TRIM_ROM_CTL_RM_Pos               0UL
#define CPUSS_TRIM_ROM_CTL_RM_Msk               0xFUL
#define CPUSS_TRIM_ROM_CTL_RME_Pos              4UL
#define CPUSS_TRIM_ROM_CTL_RME_Msk              0x10UL
#define CPUSS_TRIM_RAM_CTL_RM_Pos               0UL
#define CPUSS_TRIM_RAM_CTL_RM_Msk               0xFUL
#define CPUSS_TRIM_RAM_CTL_RME_Pos              4UL
#define CPUSS_TRIM_RAM_CTL_RME_Msk              0x10UL
#define CPUSS_TRIM_RAM_CTL_WPULSE_Pos           5UL
#define CPUSS_TRIM_RAM_CTL_WPULSE_Msk           0xE0UL
#define CPUSS_TRIM_RAM_CTL_RA_Pos               8UL
#define CPUSS_TRIM_RAM_CTL_RA_Msk               0x300UL
#define CPUSS_TRIM_RAM_CTL_WA_Pos               12UL
#define CPUSS_TRIM_RAM_CTL_WA_Msk               0x7000UL

/*******************************************************************************
*                MCWDT
*******************************************************************************/

#define MCWDT_CNTLOW(base)      (((MCWDT_STRUCT_Type *)(base))->MCWDT_CNTLOW)
#define MCWDT_CNTHIGH(base)     (((MCWDT_STRUCT_Type *)(base))->MCWDT_CNTHIGH)
#define MCWDT_MATCH(base)       (((MCWDT_STRUCT_Type *)(base))->MCWDT_MATCH)
#define MCWDT_CONFIG(base)      (((MCWDT_STRUCT_Type *)(base))->MCWDT_CONFIG)
#define MCWDT_LOCK(base)        (((MCWDT_STRUCT_Type *)(base))->MCWDT_LOCK)
#define MCWDT_CTL(base)         (((MCWDT_STRUCT_Type *)(base))->MCWDT_CTL)
#define MCWDT_INTR(base)        (((MCWDT_STRUCT_Type *)(base))->MCWDT_INTR)
#define MCWDT_INTR_SET(base)    (((MCWDT_STRUCT_Type *)(base))->MCWDT_INTR_SET)
#define MCWDT_INTR_MASK(base)   (((MCWDT_STRUCT_Type *)(base))->MCWDT_INTR_MASK)
#define MCWDT_INTR_MASKED(base) (((MCWDT_STRUCT_Type *)(base))->MCWDT_INTR_MASKED)


/*******************************************************************************
*                TCPWM
*******************************************************************************/

#define TCPWM_CTRL_SET(base)                (((TCPWM_Type *)(base))->CTRL_SET)
#define TCPWM_CTRL_CLR(base)                (((TCPWM_Type *)(base))->CTRL_CLR)
#define TCPWM_CMD_START(base)               (((TCPWM_Type *)(base))->CMD_START)
#define TCPWM_CMD_RELOAD(base)              (((TCPWM_Type *)(base))->CMD_RELOAD)
#define TCPWM_CMD_STOP(base)                (((TCPWM_Type *)(base))->CMD_STOP)
#define TCPWM_CMD_CAPTURE(base)             (((TCPWM_Type *)(base))->CMD_CAPTURE)

#define TCPWM_CNT_CTRL(base, cntNum)         (((TCPWM_Type *)(base))->CNT[cntNum].CTRL)
#define TCPWM_CNT_CC(base, cntNum)           (((TCPWM_Type *)(base))->CNT[cntNum].CC)
#define TCPWM_CNT_CC_BUFF(base, cntNum)      (((TCPWM_Type *)(base))->CNT[cntNum].CC_BUFF)
#define TCPWM_CNT_COUNTER(base, cntNum)      (((TCPWM_Type *)(base))->CNT[cntNum].COUNTER)
#define TCPWM_CNT_PERIOD(base, cntNum)       (((TCPWM_Type *)(base))->CNT[cntNum].PERIOD)
#define TCPWM_CNT_PERIOD_BUFF(base, cntNum)  (((TCPWM_Type *)(base))->CNT[cntNum].PERIOD_BUFF)
#define TCPWM_CNT_STATUS(base, cntNum)       (((TCPWM_Type *)(base))->CNT[cntNum].STATUS)
#define TCPWM_CNT_INTR(base, cntNum)         (((TCPWM_Type *)(base))->CNT[cntNum].INTR)
#define TCPWM_CNT_INTR_SET(base, cntNum)     (((TCPWM_Type *)(base))->CNT[cntNum].INTR_SET)
#define TCPWM_CNT_INTR_MASK(base, cntNum)    (((TCPWM_Type *)(base))->CNT[cntNum].INTR_MASK)
#define TCPWM_CNT_INTR_MASKED(base, cntNum)  (((TCPWM_Type *)(base))->CNT[cntNum].INTR_MASKED)
#define TCPWM_CNT_TR_CTRL0(base, cntNum)     (((TCPWM_Type *)(base))->CNT[cntNum].TR_CTRL0)
#define TCPWM_CNT_TR_CTRL1(base, cntNum)     (((TCPWM_Type *)(base))->CNT[cntNum].TR_CTRL1)
#define TCPWM_CNT_TR_CTRL2(base, cntNum)     (((TCPWM_Type *)(base))->CNT[cntNum].TR_CTRL2)

/*******************************************************************************
*               TDM
*******************************************************************************/

#define TDM_STRUCT_Type                                TDM_TDM_STRUCT_Type
#define TDM_TX_STRUCT_Type                            TDM_TDM_STRUCT_TDM_TX_STRUCT_Type
#define TDM_RX_STRUCT_Type                            TDM_TDM_STRUCT_TDM_RX_STRUCT_Type
#define TDM_STRUCT0                                 TDM0_TDM_STRUCT0
#define TDM_STRUCT1                                 TDM0_TDM_STRUCT1
#define TDM_STRUCT0_TX                                TDM0_TDM_STRUCT0_TDM_TX_STRUCT
#define TDM_STRUCT1_TX                                TDM0_TDM_STRUCT1_TDM_TX_STRUCT
#define TDM_STRUCT0_RX                                TDM0_TDM_STRUCT0_TDM_RX_STRUCT
#define TDM_STRUCT1_RX                                TDM0_TDM_STRUCT1_TDM_RX_STRUCT
#define TDM_STRUCT_TX_CTL(base)                     (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_CTL)
#define TDM_STRUCT_TX_IF_CTL(base)                     (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_IF_CTL)
#define TDM_STRUCT_TX_CH_CTL(base)                     (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_CH_CTL)
#define TDM_STRUCT_TX_TEST_CTL(base)                 (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_TEST_CTL)
#define TDM_STRUCT_TX_ROUTE_CTL(base)                 (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_ROUTE_CTL)
#define TDM_STRUCT_TX_FIFO_CTL(base)                 (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_FIFO_CTL)
#define TDM_STRUCT_TX_FIFO_STATUS(base)             (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_FIFO_STATUS)
#define TDM_STRUCT_TX_FIFO_WR(base)                 (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->TX_FIFO_WR)
#define TDM_STRUCT_TX_INTR_TX(base)                 (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->INTR_TX)
#define TDM_STRUCT_TX_INTR_TX_SET(base)             (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->INTR_TX_SET)
#define TDM_STRUCT_TX_INTR_TX_MASK(base)             (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->INTR_TX_MASK)
#define TDM_STRUCT_TX_INTR_TX_MASKED(base)             (((TDM_TDM_STRUCT_TDM_TX_STRUCT_Type *)(base))->INTR_TX_MASKED)

#define TDM_STRUCT_RX_CTL(base)                     (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_CTL)
#define TDM_STRUCT_RX_IF_CTL(base)                     (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_IF_CTL)
#define TDM_STRUCT_RX_CH_CTL(base)                     (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_CH_CTL)
#define TDM_STRUCT_RX_TEST_CTL(base)                 (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_TEST_CTL)
#define TDM_STRUCT_RX_ROUTE_CTL(base)                 (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_ROUTE_CTL)
#define TDM_STRUCT_RX_FIFO_CTL(base)                 (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_FIFO_CTL)
#define TDM_STRUCT_RX_FIFO_STATUS(base)             (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_FIFO_STATUS)
#define TDM_STRUCT_RX_FIFO_RD(base)                 (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_FIFO_RD)
#define TDM_STRUCT_RX_FIFO_RD_SILENT(base)             (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->RX_FIFO_RD_SILENT)
#define TDM_STRUCT_RX_INTR_RX(base)                 (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->INTR_RX)
#define TDM_STRUCT_RX_INTR_RX_SET(base)             (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->INTR_RX_SET)
#define TDM_STRUCT_RX_INTR_RX_MASK(base)             (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->INTR_RX_MASK)
#define TDM_STRUCT_RX_INTR_RX_MASKED(base)             (((TDM_TDM_STRUCT_TDM_RX_STRUCT_Type *)(base))->INTR_RX_MASKED)

/*******************************************************************************
*                SMIF
*******************************************************************************/

#define SMIF_DEVICE_CTL(base)               (((SMIF_DEVICE_Type *)(base))->CTL)
#define SMIF_DEVICE_ADDR(base)              (((SMIF_DEVICE_Type *)(base))->ADDR)
#define SMIF_DEVICE_ADDR_CTL(base)          (((SMIF_DEVICE_Type *)(base))->ADDR_CTL)
#define SMIF_DEVICE_MASK(base)              (((SMIF_DEVICE_Type *)(base))->MASK)
#define SMIF_DEVICE_RD_CMD_CTL(base)        (((SMIF_DEVICE_Type *)(base))->RD_CMD_CTL)
#define SMIF_DEVICE_RD_ADDR_CTL(base)       (((SMIF_DEVICE_Type *)(base))->RD_ADDR_CTL)
#define SMIF_DEVICE_RD_MODE_CTL(base)       (((SMIF_DEVICE_Type *)(base))->RD_MODE_CTL)
#define SMIF_DEVICE_RD_DUMMY_CTL(base)      (((SMIF_DEVICE_Type *)(base))->RD_DUMMY_CTL)
#define SMIF_DEVICE_RD_DATA_CTL(base)       (((SMIF_DEVICE_Type *)(base))->RD_DATA_CTL)
#define SMIF_DEVICE_WR_CMD_CTL(base)        (((SMIF_DEVICE_Type *)(base))->WR_CMD_CTL)
#define SMIF_DEVICE_WR_ADDR_CTL(base)       (((SMIF_DEVICE_Type *)(base))->WR_ADDR_CTL)
#define SMIF_DEVICE_WR_MODE_CTL(base)       (((SMIF_DEVICE_Type *)(base))->WR_MODE_CTL)
#define SMIF_DEVICE_WR_DUMMY_CTL(base)      (((SMIF_DEVICE_Type *)(base))->WR_DUMMY_CTL)
#define SMIF_DEVICE_WR_DATA_CTL(base)       (((SMIF_DEVICE_Type *)(base))->WR_DATA_CTL)

#define SMIF_DEVICE_IDX(base, deviceIndex)                 (((SMIF_Type *)(base))->DEVICE[deviceIndex])

#define SMIF_DEVICE_IDX_CTL(base, deviceIndex)             (SMIF_DEVICE_IDX(base, deviceIndex).CTL)
#define SMIF_DEVICE_IDX_ADDR(base, deviceIndex)            (SMIF_DEVICE_IDX(base, deviceIndex).ADDR)
#define SMIF_DEVICE_IDX_ADDR_CTL(base, deviceIndex)        (SMIF_DEVICE_IDX(base, deviceIndex).ADDR_CTL)
#define SMIF_DEVICE_IDX_MASK(base, deviceIndex)            (SMIF_DEVICE_IDX(base, deviceIndex).MASK)
#define SMIF_DEVICE_IDX_RD_CMD_CTL(base, deviceIndex)      (SMIF_DEVICE_IDX(base, deviceIndex).RD_CMD_CTL)
#define SMIF_DEVICE_IDX_RD_ADDR_CTL(base, deviceIndex)     (SMIF_DEVICE_IDX(base, deviceIndex).RD_ADDR_CTL)
#define SMIF_DEVICE_IDX_RD_MODE_CTL(base, deviceIndex)     (SMIF_DEVICE_IDX(base, deviceIndex).RD_MODE_CTL)
#define SMIF_DEVICE_IDX_RD_DUMMY_CTL(base, deviceIndex)    (SMIF_DEVICE_IDX(base, deviceIndex).RD_DUMMY_CTL)
#define SMIF_DEVICE_IDX_RD_DATA_CTL(base, deviceIndex)     (SMIF_DEVICE_IDX(base, deviceIndex).RD_DATA_CTL)
#define SMIF_DEVICE_IDX_WR_CMD_CTL(base, deviceIndex)      (SMIF_DEVICE_IDX(base, deviceIndex).WR_CMD_CTL)
#define SMIF_DEVICE_IDX_WR_ADDR_CTL(base, deviceIndex)     (SMIF_DEVICE_IDX(base, deviceIndex).WR_ADDR_CTL)
#define SMIF_DEVICE_IDX_WR_MODE_CTL(base, deviceIndex)     (SMIF_DEVICE_IDX(base, deviceIndex).WR_MODE_CTL)
#define SMIF_DEVICE_IDX_WR_DUMMY_CTL(base, deviceIndex)    (SMIF_DEVICE_IDX(base, deviceIndex).WR_DUMMY_CTL)
#define SMIF_DEVICE_IDX_WR_DATA_CTL(base, deviceIndex)     (SMIF_DEVICE_IDX(base, deviceIndex).WR_DATA_CTL)

#define SMIF_CTL(base)                      (((SMIF_Type *)(base))->CTL)
#define SMIF_STATUS(base)                   (((SMIF_Type *)(base))->STATUS)
#define SMIF_TX_DATA_FIFO_CTL(base)         (((SMIF_Type *)(base))->TX_DATA_FIFO_CTL)
#define SMIF_RX_DATA_FIFO_CTL(base)         (((SMIF_Type *)(base))->RX_DATA_FIFO_CTL)
#define SMIF_TX_DATA_FIFO_WR1(base)         (((SMIF_Type *)(base))->TX_DATA_FIFO_WR1)
#define SMIF_TX_DATA_FIFO_WR2(base)         (((SMIF_Type *)(base))->TX_DATA_FIFO_WR2)
#define SMIF_TX_DATA_FIFO_WR4(base)         (((SMIF_Type *)(base))->TX_DATA_FIFO_WR4)
#define SMIF_RX_DATA_FIFO_RD1(base)         (((SMIF_Type *)(base))->RX_DATA_FIFO_RD1)
#define SMIF_RX_DATA_FIFO_RD2(base)         (((SMIF_Type *)(base))->RX_DATA_FIFO_RD2)
#define SMIF_RX_DATA_FIFO_RD4(base)         (((SMIF_Type *)(base))->RX_DATA_FIFO_RD4)
#define SMIF_TX_CMD_FIFO_WR(base)           (((SMIF_Type *)(base))->TX_CMD_FIFO_WR)
#define SMIF_TX_CMD_FIFO_STATUS(base)       (((SMIF_Type *)(base))->TX_CMD_FIFO_STATUS)
#define SMIF_RX_DATA_FIFO_STATUS(base)      (((SMIF_Type *)(base))->RX_DATA_FIFO_STATUS)
#define SMIF_TX_DATA_FIFO_STATUS(base)      (((SMIF_Type *)(base))->TX_DATA_FIFO_STATUS)
#define SMIF_INTR(base)                     (((SMIF_Type *)(base))->INTR)
#define SMIF_INTR_SET(base)                 (((SMIF_Type *)(base))->INTR_SET)
#define SMIF_INTR_MASK(base)                (((SMIF_Type *)(base))->INTR_MASK)
#define SMIF_INTR_MASKED(base)              (((SMIF_Type *)(base))->INTR_MASKED)
#define SMIF_CRYPTO_INPUT0(base)            (((SMIF_Type *)(base))->CRYPTO_INPUT0)
#define SMIF_CRYPTO_INPUT1(base)            (((SMIF_Type *)(base))->CRYPTO_INPUT1)
#define SMIF_CRYPTO_INPUT2(base)            (((SMIF_Type *)(base))->CRYPTO_INPUT2)
#define SMIF_CRYPTO_INPUT3(base)            (((SMIF_Type *)(base))->CRYPTO_INPUT3)
#define SMIF_CRYPTO_KEY0(base)              (((SMIF_Type *)(base))->CRYPTO_KEY0)
#define SMIF_CRYPTO_KEY1(base)              (((SMIF_Type *)(base))->CRYPTO_KEY1)
#define SMIF_CRYPTO_KEY2(base)              (((SMIF_Type *)(base))->CRYPTO_KEY2)
#define SMIF_CRYPTO_KEY3(base)              (((SMIF_Type *)(base))->CRYPTO_KEY3)
#define SMIF_CRYPTO_OUTPUT0(base)           (((SMIF_Type *)(base))->CRYPTO_OUTPUT0)
#define SMIF_CRYPTO_OUTPUT1(base)           (((SMIF_Type *)(base))->CRYPTO_OUTPUT1)
#define SMIF_CRYPTO_OUTPUT2(base)           (((SMIF_Type *)(base))->CRYPTO_OUTPUT2)
#define SMIF_CRYPTO_OUTPUT3(base)           (((SMIF_Type *)(base))->CRYPTO_OUTPUT3)
#define SMIF_CRYPTO_CMD(base)               (((SMIF_Type *)(base))->CRYPTO_CMD)
#define SMIF_SLOW_CA_CTL(base)              (((SMIF_Type *)(base))->SLOW_CA_CTL)
#define SMIF_FAST_CA_CTL(base)              (((SMIF_Type *)(base))->FAST_CA_CTL)
#define SMIF_SLOW_CA_CMD(base)              (((SMIF_Type *)(base))->SLOW_CA_CMD)
#define SMIF_FAST_CA_CMD(base)              (((SMIF_Type *)(base))->FAST_CA_CMD)


/*******************************************************************************
*                DW
*******************************************************************************/

#define CY_DW_V1                            (0x20U > cy_device->dwVersion)
#define CY_DW_CRC                           ((uint32_t)(0x20U <= cy_device->dwVersion))
#define CY_DW0_BASE                         ((DW_Type*) 0x40280000UL)
#define CY_DW0_CH_NR                        (cy_device->cpussDw0ChNr)
#define CY_DW1_CH_NR                        (cy_device->cpussDw1ChNr)

#define CY_DW_CH_CTL_PRIO_Pos               ((uint32_t)(cy_device->dwChCtlPrioPos))
#define CY_DW_CH_CTL_PRIO_Msk               ((uint32_t)(0x3UL << CY_DW_CH_CTL_PRIO_Pos))
#define CY_DW_CH_CTL_PREEMPTABLE_Pos        ((uint32_t)(cy_device->dwChCtlPreemptablePos))
#define CY_DW_CH_CTL_PREEMPTABLE_Msk        ((uint32_t)(0x1UL << CY_DW_CH_CTL_PREEMPTABLE_Pos))
#define CY_DW_STATUS_CH_IDX_Pos             ((uint32_t)(cy_device->dwStatusChIdxPos))
#define CY_DW_STATUS_CH_IDX_Msk             (cy_device->dwStatusChIdxMsk)

#define DW_CTL(base)                        (((DW_Type*)(base))->CTL)
#define DW_STATUS(base)                     (((DW_Type const*)(base))->STATUS)
#define DW_DESCR_SRC(base)                  (((DW_Type*)(base))->ACT_DESCR_SRC)
#define DW_DESCR_DST(base)                  (((DW_Type*)(base))->ACT_DESCR_DST)

#define DW_CRC_CTL(base)                    (((DW_Type*)(base))->CRC_CTL)
#define DW_CRC_DATA_CTL(base)               (((DW_Type*)(base))->CRC_DATA_CTL)
#define DW_CRC_REM_CTL(base)                (((DW_Type*)(base))->CRC_REM_CTL)
#define DW_CRC_POL_CTL(base)                (((DW_Type*)(base))->CRC_POL_CTL)
#define DW_CRC_LFSR_CTL(base)               (((DW_Type*)(base))->CRC_LFSR_CTL)

#define DW_CH(base, chan)                   ((DW_CH_STRUCT_Type*)((uint32_t)(base) + cy_device->dwChOffset + ((chan) * cy_device->dwChSize)))
#define DW_CH_CTL(base, chan)               (DW_CH(base, chan)->CH_CTL)
#define DW_CH_STATUS(base, chan)            (DW_CH(base, chan)->CH_STATUS)
#define DW_CH_IDX(base, chan)               (DW_CH(base, chan)->CH_IDX)
#define DW_CH_CURR_PTR(base, chan)          (DW_CH(base, chan)->CH_CURR_PTR)

#define DW_CH_INTR(base, chan)              (DW_CH(base, chan)->INTR)
#define DW_CH_INTR_SET(base, chan)          (DW_CH(base, chan)->INTR_SET)
#define DW_CH_INTR_MASK(base, chan)         (DW_CH(base, chan)->INTR_MASK)
#define DW_CH_INTR_MASKED(base, chan)       (DW_CH(base, chan)->INTR_MASKED)

#define DW_V2_CRC_CTL_DATA_REVERSE_Msk DW_CRC_CTL_DATA_REVERSE_Msk
#define DW_V2_CRC_CTL_REM_REVERSE_Msk DW_CRC_CTL_REM_REVERSE_Msk
#define DW_V2_CRC_DATA_CTL_DATA_XOR_Msk DW_CRC_DATA_CTL_DATA_XOR_Msk
#define DW_V2_CRC_REM_CTL_REM_XOR_Msk DW_CRC_REM_CTL_REM_XOR_Msk
#define DW_V2_CRC_POL_CTL_POLYNOMIAL_Msk DW_CRC_POL_CTL_POLYNOMIAL_Msk
#define DW_V2_CRC_LFSR_CTL_LFSR32_Msk DW_CRC_LFSR_CTL_LFSR32_Msk
#define DW_V2_CRC_CTL_DATA_REVERSE_Pos DW_CRC_CTL_DATA_REVERSE_Pos
#define DW_V2_CRC_CTL_REM_REVERSE_Pos DW_CRC_CTL_REM_REVERSE_Pos
#define DW_V2_CRC_DATA_CTL_DATA_XOR_Pos DW_CRC_DATA_CTL_DATA_XOR_Pos
#define DW_V2_CRC_REM_CTL_REM_XOR_Pos DW_CRC_REM_CTL_REM_XOR_Pos
#define DW_V2_CRC_POL_CTL_POLYNOMIAL_Pos DW_CRC_POL_CTL_POLYNOMIAL_Pos
#define DW_V2_CRC_LFSR_CTL_LFSR32_Pos DW_CRC_LFSR_CTL_LFSR32_Pos

/*******************************************************************************
*                DMAC
*******************************************************************************/

#define CY_DMAC_CH_NR                       CPUSS_DMAC_CH_NR
#define DMAC_CTL(base)                      (((DMAC_Type*)(base))->CTL)
#define DMAC_ACTIVE(base)                   (((DMAC_Type const*)(base))->ACTIVE)
#define DMAC_CH(base, chan)                 (&(((DMAC_Type*)(base))->CH[(chan)]))
#define DMAC_CH_CTL(base, chan)             (DMAC_CH(base, chan)->CTL)
#define DMAC_CH_IDX(base, chan)             (DMAC_CH(base, chan)->IDX)
#define DMAC_CH_CURR(base, chan)            (DMAC_CH(base, chan)->CURR)
#define DMAC_CH_DESCR_SRC(base, chan)       (DMAC_CH(base, chan)->DESCR_SRC)
#define DMAC_CH_DESCR_DST(base, chan)       (DMAC_CH(base, chan)->DESCR_DST)
#define DMAC_CH_INTR(base, chan)            (DMAC_CH(base, chan)->INTR)
#define DMAC_CH_INTR_SET(base, chan)        (DMAC_CH(base, chan)->INTR_SET)
#define DMAC_CH_INTR_MASK(base, chan)       (DMAC_CH(base, chan)->INTR_MASK)
#define DMAC_CH_INTR_MASKED(base, chan)     (DMAC_CH(base, chan)->INTR_MASKED)

#define DMAC_CH_V2_INTR_COMPLETION_Msk DMAC_CH_INTR_COMPLETION_Msk
#define DMAC_CH_V2_INTR_COMPLETION_Pos DMAC_CH_INTR_COMPLETION_Pos
#define DMAC_CH_V2_INTR_SRC_BUS_ERROR_Msk DMAC_CH_INTR_SRC_BUS_ERROR_Msk
#define DMAC_CH_V2_INTR_SRC_BUS_ERROR_Pos DMAC_CH_INTR_SRC_BUS_ERROR_Pos
#define DMAC_CH_V2_INTR_DST_BUS_ERROR_Msk DMAC_CH_INTR_DST_BUS_ERROR_Msk
#define DMAC_CH_V2_INTR_DST_BUS_ERROR_Pos DMAC_CH_INTR_DST_BUS_ERROR_Pos
#define DMAC_CH_V2_INTR_SRC_MISAL_Msk DMAC_CH_INTR_SRC_MISAL_Msk
#define DMAC_CH_V2_INTR_SRC_MISAL_Pos DMAC_CH_INTR_SRC_MISAL_Pos
#define DMAC_CH_V2_INTR_DST_MISAL_Msk DMAC_CH_INTR_DST_MISAL_Msk
#define DMAC_CH_V2_INTR_DST_MISAL_Pos DMAC_CH_INTR_DST_MISAL_Pos
#define DMAC_CH_V2_INTR_CURR_PTR_NULL_Msk DMAC_CH_INTR_CURR_PTR_NULL_Msk
#define DMAC_CH_V2_INTR_CURR_PTR_NULL_Pos DMAC_CH_INTR_CURR_PTR_NULL_Pos
#define DMAC_CH_V2_INTR_ACTIVE_CH_DISABLED_Msk DMAC_CH_INTR_ACTIVE_CH_DISABLED_Msk
#define DMAC_CH_V2_INTR_ACTIVE_CH_DISABLED_Pos DMAC_CH_INTR_ACTIVE_CH_DISABLED_Pos
#define DMAC_CH_V2_INTR_DESCR_BUS_ERROR_Msk DMAC_CH_INTR_DESCR_BUS_ERROR_Msk
#define DMAC_CH_V2_INTR_DESCR_BUS_ERROR_Pos DMAC_CH_INTR_DESCR_BUS_ERROR_Pos
#define DMAC_V2_CTL_ENABLED_Msk DMAC_CTL_ENABLED_Msk
#define DMAC_V2_CTL_ENABLED_Pos DMAC_CTL_ENABLED_Pos
#define DMAC_V2_ACTIVE_ACTIVE_Msk DMAC_ACTIVE_ACTIVE_Msk
#define DMAC_V2_ACTIVE_ACTIVE_Pos DMAC_ACTIVE_ACTIVE_Pos
#define DMAC_CH_V2_DESCR_CTL_INTR_TYPE_Msk DMAC_CH_DESCR_CTL_INTR_TYPE_Msk
#define DMAC_CH_V2_DESCR_CTL_INTR_TYPE_Pos DMAC_CH_DESCR_CTL_INTR_TYPE_Pos
#define DMAC_CH_V2_DESCR_CTL_TR_IN_TYPE_Msk DMAC_CH_DESCR_CTL_TR_IN_TYPE_Msk
#define DMAC_CH_V2_DESCR_CTL_TR_IN_TYPE_Pos DMAC_CH_DESCR_CTL_TR_IN_TYPE_Pos
#define DMAC_CH_V2_DESCR_CTL_TR_OUT_TYPE_Msk DMAC_CH_DESCR_CTL_TR_OUT_TYPE_Msk
#define DMAC_CH_V2_DESCR_CTL_TR_OUT_TYPE_Pos DMAC_CH_DESCR_CTL_TR_OUT_TYPE_Pos
#define DMAC_CH_V2_DESCR_CTL_DATA_SIZE_Msk DMAC_CH_DESCR_CTL_DATA_SIZE_Msk
#define DMAC_CH_V2_DESCR_CTL_DATA_SIZE_Pos DMAC_CH_DESCR_CTL_DATA_SIZE_Pos
#define DMAC_CH_V2_DESCR_CTL_SRC_TRANSFER_SIZE_Msk DMAC_CH_DESCR_CTL_SRC_TRANSFER_SIZE_Msk
#define DMAC_CH_V2_DESCR_CTL_SRC_TRANSFER_SIZE_Pos DMAC_CH_DESCR_CTL_SRC_TRANSFER_SIZE_Pos
#define DMAC_CH_V2_DESCR_CTL_DST_TRANSFER_SIZE_Msk DMAC_CH_DESCR_CTL_DST_TRANSFER_SIZE_Msk
#define DMAC_CH_V2_DESCR_CTL_DST_TRANSFER_SIZE_Pos DMAC_CH_DESCR_CTL_DST_TRANSFER_SIZE_Pos
#define DMAC_CH_V2_DESCR_CTL_WAIT_FOR_DEACT_Msk DMAC_CH_DESCR_CTL_WAIT_FOR_DEACT_Msk
#define DMAC_CH_V2_DESCR_CTL_WAIT_FOR_DEACT_Pos DMAC_CH_DESCR_CTL_WAIT_FOR_DEACT_Pos
#define DMAC_CH_V2_DESCR_CTL_DESCR_TYPE_Msk DMAC_CH_DESCR_CTL_DESCR_TYPE_Msk
#define DMAC_CH_V2_DESCR_CTL_DESCR_TYPE_Pos DMAC_CH_DESCR_CTL_DESCR_TYPE_Pos
#define DMAC_CH_V2_DESCR_CTL_CH_DISABLE_Msk DMAC_CH_DESCR_CTL_CH_DISABLE_Msk
#define DMAC_CH_V2_DESCR_CTL_CH_DISABLE_Pos DMAC_CH_DESCR_CTL_CH_DISABLE_Pos
#define DMAC_CH_V2_DESCR_X_INCR_SRC_X_Msk DMAC_CH_DESCR_X_INCR_SRC_X_Msk
#define DMAC_CH_V2_DESCR_X_INCR_SRC_X_Pos DMAC_CH_DESCR_X_INCR_SRC_X_Pos
#define DMAC_CH_V2_DESCR_X_INCR_DST_X_Msk DMAC_CH_DESCR_X_INCR_DST_X_Msk
#define DMAC_CH_V2_DESCR_X_INCR_DST_X_Pos DMAC_CH_DESCR_X_INCR_DST_X_Pos
#define DMAC_CH_V2_DESCR_Y_SIZE_Y_COUNT_Msk DMAC_CH_DESCR_Y_SIZE_Y_COUNT_Msk
#define DMAC_CH_V2_DESCR_Y_SIZE_Y_COUNT_Pos DMAC_CH_DESCR_Y_SIZE_Y_COUNT_Pos
#define DMAC_CH_V2_DESCR_Y_INCR_SRC_Y_Msk DMAC_CH_DESCR_Y_INCR_SRC_Y_Msk
#define DMAC_CH_V2_DESCR_Y_INCR_SRC_Y_Pos DMAC_CH_DESCR_Y_INCR_SRC_Y_Pos
#define DMAC_CH_V2_DESCR_Y_INCR_DST_Y_Msk DMAC_CH_DESCR_Y_INCR_DST_Y_Msk
#define DMAC_CH_V2_DESCR_Y_INCR_DST_Y_Pos DMAC_CH_DESCR_Y_INCR_DST_Y_Pos
#define DMAC_CH_V2_CTL_ENABLED_Msk DMAC_CH_CTL_ENABLED_Msk
#define DMAC_CH_V2_CTL_ENABLED_Pos DMAC_CH_CTL_ENABLED_Pos
#define DMAC_CH_V2_CTL_PRIO_Msk DMAC_CH_CTL_PRIO_Msk
#define DMAC_CH_V2_CTL_PRIO_Pos DMAC_CH_CTL_PRIO_Pos
#define DMAC_CH_V2_IDX_X_Msk DMAC_CH_IDX_X_Msk
#define DMAC_CH_V2_IDX_X_Pos DMAC_CH_IDX_X_Pos
#define DMAC_CH_V2_IDX_Y_Msk DMAC_CH_IDX_Y_Msk
#define DMAC_CH_V2_IDX_Y_Pos DMAC_CH_IDX_Y_Pos
#define DMAC_CH_V2_DESCR_CTL_DATA_PREFETCH_Msk DMAC_CH_DESCR_CTL_DATA_PREFETCH_Msk
#define DMAC_CH_V2_DESCR_CTL_DATA_PREFETCH_Pos DMAC_CH_DESCR_CTL_DATA_PREFETCH_Pos
#define DMAC_CH_V2_CTL_B_Msk DMAC_CH_CTL_B_Msk
#define DMAC_CH_V2_CTL_B_Pos DMAC_CH_CTL_B_Pos
#define DMAC_CH_V2_DESCR_X_SIZE_X_COUNT_Msk DMAC_CH_DESCR_X_SIZE_X_COUNT_Msk
#define DMAC_CH_V2_DESCR_X_SIZE_X_COUNT_Pos DMAC_CH_DESCR_X_SIZE_X_COUNT_Pos

/*******************************************************************************
*                PERI
*******************************************************************************/
#define CY_PERI_BASE                        ((PERI_Type *) cy_device->periBase)

#define CY_PERI_V1                          ((uint32_t)(0x20U > cy_device->periVersion)) /* true if the mxperi version is 1.x */
#define CY_PERI_V2_TR_GR_SIZE               (sizeof(PERI_TR_GR_Type))
#define CY_PERI_TR_CTL_NUM                  ((uint32_t)cy_device->periTrGrSize / sizeof(uint32_t))
#define CY_PERI_TR_CTL_SEL_Pos              (0UL)
#define CY_PERI_TR_CTL_SEL_Msk              ((uint32_t)CY_PERI_TR_CTL_NUM - 1UL)
#define CY_PERI_TR_CMD_GROUP_SEL_Pos        (PERI_TR_CMD_GROUP_SEL_Pos)
#define CY_PERI_TR_CMD_GROUP_SEL_Msk        ((uint32_t)cy_device->periTrCmdGrSelMsk)

#define PERI_TR_CMD                         (*(volatile uint32_t*)((uint32_t)cy_device->periBase + \
                                                                   (uint32_t)cy_device->periTrCmdOffset))
#define PERI_TR_GR_TR_CTL(group, trCtl)     (*(volatile uint32_t*)((uint32_t)cy_device->periBase + \
                                                                   (uint32_t)cy_device->periTrGrOffset + \
                                                        ((group) * (uint32_t)cy_device->periTrGrSize) + \
                                                        ((trCtl) * (uint32_t)sizeof(uint32_t))))

#define PERI_TR_GR_TR_OUT_CTL_TR_SEL_Msk PERI_TR_GR_TR_CTL_TR_SEL_Msk
#define PERI_TR_GR_TR_OUT_CTL_TR_SEL_Pos PERI_TR_GR_TR_CTL_TR_SEL_Pos
#define PERI_V2_TR_CMD_OUT_SEL_Msk PERI_TR_CMD_OUT_SEL_Msk
#define PERI_V2_TR_CMD_OUT_SEL_Pos PERI_TR_CMD_OUT_SEL_Pos
#define PERI_V2_TR_CMD_GROUP_SEL_Msk PERI_TR_CMD_GROUP_SEL_Msk
#define PERI_V2_TR_CMD_GROUP_SEL_Pos PERI_TR_CMD_GROUP_SEL_Pos
#define CY_PERI_TR_CTL_SEL PERI_TR_GR_TR_CTL_TR_SEL
#define PERI_TR_GR_TR_OUT_CTL_TR_INV_Msk PERI_TR_GR_TR_CTL_TR_INV_Msk
#define PERI_TR_GR_TR_OUT_CTL_TR_INV_Pos PERI_TR_GR_TR_CTL_TR_INV_Pos
#define PERI_TR_GR_TR_OUT_CTL_TR_EDGE_Msk PERI_TR_GR_TR_CTL_TR_EDGE_Msk
#define PERI_TR_GR_TR_OUT_CTL_TR_EDGE_Pos PERI_TR_GR_TR_CTL_TR_EDGE_Pos
#define PERI_V2_TR_CMD_TR_EDGE_Msk PERI_TR_CMD_TR_EDGE_Msk
#define PERI_V2_TR_CMD_TR_EDGE_Pos PERI_TR_CMD_TR_EDGE_Pos
#define PERI_TR_1TO1_GR_V2_TR_CTL_TR_INV_Msk PERI_TR_1TO1_GR_TR_CTL_TR_INV_Msk
#define PERI_TR_1TO1_GR_V2_TR_CTL_TR_INV_Pos PERI_TR_1TO1_GR_TR_CTL_TR_INV_Pos
#define PERI_TR_1TO1_GR_V2_TR_CTL_TR_EDGE_Msk PERI_TR_1TO1_GR_TR_CTL_TR_EDGE_Msk
#define PERI_TR_1TO1_GR_V2_TR_CTL_TR_EDGE_Pos PERI_TR_1TO1_GR_TR_CTL_TR_EDGE_Pos
#define PERI_TR_1TO1_GR_V2_TR_CTL_TR_SEL_Msk PERI_TR_1TO1_GR_TR_CTL_TR_SEL_Msk
#define PERI_TR_1TO1_GR_V2_TR_CTL_TR_SEL_Pos PERI_TR_1TO1_GR_TR_CTL_TR_SEL_Pos
#define PERI_TR_GR_V2_TR_CTL_DBG_FREEZE_EN_Msk PERI_TR_GR_TR_CTL_DBG_FREEZE_EN_Msk
#define PERI_TR_GR_V2_TR_CTL_DBG_FREEZE_EN_Pos PERI_TR_GR_TR_CTL_DBG_FREEZE_EN_Pos
#define CY_IP_MXSPERI 1U
#define PERI_TR_CMD_COUNT_Pos 0UL /* used for proper condition in cy_trigmux.c for FX3G2 */
#define PERI_TR_CMD_COUNT_Msk 0UL /* used for proper condition in cy_trigmux.c for FX3G2 */

#define CY_PERI_CLOCK_NR                    ((uint32_t)(cy_device->periClockNr))

#define PERI_DIV_CMD                        ((CY_PERI_BASE)->DIV_CMD)

#define CY_PERI_DIV_CMD_DIV_SEL_Pos         (PERI_DIV_CMD_DIV_SEL_Pos)
#define CY_PERI_DIV_CMD_DIV_SEL_Msk         ((uint32_t)(cy_device->periDivCmdDivSelMsk))
#define CY_PERI_DIV_CMD_TYPE_SEL_Pos        ((uint32_t)(cy_device->periDivCmdTypeSelPos))
#define CY_PERI_DIV_CMD_TYPE_SEL_Msk        ((uint32_t)(0x3UL << CY_PERI_DIV_CMD_TYPE_SEL_Pos))
#define CY_PERI_DIV_CMD_PA_DIV_SEL_Pos      ((uint32_t)(cy_device->periDivCmdPaDivSelPos))
#define CY_PERI_DIV_CMD_PA_DIV_SEL_Msk      ((uint32_t)(CY_PERI_DIV_CMD_DIV_SEL_Msk << CY_PERI_DIV_CMD_PA_DIV_SEL_Pos))
#define CY_PERI_DIV_CMD_PA_TYPE_SEL_Pos     ((uint32_t)(cy_device->periDivCmdPaTypeSelPos))
#define CY_PERI_DIV_CMD_PA_TYPE_SEL_Msk     ((uint32_t)(0x3UL << CY_PERI_DIV_CMD_PA_TYPE_SEL_Pos))

#define PERI_CLOCK_CTL                      ((CY_PERI_BASE)->CLOCK_CTL)

#define CY_PERI_CLOCK_CTL_DIV_SEL_Pos       (PERI_CLOCK_CTL_DIV_SEL_Pos)
#define CY_PERI_CLOCK_CTL_DIV_SEL_Msk       (CY_PERI_DIV_CMD_DIV_SEL_Msk)
#define CY_PERI_CLOCK_CTL_TYPE_SEL_Pos      (CY_PERI_DIV_CMD_TYPE_SEL_Pos)
#define CY_PERI_CLOCK_CTL_TYPE_SEL_Msk      (CY_PERI_DIV_CMD_TYPE_SEL_Msk)

#define PERI_DIV_8_CTL                      ((volatile uint32_t *)((uint32_t)(cy_device->periBase) + (uint32_t)(cy_device->periDiv8CtlOffset)))
#define PERI_DIV_16_CTL                     ((volatile uint32_t *)((uint32_t)(cy_device->periBase) + (uint32_t)(cy_device->periDiv16CtlOffset)))
#define PERI_DIV_16_5_CTL                   ((volatile uint32_t *)((uint32_t)(cy_device->periBase) + (uint32_t)(cy_device->periDiv16_5CtlOffset)))
#define PERI_DIV_24_5_CTL                   ((volatile uint32_t *)((uint32_t)(cy_device->periBase) + (uint32_t)(cy_device->periDiv24_5CtlOffset)))

/**
  * \brief PPU structure with fixed/constant address for a peripheral group (PERI_PPU_GR)
  */
typedef struct {
   __IM uint32_t ADDR0;                         /*!< 0x00000000 PPU region address 0 (slave structure) */
  __IOM uint32_t ATT0;                          /*!< 0x00000004 PPU region attributes 0 (slave structure) */
   __IM uint32_t RESERVED[6];
   __IM uint32_t ADDR1;                         /*!< 0x00000020 PPU region address 1 (master structure) */
  __IOM uint32_t ATT1;                          /*!< 0x00000024 PPU region attributes 1 (master structure) */
   __IM uint32_t RESERVED1[6];
} PERI_PPU_PR_V1_Type;                          /*!< Size = 64 (0x40) */

typedef PERI_PPU_PR_V1_Type PERI_PPU_GR_V1_Type;
typedef PERI_PPU_PR_V1_Type PERI_GR_PPU_SL_V1_Type;
typedef PERI_PPU_PR_V1_Type PERI_GR_PPU_RG_V1_Type;

/*******************************************************************************
*                PROT
*******************************************************************************/
#define CY_PROT_BASE                        (cy_device->protBase)

#define CY_PROT_PC_MAX                      (8UL)
#define CY_PROT_BUS_MASTER_MASK             (cy_device->protBusMasterMask)
#define PROT_MPU_MS_CTL(mpu)                (((PROT_Type*)CY_PROT_BASE)->CYMPU[(mpu)].MS_CTL)
#define PROT_MPU_MPU_STRUCT_ADDR(base)      (((PROT_MPU_MPU_STRUCT_Type *) (base))->ADDR)
#define PROT_MPU_MPU_STRUCT_ATT(base)       (((PROT_MPU_MPU_STRUCT_Type *) (base))->ATT)

#define PROT_SMPU_SMPU_STRUCT_ADDR0(base)   (((PROT_SMPU_SMPU_STRUCT_Type *) (base))->ADDR0)
#define PROT_SMPU_SMPU_STRUCT_ADDR1(base)   (((PROT_SMPU_SMPU_STRUCT_Type *) (base))->ADDR1)
#define PROT_SMPU_SMPU_STRUCT_ATT0(base)    (((PROT_SMPU_SMPU_STRUCT_Type *) (base))->ATT0)
#define PROT_SMPU_SMPU_STRUCT_ATT1(base)    (((PROT_SMPU_SMPU_STRUCT_Type *) (base))->ATT1)

#define PROT_SMPU_SMPU_STRUCT_IDX_ATT0(stcIdx)    (((PROT_SMPU_Type *) CY_PROT_BASE)->SMPU_STRUCT[(stcIdx)].ATT0)
#define PROT_SMPU_SMPU_STRUCT_IDX_ATT1(stcIdx)    (((PROT_SMPU_Type *) CY_PROT_BASE)->SMPU_STRUCT[(stcIdx)].ATT1)
#define PROT_SMPU_SMPU_STRUCT_IDX(stcIdx)         (((PROT_SMPU_SMPU_STRUCT_Type *) &((PROT_SMPU_Type *) CY_PROT_BASE)->SMPU_STRUCT[(stcIdx)]))


/*******************************************************************************
*                IOSS
*******************************************************************************/

#define CY_GPIO_BASE                       ((uint32_t)(cy_device->gpioBase))

#define GPIO_INTR_CAUSE0                   (((GPIO_Type*)(cy_device->gpioBase))->INTR_CAUSE0)
#define GPIO_INTR_CAUSE1                   (((GPIO_Type*)(cy_device->gpioBase))->INTR_CAUSE1)
#define GPIO_INTR_CAUSE2                   (((GPIO_Type*)(cy_device->gpioBase))->INTR_CAUSE2)
#define GPIO_INTR_CAUSE3                   (((GPIO_Type*)(cy_device->gpioBase))->INTR_CAUSE3)

#define GPIO_PRT_OUT(base)                 (((GPIO_PRT_Type*)(base))->OUT)
#define GPIO_PRT_OUT_CLR(base)             (((GPIO_PRT_Type*)(base))->OUT_CLR)
#define GPIO_PRT_OUT_SET(base)             (((GPIO_PRT_Type*)(base))->OUT_SET)
#define GPIO_PRT_OUT_INV(base)             (((GPIO_PRT_Type*)(base))->OUT_INV)
#define GPIO_PRT_IN(base)                  (((GPIO_PRT_Type*)(base))->IN)
#define GPIO_PRT_INTR(base)                (((GPIO_PRT_Type*)(base))->INTR)
#define GPIO_PRT_INTR_MASK(base)           (((GPIO_PRT_Type*)(base))->INTR_MASK)
#define GPIO_PRT_INTR_MASKED(base)         (((GPIO_PRT_Type*)(base))->INTR_MASKED)
#define GPIO_PRT_INTR_SET(base)            (((GPIO_PRT_Type*)(base))->INTR_SET)

#define GPIO_PRT_INTR_CFG(base)            (*(volatile uint32_t *)((uint32_t)(base) + (uint32_t)(cy_device->gpioPrtIntrCfgOffset)))
#define GPIO_PRT_CFG(base)                 (*(volatile uint32_t *)((uint32_t)(base) + (uint32_t)(cy_device->gpioPrtCfgOffset)))
#define GPIO_PRT_CFG_IN(base)              (*(volatile uint32_t *)((uint32_t)(base) + (uint32_t)(cy_device->gpioPrtCfgInOffset)))
#define GPIO_PRT_CFG_OUT(base)             (*(volatile uint32_t *)((uint32_t)(base) + (uint32_t)(cy_device->gpioPrtCfgOutOffset)))
#define GPIO_PRT_CFG_SIO(base)             (*(volatile uint32_t *)((uint32_t)(base) + (uint32_t)(cy_device->gpioPrtCfgSioOffset)))
#define GPIO_PRT_CFG_IN_AUTOLVL(base)      (((GPIO_PRT_Type*)(base))->CFG_IN_AUTOLVL)

#define CY_HSIOM_BASE                      ((uint32_t)(cy_device->hsiomBase))

#define HSIOM_PRT_PORT_SEL0(base)          (((HSIOM_PRT_Type *)(base))->PORT_SEL0)
#define HSIOM_PRT_PORT_SEL1(base)          (((HSIOM_PRT_Type *)(base))->PORT_SEL1)

#define HSIOM_AMUX_SPLIT_CTL(switchCtrl)    (((HSIOM_Type *) CY_HSIOM_BASE)->AMUX_SPLIT_CTL[switchCtrl])


/*******************************************************************************
*                PDM
*******************************************************************************/

#define PDM_PCM_CTL(base)                               (((PDM_Type*)(base))->CTL)
#define PDM_PCM_CTL_CLR(base)                           (((PDM_Type*)(base))->CTL_CLR)
#define PDM_PCM_CTL_SET(base)                           (((PDM_Type*)(base))->CTL_SET)
#define PDM_PCM_CLOCK_CTL(base)                           (((PDM_Type*)(base))->CLOCK_CTL)
#define PDM_PCM_ROUTE_CTL(base)                           (((PDM_Type*)(base))->ROUTE_CTL)
#define PDM_PCM_TEST_CTL(base)                           (((PDM_Type*)(base))->TEST_CTL)
#define PDM_PCM_FIR0_COEFF0(base)                       (((PDM_Type*)(base))->FIR0_COEFF0)
#define PDM_PCM_FIR0_COEFF1(base)                       (((PDM_Type*)(base))->FIR0_COEFF1)
#define PDM_PCM_FIR0_COEFF2(base)                       (((PDM_Type*)(base))->FIR0_COEFF2)
#define PDM_PCM_FIR0_COEFF3(base)                       (((PDM_Type*)(base))->FIR0_COEFF3)
#define PDM_PCM_FIR0_COEFF4(base)                       (((PDM_Type*)(base))->FIR0_COEFF4)
#define PDM_PCM_FIR0_COEFF5(base)                       (((PDM_Type*)(base))->FIR0_COEFF5)
#define PDM_PCM_FIR0_COEFF6(base)                       (((PDM_Type*)(base))->FIR0_COEFF6)
#define PDM_PCM_FIR0_COEFF7(base)                       (((PDM_Type*)(base))->FIR0_COEFF7)

#define PDM_PCM_FIR1_COEFF0(base)                       (((PDM_Type*)(base))->FIR1_COEFF0)
#define PDM_PCM_FIR1_COEFF1(base)                       (((PDM_Type*)(base))->FIR1_COEFF1)
#define PDM_PCM_FIR1_COEFF2(base)                       (((PDM_Type*)(base))->FIR1_COEFF2)
#define PDM_PCM_FIR1_COEFF3(base)                       (((PDM_Type*)(base))->FIR1_COEFF3)
#define PDM_PCM_FIR1_COEFF4(base)                       (((PDM_Type*)(base))->FIR1_COEFF4)
#define PDM_PCM_FIR1_COEFF5(base)                       (((PDM_Type*)(base))->FIR1_COEFF5)
#define PDM_PCM_FIR1_COEFF6(base)                       (((PDM_Type*)(base))->FIR1_COEFF6)
#define PDM_PCM_FIR1_COEFF7(base)                       (((PDM_Type*)(base))->FIR1_COEFF7)
#define PDM_PCM_FIR1_COEFF8(base)                       (((PDM_Type*)(base))->FIR1_COEFF8)
#define PDM_PCM_FIR1_COEFF9(base)                       (((PDM_Type*)(base))->FIR1_COEFF9)
#define PDM_PCM_FIR1_COEFF10(base)                       (((PDM_Type*)(base))->FIR1_COEFF10)
#define PDM_PCM_FIR1_COEFF11(base)                       (((PDM_Type*)(base))->FIR1_COEFF11)
#define PDM_PCM_FIR1_COEFF12(base)                       (((PDM_Type*)(base))->FIR1_COEFF12)
#define PDM_PCM_FIR1_COEFF13(base)                       (((PDM_Type*)(base))->FIR1_COEFF13)


#define PDM_PCM_CH_CTL(base, chnum)                   (((PDM_Type*)(base))->CH[chnum].CTL)
#define PDM_PCM_CH_IF_CTL(base, chnum)                   (((PDM_Type*)(base))->CH[chnum].IF_CTL)
#define PDM_PCM_CH_CIC_CTL(base, chnum)               (((PDM_Type*)(base))->CH[chnum].CIC_CTL)
#define PDM_PCM_CH_FIR0_CTL(base, chnum)              (((PDM_Type*)(base))->CH[chnum].FIR0_CTL)
#define PDM_PCM_CH_FIR1_CTL(base, chnum)              (((PDM_Type*)(base))->CH[chnum].FIR1_CTL)
#define PDM_PCM_CH_DC_BLOCK_CTL(base, chnum)          (((PDM_Type*)(base))->CH[chnum].DC_BLOCK_CTL)
#define PDM_PCM_INTR_RX_MASK(base, chnum)             (((PDM_Type*)(base))->CH[chnum].INTR_RX_MASK)
#define PDM_PCM_INTR_RX_MASKED(base, chnum)           (((PDM_Type*)(base))->CH[chnum].INTR_RX_MASKED)
#define PDM_PCM_INTR_RX(base, chnum)                  (((PDM_Type*)(base))->CH[chnum].INTR_RX)
#define PDM_PCM_INTR_RX_SET(base, chnum)              (((PDM_Type*)(base))->CH[chnum].INTR_RX_SET)
#define PDM_PCM_RX_FIFO_STATUS(base, chnum)              (((PDM_Type*)(base))->CH[chnum].RX_FIFO_STATUS)
#define PDM_PCM_RX_FIFO_CTL(base, chnum)                 (((PDM_Type*)(base))->CH[chnum].RX_FIFO_CTL)
#define PDM_PCM_RX_FIFO_RD(base, chnum)                  (((PDM_Type*)(base))->CH[chnum].RX_FIFO_RD)
#define PDM_PCM_RX_FIFO_RD_SILENT(base, chnum)           (((PDM_Type*)(base))->CH[chnum].RX_FIFO_RD_SILENT)


/*******************************************************************************
*                IPC
*******************************************************************************/

#define CY_IPC_V1                              (0x20u > cy_device->ipcVersion) /* true if the IPC version is 1.x */

#define REG_IPC_STRUCT_ACQUIRE(base)           (((IPC_STRUCT_Type*)(base))->ACQUIRE)
#define REG_IPC_STRUCT_RELEASE(base)           (((IPC_STRUCT_Type*)(base))->RELEASE)
#define REG_IPC_STRUCT_NOTIFY(base)            (((IPC_STRUCT_Type*)(base))->NOTIFY)
#define REG_IPC_STRUCT_DATA(base)              (((IPC_STRUCT_Type*)(base))->DATA0)
#define REG_IPC_STRUCT_DATA1(base)             (((IPC_STRUCT_Type*)(base))->DATA1)
#define REG_IPC_STRUCT_LOCK_STATUS(base)       (*(volatile uint32_t*)((uint32_t)(base) + cy_device->ipcLockStatusOffset))

#define REG_IPC_INTR_STRUCT_INTR(base)         (((IPC_INTR_STRUCT_Type*)(base))->INTR)
#define REG_IPC_INTR_STRUCT_INTR_SET(base)     (((IPC_INTR_STRUCT_Type*)(base))->INTR_SET)
#define REG_IPC_INTR_STRUCT_INTR_MASK(base)    (((IPC_INTR_STRUCT_Type*)(base))->INTR_MASK)
#define REG_IPC_INTR_STRUCT_INTR_MASKED(base)  (((IPC_INTR_STRUCT_Type*)(base))->INTR_MASKED)

#define CY_IPC_STRUCT_PTR(ipcIndex)            ((IPC_STRUCT_Type*)(cy_device->ipcBase + (cy_device->ipcStructSize * (ipcIndex))))
#define CY_IPC_INTR_STRUCT_PTR(ipcIntrIndex)   &(((IPC_Type *)cy_device->ipcBase)->INTR_STRUCT[ipcIntrIndex])
#define CY_IPC_STRUCT_PTR_FOR_IP(ipcIndex, base)            ((IPC_STRUCT_Type*)((uint32_t)(base) + (sizeof(IPC_STRUCT_Type) * (ipcIndex))))
#define CY_IPC_INTR_STRUCT_PTR_FOR_IP(ipcIntrIndex, base)   (&(((IPC_Type *)base)->INTR_STRUCT[ipcIntrIndex]))

#define CY_IPC_INSTANCES                       (1U)
#define CY_IPC_CHANNELS                        ((uint32_t)(cy_device->cpussIpcNr))
#define CY_IPC_INTERRUPTS                      ((uint32_t)(cy_device->cpussIpcIrqNr))
#define CY_IPC_CHANNELS_PER_INSTANCE           CY_IPC_CHANNELS
#define CY_IPC_INTERRUPTS_PER_INSTANCE         CY_IPC_INTERRUPTS

/* ipcChannel comprises of total number of channels present in all IPC IP instances */
#define CY_IPC_PIPE_CHANNEL_NUMBER_WITHIN_INSTANCE(ipcChannel) (((ipcChannel)%CY_IPC_CHANNELS_PER_INSTANCE))
#define CY_IPC_PIPE_INTR_NUMBER_WITHIN_INSTANCE(ipcIntr)       (((ipcIntr)%CY_IPC_INTERRUPTS_PER_INSTANCE))

/* IPC channel definitions  */
#define CY_IPC_CHAN_SYSCALL_CM0             (0U)  /* System calls for the CM0 processor */
#define CY_IPC_CHAN_SYSCALL_CM4             (1U)  /* System calls for the 1st non-CM0 processor */
#define CY_IPC_CHAN_SYSCALL_DAP             (2UL) /* System calls for the DAP */
#define CY_IPC_CHAN_SEMA                    (3UL) /* IPC data channel for the Semaphores */
#define CY_IPC_CHAN_PRA                     (4UL) /* IPC data channel for PRA */
#define CY_IPC_CHAN_CYPIPE_EP0              (5UL) /* IPC data channel for CYPIPE EP0 */
#define CY_IPC_CHAN_CYPIPE_EP1              (6UL) /* IPC data channel for CYPIPE EP1 */
#define CY_IPC_CHAN_DDFT                    (7UL) /* IPC data channel for DDFT */

/* IPC Notify interrupts definitions */
#define CY_IPC_INTR_SYSCALL1                (0UL)
#define CY_IPC_INTR_CYPIPE_EP0              (3UL)
#define CY_IPC_INTR_CYPIPE_EP1              (4UL)
#define CY_IPC_INTR_PRA                     (5UL)
#define CY_IPC_INTR_SPARE                   (7UL)

/* Endpoint indexes in the pipe array */
#define CY_IPC_EP_CYPIPE_CM0_ADDR           (0UL)
#define CY_IPC_EP_CYPIPE_CM4_ADDR           (1UL)


/*******************************************************************************
*                SCB
*******************************************************************************/

#define SCB_CTRL(base)                      (((CySCB_Type*) (base))->CTRL)
#define SCB_SPI_CTRL(base)                  (((CySCB_Type*) (base))->SPI_CTRL)
#define SCB_SPI_STATUS(base)                (((CySCB_Type*) (base))->SPI_STATUS)
#define SCB_UART_CTRL(base)                 (((CySCB_Type*) (base))->UART_CTRL)
#define SCB_UART_TX_CTRL(base)              (((CySCB_Type*) (base))->UART_TX_CTRL)
#define SCB_UART_RX_CTRL(base)              (((CySCB_Type*) (base))->UART_RX_CTRL)
#define SCB_UART_FLOW_CTRL(base)            (((CySCB_Type*) (base))->UART_FLOW_CTRL)
#define SCB_I2C_CTRL(base)                  (((CySCB_Type*) (base))->I2C_CTRL)
#define SCB_I2C_STATUS(base)                (((CySCB_Type*) (base))->I2C_STATUS)
#define SCB_I2C_M_CMD(base)                 (((CySCB_Type*) (base))->I2C_M_CMD)
#define SCB_I2C_S_CMD(base)                 (((CySCB_Type*) (base))->I2C_S_CMD)
#define SCB_I2C_CFG(base)                   (((CySCB_Type*) (base))->I2C_CFG)
#define SCB_TX_CTRL(base)                   (((CySCB_Type*) (base))->TX_CTRL)
#define SCB_TX_FIFO_CTRL(base)              (((CySCB_Type*) (base))->TX_FIFO_CTRL)
#define SCB_TX_FIFO_STATUS(base)            (((CySCB_Type*) (base))->TX_FIFO_STATUS)
#define SCB_TX_FIFO_WR(base)                (((CySCB_Type*) (base))->TX_FIFO_WR)
#define SCB_RX_CTRL(base)                   (((CySCB_Type*) (base))->RX_CTRL)
#define SCB_RX_FIFO_CTRL(base)              (((CySCB_Type*) (base))->RX_FIFO_CTRL)
#define SCB_RX_FIFO_STATUS(base)            (((CySCB_Type*) (base))->RX_FIFO_STATUS)
#define SCB_RX_MATCH(base)                  (((CySCB_Type*) (base))->RX_MATCH)
#define SCB_RX_FIFO_RD(base)                (((CySCB_Type*) (base))->RX_FIFO_RD)
#define SCB_INTR_CAUSE(base)                (((CySCB_Type*) (base))->INTR_CAUSE)
#define SCB_INTR_I2C_EC(base)               (((CySCB_Type*) (base))->INTR_I2C_EC)
#define SCB_INTR_I2C_EC_MASK(base)          (((CySCB_Type*) (base))->INTR_I2C_EC_MASK)
#define SCB_INTR_I2C_EC_MASKED(base)        (((CySCB_Type*) (base))->INTR_I2C_EC_MASKED)
#define SCB_INTR_SPI_EC(base)               (((CySCB_Type*) (base))->INTR_SPI_EC)
#define SCB_INTR_SPI_EC_MASK(base)          (((CySCB_Type*) (base))->INTR_SPI_EC_MASK)
#define SCB_INTR_SPI_EC_MASKED(base)        (((CySCB_Type*) (base))->INTR_SPI_EC_MASKED)
#define SCB_INTR_M(base)                    (((CySCB_Type*) (base))->INTR_M)
#define SCB_INTR_M_SET(base)                (((CySCB_Type*) (base))->INTR_M_SET)
#define SCB_INTR_M_MASK(base)               (((CySCB_Type*) (base))->INTR_M_MASK)
#define SCB_INTR_M_MASKED(base)             (((CySCB_Type*) (base))->INTR_M_MASKED)
#define SCB_INTR_S(base)                    (((CySCB_Type*) (base))->INTR_S)
#define SCB_INTR_S_SET(base)                (((CySCB_Type*) (base))->INTR_S_SET)
#define SCB_INTR_S_MASK(base)               (((CySCB_Type*) (base))->INTR_S_MASK)
#define SCB_INTR_S_MASKED(base)             (((CySCB_Type*) (base))->INTR_S_MASKED)
#define SCB_INTR_TX(base)                   (((CySCB_Type*) (base))->INTR_TX)
#define SCB_INTR_TX_SET(base)               (((CySCB_Type*) (base))->INTR_TX_SET)
#define SCB_INTR_TX_MASK(base)              (((CySCB_Type*) (base))->INTR_TX_MASK)
#define SCB_INTR_TX_MASKED(base)            (((CySCB_Type*) (base))->INTR_TX_MASKED)
#define SCB_INTR_RX(base)                   (((CySCB_Type*) (base))->INTR_RX)
#define SCB_INTR_RX_SET(base)               (((CySCB_Type*) (base))->INTR_RX_SET)
#define SCB_INTR_RX_MASK(base)              (((CySCB_Type*) (base))->INTR_RX_MASK)
#define SCB_INTR_RX_MASKED(base)            (((CySCB_Type*) (base))->INTR_RX_MASKED)

/*******************************************************************************
*                USBFS Device
*******************************************************************************/

#define USBFS_DEV_CR0(base)             (((USBFS_Type *)(base))->USBDEV.CR0)
#define USBFS_DEV_CR1(base)             (((USBFS_Type *)(base))->USBDEV.CR1)
#define USBFS_DEV_USBIO_CR0(base)       (((USBFS_Type *)(base))->USBDEV.USBIO_CR0)
#define USBFS_DEV_USBIO_CR2(base)       (((USBFS_Type *)(base))->USBDEV.USBIO_CR2)
#define USBFS_DEV_USBIO_CR1(base)       (((USBFS_Type *)(base))->USBDEV.USBIO_CR1)
#define USBFS_DEV_USB_CLK_EN(base)      (((USBFS_Type *)(base))->USBDEV.USB_CLK_EN)
#define USBFS_DEV_BUS_RST_CNT(base)     (((USBFS_Type *)(base))->USBDEV.BUS_RST_CNT)
#define USBFS_DEV_OSCLK_DR0(base)       (((USBFS_Type *)(base))->USBDEV.EP_TYPE)
#define USBFS_DEV_OSCLK_DR1(base)       (((USBFS_Type *)(base))->USBDEV.OSCLK_DR0)
#define USBFS_DEV_SOF0(base)            (((USBFS_Type *)(base))->USBDEV.SOF0)
#define USBFS_DEV_SOF1(base)            (((USBFS_Type *)(base))->USBDEV.SOF1)
#define USBFS_DEV_SOF16(base)           (((USBFS_Type *)(base))->USBDEV.OSCLK_DR1)
#define USBFS_DEV_OSCLK_DR16(base)      (((USBFS_Type *)(base))->USBDEV.SOF16)
#define USBFS_DEV_ARB_CFG(base)         (((USBFS_Type *)(base))->USBDEV.ARB_CFG)
#define USBFS_DEV_DYN_RECONFIG(base)    (((USBFS_Type *)(base))->USBDEV.DYN_RECONFIG)
#define USBFS_DEV_BUF_SIZE(base)        (((USBFS_Type *)(base))->USBDEV.BUF_SIZE)
#define USBFS_DEV_EP_ACTIVE(base)       (((USBFS_Type *)(base))->USBDEV.EP_ACTIVE)
#define USBFS_DEV_EP_TYPE(base)         (((USBFS_Type *)(base))->USBDEV.EP_TYPE)
#define USBFS_DEV_CWA16(base)           (((USBFS_Type *)(base))->USBDEV.CWA16)
#define USBFS_DEV_CWA(base)             (((USBFS_Type *)(base))->USBDEV.CWA)
#define USBFS_DEV_CWA_MSB(base)         (((USBFS_Type *)(base))->USBDEV.CWA_MSB)
#define USBFS_DEV_DMA_THRES16(base)     (((USBFS_Type *)(base))->USBDEV.DMA_THRES16)
#define USBFS_DEV_DMA_THRES(base)       (((USBFS_Type *)(base))->USBDEV.DMA_THRES)
#define USBFS_DEV_DMA_THRES_MSB(base)   (((USBFS_Type *)(base))->USBDEV.DMA_THRES_MSB)

#define USBFS_DEV_SIE_EP_INT_EN(base)   (((USBFS_Type *)(base))->USBDEV.SIE_EP_INT_EN)
#define USBFS_DEV_SIE_EP_INT_SR(base)   (((USBFS_Type *)(base))->USBDEV.SIE_EP_INT_SR)
#define USBFS_DEV_ARB_INT_EN(base)      (((USBFS_Type *)(base))->USBDEV.ARB_INT_EN)
#define USBFS_DEV_ARB_INT_SR(base)      (((USBFS_Type *)(base))->USBDEV.ARB_INT_SR)

#define USBFS_DEV_EP0_CR(base)          (((USBFS_Type *)(base))->USBDEV.EP0_CR)
#define USBFS_DEV_EP0_CNT(base)         (((USBFS_Type *)(base))->USBDEV.EP0_CNT)
#define USBFS_DEV_EP0_DR(base, idx)     (((USBFS_Type *)(base))->USBDEV.EP0_DR[idx])

#define USBFS_DEV_MEM_DATA(base, idx)   (((USBFS_Type *)(base))->USBDEV.MEM[idx])

#define USBFS_DEV_SIE_REGS_BASE        (0x30U)
#define USBFS_DEV_SIE_REGS_SIZE        (0x40U)
#define USBFS_DEV_SIE_EP_CNT0_OFFSET   (0x00U)
#define USBFS_DEV_SIE_EP_CNT1_OFFSET   (0x04U)
#define USBFS_DEV_SIE_EP_CR0_OFFSET    (0x08U)
#define USBFS_DEV_SIE_REGS(base, endpoint) ((uint32_t)(base) + USBFS_DEV_SIE_REGS_BASE + ((endpoint) * USBFS_DEV_SIE_REGS_SIZE))

#define USBFS_DEV_SIE_EP_CNT0(base, endpoint)  (*(volatile uint32_t *) (USBFS_DEV_SIE_REGS(base, endpoint) + \
                                                                        USBFS_DEV_SIE_EP_CNT0_OFFSET))
#define USBFS_DEV_SIE_EP_CNT1(base, endpoint)  (*(volatile uint32_t *) (USBFS_DEV_SIE_REGS(base, endpoint) + \
                                                                        USBFS_DEV_SIE_EP_CNT1_OFFSET))
#define USBFS_DEV_SIE_EP_CR0(base, endpoint)   (*(volatile uint32_t *) (USBFS_DEV_SIE_REGS(base, endpoint) + \
                                                                        USBFS_DEV_SIE_EP_CR0_OFFSET))

#define USBFS_DEV_ARB_REGS_BASE         (0x200U)
#define USBFS_DEV_ARB_REGS_SIZE         (0x40U)
#define USBFS_DEV_ARB_EP_CFG_OFFSET     (0x00U)
#define USBFS_DEV_ARB_EP_INT_EN_OFFSET  (0x04U)
#define USBFS_DEV_ARB_EP_SR_OFFSET      (0x08U)
#define USBFS_DEV_ARB_RW_WA_OFFSET      (0x10U)
#define USBFS_DEV_ARB_RW_WA_MSB_OFFSET  (0x14U)
#define USBFS_DEV_ARB_RW_RA_OFFSET      (0x18U)
#define USBFS_DEV_ARB_RW_RA_MSB_OFFSET  (0x1CU)
#define USBFS_DEV_ARB_RW_DR_OFFSET      (0x20U)
#define USBFS_DEV_ARB_REGS(base, endpoint) ((uint32_t)(base) + USBFS_DEV_ARB_REGS_BASE + ((endpoint) * USBFS_DEV_ARB_REGS_SIZE))

#define USBFS_DEV_ARB_EP_CFG(base, endpoint)       (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_EP_CFG_OFFSET))
#define USBFS_DEV_ARB_EP_INT_EN(base, endpoint)    (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_EP_INT_EN_OFFSET))
#define USBFS_DEV_ARB_EP_SR(base, endpoint)        (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_EP_SR_OFFSET))
#define USBFS_DEV_ARB_RW_WA(base, endpoint)        (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_WA_OFFSET))
#define USBFS_DEV_ARB_RW_WA_MSB(base, endpoint)    (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_WA_MSB_OFFSET))
#define USBFS_DEV_ARB_RW_RA(base, endpoint)        (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_RA_OFFSET))
#define USBFS_DEV_ARB_RW_RA_MSB(base, endpoint)    (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_RA_MSB_OFFSET))
#define USBFS_DEV_ARB_RW_DR(base, endpoint)        (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_DR_OFFSET))

#define USBFS_DEV_ARB_REGS16_BASE       (0x1210U)
#define USBFS_DEV_ARB_REGS16_SIZE       (0x40U)
#define USBFS_DEV_ARB_RW_WA16_OFFSET    (0x00U)
#define USBFS_DEV_ARB_RW_RA16_OFFSET    (0x08U)
#define USBFS_DEV_ARB_RW_DR16_OFFSET    (0x10U)
#define USBFS_DEV_ARB_REGS_16(base, endpoint) ((uint32_t)(base) + USBFS_DEV_ARB_REGS16_BASE + ((endpoint) * USBFS_DEV_ARB_REGS16_SIZE))

#define USBFS_DEV_ARB_RW_WA16(base, endpoint)      (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS_16(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_WA16_OFFSET))
#define USBFS_DEV_ARB_RW_RA16(base, endpoint)      (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS_16(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_RA16_OFFSET))
#define USBFS_DEV_ARB_RW_DR16(base, endpoint)      (*(volatile uint32_t *) (USBFS_DEV_ARB_REGS_16(base, endpoint) + \
                                                                            USBFS_DEV_ARB_RW_DR16_OFFSET))

#define USBFS_DEV_LPM_POWER_CTL(base)       (((USBFS_Type *)(base))->USBLPM.POWER_CTL)
#define USBFS_DEV_LPM_USBIO_CTL(base)       (((USBFS_Type *)(base))->USBLPM.USBIO_CTL)
#define USBFS_DEV_LPM_FLOW_CTL(base)        (((USBFS_Type *)(base))->USBLPM.FLOW_CTL)
#define USBFS_DEV_LPM_LPM_CTL(base)         (((USBFS_Type *)(base))->USBLPM.LPM_CTL)
#define USBFS_DEV_LPM_LPM_STAT(base)        (((USBFS_Type const *)(base))->USBLPM.LPM_STAT)
#define USBFS_DEV_LPM_INTR_SIE(base)        (((USBFS_Type *)(base))->USBLPM.INTR_SIE)
#define USBFS_DEV_LPM_INTR_SIE_SET(base)    (((USBFS_Type *)(base))->USBLPM.INTR_SIE_SET)
#define USBFS_DEV_LPM_INTR_SIE_MASK(base)   (((USBFS_Type *)(base))->USBLPM.INTR_SIE_MASK)
#define USBFS_DEV_LPM_INTR_SIE_MASKED(base) (((USBFS_Type *)(base))->USBLPM.INTR_SIE_MASKED)
#define USBFS_DEV_LPM_INTR_LVL_SEL(base)    (((USBFS_Type *)(base))->USBLPM.INTR_LVL_SEL)
#define USBFS_DEV_LPM_INTR_CAUSE_HI(base)   (((USBFS_Type const *)(base))->USBLPM.INTR_CAUSE_HI)
#define USBFS_DEV_LPM_INTR_CAUSE_MED(base)  (((USBFS_Type const *)(base))->USBLPM.INTR_CAUSE_MED)
#define USBFS_DEV_LPM_INTR_CAUSE_LO(base)   (((USBFS_Type const *)(base))->USBLPM.INTR_CAUSE_LO)
#define USBFS_DEV_LPM_DFT_CTL(base)         (((USBFS_Type *)(base))->USBLPM.DFT_CTL)

#define USBFS_HOST_CTL0(base)               (((USBFS_Type *)(base))->USBHOST.HOST_CTL0)
#define USBFS_HOST_CTL1(base)               (((USBFS_Type *)(base))->USBHOST.HOST_CTL1)
#define USBFS_HOST_CTL2(base)               (((USBFS_Type *)(base))->USBHOST.HOST_CTL2)
#define USBFS_HOST_ERR(base)                (((USBFS_Type *)(base))->USBHOST.HOST_ERR)
#define USBFS_HOST_STATUS(base)             (((USBFS_Type *)(base))->USBHOST.HOST_STATUS)
#define USBFS_HOST_FCOMP(base)              (((USBFS_Type *)(base))->USBHOST.HOST_FCOMP)
#define USBFS_HOST_RTIMER(base)             (((USBFS_Type *)(base))->USBHOST.HOST_RTIMER)
#define USBFS_HOST_ADDR(base)               (((USBFS_Type *)(base))->USBHOST.HOST_ADDR)
#define USBFS_HOST_EOF(base)                (((USBFS_Type *)(base))->USBHOST.HOST_EOF)
#define USBFS_HOST_FRAME(base)              (((USBFS_Type *)(base))->USBHOST.HOST_FRAME)
#define USBFS_HOST_TOKEN(base)              (((USBFS_Type *)(base))->USBHOST.HOST_TOKEN)
#define USBFS_HOST_EP1_CTL(base)            (((USBFS_Type *)(base))->USBHOST.HOST_EP1_CTL)
#define USBFS_HOST_EP1_STATUS(base)         (((USBFS_Type *)(base))->USBHOST.HOST_EP1_STATUS)
#define USBFS_HOST_EP1_RW1_DR(base)         (((USBFS_Type *)(base))->USBHOST.HOST_EP1_RW1_DR)
#define USBFS_HOST_EP1_RW2_DR(base)         (((USBFS_Type *)(base))->USBHOST.HOST_EP1_RW2_DR)
#define USBFS_HOST_EP2_CTL(base)            (((USBFS_Type *)(base))->USBHOST.HOST_EP2_CTL)
#define USBFS_HOST_EP2_STATUS(base)         (((USBFS_Type *)(base))->USBHOST.HOST_EP2_STATUS)
#define USBFS_HOST_EP2_RW1_DR(base)         (((USBFS_Type *)(base))->USBHOST.HOST_EP2_RW1_DR)
#define USBFS_HOST_EP2_RW2_DR(base)         (((USBFS_Type *)(base))->USBHOST.HOST_EP2_RW2_DR)
#define USBFS_HOST_LVL1_SEL(base)           (((USBFS_Type *)(base))->USBHOST.HOST_LVL1_SEL)
#define USBFS_HOST_LVL2_SEL(base)           (((USBFS_Type *)(base))->USBHOST.HOST_LVL2_SEL)
#define USBFS_INTR_USBHOST_CAUSE_HI(base)   (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST_CAUSE_HI)
#define USBFS_INTR_USBHOST_CAUSE_MED(base)  (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST_CAUSE_MED)
#define USBFS_INTR_USBHOST_CAUSE_LO(base)   (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST_CAUSE_LO)
#define USBFS_INTR_HOST_EP_CAUSE_HI(base)   (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP_CAUSE_HI)
#define USBFS_INTR_HOST_EP_CAUSE_MED(base)  (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP_CAUSE_MED)
#define USBFS_INTR_HOST_EP_CAUSE_LO(base)   (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP_CAUSE_LO)
#define USBFS_INTR_USBHOST(base)            (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST)
#define USBFS_INTR_USBHOST_SET(base)        (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST_SET)
#define USBFS_INTR_USBHOST_MASK(base)       (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST_MASK)
#define USBFS_INTR_USBHOST_MASKED(base)     (((USBFS_Type *)(base))->USBHOST.INTR_USBHOST_MASKED)
#define USBFS_INTR_HOST_EP(base)            (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP)
#define USBFS_INTR_HOST_EP_SET(base)        (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP_SET)
#define USBFS_INTR_HOST_EP_MASK(base)       (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP_MASK)
#define USBFS_INTR_HOST_EP_MASKED(base)     (((USBFS_Type *)(base))->USBHOST.INTR_HOST_EP_MASKED)
#define USBFS_HOST_DMA_ENBL(base)           (((USBFS_Type *)(base))->USBHOST.HOST_DMA_ENBL)
#define USBFS_HOST_EP1_BLK(base)            (((USBFS_Type *)(base))->USBHOST.HOST_EP1_BLK)
#define USBFS_HOST_EP2_BLK(base)            (((USBFS_Type *)(base))->USBHOST.HOST_EP2_BLK)

/*******************************************************************************
*                MXS40USBHSDEV
*******************************************************************************/

#define USBHSDEV_DEV_PWR_CS_DISCON              (1U << USBHSDEV_DEV_PWR_CS_DISCON_Pos)
#define USBHSDEV_DEV_LPM_ATTR_RMT_WAKEUP_ENABLE (1U << USBHSDEV_DEV_LPM_ATTR_RMT_WAKEUP_ENABLE_Pos)
#define USBHSDEV_DEV_LPM_ATTR_L2_SUSP_RMT_WAKEUP_EN (1U << USBHSDEV_DEV_LPM_ATTR_L2_SUSP_RMT_WAKEUP_EN_Pos)
#define USBHSDEV_DEV_PWR_CS_DEV_SUSPEND         (1U << USBHSDEV_DEV_PWR_CS_DEV_SUSPEND_Pos)
#define USBHSDEV_DEV_PWR_CS_FORCE_FS            (1U << USBHSDEV_DEV_PWR_CS_FORCE_FS_Pos)
#define USBHSDEV_DEV_PWR_CS_SIGRSUME            (1U << USBHSDEV_DEV_PWR_CS_SIGRSUME_Pos)
#define USBHSDEV_DEV_PWR_CS_L0_ACTIVE           (1U << USBHSDEV_DEV_PWR_CS_L0_ACTIVE_Pos)
#define USBHSDEV_DEV_PWR_CS_L2_SUSPEND          (1U << USBHSDEV_DEV_PWR_CS_L2_SUSPEND_Pos)
#define USBHSDEV_DEV_PWR_CS_L1_SLEEP            (1U << USBHSDEV_DEV_PWR_CS_L1_SLEEP_Pos)
#define USBHSDEV_DEV_EPI_CS_NAK                 (1U << USBHSDEV_DEV_EPI_CS_NAK_Pos)
#define USBHSDEV_DEV_EPO_CS_NAK                 (1U << USBHSDEV_DEV_EPO_CS_NAK_Pos)
#define USBHSDEV_DEV_CS_SETUP_CLR_BUSY          (1U << USBHSDEV_DEV_CS_SETUP_CLR_BUSY_Pos)
#define USBHSDEV_DEV_CS_NAKALL                  (1U << USBHSDEV_DEV_CS_NAKALL_Pos)
#define USBHSDEV_DEV_EPI_CS_STALL               (1U << USBHSDEV_DEV_EPI_CS_STALL_Pos)
#define USBHSDEV_DEV_EPO_CS_STALL               (1U << USBHSDEV_DEV_EPO_CS_STALL_Pos)
#define USBHSDEV_DEV_TOGGLE_IO                  (1U << USBHSDEV_DEV_TOGGLE_IO_Pos)
#define USBHSDEV_DEV_TOGGLE_TOGGLE_VALID        (1U << USBHSDEV_DEV_TOGGLE_TOGGLE_VALID_Pos)
#define USBHSDEV_DEV_TOGGLE_R                   (1U << USBHSDEV_DEV_TOGGLE_R_Pos)
#define USBHSDEV_DEV_EPO_CS_VALID               (1U << USBHSDEV_DEV_EPO_CS_VALID_Pos)
#define USBHSDEV_DEV_EPI_CS_VALID               (1U << USBHSDEV_DEV_EPI_CS_VALID_Pos)
#define USBHSDEV_EEPM_ENDPOINT_EGRS_FLUSH_EP    (1U << USBHSDEV_EEPM_ENDPOINT_EGRS_FLUSH_EP_Pos)
#define USBHSDEV_EPM_CS_EGRS_FORCE_FLUSH_ALL    (1U << USBHSDEV_EPM_CS_EGRS_FORCE_FLUSH_ALL_Pos)
#define USBHSDEV_EPM_CS_IGRS_FORCE_FLUSH_ALL    (1U << USBHSDEV_EPM_CS_IGRS_FORCE_FLUSH_ALL_Pos)
#define USBHSDEV_DEV_EPI_CS_ZERO_MASK           (1U << USBHSDEV_DEV_EPI_CS_ZERO_MASK_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_SETADDR      (1U << USBHSDEV_DEV_CTL_INTR_MASK_SETADDR_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_SOF          (1U << USBHSDEV_DEV_CTL_INTR_MASK_SOF_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_SUSP         (1U << USBHSDEV_DEV_CTL_INTR_MASK_SUSP_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_URESET       (1U << USBHSDEV_DEV_CTL_INTR_MASK_URESET_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_HSGRANT      (1U << USBHSDEV_DEV_CTL_INTR_MASK_HSGRANT_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_SUTOK        (1U << USBHSDEV_DEV_CTL_INTR_MASK_SUTOK_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_SUDAV        (1U << USBHSDEV_DEV_CTL_INTR_MASK_SUDAV_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_ERRLIMIT     (1U << USBHSDEV_DEV_CTL_INTR_MASK_ERRLIMIT_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_URESUME      (1U << USBHSDEV_DEV_CTL_INTR_MASK_URESUME_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_STATUS_STAGE (1U << USBHSDEV_DEV_CTL_INTR_MASK_STATUS_STAGE_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_L1_SLEEP_REQ (1U << USBHSDEV_DEV_CTL_INTR_MASK_L1_SLEEP_REQ_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_L1_URESUME   (1U << USBHSDEV_DEV_CTL_INTR_MASK_L1_URESUME_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_RESETDONE    (1U << USBHSDEV_DEV_CTL_INTR_MASK_RESETDONE_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_HOST_URSUME_ARRIVED (1U << USBHSDEV_DEV_CTL_INTR_MASK_HOST_URSUME_ARRIVED_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_DPSLP        (1U << USBHSDEV_DEV_CTL_INTR_MASK_DPSLP_Pos)
#define USBHSDEV_DEV_CTL_INTR_MASK_PID_MISMATCH_ON_NAK (1U << USBHSDEV_DEV_CTL_INTR_MASK_PID_MISMATCH_ON_NAK_Pos)
#define USBHSDEV_DEV_CTL_INTR_SETADDR           (1U << USBHSDEV_DEV_CTL_INTR_SETADDR_Pos)
#define USBHSDEV_DEV_CTL_INTR_SOF               (1U << USBHSDEV_DEV_CTL_INTR_SOF_Pos)
#define USBHSDEV_DEV_CTL_INTR_SUSP              (1U << USBHSDEV_DEV_CTL_INTR_SUSP_Pos)
#define USBHSDEV_DEV_CTL_INTR_URESET            (1U << USBHSDEV_DEV_CTL_INTR_URESET_Pos)
#define USBHSDEV_DEV_CTL_INTR_HSGRANT           (1U << USBHSDEV_DEV_CTL_INTR_HSGRANT_Pos)
#define USBHSDEV_DEV_CTL_INTR_SUTOK             (1U << USBHSDEV_DEV_CTL_INTR_SUTOK_Pos)
#define USBHSDEV_DEV_CTL_INTR_SUDAV             (1U << USBHSDEV_DEV_CTL_INTR_SUDAV_Pos)
#define USBHSDEV_DEV_CTL_INTR_ERRLIMIT          (1U << USBHSDEV_DEV_CTL_INTR_ERRLIMIT_Pos)
#define USBHSDEV_DEV_CTL_INTR_URESUME           (1U << USBHSDEV_DEV_CTL_INTR_URESUME_Pos)
#define USBHSDEV_DEV_CTL_INTR_STATUS_STAGE      (1U << USBHSDEV_DEV_CTL_INTR_STATUS_STAGE_Pos)
#define USBHSDEV_DEV_CTL_INTR_L1_SLEEP_REQ      (1U << USBHSDEV_DEV_CTL_INTR_L1_SLEEP_REQ_Pos)
#define USBHSDEV_DEV_CTL_INTR_L1_URESUME        (1U << USBHSDEV_DEV_CTL_INTR_L1_URESUME_Pos)
#define USBHSDEV_DEV_CTL_INTR_RESETDONE         (1U << USBHSDEV_DEV_CTL_INTR_RESETDONE_Pos)
#define USBHSDEV_DEV_CTL_INTR_HOST_URSUME_ARRIVED (1U << USBHSDEV_DEV_CTL_INTR_HOST_URSUME_ARRIVED_Pos)
#define USBHSDEV_DEV_CTL_INTR_DPSLP             (1U << USBHSDEV_DEV_CTL_INTR_DPSLP_Pos)
#define USBHSDEV_DEV_CTL_INTR_PID_MISMATCH_ON_NAK (1U << USBHSDEV_DEV_CTL_INTR_PID_MISMATCH_ON_NAK_Pos)
#define USBHSDEV_DEV_EPI_CS_ZERO                (1U << USBHSDEV_DEV_EPI_CS_ZERO_Pos)
#define USBHSDEV_DEV_EPI_CS_COMMIT              (1U << USBHSDEV_DEV_EPI_CS_COMMIT_Pos)
#define USBHSPHY_PLL_CONTROL_1_SUPPLY_EN        (1U << USBHSPHY_PLL_CONTROL_1_SUPPLY_EN_Pos)
#define USBHSPHY_PLL_CONTROL_1_PLL_EN           (1U << USBHSPHY_PLL_CONTROL_1_PLL_EN_Pos)
#define USBHSPHY_CDR_CONTROL_CDR_ENABLE         (1U << USBHSPHY_CDR_CONTROL_CDR_ENABLE_Pos)
#define USBHSPHY_AFE_CONTROL_1_CPU_DELAY_ENABLE_HS_VCCD (1U << USBHSPHY_AFE_CONTROL_1_CPU_DELAY_ENABLE_HS_VCCD_Pos)
#define USBHSPHY_REG_1P1_CONTROL_ENABLE_LV      (1U << USBHSPHY_REG_1P1_CONTROL_ENABLE_LV_Pos)
#define USBHSPHY_REG_2P5_CONTROL_BYPASS_MODE    (1U << USBHSPHY_REG_2P5_CONTROL_BYPASS_MODE_Pos)
#define USBHSPHY_VREFGEN_CONTROL_ENABLE_LV      (1U << USBHSPHY_VREFGEN_CONTROL_ENABLE_LV_Pos)
#define USBHSPHY_IREFGEN_CONTROL_ENABLE_LV      (1U << USBHSPHY_IREFGEN_CONTROL_ENABLE_LV_Pos)
#define USBHSPHY_REG_1P1_CONTROL_SWITCH_EN      (1U << USBHSPHY_REG_1P1_CONTROL_SWITCH_EN_Pos)
#define USBHSPHY_INTR0_ENABLE_HS_VCCD           (1U << USBHSPHY_INTR0_ENABLE_HS_VCCD_Pos)
#define USBHSPHY_INTR0_PLL_LOCK                 (1U << USBHSPHY_INTR0_PLL_LOCK_Pos)
#define USBHSPHY_REG_2P5_CONTROL_ENABLE_LV      (1U << USBHSPHY_REG_2P5_CONTROL_ENABLE_LV_Pos)
#define USBHSPHY_INTR0_ENABLE_VCCD              (1U << USBHSPHY_INTR0_ENABLE_VCCD_Pos)
#define USBHSPHY_AFE_CONTROL_1_CPU_DELAY_ENABLE_VCCD    (1U << USBHSPHY_AFE_CONTROL_1_CPU_DELAY_ENABLE_VCCD_Pos)
#define USBHSDEV_POWER_RESETN                   (1U << USBHSDEV_POWER_RESETN_Pos)
#define USBHSDEV_POWER_VBUS_VALID               (1U << USBHSDEV_POWER_VBUS_VALID_Pos)
#define USBHSDEV_POWER_EPM_DCG_ENABLE           (1U << USBHSDEV_POWER_EPM_DCG_ENABLE_Pos)
#define USBHSDEV_DEV_LPM_ATTR_NYET              (1U << USBHSDEV_DEV_LPM_ATTR_NYET_Pos)

#endif /* CY_DEVICE_H_ */

/* [] END OF FILE */
