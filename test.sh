#!/bin/bash

set -euo pipefail

NUM_FAIL=0
NUM_PASS=0

test_command () {
    local COMMAND="${1}"
    local EXPECTED_OUTPUT="${2}"
    set +e
    local TESTRESULT
    TESTRESULT=$(bash -c "${COMMAND}")
    local RETVAL=$?
    set -e
    if [[ "$TESTRESULT" == "${EXPECTED_OUTPUT}" ]]; then
      echo "${COMMAND} [ret=$RETVAL]: [output='$TESTRESULT'] ok"
      NUM_PASS=$((NUM_PASS + 1))
    else
      echo "${COMMAND} [ret=$RETVAL]: [output='$TESTRESULT'] fail  <<<<<<<<<<<<<<<<<"
      NUM_FAIL=$((NUM_FAIL + 1))
    fi
}

SPLENVPARTITION="/dev/disk/by-partlabel/bootenv"
DISKNAME="/dev/$(basename "$(readlink -f -- "/sys/class/block/$(basename "$(readlink -f -- ${SPLENVPARTITION})")/..")")"

# Setup permissions
chmod +x /tmp/splctl
makerootfsrw

ln -sf /tmp/uboot.env /boot/uboot/uboot.env

echo "----------------------------------------"
echo " now testing SPL mode"
echo "----------------------------------------"
echo "TEST1: --> this shows handling when BOOT_STATE_A / B is unset"
fw_printenv -c /tmp/spl_fw_env.config
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B
fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl get-boot-count A" "5"
test_command "/tmp/splctl get-boot-count B" "0"
test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
echo "----------------------------------------"

####################################################
echo "----------------------------------------"
echo "TEST2: --> this shows get-state / get-primary / set-state"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
test_command "/tmp/splctl set-primary B" ""
test_command "/tmp/splctl get-primary" "B"
test_command "/tmp/splctl set-primary A" ""
test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl set-state A bad" ""
test_command "/tmp/splctl set-state B good" ""
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST3: --> this shows handling of double quotes around variables"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A "1"
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B "1"
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "good"
echo "----------------------------------------"


echo "----------------------------------------"
echo "TEST4: --> this shows that the BOOT_STATE_A has precedence over the BOOT_COUNT_A"
echo "--> and if both BOOT_STATE_B and BOOT_COUNT_B are 0, then it is bad"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST5: --> this shows that the BOOT_STATE_B has precedence over the BOOT_COUNT_B"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST6: --> this shows that the BOOT_STATE_B when undefined will look at BOOT_COUNT_A / B"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "bad"
test_command "/tmp/splctl get-state B" "good"
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST7: --> this shows that the set-primary will also mark the slot good"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl set-state B bad" ""
test_command "/tmp/splctl get-state B" "bad"
test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl set-primary B" ""
test_command "/tmp/splctl get-state B" "good"
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST8: --> this shows that the BOOT_VALID_A/B works"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_B 0
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command  "/tmp/splctl get-valid A" "bad"
test_command  "/tmp/splctl get-valid B" "bad"
echo "----------------------------------------"


echo "----------------------------------------"
echo "TEST9: --> this shows that the BOOT_VALID_A/B works"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_B 1
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command  "/tmp/splctl get-valid A" "good"
test_command  "/tmp/splctl get-valid B" "good"
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST10: --> this runs the set-bootfw-slot command"
test_command "/tmp/splctl set-bootfw-slot A" ""
test_command "fw_printenv -c /tmp/spl_fw_env.config | grep BOOT_FW_SLOT" "BOOT_FW_SLOT=A"
test_command "/tmp/splctl set-bootfw-slot B" ""
test_command "fw_printenv -c /tmp/spl_fw_env.config | grep BOOT_FW_SLOT" "BOOT_FW_SLOT=B"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_FW_SLOT
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command "fw_printenv -c /tmp/spl_fw_env.config | grep BOOT_FW_SLOT" ""
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST11: --> this runs the get-bootfw-slot command"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOTED_FW_SLOT "A"
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command "/tmp/splctl get-bootfw-slot" "A"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOTED_FW_SLOT "B"
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command "/tmp/splctl get-bootfw-slot" "B"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOTED_FW_SLOT ""
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command "/tmp/splctl get-bootfw-slot" ""
echo "----------------------------------------"

echo "----------------------------------------"
echo "TEST12: --> this shows that the BOOT_VALID_A/B works with setrw set on the disk"
blockdev --setrw "${SPLENVPARTITION}" "${DISKNAME}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"
#leave the disk as writable
#blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
test_command "/tmp/splctl set-state B bad" ""
test_command "/tmp/splctl get-state B" "bad"
test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl set-primary B" ""
test_command "/tmp/splctl get-state B" "good"
#we should not have set the disk back to ro since it was set as rw in the first place (new functionality)
test_command "blockdev --getro ${SPLENVPARTITION}" "0"
test_command "blockdev --getro ${DISKNAME}" "0"
blockdev --setro "${SPLENVPARTITION}" "${DISKNAME}"
echo "----------------------------------------"

echo "Checking output of command when calling help etc"
test_command "/tmp/splctl --help" ""
test_command "/tmp/splctl" ""
test_command "/tmp/splctl -c xx" ""
echo "------------------------"
echo "Success: $NUM_PASS"
echo "Fails: $NUM_FAIL"

echo "done..."