openocd -s ../scripts -f interface/kitprog3.cfg -f target/fx3g2.cfg -c "set ENABLE_ACQUIRE 1; kitprog3 power_config on 3300; init; kitprog3 acquire_psoc; reset init; program %1 verify reset exit"
