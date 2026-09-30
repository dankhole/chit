#!/bin/bash
# Sourced by direct build/test: offline pinned libyaml parser + safe event bridge.
build_yaml() {
    local yaml_root="$1" yaml_out="$2" yaml_sdk="$3" yaml_target="$4"
    local yaml_source yaml_object
    local yaml_objects=()
    mkdir -p "$yaml_out/yaml"
    for yaml_source in "$yaml_root"/Vendor/libyaml/src/*.c "$yaml_root"/Sources/CChitYAML/*.c; do
        yaml_object="$yaml_out/yaml/$(basename "${yaml_source%.c}").o"
        xcrun clang -isysroot "$yaml_sdk" -target "$yaml_target" -O2 \
            -I "$yaml_root/Vendor/libyaml/include" -I "$yaml_root/Vendor/libyaml/src" \
            -I "$yaml_root/Sources/CChitYAML" \
            -DHAVE_CONFIG_H=1 -c "$yaml_source" -o "$yaml_object"
        yaml_objects+=("$yaml_object")
    done
    xcrun libtool -static -o "$yaml_out/libChitYAML.a" "${yaml_objects[@]}"
}
