## master 安装

使用aliyun的源

```
apt-get update && apt-get install -y apt-transport-https

curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
 
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF

apt-get update
apt-get install -y docker.io kubeadm
```

部署脚本 kubeadm.yaml：

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controllerManager:
        extraArgs:
                horizontal-pod-autoscaler-sync-period: "10s"
                node-monitor-grace-period: "10s"
apiServer:
        extraArgs:
                runtime-config: "api/all=true"
imageRepository: registry.aliyuncs.com/google_containers
kubernetesVersion: "latest-1.23"
networking:
  podSubnet: "192.168.0.0/16"
```

因为后面网络插件安装遇见了问题，参考https://github.com/flannel-io/flannel/issues/1344，所以加了 networking 配置。

然后开始初始化：

```bash
$ kubeadm init --config kubeadm.yaml
```

init 过程中连接 kubelet 报错了：

```
[kubelet-check] The HTTP call equal to 'curl -sSL http://localhost:10248/healthz' failed with error: Get "http://localhost:10248/healthz": dial tcp 127.0.0.1:10248: connect: connection refused.
```

解决办法：

先`kubeadm reset` 清楚一下，不然等会儿重新安装会说有些文件已存在。

编辑 `/etc/docker/daemon.json`:

```json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://jen7x4zl.mirror.aliyuncs.com"]
}
```

重启docker：

```bash
$ systemctl restart docker
```

然后再次执行`kubeadm inti --config kubeadm.yaml`

记录一下必要的日志：

```
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 172.30.0.8:6443 --token go067l.k66gt7fx2cpjz04v \
        --discovery-token-ca-cert-hash sha256:98d7b902a634dbcb0a52c1f6650a103616f8ddaf9a5a9d59cb4fdb223e461c44
```

日志提示要开始使用集群需要手动执行以下命令：

```bash
$ mkdir -p $HOME/.kube
$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Kubernetes 集群默认需要加密方式访问。所以，这几条命令，就是将刚刚部署生成的 Kubernetes 集群的安全配置文件，保存到当前用户的.kube 目录下，kubectl 默认会使用这个目录下的授权信息访问 Kubernetes 集群。



查看当前唯一的节点的状态：

```bash
root@VM-0-8-ubuntu:/home/ubuntu# kubectl get nodes
NAME            STATUS     ROLES                  AGE     VERSION
vm-0-8-ubuntu   NotReady   control-plane,master   4m37s   v1.23.5
```

当前是 NotReady 状态，使用 `kubectl describe node vm-0-8-ubuntu` 查看节点详细新鞋，其中 `vm-0-8-ubuntu` 是节点名称，执行结果太长了，打出的日志中有这样一段：

```bash
 Ready            False   Sat, 26 Mar 2022 14:51:32 +0800   Sat, 26 Mar 2022 14:46:10 +0800   KubeletNotReady              container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:docker: network plugin is not ready: cni config uninitialized
```

意思是尚未部署任何网络插件。

可以使用 `kubectl get pods -n kube-system` 查看 kube-system 命名空间的 pod 状态：

```bash
root@VM-0-8-ubuntu:/home/ubuntu# kubectl get pods -n kube-system
NAME                                    READY   STATUS             RESTARTS     AGE
etcd-vm-0-8-ubuntu                      1/1     Running            0            10m
kube-apiserver-vm-0-8-ubuntu            1/1     Running            0            10m
kube-controller-manager-vm-0-8-ubuntu   0/1     CrashLoopBackOff   8 (2s ago)   10m
kube-scheduler-vm-0-8-ubuntu            1/1     Running            0            10m
```

kube-system 是 k8s 预留给系统 pod 的命名空间（非 Linux Namespace），kube-controller-manager 因为依赖网络插件，所以没起起来。

安装calico网络插件：

```
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
kubectl create -f https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml

```



"kubeadm config print init-defaults"这个命令可以告诉我们kubeadm.yaml版本信息。

> 通过 `kubectl logs -p kube-controller-manager-vm-0-8-ubuntu -n kube-system` 查看日志才知道，因为在 kubeadm.yaml 中加了  horizontal-pod-autoscaler-sync-period: "10s"  这个配置项，在当前版本已经被废弃了，导致kube-controller-manager一直起不起来，在 CrashLoopBackOff 状态，将 /etc/kubernetes/manifests/kube-controller-manager.yaml 的上述配置删除即可。



部署 Worker 节点

安装好 kubeadm 和 docker，然后执行master节点安装好之后日志中的命令：

```bash
$ kubeadm join 172.30.0.8:6443 --token bhtlzk.hwqr6ix8broo4vr7 \
        --discovery-token-ca-cert-hash sha256:39ae952bddbc1f12090887c8a6b7f2243a75c112b0d478f120b0fe84f562e77a
```

然后日志会提醒在 master 节点执行 `kubectl get nodes` 可以看见集群状态。

等待一会儿，在集群执行`kubectl get nodes` ：

```
root@VM-0-8-ubuntu:/home/ubuntu# kubectl get nodes
NAME            STATUS   ROLES                  AGE    VERSION
vm-0-5-ubuntu   Ready    <none>                 2m7s   v1.23.5
vm-0-8-ubuntu   Ready    control-plane,master   24m    v1.23.5
```

部署容器存储插件

```bash
$ git clone --single-branch --branch v1.8.7 https://github.com/rook/rook.git
$ cd rook/deploy/examples
$ ls
bucket-notification-endpoint.yaml     create-external-cluster-resources.sh  object-bucket-claim-delete.yaml        pool-device-health-metrics.yaml
bucket-notification.yaml              csi                                   object-bucket-claim-notification.yaml  pool-ec.yaml
bucket-topic.yaml                     dashboard-external-https.yaml         object-bucket-claim-retain.yaml        pool-mirrored.yaml
ceph-client.yaml                      dashboard-external-http.yaml          object-ec.yaml                         pool-test.yaml
cluster-external-management.yaml      dashboard-ingress-https.yaml          object-external.yaml                   pool.yaml
cluster-external.yaml                 dashboard-loadbalancer.yaml           object-multisite-pull-realm-test.yaml  rbdmirror.yaml
cluster-on-local-pvc.yaml             direct-mount.yaml                     object-multisite-pull-realm.yaml       README.md
cluster-on-pvc.yaml                   filesystem-ec.yaml                    object-multisite-test.yaml             rgw-external.yaml
cluster-stretched-aws.yaml            filesystem-mirror.yaml                object-multisite.yaml                  storageclass-bucket-delete.yaml
cluster-stretched.yaml                filesystem-test.yaml                  object-openshift.yaml                  storageclass-bucket-retain.yaml
cluster-test.yaml                     filesystem.yaml                       object-test.yaml                       subvolumegroup.yaml
cluster.yaml                          images.txt                            object-user.yaml                       toolbox-job.yaml
common-external.yaml                  import-external-cluster.sh            object.yaml                            toolbox.yaml
common-second-cluster.yaml            monitoring                            operator-openshift.yaml                volume-replication-class.yaml
common.yaml                           mysql.yaml                            operator.yaml                          volume-replication.yaml
crds.yaml                             nfs-test.yaml                         osd-env-override.yaml                  wordpress.yaml
create-external-cluster-resources.py  nfs.yaml                              osd-purge.yaml
```

东西挺多的，反正安装的 rook 插件，安装教程参考https://rook.github.io/docs/rook/v1.8/quickstart.html

```bash
$ kubectl apply -f common.yaml
$ kubectl apply -f operator.yaml
$ kubectl apply -f crds.yaml
$ kubectl apply -f cluster.yaml
```

参考链接：

国内源配置：https://cloud.tencent.com/developer/article/1353427

连接 kubelet 失败：https://segmentfault.com/a/1190000041553731

更改配置：https://blog.csdn.net/oceanyang520/article/details/103948450

calico: https://projectcalico.docs.tigera.io/getting-started/kubernetes/quickstart

rook: https://rook.github.io/docs/rook/v1.8/quickstart.html

