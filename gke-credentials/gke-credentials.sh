#!/usr/bin/env bash

function _gke_select_cluster() {
  IFS=';' read -ra clusters <<< "$(gcloud container clusters list --uri | sort -k9 -t/ | tr '\n' ';')"
  local count=1
  for i in ${clusters[@]}; do
    IFS="/" read -ra TOKS <<< "${i}"
    echo "  $count) ${TOKS[-1]} (${TOKS[-3]})" >&2
    ((count=count+1))
  done
  local sel=0
  while [[ $sel -lt 1 || $sel -ge $count ]]; do
    read -p "Select a GKE cluster: " sel >&2
  done
  echo "${clusters[(sel-1)]}"
}

function gke-credentials() {
  cluster=$(_gke_select_cluster)
  if [[ "${cluster}" =~ zones ]]; then
    gcloud container clusters get-credentials ${cluster}
  else
    export CLOUDSDK_CONTAINER_USE_V1_API_CLIENT=false
    IFS="/" read -ra TOKS <<< "${cluster}"
    REGION=${TOKS[-3]}
    CLUSTER_NAME=${TOKS[-1]}
    gcloud beta container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
  fi
}

gke-credentials