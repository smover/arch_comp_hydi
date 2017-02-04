#!/bin/bash
#
# Script that generates instance of the fisher model with n processes.
#
# usage: bash dist_controller.sh -lower <lower> -upper <upper>
# Generates all the models with a number of processes in the range
# <lower>..<upper>.
#
# For example bash dist_controller.sh -lower 2 -upper 10 generates 8 models, from
# 2 to 10 processes.
#
# Output models are called dist_controller_n.hydi,  where n is the total number
# of processes.
#


#------------------------------------------------------------------------------#
# usage
#
usage() {
    cat <<EOF
usage: $0 -lower <lower_bound> 
          -upper <upper_bound>
EOF
    exit 1
}

# check bound
check_bound() {
    local bound=$1

    if [ "${bound}" == "" ]; then
        echo "No bound provided!";
        usage
    fi

    if ! [[ "$bound" =~ ^[0-9]+$ ]]; then
        echo "${bound} is not a number!";
        usage
    fi
}

# print common part of main module
#
print_common_part() {
    local out_file=${1}

    cat >>${out_file} <<EOF
MODULE main

-- set the parametrs 

#define def_sampletime_par 1
#define def_lost_packet_time_par 0.25
#define def_inity_par 1

#define invarscheduler_par 0.25
#define def_computation_offset_par 0.3125

#define boundcontroller_par 1
#define waittime_par 0.25
#define waittime2_par 0.25
#define computationtime_par 1
#define mincomputationtime_par 1.25
#define invar_on_rec_par 0.25

EOF

# cat >> ${out_file} <<EOF
# MODULE main
# -- Sensor
# FROZENVAR
#   def_sampletime : real; -- 6
#   def_inity : real; -- 6
#   def_lost_packet_time : real; -- 0.5

# -- Scheduler
# FROZENVAR
#   invarscheduler : real; -- 32
#   def_computation_offset : real; -- 1.0

# -- controller 
# FROZENVAR
#   invar_on_rec : real; -- 100
#   boundcontroller : real; -- 100
#   waittime : real; -- 0
#   waittime2 : real; -- 0
#   computationtime : real; -- 5.6
#   mincomputationtime : real; -- 3.6

# INVAR
#   def_sampletime > 0 & def_inity > 0 & def_lost_packet_time > 0 &
#   def_sampletime = def_inity & 
#   invarscheduler > 0 & def_computation_offset > 0 &
#   invar_on_rec > 0 & boundcontroller > 0 & waittime > 0 & waittime2 > 0 &
#   computationtime > 0 & mincomputationtime > 0 &
#   waittime = waittime2

# INVAR def_lost_packet_time = 0.25
# INVAR def_inity = 1
# INVAR def_sampletime = 1
# INVAR def_computation_offset = 0.3125
# INVAR invarscheduler = 0.25
# INVAR mincomputationtime = 1.25
# INVAR computationtime = 1
# INVAR waittime2 = 0.25
# INVAR waittime = 0.25
# INVAR boundcontroller = 1
# INVAR invar_on_rec = 0.25

# EOF

}

# prints the definition of a sensor
print_sensor_definition() {
    local out_file=${1}

    cat >>${out_file} <<EOF
-- definition of a sensor
-- lost_packet_time: threshold before a packet is lost
MODULE SensorType(lost_packet_time, inity, sampletime)

VAR
  location : {done, read, wait, send};
  y : continuous; -- stopwatch

EVENT request_evt, read_evt, send_evt, ack_evt;

INIT
  location = done & y = inity;

FLOW location in {done, wait} -> der(y) = 1;
FLOW location in {read, send} -> der(y) = 0;


TRANS
  (EVENT = request_evt -> 
   (
    (location = done & y >= sampletime & next(location) = read & next(y) = y) |
    (location = wait & y >= lost_packet_time & next(location) = read & next(y) = y)
   )
  ) &
  (EVENT = read_evt -> 
   (
    (location = read & next(location) = wait & next(y) = 0)
   )
  ) &
  (EVENT = send_evt -> 
   (
    (location = wait  & next(location) = send & next(y) = y)
   )
  ) &
  (EVENT = ack_evt -> 
   (
    (location = send & next(location) = done & next(y) = 0)
   )
  );

INVAR
  (location = done -> y <= sampletime) &
  (location = wait -> y <= lost_packet_time);
EOF
}

# print frame condition for a variable
print_fc_var() {
    local out_file=${1}
    local var_name=${2}
    local ignore_index=${3}
    local number_of_processes=${4}
    local j=1;

    for ((j=1; j<=${number_of_processes}; j++)); do
        if [ "${j}" != "${ignore_index}" ]; then
            echo " & next(${var_name}_${j}) = ${var_name}_${j}" >> ${out_file};
        fi
    done
}


# print the definition of the scheduler
print_scheduler_definition() {
    local out_file=${1}
    local number_of_processes=${2}

    cat >>${out_file} <<EOF
-- Module definition of a scheduler.
MODULE SchedulerType(invarscheduler, def_computation_offset)
EOF

    # 1. Print variables
    echo "VAR" >> ${out_file};
    # print location
    echo "location : {idle " >>${out_file};
    for ((k=1; k<=${number_of_processes}; k++)); do
        echo ",loc_sensor_${k}" >>${out_file};
    done
    echo "};" >>${out_file};

    # print wait and continuous vars
    for ((k=1; k<=${number_of_processes}; k++)); do
        if [ "${k}" != "${number_of_processes}" ]; then
            # the last process will not wait!
            echo "wait_${k} : boolean;" >>${out_file}
        fi
        echo "x_${k} : continuous;" >>${out_file}
    done

    # 2. EVENT definition
    echo "EVENT " >> ${out_file};
    for ((k=1; k<=${number_of_processes}; k++)); do
        if [ "${k}" != 1 ]; then
            echo ", read_${k}, request_${k}" >>${out_file};
        else 
            echo "read_${k}, request_${k}" >>${out_file};
        fi
    done
    echo ";" >> ${out_file};

    # 3. INIT
    echo "INIT location = idle " >> ${out_file};
    for ((k=1; k<=${number_of_processes}; k++)); do
        if [ "${k}" != "${number_of_processes}" ]; then
            echo "& !wait_${k}" >>${out_file};
        fi
        echo "& x_${k} = 0" >>${out_file};
    done
    echo ";" >>${out_file};

    # 4. FLOW
    echo "FLOW " >> ${out_file};
    for ((k=1; k<=${number_of_processes}; k++)); do
        if [ "${k}" != 1 ]; then
            echo "& " >>${out_file};
        fi
        echo "(location = loc_sensor_${k} -> der(x_${k}) = 1) &" >>${out_file};
        echo "(location != loc_sensor_${k} -> der(x_${k}) = 0)" >>${out_file};
    done
    echo ";" >>${out_file};

    # 5. INVAR
    for ((k=1; k<=${number_of_processes}; k++)); do
#        echo "INVAR location = loc_sensor_${k} -> (x_${k} <= ${k});" >> ${out_file};
# debug
        echo "INVAR location = loc_sensor_${k} -> (x_${k} <= $((4*number_of_processes)));" >> ${out_file};
    done
    
    # 6. TRANS
    # Print trans:
    #   - request
    #   - read

    for ((k=1; k<=${number_of_processes}; k++)); do
        echo "TRANS " >>${out_file};
        echo "(EVENT = request_${k} -> (" >> ${out_file};

        echo "(location = idle & next(location) = loc_sensor_${k} & next(x_${k}) = 0 " >> ${out_file};
        print_fc_var "${out_file}" "x" "${k}" "${number_of_processes}";
        print_fc_var "${out_file}" "wait" "" "$((number_of_processes-1))"; # last process does not have preemption flag
        echo ")" >> ${out_file} # end of request event
        
        # set the "wait" flag if ${k} requests the scheduler and we are in an higher priority process"
        for ((j=$((k+1)); j<=${number_of_processes}; j++)); do
            echo "| (location = loc_sensor_${j} & next(location) = location & next(wait_${k})  & next(x_${k}) = 0" >> ${out_file};
            print_fc_var "${out_file}" "x" "${k}" "${number_of_processes}";
            # other preemption flags stay as they are
            print_fc_var "${out_file}" "wait" "${k}" "$((number_of_processes-1))"; # last process does not have preemption flag
            echo ")" >> ${out_file} # end of request event
        done

        # preemption if we are in a lower process priority
        for ((j=1; j<k; j++)); do
            echo " | (location = loc_sensor_${j} & next(location) = loc_sensor_${k} & next(wait_${j})  & next(x_${k}) = 0" >> ${out_file};
            print_fc_var "${out_file}" "x" "${k}" "${number_of_processes}";
            print_fc_var "${out_file}" "wait" "${j}" "$((number_of_processes-1))"; # last process does not have preemption flag
            echo ")"  >> ${out_file} # end of request event
        done

        echo ")) & " >> ${out_file} # end of request event

        # read
        echo "(EVENT = read_${k} -> " >> ${out_file};
        local guard_time="${k}*def_computation_offset";
#        local guard_time="0.5${k}*0.5";

        echo "(location = loc_sensor_${k} & x_${k} >= ${guard_time} & " >>${out_file}
        echo "case " >>${out_file}

        # preemption
        for ((j=$((k-1)); j>0; j--)); do
            echo "wait_${j} : next(location) = loc_sensor_${j} & !next(wait_${j}) " >> ${out_file};
            print_fc_var "${out_file}" "x" "${k}" "${number_of_processes}";
            print_fc_var "${out_file}" "wait" "${j}" "$((number_of_processes-1))";
            echo ";" >> ${out_file};
        done
        # if no preemption, then turn back to idle
        echo "TRUE : next(location) = idle " >> ${out_file};
        print_fc_var "${out_file}" "x" "" "${number_of_processes}";
        print_fc_var "${out_file}" "wait" "" "$((number_of_processes-1))";
        echo ";esac" >> ${out_file}

        # echo "(location = loc_sensor_${k} & x_${k} >= ${guard_time} & next(location) = idle " >>${out_file}
        # # add wait condition for processes with less prioriry
        # for ((j=1; j<k; j++)); do
        #     echo "& !wait_${j} " >>${out_file};
        # done
        # print_fc_var "${out_file}" "x" "" "${number_of_processes}";
        # echo ")" >> ${out_file} # end of request event

        # # read returns control to the highest priority sensor        
        # echo "| case " >> ${out_file};
        # for ((j=1; j<k; j++)); do
        #      echo "wait_${j} : next(location) = loc_sensor_${j} & !next(wait_${j}) & next(x_${k}) = x_${k} " >> ${out_file};
        #      print_fc_var "${out_file}" "x" "${k}" "${number_of_processes}";
        #      echo ";" >> ${out_file};
        # done
        # echo "TRUE: TRUE; esac" >> ${out_file};
        echo "));" >> ${out_file} # end of request event
    done
}

# print frame condition for a variable
print_fc_received() {
    local out_file=${1}
    local ignore_index=${2}
    local number_of_processes=${3}
    local j=1;

    for ((j=1; j<=${number_of_processes}; j++)); do
        if [ "${j}" != "${ignore_index}" ]; then
            echo " & next(received[${j}]) = received[${j}]" >> ${out_file};
        fi
    done
}

print_controller_definition() {
    local out_file=${1}
    local number_of_processes=${2}

    cat >>${out_file} <<EOF
-- Module definition of a scheduler.
MODULE ControllerType(invar_on_rec, boundcontroller, waittime, waittime2, computationtime, mincomputationtime)
VAR
  location : {rest, rec, wait, compute};
  z : continuous;  
  received : array 1 .. ${number_of_processes} of boolean;

EOF

    # 1. EVENT
    echo -n "EVENT signal, expire " >>${out_file};
    for ((k=1; k<=${number_of_processes}; k++)); do
        echo -n ", send_${k}, ack_${k}" >>${out_file};
    done
    echo ";" >>${out_file};

    # 2. INIT
    echo -n "INIT location = rest & z = 0" >>${out_file};
    for ((k=1; k<=${number_of_processes}; k++)); do
        echo -n " & (! received[${k}])" >>${out_file};
    done
    echo ";" >>${out_file};

    # 3. FLOW
#    echo "FLOW der(z) = 1;" >>${out_file};
    cat >> ${out_file} <<EOF 
FLOW
  (location = rest) -> der(z) = 0;
FLOW
  (location != rest) -> der(z) = 1;
EOF


    # 4. INVAR
    cat >>${out_file} <<EOF
    INVAR
    (location = rec -> z <= 1) &
    (location = wait -> z <= boundcontroller) & -- would be $((number_of_processes*20))
    (location = compute -> z <= computationtime); -- 10 z <= 56
EOF

    # 5. TRANS
    for ((k=1; k<=${number_of_processes}; k++)); do

        # send_k
        echo "TRANS " >>${out_file};
        echo "(EVENT = send_${k} -> (" >> ${out_file};

        echo "(location = rest & " >> ${out_file};
        echo "(! received[${k}]) & " >> ${out_file};
        echo "next(z) = 0 & next(location) = rec & next(received[${k}]) " >> ${out_file};
        print_fc_received "${out_file}" "${k}" "${number_of_processes}";
        echo " & TRUE)" >> ${out_file}

        echo "| (location = wait & " >> ${out_file};
        echo "(! received[${k}]) & " >> ${out_file};
        echo "next(z) = 0 & next(location) = rec & next(received[${k}]) " >> ${out_file};
        print_fc_received "${out_file}" "${k}" "${number_of_processes}";
        echo ")" >> ${out_file}
        echo "));" >> ${out_file}

        # ack_k
        echo "TRANS " >>${out_file};
        echo "(EVENT = ack_${k} -> (" >> ${out_file};

        echo "(location = rec & " >> ${out_file};
        echo "(received[${k}]) " >> ${out_file};

        # ! received[j], j != k
        echo -n "& ! (" >> ${out_file}
        first_elem="1"
        for ((j=1; j<=${number_of_processes}; j++)); do
            if [ $j != $k ]; then
                if [ "${first_elem}X" != "1X" ]; then
                    echo -n " & " >> ${out_file}
                fi
                echo -n "received[${j}]" >> ${out_file};
                first_elem=""
            fi            
        done
        echo -n ") " >> ${out_file}

        echo "& z >= waittime & next(z) = z & next(location) = wait " >> ${out_file};
        print_fc_received "${out_file}" "" "${number_of_processes}";
        echo ")" >> ${out_file}

        echo "| (location = rec " >> ${out_file};
        #big and event
        for ((j=1; j<=${number_of_processes}; j++)); do
            echo -n "& received[${j}]" >> ${out_file};
        done
        echo "& z >= waittime2 & next(z) = 0 & next(location) = compute" >> ${out_file};
        print_fc_received "${out_file}" "$" "${number_of_processes}";
        echo ")" >> ${out_file}
        echo "));" >> ${out_file}
    done # end of loop on each process for TRANS constraints

    # expire 
    echo "TRANS " >>${out_file};
    echo "(EVENT = expire -> (" >> ${out_file};

    echo "(location = wait & " >> ${out_file};
    #big and event
    echo -n "!(" >> ${out_file};
    for ((j=1; j<=${number_of_processes}; j++)); do
        if [ "${j}" != "1" ]; then
            echo -n "& received[${j}]" >> ${out_file};
        else 
            echo -n "received[${j}]" >> ${out_file};
        fi
    done
    echo -n ")" >> ${out_file};
    echo "& next(z) = z " >> ${out_file};
    echo "& next(location) = rest " >> ${out_file};
    for ((j=1; j<=${number_of_processes}; j++)); do
        echo -n "& !next(received[${j}])" >> ${out_file};
    done
    echo ")" >> ${out_file}
    echo "));" >> ${out_file}

    # signal
    echo "TRANS " >>${out_file};
    echo "(EVENT = signal -> (" >> ${out_file};
    echo "(location = compute & " >> ${out_file};
    echo "z >= mincomputationtime & next(location) = rest " >> ${out_file};
    echo " & next(z) = z " >> ${out_file};
    for ((j=1; j<=${number_of_processes}; j++)); do
        echo -n "& !next(received[${j}])" >> ${out_file};
    done
    echo ")" >> ${out_file}
    echo "));" >> ${out_file}
}

# print the safe invariant
print_safe_invar()
{
    local out_file=$1
    local c=$2

    local sametime=

    local last=
    echo -n "INVARSPEC !(" >> ${out_file}
    for (( i=1; i<=$c; i++ )); do
        if [ "${i}" == "1" ]; then
            echo -n "sensor_${i}.location = send" >> "${out_file}"
        else
            echo -n " & sensor_${i}.location = send " >> "${out_file}"
            
            sametime="${sametime} & sensor_${i}.time = sensor_$(($i-1)).time";
        fi
        last=$i
    done
    sametime="${sametime} & sensor_${last}.time = sensor_$(($last-1)).time";
    
    sametime="${sametime} & sensor_${last}.time = controller.time & controller.time = scheduler.time";
    
#    echo " ${sametime})" >> ${out_file}
    echo " )" >> ${out_file}
}


# read parameters
lower=
upper=
while [ "${1}" != "" ]; do
    case "${1}" in
        -lower)
            shift
            if [ "${1}" == "" ]; then
                echo "No lower bound provided!"
                usage
            else
                lower="${1}"
                shift
            fi
            ;;
        -upper)
            shift
            if [ "${1}" == "" ]; then
                echo "No upper bound provided!"
                usage
            else
                upper="${1}"
                shift
            fi
            ;;
        *)
            echo "Unknown parameter ${1}"
            usage
    esac
done

check_bound "${lower}"
check_bound "${upper}"

if [ $upper -lt $lower ]; then
    echo "Upper bound is less than lower bound!";
    usage
fi

for (( c=$lower; c<=$upper; c++ )); do
    if [ $c -lt 10 ]; then
        prefix="0";
    else
        prefix=""
    fi
 
    out_file="dist_controller_${prefix}${c}.hydi";

    if [ -e "${out_file}" ]; then
        rm ${out_file}
    fi
    echo "processing ${c}/${upper}";

    date=`date`
    echo "-- Generated on ${date}" >> ${out_file}

    # print common part in main
    print_common_part "${out_file}"

    # print var definition
    echo "VAR" >> "${out_file}"
    for (( i=1; i<=$c; i++ )); do
        to_limit=$((i*4));

        echo "sensor_${i} : SensorType(${to_limit}, def_inity_par, def_sampletime_par);" >> "${out_file}"
    done
    echo "scheduler: SchedulerType(invarscheduler_par, def_computation_offset_par);" >> ${out_file}
    echo "controller: ControllerType(invar_on_rec_par, boundcontroller_par, waittime_par, waittime2_par, computationtime_par, mincomputationtime_par);" >> ${out_file}
    echo "" >> "${out_file}"
    echo "-- Synchronization constraints" >> ${out_file}


    # print sync actions
    for (( i=1; i<=$c; i++ )); do
        echo "-- synch of sensor_${i} with scheduler" >> ${out_file}
        echo "SYNC sensor_${i}, scheduler EVENTS request_evt, request_${i};" >>${out_file};
        echo "SYNC sensor_${i}, scheduler EVENTS read_evt, read_${i};" >> ${out_file}

        echo "-- synch of sensor_${i} with controller" >> ${out_file}
# removed urgency condition
#        echo "SYNC sensor_${i}, controller EVENTS send_evt, send_${i} CONDITION u, sensors_u_must_be_0;" >> ${out_file}
        echo "SYNC sensor_${i}, controller EVENTS send_evt, send_${i};" >> ${out_file}
        echo "SYNC sensor_${i}, controller EVENTS ack_evt, ack_${i};" >> ${out_file}
    done

    echo "" >> "${out_file}"

#     cat >> ${out_file} <<EOF
# LTLSPEC G !(sensor_1.location = send & sensor_2.location = send  )
# LTLSPEC (G F ((controller.received[1] & controller.received[2]))) -> (G ((controller.received[1] & controller.received[2]) -> F (controller.location = compute) ));

# -- automatically generated
# LTLSPEC G (rest = controller.location ->  F rest = controller.location)
# LTLSPEC G (rest = controller.location ->  F rec = controller.location)
# LTLSPEC G (rest = controller.location ->  F wait = controller.location)
# LTLSPEC G (rest = controller.location ->  F compute = controller.location)
# LTLSPEC G (rec = controller.location ->  F rest = controller.location)
# LTLSPEC G (rec = controller.location ->  F rec = controller.location)
# LTLSPEC G (rec = controller.location ->  F wait = controller.location)
# LTLSPEC G (rec = controller.location ->  F compute = controller.location)
# LTLSPEC G (wait = controller.location ->  F rest = controller.location)
# LTLSPEC G (wait = controller.location ->  F rec = controller.location)
# LTLSPEC G (wait = controller.location ->  F wait = controller.location)
# LTLSPEC G (wait = controller.location ->  F compute = controller.location)
# LTLSPEC G (compute = controller.location ->  F rest = controller.location)
# LTLSPEC G (compute = controller.location ->  F rec = controller.location)
# LTLSPEC G (compute = controller.location ->  F wait = controller.location)
# LTLSPEC G (compute = controller.location ->  F compute = controller.location)
# LTLSPEC G (idle = scheduler.location ->  F idle = scheduler.location)
# LTLSPEC G (idle = scheduler.location ->  F loc_sensor_1 = scheduler.location)
# LTLSPEC G (idle = scheduler.location ->  F loc_sensor_2 = scheduler.location)
# LTLSPEC G (loc_sensor_1 = scheduler.location ->  F idle = scheduler.location)
# LTLSPEC G (loc_sensor_1 = scheduler.location ->  F loc_sensor_1 = scheduler.location)
# LTLSPEC G (loc_sensor_1 = scheduler.location ->  F loc_sensor_2 = scheduler.location)
# LTLSPEC G (loc_sensor_2 = scheduler.location ->  F idle = scheduler.location)
# LTLSPEC G (loc_sensor_2 = scheduler.location ->  F loc_sensor_1 = scheduler.location)
# LTLSPEC G (loc_sensor_2 = scheduler.location ->  F loc_sensor_2 = scheduler.location)
# LTLSPEC G (done = sensor_2.location ->  F done = sensor_2.location)
# LTLSPEC G (done = sensor_2.location ->  F read = sensor_2.location)
# LTLSPEC G (done = sensor_2.location ->  F wait = sensor_2.location)
# LTLSPEC G (done = sensor_2.location ->  F send = sensor_2.location)
# LTLSPEC G (read = sensor_2.location ->  F done = sensor_2.location)
# LTLSPEC G (read = sensor_2.location ->  F read = sensor_2.location)
# LTLSPEC G (read = sensor_2.location ->  F wait = sensor_2.location)
# LTLSPEC G (read = sensor_2.location ->  F send = sensor_2.location)
# LTLSPEC G (wait = sensor_2.location ->  F done = sensor_2.location)
# LTLSPEC G (wait = sensor_2.location ->  F read = sensor_2.location)
# LTLSPEC G (wait = sensor_2.location ->  F wait = sensor_2.location)
# LTLSPEC G (wait = sensor_2.location ->  F send = sensor_2.location)
# LTLSPEC G (send = sensor_2.location ->  F done = sensor_2.location)
# LTLSPEC G (send = sensor_2.location ->  F read = sensor_2.location)
# LTLSPEC G (send = sensor_2.location ->  F wait = sensor_2.location)
# LTLSPEC G (send = sensor_2.location ->  F send = sensor_2.location)
# LTLSPEC G (done = sensor_1.location ->  F done = sensor_1.location)
# LTLSPEC G (done = sensor_1.location ->  F read = sensor_1.location)
# LTLSPEC G (done = sensor_1.location ->  F wait = sensor_1.location)
# LTLSPEC G (done = sensor_1.location ->  F send = sensor_1.location)
# LTLSPEC G (read = sensor_1.location ->  F done = sensor_1.location)
# LTLSPEC G (read = sensor_1.location ->  F read = sensor_1.location)
# LTLSPEC G (read = sensor_1.location ->  F wait = sensor_1.location)
# LTLSPEC G (read = sensor_1.location ->  F send = sensor_1.location)
# LTLSPEC G (wait = sensor_1.location ->  F done = sensor_1.location)
# LTLSPEC G (wait = sensor_1.location ->  F read = sensor_1.location)
# LTLSPEC G (wait = sensor_1.location ->  F wait = sensor_1.location)
# LTLSPEC G (wait = sensor_1.location ->  F send = sensor_1.location)
# LTLSPEC G (send = sensor_1.location ->  F done = sensor_1.location)
# LTLSPEC G (send = sensor_1.location ->  F read = sensor_1.location)
# LTLSPEC G (send = sensor_1.location ->  F wait = sensor_1.location)
# LTLSPEC G (send = sensor_1.location ->  F send = sensor_1.location)
# EOF

    # echo "-- no deadlock - not proved" >> ${out_file}
    # echo -n "LTLSPEC" >> ${out_file}
    # echo -n " (G F sensor_1.location = done)" >> ${out_file}
    # for (( i=2; i<=$c; i++ )); do        
    #     echo -n " | (G F sensor_${i}.location = done)" >> ${out_file}
    # done
    # echo "" >> ${out_file}

    # echo -n "LTLSPEC" >> ${out_file}
    # echo -n " (G F (controller.received[1] " >> ${out_file}
    # for (( i=2; i<=$c; i++ )); do        
    #     echo -n " & controller.received[${i}] " >> ${out_file}
    # done
    # echo -n ")) -> " >> ${out_file}
    # echo -n "(G F (sensor_1.location = done " >> ${out_file}
    # for (( i=2; i<=$c; i++ )); do        
    #     echo -n " & sensor_${i}.location = done" >> ${out_file}
    # done
    # echo "))" >> ${out_file}

    # for (( i=1; i<=$c; i++ )); do        
    #     echo "LTLSPEC (G F controller.location = compute) -> (G F sensor_${i}.location = done)" >> ${out_file}
    # done

    print_safe_invar "${out_file}" "${c}"

    # print mirrors for the locations
    echo "" >> "${out_file}"
    # c sensors
    for (( i=1; i<=$c; i++ )); do
        echo "-- MIRROR sensor_${i}.location" >> "${out_file}"
    done
    # controller
    echo "-- MIRROR controller.location" >> "${out_file}"
    # scheduler
    echo "-- MIRROR scheduler.location" >> "${out_file}"
    echo "" >> "${out_file}"        

    # print process definition
    print_sensor_definition "${out_file}"

    # print scheduler var definition
    print_scheduler_definition "${out_file}" "${c}"

    # print the controller definition
    print_controller_definition "${out_file}" "${c}"
done
