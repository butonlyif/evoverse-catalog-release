######################################################################################################
TARGET_SEL = -mcpu=cortex-m4
TGTFLAGS = $(TARGET_SEL) -mfpu=fpv4-sp-d16 \
	-I../../Lib/FreeRTOS/portable/GCC/ARM_CM4F
######################################################################################################

FX3G2_TARGET = out/fx3g2_uvc

# C source files
CFILES += \
	 cy_usb_app.c \
	 cy_uac_app.c \
	 fx3g2_descriptors.c \
	 spi_axi.c \
	 main.c

# Compiler command line arguments.
CFLAGS              = \
	-Os --specs=nano.specs -Og -mfloat-abi=softfp $(TGTFLAGS) \
	-mthumb -ffunction-sections -fdata-sections -g \
	-I.. \
	-I../../Lib/FreeRTOS \
	-I../../Lib/FreeRTOS/include \
	-I../../Lib/pdl/COMPONENT_CAT1E/include \
	-I../../Lib/pdl/drivers/include \
	-I../../Lib/pdl/cmsis/include \
	-I../../Lib/pdl/COMPONENT_CAT1E/templates/COMPONENT_MTB \
	-I../../Lib/hb_dma \
	-I../../Lib/lvds \
	-I../../Lib/fx3g2_utils \
	-I../../Lib/fx3g2_usb_common \
	-I../../Lib/core-lib/include \
	-DCYUSB4024_BZXI -DBCLK__BUS_CLK__HZ=75000000 \
	-DFREERTOS_ENABLE=1 -DDEBUG_INFRA_EN=1

ifeq ($(LPBK_EN), yes)
# Loopback is only supported in LVDS narrow link use case with Insert Metadata disabled.
CFLAGS += -DLVDS_LB_EN=1 -DLVCMOS_EN=0 -DPORT1_EN=0 -DINMD_EN=0 -DWL_EN=0
else
# Loopback mode is disabled
CFLAGS += -DLVDS_LB_EN=0

# Set to 1 for using LVCMOS, 0 for LVDS
CFLAGS += -DLVCMOS_EN=0

# Set to 1 for using LVCMOS DDR, 0 for LVCMOS SDR
CFLAGS += -DLVCMOS_DDR_EN=1

# Set to 1 for using port_1, 0 for port_0
CFLAGS += -DPORT1_EN=0

# Set to 1 for Metadata insertion, 0 for FW header addition
CFLAGS += -DINMD_EN=0

# Set to 1 for WideLink, 0 for NarrowLink mode
CFLAGS += -DWL_EN=1

# Set to 1 for enabling thread interleaving for TH0 & TH1
CFLAGS += -DPORT0_THREAD_INTLV=1
endif

# Enable both for Precision Time Measurement, Vendor IF is required to send LDM request using control center.
CFLAGS += -DPTM_ENABLE=0
CFLAGS += -DCY_VENDOR_IF_EN=0

# Set to 1 to enable integrated Audio Interface
CFLAGS += -DAUDIO_IF_EN=1 -DSTEREO_ENABLE=0

# Set to 1 to restrict USB connection to USBHS.
CFLAGS += -DFORCE_USBHS=0

# Compile for Gen2 operation unless GEN1=yes switch is used.
ifeq ($(GEN1),yes)
    CFLAGS += -DUSBSS_GEN2_ENABLE=0
else
    CFLAGS += -DUSBSS_GEN2_ENABLE=1
endif

ifeq ($(BLENABLE), yes)
    CFLAGS += -DBLOAD_ENABLE=1
    FX3G2_LD = cyusb4xxx_cm4_loadable.ld
else
    FX3G2_LD = cyusb4xxx_cm4.ld
endif


############################    Object Files       ############################
OBJECTS += \
	out/fx3g2_descriptors.o \
	out/cy_usb_app.o \
	out/cy_uac_app.o \
	out/spi_axi.o \
	out/main.o

###################### Path to compiler/linker tools ##########################
#
CC = arm-none-eabi-gcc
AS = arm-none-eabi-gcc
LD = arm-none-eabi-gcc
OC = arm-none-eabi-objcopy

DONE=@if [ -f $(1) ]; then echo Build completed.; fi
RM=rm -f $(1)

.SUFFIXES: .o .c .s
.PHONY: all clean build

all: prep ofiles $(FX3G2_TARGET).elf $(FX3G2_TARGET).hex
	$(call DONE,$(FX3G2_TARGET).hex)

rebuild: clean all

clean:
	rm -rf out
	mkdir out
prep:
	@echo '#### Preparing to build ####'
	+(rm -rf out)
	+(mkdir out)
	+(cp ../Lib/FX10_FW_LIB/fx10-fw-lib.a out)

ofiles : $(CFILES)
	 @echo "-------------------"
	 @echo "Building the C files"
	 @echo "-------------------"
	 for f in $(CFILES); do \
	     echo "Compiling $$f"; \
	     cd out && $(CC) $(CFLAGS) -c ../$$f && cd ..; \
	 done
	 @echo "----------------------"
	 @echo "Done compiling C files"
	 @echo "----------------------"

$(FX3G2_TARGET).elf : $(OBJECTS) $(FX3G2_LD)
	@echo "--------------------"
	@echo "Linking the elf file obj" $@
	@echo "--------------------"
	$(LD) -Wl,--start-group $(TARGET_SEL) -mthumb --entry=Reset_Handler -Wl,-Map,$(FX3G2_TARGET).map -T $(FX3G2_LD) -specs=nano.specs -Wl,--gc-sections -g -ffunction-sections -finline-functions -Os -Wl,--end-group -o $(FX3G2_TARGET).elf $(OBJECTS) out/fx10-fw-lib.a

$(FX3G2_TARGET).hex : $(FX3G2_TARGET).elf
	@echo "-------------------------"
	@echo "Building the hex file" $@
	@echo "-------------------------"
ifeq ($(BLENABLE),yes)
	@echo "Generating SHA checksum"
	@echo "-------------------------"
	cymcuelftool --sign $(FX3G2_TARGET).elf SHA256 --output $(FX3G2_TARGET).sha.elf
	$(OC) -O ihex --gap-fill 0 $(FX3G2_TARGET).sha.elf $(FX3G2_TARGET).hex
else
	$(OC) -O ihex $(FX3G2_TARGET).elf $(FX3G2_TARGET).hex
endif
	@echo "-------------------------"
	@echo "Building the list file" $@
	@echo "--------------------------"
	arm-none-eabi-objdump -S $(FX3G2_TARGET).elf > $(FX3G2_TARGET).lst

##[]
