#!/usr/bin/env bash

function install-cloud-endpoints-controller() {
  # Install metacontroller
  kubectl create clusterrolebinding ${USER}-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)

	kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/metacontroller/master/manifests/metacontroller-rbac.yaml
	kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/metacontroller/master/manifests/metacontroller.yaml

  
  # Install cloud endpoints controller
  kubectl apply -f https://raw.githubusercontent.com/danisla/cloud-endpoints-controller/master/manifests/cloud-endpoints-controller-rbac.yaml
  kubectl apply -f https://raw.githubusercontent.com/danisla/cloud-endpoints-controller/master/manifests/cloud-endpoints-controller.yaml
}

install-cloud-endpoints-controller