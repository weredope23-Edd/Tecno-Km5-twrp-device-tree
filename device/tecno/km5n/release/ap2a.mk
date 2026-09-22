"""Build flag values for the AP2A release configuration."""

load("//build/make/core/release_config.scl", "value")

values = [
    value("RELEASE_ACONFIG_FLAG_DEFAULT_PERMISSION", "READ_ONLY"),
    value("RELEASE_ACONFIG_VALUE_SETS", "aconfig_value_set-aosp-ap2a"),
    value("RELEASE_AIDL_USE_UNFROZEN", False),
    value("RELEASE_ANGLE_ON_SYSTEM", True),
    value("RELEASE_BOARD_API_LEVEL", "202404"),
    value("RELEASE_BOARD_API_LEVEL_FROZEN", True),
    value("RELEASE_DEPRECATE_VNDK", True),
    value("RELEASE_PLATFORM_SDK_EXTENSION_VERSION", "11"),
    value("RELEASE_PLATFORM_SDK_VERSION", "34"),
    value("RELEASE_PLATFORM_SECURITY_PATCH", "2024-08-05"),
    value("RELEASE_PLATFORM_VERSION", "AP2A"),
    value("RELEASE_PLATFORM_VERSION_ALL_CODENAMES", "REL"),
    value("RELEASE_PLATFORM_VERSION_ALL_PREVIEW_CODENAMES", "REL,VanillaIceCream"),
    value("RELEASE_PLATFORM_VERSION_CODENAME", "REL"),
    value("RELEASE_PLATFORM_VERSION_LAST_STABLE", "14"),
    value("RELEASE_PLATFORM_VNDK_VERSION", "35"),
]
