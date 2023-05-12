#!/usr/bin/env bash

function _kube_list_pods() {
  NS_ARG="--all-namespaces"
  [[ -n "$1" ]] && NS_ARG="-n ${1}"

  IFS=';' read -ra pods <<< "$(kubectl get pods $NS_ARG -o go-template='{{range .items}}{{.metadata.name}}:{{.metadata.namespace}}:{{.status.phase}}{{"\n"}}{{end}}' | sort -k 2 -k 1 -t: | tr '\n' ';')"
  local count=1
  lines=$(for i in ${pods[@]}; do
    IFS=":" read -ra TOKS <<< "${i}"
    printf "  $count) ${TOKS[0]}\t${TOKS[1]}\t${TOKS[2]}\n"
    ((count=count+1))
  done | column -t)
  count=$(echo "$lines" | wc -l)
  echo "$lines" >&2
  local sel=0
  while [[ $sel -lt 1 || $sel -gt $count ]]; do
    read -p "Select a Pod: " sel >&2
  done
  echo "${pods[(sel-1)]}"
}

function _kube_list_pod_containers() {
  POD=$1
  NAMESPACE=$2
  IFS=';' read -ra items <<< "$(kubectl get pod ${POD} -n ${NAMESPACE} -o go-template='{{range .spec.containers}}{{.name}}{{"\n"}}{{end}}' | tr '\n' ';')"
  local count=1
  lines=$(for i in ${items[@]}; do
    printf "  $count) ${i}\n"
    ((count=count+1))
  done | column -t)
  count=$(echo "$lines" | wc -l)
  if [[ $count -gt 1 ]]; then
    printf "\nPod has multiple containers:\n" >&2
    echo "$lines" >&2
    local sel=0
    while [[ $sel -lt 1 || $sel -gt $count ]]; do
      read -p "Select a Container: " sel >&2
    done
  else
    local sel=1
  fi
  echo "${items[(sel-1)]}"
}

SEL=$(_kube_list_pods)
IFS=":" read -ra POD <<< "${SEL}"

POD_STATUS=$(echo "${POD[2]}" | tr '[:upper:]' '[:lower:]')
if [[ "${POD_STATUS}" != "running" ]]; then
  echo "ERROR: Pod ${POD[0]} is not running" >&2
  exit 1
fi

SEL=$(_kube_list_pod_containers ${POD[0]} ${POD[1]})

kubectl -n ${POD[1]} logs "${POD[0]}" -c ${SEL} $@