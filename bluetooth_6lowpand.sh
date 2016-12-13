#!/bin/bash

CONTROLLER_PATH="/sys/kernel/debug/bluetooth/6lowpan_control"
CONFIG_PATH="/etc/bluetooth/bluetooth_6lowpand.conf"
CONFIG_SWP_PATH="/etc/bluetooth/bluetooth_6lowpand.conf.swp"
MACADDR_REGEX="^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$"
BT_NODE_FILTER="Linaro"

DEFAULT_SCANNING_WINDOW=5
DEFAULT_SCANNING_INTERVAL=10

MAX_SCANNING_WINDOW=30
MAX_SCANNING_INTERVAL=300

option_ignore_filter=0

# OPTIONS
#	device
#	use-whitelist
#	scanning window
#	scanning interval
#	daemonize
#	help

# SUBCMDS
#	addwl:		Add device into white list
#	rmwl:		Remove device from white list
#	clearwl:	Clear the white list
#	lswl:		List the white list
#	lscon:		List the 6lowpan connections

# >ADD WHITELIST
#  hcitool lewladd <bdaddr>

# >REMOTE WHITELIST
#  hcitool lewlrm <bdaddr>

# >CLEAR WHITELIST
#  hcitool lewlclr

# >LIST WHITELIST
# cat /etc/bluetooth/bluetooth_6lowpand.conf

# >LIST CONNNECTIONS
# cat /sys/kernel/debug/bluetooth/6lowpan_control
#  d6:e7:34:18:4e:42 (type 2)
#  d6:e7:34:17:50:3d (type 2)
#  d6:e7:34:18:45:39 (type 2)
#  d6:e7:34:18:3c:11 (type 2)
#  d6:e7:34:17:6b:48 (type 2)
#  d6:e7:34:17:5a:48 (type 2)

function write_log {
	echo "$(date +%Y%m%d-%k%M%S) :: ${@}" >&2
}

function connect_device {
	local __addr=${1}
	local __connect=${2}
	local __device_cmd

	if [ "${__connect}" == "1" ]; then
		__device_cmd="connect ${__addr} 2"
	else
		__device_cmd="disconnect ${__addr} 2"
	fi
	echo "${__device_cmd}" > ${CONTROLLER_PATH}
}

function find_ipsp_device {
	local __timeout=${1}
	local __found_devices
	local __pid=0
	local __check_pid=0
	local __found_mac=0

	local __command_buf=$(
		nohup hcitool lescan 2>&1 &
		__pid=$!
		sleep ${__timeout}
		# check if PID is running
		__check_pid=$(ps xu | grep -v grep | awk '{ print $2 }' | grep ${__pid})
		if [ "$?" == "0" ]; then
			kill -SIGINT ${__pid}
		fi
	)

	# Lines will start with MAC and then description broken by returns:
	# Return the first MAC which is followed by BT_NODE_FILTER match
	local __lines=$(echo ${__command_buf} | tr "\r" "\n")
	for __line in ${__lines}; do
		if [[ "${__line}" =~ ${MACADDR_REGEX} ]]; then
			__found_devices=${__line}
		else
			if [ ! -z "${__found_devices}" ]; then
				if [ "${option_ignore_filter}" == "1" ] | [ "${__line}" == "${BT_NODE_FILTER}" ]; then
					# TODO check whitelist
					write_log "FOUND NODE: ${__found_devices}"
					connect_device ${__found_devices} 1
					# BUG: wait 1s before continue
					sleep 1s
				fi
			fi
			__found_devices=""
		fi
	done
}

timeout="${DEFAULT_SCANNING_WINDOW}s"
interval="${DEFAULT_SCANNING_INTERVAL}s"

# INIT bluetooth modules / reset hci0
# TODO: parse --bt-interface for "hci0"
modprobe bluetooth_6lowpan
sleep 1
echo 1 > /sys/kernel/debug/bluetooth/6lowpan_enable
sleep 1
hciconfig hci0 reset
sleep 1

# TASKS on start:
# TODO: parse for --timeout value
# TODO: parse for --interval value

# ENTER daemon loop to connect Linaro FOTA BT devices
while :; do
	find_ipsp_device ${timeout}
	sleep ${interval}
done
# EXIT daemon loop
