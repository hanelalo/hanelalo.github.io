---
title: 浅析Kubernetes中的Pod
date: 2022-03-28 21:23:36
tags: Kubernetes
categories: Kubernetes
cover: http://image.hanelalo.cn/image/202203282124366.jpg
---

# K8s Pod 浅析

## 从 Kubernetes 的架构讲起：为什么需要 Pod？

在 Docker 中，常常提到的名词是容器，试着想一下 K8s 的架构。

![kubernetes 架构](http://image.hanelalo.cn/image/202203282132359.svg)

> 取自 [kubernetes 官网](https://kubernetes.io/docs/concepts/overview/components/)。

* Control Plane，控制面板，在集群的 master 节点上，一般情况下，master 节点也不会被调度运行应用 Pod，控制面板上的组件有 `api-server`、`etcd`、`scheduler`、`controller-manager`。
  * api-server，是 k8s 对外暴露的api。
  * etcd，k8s 集群的后端存储，高可用的 KV 数据库。
  * scheduler，调度器，当要创建一个 Pod 的时候，调度器会负责选择一个节点来运行这个 Pod。
  * controller-maneger，负责一些诸如节点故障通知、监控节点状态、为 Pod 填充 Endpoints 新的等工作。
* Node，其实就是 Kubernetes 的工作节点，Pod 都在这些工作节点上运行。

假如现在又两个应用 A、B，A 和 B 之前经常发生数据交互，网络交互、文件交互都行，考虑到性能，我们肯定更愿意将这两个应用放到一台服务器上部署以提高交互的速度，假设 A 需要占用 1G 内存，B 需要占用 2G 内存，现在 K8s 集群有两个 node，其中一个 node1 内存还剩 2G，其中一个 node2 剩余 3G，当开始创建容器时，首先创建 A，发现 node1 还剩 2G，可以运行 A，所以在 node1 上运行 A，因为我们希望 A、B 在一台服务器上，所以 B 也在 node1 上创建，但是发现剩余的内存资源不够了，这个时候就只能失败。

针对上面的场景，可以考虑根据两个容器的资源总和来决定调度到哪个 node，那就势必要阻塞调度进程，等到所有容器创建指令到达时才能决定调度到哪个 node，这是个调度的性能问题。

以上是基于 Docker 的角度考虑的，调度的单位是容器，k8s 的思想有所不同，为了解决上述的问题，k8s 调度的单位是 Pod，每一个 Pod 中可以有强相关的多个容器，这样就能保证不会出现上述情况。

> 似乎只是换了个说法而已，但这确实是 Kubernetes 相对于 Mesos、Docker Swarm 等编排系统的一大优点，因为基本的思想不同，所以实现的时候肯定也天差地别，代码堆上去之后，是很不好回头的。

**所以，Pod 虽然是一个逻辑概念，但是它的出现是为了在实现容器编排的同时，还能自动的处理容器之间的复杂依赖关系。**

## 如何创建一个 Pod？

k8s 创建 Pod 或者 Service 等对象也好，都可以使用 `kubectl apply -f <config.yml>` 来根据编写好的配置文件创建。

```yaml
# nginx.yaml
apiVersion: v1
kind: Pod
metadata:
	name: nginx
	#namespace: nginx
	labels:
		app: nginx
spec:
	containers:
		- name: nginx
		  image: nginx
		  imagePullPolicy: IfNotPresent
	
```

上面就是一个简单的 nginx Pod 的配置文件。

* apiVersion，顾名思义，api 的版本而已。
* kind，表示当前要创建的对象类型，比如 Pod、Deployment、Service。
* metadata，要创建的资源的元数据，比如资源名称，所属命名空间和一些 label 标识。
* spec，这一部分就是真正的 Pod 的内容了，比如 Pod 里面都有哪些容器，这里只是一个 nginx 容器

`imagePullPolicy` 是创建容器时的镜像拉取策略，`Always` 是永远从镜像仓库拉，`IfNotPresent` 是如果本地没有再拉取，`Never` 是不拉镜像，本地没有就报错。

然后执行 `kubectl apply -f nginx.yaml`，因为没有执行命名空间，所以默认是创建在 `default` 命名空间。

然后查看 Pod：

```bash
kubectl get pod
```

就能看见 Pod 的一些简单的信息，如果创建时指定了命名空间，只需要在后面再加上 `-n <namespace>` 即可。

虽然这样也可以创建，但是，在生产环境中，我们很多应用可不止一个实例，而是会有多个实例，这样如果其中一个挂了，还有其他的可用，所以一般无状态的应用的 Pod 都是通过 Deployment 对象进行管理：

```yaml
# nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
          imagePullPolicy: IfNotPresent
```

会发现 template 部分和前面的 Pod 的内容很像，其实就是，只不过 Deployment 对象又多了一些属性，主要还是在 spec 下面：

* selector，用来选择这个 Deployment 要管理哪些 Pod，这里的意思时管理 label 中 app 属性为 nginx 的 Pod。
* replicas，创建的 Pod 数量。

执行文件 `kubectl apply -f nginx-deployment.yaml`，然后查看 Pod 就会发现启动了两个 nginx 的 Pod。

```bash
$ kubectl get pod -n nginx
NAME                     READY   STATUS    RESTARTS   AGE
nginx-66857ff745-2jb9m   1/1     Running   0          36m
nginx-66857ff745-k2fvf   1/1     Running   0          36m
```

## 配置容器健康检查和恢复

在生产环境中，对于应用是否存活这件事，不能以容器是否在运行来判断。

```yaml
# liveness.yaml
apiVersion: v1
kind: Pod
metadata:
        labels:
                test: liveness
        name: test-liveness-exec
spec:
        containers:
                - name: liveness
                  image: busybox
                  args:
                        - /bin/sh
                        - -c
                        - touch /tmp/healthy; sleep 30; rm -rf /tmp/healthy; sleep 600
                  livenessProbe:
                        exec:
                                command:
                                        - cat
                                        - /tmp/healthy
                        initialDelaySeconds: 5
                        periodSeconds: 5
```

上面的 Pod，在启动后会在 /tmp 目录下创建 healthy 文件，然后 30s 后删除，后面的 livenessProbe 就是配置健康检查的内容，表示执行 `cat /tmp/healthy` 命令，启动后 5s 执行，每 5s 一次。

当 Pod “不健康” 时会根据 Pod 的重启策略 `restartPolicy` 决定如何处理。

* Always，只要不是 Running，直接重启。
* OnFailure，容器异常时重启。
* Never，从不重启。

这个配置会对 Pod 中的所有容器生效。
