function download-latest-k9s() {
  mkdir -p ${HOME}/bin
  export URL=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | \
    grep "https.*Linux_amd64.tar.gz" | \
    cut -d : -f 2,3 | \
    tr -d \" | tr -d ' ')
  echo "INFO: Downloading K9s: $URL"
  (
    cd ${HOME}/bin && \
    curl -sfL ${URL} | tar -zxf - k9s
  )
  chmod +x ${HOME}/bin/k9s
  echo "INFO: Installed to: ${HOME}/bin/k9s"
}

function download-latest-opa() {
  mkdir -p ${HOME}/bin
  export URL=$(curl -s https://api.github.com/repos/open-policy-agent/opa/releases/latest | \
    grep "https.*opa_linux_amd64" | \
    cut -d : -f 2,3 | \
    tr -d \" | tr -d ' ')
  echo "INFO: Downloading OPA: $URL"
  (
    cd ${HOME}/bin && \
    curl -sfL ${URL} > opa
  )
  chmod +x ${HOME}/bin/opa
  echo "INFO: Installed to: ${HOME}/bin/opa"
}

function download-latest-istioctl() {
    mkdir -p ${HOME}/bin
    export URL=$(curl -s https://api.github.com/repos/istio/istio/releases/latest | \
      grep -v sha256 | grep "https.*istio-.*-linux-amd64.tar.gz" | \
      cut -d : -f 2,3 | \
      tr -d \" | tr -d ' ')
    echo "INFO: Downloading istio: $URL"
    (
      cd ${HOME}/bin && \
      curl -sfL ${URL} | tar --strip-components=2 --wildcards -zxvf - '*/bin/istioctl'
    )
}

function download-latest-helm() {
    mkdir -p ${HOME}/bin
    TAG=$(curl -s "https://api.github.com/repos/helm/helm/tags" | jq -r '.[0].name')
    export URL="https://get.helm.sh/helm-${TAG}-linux-amd64.tar.gz"
    echo "INFO: Downloading helm: $URL"
    (
      cd ${HOME}/bin && \
      curl -sfL ${URL} | tar --strip-components 1 -zxvf - linux-amd64/helm
    )
}

function download-latest-kustomize() {
  KUSTOMIZE_VERSION=3.5.3
  curl -sfL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz | \
    tar -O -zxvf - kustomize > ${HOME}/bin/kustomize
  chmod +x ${HOME}/bin/kustomize
}

function install-krew() {
  if [[ -d $HOME/.krew/bin ]]; then
    echo "ERROR: krew already installed" && return 1
  fi
  (
    set -x; cd "$(mktemp -d)" &&
    OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
    KREW="krew-${OS}_${ARCH}" &&
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
    tar zxvf ${KREW}.tar.gz &&
    ./"$KREW" install krew
  )
}

function kube-pod() {
  kubectl get pods --selector=run=$1 --output=jsonpath={.items..metadata.name}
}

function helm-install() {
  curl -L https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
}

function helm-install-github() {
  helm plugin install \
    --version master https://github.com/sagansystems/helm-github.git
}

function install-kubectl() { 
    K8S_VERSION=${1:-v1.17.14};
    OS=$(uname)
    ARCH=amd64;
    ROOTFS=${HOME};
    BIN_DIR=bin;
    K8S_URL=${K8S_URL:-https://storage.googleapis.com/kubernetes-release/release};
    curl -sfSL ${K8S_URL}/${K8S_VERSION}/bin/${OS,,}/${ARCH}/kubectl > ${ROOTFS}/${BIN_DIR}/kubectl;
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
    "tolerations": [
        {
            "effect": "NoSchedule",
            "operator": "Exists"
        }
    ],
    "hostNetwork": true,
    "hostPID": true,
    "containers": [{
      "name": "node-admin",
      "securityContext": {
        "privileged": true
      },
      "image": "alpine:3.7",
      "args": ["nsenter", "-m/proc/1/ns/mnt", "/bin/bash"],
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "name": "hostfs",
        "mountPath": "/hostfs"
      },{
        "name": "docker",
        "mountPath": "/var/run/docker.sock"
      }]
    }],
    "volumes": [{
      "name": "hostfs",
      "hostPath": {
        "path": "/",
        "type": "Directory"
      }
    },{
      "name": "docker",
      "hostPath": {
        "path": "/var/run/docker.sock",
        "type": "Socket"
      }
    }]
  }
}
EOF
  kubectl run node-admin-$(date +%s) -i -t --rm --restart=Never --image=debian:latest --overrides="${SPEC_JSON}"
}

function kube-node-gcloud() {
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
    "tolerations": [
        {
            "key": "nvidia.com/gpu",
            "effect": "NoSchedule",
            "operator": "Exists"
        }
    ],
    "hostNetwork": true,
    "containers": [{
      "name": "node-admin",
      "securityContext": {
        "privileged": true
      },
      "image": "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine",
      "command": ["/bin/bash"],
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "name": "hostfs",
        "mountPath": "/hostfs"
      },{
        "name": "docker",
        "mountPath": "/var/run/docker.sock"
      }]
    }],
    "volumes": [{
      "name": "hostfs",
      "hostPath": {
        "path": "/",
        "type": "Directory"
      }
    },{
      "name": "docker",
      "hostPath": {
        "path": "/var/run/docker.sock",
        "type": "File"
      }
    }]
  }
}
EOF
  kubectl run node-gcloud -i -t --rm --restart=Never --image=gcr.io/google.com/cloudsdktool/cloud-sdk:alpine --overrides="${SPEC_JSON}"
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
  kubectl run -n ${KUBE_SHELL_NAMESPACE:-default} -it --rm --restart=Never kube-shell --image centos:latest -- ${1-bash}
}

function kube-shell-gcp() {
  kubectl run -n ${KUBE_SHELL_NAMESPACE:-default} -it --rm --restart=Never kube-shell-gcp --image google/cloud-sdk:alpine -- ${1-bash}
}

function kube-shell-gcp-docker() {
  kubectl run -n ${KUBE_SHELL_NAMESPACE:-default} -it --rm --restart=Never kube-shell-gcp --overrides='
{
  "apiVersion": "v1",
  "spec": {
    "containers": [
      {
        "name": "cloud-sdk",
        "image": "google/cloud-sdk:alpine",
        "args": [
          "bash"
        ],
        "stdin": true,
        "stdinOnce": true,
        "tty": true,
        "volumeMounts": [{
          "mountPath": "/var/run/docker.sock",
          "name": "docker"
        }]
      }
    ],
    "volumes": [{
      "name":"docker",
      "hostPath":{
        "path": "/var/run/docker.sock"
      }
    }]
  }
}
' --image google/cloud-sdk:alpine -- ${1-bash}
}

function kube-shell-node-pool() {
  NODE_POOL=${1:-default}
  kubectl run -n ${KUBE_SHELL_NAMESPACE:-default} -it --rm --restart=Never kube-shell \
    --overrides='{"apiVersion": "v1", "spec": {"nodeSelector": { "cloud.google.com/gke-nodepool": "'${NODE_POOL}'" }}}' \
    --image centos:latest -- bash
}

function kube-shell-node() {
  NODE=${1?"USAGE: kube-shell-node <node name>"}
  kubectl run -n ${KUBE_SHELL_NAMESPACE:-default} -it --rm --restart=Never kube-shell \
  --overrides='{"apiVersion": "v1", "spec": {"nodeSelector": { "kubernetes.io/hostname": "'${NODE}'" }}}' \
    --image centos:latest -- bash
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

function helm-delete-cloud-endpoints-controller() {
  helm delete --purge cloud-endpoints-controller
  helm delete --purge metacontroller
}

function helm-install-cert-manager() {
  helm install --name cert-manager --namespace kube-system stable/cert-manager
  EMAIL=$(gcloud config get-value account)

  cat <<EOF | kubectl apply -f -
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
  namespace: kube-system
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${EMAIL}

    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-staging
    # Enable the HTTP-01 challenge provider
    http01: {}
---
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
  namespace: kube-system
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${EMAIL}

    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-production
    # Enable the HTTP-01 challenge provider
    http01: {}
EOF
}

function helm-delete-cert-manager() {
  kubectl delete clusterissuer letsencrypt-staging letsencrypt-production
  helm delete --purge cert-manager
}

function kube-cloudep-service-ingress() {
  SERVICE=$1
  PORT=$2

  [[ -z "${SERVICE}" && -z "${PORT}" ]] && echo "USAGE: kube-cloudep-service-ingress <service name> <service port>" && return 1

  PROJECT=$(gcloud config get-value project)
  HOST="${SERVICE}.endpoints.${PROJECT}.cloud.goog"

  echo "INFO: Creating Cloud Endpoints service: ${EP}"
  cat <<EOF | kubectl apply -f -
apiVersion: ctl.isla.solutions/v1
kind: CloudEndpoint
metadata:
  name: ${SERVICE}
spec:
  project: ${PROJECT}
  targetIngress:
    name: ${SERVICE}-ingress
    namespace: default
EOF

  echo "INFO: Creating Ingress for service: ${SERVICE}:${PORT}"
  cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: ${SERVICE}-ingress
  annotations:
    kubernetes.io/ingress.class: gce
    ingress.kubernetes.io/ssl-redirect: "true"
    cloud.google.com/managed-certificates: "${SERVICE}"
spec:
  rules:
  - host: "${HOST}"
    http:
     paths:
     - path: /
       backend:
         serviceName: ${SERVICE}
         servicePort: ${PORT}
EOF

  echo "INFO: Creating managed SSL certificate"
  cat <<EOF | kubectl apply -f -
apiVersion: cloud.google.com/v1alpha1
kind: ManagedCertificate
metadata:
  name: ${SERVICE}
spec:
  domains:
    - ${HOST}
EOF
}

function kube-enable-iap() {
  SERVICE=$1
  PORT_NAME=$2
  [[ -z "${SERVICE}" && -z "${PORT_NAME}" ]] && echo "USAGE: kube-enable-iap <service name> <port name>" && return 1

  [[ -z "${CLIENT_ID}" && -z "${CLIENT_SECRET}" ]] && echo "ERROR: CLIENT_ID and CLIENT_SECRET not set." && return 1
  kubectl create secret generic oauth --from-literal=client_id=${CLIENT_ID} --from-literal=client_secret=${CLIENT_SECRET}

  cat <<EOF | kubectl apply -f -
apiVersion: cloud.google.com/v1beta1
kind: BackendConfig
metadata:
  name: ${SERVICE}-${PORT_NAME}
spec:
  iap:
    enabled: true
    oauthclientCredentials:
      secretName: oauth
EOF
  echo "Add the following annotation to your service:"
  cat <<EOF
  annotations:
    beta.cloud.google.com/backend-config:
      '{"ports": {"${PORT_NAME}":"${SERVICE}-${PORT_NAME}"}}'
EOF
}

function kube-ingress-gce-ssl() {
  SERVICE=$1
  PORT=$2
  HOST=$3
  [[ -z "${SERVICE}" && -z "${PORT}" && -z "${HOST}" ]] && echo "USAGE: kube-ingress-gce <service name> <service port> <DNS hostname>" && return 1

  cat <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: ${SERVICE}-ingress
  annotations:
    kubernetes.io/ingress.class: gce
    ingress.kubernetes.io/ssl-redirect: "true"
spec:
  rules:
  - host: "${HOST}"
    http:
     paths:
     - path: /
       backend:
         serviceName: ${SERVICE}
         servicePort: ${PORT}
EOF
}

function kube-config-headless() {
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

function kube-config-headless-regional() {
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

function kube-node-cluster-admin() {
  for node in $(kubectl get nodes -o jsonpath='{..name}'); do 
    kubectl create clusterrolebinding admin-${node} --clusterrole=cluster-admin --user=system:node:${node}
  done
}

function kube-get-external-ip() {
  kubectl run example -i -t --rm --restart=Never --image centos:7 -- curl -s http://ipinfo.io/ip
}

function kube-pod-cidrs() {
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
}

function kube-workload-identity-test() {
  local NAMESPACE=$1
  local SA=$2
  [[ -z "$NAMESPACE" || -z "$SA" ]] && echo "USAGE: kube-workload-identity-test <namespace> <service account>" && return 1
  kubectl run -it --rm \
    --image google/cloud-sdk:slim \
    --serviceaccount $SA \
    --namespace $NAMESPACE \
    workload-identity-test-$(date +%s)
}

###
# Function used to deploy a squid proxy pod to a cluster
###
kube-squid-proxy() {
  echo "INFO: Creating squid proxy pod in default namespace and forwarding port 3128 to localhost"
  kubectl delete pod -n default squid-proxy 2>/dev/null >&2
  kubectl run squid-proxy -n default --restart=Never --image=danisla/squid:3.5.27-2
  kubectl wait --for=condition=ready -n default pod/squid-proxy
  kubectl port-forward -n default squid-proxy 3128:3128
  kubectl delete pod -n default squid-proxy
}

kube-inspect-pull-secret() {
  SECRET_NAME=$1
  [[ -z "${SECRET_NAME}" ]] && echo "USAGE: kube-inspect-pull-secret [<secret namespace>/]<secret name>" && return 1
  IFS="/" read -ra TOKS <<< "${SECRET_NAME}"
  EXTRA_ARGS=""
  if [[ ${#TOKS} -eq 2 ]]; then
    EXTRA_ARGS="${EXTRA_ARGS} --namespace ${TOKS[0]}"
    SECRET_NAME=${TOKS[1]}
  fi
  KUBE_ARGS=$(echo "${EXTRA_ARGS} ${SECRET_NAME}" | xargs)
  kubectl get secret ${KUBE_ARGS} -o jsonpath="{.data.\.dockerconfigjson}" | base64 -d | jq .
}

kube-create-gcr-pull-secret() {
  NAME=$1
  REGISTRY=$2
  SA_KEY=$3
  NAMESPACE=$4
  [[ -z "${NAME}" || -z "${REGISTRY}" || ! -f ${SA_KEY} || -z "${NAMESPACE}" ]] && echo "USAGE: <name> <registry URL> <JSON SA key> <namespace>" && return 1
  DOCKER_EMAIL=$(jq -r .client_email "${SA_KEY}")

  kubectl create secret docker-registry ${NAME} \
  --namespace ${NAMESPACE} \
  --docker-server=https://${REGISTRY/https:\/\//} \
  --docker-email=${DOCKER_EMAIL} \
  --docker-username=_json_key \
  --docker-password="$(cat ${SA_KEY})"
}

function kube-gce-pd-admin() {
  PD=$1
  [[ -z "${PD}" ]] && echo "USAGE: kube-pd-admin <pd name>" && return 1
  read -r -d '' SPEC_JSON <<EOF
{
  "apiVersion": "v1",
  "spec": {
    "containers": [{
      "name": "gce-pd-admin",
      "image": "debian:latest",
      "command": ["bash"],
      "workingDir": "/mnt/disk",
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "name": "pd",
        "mountPath": "/mnt/disk"
      }]
    }],
    "volumes": [{
      "name": "pd",
      "gcePersistentDisk": {
        "pdName": "${PD?}"
      }
    }]
  }
}
EOF
  echo "INFO: Starting pod with GCE PD ${PD} attached to /mnt/disk ..."
  kubectl run gce-pd-admin-$(date +%s) -i -t --rm --restart=Never --image=debian:latest --overrides="${SPEC_JSON}"
}