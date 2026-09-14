# Device-local AP2A release configuration for the Android 14 TWRP build.
# The Android 14 release-config pipeline consumes this file as Starlark.
# Keep the configuration intentionally minimal: recovery does not need
# platform-specific AP2A flag overrides.

load("//build/make/core/release_config.scl", "value")

values = []
