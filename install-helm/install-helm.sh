#!/usr/bin/env bash

curl -L https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash

helm version -c

kubectl create clusterrolebinding default-admin --clusterrole=cluster-admin --user=$(gcloud config get-value account);
kubectl create serviceaccount tiller --namespace kube-system;
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller;
helm init --service-account=tiller;
until ( helm version --tiller-connection-timeout=1 > /dev/null 2>&1 ); do
    echo "Waiting for tiller install...";
    sleep 2;
done;
echo "Helm install complete";
helm repo update
helm version