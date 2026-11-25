/***************************************************************************//**
* \file cy_autanalog_ac.h
* \version 1.0
*
* Header file for the Autonomous Controller (AC) subsystem of the Low Power Peripheral Analog System.
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
* \addtogroup group_autanalog_ac
* \{
* This driver provides API functions to configure the Autonomous Controller subsystem
* within Low Power Peripheral Analog System.
*
* \defgroup group_autanalog_ac_macros Macros
* \defgroup group_autanalog_ac_functions Functions
* \defgroup group_autanalog_ac_data_structures Data Structures
* \defgroup group_autanalog_ac_enums Enumerated Types
*/

#if !defined(CY_AUTANALOG_AC_H)
#define CY_AUTANALOG_AC_H

#include "cy_autanalog_common.h"

#ifdef CY_IP_MXS22LPPASS

#include "cy_syspm.h"

#if defined(__cplusplus)
extern "C" {
#endif

/** \addtogroup group_autanalog_ac_macros
* \{
*/

#define CY_AUTANALOG_STATE_TRANSITION_TABLE_STATES_NUM           (64U) /**< The number of states in the State Transition Table. */
#define CY_AUTANALOG_TC_NUM                                      (4U)  /**< The number of Timer/Counter blocks. */
#define CY_AUTANALOG_TRIG_OUT_NUM                                (8U)  /**< The number of output trigger blocks. */

/** \cond INTERNAL */

/* Validation macro for State Transition Table register of AC */
#define AUTANALOG_STT_AC_CFG0_DOUT(value)                        ((value) <= ACTRLR_TTCFG_TT_CFG0_DOUT_Msk)

/** \endcond */

/** \} group_autanalog_ac_macros */

/***************************************
*       Enumerated Types
***************************************/

/**
* \addtogroup group_autanalog_ac_enums
* \{
*/

/**
* Operation status of the Autonomous Controller.
*/
typedef enum
{
    CY_AUTANALOG_AC_STATUS_STOPPED = 0UL, /**< The Autonomous Controller is idle. */
    CY_AUTANALOG_AC_STATUS_RUNNING = 1UL, /**< The Autonomous Controller is running. */
    CY_AUTANALOG_AC_STATUS_PAUSED  = 2UL, /**< The Autonomous Controller is paused. */

} cy_en_autanalog_ac_status_t;


/**
* Set of masks for GPIO outputs controlled by the Autonomous Controller,
* see \ref cy_stc_autanalog_ac_t.
*/
typedef enum
{
    CY_AUTANALOG_STT_AC_GPIO_OUT_DISABLED = 0x0UL, /**< Control of the GPIO outs is disabled. */
    CY_AUTANALOG_STT_AC_GPIO_OUT0         = 0x1UL, /**< The GPIO out0 is enabled. */
    CY_AUTANALOG_STT_AC_GPIO_OUT1         = 0x2UL, /**< The GPIO out1 is enabled. */
    CY_AUTANALOG_STT_AC_GPIO_OUT2         = 0x4UL, /**< The GPIO out2 is enabled. */
    CY_AUTANALOG_STT_AC_GPIO_OUT3         = 0x8UL, /**< The GPIO out3 is enabled. */

} cy_en_autanalog_stt_ac_gpio_out_t;


/**
* The Autonomous Controller action field in the State Transition Table,
* see \ref cy_stc_autanalog_stt_ac_t.
*/
typedef enum
{
    CY_AUTANALOG_STT_AC_ACTION_STOP                = 0UL,  /**< Stop the Autonomous Controller. */
    CY_AUTANALOG_STT_AC_ACTION_NEXT                = 1UL,  /**< Proceed to the next state in the State Transition Table (default state). */
    CY_AUTANALOG_STT_AC_ACTION_WAIT_FOR            = 2UL,  /**< Wait (indefinitely) for the associated CONDITION to be TRUE
                                                         *   before moving to the next state, see \ref cy_en_autanalog_stt_ac_condition_t.
                                                         */
    CY_AUTANALOG_STT_AC_ACTION_BRANCH_IF_TRUE      = 3UL,  /**< Check if CONDITION has occurred.
                                                         *   If it has, take the indicated branch (\ref cy_stc_autanalog_stt_ac_t),
                                                         *   if not, proceed to the next state.
                                                         */
    CY_AUTANALOG_STT_AC_ACTION_BRANCH_IF_FALSE     = 4UL,  /**< Check if CONDITION has occurred.
                                                         *   If it has proceed to the next state,
                                                         *   if not, take the indicated branch.
                                                         */
    CY_AUTANALOG_STT_AC_ACTION_BRANCH_IF_TRUE_CLR  = 5UL,  /**< Check if CONDITION has occurred.
                                                         *   If it has, take the indicated branch (\ref cy_stc_autanalog_stt_ac_t),
                                                         *   if not, proceed to the next state.
                                                         *   If the indicated branch is taken, all loop counters are cleared (reset).
                                                         */
    CY_AUTANALOG_STT_AC_ACTION_BRANCH_IF_FALSE_CLR = 6UL,  /**< Check if CONDITION has occurred.
                                                         *   If it has proceed to the next state,
                                                         *   if not, take the indicated branch.
                                                         *   If the indicated branch is taken, all loop counters are cleared (reset).
                                                         */
} cy_en_autanalog_stt_ac_action_t;


/**
* The Autonomous Controller condition field in the State Transition Table,
* see \ref cy_stc_autanalog_stt_ac_t.
*/
typedef enum
{
    CY_AUTANALOG_STT_AC_CONDITION_FALSE              = 0UL,  /**< Hardcoded FALSE value. */
    CY_AUTANALOG_STT_AC_CONDITION_TRUE               = 1UL,  /**< Hardcoded TRUE value. */
    CY_AUTANALOG_STT_AC_CONDITION_BLOCK_READY        = 2UL,  /**< Enabled block(s) are ready for use. */
    CY_AUTANALOG_STT_AC_CONDITION_CNT_DONE           = 3UL,  /**< Runout for an interval timer if the ACTION is WAIT_FOR or
                                                          *  runout for a loop counter, if the ACTION is BRANCH IF.
                                                          */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_DONE           = 4UL,  /**< SAR Sequencer DONE. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_EOS            = 5UL,  /**< SAR End of Scan (EOS) event. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_RANGE0         = 6UL,  /**< SAR Range/Pulse 0 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_RANGE1         = 7UL,  /**< SAR Range/Pulse 1 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_RANGE2         = 8UL,  /**< SAR Range/Pulse 2 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_RANGE3         = 9UL,  /**< SAR Range/Pulse 3 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_BUSY           = 10UL, /**< SAR Busy status. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_FIR0_DONE      = 11UL, /**< SAR FIR0 result done. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_FIR1_DONE      = 12UL, /**< SAR FIR1 result done. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_FIFO_DONE      = 13UL, /**< SAR FIFO done. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_FIR0_FIFO_DONE = 14UL, /**< SAR FIR0 FIFO done. */
    CY_AUTANALOG_STT_AC_CONDITION_SAR_FIR1_FIFO_DONE = 15UL, /**< SAR FIR1 FIFO done. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_STROBE0     = 16UL, /**< PTComp Post Processor 0 Strobe. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_STROBE1     = 17UL, /**< PTComp Post Processor 1 Strobe. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_CMP0        = 18UL, /**< PTComp CMP0 output. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_CMP1        = 19UL, /**< PTComp CMP1 output. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_RANGE0      = 20UL, /**< PTComp Post Processor 0 Range output. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_RANGE1      = 21UL, /**< PTComp Post Processor 1 Range output. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL0_CMP0         = 22UL, /**< CTB0 Comp0 output. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL0_CMP1         = 23UL, /**< CTB0 Comp1 output. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL1_CMP0         = 24UL, /**< CTB1 Comp0 output. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL1_CMP1         = 25UL, /**< CTB1 Comp1 output. */
    CY_AUTANALOG_STT_AC_CONDITION_CHIP_ACTIVE        = 32UL, /**< Chip Active Mode Status. */
    CY_AUTANALOG_STT_AC_CONDITION_CHIP_DEEPSLEEP     = 33UL, /**< Chip DeepSleep Mode Status. */
    CY_AUTANALOG_STT_AC_CONDITION_TR_AUTANALOG_IN0      = 34UL, /**< External trigger 0 (or the FW trigger 0). */
    CY_AUTANALOG_STT_AC_CONDITION_TR_AUTANALOG_IN1      = 35UL, /**< External trigger 1 (or the FW trigger 1). */
    CY_AUTANALOG_STT_AC_CONDITION_TR_AUTANALOG_IN2      = 36UL, /**< External trigger 2 (or the FW trigger 2). */
    CY_AUTANALOG_STT_AC_CONDITION_TR_AUTANALOG_IN3      = 37UL, /**< External trigger 3 (or the FW trigger 3). */
    CY_AUTANALOG_STT_AC_CONDITION_TR_AUTANALOG_IN_WAKE  = 38UL, /**< External trigger 0-3 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_TIMER_DONE_WAKE    = 39UL, /**< Long-term timer done wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL0_CMP0_WAKE    = 40UL, /**< CTB0 Comp0 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL0_CMP1_WAKE    = 41UL, /**< CTB0 Comp1 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL1_CMP0_WAKE    = 42UL, /**< CTB1 Comp0 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_CTBL1_CMP1_WAKE    = 43UL, /**< CTB1 Comp1 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_CMP0_WAKE   = 44UL, /**< PTComp CMP0 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_PTCOMP_CMP1_WAKE   = 45UL, /**< PTComp CMP1 wakeup. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL0        = 46UL, /**< FIFO Level 0 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL1        = 47UL, /**< FIFO Level 1 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL2        = 48UL, /**< FIFO Level 2 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL3        = 49UL, /**< FIFO Level 3 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL4        = 50UL, /**< FIFO Level 4 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL5        = 51UL, /**< FIFO Level 5 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL6        = 52UL, /**< FIFO Level 6 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_FIFO_LEVEL7        = 53UL, /**< FIFO Level 7 trigger. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC0_RANGE0        = 54UL, /**< DAC0 Range 0 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC0_RANGE1        = 55UL, /**< DAC0 Range 1 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC0_RANGE2        = 56UL, /**< DAC0 Range 2 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC0_EPOCH         = 57UL, /**< DAC0 end of waveform event. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC0_STROBE        = 58UL, /**< DAC0 strobed (used for determining when DAC has acknowledged DAC_INC/DAC_DEC). */
    CY_AUTANALOG_STT_AC_CONDITION_DAC1_RANGE0        = 59UL, /**< DAC1 Range 0 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC1_RANGE1        = 60UL, /**< DAC1 Range 1 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC1_RANGE2        = 61UL, /**< DAC1 Range 2 detection. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC1_EPOCH         = 62UL, /**< DAC1 end of waveform event. */
    CY_AUTANALOG_STT_AC_CONDITION_DAC1_STROBE        = 63UL, /**< DAC1 strobed (used for determining when DAC has acknowledged DAC_INC/DAC_DEC). */

} cy_en_autanalog_stt_ac_condition_t;


/**
* The FW input trigger registers of the Autonomous Controller.
*/
typedef enum
{
    CY_AUTANALOG_FW_TRIGGER0 = 0UL, /**< FW trigger register 0. */
    CY_AUTANALOG_FW_TRIGGER1 = 1UL, /**< FW trigger register 1. */
    CY_AUTANALOG_FW_TRIGGER2 = 2UL, /**< FW trigger register 2. */
    CY_AUTANALOG_FW_TRIGGER3 = 3UL, /**< FW trigger register 3. */

} cy_en_autanalog_fw_trigger_t;


/**
* The output trigger registers of the Autonomous Controller.
*/
typedef enum
{
    CY_AUTANALOG_AC_OUT_TRIGGER0 = 0UL, /**< AC output trigger register 0. */
    CY_AUTANALOG_AC_OUT_TRIGGER1 = 1UL, /**< AC output trigger register 1. */
    CY_AUTANALOG_AC_OUT_TRIGGER2 = 2UL, /**< AC output trigger register 2. */
    CY_AUTANALOG_AC_OUT_TRIGGER3 = 3UL, /**< AC output trigger register 3. */
    CY_AUTANALOG_AC_OUT_TRIGGER4 = 4UL, /**< AC output trigger register 4. */
    CY_AUTANALOG_AC_OUT_TRIGGER5 = 5UL, /**< AC output trigger register 5. */
    CY_AUTANALOG_AC_OUT_TRIGGER6 = 6UL, /**< AC output trigger register 6. */
    CY_AUTANALOG_AC_OUT_TRIGGER7 = 7UL, /**< AC output trigger register 7. */

} cy_en_autanalog_ac_out_trigger_idx_t;


/**
* The set of masks for the output trigger registers of the Autonomous Controller.
*/
typedef enum
{
    CY_AUTANALOG_AC_OUT_TRIG_MASK_EMPTY         =       0UL,        /**< The empty mask. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_CTBL0_COMP0   =       1UL << 0U,  /**< The CTB0, Comp0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_CTBL0_COMP1   =       1UL << 1U,  /**< The CTB0, Comp1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_CTBL1_COMP0   =       1UL << 2U,  /**< The CTB1, Comp0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_CTBL1_COMP1   =       1UL << 3U,  /**< The CTB1, Comp1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_PTCOMP_CMP0   =       1UL << 4U,  /**< The PTComp CMP0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_PTCOMP_CMP1   =       1UL << 5U,  /**< The PTComp CMP1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_PTCOMP_RANGE0 =       1UL << 6U,  /**< The PTComp, post processor 0 range. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_PTCOMP_RANGE1 =       1UL << 7U,  /**< The PTComp, post processor 1 range. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC0_RANGE0   =       1UL << 8U,  /**< The DAC0, range 0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC0_RANGE1   =       1UL << 9U,  /**< The DAC0, range 1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC0_RANGE2   =       1UL << 10U, /**< The DAC0, range 2. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC0_EPOCH    =       1UL << 11U, /**< The DAC0, epoch. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC1_RANGE0   =       1UL << 13U, /**< The DAC1, range 0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC1_RANGE1   =       1UL << 14U, /**< The DAC1, range 1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC1_RANGE2   =       1UL << 15U, /**< The DAC1, range 2. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_DAC1_EPOCH    =       1UL << 16U, /**< The DAC1, epoch. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL0   =       1UL << 17U, /**< The FIFO, level 0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_SAR_DONE      =       1UL << 18U, /**< The SAR, done. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_SAR_EOS       =       1UL << 19U, /**< The SAR, EOS. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL1   =       1UL << 20U, /**< The FIFO, level 1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_SAR_RANGE0    =       1UL << 21U, /**< The SAR, range 0. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_SAR_RANGE1    =       1UL << 22U, /**< The SAR, range 1. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_SAR_RANGE2    =       1UL << 23U, /**< The SAR, range 2. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_SAR_RANGE3    =       1UL << 24U, /**< The SAR, range 3. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL2   =       1UL << 25U, /**< The FIFO, level 2. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL3   =       1UL << 26U, /**< The FIFO, level 3. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL4   =       1UL << 27U, /**< The FIFO, level 4. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL5   =       1UL << 28U, /**< The FIFO, level 5. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL6   =       1UL << 29U, /**< The FIFO, level 6. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_FIFO_LEVEL7   =       1UL << 30U, /**< The FIFO, level 7. */
    CY_AUTANALOG_AC_OUT_TRIG_MASK_AC            = ((int32_t)(1UL << 31U)), /**< The Autonomous Controller. */

} cy_en_autanalog_ac_out_trigger_mask_t;

/** The Timer clock source */
typedef enum
{
    CY_AUTANALOG_TIMER_CLK_LP = 0UL, /**< Timer clocked from CLK_LP   */
    CY_AUTANALOG_TIMER_CLK_LF = 1UL, /**< Timer clocked from CLK_LF */

} cy_en_autanalog_timer_clk_src_t;

/** \} group_autanalog_ac_enums */

/***************************************
*       Configuration Structures
***************************************/

/**
* \addtogroup group_autanalog_ac_data_structures
* \{
*/

/** The Timer configuration structure */
typedef struct
{
    bool                         enable;  /**< Enable the Timer */
    cy_en_autanalog_timer_clk_src_t clkSrc;  /**< Clock source for the Timer */
    uint16_t                     period;  /**< The Timer Period */

} cy_stc_autanalog_timer_t;


/** The Autonomous Controller configuration structure */
typedef struct
{
    cy_en_autanalog_stt_ac_gpio_out_t gpioOutEn; /**< Enable control of the GPIO outputs for the AC. */
    cy_en_autanalog_ac_out_trigger_mask_t * mask[CY_AUTANALOG_TRIG_OUT_NUM]; /**< The masks for the output trigger registers,
                                                                              *   see \ref cy_en_autanalog_ac_out_trigger_mask_t
                                                                              */
    cy_stc_autanalog_timer_t          timer;     /**< The Timer configuration structure */

} cy_stc_autanalog_ac_t;


/** The Autonomous Controller itself state */
typedef struct
{
    cy_en_autanalog_ac_status_t status; /**< The current status of the Autonomous Controller. */
    uint8_t                  state;  /**< The current state of the Autonomous Controller in the State Transition Table. */

} cy_stc_autanalog_state_ac_t;


/** The Timer/Counter state of the Autonomous Controller */
typedef struct
{
    uint16_t                val;    /**< The current Timer/Counter value. */
    uint8_t                 state;  /**< The current State Transition Table state tied to this Timer/Counter. */
    bool                    busy;   /**< The current Timer/Counter busy/idle status. */

} cy_stc_autanalog_state_tc_t;


/** The Autonomous Controller state, used in the \ref Cy_AutAnalog_GetControllerState */
typedef struct
{
    bool                     lpModeEnabled;        /**< The current mode of the AC: false - HS, true - LP */
    cy_stc_autanalog_state_ac_t ac;                   /**< The current Autonomous Controller state. */
    cy_stc_autanalog_state_tc_t tc[CY_AUTANALOG_TC_NUM]; /**< The current Timer/Counter states. */

} cy_stc_autanalog_state_t;


/**
* The State Transition Table of the Autonomous Controller sub-system within
* the Low Power Peripheral Analog System.
*/
typedef struct
{
    bool                            unlock;      /**< Mode Unlock:
                                                  *   0, Lock: MODE does NOT get updated
                                                  *   1, Unlock: MODE does get updated
                                                  */
    bool                            lpMode;      /**< Operating Mode of Low Power Peripheral Analog System:
                                                  *   false - HS, true - LP
                                                  */
    cy_en_autanalog_stt_ac_condition_t condition;   /**< Condition field. */
    cy_en_autanalog_stt_ac_action_t    action;      /**< Action field. */
    uint8_t                         branchState; /**< Branch state field, the range is 0 to 63. */
    bool                            trigInt;     /**< Trigger/Interrupt generation field. */
    uint16_t                        count;       /**< Runout value for an interval timer if the ACTION is WAIT_FOR or
                                                  *   runout value for a loop counter, if the ACTION is BRANCH_IF.
                                                  *   The actual count is CNT value + 1, therefore the range is 1 to 256.
                                                  */
    cy_en_autanalog_stt_ac_gpio_out_t  gpioOut;     /**< Data out generation for
                                                  *   Low Power Peripheral Analog System
                                                  */
} cy_stc_autanalog_stt_ac_t;

/** \} group_autanalog_ac_data_structures */


/***************************************
*        Function Prototypes
***************************************/

/**
* \addtogroup group_autanalog_ac_functions
* \{
*/

/*******************************************************************************
* Function Name: Cy_AutAnalog_AC_LoadConfig
****************************************************************************//**
*
* Configuring the AC according to the provided settings.
*
* \param acCfg
* Pointer to structure containing configuration data for AC,
* \ref cy_stc_autanalog_ac_t.
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_AC_LoadConfig(const cy_stc_autanalog_ac_t * acCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_StartAutonomousControl
****************************************************************************//**
*
* Enables the autonomous control for the Low Power Peripheral Analog System.
* The Autonomous Controller takes over.
* \note This function is applicable while the Autonomous Controller is in STOPPED or PAUSED state.
* See \ref cy_stc_autanalog_state_ac_t for more details.
*
*******************************************************************************/
void Cy_AutAnalog_StartAutonomousControl(void);


/*******************************************************************************
* Function Name: Cy_AutAnalog_PauseAutonomousControl
****************************************************************************//**
*
* Pauses the autonomous control for the Low Power Peripheral Analog System.
* The state in the State Transition Table not changes.
*
* \return
* The current state in the State Transition Table.
*
*******************************************************************************/
uint8_t Cy_AutAnalog_PauseAutonomousControl(void);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SingleStepAutonomousControl
****************************************************************************//**
*
* Executes single-step in the autonomous control for the Low Power Peripheral Analog System.
* \note This function is applicable while the Autonomous Controller is in STOPPED or PAUSED state.
* See \ref cy_stc_autanalog_state_ac_t for more details.
*
*******************************************************************************/
void Cy_AutAnalog_SingleStepAutonomousControl(void);


/*******************************************************************************
* Function Name: Cy_AutAnalog_GetControllerState
****************************************************************************//**
*
* Provides status of operation for the Autonomous Controller.
*
* \param ctrlState
* Pointer to structure for receiving sate regarding operation conditions
* of the Autonomous Controller, \ref cy_stc_autanalog_state_t.
*
* \return
* Status of execution, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_GetControllerState(cy_stc_autanalog_state_t * ctrlState);


/*******************************************************************************
* Function Name: Cy_AutAnalog_OverrideControllerState
****************************************************************************//**
*
* Trigger the Autonomous Controller to override current state with new one,
* pointed to by parameter newState.
* \note This function is applicable while the Autonomous Controller is in STOPPED or PAUSED state.
* See \ref cy_stc_autanalog_state_ac_t for more details.
*
* \param newState
* Jumping to the new state in the State Transition Table.
*
*******************************************************************************/
void Cy_AutAnalog_OverrideControllerState(uint8_t newState);


/*******************************************************************************
* Function Name: Cy_AutAnalog_RunControllerState
****************************************************************************//**
*
* Trigger the Autonomous Controller to override current state and force it to run
* from the new state, pointed to by parameter newState.
* \note This function is applicable while the Autonomous Controller is in STOPPED or PAUSED state.
* See \ref cy_stc_autanalog_state_ac_t for more details.
*
* \param newState
* Jumping to the new state in the State Transition Table.
*
*******************************************************************************/
void Cy_AutAnalog_RunControllerState(uint8_t newState);


/*******************************************************************************
* Function Name: Cy_AutAnalog_IsBusy
****************************************************************************//**
*
* Check if Autonomous Analog is currently executing (running or stopped/paused).
*
* \return
* Status of operation, returns FALSE if stopped or paused and TRUE if running.
*
*******************************************************************************/
bool Cy_AutAnalog_IsBusy(void);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SetOutputTriggerMask
****************************************************************************//**
*
* Configures which bits of the mask register will create a trigger output.
*
* \param trigIdx
* The trigger register of the Autonomous Controller for initiation of the out trigger.
* See \ref cy_en_autanalog_ac_out_trigger_idx_t.
*
* \param mask
* The mask of the triggers allowable for activation. Each bit of this mask
* allows the particular out trigger in the Low Power Peripheral Analog System.
* See \ref cy_en_autanalog_ac_out_trigger_mask_t.
*
*******************************************************************************/
void Cy_AutAnalog_SetOutputTriggerMask(cy_en_autanalog_ac_out_trigger_idx_t trigIdx, cy_en_autanalog_ac_out_trigger_mask_t mask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_GetOutputTriggerMask
****************************************************************************//**
*
* Returns the out trigger mask. Each bit of this mask allows the particular
* out trigger in the Low Power Peripheral Analog System.
*
* \param trigIdx
* The trigger register of the Autonomous Controller for initiation of the out trigger.
* See \ref cy_en_autanalog_ac_out_trigger_idx_t.
*
* \return
* The mask of the triggers allowable for activation. Each bit of this mask
* allows the particular out trigger in the Low Power Peripheral Analog System.
* See \ref cy_en_autanalog_ac_out_trigger_mask_t.
*
*******************************************************************************/
cy_en_autanalog_ac_out_trigger_mask_t Cy_AutAnalog_GetOutputTriggerMask(cy_en_autanalog_ac_out_trigger_idx_t trigIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_FwTrigger
****************************************************************************//**
*
* Sends a firmware trigger to the Autonomous Controller.
* This trigger can be used as a condition in the State Transition Table.
*
* \param triggNum
* The trigger register of the Autonomous Controller for initiation of the FW trigger.
* See \ref cy_en_autanalog_fw_trigger_t.
*
*******************************************************************************/
void Cy_AutAnalog_FwTrigger(cy_en_autanalog_fw_trigger_t triggNum);


/*******************************************************************************
* Function Name: Cy_AutAnalog_DeepSleepCallback
****************************************************************************//**
*
* Changes mode of the FIFO to write only before enter into DeepSleep
* and restores it to write/read upon wake-up.
* Please note, change of FIFO operation mode is applicable only for configuration of
* the Autonomous Controller in LP mode.
*
* \param callbackParams
* Callback parameters, see \ref cy_stc_syspm_callback_params_t
*
* \param mode
* Callback mode, see \ref cy_en_syspm_callback_mode_t
*
* \return
* \ref cy_en_syspm_status_t
*
*******************************************************************************/
cy_en_syspm_status_t Cy_AutAnalog_DeepSleepCallback(cy_stc_syspm_callback_params_t *callbackParams, cy_en_syspm_callback_mode_t mode);

/** \} group_autanalog_ac_functions */

#if defined(__cplusplus)
}
#endif

#endif /* CY_IP_MXS22LPPASS */

#endif /** !defined(CY_AUTANALOG_AC_H) */

/** \} group_autanalog_ac */

/* [] END OF FILE */
