#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o errtrace

# example
# etcd-snapshot-backup.sh $path-to-snapshot

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

usage () {
    echo 'Path to backup dir required: ./etcd-snapshot-backup.sh <path-to-backup-dir>'
    exit 1
}

ASSET_DIR=./assets

if [ -z "$1" ] || [ -f "$1" ]; then
  usage
fi

if [ ! -d "$1" ]; then
  mkdir -p $1
fi

BACKUP_DIR="$1"
DATESTRING=$(date "+%F_%H%M%S")
BACKUP_TAR_FILE=${BACKUP_DIR}/static_kuberesources_${DATESTRING}.tar.gz
SNAPSHOT_FILE="${BACKUP_DIR}/snapshot_${DATESTRING}.db"

trap "rm -f ${BACKUP_TAR_FILE} ${SNAPSHOT_FILE}" ERR

CONFIG_FILE_DIR=/etc/kubernetes
MANIFEST_DIR="${CONFIG_FILE_DIR}/manifests"
MANIFEST_STOPPED_DIR="${ASSET_DIR}/manifests-stopped"
ETCDCTL="${ASSET_DIR}/bin/etcdctl"
ETCD_DATA_DIR=/var/lib/etcd
ETCD_MANIFEST="${MANIFEST_DIR}/etcd-member.yaml"
ETCD_STATIC_RESOURCES="${CONFIG_FILE_DIR}/static-pod-resources/etcd-member"
STOPPED_STATIC_PODS="${ASSET_DIR}/tmp/stopped-static-pods"

source "/usr/local/bin/openshift-recovery-tools"

function run {
  init
  dl_etcdctl
  backup_etcd_client_certs
  backup_manifest
  backup_latest_kube_static_resources
  snapshot_data_dir
  echo "snapshot db and kube resources are successfully saved to ${BACKUP_DIR}!"
}

run