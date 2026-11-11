/***************************************************************************//**
* \file cy_usbhost_virtual.h
* \version 1.0
*
* Test code used for unit testing of the FX10 USB Device Stack.
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

#if !defined(CY_USBHOST_VIRTUAL_H)
#define CY_USBHOST_VIRTUAL_H

#include <stdbool.h>
#include "cy_device.h"
#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#if defined(__cplusplus)
extern "C" {
#endif

#define CHANGE_ENDIANITY(x)  (((x & 0x000000FF) << 24) | \
                              ((x & 0x0000FF00) << 8) | \
                              ((x &0x00FF0000) >> 8) | \
                              ((x & 0xFF000000) >> 24))

#define MSG_TO_HOST_INIT          0
#define MSG_TO_HOST_RESET_DONE    1
#define MSG_TO_HOST_SETUP         2
#define MSG_TO_HOST_DATAIN        3
#define MSG_TO_HOST_DATAOUT       4
#define MSG_TO_HOST_ACK           5

/*
 * HOST_STATE_GET_DEV_DSCR1 to determine next command as SET_ADDRESS or GET_CONFIG
 */
#define HOST_STATE_INIT          0
#define HOST_STATE_GET_DEV_DSCR  1
#define HOST_STATE_GET_DEV_DSCR1 2
#define HOST_STATE_SET_ADDR      3
#define HOST_STATE_GET_CFG_DSCR  4
#define HOST_STATE_SET_CFG       5
#define HOST_STATE_ENUM_DONE     6

/* Messages for Host */
#define MSG_TYPE_DEV_DSCR 0
#define MSG_TYPE_CFG_DSCR 1
#define MSG_TYPE_ACK      2


extern TaskHandle_t hostTaskHandle;
extern QueueHandle_t hostMsgQueue;
extern cy_stc_usbss_cal_ctxt_t *pHostCalCtxt;
extern uint32_t hostState;
extern uint32_t cmdState;

void hostInit(cy_stc_usbss_cal_ctxt_t *pCalCtxt);
void virtualHost(void *pTaskParam);

#if defined(__cplusplus)
}
#endif

#endif /* CY_USBHOST_VIRTUAL_H */
