
######################################################################################################
ifeq ($(CM4),yes)
TARGET_SEL = -mcpu=cortex-m4
TGTFLAGS = $(TARGET_SEL) -mfpu=fpv4-sp-d16 \
	-I../../FreeRTOS/portable/GCC/ARM_CM4F
endif

ifeq ($(CM0),yes)
TARGET_SEL = -mcpu=cortex-m0plus
TGTFLAGS =  $(TARGET_SEL) \
	-I../../FreeRTOS/portable/GCC/ARM_CM0
endif
######################################################################################################

CFILES = \
	 cy_hbdma.c \
	 cy_hbdma_mgr.c \
	 cy_hbdma_dscr_list.c \
	 cy_hbdma_buf_alloc.c

CFLAGS = \
	 -Os --specs=nano.specs -Og -mfloat-abi=softfp $(TGTFLAGS) \
	 -mthumb -ffunction-sections -fdata-sections -g \
	 -I.. \
	 -I../../pdl/COMPONENT_CAT1E/include \
	 -I../../pdl/drivers/include \
	 -I../../pdl/cmsis/include \
	 -I../../fx3g2_utils \
	 -I../../FreeRTOS \
	 -I../../FreeRTOS/include \
	 -I../../pdl/COMPONENT_CAT1E/templates/COMPONENT_MTB \
	 -I../../core-lib/include \
	 -DCYUSB4024_BZXI \
	 -DCY_HBDMA_ERRORDETECTION=1 -DDEBUG_INFRA_EN=1 \
	 -DFREERTOS_ENABLE=$(RTOS_EN) \
	 -DHBDMA_64KB_EN=1

CFLAGS += -DBCLK__BUS_CLK__HZ=75000000

# Path to compiler/linker tools.
CC = arm-none-eabi-gcc

DONE=@if [ -f $(1) ]; then echo Build completed.; fi
RM=rm -f $(1)

.SUFFIXES: .o .c .s
.PHONY: all clean build

all: clean ofiles

clean:
	rm -rf out
	mkdir out

ofiles : $(CFILES)
	@echo "---------------------"
	@echo "Building HBDMA files"
	@echo "-------------------"
	for f in $(CFILES); do \
		echo "Compiling $$f"; \
		cd out && $(CC) $(CFLAGS) -c ../$$f && cd ..; \
	done
	@echo "----------------------"
	@echo "Done compiling HBDMA files"
	@echo "----------------------"

