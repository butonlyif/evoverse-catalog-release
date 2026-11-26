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

# C source files
CFILES = \
	cy_fx3g2_bsp.c \
	cy_debug.c \
	cy_fault_handlers.c \
	cy_uart.c \
	cy_usbhs_dw_wrapper.c \
	dma_isr.c \
	cy_usbfs_cdc.c \
	cy_efuse_access.c

# Compiler command line arguments.
CFLAGS = \
	-Os --specs=nano.specs -Og -mfloat-abi=softfp $(TGTFLAGS) \
	-mthumb -ffunction-sections -fdata-sections -g \
	-I.. \
	-I../../FreeRTOS \
	-I../../FreeRTOS/include \
	-I../../pdl/COMPONENT_CAT1E/include \
	-I../../pdl/drivers/include \
	-I../../pdl/cmsis/include \
	-I../../pdl/COMPONENT_CAT1E/templates/COMPONENT_MTB \
	-I../../core-lib/include \
	-I../../hb_dma \
	-I../../fx3g2_usb_common \
	-DCYUSB4024_BZXI \
	-DFREERTOS_ENABLE=$(RTOS_EN) -DDEBUG_INFRA_EN=1 -DDEBUG_BLOCKING_PRINT_EN=1

CFLAGS += -DBCLK__BUS_CLK__HZ=75000000

# Path to compiler/linker tools.
CC = arm-none-eabi-gcc


DONE=@if [ -f $(1) ]; then echo Build completed.; fi
RM=rm -f $(1)

.SUFFIXES: .o .c .s
.PHONY: all clean build

all: clean ofiles

rebuild: all

clean:
	rm -rf out
	mkdir out

ofiles : $(CFILES)
	 @echo "-------------------"
	 @echo "Building FX3G2 Utils dir"
	 @echo "-------------------"
	 for f in $(CFILES); do \
	     echo "Compiling $$f"; \
	     cd out && $(CC) $(CFLAGS) -c ../$$f && cd .. ; \
	 done
	 @echo "----------------------"
	 @echo "Done compiling UTILS files"
	 @echo "----------------------"
