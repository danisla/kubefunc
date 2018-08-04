#!/usr/bin/env bash

function helm-install-cloud-endpoints-controller() {
  # Install helm github plugin
  [[ ! -d ~/.helm/plugins/helm-github.git ]] && helm plugin install --version master https://github.com/sagansystems/helm-github.git

  # Install metacontroller
  helm github install \
    --name metacontroller \
    --namespace metacontroller \
    --repo https://github.com/danisla/cloud-endpoints-controller.git \
    --ref master \
    --path charts/kube-metacontroller
  
  # Install cloud endpoints controller
  helm github install \
    --name cloud-endpoints-controller \
    --namespace metacontroller \
    --repo https://github.com/danisla/cloud-endpoints-controller.git \
    --ref master \
    --path charts/cloud-endpoints-controller
}

helm-install-cloud-endpoints-controller