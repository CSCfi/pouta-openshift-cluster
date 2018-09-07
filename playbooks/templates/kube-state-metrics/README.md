---+ kube-state-metrics

These YAML files deploy
[kube-state-metrics](https://github.com/kubernetes/kube-state-metrics). The
original YAML files are available in the kube-state-metrics repo. They have
been slightly modified for use in pouta-openshift-cluster. The main difference
is that the namespace used is monitoring-infra instead of kube-system.

kube-state-metrics provides various metrics on Kubernetes objects. You can find
more detailed documentation in the kube-state-metrics repository linked above.

