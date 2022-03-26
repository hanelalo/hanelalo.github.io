---
title: Docker 容器原理浅析
date: 2022-03-24 12:34:20
tags: Kubernetes
categories: Kubernetes
cover: http://image.hanelalo.cn/image/2022032412483123.jpg
---
# Docker 容器原理浅析

在微服务盛行的时代，相对于虚拟机更轻量级的容器技术应运而生，其中 Docker 被广泛应用，虽然现在还有 Podman 等一些新兴的容器管理工具，但万变不离其宗，我们只需要知道容器到底是如何产生，如何运行的。

## 容器和虚拟机的区别是什么？

要搞清楚这两者的区别，首先得知道容器和虚拟机的原理，从原理的角度，才能明白这两者的区别。

我们知道，虚拟机本质上是基于虚拟化技术（比如 Hypervisor），模拟出了一套硬件，在这套硬件上面运行了一个完整的操作系统。

![虚拟机](http://image.hanelalo.cn/image/202203252242870.svg)

而容器一直被称为“轻量级虚拟化技术”，这种说法是为了和虚拟机对比，这种说法本身，严格来讲其实是错的。

因为容器本身其实是宿主机上的一个进程，只不过这个进程被做了各种限制和隔离，这是下一节的内容。

![容器原理](http://image.hanelalo.cn/image/202203252249140.svg)

我们知道，操作系统本身所携带的类库是很庞大的，庞大到可能其中大部分都不是运行的应用会依赖的。

虚拟机不会考虑应用是否需要，直接无脑提供了一个完整的操作系统。容器则只是将必要的一些库封装到了镜像中，所以才会有“轻量级虚拟化技术”的说法，并且，通过上面的两张提可以看出，虚拟机中的应用，是虚拟机操作系统的进程，而容器化的应用本身其实是宿主机的一个进程，Docker Engine 只是起一个管理和控制的作用。

那么，容器这种像沙盒一样的机制，是如何实现的？

## 如何实现容器的沙盒？

### Linux Namespace

首先启动一个容器，方便分析。

```bash
$ docker run -it busybox /bin/sh
```

此时会进入刚创建的容器，在容器内执行 `ps` 命令查看进程：

```bash
$ ps
PID   USER     TIME  COMMAND
    1 root      0:00 /bin/sh
    6 root      0:00 ps
```

此时容器内由两个进程，一个是 `/bin/sh`，PID 为 1，另一个是 `ps` 命令的进程，编号为 6。

上一章讲到，docker 容器本质上是宿主机的一个进程，但是为什么在容器内，看见的容器主进程的 PID 是 1 呢？

这是因为采用了 Linux Namespace 技术，为容器做了一层隔离，这里使用的是 PID Namespace，让容器内的进程以为自己的是 1 号进程。

除了 PID Namespace，还有下一章会讲到的 Mount Namespace，和做网络隔离的 Network Namespace 等。

综上，Linux Namespace 技术主要是改变了容器进程的视图，让容器进程产生了“幻觉”，像 `docker exec` 命令和 `docker run` 指令的 `-net` 参数其实就是基于 Namespace 技术实现的，将容器进程加入到目标 Namespace 即可。

### Linux Cgroups

在做了隔离之后，还需要考虑一个问题，那就是服务器资源占用问题。

比如，我们如果不对容器使用的内存做限制。宿主机的内存有 16G，宿主机上运行着很多容器，其中一个容器因为发生异常导致使用的内存一直上涨，直到将宿主机的 16G 用完，那么其他的容器也会因此而异常，因为内存不够。

上面这种情况，如果是可以接受的，那么对于严重依赖容器的微服务来讲，容器变得毫无意义，因为挂了一个应用，其他的全挂了。

所以，容器还需要对 内存、CPU、带宽等资源的使用做限制，这里使用的是 Linux Cgroups 技术。

Linux Cgroups 技术，可以限制进程使用的 CPU、带宽、磁盘、内存等资源做限制。

Linux 秉承着一切皆文件的原则，Linux Cgroups 技术不例外，我们可以通过 `mount -t cgroup` 命令查看操作系统为 cgroup 技术挂载的相关文件。

```bash
$ mount -t cgroup
cgroup on /sys/fs/cgroup/systemd type cgroup (rw,nosuid,nodev,noexec,relatime,xattr,release_agent=/usr/lib/systemd/systemd-cgroups-agent,name=systemd)
cgroup on /sys/fs/cgroup/hugetlb type cgroup (rw,nosuid,nodev,noexec,relatime,hugetlb)
cgroup on /sys/fs/cgroup/pids type cgroup (rw,nosuid,nodev,noexec,relatime,pids)
cgroup on /sys/fs/cgroup/cpu,cpuacct type cgroup (rw,nosuid,nodev,noexec,relatime,cpuacct,cpu)
cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)
cgroup on /sys/fs/cgroup/freezer type cgroup (rw,nosuid,nodev,noexec,relatime,freezer)
cgroup on /sys/fs/cgroup/perf_event type cgroup (rw,nosuid,nodev,noexec,relatime,perf_event)
cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)
cgroup on /sys/fs/cgroup/cpuset type cgroup (rw,nosuid,nodev,noexec,relatime,cpuset)
cgroup on /sys/fs/cgroup/net_cls,net_prio type cgroup (rw,nosuid,nodev,noexec,relatime,net_prio,net_cls)
cgroup on /sys/fs/cgroup/devices type cgroup (rw,nosuid,nodev,noexec,relatime,devices)
```

可以知道这些文件都在 `/sys/fs/cgroup` 目录下，其中有 cpu、memory、cpuset、devices 等类型，这些表示可以使用多个 Cgroups 资源类型。

在每种资源类型中，又有多种限制方法。

```bash
$ ll /sys/fs/cgroup/cpu
total 0
drwxr-xr-x  3 root root 0 Mar 20 22:23 YunJing
-rw-r--r--  1 root root 0 Mar 20 22:22 cgroup.clone_children
--w--w--w-  1 root root 0 Mar 20 22:22 cgroup.event_control
-rw-r--r--  1 root root 0 Mar 20 22:22 cgroup.procs
-r--r--r--  1 root root 0 Mar 20 22:22 cgroup.sane_behavior
-rw-r--r--  1 root root 0 Mar 20 22:22 cpu.cfs_period_us
-rw-r--r--  1 root root 0 Mar 20 22:22 cpu.cfs_quota_us
-rw-r--r--  1 root root 0 Mar 20 22:22 cpu.rt_period_us
-rw-r--r--  1 root root 0 Mar 20 22:22 cpu.rt_runtime_us
-rw-r--r--  1 root root 0 Mar 20 22:22 cpu.shares
-r--r--r--  1 root root 0 Mar 20 22:22 cpu.stat
-r--r--r--  1 root root 0 Mar 20 22:22 cpuacct.stat
-rw-r--r--  1 root root 0 Mar 20 22:22 cpuacct.usage
-r--r--r--  1 root root 0 Mar 20 22:22 cpuacct.usage_percpu
drwxr-xr-x  3 root root 0 Mar 25 23:03 docker
-rw-r--r--  1 root root 0 Mar 20 22:22 notify_on_release
-rw-r--r--  1 root root 0 Mar 20 22:22 release_agent
drwxr-xr-x 59 root root 0 Mar 25 22:58 system.slice
-rw-r--r--  1 root root 0 Mar 20 22:22 tasks
drwxr-xr-x  2 root root 0 Mar 20 22:22 user.slice
```

> YunJing 这个文件夹应该是因为我使用的是腾讯云的虚拟机才会有的。

这其中有很多的文件，比如 `cfs_quota_us` 和 `cfs_period_us` 这两个文件就是限制进程在长度为 cfs_period 的时间内，只能被分配到总量为 cfs_quota 的 CPU 时间。

```bash
$ cat cpu.cfs_quota_us
-1
$ cat cpu.cfs_period_us
100000
```

cfs_quota 配置为 -1 表示不限制。

那么，如何知道这个规则限制哪些进程呢？

同级目录下有一个 tasks 文件，里面记录了限制的进程 ID。

```bash
$ cat tasks
1
2
4
6
7
8
9
10
...
```

上面我们看见的是操作系统最原始的限制，那如果现在我们需要自定义限制某些进程的 CPU 资源使用，可以在 cpu 这个目录下新建一个文件夹。

```bash
$ pwd
/sys/fs/cgroup/cpu
$ mkdir test
$ cd test
$ ls
cgroup.clone_children  cpu.cfs_period_us  cpu.rt_runtime_us  cpuacct.stat          notify_on_release
cgroup.event_control   cpu.cfs_quota_us   cpu.shares         cpuacct.usage         tasks
cgroup.procs           cpu.rt_period_us   cpu.stat           cpuacct.usage_percpu
```

会发现当我们在 cpu 目录下新建一个文件夹时，文件夹里面也自动新建了一些限制方法的文件。

现在我们在操作系统中运行一个死循环：

```bash
$ while : ; do : ; done &
[1] 17851
```

死循环的 PID 为 17851，当前的 top 显示这个死循环占用了 100% 的 CPU。

```bash
top - 09:25:57 up 5 days, 11:03,  3 users,  load average: 0.74, 0.26, 0.12
Tasks: 105 total,   2 running, 103 sleeping,   0 stopped,   0 zombie
%Cpu(s): 50.4 us,  0.3 sy,  0.0 ni, 49.1 id,  0.2 wa,  0.0 hi,  0.0 si,  0.0 st
KiB Mem :  3880192 total,   193944 free,   712920 used,  2973328 buff/cache
KiB Swap:        0 total,        0 free,        0 used.  2884072 avail Mem

  PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
17851 root      20   0  116180   1232    192 R 100.0  0.0   1:22.74 bash
 2048 root      20   0  678192  12472   2416 S   0.7  0.3  37:51.62 barad_agent
 2182 root      20   0  973884  40268  18308 S   0.7  1.0  81:16.49 YDService
    1 root      20   0   43620   4056   2596 S   0.0  0.1   0:30.75 systemd
    2 root      20   0       0      0      0 S   0.0  0.0   0:00.23 kthreadd
    4 root       0 -20       0      0      0 S   0.0  0.0   0:00.00 kworker/0:0H
    6 root      20   0       0      0      0 S   0.0  0.0   0:02.18 ksoftirqd/0
    7 root      rt   0       0      0      0 S   0.0  0.0   0:01.58 migration/0
    8 root      20   0       0      0      0 S   0.0  0.0   0:00.00 rcu_bh
    9 root      20   0       0      0      0 S   0.0  0.0   1:00.04 rcu_sched
   10 root       0 -20       0      0      0 S   0.0  0.0   0:00.00 lru-add-drain
...
```

紧接着，我们在 test 文件夹下面，为这个进程加上 cpu 使用限制：

```bash
$ echo 20000 > cpu.cfs_quota_us
$ echo 17851 > tasks
$ cat cpu.cfs_period_us
100000
```

第一行将 CPU 时间限制为 20 ms（20000 us），因为 cfs_period_us 中写入的时 100000，所以受这个规则限制的进程最多占用 20% 的 CPU；

第二行将限制的 PID 写入 tasks；

然后再看看此时的 top：

```
17851 root      20   0  116180   1232    192 R  19.9  0.0   4:21.69 bash
 2182 root      20   0  973992  40284  18308 S   1.0  1.0  81:20.40 YDService
   12 root      rt   0       0      0      0 S   0.3  0.0   0:01.19 watchdog/1
 1144 root      20   0  520420  46404  16708 S   0.3  1.2   6:33.87 containerd
 2047 root      20   0  165192   9448   2052 S   0.3  0.2   5:32.34 barad_agent
 2048 root      20   0  678192  12472   2416 S   0.3  0.3  37:53.62 barad_agent
 9006 mysql     20   0 1841484 436844  18664 S   0.3 11.3  10:47.80 mysqld
    1 root      20   0   43620   4056   2596 S   0.0  0.1   0:30.77 systemd
    2 root      20   0       0      0      0 S   0.0  0.0   0:00.23 kthreadd
    4 root       0 -20       0      0      0 S   0.0  0.0   0:00.00 kworker/0:0H
    6 root      20   0       0      0      0 S   0.0  0.0   0:02.18 ksoftirqd/0
    7 root      rt   0       0      0      0 S   0.0  0.0   0:01.58 migration/0
    8 root      20   0       0      0      0 S   0.0  0.0   0:00.00 rcu_bh
...
```

确实从 100% 降到了 20%，这说明 Linux Cgroups 技术还是生效了。

除了 cpu 的限制能力， Cgroups 技术还有其他的一些限制能力，比如：

* blkio 用来限制 I/O；
* cpuset 用来指定 cpu 核和对应内存节点；
* memory 用来限制内存；

综上，容器的两大核心技术就是 Linux Namespace 用来做进程隔离，Linux Cgroups 技术用来做进程资源限制。

## 容器的文件系统

### rootfs

和上一章一样，先启动一个容器，从容器内部开始讲起。

```bash
$ docker run --rm -it ubuntu /bin/bash
```

此时会直接进入容器内，再容器内执行 `ls`，会发现和宿主机（我的是腾讯云 CentOS 7）一样的目录结构，但是执行 `ll /tmp` 就会发现只是结构一样而已，实际的内容和宿主机根本不一样，就仿佛是容器内有完整的一套 ubuntu 的文件。

其实，因为运行的就是 ubuntu 的镜像，单看文件，确实是有一个完整的 ubuntu 的文件结构。那么，这种在容器内仿佛看见的就是一个真的操作系统的现象，是如何实现的呢？

首先要从 chroot 说起，维基百科的解释是：

> A **`chroot`** on [Unix](https://en.wikipedia.org/wiki/Unix) and [Unix-like](https://en.wikipedia.org/wiki/Unix-like) [operating systems](https://en.wikipedia.org/wiki/Operating_system) is an operation that changes the apparent [root directory](https://en.wikipedia.org/wiki/Root_directory) for the current running process and its [children](https://en.wikipedia.org/wiki/Child_process). 
>
> 在 Unix 和类 Unix 操作系统中，chroot 是一个能改变当前进程及其子进程的执行根目录的操作指令。

简单来讲，就是改变进程看见的 `/` 目录，使用了 chroot 指令后，进程看见的 `/` 目录可能在宿主机上并不是 `/` 而是一个其他的什么目录。

在上一章提到的 Mount Namespace 技术就是基于 chroot 不断改良后的产物，也是第一个 Namespace。

> 需要注意的是，Mount Namespace 虽然改变的是进程的文件视图，但其实是伴随着文件挂载的发生，才会改变进程的文件试图，如果某个进程启动后没有做挂载，就算开启了 Mount Namespace，那么它的执行目录依然将继承自宿主机（这是废话）。

基于此，就能做到为容器进程准备一个完整的执行目录，比如我在 CentOS 7 上运行一个 ubuntu 的容器，其实是在素质及上的不是 CentOS 7 根目录的某个地方，有这个 ubuntu 容器运行时的完整的文件目录，比如 `docker_asdasfa`，然后 Docker Engine 将容器进程的执行根目录切换到了这个 `docker_asdasfa` 目录下，就完成了文件系统的隔离，容器内看见的就似乎是一个完整的操作系统。

那么，现在知道 Docker 启动一个容器的过程：

1. 启动 Linux Namespace 配置；
2. 设置 Linux Cgroups 参数；
3. 切换容器进程执行根目录；

> Docker 在最后一部不是使用的 chroot，而是使用 pivot_root 系统调用，如果不支持，才会使用 chroot。
>
> piovt_root 改变的是当前 Mount Namespace 的根目录，并 umount 原来的目录，chroot 只是改变的是当前进程的根目录。

上面讲到的这种为容器运行时提供隔离的执行环境的文件系统，叫做 rootfs（Root File System，根文件系统），其实就是**容器镜像**了。

### Union FS

上一节清楚了容器镜像，它是一个有着容器运行时完整依赖的文件系统，容器一直大肆宣扬的“一致性”也是基于这个实现。

接下来的问题是，它的易用性如何保证？

加入现在我为了运行 App A，基于 Ubuntu 安装了 Jre 等环境，然后将 App A 放进去，制作了一个 App A 的 rootfs，着没毛病，那如果我现在要运行 App B，它和 App A 有着一样的环境依赖，是不是也需要自己从头开始制作一个 rootfs？

这样做，不是不可以，只是太麻烦，A 和 B 只是运行的 App 不同，Ubuntu 和 Jre 都是一样的，是否可以考虑把前面的步骤的产物保留下来，做成可以复用的一个产物？

事实上，确实也是这样做的。

上面的例子只有 Ubuntu 和 Jre 这两中东西的糅合，那如果依赖的环境再复杂一点，比如我想修改一些文件，这个时候，这种可复用的产物就越来越多了，最终汇集成容器的 rootfs 时可能就会出现，A 文件夹下新增了一个 a 文件夹，另一个人一个人又加了一个 b 文件夹，到容器里面一看，会发现 A 文件夹下面同时存在 a 和 b 两个文件夹。

会发现，最终使用的镜像，可能经过了多次修改，Docker 将这些修改，每一次都保存为一层，增加 a 文件夹会加一层，增加 b 文件夹再加一层，用户的每个操作，都会增加一层，最终就是一个增量更新的 rootfs。

这种增量更新，并且还支持多个不同物理位置挂载到一个一个目录下面的 rootfs，叫做联合文件系统（Union File System），简称 UnionFS。

> Docker 在 v19.03 开始默认使用 overlay2 UnionFS，在此之前默认使用 AuFS。

> AuFS，现在的全程 Advance UnionFS，最开始叫  Another UnionFS，后来又改名 Alternative UnionFS，最终改为 Advance UnionFS。
>
> AuFS 曾试图合并进入 Linux 内核，但多次被  Linus Torvalds（Linux 之父，真的大佬）拒绝，据说是因为代码写的太烂了哈哈哈。

以 AuFS 为例，它的 rootfs 分为了 3 层，从上到下依次是：

* 可读写层

  运行中的容器修改了文件、配置都会在这一层。

* Init 层

  Docker 自动创建的一层，比如 `docker run` 时指定的一些参数，这一层在执行 `docker commit` 时不会打包进镜像中。

* 只读层

  这一层是基础镜像，如果在容器中修改了这一层的文件，其实并没有修改到这一层的文件，而只是施加了“障眼法”，比如运行时删除了只读层的 `foo.txt`，其实在 rootfs 中并没有删除，而是增加了一个 `.wh.foo.txt` 表示文件被删除了，至于修改操作，其实就是一种写时复制的机制来实现的，并非真的修改了只读层的文件。

