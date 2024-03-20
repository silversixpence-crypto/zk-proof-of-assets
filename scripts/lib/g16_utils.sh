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
