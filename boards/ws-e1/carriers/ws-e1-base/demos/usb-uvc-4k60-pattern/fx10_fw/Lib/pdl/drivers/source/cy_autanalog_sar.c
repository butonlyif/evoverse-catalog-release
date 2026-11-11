/***************************************************************************//**
* \file cy_autanalog_sar.c
* \version 1.0
*
* \brief
* Provides the public functions for the SAR subsystem of the Low Power Peripheral Analog System.
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
#include <string.h>
#include "cy_autanalog_sar.h"

#ifdef CY_IP_MXS22LPPASS_SAR

/* Helper macros for range validation */
#define AUTANALOG_SAR_INPUT(value)                          ((value) <= CY_AUTANALOG_SAR_INPUT_MUX)
#define AUTANALOG_SAR_CHANNEL(key, value)                   ((value) < ((key == CY_AUTANALOG_SAR_INPUT_GPIO) ? \
                                                                             PASS_SAR_SAR_GPIO_CHANNELS : \
                                                                             PASS_SAR_SAR_MUX_CHANNELS))
/* Validation macros for HS/LP sequencers */
#define AUTANALOG_SAR_SEQ_NUM(value)                        ((value) <=  CY_AUTANALOG_SAR_SEQUENCER_NUM)
#define AUTANALOG_SAR_SEQ_MUX_EN(value)                     ((value) <= CY_AUTANALOG_SAR_CHAN_MUX_ENABLE)
#define AUTANALOG_SAR_SEQ_MUX_MODE(value)                   ((value) <= 0x04UL)
#define AUTANALOG_SAR_SEQ_MUX_SEL(value)                    ((value) <= 0x0FUL)
#define AUTANALOG_SAR_SEQ_SAMPLE_TIME(value)                ((value) <= CY_AUTANALOG_SAR_SAMPLE_TIME3)
#define AUTANALOG_SAR_SEQ_AVG_CNT(value)                    ((value) <= CY_AUTANALOG_SAR_ACC_CNT256)
#define AUTANALOG_SAR_SEQ_CAL_REQ(value)                    ((value) <= CY_AUTANALOG_SAR_CAL_LINEARITY)
#define AUTANALOG_SAR_SEQ_NEXT_STATE(value)                 ((value) <= CY_AUTANALOG_SAR_NEXT_ACTION_GO_TO_NEXT)
/* Validation macros for static cfg */
#define AUTANALOG_SAR_STA_CFG_CH_DEFAULT_GAIN               (0x8000UL)
#define AUTANALOG_SAR_STA_CFG_CH_DEFAULT_OFFSET             (0x0UL)
#define AUTANALOG_SAR_STA_CFG_TR_HS_CH_DEFAULT_SAMPLE_TIME  (31UL)
#define AUTANALOG_SAR_STA_CFG_TR_LP_CH_DEFAULT_SAMPLE_TIME  (5UL)
#define AUTANALOG_SAR_STA_CFG_SAMPLER_EN(value)             ((value) <= SAR_STA_HS_SAMP_CFG_HS_SAMP_EN_Msk)
#define AUTANALOG_SAR_STA_CFG_SAMPLE_TIME(value)            ((value) <= SAR_STA_TR_SAMPLE_TIME_HS_TR_SAMPLE_TIME_Msk)
#define AUTANALOG_SAR_STA_CFG_FIR_MASK(value)               ((value) <= SAR_STA_FIR_RESULT_MASK_FIR_RESULT_MASK_Msk)
#define AUTANALOG_SAR_STA_CFG_CH_GAIN(value)                (((uint16_t)(value) > 0U) && ((uint16_t)(value) <= 65535U))
#define AUTANALOG_SAR_STA_CFG_CH_OFFSET(value)              (((int16_t)(value) >= -2048) && ((int16_t)(value) <= 2047))
/* Validation macros for CTRL register */
#define AUTANALOG_SAR_CTRL_VREF(value)                      ((value) <= CY_AUTANALOG_SAR_VREF_PRB_VREF1)
#define AUTANALOG_SAR_CTRL_BUFF_PWR(value)                  ((value) <= CY_AUTANALOG_SAR_BUF_PWR_ULTRA_HIGH_RAIL)
#define AUTANALOG_SAR_CTRL_AVG_MODE(value)                  ((value) <= CY_AUTANALOG_SAR_ACC_INTERLEAVED)
#define AUTANALOG_SAR_CTRL_STARTUP_CAL(value)               ((value) <= CY_AUTANALOG_SAR_CAL_LINEARITY)
/* Validation macros for GPIO CH CFG registers */
#define AUTANALOG_SAR_GPIO_PIN(value)                       ((value) <= CY_AUTANALOG_SAR_PIN_GPIO7)
#define AUTANALOG_SAR_CH_COEF(value)                        ((value) <= CY_AUTANALOG_SAR_CH_COEFF7)
/* Validation macros for MUX CH CFG registers */
#define AUTANALOG_SAR_MUX_PIN(value)                       (((value) <= CY_AUTANALOG_SAR_PIN_MUX_GPIO7) || \
                                                            ((value) == CY_AUTANALOG_SAR_PIN_MUX_VSSA_KELVIN))
/* Validation macros for STATUS registers */
#define AUTANALOG_SAR_STATUS_SEL(value)                     ((value) <= CY_AUTANALOG_SAR_LIMIT_STATUS_STC3)
#define AUTANALOG_SAR_STATUS_COND(value)                    ((value) <= CY_AUTANALOG_SAR_COND_OUTSIDE)
/* Validation macros for RESULT STATUS and RANGE STATUS registers */
#define AUTANALOG_SAR_FIR_STATUS(value)                     ((value) <= CY_AUTANALOG_SAR_MASK_FIR1)
/* Validation macros for FIR registers */
#define AUTANALOG_SAR_FIR_IDX(value)                        ((value) < CY_AUTANALOG_SAR_FIR_NUM)
#define AUTANALOG_SAR_FIR_CHANNEL_SEL(value)                ((value) <= CY_AUTANALOG_SAR_FIR_CH_MUX15)
#define AUTANALOG_SAR_FIR_TAP_SEL(value)                    ((value) < CY_AUTANALOG_SAR_FIR_TAP_NUM)
#define AUTANALOG_SAR_FIR_TAP_VAL(value)                    (((value) >= (int16_t)-32768) && ((value) <= (int16_t)32767))
#define AUTANALOG_SAR_FIR_SHIFT_SEL(value)                  ((value) <= 0x0FUL)
/* Validation macros for FIFO registers */
#define AUTANALOG_MMIO_FIFO_BUFF_IDX(value)                 ((value) < CY_AUTANALOG_FIFO_BUFS_NUM)
#define AUTANALOG_MMIO_FIFO_CFG(value)                      ((value) <= CY_AUTANALOG_FIFO_SPLIT8)
/* Validation macros for FIFO LEVEL register */
#define AUTANALOG_MMIO_FIFO_SEL(value)                      ((value) <= CY_AUTANALOG_FIFO_SELECT7)
#define AUTANALOG_MMIO_FIFO_LEVEL(value)                    ((value) <= LPPASS_MMIO_STA_LEVEL_LEVEL_Msk)
/* Position of the sign in FIFO data with channel ID */
#define AUTANALOG_MMIO_FIFO_SIGN_POS                        (23U)
#define AUTANALOG_MMIO_FIFO_SIGN_MASK                       (0x1UL << AUTANALOG_MMIO_FIFO_SIGN_POS)
/* Position of the channel ID in FIFO data for GPIO channels */
#define AUTANALOG_MMIO_FIFO_CH_ID_POS_GPIO                  (24U)
#define AUTANALOG_MMIO_FIFO_CH_ID_MASK_GPIO                 (0x7UL << AUTANALOG_MMIO_FIFO_CH_ID_POS_GPIO)
/* Position of the channel ID in FIFO data for MUX channels */
#define AUTANALOG_MMIO_FIFO_CH_ID_POS_MUX                   (28U)
#define AUTANALOG_MMIO_FIFO_CH_ID_MASK_MUX                  (0xFUL << AUTANALOG_MMIO_FIFO_CH_ID_POS_MUX)
/* SAR ADC conversion macros */
#define AUTANALOG_SAR_SEQ_IDX(value)                        ((value) <  CY_AUTANALOG_SAR_SEQUENCER_NUM)
#define AUTANALOG_SAR_VREF_MAX(value)                       ((value) <= 1800) /* Vdda is 1.8V */
#define AUTANALOG_SAR_10V_COUNTS                            (10UL)
#define AUTANALOG_SAR_10mV_COUNTS                           (10000UL)
#define AUTANALOG_SAR_10uV_COUNTS                           (10000000UL)
#define AUTANALOG_SAR_MAX_BITS12                            (0x00001000L)
#define AUTANALOG_SAR_MAX_BITS16                            (0x00010000L)
#define AUTANALOG_SAR_OFFSET_BITS12                         (AUTANALOG_SAR_MAX_BITS12 / 2L)
#define AUTANALOG_SAR_OFFSET_BITS16                         (AUTANALOG_SAR_MAX_BITS16 / 2L)
/* SAR ADC die temperature macros */
#define AUTANALOG_SAR_TEMP_MULT                             (0x400L)    /* 2^10 - the SFLASH.SAR_TEMP_OFFSET multiplier */
#define AUTANALOG_SAR_TEMP_DIV                              (0x10000L)  /* 1 in Q16.16 format */
#define AUTANALOG_SAR_TEMP_HALF                             (0x8000L)   /* 0.5 in Q16.16 format */
#ifndef AUTANALOG_SAR_TEMP_VREF
#define AUTANALOG_SAR_TEMP_VREF                             (1200L)     /* DieTemp reference voltage */
#endif/* AUTANALOG_SAR_TEMP_VREF */
#ifndef AUTANALOG_SAR_TEMP_SCALE_MULT
#define AUTANALOG_SAR_TEMP_SCALE_MULT                       (0x8L)      /* Scale adjustment multiplier (effectively 0.5 << 4)
                                                                      * 0.5 in Q28.4 format
                                                                      */
#endif/* AUTANALOG_SAR_TEMP_SCALE_MULT */
#ifndef AUTANALOG_SAR_TEMP_SCALE_DIV
#define AUTANALOG_SAR_TEMP_SCALE_DIV                        (0x10L)     /* Scale adjustment divider (effectively 1 << 4)
                                                                      * 1 in Q28.4 format
                                                                      */
#endif/* AUTANALOG_SAR_TEMP_SCALE_DIV */
#ifndef AUTANALOG_SAR_TEMP_CENT
#define AUTANALOG_SAR_TEMP_CENT                             (0xF0000L)  /* Dual slope correction center value 15 degrees Celsius
                                                                      * in Q16.16 format
                                                                      */
#endif/* AUTANALOG_SAR_TEMP_CENT */
#ifndef AUTANALOG_SAR_TEMP_HIGH
#define AUTANALOG_SAR_TEMP_HIGH                             (0x640000L) /* 100 degrees Celsius in Q16.16 format */
#endif/* AUTANALOG_SAR_TEMP_HIGH */
#ifndef AUTANALOG_SAR_TEMP_LOW
#define AUTANALOG_SAR_TEMP_LOW                              (0x280000L) /* 40 degrees Celsius in Q16.16 format */
#endif/* AUTANALOG_SAR_TEMP_LOW */
/* TBD, get calibration coefficients from FLASH */
#define AUTANALOG_SAR_TEMP_MULTIPLIER                       (0x1)
#define AUTANALOG_SAR_TEMP_OFFSET                           (0x0)


/* Forward declarations */
static cy_en_autanalog_status_t SAR_LoadFIR(uint8_t sarIdx, uint8_t cfgNum, const cy_stc_autanalog_sar_fir_cfg_t * firCfg);
static void SAR_LoadGpioChan(uint32_t baseAddr, uint8_t cfgNum, cy_stc_autanalog_sar_hs_chan_t * const hsGpioChan[]);
static void SAR_LoadMuxChan(uint32_t baseAddr, uint8_t cfgNum, cy_stc_autanalog_sar_mux_chan_t * const intMuxChan[]);
static void SAR_LoadRangeCond(uint32_t baseAddr, uint8_t cfgNum, cy_stc_autanalog_sar_limit_t * const limitCond[]);
static int32_t SAR_CheckChanOffset(uint32_t baseAddr, cy_en_autanalog_sar_input_t sarInput, uint8_t sarChannel, bool sarMode16);
static int32_t SAR_GetAverageVoltCounts(uint32_t baseAddr, uint8_t sarSequencer,
               cy_en_autanalog_sar_input_t sarInput, uint8_t sarChannel, int32_t sarCounts, bool * sarMode16);
static int32_t SAR_GetAverageTempCounts(uint32_t baseAddr, uint8_t sarSequencer,
                                        cy_en_autanalog_sar_input_t sarInput, int32_t sarCounts);
static int32_t SAR_CountsToDegreeC(int32_t sarCounts);


cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadConfig(uint8_t sarIdx, const cy_stc_autanalog_sar_t * sarCfg)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SAR_BAD_PARAM;
    
    if (NULL != sarCfg)
    {
        result = Cy_AutAnalog_SAR_LoadStaticConfig(sarIdx, sarCfg->sarStaCfg);

        /* The High Speed configuration might be optional */
        if ((CY_AUTANALOG_SUCCESS == result) && (0U != sarCfg->hsSeqTabNum) && (NULL != sarCfg->hsSeqTabArr))
        {
            result = Cy_AutAnalog_SAR_LoadHSseqTable(sarIdx, sarCfg->hsSeqTabNum, sarCfg->hsSeqTabArr);
        }

        if (CY_AUTANALOG_SUCCESS == result)
        {
            result = Cy_AutAnalog_SAR_LoadLPseqTable(sarIdx, sarCfg->lpSeqTabNum, sarCfg->lpSeqTabArr);
        }

        if ((CY_AUTANALOG_SUCCESS == result) && (sarCfg->firNum > 0U))
        {
            result = SAR_LoadFIR(sarIdx, sarCfg->firNum, sarCfg->firCfg);
        }

        /* Currently, single instance of FIFO is tightly linked with SAR */
        if ((CY_AUTANALOG_SUCCESS == result) && (NULL != sarCfg->fifoCfg))
        {
            result = Cy_AutAnalog_FIFO_LoadConfig(0U, sarCfg->fifoCfg);
        }
    }

    return result;
}


cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadStaticConfig(uint8_t sarIdx, const cy_stc_autanalog_sar_sta_t * sarStaCfg)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SAR_BAD_PARAM;

    uint32_t baseAddr;
    uint32_t regVal;
    uint8_t cfgIdx;

    if ((NULL != sarStaCfg) && (NULL != sarStaCfg->lpStaCfg))
    {
        result = Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr);

        if (CY_AUTANALOG_SUCCESS == result)
        {
            uint16_t hsSampleTime[CY_AUTANALOG_SAR_SAMPLE_TIME_NUM] = {0U};
            CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 11.9','Review shows that usage macro NULL does not have any negative drawbacks');
            cy_stc_autanalog_sar_hs_chan_t * hsGpioChan[PASS_SAR_SAR_GPIO_CHANNELS] = {NULL};

            uint16_t hsSamplerEn = (NULL != sarStaCfg->hsStaCfg) ? sarStaCfg->hsStaCfg->hsSamplerEn : 0U;
            cy_en_autanalog_sar_vref_t hsVref = (NULL != sarStaCfg->hsStaCfg) ? sarStaCfg->hsStaCfg->hsVref : CY_AUTANALOG_SAR_VREF_VDDA;
            uint8_t hsGpioResultMask = (NULL != sarStaCfg->hsStaCfg) ? sarStaCfg->hsStaCfg->hsGpioResultMask : 0U;
            if (NULL != sarStaCfg->hsStaCfg)
            {
                (void)memcpy(hsSampleTime, sarStaCfg->hsStaCfg->hsSampleTime, sizeof(hsSampleTime));
                (void)memcpy(hsGpioChan, sarStaCfg->hsStaCfg->hsGpioChan, sizeof(hsGpioChan));
            }

            CY_ASSERT_L3(AUTANALOG_SAR_CTRL_VREF(hsVref));
            CY_ASSERT_L3(AUTANALOG_SAR_CTRL_VREF(sarStaCfg->lpStaCfg->lpVref));
            CY_ASSERT_L3(AUTANALOG_SAR_CTRL_BUFF_PWR(sarStaCfg->posBufPwr));
            CY_ASSERT_L3(AUTANALOG_SAR_CTRL_BUFF_PWR(sarStaCfg->negBufPwr));
            CY_ASSERT_L3(AUTANALOG_SAR_CTRL_AVG_MODE(sarStaCfg->accMode));
            CY_ASSERT_L3(AUTANALOG_SAR_CTRL_STARTUP_CAL(sarStaCfg->startupCal));

            regVal = _VAL2FLD(SAR_STA_CTRL_HS_VREF_SEL, hsVref);
            regVal |= _VAL2FLD(SAR_STA_CTRL_LP_VREF_SEL, sarStaCfg->lpStaCfg->lpVref);
            regVal |= _VAL2FLD(SAR_STA_CTRL_LP_DIFFERENTIAL_EN, sarStaCfg->lpStaCfg->lpDiffEn);
            regVal |= _VAL2FLD(SAR_STA_CTRL_BUF0_PWR_MODE, sarStaCfg->posBufPwr);
            regVal |= _VAL2FLD(SAR_STA_CTRL_BUF1_PWR_MODE, sarStaCfg->negBufPwr);
            regVal |= _VAL2FLD(SAR_STA_CTRL_AVG_MODE, sarStaCfg->accMode);
            regVal |= _VAL2FLD(SAR_STA_CTRL_STARTUP_CAL_EN, sarStaCfg->startupCal);
            regVal |= _VAL2FLD(SAR_STA_CTRL_CHAN_ID_EN, sarStaCfg->chanID);
            regVal |= _VAL2FLD(SAR_STA_CTRL_SHIFT_MODE, sarStaCfg->shiftMode);

            AUTANALOG_SAR_CTRL(baseAddr) = regVal;

            CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_SAMPLER_EN(hsSamplerEn));
            CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_SAMPLE_TIME(AUTANALOG_SAR_STA_CFG_TR_HS_CH_DEFAULT_SAMPLE_TIME));
            CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_SAMPLE_TIME(AUTANALOG_SAR_STA_CFG_TR_LP_CH_DEFAULT_SAMPLE_TIME));
            CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_FIR_MASK(sarStaCfg->firResultMask));

            SAR_LoadGpioChan(baseAddr, PASS_SAR_SAR_GPIO_CHANNELS, hsGpioChan);
            SAR_LoadMuxChan(baseAddr, PASS_SAR_SAR_MUX_CHANNELS, sarStaCfg->intMuxChan);
            SAR_LoadRangeCond(baseAddr, (uint8_t)CY_AUTANALOG_SAR_LIMIT_CFG_NUM, sarStaCfg->limitCond);

            regVal = _VAL2FLD(SAR_STA_HS_SAMP_CFG_HS_SAMP_EN, hsSamplerEn);
            AUTANALOG_SAR_HS_SAMP_CFG(baseAddr) = regVal;

            /* Set default values for HS/LP trigger sample time */
            regVal = _VAL2FLD(SAR_STA_TR_SAMPLE_TIME_HS_TR_SAMPLE_TIME, AUTANALOG_SAR_STA_CFG_TR_HS_CH_DEFAULT_SAMPLE_TIME);
            regVal |= _VAL2FLD(SAR_STA_TR_SAMPLE_TIME_LP_TR_SAMPLE_TIME, AUTANALOG_SAR_STA_CFG_TR_LP_CH_DEFAULT_SAMPLE_TIME);
            AUTANALOG_SAR_TR_SAMPLE_TIME(baseAddr) = regVal;

            for (cfgIdx = 0; cfgIdx < CY_AUTANALOG_SAR_SAMPLE_TIME_NUM; cfgIdx++)
            {
                CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_SAMPLE_TIME(hsSampleTime[cfgIdx]));
                CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_SAMPLE_TIME(sarStaCfg->lpStaCfg->lpSampleTime[cfgIdx]));

                regVal = _VAL2FLD(SAR_STA_SAMPLE_TIME_HS_SAMPLE_TIME, hsSampleTime[cfgIdx]);
                regVal |= _VAL2FLD(SAR_STA_SAMPLE_TIME_LP_SAMPLE_TIME, sarStaCfg->lpStaCfg->lpSampleTime[cfgIdx]);
                AUTANALOG_SAR_SAMPLE_TIME(baseAddr, cfgIdx) = regVal;
            }

            regVal = _VAL2FLD(SAR_STA_CHAN_RESULT_MASK_GPIO_CHAN_RESULT_MASK, hsGpioResultMask);
            regVal |= _VAL2FLD(SAR_STA_CHAN_RESULT_MASK_MUX_CHAN_RESULT_MASK, sarStaCfg->muxResultMask);
            AUTANALOG_SAR_CHAN_RESULT_MASK(baseAddr) = regVal;

            regVal = _VAL2FLD(SAR_STA_FIR_RESULT_MASK_FIR_RESULT_MASK, sarStaCfg->firResultMask);
            AUTANALOG_SAR_FIR_RESULT_MASK(baseAddr) = regVal;

            for (cfgIdx = 0; cfgIdx < CY_AUTANALOG_SAR_CH_CORR_COEFF_NUM; cfgIdx++)
            {
                CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_CH_GAIN(AUTANALOG_SAR_STA_CFG_CH_DEFAULT_GAIN));
                CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_CH_OFFSET(AUTANALOG_SAR_STA_CFG_CH_DEFAULT_OFFSET));

                /* Set default values for gain and offset */
                regVal = _VAL2FLD(SAR_STA_CHAN_COEFF_GAIN, AUTANALOG_SAR_STA_CFG_CH_DEFAULT_GAIN);
                regVal |= _VAL2FLD(SAR_STA_CHAN_COEFF_OFFSET, ((uint16_t)AUTANALOG_SAR_STA_CFG_CH_DEFAULT_OFFSET) & SAR_STA_CHAN_COEFF_OFFSET_Msk);
                AUTANALOG_SAR_CHAN_COEFF(baseAddr, cfgIdx) = regVal;
            }
        }
    }

    return result;
}


cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadHSseqTable(uint8_t sarIdx, uint8_t seqTabNum, const cy_stc_autanalog_sar_seq_tab_hs_t * seqTabArr)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SAR_BAD_PARAM;

    uint32_t baseAddr;
    uint32_t regVal;
    uint8_t cfgIdx;

    CY_ASSERT_L2(AUTANALOG_SAR_SEQ_NUM(seqTabNum));

    result = Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr);

    if ((CY_AUTANALOG_SUCCESS == result) && (seqTabNum > 0U) && (NULL != seqTabArr))
    {
        for (cfgIdx = 0; cfgIdx < seqTabNum; cfgIdx++)
        {
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_MUX_MODE(seqTabArr[cfgIdx].muxMode));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_MUX_SEL(seqTabArr[cfgIdx].mux0Sel));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_MUX_SEL(seqTabArr[cfgIdx].mux1Sel));

            regVal =
                    _VAL2FLD(SAR_SEQ_HS_DATA_HS_GPIO_CHAN_EN, seqTabArr[cfgIdx].chanEn) |
                    _VAL2FLD(SAR_SEQ_HS_DATA_HS_MUX_CHAN_EN_SEL, seqTabArr[cfgIdx].muxMode) |
                    _VAL2FLD(SAR_SEQ_HS_DATA_MUX0_CHAN_SEL, seqTabArr[cfgIdx].mux0Sel) |
                    _VAL2FLD(SAR_SEQ_HS_DATA_MUX1_CHAN_SEL, seqTabArr[cfgIdx].mux1Sel);

            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_SAMPLE_TIME(seqTabArr[cfgIdx].sampleTime));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_AVG_CNT(seqTabArr[cfgIdx].accCount));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_CAL_REQ(seqTabArr[cfgIdx].calReq));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_NEXT_STATE(seqTabArr[cfgIdx].nextAction));

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_SAMPLE_TIME_EN, seqTabArr[cfgIdx].sampleTimeEn);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_TR_SAMPLE_TIME_EN, 0U); /* Set default value */

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_SAMPLE_TIME_SEL, seqTabArr[cfgIdx].sampleTime);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_AVG_EN, seqTabArr[cfgIdx].accEn);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_AVG_CNT, seqTabArr[cfgIdx].accCount);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_CALIBRATE, seqTabArr[cfgIdx].calReq);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_NEXT_ACTION, seqTabArr[cfgIdx].nextAction);

            AUTANALOG_SAR_SEQ_HS_DATA(baseAddr, cfgIdx) = regVal;
        }
    }
    else
    {
        result = CY_AUTANALOG_SAR_BAD_PARAM;
    }

    return result;
}


cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadLPseqTable(uint8_t sarIdx, uint8_t seqTabNum, const cy_stc_autanalog_sar_seq_tab_lp_t * seqTabArr)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SAR_BAD_PARAM;

    uint32_t baseAddr;
    uint32_t regVal;
    uint8_t cfgIdx;

    CY_ASSERT_L2(AUTANALOG_SAR_SEQ_NUM(seqTabNum));

    result = Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr);

    if ((CY_AUTANALOG_SUCCESS == result) && (seqTabNum > 0U) && (NULL != seqTabArr))
    {
        for (cfgIdx = 0; cfgIdx < seqTabNum; cfgIdx++)
        {
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_MUX_EN(seqTabArr[cfgIdx].chanEn));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_MUX_SEL(seqTabArr[cfgIdx].mux0Sel));

            regVal =
                    _VAL2FLD(SAR_SEQ_LP_DATA_LP_CHAN_EN, seqTabArr[cfgIdx].chanEn) |
                    _VAL2FLD(SAR_SEQ_LP_DATA_CHAN_SEL, seqTabArr[cfgIdx].mux0Sel);

            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_SAMPLE_TIME(seqTabArr[cfgIdx].sampleTime));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_AVG_CNT(seqTabArr[cfgIdx].accCount));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_CAL_REQ(seqTabArr[cfgIdx].calReq));
            CY_ASSERT_L3(AUTANALOG_SAR_SEQ_NEXT_STATE(seqTabArr[cfgIdx].nextAction));

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_SAMPLE_TIME_EN, seqTabArr[cfgIdx].sampleTimeEn);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_TR_SAMPLE_TIME_EN, 0U); /* Set default value */

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_SAMPLE_TIME_SEL, seqTabArr[cfgIdx].sampleTime);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_AVG_EN, seqTabArr[cfgIdx].accEn);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_AVG_CNT, seqTabArr[cfgIdx].accCount);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_CALIBRATE, seqTabArr[cfgIdx].calReq);

            regVal |=
                    _VAL2FLD(SAR_SEQ_HS_DATA_NEXT_ACTION, seqTabArr[cfgIdx].nextAction);

            AUTANALOG_SAR_SEQ_LP_DATA(baseAddr, cfgIdx) = regVal;
        }
    }
    else
    {
        result = CY_AUTANALOG_SAR_BAD_PARAM;
    }

    return result;
}


cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadFIRconfig(uint8_t sarIdx, uint8_t firIdx, const cy_stc_autanalog_sar_fir_cfg_t * firCfg)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SAR_BAD_PARAM;

    uint32_t baseAddr;
    uint32_t regVal;
    uint8_t tapIdx;

    CY_ASSERT_L2(AUTANALOG_SAR_FIR_IDX(firIdx));

    if ((NULL != firCfg) && (NULL != firCfg->coeff))
    {
        result = Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr);

        if (CY_AUTANALOG_SUCCESS == result)
        {
            CY_ASSERT_L3(AUTANALOG_SAR_FIR_CHANNEL_SEL(firCfg->chanSel));
            CY_ASSERT_L3(AUTANALOG_SAR_FIR_TAP_SEL(firCfg->tapSel));
            CY_ASSERT_L3(AUTANALOG_SAR_FIR_SHIFT_SEL(firCfg->shiftSel));
            CY_ASSERT_L3(AUTANALOG_SAR_STATUS_SEL(firCfg->firLimit));
            CY_ASSERT_L3(AUTANALOG_MMIO_FIFO_SEL(firCfg->fifoSel));

            regVal = _VAL2FLD(SAR_STA_FIR_CFG_CHANNEL_SEL, firCfg->chanSel);
            regVal |= _VAL2FLD(SAR_STA_FIR_CFG_TAP_SEL, firCfg->tapSel);
            regVal |= _VAL2FLD(SAR_STA_FIR_CFG_SHIFT_SEL, firCfg->shiftSel);
            regVal |= _VAL2FLD(SAR_STA_FIR_CFG_WAIT_TAP_INIT, firCfg->waitTapInit);
            regVal |= _VAL2FLD(SAR_STA_FIR_CFG_STATUS_SEL, firCfg->firLimit);
            regVal |= _VAL2FLD(SAR_STA_FIR_CFG_FIFO_SEL, firCfg->fifoSel);

            AUTANALOG_SAR_FIR_CFG(baseAddr, firIdx) = regVal;

            for (tapIdx = 0; tapIdx <= firCfg->tapSel; tapIdx++)
            {
                CY_ASSERT_L3(AUTANALOG_SAR_FIR_TAP_VAL(firCfg->coeff[tapIdx]));

                if (0U == firIdx)
                {
                    AUTANALOG_SAR_FIR0_COEF(baseAddr, tapIdx) = (uint32_t)firCfg->coeff[tapIdx];
                }
                else
                {
                    AUTANALOG_SAR_FIR1_COEF(baseAddr, tapIdx) = (uint32_t)firCfg->coeff[tapIdx];
                }
            }
        }
    }

    return result;
}


uint8_t Cy_AutAnalog_SAR_GetHSchanLimitStatus(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (uint8_t)_FLD2VAL(SAR_STA_RANGE_STATUS_GPIO_CHAN_RANGE_STATUS, AUTANALOG_SAR_RANGE_STATUS(baseAddr)) : 0U;
}


void Cy_AutAnalog_SAR_ClearHSchanLimitStatus(uint8_t sarIdx, uint8_t chMask)
{
    uint32_t baseAddr;

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        AUTANALOG_SAR_RANGE_STATUS(baseAddr) = _VAL2FLD(SAR_STA_RANGE_STATUS_GPIO_CHAN_RANGE_STATUS, chMask);
    }
}


uint8_t Cy_AutAnalog_SAR_GetHSchanResultStatus(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (uint8_t)_FLD2VAL(SAR_STA_CHAN_RESULT_UPDATED_GPIO_CHAN_RESULT_UPDATED, AUTANALOG_SAR_CHAN_RESULT_STATUS(baseAddr)) : 0U;
}


void Cy_AutAnalog_SAR_ClearHSchanResultStatus(uint8_t sarIdx, uint8_t chMask)
{
    uint32_t baseAddr;

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        AUTANALOG_SAR_CHAN_RESULT_STATUS(baseAddr) = _VAL2FLD(SAR_STA_CHAN_RESULT_UPDATED_GPIO_CHAN_RESULT_UPDATED, chMask);
    }
}


uint16_t Cy_AutAnalog_SAR_GetMuxChanLimitStatus(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (uint16_t)_FLD2VAL(SAR_STA_RANGE_STATUS_MUX_CHAN_RANGE_STATUS, AUTANALOG_SAR_RANGE_STATUS(baseAddr)) : 0U;
}


void Cy_AutAnalog_SAR_ClearMuxChanLimitStatus(uint8_t sarIdx, uint16_t chMask)
{
    uint32_t baseAddr;

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        AUTANALOG_SAR_RANGE_STATUS(baseAddr) = _VAL2FLD(SAR_STA_RANGE_STATUS_MUX_CHAN_RANGE_STATUS, chMask);
    }
}


uint16_t Cy_AutAnalog_SAR_GetMuxChanResultStatus(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (uint16_t)_FLD2VAL(SAR_STA_CHAN_RESULT_UPDATED_MUX_CHAN_RESULT_UPDATED, AUTANALOG_SAR_CHAN_RESULT_STATUS(baseAddr)) : 0U;
}


void Cy_AutAnalog_SAR_ClearMuxChanResultStatus(uint8_t sarIdx, uint16_t chMask)
{
    uint32_t baseAddr;

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        AUTANALOG_SAR_CHAN_RESULT_STATUS(baseAddr) = _VAL2FLD(SAR_STA_CHAN_RESULT_UPDATED_MUX_CHAN_RESULT_UPDATED, chMask);
    }
}


int32_t Cy_AutAnalog_SAR_ReadResult(uint8_t sarIdx, cy_en_autanalog_sar_input_t input, uint8_t channel)
{
    uint32_t baseAddr;
    int32_t regVal = 0;

    CY_ASSERT_L2(AUTANALOG_SAR_INPUT(input));
    CY_ASSERT_L2(AUTANALOG_SAR_CHANNEL(input, channel));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.8', 2, 'Review shows that type conversion from unsigned to signed does not have any negative drawbacks');
        regVal = (input == CY_AUTANALOG_SAR_INPUT_GPIO) ?
                 (int32_t)_FLD2VAL(SAR_STA_GPIO_CHAN_RESULT_RESULT, AUTANALOG_SAR_GPIO_CHAN_RESULT(baseAddr, channel)):
                 (int32_t)_FLD2VAL(SAR_STA_MUX_CHAN_RESULT_RESULT, AUTANALOG_SAR_MUX_CHAN_RESULT(baseAddr, channel));
        CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.8');
    }

    return regVal;
}


uint8_t Cy_AutAnalog_SAR_FIRgetLimitStatus(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (uint8_t)_FLD2VAL(SAR_STA_RANGE_STATUS_FIR_RANGE_STATUS, AUTANALOG_SAR_RANGE_STATUS(baseAddr)) : 0U;
}


void Cy_AutAnalog_SAR_FIRclearLimitStatus(uint8_t sarIdx, uint8_t firMask)
{
    uint32_t baseAddr;

    CY_ASSERT_L2(AUTANALOG_SAR_FIR_STATUS(firMask));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        AUTANALOG_SAR_RANGE_STATUS(baseAddr) = _VAL2FLD(SAR_STA_RANGE_STATUS_FIR_RANGE_STATUS, firMask);
    }
}


uint8_t Cy_AutAnalog_SAR_FIRgetResultStatus(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (uint8_t)_FLD2VAL(SAR_STA_FIR_RESULT_UPDATED_FIR_RESULT_UPDATED, AUTANALOG_SAR_FIR_RESULT_STATUS(baseAddr)) : 0U;
}


void Cy_AutAnalog_SAR_FIRclearResultStatus(uint8_t sarIdx, uint8_t firMask)
{
    uint32_t baseAddr;

    CY_ASSERT_L2(AUTANALOG_SAR_FIR_STATUS(firMask));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        AUTANALOG_SAR_FIR_RESULT_STATUS(baseAddr) = _VAL2FLD(SAR_STA_FIR_RESULT_UPDATED_FIR_RESULT_UPDATED, firMask);
    }
}


int32_t Cy_AutAnalog_SAR_FIRreadResult(uint8_t sarIdx, uint8_t firIdx)
{
    uint32_t baseAddr;

    CY_ASSERT_L2(AUTANALOG_SAR_FIR_IDX(firIdx));

    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.8', 1, 'Review shows that type conversion from unsigned to signed does not have any negative drawbacks');
    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (int32_t)_FLD2VAL(SAR_STA_FIR_RESULT_RESULT, AUTANALOG_SAR_FIR_RESULT(baseAddr, firIdx)) : 0;
    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.8');
}


cy_en_autanalog_status_t Cy_AutAnalog_SAR_LoadOffsetGainCorr(uint8_t sarIdx, uint16_t chanGain[], int16_t chanOffset[])
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SAR_BAD_PARAM;

    uint32_t baseAddr;
    uint32_t regVal;
    uint8_t cfgIdx;

    if ((NULL != chanGain) && (NULL != chanOffset))
    {
        result = Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr);

        if (CY_AUTANALOG_SUCCESS == result)
        {
            for (cfgIdx = 0; cfgIdx < CY_AUTANALOG_SAR_CH_CORR_COEFF_NUM; cfgIdx++)
            {
                CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_CH_GAIN(chanGain[cfgIdx]));
                CY_ASSERT_L3(AUTANALOG_SAR_STA_CFG_CH_OFFSET(chanOffset[cfgIdx]));

                regVal = _VAL2FLD(SAR_STA_CHAN_COEFF_GAIN, chanGain[cfgIdx]);
                regVal |= _VAL2FLD(SAR_STA_CHAN_COEFF_OFFSET, ((uint16_t)chanOffset[cfgIdx]) & SAR_STA_CHAN_COEFF_OFFSET_Msk);
                AUTANALOG_SAR_CHAN_COEFF(baseAddr, cfgIdx) = regVal;
            }
        }
    }

    return result;
}


bool Cy_AutAnalog_SAR_IsBusy(uint8_t sarIdx)
{
    uint32_t baseAddr;

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr) ?
           (bool)_FLD2VAL(SAR_STA_STATUS_BUSY, AUTANALOG_SAR_STATUS(baseAddr)) : false;
}


float32_t Cy_AutAnalog_SAR_CountsTo_Volts(uint8_t sarIdx, uint8_t sarSequencer, cy_en_autanalog_sar_input_t sarInput,
                                       uint8_t sarChannel, uint32_t VrefmV, int32_t sarCounts)
{
    uint32_t  baseAddr;
    uint32_t  sarGain;
    int32_t   sarOffset;
    bool      sarMode16 = false;
    float32_t Volts     = 0.0F;

    CY_ASSERT_L2(AUTANALOG_SAR_SEQ_IDX(sarSequencer));
    CY_ASSERT_L2(AUTANALOG_SAR_INPUT(sarInput));
    CY_ASSERT_L2(AUTANALOG_SAR_CHANNEL(sarInput, sarChannel));
    CY_ASSERT_L2(AUTANALOG_SAR_VREF_MAX(VrefmV));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        /* Check ADC resolution and calculate average if any */
        sarCounts = SAR_GetAverageVoltCounts(baseAddr, sarSequencer, sarInput, sarChannel, sarCounts, &sarMode16);

        /* Calculate gain for SAR ADC channel */
        sarGain = sarMode16 ? (uint32_t)AUTANALOG_SAR_MAX_BITS16 : (uint32_t)AUTANALOG_SAR_MAX_BITS12;
        sarGain = CY_SYSLIB_DIV_ROUND(sarGain * (uint32_t) AUTANALOG_SAR_10mV_COUNTS / (uint32_t) 2UL, (uint32_t) VrefmV);

        /* Calculate offset for SAR ADC channel */
        sarOffset = SAR_CheckChanOffset(baseAddr, sarInput, sarChannel, sarMode16);

        /* SAR ADC result in V */
        Volts = (((float32_t) sarCounts + (float32_t) sarOffset) * (float32_t) AUTANALOG_SAR_10V_COUNTS) / (float32_t) sarGain;
    }

    return Volts;
}


int16_t Cy_AutAnalog_SAR_CountsTo_mVolts(uint8_t sarIdx, uint8_t sarSequencer, cy_en_autanalog_sar_input_t sarInput,
                                      uint8_t sarChannel, uint32_t VrefmV, int32_t sarCounts)
{
    uint32_t baseAddr;
    uint32_t sarGain;
    int32_t  sarOffset;
    bool     sarMode16 = false;
    int32_t  mVolts    = 0;

    CY_ASSERT_L2(AUTANALOG_SAR_SEQ_IDX(sarSequencer));
    CY_ASSERT_L2(AUTANALOG_SAR_INPUT(sarInput));
    CY_ASSERT_L2(AUTANALOG_SAR_CHANNEL(sarInput, sarChannel));
    CY_ASSERT_L2(AUTANALOG_SAR_VREF_MAX(VrefmV));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        /* Check ADC resolution and calculate average if any */
        sarCounts = SAR_GetAverageVoltCounts(baseAddr, sarSequencer, sarInput, sarChannel, sarCounts, &sarMode16);

        /* Calculate gain for SAR ADC channel */
        sarGain = sarMode16 ? (uint32_t)AUTANALOG_SAR_MAX_BITS16 : (uint32_t)AUTANALOG_SAR_MAX_BITS12;
        sarGain = CY_SYSLIB_DIV_ROUND(sarGain * (uint32_t) AUTANALOG_SAR_10mV_COUNTS / (uint32_t) 2UL, (uint32_t) VrefmV);

        /* Calculate offset for SAR ADC channel */
        sarOffset = SAR_CheckChanOffset(baseAddr, sarInput, sarChannel, sarMode16);

        /* SAR ADC result in mV */
        sarCounts += (int32_t) sarOffset;
        mVolts = sarCounts * (int32_t) AUTANALOG_SAR_10mV_COUNTS;
        if (sarCounts > 0)
        {
            mVolts += (int32_t) sarGain / 2;
        }
        else
        {
            mVolts -= (int32_t) sarGain / 2;
        }
        mVolts /= (int32_t) sarGain;
    }

    return (int16_t) mVolts;
}


int32_t Cy_AutAnalog_SAR_CountsTo_uVolts(uint8_t sarIdx, uint8_t sarSequencer, cy_en_autanalog_sar_input_t sarInput,
                                      uint8_t sarChannel, uint32_t VrefmV, int32_t sarCounts)
{
    uint32_t baseAddr;
    uint32_t sarGain;
    int32_t  sarOffset;
    bool     sarMode16 = false;
    int64_t  uVolts    = 0;

    CY_ASSERT_L2(AUTANALOG_SAR_SEQ_IDX(sarSequencer));
    CY_ASSERT_L2(AUTANALOG_SAR_INPUT(sarInput));
    CY_ASSERT_L2(AUTANALOG_SAR_CHANNEL(sarInput, sarChannel));
    CY_ASSERT_L2(AUTANALOG_SAR_VREF_MAX(VrefmV));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        /* Check ADC resolution and calculate average if any */
        sarCounts = SAR_GetAverageVoltCounts(baseAddr, sarSequencer, sarInput, sarChannel, sarCounts, &sarMode16);

        /* Calculate gain for SAR ADC channel */
        sarGain = sarMode16 ? (uint32_t)AUTANALOG_SAR_MAX_BITS16 : (uint32_t)AUTANALOG_SAR_MAX_BITS12;
        sarGain = CY_SYSLIB_DIV_ROUND(sarGain * (uint32_t) AUTANALOG_SAR_10mV_COUNTS / (uint32_t) 2UL, (uint32_t) VrefmV);

        /* Calculate offset for SAR ADC channel */
        sarOffset = SAR_CheckChanOffset(baseAddr, sarInput, sarChannel, sarMode16);

        /* SAR ADC result in uV */
        uVolts = (((int64_t) sarCounts + (int64_t) sarOffset) * (int64_t) AUTANALOG_SAR_10uV_COUNTS) / (int64_t) sarGain;
    }

    return (int32_t) uVolts;
}


int16_t Cy_AutAnalog_SAR_CountsTo_degreeC(uint8_t sarIdx, uint8_t sarSequencer, uint8_t sarChannel,
                                       uint32_t VrefmV, int32_t sarCounts)
{
    uint32_t                    baseAddr;
    bool                        accEn;
    cy_en_autanalog_sar_acc_mode_t accMode;
    bool                        accShift;
    bool                        avgShiftMode16;
    uint32_t                    sarGain;

    int32_t                     temp = 0;

    CY_ASSERT_L2(AUTANALOG_SAR_SEQ_IDX(sarSequencer));
    CY_ASSERT_L2(AUTANALOG_SAR_CHANNEL(CY_AUTANALOG_SAR_INPUT_MUX, sarChannel));
    CY_ASSERT_L2(AUTANALOG_SAR_VREF_MAX(VrefmV));

    if (CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_SAR, sarIdx, &baseAddr))
    {
        /* Get AVG_EN parameter for SAR ADC sequencer */
        accEn = _FLD2BOOL(SAR_SEQ_LP_DATA_AVG_EN, AUTANALOG_SAR_SEQ_LP_DATA(baseAddr, sarSequencer));

        /* Get AVG_MODE parameter for SAR ADC channel */
        CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that conversion from uint32_t to enum does not have any negative drawbacks');
        accMode = _FLD2VAL(SAR_STA_CTRL_AVG_MODE, AUTANALOG_SAR_CTRL(baseAddr));

        /* Get SHIFT_MODE parameter for SAR ADC channel */
        avgShiftMode16 = _FLD2BOOL(SAR_STA_CTRL_SHIFT_MODE, AUTANALOG_SAR_CTRL(baseAddr));

        /* Averaging is not in use at all OR averaging with 12b result */
        if (!(accEn && (accMode != CY_AUTANALOG_SAR_ACC_DISABLED) && !avgShiftMode16))
        {
            /* Get AVG_SHIFT parameter for SAR ADC channel */
            accShift = _FLD2BOOL(SAR_STA_MUX_CHAN_CFG_AVG_SHIFT, AUTANALOG_SAR_MUX_CHAN_CFG(baseAddr, sarChannel));

            /* Averaging is configured but division is not done in HW */
            if (accEn && (accMode != CY_AUTANALOG_SAR_ACC_DISABLED) && !accShift)
            {
                /* Calculate average value */
                sarCounts = SAR_GetAverageTempCounts(baseAddr, sarSequencer, CY_AUTANALOG_SAR_INPUT_MUX, sarCounts);
            }

            /* Calculate gain for SAR ADC channel */
            sarGain = CY_SYSLIB_DIV_ROUND((uint32_t)AUTANALOG_SAR_MAX_BITS12 * AUTANALOG_SAR_10mV_COUNTS / 2UL, VrefmV);

            /* Calculate the Vref back from the gain */
            CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.8','Review shows that conversion from uint32_t to int32_t does not have any negative drawbacks');
            temp = (int32_t) CY_SYSLIB_DIV_ROUND((uint32_t)AUTANALOG_SAR_MAX_BITS12 * AUTANALOG_SAR_10mV_COUNTS / 2UL, sarGain);

            /* Correct the SAR ADC counts depending on the actual Vref */
            if (AUTANALOG_SAR_TEMP_VREF != temp)
            {
                temp *= sarCounts;
                temp /= AUTANALOG_SAR_TEMP_VREF;
            }
            else
            {
                temp = sarCounts;
            }

            /* Calculate die temperature based on SAR ACD counts */
            temp = SAR_CountsToDegreeC(temp);
        }
    }

    return (int16_t) temp;
}


cy_en_autanalog_status_t Cy_AutAnalog_FIFO_LoadConfig(uint8_t fifoIdx, const cy_stc_autanalog_fifo_cfg_t * fifoCfg)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_FIFO_BAD_PARAM;

    uint32_t baseAddr;
    uint32_t regVal;
    uint8_t cfgIdx;

    result = Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_FIFO, fifoIdx, &baseAddr);

    if ((CY_AUTANALOG_SUCCESS == result) && (NULL != fifoCfg))
    {
        /* Update CFG register */
        /* Validate enumerations for CFG register */
        CY_ASSERT_L3(AUTANALOG_MMIO_FIFO_CFG(fifoCfg->split));

        regVal = _VAL2FLD(LPPASS_MMIO_STA_CFG_SEL, fifoCfg->split);

        AUTANALOG_MMIO_FIFO_STA_CFG(baseAddr) = regVal;

        /* Update LEVEL[] registers */
        for (cfgIdx = 0; cfgIdx < CY_AUTANALOG_FIFO_BUFS_NUM; cfgIdx++)
        {
            /* Validate enumerations for LEVEL[] registers */
            CY_ASSERT_L3(AUTANALOG_MMIO_FIFO_LEVEL(fifoCfg->level[cfgIdx]));

            regVal = _VAL2FLD(LPPASS_MMIO_STA_LEVEL_LEVEL, fifoCfg->level[cfgIdx]);

            AUTANALOG_MMIO_FIFO_STA_LEVEL(baseAddr, cfgIdx) = regVal;
        }
    }
    else
    {
        result = CY_AUTANALOG_FIFO_BAD_PARAM;
    }

    return result;
}


uint16_t Cy_AutAnalog_FIFO_GetSize(uint8_t fifoIdx, uint8_t buffIdx)
{
    uint32_t baseAddr;

    CY_ASSERT_L2(AUTANALOG_MMIO_FIFO_BUFF_IDX(buffIdx));

    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_FIFO, fifoIdx, &baseAddr) ?
           (uint16_t)_FLD2VAL(LPPASS_MMIO_STA_USED_USED, AUTANALOG_MMIO_FIFO_STA_USED(baseAddr, buffIdx)) : 0U;
}


int32_t Cy_AutAnalog_FIFO_ReadWord(uint8_t fifoIdx, uint8_t buffIdx)
{
    uint32_t baseAddr;

    CY_ASSERT_L2(AUTANALOG_MMIO_FIFO_BUFF_IDX(buffIdx));

    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.8', 1, 'Review shows that type conversion from unsigned to signed does not have any negative drawbacks');
    return CY_AUTANALOG_SUCCESS == Cy_AutAnalog_IdxToBaseAddr(CY_AUTANALOG_FIFO, fifoIdx, &baseAddr) ?
           (int32_t)_FLD2VAL(LPPASS_MMIO_STA_RD_DATA_RESULT, AUTANALOG_MMIO_FIFO_STA_RD_DATA(baseAddr, buffIdx)) : 0;
    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.8');
}


uint16_t Cy_AutAnalog_FIFO_ReadData(uint8_t fifoIdx, uint8_t buffIdx, int32_t * data)
{
    uint16_t locSize = 0U;

    CY_ASSERT_L2(AUTANALOG_MMIO_FIFO_BUFF_IDX(buffIdx));

    if (NULL != data)
    {
        locSize = Cy_AutAnalog_FIFO_GetSize(fifoIdx, buffIdx);

        for (uint16_t idx = 0U; idx < locSize; idx++)
        {
            data[idx] = Cy_AutAnalog_FIFO_ReadWord(fifoIdx, buffIdx);
        }
    }

    return locSize;
}


uint16_t Cy_AutAnalog_FIFO_ReadDataChanId(uint8_t fifoIdx, uint8_t buffIdx, cy_en_autanalog_sar_input_t input, int32_t * data, uint8_t * chanID)
{
    uint16_t locSize = 0U;
    uint32_t locData = 0U;

    CY_ASSERT_L2(AUTANALOG_SAR_INPUT(input));

    if ((NULL != data) && (NULL != chanID))
    {
        locSize = Cy_AutAnalog_FIFO_GetSize(fifoIdx, buffIdx);

        for (uint16_t idx = 0U; idx < locSize; idx++)
        {
            CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.8', 1, 'Review shows that type conversion from signed to unsigned does not have any negative drawbacks');
            locData = (uint32_t)Cy_AutAnalog_FIFO_ReadWord(fifoIdx, buffIdx);
            CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.8');

            CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.3', 1, 'Review shows that type conversion from uint32_t to uint8_t does not have any negative drawbacks');
            chanID[idx] = (CY_AUTANALOG_SAR_INPUT_GPIO == input) ?
                          (locData & AUTANALOG_MMIO_FIFO_CH_ID_MASK_GPIO) >> AUTANALOG_MMIO_FIFO_CH_ID_POS_GPIO :
                          (locData & AUTANALOG_MMIO_FIFO_CH_ID_MASK_MUX)  >> AUTANALOG_MMIO_FIFO_CH_ID_POS_MUX;
            CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.3');

            CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.3', 2, 'Review shows that type conversion from uint16_t to int32_t does not have any negative drawbacks');
            data[idx] = ((locData & AUTANALOG_MMIO_FIFO_SIGN_MASK) == AUTANALOG_MMIO_FIFO_SIGN_MASK) ?
                        (int32_t)(int16_t)CY_LO16(locData) :
                        (int32_t)CY_LO16(locData);
            CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.3');
        }
    }

    return locSize;
}


static cy_en_autanalog_status_t SAR_LoadFIR(uint8_t sarIdx, uint8_t cfgNum, const cy_stc_autanalog_sar_fir_cfg_t * firCfg)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_SUCCESS;

    uint8_t cfgIdx;

    for (cfgIdx = 0; cfgIdx < cfgNum; cfgIdx++)
    {
        CY_ASSERT_L3(AUTANALOG_SAR_FIR_IDX(cfgIdx));

        if (CY_AUTANALOG_SUCCESS != Cy_AutAnalog_SAR_LoadFIRconfig(sarIdx, cfgIdx, &firCfg[cfgIdx]))
        {
            result = CY_AUTANALOG_SAR_BAD_PARAM;
            break;
        }
    }

    return result;
}


static void SAR_LoadGpioChan(uint32_t baseAddr, uint8_t cfgNum, cy_stc_autanalog_sar_hs_chan_t * const hsGpioChan[])
{
    uint32_t regVal;
    uint8_t cfgIdx;

    if (NULL != hsGpioChan)
    {
        for (cfgIdx = 0; cfgIdx < cfgNum; cfgIdx++)
        {
            CY_ASSERT_L3(AUTANALOG_SAR_CHANNEL(CY_AUTANALOG_SAR_INPUT_GPIO, cfgIdx));

            if (NULL != hsGpioChan[cfgIdx])
            {
                CY_ASSERT_L3(AUTANALOG_SAR_GPIO_PIN(hsGpioChan[cfgIdx]->posPin));
                CY_ASSERT_L3(AUTANALOG_SAR_CH_COEF(hsGpioChan[cfgIdx]->posCoeff));
                CY_ASSERT_L3(AUTANALOG_SAR_GPIO_PIN(hsGpioChan[cfgIdx]->negPin));
                CY_ASSERT_L3(AUTANALOG_SAR_CH_COEF(hsGpioChan[cfgIdx]->negCoeff));
                CY_ASSERT_L3(AUTANALOG_SAR_STATUS_SEL(hsGpioChan[cfgIdx]->hsLimit));
                CY_ASSERT_L3(AUTANALOG_MMIO_FIFO_SEL(hsGpioChan[cfgIdx]->fifoSel));

                regVal = _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_POS_PIN, hsGpioChan[cfgIdx]->posPin);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_HS_DIFFERENTIAL_EN, hsGpioChan[cfgIdx]->hsDiffEn);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_SIGNED, hsGpioChan[cfgIdx]->sign);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_POS_COEFF_SEL, hsGpioChan[cfgIdx]->posCoeff);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_NEG_PIN, hsGpioChan[cfgIdx]->negPin);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_AVG_SHIFT, hsGpioChan[cfgIdx]->accShift);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_NEG_COEFF_SEL, hsGpioChan[cfgIdx]->negCoeff);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_STATUS_SEL, hsGpioChan[cfgIdx]->hsLimit);
                regVal |= _VAL2FLD(SAR_STA_GPIO_CHAN_CFG_FIFO_SEL, hsGpioChan[cfgIdx]->fifoSel);

                AUTANALOG_SAR_GPIO_CHAN_CFG(baseAddr, cfgIdx) = regVal;
            }
        }
    }
}


static void SAR_LoadMuxChan(uint32_t baseAddr, uint8_t cfgNum, cy_stc_autanalog_sar_mux_chan_t * const intMuxChan[])
{
    uint32_t regVal;
    uint8_t cfgIdx;

    if (NULL != intMuxChan)
    {
        for (cfgIdx = 0; cfgIdx < cfgNum; cfgIdx++)
        {
            CY_ASSERT_L3(AUTANALOG_SAR_CHANNEL(CY_AUTANALOG_SAR_INPUT_MUX, cfgIdx));

            if (NULL != intMuxChan[cfgIdx])
            {
                CY_ASSERT_L3(AUTANALOG_SAR_MUX_PIN(intMuxChan[cfgIdx]->posPin));
                CY_ASSERT_L3(AUTANALOG_SAR_CH_COEF(intMuxChan[cfgIdx]->posCoeff));
                CY_ASSERT_L3(AUTANALOG_SAR_MUX_PIN(intMuxChan[cfgIdx]->negPin));
                CY_ASSERT_L3(AUTANALOG_SAR_CH_COEF(intMuxChan[cfgIdx]->negCoeff));
                CY_ASSERT_L3(AUTANALOG_SAR_STATUS_SEL(intMuxChan[cfgIdx]->muxLimit));
                CY_ASSERT_L3(AUTANALOG_MMIO_FIFO_SEL(intMuxChan[cfgIdx]->fifoSel));

                regVal = _VAL2FLD(SAR_STA_MUX_CHAN_CFG_POS_MUX_SEL, intMuxChan[cfgIdx]->posPin);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_SIGNED, intMuxChan[cfgIdx]->sign);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_POS_COEFF_SEL, intMuxChan[cfgIdx]->posCoeff);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_NEG_MUX_SEL, intMuxChan[cfgIdx]->negPin);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_BUF_BYPASS, intMuxChan[cfgIdx]->buffBypass);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_AVG_SHIFT, intMuxChan[cfgIdx]->accShift);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_NEG_COEFF_SEL, intMuxChan[cfgIdx]->negCoeff);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_STATUS_SEL, intMuxChan[cfgIdx]->muxLimit);
                regVal |= _VAL2FLD(SAR_STA_MUX_CHAN_CFG_FIFO_SEL, intMuxChan[cfgIdx]->fifoSel);

                AUTANALOG_SAR_MUX_CHAN_CFG(baseAddr, cfgIdx) = regVal;
            }
        }
    }
}


static void SAR_LoadRangeCond(uint32_t baseAddr, uint8_t cfgNum, cy_stc_autanalog_sar_limit_t * const limitCond[])
{
    uint32_t regVal;
    uint8_t cfgIdx;

    if (NULL != limitCond)
    {
        for (cfgIdx = 0; cfgIdx < cfgNum; cfgIdx++)
        {
            if (NULL != limitCond[cfgIdx])
            {
                CY_ASSERT_L3(AUTANALOG_SAR_STATUS_COND(limitCond[cfgIdx]->cond));

                regVal = _VAL2FLD(SAR_STA_STATUS_CFG_RANGE_COND, limitCond[cfgIdx]->cond);
                AUTANALOG_SAR_STATUS_CFG(baseAddr, cfgIdx) = regVal;

                regVal = (uint32_t)_VAL2FLD(SAR_STA_STATUS_RANGE_LOW_RANGE_LOW, limitCond[cfgIdx]->low);
                AUTANALOG_SAR_STATUS_RANGE_LOW(baseAddr, cfgIdx) = regVal;

                regVal = (uint32_t)_VAL2FLD(SAR_STA_STATUS_RANGE_HIGH_RANGE_HIGH, limitCond[cfgIdx]->high);
                AUTANALOG_SAR_STATUS_RANGE_HIGH(baseAddr, cfgIdx) = regVal;
            }
        }
    }
}


static int32_t SAR_CheckChanOffset(uint32_t baseAddr, cy_en_autanalog_sar_input_t sarInput, uint8_t sarChannel, bool sarMode16)
{
    int32_t offset;

    bool sign = false;
    bool diff = false;
    cy_en_autanalog_sar_pin_mux_t sarPinMinus = CY_AUTANALOG_SAR_PIN_MUX_VSSA_KELVIN;

    /* Reference voltage can be routed to negative pin of SAR ADC just for MUX channels */
    if (CY_AUTANALOG_SAR_INPUT_MUX == sarInput)
    {
        /* Get SIGN parameter for MUX channel */
        sign = _FLD2BOOL(SAR_STA_MUX_CHAN_CFG_SIGNED, AUTANALOG_SAR_MUX_CHAN_CFG(baseAddr, sarChannel));

        /* Get LP_DIFFERENTIAL_EN parameter for MUX channel */
        diff = _FLD2BOOL(SAR_STA_CTRL_LP_DIFFERENTIAL_EN, AUTANALOG_SAR_CTRL(baseAddr));

        /* Get NEG_MUX_SEL parameter for MUX channel */
        CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that conversion from uint32_t to enum does not have any negative drawbacks');
        sarPinMinus = _FLD2VAL(SAR_STA_MUX_CHAN_CFG_NEG_MUX_SEL, AUTANALOG_SAR_MUX_CHAN_CFG(baseAddr, sarChannel));
    }

    /* For signed single ended channels with Vref routed to negative pin of SAR ADC,
     * offset should be set to half of scale, depend on SAR ADC numeric resolution.
     * For unsigned differential channels, offset should be also set to half of scale but with negative sign,
     * depend on SAR ADC numeric resolution.
     * Pseudo differential conversion is calculated without usage offset.
     */
    if (sign && (!diff) && ((CY_AUTANALOG_SAR_PIN_MUX_VREF0 == sarPinMinus) || (CY_AUTANALOG_SAR_PIN_MUX_VREF1 == sarPinMinus)))
    {
        offset = sarMode16 ? AUTANALOG_SAR_OFFSET_BITS16 : AUTANALOG_SAR_OFFSET_BITS12;
    }
    else if (!sign && diff)
    {
        offset = sarMode16 ? -AUTANALOG_SAR_OFFSET_BITS16 : -AUTANALOG_SAR_OFFSET_BITS12;
    }
    else
    {
        offset = 0;
    }

    return offset;
}


static int32_t SAR_GetAverageVoltCounts(uint32_t baseAddr, uint8_t sarSequencer,
               cy_en_autanalog_sar_input_t sarInput, uint8_t sarChannel, int32_t sarCounts, bool * sarMode16)
{
    bool                           avgEn;
    cy_en_autanalog_sar_acc_mode_t avgMode;
    uint8_t                        avgCnt;
    bool                           avgShift;
    bool                           avgShiftMode16 = false;

    /* Get AVG_EN parameter for SAR ADC sequencer */
    avgEn = (sarInput == CY_AUTANALOG_SAR_INPUT_GPIO) ?
             _FLD2BOOL(SAR_SEQ_HS_DATA_AVG_EN, AUTANALOG_SAR_SEQ_HS_DATA(baseAddr, sarSequencer)):
             _FLD2BOOL(SAR_SEQ_LP_DATA_AVG_EN, AUTANALOG_SAR_SEQ_LP_DATA(baseAddr, sarSequencer));

    /* Get AVG_MODE parameter for SAR ADC channel */
    CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that conversion from uint32_t to enum does not have any negative drawbacks');
    avgMode = _FLD2VAL(SAR_STA_CTRL_AVG_MODE, AUTANALOG_SAR_CTRL(baseAddr));

    /* Check if average is enabled */
    if (avgEn && (avgMode != CY_AUTANALOG_SAR_ACC_DISABLED))
    {
        /* Get AVG_CNT parameter for SAR ADC sequencer */
        CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that conversion from uint32_t to uint8_t does not have any negative drawbacks');
        avgCnt = (sarInput == CY_AUTANALOG_SAR_INPUT_GPIO) ?
                  _FLD2VAL(SAR_SEQ_HS_DATA_AVG_CNT, AUTANALOG_SAR_SEQ_HS_DATA(baseAddr, sarSequencer)):
                  _FLD2VAL(SAR_SEQ_LP_DATA_AVG_CNT, AUTANALOG_SAR_SEQ_LP_DATA(baseAddr, sarSequencer));

        /* Get AVG_SHIFT parameter for SAR ADC channel */
        avgShift = (sarInput == CY_AUTANALOG_SAR_INPUT_GPIO) ?
                    _FLD2BOOL(SAR_STA_GPIO_CHAN_CFG_AVG_SHIFT, AUTANALOG_SAR_GPIO_CHAN_CFG(baseAddr, sarChannel)):
                    _FLD2BOOL(SAR_STA_MUX_CHAN_CFG_AVG_SHIFT, AUTANALOG_SAR_MUX_CHAN_CFG(baseAddr, sarChannel));

        /* Get SHIFT_MODE parameter for SAR ADC channel */
        avgShiftMode16 = _FLD2BOOL(SAR_STA_CTRL_SHIFT_MODE, AUTANALOG_SAR_CTRL(baseAddr));

        /* Averaging is configured but division is not done in HW */
        if (!avgShift)
        {
            /* Calculate average value */
            CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.8','Review shows that conversion from unsigned to signed does not have any negative drawbacks');
            sarCounts /= (int32_t)(1UL << (avgCnt + 1UL));
        }

        /* Counts value is within 12bits resolution */
        if (((sarCounts < 0) && (sarCounts > -4096)) || (((uint32_t)sarCounts <= 4095U)))
        {
            avgShiftMode16 = false;
        }
    }

    if (NULL != sarMode16)
    {
        *sarMode16 = avgShiftMode16;
    }

    return sarCounts;
}


static int32_t SAR_GetAverageTempCounts(uint32_t baseAddr, uint8_t sarSequencer,
                                        cy_en_autanalog_sar_input_t sarInput, int32_t sarCounts)
{
    uint8_t  avgCnt;
    uint16_t avgDivider;

    /* Get AVG_CNT parameter for SAR ADC sequencer */
    CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that conversion from uint32_t to uint8_t does not have any negative drawbacks');
    avgCnt = (sarInput == CY_AUTANALOG_SAR_INPUT_GPIO) ?
              _FLD2VAL(SAR_SEQ_HS_DATA_AVG_CNT, AUTANALOG_SAR_SEQ_HS_DATA(baseAddr, sarSequencer)):
              _FLD2VAL(SAR_SEQ_LP_DATA_AVG_CNT, AUTANALOG_SAR_SEQ_LP_DATA(baseAddr, sarSequencer));

    /* Calculate divider value */
    CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that conversion from uint32_t to uint16_t does not have any negative drawbacks');
    avgDivider = (uint16_t)(1UL << (avgCnt + 1UL));

    /* Averaged value */
    sarCounts /= (int32_t)avgDivider;

    return sarCounts;
}


static int32_t SAR_CountsToDegreeC(int32_t sarCounts)
{
    int32_t temp = sarCounts;

    /* Calculate tInitial in Q16.16 */
    temp = ((int16_t)AUTANALOG_SAR_TEMP_MULTIPLIER * temp) +
           ((int16_t)AUTANALOG_SAR_TEMP_OFFSET * AUTANALOG_SAR_TEMP_MULT);

    if (temp >= AUTANALOG_SAR_TEMP_CENT)
    {
        /* Shift (tHigh - tInitial) by 4 bits to prevent scale-adjustment from overflowing. */
        /* Then divide by the integer bits of (tHigh - tCent) to end up with a Q16.16 tAdjust */
        temp += (AUTANALOG_SAR_TEMP_SCALE_MULT * ((AUTANALOG_SAR_TEMP_HIGH - temp) / AUTANALOG_SAR_TEMP_SCALE_DIV)) /
               ((AUTANALOG_SAR_TEMP_HIGH - AUTANALOG_SAR_TEMP_CENT) / AUTANALOG_SAR_TEMP_DIV);
    }
    else
    {
        /* Shift (tLow + tInitial) by 4 bits to prevent scale-adjustment from overflowing. */
        /* Then divide by the integer bits of (tLow + tCent) to end up with a Q16.16 tAdjust */
        temp += (AUTANALOG_SAR_TEMP_SCALE_MULT * ((AUTANALOG_SAR_TEMP_LOW + temp) / AUTANALOG_SAR_TEMP_SCALE_DIV)) /
               ((AUTANALOG_SAR_TEMP_LOW + AUTANALOG_SAR_TEMP_CENT) / AUTANALOG_SAR_TEMP_DIV);
    }

    /* Add tInitial + tAdjust + 0.5 to round to nearest int. Shift off frac bits, and return. */
    temp = (temp + AUTANALOG_SAR_TEMP_HALF) / AUTANALOG_SAR_TEMP_DIV;

    return temp;
}

#endif /* CY_IP_MXS22LPPASS_SAR */

/* [] END OF FILE */
