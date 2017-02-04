# Scripts that generates the scalable rod model
#
import os, sys                   
import string
import subprocess
import tempfile
import optparse

MODEL_NAME_PREFIX="dist_controller"

SENS_TEMPLATE="""
  <component id="SensorType">
    <param name="lost_packet_time" type="real" local="false" d1="1" d2="1" dynamics="const" />
    <param name="y" type="real" local="true" d1="1" d2="1" dynamics="any" />
    <param name="request_evt" type="label" local="false" />
    <param name="read_evt" type="label" local="false" />
    <param name="send_evt" type="label" local="false" />
    <param name="ack_evt" type="label" local="false" />
    <location id="1" name="done" x="257.0" y="127.0">
      <invariant>y &lt;= 1</invariant>
      <flow>y' == 1</flow>
    </location>
    <location id="2" name="read" x="509.0" y="133.0">
      <flow>y' == 0</flow>
    </location>
    <location id="3" name="wait" x="515.0" y="291.0">
      <invariant>y &lt;= lost_packet_time</invariant>
      <flow>y' == 1</flow>
    </location>
    <location id="4" name="send" x="258.0" y="289.0">
      <flow>y' == 0</flow>
    </location>
    <transition source="1" target="2">
      <label>request_evt</label>
      <guard>y &gt;= 1</guard>
      <labelposition x="-21.0" y="-49.0" />
    </transition>
    <transition source="2" target="3">
      <label>read_evt</label>
      <assignment>y = 0</assignment>
      <labelposition x="11.0" y="-16.0" />
      <middlepoint x="573.0" y="210.0" />
    </transition>
    <transition source="3" target="4">
      <label>send_evt</label>
      <labelposition x="0.0" y="0.0" />
    </transition>
    <transition source="4" target="1">
      <label>ack_evt</label>
      <assignment>y = 0</assignment>
      <labelposition x="0.0" y="-15.0" />
    </transition>
    <transition source="3" target="2">
      <label>request_evt</label>
      <guard>y &gt;= lost_packet_time</guard>
      <labelposition x="-57.0" y="-20.0" />
      <middlepoint x="431.0" y="211.0" />
    </transition>
  </component>
"""
SCHED_TEMP="""  <component id="SchedulerType">
    ${wait_vars}
    ${clock_vars}
    ${events}
    <location id="1" name="idle" x="361.0" y="178.0">
    <flow>${fc_zero}</flow>
    </location>
    ${sens_loc}
    ${idle2loc}
    ${loc2idle}
    ${setwaitloc}
    ${preemption}
    ${giveback}
  </component>
"""
WAIT_TMP="""<param name="wait${i}" type="real" local="true" d1="1" d2="1" dynamics="any" />"""
WAIT_FC_TMP="""wait${i}' == 0"""
CLOCK_VAR_TMP=""" <param name="x${i}" type="real" local="true" d1="1" d2="1" dynamics="any" />
"""
EVENTS_TMP="""<param name="read_${i}" type="label" local="false" />
    <param name="request_${i}" type="label" local="false" />
"""
FC_ZERO_TMP="""x${i}' == 0"""
SENS_LOC_TMP="""    <location id="${j}" name="loc_sensor_${i}" x="161.0" y="372.0">
      <invariant>${loc_invar}</invariant>
      <flow>${loc_fc}</flow>
    </location>
"""
IDLE2LOC_TMP="""
    <transition source="1" target="${j}">
      <label>request_${i}</label>
      <assignment>x${i} = 0</assignment>
      <labelposition x="0.0" y="0.0" />
      <middlepoint x="209.0" y="212.0" />
    </transition>
"""
LOC2IDLE_TMP="""
    <transition source="${j}" target="1">
      <label>read_${i}</label>
      <guard>x${i} &gt;= ${i} * 0.3125 &amp; ${wait_all_zero}</guard>
      <labelposition x="16.0" y="0.0" />
      <middlepoint x="301.0" y="281.0" />
    </transition>
"""
SET_WAIT_TMP="""
<!-- wait -->
    <transition source="${j}" target="${j}">
      <label>request_${i}</label>
      <assignment>wait${i} = 1</assignment>
    </transition>
"""
PREEMPT_TMP="""
<!-- preemption -->
    <transition source="${id_source}" target="${id_target}">
      <label>request_${index_target}</label>
      <assignment>wait${index_source} = ${index_source} &amp; x${index_target} = 0</assignment>
      <labelposition x="0.0" y="0.0" />
      <middlepoint x="371.5" y="464.5" />
    </transition>
"""
GIVEBACK_TMP="""
<!-- giveback -->
    <transition source="${id_source}" target="${id_target}">
      <label>read_${index_source}</label>
      <guard>x${index_source} &gt;= (${index_source}*0.3125) &amp; wait${index_target} == 1 ${less_zero} </guard>
      <assignment>wait${index_target} = 0</assignment>
      <labelposition x="-23.0" y="-52.0" />
    </transition>
"""
CONT_TEMP="""
  <component id="ControllerType">
    <param name="z" type="real" local="true" d1="1" d2="1" dynamics="any" />
    ${cont_param}
    <location id="1" name="rest" x="631.0" y="171.0">
      <flow>z' == 0 &amp; ${received_flow}</flow>
    </location>
    <location id="2" name="rec" x="293.0" y="170.0">
      <invariant>z &lt;= 1</invariant>
      <flow>z' == 1 &amp; ${received_flow}</flow>
    </location>
    <location id="3" name="wait" x="291.0" y="442.0">
      <invariant>z &lt;= 1</invariant>
      <flow>z' == 1 &amp; ${received_flow}</flow>
    </location>
    <location id="4" name="compute" x="654.0" y="446.0">
      <invariant>z &lt;= 1</invariant>
      <flow>z' == 1 &amp; ${received_flow}</flow>
    </location>
    <transition source="4" target="1">
      <label></label>
      <guard>z &gt;= 1.25</guard>
      <assignment>${all_rec_set_1}</assignment>
      <labelposition x="0.0" y="0.0" />
    </transition>
    ${cont_trans}
  </component>
"""
#  received1==1 &amp;&amp; received2 == 1
# received$1 = 0 &amp; received2 = 0
# received1 = 0 &amp; received2 = 0
CONT_TRANS="""
    <transition source="1" target="2">
      <label>send_${i}</label>
      <guard>received${i} == 0</guard>
      <assignment>z = 0 &amp; received${i} = 1</assignment>
      <labelposition x="-19.0" y="-7.0" />
    </transition>
    <transition source="3" target="2">
      <label>send_${i}</label>
      <guard>received${i} == 0</guard>
      <assignment>z = 0 &amp; received${i} = 1</assignment>
      <labelposition x="22.0" y="-7.0" />
      <middlepoint x="331.0" y="320.5" />
    </transition>
    <transition source="2" target="3">
      <label>ack_${i}</label>
      <guard>z &gt;= 0.25 &amp; received1==0</guard>
      <labelposition x="-61.0" y="-20.0" />
      <middlepoint x="232.0" y="315.5" />
    </transition>
    <transition source="2" target="4">
      <label>ack_${i}</label>
      <guard>z &gt;= 0.25 &amp; ${all_rec_eq_1}</guard>
      <assignment>z = 0</assignment>
      <labelposition x="-21.0" y="-67.0" />
    </transition>
    <transition source="3" target="1">
      <label></label>
      <guard>${all_sum} &lt; ${num}</guard>
      <assignment>${all_rec_set_to_0}</assignment>
      <labelposition x="-21.0" y="25.0" />
      <middlepoint x="475.0" y="384.5" />
    </transition>
"""
CONT_PARAM="""
    <param name="received${i}" type="real" local="true" d1="1" d2="1" dynamics="any" />
    <param name="send_${i}" type="label" local="false" />
    <param name="ack_${i}" type="label" local="false" />
"""

SYS_TEMPLATE="""
  <component id="sys">
  ${events}

  ${bindings}
  </component>
"""
BIND_SENS="""    <bind component="SensorType" as="sensor_${i}" x="449.0" y="207.0">
      <map key="lost_packet_time">${lpvalue}</map>
      <map key="request_evt">request_${i}</map>
      <map key="read_evt">read_${i}</map>
      <map key="send_evt">send_${i}</map>
      <map key="ack_evt">ack_${i}</map>
    </bind>
"""
BIND_SCHED="""    <bind component="SchedulerType" as="scheduler" x="463.0" y="415.0">
      ${bind_evts}
    </bind>
"""
BIND_SCHED_EVT="""      <map key="read_${i}">read_${i}</map>
      <map key="request_${i}">request_${i}</map>
"""
BIND_CONT="""    <bind component="ControllerType" as="controller" x="471.0" y="586.0">
${bind_evts}
    </bind>
"""
BIND_CONT_EVT="""      <map key="send_${i}">send_${i}</map>
      <map key="ack_${i}">ack_${i}</map>
"""

SYS_EVT_TMP="""
    <param name="read_${i}" type="label" local="false" />
    <param name="request_${i}" type="label" local="false" />
    <param name="send_${i}" type="label" local="false" />
    <param name="ack_${i}" type="label" local="false" />
"""

MAIN_TEMPLATE="""<?xml version="1.0" encoding="iso-8859-1"?>
<sspaceex xmlns="http://www-verimag.imag.fr/xml-namespaces/sspaceex" version="0.2" math="SpaceEx">
${sens_def}
${sched_def}
${cont_def}
${sys_def}
</sspaceex>
"""

CFG_TEMPLATE="""# analysis options
scenario = "phaver"
system = "sys"
initially = "${loc_init}"
forbidden = "${loc_forbidden}"
output-format = "TXT"
iter-max = -1
time-horizon = -1
"""

INIT_CONTROLLER="loc(controller) == rest & controller.z == 0 & ${rec_all_zero}"
INIT_SCHED="loc(scheduler) == idle & ${x_all_zero} & ${wait_all_zero}"
INIT_SENS="loc(sensor_${i}) == done & sensor_${i}.y == 1"
LOC_FORB_TEMP="""(loc(sensor_${i}) == send)"""

def subs_string(template, submap):
    return string.Template(template).safe_substitute(submap)

def gen_sched(num):
    clock_var="".join([subs_string(CLOCK_VAR_TMP, {'i' : i+1}) for i in range(num)])
    wait_decl="\n".join([subs_string(WAIT_TMP, {'i' : i+1}) for i in range(num)])
    events="".join([subs_string(EVENTS_TMP, {'i' : i+1}) for i in range(num)])
    fc_zero=" &amp; ".join([subs_string(FC_ZERO_TMP, {'i' : i+1}) for i in range(num)])    
    wait_fc=" &amp; ".join([subs_string(WAIT_FC_TMP, {'i' : i+1}) for i in range(num)])
    fc_zero += " &amp; %s" % (wait_fc)

    sens_loc = ""
    for i in range(num):
        i_index = str(i+1)
        loc_invar = "x%s &lt;= %d" % (i_index, (i+1) * 4)
        loc_fc = []
        for j in range(num):
            if i == j: continue
            j_index = str(j+1)
            elem = subs_string(FC_ZERO_TMP, {'i' : j_index})
            loc_fc.append(elem)
        elem = subs_string("x${i}' == 1", {'i' : i_index})
        loc_fc.append(elem)
        loc_fc_str=" &amp; ".join(loc_fc)
        loc_fc_str += " &amp; %s" % (wait_fc)
        idstr = str(i+2)
        loc = subs_string(SENS_LOC_TMP, {'i' : i_index, 'j' : idstr,
                                         'loc_invar' : loc_invar,
                                         'loc_fc' : loc_fc_str})
        sens_loc += loc
    idle2loc="\n".join([subs_string(IDLE2LOC_TMP, {'i' : i+1, 'j' : i+2}) for i in range(num)])

    wait_all_zero=" &amp; ".join([subs_string("wait$i == 0", {'i' : i+1}) for i in range(num)])
    loc2idle=""
    for i in range(num):
        loc2idle += "\n" + subs_string(LOC2IDLE_TMP, {'i' : i+1, 'j' : i+2,
                                                      'wait_all_zero' : wait_all_zero})


    setwaitloc=""
    for i in range(num):
        for j in range(i):
            waittrans=subs_string(SET_WAIT_TMP, {'i' : j+1, 'j' : i+2})
            setwaitloc+=waittrans
                            
    preemption=""
    for i in range(num-1):
        for j in range(num-i-1):
            index_source = i+1
            id_source = index_source + 1
            index_target = index_source + j + 1
            id_target = index_target + 1

            trans=subs_string(PREEMPT_TMP, {'index_source' : index_source,
                                            'id_source' : id_source,
                                            'index_target' : index_target,
                                            'id_target' : id_target})
            preemption+=trans

    giveback=""
    for i in range(num-1):
        index_target = i+1
        id_target = index_target + 1

        todo = num - (i + 1)
        for j in range(todo):
            index_source = index_target + j + 1
            id_source = index_source + 1

            less_zero_list = [subs_string("wait$i == 0", {'i' : z+index_target+1}) for z in range(index_source - index_target - 1)]
            less_zero=" &amp; ".join(less_zero_list)
            if (less_zero != ""):
                less_zero = " &amp; " + less_zero
            trans=subs_string(GIVEBACK_TMP, {'index_source' : index_source,
                                             'id_source' : id_source,
                                             'index_target' : index_target,
                                             'id_target' : id_target,
                                             'less_zero' : less_zero})
            giveback+=trans

    submap = {'wait_vars' : wait_decl, 'clock_vars' : clock_var,
              'events' : events, 'fc_zero' : fc_zero,
              'sens_loc' : sens_loc, 'idle2loc' : idle2loc,
              'loc2idle' : loc2idle, 'setwaitloc' : setwaitloc,
              'preemption' : preemption, 'giveback' : giveback}

    sched_def = subs_string(SCHED_TEMP, submap)
    return sched_def


def gen_cont(num):
    cont_param = "".join([subs_string(CONT_PARAM, {'i' : i+1}) for i in range(num)])


    received_flow = " &amp; ".join([subs_string("received${i}'==0", {'i' : i+1}) for i in range(num)])
    all_rec_set_1 = " &amp; ".join([subs_string("received${i}=1", {'i' : i+1}) for i in range(num)])
    all_rec_set_0 = " &amp; ".join([subs_string("received${i}=0", {'i' : i+1}) for i in range(num)])
    all_rec_eq_1 = " &amp; ".join([subs_string("received${i}==1", {'i' : i+1}) for i in range(num)])
    all_sum = " + ".join([subs_string("received${i}", {'i' : i+1}) for i in range(num)])

    cont_trans = "".join([subs_string(CONT_TRANS, {'i' : i+1, 'all_rec_eq_1' : all_rec_eq_1, 'all_sum' : all_sum, 'num' : num, 'all_rec_set_to_0' : all_rec_set_0}) for i in range(num)])

    subs_map = {'cont_param' : cont_param,
                'received_flow' : received_flow,
                'all_rec_set_1' : all_rec_set_1,
                'cont_trans' : cont_trans}
    cont_def = subs_string(CONT_TEMP, subs_map)
    return cont_def    

def sys_def(num):
    events = "".join([subs_string(SYS_EVT_TMP, {'i' : (i+1)}) for i in range(num)])

    bind_sens = "".join([subs_string(BIND_SENS, {'i' : (i+1), 'lpvalue' : (i*4)}) for i in range(num)])
    bind_sched_evt = "".join([subs_string(BIND_SCHED_EVT, {'i' : (i+1)}) for i in range(num)])
    bind_sched = subs_string(BIND_SCHED, {'bind_evts' : bind_sched_evt})
    bind_cont_evt = "".join([subs_string(BIND_CONT_EVT, {'i' : (i+1)}) for i in range(num)])
    bind_cont = subs_string(BIND_CONT, {'bind_evts' : bind_cont_evt})
    bindings = bind_sens + bind_sched + bind_cont

    sm = {'events' : events, 'bindings' : bindings}
    sysdef = subs_string(SYS_TEMPLATE, sm)
    return sysdef


def main():
    p = optparse.OptionParser()
    p.add_option('-n', '--num', help="Number of processes")
    def usage(msg=""):
        if msg:
            print msg
        p.print_help()
        sys.exit(1)

    opts, args = p.parse_args()
    if not opts.num:
        usage("No number of processes provided")
    try:
        num = int(opts.num)
    except Exception as e:
        print "Num is not a number!"
        sys.exit(1)    
    if (num < 2):
        print "Num cannot be lower than 2!"
        sys.exit(1)

    # generate model
    if (num < 10):
        zeros = "0"
    else:
        zeros = ""
    model_name="%s_%s%d.xml" % (MODEL_NAME_PREFIX, zeros, num)
    config_name="%s_%s%d.cfg" % (MODEL_NAME_PREFIX, zeros, num)
    config_cfg1_name="%s_%s%d.cfg1" % (MODEL_NAME_PREFIX, zeros, num)
        
    with open(model_name, 'w') as f:
        sens_def = SENS_TEMPLATE
        sched_def = gen_sched(num)
        cont_def = gen_cont(num)
        sysdef = sys_def(num)

        model_str = subs_string(MAIN_TEMPLATE, {'sens_def' : sens_def,
                                                'sched_def' : sched_def,
                                                'cont_def' : cont_def,
                                                'sys_def' : sysdef})
        f.write(model_str)

    fcfg1 = open(config_cfg1_name, 'w')
    with open(config_name, 'w') as f:
        rec_zero = " & ".join([subs_string("controller.received${i}==0", {'i' : i+1}) for i in range(num)])
        init_cont = subs_string(INIT_CONTROLLER, {'rec_all_zero' : rec_zero})

        x_zero = " & ".join([subs_string("scheduler.x${i}==0", {'i' : i+1}) for i in range(num)])
        wait_zero = " & ".join([subs_string("scheduler.wait${i}==0", {'i' : i+1}) for i in range(num)])
        init_sched = subs_string(INIT_SCHED, {'x_all_zero' : x_zero, 'wait_all_zero' : wait_zero})
        init_sens = " & ".join([subs_string(INIT_SENS, {'i' : i+1}) for i in range(num)])

        init = init_cont + " & " + init_sched + " & " + init_sens

        forbidden= "&".join([subs_string(LOC_FORB_TEMP, {'i' : i+1}) for i in range(num)])

        cfg_str = subs_string(CFG_TEMPLATE, {'loc_init' : init,
                                             'loc_forbidden' : forbidden})
        f.write(cfg_str)
        config_cfg1_name = cfg_str + """
        directions = box
        set-aggregation = chull
        verbosity = l
        """
        fcfg1.write(cfg_str)

    return 0

if __name__ == '__main__':
    main()
