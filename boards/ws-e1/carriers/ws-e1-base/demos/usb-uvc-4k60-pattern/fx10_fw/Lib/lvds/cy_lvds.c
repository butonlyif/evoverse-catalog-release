/***************************************************************************//**
* \file cy_lvds.c
* \version 1.00
*
* Source code file for the LVDS driver.
*
*******************************************************************************
* \copyright
* (c) (2024), Cypress Semiconductor Corporation (an Infineon company) or
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

#include "cy_device.h"

#if defined (CY_IP_MXS40LVDS2USB32SS)

#include "cy_lvds.h"
#include "cy_debug.h"
#include "cy_pdl.h"

#if defined(__cplusplus)
extern "C" {
#endif

#define NUMBER_FREQ_GEAR_RATIO_SUPPORTED        (CY_LVDS_CLK_74_25_MHZ_8_1+1)



#if (!LVCMOS_16BIT_SDR)
/**
 * @brief Lookup Table for PHY DESKEW ALGORITHM wrt INTERFACE CLK and GEAR RATIO
 */
const uint16_t cy_arr_lvds_deskew_algo[NUMBER_FREQ_GEAR_RATIO_SUPPORTED] =
{
    CY_LVDS_PHY_DESKEW_SDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 625 MHz GEAR RATIO 1:1. */
    CY_LVDS_PHY_DESKEW_DDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 625 MHz GEAR RATIO 2:1. */
    CY_LVDS_PHY_DESKEW_BYPASS,                  /**< DESKEW Algo for INTERFACE CLK 156.25 MHz GEAR RATIO 1:1. */
    CY_LVDS_PHY_DESKEW_SDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 156.25 MHz GEAR RATIO 2:1. */
    CY_LVDS_PHY_DESKEW_DDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 156.25 MHz GEAR RATIO 4:1. */
    CY_LVDS_PHY_DESKEW_DDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 156.25 MHz GEAR RATIO 8:1. */
    CY_LVDS_PHY_DESKEW_BYPASS,                  /**< DESKEW Algo for INTERFACE CLK 148.5 MHz GEAR RATIO 1:1. */
    CY_LVDS_PHY_DESKEW_SDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 148.5 MHz GEAR RATIO 2:1. */
    CY_LVDS_PHY_DESKEW_DDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 148.5 MHz GEAR RATIO 4:1. */
    CY_LVDS_PHY_DESKEW_DDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 148.5 MHz GEAR RATIO 8:1. */
    CY_LVDS_PHY_DESKEW_BYPASS,                  /**< DESKEW Algo for INTERFACE CLK 74.25 MHz GEAR RATIO 2:1. */
    CY_LVDS_PHY_DESKEW_SDR_FAST,                /**< DESKEW Algo for INTERFACE CLK 74.25 MHz GEAR RATIO 4:1. */
    CY_LVDS_PHY_DESKEW_DDR_FAST                 /**< DESKEW Algo for INTERFACE CLK 74.25 MHz GEAR RATIO 8:1. */
};

/**
 * @brief Lookup Table for PHY CNT 10US24 VAL wrt INTERFACE CLK and GEAR RATIO
*/
const uint16_t cy_arr_lvds_cnt_10us24_val[NUMBER_FREQ_GEAR_RATIO_SUPPORTED] =
{
    0x31F,                /**< CNT 10US24 VAL for INTERFACE CLK 625 MHz GEAR RATIO 1:1. */
    0x654,                /**< CNT 10US24 VAL for INTERFACE CLK 625 MHz GEAR RATIO 2:1. */
    0xC8,                 /**< CNT 10US24 VAL for INTERFACE CLK 156.25 MHz GEAR RATIO 1:1. */
    0x19A,                /**< CNT 10US24 VAL for INTERFACE CLK 156.25 MHz GEAR RATIO 2:1. */
    0x320,                /**< CNT 10US24 VAL for INTERFACE CLK 156.25 MHz GEAR RATIO 4:1. */
    0x63E,                /**< CNT 10US24 VAL for INTERFACE CLK 156.25 MHz GEAR RATIO 8:1. */
    0xBE,                 /**< CNT 10US24 VAL for INTERFACE CLK 148.5 MHz GEAR RATIO 1:1. */
    0x17C,                /**< CNT 10US24 VAL for INTERFACE CLK 148.5 MHz GEAR RATIO 2:1. */
    0x2F8,                /**< CNT 10US24 VAL for INTERFACE CLK 148.5 MHz GEAR RATIO 4:1. */
    0x5F0,                /**< CNT 10US24 VAL for INTERFACE CLK 148.5 MHz GEAR RATIO 8:1. */
    0xBE,                 /**< CNT 10US24 VAL for INTERFACE CLK 74.25 MHz GEAR RATIO 2:1. */
    0x300,                /**< CNT 10US24 VAL for INTERFACE CLK 74.25 MHz GEAR RATIO 4:1. */
    0x35E                 /**< CNT 10US24 VAL for INTERFACE CLK 74.25 MHz GEAR RATIO 8:1. */
};
#endif /* (!LVCMOS_16BIT_SDR) */

static void HandlePhyInterrupts        (uint32_t phyIntr, cy_stc_lvds_context_t *lvdsContext);
static void HandleGpifInterrupts       (uint32_t gpifIntr, cy_stc_lvds_context_t *lvdsContext);
static void HandleThreadError          (uint32_t threadError, uint32_t lvdsError, cy_stc_lvds_context_t *lvdsContext);
static void ReportGpifError            (uint32_t smNo, cy_stc_lvds_context_t *lvdsContext);

#if (!LVCMOS_16BIT_SDR)
/* Master DLL clock phase selected for LVCMOS DDR operation. */
static uint8_t glLvcmosClkPhaseSel[2] = {
    CY_LVDS_DDR_MDLL_PHASE_VAL,
    CY_LVDS_DDR_MDLL_PHASE_VAL
};
#endif /* (!LVCMOS_16BIT_SDR) */

/*******************************************************************************
* Function Name: Cy_LVDS_Init
****************************************************************************//**
*
* Initialises LVDS IP block.
*
* \param base
* Pointer to the LVDS register base address
*
* \param sipNo
* Sensor Interface Port number.
*
* \param cy_stc_lvds_config_t
* Pointer to a structure array specifies all the parameters required to configure
* the LVDS IP block
*
* \param cy_stc_lvds_context_t
* LVDS context structure.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_Init(LVDSSS_LVDS_Type * base, uint8_t sipNo,
                            const cy_stc_lvds_config_t * lvdsConfig, cy_stc_lvds_context_t *lvdsContext)
{
    cy_en_lvds_status_t status = CY_LVDS_BAD_PARAMETER;
    if((base == NULL) || (lvdsConfig == NULL) || (sipNo >= CY_LVDS_MAX_PHY_INSTANCE) ||
        (lvdsContext == NULL) || (lvdsConfig->phyConfig == NULL) || (lvdsConfig->gpifConfig == NULL))
    {
        return status;
    }

    status = Cy_LVDS_PhyInit(LVDSSS_LVDS, sipNo, lvdsConfig->phyConfig, lvdsContext);
    if(status != CY_LVDS_SUCCESS)
    {
        DBG_LVDS_ERR("LVDS_PhyInit failed for Port: %d\r\n", sipNo);
        return status;
    }

    DBG_LVDS_INFO("LVDS_PhyInit done for Port: %d\r\n", sipNo);

#if (!LVCMOS_16BIT_SDR)
    /* In case of a wide link port, both PHY needs to be initialized */
    if(lvdsConfig->phyConfig->wideLink == true)
    {
        status = Cy_LVDS_PhyInit(LVDSSS_LVDS, 1, lvdsConfig->phyConfig, lvdsContext);
        if(status != CY_LVDS_SUCCESS)
        {
            DBG_LVDS_ERR("LVDS_PhyInit failed for Port: 1\r\n");
            return status;
        }

        DBG_LVDS_INFO("LVDS_PhyInit done for Port: 1 \r\n");
    }
#endif /* (!LVCMOS_16BIT_SDR) */

    status = Cy_LVDS_GpifInit(LVDSSS_LVDS, sipNo, lvdsConfig->gpifConfig, lvdsContext);
    if(status != CY_LVDS_SUCCESS)
    {
        return status;
    }
    DBG_LVDS_INFO("LVDS_GpifInit done for Port: %d\r\n", sipNo);
    return status;
}

/*******************************************************************************
* Function Name: Cy_LVDS_InitMetadata
****************************************************************************//**
*
* Initialises LVDS Sensor interface port and Analog front end.
*
* \param base
* Pointer to the LVDS register base address
*
* \param threadNo
* There are 4 threads (0, 1, 2, 3) for which metadata insertion can pe performed.
*
* \param mdBuffer
* Pointer to a structure array (cy_stc_lvds_md_config_t) specifiying the metadata
* elements which needs to be inserted.
*
* \param mdIndex
* There are 4 Metadata per thread available to be initialized.
*
* \param mdCount
* Total number of metadata which needs to be inserted
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_InitMetadata(LVDSSS_LVDS_Type *base, uint8_t threadNo,
                            uint8_t mdIndex, uint8_t mdCount, cy_stc_lvds_md_config_t *mdBuffer)
{
    uint32_t i, value;

    if((base == NULL) || (threadNo >= CY_LVDS_MAX_THREAD_COUNT) ||
        (mdIndex >= CY_LVDS_MAX_MD_INDEX_COUNT) || (mdCount > CY_LVDS_MAX_MD_COUNT))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* Clear the MDx_CTRL register before initializing it */
    switch(mdIndex)
    {
        case 0:
            base->THREAD[threadNo].MD0_CTRL = 0x00000000;
            break;
        case 1:
            base->THREAD[threadNo].MD1_CTRL = 0x00000000;
            break;
#if (!LVCMOS_16BIT_SDR)
        case 2:
            base->THREAD[threadNo].MD2_CTRL = 0x00000000;
            break;
        case 3:
            base->THREAD[threadNo].MD3_CTRL = 0x00000000;
            break;
#endif /* (!LVCMOS_16BIT_SDR) */
    }

    for(i = 0; i < mdCount; i++)
    {
        if(mdBuffer[i].metadataType == CY_LVDS_MD_VARIABLE)
        {
            switch(mdIndex)
            {
                case 0:
                    base->THREAD[threadNo].MD0_CTRL |= (1 << i);
                    break;
                case 1:
                    base->THREAD[threadNo].MD1_CTRL |= (1 << i);
                    break;
#if (!LVCMOS_16BIT_SDR)
                case 2:
                    base->THREAD[threadNo].MD2_CTRL |= (1 << i);
                    break;
                case 3:
                    base->THREAD[threadNo].MD3_CTRL |= (1 << i);
                    break;
#endif /* (!LVCMOS_16BIT_SDR) */
            }
            value = mdBuffer[i].metadataValue + threadNo*LVDSSS_LVDS_THREAD_SECTION_SIZE;
        }
        else
        {
            value = mdBuffer[i].metadataValue;
        }
        if((threadNo == 0) || (threadNo == 1))
        {
            if(i%2 == 0)
            {
                base->TH0_TH1_METADATA_RAM[8*mdIndex + 32*threadNo + (i/2)] = value;
            }
            else
            {
                base->TH0_TH1_METADATA_RAM[8*mdIndex + 32*threadNo + ((i-1)/2)] |= value << 16;
            }
        }
#if (!LVCMOS_16BIT_SDR)
        else
        {
            if(i%2 == 0)
                base->TH2_TH3_METADATA_RAM[8*mdIndex + 32*(threadNo - 2) + (i/2)] = value;
            else
                base->TH2_TH3_METADATA_RAM[8*mdIndex + 32*(threadNo - 2) + ((i - 1)/2)] |= value << 16;
        }
#endif /* (!LVCMOS_16BIT_SDR) */
    }
    if(mdCount != 16)
    {
        switch(mdIndex)
        {
            case 0:
                base->THREAD[threadNo].MD0_CTRL |= _VAL2FLD(LVDSSS_LVDS_THREAD_MD0_CTRL_MD_SIZE, mdCount<<1);
                break;
            case 1:
                base->THREAD[threadNo].MD1_CTRL |= _VAL2FLD(LVDSSS_LVDS_THREAD_MD1_CTRL_MD_SIZE, mdCount<<1);
                break;
#if (!LVCMOS_16BIT_SDR)
            case 2:
                base->THREAD[threadNo].MD2_CTRL |= _VAL2FLD(LVDSSS_LVDS_THREAD_MD2_CTRL_MD_SIZE, mdCount<<1);
                break;
            case 3:
                base->THREAD[threadNo].MD3_CTRL |= _VAL2FLD(LVDSSS_LVDS_THREAD_MD3_CTRL_MD_SIZE, mdCount<<1);
                break;
#endif /* (!LVCMOS_16BIT_SDR) */
        }
    }

    return CY_LVDS_SUCCESS;
}

#if (!LVCMOS_16BIT_SDR)
/* Constant array that maps LVDS lane count settings from B0 silicon to that of A0 silicon. */
const uint8_t FX_A0_LVDS_LANE_CNT_MAP[] = {
    0,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_1 ==> 1 lane */
    1,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_2 ==> 2 lanes */
    2,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_3 ==> 4 lanes */
    2,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_4 ==> 4 lanes */
    3,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_5 ==> 8 lanes */
    3,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_6 ==> 8 lanes */
    3,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_7 ==> 8 lanes */
    3,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_8 ==> 8 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_9 ==> 16 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_10 ==> 16 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_11 ==> 16 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_12 ==> 16 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_13 ==> 16 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_14 ==> 16 lanes */
    4,          /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_15 ==> 16 lanes */
    4           /* CY_LVDS_PHY_LVDS_MODE_NUM_LANE_16 ==> 16 lanes */
};

/*******************************************************************************
* Function Name: Cy_LVDS_Phy_Lvds_Init
****************************************************************************//**
*
* Initialises LVDS Sensor interface port for LVDS Mode
*
* \param base
* Pointer to the LVDS register base address
*
* \param config
* Specifies port configuration such as bus direction, bus width etc.
* The value will provided by device configurator.
*
* \param portNo
* Port number on the LVDS Sensor Interface port (SIP)
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_Phy_Lvds_Init (LVDSSS_LVDS_Type * base,const cy_stc_lvds_phy_config_t * config, uint8_t portNo)
{

    uint8_t i = 0;
    uint8_t phy_deskew_algo = 0;
    uint32_t timeoutCount = 0;
    cy_en_lvds_status_t status = CY_LVDS_SUCCESS;


    if ((base == NULL) || (config == NULL) || (portNo >= CY_LVDS_MAX_PHY_INSTANCE))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* Pad for V1P1 has to be enabled */
    base->AFE[portNo].LICIO_VCCD_V1P1       |=  _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VCCD_V1P1_EN, 1u);

    /* Set LVDS_AFE0_PHY_ADC_CONFIG.ISO_N = 1 , Disable output isolation control (Active low) */
    base->AFE[portNo].PHY_ADC_CONFIG        |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_ADC_CONFIG_ISO_N, 1u);

    /* Set correct phase selection for DLL_M */
    if ((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_148_5_MHZ) || (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_74_25_MHZ))
    {
        base->AFE[portNo].DLL_M_CONFIG  |= _VAL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_MDLL_SEL_PH, 1u) |
                                           _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_MDLL_OW_PH, 1u);
    }

    /* Set DLL_M speed mode for Slow and Bypass LVDS modes. */
    if (((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_156_25_MHZ) && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1)) ||
        ((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_148_5_MHZ)  && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1)) ||
        ((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_74_25_MHZ)  && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1)) )
    {
        base->AFE[portNo].DLL_M_CONFIG          |=   _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_SPEED_MODE, 1u);
    }

    /* Set the right value for 10us DLL_M counter
       CNT_10US24_VAL calculation: (10.24 us * Frame clock MHz) + 100 */
    /* Set PHY_GENERAL_CONFIG.DESKEW_ALGORITHM */

    /* INTERFACE CLK 625 MHz Case */
    if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_625_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1) {
            DBG_LVDS_INFO("LVDS 625 Mhz 1:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_625_MHZ_1_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_625_MHZ_1_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_625_MHZ_1_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            DBG_LVDS_INFO("LVDS 625 Mhz 2:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_625_MHZ_2_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_625_MHZ_2_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_625_MHZ_2_1];
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    /* INTERFACE CLK 156.25 MHz Case */
    else if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_156_25_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1) {
            DBG_LVDS_INFO("LVDS 156.25 Mhz 1:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_156_25_MHZ_1_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_1_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_1_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            DBG_LVDS_INFO("LVDS 156.25 Mhz 2:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_156_25_MHZ_2_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_2_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_2_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_4_1) {
            DBG_LVDS_INFO("LVDS 156.25 Mhz 4:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_156_25_MHZ_4_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_4_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_4_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_8_1) {
            DBG_LVDS_INFO("LVDS 156.25 Mhz 8:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_156_25_MHZ_8_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_8_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_156_25_MHZ_8_1];
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    /* INTERFACE CLK 148.5 MHz Case */
    else if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_148_5_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1) {
            DBG_LVDS_INFO("LVDS 148.5 Mhz 1:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_148_5_MHZ_1_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_1_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_1_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            DBG_LVDS_INFO("LVDS 148.5 Mhz 2:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_148_5_MHZ_2_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_2_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_2_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_4_1) {
            DBG_LVDS_INFO("LVDS 148.5 Mhz 4:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_148_5_MHZ_4_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_4_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_4_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_8_1) {
            DBG_LVDS_INFO("LVDS 148.5 Mhz 8:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_148_5_MHZ_8_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_8_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_148_5_MHZ_8_1];
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    /* INTERFACE CLK 74.25 MHz Case */
    else if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_74_25_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            DBG_LVDS_INFO("LVDS 74.25 Mhz 2:1 Init start for Port: %d\r\n", portNo);
            /* CNT_10US24_VAL calculation: (10.24 us * Frame clock MHz) + 100 => 10.24 * 18.625 + 100 = 190 to 290 */
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_74_25_MHZ_2_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_74_25_MHZ_2_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_74_25_MHZ_2_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_4_1) {
            DBG_LVDS_INFO("LVDS 74.25 Mhz 4:1 Init start for Port: %d\r\n", portNo);
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_74_25_MHZ_4_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_74_25_MHZ_4_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_74_25_MHZ_4_1];
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_8_1) {
            DBG_LVDS_INFO("LVDS 74.25 Mhz 8:1 Init start for Port: %d\r\n", portNo);
            /* CNT_10US24_VAL calculation: (10.24 us * Frame clock MHz) + 100 => 10.24 * 74.50 + 100 = 862 */
            base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, cy_arr_lvds_cnt_10us24_val[CY_LVDS_CLK_74_25_MHZ_8_1]);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, cy_arr_lvds_deskew_algo[CY_LVDS_CLK_74_25_MHZ_8_1]);
            phy_deskew_algo = cy_arr_lvds_deskew_algo[CY_LVDS_CLK_74_25_MHZ_8_1];
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    else
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* NOTE: Only needed for LVDS DDR Fast and LVDS SDR Fast Deskew algorithms following vales */
    /* Set value for PHY_GENERAL_CONFIG.DESKEW_ERR_THRESH1,PHY_GENERAL_CONFIG.DESKEW_ERR_THRESH2
       PHY_GENERAL_CONFIG_2.MONITOR_ERR_THRESH and PHY_GENERAL_CONFIG.MONITOR_TIME */

    /* Find  PHY_DESKEW is SDR_FAST/DDR_FAST  */
    if ((phy_deskew_algo == CY_LVDS_PHY_DESKEW_DDR_FAST) || (phy_deskew_algo == CY_LVDS_PHY_DESKEW_SDR_FAST))
    {
        DBG_LVDS_INFO("PHY_DESKEW is SDR or DDR FAST Mode \r\n");
        /* DESKEW_ERR_THRESH2 value set set to 10 when the monitor is off and to 6 when the monitor is on */
        base->AFE[portNo].PHY_GENERAL_CONFIG &= ~LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ERR_THRESH1_Msk;
        base->AFE[portNo].PHY_GENERAL_CONFIG &= ~LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ERR_THRESH2_Msk;
        base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ERR_THRESH1, 3) |
                                                    _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ERR_THRESH2, 10);

        /* Set value for PHY_GENERAL_CONFIG_2.MONITOR_ERR_THRESH */
        base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_MONITOR_ERR_THRESH, 10);

        /* Set value for PHY_GENERAL_CONFIG.MONITOR_TIME */
        base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_MONITOR_TIME, 2);
    }

    Cy_SysLib_DelayUs(10);

    /* VDDIO and V1P1 have to enabled */
    base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_VDDIO, 1u) |
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_V1P1_VCCD, 1u) |
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_SCANON, 1u) |
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_V1P25_VCCD, 1u);
    Cy_SysLib_DelayUs(10);

    /* 10uA current for PLL biasing needs to be generated. 10uA have to present at i_ibias_10u_lnk0_ai */
    /* Reference current generator has to be switched ON */
    base->AFE[portNo].LICIO_VSSIO_IREF      |=  _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VSSIO_IREF_EN, 1u);
    Cy_SysLib_DelayUs(10);

    /* Switch on REG_1P25 Regulator for dll_m and use it (Not set it in bypass mode) */
    /* Switch on all needed LVDS RX with proper settings:
        1. In Bypass mode, invert the polarity of the serial clock that enters RX
	       RX.INV_CLK_SER = 1
        2. In Bypass mode,
           RX.CLK_MUX_SEL: a. For Frame Clock channel, 1 for LVDS Slow and LVDS Bypass.
                           b. Data Channel 3, 1 for LVDS Slow, 2 for LVDS Bypass.
	*/

    /* Find  Deskew Algorithm is SDR_FAST/DDR_FAST  */
    if ((phy_deskew_algo == CY_LVDS_PHY_DESKEW_DDR_FAST) || (phy_deskew_algo == CY_LVDS_PHY_DESKEW_SDR_FAST))
    {
        DBG_LVDS_INFO("PHY_DESKEW is SDR or DDR FAST Mode \r\n");
        /* Switch on REG_1P25 Regulator */
        base->AFE[portNo].REG_1P25      |=   _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_ENABLE, 1u) |
                                             _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_USE_REG, 1u);
        /* Switch on all needed LVDS RX */
        for(i = 0; i < 10; i++)
        {
            base->AFE[portNo].RX[i]    |=   _BOOL2FLD(LVDSSS_LVDS_AFE_RX_EN_DESER, 1u)|
                                            _BOOL2FLD(LVDSSS_LVDS_AFE_RX_FIXTIME_FRAMECLK, 1u);
        }
    }
    else if (phy_deskew_algo == CY_LVDS_PHY_DESKEW_BYPASS) /* Deskew Algorithm Bypass */
    {

        DBG_LVDS_INFO("PHY_DESKEW is Bypass Mode \r\n");
        /* Switch on all needed LVDS RX */
        for(i = 0; i < 10; i++)
        {
            if(i != 3)
            {
                base->AFE[portNo].RX[i]     |=  _VAL2FLD(LVDSSS_LVDS_AFE_RX_CLK_MUX_SEL, 1u) |
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_RX_INV_CLK_SER, 1u) |
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_RX_EN_DESER, 1u)|
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_RX_FIXTIME_FRAMECLK, 1u);
            }
        }
        base->AFE[portNo].RX[3]         |=  _VAL2FLD(LVDSSS_LVDS_AFE_RX_CLK_MUX_SEL, 2u) |
                                            _BOOL2FLD(LVDSSS_LVDS_AFE_RX_INV_CLK_SER, 1u) |
                                            _BOOL2FLD(LVDSSS_LVDS_AFE_RX_EN_DESER, 1u)|
                                            _BOOL2FLD(LVDSSS_LVDS_AFE_RX_FIXTIME_FRAMECLK, 1u);
    }
    else /* Deskew Algorithm Slow */
    {
        DBG_LVDS_ERR("PHY_DESKEW is Slow not supported \r\n");
        return CY_LVDS_CONFIG_ERROR;
    }

    /* Set LICIO_CIO_CTRL_DS.DS = 1 */
    base->AFE[portNo].LICIO_CIO_CTRL_DS     |=   _VAL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_CTRL_DS_DS, 0x1Fu);


    /* Set LICIO_CIO_DATA_DS[x].DS = 1 (0 <= x <= 16) */
    for(i = 0; i < 17; i++)
    {
        base->AFE[portNo].LICIO_CIO_DATA_DS[i] |=  _VAL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_DATA_DS_DS, 0x1Fu);
    }


    /* Inorder to save clock tree power of this path, set this bit field to 1 in case of LVDS mode */
    base->AFE[portNo].GENERAL_RX_LVCMOS     |=   _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_LVCMOS_MUX_SEL, 1u);

    /* Enable LVCMOS sideband control signals: LVCMOS sideband control signals can be both TX or RX */
    /* Depending on control bus bit map, pins which are input needs to be configured - For widelink there can be 14 pins */

    if(config->wideLink == true)
    {
        DBG_LVDS_INFO("LVDS WL Mode\r\n");
        for(i = 0; i < 7; i++)
        {
            if(((config->ctrlBusBitMap >> (i+(7*portNo)))) & 0x0001)
                    base->AFE[portNo].RX_LVCMOS[i+16] |= _BOOL2FLD(LVDSSS_LVDS_AFE_RX_LVCMOS_EN_LVCMOS, 1u);
        }
    }
    else
    {
        DBG_LVDS_INFO("LVDS NL Mode\r\n");
        for(i = 0; i < 7; i++)
        {
            if((config->ctrlBusBitMap >> i) & 0x0001)
                base->AFE[portNo].RX_LVCMOS[i+16] |= _BOOL2FLD(LVDSSS_LVDS_AFE_RX_LVCMOS_EN_LVCMOS, 1u);
        }
    }

    /* Turn ON LVDS receivers */
    base->AFE[portNo].GENERAL_LICIO_LI      |=   _VAL2FLD(LVDSSS_LVDS_AFE_GENERAL_LICIO_LI_LVDS_CONFIG, 3u);

    /* Switch on licio_li for Data Lane[7:0] , control Lane (8) and Frame clock (9) */
    for(i = 0; i < 10; i++)
    {
        base->AFE[portNo].LICIO_LI[i]       |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_LI_LVDS_RX_EN, 1u);

    }

    /* Set the correct mode for DR_MODE as DDR = 0 or SDR = 1  and also set DLL_BYPASS_EN in case of Bypass Mode */
    /* In case of Bypass Mode DR_MODE =1 (as SDR) */
    /* Find the Bypass Mode */
    if (phy_deskew_algo == CY_LVDS_PHY_DESKEW_BYPASS)
    {
        DBG_LVDS_INFO("PHY_DESKEW is Bypass Mode \r\n");
        /* Take LVDS pads as data source */
        base->AFE[portNo].GENERAL_RX            |=   _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_DLL_BYPASS_EN, 1u);
        base->AFE[portNo].GENERAL_RX            |=   _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_DR_MODE, 1u);
    }
    else if (phy_deskew_algo == CY_LVDS_PHY_DESKEW_SDR_FAST)
    {
        DBG_LVDS_INFO("PHY_DESKEW is SDR FAST Mode \r\n");
        base->AFE[portNo].GENERAL_RX            |=   _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_DR_MODE, 1u);
    }
    else if (phy_deskew_algo == CY_LVDS_PHY_DESKEW_DDR_FAST)
    {
        DBG_LVDS_INFO("PHY_DESKEW is DDR FAST Mode \r\n");
        base->AFE[portNo].GENERAL_RX            |=   _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_DR_MODE, 0u);
    }
    else /* Deskew Algorithm Slow */
    {
        DBG_LVDS_ERR("PHY_DESKEW is Slow not supported \r\n");
        return CY_LVDS_CONFIG_ERROR;
    }
    Cy_SysLib_DelayUs(10);


    /* Enable Differential resistance for all LVDS lanes */
    base->AFE[portNo].GENERAL_LICIO_CIO = 0x000003FF;

    /* Wait 10us */
    Cy_SysLib_DelayUs(10);

    /* Set PLL values based on port configuration then wait 1us */
    /* Switch on the PLL only when the frequency of the input clock is different from the
	    wanted frequency of the serial clock at the PLL output */

    /* INTERFACE CLK 625 MHz Case */
    if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_625_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x8u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x8u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x0u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_VCO_GAIN, 7u);
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    /* INTERFACE CLK 156.25 MHz Case */
    else if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_156_25_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u);

        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_4_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x0u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_8_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x8u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x0u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_VCO_GAIN, 7u);
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    /* INTERFACE CLK 148.5 MHz Case */
    else if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_148_5_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_4_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x0u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_8_1) {

            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x8u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x0u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u) ;
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    /* INTERFACE CLK 74.25 MHz Case */
    else if (config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_74_25_MHZ)
    {
        if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_4_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x4u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x1u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u);
        }
        else if (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_8_1) {
            base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_SERIAL_DIV, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_IN_DIV, 0x0u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FB_DIV, 0x4) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_N_FRAME_DIV, 0x0u);

            base->AFE[portNo].PLL_CONFIG_2          |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 0x2u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_VCO_GAIN, 0x4u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_MD, 0x1u) |
                                                        _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_FB_SEL, 0x2u);
        }
        else
            return CY_LVDS_BAD_PARAMETER;
    }
    else
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* Switch on PLL and wait for PLL Lock */
    /* Take care of PLL BYPASS Case 625 2:1 */
    if ((config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_625_MHZ) && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1))
    {
        DBG_LVDS_INFO("PLL BYPASS\r\n");
        Cy_SysLib_DelayUs(1);
        base->AFE[portNo].PLL_CONFIG            |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_BYPASS, 0x1u);
        Cy_SysLib_DelayUs(10);
    }
    else  /* Acquire  PLL LOCK */
    {
        /* Clear PLL_LOCK_ACQUIRED bit in PHY_INTR */
        base->AFE[portNo].PHY_INTR &= ~LVDSSS_LVDS_AFE_PHY_INTR_PLL_LOCK_ACQUIRED_Msk;

        base->AFE[portNo].PLL_CONFIG            |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_SUPPLY_EN, 0x1u);
        Cy_SysLib_DelayUs(10);

        base->AFE[portNo].PLL_CONFIG            |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_EN, 0x1u);

        DBG_LVDS_INFO("Wait till PLL Lock\r\n");
        timeoutCount = 0;
        while(!(base->AFE[portNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_PLL_LOCK_ACQUIRED_Msk))
        {
            Cy_SysLib_Delay(1);
            timeoutCount++;
            if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
            {
                status = CY_LVDS_TIMEOUT_ERROR;
                DBG_LVDS_ERR("PLL lock timed out for Port: %d\r\n", portNo);
                return status;
            }
        }
        base->AFE[portNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_PLL_LOCK_ACQUIRED_Msk;
        status = CY_LVDS_SUCCESS;
        DBG_LVDS_INFO("PLL lock done for Port: %d\r\n", portNo);
    }

    Cy_SysLib_DelayUs(1);

    /*  For SLOW/FAST deskew algorithm acquire DLL_LOCK  */
    /*  For BYPASS deskew algorithm not required DLL_LOCK */

    /* Find PHY_DESKEW SLOW or FAST DDR/SDR Deskew Algorithm Case */
    /* NOTE: FAST DDR/SDR Deskew Algorithm Case supported */
    if ((phy_deskew_algo == CY_LVDS_PHY_DESKEW_DDR_FAST) || (phy_deskew_algo == CY_LVDS_PHY_DESKEW_SDR_FAST))
    {

        /* Clear DLL_LOCK_ACQUIRED bit in PHY_INTR */
        base->AFE[portNo].PHY_INTR &= ~LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk;

        /* set DLL_M_CONFIG.EN = 1 */
        base->AFE[portNo].DLL_M_CONFIG         |=   _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_EN, 1u);
        Cy_SysLib_DelayUs(10);

        /* set DLL_S_CONFIG.SDLL_EN = 1 */
        for(i = 0; i < 12; i++)
        {
            base->AFE[portNo].DLL_S_CONFIG[i]         |=   _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_S_CONFIG_SDLL_EN, 1u);
        }

        /* Wait until DLL_M_Status.DLL_LOCK goes to 1 */
        DBG_LVDS_INFO("Wait till DLL Lock\r\n");
        timeoutCount = 0;
        while(!(base->AFE[portNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk))
        {
            Cy_SysLib_Delay(1);
            timeoutCount++;
            if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
            {
                status = CY_LVDS_TIMEOUT_ERROR;
                DBG_LVDS_ERR("LVDS DLL lock timedout for Port: %d\r\n", portNo);
                return status;
            }
        }

        base->AFE[portNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk;
        DBG_LVDS_INFO("LVDS DLL Lock done for Port: %d\r\n", portNo);
    }

    base->AFE[portNo].PHY_TRAIN_CONFIG &= ~LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_SEQ_Msk;
    base->AFE[portNo].PHY_TRAIN_CONFIG = _VAL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_SEQ,config->phyTrainingPattern) |
                                         _VAL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_CYCLES_NO,100);

    return status;
}
#endif /* (!LVCMOS_16BIT_SDR) */

/*******************************************************************************
* Function Name: Cy_LVDS_PhyInit
****************************************************************************//**
*
* Initialises LVDS Sensor interface port and Analog front end.
*
* \param base
* Pointer to the LVDS register base address
*
* \param portNo
* Port number on the LVDS Sensor Interface port (SIP)
*
* \param config
* Specifies port configuration such as bus direction, bus width etc.
* The value will provided by device configurator.
*
* \param lvdsContext
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_PhyInit(LVDSSS_LVDS_Type * base, uint8_t portNo, const cy_stc_lvds_phy_config_t * config, cy_stc_lvds_context_t *lvdsContext)
{
    uint8_t i = 0;
#if (!LVCMOS_16BIT_SDR)
    uint32_t timeoutCount = 0;
#endif /* (!LVCMOS_16BIT_SDR) */
    bool sf2bit = false;
    cy_en_lvds_status_t status = CY_LVDS_SUCCESS;

    if((base == NULL) || (config == NULL) || (portNo >= CY_LVDS_MAX_PHY_INSTANCE) ||
        (lvdsContext == NULL))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

#if LVCMOS_16BIT_SDR
    if(config->modeSelect == CY_LVDS_PHY_MODE_LVDS)
    {
        return CY_LVDS_BAD_PARAMETER;
    }
#endif /* (!LVCMOS_16BIT_SDR) */

    /* Initialize LVDS context structure */
    lvdsContext->base = base;
    if(portNo == 0)
        lvdsContext->phyConfigP0 = (cy_stc_lvds_phy_config_t *)config;
#if (!LVCMOS_16BIT_SDR)
    else
        lvdsContext->phyConfigP1 = (cy_stc_lvds_phy_config_t *)config;
#endif /* (!LVCMOS_16BIT_SDR) */

    /* Calculate value to be set in LINK_CONFIG.TWO_BIT_SLV_FF field. */
    if (config->slaveFifoMode == CY_LVDS_SLAVE_FIFO_2BIT)
    {
        sf2bit = true;
    }

    /* Initialize and enable the LINK */
    if (Cy_SysLib_GetDeviceRevision() == 0x11)
    {
#if (!LVCMOS_16BIT_SDR)
        /* Active device revision is A0. */
        if (config->modeSelect == CY_LVDS_PHY_MODE_LVDS)
        {
            base->LINK_CONFIG[portNo] =
                _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_LVDS_MODE,          config->modeSelect) |
                _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_GEARING_RATIO,      config->gearingRatio) |
                _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_WIDE_LINK,         config->wideLink) |
                _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_NUM_LANES,          FX_A0_LVDS_LANE_CNT_MAP[config->dataBusWidth]) |
                _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_TWO_BIT_SLV_FF_A0, sf2bit) |
                0x100UL;
        }
        else
#endif /* (!LVCMOS_16BIT_SDR) */
        {
            base->LINK_CONFIG[portNo] =
                _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_LVDS_MODE,          config->modeSelect) |
                _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_GEARING_RATIO,      config->gearingRatio) |
                _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_WIDE_LINK,         config->wideLink) |
                _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_NUM_LANES,          config->dataBusWidth) |
                _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_TWO_BIT_SLV_FF_A0, sf2bit) |
                0x100UL;
        }
    }
    else
    {
        /* Active device revision is B0. */
        base->LINK_CONFIG[portNo] =
            _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_LVDS_MODE,       config->modeSelect) |
            _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_GEARING_RATIO,   config->gearingRatio) |
            _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_WIDE_LINK,      config->wideLink) |
            _VAL2FLD(LVDSSS_LVDS_LINK_CONFIG_NUM_LANES,       config->dataBusWidth) |
            _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_TWO_BIT_SLV_FF, sf2bit) |
            _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_LINK_ENABLE,    1u);
#if (!LVCMOS_16BIT_SDR)
        /* In LVCMOS DDR mode with TX enabled, we need to set the BYPASS_DDR_PHY bit. */
        if ((config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS) && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) &&
            (config->dataBusDirection != CY_LVDS_PHY_AD_BUS_DIR_INPUT) && (config->lvcmosClkMode == CY_LVDS_LVCMOS_CLK_MASTER))
        {
            base->LINK_CONFIG[portNo] |= _BOOL2FLD(LVDSSS_LVDS_LINK_CONFIG_BYPASS_DDR_PHY, 1u);
        }
#endif /* (!LVCMOS_16BIT_SDR) */
    }

    Cy_LVDS_GpifConfigClock(base, portNo, config);

#if (!LVCMOS_16BIT_SDR)
    /* In LVDS mode, since the buffer wrap is done by HW without GPIF involvement, the
    below configuration is done. Each bit in the below register corresponds to 1 socket */
    if(config->modeSelect == CY_LVDS_PHY_MODE_LVDS)
    {
        base->LVDS_EOP_EOT = 0xFFFFFFFFu;
    }

    /* Configuration of LINK training registers, required for
       all LVDS modes and only for LVCMOS DDR Widelink mode */
    if((config->modeSelect == CY_LVDS_PHY_MODE_LVDS) ||
        ((config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS) && (config->wideLink == true) && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1)))
    {
        if (config->loopbackModeEn == false)
        {
            base->TRAINING_BLK_CFG = 0x3;
            base->TRAINING_BLK     = config->linkTrainingPattern;
        }
    }
#endif /* (!LVCMOS_16BIT_SDR) */

    /* LVDS IP and PHY should be enabled before AFE initialization */
    base->CTL    =  _BOOL2FLD(LVDSSS_LVDS_CTL_PHY_ENABLED,  1u) |
                    _BOOL2FLD(LVDSSS_LVDS_CTL_IP_ENABLED,   1u);

#if (!LVCMOS_16BIT_SDR)
    /* AFE Initialization sequence */
    if(config->loopbackModeEn == true)
    {
        if(config->isPutLoopbackMode)
        {
            base->AFE[portNo].LICIO_VCCD_V1P1     |= 0x00000001;
            base->AFE[portNo].PHY_GENERAL_CONFIG  |= 0x0000003C;
            base->AFE[portNo].LICIO_VSSIO_IREF    |= 0x00000001;
            Cy_SysLib_DelayUs(10);
            base->AFE[portNo].RX[9]               = 0x00000000;
            base->AFE[portNo].RX[9]               = 0x0000002B;
            base->AFE[portNo].GENERAL_RX          |= 0x00000004;
            Cy_SysLib_DelayUs(10);
            base->AFE[portNo].PLL_CONFIG          |= 0x00000404;
            Cy_SysLib_DelayUs(1);
            base->AFE[portNo].PHY_TRAIN_CONFIG    |= 0x00000001;
            Cy_LVDS_EnableLoopbackMode(base, portNo);
            DBG_LVDS_INFO("Loopback mode Init Done for Port: %d\r\n", portNo);
        }
    }
    else
#endif /* (!LVCMOS_16BIT_SDR) */
    {
        /*********** AFE Initialization sequence for LVCMOS SDR and DDR Master Mode TX ************/
        if (
                (
                 (config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS) &&
                 (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_1_1)
                )
#if (!LVCMOS_16BIT_SDR)
                ||
                (
                 (config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS) &&
                 (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) &&
                 (config->dataBusDirection != CY_LVDS_PHY_AD_BUS_DIR_INPUT) &&
                 (config->lvcmosClkMode == CY_LVDS_LVCMOS_CLK_MASTER)
                )
#endif /* (!LVCMOS_16BIT_SDR) */
           )
        {
            DBG_LVDS_INFO("LVCMOS SDR Mode\r\n");
            if ((config->lvcmosClkMode == CY_LVDS_LVCMOS_CLK_MASTER)) {
                DBG_LVDS_INFO("LVCMOS SDR/DDR MASTER Mode\r\n");
                base->AFE[portNo].LICIO_VCCD_V1P1       |= _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VCCD_V1P1_EN, 1u);
            }

            base->AFE[portNo].PHY_ADC_CONFIG            |= _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_ADC_CONFIG_ISO_N, 1u);

            base->AFE[portNo].PHY_GENERAL_CONFIG        |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_VDDIO, 1u);

            if ((config->lvcmosClkMode == CY_LVDS_LVCMOS_CLK_MASTER))
                base->AFE[portNo].PHY_GENERAL_CONFIG    |=  _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_V1P1_VCCD, 1u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_SCANON, 1u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_V1P25_VCCD, 1u);


            if ((config->lvcmosClkMode == CY_LVDS_LVCMOS_CLK_MASTER) && (config->lvcmosMasterClkSrc == CY_LVDS_MASTER_CLK_SRC_PLL))
            {
                base->AFE[portNo].PLL_CONFIG            |=  _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_REF_SEL, 2u) |  /* Reference clock taken as clock HF */
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_BYPASS, 1u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_SUPPLY_EN, 1u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_EN, 1u);

                base->AFE[portNo].LICIO_VSSIO_IREF      |=  _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VSSIO_IREF_EN, 1u);
                Cy_SysLib_DelayUs(10);

                base->AFE[portNo].REG_1P25              |=  _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_ENABLE, 1u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_USE_REG, 1u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_TRIM_VREG_1P25, 7u);
            }

            base->AFE[portNo].GENERAL_RX_LVCMOS         |=  _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_LVCMOS_CLK_MODE, 0u) |
                                                            _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_LVCMOS_MUX_SEL, 1u);

            base->AFE[portNo].LICIO_CIO_CTRL_DS         |=   _VAL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_CTRL_DS_DS, 0x1Fu);

            for(i = 0; i < 17; i++)
            {
                base->AFE[portNo].LICIO_CIO_DATA_DS[i]  |=   _VAL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_DATA_DS_DS, 0x1Fu);
            }

            /* SDR clock pads (P0CP and P1D1P) */
            if (config->lvcmosClkMode != CY_LVDS_LVCMOS_CLK_MASTER)
            {

                base->AFE[0].LICIO_CIO[24]  |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_LVCMOS_RX_EN, 0x1u);
                base->AFE[1].LICIO_CIO[9]   |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_LVCMOS_RX_EN, 0x1u);
            }
            else
            {
                base->AFE[0].LICIO_CIO[24]  |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_LVCMOS_TX_EN, 0x1u);
                base->AFE[1].LICIO_CIO[9]   |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_LVCMOS_TX_EN, 0x1u);
            }

            /* Note: Direction (input or output) of data and control lines can be programmed by GPIF or from AFE Register.
               Note: In LVCMOS SDR RX mode there is no need to activate rx_lvcmos as AFE is bypassed altogether. */
            /* Please make sure to select:
                1. LVCMOS CLK Mode (Master/Slave) using GPIF->GPIF_CONFIG.CLK_SOURCE
                2. LVCMOS ClK Src  (in Master mode) using GPIF->LVCMOS_CLK_OUT_CFG.CLK_SRC
                3. Using Correct Div for Clk Src (Master mode) using GPIF->LVCMOS_CLK_OUT_CFG.CLK_SRC_DIV_VAL */

#if (!LVCMOS_16BIT_SDR)
            DBG_LVDS_INFO("LVCMOS SDR Init Done for Port: %d\r\n", portNo);
#else
            DBG_LVDS_INFO("LVCMOS SDR or SDR/DDR Master Init Done for Port: %d\r\n", portNo);
#endif /* (!LVCMOS_16BIT_SDR) */
        }
#if (!LVCMOS_16BIT_SDR)
        /*********** AFE Initialization sequence for LVCMOS DDR ************/
        /* This case is for DDR RX Slave */
        if((config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS) && (config->gearingRatio == CY_LVDS_PHY_GEAR_RATIO_2_1) &&
                (config->dataBusDirection == CY_LVDS_PHY_AD_BUS_DIR_INPUT))
        {

            DBG_LVDS_INFO("DDR Init started for Port: %d\r\n", portNo);
            base->AFE[portNo].LICIO_VCCD_V1P1       |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VCCD_V1P1_EN, 1u);
            base->AFE[portNo].PHY_ADC_CONFIG        |=   _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_ADC_CONFIG_ISO_N, 1u);

            if(config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_100_MHZ)
            {
                base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=   _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, 1035);
            }
            else if(config->interfaceClock == CY_LVDS_PHY_INTERFACE_CLK_160_MHZ)
            {
                base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=   _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, 1700);
            }
            else
            {
                /* Assuming 80 MHz. */
                base->AFE[portNo].PHY_GENERAL_CONFIG_2  |=   _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_2_CNT_10US24_VAL, 900);
            }

            base->AFE[portNo].PHY_GENERAL_CONFIG    |=   _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_VDDIO, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_V1P1_VCCD, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_SCANON, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_ENABLE_V1P25_VCCD, 1u);
            base->AFE[portNo].PLL_CONFIG            |=   _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_REF_SEL, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_BYPASS, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_RUN_AWAY_DIS, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_SUPPLY_EN, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_EN, 1u);
            base->AFE[portNo].LICIO_VSSIO_IREF      |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VSSIO_IREF_EN, 1u);
            Cy_SysLib_DelayUs(10);

            base->AFE[portNo].REG_1P25              |=   _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_ENABLE, 1u) |
                                                        _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_USE_REG, 1u);
            Cy_SysLib_DelayUs(10);

            /* Since only RX is supported in DDR mode, all data lines will always be input */
            for(i = 0; i < 16; i++)
            {
                base->AFE[portNo].RX_LVCMOS[i]      |= _BOOL2FLD(LVDSSS_LVDS_AFE_RX_LVCMOS_EN_LVCMOS, 1u);
            }

            /* Depending on control bus bit map, pins which are input needs to be configured - For widelink there can be 20 pins*/
            if(config->wideLink == true)
            {
                for(i = 0; i < 10; i++)
                {
                    if(((config->ctrlBusBitMap >> (i+(10*portNo)))) & 0x0001)
                        base->AFE[portNo].RX_LVCMOS[i+16] |= _BOOL2FLD(LVDSSS_LVDS_AFE_RX_LVCMOS_EN_LVCMOS, 1u);
                }
            }
            else
            {
                for(i = 0; i < 10; i++)
                {
                    if((config->ctrlBusBitMap >> i) & 0x0001)
                        base->AFE[portNo].RX_LVCMOS[i+16] |= _BOOL2FLD(LVDSSS_LVDS_AFE_RX_LVCMOS_EN_LVCMOS, 1u);
                }
            }

            /* Frame clock */
            base->AFE[portNo].LICIO_CIO[26]  |=   _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_LVCMOS_RX_EN, 0x1u);

            base->AFE[portNo].LICIO_CIO_CTRL_DS     |=   _VAL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_CTRL_DS_DS, 0x1Fu);
            for(i = 0; i < 17; i++)
            {
                base->AFE[portNo].LICIO_CIO_DATA_DS[i] |=   _VAL2FLD(LVDSSS_LVDS_AFE_LICIO_CIO_DATA_DS_DS, 0x1Fu);
            }

            base->AFE[portNo].GENERAL_RX_LVCMOS |= _BOOL2FLD(LVDSSS_LVDS_AFE_GENERAL_RX_LVCMOS_EN_DDR, 1u);
            base->AFE[portNo].PLL_CONFIG_2      |= _VAL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_2_PLL_RA_UP_TR, 2u);
            base->AFE[portNo].DLL_M_CONFIG      |= _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_EN, 1u) |
                _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_SPEED_MODE, 1u) |
                _VAL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_MDLL_SEL_PH, glLvcmosClkPhaseSel[portNo]) |
                _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_MDLL_OW_PH, 1u);
            timeoutCount = 0;
            while(!(base->AFE[portNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk))
            {
                Cy_SysLib_Delay(1);
                timeoutCount++;
                if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
                {
                    status = CY_LVDS_TIMEOUT_ERROR;
                    DBG_LVDS_INFO("DDR DLL_M lock timed out for Port: %d\r\n", portNo);
                    return status;
                }
            }
            base->AFE[portNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk;
            status = CY_LVDS_SUCCESS;
            DBG_LVDS_INFO("DDR DLL_M lock done for Port: %d\r\n", portNo);

            base->AFE[portNo].PHY_TRAIN_CONFIG      |=   _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_EN, 1u);
            base->AFE[portNo].PHY_GENERAL_CONFIG    |=   _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, CY_LVDS_PHY_DESKEW_SLOW);

            timeoutCount = 0;
            while(!(base->AFE[portNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk))
            {
                Cy_SysLib_Delay(1);
                timeoutCount++;
                if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
                {
                    status = CY_LVDS_TIMEOUT_ERROR;
                    DBG_LVDS_INFO("DDR DESKEW timed out for Port: %d\r\n", portNo);
                    return status;
                }
            }
            base->AFE[portNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk;
            status = CY_LVDS_SUCCESS;
            DBG_LVDS_INFO("DDR Deskew complete for Port: %d\r\n", portNo);
        }
#endif /* (!LVCMOS_16BIT_SDR) */

#if (!LVCMOS_16BIT_SDR)
        /*********** AFE Initialization sequence for LVDS Interface  ************/
        if (config->modeSelect == CY_LVDS_PHY_MODE_LVDS) {
            status = Cy_LVDS_Phy_Lvds_Init(base,config,portNo);
        }
#endif /* (!LVCMOS_16BIT_SDR) */
    }

    return status;
}

#if (!LVCMOS_16BIT_SDR)
/*******************************************************************************
* Function Name: Cy_LVDS_PhyTrainingStart
****************************************************************************//**
*
* Enable PHY TRAINING in AFE and then wait for DESKEW COMPLETE to get set.
*
* \param base
* Pointer to the LVDS register base address
*
* \param portNo
* Port number on the LVDS Sensor Interface port (SIP)
*
* \param config
* Specifies port configuration such as bus direction, bus width etc.
* The value will provided by device configurator.
*
* \return cy_en_lvds_status_t
* CY_LVDS_CONFIG_ERROR - If the function is called for LVCMOS mode
* CY_LVDS_TIMEOUT_ERROR - If the DESKEW didn't get completed
* CY_LVDS_SUCCESS - If the operation is successful
*
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_PhyTrainingStart(LVDSSS_LVDS_Type* base, uint8_t portNo, const cy_stc_lvds_phy_config_t * config)
{
    uint32_t timeoutCount = 0;
    cy_en_lvds_status_t status = CY_LVDS_SUCCESS;

    /* PHY training is only required for LVDS modes */
    if(config->modeSelect == CY_LVDS_PHY_MODE_LVCMOS)
        return CY_LVDS_CONFIG_ERROR;

    base->AFE[portNo].PHY_TRAIN_CONFIG  |= _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_EN, 1);

    if(config->wideLink)
        base->AFE[1].PHY_TRAIN_CONFIG  |= _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_EN, 1);

    while(!(base->AFE[portNo].PHY_GENERAL_STATUS_2 & LVDSSS_LVDS_AFE_PHY_GENERAL_STATUS_2_DESKEW_COMPLETED_Msk))
    {
        Cy_SysLib_Delay(1);
        timeoutCount++;
        if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
        {
            status = CY_LVDS_TIMEOUT_ERROR;
            DBG_LVDS_INFO("DESKEW timed out for Port: %d\r\n", portNo);
            return status;
        }
    }
    status = CY_LVDS_SUCCESS;
    DBG_LVDS_INFO("Deskew complete for Port: %d\r\n", portNo);

    if(config->wideLink)
    {
        timeoutCount = 0;
        while(!(base->AFE[1].PHY_GENERAL_STATUS_2 & LVDSSS_LVDS_AFE_PHY_GENERAL_STATUS_2_DESKEW_COMPLETED_Msk))
        {
            Cy_SysLib_Delay(1);
            timeoutCount++;
            if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
            {
                status = CY_LVDS_TIMEOUT_ERROR;
                DBG_LVDS_INFO("DESKEW timed out for Port: 1\r\n");
                return status;
            }
        }
        status = CY_LVDS_SUCCESS;
        DBG_LVDS_INFO("Deskew complete for Port: 1\r\n");
    }

    return status;
}
#endif /* (!LVCMOS_16BIT_SDR) */

/*******************************************************************************
* Function Name: Cy_LVDS_PhyGpioModeEnable
****************************************************************************//**
*
* Enable GPIO mode for LVDS/LVCMOS pins.
*
* \param base
* Pointer to the LVDS register base address
*
* \param portNo
* Sensor interface port number.
*
* \param pinNo
* \ref  cy_en_lvds_phy_gpio_index_t
*
* \param dir
* \ref cy_en_lvds_phy_gpio_dir_t
*
* \param intrMode
* \ref cy_en_lvds_phy_gpio_intr_mode_t
*
* \funcusage
* \snippet
*
*******************************************************************************/
void Cy_LVDS_PhyGpioModeEnable (LVDSSS_LVDS_Type* base,
                                uint8_t portNo,
                                cy_en_lvds_phy_gpio_index_t pinNo,
                                cy_en_lvds_phy_gpio_dir_t dir,
                                cy_en_lvds_phy_gpio_intr_mode_t intrMode)
{
    if(dir == CY_LVDS_PHY_GPIO_INPUT)
    {
        base->AFE[portNo].PHY_GPIO[pinNo] |=    _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_INPUT_EN, 1u) |
                                                _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_GPIO_ENABLE, 1u);

        /* Configure interrupt corresponding to GPIO if required*/
        if(intrMode != CY_LVDS_PHY_GPIO_NO_INTERRUPT)
        {
            base->AFE[portNo].PHY_GPIO_INTR_CFG |= _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_INTR_CFG_GPIO_INTR_PIN_SEL, pinNo);
            base->AFE[portNo].PHY_GPIO_INTR_CFG |= _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_INTR_CFG_INTRMODE, intrMode);
        }
    }
    else
    {
        base->AFE[portNo].PHY_GPIO[pinNo] |= _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_OUTPUT_EN, 1u) |
                                           _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_GPIO_ENABLE, 1u);
    }
}

/*******************************************************************************
* Function Name: Cy_LVDS_PhyGpioModeDisable
****************************************************************************//**
*
* Disable GPIO mode for LVDS/LVCMOS pins.
*
* \param base
* Pointer to the LVDS register base address
*
* \param portNo
* Sensor interface port number.
*
* \param pinNo
* \ref  cy_en_lvds_phy_gpio_index_t
*
* \funcusage
* \snippet
*
*******************************************************************************/
void Cy_LVDS_PhyGpioModeDisable (LVDSSS_LVDS_Type* base, uint8_t portNo, cy_en_lvds_phy_gpio_index_t pinNo)
{
    base->AFE[portNo].PHY_GPIO[pinNo] = _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_GPIO_GPIO_ENABLE, 0);
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifEnableComp
****************************************************************************//**
*
* Configures comparators in GPIF block.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param compType
* \ref  cy_en_lvds_gpif_comp_type_t
*
* \param compValue
* The value to compare the signals against.
*
* \param compMask
* Mask that specifies which bits are to be used in the comparison.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
* \funcusage
* \snippet
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifEnableComp(LVDSSS_LVDS_Type* base, uint8_t smNo, cy_en_lvds_gpif_comp_type_t compType, void *compValue, void *compMask)
{
    uint32_t * value = (uint32_t *)compValue;
    uint32_t * mask = (uint32_t *)compMask;

    if(smNo >= CY_LVDS_MAX_GPIF_INSTANCE)
    {
        return CY_LVDS_BAD_PARAMETER;
    }
    switch (compType)
    {
        case CY_LVDS_GPIF_COMP_CTRL:
            base->GPIF[smNo].GPIF_CTRL_COMP_VALUE = value[0];
            base->GPIF[smNo].GPIF_CTRL_COMP_MASK  = mask[0];
            base->GPIF[smNo].GPIF_CONFIG  |= LVDSSS_LVDS_GPIF_GPIF_CONFIG_CTRL_COMP_ENABLE_Msk;
            break;

        case CY_LVDS_GPIF_COMP_ADDR:
            base->GPIF[smNo].GPIF_ADDR_COMP_VALUE = value[0];
            base->GPIF[smNo].GPIF_ADDR_COMP_MASK  = mask[0];
            base->GPIF[smNo].GPIF_CONFIG  |= LVDSSS_LVDS_GPIF_GPIF_CONFIG_ADDR_COMP_ENABLE_Msk;
            break;

        case CY_LVDS_GPIF_COMP_DATA:
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD0 = value[0];
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD0  = mask[0];
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD1 = value[1];
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD1  = mask[1];
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD2 = value[2];
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD2  = mask[2];
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD3 = value[3];
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD3  = mask[3];
            base->GPIF[smNo].GPIF_CONFIG  |= LVDSSS_LVDS_GPIF_GPIF_CONFIG_DATA_COMP_ENABLE_Msk;
            break;

        default:
            return CY_LVDS_BAD_PARAMETER;
    }

    return CY_LVDS_SUCCESS;
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifDisableComp
****************************************************************************//**
*
* Resets the comparators in GPIF block.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param compType
* \ref  cy_en_lvds_gpif_comp_type_t
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
* \funcusage
* \snippet
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifDisableComp(LVDSSS_LVDS_Type* base, uint8_t smNo, cy_en_lvds_gpif_comp_type_t compType)
{
    if(smNo >= CY_LVDS_MAX_GPIF_INSTANCE)
    {
        return CY_LVDS_BAD_PARAMETER;
    }
    switch (compType)
    {
        case CY_LVDS_GPIF_COMP_CTRL:
            base->GPIF[smNo].GPIF_CTRL_COMP_VALUE = 0u;
            base->GPIF[smNo].GPIF_CTRL_COMP_MASK  = 0u;
            base->GPIF[smNo].GPIF_CONFIG  &= ~LVDSSS_LVDS_GPIF_GPIF_CONFIG_CTRL_COMP_ENABLE_Msk;
            break;

        case CY_LVDS_GPIF_COMP_ADDR:
            base->GPIF[smNo].GPIF_ADDR_COMP_VALUE = 0u;
            base->GPIF[smNo].GPIF_ADDR_COMP_MASK  = 0u;
            base->GPIF[smNo].GPIF_CONFIG  &= ~LVDSSS_LVDS_GPIF_GPIF_CONFIG_ADDR_COMP_ENABLE_Msk;
            break;

        case CY_LVDS_GPIF_COMP_DATA:
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD0 = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD0  = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD1 = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD1  = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD2 = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD2  = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_VALUE_WORD3 = 0u;
            base->GPIF[smNo].GPIF_DATA_COMP_MASK_WORD3  = 0u;
            base->GPIF[smNo].GPIF_CONFIG  &= ~LVDSSS_LVDS_GPIF_GPIF_CONFIG_DATA_COMP_ENABLE_Msk;
            break;

        default:
            return CY_LVDS_BAD_PARAMETER;
    }

    return CY_LVDS_SUCCESS;
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifInitAddrCounter
****************************************************************************//**
*
* Configures GPIF Address counter.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param initValue
* Initial (reset) value for the counter.
*
* \param limit
* Value at which to stop the counter and flag an event.
*
* \param reload
* Whether to reload the counter and continue after limit is hit.
*
* \param upCount
* Whether to count upwards from the initial value.
*
* \param increment
* The value to be incremented/decremented from the counter at each step.
*
* \funcusage
* \snippet
*
*******************************************************************************/
void Cy_LVDS_GpifInitAddrCounter(LVDSSS_LVDS_Type * base, uint8_t smNo, uint32_t initValue, uint32_t limit, bool reload, bool upCount, uint8_t increment)
{
    /* Make sure that the counter is stopped */
    base->GPIF[smNo].GPIF_ADDR_COUNT_CONFIG = 0u;

    /* Set the initial value and the limit */
    base->GPIF[smNo].GPIF_ADDR_COUNT_RESET = initValue;
    base->GPIF[smNo].GPIF_ADDR_COUNT_LIMIT = limit;

    /* Set the counter configuration as desired */
    base->GPIF[smNo].GPIF_ADDR_COUNT_CONFIG = _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_ADDR_COUNT_CONFIG_ENABLE, 1u)       |
                                         _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_ADDR_COUNT_CONFIG_RELOAD, reload)   |
                                         _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_ADDR_COUNT_CONFIG_DOWN_UP, upCount) |
                                         _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_ADDR_COUNT_CONFIG_INCREMENT, increment);
}


/*******************************************************************************
* Function Name: Cy_LVDS_GpifInitCtrlCounter
****************************************************************************//**
*
* Configures GPIF control counter.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param initValue
* Initial (reset) value for the counter.
*
* \param limit
* Value at which to stop the counter and flag an event.
*
* \param reload
* Whether to reload the counter and continue after limit is hit.
*
* \param upCount
* Whether to count upwards from the initial value.
*
* \param outputBit
* Selects counter bit to be connected to CTRL[9] output.
*
* \funcusage
* \snippet
*
*******************************************************************************/
void Cy_LVDS_GpifInitCtrlCounter(LVDSSS_LVDS_Type* base, uint8_t smNo, uint32_t initValue, uint32_t limit, bool reload, bool upCount, uint8_t outputBit)
{
    /* Make sure that the counter is stopped. */
    base->GPIF[smNo].GPIF_CTRL_COUNT_CONFIG = 0;

    /* Set the initial value and the limit. */
    base->GPIF[smNo].GPIF_CTRL_COUNT_RESET = initValue;
    base->GPIF[smNo].GPIF_CTRL_COUNT_LIMIT = limit;

    /* Set the counter configuration as desired */
    base->GPIF[smNo].GPIF_CTRL_COUNT_CONFIG = _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_CTRL_COUNT_CONFIG_ENABLE, 1u)       |
                                         _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_CTRL_COUNT_CONFIG_RELOAD_CNTR, reload)   |
                                         _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_CTRL_COUNT_CONFIG_DOWN_UP_CNTR, upCount) |
                                         _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_CTRL_COUNT_CONFIG_CONNECT, outputBit);
}


/*******************************************************************************
* Function Name: Cy_LVDS_GpifInitDataCounter
****************************************************************************//**
*
* Configures GPIF data counter.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param initValueMsb
* Higher 4 byte of initial (reset) value for the counter.
*
* \param initValueLsb
* Lower 4 byte of initial (reset) value for the counter.
*
* \param limitMsb
* Higher 4 byte of value at which to stop the counter and flag an event.
*
* \param limitLsb
* Lower 4 byte of value at which to stop the counter and flag an event.
*
* \param reload
* Whether to reload the counter and continue after limit is hit.
*
* \param upCount
* Whether to count upwards from the initial value.
*
* \param increment
* The value to be incremented/decremented from the counter at each step.
*
* \funcusage
* \snippet
*
*******************************************************************************/
void Cy_LVDS_GpifInitDataCounter(LVDSSS_LVDS_Type* base, uint8_t smNo, uint32_t initValueMsb, uint32_t initValueLsb, uint32_t limitMsb, uint32_t limitLsb, bool reload, bool upCount, uint8_t increment)
{
    /* Make sure that the counter is stopped. */
    base->GPIF[smNo].GPIF_DATA_COUNT_CONFIG = 0u;

    /* Set the initial value and the limit. */
    base->GPIF[smNo].GPIF_DATA_COUNT_RESET_LSB = initValueLsb;
    base->GPIF[smNo].GPIF_DATA_COUNT_RESET_MSB = initValueMsb;
    base->GPIF[smNo].GPIF_DATA_COUNT_LIMIT_LSB = limitLsb;
    base->GPIF[smNo].GPIF_DATA_COUNT_LIMIT_MSB = limitMsb;

    /* Set the counter configuration as desired. */
    base->GPIF[smNo].GPIF_DATA_COUNT_CONFIG = _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_DATA_COUNT_CONFIG_ENABLE, 1u)       |
                                         _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_DATA_COUNT_CONFIG_RELOAD, reload)   |
                                         _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_DATA_COUNT_CONFIG_DOWN_UP, upCount) |
                                         _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_DATA_COUNT_CONFIG_INCREMENT, increment);
}


/*******************************************************************************
* Function Name: Cy_LVDS_GpifInitStateCounter
****************************************************************************//**
*
* Configures GPIF State counter.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param limit
* Value at which to stop the counter and flag an event.
*
* \funcusage
* \snippet
*
*******************************************************************************/
void Cy_LVDS_GpifInitStateCounter(LVDSSS_LVDS_Type* base, uint8_t smNo, uint16_t limit)
{
    /* Make sure that the counter is stopped. */
    base->GPIF[smNo].GPIF_STATE_COUNT_CONFIG = 0u;

    /* Set the initial value and the limit. */
    base->GPIF[smNo].GPIF_STATE_COUNT_LIMIT = limit;

    /* Enable the counter */
    base->GPIF[smNo].GPIF_STATE_COUNT_CONFIG = _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_STATE_COUNT_CONFIG_ENABLE, 1u);
}


cy_en_lvds_status_t Cy_LVDS_GpifWriteData(LVDSSS_LVDS_Type* base, uint8_t smNo, uint32_t threadIndex, bool selectThread, uint32_t numWords, uint32_t *buffer, uint32 waitOption)
{
   return CY_LVDS_BAD_PARAMETER;
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifReadData
****************************************************************************//**
*
* This API will receive the data into GPIF registers.
*
* \param base
* Pointer to the LVDS register base address.
*
* \param smNo
* GPIF state machine number.
*
* \param threadIndex
* Thread number to be used.
*
* \param selectThread
* Enables SW to select thread.
*
* \param numWords
* Number of words to read and store into the buffer.
*
* \param buffer
* Pointer to the buffer where data will be copied.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
* CY_LVDS_CONFIG_ERROR - If the sequence in which registers are configured is incorrect
*
* \funcusage
* \snippet
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifReadData(LVDSSS_LVDS_Type* base,
                                        uint8_t smNo,
                                        uint32_t threadIndex,
                                        bool selectThread,
                                        uint32_t numWords,
                                        uint32_t *buffer,
                                        uint32 waitOption)
{
    cy_en_lvds_status_t status = CY_LVDS_BAD_PARAMETER;
    uint32_t timeoutCount = 0;
    uint32_t interruptMaskVal;
    if ((threadIndex >= CY_LVDS_MAX_THREAD_COUNT) || (base == NULL) ||
        (smNo >= CY_LVDS_MAX_GPIF_INSTANCE))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* If the thread has to be activated, check if software based thread selection
     * is permitted; and do so.
     */
    if (selectThread)
    {
        if (((base->GPIF[smNo].GPIF_CONFIG & LVDSSS_LVDS_GPIF_GPIF_CONFIG_THREAD_IN_STATE_Msk) != 0) ||
                ((base->GPIF[smNo].GPIF_AD_CONFIG & LVDSSS_LVDS_GPIF_GPIF_AD_CONFIG_AIN_DATA_Msk) == 0))
        {
            return CY_LVDS_CONFIG_ERROR;
        }

        base->GPIF[smNo].GPIF_AD_CONFIG = (base->GPIF[smNo].GPIF_AD_CONFIG & ~LVDSSS_LVDS_GPIF_GPIF_AD_CONFIG_DATA_THREAD_Msk) |
            (threadIndex << LVDSSS_LVDS_GPIF_GPIF_AD_CONFIG_DATA_THREAD_Pos);
    }

    /* Clear interrupt mask bits, to ensure the handler is not invoked */
    interruptMaskVal = base->GPIF[smNo].GPIF_INTR_MASK;
    base->GPIF[smNo].GPIF_INTR_MASK &= ~ (1 << (LVDSSS_LVDS_GPIF_GPIF_STATUS_IN_DATA_VALID_Pos + threadIndex));

    /* If the register already has data, read the first word from it directly without waiting for an event. */
    if (base->GPIF[smNo].GPIF_INTR & (1 << (LVDSSS_LVDS_GPIF_GPIF_STATUS_IN_DATA_VALID_Pos + threadIndex)))
    {
        *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD0;
        *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD1;
        *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD2;
        *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD3;
        base->THREAD[threadIndex].GPIF_DATA_CTRL = (1 << threadIndex);
        numWords--;
    }

    if (numWords)
    {
        while (numWords--)
        {
            while(!(base->GPIF[smNo].GPIF_INTR & (1 << (LVDSSS_LVDS_GPIF_GPIF_STATUS_IN_DATA_VALID_Pos + threadIndex))))
            {
                Cy_SysLib_Delay(1);
                timeoutCount++;
                if (timeoutCount >= 2500U)
                {
                    status = CY_LVDS_TIMEOUT_ERROR;
                    break;
                }
            }

            if (status == CY_LVDS_TIMEOUT_ERROR)
            {
                base->GPIF[smNo].GPIF_INTR_MASK = interruptMaskVal;
                return status;
            }

            /* Read the data into the buffer and clear the data valid flag. */
            *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD0;
            *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD1;
            *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD2;
            *buffer++ = base->THREAD[threadIndex].GPIF_INGRESS_DATA_WORD3;
            base->THREAD[threadIndex].GPIF_DATA_CTRL = (1 << threadIndex);
        }
    }
    base->GPIF[smNo].GPIF_INTR_MASK = interruptMaskVal;
    return CY_LVDS_SUCCESS;
}


/*******************************************************************************
* Function Name: Cy_LVDS_GpifThreadConfig
****************************************************************************//**
*
* Configures and enables the thread. Thread number and it's various
* connfigurations are passed as parameters.
*
* \param base
* Pointer to the LVDS register base address
*
* \param threadIndex
* Thread number which needs to be configured
*
* \param socketNo
* Socket number which is to be assigned to thread.
*
* \param watermark
* Watermark position.
*
* \param burst
* Log2 of burst size.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
* \funcusage
* \snippet
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifThreadConfig(LVDSSS_LVDS_Type* base, uint8_t threadIndex, uint32_t socketNo, bool flagOnData,
                                            uint16_t watermark, uint8_t burst)
{
    uint8_t socketNoLsb;
    socketNoLsb = socketNo & 0x00000001u;
    socketNo = socketNo >> 1;
    /* Parameter checks. */
    if ((threadIndex >= CY_LVDS_MAX_THREAD_COUNT) || (base == NULL) || (socketNo >= CY_LVDS_MAX_SOCKET_COUNT))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* Disable the thread before enabling it with the correct configuration. */
    base->THREAD[threadIndex].GPIF_THREAD_CONFIG = _BOOL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR, 0u);

    /* Compute and update the register value. */
    base->THREAD[threadIndex].GPIF_THREAD_CONFIG = _VAL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_THREAD_NUM, socketNoLsb) |
                                                   _VAL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_THREAD_SOCK, socketNo) |
                                                   _VAL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_WM_CFG, flagOnData)    |
                                                   _VAL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_BURST_SIZE, burst)     |
                                                   _VAL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_WATERMARK, watermark)  |
                                                   _BOOL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR, 1u);

    return CY_LVDS_SUCCESS;
}


/*******************************************************************************
* Function Name: Cy_LVDS_GpifSMSwitch
****************************************************************************//**
*
* This function is used to start GPIF state machine execution from a desired state.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF state machine number.
*
* \param fromState
* State index from which the switch needs to be initiated.
*
* \param toState
* State index of the destination state.
*
* \param endState
* State index which triggers GPIF_DONE event
*
* \param initialAlpha
* Mask of Alpha signal which needs to be asserted when the new state machine starts
* \ref cy_en_lvds_gpif_alpha_t
*
* \param switchTimeout
* Switch timeout counter value. SWITCH_TIMEOUT interrupt gets asserted once the
* timer elapses after a WAVEFORM swith is initiated.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifSMSwitch(LVDSSS_LVDS_Type * base, uint8_t smNo,
                                uint16_t fromState, uint16_t toState, uint16_t endState,
                                cy_en_lvds_gpif_alpha_t initialAlpha, uint32_t switchTimeout)
{
    uint32_t switchVal = 0;
    uint32_t numdss;
    uint32_t gpifstat;
    uint8_t  curState;

    if((base == NULL) || (smNo >= CY_LVDS_MAX_GPIF_INSTANCE) ||
                (toState >= CY_LVDS_GPIF_MAX_NUM_STATES))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* Find the DSS level of the state machine. */
    numdss   = _FLD2VAL(LVDSSS_LVDS_GPIF_GPIF_BUS_CONFIG2_STATE_FROM_CTRL, base->GPIF[smNo].GPIF_BUS_CONFIG2);

    /* Update the initial Alpha values for the next state switch. */
    base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT = _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_ALPHA_INIT, initialAlpha) |
                                               _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_WAVEFORM_VALID, 1u);

    switchVal = _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_DESTINATION_STATE, toState) | (base->GPIF[smNo].GPIF_WAVEFORM_SWITCH);

    if (fromState < CY_LVDS_GPIF_MAX_NUM_STATES)
    {
        /* Check if the state machine is already in the fromState or a mirror. */
        curState = (base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT & LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_CURRENT_STATE_Msk) >> LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_CURRENT_STATE_Pos;
        if ((curState & GPIF_MAX_STATE(numdss)) == (fromState & GPIF_MAX_STATE(numdss)))
        {
            switchVal |= _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_SWITCH_NOW, 1u);
        }
        else
        {
            /* The timeout setting is assumed to be valid if a fromState is specified. */
            switchVal |= (_VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_TERMINAL_STATE, fromState)) | (_VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_TIMEOUT_MODE, 1u));
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH_TIMEOUT = switchTimeout;
        }
    }
    else
    {
        /* Set the switch immediately flag. */
        switchVal |= _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_SWITCH_NOW, 1u);
    }

    /* If a valid endState is specified, set this information and enable the DONE event. */
    if (endState < CY_LVDS_GPIF_MAX_NUM_STATES)
    {
        switchVal |= (_VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_DONE_STATE, endState) | _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_DONE_ENABLE, 1u));
        base->GPIF[smNo].GPIF_INTR_MASK |= _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_INTR_GPIF_DONE, 1u);
    }

    /* Write into the GPIF register to request the switch. */
    base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = switchVal;

    gpifstat = base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT;
    switch (numdss)
    {
        case 1:
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = ((switchVal & 0xFF7FFFFF) |
                                                    ((gpifstat & 0x80000000u) >> 8));
            break;
        case 2:
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = ((switchVal & 0xFF3FFFFF) |
                                                    ((gpifstat & 0xC0000000u) >> 8));
            break;
        case 3:
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = ((switchVal & 0xFF1FFFFF) |
                                                    ((gpifstat & 0xE0000000u) >> 8));
            break;
        default:
            break;
    }

    return CY_LVDS_SUCCESS;
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifSMStart
****************************************************************************//**
*
* Start the GPIF state machine from the specified state.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param stateIndex
* Index of the state from where to start the state machine.
*
* \param initialAlpha
* Alpha signal to look for once the state machine starts.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
* CY_LVDS_CONFIG_ERROR - If the sequence in which registers are configured is incorrect
*
* \note
* This function should be called after initialization both the PHY and LINK
* layer.
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifSMStart(LVDSSS_LVDS_Type* base, uint8_t smNo, uint8_t stateIndex, uint8_t initialAlpha)
{
    uint32_t numdss;
    uint32_t gpifstat;
    uint32_t switchVal;

    if(smNo >= CY_LVDS_MAX_GPIF_INSTANCE)
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* State checks. */
    if (((base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT & LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_WAVEFORM_VALID_Msk) == 1) ||
            ((base->GPIF[smNo].LEFT.WAVEFORM[0].WAVEFORM2 & 0x80000000ul) == 0))
    {
        return CY_LVDS_CONFIG_ERROR;
    }

    /* Mark the waveform as valid. */
    base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT = _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_ALPHA_INIT, initialAlpha) |
                                               _VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_WAVEFORM_VALID, 1u);

    /* Switch to the desired state and start execution. */
    switchVal = base->GPIF[smNo].GPIF_WAVEFORM_SWITCH;
    switchVal = (switchVal & 0xFF00003A) | (_VAL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_DESTINATION_STATE, stateIndex));

    base->GPIF[smNo].GPIF_WAVEFORM_SWITCH  = switchVal;
    base->GPIF[smNo].GPIF_WAVEFORM_SWITCH |= _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_WAVEFORM_SWITCH, 1u) |
                                             _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_SWITCH_NOW, 1u);

    gpifstat = base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT;
    numdss   = _FLD2VAL(LVDSSS_LVDS_GPIF_GPIF_BUS_CONFIG2_STATE_FROM_CTRL, base->GPIF[smNo].GPIF_BUS_CONFIG2);
    switch (numdss)
    {
        case 1:
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = ((switchVal & 0xFF7F003A) |
                                                    _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_WAVEFORM_SWITCH, 1u) |
                                                    _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_SWITCH_NOW, 1u) |
                                                    ((gpifstat & 0x80000000u) >> 8));
            break;

        case 2:
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = ((switchVal & 0xFF3F003A) |
                                                    _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_WAVEFORM_SWITCH, 1u) |
                                                    _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_SWITCH_NOW, 1u) |
                                                    ((gpifstat & 0xC0000000u) >> 8));
            break;

        case 3:
            base->GPIF[smNo].GPIF_WAVEFORM_SWITCH = ((switchVal & 0xFF1F003A) |
                                                    _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_WAVEFORM_SWITCH, 1u) |
                                                    _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_SWITCH_SWITCH_NOW, 1u) |
                                                    ((gpifstat & 0xE0000000u) >> 8));
            break;

        default:
            break;
    }

    return CY_LVDS_SUCCESS;
}


/*******************************************************************************
* Function Name: Cy_LVDS_GpifSMControl
****************************************************************************//**
*
* Pause or resume the Gpif State machine.
*
* \param base
* Pointer to the LVDS register base address.
*
* \param smNo
* GPIF state machine number.
*
* \param pause
* pause = 1 will pause the state machine,
* pause = 0 will resume the state machine.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
* CY_LVDS_CONFIG_ERROR - If the sequence in which registers are configured is incorrect
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifSMControl(LVDSSS_LVDS_Type * base, uint8_t smNo, bool pause)
{
    if(smNo >= CY_LVDS_MAX_GPIF_INSTANCE)
    {
        return CY_LVDS_BAD_PARAMETER;
    }
    if (((base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT & LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_WAVEFORM_VALID_Msk) == 0))
    {
        return CY_LVDS_CONFIG_ERROR;
    }

    base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT = _BOOL2FLD(LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_PAUSE, pause);

    return CY_LVDS_SUCCESS;
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifWaveformLoad
****************************************************************************//**
*
* Initialises the GPIF waveform based on the state machine.
* The waveform is an output from the GPIF designer.
*
* \param base
* Pointer to the LVDS register base address.
*
* \param smNo
* GPIF state machine number.
*
* \param stateCnt
* Number of states present in the state machine.
*
* \param firstState
* Index of the first state.
*
* \param stateDataMap
* Mapping of waveform memory with the states.
*
* \param transitionData
* Structure containing Waveform memory configuration.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
* CY_LVDS_CONFIG_ERROR - If the sequence in which registers are configured is incorrect
*
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifWaveformLoad(LVDSSS_LVDS_Type* base, uint8_t smNo, uint8 stateCnt, uint8_t firstState, uint8_t *stateDataMap, cy_stc_lvds_gpif_wavedata_t *transitionData)
{
    uint16_t index, entry;

    /* Parameter checks. */
    if ((transitionData == NULL) || ((firstState + stateCnt) > CY_LVDS_GPIF_MAX_NUM_STATES) ||
        (smNo >= CY_LVDS_MAX_GPIF_INSTANCE) || (base == NULL))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    if (((base->GPIF[smNo].GPIF_WAVEFORM_CTRL_STAT & LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_WAVEFORM_VALID_Msk) == 0))
    {
        return CY_LVDS_CONFIG_ERROR;
    }

    /* Copy the data from the input arrays into the waveform memory. */
    for (index = 0; index < stateCnt; index++)
    {
        /* No look-up table means direct mapping. */
        entry = (stateDataMap != 0) ? stateDataMap[index] : index;

        base->GPIF[smNo].LEFT.WAVEFORM[index + firstState].WAVEFORM0  = (transitionData[entry].leftData[0]);
        base->GPIF[smNo].LEFT.WAVEFORM[index + firstState].WAVEFORM1  = (transitionData[entry].leftData[1]);
        base->GPIF[smNo].LEFT.WAVEFORM[index + firstState].WAVEFORM2  = (transitionData[entry].leftData[2]);
        base->GPIF[smNo].LEFT.WAVEFORM[index + firstState].WAVEFORM3  = (transitionData[entry].leftData[3]);


        base->GPIF[smNo].RIGHT.WAVEFORM[index + firstState].WAVEFORM0 = (transitionData[entry].rightData[0]);
        base->GPIF[smNo].RIGHT.WAVEFORM[index + firstState].WAVEFORM1 = (transitionData[entry].rightData[1]);
        base->GPIF[smNo].RIGHT.WAVEFORM[index + firstState].WAVEFORM2 = (transitionData[entry].rightData[2]);
        base->GPIF[smNo].RIGHT.WAVEFORM[index + firstState].WAVEFORM3 = (transitionData[entry].rightData[3]);
    }

    return CY_LVDS_SUCCESS;
}

/*******************************************************************************
* Function Name: Cy_LVDS_GpifInitTransFunction
****************************************************************************//**
*
* Initialises the truth table for the user defined transition function in the
* GPIF State Machine
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF state machine number.
*
* \param fnTable
* Array of values corresponding to transfer function.
* The array is an output of the GPIF designer GPIF state machine number.
*
* \note
* This function should be called after initialization both the PHY and LINK
* layer.
*
*******************************************************************************/
void Cy_LVDS_GpifInitTransFunction(LVDSSS_LVDS_Type * base, uint8_t smNo, uint16 *fnTable)
{
    uint32_t index;

    for (index = 0; index < CY_LVDS_GPIF_NUM_TRANS_FUNC; index++)
    {
        base->GPIF[smNo].GPIF_FUNCTION[index] = (uint32_t)fnTable[index];
    }
}



/*******************************************************************************
* Function Name: Cy_LVDS_GpifInit
****************************************************************************//**
*
* Initializes the GPIF.
*
* \param base
* Pointer to the LVDS register base address
*
* \param smNo
* GPIF State Machine number.
*
* \param gpifConfig
* Structure containing all the configuration values for GPIF.
*
* \param lvdsContext
* LVDS driver context structure.
*
* \return cy_en_lvds_status_t
* CY_LVDS_BAD_PARAMETER - If the arguments are incorrect/invalid
* CY_LVDS_SUCCESS - If the operation is successful
*
* \note
* The gpifConig sructure will be generated by GPIF Designer tool.
*
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_GpifInit(LVDSSS_LVDS_Type * base, uint8_t smNo, const cy_stc_lvds_gpif_config_t *gpifConfig, cy_stc_lvds_context_t *lvdsContext)
{
    uint32_t addr = (uint32_t)&(base->GPIF[smNo]);
    uint8_t entry = 0;
    uint32_t index = 0;

    DBG_LVDS_INFO("Cy_LVDS_GpifInit Start\r\n");
    if ((base == NULL) || (lvdsContext == NULL) || (smNo >= CY_LVDS_MAX_GPIF_INSTANCE))
    {
        return CY_LVDS_BAD_PARAMETER;
    }

    /* Initialize context structure */
    if(smNo == 0)
        lvdsContext->gpifConfigP0 = (cy_stc_lvds_gpif_config_t *)gpifConfig;
    else
        lvdsContext->gpifConfigP1 = (cy_stc_lvds_gpif_config_t *)gpifConfig;


    for (index = 0; index < gpifConfig->regCount; index++)
    {
        *(uint32_t *)(addr + (uint32_t)gpifConfig->regData[index].regAddr) = (uint32_t)gpifConfig->regData[index].regValue;
    }

    for (index = 0; index < gpifConfig->stateCount; index++)
    {
        entry = gpifConfig->statePosition[index];
        base->GPIF[smNo].LEFT.WAVEFORM[index].WAVEFORM0  = gpifConfig->stateData[entry].leftData[0];
        base->GPIF[smNo].LEFT.WAVEFORM[index].WAVEFORM1  = gpifConfig->stateData[entry].leftData[1];
        base->GPIF[smNo].LEFT.WAVEFORM[index].WAVEFORM2  = gpifConfig->stateData[entry].leftData[2];
        base->GPIF[smNo].LEFT.WAVEFORM[index].WAVEFORM3  = gpifConfig->stateData[entry].leftData[3];

        base->GPIF[smNo].RIGHT.WAVEFORM[index].WAVEFORM0 = gpifConfig->stateData[entry].rightData[0];
        base->GPIF[smNo].RIGHT.WAVEFORM[index].WAVEFORM1 = gpifConfig->stateData[entry].rightData[1];
        base->GPIF[smNo].RIGHT.WAVEFORM[index].WAVEFORM2 = gpifConfig->stateData[entry].rightData[2];
        base->GPIF[smNo].RIGHT.WAVEFORM[index].WAVEFORM3 = gpifConfig->stateData[entry].rightData[3];
    }

    for (index = 0; index < gpifConfig->functionCount; index++)
    {
        base->GPIF[smNo].GPIF_FUNCTION[index] = gpifConfig->functionData[index];
    }

    return CY_LVDS_SUCCESS;
}



static void ReportThreadError(cy_en_lvds_gpif_thread_error_t errorCode,
                                cy_en_lvds_gpif_thread_no_t threadNo,
                                cy_stc_lvds_context_t *lvdsContext)
{
    if(lvdsContext->intrCallback->gpif_thread_error)
    {
        switch(errorCode)
        {
            case CY_LVDS_GPIF_THREAD_DIR_ERROR:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_DIR_ERROR, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_WR_OVERFLOW:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_WR_OVERFLOW, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_RD_UNDERRUN:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_RD_UNDERRUN, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_SCK_ACTIVE:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_SCK_ACTIVE, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_ADAP_OVERFLOW:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_ADAP_OVERFLOW, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_ADAP_UNDERFLOW:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_ADAP_UNDERFLOW, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_READ_FORCE_END:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_READ_FORCE_END, lvdsContext->userContext);
                break;
            case CY_LVDS_GPIF_THREAD_READ_BURST_ERR:
                lvdsContext->intrCallback->gpif_thread_error(threadNo, CY_LVDS_GPIF_THREAD_READ_BURST_ERR, lvdsContext->userContext);
                break;
            default:
                break;
        }
    }
}

static void HandleThreadError(uint32_t threadError, uint32_t lvdsError, cy_stc_lvds_context_t *lvdsContext)
{
    cy_en_lvds_gpif_thread_error_t errorCode;

    /* Check if Thread 0 has any error codes reported */
    if(threadError & LVDSSS_LVDS_LVDS_INTR_SET_WD0_THREAD0_ERR_Msk)
    {
       errorCode = (cy_en_lvds_gpif_thread_error_t)((lvdsError &
                    LVDSSS_LVDS_LVDS_ERROR_THREAD0_ERR_CODE_Msk) >>
                    LVDSSS_LVDS_LVDS_ERROR_THREAD0_ERR_CODE_Pos);
        ReportThreadError(errorCode, CY_LVDS_GPIF_THREAD_0, lvdsContext);
    }
    /* Check if Thread 1 has any error codes reported */
    if(threadError & LVDSSS_LVDS_LVDS_INTR_SET_WD0_THREAD1_ERR_Msk)
    {
        errorCode = (cy_en_lvds_gpif_thread_error_t)((lvdsError &
                    LVDSSS_LVDS_LVDS_ERROR_THREAD1_ERR_CODE_Msk) >>
                    LVDSSS_LVDS_LVDS_ERROR_THREAD1_ERR_CODE_Pos);
        ReportThreadError(errorCode, CY_LVDS_GPIF_THREAD_1, lvdsContext);
    }
#if (!LVCMOS_16BIT_SDR)
    /* Check if Thread 2 has any error codes reported */
    if(threadError & LVDSSS_LVDS_LVDS_INTR_SET_WD0_THREAD2_ERR_Msk)
    {
        errorCode = (cy_en_lvds_gpif_thread_error_t)((lvdsError &
                    LVDSSS_LVDS_LVDS_ERROR_THREAD2_ERR_CODE_Msk) >>
                    LVDSSS_LVDS_LVDS_ERROR_THREAD2_ERR_CODE_Pos);
        ReportThreadError(errorCode, CY_LVDS_GPIF_THREAD_2, lvdsContext);
    }
    /* Check if Thread 3 has any error codes reported */
    if(threadError & LVDSSS_LVDS_LVDS_INTR_SET_WD0_THREAD3_ERR_Msk)
    {
        errorCode = (cy_en_lvds_gpif_thread_error_t)((lvdsError &
                    LVDSSS_LVDS_LVDS_ERROR_THREAD3_ERR_CODE_Msk) >>
                    LVDSSS_LVDS_LVDS_ERROR_THREAD3_ERR_CODE_Pos);
        ReportThreadError(errorCode, CY_LVDS_GPIF_THREAD_3, lvdsContext);
    }
#endif /* (!LVCMOS_16BIT_SDR) */
}

static void ReportGpifError(uint32_t smNo, cy_stc_lvds_context_t *lvdsContext)
{
    cy_en_lvds_gpif_error_t gpifError;
    gpifError = (cy_en_lvds_gpif_error_t)lvdsContext->base->GPIF[smNo].GPIF_ERROR;
    switch(gpifError)
    {
    case CY_LVDS_GPIF_ERROR_IN_ADDR_OVER_WRITE:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_IN_ADDR_OVER_WRITE, lvdsContext->userContext);
        break;
    case CY_LVDS_GPIF_ERROR_EG_ADDR_NOT_VALID:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_EG_ADDR_NOT_VALID, lvdsContext->userContext);
        break;
    case CY_LVDS_GPIF_ERROR_DMA_DATA_RD_ERROR:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_DMA_DATA_RD_ERROR, lvdsContext->userContext);
        break;
    case CY_LVDS_GPIF_ERROR_DMA_DATA_WR_ERROR:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_DMA_DATA_WR_ERROR, lvdsContext->userContext);
        break;
    case CY_LVDS_GPIF_ERROR_DMA_ADDR_RD_ERROR:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_DMA_ADDR_RD_ERROR, lvdsContext->userContext);
        break;
    case CY_LVDS_GPIF_ERROR_DMA_ADDR_WR_ERROR:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_DMA_ADDR_WR_ERROR, lvdsContext->userContext);
        break;
    case CY_LVDS_GPIF_ERROR_INVALID_STATE_ERROR:
        lvdsContext->intrCallback->gpif_error(smNo, CY_LVDS_GPIF_ERROR_INVALID_STATE_ERROR, lvdsContext->userContext);
        break;
    default:
        break;
    }
}

static void HandleGpifInterrupts(uint32_t gpifIntr, cy_stc_lvds_context_t *lvdsContext)
{
    uint8_t i;
    uint32_t activeGpifIntr;
    for(i = 0; i < CY_LVDS_MAX_GPIF_INSTANCE; i++)
    {
        activeGpifIntr = (lvdsContext->base->GPIF[i].GPIF_INTR &
                        lvdsContext->base->GPIF[i].GPIF_INTR_MASK);
        lvdsContext->base->GPIF[i].GPIF_INTR = activeGpifIntr;
        if(activeGpifIntr != 0)
        {
            if(lvdsContext->intrCallback->gpif_events != NULL)
            {
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_GPIF_DONE_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_END_STATE, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_GPIF_FSM_INTR_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_SM_INTERRUPT, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_SWITCH_TIMEOUT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_SWITCH_TIMEOUT, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_CRC_ERROR_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_CRC_ERROR, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_ADDR_COUNT_HIT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_ADDR_COUNTER, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_DATA_COUNT_HIT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_DATA_COUNTER, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_CTRL_COUNT_HIT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_CTRL_COUNTER, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_ADDR_COMP_HIT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_ADDR_COMP, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_DATA_COMP_HIT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_DATA_COMP, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_CTRL_COMP_HIT_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_CTRL_COMP, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_WAVEFORM_BUSY_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_WAVEFORM_BUSY, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_EG_DATA_EMPTY_BIT0_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_EG_DATA_EMPTY_TH0, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_EG_DATA_EMPTY_BIT1_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_EG_DATA_EMPTY_TH1, lvdsContext->userContext);
                }
#if (!LVCMOS_16BIT_SDR)
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_EG_DATA_EMPTY_BIT2_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_EG_DATA_EMPTY_TH2, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_EG_DATA_EMPTY_BIT3_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_EG_DATA_EMPTY_TH3, lvdsContext->userContext);
                }
#endif /* (!LVCMOS_16BIT_SDR) */
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_IN_DATA_VALID_BIT0_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_IN_DATA_VALID_TH0, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_IN_DATA_VALID_BIT1_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_IN_DATA_VALID_TH1, lvdsContext->userContext);
                }
#if (!LVCMOS_16BIT_SDR)
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_IN_DATA_VALID_BIT2_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_IN_DATA_VALID_TH2, lvdsContext->userContext);
                }
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_IN_DATA_VALID_BIT3_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_IN_DATA_VALID_TH3, lvdsContext->userContext);
                }
#endif /* (!LVCMOS_16BIT_SDR) */
                if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_INVLD_CMD_DET_Msk)
                {
                    lvdsContext->intrCallback->gpif_events(i, CY_LVDS_GPIF_EVT_CONTROL_BYTE_INVALID, lvdsContext->userContext);
                }
            }
            if(activeGpifIntr & LVDSSS_LVDS_GPIF_GPIF_INTR_GPIF_ERR_Msk)
            {
                if(lvdsContext->intrCallback->gpif_error != NULL)
                {
                    ReportGpifError(i, lvdsContext);
                }
            }
        }
    }
}

static void HandlePhyInterrupts(uint32_t phyIntr, cy_stc_lvds_context_t *lvdsContext)
{
    uint8_t i;
    uint32_t activePhyIntr;
    for(i = 0; i < CY_LVDS_MAX_PHY_INSTANCE; i++)
    {
        activePhyIntr = (lvdsContext->base->AFE[i].PHY_INTR &
                            lvdsContext->base->AFE[i].PHY_INTR_MASK);
        lvdsContext->base->AFE[i].PHY_INTR = (lvdsContext->base->AFE[i].PHY_INTR &
                                                    activePhyIntr);
        if(activePhyIntr != 0)
        {
            if(lvdsContext->intrCallback->phy_events != NULL)
            {
                if(activePhyIntr & LVDSSS_LVDS_AFE_PHY_INTR_GPIO_INTR_Msk)
                {
                    lvdsContext->intrCallback->phy_events(i, CY_LVDS_PHY_GPIO_INTR_PORT, lvdsContext->userContext);
                }
                if(activePhyIntr & LVDSSS_LVDS_AFE_PHY_INTR_MONITOR_ADJUST_FAIL_Msk)
                {
                    lvdsContext->intrCallback->phy_events(i, CY_LVDS_PHY_MONITOR_FAIL, lvdsContext->userContext);
                }
                if(activePhyIntr & LVDSSS_LVDS_AFE_PHY_INTR_PLL_LOCK_LOST_Msk)
                {
                    lvdsContext->intrCallback->phy_events(i, CY_LVDS_PHY_PLL_LOCK_LOST, lvdsContext->userContext);
                }
                if(activePhyIntr & LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_LOST_Msk)
                {
                    lvdsContext->intrCallback->phy_events(i, CY_LVDS_PHY_MDLL_LOCK_LOST, lvdsContext->userContext);
                }
            }
        }
    }
}

static void HandleThreadEvents(cy_en_lvds_gpif_thread_no_t threadNo, uint32_t threadEvent,
                                bool setClear, cy_stc_lvds_context_t *lvdsContext)
{
    uint8_t flagNo;
    if(setClear)
    {
        switch(threadNo)
        {
            case CY_LVDS_GPIF_THREAD_0:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH0_HDR_FLGS_SET, threadEvent);
            break;
            case CY_LVDS_GPIF_THREAD_1:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH1_HDR_FLGS_SET, threadEvent);
            break;
#if (!LVCMOS_16BIT_SDR)
            case CY_LVDS_GPIF_THREAD_2:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH2_HDR_FLGS_SET, threadEvent);
            break;
            case CY_LVDS_GPIF_THREAD_3:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH3_HDR_FLGS_SET, threadEvent);
            break;
#endif /* (!LVCMOS_16BIT_SDR) */
        }
        for(flagNo = 0; flagNo < 4; flagNo++)
        {
            if((threadEvent >> flagNo) & (0x1))
            {
                switch(flagNo)
                {
                    case 0:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG0_SET, lvdsContext->userContext);
                    break;
                    case 1:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG1_SET, lvdsContext->userContext);
                    break;
#if (!LVCMOS_16BIT_SDR)
                    case 2:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG2_SET, lvdsContext->userContext);
                    break;
                    case 3:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG3_SET, lvdsContext->userContext);
                    break;
#endif /* (!LVCMOS_16BIT_SDR) */
                }
            }
        }
    }
    else
    {
        switch(threadNo)
        {
            case CY_LVDS_GPIF_THREAD_0:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH0_HDR_FLGS_CLR, threadEvent);
            break;
            case CY_LVDS_GPIF_THREAD_1:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH1_HDR_FLGS_CLR, threadEvent);
            break;
#if (!LVCMOS_16BIT_SDR)
            case CY_LVDS_GPIF_THREAD_2:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH2_HDR_FLGS_CLR, threadEvent);
            break;
            case CY_LVDS_GPIF_THREAD_3:
            threadEvent = _FLD2VAL(LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH3_HDR_FLGS_CLR, threadEvent);
            break;
#endif /* (!LVCMOS_16BIT_SDR) */
        }
        for(flagNo = 0; flagNo < 4; flagNo++)
        {
            if((threadEvent >> flagNo) & (0x1))
            {
                switch(flagNo)
                {
                    case 0:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG0_CLR, lvdsContext->userContext);
                    break;
                    case 1:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG1_CLR, lvdsContext->userContext);
                    break;
#if (!LVCMOS_16BIT_SDR)
                    case 2:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG2_CLR, lvdsContext->userContext);
                    break;
                    case 3:
                    lvdsContext->intrCallback->gpif_thread_event(threadNo, CY_LVDS_GPIF_HDR_FLG3_CLR, lvdsContext->userContext);
                    break;
#endif /* (!LVCMOS_16BIT_SDR) */
                }
            }
        }
    }
}

/*******************************************************************************
* Function Name: Cy_LVDS_IrqHandler
****************************************************************************//**
*
* LVDS Interrupt handler.
*
* \param base
* Pointer to the LVDS register base address.
*
* \param lvdsContext
* LVDS driver context structure.
*
*******************************************************************************/

void Cy_LVDS_IrqHandler(LVDSSS_LVDS_Type *base, cy_stc_lvds_context_t *lvdsContext)
{
    uint32_t activeIntr;
    uint32_t lvdsError;

    if ((base->LVDS_INTR_MASKED_WD0) || (base->LVDS_INTR_MASKED_WD1))
    {
        /* Check for active interrupts for word 0 */
        activeIntr = base->LVDS_INTR_MASKED_WD0;

        if(activeIntr != 0)
        {
            /* Fetch LVDS_ERROR before clearing LVDS_INTR_WD0 */
            lvdsError = lvdsContext->base->LVDS_ERROR;

            /* Clear Active Interrupt */
            base->LVDS_INTR_WD0 = activeIntr;
            if(lvdsContext->intrCallback != NULL)
            {
                if((activeIntr & LVDSSS_LVDS_LVDS_INTR_MASK_WD0_GPIF0_INTERRUPT_Msk) ||
                    (activeIntr & LVDSSS_LVDS_LVDS_INTR_MASK_WD0_GPIF1_INTERRUPT_Msk))
                {
                    HandleGpifInterrupts(activeIntr, lvdsContext);
                }
                if((activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_PHY_LINK0_INTERRUPT_Msk) ||
                    (activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_PHY_LINK1_INTERRUPT_Msk))
                {
                    HandlePhyInterrupts(activeIntr, lvdsContext);
                }

                if((activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_THREAD0_ERR_Msk) ||
                    (activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_THREAD1_ERR_Msk) ||
                    (activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_THREAD2_ERR_Msk) ||
                    (activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_THREAD3_ERR_Msk))
                {
                    HandleThreadError(activeIntr, lvdsError, lvdsContext);
                }
                if(lvdsContext->intrCallback->phy_events != NULL)
                {
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_FF_OVER_FLOW_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_FF_OVERFLOW, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_FF_OVER_FLOW_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_FF_OVERFLOW, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_TRAINING_DONE_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_TRAINING_DONE, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_TRAINING_DONE_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_TRAINING_DONE, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_TRAINING_BLK_DETECTED_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_LNK_TRAIN_BLK_DET, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_TRAINING_BLK_DETECTED_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_LNK_TRAIN_BLK_DET, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_TRAINING_BLK_DET_FAILD_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_LNK_TRAIN_BLK_DET_FAIL, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_TRAINING_BLK_DET_FAILD_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_LNK_TRAIN_BLK_DET_FAIL, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_L1_ENTRY_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_L1_ENTRY, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_L1_ENTRY_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_L1_ENTRY, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_L1_EXIT_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_L1_EXIT, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_L1_EXIT_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_L1_EXIT, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK0_L3_ENTRY_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(0, CY_LVDS_PHY_L3_ENTRY, lvdsContext->userContext);
                    }
                    if(activeIntr & LVDSSS_LVDS_LVDS_INTR_WD0_LNK1_L3_ENTRY_Msk)
                    {
                        lvdsContext->intrCallback->phy_events(1, CY_LVDS_PHY_L3_ENTRY, lvdsContext->userContext);
                    }
                }
            }
        }

        /* Check for active interrupts for word 1 */
        activeIntr = base->LVDS_INTR_MASKED_WD1;
        if(activeIntr != 0)
        {
            /* Clear Active Interrupt */
            base->LVDS_INTR_WD1 = activeIntr;
            if(lvdsContext->intrCallback->gpif_thread_event != NULL)
            {
                /* Check if any of the clear flag bit for Thread 0, 1, 2, 3 is asserted*/
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH0_HDR_FLGS_CLR_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_0, activeIntr, 0, lvdsContext);
                }
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH1_HDR_FLGS_CLR_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_1, activeIntr, 0, lvdsContext);
                }
#if (!LVCMOS_16BIT_SDR)
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH2_HDR_FLGS_CLR_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_2, activeIntr, 0, lvdsContext);
                }
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH3_HDR_FLGS_CLR_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_3, activeIntr, 0, lvdsContext);
                }
#endif /* (!LVCMOS_16BIT_SDR) */

                /* Check if any of the set flag bit for Thread 0, 1, 2, 3 is asserted*/
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH0_HDR_FLGS_SET_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_0, activeIntr, 1, lvdsContext);
                }
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH1_HDR_FLGS_SET_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_1, activeIntr, 1, lvdsContext);
                }
#if (!LVCMOS_16BIT_SDR)
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH2_HDR_FLGS_SET_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_2, activeIntr, 1, lvdsContext);
                }
                if(activeIntr & LVDSSS_LVDS_LVDS_INTR_MASKED_WD1_TH3_HDR_FLGS_SET_Msk)
                {
                    HandleThreadEvents(CY_LVDS_GPIF_THREAD_3, activeIntr, 1, lvdsContext);
                }
#endif /* (!LVCMOS_16BIT_SDR) */
            }
        }
    }
}


/*******************************************************************************
* Function Name: Cy_LVDS_LowPowerIrqHandler
****************************************************************************//**
*
* LVDS Low power interrupt handler.
*
* \param base
* Pointer to the LVDS register base address.
*
* \param lvdsContext
* LVDS driver context structure.
*
*******************************************************************************/
void Cy_LVDS_LowPowerIrqHandler(LVDSSS_LVDS_Type * base, cy_stc_lvds_context_t *lvdsContext)
{
    uint32_t activeIntr;
    if (base->LVDS_LOW_PWR_INTR.LVDS_WAKEUP_INTR_MASKED)
    {
        activeIntr = base->LVDS_LOW_PWR_INTR.LVDS_WAKEUP_INTR_MASKED;

        base->LVDS_LOW_PWR_INTR.LVDS_WAKEUP_INTR = activeIntr;
        if(lvdsContext->intrCallback->low_power_events != NULL)
        {
            if(activeIntr & LVDSSS_LVDS_LVDS_LOW_PWR_INTR_LVDS_WAKEUP_INTR_LNK0_L3_EXIT_Msk)
            {
                lvdsContext->intrCallback->low_power_events(CY_LVDS_LOW_POWER_LNK0_L3_EXIT, lvdsContext->userContext);
            }
            if(activeIntr & LVDSSS_LVDS_LVDS_LOW_PWR_INTR_LVDS_WAKEUP_INTR_LNK1_L3_EXIT_Msk)
            {
                lvdsContext->intrCallback->low_power_events(CY_LVDS_LOW_POWER_LNK1_L3_EXIT, lvdsContext->userContext);
            }
        }
    }
}

#if (!LVCMOS_16BIT_SDR)
/*******************************************************************************
* Function Name: Cy_LVDS_SetLvcmosDDRClockPhase
****************************************************************************//**
*
* Select the DLL clock phase to be used on the receiver side when the Sensor
* Interface Port (SIP) is configured to work in LVCMOS DDR mode.
*
* \param sipNo
* Sensor Interface Port number.
*
* \param clkPhase
* Selected clock phase value in the range of 0 to 15.
*
*******************************************************************************/
void Cy_LVDS_SetLvcmosDDRClockPhase (uint8_t sipNo, uint8_t clkPhase)
{
    /* Store the desired clock phase value if it is in the valid range. */
    if ((sipNo < CY_LVDS_MAX_PHY_INSTANCE) && (clkPhase < 16)) {
        glLvcmosClkPhaseSel[sipNo] = clkPhase;
    }
}
#endif /* (!LVCMOS_16BIT_SDR) */

/*******************************************************************************
* Function Name: Cy_LVDS_L3_Entry
****************************************************************************//**
*
* Handle entry into the L3 low power state for one of Sensor Interface Ports.
*
* \param base
* Pointer to SIP IP register set.
*
* \param lvdsContext
* Pointer to driver context structure.
*
* \param sipNo
* Sensor Interface Port number.
*******************************************************************************/
void Cy_LVDS_L3_Entry (LVDSSS_LVDS_Type *base,
                       cy_stc_lvds_context_t *lvdsContext,
                       uint8_t sipNo)
{
    /*
       DLL_M_CONFIG.EN =0
       PLL_CONFIG.PLL_EN =0
       PLL_CONFIG.PLL_SUPPLY_EN = 0
       REG_1P25.ENABLE = 0
       REG_1P25.USE_REG = 0
       LICIO_VSSIO_IREF.EN = 0
       LICIO_VCCD_V1P1.EN = 0
     */

    /*
       a) Disables all thread's by programming
          "GPIF_THREAD_CONFIG.ENABLE_THREAD_CTLR" to 0
       b) Suspend the sockets
       c) Disables DLL first, followed by PLL
       d) Asserts active reset
          Programming soft reset bits (LVDS_CTL.LINK_ENABLE, LVDS_CTL.PHY_ENABLE) to 0
     */

    if ((base == NULL) || (lvdsContext == NULL)) {
        DBG_LVDS_ERR("L3_Entry: Invalid parameters\r\n");
        return;
    }

    /*  Mark the GPIF state machine configuration invalid. */
    base->GPIF[sipNo].GPIF_WAVEFORM_CTRL_STAT &= ~LVDSSS_LVDS_GPIF_GPIF_WAVEFORM_CTRL_STAT_WAVEFORM_VALID_Msk;

    /* Disable all threads. */
    if (sipNo == 0)
    {
        base->THREAD[0].GPIF_THREAD_CONFIG &= ~LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR_Msk;
        base->THREAD[1].GPIF_THREAD_CONFIG &= ~LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR_Msk;
    }

#if (!LVCMOS_16BIT_SDR)
    if ((lvdsContext->phyConfigP0->wideLink == true) || (sipNo == 1))
    {
        base->THREAD[2].GPIF_THREAD_CONFIG &= ~LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR_Msk;
        base->THREAD[3].GPIF_THREAD_CONFIG &= ~LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR_Msk;
    }
#endif /* (!LVCMOS_16BIT_SDR) */

    base->AFE[sipNo].PHY_TRAIN_CONFIG &= ~LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_EN_Msk;

    base->AFE[sipNo].DLL_M_CONFIG &=  ~LVDSSS_LVDS_AFE_DLL_M_CONFIG_EN_Msk;
    base->AFE[sipNo].PLL_CONFIG   &=  ~LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_EN_Msk;
    Cy_SysLib_DelayUs(2);
    base->AFE[sipNo].PLL_CONFIG   &=  ~LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_SUPPLY_EN_Msk;

    base->AFE[sipNo].REG_1P25  &= ~(LVDSSS_LVDS_AFE_REG_1P25_ENABLE_Msk | LVDSSS_LVDS_AFE_REG_1P25_USE_REG_Msk);

    base->AFE[sipNo].LICIO_VSSIO_IREF      &= ~LVDSSS_LVDS_AFE_LICIO_VSSIO_IREF_EN_Msk;
    base->AFE[sipNo].LICIO_VCCD_V1P1       &= ~LVDSSS_LVDS_AFE_LICIO_VCCD_V1P1_EN_Msk;

    /* Disable the LINK and AFE blocks once L3 entry has been processed on all active ports. */
    if (((sipNo == 0) && (lvdsContext->phyConfigP0->wideLink != true)) || (sipNo == 1))
    {
        base->CTL &= ~(LVDSSS_LVDS_CTL_LINK_ENABLED_Msk | LVDSSS_LVDS_CTL_PHY_ENABLED_Msk);
    }

    DBG_LVDS_INFO("L3_Entry Done\r\n");
}

/*******************************************************************************
* Function Name: Cy_LVDS_L3_Exit
****************************************************************************//**
*
* Handle exit from L3 low power state for one of Sensor Interface Ports.
*
* \param base
* Pointer to SIP IP register set.
*
* \param lvdsContext
* Pointer to driver context structure.
*
* \param sipNo
* Sensor Interface Port number.
*
* \return
* Status of the L3 exit operation.
*******************************************************************************/
cy_en_lvds_status_t Cy_LVDS_L3_Exit (LVDSSS_LVDS_Type *base,
                                     cy_stc_lvds_context_t *lvdsContext,
                                     uint8_t sipNo)
{
    cy_stc_lvds_phy_config_t *pPhyConfig = NULL;

    /*
       LICIO_VCCD_V1P1.EN = 1
       LICIO_VSSIO_IREF.EN = 1
       REG_1P25.ENABLE = 1
       PLL_CONFIG.PLL_SUPPLY_EN = 1
       Wait for 8usec
       PLL_CONFIG.PLL_EN = 1
       Wait for PLL Lock
       Poll PLL_STATUS.PLL_LOCK for 1
       DLL_M_CONFIG.EN = 1
       Wait for DLL Lock
       Poll DLL_M_STATUS.DLL_LOCK for 1
       PHY_TRAIN_CONFIG.TRAIN_EN = 1
     */

    /*
       a) de-assert active reset
          Programming soft reset bits (LVDS_CTL.LINK_ENABLE, LVDS_CTL.PHY_ENABLE) to 1.
       b) Enable sockets
       c) Enable threads
       d) Enable clocks (enabling PLL and DLL)
       e) Re-initiates link training
       f) Enables the GPIF_WAVEFORM_SWITCH.SWITCH_NOW
     */
    uint32_t timeoutCount = 0;
    cy_en_lvds_status_t status = CY_LVDS_SUCCESS;

    if ((base == NULL) || (lvdsContext == NULL))
    {
        DBG_LVDS_ERR("L3_Exit: Invalid parameters\r\n");
        return CY_LVDS_BAD_PARAMETER;
    }

    if (sipNo == 0)
    {
        pPhyConfig = lvdsContext->phyConfigP0;
    }
    else
    {
        pPhyConfig = lvdsContext->phyConfigP1;
    }

    /* Enable IP block once all active ports are out of L3. */
    if (((sipNo == 1) && (lvdsContext->phyConfigP0->wideLink != true)) || (sipNo == 0))
    {
        /* TBD : LVDSSS_LVDS_CTL_IP_ENABLED ?   */
        base->CTL |= _BOOL2FLD(LVDSSS_LVDS_CTL_PHY_ENABLED,  1u) |
                     _BOOL2FLD(LVDSSS_LVDS_CTL_LINK_ENABLED, 1u);
    }

    base->AFE[sipNo].LICIO_VCCD_V1P1  |= _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VCCD_V1P1_EN, 1u);
    base->AFE[sipNo].LICIO_VSSIO_IREF |= _BOOL2FLD(LVDSSS_LVDS_AFE_LICIO_VSSIO_IREF_EN, 1u);
    Cy_SysLib_DelayUs(2);

    base->AFE[sipNo].REG_1P25         |= _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_ENABLE, 1u) |
                                         _BOOL2FLD(LVDSSS_LVDS_AFE_REG_1P25_USE_REG, 1u);
    Cy_SysLib_DelayUs(2);

    base->AFE[sipNo].PLL_CONFIG       |= _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_SUPPLY_EN, 1u);
    Cy_SysLib_DelayUs(8);
    base->AFE[sipNo].PLL_CONFIG       |= _BOOL2FLD(LVDSSS_LVDS_AFE_PLL_CONFIG_PLL_EN, 1u);

#if (!LVCMOS_16BIT_SDR)
    if (pPhyConfig->modeSelect != CY_LVDS_PHY_MODE_LVCMOS)
    {
        timeoutCount = 0;
        while(!(base->AFE[sipNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_PLL_LOCK_ACQUIRED_Msk))
        {
            Cy_SysLib_Delay(1);
            timeoutCount++;
            if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
            {
                status = CY_LVDS_TIMEOUT_ERROR;
                DBG_LVDS_ERR("L3_Exit: PLL lock timed out for Port: %d\r\n", sipNo);
                return status;
            }
        }

        base->AFE[sipNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_PLL_LOCK_ACQUIRED_Msk;
        status = CY_LVDS_SUCCESS;
    }
#endif /* (!LVCMOS_16BIT_SDR) */

    base->AFE[sipNo].DLL_M_CONFIG |= _BOOL2FLD(LVDSSS_LVDS_AFE_DLL_M_CONFIG_EN, 1u);
    timeoutCount = 0;
    while(!(base->AFE[sipNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk))
    {
        Cy_SysLib_Delay(1);
        timeoutCount++;
        if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
        {
            status = CY_LVDS_TIMEOUT_ERROR;
            DBG_LVDS_ERR("L3_Exit: LVDS DLL lock timed out for Port: %d\r\n", sipNo);
            return status;
        }
    }

    base->AFE[sipNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_MDLL_LOCK_ACQUIRED_Msk;

    /* In Case of LVCMOS external phyTrainingPattern not Required */
    if (pPhyConfig->modeSelect == CY_LVDS_PHY_MODE_LVCMOS)
    {
        base->AFE[sipNo].PHY_TRAIN_CONFIG   |= _BOOL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_EN, 1u);
        base->AFE[sipNo].PHY_GENERAL_CONFIG |= _VAL2FLD(LVDSSS_LVDS_AFE_PHY_GENERAL_CONFIG_DESKEW_ALGORITHM, CY_LVDS_PHY_DESKEW_SLOW);

        timeoutCount = 0;
        while (!(base->AFE[sipNo].PHY_INTR & LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk))
        {
            Cy_SysLib_Delay(1);
            timeoutCount++;
            if (timeoutCount >= CY_LVDS_MAX_TIMEOUT_COUNT)
            {
                status = CY_LVDS_TIMEOUT_ERROR;
                DBG_LVDS_ERR("L3_Exit: DDR DESKEW timed out for Port: %d\r\n", sipNo);
                return status;
            }
        }

        base->AFE[sipNo].PHY_INTR = LVDSSS_LVDS_AFE_PHY_INTR_DESKEW_COMPLETED_Msk;
        status = CY_LVDS_SUCCESS;
        DBG_LVDS_INFO("L3_Exit: DDR Deskew complete for Port: %d\r\n", sipNo);
    }
#if (!LVCMOS_16BIT_SDR)
    else  /* In case of LVDS external phyTrainingPattern required */
    {

        base->AFE[sipNo].PHY_TRAIN_CONFIG &= ~LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_SEQ_Msk;
        base->AFE[sipNo].PHY_TRAIN_CONFIG  = _VAL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_SEQ, pPhyConfig->phyTrainingPattern) |
                                             _VAL2FLD(LVDSSS_LVDS_AFE_PHY_TRAIN_CONFIG_TRAIN_CYCLES_NO,100);
    }
#endif /* (!LVCMOS_16BIT_SDR) */

    /* Enable Thread in case of LVCMOS */
    if (pPhyConfig->modeSelect == CY_LVDS_PHY_MODE_LVCMOS)
    {
        if (sipNo == 0)
        {
            base->THREAD[0].GPIF_THREAD_CONFIG |= _BOOL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR, 1u);
            base->THREAD[1].GPIF_THREAD_CONFIG |= _BOOL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR, 1u);
        }
#if (!LVCMOS_16BIT_SDR)
        if ((lvdsContext->phyConfigP0->wideLink == true) || (sipNo == 1))
        {
            base->THREAD[2].GPIF_THREAD_CONFIG |= _BOOL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR, 1u);
            base->THREAD[3].GPIF_THREAD_CONFIG |= _BOOL2FLD(LVDSSS_LVDS_THREAD_GPIF_THREAD_CONFIG_ENABLE_THREAD_CTLR, 1u);
        }
#endif /* (!LVCMOS_16BIT_SDR) */
    }

    return status;
}

#if defined(__cplusplus)
}
#endif

#endif /* CY_IP_MXS40LVDS2USB32SS */

/* [] END OF FILE */
