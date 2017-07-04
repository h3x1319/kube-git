#!/bin/bash

# kube-watch - is a small utility set that servers for the purpose of kubernetes objects revision controll system and
# kubernetes cluster dump, that can be used in order to migrate setup to different kubernetes cluster
# kube-trigger - is a part of kube-watch bashinator that watches for changes under kubernetes objects in etcd
# kube-dump - is a utility that dumps kubernetes object tree using kubectl mechanism for clean export 

# Defaults
namespace="default"
resources="deployments"

function usage() {
  # Local var because of grep
  declare helpdoc='HELP'
  helpdoc+='DOC'

  declare -r script_name=$(basename "$0")
  echo 'Watch for changes in kubernetes cluster and dump cluster and resource definition upon change'
  echo 'Requirements: aws-cli, etcdctl, jq'
  echo "Usage: $script_name [opts]"
  echo 'Opts:'
  grep "$helpdoc" "$0" -B 1 | egrep -v '^--$' | sed -e 's/^  //g' -e "s/# $helpdoc: //g"
}

# Parse parameters
while [[ $# > 0 ]]; do
  param="${1}"
  value="${2:-}"

  case $param in
    -r|--resources)
      # HELPDOC: dev | stg | prod
      resources="$value"
      shift
      ;;
    -n|--namespace)
      # HELPDOC: AWS EC2 role tag
      namespace="$value"
      shift
      ;;
    -h|--help)
      # HELPDOC: display this message and exit
      usage
      exit 0
      ;;

    *)
      echo "Illegal option: $value" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p ./registry/deployments/$namespace
git pull --rebase origin master

# List of available resources
# secrets configmaps limitranges persistentvolumes persistentvolumeclaims replicasets ingress daemonssets services controllers
init_registry() {
  for i in `etcdctl ls /registry/deployments/$namespace --recursive -p | grep -v '/$'`; do 
    etcdctl get $i | \
	jq 'del(.spec.clusterIP,
		.metadata.uid,
		.metadata.selfLink,
		.metadata.resourceVersion,
		.metadata.creationTimestamp,
		.metadata.generation,
		.status,
		.spec.template.spec.securityContext,
		.spec.template.spec.dnsPolicy,
		.spec.template.spec.terminationGracePeriodSeconds,
		.spec.template.spec.restartPolicy)' > ./$i 
  done 
}

run_trigger() {
  for i in "$resources" 
    do 
      etcdctl exec-watch --recursive /registry/$i/$namespace/ -- bash -x -c './kube-trigger.sh'  
    done
}

init_registry
run_trigger
