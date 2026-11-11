/***************************************************************************//**
* \file cy_autanalog.c
* \version 1.0
*
* \brief
* Provides an API definition of the Autonomous Analog driver.
*
********************************************************************************
* \copyright
* Copyright 2022-2023 Cypress Semiconductor Corporation
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
#include "cy_autanalog.h"

#ifdef CY_IP_MXS22LPPASS

/* Helper macros for range validation */
#define AUTANALOG_PRB_IDX(value)                                    ((value) < CY_AUTANALOG_PRB_NUM)
/* Validation macros for CLOCK_DIV registers */
#define AUTANALOG_CLOCK_DIV_PRIO_HS_DEFAULT                         (19UL)
#define AUTANALOG_CLOCK_DIV(value)                                  ((value) <= INFRA_CLOCK_PTC_LP_DIV_DIV_VAL_Msk)
/* Validation macros for PRIO_CFG register */
#define AUTANALOG_PRIO_CFG_DEFAULT                                  (0UL)
/* Validation macros for LPOSC register */
#define AUTANALOG_LPOSC_CFG_DEFAULT                                 (0x80000000U) /* ENABLE, ALWAYS_ON */
/* Validation macros for AREF register */
#define AUTANALOG_AREF_CTRL_DEFAULT                                 (0UL)
#define AUTANALOG_AREF_CTRL(value)                                  ((value) <= CY_AUTANALOG_VREF_EXT)
/* Validation macros for PRB register */
#define AUTANALOG_PRB_VREF_CTRL_CFG(value)                          ((value) <= CY_AUTANALOG_PRB_VDDA)
#define AUTANALOG_PRB_VREF_CTRL_VAL(value)                          ((value) <= CY_AUTANALOG_PRB_TAP_15)

/* Validation macros for State Transition Table registers of AC */
#define AUTANALOG_STT_AC_CFG1_CNT(value)                             ((value) <= 0x0FFFUL)
#define AUTANALOG_STT_AC_CFG1_ACTION(value)                          ((value) <= CY_AUTANALOG_STT_AC_ACTION_BRANCH_IF_FALSE_CLR)
#define AUTANALOG_STT_AC_CFG1_COND(value)                            ((value) <= CY_AUTANALOG_STT_AC_CONDITION_DAC1_STROBE)
#define AUTANALOG_STT_AC_CFG1_BR_ADDR(value)                         ((value) < CY_AUTANALOG_STATE_TRANSITION_TABLE_STATES_NUM)
/* Validation macros for State Transition Table registers of CTB */
#define AUTANALOG_STT_CTB_CFG(value)                                 ((value) <  CY_AUTANALOG_CTB_DYN_CFG_MAX)
#define AUTANALOG_STT_CTB_GAIN(value)                                ((value) <= CY_AUTANALOG_STT_CTB_OA_GAIN_32_00)
/* Validation macros for State Transition Table registers of PTComp */
#define AUTANALOG_STT_PTCOMP_CFG(value)                              ((value) <  CY_AUTANALOG_PTCOMP_DYN_CFG_MAX)
/* Validation macros for State Transition Table registers of DAC */
#define AUTANALOG_STT_DAC_CHANNEL(value)                             ((value) <  CY_AUTANALOG_DAC_CH_CFG_NUM)
#define AUTANALOG_STT_DAC_DIRECTION(value)                           ((value) <= CY_AUTANALOG_DAC_DIRECTION_REVERSE)
/* Validation macros for State Transition Table registers of SAR */
#define AUTANALOG_STT_SAR_STATE(value)                               ((value) <= ACTRLR_TTCFG_TT_CFG3_SAR_ENTRY_ADDR_Msk)


/* Forward declarations */
static void Analog_UpdateTimerTable_AC(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState);
static void Analog_UpdateTimerTable_PRB(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState);
#ifdef CY_IP_MXS22LPPASS_CTB
static void Analog_UpdateTimerTable_CTB(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState);
#endif
#ifdef CY_IP_MXS22LPPASS_PTC
static void Analog_UpdateTimerTable_PTC(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState);
#endif
#ifdef CY_IP_MXS22LPPASS_DAC
static void Analog_UpdateTimerTable_DAC(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState);
#endif
#ifdef CY_IP_MXS22LPPASS_SAR
static void Analog_UpdateTimerTable_SAR(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState);
#endif


void Cy_AutAnalog_AdvPowerControl(bool sleepModeAC, bool lpOscDutyCycle)
{
    /* Update AC CFG register */
    CY_REG32_CLR_SET(AUTANALOG_AC_CFG(ACTRLR_BASE), ACTRLR_CFG_SLEEP_MODE, sleepModeAC);

    /* Update LPOSC CFG register */
    CY_REG32_CLR_SET(AUTANALOG_INFRA_LPOSC_CFG(INFRA_BASE), INFRA_LPOSC_CFG_MODE, lpOscDutyCycle);
}


void Cy_AutAnalog_Clear(void)
{
    /* Disables AC as a prerequisite to access other registers */
    AUTANALOG_AC_CTRL(ACTRLR_BASE) = _VAL2FLD(ACTRLR_CTRL_ENABLED, 0x0U);

    /* Clears the content of the FIFO (readout all the data) */
    cy_en_autanalog_fifo_split_t splitNum;
    uint8_t                      buffNum;
    uint16_t                     locSize;

    splitNum = (cy_en_autanalog_fifo_split_t)AUTANALOG_MMIO_FIFO_STA_CFG(LPPASS_MMIO_BASE);
    if (CY_AUTANALOG_FIFO_SPLIT1 == splitNum)
    {
        buffNum = 1U;
    }
    else if (CY_AUTANALOG_FIFO_SPLIT2 == splitNum)
    {
        buffNum = 2U;
    }
    else if (CY_AUTANALOG_FIFO_SPLIT4 == splitNum)
    {
        buffNum = 4U;
    }
    else if (CY_AUTANALOG_FIFO_SPLIT8 == splitNum)
    {
        buffNum = 8U;
    }
    else
    {
        /* Should not happens */
        buffNum = 0U;
    }

    for (uint8_t buffIdx = 0U; buffIdx < buffNum; buffIdx++)
    {
        /* One instance of the FIFO tied to the SAR ADC is currently supported */
        locSize = Cy_AutAnalog_FIFO_GetSize(0U, buffIdx);

        for (uint16_t idx = 0U; idx < locSize; idx++)
        {
            (void)Cy_AutAnalog_FIFO_ReadWord(0U, buffIdx);
        }
    }

    /* Clears the content of waveforms in LUT for the DAC */
    for (uint16_t sampleIdx = 0U; sampleIdx < CY_AUTANALOG_DAC_DATA_SAMPLES_NUM; sampleIdx++)
    {
        AUTANALOG_DAC_LUT(DAC0_BASE, sampleIdx) = 0x0UL;
        AUTANALOG_DAC_LUT(DAC1_BASE, sampleIdx) = 0x0UL;
    }

    /* Resets to default the MMIO registers, which contain the State Transition Table */
    for (uint8_t stateIdx = 0U; stateIdx < CY_AUTANALOG_STATE_TRANSITION_TABLE_STATES_NUM; stateIdx++)
    {
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, stateIdx) = 0x0UL;
        AUTANALOG_AC_TT_CFG1(ACTRLR_BASE, stateIdx) = 0x0UL;
        AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, stateIdx) = 0x0UL;
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, stateIdx) = 0x0UL;
        AUTANALOG_AC_TT_CFG4(ACTRLR_BASE, stateIdx) = 0x0UL;
    }
}


uint32_t Cy_AutAnalog_Init(const cy_stc_autanalog_t * cfgAndStates)
{
    CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that type conversion from enum to uint32_t does not have any negative drawbacks');
    uint32_t retVal = CY_AUTANALOG_BAD_PARAM;

    if (NULL != cfgAndStates)
    {
        /* Loads static and dynamic pairs of the configuration into the MMIO */
        retVal = Cy_AutAnalog_LoadConfig(cfgAndStates->configuration);

        CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.4','Review shows that comparison of enum with uint32_t does not have any negative drawbacks');
        if (CY_AUTANALOG_SUCCESS == retVal)
        {
            /* Loads the entire content of the State Transition Table into the MMIO */
            CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that assignment of enum to uint32_t does not have any negative drawbacks');
            retVal = Cy_AutAnalog_LoadStateTransitionTable(cfgAndStates->numSttEntries, cfgAndStates->stateTransitionTable);
        }
    }

    return retVal;
}


void Cy_AutAnalog_Disable(void)
{
    /* Updates the AC CTL register */
    AUTANALOG_AC_CTRL(ACTRLR_BASE) = _VAL2FLD(ACTRLR_CTRL_ENABLED, 0x0U);

    /* Updates the AC CFG register */
    CY_REG32_CLR_SET(AUTANALOG_AC_CFG(ACTRLR_BASE), ACTRLR_CFG_DISABLE_MODE, 0x1U);
}


void Cy_AutAnalog_Enable(void)
{
    /* Sets the AC CFG register */
    CY_REG32_CLR_SET(AUTANALOG_AC_CFG(ACTRLR_BASE), ACTRLR_CFG_DISABLE_MODE, 0x0U);

    /* Updates the AC CTRL register */
    AUTANALOG_AC_CTRL(ACTRLR_BASE) = _VAL2FLD(ACTRLR_CTRL_ENABLED, 0x1U);
}


uint32_t Cy_AutAnalog_LoadConfig(const cy_stc_autanalog_cfg_t * analogCfg)
{
    CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that type conversion from enum to uint32_t does not have any negative drawbacks');
    uint32_t retVal = CY_AUTANALOG_BAD_PARAM;

    if (NULL != analogCfg)
    {
        CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that type conversion from enum to uint32_t does not have any negative drawbacks');
        retVal = CY_AUTANALOG_ENABLE_ERR;

        uint8_t cfgIdx;
        uint32_t regVal;

        /* Enable IP block for further operation */
        Cy_AutAnalog_Enable();

        /* Delay for powering of the LPPASS, 10uS maximum */
        Cy_SysLib_DelayUs(10U);

        /* Get acknowledge for readiness of the LPPASS */
        regVal = _FLD2VAL(ACTRLR_PWR_STATUS_SW_OK, AUTANALOG_AC_PWR_STATUS(ACTRLR_BASE));
        if (regVal != 0U)
        {
            /* Delay for startup of IZTAT current reference, 200uS maximum */
            Cy_SysLib_DelayUs(200U);

            CY_MISRA_DEVIATE_LINE('MISRA C-2012 Rule 10.3','Review shows that type conversion from enum to uint32_t does not have any negative drawbacks');
            retVal = CY_AUTANALOG_SUCCESS;

            /* Update LPOSC register */
            AUTANALOG_INFRA_LPOSC_CFG(INFRA_BASE) = AUTANALOG_LPOSC_CFG_DEFAULT;

            /* Validate enumerations for CLOCK_PRIO_HS_DIV register */
            CY_ASSERT_L3(AUTANALOG_CLOCK_DIV(AUTANALOG_CLOCK_DIV_PRIO_HS_DEFAULT));
            /* Update CLOCK_PRIO_HS_DIV register */
            AUTANALOG_INFRA_CLOCK_PRIO_HS_DIV(INFRA_BASE) = AUTANALOG_CLOCK_DIV_PRIO_HS_DEFAULT;

            /* Update PRIO_CFG[] registers */
            for (cfgIdx = 0U; cfgIdx < CY_AUTANALOG_PRIORITY_ENABLER_NUM; cfgIdx++)
            {
                AUTANALOG_INFRA_PRIO_CFG(INFRA_BASE, cfgIdx) = AUTANALOG_PRIO_CFG_DEFAULT;
            }

            /* Update AREF register */
            AUTANALOG_INFRA_AREF_CTRL(INFRA_BASE) = AUTANALOG_AREF_CTRL_DEFAULT;

            /* Configure PRBs */
            if (NULL != analogCfg->prb)
            {
                for (cfgIdx = 0U; cfgIdx < CY_AUTANALOG_PRB_NUM; cfgIdx++)
                {
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.1', 1, 'Review shows that usage type enum as operand to the arithmetic operator OR does not have any negative drawbacks');
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.4', 1, 'Review shows that interpretation of type enum as uint32_t does not have any negative drawbacks');
                    retVal |= Cy_AutAnalog_PRB_LoadConfig(cfgIdx, analogCfg->prb);
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.4');
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.1');

                    /* Delay for start up VDDA or VBGR */
                    Cy_SysLib_DelayUs(analogCfg->prb->prb[cfgIdx]->src == CY_AUTANALOG_PRB_VDDA ? 150U : 100U);
                }
            }

            /* Configure CTBs */
#ifdef CY_IP_MXS22LPPASS_CTB
            for (cfgIdx = 0U; cfgIdx < PASS_NR_CTBLS; cfgIdx++)
            {
                if (NULL != analogCfg->ctb[cfgIdx])
                {
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.1', 1, 'Review shows that usage type enum as operand to the arithmetic operator OR does not have any negative drawbacks');
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.4', 1, 'Review shows that interpretation of type enum as uint32_t does not have any negative drawbacks');
                    retVal |= Cy_AutAnalog_CTB_LoadConfig(cfgIdx, analogCfg->ctb[cfgIdx]);
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.4');
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.1');

                    /* Start up delay for AREF, 10uS maximum */
                    Cy_SysLib_DelayUs(10U);
                }
            }
#endif

            /* Configure PTC */
#ifdef CY_IP_MXS22LPPASS_PTC
            for (cfgIdx = 0U; cfgIdx < PASS_NR_PTCS; cfgIdx++)
            {
                if (NULL != analogCfg->ptcomp[cfgIdx])
                {
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.1', 1, 'Review shows that usage type enum as operand to the arithmetic operator OR does not have any negative drawbacks');
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.4', 1, 'Review shows that interpretation of type enum as uint32_t does not have any negative drawbacks');
                    retVal |= Cy_AutAnalog_PTComp_LoadConfig(cfgIdx, analogCfg->ptcomp[cfgIdx]);
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.4');
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.1');

                    /* Start up delay for AREF, 10uS maximum */
                    Cy_SysLib_DelayUs(10U);
                }
            }
#endif

            /* Configure DACs */
#ifdef CY_IP_MXS22LPPASS_DAC
            for (cfgIdx = 0U; cfgIdx < PASS_NR_DACS; cfgIdx++)
            {
                if (NULL != analogCfg->dac[cfgIdx])
                {
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.1', 1, 'Review shows that usage type enum as operand to the arithmetic operator OR does not have any negative drawbacks');
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.4', 1, 'Review shows that interpretation of type enum as uint32_t does not have any negative drawbacks');
                    retVal |= Cy_AutAnalog_DAC_LoadConfig(cfgIdx, analogCfg->dac[cfgIdx]);
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.4');
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.1');

                    /* Start up delay for AREF, 10uS maximum */
                    Cy_SysLib_DelayUs(10U);
                }
            }
#endif

            /* Configure SAR */
#ifdef CY_IP_MXS22LPPASS_SAR
            for (cfgIdx = 0U; cfgIdx < PASS_NR_SARS; cfgIdx++)
            {
                if (NULL != analogCfg->sar[cfgIdx])
                {
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.1', 1, 'Review shows that usage type enum as operand to the arithmetic operator OR does not have any negative drawbacks');
                    CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.4', 1, 'Review shows that interpretation of type enum as uint32_t does not have any negative drawbacks');
                    retVal |= Cy_AutAnalog_SAR_LoadConfig(cfgIdx, analogCfg->sar[cfgIdx]);
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.4');
                    CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.1');

                    /* Start up delay for AREF, 10uS maximum */
                    Cy_SysLib_DelayUs(10U);
                }
            }
#endif

            /* Configure AC */
            CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.1', 1, 'Review shows that usage type enum as operand to the arithmetic operator OR does not have any negative drawbacks');
            CY_MISRA_DEVIATE_BLOCK_START('MISRA C-2012 Rule 10.4', 1, 'Review shows that interpretation of type enum as uint32_t does not have any negative drawbacks');
            retVal |= Cy_AutAnalog_AC_LoadConfig(analogCfg->ac);
            CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.4');
            CY_MISRA_BLOCK_END('MISRA C-2012 Rule 10.1');
        }
    }

    return retVal;
}


cy_en_autanalog_status_t Cy_AutAnalog_LoadStateTransitionTable(uint8_t numEntries, const cy_stc_autanalog_stt_t * stateTransitionTable)
{
    cy_en_autanalog_status_t retVal = CY_AUTANALOG_BAD_PARAM;

    if ((CY_AUTANALOG_STATE_TRANSITION_TABLE_STATES_NUM >= numEntries) && (NULL != stateTransitionTable))
    {
        uint8_t stateIdx;

        /* Resets to default the MMIO registers that contain the State Transition table */
        for (stateIdx = 0U; stateIdx < CY_AUTANALOG_STATE_TRANSITION_TABLE_STATES_NUM; stateIdx++)
        {
            AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, stateIdx) = 0x0UL;
            AUTANALOG_AC_TT_CFG1(ACTRLR_BASE, stateIdx) = 0x0UL;
            AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, stateIdx) = 0x0UL;
            AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, stateIdx) = 0x0UL;
            AUTANALOG_AC_TT_CFG4(ACTRLR_BASE, stateIdx) = 0x0UL;
        }

        /* Updates the MMIO registers that contain the State Transition table */
        retVal = Cy_AutAnalog_UpdateStateTransitionTable(numEntries, stateTransitionTable, 0U);
    }

    return retVal;
}


cy_en_autanalog_status_t Cy_AutAnalog_UpdateStateTransitionTable(uint8_t numEntries, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t startState)
{
    cy_en_autanalog_status_t retVal = CY_AUTANALOG_BAD_PARAM;

    /* Checks the valid ranges for the STT update */
    if ((numEntries > 0U) && (CY_AUTANALOG_STATE_TRANSITION_TABLE_STATES_NUM - startState >= numEntries) && (NULL != stateTransitionTable))
    {
        uint8_t stateIdx;

        for (stateIdx = 0U; stateIdx < numEntries; stateIdx++)
        {
            /* Updates the section of the STT related to the AC */
            Analog_UpdateTimerTable_AC(stateIdx, stateTransitionTable, startState);

            /* Updates the section of STT related to the PRB */
            Analog_UpdateTimerTable_PRB(stateIdx, stateTransitionTable, startState);

#ifdef CY_IP_MXS22LPPASS_CTB
            /* Updates the section of STT related to the CTB */
            Analog_UpdateTimerTable_CTB(stateIdx, stateTransitionTable, startState);
#endif

#ifdef CY_IP_MXS22LPPASS_PTC
            /* Updates the section of STT related to the PTComp */
            Analog_UpdateTimerTable_PTC(stateIdx, stateTransitionTable, startState);
#endif

#ifdef CY_IP_MXS22LPPASS_DAC
            /* Updates the section of STT related to the DAC */
            Analog_UpdateTimerTable_DAC(stateIdx, stateTransitionTable, startState);
#endif

#ifdef CY_IP_MXS22LPPASS_SAR
            /* Updates the section of STT related to the SAR ADC */
            Analog_UpdateTimerTable_SAR(stateIdx, stateTransitionTable, startState);
#endif
            startState++;
        }

        retVal = CY_AUTANALOG_SUCCESS;
    }

    return retVal;
}


cy_en_autanalog_status_t Cy_AutAnalog_PRB_LoadConfig(uint8_t prbIdx, const cy_stc_autanalog_prb_t * prbCfg)
{
    cy_en_autanalog_status_t result = CY_AUTANALOG_PRB_BAD_PARAM;
    uint32_t regVal;

    if ((CY_AUTANALOG_PRB_NUM > prbIdx) && (NULL != prbCfg) && (NULL != prbCfg->prb[prbIdx]))
    {
        /* Validate enumerations for PRB_VREF_CTRL register */
        CY_ASSERT_L1(AUTANALOG_PRB_VREF_CTRL_CFG(prbCfg->prb[prbIdx]->src));
        CY_ASSERT_L1(AUTANALOG_PRB_VREF_CTRL_VAL(prbCfg->prb[prbIdx]->tap));

        /* Define value for PRB_VREF_CTRL register */
        regVal = _VAL2FLD(INFRA_PRB_VREF_CTRL_CFG, prbCfg->prb[prbIdx]->src);
        regVal |= _VAL2FLD(INFRA_PRB_VREF_CTRL_VAL, prbCfg->prb[prbIdx]->tap);
        regVal |= _VAL2FLD(INFRA_PRB_VREF_CTRL_EN, prbCfg->prb[prbIdx]->enable);

        /* Update PRB_VREF_CTRL register */
        AUTANALOG_INFRA_PRB_VREF_CTRL(INFRA_BASE, prbIdx) = regVal;

        result = CY_AUTANALOG_SUCCESS;
    }

    return result;
}


void Cy_AutAnalog_PRB_Write(uint8_t prbIdx, cy_en_autanalog_prb_tap_t tap)
{
    uint32_t regVal;

    /* Validate enumerations for PRB_VREF_CTRL register */
    CY_ASSERT_L1(AUTANALOG_PRB_IDX(prbIdx));
    CY_ASSERT_L1(AUTANALOG_PRB_VREF_CTRL_VAL(tap));

    /* Sets the value for PRB_VREF_CTRL register */
    regVal = AUTANALOG_INFRA_PRB_VREF_CTRL(INFRA_BASE, prbIdx);
    regVal &= ~INFRA_PRB_VREF_CTRL_VAL_Msk;
    regVal |= _VAL2FLD(INFRA_PRB_VREF_CTRL_VAL, tap);

    /* Updates the PRB_VREF_CTRL register */
    AUTANALOG_INFRA_PRB_VREF_CTRL(INFRA_BASE, prbIdx) = regVal;
}


/*******************************************************************************
* Function Name: Analog_UpdateTimerTable_AC
****************************************************************************//**
*
* Used to update a particular state in the State Transition Table for the AC subsystem.
*
* \param stateIdx
* Defines the state in the State Transition Table to update the AC subsystem.
*
* \param stateTransitionTable
* Pointer to array containing new set of configuration data for State Transition Table,
* which must be updated.
*
*******************************************************************************/
static void Analog_UpdateTimerTable_AC(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState)
{
    if (NULL != stateTransitionTable[stateIdx].ac)
    {
        uint8_t devIdx;
        uint32_t regVal;

        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_DOUT_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_MODE_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_MODE_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_PRB_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_CTBL0_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_CTBL1_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_PTC_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_DAC0_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_DAC1_UNLOCK_Msk;
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG0_SAR_UNLOCK_Msk;

        CY_ASSERT_L3(AUTANALOG_STT_AC_CFG0_DOUT(stateTransitionTable[stateIdx].ac->gpioOut));

        regVal =
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_DOUT, stateTransitionTable[stateIdx].ac->gpioOut) |
                _BOOL2FLD(ACTRLR_TTCFG_TT_CFG0_MODE, stateTransitionTable[stateIdx].ac->lpMode) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_MODE_UNLOCK, stateTransitionTable[stateIdx].ac->unlock);
                if (NULL != stateTransitionTable[stateIdx].prb)
                {
                    regVal |= _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_PRB_UNLOCK, stateTransitionTable[stateIdx].prb->unlock);
                }
#ifdef CY_IP_MXS22LPPASS_CTB
                for (devIdx = 0U; devIdx < PASS_NR_CTBLS; devIdx++)
                {
                    if (NULL != stateTransitionTable[stateIdx].ctb[devIdx])
                    {
                        regVal |= (0U == devIdx) ?
                       _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_CTBL0_UNLOCK, stateTransitionTable[stateIdx].ctb[devIdx]->unlock) :
                       _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_CTBL1_UNLOCK, stateTransitionTable[stateIdx].ctb[devIdx]->unlock);
                    }
                }
#endif
#ifdef CY_IP_MXS22LPPASS_PTC
                if (NULL != stateTransitionTable[stateIdx].ptcomp[0U])
                {
                    regVal |= _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_PTC_UNLOCK, stateTransitionTable[stateIdx].ptcomp[0U]->unlock);
                }
#endif
#ifdef CY_IP_MXS22LPPASS_DAC
                for (devIdx = 0U; devIdx < PASS_NR_DACS; devIdx++)
                {
                    if (NULL != stateTransitionTable[stateIdx].dac[devIdx])
                    {
                        regVal |= (0U == devIdx) ?
                       _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_DAC0_UNLOCK, stateTransitionTable[stateIdx].dac[devIdx]->unlock) :
                       _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_DAC1_UNLOCK, stateTransitionTable[stateIdx].dac[devIdx]->unlock);
                    }
                }
#endif
#ifdef CY_IP_MXS22LPPASS_SAR
                if (NULL != stateTransitionTable[stateIdx].sar[0U])
                {
                    regVal |= _VAL2FLD(ACTRLR_TTCFG_TT_CFG0_SAR_UNLOCK, stateTransitionTable[stateIdx].sar[0U]->unlock);
                }
#endif
        AUTANALOG_AC_TT_CFG0(ACTRLR_BASE, targetState) |= regVal;

        /* AUTANALOG_AC_TT_CFG1 */
        CY_ASSERT_L3(AUTANALOG_STT_AC_CFG1_CNT(stateTransitionTable[stateIdx].ac->count));
        CY_ASSERT_L3(AUTANALOG_STT_AC_CFG1_ACTION(stateTransitionTable[stateIdx].ac->action));
        CY_ASSERT_L3(AUTANALOG_STT_AC_CFG1_COND(stateTransitionTable[stateIdx].ac->condition));
        CY_ASSERT_L3(AUTANALOG_STT_AC_CFG1_BR_ADDR(stateTransitionTable[stateIdx].ac->branchState));

        regVal =
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG1_CNT, stateTransitionTable[stateIdx].ac->count) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG1_ACTION, stateTransitionTable[stateIdx].ac->action) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG1_COND, stateTransitionTable[stateIdx].ac->condition) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG1_BR_ADDR, stateTransitionTable[stateIdx].ac->branchState) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG1_INTR_SET, stateTransitionTable[stateIdx].ac->trigInt);

        AUTANALOG_AC_TT_CFG1(ACTRLR_BASE, targetState) = regVal;
    }
}


/*******************************************************************************
* Function Name: Analog_UpdateTimerTable_PRB
****************************************************************************//**
*
* Used to update a particular state in the State Transition Table for the PRB subsystem.
*
* \param stateIdx
* Defines the state in the State Transition Table to update the PRB subsystem.
*
* \param stateTransitionTable
* Pointer to array containing new set of configuration data for State Transition Table,
* which must be updated.
*
*******************************************************************************/
static void Analog_UpdateTimerTable_PRB(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState)
{
    if (NULL != stateTransitionTable[stateIdx].prb)
    {
        uint32_t regVal;

        /* AUTANALOG_AC_TT_CFG4 */
        CY_ASSERT_L3(AUTANALOG_PRB_VREF_CTRL_VAL(stateTransitionTable[stateIdx].prb->prbVref0Tap));
        CY_ASSERT_L3(AUTANALOG_PRB_VREF_CTRL_VAL(stateTransitionTable[stateIdx].prb->prbVref1Tap));

        regVal =
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG4_PRB_VREF0_FW_MODE, stateTransitionTable[stateIdx].prb->prbVref0Fw) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG4_PRB_VREF0_VAL, stateTransitionTable[stateIdx].prb->prbVref0Tap) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG4_PRB_VREF1_FW_MODE, stateTransitionTable[stateIdx].prb->prbVref1Fw) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG4_PRB_VREF1_VAL, stateTransitionTable[stateIdx].prb->prbVref1Tap);

        AUTANALOG_AC_TT_CFG4(ACTRLR_BASE, targetState) = regVal;
    }
}


#ifdef CY_IP_MXS22LPPASS_CTB /* Two instances of the CTB are currently supported */
/*******************************************************************************
* Function Name: Analog_UpdateTimerTable_CTB
****************************************************************************//**
*
* Used to update a particular state in the State Transition Table for the CTB subsystem.
*
* \param stateIdx
* Defines the state in the State Transition Table for update of the CTB subsystem.
*
* \param stateTransitionTable
* Pointer to array containing new set of configuration data for State Transition Table,
* which must be updated.
*
*******************************************************************************/
static void Analog_UpdateTimerTable_CTB(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState)
{
    uint8_t devIdx;
    uint32_t regVal;

    for (devIdx = 0U; devIdx < PASS_NR_CTBLS; devIdx++)
    {
        if (NULL != stateTransitionTable[stateIdx].ctb[devIdx])
        {
            /* AUTANALOG_AC_TT_CFG2 */
            CY_ASSERT_L3(AUTANALOG_STT_CTB_CFG(stateTransitionTable[stateIdx].ctb[devIdx]->cfgOpamp0));
            CY_ASSERT_L3(AUTANALOG_STT_CTB_GAIN(stateTransitionTable[stateIdx].ctb[devIdx]->gainOpamp0));
            CY_ASSERT_L3(AUTANALOG_STT_CTB_CFG(stateTransitionTable[stateIdx].ctb[devIdx]->cfgOpamp1));
            CY_ASSERT_L3(AUTANALOG_STT_CTB_GAIN(stateTransitionTable[stateIdx].ctb[devIdx]->gainOpamp1));

            if (0U == devIdx)
            {
                /* CTBL0 */
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL0_OA0_EN_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL0_OA0_CFG_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL0_OA0_GAIN_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL0_OA1_EN_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL0_OA1_CFG_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL0_OA1_GAIN_Msk;
            }
            else
            {
                /* CTBL1 */
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL1_OA0_EN_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL1_OA0_CFG_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL1_OA0_GAIN_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL1_OA1_EN_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL1_OA1_CFG_Msk;
                AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG2_CTBL1_OA1_GAIN_Msk;
            }

            regVal = (0U == devIdx) ?
                    /* CTBL0 */
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL0_OA0_EN, stateTransitionTable[stateIdx].ctb[devIdx]->enableOpamp0) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL0_OA0_CFG, stateTransitionTable[stateIdx].ctb[devIdx]->cfgOpamp0) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL0_OA0_GAIN, stateTransitionTable[stateIdx].ctb[devIdx]->gainOpamp0) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL0_OA1_EN, stateTransitionTable[stateIdx].ctb[devIdx]->enableOpamp1) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL0_OA1_CFG, stateTransitionTable[stateIdx].ctb[devIdx]->cfgOpamp1) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL0_OA1_GAIN, stateTransitionTable[stateIdx].ctb[devIdx]->gainOpamp1):
                    /* CTBL1 */
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL1_OA0_EN, stateTransitionTable[stateIdx].ctb[devIdx]->enableOpamp0) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL1_OA0_CFG, stateTransitionTable[stateIdx].ctb[devIdx]->cfgOpamp0) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL1_OA0_GAIN, stateTransitionTable[stateIdx].ctb[devIdx]->gainOpamp0) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL1_OA1_EN, stateTransitionTable[stateIdx].ctb[devIdx]->enableOpamp1) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL1_OA1_CFG, stateTransitionTable[stateIdx].ctb[devIdx]->cfgOpamp1) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG2_CTBL1_OA1_GAIN, stateTransitionTable[stateIdx].ctb[devIdx]->gainOpamp1);

            AUTANALOG_AC_TT_CFG2(ACTRLR_BASE, targetState) |= regVal;
        }
    }
}
#endif


#ifdef CY_IP_MXS22LPPASS_PTC /* One instance of the PTComp is currently supported */
/*******************************************************************************
* Function Name: Analog_UpdateTimerTable_PTC
****************************************************************************//**
*
* Used to update a particular state in the State Transition Table for the PTComp subsystem.
*
* \param stateIdx
* Defines the state in the State Transition Table to update the PTComp subsystem.
*
* \param stateTransitionTable
* Pointer to array containing new set of configuration data for State Transition Table,
* which must be updated.
*
*******************************************************************************/
static void Analog_UpdateTimerTable_PTC(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState)
{
    uint32_t regVal;

    if (NULL != stateTransitionTable[stateIdx].ptcomp[0U])
    {
        /* AUTANALOG_AC_TT_CFG3 */
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_PTC_CMP0_EN_Msk;
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_PTC_CMP0_CFG_Msk;
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_PTC_CMP1_EN_Msk;
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_PTC_CMP1_CFG_Msk;

        CY_ASSERT_L3(AUTANALOG_STT_PTCOMP_CFG(stateTransitionTable[stateIdx].ptcomp[0U]->dynCfgIdxComp0));
        CY_ASSERT_L3(AUTANALOG_STT_PTCOMP_CFG(stateTransitionTable[stateIdx].ptcomp[0U]->dynCfgIdxComp1));

        regVal =
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_PTC_CMP0_EN, stateTransitionTable[stateIdx].ptcomp[0U]->enableComp0) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_PTC_CMP0_CFG, stateTransitionTable[stateIdx].ptcomp[0U]->dynCfgIdxComp0) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_PTC_CMP1_EN, stateTransitionTable[stateIdx].ptcomp[0U]->enableComp1) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_PTC_CMP1_CFG, stateTransitionTable[stateIdx].ptcomp[0U]->dynCfgIdxComp1);

         AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) |= regVal;
    }
}
#endif


#ifdef CY_IP_MXS22LPPASS_DAC /* Two instances of the DAC are currently supported */
/*******************************************************************************
* Function Name: Analog_UpdateTimerTable_DAC
****************************************************************************//**
*
* Used to update a particular state in the State Transition Table for the DAC subsystem.
*
* \param stateIdx
* Defines the state in the State Transition Table for update of the DAC subsystem.
*
* \param stateTransitionTable
* Pointer to array containing new set of configuration data for State Transition Table,
* which must be updated.
*
*******************************************************************************/
static void Analog_UpdateTimerTable_DAC(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState)
{
    uint8_t devIdx;
    uint32_t regVal;
    uint32_t direction;

    for (devIdx = 0U; devIdx < PASS_NR_DACS; devIdx++)
    {
        if (NULL != stateTransitionTable[stateIdx].dac[devIdx])
        {
            /* AUTANALOG_AC_TT_CFG3 */
            CY_ASSERT_L3(AUTANALOG_STT_DAC_CHANNEL(stateTransitionTable[stateIdx].dac[devIdx]->channel));
            CY_ASSERT_L3(AUTANALOG_STT_DAC_DIRECTION(stateTransitionTable[stateIdx].dac[devIdx]->direction));

            if (0U == devIdx)
            {
                /* DAC0 */
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC0_EN_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC0_CHANNEL_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC0_INC_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC0_DEC_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC0_TR_Msk;
            }
            else
            {
                /* DAC1 */
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC1_EN_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC1_CHANNEL_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC1_INC_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC1_DEC_Msk;
                AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_DAC1_TR_Msk;
            }

            direction = (0U == devIdx) ?
                    /* DAC0 */
                    (stateTransitionTable[stateIdx].dac[devIdx]->direction == CY_AUTANALOG_DAC_DIRECTION_FORWARD ?
                        ACTRLR_TTCFG_TT_CFG3_DAC0_INC_Msk:
                        ACTRLR_TTCFG_TT_CFG3_DAC0_DEC_Msk):
                    /* DAC1 */
                    (stateTransitionTable[stateIdx].dac[devIdx]->direction == CY_AUTANALOG_DAC_DIRECTION_FORWARD ?
                        ACTRLR_TTCFG_TT_CFG3_DAC1_INC_Msk:
                        ACTRLR_TTCFG_TT_CFG3_DAC1_DEC_Msk);

            regVal = (0U == devIdx) ?
                    /* DAC0 */
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_DAC0_EN, stateTransitionTable[stateIdx].dac[devIdx]->enable) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_DAC0_CHANNEL, stateTransitionTable[stateIdx].dac[devIdx]->channel) |
                    direction |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_DAC0_TR, stateTransitionTable[stateIdx].dac[devIdx]->trigger):
                    /* DAC1 */
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_DAC1_EN, stateTransitionTable[stateIdx].dac[devIdx]->enable) |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_DAC1_CHANNEL, stateTransitionTable[stateIdx].dac[devIdx]->channel) |
                    direction |
                    _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_DAC1_TR, stateTransitionTable[stateIdx].dac[devIdx]->trigger);

            AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) |= regVal;
        }
    }
}
#endif


#ifdef CY_IP_MXS22LPPASS_SAR  /* One instance of the SAR is currently supported */
/*******************************************************************************
* Function Name: Analog_UpdateTimerTable_SAR
****************************************************************************//**
*
* Used to update a particular state in the State Transition Table for the SAR subsystem.
*
* \param stateIdx
* Defines the state in the State Transition Table to update the SAR subsystem.
*
* \param stateTransitionTable
* Pointer to array containing new set of configuration data for State Transition Table,
* which must be updated.
*
*******************************************************************************/
static void Analog_UpdateTimerTable_SAR(uint8_t stateIdx, const cy_stc_autanalog_stt_t * stateTransitionTable, uint8_t targetState)
{
    uint32_t regVal;

    if (NULL != stateTransitionTable[stateIdx].sar[0U])
    {
        /* AUTANALOG_AC_TT_CFG3 */
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_SAR_ENTRY_ADDR_Msk;
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_SAR_TR_Msk;
        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) &= ~ACTRLR_TTCFG_TT_CFG3_SAR_EN_Msk;

        CY_ASSERT_L3(AUTANALOG_STT_SAR_STATE(stateTransitionTable[stateIdx].sar[0U]->entryState));

        regVal =
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_SAR_ENTRY_ADDR, stateTransitionTable[stateIdx].sar[0U]->entryState) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_SAR_TR, stateTransitionTable[stateIdx].sar[0U]->trigger) |
                _VAL2FLD(ACTRLR_TTCFG_TT_CFG3_SAR_EN, stateTransitionTable[stateIdx].sar[0U]->enable);

        AUTANALOG_AC_TT_CFG3(ACTRLR_BASE, targetState) |= regVal;
    }
}
#endif

#endif /* CY_IP_MXS22LPPASS */

/* [] END OF FILE */
