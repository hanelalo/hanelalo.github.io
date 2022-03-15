---
title: 简单实现一个 RPC 框架
date: 2021-04-29 21:46:36
tags: Dubbo
categories: Dubbo
cover: http://image.hanelalo.cn/images/202111061312140.png
---

# 简单实现一个 RPC 框架

> 本文为拉勾教育《Dubbo源码解读与实战》学习笔记。
>
> Dubbo 最开始是 alibaba 开发的框架，后来弃用了，最近几年微服务盛行，alibaba 又想发展开源事业，所以又把 Dubbo 捡了起来，更新了使用到的技术框架，优化了代码和测试之后，就捐献给了 apache 基金会，现在去看 Dubbo 的源码，还能看见有些地方还有针对 `alibaba` 这个包路径的处理。

## 技术框架依赖

虽然只是练手，没必要，但考虑到扩展性，大部分组件都抽象成统一的接口。

框架的网路通信基于 netty 实现，请求和响应使用 Hessian 做序列化，logback + slf4j 做了日志支持，zookeeper 客户端选用 curator，为了偷懒，还加入了国产的开源工具 hutool 做一些常用的判断等等。

```xml
  <dependencies>
    <dependency>
      <groupId>io.netty</groupId>
      <artifactId>netty-all</artifactId>
      <version>4.1.6.Final</version>
    </dependency>
    <dependency>
      <groupId>com.caucho</groupId>
      <artifactId>hessian</artifactId>
      <version>4.0.38</version>
    </dependency>
    <dependency>
      <groupId>cn.hutool</groupId>
      <artifactId>hutool-all</artifactId>
      <version>5.4.0</version>
    </dependency>
    <dependency>
      <groupId>org.slf4j</groupId>
      <artifactId>slf4j-api</artifactId>
      <version>1.7.30</version>
    </dependency>
    <dependency>
      <groupId>ch.qos.logback</groupId>
      <artifactId>logback-classic</artifactId>
      <version>1.2.3</version>
    </dependency>
    <dependency>
      <groupId>ch.qos.logback</groupId>
      <artifactId>logback-core</artifactId>
      <version>1.2.3</version>
    </dependency>
    <dependency>
      <groupId>org.apache.curator</groupId>
      <artifactId>curator-x-discovery</artifactId>
      <version>4.0.1</version>
    </dependency>
  </dependencies>
```

netty 是开源的高性能 Java 网络通信框架，封装了 Java 网络 IO 的繁杂操作，为网络通信相关的开发节省了不少事，很多自定义的网络协议都是使用 netty 实现，对于常见的网络通信问题，netty 也提供了解决方案，比如 TCP 的粘包、半包问题，值得一提的是，Spring 家族中设计网络调用的部分其实也是使用 netty 实现的。

Hessian 本身是一个二进制 WebService 协议，这里只是用来做对象的序列化和反序列化而已。

curator 其实就是一个 zookeeper 的 Java 客户端程序，也是 Apache 基金会的看开源项目，官网的通俗解释就是 `Guava is to Java what Curator is to Zookeeper`，没理解错的话就是说 curator 对于 zookeeper 来说，就相当于是 Guava 在 Java 中的意义。

netty 本身支持好几种日志框架的接入，使用 logback + slf4j 只是因为平时也在用而已，日志配置如下：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration debug="false">
  <!--控制台日志， 控制台输出 -->
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="ch.qos.logback.classic.encoder.PatternLayoutEncoder">
      <!--格式化输出：%d表示日期，%thread表示线程名，%-5level：级别从左显示5个字符宽度,%msg：日志消息，%n是换行符-->
      <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} - %msg%n</pattern>
    </encoder>
  </appender>
  <!-- 日志输出级别 -->
  <root level="INFO">
    <appender-ref ref="STDOUT" />
  </root>
</configuration>
```

## 代码架构设计

首先需要明确我们需要实现的功能：

![代码架构设计](/img/post/simple-rpc-code-arch.png)

* codec  提供请求和响应的编解码能力。
* factory 服务提供者的服务管理，参考 Spring 容器，服务其实就相当于一个单例 Bean，需要一个工厂管理这些服务的实例。
* protocol  自定义协议
* proxy 服务调用的代理，使用 JDK 动态代理，其实就是为了实现调用远程方法就像调本地方法的效果
* registry  服务注册中心通信模块，这里是 Zookeeper 作为注册中心的实现
* serialization  序列化模块，和 codec 的区别在于，codec 是在依赖 serialization 的基础上还有网络通信的处理。
* transport  数据传输服务，其实就是客户端和服务端的实例对象，这里会开启网络端口的监听，接受请求然后搭配其他模块做出响应。

## 自定义协议

每一条网络上的消息，都抽象成协议头和要传输的数据。

```java
public class Message<T> {
  private Header header;
  private T content;
}
```

协议头的定义如下：

```java
/**
 * 协议头部信息
 */
public class Header {

  /** 魔数 */
  private short magic;
  /** 版本 */
  private byte version;
  /** 附加信息 */
  private byte extraMsg;
  /** 消息id */
  private Long messageId;
  /** 消息体长度 */
  private Integer size;
}
```

`magic` 字段， `short` 类型，2 字节，只是为了和其他协议区分开，也是为了在网络数据反序列化时用来识别是否是本协议数据的标识，这个在后面处理粘包和半包问题时就知道了。

`version` 字段，1 字节，只不过是让协议设计的更加完善，在平时练习的时候用处不大。

`extraMsg` 字段，1 字节，在实现的时候并没有用到，不过如果要实现服务的心跳检测时，就需要使用到这个字段了。

`messageId` 字段，消息 id，`Long` 类型，8 字节。

`size` 字段，消息主题的长度，`int` 类型，4 字节。

上面每个字段都有特别强调有几个字节，需要注意，因为 RPC 追求效率，使用的二进制协议，所以数据的每个字节代表的意思都是很精确的。

既然是 RPC 框架，那每次调用就需要知道要调用的是哪个服务的哪个方法，方法参数类型，和参数列表，所以每次调用的请求数据可以抽象成：

```java
/**
 * 请求信息
 */
public class Request implements Serializable {
  /** 服务名 */
  private String serviceName;
  /** 方法名 */
  private String methodName;
  /** 参数类型列表 */
  private Class[] argTypes;
  /** 参数 */
  private Object[] args;

  public Request() {
  }

  public Request(String serviceName, String methodName, Object[] args) {
    this.serviceName = serviceName;
    this.methodName = methodName;
    this.args = args;
    this.argTypes = new Class[args.length];
    for (int i = 0; i < args.length; i++) {
      argTypes[i] = args[i].getClass();
    }
  }
```

然后，每次调用，大概率都会有返回值，所以需要定义响应信息：

```java
/**
 * 响应信息
 */
public class Response implements Serializable {
  /** 相应错误码，正常为 0 ，不为 0 说明是异常响应*/
  private int code = 0;
  /** 错误信息 */
  private String errorMsg;
  /** 请求返回信息 */
  private Object result;
}
```



## 序列化

这个简单， Hessian 本身就提供了方便序列化的 API。

为什么要序列化? 因为网络通信，不管用的什么协议，最终传输的数据都是二进制的。

为了扩展性，定义 `Serialization` 接口，只不过只增加 Hessian 的实现：

```java
public interface Serialization {

  /**
   * 序列化
   */
  <T> byte[] serialize(T obj) throws IOException;

  /**
   * 反序列化
   */
  <T> T deserialize(byte[] data, Class<T> clazz) throws IOException;
}
```

```java
public class HessianSerialization implements Serialization {

  /**
   * 序列化
   */
  @Override
  public <T> byte[] serialize(T obj) throws IOException {
    ByteArrayOutputStream bos = new ByteArrayOutputStream();
    Hessian2Output out = new Hessian2Output(bos);
    out.writeObject(obj);
    out.flush();
    return bos.toByteArray();
  }

  /**
   * 反序列化
   */
  @Override
  public <T> T deserialize(byte[] data, Class<T> clazz) throws IOException {
    InputStream is = new ByteArrayInputStream(data);
    Hessian2Input input = new Hessian2Input(is);
    return (T) input.readObject(clazz);
  }
}
```

同时也提供 `SerializationFactory` 来将序列化方式的选择逻辑封装，具体使用的序列化方式，可以是双方约定，然后存在协议头的 `extraMsg` 字段中，这里只有 Hessian 的实现，所以就直接返回一个默认实现：

```java
public class SerializationFactory {
  public static Serialization get() {
    return new HessianSerialization();
  }
}
```

 ## 注册中心

同样是扩展性考虑，对注册中心抽象一个 `Registry` 接口。

```java
public interface Registry <T>{

  void registerService(ServiceInstance<T> serviceInstance) throws Exception;

  void unregisterService(ServiceInstance<T> serviceInstance) throws Exception;

  List<ServiceInstance<T>> queryInstance(String serviceName);
}
```

> 写到这里发现一个问题，这 `ServiceInstance` 是 curator 中的 API，对具体实现有依赖，这违背了最开始抽象接口的思想，不过反正是个练习，就得过且过吧。

然后，提供一个 Zookeeper 的实现。

```java
public class ZookeeperRegistry<T> implements Registry<T> {

  /** 服务实例序列化 */
  private InstanceSerializer serializer = new JsonInstanceSerializer<>(ServerInfo.class);
  /** 服务发现 */
  private ServiceDiscovery<T> serviceDiscovery;
  /** curator 提供的服务实例信息的本地缓存机制 */
  private ServiceCache<T> serviceCache;
  /** 默认的 zookeeper 地址 */
  private String address = "localhost:2181";

  public void start() throws Exception {
    String root = "/hanelalo/rpc";
    // 创建连接 zookeeper 的客户端实例
    CuratorFramework client = CuratorFrameworkFactory
        .newClient(address, new ExponentialBackoffRetry(1000, 3));
    client.start();
    // 阻塞，直到连接成功
    client.blockUntilConnected();
    // 检查节点是否存在，不存在就创建
    client.createContainers(root);
    // 初始化服务发现逻辑
    serviceDiscovery =
        ServiceDiscoveryBuilder.builder(ServerInfo.class)
            .client(client)
            .basePath(root)
            .serializer(serializer).build();
    serviceDiscovery.start();
    // 缓存 /helloService 实例信息到本地
    serviceCache = serviceDiscovery.serviceCacheBuilder().name("/helloService").build();
    serviceCache.start();
  }

  @Override
  public void registerService(ServiceInstance<T> serviceInstance) throws Exception {
    serviceDiscovery.registerService(serviceInstance);
  }

  @Override
  public void unregisterService(ServiceInstance<T> serviceInstance) throws Exception {
    serviceDiscovery.unregisterService(serviceInstance);
  }

  @Override
  public List<ServiceInstance<T>> queryInstance(String serviceName) {
    return serviceCache.getInstances().stream()
        .filter(instance -> StrUtil.equals(instance.getName(), serviceName))
        .collect(Collectors.toList());
  }
}
```

虽然写了很多注释，但是依然有需要强调的地方。

在创建 zookeeper 客户端实例时，创建了一个 `ExponentialBackoffRetry`，定义的是重试策略，`new ExponentialBackoffRetry(1000, 3)` 的意思是，最多重试 3 次，每次重试的间隔是 `max(1000, 1000 * random(1 << retryCount))`，也就是说重试间隔是 1000 的倍数，最少间隔 1000 ms。

##  请求和响应编码解码

### 半包和粘包

因为不管应用层的协议怎么定义，传输层终究还是使用的 TCP 协议，所以不得不处理 TCP 的粘包半包问题，netty 提供了三种粘包半包的处理方式。

* 定长窗口

  就是将协议数据长度写死，比如，不管是怎样的请求，我的协议数据长度，就是 100 字节。

* 固定结束符

  就像 C 语言里面的字符串一样，字符串的结束符都是 `'\0'` 一样，认为遇见某个字符时就是这条消息读取完毕了。

* 定义数据长度字段

  相对与前两种，这一种比较灵活，以前面自定义的协议为例，在协议头里面，有几个固定字段，还有一个专门的字段用来记录消息数据的长度。

  ```java
  /**
   * 协议头部信息
   */
  public class Header {
  
    /** 魔数 */
    private short magic;
    /** 版本 */
    private byte version;
    /** 附加信息 */
    private byte extraMsg;
    /** 消息id */
    private Long messageId;
    /** 消息体长度 */
    private Integer size;
  }
  ```

  会发现，每条消息，只要跳过前 12 个字节，然后再读取后面四个字节，就得到了消息数据的长度 `size`，然后再往后读取 `size` 个字节，就刚好读取了一条完整的消息，一个字节不多，一个字节不少，netty 提供的第三种解决方案就是这样。

这里也采用第三种方式来处理粘包半包问题：

```java
public class Splitter extends LengthFieldBasedFrameDecoder {

  /**
   * @param maxFrameLength 每一个窗口最大长度
   * @param lengthFieldOffset 长度标识偏移量
   * @param lengthFieldLength 长度标识符数据长度
   */
  public Splitter(int maxFrameLength, int lengthFieldOffset,
      int lengthFieldLength) {
    super(maxFrameLength, lengthFieldOffset, lengthFieldLength);
  }

  @Override
  protected Object decode(ChannelHandlerContext ctx, ByteBuf in) throws Exception {
    // 非本协议连接，拒绝
    if(in.getShort(in.readerIndex()) != Constances.MAGIC){
      System.out.println("非本协议连接...");
      ctx.channel().close();
      return null;
    }
    return super.decode(ctx, in);
  }
}
```

首先，为了确定当前的数据是本协议的数据，需要先读取 2 个字节，得到魔数，如果和协议定义的魔数不等，说明不是本协议的数据，那就不处理了。

### 请求编码解码

> 先明确一点，客户端要编码的是请求，解码的响应，服务端要编码的是响应，解码的是请求。

#### 编码

```java
public class RequestRpcEncoder extends MessageToByteEncoder<Message<Request>> {

  @Override
  protected void encode(ChannelHandlerContext channelHandlerContext, Message<Request> message,
      ByteBuf byteBuf) throws Exception {
    Header header = message.getHeader();
    byteBuf.writeShort(header.getMagic());
    byteBuf.writeByte(header.getVersion());
    byteBuf.writeByte(header.getExtraMsg());
    byteBuf.writeLong(header.getMessageId());
    Request request = message.getContent();
    byte[] bytes = SerializationFactory.get().serialize(request);
    byteBuf.writeInt(bytes.length);
    byteBuf.writeBytes(bytes);
  }
}
```

这里按照协议头的数据类型逐一写到通信管道中，注意的是，这里每个字段写入的顺序都是严格要求的，并且，受前面粘包半包处理逻辑的影响，消息体长度字段必须最后写入，后面再紧跟消息体数据。

`MessageToByteEncoder` 是 netty 框架提供的从 Java 对象转换成二进制的 `ChannelOutboundHandlerAdapter`，因为不是本文重点，不扩展，其实非要实现一个编码逻辑也可以，只不过 `MessageToByteEncoder` 封装了类型匹配的逻辑。

#### 解码

```java
public class RequestRpcDecoder extends ByteToMessageDecoder {

  @Override
  protected void decode(ChannelHandlerContext channelHandlerContext, ByteBuf byteBuf,
      List<Object> list) throws Exception {
    if(byteBuf.readableBytes() < Constances.HEADER_SIZE){
      return;
    }
    byteBuf.markReaderIndex();
    short magic = byteBuf.readShort();
    if (magic != Constances.MAGIC) {
      byteBuf.resetReaderIndex();
      throw new RuntimeException("magic number error: " + magic);
    }
    byte version = byteBuf.readByte();
    byte extraMsg = byteBuf.readByte();
    long messageId = byteBuf.readLong();
    int size = byteBuf.readInt();
    if(byteBuf.readableBytes() < size){
      byteBuf.resetReaderIndex();
      return;
    }
    byte[] payload = new byte[size];
    byteBuf.readBytes(payload);
    Serialization serialization = SerializationFactory.get();
    Request request = serialization.deserialize(payload, Request.class);
    Header header = new Header();
    header
        .setExtraMsg(extraMsg)
        .setMagic(magic)
        .setMessageId(messageId)
        .setSize(size)
        .setVersion(version);
    Message<Request> message = new Message<Request>().setHeader(header).setContent(request);
    list.add(message);
  }
}
```

解码和编码是相反的过程，这里拿到的数据是已经经过 `Spliiter` 拆包后的数据，所以肯定是一个完整的消息数据。

### 响应编码解码

不解释，和请求的编码解码一样的。

```java
public class ResponseRpcEncoder extends MessageToByteEncoder<Message<Response>> {

  @Override
  protected void encode(ChannelHandlerContext channelHandlerContext, Message<Response> message,
      ByteBuf byteBuf) throws Exception {
    Header header = message.getHeader();
    byteBuf.writeShort(header.getMagic());
    byteBuf.writeByte(header.getVersion());
    byteBuf.writeByte(header.getExtraMsg());
    byteBuf.writeLong(header.getMessageId());
    Response response = message.getContent();
    byte[] bytes = SerializationFactory.get().serialize(response);
    byteBuf.writeInt(bytes.length);
    byteBuf.writeBytes(bytes);
  }
}
```

```java
public class ResponseRpcDecoder extends ByteToMessageDecoder {

  @Override
  protected void decode(ChannelHandlerContext channelHandlerContext, ByteBuf byteBuf,
      List<Object> list) throws Exception {
    if(byteBuf.readableBytes() < Constances.HEADER_SIZE){
      return;
    }
    byteBuf.markReaderIndex();
    short magic = byteBuf.readShort();
    if (magic != Constances.MAGIC) {
      byteBuf.resetReaderIndex();
      throw new RuntimeException("magic number error: " + magic);
    }
    byte version = byteBuf.readByte();
    byte extraMsg = byteBuf.readByte();
    long messageId = byteBuf.readLong();
    int size = byteBuf.readInt();
    if(byteBuf.readableBytes() < size){
      byteBuf.resetReaderIndex();
      return;
    }
    byte[] payload = new byte[size];
    byteBuf.readBytes(payload);
    Serialization serialization = SerializationFactory.get();
    Response response = serialization.deserialize(payload, Response.class);
    Header header = new Header();
    header
        .setExtraMsg(extraMsg)
        .setMagic(magic)
        .setMessageId(messageId)
        .setSize(size)
        .setVersion(version);
    Message<Response> message = new Message<Response>().setHeader(header).setContent(response);
    list.add(message);
  }
}
```

## 服务实例对象管理

在生产者这一端，参考 Spring 的思想，对于本身的所提供的服务，默认采用单例模式，所以需要一个类似 IOC 一样对象管理容器，简单实现一下就好。

```java
public class BeanManager {

  private static final Map<String, Object> SERVICES = new HashMap<>();

  public static Object getBean(String serviceName) {
    return SERVICES.get(serviceName);
  }

  public static void registry(String serviceName, Object object){
    SERVICES.put(serviceName, object);
  }

}
```

## 初始化服务端和客户端 API

### 服务端



```java
public class RpcServer {

  private EventLoopGroup boosGroup;
  private EventLoopGroup workerGroup;
  private ServerBootstrap serverBootstrap;
  private final int port;

  public RpcServer(int port) {
    this.port = port;
    boosGroup = new NioEventLoopGroup(4,task -> {
      return new Thread(task, "server-boss-group");
    });
    workerGroup = new NioEventLoopGroup(9,task -> {
      return new Thread(task, "server-worker-group");
    });
    serverBootstrap =
        new ServerBootstrap()
            .group(boosGroup, workerGroup)
            .channel(NioServerSocketChannel.class)
            .option(ChannelOption.SO_REUSEADDR, Boolean.TRUE)
            .childOption(ChannelOption.TCP_NODELAY, Boolean.TRUE)
            .childOption(ChannelOption.ALLOCATOR, PooledByteBufAllocator.DEFAULT)
            .handler(new LoggingHandler(LogLevel.INFO))
            .childHandler(
                new ChannelInitializer<NioSocketChannel>() {
                  @Override
                  protected void initChannel(NioSocketChannel socketChannel) throws Exception {
                    socketChannel.pipeline().addLast(new Splitter(Integer.MAX_VALUE, 12, 4));
                    socketChannel.pipeline().addLast(new RequestRpcDecoder());
                    socketChannel.pipeline().addLast(new ResponseRpcEncoder());
                    socketChannel.pipeline().addLast(new RpcServerHandler());
                  }
                });
  }

  public ChannelFuture start(){
    ChannelFuture channelFuture = serverBootstrap.bind(port);
    Channel channel = channelFuture.channel();
    channel.closeFuture();
    return channelFuture;
  }

}

```

在初始化服务端的时候，工作线程处理逻辑中首先会通过 `Splitter` 拆包，然后经过 `RequestRpcDncoder` 做请求信息的解码，然后经过 `RpcServerHandler` 做业务处理返回响应信息，最后经过 `ResponseRpcEncoder` 编码后返回给客户端。虽然是先添加 `ResponseRpcEncoder` 后添加 `RpcServerHandler`，但是因为 `RpcServerHandler` 是入站适配器，`ResponseRpcEncoder` 是出站适配器，所以整个消息的处理流程是 `RpcServerHandler` 在 `ResponseRpcEncoder` 之前的。

接下来再看看是如何调用的业务处理逻辑。

```java
public class RpcServerHandler extends SimpleChannelInboundHandler<Message<Request>> {

  private static final AtomicInteger threadId = new AtomicInteger(1);

  private final Executor executor =
      new ThreadPoolExecutor(
          3,
          10,
          60,
          TimeUnit.SECONDS,
          new SynchronousQueue<>(),
          task -> new Thread(task, "server-handler-thread-" + threadId.getAndIncrement()),
          new AbortPolicy());

  @Override
  protected void channelRead0(ChannelHandlerContext channelHandlerContext,
      Message<Request> requestMessage) throws Exception {
    executor.execute(new InvokeRunnable(channelHandlerContext, requestMessage));
  }
}
```

这里也是实现了一个 netty 提供的入站适配器 `SimpleChannelInboundHandler`，可以处理指定类型的请求信息。

参考现代的各种应用服务器，都是将业务处理逻辑放到了线程中，所以在这里也初始化了一个线程池，将真正的业务处理逻辑封装到 `InvokeRunnable` 中，下面只是简单举个例子。

```java
public class InvokeRunnable implements Runnable {

  private final ChannelHandlerContext ctx;
  private final Message<Request> message;

  public InvokeRunnable(ChannelHandlerContext ctx, Message<Request> message) {
    this.ctx = ctx;
    this.message = message;
  }

  @Override
  public void run() {
    Response response = new Response();
    Object result = null;
    try {
      Request request = message.getContent();
      // 拿到要调用的服务
      String serviceName = request.getServiceName();
      // 拿到服务的单例
      Object service = BeanManager.getBean(serviceName);
      // 拿到要调用的方法
      Method method = service.getClass().getMethod(request.getMethodName(), request.getArgTypes());
      // 执行方法
      result = method.invoke(service, request.getArgs());
    } catch (Exception e) {
      e.printStackTrace();
    }
    response.setResult(result);
    ctx.writeAndFlush(new Message<Response>().setHeader(message.getHeader()).setContent(response));
  }
}
```

### 客户端



```java
public class RpcClient implements Closeable {

  protected Bootstrap clientBootstrap;
  protected EventLoopGroup eventLoopGroup;
  private final String host;
  private final int port;

  public RpcClient(String host, int port) {
    this.host = host;
    this.port = port;
    clientBootstrap = new Bootstrap();
    eventLoopGroup = new NioEventLoopGroup();
    clientBootstrap
        .group(eventLoopGroup)
        .option(ChannelOption.TCP_NODELAY, true)
        .option(ChannelOption.SO_KEEPALIVE, true)
        .channel(NioSocketChannel.class)
        .handler(
            new ChannelInitializer<SocketChannel>() {
              @Override
              protected void initChannel(SocketChannel socketChannel) throws Exception {
                socketChannel.pipeline().addLast(new Splitter(Integer.MAX_VALUE, 12, 4));
                socketChannel.pipeline().addLast(new RequestRpcEncoder());
                socketChannel.pipeline().addLast(new ResponseRpcDecoder());
                socketChannel.pipeline().addLast(new RpcClientHandler());
              }
            });
  }

  public ChannelFuture connect(){
    ChannelFuture connect = clientBootstrap.connect(host, port);
    connect.awaitUninterruptibly();
    return connect;
  }

  public Bootstrap getClientBootstrap() {
    return clientBootstrap;
  }

  public EventLoopGroup getEventLoopGroup() {
    return eventLoopGroup;
  }

  public String getHost() {
    return host;
  }

  public int getPort() {
    return port;
  }

  @Override
  public void close() throws IOException {
    eventLoopGroup.shutdownGracefully();
  }
}
```

和服务端一样，消息数据也是会先通过 `Splitter` 做拆包，然后经过 `ResponseRpcDecoder` 做解码得到响应对象，然后在 `RpcClientHandler` 处理响应信息。

参考 dubbo 框架，使用异步通信，所以这里也自己实现一个简陋的 Future 模式：

```java
public class NettyResponseFuture<T> {

  private final long createTime;
  private final long timeout;
  private final Message<Request> message;
  private final Channel channel;
  private final Promise<T> promise;

  public NettyResponseFuture(long createTime, long timeout,
      Message<Request> message, Channel channel, Promise<T> promise) {
    this.createTime = createTime;
    this.timeout = timeout;
    this.message = message;
    this.channel = channel;
    this.promise = promise;
  }

  public long getCreateTime() {
    return createTime;
  }

  public long getTimeout() {
    return timeout;
  }

  public Message<Request> getMessage() {
    return message;
  }

  public Channel getChannel() {
    return channel;
  }

  public Promise<T> getPromise() {
    return promise;
  }
}

```

然后，将与服务端的连接抽象为 `Connection` 对象：

```java
public class Connection implements Closeable {

  private static final AtomicLong ID_GENERATOR = new AtomicLong(0);
  public final static Map<Long, NettyResponseFuture<Response>> IN_FLIGHT_REQUEST_MAP
      = new ConcurrentHashMap<>();
  private ChannelFuture channelFuture;
  private AtomicBoolean isConnected = new AtomicBoolean();

  public Connection() {
    this.isConnected.set(false);
    this.channelFuture = null;
  }

  public Connection(ChannelFuture channelFuture,
      AtomicBoolean isConnected) {
    this.channelFuture = channelFuture;
    this.isConnected = isConnected;
  }

  public NettyResponseFuture<Response> request(Message<Request> message, long timeout) {
    long msgId = ID_GENERATOR.getAndIncrement();
    message.getHeader().setMessageId(msgId);
    NettyResponseFuture<Response> nettyResponseFuture = new NettyResponseFuture<>(
        System.currentTimeMillis(),
        timeout,
        message,
        channelFuture.channel(),
        new DefaultPromise<>(new DefaultEventLoop()));
    IN_FLIGHT_REQUEST_MAP.put(msgId, nettyResponseFuture);
    channelFuture.channel().writeAndFlush(message);
    return nettyResponseFuture;
  }

  @Override
  public void close() throws IOException {
    channelFuture.channel().close();
  }
}
```

内部维护一个原子操作的 Long 类型来生成消息 ID，这个消息 ID 会写到消息头中，服务段处理后，也会将这个消息头带回来，还维护了一个 `IN_FLIGHT_REQUEST_MAP` 用来保存每一个消息 id 对应的 `NettyResponseFuture`，当客户端接收到响应后，就可以通过消息 ID 拿到对应得 `NettyResponseFuture` 就可以将响应信息正确返回给调用方，要是不理解这段，可以去了解一下 Reactor 线程模型。

然后，看看拿到响应信息后如何处理？

```java
public class RpcClientHandler extends SimpleChannelInboundHandler<Message<Response>> {

  @Override
  protected void channelRead0(ChannelHandlerContext channelHandlerContext,
      Message<Response> responseMessage) throws Exception {
    NettyResponseFuture<Response> responseFuture = Connection.IN_FLIGHT_REQUEST_MAP
        .remove(responseMessage.getHeader().getMessageId());
    Response response = responseMessage.getContent();
    responseFuture.getPromise().setSuccess(response);
  }
}
```

其实也比较简单，就和前面讲的一样，就是通过消息 ID 拿到对应的 `NettyResponseFuture`，然后调用 `Promise.setSuccess(response)` 表示这次调用成功。

## 代理服务调用逻辑

当生产者提供了一个服务，消费端想要达到调用本进程的代码逻辑一样调用生产者的 API，所以就需要对接口进行代理，虽然常用的动态代理有 cglib 和 JDK 动态代理，但是这里就直接使用 JDK 动态代理了，因为毕竟这种远程调用，通信双方共享的代码肯定是接口，而不是一个具体的实现类。

```java
public class RpcProxy implements InvocationHandler {

  private String serviceName;
  private Registry<ServerInfo> registry;
  private Map<Method, Header> headerCache = new ConcurrentHashMap<>();

  public RpcProxy(String serviceName,
      Registry<ServerInfo> registry) {
    this.serviceName = serviceName;
    this.registry = registry;
  }

  public static <T> T newInstance(Class<T> clazz,String serviceName, Registry<ServerInfo> registry) {
    return (T) Proxy.newProxyInstance(
        Thread.currentThread().getContextClassLoader(),
        new Class[] {clazz},
        new RpcProxy(serviceName, registry));
  }

  @Override
  public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
    List<ServiceInstance<ServerInfo>> serviceInstances = registry.queryInstance(serviceName);
    ServiceInstance<ServerInfo> serviceInstance = serviceInstances
        .get(ThreadLocalRandom.current().nextInt(serviceInstances.size()));
    String methodName = method.getName();
    Header header = headerCache.computeIfAbsent(
        method, h -> new Header().setMagic(Constances.MAGIC).setVersion(Constances.VERSION));
    Message<Request> message =
        new Message<Request>()
            .setHeader(header)
            .setContent(
                new Request(serviceName, methodName,args));
    return remoteCall(serviceInstance.getPayload(), message);
  }

  private Object remoteCall(ServerInfo serverInfo, Message<Request> message)
      throws ExecutionException, InterruptedException, TimeoutException {
    if (Objects.isNull(serverInfo)) {
      throw new RuntimeException("get available server failed");
    }
    RpcClient rpcClient = new RpcClient(serverInfo.getHost(), serverInfo.getPort());
    ChannelFuture channelFuture = rpcClient.connect().awaitUninterruptibly();
    Connection connection = new Connection(channelFuture, new AtomicBoolean(true));
    NettyResponseFuture<Response> responseFuture = connection.request(message, 60);
    return responseFuture.getPromise().get(60, TimeUnit.SECONDS).getResult();
  }
}
```

可以看见，在代理逻辑中，通过注册中心拿到了 `serviceName` 对应的所有的服务实例的信息，然后随机选一个实例连接得到一个 `Connection`，最终通过 `Connection.request()` 发起请求，并设置等待调用返回的阻塞时间为 60 秒。

# 测试

定义一个 HelloService 作为远程调用的服务:

```java
public interface HelloService {

  String sayHello(String message);

  HelloResponse hello(HelloRequest request);
}

public class HelloRequest implements Serializable {

  private String message;

  public String getMessage() {
    return message;
  }

  public HelloRequest setMessage(String message) {
    this.message = message;
    return this;
  }
}

public class HelloResponse implements Serializable {

  private String message;

  public String getMessage() {
    return message;
  }

  public HelloResponse setMessage(String message) {
    this.message = message;
    return this;
  }
}
```

这个接口需要在服务端有一个实现：

```java
public class HelloServiceImpl implements HelloService {

  private static final Logger logger = LoggerFactory.getLogger(HelloServiceImpl.class);

  @Override
  public String sayHello(String message) {
    logger.info(message);
    return "Hello " + message;
  }

  @Override
  public HelloResponse hello(HelloRequest request) {
    logger.info("hello request: {}",request.getMessage());
    return new HelloResponse().setMessage("Hello " + request.getMessage());
  }
}
```

先用 docker 启动一个 zookeeper 作为注册中心：

```bash
$ docker run --name zk -d -p 2181:2181 zookeeper
```

现在初始化一个服务提供者的实例：

```java
public class Provider {

  public static void main(String[] args) throws Exception {
    BeanManager.registry("helloService", new HelloServiceImpl());
    ZookeeperRegistry<ServerInfo> discovery = new ZookeeperRegistry<>();
    discovery.start();
    ServerInfo serverInfo = new ServerInfo("127.0.0.1", 20880);
    discovery.registerService(
        ServiceInstance.<ServerInfo>builder()
            .name("helloService")
            .payload(serverInfo)
            .build());
    RpcServer rpcServer = new RpcServer(20880);
    rpcServer.start();
  }
}
```

首先实例化了一个 `HelloServiceImpl` 注册到 `BeanManager` 中，然后启动注册中心，将 `helloService` 注册到 zookeeper 中，其实就是在 zookeeper 中新建了节点，最后，服务端监听 `20880` 端口并启动，等待请求的到来。

现在初始化一个消费者服务，通过远程调用 `HelloService`：

```java
public class Consumer {

  private static final Logger logger = LoggerFactory.getLogger(Consumer.class);

  public static void main(String[] args) throws Exception {
    ZookeeperRegistry<ServerInfo> discovery = new ZookeeperRegistry<>();
    discovery.start();
    HelloService helloService = RpcProxy.newInstance(HelloService.class, "helloService", discovery);
    String res = helloService.sayHello("world");
    logger.info(res);
    HelloResponse response = helloService.hello(new HelloRequest().setMessage("hanelalo"));
    logger.info("hello response: {}", response.getMessage());
  }
}
```

同样也会初始化一个注册中心的实例，通过 `RpcProxy` 得到一个 `HelloService`  的代理类，内部的代理逻辑会调用远程服务。

到这里，基本也就结束了。

其实，整个框架还有很多应该做的事没做，比如：

* 心跳信息
* 本地订阅的缓存的刷新
* 注册中心对 zookeeper 的 curator 客户端依赖

不过，写到这里，也终于对 rpc 以及 dubbo 有一个初步的认识。