#include "cy_smif.h"

void spi_axi_wr(SMIF_Type *baseaddr, cy_stc_smif_context_t *smifContext, int axi_addr, int axi_data);
int spi_axi_rd(SMIF_Type *baseaddr, cy_stc_smif_context_t *smifContext, int axi_addr);
