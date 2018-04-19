function kube-pod() {
  kubectl get pods --selector=run=$1 --output=jsonpath={.items..metadata.name}
}

function helm-install() {
  VERSION=${1:-2.8.2}

  case "$(uname)" in
  "Linux")
  URL="https://storage.googleapis.com/kubernetes-helm/helm-v${VERSION}-linux-amd64.tar.gz"
  ;;
  "Darwin")
  URL="https://storage.googleapis.com/kubernetes-helm/helm-v${VERSION}-darwin-amd64.tar.gz"
  ;;
  *)
  echo "Unsupported platform: $(uname)"
  return 1
  ;;
  esac 
  
  # Extract helm to ${HOME}/bin
  (cd /tmp && curl -sL -o- "${URL}" | tar --strip-components 1 -z -x -f - && \
    rm LICENSE README.md && mkdir -p ${HOME}/bin/ && mv helm ${HOME}/bin/helm)

  # Add ${HOME}/bin to PATH
  if [[ -z $(grep 'export PATH=${HOME}/bin:${PATH}' ~/.bashrc) ]]; then
  	echo 'export PATH=${HOME}/bin:${PATH}' >> ~/.bashrc
  fi
  
  echo "Installed: ${HOME}/bin/helm version v${VERSION}"

    cat - << EOF 
 
Run the following to reload your PATH with helm:

  source ~/.bashrc

EOF
}

function helm-install-github() {
  helm plugin install \
    --version master https://github.com/sagansystems/helm-github.git
}

function install-kubectl() { 
    K8S_VERSION=${1:-v1.8.1};
    OS=${2:-darwin}
    ARCH=amd64;
    ROOTFS=${HOME};
    BIN_DIR=bin;
    K8S_URL=${K8S_URL:-https://storage.googleapis.com/kubernetes-release/release};
    curl -sfSL ${K8S_URL}/${K8S_VERSION}/bin/${OS}/${ARCH}/kubectl > ${ROOTFS}/${BIN_DIR}/kubectl;
    [[ $? -ne 0 ]] && echo "ERROR: could not download kubectl" && return 1;
    chmod +x ${ROOTFS}/${BIN_DIR}/kubectl;
    echo "Installed kubectl in ${BIN_DIR}/kubectl"
}

function kube-set-context() {
	ctx=$1
	echo "INFO: Setting kubectl context to: ${ctx}"
	kubectl config set-context $(kubectl config current-context) --namespace=${ctx}
}

function kube-staging-prod-configs() {
  echo "export S_CFG='--kubeconfig ${HOME}/.kube/kubeconfig-staging'"
  echo "export P_CFG='--kubeconfig ${HOME}/.kube/kubeconfig-production'"
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

  read -r -d '' SPEC_JSON <<EOF
{
  "apiVersion": "v1",
  "spec": {
    ${SPEC_AFFINITY}
    "hostNetwork": true,
    "containers": [{
      "name": "node-admin",
      "securityContext": {
        "privileged": true
      },
      "image": "alpine:3.7",
      "args": ["chroot", "/hostfs", "/bin/bash"],
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

function helm-install-rbac() {
  kubectl create clusterrolebinding default-admin --clusterrole=cluster-admin --user=$(gcloud config get-value account)
  kubectl create serviceaccount tiller --namespace kube-system
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
  helm init --service-account=tiller
  until (helm version --tiller-connection-timeout=1 >/dev/null 2>&1); do echo "Waiting for tiller install..."; sleep 2; done
  echo "Helm install complete"
  helm version
}

function hyperkube-copy() {
  VERSION=$1
  [[ -z ${VERSION} ]] && echo "USAGE: hyperkube-copy <VERSION>" && return 1
  IMAGE="gcr.io/google_containers/hyperkube:${VERSION}"
  docker pull $IMAGE
  [[ $? -ne 0 ]] && echo "Error pulling image: ${IMAGE}" && return 1
  NAME=hyperkube-copy
  docker create --name ${NAME} ${IMAGE}
  echo "Copying hyperkube to ./hyperkube"
  docker cp ${NAME}:/hyperkube ./hyperkube
  docker rm ${NAME}
  for f in apiserver controller-manager kubectl kubelet proxy scheduler; do
    echo "Linking ${f} to ./hyperkube"
    ln -s ./hyperkube ${f}
  done
}

function kube-release-list() {
  gsutil ls gs://kubernetes-release/release
}

function kubeadm-download() {
  VERSION=$1
  [[ -z ${VERSION} ]] && echo "USAGE: kubeadm-download <VERSION>" && return 1
  gsutil cp gs://kubernetes-release/release/${VERSION}/bin/linux/amd64/kubeadm ./
}

function kube-shell() {
  kubectl run -it --rm --restart=Never kube-shell --image centos:latest -- ${1-bash}
}

function kube-shell-gcp() {
  kubectl run -it --rm --restart=Never kube-shell --image google/cloud-sdk:alpine -- ${1-bash}
}

function helm-install-elasticsearch() {
  # Installs Elasticsearch chart with internal loadbalancer.
  helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
  helm repo update
  cat > elastic-values.yaml <<EOF
rbac:
  create: "true"
client:
  serviceType: "LoadBalancer"
  serviceAnnotations:
    cloud.google.com/load-balancer-type: "Internal"
EOF
  helm install --name elasticsearch incubator/elasticsearch -f elastic-values.yaml
}

function helm-delete-elasticsearch() {
  # Deletes elasticsearch and PVCs
  helm delete --purge elasticsearch
  kubectl delete pvc -l release=elasticsearch,component=data
  kubectl delete pvc -l release=elasticsearch,component=master
}

kube-config-headless() {
  # from: https://gke.ahmet.im/auth/headless-auth-without-gcloud/
  CLUSTER=$1
  ZONE=$2
  [[ -z "$CLUSTER" || -z "${ZONE}" ]] && echo "USAGE: eval \$(kube-config-headless <cluster> <zone>)" && return 1
  YAML="kubeconfig-${CLUSTER}-${ZONE}.yaml"
  CLUSTER_USER=$(gcloud config get-value account 2>/dev/null)
  GET_CMD="gcloud container clusters describe ${CLUSTER} --zone=${ZONE}"
  cat > ${YAML} <<EOF
apiVersion: v1
kind: Config
current-context: ${CLUSTER}-${ZONE}
contexts: [{name: ${CLUSTER}-${ZONE}, context: {cluster: ${CLUSTER}-${ZONE}, user: ${CLUSTER_USER}}}]
users: [{name: ${CLUSTER_USER}, user: {auth-provider: {name: gcp}}}]
clusters:
- name: ${CLUSTER}-${ZONE}
  cluster:
    server: "https://$(eval "$GET_CMD --format='value(endpoint)'")"
    certificate-authority-data: "$(eval "$GET_CMD --format='value(masterAuth.clusterCaCertificate)'")"
EOF
  echo "export KUBECONFIG=\${PWD}/${YAML}"
}

kube-config-headless-regional() {
  # from: https://gke.ahmet.im/auth/headless-auth-without-gcloud/
  CLUSTER=$1
  REGION=$2
  [[ -z "$CLUSTER" || -z "${REGION}" ]] && echo "USAGE: eval \$(kube-config-headless <cluster> <zone>)" && return 1
  YAML="kubeconfig-${CLUSTER}-${REGION}.yaml"
  CLUSTER_USER=$(gcloud config get-value account 2>/dev/null)
  export CLOUDSDK_CONTAINER_USE_V1_API_CLIENT=false
  GET_CMD="gcloud beta container clusters describe ${CLUSTER} --region=${REGION}"
  cat > ${YAML} <<EOF
apiVersion: v1
kind: Config
current-context: ${CLUSTER}-${REGION}
contexts: [{name: ${CLUSTER}-${REGION}, context: {cluster: ${CLUSTER}-${REGION}, user: ${CLUSTER_USER}}}]
users: [{name: ${CLUSTER_USER}, user: {auth-provider: {name: gcp}}}]
clusters:
- name: ${CLUSTER}-${REGION}
  cluster:
    server: "https://$(eval "$GET_CMD --format='value(endpoint)'")"
    certificate-authority-data: "$(eval "$GET_CMD --format='value(masterAuth.clusterCaCertificate)'")"
EOF
  echo "export KUBECONFIG=\${PWD}/${YAML}"
}

kube-node-cluster-admin() {
  for node in $(kubectl get nodes -o jsonpath='{..name}'); do 
    kubectl create clusterrolebinding admin-${node} --clusterrole=cluster-admin --user=system:node:${node}
  done
}

kube-get-external-ip() {
  kubectl run example -i -t --rm --restart=Never --image centos:7 -- curl -s http://ipinfo.io/ip
}