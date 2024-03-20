verify_patched_node_path() {
    local path=$1
    local err_prefix=$2

    if [[ -z "$path" ]]; then
        echo "$err_prefix: Path to patched node binary not set. This must be set if using '-b' (see '-n')."
        print_usage
        exit 1
    fi

    patched_node_file=$(basename $path)
    if [[ ! -f "$path" ]] || [[ $patched_node_file != "node" ]]; then
        echo "$err_prefix: $path must point to a file with name 'node'"
        exit 1
    fi
}

verify_zkey_path() {
    local zkey_path=$1
    local err_prefix=$2

    if [[ -z $zkey_path ]]; then
        ERR_MSG="$ERR_PREFIX: Path to zkey not set, but '-Z' option was given."
        exit 1
    fi

    if [[ "${zkey_path##*.}" != "zkey" ]] || [[ ! -f "$zkey_path" ]]; then
        ERR_MSG="$ERR_PREFIX: <zkey_path> '$zkey_path' does not point to an existing zkey file."
        exit 1
    fi
}

set_default_zkey_path_final() {
    declare -n ret=$3

    local build_dir=$1
    local circuit_name=$2

    ret="$build_dir"/"$circuit_name"_final.zkey
}
