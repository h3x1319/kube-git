# kube-git
Is a set of tools in order to use git as a revision control system for kubernetes, as well as to perform dump of the kube cluster in form of yaml manifest to s3 bucket for backup and migration purpose.

kube-watch - is a small utility wrapper for git revision controll system as well as s3 cluster dump, that can be used in order to migrate setup to different kubernetes cluster

kube-trigger - is a utility that watches for changes under kubernetes objects in etcd using etcdctl

etcdctl exec-watch --recursive /registry/deployments/dev-fed -- bash -c './kube-watch.sh'
