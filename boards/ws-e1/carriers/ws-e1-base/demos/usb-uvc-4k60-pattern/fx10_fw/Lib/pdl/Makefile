
######################################################################################################
ifeq ($(CM4),yes)
ASMFILES = COMPONENT_CAT1E/templates/COMPONENT_MTB/COMPONENT_CM4/TOOLCHAIN_GCC_ARM/startup_fx3g2_cm4.S

CFILES = \
	 COMPONENT_CAT1E/templates/COMPONENT_MTB/COMPONENT_CM4/system_fx3g2_cm4.c \

OBJECTS = \
	  out/startup_fx3g2_cm4.o \
	  out/system_fx3g2_cm4.o

TARGET_SEL = -mcpu=cortex-m4
TGTFLAGS = $(TARGET_SEL) -mfpu=fpv4-sp-d16
endif

ifeq ($(CM0),yes)
ASMFILES = COMPONENT_CAT1E/templates/COMPONENT_MTB/COMPONENT_CM0P/TOOLCHAIN_GCC_ARM/startup_fx3g2_cm0plus.S

CFILES = \
	 COMPONENT_CAT1E/templates/COMPONENT_MTB/COMPONENT_CM0P/system_fx3g2_cm0plus.c

OBJECTS = \
	  out/startup_fx3g2_cm0plus.o \
	  out/system_fx3g2_cm0plus.o

TARGET_SEL = -mcpu=cortex-m0plus
TGTFLAGS =  $(TARGET_SEL)
endif
######################################################################################################

# ASM source files
ASMFILES += \
	   drivers/source/TOOLCHAIN_GCC_ARM/cy_syslib_ext.s

# C source files
CFILES += \
	 drivers/source/cy_dma.c \
	 drivers/source/cy_dmac.c \
	 drivers/source/cy_gpio.c \
	 drivers/source/cy_scb_common.c \
	 drivers/source/cy_scb_ezi2c.c \
	 drivers/source/cy_scb_i2c.c \
	 drivers/source/cy_scb_uart.c \
	 drivers/source/cy_sysclk.c \
	 drivers/source/cy_sysclk_v2.c \
	 drivers/source/cy_sysint.c \
	 drivers/source/cy_sysint_v2.c \
	 drivers/source/cy_syslib.c \
	 drivers/source/cy_systick.c \
	 drivers/source/cy_systick_v2.c \
	 drivers/source/cy_tcpwm_counter.c \
	 drivers/source/cy_tcpwm_pwm.c \
	 drivers/source/cy_trigmux.c \
	 drivers/source/cy_ipc_drv.c \
	 drivers/source/cy_ipc_pipe.c \
	 drivers/source/cy_ipc_sema.c \
	 drivers/source/cy_wdt.c \
	 drivers/source/cy_pdm_pcm_v2.c \
	 drivers/source/cy_syspm.c \
	 drivers/source/cy_smif.c \
	 COMPONENT_CAT1E/source/cy_device.c \

# Compiler command line arguments.
CFLAGS              = \
	-Os --specs=nano.specs -Og -mfloat-abi=softfp $(TGTFLAGS) \
	-mthumb -ffunction-sections -fdata-sections -g \
	-I.. \
	-I../../Core/Include \
	-I../../fx3g2_utils \
	-I../COMPONENT_CAT1E/include \
	-I../drivers/include \
	-I../cmsis/include \
	-I../COMPONENT_CAT1E/templates/COMPONENT_MTB \
	-I../../core-lib/include \
	-DCYUSB4024_BZXI \
	-DFREERTOS_ENABLE=$(RTOS_EN) -DDEBUG_INFRA_EN=1

CFLAGS += -DBCLK__BUS_CLK__HZ=75000000

# Assembler command line arguments.
AFLAGS = -c $(TARGET_SEL) --specs=nano.specs -mfloat-abi=softfp \
	 -mthumb -ffunction-sections -fdata-sections -g

OBJECTS +=		\
	out/cy_syslib_ext.o \
	out/cy_dma.o \
	out/cy_dmac.o \
	out/cy_gpio.o \
	out/cy_scb_common.o \
	out/cy_scb_ezi2c.o \
	out/cy_scb_i2c.o \
	out/cy_scb_uart.o \
	out/cy_sysclk.o \
	out/cy_sysclk_v2.o \
	out/cy_sysint.o \
	out/cy_sysint_v2.o \
	out/cy_syslib.o \
	out/cy_systick.o \
	out/cy_systick_v2.o \
	out/cy_tcpwm_counter.o \
	out/cy_tcpwm_pwm.o \
	out/cy_trigmux.o \
	out/cy_ipc_drv.o \
	out/cy_ipc_pipe.o \
	out/cy_ipc_sema.o \
	out/cy_wdt.o \
	out/cy_pdm_pcm_v2.o \
	out/cy_syspm.o \
	out/cy_smif.o \
	out/cy_device.o


# Path to compiler/linker tools.
CC = arm-none-eabi-gcc
AS = arm-none-eabi-gcc


DONE=@if [ -f $(1) ]; then echo Build completed.; fi
RM=rm -f $(1)

.SUFFIXES: .o .c .s
.PHONY: all clean build

all: clean ofiles

rebuild: all

clean:
	rm -rf out
	mkdir out

ofiles : $(CFILES) $(ASMFILES)
	 @echo "---------------------"
	 @echo "Building the ASM files"
	 @echo "---------------------"
ifeq ($(CM4),yes)
	 $(AS) $(AFLAGS) COMPONENT_CAT1E/templates/COMPONENT_MTB/COMPONENT_CM4/TOOLCHAIN_GCC_ARM/startup_fx3g2_cm4.S -o out/startup_fx3g2_cm4.o
endif
ifeq ($(CM0),yes)
	 $(AS) $(AFLAGS) COMPONENT_CAT1E/templates/COMPONENT_MTB/COMPONENT_CM0P/TOOLCHAIN_GCC_ARM/startup_fx3g2_cm0plus.S -o out/startup_fx3g2_cm0plus.o
endif
	 $(AS) $(AFLAGS) drivers/source/TOOLCHAIN_GCC_ARM/cy_syslib_ext.s -o out/cy_syslib_ext.o
	 @echo "-------------------"
	 @echo "Building PDL files"
	 @echo "-------------------"
	 for f in $(CFILES); do \
	     echo "Compiling $$f"; \
	     cd out && $(CC) $(CFLAGS) -c ../$$f && cd .. ; \
	 done
	 @echo "----------------------"
	 @echo "Done compiling PDL files"
	 @echo "----------------------"
