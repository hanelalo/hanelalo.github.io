---
title: Dubbo入门
date: 2021-05-19 21:41:25
tags: Dubbo
categories: Dubbo
cover: https://hanelalo.github.io/images/202111061324902.png
---

# Dubbo 入门

## 背景：网站架构演进

1. 单一应用架构

   初期网站流量小，所有功能部署在一个应用中，此时的关键是用于 CURD 的 ORM 框架。

2. 垂直应用架构

   访问量上涨，将原来的单体应用垂直拆分成几个互不相关的应用分开部署，此时的关键在于 MVC 框架。

3. 分布式服务架构

   垂直拆分的应用越来越多，逐渐有了应用之间的交互，将核心业务抽离形成一个独立稳定的服务，此时用于业务调用和整合的 RPC 框架是关键。

4. 流动计算架构

   当服务越来越多，发现有些服务其实只需要极少的资源，有些服务需要更大的资源，为了提高硬件资源利用率，资源调度和治理中心 (SOA) 是关键。

## Dubbo 解决的问题

1. URL 配置管理困难，硬件负载均衡压力越来越大。
2. 服务依赖关系复杂，甚至说不清服务依赖导致的固定的服务启动顺序。
3. 服务容量不可控，需要多少台机器？什么时候加机器？

## 架构

![](/img/post/dubbo-registry.png)

* Provider

  服务提供方

* Consumer

  服务消费方

* Registry

  服务发现、服务注册中心

* Monitor

  服务监控，服务调用次数、调用时间统计

* Container

  服务运行容器

### 调用关系

1. 服务容器启动，加载要提供的服务。
2. 服务启动时向注册中心注册自己所提供的服务。
3. 服务消费者启动，向注册中心订阅自己所需的服务。
4. 注册中心返回服务提供者的地址列表给消费者，如果服务提供者有变动，将会通过和消费者建立的长连接推送变更数据给消费者。
5. 服务消费者通过**软负载均衡**算法从地址列表中选择一个服务提供者的地址进行调用，如果失败，重新选择另一台调用。
6. 服务消费者和提供者，每分钟向监控中心发送服务调用次数和调用的时间。

### 连通性

* 注册中心只是服务目录，消费者和提供者只在启动时和注册中心交互，且注册中心不会转发调用请求，负载压力较小。
* 服务消费者和提供者每分钟向监控中心报告服务调用情况，以报表展示。
* 注册中心、服务提供者、服务消费者三者之间采用的是长连接。
* 注册中心通过长连接感知服务提供者是否下线，如果提供者宕机，可以立即通过和消费者的长连接通知消费者。
* 只是注册中心宕机，不会影响服务调用，因为消费者本地缓存了服务提供者的地址列表。
* 服务消费者可以通过配置服务提供者地址直连服务提供者。

### 健壮性

* 监控中心宕机不影响使用，丢失部分监控数据。
* 注册中心对等集群，一台宕机，自动切换到另一台。
* 注册中心全部宕机，服务消费者和提供者可以依赖本地缓存中的数据通信。
* 服务提供者全部宕机，消费者会无限次重连，等待服务提供者恢复。

### 伸缩性

* 注册中心可以动态增加实例，所有客户端自动发现新的注册中心。
* 服务提供者无状态，可动态增加实例，注册中心将自动推送新的服务提供者给消费者。

## 使用示例

这里提供 3 种使用示例：

* 基于原生 API 的使用示例
* 基于 XML 配置的使用示例
* 基于注解的使用示例

> 示例代码见：https://github.com/hanelalo/exercise-dubbo

不管哪种示例，都是使用的 Zookeeper 作为注册中心，所以需要提前准备好 Zookeeper 的环境，这里直接起了一个 docker 容器：

```bash
$ docker run --name zk -p 2181:2181 -d zookeeper
```

在开始演示示例代码前，先定义要暴露的服务，其实就是一个接口，这个需要单独放到一个模块，因为不管是服务提供者还是消费者都需要依赖这个模块：

```java
public interface EchoService {
  String echo(String message);
}
```

不管是基于何种方式提供或者消费服务， EchoService 的实现都是下面这样：

```java
public class EchoServiceImpl implements EchoService {

  @Override
  public String echo(String message) {
    String now = new SimpleDateFormat("HH:mm:ss").format(new Date());
    System.out.println(
        "["
            + now
            + "]"
            + " Hello, "
            + message
            + ", request from consumer: "
            + RpcContext.getContext().getRemoteAddress());
    return message;
  }
}
```

### 基于原生 API

#### 服务提供者

```java
public class ApiProviderBootstrap {

  public static void main(String[] args) throws IOException {
    // 初始化一个服务配置对象
    ServiceConfig<EchoService> serviceConfig = new ServiceConfig<>();
    // 设置提供服务的应用名称
    serviceConfig.setApplication(new ApplicationConfig("api-echo-provider"));
    // 设置注册中心地址
    serviceConfig.setRegistry(new RegistryConfig("zookeeper://127.0.0.1:2181"));
    // 配置要注册的服务的接口
    serviceConfig.setInterface(EchoService.class);
    // 配置要注册的服务的实现
    serviceConfig.setRef(new EchoServiceImpl());
    // 启动应用, 注册服务
    serviceConfig.export();
    System.out.println("api-echo-provider started...");
    System.in.read();
  }
}
```

1. 初始化一个服务配置对象 ServiceConfig，这个类其实就是一个服务的配置对象。
2. 设置应用名称。
3. 设置注册中心，这里使用前面启动起来的 Zookeeper 容器。
4. 设置服务的接口类。
5. 设置接口的实现类，其实就是进行服务和具体实现逻辑的绑定。
6. 启动应用，将服务注册到注册中心。

#### 服务消费者

```java
public class ApiConsumerBootstrap {

  public static void main(String[] args) {
    // 服务引用配置, 其实可以理解为就是用来订阅服务的操作对象
    ReferenceConfig<EchoService> referenceConfig = new ReferenceConfig<>();
    // 设置要订阅的服务的接口类
    referenceConfig.setInterface(EchoService.class);
    // 设置消费者应用名称
    referenceConfig.setApplication(new ApplicationConfig("echo-annotation-consumer"));
    // 设置注册中心
    referenceConfig.setRegistry(new RegistryConfig("zookeeper://127.0.0.1:2181"));
    // 获取 EchoService 的代理类对象
    EchoService echoService = referenceConfig.get();
    System.out.println(echoService.echo("Hello World"));
  }
}
```

1. 初始化一个服务引用的配置 ReferenceConfig，这个类是消费者配置的抽象。
2. 设置要订阅的服务的 API。
3. 设置消费者名称。
4. 配置注册中心。
5. 获取 EchoService 的代理对象，调用这个对象的方法时，其实会通过动态代理对象发送请求到服务提供者。

### 基于 XMl 配置

Dubbo 依赖 Spring 实现 XML 配置和服务的对象管理，所以不管是服务提供者还是消费者，都需要自行编写 Spring 的配置文件，Dubbo 在此基础上又增加了自定义标签来对服务进行配置。

#### 服务提供者

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<beans xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:dubbo="http://dubbo.apache.org/schema/dubbo"
  xmlns="http://www.springframework.org/schema/beans"
  xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd
       http://dubbo.apache.org/schema/dubbo http://dubbo.apache.org/schema/dubbo/dubbo.xsd">
  <!--服务名-->
  <dubbo:application name="echo-service-provide"/>
  <!--注册中心地址-->
  <dubbo:registry address="zookeeper://127.0.0.1:2181"/>
  <!--使用 dubbo 协议并监听 20880 端口-->
  <dubbo:protocol name="dubbo" port="20880"/>
  <!-- 注册 EchoService 的 bean -->
  <bean id="echoService" class="org.hanelalo.echo.xml.provider.EchoServiceImpl"/>
  <!--声明要暴露的服务，并和具体实现的 bean 绑定-->
  <dubbo:service interface="org.hanelalo.echo.api.EchoService" ref="echoService"/>
</beans>
```

1. `<dubbo:registry>`是用来指定注册中心地址的。
2. `<dubbo:protocol>`是用来指定服务使用的网络协议和这个协议监听的端口号。
3. 将 EchoServiceImpl 注册为一个 Spring Bean。
4. `<dubbo:service>`做了两件事，`interface`指定注册的服务，`ref`执行这个服务的实现逻辑，这里直接绑定了 EchoService 的实现类的 Bean。

启动一个 Spring 容器：

```java
public class Bootstrap {
  public static void main(String[] args) throws IOException {
    ClassPathXmlApplicationContext context =
        new ClassPathXmlApplicationContext("spring/echo-provider.xml");
    context.start();
    System.in.read();
  }
}
```

#### 服务消费者

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<beans xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:dubbo="http://dubbo.apache.org/schema/dubbo"
  xmlns="http://www.springframework.org/schema/beans"
  xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd
       http://dubbo.apache.org/schema/dubbo http://dubbo.apache.org/schema/dubbo/dubbo.xsd">
  <dubbo:application name="echo-consumer"/>
  <dubbo:registry address="zookeeper://127.0.0.1:2181"/>
  <dubbo:reference id="echoService" check="false" interface="org.hanelalo.echo.api.EchoService"/>
</beans>
```

1. `<dubbo:registry>`指定注册中心。
2. `<dubbo:reference>`用来订阅服务，启动时会根据这个标签的信息向注册中心发起订阅的请求，注册中心把 EchoService 的地址列表返给消费者。

可以发现，相对于服务提供者，这里少了对协议的配置，所以，**每个服务使用的通信协议都是由服务提供者决定。**

```java
public class EchoClient {
  public static void main(String[] args) {
    ClassPathXmlApplicationContext context =
        new ClassPathXmlApplicationContext("spring/echo-consumer.xml");
    context.start();
    EchoService echoService = (EchoService) context.getBean("echoService");
    String result = echoService.echo("Hello World");
    System.out.println(result);
  }
}
```

### 基于注解配置

#### 服务提供者

服务提供者配置：

```java
@Configuration
@EnableDubbo(scanBasePackageClasses = EchoProviderConfiguration.class)
public class EchoProviderConfiguration {

  @Bean
  public ProviderConfig providerConfig(){
    return new ProviderConfig();
  }

  @Bean
  public ApplicationConfig applicationConfig() {
    ApplicationConfig applicationConfig = new ApplicationConfig();
    applicationConfig.setName("echo-annotation-provider");
    return applicationConfig;
  }

  @Bean
  public RegistryConfig registryConfig() {
    RegistryConfig registryConfig = new RegistryConfig();
    registryConfig.setProtocol("zookeeper");
    registryConfig.setAddress("localhost");
    registryConfig.setPort(2181);
    return registryConfig;
  }

  @Bean
  public ProtocolConfig protocolConfig() {
    ProtocolConfig protocolConfig = new ProtocolConfig();
    protocolConfig.setName("dubbo");
    protocolConfig.setPort(20880);
    return protocolConfig;
  }
}
```

* `@EnableDubbo`，就是用来开启对 Dubbo 的支持。
* `providerConfig()`，注册一个 `ProviderConfig` Bean，表明这是一个服务提供者。
* `applicationConfig()`，注册应用配置 Bean。
* `registryConfig()`，注册中心的配置 Bean。
* `protocolConfig()`，通信协议配置 Bean。

相比之下，这里的配置里面比 XML 配置少了对要注册的服务 EchoService 的配置，要将 EchoService 暴露出去，只需要在实现类上加上 `@DubboService` 即可。

```java
@DubboService
class EchoServiceImpl implements EchoService {

  @Override
  public String echo(String message) {
    String now = new SimpleDateFormat("HH:mm:ss").format(new Date());
    System.out.println(
        "["
            + now
            + "]"
            + " Hello, "
            + message
            + ", request from consumer: "
            + RpcContext.getContext().getRemoteAddress());
    return message;
  }
}
```

通过 Spring 启动应用：

```java
public class AnnotationProviderBootstrap {

  public static void main(String[] args) throws IOException {
    AnnotationConfigApplicationContext context =
        new AnnotationConfigApplicationContext(EchoProviderConfiguration.class);
    context.start();
    System.in.read();
  }
}
```

#### 服务消费者

配置服务消费者

```java
@Configuration
@EnableDubbo(scanBasePackageClasses = EchoConsumerConfiguration.class)
@ComponentScan(basePackageClasses = EchoConsumerConfiguration.class)
public class EchoConsumerConfiguration {

  @Bean
  public ApplicationConfig applicationConfig(){
    ApplicationConfig applicationConfig = new ApplicationConfig();
    applicationConfig.setName("echo-annotation-consumer");
    return applicationConfig;
  }

  @Bean
  public ConsumerConfig consumerConfig(){
    return new ConsumerConfig();
  }

  @Bean
  public RegistryConfig registryConfig() {
    RegistryConfig registryConfig = new RegistryConfig();
    registryConfig.setProtocol("zookeeper");
    registryConfig.setAddress("localhost");
    registryConfig.setPort(2181);
    return registryConfig;
  }
}
```

和服务提供者类似，不再一一介绍了。

再来看看如何消费服务：

```java
@Component
public class EchoAnnotationConsumer {

  @DubboReference private EchoService echoService;
  public String echo(String message){
    return echoService.echo(message);
  }
}
```

和 Spring 的注入不同，这里是通过 Dubbo 的 `@DubboReference` 注解获取的 EchoService 的代理对象。

通过 Spring 启动服务消费者：

```java
public class EchoAnnotationConsumerBootstrap {

  public static void main(String[] args) {
    AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext(EchoConsumerConfiguration.class);
    context.start();
    EchoAnnotationConsumer consumer = context.getBean(EchoAnnotationConsumer.class);
    System.out.println(consumer.echo("Hello World"));
  }
}
```

