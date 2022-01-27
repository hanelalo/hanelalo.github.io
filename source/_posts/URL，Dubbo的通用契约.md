---
title: URL，Dubbo的通用契约
date: 2021-05-09 19:26:00
tags: Dubbo
categories: Dubbo
cover: https://hanelalo.github.io/images/202111061356022.png
---

# Dubbo 中的 URL

Dubbo 中任意一个服务的实现都可以抽象成一个 URL，比如：

`dubbo://172.17.32.91:20880/org.apache.dubbo.demo.DemoService?anyhost=true&application=dubbo-demo-api-provider&dubbo=2.0.2&interface=org.apache.dubbo.demo.DemoService&methods=sayHello,sayHelloAsync&pid=32508&release=&side=provider&timestamp=1593253404714`

## URL 结构

以上面的 URL 为例，一个 URL 分为 5 个部分：

* protocol，也就是 `dubbo:`
* username/password，上面的 URL 中没有
* host/port，服务 host 和端口
* path，`org.apache.dubbo.demo.DemoService`
* parameters，参数



## 使用 URL 的好处

* 使用 URL 作为参数传递的契约，不用揣测数据传输格式和含义，代码易读。
* 因为有 parameters 部分，相当于 URL 中有一个 String 作为 key 的 Map 结构，如果代码需要新的扩展，只需要加 URL 中的参数即可，不用改变入参的结构。
* 公共契约，节约沟通成本。



## Dubbo 中 URL 的应用

* 从 @Adaptive、@SPI、@Activate 注解的使用原理上看，可以根据 URL 中的参数决定要使用什么扩展实现。

* 暴露服务

  当一个 Dubbo 实现的服务启动的时候，会向注册中心注册一个 URL

  ```
  dubbo://172.20.224.1:20880/org.hanelalo.echo.api.EchoService?anyhost=true&application=echo-service-provide&deprecated=false&dubbo=2.0.2&dynamic=true&generic=false&interface=org.hanelalo.echo.api.EchoService&methods=echo&pid=16952&release=2.7.7&side=provider&timestamp=1620550994445
  ```

  上面这个 URL 表示服务使用的 `dubbo` 协议，地址是 `172.20.224.1:20880`，暴露的服务是 `org.hanelalo.echo.api.EchoService`，再往后就是一些服务本身的参数配置了，如果使用 Zookeeper 作为注册中心，dynamic 的值将决定创建的是临时节点还是持久节点。

* 服务订阅

  ```
  consumer://192.168.2.6/org.hanelalo.echo.api.EchoService?application=echo-consumer&category=providers,configurators,routers&check=false&dubbo=2.0.2&init=false&interface=org.hanelalo.echo.api.EchoService&methods=echo&pid=24340&release=2.7.7&side=consumer&sticky=false&timestamp=1620551300415
  ```

  这是启动一个客户端订阅前面暴露的服务时，产生的 URL，协议是 `consumer` 表示这是一个服务消费者，`application` 参数是消费者的名字，`category` 表示要订阅的内容有 `provider`、`configurators`、`routers` 这三种类型。