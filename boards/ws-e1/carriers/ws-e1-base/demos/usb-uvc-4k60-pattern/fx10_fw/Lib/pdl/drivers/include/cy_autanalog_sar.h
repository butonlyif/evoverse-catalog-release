/***************************************************************************//**
* \file cy_autanalog_sar.h
* \version 1.0
*
* Header file for the SAR ADC subsystem of the Low Power Peripheral Analog System
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
* \addtogroup group_autanalog_sar
* \{
*   This driver provides API functions to configure the SAR ADC within Low Power Peripheral Analog System.
*
*   \defgroup group_autanalog_sar_macros Macros
*   \{
*     \defgroup group_autanalog_sar_hs_chan_macros High Speed Channel Enable masks
*     \defgroup group_autanalog_sar_lp_chan_macros Low Power Channel Enable masks
*   \}
*   \defgroup group_autanalog_sar_functions Functions
*   \defgroup group_autanalog_sar_data_structures Data Structures
*   \defgroup group_autanalog_sar_enums Enumerated Types
*
* \} group_autanalog_sar
*
* \addtogroup group_autanalog_fifo
* \{
*   This block collects the SAR data
*
*   \defgroup group_autanalog_fifo_macros Macros
*   \defgroup group_autanalog_fifo_functions Functions
*   \{
*       \defgroup group_autanalog_fifo_functions_int Interrupt Functions
*   \}
*   \defgroup group_autanalog_fifo_data_structures Data Structures
*   \defgroup group_autanalog_fifo_enums Enumerated Types
* \} group_autanalog_fifo
*/

#if !defined(CY_AUTANALOG_SAR_H)
#define CY_AUTANALOG_SAR_H

#include "cy_device.h"

#ifdef CY_IP_MXS22LPPASS_SAR

#include "cy_autanalog_common.h"

#if defined(__cplusplus)
extern "C" {
#endif

/** \addtogroup group_autanalog_sar_macros
* \{
*/

#define CY_AUTANALOG_SAR_SEQUENCER_NUM     (32UL) /**< The number of SAR High Speed and Low Power sequencers */
#define CY_AUTANALOG_SAR_SAMPLE_TIME_NUM   (4UL)  /**< The number of sample timers */
#define CY_AUTANALOG_SAR_LIMIT_CFG_NUM     (4UL)  /**< The number of limits configuration structures */
#define CY_AUTANALOG_SAR_CH_CORR_COEFF_NUM (8UL)  /**< The number of channel correction coefficients */
#define CY_AUTANALOG_SAR_FIR_NUM           (2UL)  /**< The number of FIR filters */
#define CY_AUTANALOG_SAR_FIR_TAP_NUM       (64UL) /**< The maximum number of taps in FIR filter configuration */


/** FIFO interrupt masks */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW0  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW0_INT_Msk)  /**< FIFO LEVEL 0 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW1  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW1_INT_Msk)  /**< FIFO LEVEL 1 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW2  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW2_INT_Msk)  /**< FIFO LEVEL 2 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW3  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW3_INT_Msk)  /**< FIFO LEVEL 3 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW4  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW4_INT_Msk)  /**< FIFO LEVEL 4 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW5  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW5_INT_Msk)  /**< FIFO LEVEL 5 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW6  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW6_INT_Msk)  /**< FIFO LEVEL 6 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_OVERFLOW7  (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_OVERFLOW7_INT_Msk)  /**< FIFO LEVEL 7 overflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW0 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW0_INT_Msk) /**< FIFO LEVEL 0 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW1 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW1_INT_Msk) /**< FIFO LEVEL 1 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW2 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW2_INT_Msk) /**< FIFO LEVEL 2 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW3 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW3_INT_Msk) /**< FIFO LEVEL 3 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW4 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW4_INT_Msk) /**< FIFO LEVEL 4 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW5 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW5_INT_Msk) /**< FIFO LEVEL 5 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW6 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW6_INT_Msk) /**< FIFO LEVEL 6 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_UNDERFLOW7 (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_UNDERFLOW7_INT_Msk) /**< FIFO LEVEL 7 underflow interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL0     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL0_INT_Msk)     /**< FIFO LEVEL 0 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL1     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL1_INT_Msk)     /**< FIFO LEVEL 1 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL2     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL2_INT_Msk)     /**< FIFO LEVEL 2 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL3     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL3_INT_Msk)     /**< FIFO LEVEL 3 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL4     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL4_INT_Msk)     /**< FIFO LEVEL 4 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL5     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL5_INT_Msk)     /**< FIFO LEVEL 5 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL6     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL6_INT_Msk)     /**< FIFO LEVEL 6 cause interrupt */
#define CY_AUTANALOG_INT_FIFO_LEVEL7     (LPPASS_MMIO_FIFO_INTR_CAUSE_FIFO_LEVEL7_INT_Msk)     /**< FIFO LEVEL 7 cause interrupt */


/** Combined FIFO interrupt mask */
#define CY_AUTANALOG_INTR_FIFO             (CY_AUTANALOG_INT_FIFO_OVERFLOW0 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW1 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW2 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW3 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW4 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW5 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW6 | \
                                         CY_AUTANALOG_INT_FIFO_OVERFLOW7 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW0 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW1 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW2 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW3 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW4 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW5 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW6 | \
                                         CY_AUTANALOG_INT_FIFO_UNDERFLOW7 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL0 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL1 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL2 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL3 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL4 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL5 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL6 | \
                                         CY_AUTANALOG_INT_FIFO_LEVEL7)


/** \addtogroup group_autanalog_sar_hs_chan_macros
* Only for the High Speed mode: can be ORed together and applied to the cy_stc_autanalog_sar_seq_tab_t::chanEn
* \{
*/
/** GPIO channels masks */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO_DISABLED           (0x00000000UL) /**< Disable usage of GPIO channels */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO0                   (0x00000001UL) /**< GPIO channel 0 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO1                   (0x00000002UL) /**< GPIO channel 1 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO2                   (0x00000004UL) /**< GPIO channel 2 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO3                   (0x00000008UL) /**< GPIO channel 3 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO4                   (0x00000010UL) /**< GPIO channel 4 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO5                   (0x00000020UL) /**< GPIO channel 5 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO6                   (0x00000040UL) /**< GPIO channel 6 */
#define CY_AUTANALOG_SAR_CHAN_MASK_GPIO7                   (0x00000080UL) /**< GPIO channel 7 */

/** MUX channels configurations */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX_DISABLED             (0x00000000UL) /**< MUX channels disabled */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX0_SINGLE_ENDED        (0x00000001UL) /**< MUX channel 0 single ended */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX1_SINGLE_ENDED        (0x00000002UL) /**< MUX channel 1 single ended */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX0_MUX1_SINGLE_ENDED   (0x00000003UL) /**< MUX channel 0,1 single ended */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX0_PSEUDO_DIFF         (0x00000004UL) /**< MUX channel pseudo differential */

/** MUX channels samplers masks */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX_SAMPLER_DISABLED    (0x00000000UL) /**< Disable MUX channels samplers */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX0_SAMPLER            (0x00000100UL) /**< Enable MUX channel 0 sampler */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX1_SAMPLER            (0x00000200UL) /**< Enable MUX channel 1 sampler */

/** \} group_autanalog_sar_hs_chan_macros */


/** \addtogroup group_autanalog_sar_lp_chan_macros
* Only for the Low Power mode: the enable mask of the single channel cy_stc_autanalog_sar_seq_tab_t::chanEn
* \{
*/
#define CY_AUTANALOG_SAR_CHAN_MUX_ENABLE                   (0x1UL)        /**< LP channel enable */

/** MUX channels configurations */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX0                     (0x00000000UL) /**< MUX channel 0 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX1                     (0x00000001UL) /**< MUX channel 1 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX2                     (0x00000002UL) /**< MUX channel 2 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX3                     (0x00000003UL) /**< MUX channel 3 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX4                     (0x00000004UL) /**< MUX channel 4 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX5                     (0x00000005UL) /**< MUX channel 5 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX6                     (0x00000006UL) /**< MUX channel 6 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX7                     (0x00000007UL) /**< MUX channel 7 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX8                     (0x00000008UL) /**< MUX channel 8 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX9                     (0x00000009UL) /**< MUX channel 9 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX10                    (0x0000000AUL) /**< MUX channel 10 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX11                    (0x0000000BUL) /**< MUX channel 11 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX12                    (0x0000000CUL) /**< MUX channel 12 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX13                    (0x0000000DUL) /**< MUX channel 13 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX14                    (0x0000000EUL) /**< MUX channel 14 */
#define CY_AUTANALOG_SAR_CHAN_CFG_MUX15                    (0x0000000FUL) /**< MUX channel 15 */

/** MUX channels masks */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX_DISABLED            (0x00000000UL) /**< Disable usage of MUX channels */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX0                    (0x00000001UL) /**< MUX channel 0 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX1                    (0x00000002UL) /**< MUX channel 1 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX2                    (0x00000004UL) /**< MUX channel 2 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX3                    (0x00000008UL) /**< MUX channel 3 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX4                    (0x00000010UL) /**< MUX channel 4 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX5                    (0x00000020UL) /**< MUX channel 5 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX6                    (0x00000040UL) /**< MUX channel 6 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX7                    (0x00000080UL) /**< MUX channel 7 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX8                    (0x00000100UL) /**< MUX channel 8 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX9                    (0x00000200UL) /**< MUX channel 9 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX10                   (0x00000400UL) /**< MUX channel 10 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX11                   (0x00000800UL) /**< MUX channel 11 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX12                   (0x00001000UL) /**< MUX channel 12 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX13                   (0x00002000UL) /**< MUX channel 13 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX14                   (0x00004000UL) /**< MUX channel 14 */
#define CY_AUTANALOG_SAR_CHAN_MASK_MUX15                   (0x00008000UL) /**< MUX channel 15 */

/** \} group_autanalog_sar_lp_chan_macros */

/** \addtogroup group_autanalog_fir_macros
* \{
*/

/** FIR channels configurations */
#define CY_AUTANALOG_SAR_CFG_FIR0                          (0x00000000UL) /**< FIR filter 0 */
#define CY_AUTANALOG_SAR_CFG_FIR1                          (0x00000001UL) /**< FIR filter 1 */

/** FIR channels masks */
#define CY_AUTANALOG_SAR_MASK_FIR_DISABLED                 (0x00000000UL) /**< Disable usage of FIR filters */
#define CY_AUTANALOG_SAR_MASK_FIR0                         (0x00000001UL) /**< FIR filter 0 */
#define CY_AUTANALOG_SAR_MASK_FIR1                         (0x00000002UL) /**< FIR filter 1 */

/** \} group_autanalog_fir_macros */


/** \addtogroup group_autanalog_fifo_macros
* \{
*/
#define CY_AUTANALOG_FIFO_BUFS_NUM                          (8UL)          /**< The maximum number of FIFO buffers */

/** \} group_autanalog_fifo_macros */


/** \cond INTERNAL */

/* Validation macros for FIFO INT registers */
#define CY_AUTANALOG_INTR_FIFO_MASK(interrupt)              (0UL == ((interrupt) & ~CY_AUTANALOG_INTR_FIFO))

/** \endcond */


/* Forward declarations */
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptCause(uint8_t fifoIdx);
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptStatus(uint8_t fifoIdx);
__STATIC_INLINE void Cy_AutAnalog_FIFO_ClearInterrupt(uint8_t fifoIdx, uint32_t interrupt);
__STATIC_INLINE void Cy_AutAnalog_FIFO_SetInterrupt(uint8_t fifoIdx, uint32_t interrupt);
__STATIC_INLINE void Cy_AutAnalog_FIFO_SetInterruptMask(uint8_t fifoIdx, uint32_t mask);
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptMask(uint8_t fifoIdx);
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptStatusMasked(uint8_t fifoIdx);


/** \} group_autanalog_sar_macros */


/***************************************
*       Enumerated Types
***************************************/

/**
* \addtogroup group_autanalog_sar_enums
* \{
*/

/** SAR input type selection */
typedef enum
{
    CY_AUTANALOG_SAR_INPUT_GPIO = 0U, /**< GPIO channels */
    CY_AUTANALOG_SAR_INPUT_MUX  = 1U, /**< MUX channels */

} cy_en_autanalog_sar_input_t;


/** Sampling Timer selection */
typedef enum
{
    CY_AUTANALOG_SAR_SAMPLE_TIME0 = 0U, /**< Sampling Timer 0 */
    CY_AUTANALOG_SAR_SAMPLE_TIME1 = 1U, /**< Sampling Timer 1 */
    CY_AUTANALOG_SAR_SAMPLE_TIME2 = 2U, /**< Sampling Timer 2 */
    CY_AUTANALOG_SAR_SAMPLE_TIME3 = 3U, /**< Sampling Timer 3 */

} cy_en_autanalog_sar_sample_time_t;


/** Configure number of samples for averaging */
typedef enum
{
    CY_AUTANALOG_SAR_ACC_CNT2   = 0UL, /**< Set samples averaged to 2 */
    CY_AUTANALOG_SAR_ACC_CNT4   = 1UL, /**< Set samples averaged to 4 */
    CY_AUTANALOG_SAR_ACC_CNT8   = 2UL, /**< Set samples averaged to 8 */
    CY_AUTANALOG_SAR_ACC_CNT16  = 3UL, /**< Set samples averaged to 16 */
    CY_AUTANALOG_SAR_ACC_CNT32  = 4UL, /**< Set samples averaged to 32 */
    CY_AUTANALOG_SAR_ACC_CNT64  = 5UL, /**< Set samples averaged to 64 */
    CY_AUTANALOG_SAR_ACC_CNT128 = 6UL, /**< Set samples averaged to 128 */
    CY_AUTANALOG_SAR_ACC_CNT256 = 7UL  /**< Set samples averaged to 256 */

} cy_en_autanalog_sar_acc_cnt_t;


/** Calibration Request options */
typedef enum
{
    CY_AUTANALOG_SAR_CAL_DISABLED  = 0UL, /**< Calibration Disabled */
    CY_AUTANALOG_SAR_CAL_BOTH      = 1UL, /**< Calibrate both Offset and Linearity */
    CY_AUTANALOG_SAR_CAL_OFFSET    = 2UL, /**< Calibrate Offset only */
    CY_AUTANALOG_SAR_CAL_LINEARITY = 3UL, /**< Calibrate Linearity only */

} cy_en_autanalog_sar_calibrate_t;


/** The Next State settings */
typedef enum
{
    CY_AUTANALOG_SAR_NEXT_ACTION_STATE_STOP       = 0UL, /**< Stop, send SAR_DONE trigger and go to idle */
    CY_AUTANALOG_SAR_NEXT_ACTION_GO_TO_ENTRY_ADDR = 1UL, /**< This implements a continuous mode,
                                                      *   send SAR_DONE trigger and go back to Entry Addr
                                                      */
    CY_AUTANALOG_SAR_NEXT_ACTION_GO_TO_NEXT       = 2UL, /**< Go to Next Addr */

} cy_en_autanalog_sar_next_act_t;


/** Reference voltage selection */
typedef enum
{
    CY_AUTANALOG_SAR_VREF_VDDA      = 0UL, /**< Vdda */
    CY_AUTANALOG_SAR_VREF_EXT       = 1UL, /**< External */
    CY_AUTANALOG_SAR_VREF_VBGR      = 2UL, /**< BandGap */
    CY_AUTANALOG_SAR_VREF_VDDA_BY_2 = 3UL, /**< Vdda/2 */
    CY_AUTANALOG_SAR_VREF_PRB_VREF0 = 4UL, /**< PRB_VREF0 */
    CY_AUTANALOG_SAR_VREF_PRB_VREF1 = 5UL, /**< PRB_VREF1 */

} cy_en_autanalog_sar_vref_t;


/** Buffer power modes */
typedef enum
{
    CY_AUTANALOG_SAR_BUF_PWR_OFF             =  0UL, /**< Off */
    CY_AUTANALOG_SAR_BUF_PWR_ULTRA_LOW       =  1UL, /**< ULTRA_LOW */
    CY_AUTANALOG_SAR_BUF_PWR_ULTRA_LOW_RAIL  =  2UL, /**< ULTRA_LOW_RAIL */
    CY_AUTANALOG_SAR_BUF_PWR_LOW             =  3UL, /**< LOW */
    CY_AUTANALOG_SAR_BUF_PWR_LOW_RAIL        =  4UL, /**< LOW_RAIL */
    CY_AUTANALOG_SAR_BUF_PWR_MEDIUM          =  5UL, /**< MEDIUM */
    CY_AUTANALOG_SAR_BUF_PWR_MEDIUM_RAIL     =  6UL, /**< MEDIUM_RAIL */
    CY_AUTANALOG_SAR_BUF_PWR_HIGH            =  7UL, /**< HIGH */
    CY_AUTANALOG_SAR_BUF_PWR_HIGH_RAIL       =  8UL, /**< HIGH_RAIL */
    CY_AUTANALOG_SAR_BUF_PWR_ULTRA_HIGH      =  9UL, /**< ULTRA_HIGH */
    CY_AUTANALOG_SAR_BUF_PWR_ULTRA_HIGH_RAIL = 10UL, /**< ULTRA_HIGH_RAIL */

} cy_en_autanalog_sar_buf_pwr_t;


/** Averaging mode applied to all channels in a scan where averaging is enabled */
typedef enum
{
    CY_AUTANALOG_SAR_ACC_DISABLED    = 0UL, /**< Average disabled */
    CY_AUTANALOG_SAR_ACC_ACCUNDUMP   = 1UL, /**< Accumulate and Dump (1st order accumulate and dump filter):
                                          *   a channel will be sampled back to back and averaged
                                          */
    CY_AUTANALOG_SAR_ACC_INTERLEAVED = 2UL, /**< Interleaved: Each scan (trigger) one sample is taken per channel
                                          *   and averaged over several scans
                                          */
} cy_en_autanalog_sar_acc_mode_t;


/** Input channel selection for FIR filter */
typedef enum
{
    CY_AUTANALOG_SAR_FIR_CH_DISABLED = 0UL,  /**< DISABLED */
    CY_AUTANALOG_SAR_FIR_CH_GPIO0    = 1UL,  /**< GPIO 0 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO1    = 2UL,  /**< GPIO 1 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO2    = 3UL,  /**< GPIO 2 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO3    = 4UL,  /**< GPIO 3 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO4    = 5UL,  /**< GPIO 4 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO5    = 6UL,  /**< GPIO 5 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO6    = 7UL,  /**< GPIO 6 */
    CY_AUTANALOG_SAR_FIR_CH_GPIO7    = 8UL,  /**< GPIO 7 */
    CY_AUTANALOG_SAR_FIR_CH_MUX0     = 9UL,  /**< MUX 0 */
    CY_AUTANALOG_SAR_FIR_CH_MUX1     = 10UL, /**< MUX 1 */
    CY_AUTANALOG_SAR_FIR_CH_MUX2     = 11UL, /**< MUX 2 */
    CY_AUTANALOG_SAR_FIR_CH_MUX3     = 12UL, /**< MUX 3 */
    CY_AUTANALOG_SAR_FIR_CH_MUX4     = 13UL, /**< MUX 4 */
    CY_AUTANALOG_SAR_FIR_CH_MUX5     = 14UL, /**< MUX 5 */
    CY_AUTANALOG_SAR_FIR_CH_MUX6     = 15UL, /**< MUX 6 */
    CY_AUTANALOG_SAR_FIR_CH_MUX7     = 16UL, /**< MUX 7 */
    CY_AUTANALOG_SAR_FIR_CH_MUX8     = 17UL, /**< MUX 8 */
    CY_AUTANALOG_SAR_FIR_CH_MUX9     = 18UL, /**< MUX 9 */
    CY_AUTANALOG_SAR_FIR_CH_MUX10    = 19UL, /**< MUX 10 */
    CY_AUTANALOG_SAR_FIR_CH_MUX11    = 20UL, /**< MUX 11 */
    CY_AUTANALOG_SAR_FIR_CH_MUX12    = 21UL, /**< MUX 12 */
    CY_AUTANALOG_SAR_FIR_CH_MUX13    = 22UL, /**< MUX 13 */
    CY_AUTANALOG_SAR_FIR_CH_MUX14    = 23UL, /**< MUX 14 */
    CY_AUTANALOG_SAR_FIR_CH_MUX15    = 24UL, /**< MUX 15 */

} cy_en_autanalog_sar_fir_channel_t;


/** The SAR range status selection */
typedef enum
{
    CY_AUTANALOG_SAR_LIMIT_STATUS_DISABLED = 0UL, /**< Limit status is not in use, see \ref cy_stc_autanalog_sar_limit_t */
    CY_AUTANALOG_SAR_LIMIT_STATUS_STC0     = 1UL, /**< Limit status structure 0 */
    CY_AUTANALOG_SAR_LIMIT_STATUS_STC1     = 2UL, /**< Limit status structure 1 */
    CY_AUTANALOG_SAR_LIMIT_STATUS_STC2     = 3UL, /**< Limit status structure 2 */
    CY_AUTANALOG_SAR_LIMIT_STATUS_STC3     = 4UL, /**< Limit status structure 3 */

} cy_en_autanalog_sar_limit_t;


/** The FIFO selection for FIR filter */
typedef enum
{
    CY_AUTANALOG_SAR_FIR_FIFO_DISABLED = 0UL, /**< FIFO is not in use */
    CY_AUTANALOG_SAR_FIR_FIFO0         = 1UL, /**< FIFO 0 */
    CY_AUTANALOG_SAR_FIR_FIFO1         = 2UL, /**< FIFO 1 */
    CY_AUTANALOG_SAR_FIR_FIFO2         = 3UL, /**< FIFO 2 */
    CY_AUTANALOG_SAR_FIR_FIFO3         = 4UL, /**< FIFO 3 */
    CY_AUTANALOG_SAR_FIR_FIFO4         = 5UL, /**< FIFO 4 */
    CY_AUTANALOG_SAR_FIR_FIFO5         = 6UL, /**< FIFO 5 */
    CY_AUTANALOG_SAR_FIR_FIFO6         = 7UL, /**< FIFO 6 */
    CY_AUTANALOG_SAR_FIR_FIFO7         = 8UL, /**< FIFO 7 */

} cy_en_autanalog_sar_fir_fifo_t;


/** The GPIO channel Input Assignment */
typedef enum
{
    CY_AUTANALOG_SAR_PIN_GPIO0 =  0UL, /**< pin 0 */
    CY_AUTANALOG_SAR_PIN_GPIO1 =  1UL, /**< pin 1 */
    CY_AUTANALOG_SAR_PIN_GPIO2 =  2UL, /**< pin 2 */
    CY_AUTANALOG_SAR_PIN_GPIO3 =  3UL, /**< pin 3 */
    CY_AUTANALOG_SAR_PIN_GPIO4 =  4UL, /**< pin 4 */
    CY_AUTANALOG_SAR_PIN_GPIO5 =  5UL, /**< pin 5 */
    CY_AUTANALOG_SAR_PIN_GPIO6 =  6UL, /**< pin 6 */
    CY_AUTANALOG_SAR_PIN_GPIO7 =  7UL, /**< pin 7 */

} cy_en_autanalog_sar_pin_hs_t;


/** The SAR channel input coefficient select */
typedef enum
{
    CY_AUTANALOG_SAR_CH_COEFF_DISABLED = 0UL, /**< Channel input coefficient is not in use */
    CY_AUTANALOG_SAR_CH_COEFF0         = 1UL, /**< Channel input coefficient 0 */
    CY_AUTANALOG_SAR_CH_COEFF1         = 2UL, /**< Channel input coefficient 1 */
    CY_AUTANALOG_SAR_CH_COEFF2         = 3UL, /**< Channel input coefficient 2 */
    CY_AUTANALOG_SAR_CH_COEFF3         = 4UL, /**< Channel input coefficient 3 */
    CY_AUTANALOG_SAR_CH_COEFF4         = 5UL, /**< Channel input coefficient 4 */
    CY_AUTANALOG_SAR_CH_COEFF5         = 6UL, /**< Channel input coefficient 5 */
    CY_AUTANALOG_SAR_CH_COEFF6         = 7UL, /**< Channel input coefficient 6 */
    CY_AUTANALOG_SAR_CH_COEFF7         = 8UL, /**< Channel input coefficient 7 */

} cy_en_autanalog_sar_ch_coeff_t;


/** The MUX channel Input Assignment */
typedef enum
{
    CY_AUTANALOG_SAR_PIN_MUX_COREIO0     =  0UL, /**< COREIO 0 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO1     =  1UL, /**< COREIO 1 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO2     =  2UL, /**< COREIO 2 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO3     =  3UL, /**< COREIO 3 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO4     =  4UL, /**< COREIO 4 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO5     =  5UL, /**< COREIO 5 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO6     =  6UL, /**< COREIO 6 */
    CY_AUTANALOG_SAR_PIN_MUX_COREIO7     =  7UL, /**< COREIO 7 */
    CY_AUTANALOG_SAR_PIN_MUX_CTBL0_OA0   =  8UL, /**< CTBL 0 OpAmp 0 */
    CY_AUTANALOG_SAR_PIN_MUX_CTBL0_OA1   =  9UL, /**< CTBL 0 OpAmp 1 */
    CY_AUTANALOG_SAR_PIN_MUX_CTBL1_OA0   = 10UL, /**< CTBL 1 OpAmp 0 */
    CY_AUTANALOG_SAR_PIN_MUX_CTBL1_OA1   = 11UL, /**< CTBL 1 OpAmp 1 */
    CY_AUTANALOG_SAR_PIN_MUX_VREF0       = 12UL, /**< Vref 0 */
    CY_AUTANALOG_SAR_PIN_MUX_VREF1       = 13UL, /**< Vref 1 */
    CY_AUTANALOG_SAR_PIN_MUX_TEMP_SENSOR = 14UL, /**< Temperature sensor */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO0       = 15UL, /**< GPIO 0 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO1       = 16UL, /**< GPIO 1 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO2       = 17UL, /**< GPIO 2 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO3       = 18UL, /**< GPIO 3 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO4       = 19UL, /**< GPIO 4 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO5       = 20UL, /**< GPIO 5 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO6       = 21UL, /**< GPIO 6 */
    CY_AUTANALOG_SAR_PIN_MUX_GPIO7       = 22UL, /**< GPIO 7 */
    CY_AUTANALOG_SAR_PIN_MUX_VSSA_KELVIN = 25UL, /**< VSSA_KELVIN */

} cy_en_autanalog_sar_pin_mux_t;


/** The range detection condition */
typedef enum
{
    CY_AUTANALOG_SAR_COND_BELOW   = 0UL, /**< result < RANGE_LOW */
    CY_AUTANALOG_SAR_COND_INSIDE  = 1UL, /**< RANGE_LOW <= result < RANGE_HIGH */
    CY_AUTANALOG_SAR_COND_ABOVE   = 2UL, /**< result > RANGE_HIGH */
    CY_AUTANALOG_SAR_COND_OUTSIDE = 3UL, /**< result < RANGE_LOW || result >= RANGE_HIGH */

} cy_en_autanalog_sar_cond_t;


/** The numerical resolution of ADC */
typedef enum
{
    CY_AUTANALOG_SAR_NUM_RES_BITS12 = 0UL, /**< The resolution 12 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS13 = 1UL, /**< The resolution 13 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS14 = 2UL, /**< The resolution 14 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS15 = 3UL, /**< The resolution 15 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS16 = 4UL, /**< The resolution 16 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS17 = 5UL, /**< The resolution 17 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS18 = 6UL, /**< The resolution 18 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS19 = 7UL, /**< The resolution 19 bits */
    CY_AUTANALOG_SAR_NUM_RES_BITS20 = 8UL, /**< The resolution 20 bits */

} cy_en_autanalog_sar_num_res_t;

/** \} group_autanalog_sar_enums */


/**
* \addtogroup group_autanalog_fifo_enums
* \{
*/

/** The FIFO selection */
typedef enum
{
    CY_AUTANALOG_FIFO_DISABLED = 0UL, /**< DISABLED */
    CY_AUTANALOG_FIFO_SELECT0  = 1UL, /**< FIFO 0 */
    CY_AUTANALOG_FIFO_SELECT1  = 2UL, /**< FIFO 1 */
    CY_AUTANALOG_FIFO_SELECT2  = 3UL, /**< FIFO 2 */
    CY_AUTANALOG_FIFO_SELECT3  = 4UL, /**< FIFO 3 */
    CY_AUTANALOG_FIFO_SELECT4  = 5UL, /**< FIFO 4 */
    CY_AUTANALOG_FIFO_SELECT5  = 6UL, /**< FIFO 5 */
    CY_AUTANALOG_FIFO_SELECT6  = 7UL, /**< FIFO 6 */
    CY_AUTANALOG_FIFO_SELECT7  = 8UL, /**< FIFO 7 */

} cy_en_autanalog_fifo_sel_t;


/** The range detection condition */
typedef enum
{
    CY_AUTANALOG_FIFO_SPLIT1 = 0UL, /**< The FIFO is a single 512-word buffer */
    CY_AUTANALOG_FIFO_SPLIT2 = 1UL, /**< The FIFO is split into two 256-word buffers */
    CY_AUTANALOG_FIFO_SPLIT4 = 2UL, /**< The FIFO is split into four 128-word buffers */
    CY_AUTANALOG_FIFO_SPLIT8 = 3UL, /**< The FIFO is split into eight 64-word buffers */

} cy_en_autanalog_fifo_split_t;

/** \} group_autanalog_fifo_enums */


/***************************************
*       Configuration Structures
***************************************/

/**
* \addtogroup group_autanalog_sar_data_structures
* \{
*/

/** The SAR Sequencer Table configuration structure for HS mode */
typedef struct
{
    uint8_t                        chanEn;          /**< Enable masks for GPIO channels[7:0],
                                                     *   see \ref group_autanalog_sar_hs_chan_macros \n
                                                     */
    uint8_t                        muxMode;         /**< Define mode of operation for MUX channels,
                                                     *   see \ref group_autanalog_sar_hs_chan_macros
                                                     */
    uint8_t                        mux0Sel;         /**< MUX 0 channel selection, 0...15 */
    uint8_t                        mux1Sel;         /**< MUX 1 channel selection, 0...15 */
    bool                           sampleTimeEn;    /**< Enable sample time option for SAR */
    cy_en_autanalog_sar_sample_time_t sampleTime;      /**< Sample Timer Selection. Choose one out of four available Sample Timers
                                                     *   \ref cy_stc_autanalog_sar_sta_hs_t::hsSampleTime or \ref cy_stc_autanalog_sar_sta_lp_t::lpSampleTime
                                                     */
    bool                           accEn;           /**< Averaging enable */
    cy_en_autanalog_sar_acc_cnt_t     accCount;        /**< Averaging Count for channels that have averaging enabled (AVG_EN). A channel will be sampled (1<<(AVG_CNT+1)) = [2..256] times.
                                                     *   - In ACCUNDUMP mode  (1st order accumulate and dump filter) a channel will be sampled back to back,
                                                     *   the average result is calculated and stored and then the next enabled channel is sampled.
                                                     *   If shifting is not enabled (AVG_SHIFT=0) then the result is forced to shift right so that is fits in 16 bits,
                                                     *   so right shift is done by max(0,AVG_CNT-3).
                                                     *   - In INTERLEAVED mode one sample is taken per triggered scan, only in the scan where the final averaging count is reached
                                                     *   a valid average is calculated and stored in the RESULT register (by definition the same scan for all the channels that have
                                                     *   averaging enabled). In all other scans the RESULT register for averaged channels will have an invalid result and the
                                                     *   intermediate accumulated value is stored in the 16-bit WORK register. In this mode make sure that the averaging count is
                                                     *   low enough to ensure that the intermediate value does not exceed 16-bits otherwise the MSBs will be lost.
                                                     *   So for a 12-bit resolution the averaging count should be set to 16 or less (AVG_CNT=<3).
                                                     */
    cy_en_autanalog_sar_calibrate_t   calReq;          /**< Calibration Request. This signals the ADC to initiate a calibration process.
                                                     *   This process is required whenever: the ADC is first enabled, MUX0(1)_CHAN_SEL values are changed,
                                                     *   or the external inputs to the GPIO Channels are switched.
                                                     */
    cy_en_autanalog_sar_next_act_t  nextAction;        /**< Next action field */

} cy_stc_autanalog_sar_seq_tab_hs_t;


/** The SAR Sequencer Table configuration structure for LP mode */
typedef struct
{
    uint8_t                        chanEn;          /**< For LP mode: enable usage of MUX channels,
                                                     *   see \ref group_autanalog_sar_lp_chan_macros
                                                     */
    uint8_t                        mux0Sel;         /**< MUX channel selection, 0...15 */
    bool                           sampleTimeEn;    /**< Enable sample time option for SAR */
    cy_en_autanalog_sar_sample_time_t sampleTime;      /**< Sample Timer Selection. Choose one out of four available Sample Timers
                                                     *   \ref cy_stc_autanalog_sar_sta_hs_t::hsSampleTime or \ref cy_stc_autanalog_sar_sta_lp_t::lpSampleTime
                                                     */
    bool                           accEn;           /**< Averaging enable */
    cy_en_autanalog_sar_acc_cnt_t     accCount;        /**< Averaging Count for channels that have averaging enabled (AVG_EN). A channel will be sampled (1<<(AVG_CNT+1)) = [2..256] times.
                                                     *   - In ACCUNDUMP mode  (1st order accumulate and dump filter) a channel will be sampled back to back,
                                                     *   the average result is calculated and stored and then the next enabled channel is sampled.
                                                     *   If shifting is not enabled (AVG_SHIFT=0) then the result is forced to shift right so that is fits in 16 bits,
                                                     *   so right shift is done by max(0,AVG_CNT-3).
                                                     *   - In INTERLEAVED mode one sample is taken per triggered scan, only in the scan where the final averaging count is reached
                                                     *   a valid average is calculated and stored in the RESULT register (by definition the same scan for all the channels that have
                                                     *   averaging enabled). In all other scans the RESULT register for averaged channels will have an invalid result and the
                                                     *   intermediate accumulated value is stored in the 16-bit WORK register. In this mode make sure that the averaging count is
                                                     *   low enough to ensure that the intermediate value does not exceed 16-bits otherwise the MSBs will be lost.
                                                     *   So for a 12-bit resolution the averaging count should be set to 16 or less (AVG_CNT=<3).
                                                     */
    cy_en_autanalog_sar_calibrate_t   calReq;          /**< Calibration Request. This signals the ADC to initiate a calibration process.
                                                     *   This process is required whenever: the ADC is first enabled, MUX0(1)_CHAN_SEL values are changed,
                                                     *   or the external inputs to the GPIO Channels are switched.
                                                     */
    cy_en_autanalog_sar_next_act_t    nextAction;      /**< Next action field */

} cy_stc_autanalog_sar_seq_tab_lp_t;


/** The FIR filter Configuration structure */
typedef struct
{
    cy_en_autanalog_sar_fir_channel_t chanSel;     /**< FIR filter channel selector */
    int16_t                      * coeff;       /**< FIR filter coefficients, size of array is defined by
                                                 *   \ref cy_stc_autanalog_sar_fir_cfg_t::tapSel
                                                 *   The coefficient values can range from -1+1/2^15 to 1-1/2^15 with
                                                 *   a resolution of 1/2^15.
                                                 *   The coefficient uses twos-complement notation and the decimal point is
                                                 *   fixed to the right of the most significant bit.
                                                 *   Examples: -0.25 = 0xE000 and 0.25 = 0x2000
                                                 */
    uint8_t                        tapSel;      /**< FIR Tap Select = TAP_SEL + 1, range 1..64 */
    uint8_t                        shiftSel;    /**< Shift the FIR filter output right by the number in this field */
    bool                           waitTapInit; /**< Wait for TAP_SEL number before outputing the first valid data */
    cy_en_autanalog_sar_limit_t       firLimit;    /**< FIR filter limit status selections */
    cy_en_autanalog_fifo_sel_t        fifoSel;     /**< FIFO selections. Select 1 of the 8 for FIFO data storage */

} cy_stc_autanalog_sar_fir_cfg_t;


/** The GPIO channel configuration structure */
typedef struct
{
    cy_en_autanalog_sar_pin_hs_t posPin;     /**< Positive pin assignment */
    bool                        hsDiffEn;   /**< High Speed Differential Enable */
    bool                        sign;       /**< Output data as a signed value */
    cy_en_autanalog_sar_ch_coeff_t posCoeff;   /**< Positive Input Coefficient Select */
    cy_en_autanalog_sar_pin_hs_t negPin;     /**< Negative pin assignment */
    bool                        accShift;   /**< After averaging the result is shifted right to fit in the sample resolution */
    cy_en_autanalog_sar_ch_coeff_t negCoeff;   /**< Negative Input Coefficient Select */
    cy_en_autanalog_sar_limit_t    hsLimit;  /**< HS channels limit status selection */
    cy_en_autanalog_fifo_sel_t     fifoSel;    /**< FIFO selections. Select 1 of the 8 for FIFO data storage */

} cy_stc_autanalog_sar_hs_chan_t;


/** The MUX channel configuration structure */
typedef struct
{
    cy_en_autanalog_sar_pin_mux_t  posPin;     /**< Positive pin assignment */
    bool                        sign;       /**< Output data as a signed value */
    cy_en_autanalog_sar_ch_coeff_t posCoeff;   /**< Positive Input Coefficient Select */
    cy_en_autanalog_sar_pin_mux_t  negPin;     /**< Negative pin assignment */
    bool                        buffBypass; /**< Channel Buffer bypass */
    bool                        accShift;   /**< After averaging the result is shifted right to fit in the sample resolution */
    cy_en_autanalog_sar_ch_coeff_t negCoeff;   /**< Negative Input Coefficient Select */
    cy_en_autanalog_sar_limit_t    muxLimit;   /**< MUX channels limit status selection */
    cy_en_autanalog_fifo_sel_t     fifoSel;    /**< FIFO selections. Select 1 of the 8 for FIFO data storage */

} cy_stc_autanalog_sar_mux_chan_t;


/** The range detection configuration structure */
typedef struct
{
    cy_en_autanalog_sar_cond_t cond; /**< Range detection condition select */
    int32_t                 low;  /**< Low threshold for range detection */
    int32_t                 high; /**< High threshold for range detection */

} cy_stc_autanalog_sar_limit_t;


/** The LP Static SAR configuration structure */
typedef struct
{
    bool                            lpDiffEn;                                    /**< Low Power Differential Enable */
    cy_en_autanalog_sar_vref_t         lpVref;                                      /**< Low power Vref selection */
    uint16_t                        lpSampleTime[CY_AUTANALOG_SAR_SAMPLE_TIME_NUM]; /**< The array of sample time settings in LP mode (4.096 MHz)
                                                                                  *   clock cycles for the Sample Timers 0..3, valid range 1..1024
                                                                                  */
} cy_stc_autanalog_sar_sta_lp_t;


/** The HS Static SAR configuration structure */
typedef struct
{
    uint16_t                        hsSamplerEn;                                 /**< HS Sampler Enables, all ON by default */
    cy_en_autanalog_sar_vref_t         hsVref;                                      /**< High speed Vref selection */
    uint16_t                        hsSampleTime[CY_AUTANALOG_SAR_SAMPLE_TIME_NUM]; /**< The array of sample time settings in HS mode (80 MHz)
                                                                                  *   clock cycles for the Sample Timers 0..3, valid range 1..1024
                                                                                  */
    cy_stc_autanalog_sar_hs_chan_t * hsGpioChan[PASS_SAR_SAR_GPIO_CHANNELS];   /**< Pointers to High Speed GPIO channel configuration structures,
                                                                                  *   NULL means the channel is not configured
                                                                                  */
    uint8_t                         hsGpioResultMask;                            /**< GPIO channels result mask */

} cy_stc_autanalog_sar_sta_hs_t;


/** The Static SAR configuration structure */
typedef struct
{
    cy_stc_autanalog_sar_sta_lp_t   *  lpStaCfg;                                    /**< Low power part of Static configuration */
    cy_stc_autanalog_sar_sta_hs_t   *  hsStaCfg;                                    /**< High speed part of Static configuration,
                                                                                  *    Note: this configuration is not mandatory,
                                                                                  *    NULL pointer is allowed
                                                                                  */
    cy_en_autanalog_sar_buf_pwr_t      posBufPwr;                                   /**< Positive buffer (0) power setting */
    cy_en_autanalog_sar_buf_pwr_t      negBufPwr;                                   /**< Negative buffer (1) power setting */
    cy_en_autanalog_sar_acc_mode_t     accMode;                                     /**< Averaging mode */
    cy_en_autanalog_sar_calibrate_t    startupCal;                                  /**< Enable the SAR calibration during startup */
    bool                            chanID;                                      /**< Channel Number Identifier Enable */
    bool                            shiftMode;                                   /**< If AVG_SHIFT is enabled for a given channel,
                                                                                  *   shift the result to support 12 or 16-bit resolutions
                                                                                  */
    cy_stc_autanalog_sar_mux_chan_t  * intMuxChan[PASS_SAR_SAR_MUX_CHANNELS];       /**< Pointers to internal MUX channel configuration structures,
                                                                                  *   NULL means the channel is not configured
                                                                                  */
    cy_stc_autanalog_sar_limit_t     * limitCond[CY_AUTANALOG_SAR_LIMIT_CFG_NUM];      /**< Pointers to range detection configuration structures,
                                                                                  *   NULL means the range condition is not configured
                                                                                  */
    uint16_t                        muxResultMask;                               /**< MUX channels result mask */
    uint8_t                         firResultMask;                               /**< FIR filter result mask */

} cy_stc_autanalog_sar_sta_t;


/**
* \addtogroup group_autanalog_fifo_data_structures
* \{
*/


/** The FIFO configuration structure */
typedef struct
{
    cy_en_autanalog_fifo_split_t split;                          /**< The FIFO split configuration */
    uint16_t                  level[CY_AUTANALOG_FIFO_BUFS_NUM]; /**< Array of the FIFO buffer level settings,
                                                               *   valid range is 0..511,
                                                               *   but the real functional range depends on
                                                               *   the cy_stc_autanalog_fifo_cfg_t::split setting
                                                               */
} cy_stc_autanalog_fifo_cfg_t;

/** \} group_autanalog_fifo_data_structures */


/** The high-level SAR configuration structure */
typedef struct
{
    /** Static configuration */
    cy_stc_autanalog_sar_sta_t     * sarStaCfg;      /**< Pointer to the SAR Static configuration structure */

    /** Hight Speed Sequencer Table */
    uint8_t                       hsSeqTabNum;    /**< Amount of SAR Hight Speed Sequencer Table structures, valid range 0...32 */
    cy_stc_autanalog_sar_seq_tab_hs_t * hsSeqTabArr; /**< Pointer to the array of the SAR Hight Speed Sequencer Table structures, the array length is specified by hsTtCnt */
    /** Low Power Sequencer Table */
    uint8_t                       lpSeqTabNum;    /**< Amount of SAR Low Power Sequencer Table structures, valid range 0...32 */
    cy_stc_autanalog_sar_seq_tab_lp_t * lpSeqTabArr; /**< Pointer to the array of the SAR Low Power Sequencer Table structures, the array length is specified by lpTtCnt */

    /* FIR */
    uint8_t                       firNum;         /**< Number of used FIR filters */
    cy_stc_autanalog_sar_fir_cfg_t * firCfg;         /**< FIR filter Configuration */

    /** FIFO */
    cy_stc_autanalog_fifo_cfg_t    * fifoCfg;        /**< Pointer to the FIFO configuration structure */

} cy_stc_autanalog_sar_t;


/** The SAR section of the State Transition Table state, to be used in \ref cy_stc_autanalog_stt_t */
typedef struct
{
    bool     unlock;     /**< SAR Unlock:
                          * 0, Lock:
                          *     SAR field SAR_EN
                          *     does NOT get updated
                          * 1, Unlock:
                          *     SAR field SAR_EN
                          *     does get updated
                          */
    bool     enable;     /**< Enable the SAR subsystem clock */
    bool     trigger;    /**< SAR trigger */
    uint8_t  entryState; /**< SAR Sequencer entry state, points to the item of the
                          *   \ref cy_stc_autanalog_sar_t::hsSeqTabArr or
                          *   \ref cy_stc_autanalog_sar_t::lpSeqTabArr depends on the current
                          *   \ref cy_stc_autanalog_stt_ac_t::mode setting,
                          *   the valid range is 0...31
                          */
} cy_stc_autanalog_stt_sar_t;

/** \} group_autanalog_sar_data_structures */


/***************************************
*        Function Prototypes
***************************************/

/**
* \addtogroup group_autanalog_sar_functions
* \{
*/

/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_LoadConfig
****************************************************************************//**
*
* Loads the entire SAR ADC configuration.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param sarCfg
* Pointer to the SAR configuration structure \ref cy_stc_autanalog_sar_t
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadConfig(uint8_t sarIdx, const cy_stc_autanalog_sar_t * sarCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_LoadStaticConfig
****************************************************************************//**
*
* Loads the SAR ADC static configuration.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param sarStaCfg
* Pointer to the SAR static configuration structure \ref cy_stc_autanalog_sar_sta_t
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadStaticConfig(uint8_t sarIdx, const cy_stc_autanalog_sar_sta_t * sarStaCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_LoadHSseqTable
****************************************************************************//**
*
* Loads the SAR ADC HS Sequencer Table configurations.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param seqTabNum
* The amount of the SAR HS Sequencer Table configuration structures in the array
*
* \param seqTabArr
* Pointer to the array of the SAR HS Sequencer Table configuration structures
* \ref cy_stc_autanalog_sar_seq_tab_hs_t
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadHSseqTable(uint8_t sarIdx, uint8_t seqTabNum, const cy_stc_autanalog_sar_seq_tab_hs_t * seqTabArr);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_LoadLPseqTable
****************************************************************************//**
*
* Loads the SAR ADC LP Sequencer Table configurations.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param seqTabNum
* The amount of the SAR LP Sequencer Table configuration structures in the array
*
* \param seqTabArr
* Pointer to the array of the SAR LP Sequencer Table configuration structures
* \ref cy_stc_autanalog_sar_seq_tab_lp_t
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadLPseqTable(uint8_t sarIdx, uint8_t seqTabNum, const cy_stc_autanalog_sar_seq_tab_lp_t * seqTabArr);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_LoadFIRconfig
****************************************************************************//**
*
* Loads the SAR ADC FIR filter configurations.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param firIdx
* The index of the FIR filter configuration structure, 0 or 1,
* see \ref cy_stc_autanalog_sar_t::firCfg
*
* \param firCfg
* Pointer to the array of the SAR FIR filter configuration structures.
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadFIRconfig(uint8_t sarIdx, uint8_t firIdx, const cy_stc_autanalog_sar_fir_cfg_t * firCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_GetHSchanLimitStatus
****************************************************************************//**
*
* Provides range detect status for SAR GPIO channels.
* SAR sets this bit for each channel if the conversion result (after averaging, if enabled) of that channel
* met the condition specified by the \ref cy_stc_autanalog_sar_hs_chan_t::hsLimit.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* Range detect status. Compare this value with one of masks for the GPIO channels.
*
*******************************************************************************/
uint8_t Cy_AutAnalog_SAR_GetHSchanLimitStatus(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_ClearHSchanLimitStatus
****************************************************************************//**
*
* Clears range detect status for SAR GPIO channels.
* See \ref Cy_AutAnalog_SAR_GetHSchanLimitStatus
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param chMask
* The combined mask for GPIO channels which requires reset of their range detect status.
*
*******************************************************************************/
void Cy_AutAnalog_SAR_ClearHSchanLimitStatus(uint8_t sarIdx, uint8_t chMask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_GetHSchanResultStatus
****************************************************************************//**
*
* Provides result updated status for SAR GPIO channels.
* SAR sets this bit for each channel if that channel was sampled during the previous scan and,
* in case of interleaved averaging, reached the averaging count.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* SAR result update status. Compare this value with one of masks for the GPIO channels.
*
*******************************************************************************/
uint8_t Cy_AutAnalog_SAR_GetHSchanResultStatus(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_ClearHSchanResultStatus
****************************************************************************//**
*
* Clears result updated status for SAR GPIO channels.
* See \ref Cy_AutAnalog_SAR_GetHSchanResultStatus
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param chMask
* The combined mask for GPIO channels which requires reset of their result updated status.
*
*******************************************************************************/
void Cy_AutAnalog_SAR_ClearHSchanResultStatus(uint8_t sarIdx, uint8_t chMask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_GetMuxChanLimitStatus
****************************************************************************//**
*
* Provides range detect status for SAR MUX channels.
* SAR sets this bit for each channel if the conversion result (after averaging, if enabled) of that channel
* met the condition specified by the \ref cy_stc_autanalog_sar_mux_chan_t::muxLimit.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* Range detect status. Compare this value with one of masks for the MUX channels.
*
*******************************************************************************/
uint16_t Cy_AutAnalog_SAR_GetMuxChanLimitStatus(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_ClearMuxChanLimitStatus
****************************************************************************//**
*
* Clears range detect status for SAR MUX channels.
* See \ref Cy_AutAnalog_SAR_GetMuxChanLimitStatus
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param chMask
* The combined mask for MUX channels which requires reset of their range detect status.
*
*******************************************************************************/
void Cy_AutAnalog_SAR_ClearMuxChanLimitStatus(uint8_t sarIdx, uint16_t chMask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_GetMuxChanResultStatus
****************************************************************************//**
*
* Provides result updated status for SAR MUX channels.
* SAR sets this bit for each channel if that channel was sampled during the previous scan and,
* in case of interleaved averaging, reached the averaging count.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* SAR result update status. Compare this value with one of masks for the MUX channels.
*
*******************************************************************************/
uint16_t Cy_AutAnalog_SAR_GetMuxChanResultStatus(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_ClearMuxChanResultStatus
****************************************************************************//**
*
* Clears result updated status for SAR MUX channels.
* See \ref Cy_AutAnalog_SAR_GetMuxChanResultStatus
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param chMask
* The combined mask for MUX channels which requires reset of their result updated status.
*
*******************************************************************************/
void Cy_AutAnalog_SAR_ClearMuxChanResultStatus(uint8_t sarIdx, uint16_t chMask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_ReadResult
****************************************************************************//**
*
* Provides SAR conversion data for dedicated channel.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param input
* The type of the SAR Sequencer Table configuration structure \ref cy_en_autanalog_sar_input_t.
*
* \param channel
* Channel for SAR conversion.
*
* \return
* SAR conversion result.
*
*******************************************************************************/
int32_t Cy_AutAnalog_SAR_ReadResult(uint8_t sarIdx, cy_en_autanalog_sar_input_t input, uint8_t channel);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_FIRgetLimitStatus
****************************************************************************//**
*
* Provides range detect status for SAR FIR filter output.
* SAR sets this bit for each FIR filter in case of filtering result
* met the condition specified by the \ref cy_stc_autanalog_sar_fir_cfg_t::firLimit.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* Range detect status. Compare this value with one of masks for the FIR filters.
*
*******************************************************************************/
uint8_t Cy_AutAnalog_SAR_FIRgetLimitStatus(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_FIRclearLimitStatus
****************************************************************************//**
*
* Clears range detect status for SAR FIR filters.
* See \ref Cy_AutAnalog_SAR_FIRgetLimitStatus
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param firMask
* The combined mask for FIR filters which requires reset of their range detect status.
*
*******************************************************************************/
void Cy_AutAnalog_SAR_FIRclearLimitStatus(uint8_t sarIdx, uint8_t firMask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_FIRgetResultStatus
****************************************************************************//**
*
* Provides result update status for SAR FIR filter output.
* SAR sets this bit for each FIR filter in case of update filtering result.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* FIR result update status. Compare this value with one of masks for the FIR filters.
*
*******************************************************************************/
uint8_t Cy_AutAnalog_SAR_FIRgetResultStatus(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_FIRclearResultStatus
****************************************************************************//**
*
* Clears result updated status for SAR FIR filter output.
* See \ref Cy_AutAnalog_SAR_FIRgetResultStatus
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param firMask
* The combined mask for FIR filters which requires reset of their result updated status.
*
*******************************************************************************/
void Cy_AutAnalog_SAR_FIRclearResultStatus(uint8_t sarIdx, uint8_t firMask);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_FIRreadResult
****************************************************************************//**
*
* Provides FIR filter output data.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param firIdx
* The index of the FIR filter configuration structure, 0 or 1.
*
* \return
* FIR filter output data.
*
*******************************************************************************/
int32_t Cy_AutAnalog_SAR_FIRreadResult(uint8_t sarIdx, uint8_t firIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_LoadOffsetGainCorr
****************************************************************************//**
*
* Loads offset and gain correction coefficients for the SAR channels.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param chanGain
* Array of gain correction coefficients
* for the first eight channels of SAR.
*
* \param chanOffset
* Array of offset correction coefficients
* for the first eight channels of SAR.
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadOffsetGainCorr(uint8_t sarIdx, uint16_t chanGain[], int16_t chanOffset[]);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_IsBusy
****************************************************************************//**
*
* Provides status of SAR conversion execution at moment of request.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \return
* Status of SAR conversion.
*
*******************************************************************************/
bool Cy_AutAnalog_SAR_IsBusy(uint8_t sarIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_CountsTo_Volts
****************************************************************************//**
*
* Converts the SAR ADC output to Volts.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param sarSequencer
* The SAR ADC sequencer for conversion of output to Volts.
*
* \param sarInput
* The type of the SAR Sequencer Table configuration structure \ref cy_en_autanalog_sar_input_t.
*
* \param sarChannel
* Channel for SAR ADC conversion.
*
* \param VrefmV
* Reference voltage in mV.
*
* \param sarCounts
* SAR conversion result for the channel,
* see \ref Cy_AutAnalog_SAR_ReadResult.
* Or see \ref Cy_AutAnalog_FIFO_ReadWord (\ref Cy_AutAnalog_FIFO_ReadData, ref Cy_AutAnalog_FIFO_ReadDataChanId)
* in case of receiving data for conversion from FIFO.
*
* \return
* SAR conversion result in Volts.
*
*******************************************************************************/
float32_t Cy_AutAnalog_SAR_CountsTo_Volts(uint8_t sarIdx, uint8_t sarSequencer, cy_en_autanalog_sar_input_t sarInput,
                                       uint8_t sarChannel, uint32_t VrefmV, int32_t sarCounts);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_CountsTo_mVolts
****************************************************************************//**
*
* Converts the SAR ADC output to miliVolts.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param sarSequencer
* The SAR ADC sequencer for conversion of output to mVolts.
*
* \param sarInput
* The type of the SAR Sequencer Table configuration structure \ref cy_en_autanalog_sar_input_t.
*
* \param sarChannel
* Channel for SAR ADC conversion.
*
* \param VrefmV
* Reference voltage in mV.
*
* \param sarCounts
* SAR conversion result for the channel,
* see \ref Cy_AutAnalog_SAR_ReadResult.
* Or see \ref Cy_AutAnalog_FIFO_ReadWord (\ref Cy_AutAnalog_FIFO_ReadData, ref Cy_AutAnalog_FIFO_ReadDataChanId)
* in case of receiving data for conversion from FIFO.
*
* \return
* SAR conversion result in miliVolts.
*
*******************************************************************************/
int16_t Cy_AutAnalog_SAR_CountsTo_mVolts(uint8_t sarIdx, uint8_t sarSequencer, cy_en_autanalog_sar_input_t sarInput,
                                      uint8_t sarChannel, uint32_t VrefmV, int32_t sarCounts);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_CountsTo_uVolts
****************************************************************************//**
*
* Converts the SAR ADC output to microVolts.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param sarSequencer
* The SAR ADC sequencer for conversion of output to uVolts.
*
* \param sarInput
* The type of the SAR Sequencer Table configuration structure \ref cy_en_autanalog_sar_input_t.
*
* \param sarChannel
* Channel for SAR conversion.
*
* \param VrefmV
* Reference voltage in mV.
*
* \param sarCounts
* SAR conversion result for the channel,
* see \ref Cy_AutAnalog_SAR_ReadResult.
* Or see \ref Cy_AutAnalog_FIFO_ReadWord (\ref Cy_AutAnalog_FIFO_ReadData, ref Cy_AutAnalog_FIFO_ReadDataChanId)
* in case of receiving data for conversion from FIFO.
*
* \return
* SAR conversion result in microVolts.
*
*******************************************************************************/
int32_t Cy_AutAnalog_SAR_CountsTo_uVolts(uint8_t sarIdx, uint8_t sarSequencer, cy_en_autanalog_sar_input_t sarInput,
                                      uint8_t sarChannel, uint32_t VrefmV, int32_t sarCounts);


/*******************************************************************************
* Function Name: Cy_AutAnalog_SAR_CountsTo_degreeC
****************************************************************************//**
*
* Converts the SAR ADC output to degree in Celsius.
*
* \note Measurement of the die temperature works only for MUX channels in single ended configuration with
* connection of negative input of SAR ADC to Vss and connection of positive input of SAR ADC to temperature sensor.

* \note Averaging can be enabled to reduce the noise.
* However, configuration settings for averaging should specify a 12-bit resolution for ADC output in result.
*
* \param sarIdx
* SAR block index within Low Power Peripheral Analog System.
*
* \param sarSequencer
* The SAR ADC sequencer for conversion of output to uVolts.
*
* \param sarChannel
* Channel for SAR conversion.
*
* \param VrefmV
* Reference voltage in mV.
* \note Vref 1.2V should be used during measurement of the die temperature.
*
* \param sarCounts
* SAR conversion result for the channel,
* see \ref Cy_AutAnalog_SAR_ReadResult.
* Or see \ref Cy_AutAnalog_FIFO_ReadWord (\ref Cy_AutAnalog_FIFO_ReadData, ref Cy_AutAnalog_FIFO_ReadDataChanId)
* in case of receiving data for conversion from FIFO.
*
* \return
* SAR conversion result in degree C.
* In case of invalid parameters or incorrect averaging configuration, function return 0 in result.
*
*******************************************************************************/
int16_t Cy_AutAnalog_SAR_CountsTo_degreeC(uint8_t sarIdx, uint8_t sarSequencer, uint8_t sarChannel,
                                       uint32_t VrefmV, int32_t sarCounts);

/** \} group_autanalog_sar_functions */

/**
* \addtogroup group_autanalog_fifo_functions
* \{
*/

/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_LoadConfig
****************************************************************************//**
*
* Loads the entire FIFO configuration.
*
* \param fifoIdx
* FIFO block index within Low Power Peripheral Analog System.
*
* \param fifoCfg
* Pointer to the FIFO configuration structure \ref cy_stc_autanalog_fifo_cfg_t
*
* \return
* Status of initialization, \ref cy_en_autanalog_status_t.
*
*******************************************************************************/
cy_en_autanalog_status_t Cy_AutAnalog_FIFO_LoadConfig(uint8_t fifoIdx, const cy_stc_autanalog_fifo_cfg_t * fifoCfg);


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_GetSize
****************************************************************************//**
*
* Returns the current number of data samples in buffer.
*
* \param fifoIdx
* FIFO block index within Low Power Peripheral Analog System.
*
* \param buffIdx
* The buffer index within FIFO block.
*
* \return
* The 9-bit number of samples.
*
*******************************************************************************/
uint16_t Cy_AutAnalog_FIFO_GetSize(uint8_t fifoIdx, uint8_t buffIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_ReadWord
****************************************************************************//**
*
* Reads one sample from the specified FIFO buffer.
*
* \param fifoIdx
* FIFO block index within Low Power Peripheral Analog System.
*
* \param buffIdx
* FIFO buffer index within FIFO block.
*
* \return
* The 32-bit FIFO sample.
*
*******************************************************************************/
int32_t Cy_AutAnalog_FIFO_ReadWord(uint8_t fifoIdx, uint8_t buffIdx);


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_ReadData
****************************************************************************//**
*
* Loads the entire data from the FIFO.
*
* \param fifoIdx
* FIFO block index within Low Power Peripheral Analog System.
*
* \param buffIdx
* The buffer index within FIFO block.
*
* \param data
* The pointer to the data array with a size not less than the buffer size 
* (specified by the \ref cy_stc_autanalog_fifo_cfg_t::split setting)
*
* \return
* The 9-bit size of the buffer payload being copied into the data array
*
*******************************************************************************/
uint16_t Cy_AutAnalog_FIFO_ReadData(uint8_t fifoIdx, uint8_t buffIdx, int32_t * data);


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_ReadDataChanId
****************************************************************************//**
*
* Loads the entire data with channel ID from the FIFO.
*
* \param fifoIdx
* FIFO block index within Low Power Peripheral Analog System.
*
* \param buffIdx
* The buffer index within FIFO block.
*
* \param input
* The type of the SAR Sequencer Table configuration structure \ref cy_en_autanalog_sar_input_t.
*
* \param data
* The pointer to the data array with a size not less than the buffer size
* (specified by the \ref cy_stc_autanalog_fifo_cfg_t::split setting)
*
* \param chanID
* The pointer to the channel IDs array with a size not less than the buffer size
* (specified by the \ref cy_stc_autanalog_fifo_cfg_t::split setting)
*
* \return
* The 9-bit size of the buffer payload being copied into the data array
*
*******************************************************************************/
uint16_t Cy_AutAnalog_FIFO_ReadDataChanId(uint8_t fifoIdx, uint8_t buffIdx, cy_en_autanalog_sar_input_t input, int32_t * data, uint8_t * chanID);


/**
* \addtogroup group_autanalog_fifo_functions_int
* This set of functions is used to handle FIFO interrupts in the SAR ADC.
* \{
*/
/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_GetInterruptCause
****************************************************************************//**
*
* Returns the cause of the interrupt for the FIFO.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \return
* The mask of the event, which causes an interrupt in the FIFO.
*
*******************************************************************************/
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptCause(uint8_t fifoIdx)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    return AUTANALOG_MMIO_FIFO_INTR_CAUSE(LPPASS_MMIO_BASE);
}


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_GetInterruptStatus
****************************************************************************//**
*
* Returns the status of combined FIFO interrupt requests.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \return
* The combined mask of interrupt requests for the FIFO.
*
*******************************************************************************/
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptStatus(uint8_t fifoIdx)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    return AUTANALOG_MMIO_FIFO_INTR(LPPASS_MMIO_BASE);
}


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_ClearInterrupt
****************************************************************************//**
*
* Clears the interrupts for the FIFO.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \param interrupt
* The mask of the interrupts to be cleared. Each bit of this mask is responsible for
* clearing of the corresponding interrupt in the FIFO.
*
*******************************************************************************/
__STATIC_INLINE void Cy_AutAnalog_FIFO_ClearInterrupt(uint8_t fifoIdx, uint32_t interrupt)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    CY_ASSERT_L2(CY_AUTANALOG_INTR_FIFO_MASK(interrupt));

    AUTANALOG_MMIO_FIFO_INTR(LPPASS_MMIO_BASE) = CY_AUTANALOG_INTR_FIFO & interrupt;
}


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_SetInterrupt
****************************************************************************//**
*
* Sets a software interrupt request for the FIFO.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \param interrupt
* The mask of the interrupts to be set. Each bit of this mask is responsible for
* triggering of the corresponding interrupt in the FIFO.
*
*******************************************************************************/
__STATIC_INLINE void Cy_AutAnalog_FIFO_SetInterrupt(uint8_t fifoIdx, uint32_t interrupt)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    CY_ASSERT_L2(CY_AUTANALOG_INTR_FIFO_MASK(interrupt));

    AUTANALOG_MMIO_FIFO_INTR_SET(LPPASS_MMIO_BASE) = CY_AUTANALOG_INTR_FIFO & interrupt;
}


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_SetInterruptMask
****************************************************************************//**
*
* Configures which bits of the interrupt request register will trigger
* an interrupt event in the FIFO.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \param mask
* The mask of interrupts allowed to be activated. Each bit of this mask
* allows the corresponding interrupt to be triggered in the FIFO.
*
*******************************************************************************/
__STATIC_INLINE void Cy_AutAnalog_FIFO_SetInterruptMask(uint8_t fifoIdx, uint32_t mask)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    CY_ASSERT_L2(CY_AUTANALOG_INTR_FIFO_MASK(mask));

    AUTANALOG_MMIO_FIFO_INTR_MASK(LPPASS_MMIO_BASE) = CY_AUTANALOG_INTR_FIFO & mask;
}


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_GetInterruptMask
****************************************************************************//**
*
* Returns the interrupt mask. Each bit of this mask represents an interrupt
* that is allowed in the FIFO.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \return
* The mask of the interrupts that can be activated.
*
*******************************************************************************/
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptMask(uint8_t fifoIdx)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    return AUTANALOG_MMIO_FIFO_INTR_MASK(LPPASS_MMIO_BASE);
}


/*******************************************************************************
* Function Name: Cy_AutAnalog_FIFO_GetInterruptStatusMasked
****************************************************************************//**
*
* Returns the result of the bitwise AND operation between the
* corresponding interrupt request and mask bits.
* See \ref Cy_AutAnalog_FIFO_GetInterruptStatus and \ref Cy_AutAnalog_FIFO_SetInterruptMask.
*
* \param fifoIdx
* The index of the FIFO block within the Autonomous Analog infrastructure.
*
* \return
* The masked status of combined interrupt requests for the FIFO.
*
*******************************************************************************/
__STATIC_INLINE uint32_t Cy_AutAnalog_FIFO_GetInterruptStatusMasked(uint8_t fifoIdx)
{
    CY_UNUSED_PARAMETER(fifoIdx); /* One instance of the FIFO is currently supported */

    return AUTANALOG_MMIO_FIFO_INTR_MASKED(LPPASS_MMIO_BASE);
}

/** \} group_autanalog_fifo_functions_int */

/** \} group_autanalog_fifo_functions */

#if defined(__cplusplus)
}
#endif

#endif /* CY_IP_MXS22LPPASS_SAR */

#endif /** !defined(CY_AUTANALOG_SAR_H) */



/* [] END OF FILE */
