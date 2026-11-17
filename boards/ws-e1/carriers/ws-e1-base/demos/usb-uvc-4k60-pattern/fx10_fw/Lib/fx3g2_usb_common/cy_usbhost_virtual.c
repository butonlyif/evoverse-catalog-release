/***************************************************************************//**
* \file cy_usbhost_virtual.c
* \version 1.0
*
* Test code used for unit testing of the USB Device Stack handlers.
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

#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"
#include "event_groups.h"

#include "cy_pdl.h"
#include "cy_device.h"
#include "cy_usb_common.h"
#include "cy_usbss_cal_drv.h"
#include "cy_usbhost_virtual.h"
#include <string.h>

#if defined(__cplusplus)
extern "C" {
#endif

/*
 * Global variables used for virtual Host:
 * hostTaskHandle: Virtual Host runs as thread and this is handle for the same.
 * hostMsgQueue: Virtual host waits on this queue for message from device.
 * pHostCalCtxt: Context has callback pointer which is used to send msg to
 *               device ie USBD.
 * hostState:
 * cmdState:
 * */
TaskHandle_t hostTaskHandle;
QueueHandle_t hostMsgQueue;
cy_stc_usbss_cal_ctxt_t *pHostCalCtxt;
uint32_t hostState;
uint32_t cmdState;

/* Get Descriptor Setup pkt */
uint8_t getDevDscrSetup[] = {0x80,0x06,0x00,0x01,0x00,0x00,0x40,0x00};
/* Set Address Setup pkt */
uint8_t setAddrSetup[] = {0x00,0x05,0x26,0x00,0x00,0x00,0x00,0x00};
/* Get Config Descriptor  */
uint8_t GetConfigDscrSetUp[] = {0x80,0x06,0x00,0x02,0x00,0x00,0x20,0x00};
/* SetConfig  setup packet */
uint8_t setConfigSetup[] = {0x00,0x09,0x01,0x00,0x00,0x00,0x00,0x00};

/*
 * Function: hostInit()
 * Description: It initializes virtual host which includes
 *              creation of task as well as message queue.
 * Parameter: cy_stc_usbss_cal_ctxt_t.
 * return: None
 * Note: This init should be called after APP/USBD and other initialization.
 *       This should be last call in init process.
 */
void
hostInit (cy_stc_usbss_cal_ctxt_t *pCalCtxt)
{
    BaseType_t status = pdFALSE;
    cy_stc_usb_host_msg_t msgToHost;
    BaseType_t  xHigherPriorityTaskWoken;

    /*
     * Assign pCalCtxt for callback, create task and message queue which are
     * global variable.
     */
    DBG_vHOST_INFO("HostInit\r\n");
    pHostCalCtxt = pCalCtxt;
    /* queue size 8, message size 32 byte */
    hostMsgQueue = xQueueCreate(8, 32);
   /* Create task and check status to confirm task created properly. */
    status = xTaskCreate(virtualHost, "hostTask", 800, NULL, 8, &hostTaskHandle);

    hostState = HOST_STATE_INIT;
    msgToHost.type = MSG_TO_HOST_INIT;
    status = xQueueSendFromISR(hostMsgQueue, &msgToHost,
                                            &(xHigherPriorityTaskWoken));
     if (status != pdPASS) {
        DBG_vHOST_INFO("NotAbleToSendMsg\r\n");
     }
    return;
}

/*
 * Function: virtualHost()
 * Description: Host functionality for controll trnasfer is implemented here.
 *              Setup/Data/StatusStage is implemented here.
 * Parameter: taskParam.
 * return: None.
 */
void
virtualHost (void *pTaskParam)
{
    uint32_t setup1, setup2;
    bool yield_reqd = false;
    /* cy_stc_usb_cal_msg_t used to send message to device. */
    cy_stc_usb_cal_msg_t msg = {CY_USB_CAL_MSG_INVALID, 0, 0};
    BaseType_t status = pdFALSE;
    cy_stc_usb_host_msg_t msgReceived;
    cy_stc_usb_host_msg_t msgToHost;
    BaseType_t  xHigherPriorityTaskWoken;

    do {

        status = xQueueReceive(hostMsgQueue, &msgReceived, 100);
        if (status != pdPASS) {
            vTaskDelay(pdMS_TO_TICKS(5));
            continue;
        }

        switch (msgReceived.type) {
            case MSG_TO_HOST_INIT:
                DBG_vHOST_INFO("MSG_INIT\r\n");
                /* In HOST INIT, send RESET MESSAGE to device. */
                msg.type = CY_USB_CAL_MSG_RESET;
                msg.data[0] = 0x00;
                msg.data[1] = 0x00;
                /* send message to USBD layer*/
                yield_reqd |= Cy_USBSS_Cal_SendMsg(pHostCalCtxt, &msg);
                /*
                 * After sending RESET MESSAGE, host can move its state machine
                 * by sending RESET_DONE messge to itself.
                 */
                msgToHost.type = MSG_TO_HOST_RESET_DONE;
                status = xQueueSendFromISR(hostMsgQueue, &msgToHost,
                                            &(xHigherPriorityTaskWoken));
                break;

            case MSG_TO_HOST_RESET_DONE:
                DBG_vHOST_INFO("MSG_RESET_DONE\r\n");
                /*
                 * In RESET_DONE message, Move State machine to sending
                 * SETUP token by sending message to itself.
                 * TBD: RESET_DONE intemediate state can be removed later.
                 */
                hostState = HOST_STATE_GET_DEV_DSCR;
                msgToHost.type = MSG_TO_HOST_SETUP;
                status = xQueueSendFromISR(hostMsgQueue, &msgToHost,
                                            &(xHigherPriorityTaskWoken));
                break;

            case MSG_TO_HOST_SETUP:
                DBG_vHOST_INFO("MSG_SETUP\r\n");
                /*
                 * In this state, required setup packet will be sent
                 * to device.
                 */
                while (1) {
                    if (hostState ==  HOST_STATE_ENUM_DONE) {
                        DBG_vHOST_INFO("HOST_ENUM_DONE...\r\n");
                        return;
                    }

                    if (hostState == HOST_STATE_GET_DEV_DSCR) {
                        DBG_vHOST_INFO("DEV_DSCR\r\n");
                        memcpy(&setup1, getDevDscrSetup, 4);
                        memcpy(&setup2, (getDevDscrSetup+ 4), 4);
                        msg.type = CY_USB_CAL_MSG_PROT_SUTOK;
                        break;
                    }

                    if (hostState == HOST_STATE_SET_ADDR) {
                        DBG_vHOST_INFO("SET_ADDR\r\n");
                        msg.type = CY_USB_CAL_MSG_SETADDR;
                        break;
                    }

                    if (hostState == HOST_STATE_GET_DEV_DSCR1) {
                        DBG_vHOST_INFO("DEV_DSCR1\r\n");
                        memcpy(&setup1, getDevDscrSetup, 4);
                        memcpy(&setup2, (getDevDscrSetup+ 4), 4);
                        msg.type = CY_USB_CAL_MSG_PROT_SUTOK;
                        break;
                    }

                    if (hostState == HOST_STATE_GET_CFG_DSCR) {
                        DBG_vHOST_INFO("CFG_DSCR\r\n");
                        memcpy(&setup1, GetConfigDscrSetUp, 4);
                        memcpy(&setup2, (GetConfigDscrSetUp + 4), 4);
                        DBG_vHOST_INFO("s1:%x s2:%x\r\n", setup1, setup2);
                        msg.type = CY_USB_CAL_MSG_PROT_SUTOK;
                        break;
                    }

                    if (hostState ==  HOST_STATE_SET_CFG) {
                        DBG_vHOST_INFO("SET_CFG\r\n");
                        memcpy(&setup1, setConfigSetup, 4);
                        memcpy(&setup2, (setConfigSetup + 4), 4);
                        DBG_vHOST_INFO("setup1:%x setup2:%x\r\n", setup1, setup2);
                        msg.type = CY_USB_CAL_MSG_PROT_SUTOK;
                        break;
                    }
                }
                msg.data[0] = setup1;
                msg.data[1] = setup2;
                yield_reqd |= Cy_USBSS_Cal_SendMsg(pHostCalCtxt, &msg);
                vTaskDelay(pdMS_TO_TICKS(5));
                break;

            case MSG_TO_HOST_DATAIN:
                DBG_vHOST_INFO("MSG_DATAIN, Start Status Stage\r\n");
                /*
                 * Process Data based on host State and initiate status stage.
                 */
                msg.type = CY_USB_CAL_MSG_STATUS_STAGE;
                msg.data[0] = 0x00;
                msg.data[1] = 0x00;
                yield_reqd |= Cy_USBSS_Cal_SendMsg(pHostCalCtxt, &msg);
                vTaskDelay(pdMS_TO_TICKS(5));
                break;

            case MSG_TO_HOST_DATAOUT:
                DBG_vHOST_INFO("MSG_DATAOUT\r\n");
                break;

            case MSG_TO_HOST_ACK:
                DBG_vHOST_INFO("MSG_ACK\r\n");
                /*
                 * Control comes here means status stage of previous command
                 * is completed. Now its time to send next command. SET_ADDR
                 * does not have data stage so it will directly SEND ACK.
                 *
                 */
                while (1) {
                    if (hostState == HOST_STATE_GET_DEV_DSCR) {
                        DBG_vHOST_INFO("NS:SET_ADDR\r\n");
                        hostState = HOST_STATE_SET_ADDR;
                        break;
                    }
                    if (hostState == HOST_STATE_SET_ADDR) {
                        DBG_vHOST_INFO("NS:DEV_DSCR1\r\n");
                        hostState = HOST_STATE_GET_DEV_DSCR1;
                        break;
                    }
                    if (hostState == HOST_STATE_GET_DEV_DSCR1) {
                        DBG_vHOST_INFO("NS:CFG_DSCR\r\n");
                        hostState = HOST_STATE_GET_CFG_DSCR;
                        break;
                    }
                    if (hostState == HOST_STATE_GET_CFG_DSCR) {
                        DBG_vHOST_INFO("NS:SET_CFG\r\n");
                        hostState = HOST_STATE_SET_CFG;
                        break;
                    }
                    if (hostState == HOST_STATE_SET_CFG) {
                        DBG_vHOST_INFO("NS:ENUM_DONE\r\n");
                        hostState = HOST_STATE_ENUM_DONE;
                        break;
                    }
                };
                msgToHost.type = MSG_TO_HOST_SETUP;
                status = xQueueSendFromISR(hostMsgQueue, &msgToHost,
                                            &(xHigherPriorityTaskWoken));
                vTaskDelay(pdMS_TO_TICKS(5));
                break;

            default:
                DBG_vHOST_INFO("MSG_DEFAULT\r\n");
                break;
        }
    } while (1);
}

#if defined(__cplusplus)
}
#endif

/* EOF */

