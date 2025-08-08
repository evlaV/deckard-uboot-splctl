#!/bin/bash

set -euo pipefail

NUM_FAIL=0
NUM_PASS=0

test_command () {
    local COMMAND="${1}"
    local EXPECTED_OUTPUT="${2}"
    set +e
    local TESTRESULT=$(${COMMAND})
    local RETVAL=$?
    set -e
    if [[ "$TESTRESULT" == "${EXPECTED_OUTPUT}" ]]; then
      echo "${COMMAND} [ret=$RETVAL]: [output='$TESTRESULT'] ok"
      NUM_PASS=$(($NUM_PASS + 1))
    else
      echo "${COMMAND} [ret=$RETVAL]: [output='$TESTRESULT'] fail"
      NUM_FAIL=$(($NUM_FAIL + 1))
    fi
}

SPLENVPARTITION="/dev/disk/by-partlabel/bootenv"

# Setup permissions
chmod +x /tmp/splctl
makerootfsrw

echo "----------------------------------------"
echo "--> this shows the non-spl mode that is used with ev1 units that dont have spl"
touch /tmp/spl_mode_disable.txt
ln -s /tmp/uboot.env /boot/uboot/uboot.env

fw_setenv BOOT_ORDER "A B"
fw_setenv BOOT_A_LEFT 3
fw_setenv BOOT_B_LEFT 3
echo "------------------------------------------"
fw_printenv
echo "------------------------------------------"

test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl get-boot-count A" "3"
test_command "/tmp/splctl get-boot-count B" "3"
test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "good"

fw_setenv BOOT_ORDER "B A"
fw_setenv BOOT_A_LEFT 0
fw_setenv BOOT_B_LEFT 3
echo "------------------------------------------"
fw_printenv
echo "------------------------------------------"

test_command "/tmp/splctl get-primary" "B"
test_command "/tmp/splctl get-boot-count A" "0"
test_command "/tmp/splctl get-boot-count B" "3"
test_command "/tmp/splctl get-state A" "bad"
test_command "/tmp/splctl get-state B" "good"

fw_setenv BOOT_ORDER "B A"
fw_setenv BOOT_A_LEFT 0
fw_setenv BOOT_B_LEFT 3
echo "------------------------------------------"
fw_printenv
echo "------------------------------------------"

test_command "/tmp/splctl get-primary" "B"
test_command "/tmp/splctl set-primary A" ""
test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl get-boot-count A" "3"
test_command "/tmp/splctl get-boot-count B" "3"
test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "good"


# Remove spl mode disable so we can test SPL mode
rm -fv /tmp/spl_mode_disable.txt
rm -fv /boot/uboot/uboot.env

echo "----------------------------------------"
echo "----------------------------------------"
echo " now testing SPL mode"
echo "----------------------------------------"
echo "--> this shows handling when BOOT_STATE_A / B is unset"
fw_printenv -c /tmp/spl_fw_env.config
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B
fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"
busybox blockdev --setro "${SPLENVPARTITION}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl get-boot-count A" "5"
test_command "/tmp/splctl get-boot-count B" "0"
test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
echo "----------------------------------------"

####################################################
echo "----------------------------------------"
echo "--> this shows get-state / get-primary / set-state"
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0
busybox blockdev --setro "${SPLENVPARTITION}"
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
echo "--> this shows handling of double quotes around variables"
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A "1"
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B "1"
busybox blockdev --setro "${SPLENVPARTITION}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "good"
echo "----------------------------------------"


echo "----------------------------------------"
echo "--> this shows that the BOOT_STATE_A has precedence over the BOOT_COUNT_A"
echo "--> and if both BOOT_STATE_B and BOOT_COUNT_B are 0, then it is bad"
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0
busybox blockdev --setro "${SPLENVPARTITION}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
echo "----------------------------------------"

echo "----------------------------------------"
echo "--> this shows that the BOOT_STATE_B has precedence over the BOOT_COUNT_B"
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0
busybox blockdev --setro "${SPLENVPARTITION}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "good"
test_command "/tmp/splctl get-state B" "bad"
echo "----------------------------------------"

echo "----------------------------------------"
echo "--> this shows that the BOOT_STATE_B when undefined will look at BOOT_COUNT_A / B"
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B
busybox blockdev --setro "${SPLENVPARTITION}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl get-state A" "bad"
test_command "/tmp/splctl get-state B" "good"
echo "----------------------------------------"

echo "----------------------------------------"
echo "--> this shows that the set-primary will also mark the slot good"
busybox blockdev --setrw "${SPLENVPARTITION}"
fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B
busybox blockdev --setro "${SPLENVPARTITION}"
fw_printenv -c /tmp/spl_fw_env.config

test_command "/tmp/splctl set-state B bad" ""
test_command "/tmp/splctl get-state B" "bad"
test_command "/tmp/splctl get-primary" "A"
test_command "/tmp/splctl set-primary B" ""
test_command "/tmp/splctl get-state B" "good"
echo "----------------------------------------"

echo "----------------------------------------"
echo "--> this shows that the BOOT_VALID_A/B works"
busybox blockdev --setrw $SPLENVPARTITION
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_A 0
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_B 0
busybox blockdev --setro $SPLENVPARTITION
test_command  "/tmp/splctl get-valid A" "bad"
test_command  "/tmp/splctl get-valid B" "bad"
echo "----------------------------------------"

echo "----------------------------------------"
echo "--> this shows that the BOOT_VALID_A/B works"
busybox blockdev --setrw $SPLENVPARTITION"
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_A 1
fw_setenv -c /tmp/spl_fw_env.config BOOT_VALID_B 1
busybox blockdev --setro $SPLENVPARTITION
test_command  "/tmp/splctl get-valid A" "good"
test_command  "/tmp/splctl get-valid B" "good"
echo "----------------------------------------"

echo "----------------------------------------"
echo "--> this runs the set-bootfw-slot command"
test_command "/tmp/splctl set-bootfw-slot A" ""
test_command "fw_printenv -c /tmp/spl_fw_env.config | grep BOOT_FW_SLOT" "BOOT_FW_SLOT=A"
test_command "/tmp/splctl set-bootfw-slot B" ""
test_command "fw_printenv -c /tmp/spl_fw_env.config | grep BOOT_FW_SLOT" "BOOT_FW_SLOT=B"
busybox blockdev --setrw $SPLENVPARTITION"
fw_setenv -c /tmp/spl_fw_env.config BOOT_FW_SLOT
busybox blockdev --setro $SPLENVPARTITION"  
test_command "fw_printenv -c /tmp/spl_fw_env.config | grep BOOT_FW_SLOT" ""
echo "----------------------------------------"

echo "Checking output of command when calling help etc"
test_command "/tmp/splctl --help" ""
test_command "/tmp/splctl" ""
test_command "/tmp/splctl -c xx" ""

echo "Success: $NUM_PASS"
echo "Fails: $NUM_FAIL"

echo "done..."