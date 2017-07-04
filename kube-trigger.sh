#!/bin/bash

# kube-watch - is a small utility set that servers for the purpose of kubernetes objects revision controll system 
# and kubernetes cluster dump, that can be used in order to migrate setup to different kubernetes cluster
# kube-trigger - is a part of kube-watch that watches for changes under kubernetes objects in etcd
# etcdctl exec-watch --recursive /registry/deployments/dev-fed -- bash -c './kube-watch.sh'

#set -o pipefail
#set -o errexit
#
s3bucket="kubernetes-dump-s3bucket"
region="eu-central-1"
basedir=`dirname "$ETCD_WATCH_KEY"`
git_branch_name=$(git symbolic-ref --short HEAD)
git_commit_sha=$(git rev-parse --short HEAD)
deploytag="${git_branch_name}-${git_commit_sha}"

mkdir -p ./$basedir
mkdir -p ./cluster-dump

get_git_root() {
  # returns: $git_root
  this_dir=$(pwd -P)
  git_root=""
  # climb up until we find .git directory
  while (:); do
    if [ -d .git ]; then
      git_root=$(pwd -P)
      break
    elif [[ $(pwd -P) == "/" ]]; then
      echo "Failed to guess the root of the git repo."
      exit 1
    else
      cd ..
    fi
  done
 cd $this_dir
}

dump_namespaces() {
  kubectl get --export -o=json ns | \
  jq '.items[] |
  	select(.metadata.name!="kube-system") |
  	select(.metadata.name!="default") |
  	del(.status,
          .metadata.uid,
          .metadata.selfLink,
          .metadata.resourceVersion,
          .metadata.creationTimestamp,
          .metadata.generation
      )' > ./cluster-dump/ns.json
}

dump_resources() {
  for ns in $(jq -r '.metadata.name' < ./cluster-dump/ns.json);do
      echo "Namespace: $ns"
      kubectl --namespace="${ns}" get --export -o=json svc,rc,secrets,ds,cm,deploy,ep,hpa,ing,limits,pvc,pv,rs,quota | \
      jq '.items[] |
          select(.type!="kubernetes.io/service-account-token") |
          del(
              .spec.clusterIP,
              .metadata.uid,
              .metadata.selfLink,
              .metadata.resourceVersion,
              .metadata.creationTimestamp,
              .metadata.generation,
              .status,
              .spec.template.spec.securityContext,
              .spec.template.spec.dnsPolicy,
              .spec.template.spec.terminationGracePeriodSeconds,
              .spec.template.spec.restartPolicy
          )' >> "./cluster-dump/cluster-dump.json"
  done
}

dump_etcd() {
  if [ ! -d ./etcd-backup ]; then
    mkdir -p ./etcd-backup
  else
    rm -rf ./etcd-backup/*
  fi
    etcdctl backup --data-dir /var/lib/etcd/data \
        	   --backup-dir etcd-backup 
}

git_push() {
# pushes changes in etcd registry to git, for revision controll
# later the git sha can be used to restart cluster state from cluster dump stored in S3 bucket 
  git add ./"$ETCD_WATCH_KEY"
  git commit -m "changed deployment $ETCD_WATCH_KEY field: $object_field , caused by $change_cause"
  git push origin master --force
}

upload_cluster_dump_to_s3() {
  get_git_root
  tar cf "/tmp/$deploytag.tar.gz" --exclude ".git" -C "$git_root" .
  aws s3 --region $region cp "/tmp/$deploytag.tar.gz" "s3://$s3bucket/"
  echo "$deploytag"
}

# Main
  echo "$ETCD_WATCH_VALUE" | \
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
		.spec.template.spec.restartPolicy
	    )' > ./"$ETCD_WATCH_KEY"_new

  if ! diff -q ./"$ETCD_WATCH_KEY"_new ./"$ETCD_WATCH_KEY"; then

        change_cause=$(diff ./"$ETCD_WATCH_KEY"_new ./"$ETCD_WATCH_KEY" 2>&1 | \
			grep -o 'change-cause.*$' 2>&1 | cut -d '\' -f3 2>&1 | sed 's/"//g' 2>&1 | head -n 1 2>&1)

	object_field=$(diff -c ./"$ETCD_WATCH_KEY"_new ./"$ETCD_WATCH_KEY" 2>&1 | \
			grep -v 'last-applied-configuration' 2>&1 | grep -v 'revision' | grep ! 2>&1 | head -n 1 2>&1 | cut -d '!' -f2- 2>&1 | sed 's/ //g')

	  mv ./"$ETCD_WATCH_KEY"_new ./"$ETCD_WATCH_KEY"
	    echo "object $ETCD_WATCH_KEY has changed with field $object_field" 
	      dump_namespaces
	     dump_resources
            dump_etcd
	   git_push
	  upload_cluster_dump_to_s3
  fi
