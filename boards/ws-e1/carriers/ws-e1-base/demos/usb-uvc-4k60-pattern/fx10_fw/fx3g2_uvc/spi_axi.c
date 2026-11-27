#include "cy_smif.h"

#define CMD_WITHOUT_PARAM   (0u) 
#define TX_LAST_BYTE       	(1u) 	/* The last byte in command transmission 
									* (SS is set to high after transmission) 
									*/
#define TX_NOT_LAST_BYTE    (0u) 	/* Not the last byte in command transmission 
									* (SS remains low after transmission)
                                    */

#define AXI_WR 0x00
#define AXI_RD 0x01
cy_smif_event_cb_t RxCmpltCallback;

void spi_axi_wr(SMIF_Type *baseaddr, cy_stc_smif_context_t *smifContext, int axi_addr, int axi_data)
{
    char wr_buf[10];
    wr_buf[0] = (axi_addr >> 24) & 0xff;
    wr_buf[1] = (axi_addr >> 16) & 0xff;
    wr_buf[2] = (axi_addr >> 8) & 0xff;
    wr_buf[3] = (axi_addr >> 0) & 0xff;

    wr_buf[4] = (axi_data >> 24) & 0xff;
    wr_buf[5] = (axi_data >> 16) & 0xff;
    wr_buf[6] = (axi_data >> 8) & 0xff;
    wr_buf[7] = (axi_data >> 0) & 0xff;

    wr_buf[8] = 0x00;
    wr_buf[9] = 0x00;
    Cy_SMIF_TransmitCommand( baseaddr,
                            AXI_WR,		
                            CY_SMIF_WIDTH_SINGLE,
                            wr_buf, 
                            10, 
                            CY_SMIF_WIDTH_SINGLE, 
                            CY_SMIF_SLAVE_SELECT_2, 
                            TX_LAST_BYTE, 
                            smifContext);
    /* Check if the SMIF IP is busy */
    while(Cy_SMIF_BusyCheck(baseaddr))
    {
        /* Wait until the SMIF IP operation is completed. */
    }
}

int spi_axi_rd(SMIF_Type *baseaddr, cy_stc_smif_context_t *smifContext, int axi_addr)
{
    char wr_buf[5];
    char rd_buf[6];
    int axi_data;
    wr_buf[0] = (axi_addr >> 24) & 0xff;
    wr_buf[1] = (axi_addr >> 16) & 0xff;
    wr_buf[2] = (axi_addr >> 8) & 0xff;
    wr_buf[3] = (axi_addr >> 0) & 0xff;
    wr_buf[4] = 0;
    Cy_SMIF_TransmitCommand( baseaddr,
                            AXI_RD,		
                            CY_SMIF_WIDTH_SINGLE,
                            wr_buf, 
                            5, 
                            CY_SMIF_WIDTH_SINGLE, 
                            CY_SMIF_SLAVE_SELECT_2, 
                            TX_NOT_LAST_BYTE, 
                            smifContext);

    //Cy_SMIF_SendDummyCycles (baseaddr, 0x06);
    Cy_SMIF_ReceiveData(  baseaddr,
                            rd_buf, 
                            5, 
                            CY_SMIF_WIDTH_SINGLE, 
                            RxCmpltCallback,
                            smifContext);
    /* Check if the SMIF IP is busy */
    while(Cy_SMIF_BusyCheck(baseaddr))
    {
        /* Wait until the SMIF IP operation is completed. */
    }
    return axi_data = (rd_buf[0] << 24) | (rd_buf[1] << 16) | (rd_buf[2] << 8) | (rd_buf[3] << 0);
}