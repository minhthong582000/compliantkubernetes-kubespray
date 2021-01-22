#!/bin/bash

# This script takes care of initializing a CK8S configuration path for kubespray.
# It writes the default configuration files to the config path and generates
# some defaults where applicable.
# It's not to be executed on its own but rather via `ck8s-kubespray init ...`.

set -eu -o pipefail
shopt -s globstar nullglob dotglob

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "error when running $0: argument mismatch" 1>&2
    exit 1
fi

flavor=$1
ssh_key_file=$2
if [ $# -eq 3 ]; then
    fingerprint=$3
fi

here="$(dirname "$(readlink -f "$0")")"
# shellcheck source=common.bash
source "${here}/common.bash"

CK8S_CLOUD_PROVIDER=${CK8S_CLOUD_PROVIDER:-""}
if [[ ${CK8S_CLOUD_PROVIDER} != "" ]]; then
    log_error "ERROR: CK8S_CLOUD_PROVIDER is not supported"
    exit 1
fi

# Validate the flavor
if [ "${flavor}" != "default" ] && [ "${flavor}" != "gcp" ] && [ "${flavor}" != "aws" ]; then
    log_error "ERROR: Unsupported flavor: ${flavor}"
    exit 1
fi

generate_sops_config() {
    if [ -z ${fingerprint+x} ]; then
        if [ -z ${CK8S_PGP_FP+x} ]; then
            log_error "ERROR: either the <SOPS fingerprint> argument or the env variable CK8S_PGP_FP must be set."
            exit 1
        else
            fingerprint="${CK8S_PGP_FP}"
        fi
    fi
    log_info "Initializing SOPS config with PGP fingerprint: ${fingerprint}"
    sops_config_write_fingerprints "${fingerprint}"
}

copy_ssh_file() {
    if [ -f "${secrets[ssh_key]}" ]; then
        log_info "SSH key already exists: ${secrets[ssh_key]}"
    else
        mkdir -p "${ssh_folder}"
        cp "${ssh_key_file}" "${secrets[ssh_key]}"
        sops_encrypt "${secrets[ssh_key]}"
    fi
}

if [ -f "${sops_config}" ]; then
    log_info "SOPS config already exists: ${sops_config}"
    validate_sops_config
else
    generate_sops_config
fi

copy_ssh_file

log_info "Initializing CK8S configuration with flavor: ${flavor}"
mkdir -p "${config_path}"

# Copy default group_vars
cp -r "${config_defaults_path}/common/group_vars" "${config_path}/"

if [[ "${flavor}" == "default" ]]; then
  cp -r "${config_defaults_path}/default/group_vars" "${config_path}/"
elif [[ "${flavor}" == "gcp" ]]; then
  cp -r "${config_defaults_path}/gcp/group_vars" "${config_path}/"
elif [[ "${flavor}" == "aws" ]]; then
  cp -r "${config_defaults_path}/aws/group_vars" "${config_path}/"
fi

# Copy inventory.ini
if [[ ! -f "${config[inventory_file]}" ]]; then
  PREFIX=${prefix} envsubst > "${config[inventory_file]}" < "${config_defaults_path}/inventory.ini"
else
  log_info "Inventory already exists, leaving it as it is"
fi

log_info "Config initialized"

log_info "Time to edit the following files:"
log_info "${config[inventory_file]}"
