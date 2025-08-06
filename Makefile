all:

BUILD := build
DESTDIR := prefix

SRCS := crc32.c linux_string.c attr.c ctype.c flags.c fw_env_main.c fw_env.c
CFLAGS := -static -O2 -g -I. -DUSE_HOSTCC

$(BUILD):
	mkdir -p $@

$(BUILD)/splctl: $(SRCS) | $(BUILD)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)
all: $(BUILD)/splctl

install:
	install -Dm755 "$(BUILD)/splctl" "$(DESTDIR)/usr/bin/splctl"

clean:
	rm -rf $(BUILD)

cross-compile:
	podman run --arch=aarch64 -v .:/work -w /work -ti "registry.gitlab.steamos.cloud/deckard/deckardos/holo/steamos-arm64-base:latest" "make"

test: $(BUILD)/splctl
	echo "Testing via adb..."
	adb push $(BUILD)/splctl /tmp/
	adb push spl_fw_env.config /tmp/
	adb push uboot.env /tmp/
	adb push test.sh /tmp/
	adb shell "/bin/bash /tmp/test.sh"