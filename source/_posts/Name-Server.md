---
title: Name Server
date: 2020-10-06 23:01:53
tags: RocketMQ
categories: 消息中间件
cover: https://hanelalo.github.io/images/202111061351737.png
---

# Name Server

# Name Server 启动

Name Server 启动的时候, 会先通过启动 `-c` 这个参数读取配置. 

```Java
        final NamesrvConfig namesrvConfig = new NamesrvConfig();
        final NettyServerConfig nettyServerConfig = new NettyServerConfig();
        nettyServerConfig.setListenPort(9876);
        if (commandLine.hasOption('c')) {
            String file = commandLine.getOptionValue('c');
            if (file != null) {
                InputStream in = new BufferedInputStream(new FileInputStream(file));
                properties = new Properties();
                properties.load(in);
                MixAll.properties2Object(properties, namesrvConfig);
                MixAll.properties2Object(properties, nettyServerConfig);

                namesrvConfig.setConfigStorePath(file);

                System.out.printf("load config properties file OK, %s%n", file);
                in.close();
            }
        }
```

可以看见  Netty 默认监听的端口就是 9876.

## NamesrvConfig 配置项

```Java
    // 主目录
    private String rocketmqHome = System.getProperty(MixAll.ROCKETMQ_HOME_PROPERTY, System.getenv(MixAll.ROCKETMQ_HOME_ENV));
    // 存储 KV 配置属性的
    private String kvConfigPath = System.getProperty("user.home") + File.separator + "namesrv" + File.separator + "kvConfig.json";
    // 配置文件存储路径, 没用, 要改的话一般都是通过 -c 来指定路径.
    private String configStorePath = System.getProperty("user.home") + File.separator + "namesrv" + File.separator + "namesrv.properties";
    private String productEnvName = "center";
    private boolean clusterTest = false;
    // 是否允许顺序消息,默认关闭.
    private boolean orderMessageEnable = false;
```



## NettySrvConfig

```Java
    // 监听端口,这里写的 8888, 但实际上默认初始化为 9876
    private int listenPort = 8888;
    // Netty 业务线程池大小
    private int serverWorkerThreads = 8;
    // netty public 线程池大小,根据不同场景, netty 提供了相应不同的线程池,
    // 比如消息发送,消息消费,心跳检测等.如果出现未注册的业务类型, 就交由 public 线程处理
    private int serverCallbackExecutorThreads = 0;
    // IO 线程池大小,主要用来解析网络请求,将请求转发到相应的业务的线程池,然后将结果返回.
    private int serverSelectorThreads = 3;
    // send oneway 最大并发度(broker端配置)
    private int serverOnewaySemaphoreValue = 256;
    // 异步发送消息最大并发度(broker端配置)
    private int serverAsyncSemaphoreValue = 64;
    // 网络连接最大空闲时间,默认 120s, 过了这个时间就关闭连接.
    private int serverChannelMaxIdleTimeSeconds = 120;
    // socket 发送缓存区大小
    private int serverSocketSndBufSize = NettySystemConfig.socketSndbufSize;
    // socket 接收缓存大小
    private int serverSocketRcvBufSize = NettySystemConfig.socketRcvbufSize;
    // ByteBuffer 是否开启
    private boolean serverPooledByteBufAllocatorEnable = true;
    // 是否开启 epoll
    private boolean useEpollNativeSelector = false;
```

## 启动 NamesrvController

有了前面的两个配置, 就可以构建一个 NamesrvController 了.

```Java
    public NamesrvController(NamesrvConfig namesrvConfig, NettyServerConfig nettyServerConfig) {
        this.namesrvConfig = namesrvConfig;
        this.nettyServerConfig = nettyServerConfig;
        this.kvConfigManager = new KVConfigManager(this);
        this.routeInfoManager = new RouteInfoManager();
        this.brokerHousekeepingService = new BrokerHousekeepingService(this);
        this.configuration = new Configuration(
            log,
            this.namesrvConfig, this.nettyServerConfig
        );
        this.configuration.setStorePathFromConfig(this.namesrvConfig, "configStorePath");
    }
```

发现这里面除了初始化配置, 还初始化了路由管理器等信息.

接下来就开始启动 NamesrvController.

首先启动两个线程池, 一个每 10 秒检查一次心跳, 一个每 10 分钟打印一次 KvConfigManager 信息.

```Java
public boolean initialize() {
        this.kvConfigManager.load();
        this.remotingServer = new NettyRemotingServer(this.nettyServerConfig, this.brokerHousekeepingService);
        // 启动 netty 工作线程池
        this.remotingExecutor =
            Executors.newFixedThreadPool(nettyServerConfig.getServerWorkerThreads(), new ThreadFactoryImpl("RemotingExecutorThread_"));
        this.registerProcessor();
        /* broker 心跳检测线程,每 10s 检测一次 */
        this.scheduledExecutorService.scheduleAtFixedRate(
            NamesrvController.this.routeInfoManager::scanNotActiveBroker,5,10,TimeUnit.SECONDS);
        /** 每 10 分钟输出一次 KvConfigManager 的信息 */
        this.scheduledExecutorService.scheduleAtFixedRate(
            NamesrvController.this.kvConfigManager::printAllPeriodically,1,10,TimeUnit.MINUTES);

        if (TlsSystemConfig.tlsMode != TlsMode.DISABLED) {
            // Register a listener to reload SslContext
            try {
                //...
            } catch (Exception e) {
                log.warn("FileWatchService created error, can't load the certificate dynamically");
            }
        }
        return true;
    }
```

最后, 注册一个关闭服务的钩子, 保证在服务关闭时, 所有线程池也关闭.

```Java
        Runtime.getRuntime().addShutdownHook(new ShutdownHookThread(log, new Callable<Void>() {
            @Override
            public Void call() throws Exception {
                controller.shutdown();
                return null;
            }
        }));
```

# 路由注册

上一章讲了 Name Server 的启动, 发现在初始化 Name Server 时,就已经初始化了路由管理器(RouteInfoManager).  

```Java
public class RouteInfoManager {
    private static final InternalLogger log = InternalLoggerFactory.getLogger(LoggerName.NAMESRV_LOGGER_NAME);
    private final static long BROKER_CHANNEL_EXPIRED_TIME = 1000 * 60 * 2;
    private final ReadWriteLock lock = new ReentrantReadWriteLock();
    /* topic 消息路由信息 */
    private final HashMap<String/* topic */, List<QueueData>> topicQueueTable;
    /* Broker 信息，包含 brokerName，集群名称，主备 Broker 名称 */
    private final HashMap<String/* brokerName */, BrokerData> brokerAddrTable;
    /* 集群信息，存储集群众所有 broker 名称 */
    private final HashMap<String/* clusterName */, Set<String/* brokerName */>> clusterAddrTable;
    /* broker 心跳信息，每次心跳检测后都会更新相应 broker 的信息 */
    private final HashMap<String/* brokerAddr */, BrokerLiveInfo> brokerLiveTable;
    /* Broker 上的 FliterServer 列表，用于类模式消息过滤 */
    private final HashMap<String/* brokerAddr */, List<String>/* Filter Server */> filterServerTable;

    public RouteInfoManager() {
        this.topicQueueTable = new HashMap<String, List<QueueData>>(1024);
        this.brokerAddrTable = new HashMap<String, BrokerData>(128);
        this.clusterAddrTable = new HashMap<String, Set<String>>(32);
        this.brokerLiveTable = new HashMap<String, BrokerLiveInfo>(256);
        this.filterServerTable = new HashMap<String, List<String>>(256);
    }
```

先去看看 Broker 发送心跳包的源码, Broker 的启动就不深究了, 好像都差不多.

找到 Broker 启动的时候, 启动了一个线程池用来发送心跳.

```Java
        this.scheduledExecutorService.scheduleAtFixedRate(new Runnable() {

            @Override
            public void run() {
                try {
                    BrokerController.this.registerBrokerAll(true, false, brokerConfig.isForceRegister());
                } catch (Throwable e) {
                    log.error("registerBrokerAll Exception", e);
                }
            }
        }, 1000 * 10, Math.max(10000, Math.min(brokerConfig.getRegisterNameServerPeriod(), 60000)), TimeUnit.MILLISECONDS);
```

跟进源码, 最终调用 BrokerOuterAPI.registerAll() 方法.

```Java
public List<RegisterBrokerResult> registerBrokerAll(
        // 集群名
        final String clusterName,
        // broker 地址
        final String brokerAddr,
        // broker 名
        final String brokerName,
        // broker id
        final long brokerId,
        // master 地址,第一次请求时为空, slave 注册后由 Name Server 返回
        final String haServerAddr,
        final TopicConfigSerializeWrapper topicConfigWrapper,
        final List<String> filterServerList,
        final boolean oneway,
        final int timeoutMills,
        final boolean compressed) {

        final List<RegisterBrokerResult> registerBrokerResultList = Lists.newArrayList();
        // 获取 Name Server 地址列表
        List<String> nameServerAddressList = this.remotingClient.getNameServerAddressList();
        if (nameServerAddressList != null && nameServerAddressList.size() > 0) {

            final RegisterBrokerRequestHeader requestHeader = new RegisterBrokerRequestHeader();
            requestHeader.setBrokerAddr(brokerAddr);
            requestHeader.setBrokerId(brokerId);
            requestHeader.setBrokerName(brokerName);
            requestHeader.setClusterName(clusterName);
            requestHeader.setHaServerAddr(haServerAddr);
            requestHeader.setCompressed(compressed);

            RegisterBrokerBody requestBody = new RegisterBrokerBody();
            requestBody.setTopicConfigSerializeWrapper(topicConfigWrapper);
            requestBody.setFilterServerList(filterServerList);
            final byte[] body = requestBody.encode(compressed);
            final int bodyCrc32 = UtilAll.crc32(body);
            requestHeader.setBodyCrc32(bodyCrc32);
            final CountDownLatch countDownLatch = new CountDownLatch(nameServerAddressList.size());
            for (final String namesrvAddr : nameServerAddressList) {
                brokerOuterExecutor.execute(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            RegisterBrokerResult result = registerBroker(namesrvAddr,oneway, timeoutMills,requestHeader,body);
                            if (result != null) {
                                registerBrokerResultList.add(result);
                            }

                            log.info("register broker[{}]to name server {} OK", brokerId, namesrvAddr);
                        } catch (Exception e) {
                            log.warn("registerBroker Exception, {}", namesrvAddr, e);
                        } finally {
                            countDownLatch.countDown();
                        }
                    }
                });
            }

            try {
                countDownLatch.await(timeoutMills, TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
            }
        }

        return registerBrokerResultList;
    }
```

注册 Broker 时, 先获取了 Name Server 的地址列表, 然后发送 broker 的 ip, 集群名, BrokerID 等等信息到每个 Name Server 完成注册.

接下里看看, Name Server 接收心跳后又怎么处理.

回去查看启动 Name Server 的代码, 在启动 NamesrvController 的时候, 还开启了一个 netty 的业务线程池.

```Java
    // 启动 netty 工作线程池
    this.remotingExecutor = Executors.newFixedThreadPool(nettyServerConfig.getServerWorkerThreads(), new ThreadFactoryImpl("RemotingExecutorThread_"));
    this.registerProcessor();
```

查看 registerProcessor() 方法, 这个线程池实际的处理逻辑, 最后会交给 `DefaultRequestProcessor` 来处理.

```Java
private void registerProcessor() {
    if (namesrvConfig.isClusterTest()) {
        this.remotingServer.registerDefaultProcessor(new ClusterTestRequestProcessor(this, namesrvConfig.getProductEnvName()),
        this.remotingExecutor);
    } else {
    this.remotingServer.registerDefaultProcessor(new DefaultRequestProcessor(this), this.remotingExecutor);
    }
}
```

看看 `DefaultRequestProcessor`  的代码, 如果请求解析为 RequestCode.REGISTER_BROKER, 也就是注册 Broker, 最终会调用到 RouteInfoManager 的 `registerBroker` 方法:

修改路由信息, 是需要加锁的, 防止并发修改路由. 

1. 维护集群信息, 根据请求中的集群名, 查看集群是否存在, 如果不存在就创建, 最后将新的 brokerName 添加进相应的集群.

```Java
    this.lock.writeLock().lockInterruptibly();
    Set<String> brokerNames = this.clusterAddrTable.get(clusterName);
    if (null == brokerNames) {
        brokerNames = new HashSet<String>();
        this.clusterAddrTable.put(clusterName, brokerNames);
    }
    brokerNames.add(brokerName);
```

1. 维护 broker 地址列表(brokerAddrTable), 同样是先判断 brokerName 是否已存在, 不存在就新建一个 BrokerData, 里面有集群名, broker 名, 以及集群中每个 id 对应 broker 的地址.

```Java
    boolean registerFirst = false;
    BrokerData brokerData = this.brokerAddrTable.get(brokerName);
    if (null == brokerData) {
        registerFirst = true;
        brokerData = new BrokerData(clusterName, brokerName, new HashMap<Long, String>());
        this.brokerAddrTable.put(brokerName, brokerData);
    }
    Map<Long, String> brokerAddrsMap = brokerData.getBrokerAddrs();
    //Switch slave to master: first remove <1, IP:PORT> in namesrv, then add <0, IP:PORT>
    //The same IP:PORT must only have one record in brokerAddrTable
    brokerAddrsMap.entrySet().removeIf(item -> 
        null != brokerAddr && brokerAddr.equals(item.getValue())
        && brokerId != item.getKey());
    String oldAddr = brokerData.getBrokerAddrs().put(brokerId, brokerAddr);
    registerFirst = registerFirst || (null == oldAddr);
```

1. 如果是 master 节点并且配置发生改变或者是第一次注册, 会新建或者更新队列信息.

```Java
    if (null != topicConfigWrapper
        && MixAll.MASTER_ID == brokerId) {
        if (this.isBrokerTopicConfigChanged(brokerAddr, topicConfigWrapper.getDataVersion())
            || registerFirst) {
            ConcurrentMap<String, TopicConfig> tcTable = topicConfigWrapper.getTopicConfigTable();
            if (tcTable != null) {
                for (Map.Entry<String, TopicConfig> entry : tcTable.entrySet()) {
                    this.createAndUpdateQueueData(brokerName, entry.getValue());
                }
            }
        }
    }
```

看看 `createAndUpdateQueueData` 方法:

```Java
private void createAndUpdateQueueData(final String brokerName, final TopicConfig topicConfig) {
        QueueData queueData = new QueueData();
        queueData.setBrokerName(brokerName);
        queueData.setWriteQueueNums(topicConfig.getWriteQueueNums());
        queueData.setReadQueueNums(topicConfig.getReadQueueNums());
        queueData.setPerm(topicConfig.getPerm());
        queueData.setTopicSynFlag(topicConfig.getTopicSysFlag());

        List<QueueData> queueDataList = this.topicQueueTable.get(topicConfig.getTopicName());
        if (null == queueDataList) {
            queueDataList = new LinkedList<QueueData>();
            queueDataList.add(queueData);
            this.topicQueueTable.put(topicConfig.getTopicName(), queueDataList);
            log.info("new topic registered, {} {}", topicConfig.getTopicName(), queueData);
        } else {
            boolean addNewOne = true;

            Iterator<QueueData> it = queueDataList.iterator();
            while (it.hasNext()) {
                QueueData qd = it.next();
                if (qd.getBrokerName().equals(brokerName)) {
                    if (qd.equals(queueData)) {
                        addNewOne = false;
                    } else {
                        log.info("topic changed, {} OLD: {} NEW: {}", topicConfig.getTopicName(), qd,
                            queueData);
                        it.remove();
                    }
                }
            }

            if (addNewOne) {
                queueDataList.add(queueData);
            }
        }
    }
```

首先判断 topic 存不存在, 不存在就创建一个, 将新的队列信息放进去.

如果 topic 存在, 根据新的队列数据和原有的对比, 决定要不要新增一条 queueData.

1. 维护 broker 心跳信息.

```Java
BrokerLiveInfo prevBrokerLiveInfo = this.brokerLiveTable.put(brokerAddr,
                        new BrokerLiveInfo(
                        System.currentTimeMillis(),
                        topicConfigWrapper.getDataVersion(),
                        channel,
                        haServerAddr));
if (null == prevBrokerLiveInfo) {
    log.info("new broker registered, {} HAServer: {}", brokerAddr, haServerAddr);
}
```

5, 维护过滤服务器信息.

```Java
if (filterServerList != null) {
    if (filterServerList.isEmpty()) {
        this.filterServerTable.remove(brokerAddr);
    } else {
        this.filterServerTable.put(brokerAddr, filterServerList);
    }
}
```

1. 如果节点是 slave 节点, 需要返回 master 信息

```Java
if (MixAll.MASTER_ID != brokerId) {
    String masterAddr = brokerData.getBrokerAddrs().get(MixAll.MASTER_ID);
    if (masterAddr != null) {
        BrokerLiveInfo brokerLiveInfo = this.brokerLiveTable.get(masterAddr);
        if (brokerLiveInfo != null) {
            result.setHaServerAddr(brokerLiveInfo.getHaServerAddr());
            result.setMasterAddr(masterAddr);
        }
    }
}
```

1. 释放锁.

```Java
this.lock.writeLock().unlock();
```

这是一个读写锁.

```Java
private final ReadWriteLock lock = new ReentrantReadWriteLock();
```

前面第一步加的是写锁, 读写锁的特性是, 支持并发读, 不支持并发写.

# 路由删除

出发 NameServer 路由删除动作的情况有两种:

1. broker 正常关闭. 在 BrokerController 启动的时候有注册一个钩子， 正常关闭时，会调用 `BrokerController.unregisterBrokerAll()` 方法, 向 Name Server 注销.
2. Broker 发生异常, 导致 Name Server 心跳检查线程扫描到该 Broker 的心跳信息已经过时.

这里以心跳检查线程删除无效 broker 为例. 这个依赖于启动 Name Server 时一起启动的心跳检查线程:

```
this.scheduledExecutorService.scheduleAtFixedRate(
            NamesrvController.this.routeInfoManager::scanNotActiveBroker,5,10,TimeUnit.SECONDS);
```

每 10 秒调用一次 `RouteInfoManager.scanNotActiveBroker()` 方法.

```Java
    private final static long BROKER_CHANNEL_EXPIRED_TIME = 1000 * 60 * 2;
    public void scanNotActiveBroker() {
        Iterator<Entry<String, BrokerLiveInfo>> it = this.brokerLiveTable.entrySet().iterator();
        while (it.hasNext()) {
            Entry<String, BrokerLiveInfo> next = it.next();
            long last = next.getValue().getLastUpdateTimestamp();
            if ((last + BROKER_CHANNEL_EXPIRED_TIME) < System.currentTimeMillis()) {
                RemotingUtil.closeChannel(next.getValue().getChannel());
                it.remove();
                log.warn("The broker channel expired, {} {}ms", next.getKey(), BROKER_CHANNEL_EXPIRED_TIME);
                this.onChannelDestroy(next.getKey(), next.getValue().getChannel());
            }
        }
    }
```

遍历 broker 心跳信息表 brokerLiveTable, 以 `BROKER_CHANNEL_EXPIRED_TIME` 为条件(默认 2 分钟)找到过期的 broker 心跳信息, 然后删除该 broker. `RemotingUtil.closeChannel(next.getValue().getChannel())` 只是用来关闭了 broker 和 Name Sevrer 之间的连接, 主要看看 `onChannelDestroy` .



1. 首先获取读锁, 然后找到了目标 broker 的心跳信息, 释放读锁.

```Java
try {
    this.lock.readLock().lockInterruptibly();
    Iterator<Entry<String, BrokerLiveInfo>> itBrokerLiveTable = this.brokerLiveTable.entrySet().iterator();
    while (itBrokerLiveTable.hasNext()) {
        Entry<String, BrokerLiveInfo> entry = itBrokerLiveTable.next();
        if (entry.getValue().getChannel() == channel) {
            brokerAddrFound = entry.getKey();
            break;
        }
    }
} finally {
    this.lock.readLock().unlock();
}
```

2. 然后获取写锁, 删除 brokerLiveTable 和 filterServerTable 中相应的 broker 的信息.

```Java
    this.lock.writeLock().lockInterruptibly();
    this.brokerLiveTable.remove(brokerAddrFound);
    this.filterServerTable.remove(brokerAddrFound);
```

3. 从 brokerAddrTable 中删除 broker 地址信息.

```Java
String brokerNameFound = null;
boolean removeBrokerName = false;
Iterator<Entry<String, BrokerData>> itBrokerAddrTable =
this.brokerAddrTable.entrySet().iterator();
    while (itBrokerAddrTable.hasNext() && (null == brokerNameFound)) {
        BrokerData brokerData = itBrokerAddrTable.next().getValue();
        Iterator<Entry<Long, String>> it = brokerData.getBrokerAddrs().entrySet().iterator();
        while (it.hasNext()) {
        Entry<Long, String> entry = it.next();
        Long brokerId = entry.getKey();
        String brokerAddr = entry.getValue();
        if (brokerAddr.equals(brokerAddrFound)) {
            brokerNameFound = brokerData.getBrokerName();
            it.remove();
            log.info("remove brokerAddr[{}, {}] from brokerAddrTable, because channel destroyed",brokerId, brokerAddr);
            break;
        }
    }
if (brokerData.getBrokerAddrs().isEmpty()) {
    removeBrokerName = true;
    itBrokerAddrTable.remove();
    log.info("remove brokerName[{}] from brokerAddrTable, because channel destroyed",brokerData.getBrokerName());
    }
}
```

4. 如果这个 broker 删除后, 该 brokerName 对应的 brokerAddrs 是空的, 那就证明这个 broker 没用了, 那就从 clusterAddrTable 中删除 brokerName.

```Java
if (brokerNameFound != null && removeBrokerName) {
    Iterator<Entry<String, Set<String>>> it = this.clusterAddrTable.entrySet().iterator();
    while (it.hasNext()) {
    Entry<String, Set<String>> entry = it.next();
    String clusterName = entry.getKey();
    Set<String> brokerNames = entry.getValue();
    boolean removed = brokerNames.remove(brokerNameFound);
    if (removed) {
        log.info("remove brokerName[{}], clusterName[{}] from clusterAddrTable, because channel destroyed",brokerNameFound, clusterName);
        if (brokerNames.isEmpty()) {
        log.info("remove the clusterName[{}] from clusterAddrTable, because channel destroyed and no broker in this cluster",clusterName);
        it.remove();
    }
    break;
        }
    }
}
```

5. 删除 brokerName 的同时从队列信息中将 broker 对应的数据也删除. 先删除 topic 中对应的 broker 数据, 如果该 topic 只包含了要删除的 broker, 那将 topic 也删除.

```Java
if (removeBrokerName) {
    Iterator<Entry<String, List<QueueData>>> itTopicQueueTable =
    this.topicQueueTable.entrySet().iterator();
    while (itTopicQueueTable.hasNext()) {
        Entry<String, List<QueueData>> entry = itTopicQueueTable.next();
        String topic = entry.getKey();
        List<QueueData> queueDataList = entry.getValue();
        Iterator<QueueData> itQueueData = queueDataList.iterator();
        while (itQueueData.hasNext()) {
            QueueData queueData = itQueueData.next();
            if (queueData.getBrokerName().equals(brokerNameFound)) {
                itQueueData.remove();
                log.info("remove topic[{} {}], from topicQueueTable, because channel destroyed",topic, queueData);
            }
        }
        if (queueDataList.isEmpty()) {
            itTopicQueueTable.remove();
            log.info("remove topic[{}] all queue, from topicQueueTable, because channel destroyed",topic);
        }
    }
}
```

6. 释放写锁.

```
this.lock.writeLock().unlock();
```

# 路由发现

回到前面讲路由注册的时候, 说到 NameServer 的请求交给 `DefaultRequestProcessor` 处理. 获取路由信息的请求. 自然也是交给他了.

当路由信息更新的时候, Name Server 并不会主动推送到客户端, 一般都是客户端自己定时调用获取最新的路由信息.

这种请求的类型是 `GET_ROUTEINFO_BY_TOPIC` , 最后调用 `getRouteInfoByTopic` 方法做真正的处理.

```Java
public RemotingCommand getRouteInfoByTopic(ChannelHandlerContext ctx,
        RemotingCommand request) throws RemotingCommandException {
        final RemotingCommand response = RemotingCommand.createResponseCommand(null);
        final GetRouteInfoRequestHeader requestHeader =
            (GetRouteInfoRequestHeader) request.decodeCommandCustomHeader(GetRouteInfoRequestHeader.class);

        TopicRouteData topicRouteData = this.namesrvController.getRouteInfoManager().pickupTopicRouteData(requestHeader.getTopic());

        if (topicRouteData != null) {
            if (this.namesrvController.getNamesrvConfig().isOrderMessageEnable()) {
                String orderTopicConf =
                    this.namesrvController.getKvConfigManager().getKVConfig(NamesrvUtil.NAMESPACE_ORDER_TOPIC_CONFIG,
                        requestHeader.getTopic());
                topicRouteData.setOrderTopicConf(orderTopicConf);
            }

            byte[] content = topicRouteData.encode();
            response.setBody(content);
            response.setCode(ResponseCode.SUCCESS);
            response.setRemark(null);
            return response;
        }

        response.setCode(ResponseCode.TOPIC_NOT_EXIST);
        response.setRemark("No topic route info in name server for the topic: " + requestHeader.getTopic()
            + FAQUrl.suggestTodo(FAQUrl.APPLY_TOPIC_URL));
        return response;
    }
```