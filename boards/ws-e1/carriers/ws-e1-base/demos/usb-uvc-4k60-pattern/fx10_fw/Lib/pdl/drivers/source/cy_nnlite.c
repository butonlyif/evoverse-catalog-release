/***************************************************************************//**
* \file  cy_nnlite.c
* \version 1.0
*
*
* Provides an API implementation of the nn lite accelerator driver.
*
********************************************************************************
* \copyright
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
#if defined (CY_IP_MXNNLITE)

#include "cy_nnlite.h"

#if defined(__cplusplus)
extern "C" {
#endif

#define  STATUS_REG_MASK (MXNNLITE_1_0_STATUS_BUSY_STATUS_Msk | \
                     MXNNLITE_1_0_STATUS_ACTIVATIONSTREAMERDONE_Msk)


/*****************************************************************************/
/* Function implementation - global ('extern') and local ('static')          */
/*****************************************************************************/

/**
 *****************************************************************************
 ** nnlite driver init function, validate context structure and
 ** set driver to init state
 **
 ** [in]  context     pointer to the driver context structure
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_Init(NNLITE_Type *nnlite, cy_nnlite_context_t *context)
{

  cy_en_nnlite_status_t status;

  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }

  else if (context->nnliteState != CY_NNLITE_DEINIT)
  {
    status = CY_NNLITE_BAD_STATE;
  }
  else
  {
    context->nnliteState = CY_NNLITE_INIT;
    status = CY_NNLITE_SUCCESS;
  }

  return status;
}

/**
 *****************************************************************************
 ** nnlite driver deinit function check's for pending or ongoing
 ** operation and set driver state to deinit
 **
 **
 ** [in]  nnlite      base pointer of register map.
 **
 ** [in]  context     pointer to the driver context structure
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_DeInit(NNLITE_Type *nnlite, cy_nnlite_context_t *context)
{
  cy_en_nnlite_status_t status;
  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else if ((context->nnliteState == CY_NNLITE_OP_STARTED) ||
      (context->nnliteState == CY_NNLITE_DEINIT))
 {
    /* operation is going on, can not deinit*/
    status = CY_NNLITE_BAD_STATE;
  }
  else
  {
    context->nnliteState = CY_NNLITE_DEINIT;
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}

/**
 *****************************************************************************
 ** nnlite start operation, streamer should should be configured before
 ** calling this function, this function will write to start bit in CMD MEMIO
 **
 **
 ** [in]  nnlite      base pointer of register map.
 **
 ** [in]  context     pointer to the driver context structure
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_Start(NNLITE_Type *nnlite, cy_nnlite_context_t *context)
{
  cy_en_nnlite_status_t status;

  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else if(context->nnliteState != CY_NNLITE_CONFIG_STATE)
  {
    status = CY_NNLITE_BAD_STATE;
  }
  else
  {
    context->opStatus = CY_NNLITE_SUCCESS;
    nnlite->CMD |= _VAL2FLD(MXNNLITE_1_0_CMD_START_CMD, 1);
    context->nnliteState = CY_NNLITE_OP_STARTED;
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}

/**
 *****************************************************************************
 ** nnlite stop/abort operation, can be used to stop/abort current operation
 ** or to reset all configuration, API write abort in CMD MEMIO which will
 ** reset all the registers
 **
 ** [in]  nnlite      base pointer of register map.
 **
 ** [in]  context     pointer to the driver context structure
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_Stop(NNLITE_Type *nnlite, cy_nnlite_context_t *context)
{
  cy_en_nnlite_status_t status;
  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->CMD |= _VAL2FLD(MXNNLITE_1_0_CMD_ABORT_CMD, 1);
    context->nnliteState = CY_NNLITE_INIT;
    status = CY_NNLITE_SUCCESS;
  }
  return status;

}

/**
 *****************************************************************************
 ** nnlite get nnlite operation status, can be used to poll operation status
 **
 ** [in]  nnlite    base pointer of register map.
 **
 ** [out] opStatus    nnlite last operation status
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_GetOperationStatus(NNLITE_Type *nnlite, uint32_t *opStatus)
{
  cy_en_nnlite_status_t status = CY_NNLITE_SUCCESS;
  if ((NULL == nnlite) || (NULL == opStatus))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    *opStatus = (nnlite->STATUS & STATUS_REG_MASK);
  }

  return status;
}

/**
 *****************************************************************************
 **  nnlite set Activation Type Control
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  nnLayer    NN Layer operation type
 **
 **  [in]  actEn      Output Activation enable
 **
 **  [in]  actDataSize    Activation size
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_ActivationTypeCtrl(NNLITE_Type *nnlite,
                        cy_en_nnlite_layer_t nnLayer, bool actEn,
                        cy_en_nnlite_activation_size_t actDataSize)
{
  cy_en_nnlite_status_t status;
  if ((NULL == nnlite) || (nnLayer > CY_NNLITE_CONV_LAYER))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    /* reset to 0 */
    nnlite->NNLAYER_ACTIVATION_TYPE_CTL = 0;
    nnlite->NNLAYER_ACTIVATION_TYPE_CTL =
      _VAL2FLD(MXNNLITE_1_0_NNLAYER_ACTIVATION_TYPE_CTL_NNLAYER_TYPE_CTL, nnLayer) |
      _VAL2FLD(MXNNLITE_1_0_NNLAYER_ACTIVATION_TYPE_CTL_ACTIVATION_FUNC_EN, actEn) |
      _VAL2FLD(MXNNLITE_1_0_NNLAYER_ACTIVATION_TYPE_CTL_ACTIVATION_SIZE_CTL, actDataSize);
    status = CY_NNLITE_SUCCESS;
  }

  return status;

}


/**
 *****************************************************************************
 **  nnlite streamer buffer base set
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  strmId     streamer id
 **
 **  [in]  baseAddr   base address of buffer
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_StreamerBaseAddrSet(NNLITE_Type *nnlite,
                        cy_en_nnlite_streamer_id_t strmId, const void *baseAddr)
{
  cy_en_nnlite_status_t status = CY_NNLITE_SUCCESS;
  if ((NULL == nnlite) || (NULL == baseAddr) ||
      (strmId > CY_NNLITE_OUT_STREAMER))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    switch(strmId)
    {
      case CY_NNLITE_WEIGHT_STREAMER:
        nnlite->WEIGHTSTREAMERBASEADDR = cy_CbusRemapAddr(baseAddr);
        break;
      case CY_NNLITE_BIAS_STREAMER:
        nnlite->BIASBASEADDR = cy_CbusRemapAddr(baseAddr);
        break;
      case CY_NNLITE_ACTIVATION_STREAMER:
        nnlite->ACTIVATIONSTREAMERBASEADDR = cy_AhbRemapAddr(baseAddr);
        break;
      case CY_NNLITE_OUT_STREAMER:
        nnlite->OUTSTREAMERBASEADDR = (uint32_t)baseAddr;
        break;
      default:
        status = CY_NNLITE_BAD_PARAM;
        break;
    }
  }

  return status;
}

/**
 *****************************************************************************
 **  parse sparsity map, API will  parse sparsity bit map and update non
 **  zero weight pointer, sparsity bit map address and weight pointer in
 **  sparCfg, sparsity configuration structure
 **
 **  [in]  nnlite base pointer of register map.
 **
 **  [in]  sparsitybaseAddr sparsity map base address
 **
 **  [in]  activationRepeats  activation streamer repeat count
 **
 **  [in]  sparseBitMapLen  sparsity bit map length
 **
 **  [out]  sparCfg sparsity configuration
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_ParseSparsity(NNLITE_Type *nnlite, const void *sparsitybaseAddr,
    uint32_t activationRepeats, uint32_t sparseBitMapLen, cy_nnlite_sparsity_cfg_t *sparCfg)
{
  cy_en_nnlite_status_t status;
  uint32_t nonZeroWtLen;

  if ((NULL == nnlite) || (NULL == sparCfg) || (NULL == sparsitybaseAddr))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    /* nonzero wt pointer each of length 2 bytes */
    nonZeroWtLen =  activationRepeats * 2UL;
    sparCfg->nonZeroWtAddr      = (uint32_t)sparsitybaseAddr;
    sparCfg->sparsityBitMapAddr = (uint32_t)sparsitybaseAddr + nonZeroWtLen;

    /* wt pointer == sparsebase + non zero wt pointer len +
     * len of sparse bit map
     * */
    sparCfg->wtAddr = (uint32_t)sparsitybaseAddr + nonZeroWtLen + sparseBitMapLen;
    status = CY_NNLITE_SUCCESS;
  }

  return status;
}

/**
 *****************************************************************************
 **  configure sparsity from valid cy_nnlite_sparsity_cfg
 **  write non zero wt pointer and sparsity bit map MEMIO and enable sparsity
 **  in streamer mode MEMIO
 **
 **  [in]  nnlite base pointer of register map.
 **
 **  [in]  cy_nnlite_sparsity_cfg_t sparsity configuration
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_SparsityCfg(NNLITE_Type *nnlite, cy_nnlite_sparsity_cfg_t *sparCfg)
{
  cy_en_nnlite_status_t status;

  if ((NULL == nnlite) || (NULL == sparCfg))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->NONZEROWEIGHTSPOINTER = cy_CbusRemapAddr((uint32_t *)sparCfg->nonZeroWtAddr);
    nnlite->ACTIVATIONSTREAMERSPARSITYMAPBASEADDR = cy_CbusRemapAddr((uint32_t *)sparCfg->sparsityBitMapAddr);
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}
/**
 *****************************************************************************
 ** nnlite enable sparsity in streamer mode MEMIO
 **
 **  [in]  nnlite base pointer of register map.
 **
 **  [in] sparsityEn sparsity enable
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_SparsityEnable(NNLITE_Type *nnlite, bool sparsityEn)
{
    cy_en_nnlite_status_t status;
    if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    if (sparsityEn)
    {
        nnlite->STREAMERMODES |=
          _VAL2FLD(MXNNLITE_1_0_STREAMERMODES_ACTIVATIONSTREAMERSPARSEEN, 1);
    }
    else
    {
      nnlite->STREAMERMODES &=
        ~(_VAL2FLD(MXNNLITE_1_0_STREAMERMODES_ACTIVATIONSTREAMERSPARSEEN, 1));
    }
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}
/**
 *****************************************************************************
 **  nnlite activation streamer configuration set, API will configure
 **  parameters for activation streamer
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  context     pointer to the driver context structure
 **
 **  [in]  filterWidth  filter width
 **
 **  [in]  filterHeight  filter height
 **
 **  [in]  activationRepeats  activation streamer repeat count
 **
 **  [in]  inputWidth  input activation Width
 **
 **  [in]  inputHeight  input activation Height
 **
 **  [in]  inputChannel  input activation channels
 **
 **  [in]  startCol  starting column for activation
 **
 **  [in]  startRow  starting row for activation
 **
 **  [in]  padVal  padding value
 **
 **  [in]  padHeight  padding Height
 **
 **  [in]  padWidth  padding Width
 **
 **  [in]  strideCol  Stride column
 **
 **  [in]  strideRow  Stride rows
 **
 **  [in]  inputOffset input offset value
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_ActivationStreamerCfg(NNLITE_Type *nnlite, cy_nnlite_context_t *context,
    uint32_t filterWidth, uint32_t filterHeight,
    uint32_t activationRepeats, uint32_t inputWidth,
    uint32_t inputHeight, uint32_t inputChannel,
    uint32_t startCol, uint32_t startRow,
    int8_t padVal, uint8_t padWidth,
    uint8_t padHeight, uint8_t strideCol,
    uint8_t strideRow, int32_t inputOffset)
{
  cy_en_nnlite_status_t status;
  uint32_t startColChannelTimesPadWidth;
  uint32_t startRowPadHeight;
  uint32_t padWidthTimesChannel;

  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else if((context->nnliteState == CY_NNLITE_INIT) ||
            (context->nnliteState ==  CY_NNLITE_OP_DONE))
  {
    padWidthTimesChannel = padWidth * inputChannel;
    startColChannelTimesPadWidth = startCol - padWidthTimesChannel;
    startRowPadHeight = startRow - padHeight;

    nnlite->ACTIVATIONSTREAMEROFFSET = (uint32_t)inputOffset;
    /* weights dims*/
    nnlite->ACTIVATIONSTREAMERKERNELCHANNELTIMESWIDTH = (filterWidth * inputChannel);
    nnlite->ACTIVATIONSTREAMERKERNELHEIGHT = filterHeight;

    /* is equal to number of filters for conv or equal to filer 2nd dimension for fc layer */
    nnlite->ACTIVATIONSTREAMERREPEATS = activationRepeats;

    /* input dims */
    nnlite->ACTIVATIONSTREAMERCHANNELTIMESWIDTH = (inputWidth * inputChannel);
    nnlite->ACTIVATIONSTREAMERHEIGHT = inputHeight;
    nnlite->ACTIVATIONSTREAMERSTARTCOL =  startColChannelTimesPadWidth;
    nnlite->ACTIVATIONSTREAMERSTARTROW = startRowPadHeight;
    nnlite->ACTIVATIONSTREAMERPADDING =
      _VAL2FLD(MXNNLITE_1_0_ACTIVATIONSTREAMERPADDING_ACTIVATIONSTREAMERPADVALUE, padVal);

    nnlite->STRIDE =
      _VAL2FLD(MXNNLITE_1_0_STRIDE_STRIDECHANNELTIMESCOLUMN, strideCol * inputChannel) |
      _VAL2FLD(MXNNLITE_1_0_STRIDE_STRIDEROW, strideRow);

    status = CY_NNLITE_SUCCESS;
  }
  else
  {
    status = CY_NNLITE_BAD_STATE;
  }
  return status;
}

/**
 *****************************************************************************
 **  nnlite weight streamer configuration set, API will configure offset
 **  for weight streamer and weights per neuron parameter
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  context    pointer to the driver context structure
 **
 **  [in]  weightPerNeuron  wight/filter elements count per neuron
 **
 **  [in]  filterOffset  wight/filter elements offset value
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_WeightStreamerCfg(NNLITE_Type *nnlite, cy_nnlite_context_t *context,
    uint32_t weightPerNeuron, int32_t filterOffset)
{
  cy_en_nnlite_status_t status;
  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->WEIGHTSTREAMERKERNELCHANNELTIMESHEIGHTTIMESWIDTH = weightPerNeuron;
    nnlite->WEIGHTSTREAMEROFFSET = (uint32_t)filterOffset;
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}

/**
 *****************************************************************************
 **  nnlite out streamer configuration set, API will set clipping mask,
 **  offset, scaling factor ,width and height for output streamer
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  context    pointer to the driver context structure
 **
 **  [in]  clippingMask  output clipping mask for max or min value
 **
 **  [in]  outputOffset  output elements offset value
 **
 **  [in]  outputScalingFactor  output scaling factor
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_OutputStreamerCfg(NNLITE_Type *nnlite, cy_nnlite_context_t *context,
    uint32_t clippingMask, int32_t outputOffset,
    uint32_t outputWidth, uint32_t outputHeight,
    float outputScalingFactor)
{
  cy_en_nnlite_status_t status;
  void *scalingFactorPtr;
  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    context->nnliteState = CY_NNLITE_CONFIG_STATE;
    scalingFactorPtr = &outputScalingFactor;
    nnlite->OUTSTREAMERCLIPPINGMASK = clippingMask;
    nnlite->OUTSTREAMEROUTPUTOFFSET = (uint32_t)outputOffset;
    nnlite->OUTSTREAMERSCALINGFACTOR = *(uint32_t *)scalingFactorPtr;
    nnlite->OUTPUTWIDTH = outputWidth;
    nnlite->OUTPUTHEIGHT = outputHeight;
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}

/**
 *****************************************************************************
 **  nnlite bias streamer enable
 **
 **  [in]  nnlite    base pointer of register map.
 **
 **  [in]  biasEn    bias streamer enable
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_BiasStreamerEnable(NNLITE_Type *nnlite, bool biasEn)
{
    cy_en_nnlite_status_t status;

  if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    status = CY_NNLITE_SUCCESS;
    if (biasEn)
     {
        nnlite->STREAMERMODES |= _VAL2FLD(MXNNLITE_1_0_STREAMERMODES_BIASEN, 1);
     }
     else
     {
        nnlite->STREAMERMODES &= ~(_VAL2FLD(MXNNLITE_1_0_STREAMERMODES_BIASEN, 1));
     }
  }
  return status;
}
/**
 *****************************************************************************
 **  nnlite set Interpolation lookup table to be used along
 **  with Cy_NNLite_SetinterpolationParam. For lut 0 and lut 1 both,
 **  Cy_NNLite_SetinterpolationParam need to be set.
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  lut        lookup table
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_SetInterpolationLUTAddr(NNLITE_Type *nnlite, bool lut)
{
  cy_en_nnlite_status_t status;
  if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    if (lut)
    {
      nnlite->INTERPOLATIONLUTADDR = 1U;
    }
    else
    {
      nnlite->INTERPOLATIONLUTADDR = 0U;
    }
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}

/**
 *****************************************************************************
 ** Set interpolation parameters.
 **
 ** [in]  nnlite    nnlite base pointer.
 **
 ** [in] slope      number of elements.
 **
 ** [in] intercept  intercept value.
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_SetInterpolationParam(NNLITE_Type *nnlite,
                                        uint16_t slope, uint16_t intercept)
{
  cy_en_nnlite_status_t status;
  if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->INTERPOLATIONLUTWDATA =
    _VAL2FLD(MXNNLITE_1_0_INTERPOLATIONLUTWDATA_INTERPOLATIONSLOPE, slope) |
    _VAL2FLD(MXNNLITE_1_0_INTERPOLATIONLUTWDATA_INTERPOLATIONYINTERCEPT, intercept);

    status = CY_NNLITE_SUCCESS;
  }

  return status;
}

/**
 *****************************************************************************
 **  nnlite get nnlite interrupt status
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [out]  intrStatus    nnlite interrupt status register
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_GetInterruptStatus(NNLITE_Type *nnlite, uint32_t *intrStatus)
{
  cy_en_nnlite_status_t status;

  if ((NULL == nnlite) || (NULL == intrStatus))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    *intrStatus  = nnlite->INTR;
    status = CY_NNLITE_SUCCESS;
  }

  return status;

}

/**
 *****************************************************************************
 **  get nnlite interrupt mask
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [out]  intrMask    nnlite interrupt mask
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_GetInterruptMask(NNLITE_Type *nnlite, uint32_t *intrMask)
{
  cy_en_nnlite_status_t status;

  if ((NULL == nnlite) || (NULL == intrMask))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    *intrMask = nnlite->INTR_MASK;
    status = CY_NNLITE_SUCCESS;
  }
  return status;

}

 /*****************************************************************************
 **  nnlite get driver state
 **
 **  [in]  nnlite base pointer of register map.
 **
 **  [in]  context    pointer to the driver context structure
 **
 **  [out]  nnliteState nnlite driver state
 *****************************************************************************/
cy_en_nnlite_status_t Cy_NNLite_GetDriverState(NNLITE_Type *nnlite,
                                               cy_nnlite_context_t *context,
                                               cy_en_nnlite_state_t *nnliteState)
{
  cy_en_nnlite_status_t status = CY_NNLITE_SUCCESS;
  if ((NULL == nnlite) || (NULL == nnliteState))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    *nnliteState = context->nnliteState;
  }
  return status;
}

/**
 *****************************************************************************
 **   nnlite set datawire trigger control, trigger datawire for next layer
 **  when trigger is 1
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  trigEn  datawire trigger enable
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_DatawireTriggerEnable(NNLITE_Type *nnlite, bool trigEn)
{
  cy_en_nnlite_status_t status;

  if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->TRIG_MASK = (uint32_t)trigEn;
    status = CY_NNLITE_SUCCESS;
  }
  return status;
}

/**
 *****************************************************************************
 **   nnlite set interrupt mask, available interrupt are operation STATUS Done,
 **   MEM Fetch Error different streamers, Output Saturation interrupt
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  intrMask       interrupt mask value
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_SetInterruptMask(NNLITE_Type *nnlite, uint32_t intrMask)
{
  cy_en_nnlite_status_t status;

  if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->INTR_MASK = (intrMask & 0x7FUL);
    status = CY_NNLITE_SUCCESS;
  }
  return status;

}

/**
 *****************************************************************************
 **   clear nnlite interrupts
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  intrMask    nnlite interrupts to be cleared
 *****************************************************************************/
cy_en_nnlite_status_t
Cy_NNLite_InterruptClear(NNLITE_Type *nnlite, uint32_t intrMask)
{
  cy_en_nnlite_status_t status;

  if (NULL == nnlite)
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    nnlite->INTR = (intrMask & 0x7FUL);
    status = CY_NNLITE_SUCCESS;
  }
  return status;

}

/**
 *****************************************************************************
 **   interrupt mask to status mapping
 **
 **  [in]  intrStatus interrupt status
 *****************************************************************************/
static cy_en_nnlite_status_t
Cy_NNLite_InterruptStatusToErrMap(uint32_t intrStatus)
{
  cy_en_nnlite_status_t status;
  switch(intrStatus)
  {
    case MXNNLITE_1_0_INTR_INTR_DONE_Msk:
      status = CY_NNLITE_SUCCESS;
      break;
    case MXNNLITE_1_0_INTR_INTR_MEM_ERR_SPARSITY_Msk:
      status = CY_NNLITE_MEM_ERR_SPARSITY;
      break;
    case MXNNLITE_1_0_INTR_INTR_MEM_ERR_ACTIVATIONSTREAMER_Msk:
      status = CY_NNLITE_MEM_ERR_ACTIVATION_STREAMER;
      break;
    case MXNNLITE_1_0_INTR_INTR_MEM_ERR_WEIGHTSTREAMER_Msk:
      status = CY_NNLITE_MEM_ERR_WEIGHT_STREAMER;
      break;
    case MXNNLITE_1_0_INTR_INTR_MEM_ERR_BIASSTREAMER_Msk:
      status = CY_NNLITE_MEM_ERR_BIAS_STREAMER;
      break;
    case MXNNLITE_1_0_INTR_INTR_MEM_ERR_OUTPUTSTREAMER_Msk:
      status = CY_NNLITE_MEM_ERR_OUTPUT_STREAMER;
      break;
    case MXNNLITE_1_0_INTR_INTR_SATURATION_Msk:/* fall through for saturation */
    case (MXNNLITE_1_0_INTR_INTR_DONE_Msk | MXNNLITE_1_0_INTR_INTR_SATURATION_Msk) :
      status = CY_NNLITE_SATURATION;
      break;
    default :
      status = CY_NNLITE_SUCCESS;
      break;

  }
  return status;
}


/**
 *****************************************************************************
 ** wait for completion of operation, will wait for BUSY_STATUS to go low,
 ** in busy loop
 **
 ** [in]  nnlite      base pointer of register map.
 **
 ** [in]  context     pointer to the driver context structure
*****************************************************************************/
cy_en_nnlite_status_t Cy_NNLite_WaitForCompletion(NNLITE_Type *nnlite,
                                                  cy_nnlite_context_t *context)
{
  cy_en_nnlite_status_t status;
  uint32_t interruptStatus;
  if ((NULL == nnlite) || (NULL == context))
  {
    status = CY_NNLITE_BAD_PARAM;
  }
  else
  {
    /* poll for Busy bit */
    do {
    } while (1U == (nnlite->STATUS & MXNNLITE_1_0_STATUS_BUSY_STATUS_Msk));

    (void)Cy_NNLite_GetInterruptStatus(nnlite, &interruptStatus);
    status = Cy_NNLite_InterruptStatusToErrMap(interruptStatus);
    (void)Cy_NNLite_InterruptClear(nnlite, interruptStatus);

    if (context->nnliteState == CY_NNLITE_OP_STARTED)
    {
      context->nnliteState = CY_NNLITE_OP_DONE;
    }
  }
  return status;
}

/**
 *****************************************************************************
 **   nnlite  ISR handler
 **
 **  [in]  nnlite     base pointer of register map.
 **
 **  [in]  context    nnlite context structure pointer
 *****************************************************************************/
void Cy_NNLite_InterruptHandler(NNLITE_Type *nnlite,
                                  cy_nnlite_context_t *context)
{
  uint32_t intrStatus = 0;

  (void)Cy_NNLite_GetInterruptStatus(nnlite, &intrStatus);
  if (context->nnliteState == CY_NNLITE_OP_STARTED)
  {
    context->opStatus = Cy_NNLite_InterruptStatusToErrMap(intrStatus);
    context->nnliteState = CY_NNLITE_OP_DONE;
  }

  (void)Cy_NNLite_InterruptClear(nnlite, intrStatus);
}

#if defined(__cplusplus)
}
#endif

#endif /* CY_IP_MXNNLITE */

/* [] END OF FILE */
