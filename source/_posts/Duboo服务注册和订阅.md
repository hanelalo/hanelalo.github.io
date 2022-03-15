---
title: Duboo服务注册和订阅
date: 2021-05-11 23:36:06
tags: Dubbo
category: Dubbo
cover: http://image.hanelalo.cn/images/202111061326845.png
---

# 服务注册和订阅

RegistryService 接口中定义了以下 4 个方法：

* register()  服务注册
* unregister() 取消注册
* subscribe() 服务订阅
* unsubscribe() 取消订阅

最终在具体的子类中通过一系列 `do*()` 方法实现这 4 个功能。

## 注册中心初始化

以 ZookeeperRegistry 为例，Dubbo 2.7 使用 Curator 作为 Zookeeper 客户端的实现，最终抽象了一个 ZookeeperClient 的接口，ZookeeperClient 接口有一个 AbstractZookeeperClient 抽象类，以泛型的方式支持了数据监听和子节点的监听，监听器的具体类型，交由具体的实现类决定。

这样设计的原因在于，历史版本中 Dubbo 中 ZookeeperClient 的实现除了 Curator 还由 ZkClient，这两种开源框架里面对与数据的监听的实现类型不一样，考虑扩展性，才选择子 AbstractZookeeperClient 中以泛型方式做抽象。

ZookeeperRegistry 通过 URL 和 ZookeeperTransporter 两个参数完成初始化。

```java
    public ZookeeperRegistry(URL url, ZookeeperTransporter zookeeperTransporter) {
	// ...
    }
```

* url

  Zookeeper 实例的地址

* zookeeperTransporter

  接口上使用 `@SPI(curator)` 说明默认实现是 curator，只提供了一个 `connect()` 方法。

  ```java
  @SPI("curator")
  public interface ZookeeperTransporter {
  
      @Adaptive({Constants.CLIENT_KEY, Constants.TRANSPORTER_KEY})
      ZookeeperClient connect(URL url);
  
  }
  ```

  和其他的很多功能接口设计一样，它也有一个抽象类的实现 `AbstractZookeeperTransporter`：

  ```java
  public abstract class AbstractZookeeperTransporter implements ZookeeperTransporter {
      private static final Logger logger = LoggerFactory.getLogger(ZookeeperTransporter.class);
      private final Map<String, ZookeeperClient> zookeeperClientMap = new ConcurrentHashMap<>();
  
      @Override
      public ZookeeperClient connect(URL url) {
          ZookeeperClient zookeeperClient;
          // address format: {[username:password@]address}
          List<String> addressList = getURLBackupAddress(url);
          // The field define the zookeeper server , including protocol, host, port, username, password
          if ((zookeeperClient = fetchAndUpdateZookeeperClientCache(addressList)) != null && zookeeperClient.isConnected()) {
              logger.info("find valid zookeeper client from the cache for address: " + url);
              return zookeeperClient;
          }
          // avoid creating too many connections， so add lock
          synchronized (zookeeperClientMap) {
              if ((zookeeperClient = fetchAndUpdateZookeeperClientCache(addressList)) != null && zookeeperClient.isConnected()) {
                  logger.info("find valid zookeeper client from the cache for address: " + url);
                  return zookeeperClient;
              }
  
              zookeeperClient = createZookeeperClient(url);
              logger.info("No valid zookeeper client found from cache, therefore create a new client for url. " + url);
              writeToClientMap(addressList, zookeeperClient);
          }
          return zookeeperClient;
      }
  }
  ```

  * 首先解析 URL，得到 Zookeeper 集群的备用实例 address 列表，通过 URL 中的 `backup` 获取。
  * 尝试从 zookeeperClientMap 缓存中获取已经建立连接的 zookeeperClient，但是如果第一次调用 `connect()` 方法，这里会是 null。
  * 缓存中没有获取，那就对 zookeeperClientMap 加锁，因为接下来会创建新的 ZookeeperClient，如果创建成功了会放到缓存中，对 zookeeperClientMap 加锁，可以避免同一个实例的连接重复创建。

  `createZookeeperClient(url)` 方法是一个抽象方法，由子类实现，其实只有 `CuratorZookeeperTransporter` 一个子类：

  ```java
  public class CuratorZookeeperTransporter extends AbstractZookeeperTransporter {
      @Override
      public ZookeeperClient createZookeeperClient(URL url) {
          return new CuratorZookeeperClient(url);
      }
  }
  ```

  这个实现类在 SPI 文件中定义的扩展名称就是 `curator`：

  ```properties
  curator=org.apache.dubbo.remoting.zookeeper.curator.CuratorZookeeperTransporter
  ```

  对于返回的 CuratorZookeeperClient，也只是做了一个初始化，那么也必然是在这个初始化操作中建立和 Zookeepr 服务器的连接。

  ```java
      public CuratorZookeeperClient(URL url) {
          super(url);
          try {
              int timeout = url.getParameter(TIMEOUT_KEY, DEFAULT_CONNECTION_TIMEOUT_MS);
              int sessionExpireMs = url.getParameter(ZK_SESSION_EXPIRE_KEY, DEFAULT_SESSION_TIMEOUT_MS);
              CuratorFrameworkFactory.Builder builder = CuratorFrameworkFactory.builder()
                      .connectString(url.getBackupAddress())
                      .retryPolicy(new RetryNTimes(1, 1000))
                      .connectionTimeoutMs(timeout)
                      .sessionTimeoutMs(sessionExpireMs);
              String authority = url.getAuthority();
              if (authority != null && authority.length() > 0) {
                  builder = builder.authorization("digest", authority.getBytes());
              }
              client = builder.build();
              client.getConnectionStateListenable().addListener(new CuratorConnectionStateListener(url));
              client.start();
              boolean connected = client.blockUntilConnected(timeout, TimeUnit.MILLISECONDS);
              if (!connected) {
                  throw new IllegalStateException("zookeeper not connected");
              }
          } catch (Exception e) {
              throw new IllegalStateException(e.getMessage(), e);
          }
      }
  ```

  1. 从 url 的 `timeout` 参数获取超时时间，默认是 5000ms。
  2. 从 url 的 `zk.session.expire` 参数获取 session 过期时间，默认是 60000ms，也就是 1 分钟。
  3. 后面就是构建连接参数并尝试建立连接，其中通过 `RetryNTimes` 指定了重试策略，还添加了一个 `CuratorConnectionStateListener` 对连接状态做监听，这个 `CuratorConnectionStateListener` 是 `CuratorZookeeperClient` 的一个内部类，监听到连接的状态变化时，调用 `CuratorZookeeperClient` 的 `stateChanged(int state)` 方法，而这个方法会遍历 `CuratorZookeeperClient.stateListeners` 这个 set 中的 `StateListener` 来处理事件。

讲完了 CuratorZookeeperRegistry 的入参，紧接着才看实现代码：

```java
    public ZookeeperRegistry(URL url, ZookeeperTransporter zookeeperTransporter) {
        super(url);
        if (url.isAnyHost()) {
            throw new IllegalStateException("registry address == null");
        }
        String group = url.getParameter(GROUP_KEY, DEFAULT_ROOT);
        if (!group.startsWith(PATH_SEPARATOR)) {
            group = PATH_SEPARATOR + group;
        }
        this.root = group;
        zkClient = zookeeperTransporter.connect(url);
        zkClient.addStateListener((state) -> {
            if (state == StateListener.RECONNECTED) {
                logger.warn("Trying to fetch the latest urls, in case there're provider changes during connection loss.\n" +
                        " Since ephemeral ZNode will not get deleted for a connection lose, " +
                        "there's no need to re-register url of this instance.");
                ZookeeperRegistry.this.fetchLatestAddresses();
            } else if (state == StateListener.NEW_SESSION_CREATED) {
                logger.warn("Trying to re-register urls and re-subscribe listeners of this instance to registry...");
                try {
                    ZookeeperRegistry.this.recover();
                } catch (Exception e) {
                    logger.error(e.getMessage(), e);
                }
            } else if (state == StateListener.SESSION_LOST) {
                logger.warn("Url of this instance will be deleted from registry soon. " +
                        "Dubbo client will try to re-register once a new session is created.");
            } else if (state == StateListener.SUSPENDED) {

            } else if (state == StateListener.CONNECTED) {

            }
        });
    }
```

1. 通过 `group` 参数从 url 中获取服务分组，默认时 `dubbo`，如果不是以 `/` 开头，就加上 `/`，这个路径就作为根节点了。
2. 调用 `zookeeperTransporter.connect(url)` 建立连接，返回一个 zkClient。
3. 调用 `zkClient.addStateListener()` 方法添加连接状态的监听器，这个监听器其实就是添加到了前面提到 `CuratorZookeeperClient.stateListeners` 中，这里面主要对 `RECONNECTED` 和 `NEW_SESSION_CREATED`  两个事件做处理，`RECONNECTED` 事件会通过 `ZookeeperRegistry#fetchLatestAddresses()`重新订阅所有服务，`NEW_SESSION_CREATED` 事件会通过 `ZookeeperRegistry#recover()` 重新注册所有服务，这两个方法其实是 ZookeeperRegistry 的父类 `FailbackRegistry` 中提供的，将在下一章中剖析 `FailbackRegistry` 实现重试机制时在分解。

## 服务注册

服务注册的能力是在 RegistryService 中定义，在子类中实现，查看源码会发现最终的具体实现类都只实现了 `do*()` 系列的方法，比如 doRegister()，这个方法是父类 FailbackRegistry 中的抽象方法，由 register() 方法调用。FailbackRegistry 这一层的封装主要是为了完成网络通信出现问题时进行重试，将在下一篇文章详解。

这里先看看 `FailbackRegistry#register()` 的主要逻辑：

```java
    @Override
    public void register(URL url) {
        // 协议检查
        if (!acceptable(url)) {
            logger.info("URL " + url + " will not be registered to Registry. Registry " + url + " does not accept service of this protocol type.");
            return;
        }
        // 调用父类 register()
        super.register(url);
        // 删除注册失败和取消注册失败的重试任务
        removeFailedRegistered(url);
        removeFailedUnregistered(url);
        try {
            // 调用子类实现中的注册逻辑
            doRegister(url);
        } catch (Exception e) {
            Throwable t = e;

            // If the startup detection is opened, the Exception is thrown directly.
            boolean check = getUrl().getParameter(Constants.CHECK_KEY, true)
                    && url.getParameter(Constants.CHECK_KEY, true)
                    && !CONSUMER_PROTOCOL.equals(url.getProtocol());
            boolean skipFailback = t instanceof SkipFailbackWrapperException;
            if (check || skipFailback) {
                if (skipFailback) {
                    t = t.getCause();
                }
                throw new IllegalStateException("Failed to register " + url + " to registry " + getUrl().getAddress() + ", cause: " + t.getMessage(), t);
            } else {
                logger.error("Failed to register " + url + ", waiting for retry, cause: " + t.getMessage(), t);
            }

            // Record a failed registration request to a failed list, retry regularly
            addFailedRegistered(url);
        }
    }
```

1. 检查 URL 是否可以注册，主要校验服务协议。

2. 调用父类中的 register() 方法，也就是 `AbstractRegistry#register()`：

   ```java
   @Override
   public void register(URL url) {
       if (url == null) {
           throw new IllegalArgumentException("register url == null");
       }
       if (logger.isInfoEnabled()) {
           logger.info("Register: " + url);
       }
       registered.add(url);
   }
   ```

   这里其实就是将注册的 url 放到 registered 这个 list 里面，从名字上就可以知道这里面记录的是已经注册的 url。

3. 删除注册和取消注册的自动任务，下一篇文章展开讲，这里不关注也不影响。

4. 调用子类的 `doRegister()` 方法完成注册。

FailbackRegistry 的逻辑清楚之后，再看看 `ZookeeperRegistry#doRegister()` 的逻辑。

```java
    @Override
    public void doRegister(URL url) {
        try {
            zkClient.create(toUrlPath(url), url.getParameter(DYNAMIC_KEY, true));
        } catch (Throwable e) {
            throw new RpcException("Failed to register " + url + " to zookeeper " + getUrl() + ", cause: " + e.getMessage(), e);
        }
    }
```

依然是 ZookeeperRegistry 中的实现，它其实就是通过 `zkClient.create()` 方法创建了一个节点，就算是完成了注册，看起来比较简单，值得注意的是，ZookeeperRegistry 继承了 FailbackRegistry，FailbackRegistry 又继承了 AbstractRegistry，在调用到 `doRegister(url)` 方法之前其实也做了本地的缓存数据的维护的。

`url.getParameter(DYNAMIC_KEY, true)` 就是获取 URL 中的一个 `dynamic` 参数来决定创建的节点是否是临时节点，默认为 `true`。

## 服务订阅

和服务注册的设计一样，真正的订阅逻辑由 `doSubscribe()` 实现，但是在父类中又维护了部分逻辑。

首先看看 `FailbackRegistry#subscribe()` 中的实现：

```java
@Override
public void subscribe(URL url, NotifyListener listener) {
    // 调用父类实现
    super.subscribe(url, listener);
    // 删除处理订阅失败的任务
    removeFailedSubscribed(url, listener);
    try {
        // 调用子类实现
        doSubscribe(url, listener);
    } catch (Exception e) {
        Throwable t = e;

        List<URL> urls = getCacheUrls(url);
        if (CollectionUtils.isNotEmpty(urls)) {
            notify(url, listener, urls);
            logger.error("Failed to subscribe " + url + ", Using cached list: " + urls + " from cache file: " + getUrl().getParameter(FILE_KEY, System.getProperty("user.home") + "/dubbo-registry-" + url.getHost() + ".cache") + ", cause: " + t.getMessage(), t);
        } else {
            // If the startup detection is opened, the Exception is thrown directly.
            boolean check = getUrl().getParameter(Constants.CHECK_KEY, true)
                    && url.getParameter(Constants.CHECK_KEY, true);
            boolean skipFailback = t instanceof SkipFailbackWrapperException;
            if (check || skipFailback) {
                if (skipFailback) {
                    t = t.getCause();
                }
                throw new IllegalStateException("Failed to subscribe " + url + ", cause: " + t.getMessage(), t);
            } else {
                logger.error("Failed to subscribe " + url + ", waiting for retry, cause: " + t.getMessage(), t);
            }
        }

        // Record a failed registration request to a failed list, retry regularly
        addFailedSubscribed(url, listener);
    }
}
```

1. 调用父类 `AbstractRegistry#subscribe()` 的订阅逻辑：

   ```java
   @Override
   public void subscribe(URL url, NotifyListener listener) {
       if (url == null) {
           throw new IllegalArgumentException("subscribe url == null");
       }
       if (listener == null) {
           throw new IllegalArgumentException("subscribe listener == null");
       }
       if (logger.isInfoEnabled()) {
           logger.info("Subscribe: " + url);
       }
       Set<NotifyListener> listeners = subscribed.computeIfAbsent(url, n -> new ConcurrentHashSet<>());
       listeners.add(listener);
   }
   ```

   父类的实现中主要是维护 `subscribed` 中订阅的 url 和通知监听器之间的映射关系。

2. 删除处理订阅失败的任务。

3. 调用子类实现，和具体的注册中心进程交互。

和服务注册不一样的是，在服务订阅的时候，传入了一个 `NotifyListener` ，这个 `NotifyListener` 在这里主要是在服务提供方发生改变时能通知到服务订阅方能做相应的处理，最终是在 `notify()` 方法中调用：

```java
    // url 是 consumer, listener 是发送通知的监听器，就是 subscribe() 方法传入的监听器, urls 是从缓存中获取的 consumer 已经订阅的 provider 的 url
	protected void notify(URL url, NotifyListener listener, List<URL> urls) {
	    // 一大堆边界条件检查
        // keep every provider's category.
        Map<String, List<URL>> result = new HashMap<>();
        for (URL u : urls) {
            // 匹配 consumer 和 provider 的 url
            if (UrlUtils.isMatch(url, u)) {
                // 通过 provider 的 url 中的 category 参数进行分类，默认为 providers
                String category = u.getParameter("category", "providers");
                List<URL> categoryList = result.computeIfAbsent(category, k -> new ArrayList<>());
                categoryList.add(u);
            }
        }
        if (result.size() == 0) {
            return;
        }
        Map<String, List<URL>> categoryNotified = notified.computeIfAbsent(url, u -> new ConcurrentHashMap<>());
        for (Map.Entry<String, List<URL>> entry : result.entrySet()) {
            String category = entry.getKey();
            List<URL> categoryList = entry.getValue();
            categoryNotified.put(category, categoryList);
            // 调用 NotifyListener
            listener.notify(categoryList);
		   // 更新本地 properties 和配置文件缓存
            saveProperties(url);
        }
    }
```

`notify()` 方法的逻辑已经在代码中注释，需要注意的是 `UrlUtils.isMatch()` 方法，其实就是做一些参数对比。

```java
    public static boolean isMatch(URL consumerUrl, URL providerUrl) {
     	// 检验 consumer 和 provider 中的 service 是不是一致，比如 consumer 是 HelloService, provider 是 EchoService, 那肯定不行
        String consumerInterface = consumerUrl.getServiceInterface();
        String providerInterface = providerUrl.getServiceInterface();

        if (!(ANY_VALUE.equals(consumerInterface)
                || ANY_VALUE.equals(providerInterface)
                || StringUtils.isEquals(consumerInterface, providerInterface))) {
            return false;
        }
		// 对比 category, 其实就是看 provider 的 category 是否在 consumer 的 category 中
        if (!isMatchCategory(providerUrl.getParameter("category", "providers"),
                consumerUrl.getParameter(CATEGORY_KEY, DEFAULT_CATEGORY))) {
            return false;
        }
        // provider 的 enable 参数检验
        if (!providerUrl.getParameter("enabled", true)
                && !ANY_VALUE.equals(consumerUrl.getParameter(ENABLED_KEY))) {
            return false;
        }
	    // 对比 provider 和 consumer 的其他参数
        String consumerGroup = consumerUrl.getParameter("group");
        String consumerVersion = consumerUrl.getParameter("version");
        String consumerClassifier = consumerUrl.getParameter("classifier", "*");

        String providerGroup = providerUrl.getParameter("group");
        String providerVersion = providerUrl.getParameter("version");
        String providerClassifier = providerUrl.getParameter("classifier", "*");
        return ("*".equals(consumerGroup) || StringUtils.isEquals(consumerGroup, providerGroup) || StringUtils.isContains(consumerGroup, providerGroup))
                && ("*".equals(consumerVersion) || StringUtils.isEquals(consumerVersion, providerVersion))
                && (consumerClassifier == null || "*".equals(consumerClassifier) || StringUtils.isEquals(consumerClassifier, providerClassifier));
    }
```

然后就是在统治之后保存更新本地缓存的 `saveProperties()` 方法：

```java
private void saveProperties(URL url) {
    // 如果 file == null，说明未开启本地缓存
    if (file == null) {
        return;
    }
    try {
        StringBuilder buf = new StringBuilder();
        Map<String, List<URL>> categoryNotified = notified.get(url);
        if (categoryNotified != null) {
            for (List<URL> us : categoryNotified.values()) {
                for (URL u : us) {
                    if (buf.length() > 0) {
                        buf.append(URL_SEPARATOR);
                    }
                    buf.append(u.toFullString());
                }
            }
        }
        properties.setProperty(url.getServiceKey(), buf.toString());
        long version = lastCacheChanged.incrementAndGet();
        // syncSaveFile 在之前介绍过，就是用来决定更新本地缓存文件是直接更新还是交给线程池更新
        if (syncSaveFile) {
            doSaveProperties(version);
        } else {
            registryCacheExecutor.execute(new SaveProperties(version));
        }
    } catch (Throwable t) {
        logger.warn(t.getMessage(), t);
    }
}
```

* 如果 `file == null`，直接返回，在前面分析注册中心初始化过程的时候，通过配置注册中心 url 中的 `file.cache` 参数可以决定是否要启用本地缓存，默认是启用的，这里如果 `file==null`，说明 `file.cache` 参数配置为 false，未开启本地配置缓存。
* 在最终保存缓存到文件的时候，由 `syncSaveFile` 决定是当前线程保存还是交给 `registryCacheExecutor` 这个单线程的线程池执行，这也是在初始化注册中心的时候，由 url 中的 `save.file` 参数决定的，默认未 `false`。

到这里，终于把服务订阅的通用部分逻辑理解透彻了，现在看看 `ZookeeperRegistry#doSubscribe()` 中的实现。

在 Zookeeper 的实现中，订阅逻辑分为了两部分：

```java
    @Override
    public void doSubscribe(final URL url, final NotifyListener listener) {
        try {
            if ("*".equals(url.getServiceInterface())) {
			// 提供给服务监控的(Monitor)
            } else {
             // 提供给服务消费方(Consumer)
            }
        } catch (Throwable e) {
            throw new RpcException("Failed to subscribe " + url + " to zookeeper " + getUrl() + ", cause: " + e.getMessage(), e);
        }
    }
```

`url` 是消费者的 url，url 的 protocol 就是 `consumer`，`listener` 参数在前面已经介绍过了。

`dubbo` 在这里的潜规则是，如果 consumer 的 url 中的 `serviceInterface` 属性是 `*`，就认为是订阅所有服务，这种场景一般也只可能是服务监控的场景，如果不是 `*`，那一般的 `serviceInterface` 都是像 `org.hanelalo.api.HelloService` 这种类全路径的形式，主要关注普通消费者的订阅，者个分支逻辑明白后，另一个分支的逻辑也就不难了。

### 普通消费者的订阅

```java
                // 用来控制监听器的运行，保证监听器在订阅完成后才开始运行
                CountDownLatch latch = new CountDownLatch(1);
                List<URL> urls = new ArrayList<>();
                // 获取各个分类的 url, 服务订阅的时候一般都是 routers, configurators 这些，每一个都对应了 zookeeper 上的一个节点的
                for (String path : toCategoriesPath(url)) {
                    ConcurrentMap<NotifyListener, ChildListener> listeners = zkListeners.computeIfAbsent(url, k -> new ConcurrentHashMap<>());
                    // 维护一个 NotifyListener 和 ChildListener 的 map
                    ChildListener zkListener = listeners.computeIfAbsent(listener, k -> new RegistryChildListenerImpl(url, k, latch));
                    if (zkListener instanceof RegistryChildListenerImpl) {
                        // 将 latch 设置进去，再订阅完成前，阻塞监听器的运行
                        ((RegistryChildListenerImpl) zkListener).setLatch(latch);
                    }
                    // 在 zookeeper 上创建持久节点
                    zkClient.create(path, false);
                    // 添加子节点的监控
                    List<String> children = zkClient.addChildListener(path, zkListener);
                    if (children != null) {
                        urls.addAll(toUrlsWithEmpty(url, path, children));
                    }
                }
                // 订阅成功，发通知
                notify(url, listener, urls);
                // 订阅完成，将 CountDownLatch 放开，不再阻塞监听器的运行
                latch.countDown();
```

1. 准备一个 CountDownLatch，用来阻塞后面初始化的监控子节点变化的监听器的运行。
2. 通过 category 参数进行地址拆分。
3. 初始化一个子节点监听器，和 NotifyListener 建立映射关系，并把第一步初始化的 CountDownLatch 设置进去，阻塞监听器的运行，防止订阅还未完成，监听器内部的处理逻辑就开始运行。
4. 通过 `zkClient.create(path, false)` 在 zookeeper 服务器上创建接点，第二个参数未 false，说明是永久节点。
5. 添加对 `path` 这个路径的子节点监控，返回子节点的 url 列表。
6. 调用 NotifyListener 发送通知，更新缓存。
7. 将第一步的 CountDownLatch 放开，订阅完成，子节点监听器不再阻塞。

现在再看看 `zkClient.addListener(path. zkListener)` 方法，它是在 ZookeeperClient 的抽象实现类 `AbstractZookeeperClient` 中实现：

```java
    @Override
    public List<String> addChildListener(String path, final ChildListener listener) {
        ConcurrentMap<ChildListener, TargetChildListener> listeners = childListeners.computeIfAbsent(path, k -> new ConcurrentHashMap<>());
        TargetChildListener targetListener = listeners.computeIfAbsent(listener, k -> createTargetChildListener(path, k));
        return addTargetChildListener(path, targetListener);
    }
```

`TargetChildListener` 看起来像一个类，但其实是一个在 `AbstractZookeeperClient` 中定义的泛型，而 `createTargetChildListener()` 和 `addTargetChildListener()` 这两个方法又是交给子类实现的抽象类，这样的设计，既有与具体的 Zookeeper 客户端框架选型解耦的关系，也有历史原因，现在的源码中也只有 `CuratorZookeeperClient` 的实现：

```java
    @Override
    public CuratorZookeeperClient.CuratorWatcherImpl createTargetChildListener(String path, ChildListener listener) {
        return new CuratorZookeeperClient.CuratorWatcherImpl(client, listener, path);
    }

    @Override
    public List<String> addTargetChildListener(String path, CuratorWatcherImpl listener) {
        try {
            return client.getChildren().usingWatcher(listener).forPath(path);
        } catch (NoNodeException e) {
            return null;
        } catch (Exception e) {
            throw new IllegalStateException(e.getMessage(), e);
        }
    }
```

