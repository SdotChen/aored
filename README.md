# AO_RED

An ASIC-oriented queue management algorithm based on Tofino **SDE 9.7.0**.

## How to compile the program?

We have write a script `bianyi.sh` to fast compile the program. Just need:

 `bash bianyi.sh $PWD/ao_red.p4`

**Note**: Variable $SDE should be correctly set.

## How to run the program?

`$SDE/run_switchd.sh -p ao_red`

## Scripts

| file                 | description                                                  | Usage                                            |
| -------------------- | ------------------------------------------------------------ | ------------------------------------------------ |
| add-port.txt         | Add and enable the ports.                                    | $SDE/run_bfshell.sh -f add_port.txt              |
| drop_prob_mapping.py | Help get the prob for recirculate packets.                   | $SDE/run_bfshell.sh -b $PWD/drop_prob_mapping.py |
| drop_prob_clear.py   | For convenient param tuning. If the table `map_qdepth_to_prob_t` has entries, `drop_prob_mapping.py` can be used again after  `drop_prob_clear.py` is used. | $SDE/run_bfshell.sh -b $PWD/drop_prob_clear.py   |
| flowtable.py         | Set the target egress port according to packet's IP dst addr. | $SDE/run_bfshell.sh -b $PWD/flowtable.py         |
| mcast_table.py       | Multicast settings.                                          | $SDE/run_bfshell.sh -b $PWD/mcast_table.py       |
| meter_conf.py        | Set the R and the target port for metering.                  | $SDE/run_bfshell.sh -b $PWD/meter_conf.py        |
| mod_mac.py           | Modify the MAC dst addr.                                     | $SDE/run_bfshell.sh -b $PWD/mod_mac.py           |

