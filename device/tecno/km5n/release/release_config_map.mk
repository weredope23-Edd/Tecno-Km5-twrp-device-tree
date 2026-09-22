# Device-local Android 14 release configuration for TWRP builds.
# Match the Android 14 AOSP release-config map structure so the build system
# discovers both the flag declarations and the AP2A value file.

local_dir := $(dir $(lastword $(MAKEFILE_LIST)))

FLAG_DECLARATION_FILES := $(local_dir)build_flags.scl

$(call declare-release-config,ap2a,$(local_dir)ap2a.mk)

local_dir :=
