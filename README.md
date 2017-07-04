# kube-git

Is a set of tools that allow to use git as a revision control system for kubernetes, as well as to perform dump of the kube cluster in form of yaml manifest to s3 bucket for backup and migration purpose.


# Requirements:

 - awscli command line tools
 - git
 - AWS credentials under ~/.aws or as a environmental variables
 - Git credentials under ~/.gitconfig or locally under ./.git

# kube-watch.sh 
is a small wrapper for git revision controll system as well as s3 cluster dump.

# kube-trigger
is a utility that watches for changes under kubernetes objects in etcd using etcdctl

# Howto
etcdctl exec-watch --recursive /registry/deployments/dev-fed -- bash -c './kube-watch.sh'
