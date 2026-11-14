/***************************************************************************//**
* \file main.c
* \version 1.0
*
* Main source file of the FX10 Integrated Audio+Video class application.
*
*******************************************************************************
* \copyright
* (c) (2021-2023), Cypress Semiconductor Corporation (an Infineon company) or
* an affiliate of Cypress Semiconductor Corporation.
*
* SPDX-License-Identifier: Apache-2.0
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* author:691229847@qq.com
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*******************************************************************************/

#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"
#include "cy_pdl.h"
#include <string.h>
#include "cy_usb_common.h"
#include "cy_usbss_cal_drv.h"
#include "cy_usb_uvc_device.h"
#include "cy_usb_usbd.h"
#include "cy_usb_app.h"
#include "cy_debug.h"
#include "cy_fx3g2_bsp.h"
#include "cy_usbd_version.h"
#include "cy_hbdma_version.h"
#include "cy_lvds.h"
#include "cy_smif.h"
#include "../app_version.h"
#include "timers.h"
#include "spi_axi.h"
#if LVCMOS_EN
#include "cy_gpif_header_lvcmos.h"
#else
#include "cy_gpif_header_lvds.h"
#endif

#if PTM_ENABLE
/* RTOS SW timer specific stuff */
/* 100 ms */
#define AUTO_RELOAD_TIMER_PERIOD (pdMS_TO_TICKS(2000UL))
TimerHandle_t xAutoReloadTimer;
BaseType_t xTimerStarted;
#endif /* PTM_ENABLE */

#if DEBUG_INFRA_EN
/* Debug log related initilization */
TaskHandle_t printLogTaskHandle;
#endif /* DEBUG_INFRA_EN */

/* Global variables associated with High BandWidth DMA setup. */
cy_stc_hbdma_context_t HBW_DrvCtxt;     /* High BandWidth DMA driver context. */
cy_stc_hbdma_dscr_list_t HBW_DscrList;  /* High BandWidth DMA descriptor free list. */
cy_stc_hbdma_buf_mgr_t HBW_BufMgr;      /* High BandWidth DMA buffer manager. */
cy_stc_hbdma_mgr_context_t HBW_MgrCtxt; /* High BandWidth DMA manager context. */
cy_stc_usb_usbd_ctxt_t usbdCtxt;
cy_stc_usb_app_ctxt_t appCtxt;
cy_stc_usbss_cal_ctxt_t ssCalCtxt;
cy_stc_usb_cal_ctxt_t hsCalCtxt;

/* CPU DMA register pointers. */
DMAC_Type *pCpuDmacBase;
DW_Type   *pCpuDw0Base;
DW_Type   *pCpuDw1Base;
void ReportStatus();
cy_stc_smif_context_t smifContext;
uint32_t hfclkFreq = BCLK__BUS_CLK__HZ;
static uint32_t g_UsbEvtLogBuf[512u];

#define SMIF_EnableInt()   NVIC_EnableIRQ((IRQn_Type)smif_interrupt_IRQn)

/***************************************
*       SMIF API Constants
***************************************/

/* SMIF configuration parameters */
#define DESELECT_DELAY      (1u)	/* The minimal duration of SPI de-selection */ 
#define RX_CLOCK_SELECT     (1u)	/* The clock source for the receiver clock */
#define AHB_BUS_ERROR       (0u)	/* What happens when there is a Read 
									* to an empty RX FIFO or Write to a full TX FIFO
                                    */ 
                                    
/* SMIF Interrupt Configuration*/
#define SMIF_INT_MAP        (NvicMux10)     /* 
                                             * Mapping the SMIF M4 core interrupt to 
                                             * the 10th M0+ core interrupt
                                             */
#define SMIF_PRIORITY       (1u)            /* SMIF interrupt priority */

#define TX_RX_EQUAL       	(1u) 	/* The transmitted and received arrays are equal */
#define TX_RX_NOT_EQUAL     (0u) 	/* The transmitted and received arrays are not equal */
#define TIMEOUT_1_MS        (1000ul)/* 1 ms timeout for all blocking functions */
#if BLOAD_ENABLE

/* Offset within the flash where the application binary is to be placed. */
#define APP_FLASH_OFFSET        (0x8000)

/* Section reserved to store the application signature. Size is equal to flash row size. */
__attribute__ ((section(".cy_app_signature"), used)) const uint8_t cyFx3g2AppSignature[512] = {0};

#else

/* Offset within the flash where the application binary is to be placed. */
#define APP_FLASH_OFFSET        (0)

#endif /* BLOAD_ENABLE */

#if CY_CPU_CORTEX_M4
__attribute__((section(".cm0_code"), used))
const uint32_t Cm0Code[256] = {
    0x08003C00,
    0x100000C9 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x100000D1 + APP_FLASH_OFFSET,
    0x480A490B,
    0x490B6008,
    0x4A0B6808,
    0x4A0B4010,
    0x60084310,
    0x6848490A,
    0xD5FC06C0,
    0x2004B662,
    0x61084908,
    0xBF00BF00,
    0xE7FABF30,
    0x10000400 + APP_FLASH_OFFSET,
    0x40200200,
    0x40201200,
    0x0000FFFC,
    0x05FA0003,
    0x40200000,
    0xE000ED00,
    0xF7FF2000,
    0xBF30FFD9,
    0x00004770,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00000000};
#endif /* CY_CPU_CORTEX_M4 */

extern void xPortPendSVHandler(void);
extern void xPortSysTickHandler(void);
extern void vPortSVCHandler(void);

/* RAM buffer used to hold debug log data. */
#define LOGBUF_RAM_SZ           (1024U)
volatile uint32_t LogDataBuffer[LOGBUF_RAM_SZ / 4U];

/* Select SCB interface used for UART based logging. */
#define LOGGING_SCB             (SCB1)
#define LOGGING_SCB_IDX         (1)

extern void fx3g2_clk_init (void);
void vPortSetupTimerInterrupt(void)
{
    /* Register the exception vectors. */
    Cy_SysInt_SetVector(PendSV_IRQn, xPortPendSVHandler);
    Cy_SysInt_SetVector(SVCall_IRQn, vPortSVCHandler);
    Cy_SysInt_SetVector(SysTick_IRQn, xPortSysTickHandler);

    /* Start the SysTick timer with a period of 1 ms. */
    Cy_SysTick_SetClockSource(CY_SYSTICK_CLOCK_SOURCE_CLK_CPU);
    Cy_SysTick_SetReload(hfclkFreq / 1000U);
    Cy_SysTick_Clear();
    Cy_SysTick_Enable();
}

#if DEBUG_INFRA_EN
void PrintTaskHandler(void *pTaskParam)
{
    while (1)
    {
        /* Print any pending logs to the output console. */
        Cy_Debug_PrintLog();

        /* Put the thread to sleep for 5 ms */
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}
#endif /* DEBUG_INFRA_EN */

#if PTM_ENABLE
/*****************************************************************************
* Function Name: ITP_EnableCB
******************************************************************************
* Summary:
*  Callback function for software timer
*
* Parameters:
*  xTimer

* Return:
*  Does not return.
*****************************************************************************/

void ITP_EnableCB(TimerHandle_t xTimer)
{
    USB32DEV->USB32DEV_PROT.PROT_INTR_MASK |= USB32DEV_PROT_INTR_ITP_EV_Msk;
}

/*****************************************************************************
* Function Name: Software timer initialization
******************************************************************************
* Summary:
*  Does some init for running rtos based auto reload software timer
*  which periodically enables ITP interrupt for LDM exchange mechanism
*
* Parameters:
*  void

* Return:
*  Does not return.
*****************************************************************************/
void Cy_SoftwareTimerInit(void)
{
    DBG_USBD_INFO("Initializing software timer\r\n");
    xAutoReloadTimer = xTimerCreate("AutoReload",
                                    AUTO_RELOAD_TIMER_PERIOD,
                                    pdTRUE,
                                    0,
                                    ITP_EnableCB);

    xTimerStarted = xTimerStart(xAutoReloadTimer, 0);
}
#endif /* PTM_ENABLE */

void LVDS_GpifEventCb(uint8_t smNo, cy_en_lvds_gpif_event_type_t gpifEvent, void *cntxt)
{
    CyU3vAppGpifIntr(&appCtxt);
}


void LVDS_PhyEventCb(uint8_t smNo, cy_en_lvds_phy_events_t phyEvent, void *cntxt)
{
    if(phyEvent == CY_LVDS_PHY_L1_EXIT)
    {
        if(smNo == 0)
        {
           DBG_APP_INFO("P0_L1_Exit\r\n");
        }
        else
        {
           DBG_APP_INFO("P1_L1_Exit\r\n");
        }
    }
    if(phyEvent == CY_LVDS_PHY_L1_ENTRY)
    {
        if(smNo == 0)
        {
            DBG_APP_INFO("P0_L1_Entry\r\n");
        }
        else
        {
            DBG_APP_INFO("P1_L1_Entry\r\n");
        }
    }
    if(phyEvent == CY_LVDS_PHY_L3_ENTRY)
    {
        if(smNo == 0)
        {
            DBG_APP_INFO("P0_L3_Entry\r\n");
        }
        else
        {
            DBG_APP_INFO("P1_L3_Entry\r\n");
        }
    }
}
void LVDS_LowPowerEventCb(cy_en_lvds_low_power_events_t lowPowerEvent, void *cntxt)
{
    if(lowPowerEvent == CY_LVDS_LOW_POWER_LNK0_L3_EXIT)
    {
        DBG_APP_INFO("P0_L3_Exit\r\n");
    }
    if(lowPowerEvent == CY_LVDS_LOW_POWER_LNK1_L3_EXIT)
    {
        DBG_APP_INFO("P1_L3_Exit\r\n");
    }
}
cy_stc_lvds_app_cb_t cb =
{
	.gpif_events = LVDS_GpifEventCb,
	.gpif_error = NULL,
	.gpif_thread_error = NULL,
	.gpif_thread_event = NULL,
    .phy_events = LVDS_PhyEventCb,
    .low_power_events   = LVDS_LowPowerEventCb
};

cy_stc_lvds_context_t lvdsContext;

cy_stc_lvds_md_config_t mdArray0[16] = {
                        {CY_LVDS_MD_VARIABLE0,             CY_LVDS_MD_VARIABLE},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT},
                        {0x0000,                           CY_LVDS_MD_CONSTANT}
                    };
/*****************************************************************************
 * Function Name: InitLvdsInterface
 *****************************************************************************
 * Summary
 *  Initialize the LVDS interface. Currently, only the SIP #0 is being initialized
 *  and configured to allow transfers into the HBW SRAM through DMA.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  void
 ****************************************************************************/
cy_en_lvds_status_t Cy_LVDS_PhyTrainingStartMy(LVDSSS_LVDS_Type* base, uint8_t portNo, const cy_stc_lvds_phy_config_t * config)
{
    uint32_t timeoutCount = 0;
    cy_en_lvds_status_t status = CY_LVDS_SUCCESS;

    /* PHY training is only required for LVDS modes */
    if(config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS)
        return CY_LVDS_CONFIG_ERROR;
    base->AFE[portNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk;
    spi_axi_wr(SMIF0, &smifContext, 0x00100010, portNo);
    base->AFE[portNo].PHY_TRAIN_CONFIG  |= _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_EN, 1);
    Cy_LVDS_PhyGpioSet(LVDSSS_LVDS, 0, CY_LVDS_PHY_GPIO_CTL6);  
    if (!((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_156_25_MHZ) && 
        (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1)))
    {
        while(!(base->AFE[portNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk))
        {
            //Cy_SysLib_Delay(1);
            timeoutCount++;
            if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT) 
            {
                status = CY_LVDS_TIMEOUT_ERROR;
                DBG_LVDS_INFO("DESKEW timed out for Port: %d\r\n", portNo);
                return status;
            }   
        }
        Cy_LVDS_PhyGpioClr(LVDSSS_LVDS, 0, CY_LVDS_PHY_GPIO_CTL6);  
        base->AFE[portNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk;
        
        status = CY_LVDS_SUCCESS;
        DBG_LVDS_INFO("Deskew complete for Port: %d\r\n", portNo);
        DBG_APP_INFO("PHY_GENERAL_STATUS_2=%x\r\n", LVDSSS_LVDS_AFE0->PHY_GENERAL_STATUS_2); 
    }
    DBG_LVDS_INFO("TRAINING_BLK_CFG: %x\r\n", LVDSSS_LVDS->TRAINING_BLK_CFG);
    DBG_LVDS_INFO("TRAINING_BLK: %x\r\n", LVDSSS_LVDS->TRAINING_BLK);
    DBG_LVDS_INFO("LINK_TRAINING_STS0: %x\r\n", LVDSSS_LVDS->LINK_TRAINING_STS[0]);
    DBG_LVDS_INFO("LINK_TRAINING_STS1: %x\r\n", LVDSSS_LVDS->LINK_TRAINING_STS[1]);
    /* Required for auto-skew correction for SDR fast and DDR fast DESKEW algorithm */
/*    if (!((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_156_25_MHZ) && 
        (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1)))   
        base->AFE[portNo].GENERAL_RX |= _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_BER_RSTN, 1u);
*/
    spi_axi_wr(SMIF0, &smifContext, 0x0010000a, 0);
    return status;
}
void InitLvdsInterface (void)
{
    
    spi_axi_wr(SMIF0, &smifContext, 0x0010000a, 0);
    Cy_SysLib_Delay(1);
#if LVDS_LB_EN
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_INIT_LVDS_LB_EN);
    Cy_LVDS_PhyInit(LVDSSS_LVDS, 1, &LVDS1_config, &lvdsContext);
    Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 3, 1, 0, 0, 0);
    Cy_LVDS_GpifInit(LVDSSS_LVDS, 1, &cy_lvds_gpif_config_th3_socket, &lvdsContext);
    DBG_APP_INFO("GPIF1 loopback config done\r\n");

    cy_en_hbdma_mgr_status_t mgrstat;
    cy_stc_hbdma_chn_config_t chn_conf = 
    {
        .size = 0xF0E0,
        .count = 2,
        .chType = CY_HBDMA_TYPE_MEM_TO_IP,
        .bufferMode = true,
        .prodSckCount = 1,
        .prodSck = {CY_HBDMA_VIRT_SOCKET_WR, CY_HBDMA_VIRT_SOCKET_WR},
        .consSckCount = 1,
        .consSck = {CY_HBDMA_LVDS_SOCKET_17, CY_HBDMA_LVDS_SOCKET_17},
        .eventEnable = 0,
        .intrEnable = 0x3FF,
        .cb = HbDma_Cb_Loopback,
        .userCtx = (void *)&appCtxt
    };

    mgrstat = Cy_HBDma_Channel_Create(&HBW_MgrCtxt, &lvdsLbPgmChannel, &chn_conf);
    if (mgrstat != CY_HBDMA_MGR_SUCCESS)
    {
        DBG_APP_ERR("Loopback channel create failed 0x%x\r\n", mgrstat);
    }
#endif /* LVDS_LB_EN */

#if PORT1_EN
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_PPORT1_EN);
    Cy_LVDS_Init(LVDSSS_LVDS, 1, &cy_lvds0_config, &lvdsContext);
    DBG_APP_INFO("LVDS Port 1 Init done\r\n");

    /* Set Interrupt Mask for GPIF */
    Cy_LVDS_SetInterruptMask(LVDSSS_LVDS, 0xffffffff);
    LVDSSS_LVDS->LVDS_INTR_MASK_WD1= 0xffffffff;
    DBG_APP_INFO("Set Interrupt Mask for GPIF\r\n");

    Cy_LVDS_RegisterCallback(LVDSSS_LVDS, &cb, &lvdsContext, &appCtxt);

#if (LVCMOS_EN && (!INMD_EN) )
    Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 2, 0, 0, 0, 0);
#endif

/* In case of LVDS call PHY Training for PORT1 */
#if (!LVCMOS_EN)
    Cy_LVDS_PhyTrainingStart(LVDSSS_LVDS, 1, cy_lvds0_config.phyConfig);
#endif

    Cy_LVDS_Enable(LVDSSS_LVDS);
    DBG_APP_INFO("LVDSEn\r\n");

#if INMD_EN
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_INMD_EN);
    Cy_LVDS_InitMetadata(LVDSSS_LVDS, 2, 0, 16, mdArray0);
    DBG_APP_INFO("MetaDataInit - PORT 1\r\n");
#endif

#if LVCMOS_EN
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_LVCMOS_EN);
    Cy_LVDS_GpifSMStart(LVDSSS_LVDS, 1, 0, 0x4);
#else
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_LVDS_EN);
    Cy_LVDS_GpifSMStart(LVDSSS_LVDS, 1, 0, 0);
#endif

    DBG_APP_INFO("Gpif1SMStart\r\n");
#else  /* ---- NOTE : PORT1 END / PORT0 START ----- */
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_PPORT0_EN);
    Cy_LVDS_PhyInit(LVDSSS_LVDS, 0, cy_lvds0_config.phyConfig, &lvdsContext);
    DBG_APP_INFO("LVDSPhy0_Init done\r\n");

/* In case of LVDS call PHY Training for PORT0 */
#if ((!LVCMOS_EN) && (!LVDS_LB_EN))
    Cy_LVDS_PhyTrainingStartMy(LVDSSS_LVDS, 0, cy_lvds0_config.phyConfig);
#endif
	
#if (WL_EN)
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_PPORT0_EN);
    Cy_LVDS_PhyInit(LVDSSS_LVDS, 1, cy_lvds0_config.phyConfig, &lvdsContext);
    DBG_APP_INFO("LVDSPhy1_Init done\r\n");

/* In case of LVDS call PHY Training for PORT1 */
#if (!LVCMOS_EN)
    Cy_LVDS_PhyTrainingStartMy(LVDSSS_LVDS, 1, cy_lvds0_config.phyConfig);
#endif

#endif /* (WL_EN) */

    Cy_LVDS_GpifInit(LVDSSS_LVDS, 0, cy_lvds0_config.gpifConfig, &lvdsContext);
    DBG_APP_INFO("LVDSGPIF0_Init done\r\n");

    /* Set Interrupt Mask for GPIF */
    Cy_LVDS_SetInterruptMask(LVDSSS_LVDS, 0xffffffff);
    DBG_APP_INFO("Set Interrupt Mask for GPIF\r\n");

    Cy_LVDS_RegisterCallback(LVDSSS_LVDS, &cb, &lvdsContext, &appCtxt);

#if LVDS_LB_EN
    Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 0, 0, 0, 0, 0);
#endif

#if PORT0_THREAD_INTLV
    LVDSSS_LVDS->THREAD_INTLV_CTL |= (1 << 0);
#endif

#if (LVCMOS_EN && (!INMD_EN) )
    Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 0, 0, 0, 0, 0);
#endif
    //Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 0, 0, 0, 0, 0);
   // Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 1, 0, 0, 0, 0);
   // Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 2, 0, 0, 0, 0);
   // Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS, 3, 0, 0, 0, 0);
    Cy_LVDS_Enable(LVDSSS_LVDS);
    DBG_APP_INFO("LVDSEn 11\r\n");

#if INMD_EN
    Cy_LVDS_InitMetadata(LVDSSS_LVDS, 0, 0, 16, mdArray0);
    DBG_APP_INFO("MetaDataInit - PORT 0\r\n");
#endif

#if LVCMOS_EN
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_LVCMOS_EN);
    Cy_LVDS_GpifSMStart(LVDSSS_LVDS, 0, 0, 0x4);
#else
    Cy_USBD_AddEvtToLog(&usbdCtxt, CY_USB_EVT_LVDS_EN);
    DBG_APP_INFO("Starting SM\r\n");
    Cy_LVDS_GpifSMStart(LVDSSS_LVDS, 0, 0, 0);
#endif

    DBG_APP_INFO("Gpif0SMStart\r\n");
#endif

#if LVDS_LB_EN
    Cy_LVDS_GpifSMStart(LVDSSS_LVDS, 1, 0, 0);
#endif

    /* Set INTR for LVDS LPM */
#if (!WL_EN)
    /* Enable L3 entry interrupt for both links. */
    Cy_LVDS_SetInterruptMask(LVDSSS_LVDS, 0xC0000000);
#else
    /* Enable L3 entry interrupt for link0. */
    Cy_LVDS_SetInterruptMask(LVDSSS_LVDS, 0x40000000);
#endif /* (!WL_EN) */
ReportStatus();
}


/*****************************************************************************
 * Function Name: ISR section
 ******************************************************************************
 * Summary:
 *  Various interrupt handlers
 *****************************************************************************/

void LVDS_ISR(void)
{
    Cy_LVDS_IrqHandler(LVDSSS_LVDS, &lvdsContext);
    DBG_APP_INFO("LVDS_ISR\r\n");
}

void LVDS_LPM_Isr(void)
{
    Cy_LVDS_LowPowerIrqHandler(LVDSSS_LVDS, &lvdsContext);
}

void LvdsPort0Dma_ISR(void)
{
    /* Call the HBDMA interrupt handler with the appropriate adapter ID. */
    Cy_HBDma_HandleInterrupts(&HBW_DrvCtxt, CY_HBDMA_ADAP_LVDS_0);
    portYIELD_FROM_ISR(true);
    //DBG_APP_INFO("LvdsPort0Dma_ISR\r\n");
}

void LvdsPort1Dma_ISR(void)
{
    /* Call the HBDMA interrupt handler with the appropriate adapter ID. */
    Cy_HBDma_HandleInterrupts(&HBW_DrvCtxt, CY_HBDMA_ADAP_LVDS_1);
    portYIELD_FROM_ISR(true);
    DBG_APP_INFO("LvdsPort1Dma_ISR\r\n");
                    DBG_APP_INFO("****VARW0=%x\r\n",LVDSSS_LVDS_THREAD0->VARW0);
                    DBG_APP_INFO("****VARW0=%x\r\n",LVDSSS_LVDS_THREAD1->VARW0);
                    DBG_APP_INFO("****VARW0=%x\r\n",LVDSSS_LVDS_THREAD2->VARW0);
                    DBG_APP_INFO("****VARW0=%x\r\n",LVDSSS_LVDS_THREAD3->VARW0);
}

void UsbSS_ISR(void)
{
    /* Call the USB32DEV interrupt handler. */
    Cy_USBSS_Cal_IntrHandler(&ssCalCtxt);
}

/*****************************************************************************
 * Function Name: UsbHS_ISR
 ******************************************************************************
 * Summary:
 *  Handler for USB-HS Interrupts.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  None
 *****************************************************************************/
void UsbHS_ISR(void)
{
#if FREERTOS_ENABLE
    if (Cy_USBHS_Cal_IntrHandler(&hsCalCtxt))
    {
        portYIELD_FROM_ISR(true);
    }
#else
    Cy_USBHS_Cal_IntrHandler(&hsCalCtxt);
#endif /* FREERTOS_ENABLE */
}

void UsbIngressDma_ISR(void)
{
    /* Call the HBDMA interrupt handler with the appropriate adapter ID. */
    Cy_HBDma_HandleInterrupts(&HBW_DrvCtxt, CY_HBDMA_ADAP_USB_IN);
    portYIELD_FROM_ISR(true);
}

void UsbEgressDma_ISR(void)
{
    /* Call the HBDMA interrupt handler with the appropriate adapter ID. */
    Cy_HBDma_HandleInterrupts(&HBW_DrvCtxt, CY_HBDMA_ADAP_USB_EG);
    portYIELD_FROM_ISR(true);
}

void UvcDataWire_ISR (void)
{
    /* Clear the interrupt first. */
    Cy_USB_AppClearDmaInterrupt(&appCtxt, appCtxt.uvcInEpNum, CY_USB_ENDP_DIR_IN);

    /* The current data buffer has been consumed. Move to another buffer if available. */
    CyUvcAppHandleSendCompletion(&appCtxt);
}

/*****************************************************************************
 * Function Name: VbusDetGpio_ISR
 *****************************************************************************
 * Summary
 *  Interrupt handler for the Vbus detect GPIO transition detection.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  void
 ****************************************************************************/
static void VbusDetGpio_ISR(void)
{
    BaseType_t xHigherPriorityTaskWoken;
    cy_stc_usbd_app_msg_t xMsg;

    /* Send VBus changed message to the task thread. */
    xMsg.type = CY_USB_UVC_VBUS_CHANGE_INTR;
    xQueueSendFromISR(appCtxt.uvcMsgQueue, &(xMsg), &(xHigherPriorityTaskWoken));

    /* Remember that VBus change has happened and disable the interrupt. */
    appCtxt.vbusChangeIntr = true;
    Cy_GPIO_SetInterruptMask(VBUS_DETECT_GPIO_PORT, VBUS_DETECT_GPIO_PIN, 0);
}

/*****************************************************************************
 * Function Name: PrintVersionInfo
 ******************************************************************************
 * Summary:
 *  Function to print version information to UART console.
 *
 * Parameters:
 *  type: Type of version string.
 *  version: Version number including major, minor, patch and build number.
 *
 * Return:
 *  None
 *****************************************************************************/
void PrintVersionInfo(const char *type, uint32_t version)
{
    char tString[32];
    uint16_t vBuild;
    uint8_t vMajor, vMinor, vPatch;
    uint8_t typeLen = strlen(type);

    vMajor = (version >> 28U);
    vMinor = ((version >> 24U) & 0x0FU);
    vPatch = ((version >> 16U) & 0xFFU);
    vBuild = (uint16_t)(version & 0xFFFFUL);

    memcpy(tString, type, typeLen);
    tString[typeLen++] = '0' + (vMajor / 10);
    tString[typeLen++] = '0' + (vMajor % 10);
    tString[typeLen++] = '.';
    tString[typeLen++] = '0' + (vMinor / 10);
    tString[typeLen++] = '0' + (vMinor % 10);
    tString[typeLen++] = '.';
    tString[typeLen++] = '0' + (vPatch / 10);
    tString[typeLen++] = '0' + (vPatch % 10);
    tString[typeLen++] = '.';
    tString[typeLen++] = '0' + (vBuild / 1000);
    tString[typeLen++] = '0' + ((vBuild % 1000) / 100);
    tString[typeLen++] = '0' + ((vBuild % 100) / 10);
    tString[typeLen++] = '0' + (vBuild % 10);
    tString[typeLen++] = '\r';
    tString[typeLen++] = '\n';
    tString[typeLen] = 0;

    DBG_APP_INFO("%s", tString);
}

/*****************************************************************************
 * Function Name: USBSSInit
 *****************************************************************************
 * Summary
 *  Initialize USBSS block and attempt device enumeration.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  void
 ****************************************************************************/
void USBSSInit (void)
{
    cy_stc_gpio_pin_config_t pinCfg;
    cy_stc_sysint_t intrCfg;
    cy_stc_debug_config_t    dbgCfg;

    /* Initialize the UART for logging. */
    InitUart(LOGGING_SCB_IDX);

    dbgCfg.pBuffer   = (uint8_t *)LogDataBuffer;
    dbgCfg.traceLvl  = 3U;
    dbgCfg.bufSize   = LOGBUF_RAM_SZ;
    dbgCfg.dbgIntfce = CY_DEBUG_INTFCE_UART_SCB1;
    dbgCfg.printNow  = true; /* Delay output of messages till logging task runs. */
    Cy_Debug_LogInit(&dbgCfg);

    memset((void *)&pinCfg, 0, sizeof(pinCfg));

    /* Configure VBus detect GPIO. */
    pinCfg.driveMode = CY_GPIO_DM_HIGHZ;
    pinCfg.hsiom     = HSIOM_SEL_GPIO;
    pinCfg.intEdge   = CY_GPIO_INTR_BOTH;
    pinCfg.intMask   = 0x01UL;
    Cy_GPIO_Pin_Init(VBUS_DETECT_GPIO_PORT, VBUS_DETECT_GPIO_PIN, &pinCfg);

    /* Register edge detect interrupt for Vbus detect GPIO. */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = VBUS_DETECT_GPIO_INTR;
    intrCfg.intrPriority = 7;
#else
    intrCfg.cm0pSrc = VBUS_DETECT_GPIO_INTR;
    intrCfg.intrSrc = NvicMux5_IRQn;
    intrCfg.intrPriority = 3;
#endif
    Cy_SysInt_Init(&intrCfg, VbusDetGpio_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /*
     * CMR-4 RTL specific initialization: The LVDS2USB32SS and USB32DEV IP blocks
     * need to be enabled before we try to do High BandWidth DMA initialization.
     */
    MAIN_REG->CTRL |= MAIN_REG_CTRL_IP_ENABLED_Msk;
#if USBSS_GEN2_ENABLE
    USB32DEV->USB32DEV_PROT.PROT_SUBLINK_LSM = 0x000A000A;
#endif /* USBSS_GEN2_ENABLE */
    USB32DEV->USB32DEV_MAIN.CTRL |= USB32DEV_MAIN_CTRL_IP_ENABLED_Msk;

    /* Register the LVDS ISR and enable the interrupt for LVDS. */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_lvds_int_o_IRQn;
    intrCfg.intrPriority = 6;
#else
    intrCfg.intrSrc = NvicMux0_IRQn;
    intrCfg.intrPriority = 2;
    intrCfg.cm0pSrc = lvds2usb32ss_lvds_int_o_IRQn;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, LVDS_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /* Register the ISR and enable the interrupt for SIP0 DMA adapter. */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_lvds_dma_adap0_int_o_IRQn;
    intrCfg.intrPriority = 3;
#else
    intrCfg.intrSrc = NvicMux4_IRQn;
    intrCfg.intrPriority = 1;
    intrCfg.cm0pSrc = lvds2usb32ss_lvds_dma_adap0_int_o_IRQn;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, &LvdsPort0Dma_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /* Register the ISR and enable the interrupt for SIP1 DMA adapter. */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_lvds_dma_adap1_int_o_IRQn;
    intrCfg.intrPriority = 3;
#else
    intrCfg.intrSrc = NvicMux4_IRQn;
    intrCfg.intrPriority = 1;
    intrCfg.cm0pSrc = lvds2usb32ss_lvds_dma_adap1_int_o_IRQn;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, &LvdsPort1Dma_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /* Register the USBSS ISR and enable the interrupt. */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_usb32_int_o_IRQn;
    intrCfg.intrPriority = 4;
#else
    intrCfg.intrSrc = NvicMux1_IRQn;
    intrCfg.cm0pSrc = lvds2usb32ss_usb32_int_o_IRQn;
    intrCfg.intrPriority = 0;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, &UsbSS_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_usb32_wakeup_int_o_IRQn;
    intrCfg.intrPriority = 4;
#else
    intrCfg.intrSrc = NvicMux1_IRQn;
    intrCfg.cm0pSrc = lvds2usb32ss_usb32_wakeup_int_o_IRQn;
    intrCfg.intrPriority = 0;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, &UsbSS_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /* ISR for the USB Ingress DMA adapter */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_usb32_ingrs_dma_int_o_IRQn;
    intrCfg.intrPriority = 3;
#else
    intrCfg.intrSrc = NvicMux3_IRQn;
    intrCfg.cm0pSrc = lvds2usb32ss_usb32_ingrs_dma_int_o_IRQn;
    intrCfg.intrPriority = 0;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, &UsbIngressDma_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

/* ISR for the USB Egress DMA adapter */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc = lvds2usb32ss_usb32_egrs_dma_int_o_IRQn;
    intrCfg.intrPriority = 3;
#else
    intrCfg.intrSrc = NvicMux2_IRQn;
    intrCfg.cm0pSrc = lvds2usb32ss_usb32_egrs_dma_int_o_IRQn;
    intrCfg.intrPriority = 0;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, &UsbEgressDma_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /* Register ISR for and enable USBHS Interrupt. */
#if CY_CPU_CORTEX_M4
    intrCfg.intrSrc      = usbhsdev_interrupt_u2d_active_o_IRQn;
    intrCfg.intrPriority = 4;
#else
    intrCfg.cm0pSrc      = usbhsdev_interrupt_u2d_active_o_IRQn;
    intrCfg.intrSrc      = NvicMux5_IRQn;
    intrCfg.intrPriority = 2;
#endif /* CY_CPU_CORTEX_M4 */
    Cy_SysInt_Init(&intrCfg, UsbHS_ISR);
    NVIC_EnableIRQ(intrCfg.intrSrc);

    /* Register ISR for LVDS LPM */
    intrCfg.intrSrc      = lvds2usb32ss_lvds_wakeup_int_o_IRQn;
    intrCfg.intrPriority = 0;
    Cy_SysInt_Init(&intrCfg, LVDS_LPM_Isr);
    NVIC_EnableIRQ(lvds2usb32ss_lvds_wakeup_int_o_IRQn);
}

bool InitHbDma(void)
{
    cy_en_hbdma_status_t drvstat;
    cy_en_hbdma_mgr_status_t mgrstat;

    /* Initialize the HBW DMA driver layer. */
    drvstat = Cy_HBDma_Init(LVDSSS_LVDS, USB32DEV, &HBW_DrvCtxt, 0, 0);
    if (drvstat != CY_HBDMA_SUCCESS)
    {
        return false;
    }

    /* Setup a HBW DMA descriptor list. */
    mgrstat = Cy_HBDma_DscrList_Create(&HBW_DscrList, 256U);
    if (mgrstat != CY_HBDMA_MGR_SUCCESS)
    {
        return false;
    }

    /* Initialize the DMA buffer manager. We will use 512 KB of space from 0x1C030000 onwards. */
    mgrstat = Cy_HBDma_BufMgr_Create(&HBW_BufMgr, (uint32_t *)0x1C030000UL, 0x80000UL);
    if (mgrstat != CY_HBDMA_MGR_SUCCESS)
    {
        return false;
    }

    /* Initialize the HBW DMA channel manager. */
    mgrstat = Cy_HBDma_Mgr_Init(&HBW_MgrCtxt, &HBW_DrvCtxt, &HBW_DscrList, &HBW_BufMgr);
    if (mgrstat != CY_HBDMA_MGR_SUCCESS)
    {
        return false;
    }

    return true;
}

void Cy_USBSS_DeInit(cy_stc_usbss_cal_ctxt_t *pCalCtxt)
{
    USB32DEV_Type *base = pCalCtxt->regBase;
    USB32DEV_MAIN_Type *USB32DEV_MAIN = &base->USB32DEV_MAIN;

    /* Disable the clock for USB3.2 function */
    USB32DEV_MAIN->CTRL &= ~USB32DEV_MAIN_CTRL_CLK_EN_Msk;

    /* Disable PHYSS */
    base->USB32DEV_PHYSS.USB40PHY[0].USB40PHY_TOP.TOP_CTRL_0 &=
        ~(USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_PWR_GOOD_CORE_RX_Msk |
                USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_PWR_GOOD_CORE_PLL_Msk |
                USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_VBUS_Msk |
                USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_PHYSS_EN_Msk |
                USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_PCLK_EN_Msk);

    base->USB32DEV_PHYSS.USB40PHY[1].USB40PHY_TOP.TOP_CTRL_0 &=
                    ~(USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_PWR_GOOD_CORE_RX_Msk |
                     USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_PWR_GOOD_CORE_PLL_Msk |
                     USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_VBUS_Msk |
                     USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_REG_PHYSS_EN_Msk |
                     USB32DEV_PHYSS_USB40PHY_TOP_CTRL_0_PCLK_EN_Msk);

    /* Disable the SuperSpeed Device function */
    USB32DEV_MAIN->CTRL &= ~USB32DEV_MAIN_CTRL_SSDEV_ENABLE_Msk;
}

/*****************************************************************************
 * Function Name: DisableUsbBlock
 ******************************************************************************
 * Summary:
 *  Function to disable the USB32DEV IP block after terminating current
 *  connection.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  None
 *****************************************************************************/
void DisableUsbBlock (void)
{
    /* Disable the USB32DEV IP. */
    USB32DEV->USB32DEV_MAIN.CTRL &= ~USB32DEV_MAIN_CTRL_IP_ENABLED_Msk;

    /* Disable HBDMA adapter interrupts and the adapter itself. */
    NVIC_DisableIRQ(lvds2usb32ss_usb32_ingrs_dma_int_o_IRQn);
    NVIC_DisableIRQ(lvds2usb32ss_usb32_egrs_dma_int_o_IRQn);
    Cy_HBDma_DeInit(&HBW_DrvCtxt);

    DBG_APP_INFO("Disabled HBWSS DMA adapters\r\n");
}

/*****************************************************************************
 * Function Name: EnableUsbBlock
 ******************************************************************************
 * Summary:
 *  Function to enable the USB32DEV IP block before enabling a new USB
 *  connection.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  None
 *****************************************************************************/
void EnableUsbBlock (void)
{
    /* Enable the USB DMA adapters and respective interrupts. */
    Cy_HBDma_Init(NULL, USB32DEV, &HBW_DrvCtxt, 0, 0);

    NVIC_EnableIRQ(lvds2usb32ss_usb32_ingrs_dma_int_o_IRQn);
    NVIC_EnableIRQ(lvds2usb32ss_usb32_egrs_dma_int_o_IRQn);

#if USBSS_GEN2_ENABLE
    USB32DEV->USB32DEV_PROT.PROT_SUBLINK_LSM = 0x000A000A;
#endif /* USBSS_GEN2_ENABLE */

    /* Make sure to enable USB32DEV IP. */
    USB32DEV->USB32DEV_MAIN.CTRL |= USB32DEV_MAIN_CTRL_IP_ENABLED_Msk;
}

/*****************************************************************************
 * Function Name: UsbSSConnectionEnable
 *****************************************************************************
 * Summary
 *  PSVP specific USB connect function.
 *
 * Parameters:
 *  pAppCtxt: Pointer to UVC application context structure.
 *
 * Return:
 *  void
 ****************************************************************************/
bool UsbSSConnectionEnable (cy_stc_usb_app_ctxt_t *pAppCtxt)
{
#if (!FORCE_USBHS)

#if USBSS_GEN2_ENABLE
    Cy_USBD_ConnectDevice(pAppCtxt->pUsbdCtxt, CY_USBD_USB_DEV_SS_GEN2);
#else
    Cy_USBD_ConnectDevice(pAppCtxt->pUsbdCtxt, CY_USBD_USB_DEV_SS_GEN1);
#endif /* USBSS_GEN2_ENABLE */

#else
    DBG_APP_INFO("USB_DEV_HS\r\n");
    Cy_USBD_ConnectDevice(pAppCtxt->pUsbdCtxt, CY_USBD_USB_DEV_HS);
    pAppCtxt->usbConnected = true;
#endif /* FORCE_USBHS */

    return true;
}

/*****************************************************************************
 * Function Name: UsbSSConnectionDisable
 *****************************************************************************
 * Summary
 *  PSVP specific USB disconnect function.
 *
 * Parameters:
 *  None
 *
 * Return:
 *  void
 ****************************************************************************/
void UsbSSConnectionDisable (cy_stc_usb_app_ctxt_t *pAppCtxt)
{
    Cy_USBD_DisconnectDevice(pAppCtxt->pUsbdCtxt);
    Cy_USBSS_DeInit(pAppCtxt->pUsbdCtxt->pSsCalCtxt);
    pAppCtxt->usbConnected = false;
    pAppCtxt->devState     = CY_USB_DEVICE_STATE_DISABLE;
    pAppCtxt->prevDevState = CY_USB_DEVICE_STATE_DISABLE;
}

void ExtMemInterrupt(void)
{
    Cy_SMIF_Interrupt(SMIF0, &smifContext);
}
/*****************************************************************************
* Function Name: main(void)
******************************************************************************
* Summary:
*  Entry to the application.
*
* Parameters:
*  void

* Return:
*  Does not return.
*****************************************************************************/
int main (void)
{
    /* Update the HFCLK frequency with the PDL first. */
    Cy_SysClk_ClkHfUpdateFrequency(hfclkFreq);

    /* Initialize the PDL driver library and set the clock variables. */
    Cy_PDL_Init (&cy_deviceIpBlockCfgFx3G2);

    /* Initialize the device clocks to the desired values. */
    fx3g2_clk_init();
    Cy_Fx3G2_InitPeripheralClocks(true, false);

    hfclkFreq = Cy_SysClk_ClkFastGetFrequency();

    /* Unlock and then disable the watchdog. */
    Cy_WDT_Unlock();
    Cy_WDT_Disable();
    /* Enable interrupts. */
    __enable_irq ();

    memset((uint8_t *)&appCtxt, 0, sizeof(appCtxt));
    memset((uint8_t *)&ssCalCtxt, 0, sizeof(ssCalCtxt));
    memset((uint8_t *)&hsCalCtxt, 0, sizeof(hsCalCtxt));
    memset((uint8_t *)&usbdCtxt, 0, sizeof(usbdCtxt));

    pCpuDmacBase = ((DMAC_Type *)DMAC_BASE);
    pCpuDw0Base = ((DW_Type *)DW0_BASE);
    pCpuDw1Base = ((DW_Type *)DW1_BASE);

    /* Initialize the PDL and register ISR for USB block. */
    USBSSInit();

#if AUDIO_IF_EN
    MxPdmInit();
#endif /* AUDIO_IF_EN */
    cy_stc_gpio_pin_config_t pinCfg;
    /* Configure P6.0��P6.3��P7.0��P7.1 as  signals. */
    memset ((void *)&pinCfg, 0, sizeof(pinCfg));
    pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
    pinCfg.hsiom     = P6_0_SMIF_SPI_CLK;
    Cy_GPIO_Pin_Init(P6_0_PORT, P6_0_PIN, &pinCfg);

    memset ((void *)&pinCfg, 0, sizeof(pinCfg));
    pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
    pinCfg.hsiom     = P6_3_SMIF_SPI_SELECT2;
    Cy_GPIO_Pin_Init(P6_3_PORT, P6_3_PIN, &pinCfg);

    memset ((void *)&pinCfg, 0, sizeof(pinCfg));
    pinCfg.driveMode = CY_GPIO_DM_STRONG_IN_OFF;
    pinCfg.hsiom     = P7_0_SMIF_SPI_DATA0;
    Cy_GPIO_Pin_Init(P7_0_PORT, P7_0_PIN, &pinCfg);

    memset ((uint8_t *)&pinCfg, 0, sizeof(pinCfg));
    pinCfg.driveMode = CY_GPIO_DM_HIGHZ;
    pinCfg.hsiom     = P7_1_SMIF_SPI_DATA1;
    Cy_GPIO_Pin_Init(P7_1_PORT, P7_1_PIN, &pinCfg);


/* The SMIF interrupt setup */
    cy_stc_sysint_t smifIntConfig =
    {
        .intrSrc = (IRQn_Type)smif_interrupt_IRQn,      /* SMIF interrupt */
        .intrPriority = SMIF_PRIORITY       /* SMIF interrupt priority */
    };
    
    Cy_SysInt_Init(&smifIntConfig, ExtMemInterrupt);

/* SMIF configuration parameters */
    cy_stc_smif_config_t SPI_FRAMConfig =
    {
        .mode           = CY_SMIF_NORMAL,   /* The mode of operation */
        .deselectDelay  = DESELECT_DELAY,   /* The minimum duration of SPI deselection */
        .rxClockSel     = RX_CLOCK_SELECT,  /* The clock source for the receiver clock */
        .blockEvent     = AHB_BUS_ERROR,    /* What happens when there is a Read to an empty RX FIFO or Write to a full TX FIFO*/
    };
	
/* SMIF initialization */
    Cy_SMIF_Init(SMIF0, &SPI_FRAMConfig, TIMEOUT_1_MS, &smifContext);
    Cy_SMIF_SetDataSelect(SMIF0, CY_SMIF_SLAVE_SELECT_2, CY_SMIF_DATA_SEL0);
    Cy_SMIF_Enable(SMIF0, &smifContext);
   
/* Enable the SMIF interrupt */
    SMIF_EnableInt();
    int axi_data;
    spi_axi_wr(SMIF0, &smifContext, 0x00100010, 0);
    while(1)
    {
        axi_data = spi_axi_rd(SMIF0, &smifContext, 0x00100003);
        DBG_APP_INFO("wait the fpga pro done!!: %x\r\n", axi_data);
        if(axi_data == 0x53)
            break;
    }
    spi_axi_wr(SMIF0, &smifContext, 0x00100003, 0x01);
    spi_axi_wr(SMIF0, &smifContext, 0x00100004, 0x01);
    spi_axi_wr(SMIF0, &smifContext, 0x00100005, 0x01);
    spi_axi_wr(SMIF0, &smifContext, 0x00100006, 0x01);
    spi_axi_wr(SMIF0, &smifContext, 0x00100007, 0x01);

    spi_axi_wr(SMIF0, &smifContext, 0x0010000C, 0x01);
    spi_axi_wr(SMIF0, &smifContext, 0x0010000D, 0x25);
    spi_axi_wr(SMIF0, &smifContext, 0x0010000E, 0xaa);

    axi_data = spi_axi_rd(SMIF0, &smifContext, 0x00100003);

    DBG_APP_INFO("LVDS_PHY_TS_OFFSET_8: %x\r\n", axi_data);
    axi_data = spi_axi_rd(SMIF0, &smifContext, 0x00100004);
    DBG_APP_INFO("TRAINING_BLK_SEQ_BYTE_P0_OFFSET_8: %x\r\n", axi_data);
    axi_data = spi_axi_rd(SMIF0, &smifContext, 0x00100005);
    DBG_APP_INFO("TRAINING_BLK_SEQ_BYTE_P1_OFFSET_8: %x\r\n", axi_data);
    axi_data = spi_axi_rd(SMIF0, &smifContext, 0x00100006);
    DBG_APP_INFO("TRAINING_BLK_SEQ_BYTE_P2_OFFSET_8: %x\r\n", axi_data);
    axi_data = spi_axi_rd(SMIF0, &smifContext, 0x00100007);
    DBG_APP_INFO("TRAINING_BLK_SEQ_BYTE_P3_OFFSET_8: %x\r\n", axi_data);

    Cy_LVDS_PhyGpioModeEnable(LVDSSS_LVDS, 0, CY_LVDS_PHY_GPIO_CTL6, CY_LVDS_PHY_GPIO_OUTPUT, CY_LVDS_PHY_GPIO_NO_INTERRUPT);
    Cy_LVDS_PhyGpioClr(LVDSSS_LVDS, 0, CY_LVDS_PHY_GPIO_CTL6);

#if DEBUG_INFRA_EN
    /* Print application, USBD stack and HBDMA version information. */
    PrintVersionInfo("APP_VERSION: ", APP_VERSION_NUM);
    PrintVersionInfo("USBD_VERSION: ", USBD_VERSION_NUM);
    PrintVersionInfo("HBDMA_VERSION: ", HBDMA_VERSION_NUM);

    /* Create task for printing logs and check status. */
    xTaskCreate(PrintTaskHandler, "PrintLogTask", 512, NULL, 5, &printLogTaskHandle);
#endif /* DEBUG_INFRA_EN */

    /* Store IP base address in CAL context. */
    ssCalCtxt.regBase = USB32DEV;
    hsCalCtxt.pCalBase = MXS40USBHSDEV_USBHSDEV;
    hsCalCtxt.pPhyBase = MXS40USBHSDEV_USBHSPHY;

    /*
     * Make sure any previous USB connection state is cleared. Give some delay to allow the host to process
     * disconnection.
     */
    Cy_USBSS_DeInit(&ssCalCtxt);
    Cy_SysLib_Delay(500);

    /* Initialize the HbDma IP and DMA Manager */
    InitHbDma();
    DBG_APP_INFO("InitHbDma done\r\n");

    /* Initialize the USBD layer */
    Cy_USB_USBD_Init(&appCtxt, &usbdCtxt, pCpuDmacBase, &hsCalCtxt, &ssCalCtxt, &HBW_MgrCtxt);
    DBG_APP_INFO("USBD_Init done\r\n");

    /* Select 480 MHz clock from USB2 PLL for DMA operation and divide by 2 to get 240 MHz. */
    Cy_USBD_SetDmaClkFreq(&usbdCtxt, CY_HBDMA_CLK_240_MHZ);
    MAIN_REG->CTRL = (MAIN_REG->CTRL & 0xF00FFFFFUL) | 0x09900000UL;

    /*
     * Make sure InitEventLog called before AppInit or before creating
     * thread for application.
     * Allocate a memory block and register it as USB event log buffer.
     */
    appCtxt.pUsbEvtLogBuf = (uint32_t *)g_UsbEvtLogBuf;
    Cy_USBD_InitEventLog(&usbdCtxt, appCtxt.pUsbEvtLogBuf, 512u);

    /* Initialize the application and create echo device thread. */
    Cy_USB_AppInit(&appCtxt, &usbdCtxt, pCpuDmacBase, pCpuDw0Base, pCpuDw1Base, &HBW_MgrCtxt);
    /* Register USB descriptors with the stack. */
    CyApp_RegisterUsbDescriptors(&appCtxt, CY_USBD_USB_DEV_SS_GEN1);

#if PTM_ENABLE
    Cy_SoftwareTimerInit();
#endif

    /* Invokes scheduler: Not expected to return. */
    vTaskStartScheduler();
    while (1);

    return 0;
}

/*****************************************************************************
 * Function Name: Cy_OnResetUser(void)
 ******************************************************************************
 * Summary:
 *  Init function which is executed before the load regions in RAM are updated.
 *  The High BandWidth subsystem needs to be enable here to allow variables
 *  placed in the High BandWidth SRAM to be updated.
 *
 * Parameters:
 *  void
 *
 * Return:
 *  void
 *****************************************************************************/
void Cy_OnResetUser(void)
{
    Cy_Fx3G2_OnResetInit();
}

static uint16_t gCurUsbEvtLogIndex = 0;

/*****************************************************************************
* Function Name: AppPrintUsbEventLog
******************************************************************************
* Summary:
*  Function to print out the USB event log buffer content.
*
* Parameters:
*  pAppCtxt: Pointer to application context data structure.
*  pSSCal: Pointer to SSCAL context data structure.
*
* Return:
*  void
*****************************************************************************/
void AppPrintUsbEventLog (cy_stc_usb_app_ctxt_t *pAppCtxt, cy_stc_usbss_cal_ctxt_t *pSSCal)
{
    uint16_t prevLogIdx = gCurUsbEvtLogIndex;

    (void)pSSCal;

    /* Print out any pending USB event log data. */
    gCurUsbEvtLogIndex = Cy_USBD_GetEvtLogIndex(pAppCtxt->pUsbdCtxt);
    while (gCurUsbEvtLogIndex != prevLogIdx) {
        DBG_APP_INFO("USBEVT: %x\r\n", pAppCtxt->pUsbEvtLogBuf[prevLogIdx]);
        prevLogIdx++;
        if (prevLogIdx == 512u) {
            prevLogIdx = 0u;
        }
    }
}
void ReportStatus()
{
    DBG_APP_INFO("LINK_CONFIG0=%x\r\n", LVDSSS_LVDS->LINK_CONFIG[0]); 
    DBG_APP_INFO("LINK_CONFIG1=%x\r\n", LVDSSS_LVDS->LINK_CONFIG[1]); 
    DBG_APP_INFO("LVDS_INTR_WD0=%x\r\n", LVDSSS_LVDS->LVDS_INTR_MASKED_WD0); 
    DBG_APP_INFO("LVDS_INTR_WD1=%x\r\n", LVDSSS_LVDS->LVDS_INTR_MASKED_WD1); 
    DBG_APP_INFO("LVDS_ERROR=%x\r\n", LVDSSS_LVDS->LVDS_ERROR); 
    DBG_APP_INFO("PHY_GENERAL_CONFIG=%x\r\n", LVDSSS_LVDS_AFE0->PHY_GENERAL_CONFIG); 
    DBG_APP_INFO("PHY_GENERAL_STATUS_1=%x\r\n", LVDSSS_LVDS_AFE0->PHY_GENERAL_STATUS_1); 
    DBG_APP_INFO("PHY_GENERAL_STATUS_2=%x\r\n", LVDSSS_LVDS_AFE0->PHY_GENERAL_STATUS_2); 
    DBG_APP_INFO("PHY_GENERAL_STATUS_1=%x\r\n", LVDSSS_LVDS_AFE1->PHY_GENERAL_STATUS_1); 
    DBG_APP_INFO("PHY_GENERAL_STATUS_2=%x\r\n", LVDSSS_LVDS_AFE1->PHY_GENERAL_STATUS_2); 
    DBG_APP_INFO("GPIF_STATUS=%x\r\n", LVDSSS_LVDS_GPIF0->GPIF_STATUS);
    DBG_APP_INFO("GPIF_INTR=%x\r\n", LVDSSS_LVDS_GPIF0->GPIF_INTR_MASKED);
    DBG_APP_INFO("GPIF_ERROR=%x\r\n", LVDSSS_LVDS_GPIF0->GPIF_ERROR);
    
}
/* [] END OF FILE */
