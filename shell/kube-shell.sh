#!/usr/bin/env bash

IMAGE=${1:-centos:latest}

kubectl run -n ${KUBECTL_PLUGINS_CURRENT_NAMESPACE} -it --rm --restart=Never kube-shell --image ${IMAGE} -- bash