/***************************************************************************//**
* \file cy_usb_app.h
* \version 1.0
*
* Defines the interfaces used in the FX10 USB Video Class application.
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

#ifndef _CY_USB_APP_H_
#define _CY_USB_APP_H_

#include "cy_pdl.h"
#include "cy_debug.h"
#include "cy_usbhs_dw_wrapper.h"

#if defined(__cplusplus)
extern "C" {
#endif

/* Loopback program color bands*/
#define BAND1_COLOR_YUYV                0x80ff80ff    // White
#define BAND2_COLOR_YUYV                0x94ff00ff    // Yellow
#define BAND3_COLOR_YUYV                0x1ac8bfc8    // Blue
#define BAND4_COLOR_YUYV                0x4aca55ca    // Green
#define BAND5_COLOR_YUYV                0xf3969f96    // Pink
#define BAND6_COLOR_YUYV                0xff4c544c    // Red
#define BAND7_COLOR_YUYV                0x9e40d340    // Violet
#define BAND8_COLOR_YUYV                0x80008000    // Black
#define COLORBAR_BAND_COUNT_4K          120
#define COLORBAR_BAND_COUNT_1080P       60
#define COLORBAR_BAND_COUNT_720P        40
#define COLORBAR_BAND_COUNT_480P        20
#define LOOPBACK_MEM_BUF_SIZE           0xF0C0

/* P4.0 is used for VBus detect functionality. */
#define VBUS_DETECT_GPIO_PORT           (P4_0_PORT)
#define VBUS_DETECT_GPIO_PIN            (P4_0_PIN)
#define VBUS_DETECT_GPIO_INTR           (ioss_interrupts_gpio_dpslp_4_IRQn)
#define VBUS_DETECT_STATE               (0u)

/* Number of buffers used for PDM data transfer. */
#define PDM_APP_BUFFER_CNT              (4u)

typedef struct cy_stc_usb_app_ctxt_ cy_stc_usb_app_ctxt_t;

/* USBD layer return code shared between USBD layer and Application layer. */
typedef enum cy_en_usb_app_ret_code_ {
    CY_USB_APP_STATUS_SUCCESS=0,
    CY_USB_APP_STATUS_FAILURE,
}cy_en_usb_app_ret_code_t;

/*
 * USB application data structure which is bridge between USB system and device
 * functionality.
 * It maintains some usb system information which comes from USBD and it also
 * maintains info about functionality.
 */
struct cy_stc_usb_app_ctxt_
{
    uint8_t firstInitDone;
    cy_en_usb_device_state_t devState;
    cy_en_usb_device_state_t prevDevState;
    cy_en_usb_speed_t devSpeed;
    uint8_t devAddr;
    uint8_t activeCfgNum;
    cy_en_usb_enum_method_t enumMethod;
    uint8_t prevAltSetting;
    cy_en_usb_speed_t desiredSpeed;

    cy_stc_app_endp_dma_set_t endpInDma[CY_USB_MAX_ENDP_NUMBER];
    cy_stc_app_endp_dma_set_t endpOutDma[CY_USB_MAX_ENDP_NUMBER];
    DMAC_Type *pCpuDmacBase;
    DW_Type *pCpuDw0Base;
    DW_Type *pCpuDw1Base;

    cy_stc_hbdma_mgr_context_t *pHbDmaMgrCtxt;
    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt;
    cy_stc_hbdma_channel_t *hbBulkInChannel;

    /* UVC specific fields. */
    uint8_t uvcInEpNum;                         /** Index of UVC streaming endpoint. */
    uint8_t uvcPendingBufCnt;                   /** Number of data buffers which are pending to be streamed. */
    bool    uvcFlowCtrlFlag;                    /** Flag indicating that UVC channel is in flow control. */

    /* Global Task handles */
    TaskHandle_t uvcDevicetaskHandle;           /** UVC application task. */
    QueueHandle_t uvcMsgQueue;                  /** Message queue used to send messages to the UVC task. */

    bool usbConnectDone;
    bool vbusChangeIntr;                        /** VBus change interrupt received flag. */
    bool vbusPresent;                           /** VBus presence indicator flag. */
    bool usbConnected;                          /** Whether USB connection is enabled. */
    TimerHandle_t vbusDebounceTimer;            /** VBus change debounce timer handle. */
    uint32_t *pUsbEvtLogBuf;
    TimerHandle_t evtLogTimer;                  /** Timer to print eventLog. */

#if AUDIO_IF_EN
    /* UAC interface specific fields. */
    cy_stc_hbdma_channel_t *pPDMToUsbChn;       /** PDM to USB DMA channel handle. */
    uint8_t *pPDMRxBuffer[PDM_APP_BUFFER_CNT];  /** Pointer of buffers to read PDM data into. */
    uint16_t pdmRxDataLen[PDM_APP_BUFFER_CNT];  /** Amount of data in each PDM RX buffer. */
    uint8_t  pdmRxBufIndex;                     /** Index of current PDM read buffer. */
    uint8_t  nxtAudioTxBufIndex;                /** Index of next audio buffer to be sent on USB EP. */
    uint8_t  pdmRxFreeBufCount;                 /** Number of free PDM RX buffers. */
    bool     pdmInXferPending;                  /** Whether a write has been queued on IN EP. */
    uint8_t  pdmPendingDmaFlag;                 /** Flag indicating whether DMA transfer is pending on
                                                    each PDM RX channel. */
    TaskHandle_t  uacAppTaskHandle;             /** Handle to the UAC application task. */
    QueueHandle_t uacMsgQueue;                  /** Handle to UAC application message queue. */
    TimerHandle_t pdmActivateTimer;             /** Handle of timer used to activate PDM channels. */
#endif /* AUDIO_IF_EN */
};

typedef struct
{
    uint8_t *pBuffer;
    uint8_t start;
    uint8_t end;
    uint8_t dataMode;
    uint8_t dataSrc;
    uint8_t ctrlByte;
    uint16_t repeatCount;
    uint32_t dataL;
    uint32_t dataH;
    uint32_t ctrlBusVal;
    uint32_t lbPgmCount;
} cy_stc_lvds_loopback_config_t;

typedef struct
{
    uint32_t dataWord0;
    uint32_t dataWord1;
    uint32_t dataWord2;
    uint32_t dataWord3;
} cy_stc_lvds_loopback_mem_t;

extern cy_stc_hbdma_channel_t lvdsLbPgmChannel;

void Cy_LVDS_InitLbPgm(cy_stc_hbdma_buff_status_t *buffStat,
                       cy_stc_lvds_loopback_config_t *lbPgmConfig);
void HbDma_Cb_Loopback(cy_stc_hbdma_channel_t *handle,
                       cy_en_hbdma_cb_type_t type,
                       cy_stc_hbdma_buff_status_t *pbufStat,
                       void *userCtx);

void Cy_USB_AppInit(cy_stc_usb_app_ctxt_t *pAppCtxt,
                    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                    DMAC_Type *pCpuDmacBase,
                    DW_Type *pCpuDw0Base,
                    DW_Type *pCpuDw1Base,
                    cy_stc_hbdma_mgr_context_t *pHbDmaMgrCtxt);

void Cy_USB_AppRegisterCallback(cy_stc_usb_app_ctxt_t *pAppCtxt);
uint32_t *Cy_USB_CalculateEpmAddr(uint32_t endpNum,
        cy_en_usb_endp_dir_t endpDirection);

void Cy_USB_AppSetCfgCallback(void *pAppCtxt,
                              cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                              cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppBusResetCallback(void *pAppCtxt,
                                cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppBusResetDoneCallback(void *pAppCtxt,
                                    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                    cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppBusSpeedCallback(void *pAppCtxt,
                                cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppSetupCallback(void *pAppCtxt,
                             cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                             cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppSuspendCallback(void *pAppCtxt,
                               cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppResumeCallback (void *pAppCtxt,
                               cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppSetIntfCallback(void *pAppCtxt,
                               cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppL1SleepCallback(void *pUsbApp,
                               cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppL1ResumeCallback(void *pUsbApp,
                                cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppZlpCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                           cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppSlpCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                           cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppSetFeatureCallback(void *pUsbApp,
                                  cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                  cy_stc_usb_cal_msg_t *pMsg);
void Cy_USB_AppClearFeatureCallback(void *pUsbApp,
                                  cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                  cy_stc_usb_cal_msg_t *pMsg);
/* Function to register all USB descriptors with the stack. */
void CyApp_RegisterUsbDescriptors(cy_stc_usb_app_ctxt_t *pAppCtxt,
                                    cy_en_usb_speed_t usbSpeed);
void Cy_USB_AppQueueRead (cy_stc_usb_app_ctxt_t *pAppCtxt,
        uint8_t endpNumber, uint8_t *pBuffer, uint16_t dataSize);
uint16_t Cy_USB_AppReadShortPacket(cy_stc_usb_app_ctxt_t *pAppCtxt,
        uint8_t endpNumber, uint16_t pktSize);
void Cy_USB_AppQueueWrite (cy_stc_usb_app_ctxt_t *pAppCtxt,
        uint8_t endpNumber, uint8_t *pBuffer, uint16_t dataSize);
void Cy_USB_AppInitDmaIntr(uint32_t endpNumber,
        cy_en_usb_endp_dir_t endpDirection,
        cy_israddress userIsr);
void Cy_USB_AppClearDmaInterrupt(cy_stc_usb_app_ctxt_t *pAppCtxt,
        uint32_t endpNumber, cy_en_usb_endp_dir_t endpDirection);
void CyUvcAppHandleSendCompletion(cy_stc_usb_app_ctxt_t *pUsbApp);
void UvcDataWire_ISR(void);

/* Enable the USB data connection. */
bool UsbSSConnectionEnable(cy_stc_usb_app_ctxt_t *pAppCtxt);

/* Disable the USB data connection. */
void UsbSSConnectionDisable(cy_stc_usb_app_ctxt_t *pAppCtxt);

/* Initialize the LVDS/LVCMOS interface to receive the video data through. */
void InitLvdsInterface(void);

/* Configure USB endpoints based on the settings provided in the endpoint descriptor. */
void Cy_USB_AppConfigureEndp(cy_stc_usb_usbd_ctxt_t *pUsbdCtxt, uint8_t *pEndpDscr);

/* Configure application level DMA resources corresponding to a USB endpoint. */
void Cy_USB_AppSetupEndpDmaParams(cy_stc_usb_app_ctxt_t *pUsbApp, uint8_t *pEndpDscr);

/* Initialize the PDM IP to receive data from PDM microphone. */
void MxPdmInit(void);

/* De-initialize the PDM IP. */
void MxPdmDeinit(void);

/* Enable or disable the interrupt handlers for the DataWire channels reading
 * data out from the PDM receive FIFOs.
 */
void Cy_USB_App_PDM_InitDmaIntr(bool enable);

/* Interrupt service routine for completion of data transfer on USB 2.x
 * IN endpoint used for audio streaming.
 */
void Cy_PDM_InEpDma_ISR(void);

/* Initialize UAC application context structures. */
void Cy_UAC_AppInit(cy_stc_usb_app_ctxt_t *pAppCtxt);

/* Queue a read using DataWire channels from the PDM receive FIFO. */
void Cy_PDM_QueuePDMRead(cy_stc_usb_app_ctxt_t *pAppCtxt, uint32_t dataLength);

/* Handler for SET_INTERFACE requests addressed to the UAC streaming interface. */
void Cy_App_SetUACIntfHandler(cy_stc_usb_app_ctxt_t *pAppCtxt, uint8_t altSetting);

/* Function to print any new USB event log data since the last call. */
void AppPrintUsbEventLog(cy_stc_usb_app_ctxt_t *pAppCtxt, cy_stc_usbss_cal_ctxt_t *pSSCal);

#if defined(__cplusplus)
}
#endif

#endif /* _CY_USB_APP_H_ */

/* End of File */

