#!/usr/bin/env bash

function helm-install-cloud-endpoints-controller() {
  # Install helm github plugin
  [[ ! -d ~/.helm/plugins/helm-github.git ]] && helm plugin install --version master https://github.com/sagansystems/helm-github.git

  # Install metacontroller
  kubectl create clusterrolebinding $(USER)-cluster-admin-binding --clusterrole=cluster-admin --user=$(shell gcloud config get-value account)

	kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/metacontroller/master/manifests/metacontroller-rbac.yaml
	kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/metacontroller/master/manifests/metacontroller.yaml

  
  # Install cloud endpoints controller
  kubectl apply -f https://raw.githubusercontent.com/danisla/cloud-endpoints-controller/master/manifests/cloud-endpoints-controller-rbac.yaml
  kubectl apply -f https://raw.githubusercontent.com/danisla/cloud-endpoints-controller/master/manifests/cloud-endpoints-controller.yaml
}

helm-install-cloud-endpoints-controller