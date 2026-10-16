/***************************************************************************//**
* \file cy_usb_app.c
* \version 1.0
*
* Implements the USB data handling part of the USB Video Class application.
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
#include "cy_device.h"
#include "cy_usb_common.h"
#include "cy_usbhs_cal_drv.h"
#include "cy_usbss_cal_drv.h"
#include "cy_hbdma.h"
#include "cy_hbdma_mgr.h"
#include "cy_usb_usbd.h"
#include "cy_usbhs_dw_wrapper.h"
#include "cy_usb_uvc_device.h"
#include "cy_usb_app.h"
#include "cy_debug.h"
#include "cy_lvds.h"

/* GPIF State Machine number */
#if PORT1_EN
uint8_t cy_u3v_smNo = 1;
#else
uint8_t cy_u3v_smNo = 0;
#endif

/* Buffer counter for different resolution */
uint16_t cy_uvc_commitLength = 0, cy_uvc_buffer_counter = 1;

/* Default Frame Index is  4K  as 1st index */
uint16_t cy_uvc_currentFrameIndex = CY_USB_UVC_SS_4K_FRAME_INDEX;
uint16_t cy_usb_full_buffer_no = CY_USB_FULL_BUFFER_NO_3840_2160;
uint16_t cy_usb_no_bytes_last_buffer = CY_USB_NO_BYTE_LAST_BUFFER_3840_2160;
uint16_t cy_usb_colorbar_size = COLORBAR_BAND_COUNT_4K;
extern cy_stc_smif_context_t smifContext;
#if LVDS_LB_EN

#if INMD_EN
#error "Insert metadata feature is not compatible with LVDS IP based data loopback."
#endif /* INMD_EN */

uint32_t lvdsConsCount = 0;
cy_stc_hbdma_channel_t lvdsLbPgmChannel;

#endif /* LVDS_LB_EN */

/* UVC Probe Control Settings for a USB 3.0 connection. */

/* 3840*2160 @30 fps */
USB3_DESC_ATTRIBUTES uint8_t cy_uvc_probectrl_4K[CY_USB_UVC_MAX_PROBE_SETTING];
uint8_t cy_uvc_probectrl_4K_[]= {
    0x00, 0x00,                         /* bmHint : no hit */
    0x01,                               /* Use 1st Video format index */
    CY_USB_UVC_SS_4K_FRAME_INDEX,       /* Use 1st Video frame index */
    //0x15, 0x16, 0x05, 0x00,             /* Desired frame interval in the unit of 100ns: 30 fps */
    0x0A, 0x8B, 0x02, 0x00,             /* Desired frame interval in the unit of 100ns: 60 fps */
    0x00, 0x00,                         /* Key frame rate in key frame/video frame units */
    0x00, 0x00,                         /* PFrame rate in PFrame / key frame units */
    0x00, 0x00,                         /* Compression quality control */
    0x00, 0x00,                         /* Window size for average bit rate*/
    0x00, 0x00,                         /* Internal video streaming i/f latency in ms */
    0x00, 0x20, 0xFD, 0x00,             /* Max video frame size in bytes: 3840*2160*2 = 0x00FD2000*/
    0x20, 0xF0, 0x00, 0x00,             /* No. of bytes device can rx in single payload = 61472 bytes */
    0x00, 0x60, 0xE3, 0x16,             /* Device Clock */
    0x00, 0x00, 0x00, 0x00              /* Framing and format information. */
};

/* 1280*720 @30 fps */
USB3_DESC_ATTRIBUTES uint8_t cy_uvc_probectrl_720p[CY_USB_UVC_MAX_PROBE_SETTING];
uint8_t cy_uvc_probectrl_720p_[]= {
    0x00, 0x00,                         /* bmHint : no hit */
    0x01,                               /* Use 1st Video format index */
    CY_USB_UVC_SS_720P_FRAME_INDEX,     /* Use 2nd Video frame index */
    0x15, 0x16, 0x05, 0x00,             /* Desired frame interval in the unit of 100ns: 30 fps */
    0x00, 0x00,                         /* Key frame rate in key frame/video frame units */
    0x00, 0x00,                         /* PFrame rate in PFrame / key frame units */
    0x00, 0x00,                         /* Compression quality control */
    0x00, 0x00,                         /* Window size for average bit rate*/
    0x00, 0x00,                         /* Internal video streaming i/f latency in ms */
    0x00, 0x20, 0x1C, 0x00,             /* Max video frame size in bytes: 1280*720*2 = 0x001C2000 */
    0x20, 0xF0, 0x00, 0x00,             /* No. of bytes device can rx in single payload = 61472 bytes */
    0x00, 0x60, 0xE3, 0x16,             /* Device Clock */
    0x00, 0x00, 0x00, 0x00              /* Framing and format information. */
};

/* 640*480  @15 fps */
USB3_DESC_ATTRIBUTES uint8_t cy_uvc_probectrl_VGA[CY_USB_UVC_MAX_PROBE_SETTING];
uint8_t cy_uvc_probectrl_VGA_[] = {
    0x00, 0x00,                         /* bmHint : no hit */
    0x01,                               /* Use 1st Video format index */
    CY_USB_UVC_SS_VGA_FRAME_INDEX,      /* Use 3rd Video frame index */
    0x2A, 0x2C, 0x0A, 0x00,             /* Desired frame interval in the unit of 100ns: 15 fps */
    0x00, 0x00,                         /* Key frame rate in key frame/video frame units*/
    0x00, 0x00,                         /* PFrame rate in PFrame / key frame units */
    0x00, 0x00,                         /* Compression quality control */
    0x00, 0x00,                         /* Window size for average bit rate */
    0x00, 0x00,                         /* Internal video streaming i/f latency in ms */
    0x00, 0x60, 0x09, 0x00,             /* Max video frame size in bytes: 640*480*2 = 0x00096000 */
    0x20, 0xF0, 0x00, 0x00,             /* No. of bytes device can rx in single payload = 61472 bytes */
    0x00, 0x60, 0xE3, 0x16,             /* Device Clock */
    0x00, 0x00, 0x00, 0x00              /* Framing and format information. */
};

/* USBHS: 640*480  @15 fps */
USB3_DESC_ATTRIBUTES uint8_t cy_uvc_probectrl_HS_VGA[CY_USB_UVC_MAX_PROBE_SETTING];
uint8_t cy_uvc_probectrl_HS_VGA_[] = {
    0x00, 0x00,                         /* bmHint : no hit */
    0x01,                               /* Use 1st Video format index */
    CY_USB_UVC_HS_VGA_FRAME_INDEX,      /* Use 1st Video frame index */
    0x2A, 0x2C, 0x0A, 0x00,             /* Desired frame interval in the unit of 100ns: 15 fps */
    0x00, 0x00,                         /* Key frame rate in key frame/video frame units*/
    0x00, 0x00,                         /* PFrame rate in PFrame / key frame units */
    0x00, 0x00,                         /* Compression quality control */
    0x00, 0x00,                         /* Window size for average bit rate */
    0x00, 0x00,                         /* Internal video streaming i/f latency in ms */
    0x00, 0x60, 0x09, 0x00,             /* Max video frame size in bytes: 640*480*2 = 0x00096000 */
    0x20, 0xF0, 0x00, 0x00,             /* No. of bytes device can rx in single payload = 61472 bytes */
    0x00, 0x60, 0xE3, 0x16,             /* Device Clock */
    0x00, 0x00, 0x00, 0x00              /* Framing and format information. */
};

/* Video Probe Commit Control */
USB3_DESC_ATTRIBUTES uint8_t cy_uvc_commitctrl[CY_USB_UVC_MAX_PROBE_SETTING_ALIGNED];

/* Whether SET_CONFIG is complete or not. */
static volatile bool cy_uvc_devconfigured = false;
static volatile bool cy_uvc_IsApplnActive = false;

/* UVC Header */
USB3_DESC_ATTRIBUTES uint8_t cy_uvc_header[CY_USB_UVC_MAX_HEADER];
uint8_t cy_uvc_header_[] = {
    32,                                 /* Header Length */
    0x8C,                               /* Bit field header field */
    0x00, 0x00, 0x00, 0x00,             /* Presentation time stamp field */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, /* Source clock reference field */
    0x00, 0x00, 0x00, 0x00, 0x00,       /* Zero padding for 32 byte align */
    0x00, 0x00, 0x00, 0x00, 0x00,       /* Zero padding for 32 byte align */
    0x00, 0x00, 0x00, 0x00, 0x00,       /* Zero padding for 32 byte align */
    0x00, 0x00, 0x00, 0x00, 0x00        /* Zero padding for 32 byte align */
};

HBDMA_BUF_ATTRIBUTES uint32_t Ep0TestBuffer[32U];
HBDMA_BUF_ATTRIBUTES uint32_t SetSelDataBuffer[8];

void
CyU3vAppGpifIntr(void *pApp)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt;
    pAppCtxt = (cy_stc_usb_app_ctxt_t*)pApp;

    /* Reset the DMA channel through which data is received from the LVDS side. */
    Cy_HBDma_Channel_Reset(pAppCtxt->hbBulkInChannel);

    /* Flush and reset the endpoint and clear the STALL bit. */
    Cy_USBD_FlushEndp(pAppCtxt->pUsbdCtxt, pAppCtxt->uvcInEpNum, CY_USB_ENDP_DIR_IN);
    Cy_USBD_ResetEndp(pAppCtxt->pUsbdCtxt, pAppCtxt->uvcInEpNum, CY_USB_ENDP_DIR_IN, false);
    Cy_USB_USBD_EndpSetClearStall(pAppCtxt->pUsbdCtxt, pAppCtxt->uvcInEpNum,CY_USB_ENDP_DIR_IN, false);
    pAppCtxt->uvcPendingBufCnt = 0;
    Cy_USBD_SendAckSetupDataStatusStage(pAppCtxt->pUsbdCtxt);

    return;
}

#if LVDS_LB_EN
void Cy_LVDS_InitLbPgm(cy_stc_hbdma_buff_status_t *buffStat, cy_stc_lvds_loopback_config_t *lbPgmConfig)
{
    cy_stc_lvds_loopback_mem_t lbPgm;
    lbPgm.dataWord0 =   ((0x00000001) |
                        (lbPgmConfig->start << 1) |
                        (lbPgmConfig->end << 2) |
                        (lbPgmConfig->dataMode << 4) |
                        (lbPgmConfig->repeatCount << 8) |
                        (lbPgmConfig->dataSrc << 20));
    lbPgm.dataWord1 =   ((lbPgmConfig->ctrlByte) |
                        (lbPgmConfig->ctrlBusVal << 12));
    lbPgm.dataWord2 = lbPgmConfig->dataL;
    lbPgm.dataWord3 = lbPgmConfig->dataH;
    lbPgmConfig->pBuffer = buffStat->pBuffer + lbPgmConfig->lbPgmCount * 16;
    memcpy(lbPgmConfig->pBuffer, &lbPgm, 16);
    lbPgmConfig->lbPgmCount += 1;
}

void Cy_LVDS_CommitColorbarData(void)
{
    uint32_t loop = 0, lineCount = 0;
    cy_stc_hbdma_buff_status_t buffStat;
    cy_stc_lvds_loopback_config_t lbPgmConfig = 
    {
        .lbPgmCount = 0,
        .pBuffer = NULL,
        .start = 0,
        .end = 0,
        .dataMode = 0x00,
        .dataSrc = 0x00,
        .ctrlByte = 0x01,
        .repeatCount = 0x0001,
        .dataL = 0x00000000,
        .dataH = 0xDEADBEEF,
        .ctrlBusVal = 0x00000000
    };

    if (Cy_HBDma_Channel_GetBuffer(&lvdsLbPgmChannel, &buffStat) != CY_HBDMA_MGR_SUCCESS) {
        DBG_APP_ERR("GetLpbkBuf 1 failed\r\n");
        return;
    }

    lbPgmConfig.pBuffer = buffStat.pBuffer;
    
    /* Start command */
    lbPgmConfig.start = 1;
    Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
    
    /* Few cycles of IDLE */
    lbPgmConfig.start = 0;
    for(loop = 0; loop < 10; loop++)
    {
        Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
    }

    /* DATA control byte*/
    lbPgmConfig.ctrlByte = 0x80;
    for (lineCount = 0; lineCount < (480 / cy_usb_colorbar_size); lineCount++)
    {
        /* BAND1 of colorbar */
        lbPgmConfig.dataL = BAND1_COLOR_YUYV;
        lbPgmConfig.dataH = BAND1_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND2 of colorbar */
        lbPgmConfig.dataL = BAND2_COLOR_YUYV;
        lbPgmConfig.dataH = BAND2_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND3 of colorbar */
        lbPgmConfig.dataL = BAND3_COLOR_YUYV;
        lbPgmConfig.dataH = BAND3_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND4 of colorbar */
        lbPgmConfig.dataL = BAND4_COLOR_YUYV;
        lbPgmConfig.dataH = BAND4_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND5 of colorbar */
        lbPgmConfig.dataL = BAND5_COLOR_YUYV;
        lbPgmConfig.dataH = BAND5_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND6 of colorbar */
        lbPgmConfig.dataL = BAND6_COLOR_YUYV;
        lbPgmConfig.dataH = BAND6_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND7 of colorbar */
        lbPgmConfig.dataL = BAND7_COLOR_YUYV;
        lbPgmConfig.dataH = BAND7_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }

        /* BAND8 of colorbar */
        lbPgmConfig.dataL = BAND8_COLOR_YUYV;
        lbPgmConfig.dataH = BAND8_COLOR_YUYV;
        for(loop = 0; loop < cy_usb_colorbar_size; loop++)
        {
            Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);
        }
    }

    /* End of program command */    
    lbPgmConfig.end = 0x1;
    lbPgmConfig.ctrlByte = 0x01;
    lbPgmConfig.repeatCount = 0x00000000;
    Cy_LVDS_InitLbPgm(&buffStat, &lbPgmConfig);

    /* Commit the data into buffer */
    buffStat.count = 16 * (lbPgmConfig.lbPgmCount);
    Cy_HBDma_Channel_CommitBuffer(&lvdsLbPgmChannel, &buffStat);
}
#endif /*LVDS_LB_EN*/

/*
 * Function: Cy_USB_UvcAddHeader()
 * Description:  UVC header addition function
 * Parameter: Buffer pointer,Frame ID
 * return: void
 */
void Cy_USB_UvcAddHeader(
    uint8_t *buffer_p, /* Buffer pointer */
    uint8_t frameInd   /* EOF or normal frame indication */
)
{
    /* Copy header to buffer */
    memcpy(buffer_p, (uint8_t *)cy_uvc_header, CY_USB_UVC_MAX_HEADER);

    /* Check if last packet of the frame. */
    if (frameInd == CY_USB_UVC_HEADER_EOF)
    {
        /* Modify UVC header to toggle Frame ID */
        cy_uvc_header[1] ^= CY_USB_UVC_HEADER_FRAME_ID;

        /* Indicate End of Frame in the buffer */
        buffer_p[1] |= CY_USB_UVC_HEADER_EOF;
    }
} /* end of function */

/*
 * Function: Cy_USB_AppDisableEndpDma()
 * Description: This function de-inits all active USB DMA channels as part of USB disconnect process.
 * Parameter: cy_stc_usb_app_ctxt_t *
 * return: void
 */
void
Cy_USB_AppDisableEndpDma (cy_stc_usb_app_ctxt_t *pAppCtxt)
{
    uint8_t i;

    /* On USB 2.x connections, make sure the DataWire channels are disabled and reset. */
    if (pAppCtxt->devSpeed <= CY_USBD_USB_DEV_HS) {
        for (i = 1; i < CY_USB_MAX_ENDP_NUMBER; i++) {
            if (pAppCtxt->endpInDma[i].valid) {
                /* DeInit the DMA channel and disconnect the triggers. */
                Cy_USBHS_App_DisableEpDmaSet(&(pAppCtxt->endpInDma[i]));
            }

            if (pAppCtxt->endpOutDma[i].valid) {
                /* DeInit the DMA channel and disconnect the triggers. */
                Cy_USBHS_App_DisableEpDmaSet(&(pAppCtxt->endpOutDma[i]));
            }
        }
    }

        /* Disable and destroy the High BandWidth DMA channels. */
    if (pAppCtxt->hbBulkInChannel != NULL) {
        Cy_HBDma_Channel_Disable(pAppCtxt->hbBulkInChannel);
        Cy_HBDma_Channel_Destroy(pAppCtxt->hbBulkInChannel);
        pAppCtxt->hbBulkInChannel = NULL;

        /* Flush the EPM in case of USB 3.x connection. */
        if (pAppCtxt->devSpeed >= CY_USBD_USB_DEV_SS_GEN1) {
            Cy_USBD_FlushEndp(pAppCtxt->pUsbdCtxt, pAppCtxt->uvcInEpNum, CY_USB_ENDP_DIR_IN);
        }
    }

#if AUDIO_IF_EN
    if (pAppCtxt->pPDMToUsbChn != NULL) {
        Cy_HBDma_Channel_Disable(pAppCtxt->pPDMToUsbChn);
        Cy_HBDma_Channel_Destroy(pAppCtxt->pPDMToUsbChn);
        pAppCtxt->pPDMToUsbChn = NULL;

        /* Flush the EPM in case of USB 3.x connection. */
        if (pAppCtxt->devSpeed >= CY_USBD_USB_DEV_SS_GEN1) {
            Cy_USBD_FlushEndp(pAppCtxt->pUsbdCtxt, UAC_IN_ENDPOINT, CY_USB_ENDP_DIR_IN);
        }
    }
#endif /* AUDIO_IF_EN */

#if LVDS_LB_EN
    pAppCtxt->uvcFlowCtrlFlag = false;
    lvdsConsCount = 0;
    Cy_HBDma_Channel_Reset(&lvdsLbPgmChannel);
    Cy_HBDma_Channel_Enable(&lvdsLbPgmChannel, 0);
#endif /* LVDS_LB_EN */
}

/*
 * Function: Cy_USB_UvcSetCurRqtHandler()
 * Description: This function handles the SET_CUR request addresses to the
 * UVC video streaming interface.
 * Parameter: pAppCtxt, wLength
 * return: void
 */
void Cy_USB_UvcSetCurRqtHandler (cy_stc_usb_app_ctxt_t *pAppCtxt, uint16_t wLength)
{
    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt = pAppCtxt->pUsbdCtxt;
    cy_en_hbdma_mgr_status_t mgrStatus;
    cy_en_usbd_ret_code_t retStatus;
    uint16_t loopCnt = 250u;
    cy_stc_usbd_app_msg_t xMsg;
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;

    DBG_APP_INFO("UVC_UVC_SET_CUR_REQ\r\n");

    /* Read the data out commitctrl buffer */
    retStatus = Cy_USB_USBD_RecvEndp0Data(pUsbdCtxt, cy_uvc_commitctrl, wLength);
    if (retStatus == CY_USBD_STATUS_SUCCESS)
    {
        /* Wait until receive DMA transfer has been completed. */
        while ((!Cy_USBD_IsEp0ReceiveDone(pUsbdCtxt)) && (loopCnt--)) {
            Cy_SysLib_DelayUs(10);
        }
        if (!Cy_USBD_IsEp0ReceiveDone(pUsbdCtxt)) {
            DBG_APP_ERR("SET_CUR data timed out\r\n");
            Cy_USB_USBD_RetireRecvEndp0Data(pUsbdCtxt);
            Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, 0x00, CY_USB_ENDP_DIR_IN, TRUE);
            return;
        }

        cy_uvc_currentFrameIndex = cy_uvc_commitctrl[3];
        DBG_APP_INFO("SET_CUR cy_uvc_currentFrameIndex:%x\r\n", cy_uvc_currentFrameIndex);

        /* Reset the Counter */
        cy_uvc_buffer_counter = 1;

        if (pAppCtxt->devSpeed > CY_USBD_USB_DEV_HS)
        {
            /* Copy the relevant settings from the host provided data into the
               active data structure. */
            if (cy_uvc_currentFrameIndex == CY_USB_UVC_SS_720P_FRAME_INDEX)
            {
                memcpy(&cy_uvc_probectrl_720p[2], &cy_uvc_commitctrl[2], CY_USB_UVC_PROBE_CONTROL_UPDATE_SIZE);
                cy_usb_full_buffer_no = CY_USB_FULL_BUFFER_NO_1280_720;
                cy_usb_colorbar_size = COLORBAR_BAND_COUNT_720P;
                cy_usb_no_bytes_last_buffer = CY_USB_NO_BYTE_LAST_BUFFER_1280_720;
            }
            else if (cy_uvc_currentFrameIndex == CY_USB_UVC_SS_VGA_FRAME_INDEX)
            {
                memcpy(&cy_uvc_probectrl_VGA[2], &cy_uvc_commitctrl[2], CY_USB_UVC_PROBE_CONTROL_UPDATE_SIZE);
                cy_usb_full_buffer_no = CY_USB_FULL_BUFFER_NO_640_480;
                cy_usb_colorbar_size = COLORBAR_BAND_COUNT_480P;
                cy_usb_no_bytes_last_buffer = CY_USB_NO_BYTE_LAST_BUFFER_640_480;
            }
            else if (cy_uvc_currentFrameIndex == CY_USB_UVC_SS_4K_FRAME_INDEX)
            {
                memcpy(&cy_uvc_probectrl_4K[2], &cy_uvc_commitctrl[2], CY_USB_UVC_PROBE_CONTROL_UPDATE_SIZE);
                cy_usb_full_buffer_no = CY_USB_FULL_BUFFER_NO_3840_2160;
                cy_usb_colorbar_size = COLORBAR_BAND_COUNT_4K;
                cy_usb_no_bytes_last_buffer = CY_USB_NO_BYTE_LAST_BUFFER_3840_2160;
            }
            else
            {
                DBG_APP_ERR("Error FrameIndex\r\n");
                cy_uvc_currentFrameIndex = CY_USB_UVC_SS_4K_FRAME_INDEX;
            }
        }
        else
        {
            if (cy_uvc_currentFrameIndex == CY_USB_UVC_HS_VGA_FRAME_INDEX)
            {
                memcpy(&cy_uvc_probectrl_HS_VGA[2], &cy_uvc_commitctrl[2], CY_USB_UVC_PROBE_CONTROL_UPDATE_SIZE);
                cy_usb_full_buffer_no = CY_USB_FULL_BUFFER_NO_640_480;
                cy_usb_colorbar_size = COLORBAR_BAND_COUNT_480P;
                cy_usb_no_bytes_last_buffer = CY_USB_NO_BYTE_LAST_BUFFER_640_480;
            }
            else
            {
                DBG_APP_ERR("Error FrameIndex\r\n");
                cy_uvc_currentFrameIndex = CY_USB_UVC_HS_VGA_FRAME_INDEX;
            }
        }

//#if INMD_EN
//        Cy_LVDS_GpifClearFwTrig(LVDSSS_LVDS,cy_u3v_smNo);
//#endif /* INMD_EN */

        if (pAppCtxt->devSpeed >= CY_USBD_USB_DEV_SS_GEN1) {
            /* Allow data from multiple DMA buffers to be combined into one burst. */
            Cy_USBD_SetEpBurstMode(pAppCtxt->pUsbdCtxt, pAppCtxt->uvcInEpNum, CY_USB_ENDP_DIR_IN, true);
        }

        mgrStatus = Cy_HBDma_Channel_Enable(pAppCtxt->hbBulkInChannel, 0);
        DBG_APP_INFO("HB-DMA InChnEnable status: %x\r\n", mgrStatus);

        cy_uvc_IsApplnActive = true;

        if (mgrStatus == CY_HBDMA_MGR_SUCCESS) {
            /* Notify the VCOM task that VBus debounce is complete. */
            xMsg.type = CY_USB_UVC_VIDEO_STREAMING_START;
            xQueueSendFromISR(pAppCtxt->uvcMsgQueue, &(xMsg), &(xHigherPriorityTaskWoken));
        }
    }
    else
    {
        DBG_APP_ERR("Error RecvEndp0Data\r\n");
    }
}

/*
 * Function: Cy_USB_UvcDeviceTaskHandler()
 * Description: This function handles Streaming UVC Device.
 * Parameter: pTaskParam
 * return: void
 *
 * NOTE : The actual data forwarding from sensor to USB host is done from the DMA and GPIF callback
       functions. The thread is only responsible for checking for streaming start/stop conditions.
 */

void ReportStatus();
void Cy_USB_UvcDeviceTaskHandler(void *pTaskParam)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt = (cy_stc_usb_app_ctxt_t *)pTaskParam;
    cy_stc_usbd_app_msg_t queueMsg;
    BaseType_t xStatus;

    /* Reset Frame Id in UVC Header */
    cy_uvc_header_[1] = CY_USB_UVC_HEADER_DEFAULT_BFH;
    DBG_APP_INFO("UvcDeviceThreadCreated\r\n");
    vTaskDelay(100);

    /* Initialize the LVDS interface. */
    InitLvdsInterface(); 

    /*  All UVC control structures copied from flash to the HBW SRAM buffers */
    memcpy (cy_uvc_probectrl_4K, cy_uvc_probectrl_4K_, sizeof(cy_uvc_probectrl_4K_));
    memcpy (cy_uvc_probectrl_720p, cy_uvc_probectrl_720p_, sizeof(cy_uvc_probectrl_720p_));
    memcpy (cy_uvc_probectrl_VGA, cy_uvc_probectrl_VGA_, sizeof(cy_uvc_probectrl_VGA_));
    memcpy (cy_uvc_probectrl_HS_VGA, cy_uvc_probectrl_HS_VGA_, sizeof(cy_uvc_probectrl_HS_VGA_));
    memcpy (cy_uvc_header, cy_uvc_header_, sizeof(cy_uvc_header_));

    /* If VBus is present, enable the USB connection. */
    pAppCtxt->vbusPresent = (Cy_GPIO_Read(VBUS_DETECT_GPIO_PORT, VBUS_DETECT_GPIO_PIN) == VBUS_DETECT_STATE);
    if (pAppCtxt->vbusPresent) {
        UsbSSConnectionEnable(pAppCtxt);
    }

    for (;;)
    {
        /*
         * Wait until some data is received from the queue.
         * Timeout after 100 ms.
         */
        xStatus = xQueueReceive(pAppCtxt->uvcMsgQueue, &queueMsg, 100);
        if (xStatus != pdPASS) {
            continue;
        }

        switch (queueMsg.type) {
            case CY_USB_UVC_VBUS_CHANGE_INTR:
                /* Start the debounce timer. */
                xTimerStart(pAppCtxt->vbusDebounceTimer, 0);
                break;

            case CY_USB_UVC_VBUS_CHANGE_DEBOUNCED:
                /* Check whether VBus state has changed. */
                pAppCtxt->vbusPresent = (Cy_GPIO_Read(VBUS_DETECT_GPIO_PORT, VBUS_DETECT_GPIO_PIN) == VBUS_DETECT_STATE);

                if (pAppCtxt->vbusPresent) {
                    if (!pAppCtxt->usbConnected) {
                        DBG_APP_INFO("Enabling USB connection due to VBus detect\r\n");
                        UsbSSConnectionEnable(pAppCtxt);
                    }
                } else {
                    if (pAppCtxt->usbConnected) {
                        Cy_USB_AppDisableEndpDma(pAppCtxt);
                        DBG_APP_INFO("Disabling USB connection due to VBus removal\r\n");
                        UsbSSConnectionDisable(pAppCtxt);
                    }
                }
                break;

            case CY_USB_UVC_VIDEO_STREAMING_START:
                DBG_APP_INFO("****Start CY_USB_UVC_VIDEO_STREAMING_START\r\n");
                while(0)
                {
                    spi_axi_wr(SMIF0, &smifContext, 0x0010000C, 0x03);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD0->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD1->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD2->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD3->VARW0);
                    spi_axi_wr(SMIF0, &smifContext, 0x0010000C, 0x01);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD0->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD1->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD2->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD3->VARW0);

                    spi_axi_wr(SMIF0, &smifContext, 0x0010000D, 0x25);
                    spi_axi_wr(SMIF0, &smifContext, 0x0010000C, 0x03);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD0->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD1->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD2->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD3->VARW0);
                    spi_axi_wr(SMIF0, &smifContext, 0x0010000C, 0x01);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD0->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD1->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD2->VARW0);
                    DBG_APP_INFO("****VARW0=%x\n",LVDSSS_LVDS_THREAD3->VARW0);
                    
                }
    spi_axi_wr(SMIF0, &smifContext, 0x00100020, 2);
    char axi_data = spi_axi_rd(SMIF0, &smifContext, 0x0010000a);
    DBG_APP_INFO("TRAINING_BLK_SEQ_BYTE_P0_OFFSET_8: %x\r\n", axi_data);
                ReportStatus();
#if LVDS_LB_EN
                if ((lvdsConsCount == 0) && (cy_uvc_IsApplnActive == true))
                {
                    DBG_APP_INFO("****Start loopback\r\n");
                    pAppCtxt->uvcFlowCtrlFlag = false;
                    Cy_HBDma_Channel_Enable(&lvdsLbPgmChannel, 0);
                    Cy_LVDS_CommitColorbarData();
                    Cy_LVDS_CommitColorbarData(); 
                    LVDSSS_LVDS->GPIF[1].GPIF_WAVEFORM_CTRL_STAT |= LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_CPU_LAMBDA_Msk;
                }
#endif /* LVDS_LB_EN */
                Cy_USBD_AddEvtToLog(pAppCtxt->pUsbdCtxt, CY_USB_UVC_EVT_VSTREAM_START);
                break;

            case CY_USB_UVC_DEVICE_SET_CUR_RQT:
                Cy_USB_UvcSetCurRqtHandler(pAppCtxt, queueMsg.data[0]);
                Cy_USBD_AddEvtToLog(pAppCtxt->pUsbdCtxt, CY_USB_UVC_EVT_SET_CUR_REQ);
                break;

            default:
                break;
        }
    }
    
}

/*
 * Function: Cy_USB_PrintEvtLogTimerCb()
 * Description: This Function will be called when timer expires.
 *              This function print event log.
 * Parameter: xTimer
 * return: void
 */
void
Cy_USB_PrintEvtLogTimerCb(TimerHandle_t xTimer)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt;

    /* retrieve pAppCtxt */
    pAppCtxt = ( cy_stc_usb_app_ctxt_t *)pvTimerGetTimerID(xTimer);
    if (pAppCtxt->devState == CY_USB_DEVICE_STATE_CONFIGURED) {
        /*
         * Print out the contents of the USB event log buffer which has
         * logged event related to enumeration and line training.
         */
        AppPrintUsbEventLog(pAppCtxt, pAppCtxt->pUsbdCtxt->pSsCalCtxt);
    }
}   /* end of function() */



/*
 * Function: Cy_USB_VbusDebounceTimerCallback()
 * Description: Timer used to do debounce on VBus changed interrupt notification.
 *
 * Parameter:
 *      xTimer: RTOS timer handle.
 * return: void
 */
void
Cy_USB_VbusDebounceTimerCallback (TimerHandle_t xTimer)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt = (cy_stc_usb_app_ctxt_t *)pvTimerGetTimerID(xTimer);
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    cy_stc_usbd_app_msg_t xMsg;

    DBG_APP_INFO("VbusDebounce_CB\r\n");
    if (pAppCtxt->vbusChangeIntr) {
        /* Notify the VCOM task that VBus debounce is complete. */
        xMsg.type = CY_USB_UVC_VBUS_CHANGE_DEBOUNCED;
        xQueueSendFromISR(pAppCtxt->uvcMsgQueue, &(xMsg), &(xHigherPriorityTaskWoken));

        /* Clear and re-enable the interrupt. */
        pAppCtxt->vbusChangeIntr = false;
        Cy_GPIO_ClearInterrupt(VBUS_DETECT_GPIO_PORT, VBUS_DETECT_GPIO_PIN);
        Cy_GPIO_SetInterruptMask(VBUS_DETECT_GPIO_PORT, VBUS_DETECT_GPIO_PIN, 1);
    }
}   /* end of function  */

/*
 * Function: Cy_USB_AppInit()
 * Description: This function Initializes application related data structures,
 *              register callback and creates queue and task for device
 *              function.
 * Parameter: cy_stc_usb_app_ctxt_t, cy_stc_usb_usbd_ctxt_t, DMAC_Type
 *            DW_Type, DW_Type, cy_stc_hbdma_mgr_context_t*
 * return: None.
 * Note: This function should be called after USBD_Init()
 */
void Cy_USB_AppInit(cy_stc_usb_app_ctxt_t *pAppCtxt,
                    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt, DMAC_Type *pCpuDmacBase,
                    DW_Type *pCpuDw0Base, DW_Type *pCpuDw1Base,
                    cy_stc_hbdma_mgr_context_t *pHbDmaMgrCtxt)
{
    uint32_t index;
    BaseType_t status = pdFALSE;
    cy_stc_app_endp_dma_set_t *pEndpInDma;
    cy_stc_app_endp_dma_set_t *pEndpOutDma;

    pAppCtxt->devState = CY_USB_DEVICE_STATE_DISABLE;
    pAppCtxt->prevDevState = CY_USB_DEVICE_STATE_DISABLE;
    pAppCtxt->devSpeed = CY_USBD_USB_DEV_FS;
    pAppCtxt->devAddr = 0x00;
    pAppCtxt->activeCfgNum = 0x00;
    pAppCtxt->prevAltSetting = 0x00;
    pAppCtxt->enumMethod = CY_USB_ENUM_METHOD_FAST;
    pAppCtxt->pHbDmaMgrCtxt = pHbDmaMgrCtxt;

    for (index = 0x00; index < CY_USB_MAX_ENDP_NUMBER; index++)
    {
        pEndpInDma = &(pAppCtxt->endpInDma[index]);
        memset((void *)pEndpInDma, 0, sizeof(cy_stc_app_endp_dma_set_t));

        pEndpOutDma = &(pAppCtxt->endpOutDma[index]);
        memset((void *)pEndpOutDma, 0, sizeof(cy_stc_app_endp_dma_set_t));
    }

    pAppCtxt->pCpuDmacBase = pCpuDmacBase;
    pAppCtxt->pCpuDw0Base = pCpuDw0Base;
    pAppCtxt->pCpuDw1Base = pCpuDw1Base;
    pAppCtxt->pUsbdCtxt = pUsbdCtxt;
    pAppCtxt->uvcPendingBufCnt = 0;
    pAppCtxt->uvcFlowCtrlFlag = false;

    /*
     * Callbacks registered with USBD layer. These callbacks will be called
     * based on appropriate event.
     */
    Cy_USB_AppRegisterCallback(pAppCtxt);

    if (!(pAppCtxt->firstInitDone))
    {
        pAppCtxt->vbusChangeIntr = false;
        pAppCtxt->vbusPresent    = false;
        pAppCtxt->usbConnected   = false;

        /* Create the message queue and register it with the kernel. */
        pAppCtxt->uvcMsgQueue = xQueueCreate(CY_USB_UVC_DEVICE_MSG_QUEUE_SIZE,
                CY_USB_UVC_DEVICE_MSG_SIZE);
        if (pAppCtxt->uvcMsgQueue == NULL) {
            DBG_APP_ERR("QueuecreateFail\r\n");
            return;
        }

        vQueueAddToRegistry(pAppCtxt->uvcMsgQueue, "UVCDeviceMsgQueue");

        /* Create task and check status to confirm task created properly. */
        status = xTaskCreate(Cy_USB_UvcDeviceTaskHandler, "UvcDeviceTask", 2048,
                             (void *)pAppCtxt, 5, &(pAppCtxt->uvcDevicetaskHandle));
        if (status != pdPASS)
        {
            DBG_APP_ERR("TaskcreateFail\r\n");
            return;
        }

#if AUDIO_IF_EN
        Cy_UAC_AppInit(pAppCtxt);
#endif /* AUDIO_IF_EN */

        pAppCtxt->vbusDebounceTimer = xTimerCreate("VbusDebounceTimer", 200, pdFALSE,
                (void *)pAppCtxt, Cy_USB_VbusDebounceTimerCallback);
        if (pAppCtxt->vbusDebounceTimer == NULL) {
            DBG_APP_ERR("TimerCreateFail\r\n");
            return;
        }
        DBG_APP_INFO("VBus debounce timer created\r\n");

        pAppCtxt->evtLogTimer = xTimerCreate("EventLogTimer", 10000, pdTRUE,
                                             (void *)pAppCtxt,
                                             Cy_USB_PrintEvtLogTimerCb);
        if (pAppCtxt->evtLogTimer == NULL) {
            DBG_APP_ERR("evtLogTimer Create Fail\r\n");
            return;
        } else {
            /* Start the debounce timer. */
            DBG_APP_INFO("evtLogTimer Start\r\n");
            xTimerStart(pAppCtxt->evtLogTimer, 0);
        }

        pAppCtxt->firstInitDone = 0x01;
    }

    /* Zero out the EP0 test buffer. */
    memset((uint8_t *)Ep0TestBuffer, 0, sizeof(Ep0TestBuffer));

    return;
} /* end of function. */


/*
 * Function: Cy_USB_AppSetAddressCallback()
 * Description: This Function will be called by USBD layer when
 *              a USB address has been assigned to the device.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void
Cy_USB_AppSetAddressCallback (void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                       cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt = (cy_stc_usb_app_ctxt_t *)pUsbApp;

    /* Update the state variables. */
    pAppCtxt->devState     = CY_USB_DEVICE_STATE_ADDRESS;
    pAppCtxt->prevDevState = CY_USB_DEVICE_STATE_DEFAULT;
    pAppCtxt->devAddr      = pUsbdCtxt->devAddr;
    pAppCtxt->devSpeed     = Cy_USBD_GetDeviceSpeed(pUsbdCtxt);

    /* Check the type of USB connection and register appropriate descriptors. */
    CyApp_RegisterUsbDescriptors(pAppCtxt, pAppCtxt->devSpeed);
}


/*
 * Function: Cy_USB_AppRegisterCallback()
 * Description: This function will register all calback with USBD layer.
 * Parameter: cy_stc_usb_app_ctxt_t.
 * return: None.
 */
void Cy_USB_AppRegisterCallback(cy_stc_usb_app_ctxt_t *pAppCtxt)
{
    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt = pAppCtxt->pUsbdCtxt;

    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_RESET,
                             Cy_USB_AppBusResetCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_RESET_DONE,
                             Cy_USB_AppBusResetDoneCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_BUS_SPEED,
                             Cy_USB_AppBusSpeedCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_SETUP,
                             Cy_USB_AppSetupCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_SUSPEND,
                             Cy_USB_AppSuspendCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_RESUME,
                             Cy_USB_AppResumeCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_SET_CONFIG,
                             Cy_USB_AppSetCfgCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_SET_INTF,
                             Cy_USB_AppSetIntfCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_L1_SLEEP,
                             Cy_USB_AppL1SleepCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_L1_RESUME,
                             Cy_USB_AppL1ResumeCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_ZLP,
                             Cy_USB_AppZlpCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_SLP,
                             Cy_USB_AppSlpCallback);
    Cy_USBD_RegisterCallback(pUsbdCtxt, CY_USB_USBD_CB_SETADDR,
                             Cy_USB_AppSetAddressCallback);
    return;
} /* end of function. */

/*
 * Function: CyUvcAppHandleProduceEvent()
 * Description: Function that handles a produce event indicating receipt of data through
 * the LVDS ingress socket.
 * Parameters:
 *      cy_stc_usb_app_ctxt_t *pUsbApp: Pointer to UVC application context structure.
 *      cy_stc_hbdma_channel_t *pChHandle: Pointer to DMA channel structure.
 * Return: None.
 */
static void
CyUvcAppHandleProduceEvent (
        cy_stc_usb_app_ctxt_t  *pUsbApp,
        cy_stc_hbdma_channel_t *pChHandle)
{
    cy_en_hbdma_mgr_status_t   status;
    cy_stc_hbdma_buff_status_t buffStat;

    /* Wait for a free buffer. */
    status = Cy_HBDma_Channel_GetBuffer(pChHandle, &buffStat);
    if (status != CY_HBDMA_MGR_SUCCESS)
    {
        DBG_APP_ERR("HB-DMA GetBuffer Error\r\n");
        return;
    }

#if INMD_EN
    if (pUsbApp->devSpeed <= CY_USBD_USB_DEV_HS)
    {
        Cy_USB_AppQueueWrite(pUsbApp, pUsbApp->uvcInEpNum, buffStat.pBuffer, buffStat.count);
    }
#else
    /* Add headers on every frame. Need to check if the EOF bit has to be set. */
    if (cy_uvc_buffer_counter <= cy_usb_full_buffer_no)
    {
        /* Not the end of frame. */
        Cy_USB_UvcAddHeader(buffStat.pBuffer - CY_USB_UVC_MAX_HEADER, CY_USB_UVC_HEADER_FRAME);
        cy_uvc_buffer_counter++;
        cy_uvc_commitLength = CY_USB_UVC_STREAM_BUF_SIZE;
    }
    else
    {
        /* Short packet: End of frame. */
        Cy_USB_UvcAddHeader(buffStat.pBuffer - CY_USB_UVC_MAX_HEADER, CY_USB_UVC_HEADER_EOF);
        cy_uvc_commitLength = cy_usb_no_bytes_last_buffer + CY_USB_UVC_MAX_HEADER;
        cy_uvc_buffer_counter = 1;
    }

    buffStat.count   = cy_uvc_commitLength;
    buffStat.size    = (cy_uvc_commitLength + 15) & 0xFFF0; // Round size up to a multiple of 16 bytes.
    buffStat.pBuffer = buffStat.pBuffer - CY_USB_UVC_MAX_HEADER;

    /* Commit the buffer for transfer */
    if (pUsbApp->devSpeed >= CY_USBD_USB_DEV_SS_GEN1)
    {
        status = Cy_HBDma_Channel_CommitBuffer(pChHandle, &buffStat);
        if (status != CY_HBDMA_MGR_SUCCESS)
        {
            DBG_APP_ERR("HB-DMA CommitBuffer Error\r\n");
        }
    }
    else
    {
        Cy_USB_AppQueueWrite(pUsbApp, pUsbApp->uvcInEpNum, buffStat.pBuffer, cy_uvc_commitLength);
    }
#endif /* INMD_EN */
}

#if LVDS_LB_EN
/*
 * Function: CyUvcAppCommitColorbarData()
 * Description: Function that commits loopback data patterns that inject the colorbar
 * data pattern into the LVDS ingress socket.
 * Parameters:
 *      cy_stc_usb_app_ctxt_t *pUsbApp: Pointer to UVC application context structure.
 *      cy_stc_hbdma_channel_t *pChHandle: Pointer to DMA channel structure.
 * Return: None.
 */
static void
CyUvcAppCommitColorbarData (
        cy_stc_usb_app_ctxt_t  *pUsbApp,
        cy_stc_hbdma_channel_t *pChHandle)
{
    cy_stc_hbdma_buff_status_t lbBuffStat;

    /* Two buffers of the producer socket are required to fill one buffer of the streaming socket. */
    if (Cy_HBDma_Channel_GetBuffer(pChHandle, &lbBuffStat) != CY_HBDMA_MGR_SUCCESS) {
        DBG_APP_ERR("GetLpbkBuf 2 failed\r\n");
        return;
    }

    lbBuffStat.count = LOOPBACK_MEM_BUF_SIZE;
    Cy_HBDma_Channel_CommitBuffer(pChHandle, &lbBuffStat);

    if (Cy_HBDma_Channel_GetBuffer(pChHandle, &lbBuffStat) != CY_HBDMA_MGR_SUCCESS) {
        DBG_APP_ERR("GetLpbkBuf 3 failed\r\n");
        return;
    }

    lbBuffStat.count = LOOPBACK_MEM_BUF_SIZE;
    Cy_HBDma_Channel_CommitBuffer(pChHandle, &lbBuffStat);
}
#endif /* LVDS_LB_EN */

/*
 * Function: CyUvcAppHandleSendCompletion()
 * Description: Function that handles DMA transfer completion on the USB-HS BULK-IN
 * endpoint. This is equivalent to the receipt of a consume event in the USB-SS use
 * case and we can discard the active data buffer on the LVDS side.
 *
 * Parameters:
 *      cy_stc_usb_app_ctxt_t *pUsbApp: Pointer to UVC application context structure.
 * Return: None.
 */
void
CyUvcAppHandleSendCompletion (
        cy_stc_usb_app_ctxt_t *pUsbApp)
{
    cy_stc_hbdma_buff_status_t buffStat;
    cy_en_hbdma_mgr_status_t   dmaStat;

    /* At least one buffer must be pending. */
    if (pUsbApp->uvcPendingBufCnt == 0)
    {
        DBG_APP_ERR("PendingBufCnt=0 on SendComplete\r\n");
        return;
    }

    /* The buffer which has been sent to the USB host can be discarded. */
    dmaStat = Cy_HBDma_Channel_DiscardBuffer(pUsbApp->hbBulkInChannel, &buffStat);
    if (dmaStat != CY_HBDMA_MGR_SUCCESS)
    {
        DBG_APP_ERR("DiscardBuffer failed with status=%x\r\n", dmaStat);
        return;
    }

#if LVDS_LB_EN
    /* If colorbar data pattern was blocked, enable it to fill one more data buffer. */
    if (pUsbApp->uvcFlowCtrlFlag)
    {
        pUsbApp->uvcFlowCtrlFlag = false;
        CyUvcAppCommitColorbarData(pUsbApp, &lvdsLbPgmChannel);
    }
#endif /* LVDS_LB_EN */

    /* If another DMA buffer has already been filled by the producer, go
     * on and send it to the host controller.
     */
    pUsbApp->uvcPendingBufCnt--;
    if (pUsbApp->uvcPendingBufCnt > 0)
    {
        CyUvcAppHandleProduceEvent(pUsbApp, pUsbApp->hbBulkInChannel);
    }
}

/*
 * Function: HbDma_Cb()
 * Description: It adds the UVC header to the frame/buffer coming from LVDS and commits to USB.
 * Parameter: cy_stc_hbdma_channel_t *, cy_en_hbdma_cb_type_t, cy_stc_hbdma_buff_status_t, void* .
 * Return: None.
 */
void HbDma_Cb(
        cy_stc_hbdma_channel_t *handle,
        cy_en_hbdma_cb_type_t type,
        cy_stc_hbdma_buff_status_t *pbufStat,
        void *userCtx)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt = (cy_stc_usb_app_ctxt_t *)userCtx;

    if (type == CY_HBDMA_CB_PROD_EVENT)
    {
        /* Video streamer application enable */
        if ((cy_uvc_IsApplnActive == true) && (cy_uvc_devconfigured == true))
        {
            if (pAppCtxt->devSpeed >= CY_USBD_USB_DEV_SS_GEN1)
            {
                CyUvcAppHandleProduceEvent(pAppCtxt, handle);
            }
            else
            {
                pAppCtxt->uvcPendingBufCnt++;
                if (pAppCtxt->uvcPendingBufCnt == 1)
                {
                    CyUvcAppHandleProduceEvent(pAppCtxt, handle);
                }
            }
        }
    }

#if LVDS_LB_EN
    if (type == CY_HBDMA_CB_CONS_EVENT)
    {
        /* If the loopback TX socket is in flow control state, commit two more buffers. */
        if (pAppCtxt->uvcFlowCtrlFlag)
        {
            pAppCtxt->uvcFlowCtrlFlag = false;
            CyUvcAppCommitColorbarData(pAppCtxt, &lvdsLbPgmChannel);
        }
    }
#endif /* LVDS_LB_EN */

} /* end of function  */

#if LVDS_LB_EN
void HbDma_Cb_Loopback (cy_stc_hbdma_channel_t *handle,
                        cy_en_hbdma_cb_type_t type,
                        cy_stc_hbdma_buff_status_t *pbufStat,
                        void *userCtx)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt = (cy_stc_usb_app_ctxt_t *)userCtx;

    if(type == CY_HBDMA_CB_CONS_EVENT)
    {
        lvdsConsCount++;

        /*
         * If the LVDS producer socket is active, commit the next two buffers.
         * Otherwise, set a flag indicating flow control state.
         */
        if ((lvdsConsCount & 0x01) == 0) {
            if((_FLD2VAL(LVDSSS_LVDS_ADAPTER_DMA_SCK_STATUS_STATE, \
                            (LVDSSS_LVDS->ADAPTER_DMA[0].SCK[0].SCK_STATUS))) == 0x2) {
                CyUvcAppCommitColorbarData(pAppCtxt, &lvdsLbPgmChannel);
            } else {
                pAppCtxt->uvcFlowCtrlFlag = true;
            }
        }
    }
}
#endif /* LVDS_LB_EN */

#if AUDIO_IF_EN
/*****************************************************************************
 * Function Name: UAC_HbDma_Cb
 ******************************************************************************
 * Summary:
 *  Callback function to manage data transfers on the USB Audio Class endpoint
 *  in USB 3.x connections.
 *
 * Parameters:
 *  handle: Pointer to the DMA channel associated with the endpoint.
 *  type: Type of callback event
 *  pbufStat: Event specific data
 *  userCtx: User context data to be de-referenced to obtain the application context.
 *
 * Return:
 *  void
 *****************************************************************************/
static void UAC_HbDma_Cb (cy_stc_hbdma_channel_t *handle,
                          cy_en_hbdma_cb_type_t type,
                          cy_stc_hbdma_buff_status_t *pbufStat,
                          void *userCtx)
{
    cy_stc_usb_app_ctxt_t *pAppCtxt = (cy_stc_usb_app_ctxt_t *)userCtx;

    /* As this is an IN endpoint, only consume events are expected. */
    if (type == CY_HBDMA_CB_CONS_EVENT)
    {
        /* Data has been consumed on USB side and buffer is free now. If all buffers
         * were full previously, we can queue a read operation using the newly freed
         * buffer.
         */
        if (pAppCtxt->pdmRxFreeBufCount == 0)
        {
            /* Queue read from the PDM RX FIFO into the next DMA buffer. */
            Cy_PDM_QueuePDMRead(pAppCtxt, 96);
        }

        pAppCtxt->pdmRxFreeBufCount++;
    }
}
#endif /* AUDIO_IF_EN */

/*****************************************************************************
 * Function Name: Cy_USB_AppSetupEndpDmaParamsSs
 ******************************************************************************
 * Summary:
 *  Perform high bandwidth DMA initialization associated with a USB endpoint.
 *
 * Parameters:
 *  pUsbApp: Pointer to application context structure.
 *  pEndpDscr: Endpoint descriptor
 *
 * Return:
 *  void
 *****************************************************************************/
static void
Cy_USB_AppSetupEndpDmaParamsSs (cy_stc_usb_app_ctxt_t *pUsbApp,
                                uint8_t *pEndpDscr)
{
    cy_stc_hbdma_chn_config_t dmaConfig;
    cy_en_hbdma_mgr_status_t mgrStat;
    uint32_t endpNumber, dir;
    uint16_t maxPktSize;
    uint8_t *pCompDscr;
    uint8_t burstSize;

    Cy_USBD_GetEndpNumMaxPktDir(pEndpDscr, &endpNumber, &maxPktSize, &dir);
    pCompDscr = Cy_USBD_GetSsEndpCompDscr(pUsbApp->pUsbdCtxt, pEndpDscr);
    Cy_USBD_GetEndpCompnMaxburst(pCompDscr, &burstSize);

    DBG_APP_INFO("AppSetupEndpDmaParamsSs: endpNum:0x%x maxPktSize:0x%x "
                 "dir:0x%x burstSize:0x%x\r\n",
                 endpNumber, maxPktSize,
                 dir, burstSize);

    /* Handling UVC streaming endpoint. */
    if ((endpNumber == UVC_STREAM_ENDPOINT) && (dir != 0)) {
        pUsbApp->uvcInEpNum       = (uint8_t)endpNumber;
        pUsbApp->uvcPendingBufCnt = 0;

        dmaConfig.chType       = CY_HBDMA_TYPE_IP_TO_IP;    /* DMA Channel type: from LVDS to USB EG IP. */
        dmaConfig.consSckCount = 1;                         /* Only one consumer socket per channel. */
        dmaConfig.consSck[0] = (cy_hbdma_socket_id_t)(CY_HBDMA_USBEG_SOCKET_00 + endpNumber);
        dmaConfig.consSck[1] = (cy_hbdma_socket_id_t)0;
        if (pUsbApp->devSpeed <= CY_USBD_USB_DEV_HS)
        {
            dmaConfig.chType     = CY_HBDMA_TYPE_IP_TO_MEM;
            dmaConfig.consSck[0] = (cy_hbdma_socket_id_t)0;
        }

#if INMD_EN
        dmaConfig.prodHdrSize = 0;
        dmaConfig.prodBufSize = CY_USB_UVC_STREAM_BUF_SIZE;
        if (pUsbApp->devSpeed > CY_USBD_USB_DEV_HS)
        {
            /* In SS connection with header addition by LVDS IP, we can use an AUTO channel. */
            dmaConfig.eventEnable = 1;      /* Enable event signalling between LVDS ingress and USB egress sockets. */
            dmaConfig.intrEnable  = 0;      /* No interrupts required in this case. */
        }
        else
        {
            /* In HS connection, we have to use a MANUAL channel. */
            dmaConfig.eventEnable = 0;      /* Event signalling cannot be used with USBHS endpoint. */
            dmaConfig.intrEnable  = LVDSSS_LVDS_ADAPTER_DMA_SCK_INTR_PRODUCE_EVENT_Msk;
        }
#else
        dmaConfig.prodHdrSize = CY_USB_UVC_MAX_HEADER;
        dmaConfig.prodBufSize = CY_USB_UVC_STREAM_BUF_SIZE - CY_USB_UVC_MAX_HEADER;
        dmaConfig.eventEnable = 0;          /* Manual channel: Disable event signalling between sockets. */
        dmaConfig.intrEnable  = LVDSSS_LVDS_ADAPTER_DMA_SCK_INTR_PRODUCE_EVENT_Msk |
            LVDSSS_LVDS_ADAPTER_DMA_SCK_INTR_CONSUME_EVENT_Msk|0x7ff;
#endif /* INMD_EN */

        dmaConfig.size       = CY_USB_UVC_STREAM_BUF_SIZE;  /* DMA Buffer size in bytes */
        dmaConfig.count      = CY_USB_UVC_STREAM_BUF_COUNT; /* DMA Buffer Count */
        dmaConfig.bufferMode = true;                        /* DMA buffer mode enabled */
        dmaConfig.cb         = HbDma_Cb;                    /* HB-DMA callback */
        dmaConfig.userCtx    = (void *)(pUsbApp);           /* Pass the application context as user context. */
#if PORT1_EN
        dmaConfig.prodSckCount = 1; /* No. of producer sockets */
        dmaConfig.prodSck[0] = CY_HBDMA_LVDS_SOCKET_16;
        dmaConfig.prodSck[1] = (cy_hbdma_socket_id_t)0;
#else
#if PORT0_THREAD_INTLV
        dmaConfig.prodSckCount = 2; /* No. of producer sockets */
        dmaConfig.prodSck[0] = CY_HBDMA_LVDS_SOCKET_00;
        dmaConfig.prodSck[1] = CY_HBDMA_LVDS_SOCKET_01;
#else
        dmaConfig.prodSckCount = 1; /* No. of producer sockets */
        dmaConfig.prodSck[0] = CY_HBDMA_LVDS_SOCKET_00;
        dmaConfig.prodSck[1] = (cy_hbdma_socket_id_t)0; /* Producer Socket ID: None */
#endif /* PORT0_THREAD_INTLV */
#endif /* PORT1_EN */

        if (pUsbApp->hbBulkInChannel != NULL)
        {
            DBG_APP_ERR("Streaming DMA channel already created\r\n");
            return;
        }

        mgrStat = Cy_HBDma_Channel_Create(pUsbApp->pUsbdCtxt->pHBDmaMgr,
                &(pUsbApp->endpInDma[endpNumber].hbDmaChannel),
                &dmaConfig);
        if (mgrStat != CY_HBDMA_MGR_SUCCESS)
        {
            DBG_APP_ERR("BulkIn channel create failed 0x%x\r\n", mgrStat);
            return;
        }

        /* Store the DMA channel pointer. */
        pUsbApp->hbBulkInChannel = &(pUsbApp->endpInDma[endpNumber].hbDmaChannel);
    }

#if AUDIO_IF_EN
    /* Handle UAC streaming endpoint. */
    if ((endpNumber == UAC_IN_ENDPOINT) && (dir != 0)) {
        if (pUsbApp->pPDMToUsbChn != NULL) {
            DBG_APP_ERR("ISOC-IN channel already created\r\n");
            return;
        }

        dmaConfig.size         = 192;                       /* DMA Buffer size in bytes */
        dmaConfig.count        = PDM_APP_BUFFER_CNT;        /* DMA Buffer Count */
        dmaConfig.prodHdrSize  = 0;                         /* No header being added. */
        dmaConfig.prodBufSize  = 192;
        dmaConfig.eventEnable  = 0;
        dmaConfig.intrEnable   = 0x3;
        dmaConfig.bufferMode   = false;                     /* DMA buffer mode disabled */
        dmaConfig.chType       = CY_HBDMA_TYPE_MEM_TO_IP;   /* DMA Channel type: from MEM to USB EG IP. */
        dmaConfig.prodSckCount = 1;                         /* No. of producer sockets */
        dmaConfig.prodSck[0]   = CY_HBDMA_VIRT_SOCKET_WR;
        dmaConfig.prodSck[1]   = (cy_hbdma_socket_id_t)0;   /* Producer Socket ID: None */
        dmaConfig.consSckCount = 1;                         /* No. of consumer Sockets */
        dmaConfig.consSck[0]   = (cy_hbdma_socket_id_t)(CY_HBDMA_USBEG_SOCKET_00 + endpNumber);
        dmaConfig.consSck[1]   = (cy_hbdma_socket_id_t)0;   /* Consumer Socket ID: None */
        dmaConfig.cb           = UAC_HbDma_Cb;              /* HB-DMA callback */
        dmaConfig.userCtx      = (void *)(pUsbApp);         /* Pass the application context as user context. */

        mgrStat = Cy_HBDma_Channel_Create(pUsbApp->pUsbdCtxt->pHBDmaMgr,
                &(pUsbApp->endpInDma[endpNumber].hbDmaChannel),
                &dmaConfig);
        if (mgrStat != CY_HBDMA_MGR_SUCCESS) {
            DBG_APP_ERR("ISOCIN channel create failed 0x%x\r\n", mgrStat);
            return;
        }

        /* Store the pointer to the DMA channel. */
        pUsbApp->pPDMToUsbChn = &(pUsbApp->endpInDma[endpNumber].hbDmaChannel);

        /* Get the list of DMA buffers to be used for PDM to USB transfers. */
        mgrStat = Cy_HBDma_Channel_GetBufferInfo(pUsbApp->pPDMToUsbChn, pUsbApp->pPDMRxBuffer, PDM_APP_BUFFER_CNT);
        if (mgrStat != CY_HBDMA_MGR_SUCCESS)
        {
            DBG_APP_ERR("Get Buffer INFO failed 0x%x\r\n", mgrStat);
            return;
        }

        pUsbApp->pdmRxBufIndex      = 0;
        pUsbApp->pdmRxFreeBufCount  = PDM_APP_BUFFER_CNT;
        pUsbApp->nxtAudioTxBufIndex = 0;
        pUsbApp->pdmInXferPending   = false;

        DBG_APP_INFO("HBDMA ISOCIN endpNum:%x ChnCreate status: %x\r\n", endpNumber, mgrStat);

        if (pUsbApp->devSpeed > CY_USBD_USB_DEV_HS) {
            /* Enable the channel for data transfer. */
            mgrStat = Cy_HBDma_Channel_Enable(pUsbApp->pPDMToUsbChn, 0);
            DBG_APP_INFO("HBDMA PDM to USB channel enable status: %x\r\n", mgrStat);
        }
    }
#endif /* AUDIO_IF_EN */
} /* end of function  */

/*
 * Function: Cy_USB_AppSetupEndpDmaParamsHs()
 * Description: This Function will setup Endpoint and DMA related parameters
 *             for high speed device before transfer initiated.
 * Parameter: cy_stc_usb_app_ctxt_t, pEndpDscr
 * return: void
 */
static void
Cy_USB_AppSetupEndpDmaParamsHs(cy_stc_usb_app_ctxt_t *pUsbApp,
                               uint8_t *pEndpDscr)
{
    cy_stc_app_endp_dma_set_t *pEndpDmaSet;
    DW_Type *pDW;
    bool stat;
    uint32_t endpNumber;
    uint16_t maxPktSize = 0x00;
    cy_en_usb_endp_dir_t endpDirection;

    endpNumber = ((*(pEndpDscr + CY_USB_ENDP_DSCR_OFFSET_ADDRESS)) & 0x7F);
    Cy_USBD_GetEndpMaxPktSize(pEndpDscr, &maxPktSize);

    if (*(pEndpDscr + CY_USB_ENDP_DSCR_OFFSET_ADDRESS) & 0x80)
    {
        endpDirection = CY_USB_ENDP_DIR_IN;
        pEndpDmaSet = &(pUsbApp->endpInDma[endpNumber]);
        pDW = pUsbApp->pCpuDw1Base;
    }
    else
    {
        endpDirection = CY_USB_ENDP_DIR_OUT;
        pEndpDmaSet = &(pUsbApp->endpOutDma[endpNumber]);
        pDW = pUsbApp->pCpuDw0Base;
    }

    stat = Cy_USBHS_App_EnableEpDmaSet(pEndpDmaSet, pDW, endpNumber, endpNumber, endpDirection, maxPktSize);
    DBG_APP_INFO("Enable EPDmaSet: endp=%x dir=%x stat=%x\r\n", endpNumber, endpDirection, stat);
} /* end of function  */

/*
 * Function: Cy_USB_AppSetupEndpDmaParams()
 * Description: This Function will setup Endpoint and DMA related parameters
 *              before transfer initiated.
 * Parameter: cy_stc_usb_app_ctxt_t, pEndpDscr
 * return: void
 */
void Cy_USB_AppSetupEndpDmaParams (cy_stc_usb_app_ctxt_t *pUsbApp,
                                   uint8_t *pEndpDscr)
{
    /* We always need to do SS setup so that we can get data from the LVDS interface. */
    Cy_USB_AppSetupEndpDmaParamsSs(pUsbApp, pEndpDscr);

    if (pUsbApp->devSpeed <= CY_USBD_USB_DEV_HS)
    {
        Cy_USB_AppSetupEndpDmaParamsHs(pUsbApp, pEndpDscr);
    }
}

/*
 * Function: Cy_USB_AppConfigureEndp()
 * Description: This Function is used by application to configure endpoints
 *              after set configuration.  This function should be used for
 *              all endpoints except endp0.
 * Parameter: cy_stc_usb_usbd_ctxt_t, pEndpDscr
 * return: void
 */
void Cy_USB_AppConfigureEndp (cy_stc_usb_usbd_ctxt_t *pUsbdCtxt, uint8_t *pEndpDscr)
{
    cy_stc_usb_endp_config_t endpConfig;
    cy_en_usb_endp_dir_t endpDirection;
    bool valid;
    uint32_t endpType;
    uint32_t endpNumber, dir;
    uint16_t maxPktSize;
    uint32_t isoPkts = 0x00;
    uint8_t burstSize = 0x00;
    uint8_t maxStream = 0x00;
    uint8_t *pCompDscr = NULL;
    cy_en_usbd_ret_code_t usbdRetCode;

    /* If it is not endpoint descriptor then return */
    if (!Cy_USBD_EndpDscrValid(pEndpDscr))
    {
        return;
    }
    Cy_USBD_GetEndpNumMaxPktDir(pEndpDscr, &endpNumber, &maxPktSize, &dir);

    if (dir)
    {
        endpDirection = CY_USB_ENDP_DIR_IN;
    }
    else
    {
        endpDirection = CY_USB_ENDP_DIR_OUT;
    }
    Cy_USBD_GetEndpType(pEndpDscr, &endpType);

    if ((CY_USB_ENDP_TYPE_ISO == endpType) || (CY_USB_ENDP_TYPE_INTR == endpType))
    {
        /* The ISOINPKS setting in the USBHS register is the actual packets per microframe value. */
        isoPkts = ((*((uint8_t *)(pEndpDscr + CY_USB_ENDP_DSCR_OFFSET_MAX_PKT + 1)) & CY_USB_ENDP_ADDL_XN_MASK) >> CY_USB_ENDP_ADDL_XN_POS) + 1;
    }

    valid = 0x01;
    if (pUsbdCtxt->devSpeed > CY_USBD_USB_DEV_HS)
    {
        /* Get companion descriptor and from there get burstSize. */
        pCompDscr = Cy_USBD_GetSsEndpCompDscr(pUsbdCtxt, pEndpDscr);
        Cy_USBD_GetEndpCompnMaxburst(pCompDscr, &burstSize);
        Cy_USBD_GetEndpCompnMaxStream(pCompDscr, &maxStream);
    }

    /* Prepare endpointConfig parameter. */
    endpConfig.endpType = (cy_en_usb_endp_type_t)endpType;
    endpConfig.endpDirection = endpDirection;
    endpConfig.valid = valid;
    endpConfig.endpNumber = endpNumber;
    endpConfig.maxPktSize = (uint32_t)maxPktSize;
    endpConfig.isoPkts = isoPkts;
    endpConfig.burstSize = burstSize;
    endpConfig.streamID = maxStream;
    endpConfig.allowNakTillDmaRdy = false;
    usbdRetCode = Cy_USB_USBD_EndpConfig(pUsbdCtxt, endpConfig);

    /* Print status of the endpoint configuration to help debug. */
    DBG_APP_INFO("#ENDPCFG: %d, %d\r\n", endpNumber, usbdRetCode);
    return;
} /* end of function */

/*
 * Function: Cy_USB_AppSetCfgCallback()
 * Description: This Function will be called by USBD  layer when
 *              set configuration command successful. This function
 *              does sanity check and prepare device for function
 *              to take over.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t
 * return: void
 */
void Cy_USB_AppSetCfgCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                              cy_stc_usb_cal_msg_t *pMsg)
{

    cy_uvc_devconfigured = true;
    cy_stc_usb_app_ctxt_t *pUsbApp;
    uint8_t *pActiveCfg, *pIntfDscr, *pEndpDscr;
    uint8_t index, numOfIntf, numOfEndp;
    cy_en_usb_speed_t devSpeed;

    DBG_APP_INFO("AppSetCfgCbStart\r\n");

    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;
    pUsbApp->devSpeed = Cy_USBD_GetDeviceSpeed(pUsbdCtxt);
    devSpeed = pUsbApp->devSpeed;

   /*
     * Print out the contents of the USB event log buffer which has
     * logged event related to enumeration and line training.
     */
    AppPrintUsbEventLog(pAppCtxt, pUsbdCtxt->pSsCalCtxt);

    /* Disable optional Low Power Mode transitions. */
    Cy_USBD_LpmDisable(pUsbdCtxt);

    /*
     * Based on type of application as well as how data flows,
     * data wire can be used so initialize datawire.
     */
    Cy_DMA_Enable(pUsbApp->pCpuDw0Base);
    Cy_DMA_Enable(pUsbApp->pCpuDw1Base);

    pActiveCfg = Cy_USB_USBD_GetActiveCfgDscr(pUsbdCtxt);
    if (!pActiveCfg)
    {
        /* Set config should be called when active config value > 0x00. */
        return;
    }
    numOfIntf = Cy_USBD_FindNumOfIntf(pActiveCfg);
    if (numOfIntf == 0x00)
    {
        return;
    }

    for (index = 0x00; index < numOfIntf; index++)
    {
        /* During Set Config command always altSetting 0 will be active. */
        pIntfDscr = Cy_USBD_GetIntfDscr(pUsbdCtxt, index, 0x00);
        if (pIntfDscr == NULL)
        {
            DBG_APP_INFO("pIntfDscrNull\r\n");
            return;
        }

        numOfEndp = Cy_USBD_FindNumOfEndp(pIntfDscr);
        if (numOfEndp == 0x00)
        {
            DBG_APP_INFO("numOfEndp 0\r\n");
            continue;
        }

        pEndpDscr = Cy_USBD_GetEndpDscr(pUsbdCtxt, pIntfDscr);
        while (numOfEndp != 0x00)
        {
            Cy_USB_AppConfigureEndp(pUsbdCtxt, pEndpDscr);
            Cy_USB_AppSetupEndpDmaParams(pAppCtxt, pEndpDscr);
            numOfEndp--;

            if (devSpeed > CY_USBD_USB_DEV_HS)
            {
                pEndpDscr = (pEndpDscr + (*(pEndpDscr + CY_USB_DSCR_OFFSET_LEN)) + 6);
            }
            else
            {
                pEndpDscr = (pEndpDscr + (*(pEndpDscr + CY_USB_DSCR_OFFSET_LEN)));
            }
        }
    }

    if (devSpeed <= CY_USBD_USB_DEV_HS)
    {
        /* Enable the interrupt for the DataWire channel used for video streaming to USBHS BULK-IN endpoint. */
        Cy_USB_AppInitDmaIntr(pUsbApp->uvcInEpNum, CY_USB_ENDP_DIR_IN, UvcDataWire_ISR);
    }

    pUsbApp->prevDevState = CY_USB_DEVICE_STATE_CONFIGURED;
    pUsbApp->devState = CY_USB_DEVICE_STATE_CONFIGURED;

    DBG_APP_INFO("AppSetCfgCbEnd Done\r\n");
    return;
} /* end of function */

/*
 * Function: Cy_USB_AppBusResetCallback()
 * Description: This Function will be called by USBD when bus detects RESET.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t
 * return: void
 */
void Cy_USB_AppBusResetCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pUsbApp;

    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;

    DBG_APP_INFO("AppBusResetCallback\r\n");

    /* Stop and destroy the high bandwidth DMA channel if present. To be done before AppInit is called. */
    if (pUsbApp->hbBulkInChannel != NULL)
    {
        DBG_APP_TRACE("HBDMA destroy\r\n");
        Cy_HBDma_Channel_Disable(pUsbApp->hbBulkInChannel);
        Cy_HBDma_Channel_Destroy(pUsbApp->hbBulkInChannel);
        pUsbApp->hbBulkInChannel = NULL;
    }

    /*
     * USBD layer takes care of reseting its own data structure as well as
     * takes care of calling CAL reset APIs. Application needs to take care
     * of reseting its own data structure as well as "device function".
     */
    Cy_USB_AppInit(pUsbApp, pUsbdCtxt, pUsbApp->pCpuDmacBase,
                   pUsbApp->pCpuDw0Base, pUsbApp->pCpuDw1Base,
                   pUsbApp->pHbDmaMgrCtxt);
    pUsbApp->devState = CY_USB_DEVICE_STATE_RESET;
    pUsbApp->prevDevState = CY_USB_DEVICE_STATE_RESET;

    if (pUsbdCtxt->devSpeed >= CY_USBD_USB_DEV_SS_GEN1)
    {
        /*
         * Toggle the REG_VBUS and PCLK_EN bits in the PHY.TOP_CTRL_0 register
         * when there is a Warm Reset.
         */
        if ((USB32DEV->USB32DEV_LNK.LNK_LTSSM_STATE & USB32DEV_LNK_LTSSM_STATE_LTSSM_STATE_Msk) ==
            CY_USBSS_LNK_STATE_RXDETECT_RES)
        {
            DBG_APP_TRACE("Skip reset PHY on WarmReset\r\n");
        }
    }
    cy_uvc_devconfigured = false;
    cy_uvc_IsApplnActive = false;
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppBusResetDoneCallback()
 * Description: This Function will be called by USBD  layer when
 *              set configuration command successful. This function
 *              does sanity check and prepare device for function
 *              to take over.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t
 * return: void
 */
void Cy_USB_AppBusResetDoneCallback(void *pAppCtxt,
                                    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                    cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pUsbApp;

    DBG_APP_INFO("ppBusResetDoneCallback\r\n");

    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;
    pUsbApp->devState = CY_USB_DEVICE_STATE_DEFAULT;
    pUsbApp->prevDevState = pUsbApp->devState;
    return;
} /* end of function. */

extern uint8_t CyFxUSB20DeviceDscr[];

/*
 * Function: Cy_USB_AppBusSpeedCallback()
 * Description: This Function will be called by USBD  layer when
 *              speed is identified or speed change is detected.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t
 * return: void
 */
void Cy_USB_AppBusSpeedCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pUsbApp;

    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;
    pUsbApp->devState = CY_USB_DEVICE_STATE_DEFAULT;
    pUsbApp->devSpeed = Cy_USBD_GetDeviceSpeed(pUsbdCtxt);
    Cy_USBD_SetDscr(pUsbApp->pUsbdCtxt, CY_USB_SET_HS_DEVICE_DSCR, 0, (uint8_t *)CyFxUSB20DeviceDscr);
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppSetupCallback()
 * Description: This Function will be called by USBD  layer when
 *              set configuration command successful. This function
 *              does sanity check and prepare device for function
 *              to take over.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t
 * return: void
 */
void Cy_USB_AppSetupCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                             cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pUsbApp;
    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;
    uint8_t bRequest, bReqType;
    uint8_t bType, bTarget, temp;
    uint16_t wValue, wIndex, wLength;
    bool isReqHandled = false;
    cy_en_usbd_ret_code_t retStatus = CY_USBD_STATUS_SUCCESS;
    cy_en_usb_endp_dir_t epDir = CY_USB_ENDP_DIR_INVALID;
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    cy_stc_usbd_app_msg_t xMsg;

    DBG_APP_INFO("AppSetupCallback\r\n");

    /* Fast enumeration is used. Only requests addressed to the interface, class,
     * vendor and unknown control requests are received by this function. */

    /* Decode the fields from the setup request. */
    bReqType = pUsbdCtxt->setupReq.bmRequest;
    bType = ((bReqType & CY_USB_CTRL_REQ_TYPE_MASK) >> CY_USB_CTRL_REQ_TYPE_POS);
    bTarget = (bReqType & CY_USB_CTRL_REQ_RECIPENT_OTHERS);
    bRequest = pUsbdCtxt->setupReq.bRequest;
    wValue = pUsbdCtxt->setupReq.wValue;
    wIndex = pUsbdCtxt->setupReq.wIndex;
    wLength = pUsbdCtxt->setupReq.wLength;

    if (bType == CY_USB_CTRL_REQ_STD)
    {
        DBG_APP_INFO("CY_USB_CTRL_REQ_STD\r\n");
        if (bRequest == CY_USB_SC_SET_FEATURE)
        {
            DBG_APP_INFO("CY_USB_SC_SET_FEATURE\r\n");
            /* Function Suspend: ACK the request if the device is in configured state in an USB 3.x connection. */
            if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_INTF) && (wValue == 0))
            {
                DBG_APP_INFO("CY_USB_CTRL_REQ_RECIPENT_INTF\r\n");
                if ((pUsbApp->devSpeed >= CY_USBD_USB_DEV_SS_GEN1) && (cy_uvc_devconfigured))
                    Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
                else
                    Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, 0x00, CY_USB_ENDP_DIR_IN, TRUE);

                isReqHandled = true;
            }

            /* SET-FEATURE(EP-HALT) is only supported to facilitate Chapter 9 compliance tests. */
            if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_ENDP) && (wValue == CY_USB_FEATURE_ENDP_HALT))
            {
                DBG_APP_INFO("CY_USB_CTRL_REQ_RECIPENT_ENDP\r\n");
                epDir = ((wIndex & 0x80UL) ? (CY_USB_ENDP_DIR_IN) : (CY_USB_ENDP_DIR_OUT));
                Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, ((uint32_t)wIndex & 0x7FUL),
                        epDir, true);

                Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
                isReqHandled = true;
            }

            if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_DEVICE) &&
                    ((wValue == CY_USB_FEATURE_U1_ENABLE) || (wValue == CY_USB_FEATURE_U2_ENABLE))) {
                /* Set U1/U2 enable. Just ACK the request. */
                Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
                isReqHandled = true;
            }
        }

        if (bRequest == CY_USB_SC_CLEAR_FEATURE)
        {
            DBG_APP_INFO("CY_USB_SC_CLEAR_FEATURE\r\n");
            /* Function Suspend: ACK the request if the device is in configured state in an USB 3.x connection. */
            if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_INTF) && (wValue == 0))
            {
                DBG_APP_INFO("CY_USB_CTRL_REQ_RECIPENT_INTF\r\n");
                if ((pUsbApp->devSpeed >= CY_USBD_USB_DEV_SS_GEN1) && (cy_uvc_devconfigured))
                    Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
                else
                    Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, 0x00, CY_USB_ENDP_DIR_IN, TRUE);

                isReqHandled = true;
            }

            if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_ENDP) && (wValue == CY_USB_FEATURE_ENDP_HALT))
            {
                DBG_APP_INFO("CY_USB_CTRL_REQ_RECIPENT_ENDP && CY_USB_FEATURE_ENDP_HALT\r\n");
                epDir = ((wIndex & 0x80UL) ? (CY_USB_ENDP_DIR_IN) : (CY_USB_ENDP_DIR_OUT));
                if ((epDir == CY_USB_ENDP_DIR_OUT) || ((wIndex & 0x7F) != pUsbApp->uvcInEpNum))
                {
                    /* For any EP other than the UVC streaming endpoint, just clear the STALL bit. */
                    Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, ((uint32_t)wIndex & 0x7FUL),
                            epDir, false);
                    Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
                }
                else
                {
//#if (!INMD_EN)
                    /* Waiting until the GPIF state machine is no longer pushing data into the DMA buffer */
                    do {
                    } while((Cy_LVDS_GpifGetSMState(LVDSSS_LVDS,cy_u3v_smNo) >= 2));
                    DBG_APP_INFO("DMA Socket is stall\r\n");

                    /* Reset the DMA channel through which data is received from the LVDS side. */
                    Cy_HBDma_Channel_Reset(pUsbApp->hbBulkInChannel);

                    /* On USB 2.0 connection, reset the DataWire channel used to send data to the EPM. */
                    if (pUsbApp->devSpeed <= CY_USBD_USB_DEV_HS)
                    {
                        Cy_USBHS_App_ResetEpDma(&(pUsbApp->endpInDma[pUsbApp->uvcInEpNum]));
                    }

                    /* Flush and reset the endpoint and clear the STALL bit. */
                    Cy_USBD_FlushEndp(pUsbdCtxt, pUsbApp->uvcInEpNum, CY_USB_ENDP_DIR_IN);
                    Cy_USBD_ResetEndp(pUsbdCtxt, pUsbApp->uvcInEpNum, CY_USB_ENDP_DIR_IN, false);
                    Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, ((uint32_t)wIndex & 0x7FUL),
                            epDir, false);

                    pUsbApp->uvcPendingBufCnt = 0;
                    Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
//#else
//                    Cy_LVDS_GpifSetFwTrig(LVDSSS_LVDS,cy_u3v_smNo);
//                    Cy_HBDma_Channel_AutoDropData(pUsbApp->hbBulkInChannel);
//                    DBG_APP_INFO("SetFwTrig\r\n");
//#endif

#if LVDS_LB_EN
                    pUsbApp->uvcFlowCtrlFlag = false;
                    lvdsConsCount = 0;
                    Cy_HBDma_Channel_Reset(&lvdsLbPgmChannel);
                    Cy_HBDma_Channel_Enable(&lvdsLbPgmChannel, 0);
#endif /* LVDS_LB_EN */
                }

                isReqHandled = true;
            }

            if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_DEVICE) &&
                    ((wValue == CY_USB_FEATURE_U1_ENABLE) || (wValue == CY_USB_FEATURE_U2_ENABLE))) {
                /* Set U1/U2 disable. Just ACK the request. */
                Cy_USBD_SendAckSetupDataStatusStage(pUsbdCtxt);
                isReqHandled = true;
            }
        }
    }

    if (bType == CY_USB_CTRL_REQ_VENDOR)
    {
        /* Command to fetch SRAM content or MMIO registers for debug. */
        if ((bRequest == 0xA0) && (wLength != 0) && (wLength <= 4096U) && ((wLength & 0x03) == 0))
        {
            uint32_t baseAddr = (wValue << 16U) | wIndex;
            uint16_t i;

            if ((baseAddr >= 0x1C000000UL) && (baseAddr < 0x20000000UL))
            {
                retStatus = Cy_USB_USBD_SendEndp0Data(pUsbdCtxt, (uint8_t *)baseAddr, wLength);
            }
            else
            {
                for (i = 0; i < wLength / 4; i++)
                {
                    Ep0TestBuffer[i] = ((uint32_t *)baseAddr)[i];
                }
                retStatus = Cy_USB_USBD_SendEndp0Data(pUsbdCtxt, (uint8_t *)Ep0TestBuffer, wLength);
            }
        }
    }

    /* Check for UVC Class Requests */
    if (bType == CY_USB_CTRL_REQ_CLASS)
    {

        DBG_APP_INFO("UVC Class Requests\r\n");
        /* Handle requests addressed to the Video Control interface. */
        if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_INTF) && (CY_GET_LSB(wIndex) == CY_USB_UVC_INTERFACE_VC))
        {
            DBG_APP_INFO("CY_USB_CTRL_REQ_RECIPENT_INTF && CY_USB_UVC_INTERFACE_VC\r\n");
            /* Respond to VC_REQUEST_ERROR_CODE_CONTROL and stall every other request as this example does not support
               any of the Video Control features */
            if ((CY_GET_MSB(wIndex) == 0x00) && (wValue == CY_USB_UVC_VC_RQT_ERROR_CODE_CONTROL))
            {
                temp = CY_USB_UVC_RQT_STAT_INVALID_CTRL;
                isReqHandled = true;
                DBG_APP_INFO("UVC_RQT_STAT_INVALID_CTRL\r\n");
                Cy_USB_USBD_SendEndp0Data(pUsbdCtxt, &temp, 0x01);
            }
        }

        /* Handle requests addressed to the Video Streaming interface. */
        if ((bTarget == CY_USB_CTRL_REQ_RECIPENT_INTF) && (CY_GET_LSB(wIndex) == CY_USB_UVC_INTERFACE_VS))
        {
            isReqHandled = true;
            DBG_APP_INFO("CY_USB_CTRL_REQ_RECIPENT_INTF && CY_USB_UVC_INTERFACE_VS\r\n");
            switch (wValue)
            {

            case CY_USB_UVC_VS_PROBE_CONTROL:
            case CY_USB_UVC_VS_COMMIT_CONTROL:
            {
                switch (bRequest)
                {
                case CY_USB_UVC_GET_INFO_REQ:
                    DBG_APP_INFO("UVC_GET_INFO_REQ\r\n");
                    Ep0TestBuffer[0] = 3; /* GET/SET requests are supported. */
                    Cy_USB_USBD_SendEndp0Data(pUsbdCtxt, (uint8_t *)Ep0TestBuffer, 0x01);
                    break;

                case CY_USB_UVC_GET_LEN_REQ:
                    DBG_APP_INFO("UVC_GET_LEN_REQ\r\n");
                    Ep0TestBuffer[0] = CY_USB_UVC_MAX_PROBE_SETTING;
                    Cy_USB_USBD_SendEndp0Data(pUsbdCtxt, (uint8_t *)Ep0TestBuffer, 0x01);
                    break;

                /* We only have one functional setting. Keep returning the same as current, default
                 * minimum and maximum. */
                case CY_USB_UVC_GET_CUR_REQ:
                case CY_USB_UVC_GET_DEF_REQ:
                case CY_USB_UVC_GET_MIN_REQ:
                case CY_USB_UVC_GET_MAX_REQ:
                    DBG_APP_INFO("UVC_GET_CUR_DEF_MIN_MAX_REQ:%x \r\n", bRequest);

                    if (pUsbApp->devSpeed > CY_USBD_USB_DEV_HS)
                    {

                        if (cy_uvc_currentFrameIndex == CY_USB_UVC_SS_4K_FRAME_INDEX)
                        {
                            retStatus = Cy_USB_USBD_SendEndp0Data(pUsbdCtxt,
                                                                  (uint8_t *)cy_uvc_probectrl_4K, CY_USB_UVC_MAX_PROBE_SETTING);
                        }
                        else if (cy_uvc_currentFrameIndex == CY_USB_UVC_SS_720P_FRAME_INDEX)
                        {
                            retStatus = Cy_USB_USBD_SendEndp0Data(pUsbdCtxt,
                                                                  (uint8_t *)cy_uvc_probectrl_720p, CY_USB_UVC_MAX_PROBE_SETTING);
                        }
                        else if (cy_uvc_currentFrameIndex == CY_USB_UVC_SS_VGA_FRAME_INDEX)
                        {
                            retStatus = Cy_USB_USBD_SendEndp0Data(pUsbdCtxt,
                                                                  (uint8_t *)cy_uvc_probectrl_VGA, CY_USB_UVC_MAX_PROBE_SETTING);
                        }
                        else
                        {
                            DBG_APP_ERR("currentFrameIndex\r\n");
                        }

                        if (retStatus != CY_USBD_STATUS_SUCCESS)
                        {
                            DBG_APP_ERR("Error SendEndp0Data\r\n");
                        }
                    }
                    else
                    {
                        if (cy_uvc_currentFrameIndex == CY_USB_UVC_HS_VGA_FRAME_INDEX)
                        {
                            retStatus = Cy_USB_USBD_SendEndp0Data(pUsbdCtxt,
                                                                  (uint8_t *)cy_uvc_probectrl_HS_VGA, CY_USB_UVC_MAX_PROBE_SETTING);
                        }
                        else
                        {
                            DBG_APP_ERR("currentFrameIndex\r\n");
                        }

                        if (retStatus != CY_USBD_STATUS_SUCCESS)
                        {
                            DBG_APP_ERR("Error SendEndp0Data\r\n");
                        }
                    }

                    break;

                case CY_USB_UVC_SET_CUR_REQ:
                    /* Since this request has OUT data, it should be handled in task context. */
                    xMsg.type    = CY_USB_UVC_DEVICE_SET_CUR_RQT;
                    xMsg.data[0] = wLength;
                    xQueueSendFromISR(pUsbApp->uvcMsgQueue, &(xMsg), &(xHigherPriorityTaskWoken));
                    isReqHandled = true;
                    break;

                default:
                    isReqHandled = false;
                    break;
                }
            }
            break;

            default:
                isReqHandled = false;
                break;
            }
        }

        /* Don't try to stall the endpoint if we have already attempted data transfer. */
    }

    /* SET_SEL request is supposed to have an OUT data phase of 6 bytes. */
    if ((bRequest == CY_USB_SC_SET_SEL) && (wLength == 6))
    {
        /* SET_SEL request is only received in USBSS case and the Cy_USB_USBD_RecvEndp0Data is blocking. */
        retStatus = Cy_USB_USBD_RecvEndp0Data(pUsbdCtxt, (uint8_t *)SetSelDataBuffer, wLength);
        DBG_APP_INFO("SET_SEL: EP0 recv stat = %d, Data=%x:%x\r\n",
                retStatus, SetSelDataBuffer[0], SetSelDataBuffer[1]);
        isReqHandled = true;
    }

    /*
     * If Request is not handled by the callback, Stall the command.
     */
    if (!isReqHandled)
    {
        Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, 0x00,
                                      CY_USB_ENDP_DIR_IN, TRUE);
    }
} /* end of function. */

/*
 * Function: Cy_USB_AppSuspendCallback()
 * Description: This Function will be called by USBD  layer when
 *              Suspend signal/message is detected.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppSuspendCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pUsbApp;

    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;
    pUsbApp->prevDevState = pUsbApp->devState;
    pUsbApp->devState = CY_USB_DEVICE_STATE_SUSPEND;
} /* end of function. */

/*
 * Function: Cy_USB_AppResumeCallback()
 * Description: This Function will be called by USBD  layer when
 *              Resume signal/message is detected.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppResumeCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                              cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_app_ctxt_t *pUsbApp;
    cy_en_usb_device_state_t tempState;

    pUsbApp = (cy_stc_usb_app_ctxt_t *)pAppCtxt;

    tempState = pUsbApp->devState;
    pUsbApp->devState = pUsbApp->prevDevState;
    pUsbApp->prevDevState = tempState;
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppSetIntfCallback()
 * Description: This Function will be called by USBD  layer when
 *              set interface is called.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppSetIntfCallback(void *pAppCtxt, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg)
{
    cy_stc_usb_setup_req_t *pSetupReq;
    uint8_t intfNum, altSetting;

    DBG_APP_INFO("AppSetIntfCallback Start\r\n");
    pSetupReq  = &(pUsbdCtxt->setupReq);
    intfNum    = pSetupReq->wIndex;
    altSetting = pSetupReq->wValue;

#if AUDIO_IF_EN
    if (intfNum == UAC_STREAM_INTF_NUM) {
        Cy_App_SetUACIntfHandler((cy_stc_usb_app_ctxt_t *)pAppCtxt, altSetting);
        return;
    }
#endif /* AUDIO_IF_EN */

    /* Interface does not support multiple alternate settings: Stall the SET_INTERFACE request. */
    DBG_APP_INFO("SetIntf(%d) on interface %d: Stalled\r\n", altSetting, intfNum);
    Cy_USB_USBD_EndpSetClearStall(pUsbdCtxt, 0x00, CY_USB_ENDP_DIR_IN, true);
    DBG_APP_INFO("AppSetIntfCallback done\r\n");
} /* end of function. */

/*
 * Function: Cy_USB_AppZlpCallback()
 * Description: This Function will be called by USBD layer when
 *              ZLP message comes.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppZlpCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                           cy_stc_usb_cal_msg_t *pMsg)
{
    DBG_APP_INFO("AppZlpCb\r\n");

    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppL1SleepCallback()
 * Description: This Function will be called by USBD layer when
 *              L1 Sleep message comes.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppL1SleepCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                               cy_stc_usb_cal_msg_t *pMsg)
{
    DBG_APP_INFO("AppL1SleepCb\r\n");
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppL1ResumeCallback()
 * Description: This Function will be called by USBD layer when
 *              L1 Resume message comes.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppL1ResumeCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                cy_stc_usb_cal_msg_t *pMsg)
{
    DBG_APP_INFO("AppL1ResumeCb\r\n");
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppSlpCallback()
 * Description: This Function will be called by USBD layer when
 *              SLP message comes.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppSlpCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                           cy_stc_usb_cal_msg_t *pMsg)
{
    DBG_APP_INFO("AppSlpCb\r\n");
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppSetFeatureCallback()
 * Description: This Function will be called by USBD layer when
 *              set feature message comes.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppSetFeatureCallback(void *pUsbApp, cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                  cy_stc_usb_cal_msg_t *pMsg)
{
    DBG_APP_INFO("AppSetFeatureCb\r\n");
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppClearFeatureCallback()
 * Description: This Function will be called by USBD layer when
 *              clear feature message comes.
 * Parameter: pAppCtxt, cy_stc_usb_usbd_ctxt_t, cy_stc_usb_cal_msg_t
 * return: void
 */
void Cy_USB_AppClearFeatureCallback(void *pUsbApp,
                                    cy_stc_usb_usbd_ctxt_t *pUsbdCtxt,
                                    cy_stc_usb_cal_msg_t *pMsg)
{
    DBG_APP_INFO("AppClearFeatureCb\r\n");
    return;
} /* end of function. */

/*
 * Function: Cy_USB_AppQueueWrite()
 * Description: Function to queue write operation on an IN endpoint.
 * Parameter: pAppCtxt, endpNumber, pBuffer, dataSize
 * return: void
 */
void Cy_USB_AppQueueWrite(cy_stc_usb_app_ctxt_t *pAppCtxt, uint8_t endpNumber,
                          uint8_t *pBuffer, uint16_t dataSize)
{
    cy_stc_app_endp_dma_set_t *dmaset_p;

    /* Null pointer checks. */
    if ((pAppCtxt == NULL) || (pAppCtxt->pUsbdCtxt == NULL) ||
            (pAppCtxt->pCpuDw1Base == NULL) || (pBuffer == NULL)) {
        DBG_APP_ERR("QueueWrite Err0\r\n");
        return;
    }

    /*
     * Verify that the selected endpoint is valid and the dataSize
     * is non-zero.
     */
    dmaset_p = &(pAppCtxt->endpInDma[endpNumber]);
    if ((dmaset_p->valid == 0) || (dataSize == 0)) {
        DBG_APP_ERR("QueueWrite Err1\r\n");
        return;
    }

    Cy_USBHS_App_QueueWrite(dmaset_p, pBuffer, dataSize);
} /* end of function */

/*
 * Function: Cy_USB_AppInitDmaIntr()
 * Description: Function to register an ISR for the DMA channel associated
 *              with an endpoint.
 * Parameters:
 *      endpNumber: Endpoint number
 *      endpDirection: Endpoint direction.
 *      userIsr: ISR function pointer. Can be NULL if interrupt is to be
 *               disabled.
 * return: void
 */
void Cy_USB_AppInitDmaIntr(uint32_t endpNumber, cy_en_usb_endp_dir_t endpDirection,
                           cy_israddress userIsr)
{
    cy_stc_sysint_t intrCfg;
    if ((endpNumber > 0) && (endpNumber < CY_USB_MAX_ENDP_NUMBER))
    {
#if (!CY_CPU_CORTEX_M4)
        intrCfg.intrPriority = 3;
        intrCfg.intrSrc = NvicMux7_IRQn;
        if (endpDirection == CY_USB_ENDP_DIR_IN)
        {
            /* DW1 channels 0 onwards are used for IN endpoints. */
            intrCfg.cm0pSrc = (cy_en_intr_t)(cpuss_interrupts_dw1_0_IRQn + endpNumber);
        }
        else
        {
            /* DW0 channels 0 onwards are used for OUT endpoints. */
            intrCfg.cm0pSrc = (cy_en_intr_t)(cpuss_interrupts_dw0_0_IRQn + endpNumber);
        }
#else
        intrCfg.intrPriority = 5;
        if (endpDirection == CY_USB_ENDP_DIR_IN)
        {
            /* DW1 channels 0 onwards are used for IN endpoints. */
            intrCfg.intrSrc =
                (IRQn_Type)(cpuss_interrupts_dw1_0_IRQn + endpNumber);
        }
        else
        {
            /* DW0 channels 0 onwards are used for OUT endpoints. */
            intrCfg.intrSrc =
                (IRQn_Type)(cpuss_interrupts_dw0_0_IRQn + endpNumber);
        }
#endif /* (!CY_CPU_CORTEX_M4) */

        if (userIsr != NULL)
        {
            /* If an ISR is provided, register it and enable the interrupt. */
            Cy_SysInt_Init(&intrCfg, userIsr);
            NVIC_EnableIRQ(intrCfg.intrSrc);
        }
        else
        {
            /* ISR is NULL. Disable the interrupt. */
            NVIC_DisableIRQ(intrCfg.intrSrc);
        }
    }
} /* end of function. */

/*
 * Function: Cy_USB_AppClearDmaInterrupt()
 * Description: Function to clear the pending DMA interrupt associated with an
 *              endpoint.
 * Parameters:
 *      pAppCtxt: Pointer to USB application context structure.
 *      endpNumber: Endpoint number
 *      endpDirection: Endpoint direction.
 * return: void
 */
void Cy_USB_AppClearDmaInterrupt(cy_stc_usb_app_ctxt_t *pAppCtxt,
                                 uint32_t endpNumber, cy_en_usb_endp_dir_t endpDirection)
{
    if ((pAppCtxt != NULL) && (endpNumber > 0) &&
            (endpNumber < CY_USB_MAX_ENDP_NUMBER)) {
        if (endpDirection == CY_USB_ENDP_DIR_IN) {
            Cy_USBHS_App_ClearDmaInterrupt(&(pAppCtxt->endpInDma[endpNumber]));
        } else  {
            Cy_USBHS_App_ClearDmaInterrupt(&(pAppCtxt->endpOutDma[endpNumber]));
        }
    }
} /* end of function. */

/*[]*/

