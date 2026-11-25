/***************************************************************************//**
* \file cy_autanalog_ptc.h
* \version 1.0
*
* Header file for the Programmable Threshold Comparator (PTComp) subsystem of the
* Low Power Peripheral Analog System
*
********************************************************************************
* \copyright
* Copyright 2022 Cypress Semiconductor Corporation
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

/**
* \addtogroup group_autanalog_ptcomp
* \{
* This driver provides API functions to configure the analog PTComp within
* Low Power Peripheral Analog System.
*
* \defgroup group_autanalog_ptcomp_macros Macros
* \defgroup group_autanalog_ptcomp_functions Functions
*   \{
*       \defgroup group_autanalog_ptcomp_functions_init Initialization Functions
*   \}
* \defgroup group_autanalog_ptcomp_data_structures Data Structures
* \defgroup group_autanalog_ptcomp_enums Enumerated Types
*/
#if !defined(CY_AUTANALOG_PTC_H)
#define CY_AUTANALOG_PTC_H

#include "cy_device.h"

#ifdef CY_IP_MXS22LPPASS_PTC

#include "cy_autanalog_common.h"

#if defined(__cplusplus)
extern "C" {
#endif

/** \addtogroup group_autanalog_ptcomp_macros
* \{
*/

/** Maximum number of dynamic configurations for PTComp */
#define CY_AUTANALOG_PTCOMP_DYN_CFG_MAX                          (8UL)

/** Maximum number of post-processing configurations for PTComp */
#define CY_AUTANALOG_PTCOMP_PP_CFG_MAX                           (2UL)

/** \} group_autanalog_ptcomp_macros */

/***************************************
*       Enumerated Types
***************************************/

/**
* \addtogroup group_autanalog_ptcomp_enums
* \{
*/

/**
* Configure power mode usage for each Comp.
* Each power setting consumes different levels of current.
* See the device datasheet for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_COMP_PWR_OFF    = 0UL, /**< Comp powering is off */
    CY_AUTANALOG_PTCOMP_COMP_PWR_ULP    = 1UL, /**< Comp power mode is ultra low */
    CY_AUTANALOG_PTCOMP_COMP_PWR_LP     = 2UL, /**< Comp power mode is low */
    CY_AUTANALOG_PTCOMP_COMP_PWR_NORMAL = 3UL, /**< Comp power mode is normal */

} cy_en_autanalog_ptcomp_comp_pwr_t;


/**
* Enable 30mV hysteresis for each Comp.
* See the device datasheet for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_COMP_HYST_OFF   = 0UL, /**< Comp hysteresis is OFF */
    CY_AUTANALOG_PTCOMP_COMP_HYST_ON    = 1UL, /**< Comp hysteresis is ON */

} cy_en_autanalog_ptcomp_comp_hyst_t;


/**
* Configure the type of edge that will trigger a comparator interrupt or
* disable the interrupt entirely.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_COMP_INT_DISABLED     = 0UL, /**< Disabled, no interrupts will be detected */
    CY_AUTANALOG_PTCOMP_COMP_INT_EDGE_RISING  = 1UL, /**< Rising edge generates an interrupt */
    CY_AUTANALOG_PTCOMP_COMP_INT_EDGE_FALLING = 2UL, /**< Falling edge generates an interrupt */
    CY_AUTANALOG_PTCOMP_COMP_INT_EDGE_BOTH    = 3UL, /**< Both edges generate an interrupt */

} cy_en_autanalog_ptcomp_comp_int_t;


/**
* The PTComp has possibility to configuring the switch routing matrix
* for connection of the inputs of each Comp to the different sources.
* See the device Architecture Technical Reference Manual for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_COMP_COREIO0   = 0UL,  /**< Comp input connected to COREIO_0 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO1   = 1UL,  /**< Comp input connected to COREIO_1 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO2   = 2UL,  /**< Comp input connected to COREIO_2 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO3   = 3UL,  /**< Comp input connected to COREIO_3 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO4   = 4UL,  /**< Comp input connected to COREIO_4 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO5   = 5UL,  /**< Comp input connected to COREIO_5 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO6   = 6UL,  /**< Comp input connected to COREIO_6 */
    CY_AUTANALOG_PTCOMP_COMP_COREIO7   = 7UL,  /**< Comp input connected to COREIO_7 */
    CY_AUTANALOG_PTCOMP_COMP_CTBL0_OA0 = 8UL,  /**< Comp input connected to CTBL0 OA0 output */
    CY_AUTANALOG_PTCOMP_COMP_CTBL0_OA1 = 9UL,  /**< Comp input connected to CTBL0 OA1 output */
    CY_AUTANALOG_PTCOMP_COMP_CTBL1_OA0 = 10UL, /**< Comp input connected to CTBL1 OA0 output */
    CY_AUTANALOG_PTCOMP_COMP_CTBL1_OA1 = 11UL, /**< Comp input connected to CTBL1 OA1 output */
    CY_AUTANALOG_PTCOMP_COMP_VREF0     = 12UL, /**< Comp input connected to VREF0 */
    CY_AUTANALOG_PTCOMP_COMP_VREF1     = 13UL, /**< Comp input connected to VREF1 */
    CY_AUTANALOG_PTCOMP_COMP_VREF2     = 14UL, /**< Comp input connected to VREF2 */
    CY_AUTANALOG_PTCOMP_COMP_VREF3     = 15UL, /**< Comp input connected to VREF3 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO0     = 16UL, /**< Comp input connected to GPIO_0 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO1     = 17UL, /**< Comp input connected to GPIO_1 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO2     = 18UL, /**< Comp input connected to GPIO_2 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO3     = 19UL, /**< Comp input connected to GPIO_3 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO4     = 20UL, /**< Comp input connected to GPIO_4 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO5     = 21UL, /**< Comp input connected to GPIO_5 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO6     = 22UL, /**< Comp input connected to GPIO_6 */
    CY_AUTANALOG_PTCOMP_COMP_GPIO7     = 23UL, /**< Comp input connected to GPIO_7 */

} cy_en_autanalog_ptcomp_comp_mux_t;


/**
* The source for post-processing logic.
* See the device datasheet for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_PP_IN_SRC_DISABLED  = 0UL, /**< Source for post-processing is disabled */
    CY_AUTANALOG_PTCOMP_PP_IN_SRC_COMP0     = 1UL, /**< Output of COMP0 used as a source in post-processing */
    CY_AUTANALOG_PTCOMP_PP_IN_SRC_COMP1     = 2UL, /**< Output of COMP1 used as a source in post-processing */

} cy_en_autanalog_ptcomp_pp_input_src_t;


/**
* Level or edge sensing type for handling two outputs from Comps in post-processing.
* See the device datasheet for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_PP_IN_TYPE_LEVEL        = 0UL, /**< Level sensitive data for post-process */
    CY_AUTANALOG_PTCOMP_PP_IN_TYPE_EDGE_RISING  = 1UL, /**< Rising edge sensitive data for post-process */
    CY_AUTANALOG_PTCOMP_PP_IN_TYPE_EDGE_FALLING = 2UL, /**< Falling edge sensitive data for post-process */
    CY_AUTANALOG_PTCOMP_PP_IN_TYPE_EDGE_BOTH    = 3UL, /**< Both edges sensitive data for post-process */

} cy_en_autanalog_ptcomp_pp_input_type_t;


/**
* Post Processor Counter Mode.
* See the device Architecture Technical Reference Manual for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_PP_CNT_MODE_DIRECT = 0UL, /**< Direct mode of post-process */
    CY_AUTANALOG_PTCOMP_PP_CNT_MODE_FRAME  = 1UL, /**< Frame mode of post-process */
    CY_AUTANALOG_PTCOMP_PP_CNT_MODE_WINDOW = 2UL, /**< Window mode of post-process */

} cy_en_autanalog_ptcomp_pp_cnt_mode_t;


/**
* Size of counter window in number of clock cycles for PTComp.
* See the device Architecture Technical Reference Manual for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_PP_WINDOW_TWO              = 0UL, /**< Window size of 2 */
    CY_AUTANALOG_PTCOMP_PP_WINDOW_FOUR             = 1UL, /**< Window size of 4 */
    CY_AUTANALOG_PTCOMP_PP_WINDOW_EIGHT            = 2UL, /**< Window size of 8 */
    CY_AUTANALOG_PTCOMP_PP_WINDOW_SIXTEEN          = 3UL, /**< Window size of 16 */
    CY_AUTANALOG_PTCOMP_PP_WINDOW_THIRTY_TWO       = 4UL, /**< Window size of 32 */
    CY_AUTANALOG_PTCOMP_PP_WINDOW_SIXTY_FOUR       = 5UL, /**< Window size of 64 */
    CY_AUTANALOG_PTCOMP_PP_WINDOW_ONE_TWENTY_EIGHT = 6UL, /**< Window size of 128 */

} cy_en_autanalog_ptcomp_pp_window_size_t;


/**
* Logical function of lookup table (truth table) for handling two outputs from Comps in post-processing.
* See the device Architecture Technical Reference Manual for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A           = 0UL,  /**< Boolean function A */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_BAR_AND_B = 1UL,  /**< Boolean function (NOT A) AND B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_B           = 2UL,  /**< Boolean function B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_AND_B     = 3UL,  /**< Boolean function A AND B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_AND_B_BAR = 4UL,  /**< Boolean function A AND (NOT B) */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_XOR_B     = 5UL,  /**< Boolean function A XOR B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_OR_B      = 6UL,  /**< Boolean function A OR B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_NOR_B     = 7UL,  /**< Boolean function NOT (A OR B) */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_XNOR_B    = 8UL,  /**< Boolean function (A OR (NOT B)) AND ((NOT A) OR B) */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_B_BAR       = 9UL,  /**< Boolean function NOT B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_OR_B_BAR  = 10UL, /**< Boolean function A OR (NOT B) */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_BAR       = 11UL, /**< Boolean function NOT A */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_BAR_OR_B  = 12UL, /**< Boolean function (NOT A) OR B */
    CY_AUTANALOG_PTCOMP_PP_DATA_FUNC_A_NAND_B    = 13UL, /**< Boolean function NOT (A AND B) */

} cy_en_autanalog_ptcomp_pp_data_func_t;


/**
* Range condition for post-processing counter.
* See the device Architecture Technical Reference Manual for more detail.
*/
typedef enum
{
    CY_AUTANALOG_PTCOMP_PP_COND_BELOW   = 0UL, /**< Counter value is below threshold */
    CY_AUTANALOG_PTCOMP_PP_COND_INSIDE  = 1UL, /**< Counter value is inside range */
    CY_AUTANALOG_PTCOMP_PP_COND_ABOVE   = 2UL, /**< Counter value is above threshold */
    CY_AUTANALOG_PTCOMP_PP_COND_OUTSIDE = 3UL, /**< Counter value is outside range */

} cy_en_autanalog_ptcomp_pp_cond_t;

/** \} group_autanalog_ptcomp_enums */

/***************************************
*       Configuration Structures
***************************************/

/**
* \addtogroup group_autanalog_ptcomp_data_structures
* \{
*/

/**
* The post-processing configuration for PTComp.
*/
typedef struct
{
    cy_en_autanalog_ptcomp_pp_input_src_t   inpSrc;         /**< Input source for post-processing */
    cy_en_autanalog_ptcomp_pp_input_type_t  inputType;      /**< Sensing type of Comp outputs */
    cy_en_autanalog_ptcomp_pp_cnt_mode_t    cntMode;        /**< Post-processor counter mode */
    cy_en_autanalog_ptcomp_pp_data_func_t   dataFunction;   /**< Logical function for lookup table */
    cy_en_autanalog_ptcomp_pp_window_size_t windowSize;     /**< Size of counter window in post-processing */
    uint16_t                             period;         /**< Post-processing frame period in number of clock cycles for PTComp */
    cy_en_autanalog_ptcomp_pp_cond_t        limitCondition; /**< Limit condition for post-processing counter */
    uint16_t                             thresholdLow;   /**< Low threshold value for post-processing counter */
    uint16_t                             thresholdHigh;  /**< High threshold value for post-processing counter */

} cy_stc_autanalog_ptcomp_comp_pp_t;


/**
* The static configuration structure includes configuration settings that are application specific
* but are intended to remain static for any given application of the PTComp.
*/
typedef struct
{
    uint16_t                         lpDivPtcomp;   /**< Clock divider for the
                                                     *   \ref group_autanalog_ptcomp subsystem,
                                                     *   valid range is 1...1024
                                                     */
    /**< Static part of configuration for Comp0 */
    cy_en_autanalog_ptcomp_comp_pwr_t   powerModeComp0; /**< Comp0 power level */
    cy_en_autanalog_ptcomp_comp_hyst_t  compHystComp0;  /**< Comp0 30mV hysteresis */
    cy_en_autanalog_ptcomp_comp_int_t   compEdgeComp0;  /**< Comp0 interrupt and trigger generation mode */

    /**< Static part of configuration for Comp1 */
    cy_en_autanalog_ptcomp_comp_pwr_t   powerModeComp1; /**< Comp1 power level */
    cy_en_autanalog_ptcomp_comp_hyst_t  compHystComp1;  /**< Comp1 30mV hysteresis */
    cy_en_autanalog_ptcomp_comp_int_t   compEdgeComp1;  /**< Comp1 interrupt and trigger generation mode */

    /**< Post-processing part of configuration for PTComp */
    uint8_t                          compPpCfgNum;   /**< Overall number of post-processing configurations for PTComp */
    cy_stc_autanalog_ptcomp_comp_pp_t * compPpCfgArr;   /**< Pointer to the array of post-processing configurations for PTComp */

} cy_stc_autanalog_ptcomp_comp_sta_t;


/**
* The dynamic configuration structure includes Comp configuration
* that is adjusted by the Autonomous Controller during operation.
*/
typedef struct
{
    cy_en_autanalog_ptcomp_comp_mux_t ninvInpMux; /**< Comp non-inverting input connection */
    cy_en_autanalog_ptcomp_comp_mux_t invInpMux;  /**< Comp inverting input connection */

} cy_stc_autanalog_ptcomp_comp_dyn_t;


/**
* Configuration structure to set up the entire PTComp to be used with \ref Cy_AutAnalog_PTComp_LoadConfig.
*/
typedef struct
{
    /**< Static part of configuration */
    cy_stc_autanalog_ptcomp_comp_sta_t * ptcompStaCfg;    /**< Pointer to the array of static configurations for Comps */

    /**< Dynamic part of configuration */
    uint8_t                           ptcompDynCfgNum; /**< Overall number of dynamic configurations for Comps */
    cy_stc_autanalog_ptcomp_comp_dyn_t * ptcompDynCfgArr; /**< Pointer to the array of dynamic configurations for Comps */

} cy_stc_autanalog_ptcomp_t;


/** The PTComp section of the State Transition Table state, to be used in \ref cy_stc_autanalog_stt_t */
typedef struct
{
    bool     unlock;         /**< PTComp Unlock
                              * 0, Lock:
                              *     PTComp fields PTC_CMPx_EN, PTC_CMPx_CFG
                              *     do NOT get updated
                              * 1, Unlock:
                              *     PTComp fields PTC_CMPx_EN, PTC_CMPx_CFG
                              *     do get updated
                              */
    bool     enableComp0;    /**< Enable Comp0. */
    uint8_t  dynCfgIdxComp0; /**< PTComp CMP0 dynamic configuration selection index,
                              *   see \ref cy_stc_autanalog_ptcomp_comp_dyn_t,
                              *   the range is 0 to 7.
                              */
    bool     enableComp1;    /**< Enable Comp1. */
    uint8_t  dynCfgIdxComp1; /**< PTComp CMP1 dynamic configuration selection index,
                              *   see \ref cy_stc_autanalog_ptcomp_comp_dyn_t,
                              *   the range is 0 to 7.
                              */
} cy_stc_autanalog_stt_ptcomp_t;

/** \} group_autanalog_ptcomp_data_structures */

/***************************************
*        Function Prototypes
***************************************/

/**
* \addtogroup group_autanalog_ptcomp_functions
* \{
*/

/**
* \addtogroup group_autanalog_ptcomp_functions_init
* This set of functions are for configuring the PTComp.
* \{
*/

/*******************************************************************************
* Function Name: Cy_AutAnalog_PTComp_LoadConfig
****************************************************************************//**
*
* Configuring both Comps in the PTComp according to the provided settings.
*
* \param ptcompIdx
* PTComp block index within Low Power Peripheral Analog System.
*
* \param ptcompCfg
* Pointer to structure containing configuration data for entire PTComp,
* \ref cy_stc_autanalog_ptcomp_t.
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_PTComp_LoadConfig(uint8_t ptcompIdx, const cy_stc_autanalog_ptcomp_t * ptcompCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_PTComp_LoadStaticConfig
****************************************************************************//**
*
* Configuring the particular Comp according to the provided settings in
* static configuration structure.
*
* \param ptcompIdx
* PTComp block index within Low Power Peripheral Analog System.
*
* \param ptcompStaCfg
* Pointer to structure containing static configuration data for the Comp,
* \ref cy_stc_autanalog_ptcomp_comp_sta_t.
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_PTComp_LoadStaticConfig(uint8_t ptcompIdx, const cy_stc_autanalog_ptcomp_comp_sta_t * ptcompStaCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_PTComp_LoadDynamicConfig
****************************************************************************//**
*
* Defines configuration settings that is adjusted by the Autonomous Controller during operation
* for both Comps in the PTComp according to the provided settings in dynamic configuration structure.
*
* \param ptcompIdx
* PTComp block index within Low Power Peripheral Analog System.
*
* \param ptcompDynCfgNum
* Actual number of dynamic configurations for PTComp.
*
* \param ptcompDynCfgArr
* Pointer to structure containing dynamic configuration data for both Comps in the PTComp,
* \ref cy_stc_autanalog_ptcomp_comp_dyn_t.
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_PTComp_LoadDynamicConfig(uint8_t ptcompIdx, uint8_t ptcompDynCfgNum, const cy_stc_autanalog_ptcomp_comp_dyn_t * ptcompDynCfgArr);


/*******************************************************************************
* Function Name: Cy_AutAnalog_PTComp_Read
****************************************************************************//**
*
* Returns status of comparator output.
*
* \param ptcompIdx
* PTComp block index within Low Power Peripheral Analog System
*
* \param compIdx
* Comparator index within PTComp
*
* \return
* Status of Comp output: false means low, true means high.
*
*******************************************************************************/
bool Cy_AutAnalog_PTComp_Read(uint8_t ptcompIdx, uint8_t compIdx);

/** \} */

/** \} group_autanalog_ptcomp_functions */

#if defined(__cplusplus)
}
#endif

#endif /* CY_IP_MXS22LPPASS_PTC */

#endif /** !defined(CY_AUTANALOG_PTC_H) */

/** \} group_autanalog_ptcomp */

/* [] END OF FILE */
