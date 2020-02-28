#!/bin/bash

set -o pipefail

die()
{
    echo >&2 "dead:" "$@"
    [[ -n $temp_file && -f $temp_file ]] && rm "$temp_file"
    exit 1
}

script_dir=$(dirname "${BASH_SOURCE[0]}") || die
readonly script_dir

RUSTUP=$(command -v rustup) || die "rustup must be installed"
readonly RUSTUP

ff_p()
{
    while read -r path
    do
        if [[ $(basename "$path") == "$1"* ]]
        then
            echo "$path"
            return 0
        fi
    done
    die >&2 "Couldn't find any file with the prefix \"$1\""
}

ff_f()
{
    find "$ndk/toolchains/llvm/prebuilt" -type f -name "$@"
}

ff()
{
    [[ $# -lt 2 ]] && die "ff: Too few arguments"
    ff_f "$1" | ff_p "$2"
}

if [[ -z $NDK ]]
then
    if [[ -z $NDK_HOME ]]
    then
        die "Couldn't find the NDK"
    else
        readonly ndk=${NDK_HOME%/}
    fi
else
    readonly ndk=${NDK%/}
fi

temp_file=$(mktemp)
readonly temp_file
[[ -w $temp_file ]] || die "mktemp failed!"

ARCHES=(arm arm64 x86 x86_64)
readonly ARCHES

create_cargo_config()
{
    local label
    local cpu_name
    TARGETS=()

    for arch in "$@"
    do
        case "$arch" in
            arm64)
                label=aarch64
                ;;
            x86)
                label=i686
                ;;
            *)
                label=$arch
                ;;
        esac

        case "$arch" in
            arm)
                cpu_name=armv7-linux-androideabi
                ;;
            *)
                cpu_name=${label}-linux-android
                ;;
        esac

        cat >> "$temp_file" << _END
[target.${cpu_name}]
ar = "$(ff '*-ar' "$label")"
linker = "$(ff '*21-clang' "$label")"
_END
        TARGETS+=("$cpu_name")

        echo "Preparing $arch / $cpu_name..."
    done
}

init_toolchains()
{
    for cpu_name in "$@"
    do
        "$RUSTUP" target add "$cpu_name" || die "rustup failed on $cpu_name"
    done
}

readonly cargo_config_directory=${CARGO_HOME:-"$HOME/.cargo"}

create_cargo_config "${ARCHES[@]}"
[[ ${#ARCHES[*]} -eq ${#TARGETS[*]} ]] || die "Something went horribly wrong"
mkdir -p "$cargo_config_directory"
mv "$temp_file" "$cargo_config_directory/config" || "Cannot write to \"$cargo_config_directory/config\""
init_toolchains "${TARGETS[@]}"

tee "${script_dir}/local.properties" << _END
sdk.dir=${ANDROID_HOME}
rust.pythonCommand=$(command -v python)
_END

