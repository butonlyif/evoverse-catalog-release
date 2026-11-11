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
	 cy_usb_usbd.c \
	 cy_usbhs_cal_drv.c \
	 cy_usbss_cal_drv.c


# Compiler command line arguments.
CFLAGS              = \
	-Os --specs=nano.specs -Og -mfloat-abi=softfp $(TGTFLAGS) \
	-mthumb -ffunction-sections -fdata-sections -g \
	-I.. \
	-I../Core/Include \
	-I../../fx3g2_utils \
	-I../../FreeRTOS \
	-I../../FreeRTOS/include \
	-I../../pdl/COMPONENT_CAT1E/include \
	-I../../pdl/drivers/include \
	-I../../pdl/cmsis/include \
	-I../../pdl/COMPONENT_CAT1E/templates/COMPONENT_MTB \
	-I../../hb_dma \
	-I../../core-lib/include \
	-DCYUSB4024_BZXI \
	-DFREERTOS_ENABLE=$(RTOS_EN) -DDEBUG_INFRA_EN=1

CFLAGS += -DBCLK__BUS_CLK__HZ=75000000

OBJECTS =		\
	out/cy_usb_usbd.o \
	out/cy_usbhs_cal_drv.o \
	out/cy_usbss_cal_drv.o

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
	 @echo "Building the USB stack C files"
	 @echo "-------------------"
	 for f in $(CFILES); do \
	     echo "Compiling $$f"; \
	     cd out && $(CC) $(CFLAGS) -c ../$$f && cd .. ; \
	 done
	 @echo "----------------------"
	 @echo "Done compiling USB stack C files"
	 @echo "----------------------"

