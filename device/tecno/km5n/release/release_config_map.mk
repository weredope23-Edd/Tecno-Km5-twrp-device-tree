# Device-local Android 14 release configuration for TWRP builds.
# The minimal TWRP AOSP manifest currently does not declare any release
# configs, so Android 14 lunch rejects the standard ap2a target. Define ap2a
# locally as a valid device release configuration.
$(call declare-release-config,ap2a,device/tecno/km5n/release/ap2a.mk)
