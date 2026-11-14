#ifndef HEADER_INTC_H_
#define HEADER_INTC_H_

#include <stdint.h>
#include "bsp.h"
#include "plic.h"
#include "riscv.h"
#include "mmc.h"

typedef struct _IntStruct{
	u32 command_complete;
	u32 transfer_complete;
	u32 block_gap_event;
	u32 buffer_write_ready;
	u32 buffer_read_ready;
	u32 card_insertion;
	u32 card_removal;
	u32 command_timeout_error;
	u32 command_crc_error;
	u32 command_end_bit_error;
	u32 command_index_error;
	u32 data_crc_error;
}IntStruct;

void IntcInitialize(struct mmc *mmc);

#endif
