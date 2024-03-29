#!/usr/bin/env bash

set -o errexit
set -o pipefail

# example
# export SETUP_ETCD_ENVIRONMENT=$(oc adm release info --image-for machine-config-operator --registry-config=./config.json)
# export KUBE_CLIENT_AGENT=$(oc adm release info --image-for kube-client-agent --registry-config=./config.json)
# sudo -E ./etcd-member-recover.sh 192.168.1.100 $etcd_name

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

: ${SETUP_ETCD_ENVIRONMENT:?"Need to set SETUP_ETCD_ENVIRONMENT"}
: ${KUBE_CLIENT_AGENT:?"Need to set KUBE_CLIENT_AGENT"}

usage () {
    echo 'Recovery server IP address and etcd name required: ./etcd-member-recover.sh 192.168.1.100 $etcd_name'
    exit 1
}

if [ "$1" == "" ] || [ "$2" == "" ]; then
    usage
fi

RECOVERY_SERVER_IP=$1
ETCD_NAME=$2

ASSET_DIR=./assets
ASSET_DIR_TMP="$ASSET_DIR/tmp"
CONFIG_FILE_DIR=/etc/kubernetes
MANIFEST_DIR="${CONFIG_FILE_DIR}/manifests"
RUN_ENV=/run/etcd/environment

MANIFEST_STOPPED_DIR="$ASSET_DIR/manifests-stopped"
ETCD_MANIFEST="${MANIFEST_DIR}/etcd-member.yaml"
ETCD_CONFIG=$RUN_ENV
ETCDCTL=$ASSET_DIR/bin/etcdctl
ETCD_DATA_DIR=/var/lib/etcd
ETCD_STATIC_RESOURCES="${CONFIG_FILE_DIR}/static-pod-resources/etcd-member"

SHARED=/usr/local/share/openshift-recovery
TEMPLATE="$SHARED/template/etcd-generate-certs.yaml.template"

source "/usr/local/bin/openshift-recovery-tools"

function run {
  init
  dl_etcdctl
  backup_manifest
  DISCOVERY_DOMAIN=$(grep -oP '(?<=discovery-srv=).*[^"]' $ASSET_DIR/backup/etcd-member.yaml ) || true
  if [ -z "$DISCOVERY_DOMAIN" ]; then
    echo "Discovery domain can not be extracted from $ASSET_DIR/backup/etcd-member.yaml"
    exit 1
  fi
  validate_environment
  source  /run/etcd/environment
  backup_etcd_conf
  backup_etcd_client_certs
  stop_etcd
  backup_data_dir
  backup_certs
  remove_certs
  gen_config
  CLUSTER_NAME=$(echo ${DISCOVERY_DOMAIN} | grep -oP '^.*?(?=\.)') || true
  populate_template '__ETCD_DISCOVERY_DOMAIN__' "$DISCOVERY_DOMAIN" "$TEMPLATE" "$ASSET_DIR/tmp/etcd-generate-certs.stage1"
  populate_template '__SETUP_ETCD_ENVIRONMENT__' "$SETUP_ETCD_ENVIRONMENT" "$ASSET_DIR/tmp/etcd-generate-certs.stage1" "$ASSET_DIR/tmp/etcd-generate-certs.stage2"
  populate_template '__KUBE_CLIENT_AGENT__' "$KUBE_CLIENT_AGENT" "$ASSET_DIR/tmp/etcd-generate-certs.stage2" "$MANIFEST_STOPPED_DIR/etcd-generate-certs.yaml"
  start_cert_recover
  verify_certs
  stop_cert_recover
  patch_manifest
  etcd_member_add
  start_etcd
}

run