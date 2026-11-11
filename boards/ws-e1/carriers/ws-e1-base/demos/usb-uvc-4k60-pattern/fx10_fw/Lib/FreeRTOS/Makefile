######################################################################################################
ifeq ($(CM4),yes)
CFILES = \
	 portable/GCC/ARM_CM4F/port.c

TARGET_SEL = -mcpu=cortex-m4
TGTFLAGS = $(TARGET_SEL) -mfpu=fpv4-sp-d16 \
	-I../portable/GCC/ARM_CM4F
endif

ifeq ($(CM0),yes)
CFILES = \
	 portable/GCC/ARM_CM0/port.c

TARGET_SEL = -mcpu=cortex-m0plus
TGTFLAGS =  $(TARGET_SEL) \
	-I../portable/GCC/ARM_CM0
endif
######################################################################################################

# C source files
CFILES += \
	portable/MemMang/heap_4.c  \
	croutine.c \
	event_groups.c \
	list.c \
	queue.c \
	stream_buffer.c \
	tasks.c \
	timers.c

# Compiler command line arguments.
CFLAGS = \
	-Os --specs=nano.specs -Og -mfloat-abi=softfp $(TGTFLAGS) \
	-mthumb -ffunction-sections -fdata-sections -g \
	-I.. \
	-I../Core/Include \
	-I../include \
	-I../../fx3g2_utils \
	-DCYUSB4024_BZXI \
	-DFREERTOS_ENABLE=$(RTOS_EN) -DDEBUG_INFRA_EN=1

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
	 @mkdir -p out
	 @echo "-------------------"
	 @echo "Building the FreeRTOS C files"
	 @echo "-------------------"
	 for f in $(CFILES); do \
	     echo "Compiling $$f"; \
	     cd out && $(CC) $(CFLAGS) -c ../$$f && cd .. ; \
	 done
	 @echo "----------------------"
	 @echo "Done compiling FreeRTOS C files"
	 @echo "----------------------"
