# Shared benchmarks for the ARCH competition (http://cps-vo.org/group/ARCH/FriendlyCompetition)

The repository contains the definition of the benchmarks proposed for the ARCH competition.

The benchmarks are from the HPWC (Hybrid piece-wise constant) dynamic and can be used in the category HPWC.

Any question about the benchmark can be done to: sergio.mover <at> colorado.edu

The benchmarks are:
1. Distributed controller: The benchmarks is an extension of the benchmarks presented in [1].
It models the distributed controller
for a robot that reads and processes data from different sensors. A
scheduler component determines what sensor data must be read
(different sensors have different priorities, and higher priorities
sensors preempts lower priority sensors).

Each component (sensors, controller and scheduler) are modeled as
hybrid automata that are composed asynchronously, and communicate by
message passing.

The model extension w.r.t. [1] consists of adding multiple sensors
with multiple priorities.
While the benchmarks does not come from a real case study, it shows an
example of architecture of systems that can be found in real
applications (e.g. a control system that must consume data from
different sensors, where the data from some sensor is more critical
for the correct behavior of the system).

The problem is also a challenging instance for the verification tools:
- there are multiple, interacting asynchronous components.
As usual, adding a component increases the state space of the system.
- The system has several discrete states to track what sensor data has  been read and the status of each sensor.
Also this aspects is interesting 

- The dynamic of the system is pretty straightforward now, since there  are only stopwatches.
In principle the problem can be made more difficult by adding non-deterministic dynamic (e.g. the derivative can be in a range).

The model contains a safety property stating that it is never the case that all the sensors want to send data at the same time.


We provide the model for the benchmarks instances with an increasing
number of sensors (from 2 to 15) in thy hydi format (for the model
checker HyCOMP [2]) and in the SpaceEx format (for the model checker
SpaceEx [3]). In the latter case we also provide configurations files
that contains the initial and error condition and a setup of
parameters that can be used to verify the models.

The models are in the folders:
- `benchmarks/dist_controller/hydi`
- `benchmarks/dist_controller/spaceex`

We also provide two scripts `benchmarks/dist_controller/gen_dist_hydi.sh`
and `benchmarks/dist_controller/gen_dist_spaceex.py` to generate more
instances varying the number of sensors.


2. TTEThernet: this benchmark was proposed to ARCH by Christian Herrera, Sergy Bogomolov and Wilfred Steiner.

- Original reference from ARCH: http://cps-vo.org/group/ARCH/benchmarks

Here we provide a copy of their models.
Refer to the original documentation in `/benchmarks/TTEthernet/tt_ethernet_description.pdf`.



[1] ```
Hytech: The cornell hybrid technology tool.
Thomas A. Henzinger, Pei-Hsin Ho
Hybrid Systems 1994
```

[2] ```
HYCOMP: an SMT-based Model Checker for Hybrid Systems
Alessandro Cimatti, Alberto Griggio, Sergio Mover, and Stefano Tonetta
TACAS 2015
```

[3] ```
SpaceEx: Scalable Verification of Hybrid Systems.
Goran Frehse, Colas Le Guernic, Alexandre Donzé, Scott Cotton, Rajarshi Ray, Olivier Lebeltel, Rodolfo Ripado, Antoine Girard, Thao Dang, Oded Maler
CAV 2011
```

