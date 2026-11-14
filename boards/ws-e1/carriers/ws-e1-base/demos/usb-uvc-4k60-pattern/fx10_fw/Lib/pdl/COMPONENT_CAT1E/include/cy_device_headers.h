/***************************************************************************//**
* \file cy_device_headers.h
*
* \brief
* Common header file to be included by the drivers.
*
********************************************************************************
* \copyright
* (c) (2016-2024), Cypress Semiconductor Corporation (an Infineon company) or
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

#ifndef _CY_DEVICE_HEADERS_H_
#define _CY_DEVICE_HEADERS_H_

#if defined (CYUSB4024_BZXI)
    #include "cyusb4024_bzxi.h"
#elif ((defined (CYUSB4014_FCAXI)) || (defined (CYUSB4014_BZXI)))
    #include "cyusb4014_fcaxi.h"
#elif defined (CYUSB4013_FCAXI)
    #include "cyusb4013_fcaxi.h"
#elif defined (CYUSB4012_FCAXI)
    #include "cyusb4012_fcaxi.h"
#elif defined (CYUSB4011_FCAXI)
    #include "cyusb4011_fcaxi.h"
#elif defined (CYUSB3084_FCAXI)
    #include "cyusb3084_fcaxi.h"
#elif defined (CYUSB3083_FCAXI)
    #include "cyusb3083_fcaxi.h"
#elif defined (CYUSB3082_FCAXI)
    #include "cyusb3082_fcaxi.h"
#elif defined (CYUSB3081_FCAXI)
    #include "cyusb3081_fcaxi.h"
#elif defined (CYUSB3284_FCAXI)
    #include "cyusb3284_fcaxi.h"
#elif defined (CYUSB3282_FCAXI)
    #include "cyusb3282_fcaxi.h"
#elif defined (CYUSB4022_FCAXI)
    #include "cyusb4022_fcaxi.h"
#elif defined (CYUSB4021_FCAXI)
    #include "cyusb4021_fcaxi.h"
#elif defined (CYUSB2315_BF104AXI)
    #include "cyusb2315_bf104axi.h"
#elif defined (CYUSB2315A_BF104AXI)
    #include "cyusb2315a_bf104axi.h"
#elif defined (CYUSB2316_BF104AXI)
    #include "cyusb2316_bf104axi.h"
#elif defined (CYUSB2317_BF104AXI)
    #include "cyusb2317_bf104axi.h"
#elif defined (CYUSB2318_BF104AXI)
    #include "cyusb2318_bf104axi.h"
#else
    #error Undefined part number. Consider updating PDL via ModusToolbox Library Manager to resolve the issue.
#endif

#endif /* _CY_DEVICE_HEADERS_H_ */


/* [] END OF FILE */
