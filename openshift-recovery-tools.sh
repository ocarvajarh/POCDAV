#!/usr/bin/env bash
export ETCDCTL_API=3
export ETCD_VERSION=v3.3.17

ETCDCTL_WITH_TLS="$ETCDCTL --cert $ASSET_DIR/backup/etcd-client.crt --key $ASSET_DIR/backup/etcd-client.key --cacert $ASSET_DIR/backup/etcd-ca-bundle.crt"

init() {
  ASSET_BIN=${ASSET_DIR}/bin
  if [ ! -d "$ASSET_BIN" ]; then
    echo "Creating asset directory ${ASSET_DIR}"
    for dir in {bin,tmp,shared,backup,templates,restore,manifests}; do
      /usr/bin/mkdir -p ${ASSET_DIR}/${dir}
    done
  fi
}

# download and test etcdctl from upstream release assets
dl_etcdctl() {
  local etcdimg="quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:835fe7138a0123ca733ac4ba6557af0f74aff78b2da54310f120584b8ecb417c"
  local etcdctr=$(podman create "${etcdimg}")
  local etcdmnt=$(podman mount "${etcdctr}")
  cp ${etcdmnt}/bin/etcdctl $ASSET_DIR/bin
  umount "${etcdmnt}"
  podman rm "${etcdctr}"
  $ASSET_DIR/bin/etcdctl version
}

#backup etcd client certs
backup_etcd_client_certs() {
  echo "Trying to backup etcd client certs.."
  if [ -f "$ASSET_DIR/backup/etcd-ca-bundle.crt" ] && [ -f "$ASSET_DIR/backup/etcd-client.crt" ] && [ -f "$ASSET_DIR/backup/etcd-client.key" ]; then
     echo "etcd client certs already backed up and available $ASSET_DIR/backup/"
  else
    STATIC_DIRS=($(ls -td "${CONFIG_FILE_DIR}"/static-pod-resources/kube-apiserver-pod-[0-9]*)) || true
    if [ -z "${STATIC_DIRS}" ]; then
      echo "error finding static-pod-resources"
      exit 1
    fi
    for APISERVER_POD_DIR in "${STATIC_DIRS[@]}"; do
      SECRET_DIR="${APISERVER_POD_DIR}/secrets/etcd-client"
      CONFIGMAP_DIR="${APISERVER_POD_DIR}/configmaps/etcd-serving-ca"
      if [ -f "$CONFIGMAP_DIR/ca-bundle.crt" ] && [ -f "$SECRET_DIR/tls.crt" ] && [ -f "$SECRET_DIR/tls.key" ]; then
        echo "etcd client certs found in $APISERVER_POD_DIR backing up to $ASSET_DIR/backup/"
        cp $CONFIGMAP_DIR/ca-bundle.crt $ASSET_DIR/backup/etcd-ca-bundle.crt
        cp $SECRET_DIR/tls.crt $ASSET_DIR/backup/etcd-client.crt
        cp $SECRET_DIR/tls.key $ASSET_DIR/backup/etcd-client.key
        return 0
      else
        echo "${APISERVER_POD_DIR} does not contain etcd client certs, trying next .."
      fi
    done
    echo "backup failed: client certs not found"
    exit 1
  fi
}

#backup latest static pod resources for kube-apiserver
backup_latest_kube_static_resources() {
  echo "Trying to backup latest static pod resources.."
  LATEST_STATIC_POD_DIR=$(ls -vd "${CONFIG_FILE_DIR}"/static-pod-resources/kube-apiserver-pod-[0-9]* | tail -1) || true
  if [ -z "$LATEST_STATIC_POD_DIR" ]; then
      echo "error finding static-pod-resources"
      exit 1
  fi

  # tar up the static kube resources, with the path relative to CONFIG_FILE_DIR
  tar -cpzf $BACKUP_TAR_FILE -C ${CONFIG_FILE_DIR} ${LATEST_STATIC_POD_DIR#$CONFIG_FILE_DIR/}
}

append_snapshot_to_tar_and_gzip() {
  # "r" flag is used to append snapshot.db to the existing tar archive
  tar rf ${BACKUP_TAR_FILE} -C ${ASSET_DIR}/tmp snapshot.db
  gzip ${BACKUP_TAR_FILE}
}

# backup current etcd-member pod manifest
backup_manifest() {
  if [ -e "${ASSET_DIR}/backup/etcd-member.yaml" ]; then
    echo "etcd-member.yaml found in ${ASSET_DIR}/backup/"
  else
    echo "Backing up ${ETCD_MANIFEST} to ${ASSET_DIR}/backup/"
    cp ${ETCD_MANIFEST} ${ASSET_DIR}/backup/
  fi
}

# backup etcd.conf
backup_etcd_conf() {
  if [ -e "${ASSET_DIR}/backup/etcd.conf" ]; then
    echo "etcd.conf backup upready exists $ASSET_DIR/backup/etcd.conf"
  else
    echo "Backing up /etc/etcd/etcd.conf to ${ASSET_DIR}/backup/"
    cp /etc/etcd/etcd.conf ${ASSET_DIR}/backup/
  fi
}

backup_data_dir() {
  if [ -f "$ASSET_DIR/backup/etcd/member/snap/db" ]; then
    echo "etcd data-dir backup found $ASSET_DIR/backup/etcd.."
  elif [ ! -f "${ETCD_DATA_DIR}/member/snap/db" ]; then
    echo "Local etcd snapshot file not found, backup skipped.."
  else
    echo "Backing up etcd data-dir.."
    cp -rap ${ETCD_DATA_DIR} $ASSET_DIR/backup/
  fi
}

snapshot_data_dir() {
  ${ETCDCTL_WITH_TLS} snapshot save ${SNAPSHOT_FILE}
}

# backup etcd peer, server and metric certs
backup_certs() {
  COUNT=$(ls $ETCD_STATIC_RESOURCES/system\:etcd-* 2>/dev/null | wc -l) || true
  BACKUP_COUNT=$(ls $ASSET_DIR/backup/system\:etcd-* 2>/dev/null | wc -l) || true

  if [ "$BACKUP_COUNT" -gt 1 ]; then
    echo "etcd TLS certificate backups found in $ASSET_DIR/backup.."
  elif [ "$COUNT" -eq 0 ]; then
    echo "etcd TLS certificates not found, backup skipped.."
  else
    echo "Backing up etcd certificates.."
    cp $ETCD_STATIC_RESOURCES/system\:etcd-* $ASSET_DIR/backup/
  fi
}

# stop etcd by moving the manifest out of /etcd/kubernetes/manifests
# we wait for all etcd containers to die.
stop_etcd() {
  echo "Stopping etcd.."

  if [ ! -d "$MANIFEST_STOPPED_DIR" ]; then
    mkdir $MANIFEST_STOPPED_DIR
  fi

  if [ -e "$ETCD_MANIFEST" ]; then
    mv $ETCD_MANIFEST $MANIFEST_STOPPED_DIR
  fi

  for name in {etcd-member,etcd-metric}
  do
    while [ ! -z "$(crictl pods -name $name --state Ready -q)" ]; do
      echo "Waiting for $name to stop"
      sleep 10
    done
  done
}

remove_data_dir() {
  echo "Removing etcd data-dir ${ETCD_DATA_DIR}"
  rm -rf ${ETCD_DATA_DIR}
}

remove_certs() {
  COUNT=$(ls $ETCD_STATIC_RESOURCES/system\:etcd-* 2>/dev/null | wc -l) || true
  if [ "$COUNT" -gt 1 ]; then
     echo "Removing etcd certs.."
     rm -f $ETCD_STATIC_RESOURCES/system\:etcd-*
  else
     echo "remove_certs: etcd TLS certificates are not found."
  fi
}

remove_kube_static_resources() {
  # Only remove those directories that are greater or equal to the backed up revision.
  REVISION=$(tar tf $BACKUP_FILE | grep -oP "(?<=static-pod-resources/kube-apiserver-)pod-[0-9]*" | head -1) || true
  KUBE_DIRS=$(ls -vd ${CONFIG_FILE_DIR}/static-pod-resources/kube-apiserver-pod-[0-9]* | awk -v REV="${REVISION}$" '$0 ~ REV {seen=1} seen { print}') || true
  if [ ! -z "${KUBE_DIRS}" ]; then
     echo "Removing newer static pod resources..."
     rm -rf ${KUBE_DIRS}
  else
     echo "remove_kube_static_resources: newer revisions of kube-apiserver-pod static resources are not found."
  fi
}

restore_snapshot() {
  if [ ! -f "$SNAPSHOT_FILE" ]; then
    echo "Snapshot file not found, restore failed: $SNAPSHOT_FILE."
    exit 1
  fi

  echo "Restoring etcd member $ETCD_NAME from snapshot.."
  ${ETCDCTL} snapshot restore $SNAPSHOT_FILE \
    --name $ETCD_NAME \
    --initial-cluster ${ETCD_INITIAL_CLUSTER} \
    --initial-cluster-token etcd-cluster-1 \
    --skip-hash-check=true \
    --initial-advertise-peer-urls https://${ETCD_IPV4_ADDRESS}:2380 \
    --data-dir $ETCD_DATA_DIR
}

restore_kube_static_resources() {
  tar -C ${CONFIG_FILE_DIR} -xzf $BACKUP_FILE static-pod-resources
}

patch_manifest() {
  echo "Patching etcd-member manifest.."
  cp $ASSET_DIR/backup/etcd-member.yaml $ASSET_DIR/tmp/etcd-member.yaml.template
  sed -i /' '--discovery-srv/d $ASSET_DIR/tmp/etcd-member.yaml.template
  mv $ASSET_DIR/tmp/etcd-member.yaml.template $MANIFEST_STOPPED_DIR/etcd-member.yaml
}

# generate a kubeconf like file for the cert agent to consume and contact signer.
gen_config() {
  CA=$(base64 $ASSET_DIR/backup/etcd-ca-bundle.crt | tr -d '\n') || true
  CERT=$(base64 $ASSET_DIR/backup/etcd-client.crt | tr -d '\n') || true
  KEY=$(base64 $ASSET_DIR/backup/etcd-client.key | tr -d '\n') || true

  cat > $ETCD_STATIC_RESOURCES/.recoveryconfig << EOF
clusters:
- cluster:
    certificate-authority-data: ${CA}
    server: https://${RECOVERY_SERVER_IP}:9943
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: kubelet
  name: kubelet
current-context: kubelet
preferences: {}
users:
- name: kubelet
  user:
    client-certificate-data: ${CERT}
    client-key-data: ${KEY}
EOF
}

# add member to cluster
etcd_member_add() {
  echo "Updating etcd membership.."
  if [ -d "$ETCD_DATA_DIR" ]; then
    echo "Removing etcd data_dir $ETCD_DATA_DIR.."
    rm -rf $ETCD_DATA_DIR
  fi

  RESPONSE=$($ETCDCTL_WITH_TLS --endpoints ${RECOVERY_SERVER_IP}:2379 member add $ETCD_NAME --peer-urls=https://${ETCD_DNS_NAME}:2380)
  if [ $? -eq 0 ]; then
    echo "$RESPONSE"
    APPEND_CONF=$(echo "$RESPONSE" | sed -e '1,2d')
    echo -e "\n\n#[recover]\n$APPEND_CONF" >> $ETCD_CONFIG
  else
    echo "$RESPONSE"
    exit 1
  fi
}

start_etcd() {
  echo "Starting etcd.."
  mv ${MANIFEST_STOPPED_DIR}/etcd-member.yaml $MANIFEST_DIR
}

# remove member from cluster by name
etcd_member_remove() {
  NAME="$1"

  if [ -z "$NAME" ]; then
    echo "etcd_member_remove requires 1 argument NAME"
    exit 1
  fi

  ID=$($ETCDCTL_WITH_TLS member list | awk -F "," "/\s${NAME}\,/"'{print $1}') || true
  if [ "$?" -ne 0 ] || [ -z "$ID" ]; then
    echo "could not find etcd member $NAME to remove."
    exit 1
  fi

  $ETCDCTL_WITH_TLS member remove $ID
  if [ "$?" -ne 0 ]; then
    echo "removing etcd member $NAME with ID: $ID failed"
    exit 1
  fi
  echo "etcd member $NAME with $ID successfully removed.."
}

populate_template() {
  FIND="$1"
  REPLACE="$2"
  TEMPLATE="$3"
  OUT="$4"

  echo "Populating template $TEMPLATE"

  if [ -z "$FIND" ] || [ -z "$REPLACE" ] || [ -z "$TEMPLATE" ] || [ -z "$OUT" ]; then
    echo "populate_template requires 4 arguments FIND, REPLACE, TEMPLATE and OUT"
    exit 1
  elif [ ! -f "$TEMPLATE" ]; then
    echo "template $TEMPLATE does not exist"
    exit 1
  fi

  TMP_FILE=$(date +"%m-%d-%Y-%H%M")
  cp $TEMPLATE "$ASSET_DIR/tmp/${TMP_FILE}"

  sed -i "s|${FIND}|${REPLACE}|" "$ASSET_DIR/tmp/${TMP_FILE}"
  mv "$ASSET_DIR/tmp/${TMP_FILE}" "$OUT"
}

start_cert_recover() {
  echo "Starting etcd client cert recovery agent.."
  mv ${MANIFEST_STOPPED_DIR}/etcd-generate-certs.yaml $MANIFEST_DIR
}

verify_certs() {
  iterations=0
  while [ "$(ls $ETCD_STATIC_RESOURCES | wc -l)" -lt 9  ]; do
    let iterations=$iterations+1
    if [ $iterations -gt 60 ]; then
      echo "Failed to verify cert generation after 60 iterations. Exiting!"
      exit 1
    fi
    echo "Waiting for certs to generate... ($iterations/60)"
    sleep 10
  done
}

stop_cert_recover() {
  echo "Stopping cert recover.."

  if [ -f "${CONFIG_FILE_DIR}/manifests/etcd-generate-certs.yaml" ]; then
    mv ${CONFIG_FILE_DIR}/manifests/etcd-generate-certs.yaml $MANIFEST_STOPPED_DIR
  fi

  for name in {generate-env,generate-certs}; do
    while [ ! -z "$(crictl pods -name $name --state Ready -q)" ]; do
      echo "Waiting for $name to stop"
      sleep 10
    done
  done
}

stop_static_pods() {
  echo "Stopping all static pods.."

  if [ ! -d "$MANIFEST_STOPPED_DIR" ]; then
    mkdir $MANIFEST_STOPPED_DIR
  fi

  find ${MANIFEST_DIR} -maxdepth 1 -type f -printf "%f\n" > $STOPPED_STATIC_PODS

  while read STATIC_POD; do
    echo "..stopping $STATIC_POD"
    mv ${MANIFEST_DIR}/${STATIC_POD} $MANIFEST_STOPPED_DIR
  done <$STOPPED_STATIC_PODS
}

start_static_pods() {
  echo "Starting static pods.."
  find ${MANIFEST_STOPPED_DIR} -maxdepth 1 -type f -printf "%f\n" > $STOPPED_STATIC_PODS
  while read STATIC_POD; do
    echo "..starting $STATIC_POD"
    mv ${MANIFEST_STOPPED_DIR}/${STATIC_POD} $MANIFEST_DIR
  done <$STOPPED_STATIC_PODS
}

stop_kubelet() {
  echo "Stopping kubelet.."
  systemctl stop kubelet.service
}

start_kubelet() {
  echo "Starting kubelet.."
  systemctl daemon-reload
  systemctl start kubelet.service
}

stop_all_containers() {
  conids=$(crictl ps -q)
  iterations=0
  while [ ! -z "$conids" ]; do
      let iterations=$iterations+1
      if [ $iterations -ge 60 ]; then
          echo "Failed to stop all containers after 60 iterations. Exiting!"
          exit 1
      fi
      crictl stop $conids || true
      echo "Waiting for all containers to stop... ($iterations/60)"
      sleep 5
      conids=$(crictl ps -q)
  done
  echo "All containers are stopped."
}

# validate_environment performs the same actions as the discovery container in etcd-member init
# sometimes $RUN_ENV is not available if the node is rebooted so we recreate here.
validate_environment() {
  if [ -f "$RUN_ENV" ] && [ -s "$RUN_ENV" ];then
    return 0
  fi
  SRV_A_RECORD=$(dig +noall +answer SRV _etcd-server-ssl._tcp.${DISCOVERY_DOMAIN} | grep -oP '(?<=2380 ).*[^\.]' | xargs) || true
  HOST_IPS=$(ip -o addr |  grep -oP '(?<=inet )(\d{1,3}\.?){4}') || true

  if [ -z "$SRV_A_RECORD" ]; then
    echo "SRV A record query for ${DISCOVERY_DOMAIN} failed please update DNS"
    exit 1
  elif [ -z "$HOST_IPS" ]; then
    echo "Unable to find any IPv4 addresses for host interfaces"
    exit 1
  fi

  for a in ${SRV_A_RECORD[@]}; do
    echo "checking against $a"
    for i in ${HOST_IPS[@]}; do
      DIG_IP=$(dig +short $a)
      if [ -z "$DIG_IP" ]; then
        echo "No matching A record found for $a skipping"
        continue
      elif [ "$DIG_IP" == "$i" ]; then
        echo "dns name is $a"
        cat > $RUN_ENV << EOF
ETCD_IPV4_ADDRESS=$DIG_IP
ETCD_DNS_NAME=$a
ETCD_WILDCARD_DNS_NAME=*.${DISCOVERY_DOMAIN}
EOF
        return 0
      fi
    done
  done
  echo "SRV query failed no matching records found"
  exit 1
}

# validate_etcd_name uses regex to return the etcd member name key from ETCD_INITIAL_CLUSTER matching the local ETCD_DNS_NAME.
validate_etcd_name() {
  ETCD_NAME=$(echo ${ETCD_INITIAL_CLUSTER} | grep -oP "(?<=)[^,,\s]*(?==[^=]*${ETCD_DNS_NAME}\b)") || true
  if [ -z "$ETCD_NAME" ]; then
    echo "Validating INITIAL_CLUSTER failed: ${ETCD_DNS_NAME} is not found in ${ETCD_INITIAL_CLUSTER}" >&2
    exit 1
  fi
  echo "$ETCD_NAME"