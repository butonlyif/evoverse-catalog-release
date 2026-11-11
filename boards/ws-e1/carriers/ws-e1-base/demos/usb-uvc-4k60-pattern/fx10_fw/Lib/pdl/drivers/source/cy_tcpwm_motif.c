/***************************************************************************//**
* \file cy_tcpwm_motif.c
* \version 1.60
*
* \brief
*  The source file of the tcpwm motif driver.
*
********************************************************************************
* \copyright
* Copyright 2023 Cypress Semiconductor Corporation
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

#include "cy_tcpwm_motif.h"

#ifdef CY_IP_MXTCPWM

#if (CY_IP_MXTCPWM_VERSION >= 3U)
#if defined(__cplusplus)
extern "C" {
#endif


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Hall_Sensor_Init
***************************************************************************//**
*
* MOTIF module initialization in Hall sensor Mode
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param config Hall sensor configuration \ref cy_stc_tcpwm_motif_hall_sensor_config_t
*
* return Returns the status of the operation.
*
* 
*******************************************************************************/
cy_en_tcpwm_status_t Cy_TCPWM_MOTIF_Hall_Sensor_Init(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_tcpwm_motif_hall_sensor_config_t const *config)
{
    cy_en_tcpwm_status_t status = CY_TCPWM_BAD_PARAM;
    /* The Hall Sensor mode is divided in three major loops: 
     * detection of an update in the Hall inputs,
     * delay between the detection and the sampling of the Hall inputs for comparison against the expected
     * Hall Pattern and the update of the Multi-Channel pattern. */

    if ((NULL != base) && (NULL != config))
    {
        TCPWM_MOTIF_HMEC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HMEC_HDBP, config->debounce_bypass) |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HMEC_HDBP, config->pp_compare));
        TCPWM_MOTIF_MCMEC(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMEC_MSBP, config->sync_bypass) |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMEC_MFCE, config->fault_clear) |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMEC_MEBP, config->delay_bypass));
        if(config->output_config != NULL)
        {

            TCPWM_MOTIF_HOSC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_EDN,  config->output_config->edge_detect_event_config)        |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_CHN,  config->output_config->correct_hall_event_config)       |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_IDN,  config->output_config->idle_wrong_hall_event_config)    |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_HSTN, config->output_config->start_event_config)              |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_SPN,  config->output_config->pattern_mismatch_event_config)   |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_CPN,  config->output_config->curr_pattern_match_event_config) |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_PPN,  config->output_config->prev_pattern_match_event_config));
        }
        /* Each MOTIF module contains two LUT's(Look Up Tables). Hall LUT (HLUT, also called "input LUT") and Modulation LUT (MLUT, also called  "output LUT").
         HLUT contains Hall input pattern which gets loaded to HALP registers.
         MLUT contains output PWM modulation pattern which gets loaded to MCM.MCMP register.
         HLUT is 3x6 bits. MLUT is 32x6 bits
         */
        if (config->lut_enable)
        {
            TCPWM_MOTIF_CLUT(base) &= ~TCPWM_MOTIF_GRP_MOTIF_CLUT_LUTEN_Msk;
            TCPWM_MOTIF_CLUT(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_CLUT_LUTEN, config->lut_enable));
            
            if (NULL != config->hlut_config)
            {
                TCPWM_MOTIF_HALPS(base)   = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HCPS0, config->hlut_config->hlut_data_pos0) |
                                             _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HEPS1, config->hlut_config->hlut_data_pos1) |
                                             _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HPPS2, config->hlut_config->hlut_data_pos2) |
                                             _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HLUT3, config->hlut_config->hlut_data_pos3) |
                                             _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HLUT4, config->hlut_config->hlut_data_pos4) |
                                             _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HLUT5, config->hlut_config->hlut_data_pos5));
            }
            if (NULL != config->mlut_config)
            {
                TCPWM_MOTIF_MCSM(base)   = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, config->mlut_config->mlut_data_pos0));
                TCPWM_MOTIF_MCSM1(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, config->mlut_config->mlut_data_pos1));
                TCPWM_MOTIF_MCSM2(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, config->mlut_config->mlut_data_pos2));
                TCPWM_MOTIF_MCSM3(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, config->mlut_config->mlut_data_pos3));
                TCPWM_MOTIF_MCSM4(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, config->mlut_config->mlut_data_pos4));
                TCPWM_MOTIF_MCSM5(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, config->mlut_config->mlut_data_pos5));
            }
        }
        TCPWM_MOTIF_PCONF(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_FSEL, CY_MOTIF_HALL_SENSOR_MODE) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_SPES, config->edge_for_sampling_trigger) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_LPC, config->low_pass_filter_config) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MSES, config->edge_for_mset_trigger) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MSYES, config->edge_for_msync_trigger) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MCUE, config->mcp_mode) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_EWIE, config->external_wrong_hall_event_enable) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_EWIL, config->external_wrong_hall_event_active_level) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_FTS, config->fault_event_selection) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_CHEC, config->correct_event_selection) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE, 1U));
        
    /* The Hall inputs are directly connected to an edge detection circuitry and with any modification in any of these three inputs, an event is generated.
       This event can be connected to one TCPWM counter via trigger multiplexer that is controlling the delay between the edge detection and the next step on the Hall sensor mode, the sampling of the Hall Inputs.
     */
    
        status = CY_TCPWM_SUCCESS;
    }
    return(status);
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_DeInit
***************************************************************************//**
*
* De initializes MOTIF block. 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_DeInit(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    TCPWM_MOTIF_PCONF(base) &= ~TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE_Msk;
    TCPWM_MOTIF_PCONF(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE, 0U));
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Enable
***************************************************************************//**
*
* Enables the MOTIF module. Modulation output from motif is started with it's default values
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Enable(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    TCPWM_MOTIF_PCONF(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE, 1U));
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Disable
***************************************************************************//**
*
* Disables the MOTIF Module. Modulation output from motif is reset to it's default value
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Disable(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    TCPWM_MOTIF_PCONF(base) &= ~TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE_Msk;
    TCPWM_MOTIF_PCONF(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE, 0U));
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Start
***************************************************************************//**
*
*  Modulation output from motif is started with existing values
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Start(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    TCPWM_MOTIF_PRUNS(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PRUNS_SRB, 1U));
}


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Stop
***************************************************************************//**
*
*  Modulation output from motif retains the existing values and MOTIF functionality Stops.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Stop(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    /* Output events gets reset to default value,
     *Interrupt output get reset to default value and modulation output keep the existing value
     */
    TCPWM_MOTIF_PRUNS(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PRUNS_SRB, 0U));
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Suspend
***************************************************************************//**
*
* Configures the entering in suspend for the MOTIF module.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param suspend_config
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Suspend(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_en_motif_suspend_config_t suspend_config)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_PSUS(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PSUS_SUS, suspend_config));
    }
    
}


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_HALL_Output_Config
***************************************************************************//**
*
* Configures the output pins for each of the hall event.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param output_config HALL Output Configuration \ref cy_stc_hall_output_config_t
*
* \note User to make sure that no two event s are routed to same node.
******************************************************************************/
void Cy_TCPWM_MOTIF_HALL_Output_Config(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_hall_output_config_t *output_config)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_HOSC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_EDN,  output_config->edge_detect_event_config)        |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_CHN,  output_config->correct_hall_event_config)       |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_IDN,  output_config->idle_wrong_hall_event_config)    |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_HSTN, output_config->start_event_config)              |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_SPN,  output_config->pattern_mismatch_event_config)   |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_CPN,  output_config->curr_pattern_match_event_config) |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HOSC_PPN,  output_config->prev_pattern_match_event_config));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Configure_Debounce_Bypass
***************************************************************************//**
*
* Enable/Disable HALL Sensor debounce stage bypass 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param bypass_sd Passing true will disable HALL Sensor sample delay. hall inputs are immediately sample after the low pass filter with out delay.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Configure_Debounce_Bypass(TCPWM_MOTIF_GRP_MOTIF_Type *base, bool bypass_sd)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_HMEC(base)  &= ~TCPWM_MOTIF_GRP_MOTIF_HMEC_HDBP_Msk;
        TCPWM_MOTIF_HMEC(base)  |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HMEC_HDBP, bypass_sd));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_HALL_Previous_Pattern_Compare
***************************************************************************//**
*
* Enable/Disable HALL Previous Pattern compare 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param pp_compare Previous Pattern Compare enable or disable
*
* \note Passing true will enables the compare logic between the sampled hall input values and the previous hall pattern. 
*   HALP.HPP will hold the previous pattern. 
*   This will be used together with the comparison of the current and expected pattern to generate a wrong hall event.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_HALL_Previous_Pattern_Compare(TCPWM_MOTIF_GRP_MOTIF_Type *base, bool pp_compare)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_HMEC(base)  &= ~TCPWM_MOTIF_GRP_MOTIF_HMEC_HPPE_Msk;
        TCPWM_MOTIF_HMEC(base)  |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HMEC_HPPE, pp_compare));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Hall_Input_Sample_Trigger
***************************************************************************//**
*
* The application software can issue/request a sample of the Hall Inputs
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Hall_Input_Sample_Trigger(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_HIST(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HIST_HIS, 1U));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Update_Hall_Pattern
***************************************************************************//**
*
* Update Hall pattern immediately.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* \note The update of the fields HALP.HCP, HALP.HEP and HALP.HPP can come from software by calling this function.
******************************************************************************/
void Cy_TCPWM_MOTIF_Update_Hall_Pattern(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMS(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMS_STHR, 1U));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Set_HALL_Pattern
***************************************************************************//**
*
* Sets the Hall patterns: Current, Expected and Previous patterns
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param current_pattern Current Pattern 
*
* param expected_pattern Expected Pattern 
*
* param previous_pattern Previous Pattern 
* 
* \note When the sampling trigger is sensed, the Hall inputs are stored and compared against the Current Pattern, HALP.HCP,
*   the Expected Hall Pattern, HALP.HEP and the Previous Pattern HALP.HPP (the Previous Pattern comparison can be disabled)
*
******************************************************************************/  
 void Cy_TCPWM_MOTIF_Set_HALL_Pattern(TCPWM_MOTIF_GRP_MOTIF_Type *base, uint8_t current_pattern, uint8_t expected_pattern, uint8_t previous_pattern)
 {
     if (NULL != base)
    {
        TCPWM_MOTIF_HALPS(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HCPS0, current_pattern) |
                                    _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HEPS1, expected_pattern)|
                                    _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HPPS2, previous_pattern)); 
    }
 }

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Set_LUT_Mode
***************************************************************************//**
*
* Enables/disables LUT mode.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param lut_enable LUT mode enable disable
*
* \note HALL Sensor works in LUT mode enabled and disabled. When LUT mode is enabled user provides look up table values
*   and they will be compared with the actual output values. When motor changes direction, MOTIF is stopped and 
*   user need to populate the LUT again. 
* \note This function is used to enable disable LUT mode. Sam function for both HALL Sensor mode and Multi channel pattern mode
******************************************************************************/  
void Cy_TCPWM_MOTIF_Set_LUT_Mode(TCPWM_MOTIF_GRP_MOTIF_Type *base, bool lut_enable)
{
    /* Each MOTIF module contains two LUT's(Look Up Tables). Hall LUT (HLUT, also called "input LUT") and Modulation LUT (MLUT, also called "output LUT").
       HLUT contains Hall input pattern which gets loaded to HALP registers.
       MLUT contains output PWM modulation pattern which gets loaded to MCM.MCMP register.
       HLUT is 3x6 bits. MLUT is 32x6 bits
     */
    if (NULL != base)
    {
        TCPWM_MOTIF_CLUT(base) &= ~TCPWM_MOTIF_GRP_MOTIF_CLUT_LUTEN_Msk;
        TCPWM_MOTIF_CLUT(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_CLUT_LUTEN, lut_enable));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Get_LUT_Status
***************************************************************************//**
*
* Returns a value that points to the corresponding input Hall LUT values set
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* return value that points to the corresponding input Hall LUT values set
*
* \note If LUT mode is not enabled this function returns always 0.
*  In Lut mode the Valid values that this function return are 0,1,2,3,4,5. Each value points to the corresponding input Hall LUT values set. 
*  Invalid values are 6,7
******************************************************************************/ 
uint8_t Cy_TCPWM_MOTIF_Get_LUT_Status(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    uint8_t lut_status = 0U;
    if (NULL != base)
    {
        lut_status =(uint8_t)(_FLD2VAL(TCPWM_MOTIF_GRP_MOTIF_SLUT_PTR, TCPWM_MOTIF_SLUT(base)));
    }
    return lut_status;
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Update_HLUT
***************************************************************************//**
*
* Update look up table contents for Hall Sensor in LUT mode.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param hlut_config HALL Look Up Table Configuration \ref cy_stc_tcpwm_motif_hlut_t
*
* \note Update look up table contents for Hall Sensor in LUT mode.
*   User writes HLUT and MLUT when MOTIF is stopped.
*   Writing into both LUT while MOTIF is started might lead to incorrect behavior.
*   The LUT is loaded with forward or reverse pattern depending on motor desired direction.
*   The pattern is stored in LUT independently from motor position.
*   The hardware is responsible to find out the current motor position and to load the right hall and modulation pattern.
*   HLUT and MLUT share the same hardware pointer for data extraction, therefore user needs to take care of keeping them aligned with respect to LUT address.
*   A wrong programming might lead to incorrect behavior. 
******************************************************************************/
void Cy_TCPWM_MOTIF_Update_HLUT(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_tcpwm_motif_hlut_t *hlut_config)
{
    if ((NULL != base) && (NULL != hlut_config))
    {
        TCPWM_MOTIF_HALPS(base)   = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HCPS0, hlut_config->hlut_data_pos0) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HEPS1, hlut_config->hlut_data_pos1) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HPPS2, hlut_config->hlut_data_pos2) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HLUT3, hlut_config->hlut_data_pos3) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HLUT4, hlut_config->hlut_data_pos4) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_HALPS_HLUT5, hlut_config->hlut_data_pos5));
    }
    
}


/***** Multi Channel Pattern Mode *****/


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_Init
***************************************************************************//**
*
* MOTIF module initialization in Multi Channel Pattern Mode
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param mcp_config Multi Channel Pattern configuration \ref cy_stc_tcpwm_motif_mcp_config_t
*
* return Returns the status of the operation.
*
*
******************************************************************************/
cy_en_tcpwm_status_t Cy_TCPWM_MOTIF_MCP_Init(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_tcpwm_motif_mcp_config_t const *mcp_config)
{
    cy_en_tcpwm_status_t status = CY_TCPWM_BAD_PARAM;

    if ((NULL != base) && (NULL != mcp_config))
    {
        TCPWM_MOTIF_MCMEC(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMEC_MSBP, mcp_config->sync_bypass));
        if (NULL != mcp_config->output_config)
        {

                TCPWM_MOTIF_MOSC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MOSC_PUN,  mcp_config->output_config->pattern_update_event_config)  |
                                           _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MOSC_SHN,  mcp_config->output_config->update_sync_event_config)     |
                                           _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MOSC_MSTN, mcp_config->output_config->start_event_config));
        }
        if (mcp_config->lut_enable)
        {
            TCPWM_MOTIF_CLUT(base) &= ~TCPWM_MOTIF_GRP_MOTIF_CLUT_LUTEN_Msk;
            TCPWM_MOTIF_CLUT(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_CLUT_LUTEN, mcp_config->lut_enable));
            
            if (NULL != mcp_config->mlut_config)
            {
                TCPWM_MOTIF_MCSM(base)   = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_config->mlut_config->mlut_data_pos0));
                TCPWM_MOTIF_MCSM1(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_config->mlut_config->mlut_data_pos1));
                TCPWM_MOTIF_MCSM2(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_config->mlut_config->mlut_data_pos2));
                TCPWM_MOTIF_MCSM3(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_config->mlut_config->mlut_data_pos3));
                TCPWM_MOTIF_MCSM4(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_config->mlut_config->mlut_data_pos4));
                TCPWM_MOTIF_MCSM5(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_config->mlut_config->mlut_data_pos5));
            }
        }
        TCPWM_MOTIF_PCONF(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_FSEL, CY_MOTIF_STANDALONE_MULTICHANNEL_MODE) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MSES, mcp_config->edge_for_mset_trigger) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MSYES, mcp_config->edge_for_msync_trigger) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MCUE, mcp_config->mcp_mode) |
                                  _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE, 1U));

    status = CY_TCPWM_SUCCESS;
    }
    return(status);
    
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_Trigger_EdgeSel
***************************************************************************//**
*
* select the active edge for the trigger of Multi channel pattern update 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param edge_select Edge select for the Multi-Channel pattern \ref cy_en_trigger_edge_selection_t. 
*
* \note After the Correct Hall Event is detected, a delay can be generated between this detection and the update of the Multi-Channel pattern. 
* The delay for the update of the Multi-Channel pattern can be controlled directly by a TCPWM counter.
* The trigger that indicates that the delay is finished, is mapped to input MOTIFx.MSET (input for MCP trigger)
*
******************************************************************************/
void Cy_TCPWM_MOTIF_MCP_Trigger_EdgeSel(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_en_trigger_edge_selection_t edge_select)
{
    if (NULL != base)
    {
        /* This delay can be by passed in the mcp config by setting delay_bypass bit or by calling y_TCPWM_MOTIF_MCP_Delay_Bypass function */
        TCPWM_MOTIF_PCONF(base) &= ~TCPWM_MOTIF_GRP_MOTIF_MCMS_STHR_Msk;
        TCPWM_MOTIF_PCONF(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMS_STHR, edge_select));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_Bypass_Delay
***************************************************************************//**
*
* Enable/Disable multi channel pattern delay bypass 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param bypass_delay Bypass Delay . 
*
* \note After the Correct Hall Event is detected, a delay can be generated between this detection and the update of the Multi-Channel pattern. 
*   The delay for the update of the Multi-Channel pattern can be controlled directly by a TCPWM counter.
*   The trigger that indicates that the delay is finished, is mapped to input MOTIFx.MSET (input for MCP trigger)
*   This delay can be by passed by passing true to this function
*
******************************************************************************/
void Cy_TCPWM_MOTIF_MCP_Bypass_Delay(TCPWM_MOTIF_GRP_MOTIF_Type *base, bool bypass_delay)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMEC(base)  &= ~TCPWM_MOTIF_GRP_MOTIF_MCMEC_MEBP_Msk;
        TCPWM_MOTIF_MCMEC(base)  |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMEC_MEBP, bypass_delay));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_SW_Update_Enable
***************************************************************************//**
*
* Selects the source that enables an update of the Multi-Channel pattern.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param sw_update_enable When set to true, the Multi-Channel pattern can only be updated after the SW has called the function Cy_TCPWM_MOTIF_Update_Multi_Channel_Pattern.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_MCP_SW_Update_Enable(TCPWM_MOTIF_GRP_MOTIF_Type *base, bool sw_update_enable)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_PCONF(base) &= ~TCPWM_MOTIF_GRP_MOTIF_PCONF_MCUE_Msk;
        TCPWM_MOTIF_PCONF(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_MCUE, sw_update_enable));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Update_Multi_Channel_Pattern
***************************************************************************//**
*
* Update multi channel pattern.
* The update is not done immediately due to the fact that the trigger that synchronizes the update with the PWM is still needed
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* \note Calling this function enables the Multi-Channel pattern update.
*  The update is not done immediately due to the fact that the trigger that synchronizes the update with the PWM is still needed.
 * The input MOTIFx.MSYNC is used for synchronization. 
******************************************************************************/
void Cy_TCPWM_MOTIF_Update_Multi_Channel_Pattern(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMS(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMS_MNPS, 1U));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Clear_Multi_Channel_Pattern
***************************************************************************//**
*
* Clears the Multi-Channel Pattern value with the content of the MCP Fault register
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Clear_Multi_Channel_Pattern(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMC(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMC_MPC, 1U));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Clear_Updation_Of_Multi_Channel_Pattern
***************************************************************************//**
*
* Clears updating of multi channel pattern. Sets that Multi channel pattern is not read to be updated.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Clear_Updation_Of_Multi_Channel_Pattern(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMC(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMC_MNPC, 1U));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Get_Multi_Channel_Pattern_Update_Status
***************************************************************************//**
*
* returns the Multi Channel Pattern update status.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* return indicates if the Multi-Channel pattern is ready to be updated or not. 0: MCP is ready and 1: MCP is not ready. 
*
******************************************************************************/
bool Cy_TCPWM_MOTIF_Get_Multi_Channel_Pattern_Update_Status(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    return (bool) (_FLD2VAL(TCPWM_MOTIF_GRP_MOTIF_MCMF_MSS, TCPWM_MOTIF_MCMF(base)));
}


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Update_Multi_Channel_Pattern_Immediately
***************************************************************************//**
*
* Update multi channel pattern immediately.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* \note Calling this function enables the Multi-Channel pattern update immediately. 
*   The update is done immediately with out waiting for the trigger that synchronizes the update with the PWM.
******************************************************************************/
void Cy_TCPWM_MOTIF_Update_Multi_Channel_Pattern_Immediately(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMS(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMS_STMR, 1U));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_Bypass_Synchronization
***************************************************************************//**
*
* Synchronization of the trigger with the PWM is bypassed if set
*
* \param base The pointer to the TCPWM_MOTIF instance address.
*
* \param bypass_sync Synchronization bypass configuration.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_MCP_Bypass_Synchronization(TCPWM_MOTIF_GRP_MOTIF_Type *base, bool bypass_sync)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCMEC(base) &= ~TCPWM_MOTIF_GRP_MOTIF_MCMEC_MSBP_Msk;
        TCPWM_MOTIF_MCMEC(base) |= (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCMEC_MSBP, bypass_sync));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Set_MCP_Value
***************************************************************************//**
*
* Sets Multi channel pattern value.
* Every time a multi channel pattern transfer is triggered, this value is transferred.
* This is applicable when multi channel look up table mode is disabled.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param mcp_value Multi Channel Pattern Value
******************************************************************************/
void Cy_TCPWM_MOTIF_Set_MCP_Value (TCPWM_MOTIF_GRP_MOTIF_Type *base, uint32_t mcp_value)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCSM(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mcp_value));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_Value_When_Fault_Hall
***************************************************************************//**
*
* Sets MCP value when there is a fault HALL event.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param mcp_value Multi channel pattern value to be configured when there is a fault HALL event.
*
* \note It is possible also to use the Hall Fault Event to clear/load the Multi-Channel Pattern with a pre-configured value - MCPF.MCFV.
*  This mechanism can be used whenever a wrong operation is detected and a specific safe pattern needs to be applied to the PWM timers that are controlling the output switches.
******************************************************************************/
void Cy_TCPWM_MOTIF_MCP_Value_When_Fault_Hall(TCPWM_MOTIF_GRP_MOTIF_Type *base, uint32_t mcp_value)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_MCPF(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCPF_MCFV, mcp_value));
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Update_MLUT
***************************************************************************//**
*
* Update look up table for multi channel pattern MLUT mode
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param mlut_config  Multi Channel Pattern Look UP Table values. \ref cy_stc_tcpwm_motif_mlut_t
*
* \note Update look up table for multi channel pattern MLUT 
*   User writes HLUT and MLUT when MOTIF is stopped.
*   Writing into both LUT while MOTIF is started might lead to incorrect behavior.
*   The LUT is loaded with forward or reverse pattern depending on motor desired direction.
*   The pattern is stored in LUT independently from motor position.
*   The hardware is responsible to find out the current motor position and to load the right hall and modulation pattern.
*   HLUT and MLUT share the same hardware pointer for data extraction, therefore user needs to take care of keeping them aligned with respect to LUT address.
*   A wrong programming might lead to incorrect behavior. 
******************************************************************************/
void Cy_TCPWM_MOTIF_Update_MLUT(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_tcpwm_motif_mlut_t *mlut_config)
{
    if ((NULL != base) && (NULL != mlut_config))
    {
        TCPWM_MOTIF_MCSM(base)   = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mlut_config->mlut_data_pos0));
        TCPWM_MOTIF_MCSM1(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mlut_config->mlut_data_pos1));
        TCPWM_MOTIF_MCSM2(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mlut_config->mlut_data_pos2));
        TCPWM_MOTIF_MCSM3(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mlut_config->mlut_data_pos3));
        TCPWM_MOTIF_MCSM4(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mlut_config->mlut_data_pos4));
        TCPWM_MOTIF_MCSM5(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MCSM_MCMPS, mlut_config->mlut_data_pos5));
    }
    
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Multi_Channel_Output_Config
***************************************************************************//**
*
* Configures the output nodes for each of the Multi Channel Pattern output event
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param output_config Output configuration. \ref cy_stc_multi_channel_output_config_t
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Multi_Channel_Output_Config(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_multi_channel_output_config_t *output_config)
{
    
    if ((NULL != base) && (NULL != output_config))
    {

            TCPWM_MOTIF_MOSC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MOSC_PUN,  output_config->pattern_update_event_config)  |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MOSC_SHN,  output_config->update_sync_event_config)     |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_MOSC_MSTN, output_config->start_event_config));
    }
}

/** -------- Quadrature decoder Mode -------------- */

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Quaddec_Init
***************************************************************************//**
*
* MOTIF module initialization in Quadrature Decoder Mode
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param config Quadrature decoder configuration \ref cy_stc_tcpwm_motif_quaddec_config_t
*
* return Returns the status of the operation.
*
*
******************************************************************************/
cy_en_tcpwm_status_t Cy_TCPWM_MOTIF_Quaddec_Init(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_tcpwm_motif_quaddec_config_t const *config)
{
    cy_en_tcpwm_status_t status = CY_TCPWM_BAD_PARAM;

    if ((NULL != base) && (NULL != config))
    {

        if(config->output_config != NULL)
        {

            TCPWM_MOTIF_QOSC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_QCN,  config->output_config->clock_event_config)         |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_DON,  config->output_config->direction_event_config)     |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_PCN,  config->output_config->period_clock_event_config)  |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_CCN,  config->output_config->clear_capture_event_config) |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_IXN,  config->output_config->index_event_config)         |
                                       _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_QSTN, config->output_config->start_event_config));
        }
        
        if(config->position_decoder_mode == CY_MOTIF_PD_QUAD_MODE)
        {
            TCPWM_MOTIF_QDC(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PALS, config->phase_A_level_selector)      |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PBLS, config->phase_B_level_selector)      |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_INDS, config->index_signal_level_selector) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PACS, config->clock_signal_for_phase_A)    |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PBDS, config->clock_signal_for_phase_B)    |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_IDS, config->clock_signal_for_index)       |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PHS, config->phase_signal_swap)            |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PAEM, config->phae_A_edge_mode)            |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PBEM, config->phae_B_edge_mode)            |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_ICM, config->progindex_occurrence));
        }
        else
        {
            TCPWM_MOTIF_QDC(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PALS, config->phase_A_level_selector)   |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PBLS, config->phase_B_level_selector)   |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PACS, config->clock_signal_for_phase_A) |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PBDS, config->clock_signal_for_phase_B) |
                                      _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PHS, config->phase_signal_swap)        |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PAEM, config->phae_A_edge_mode)         |
                                     _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QDC_PBEM, config->phae_B_edge_mode));
            
        }
        
        TCPWM_MOTIF_PCONF(base) = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_FSEL, CY_MOTIF_QUAD_DECODER_MODE)    |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_QDCM, config->position_decoder_mode) |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_ENABLE, 1U));
        
        status = CY_TCPWM_SUCCESS;
    }

    return(status);
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Configure_Postion_Decoder_Mode
***************************************************************************//**
*
* Configures Position Decoder to either Quad mode or direction count mode based on the selection..
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param mode Mode to be set for the position decoder. \ref cy_en_position_decoder_mode_t
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Configure_Postion_Decoder_Mode(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_en_position_decoder_mode_t mode)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_PCONF(base) &= ~TCPWM_MOTIF_GRP_MOTIF_PCONF_QDCM_Msk;
        TCPWM_MOTIF_PCONF(base) |= _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_QDCM, mode);
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Get_Quaddec_Rotation_Direction
***************************************************************************//**
*
* returns the quaddec rotation direction.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* returns the quaddec rotation direction. 0: Counter clockwise rotation. 1: Clockwise Rotation 
*
******************************************************************************/ 
bool Cy_TCPWM_MOTIF_Get_Quaddec_Rotation_Direction(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    return (bool)(_FLD2VAL(TCPWM_MOTIF_GRP_MOTIF_QDC_DVAL, TCPWM_MOTIF_QDC(base)));
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Quaddec_Output_Config
***************************************************************************//**
*
* Configures the output nodes for each of the quaddec output event
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param output_config Output configuration. \ref cy_stc_quaddec_output_config_t
*
******************************************************************************/
void Cy_TCPWM_MOTIF_Quaddec_Output_Config(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_quaddec_output_config_t *output_config)
{
    if ((NULL != base) && (NULL != output_config))
    {
        TCPWM_MOTIF_QOSC(base)  = (_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_QCN,  output_config->clock_event_config)         |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_DON,  output_config->direction_event_config)     |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_PCN,  output_config->period_clock_event_config)  |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_CCN,  output_config->clear_capture_event_config) |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_IXN,  output_config->index_event_config)         |
                                   _VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_QOSC_QSTN, output_config->start_event_config));
    }
}


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_MCP_Quaddec_Init
***************************************************************************//**
*
* MOTIF module initialization in Quadrature Decoder Mode and Multi Channel Pattern mode. 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param MCP and Quad configuration \ref cy_stc_tcpwm_motif_mcp_quaddec_config_t
*
* return Returns the status of the operation.
*
*
******************************************************************************/
cy_en_tcpwm_status_t Cy_TCPWM_MOTIF_MCP_Quaddec_Init(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_stc_tcpwm_motif_mcp_quaddec_config_t const *mcp_quad_config)
{
    cy_en_tcpwm_status_t status = CY_TCPWM_BAD_PARAM;

    if ((NULL != base) && (NULL != mcp_quad_config))
    {
        if(NULL != mcp_quad_config->mcp_config)
        {
            /* Configure Multichannel pattern mode */
            status = Cy_TCPWM_MOTIF_MCP_Init(base, mcp_quad_config->mcp_config);
            
            if((status == CY_TCPWM_SUCCESS) && (NULL != mcp_quad_config->quaddec_config))
            {
                /* Configure Multichannel pattern mode */
                status = Cy_TCPWM_MOTIF_Quaddec_Init(base, mcp_quad_config->quaddec_config);
            }
        }
        if(status == CY_TCPWM_SUCCESS)
        {
            TCPWM_MOTIF_PCONF(base) &=  ~TCPWM_MOTIF_GRP_MOTIF_PCONF_FSEL_Msk;
            TCPWM_MOTIF_PCONF(base) |=(_VAL2FLD(TCPWM_MOTIF_GRP_MOTIF_PCONF_FSEL, CY_MOTIF_SAMC_QD_MODE));
        }

    }

    return(status);
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_Get_Lowpass_Filter_Status
***************************************************************************//**
*
* returns the status of the low pass filter.
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param lowpass_filter low pass filter. \ref cy_en_low_pass_filter_number_t
*
* Returns the status of the low pass filter 
*
******************************************************************************/ 
uint16_t Cy_TCPWM_MOTIF_Get_Lowpass_Filter_Status(TCPWM_MOTIF_GRP_MOTIF_Type *base, cy_en_low_pass_filter_number_t lowpass_filter)
{
    uint16_t filter_status = 0;
    if (NULL != base)
    {
        switch(lowpass_filter)
        {
            case CY_LOW_PASS_FILTER_0:
            {
                filter_status = (uint16_t) (_FLD2VAL(TCPWM_MOTIF_GRP_MOTIF_PLP0S_LPP0, TCPWM_MOTIF_PLP0S(base)));
                break;
            }
            case CY_LOW_PASS_FILTER_1:
            {
                filter_status = (uint16_t) (_FLD2VAL(TCPWM_MOTIF_GRP_MOTIF_PLP1S_LPP1, TCPWM_MOTIF_PLP1S(base)));
                break;
            }
            case CY_LOW_PASS_FILTER_2:
            {
                filter_status = (uint16_t) (_FLD2VAL(TCPWM_MOTIF_GRP_MOTIF_PLP2S_LPP2, TCPWM_MOTIF_PLP2S(base)));
                break;
            }
            default:
                filter_status = 0;
            break;
        }
    }
    return filter_status;
}
/** ------ Interrupts    ------- */

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_GetInterruptStatus
***************************************************************************//**
*
* Reports the status of the interrupts
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* return returns the Status of the interrupts
*
******************************************************************************/
uint32_t Cy_TCPWM_MOTIF_GetInterruptStatus(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    uint32_t status = 0;
    if (NULL != base)
    {
        status = TCPWM_MOTIF_PFLG(base);
    }
    return status;
}


/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_ClearInterrupt
***************************************************************************//**
*
* Clears the triggered interrupts
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param mask interrupts to be cleared.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_ClearInterrupt(TCPWM_MOTIF_GRP_MOTIF_Type *base, uint32_t mask)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_RPFLG(base) = mask;
    }

}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_SetInterrupt
***************************************************************************//**
*
* Software option to set the required interrupts. Interrupt handler will be called. 
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param interrupts to be set.
*
******************************************************************************/
void Cy_TCPWM_MOTIF_SetInterrupt(TCPWM_MOTIF_GRP_MOTIF_Type *base, uint32_t mask)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_SPFLG(base) = mask;
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_SetInterruptMask
***************************************************************************//**
*
* Sets one or more MOTIF module interrupt factor bits (sets the INTR_MASK register).
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* param interrupt Interrupt bit mask 
*
******************************************************************************/
void Cy_TCPWM_MOTIF_SetInterruptMask(TCPWM_MOTIF_GRP_MOTIF_Type *base, uint32_t mask)
{
    if (NULL != base)
    {
        TCPWM_MOTIF_PFLGE(base) = mask;
    }
}

/******************************************************************************
* Function Name: Cy_TCPWM_MOTIF_GetInterruptMask
***************************************************************************//**
*
* Reports the interrupt mask set
*
* param base The pointer to the TCPWM_MOTIF instance address.
*
* returns the interrupt mask set
*
******************************************************************************/
uint32_t Cy_TCPWM_MOTIF_GetInterruptMask(TCPWM_MOTIF_GRP_MOTIF_Type *base)
{
    uint32_t mask = 0;
    if (NULL != base)
    {
        mask = TCPWM_MOTIF_PFLGE(base);
    }
    return mask;
}


#if defined(__cplusplus)
}
#endif
#endif /*(CY_IP_MXTCPWM_VERSION >= 3U)*/
#endif /* CY_IP_MXTCPWM */

/* [] END OF FILE */
