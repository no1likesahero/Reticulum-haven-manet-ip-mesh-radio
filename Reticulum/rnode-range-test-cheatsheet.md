# RNode Range Test - Haven Gate Cheatsheet

## SSH into the gate
```bash
ssh root@192.168.0.119
# password: havengreen
```

## Start the ping script (survives disconnect)
```bash
screen -dmS ping python3 -u /root/gate_ping.py
```

## Reattach to see live output
```bash
screen -r ping
# Ctrl+A then D to detach
```

## Watch log from outside screen
```bash
screen -S ping -X hardcopy /tmp/gate_ping.log && cat /tmp/gate_ping.log
```

## Check if ping script is running
```bash
ps | grep gate_ping
```

## Stop the ping script
```bash
kill $(ps | grep gate_ping | grep -v grep | awk '{print $1}')
```

## Check RNode status (RSSI, SNR, battery, airtime)
```bash
rnstatus
```

## Check Reticulum interfaces
```bash
rnstatus -a
```

## Check known paths (confirm Tesla node is reachable)
```bash
rnpath -t
```

## Restart rnsd (if RNode interface is down)
```bash
/etc/init.d/rnsd restart
```

## Check rnsd is running
```bash
ps | grep rnsd | grep -v grep
```

## RNode config (frequency, bandwidth, SF, etc.)
```bash
cat /root/.reticulum/config
```

## Radio parameters for this test
- Frequency: 915 MHz
- Bandwidth: 125 kHz
- Spreading Factor: SF12
- Coding Rate: 4/5
- TX Power: 27 dBm
- Tesla LXMF: 7dba1291b0f92deabc530ef0968e7ca8
