set on_failure_script_quits 1 

time
hycomp_read_model
hycomp_compile_model
hycomp_untime_network -m timed -a -d 
hycomp_async2sync_network -r
hycomp_net2mono
time
echo "verification"
#hycomp_check_invar_bmc_cegarwa 
hycomp_check_invar_ic3 -v 1
time

quit

