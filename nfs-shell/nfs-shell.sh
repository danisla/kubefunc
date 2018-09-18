#!/usr/bin/env bash

export POD_NAME=""
function cleanup() {
    [[ -n "${POD_NAME}" ]] && kubectl delete pod ${POD_NAME}
}
trap cleanup EXIT TERM

function _get_nfs_info() {
    serverpath=""
    while [[ -z "${serverpath}" ]]; do
        read -p "Enter path to NFS mount in the form of SERVER:PATH : " input >&2
        IFS=':' read -ra toks <<< "${input}"
        if [[ ${#toks[@]} -ne 2 ]]; then
          echo "Invalid input. Must be in the form of SERVER:PATH" >&2
        else
          serverpath=$input
        fi
    done
    echo "${serverpath}"
}

function kube-nfs-shell() {
    serverpath=$1
    [[ -z "${serverpath}" ]] && serverpath=$(_get_nfs_info)

    IFS=':' read -ra toks <<< "${serverpath}"
    nfsserver=${toks[0]}
    nfspath=${toks[1]}
    echo "INFO: Creating pod with NFS mount ${nfsserver}:${nfspath} at /mnt/nfs" >&2

    read -r -d '' SPEC_JSON <<EOF
{
  "apiVersion": "v1",
  "spec": {
    "containers": [{
      "name": "shell",
      "image": "alpine:3.7",
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "name": "nfs",
        "mountPath": "/mnt/nfs"
      }]
    }],
    "volumes": [{
      "name": "nfs",
      "nfs": {
        "server": "${nfsserver}",
        "path": "${nfspath}"
      }
    }]
  }
}
EOF
    ts=$(date +%s)
    POD_NAME="nfs-shell-${ts}"
    NAMESPACE=${KUBECTL_PLUGINS_CURRENT_NAMESPACE:-default}
    kubectl run -n ${NAMESPACE} ${POD_NAME} -i -t --rm --restart=Never --image=alpine:3.7 --overrides="${SPEC_JSON}"
    POD_NAME=""
}

kube-nfs-shell $@