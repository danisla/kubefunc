#!/usr/bin/env bash

function _kube_list_nodes() {
  IFS=';' read -ra items <<< "$(kubectl get nodes -o go-template='{{range .items}}{{.metadata.name}}:{{.status.nodeInfo.kubeletVersion}}{{"\n"}}{{end}}' | sort -k 2 -k 1 -t: | tr '\n' ';')"
  local count=1
  lines=$(for i in ${items[@]}; do
    IFS=":" read -ra TOKS <<< "${i}"
    printf "  $count) ${TOKS[0]}\t${TOKS[1]}\n"
    ((count=count+1))
  done | column -t)
  count=$(echo "$lines" | wc -l)
  echo "$lines" >&2
  local sel=0
  while [[ $sel -lt 1 || $sel -gt $count ]]; do
    read -p "Select a node: " sel >&2
  done
  echo "${items[(sel-1)]}"
}

function kube-node-admin() {
  NODE=$1
  [[ -n "${NODE}" ]] && read -r -d '' SPEC_AFFINITY <<- EOM
    "affinity": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [
            {
              "matchExpressions": [
                {
                  "key": "kubernetes.io/hostname",
                  "operator": "In",
                  "values": [ "${NODE}" ]
                }
              ]
            }
          ]
        }
      }
    },
EOM
  read -r -d '' SPEC_TOLERATIONS <<- EOM
    "tolerations": [
      { "effect": "NoSchedule",
        "key": "node-role.kubernetes.io/master",
        "operator": "Exists"
      }
    ],
EOM

  read -r -d '' SPEC_JSON <<EOF
{
  "apiVersion": "v1",
  "spec": {
    ${SPEC_TOLERATIONS}
    ${SPEC_AFFINITY}
    "hostNetwork": true,
    "hostPID": true,
    "containers": [{
      "name": "node-admin",
      "securityContext": {
        "privileged": true
      },
      "image": "alpine:3.9",
      "args": ["nsenter", "-m/proc/1/ns/mnt", "/bin/bash"],
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "name": "hostfs",
        "mountPath": "/hostfs"
      }]
    }],
    "volumes": [{
      "name": "hostfs",
      "hostPath": {
        "path": "/",
        "type": "Directory"
      }
    }]
  }
}
EOF
  kubectl run node-admin -i -t --rm --restart=Never --image=debian:latest --overrides="${SPEC_JSON}"
}

SEL=$(_kube_list_nodes)
IFS=":" read -ra NODE <<< "${SEL}"

kube-node-admin ${NODE[0]}
