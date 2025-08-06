
#!/bin/bash

set -e

chmod +w splctl || true

CC="aarch64-linux-gnu-gcc"
#CC="gcc"
$CC -static -g -o splctl crc32.c linux_string.c attr.c ctype.c flags.c fw_env_main.c fw_env.c -I. -DUSE_HOSTCC 
chmod +x splctl

echo "done compiling..."

ls -al splctl

sleep 1


TEST=1

failcount=0
successcount=0

if [[ "$TEST" == "1" ]]; then

  test_command () {
    set +e
    TESTRESULT=$(adb shell "$1")
    RETVAL=$?
    set -e
    if [[ "$TESTRESULT" == "$2" ]]; then
      echo "$1 [ret=$RETVAL]: [output='$TESTRESULT'] ok"
      successcount=$(($successcount + 1))
    else
      echo "$1 [ret=$RETVAL]: [output='$TESTRESULT'] fail"
      failcount=$(($failcount + 1))
    fi
  }


  SPLENVPARTITION="/dev/disk/by-partlabel/bootenv"

  echo "testing via adb..."
  adb push splctl /tmp/ 
  adb push spl_fw_env.config /tmp/

  echo "----------------------------------------"
  echo "--> this shows the non-spl mode that is used with ev1 units that dont have spl"
  adb shell "touch /tmp/spl_mode_disable.txt"
 
  adb push uboot.env /tmp/
  adb shell "makerootfsrw && ln -s /tmp/uboot.env /boot/uboot/uboot.env || true"

  adb shell 'fw_setenv BOOT_ORDER "A B"'
  adb shell "fw_setenv BOOT_A_LEFT 3"
  adb shell "fw_setenv BOOT_B_LEFT 3"
  echo "------------------------------------------"
  adb shell "fw_printenv"
  echo "------------------------------------------"

  test_command  "/tmp/splctl get-primary" "A"
  test_command  "/tmp/splctl get-boot-count A" "3"
  test_command  "/tmp/splctl get-boot-count B" "3"
  test_command  "/tmp/splctl get-state A" "good"
  test_command  "/tmp/splctl get-state B" "good"
  
  adb shell 'fw_setenv BOOT_ORDER "B A"'
  adb shell "fw_setenv BOOT_A_LEFT 0"
  adb shell "fw_setenv BOOT_B_LEFT 3"
  echo "------------------------------------------"
  adb shell "fw_printenv"
  echo "------------------------------------------"

  test_command  "/tmp/splctl get-primary" "B"
  test_command  "/tmp/splctl get-boot-count A" "0"
  test_command  "/tmp/splctl get-boot-count B" "3"
  test_command  "/tmp/splctl get-state A" "bad"
  test_command  "/tmp/splctl get-state B" "good"

  adb shell 'fw_setenv BOOT_ORDER "B A"'
  adb shell "fw_setenv BOOT_A_LEFT 0"
  adb shell "fw_setenv BOOT_B_LEFT 3"
  echo "------------------------------------------"
  adb shell "fw_printenv"
  echo "------------------------------------------"

  test_command  "/tmp/splctl get-primary" "B"
  test_command  "/tmp/splctl set-primary A" ""
  test_command  "/tmp/splctl get-primary" "A"
  test_command  "/tmp/splctl get-boot-count A" "3"
  test_command  "/tmp/splctl get-boot-count B" "3"
  test_command  "/tmp/splctl get-state A" "good"
  test_command  "/tmp/splctl get-state B" "good"

  adb shell "rm -fv /tmp/spl_mode_disable.txt"
  adb shell "rm -fv /boot/uboot/uboot.env"

  echo "----------------------------------------"
  echo "----------------------------------------"
  echo " now testing SPL mode"
  echo "----------------------------------------"
  echo "--> this shows handling when BOOT_STATE_A / B is unset"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"
 
  test_command  "/tmp/splctl get-primary" "A"
  test_command  "/tmp/splctl get-boot-count A" "5"
  test_command  "/tmp/splctl get-boot-count B" "0"
  test_command  "/tmp/splctl get-state A" "good"
  test_command  "/tmp/splctl get-state B" "bad"
  echo "----------------------------------------"

  ####################################################
  echo "----------------------------------------"
  echo "--> this shows get-state / get-primary / set-state"
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0"
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"

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
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A \"1\"'
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B \"1\"'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"

  test_command "/tmp/splctl get-state A" "good"
  test_command "/tmp/splctl get-state B" "good"
  echo "----------------------------------------"


  echo "----------------------------------------"
  echo "--> this shows that the BOOT_STATE_A has precedence over the BOOT_COUNT_A"
  echo "--> and if both BOOT_STATE_B and BOOT_COUNT_B are 0, then it is bad"
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 0"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1'
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"

  test_command "/tmp/splctl get-state A" "good"
  test_command "/tmp/splctl get-state B" "bad"
  echo "----------------------------------------"
  
  echo "----------------------------------------"
  echo "--> this shows that the BOOT_STATE_B has precedence over the BOOT_COUNT_B"
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1'
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B 0'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"

  test_command "/tmp/splctl get-state A" "good"
  test_command "/tmp/splctl get-state B" "bad"
  echo "----------------------------------------"

  echo "----------------------------------------"
  echo "--> this shows that the BOOT_STATE_B when undefined will look at BOOT_COUNT_A / B"
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 0"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A'
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"

  test_command "/tmp/splctl get-state A" "bad"
  test_command "/tmp/splctl get-state B" "good"
  echo "----------------------------------------"

  echo "----------------------------------------"
  echo "--> this shows that the set-primary will also mark the slot good"
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_ORDER "A B"'
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_A 5"
  adb shell "fw_setenv -c /tmp/spl_fw_env.config BOOT_COUNT_B 5"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_A 1'
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config BOOT_STATE_B'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  adb shell "fw_printenv -c /tmp/spl_fw_env.config"

  test_command "/tmp/splctl set-state B bad" ""
  test_command "/tmp/splctl get-state B" "bad"
  test_command "/tmp/splctl get-primary" "A"
  test_command "/tmp/splctl set-primary B" ""
  test_command "/tmp/splctl get-state B" "good"
  echo "----------------------------------------"

  echo "----------------------------------------"
  echo "--> this shows that the force-rescue command works"
  #first clear FORCE_RESCUE
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config FORCE_RESCUE'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  test_command "/tmp/splctl force-rescue" ""
  adb shell "fw_printenv -c /tmp/spl_fw_env.config" | grep FORCE_RESCUE
  #now clear FORCE_RESCUE again
  adb shell "busybox blockdev --setrw $SPLENVPARTITION"
  adb shell 'fw_setenv -c /tmp/spl_fw_env.config FORCE_RESCUE'
  adb shell "busybox blockdev --setro $SPLENVPARTITION"
  echo "----------------------------------------"

  echo "Checking output of command when calling help etc"
  test_command "/tmp/splctl --help" ""
  test_command "/tmp/splctl" ""
  test_command "/tmp/splctl -c xx" ""

  echo "Success: $successcount"
  echo "Fails: $failcount"

  echo "done..."
fi
