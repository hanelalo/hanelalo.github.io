---
title: Dubbo 注册中心
date: 2021-05-09 19:27:17
tags: Dubbo
categories: Dubbo
cover: https://hanelalo.github.io/images/202111061347425.png
---

# Dubbo 注册中心

![dubbo 注册中心](/img/post/dubbo-registry.png)

## Registry

注册中心实际上是独立于服务 provider 和 consumer 之外的一个独立进程，而 provider 和 consumer 只是再自己的进程中会有一个注册中心的客户端，Dubbo 中，这个客户端抽象成了 Registry 接口。

不论是服务注册还是服务订阅，都是通过自己维护的 Registry 来实现。

```java
public interface Registry extends Node, RegistryService {
    default void reExportRegister(URL url) {
        register(url);
    }

    default void reExportUnregister(URL url) {
        unregister(url);
    }
}
```

![Registry 继承关系图](/img/post/Registry.png)

Registry 继承了 Node 和 RegistryService。Node 是对注册中心的抽象，也可以是对 Provider 和 Consumer 的抽象。

```java
public interface Node {
	// 获取节点 URL
    URL getUrl();
	// 节点是否可用
    boolean isAvailable();
	// 销毁
    void destroy();
}
```

`RegistryService` 里面定义了注册、取消注册、订阅、取消订阅等方法：

```java
public interface RegistryService {
	// 通过 URL 注册服务
    void register(URL url);
	// 取消注册
    void unregister(URL url);
	// 订阅服务
    void subscribe(URL url, NotifyListener listener);
	// 取消订阅
    void unsubscribe(URL url, NotifyListener listener);
	// 查询符合一定条件的 URL
    List<URL> lookup(URL url);
}
```

回看前面的 Registry，发现它的两个 default 方法其实是委托给 `RegistryService#register` 和 `RegistryService#unregister` 实现的。

`Registry` 接口提供了一个默认的抽象类实现`AbstractRegistry`，而具体的子类只需要实现抽象类中的几个方法即可：

```java
    // Local disk cache, where the special key value.registries records the list of registry centers, and the others are the list of notified service providers
    private final Properties properties = new Properties();
    // Is it synchronized to save the file
    private boolean syncSaveFile;
	// File cache timing writing
    private final ExecutorService registryCacheExecutor = Executors.newFixedThreadPool(1, new NamedThreadFactory("DubboSaveRegistryCache", true));
	/** 包含创建该 Registry 的所有信息 */
    private URL registryUrl;
    // Local disk cache file
    private File file;

    public AbstractRegistry(URL url) {
        setUrl(url);
        if (url.getParameter(REGISTRY__LOCAL_FILE_CACHE_ENABLED, true)) {
            // Start file save timer
            syncSaveFile = url.getParameter(REGISTRY_FILESAVE_SYNC_KEY, false);
            String defaultFilename = System.getProperty("user.home") + "/.dubbo/dubbo-registry-" + url.getParameter(APPLICATION_KEY) + "-" + url.getAddress().replaceAll(":", "-") + ".cache";
            String filename = url.getParameter(FILE_KEY, defaultFilename);
            File file = null;
            if (ConfigUtils.isNotEmpty(filename)) {
                file = new File(filename);
                if (!file.exists() && file.getParentFile() != null && !file.getParentFile().exists()) {
                    if (!file.getParentFile().mkdirs()) {
                        throw new IllegalArgumentException("Invalid registry cache file " + file + ", cause: Failed to create directory " + file.getParentFile() + "!");
                    }
                }
            }
            this.file = file;
            // When starting the subscription center,
            // we need to read the local cache file for future Registry fault tolerance processing.
            loadProperties();
            notify(url.getBackupUrls());
        }
    }
```

* `properties` 

  是维护在内存中的配置键值对，主要是暴露或者订阅的接口相关的描述信息，本地保留一份注册信息的缓存快照，其实是为了降低注册中心的访问压力。

* `file`  

  `properties` 在磁盘上的文件对象

* `syncSaveFile`

  `properties` 是否要同步保存到磁盘上

* `registryCacheExecutor`

  从名称上看是注册中心缓存的 Executor，其实就是拿来保存 `properties` 到磁盘上的只用一个线程的线程池，只不过是当 `syncSaveFile` 为 `false` 时才会有用。

* `registryUrl`

  包含创建该 `Registry` 的所有信息。

观察 `AbstractRegistry` 的 `register()`、`unregister()`、`subscribe()`、`unsubscribe()` 四个方法，发现这里面并没有做和真实的注册中心进程交互的操作，只是维护了自身的数据而已，所以真正的交互操作交给了子类去重写这几个方法来实现。

各个具体实现的继承关系，发现都继承 `AbstracRegistry` 的 `FailbackRegistry` 子类，这个子类的职责是实现通信失败后重试的功能，真正的服务发现功能则是子类实现 `FailbackRegistry` 里面的 `do*()` 系列的方法来完成。

```java
public abstract class FailbackRegistry extends AbstractRegistry {
    /*  retry task map */
    /** 注册失败的 URL */
    private final ConcurrentMap<URL, FailedRegisteredTask> failedRegistered = new ConcurrentHashMap<URL, FailedRegisteredTask>();
    /** 取消注册失败的 URL */
    private final ConcurrentMap<URL, FailedUnregisteredTask> failedUnregistered = new ConcurrentHashMap<URL, FailedUnregisteredTask>();
    /** 订阅失败的 URL */
    private final ConcurrentMap<Holder, FailedSubscribedTask> failedSubscribed = new ConcurrentHashMap<Holder, FailedSubscribedTask>();
    /** 取消订阅失败的 URL */
    private final ConcurrentMap<Holder, FailedUnsubscribedTask> failedUnsubscribed = new ConcurrentHashMap<Holder, FailedUnsubscribedTask>();

    /**
     * The time in milliseconds the retryExecutor will wait
     */
    private final int retryPeriod;

    // Timer for failure retry, regular check if there is a request for failure, and if there is, an unlimited retry
    private final HashedWheelTimer retryTimer;
}
```

* `failedRegistered` 

  key 是注册失败的 URL，value 是重试任务。

* `failedUnregistered`

  key 是取消注册失败的 URL，value 是重试任务。

* `failedSubscribed`

  key 是订阅失败的 URL，value 是重试任务。

* `failedUnsubscribed`

  key 是取消订阅失败的 URL，value 是重试任务。

* `retryPeriod`

  重试间隔，默认为 5000 毫秒，可以在 URL 中通过 `retry.period` 配置。

* `retryTimer`

  重试任务的时间论算法实现

原本是还有一个 `failedNotifyed` 系列的通知重试任务，但是最新的源码中已经删除了，原因见：[remove notification retry task](https://github.com/apache/dubbo/pull/6401)



## RegistryFactory

![RegistryFactory 继承结构](/img/post/RegistryFactory.png)

`RegistryFactory` 是 `Registry` 的工厂类。

```java
@SPI("dubbo")
public interface RegistryFactory {

    @Adaptive({"protocol"})
    Registry getRegistry(URL url);
}
```

`RegistryFacotry` 通过 `SPI` 指定了默认的扩展实现为 `dubbo`，查看源码重的 SPI 配置文件，其实就是 `DubboRegistryFactory`。

`getRegistry(URL url)` 方法又通过 `@Adaptive` 注解指定通过 URL 中的 `protocol` 参数来决定使用哪一个扩展实现。

`RegistryFactory` 也有一个抽象实现类 `AbstractRegistryFactory`，除此之外还有一个 `RegistryFactoryWrapper` 包装类直接实现了 `RegistryFactory` 接口。

```java
public class RegistryFactoryWrapper implements RegistryFactory {
    private RegistryFactory registryFactory;

    public RegistryFactoryWrapper(RegistryFactory registryFactory) {
        this.registryFactory = registryFactory;
    }

    @Override
    public Registry getRegistry(URL url) {
        return new ListenerRegistryWrapper(registryFactory.getRegistry(url),
                Collections.unmodifiableList(ExtensionLoader.getExtensionLoader(RegistryServiceListener.class)
                        .getActivateExtension(url, "registry.listeners")));
    }
}
```

构造函数传入的依然是一个 `RegistryFactory` 的实现，而包装这一层的意义在于，`getRegistry()` 方法返回的是一个 `Registry` 的包装类 `ListenerRegistryWrapper`，它支持通过 `RegistryServiceListener` 对 `Registry` 进行事件监听，实际上 `RegistryServiceListener` 就监听了 `register`、`unregister`、`subscribe`、`unsubscribe` 四种事件。

```java
@SPI
public interface RegistryServiceListener {
    default void onRegister(URL url) {

    }


    default void onUnregister(URL url) {

    }

    default void onSubscribe(URL url) {

    }

    default void onUnsubscribe(URL url) {

    }
}
```

`RegistryServiceListener` 使用了 `SPI` 注解，说明它是可以通过 dubbo 的 SPI 机制加载监听器实例的， `RegistryFactoryWrapper` 中也确实是通过 `ExtensionLoader.getExtensionLoader(RegistryServiceListener.class).getActivateExtension(url, "registry.listeners")` 获取监听器实例。

具体是同可以参考源码中 `RegistryFactoryWrapperTest` 测试类。



> 注册和订阅的过程，下次一定！！！

