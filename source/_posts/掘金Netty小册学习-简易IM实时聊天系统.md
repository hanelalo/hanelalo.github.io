---
title: 掘金 Netty 小册学习-简易 IM 实时聊天系统
date: 2021-03-20 22:47:11
tags: Netty
categories: Java
cover: http://image.hanelalo.cn/images/202111061337386.png
---

> 本文是在掘金学习[《Netty 入门与实战：仿写微信 IM 即时通讯系统》](https://juejin.cn/book/6844733738119593991/section)时做的笔记，这个小册作为 Netty 入门资料还是不错的。

# 什么是 Netty ？

[Netty](https://netty.io/wiki/user-guide-for-4.x.html) 是一个开源的 Java 高性能网络框架，网络也是一种 IO，IO 分为 BIO 和 NIO 和 AIO 三种，这三种 IO 的区别参见[8分钟深入浅出搞懂BIO、NIO、AIO](https://zhuanlan.zhihu.com/p/83597838)，这些玩意儿其实平时都看不见能让人想起来他们的代码，但是又时常都用到了，比如 Spring 的网络通信底层就是使用 Netty 实现，Netty 目前支持 NIO 和 BIO 两种模式，没深究为什么要支持 NIO 而不是 AIO，记得似乎是 Netty 后来新版本主要是为了支持 AIO，但是发现相对于 NIO 的实现版本没多大性能提升，而且 AIO 还是 JDK 1.7 才有的，所以官方就不推荐使用了。Netty 的开发人员还是很强的，据说曾经给 Open JDK 提了个 bug 没人理，后来 Netty 只能自己内部解决。 

Netty 的高扩展性，让它成为了 Java 里面很多自定义协议的实现工具，本文要讲的 IM 实时聊天系统就会实现一个简单的网络协议。

# 前置知识

> 也是在学习过程中看评论的一点感悟。

* 不管是什么协议，真正通信的时候，都是以二进制传输的。
* [lombok](https://projectlombok.org/)，一个一般情况下不会出问题的，让代码看起来更简洁的工具框架。

# Netty 简单使用

## 启动一个服务器

```java
public class NettyServer {
  public static void main(String[] args) {

    ServerBootstrap serverBootstrap = new ServerBootstrap();
    /** handle connection event */
    NioEventLoopGroup boss = new NioEventLoopGroup();
    /** handle io event, business operation */
    NioEventLoopGroup worker = new NioEventLoopGroup();
    serverBootstrap
        .group(boss, worker)
        // switch io model, general Nio, you can use OIO, but why use netty ?
        .channel(NioServerSocketChannel.class)
        .childHandler(
            new ChannelInitializer<NioSocketChannel>() {
              @Override
              protected void initChannel(NioSocketChannel ch) {
                System.out.println("netty ...");
              }
            });
    ChannelFuture bind = serverBootstrap.bind(8000);
    bind.addListener(
        future -> {
          if (future.isSuccess()) {
            System.out.println("bind port sucess");
          } else {
            System.out.println("bind port failed");
          }
        });
  }
}

```

Netty 将处理网络连接和做数据读写分成了两个线程池来实现，`boss` 用来处理网络连接事件，`worker` 用来做业务处理，`channel()` 方法用来指定创建的 Channle 类型，如果不指定，则自动根据操作系统选择， Windows 一般都会是 `NioSocketChannel`，`childHandler()` 方法用来指定接收到请求的回调处理逻辑，`bind()` 用来绑定端口。

## 启动一个客户端

```java
public class NettyClient {

  public static void main(String[] args) {
    Bootstrap bootstrap = new Bootstrap();
    NioEventLoopGroup group = new NioEventLoopGroup();
    bootstrap
        .group(group)
        .channel(NioSocketChannel.class)
        .handler(
            new ChannelInitializer<NioSocketChannel>() {
              @Override
              protected void initChannel(NioSocketChannel ch) throws Exception {
				// 业务处理
              }
            })
        .connect("127.0.0.1", 8000);
  }
```

注意这里使用的不再是 `SeverBootstrap`，而是 `Bootstrap`，因为作为客户端来说，不像服务端一样需要处理多个连接，`group()`  和服务端类似，只不过可以理解为绑定的线程都是用来做业务处理，`handler()` 和服务端的 `childHandler` 类似，用来绑定业务处理逻辑代码，`connect()` 指定服务端地址和端口，建立连接。

# 自定义协议

## 为什么要自定义协议 ？

因为这里没法直接使用 Http 协议，Netty 属于比较底层的框架，直接强行解析 Http 协议的话，那写 Netty 的人就是我了。。。

## 协议格式

* 魔数

  4 个字节，也就是一个 int 值，二进制数据包最前面几个字节为固定数字，称为魔数，不屑这一个魔数的化，万一绑定的是 80 端口，可能就直接当成 Http 协议解析了，这就像 Java 的 Class 文件里面开头就有一个 `Coffe(没记错的话)` 的魔数，主要是为了和其他协议区分开。

* 协议版本

  1 个字节，还是很大了，最大 128 呢，一个协议要是真的更新这么多个版本，那肯定是个垃圾，当前虽然是一个屁用没有的字段，但是既然要模仿，那就模仿得像一点，得体现出现代自定义协议必备的可扩展性。

* 命令类型

  1 个字节，因为是自定义协议，一般都是针对某些系统之间的特定协议，所以完全可以指定一些命令类型，比如用来标识当前的数据请求时登录还是其他的什么请求。

* 主体数据长度

  4 个字节，也就是一个 int 值，用来标识真正的请求二进制主体数据的大小，也就是主题数据的 byte 数组的长度

* 主体数据

## 协议数据抽象

```java
@Data
public abstract class Packet {

  /** 协议版本 */
  private byte version = 1;
  /** 需要序列化成 json 的原因，虽然这个字段没用，但是还是得显式定义 */
  private String command;

  /**
   * 获取命令
   */
  public abstract byte getCommand();
}
```

## 序列化实现

```java
/**
 * 序列化
 */
public interface Serializer {

  Serializer DEFAULT = new JSONSerializer();

  /**
   * 序列化算法
   * @return byte
   */
  byte getSerializerAlgorithm();

  /**
   * 序列化
   */
  byte[] serialize(Object object);

  /**
   * 反序列化
   */
  <T> T deserialize(Class<T> clazz, byte[] bytes);
}
```

```java
public class JSONSerializer implements Serializer {

  private final ObjectMapper objectMapper;

  public JSONSerializer(){
    objectMapper = new ObjectMapper();
  }

  @Override
  public byte getSerializerAlgorithm() {
    return SerializerAlgorithm.JSON;
  }

  @Override
  public byte[] serialize(Object object) {
    try {
      return objectMapper.writeValueAsString(object).getBytes(StandardCharsets.UTF_8);
    } catch (JsonProcessingException e) {
      e.printStackTrace();
    }
    return new byte[]{};
  }

  @Override
  public <T> T deserialize(Class<T> clazz, byte[] bytes) {
    try {
      return objectMapper.readValue(new String(bytes), clazz);
    } catch (IOException e) {
      e.printStackTrace();
    }
    return null;
  }

}
```

序列化的实现，首先将 Java 对象转成 json 字符串，这里使用的是 jackson，然后才转成了二进制数组。

这样做是因为之前看了 Dubbo 和 Feign 的区别时，知道 Dubbo 是和 Java 这门语言强绑定的，因为直接将对象序列化为二进制，而 Feign 是先序列化为 json 字符串，然后再将 json 字符串序列化为二进制，这两种方法好处坏处都有， Dubbo 性能更高，因为序列化和反序列化都比 Feign 少了一步 json 转化，但是也因此和 Java 这门语言强绑定，也就是通信的两端都必须是 Java 实现，而 Feign 虽然因为转换成 json 导致性能不如 Dubbo，但是也因为是转换成了 json，解开了对语言的绑定，毕竟现在各种语言都有很多 json 工具的。

## 序列化工具类

```java
public class PacketCodeC {

  public static final int MAGIC_NUMBER = 0x12345678;

  public static PacketCodeC INSTANCE = new PacketCodeC();

  private PacketCodeC(){}

  @Deprecated
  public ByteBuf encode(Packet packet){
    ByteBuf byteBuf = ByteBufAllocator.DEFAULT.ioBuffer();
    byte[] bytes = Serializer.DEFAULT.serialize(packet);

    // 魔数，用来忽悠 http
    byteBuf.writeInt(MAGIC_NUMBER);
    // 版本号
    byteBuf.writeByte(packet.getVersion());
    // 序列化算法
    byteBuf.writeByte(Serializer.DEFAULT.getSerializerAlgorithm());
    // 命令类型
    byteBuf.writeByte(packet.getCommand());
    // 请求数据主体长度
    byteBuf.writeInt(bytes.length);
    // 请求主体数据
    byteBuf.writeBytes(bytes);

    return byteBuf;
  }

  public Packet decode(ByteBuf byteBuf){
    // 跳过魔数
    byteBuf.skipBytes(4);
    // 跳过版本号
    byteBuf.skipBytes(1);
    // 序列化算法
    byte algorithm = byteBuf.readByte();
    // 命令类型
    byte command = byteBuf.readByte();
    // 数据长度
    int packageLength = byteBuf.readInt();
    // 请求数据
    byte[] dataBytes = new byte[packageLength];
    byteBuf.readBytes(dataBytes);
    // 根据命令类型获取请求类型
    Class<? extends Packet> clazzType = getClazzTypeBy(command);
    return Serializer.DEFAULT.deserialize(clazzType, dataBytes);
  }

  private Class<? extends Packet> getClazzTypeBy(byte command) {
    return CommandUtil.fromCommand(command);
  }

  public void encode(ByteBuf byteBuf, Packet packet) {
    byte[] bytes = Serializer.DEFAULT.serialize(packet);
    // 魔数，用来忽悠 http
    byteBuf.writeInt(MAGIC_NUMBER);
    // 版本号
    byteBuf.writeByte(packet.getVersion());
    // 序列化算法
    byteBuf.writeByte(Serializer.DEFAULT.getSerializerAlgorithm());
    // 命令类型
    byteBuf.writeByte(packet.getCommand());
    // 请求数据主体长度
    byteBuf.writeInt(bytes.length);
    // 请求主体数据
    byteBuf.writeBytes(bytes);
  }
}
```

通过上面的编码和解码的实现，可以知道其实这两者就是相反的两个过程。

ByteBuf 可以理解为 Netty 提供的一个直接能够操作一部分内存的每一个字节的工具，具体的参考https://waylau.com/essential-netty-in-action。

# pipeline 和 ChannelHandler

一般情况下，一个服务器程序，不可能只处理一种请求，所以前面定义协议的时候，还专门在协议里加入了 `command` 字段，但是，要如何做到对多种请求的处理和响应？

Netty 提供了 ChannleHandler 来处理各种请求，主要实现了 `ChannelInboundHandlerAdapter` 和 `ChannelOutboundHandlerAdapter` ，前者用来处理接受的数据，后者用来处理要发送的数据。

像协议数据包的编码与解码，是每次请求处理都需要做的，这样的操作，如果在每一个 ChannelHandler 里面直接都写一遍就很烦，所以 Netty 提供了一个 `MessageToMessageCodec` 处理器，也是一个 `ChannelHandler`，只需要实现其 `encode` 和 `decode` 方法就可以实现数据的自动解码和编码。

上面提到的各种 `ChannelHandler` 都是具体的处理逻辑的实现，但是再想想，要如何做到让每次的请求都做解码处理，每次响应的的数据都自动编码处理。

仔细回忆一下在初学 Java Web 时，有学过 Filter 这样一个东西，而且还可以定义很多个 Filter，然后只需要在 `web.xml` 中注册即可，也就是说，对于 Filter 的调用的编排，在 `web.xml` 中定义，而 Netty 也提供了类似的机制，也就是 pipeline。

pipeline 内部使用一个双向链表实现，每个节点就是一个 `ChannleHandler`，每个 `ChannelHandler` 执行完就会掉用下一个节点的 `ChannleHandler`，这里先放上 IM 聊天系统最终版的一点代码方便解释。

```java
    serverBootstrap
        .group(boss, worker)
        .channel(NioServerSocketChannel.class)
        .attr(Attributes.LOGIN, false)
        .childHandler(
            new ChannelInitializer<NioSocketChannel>() {
              @Override
              protected void initChannel(NioSocketChannel ch) {
                ch.pipeline().addLast(new ClientIdleStateHandler(10, 10, 10));
                ch.pipeline().addLast(new Splitter(Integer.MAX_VALUE, 7, 4));
                ch.pipeline().addLast(PacketCodeCHandler.INSTANCE);
                ch.pipeline().addLast(LoginRequestHandler.INSTANCE);
                ch.pipeline().addLast(AuthHandler.INSTANCE);
                ch.pipeline().addLast(new HeartBeatRequestHandler());
                ch.pipeline().addLast(MessageRequestHandler.INSTANCE);
              }
            });
```

上面的代码中，在 `childHandler()` 中注册了很多中 `ChannleHandler`，添加的顺序就是执行的顺序。

# 自动编码、解码实现

```java
/**
 * 继承网络数据的编码和解码
 */
@Sharable
public class PacketCodeCHandler extends MessageToMessageCodec<ByteBuf, Packet> {

  public static PacketCodeCHandler INSTANCE = new PacketCodeCHandler();

  @Override
  protected void encode(ChannelHandlerContext ctx, Packet msg, List<Object> out) throws Exception {
    ByteBuf byteBuf = ctx.channel().alloc().ioBuffer();
    PacketCodeC.INSTANCE.encode(byteBuf, msg);
    out.add(byteBuf);
  }

  @Override
  protected void decode(ChannelHandlerContext ctx, ByteBuf msg, List<Object> out) throws Exception {
    out.add(PacketCodeC.INSTANCE.decode(msg));
  }
}
```

`@Sharable` 代表这个 ChannelHandler 可以多个 Channle 共享一个实例，这种的一般都是无状态的 ChannleHandler，所以这里也就直接对外提供了一个单例。

# 粘包和半包的解决

不管是什么协议，最终都是以二进制的形式传输，当一个 Channle 的数据交互足够频繁的时候，就会出现粘包或者半包现象。

就不代码演示了（测试代码被我删了），简单解释就是如果直接向服务器发送 1000 次 “Hello World”，会发现服务器有时候解析出来的刚好也是 “Hello World”，而有时候可能只有一个 “Hello”，这叫做**半包**，再有时候可能一次解析了 n  个 “Hello World” 出来，这叫做**粘包**。

这是因为每次发送的数据可能小于也可能大于 TCP 套接字缓冲区的大小，导致服务端每次接收到的数据包不一定是完整。

## 那么 Netty 是如何解决粘包和半包问题的 ？

再看看半包和粘包问题，发现主要是因为不知道一个完整的数据包的大小到底是多少，导致无法控制，那如果知道完整的数据包的大小，不就可以解决这个问题了，这个过程称为**拆包**。

所以，Netty 提供了三种解决方案：

* FixedLengthFrameDecoder

  看名字就知道，这个是定长数据的拆包实现。`frameLength` 就是每个完整数据包的长度。

  ```java
      public FixedLengthFrameDecoder(int frameLength) {
          if (frameLength <= 0) {
              throw new IllegalArgumentException(
                      "frameLength must be a positive integer: " + frameLength);
          }
          this.frameLength = frameLength;
      }
  ```

* DelimiterBasedFrameDecoder

  以特定分割符作为完整数据包结束标识的拆包实现，比如以换行符 `\n` 作为数据包结束标识，尽管如此，但是如果主体数据刚好也有这个特殊字符，就直接把数据包拆坏了。`maxFrameLength` 是数据包最长长度，`delimiter` 就是分割符。

  ```java
      public DelimiterBasedFrameDecoder(int maxFrameLength, ByteBuf delimiter) {
          this(maxFrameLength, true, delimiter);
      }
  ```

* LengthFieldBasedFrameDecoder

  针对协议内容中有专门的标识作为数据长度的协议的拆包实现，比如前面定义的协议就可以使用它来拆包。

  * `maxFrameLength` 每个完整数据包最大长度，一般都是 `Integer.MAX_VALUE`
  * `lengthFieldOffset` 数据长度标识便宜量，也就是数据长度标识在协议数据包里面的开始位置，前面的自定义协议中，魔术占了 4 字节，版本占了 1 字节，命令类型占了 1 字节，加起来 6 个字节，所以标识数据长度的标识符的开始位置为 7
  * lengthFieldLength 数据长度标识符的长度，本文实际使用的时候，因为该标识符是一个 int，4 个字节，所以为 4。

  ```java
      public LengthFieldBasedFrameDecoder(
              int maxFrameLength,
              int lengthFieldOffset, int lengthFieldLength) {
          this(maxFrameLength, lengthFieldOffset, lengthFieldLength, 0, 0);
      }
  ```

# 协议拒绝连接

当发现数据包不是自己协议的数据包时，需要断开连接，而判断数据包是否符合要求的依据，就是协议头里面的魔数，所以在拆包的时候就可以做这个检测。

```java
/**
 * 自动拆包
 * 实现 LengthFieldBasedFrameDecoder，支持带数据长度标识的自定义协议的拆包
 */
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
    // 因为这里拿到了 ByteBuf 说不定他就是半包或者粘包的产物，所以需要从 readerIndex 开始读取一个 int 来确定魔数
    if(in.getInt(in.readerIndex()) != PacketCodeC.MAGIC_NUMBER){
      System.out.println("非本协议连接...");
      ctx.channel().close();
      return null;
    }
    return super.decode(ctx, in);
  }
}
```

# 登录

> 这里只是实现一个简单的登录操作，所以就不搞什么用户校验的逻辑了。

## 请求和响应

```java
@Data
@ToString(callSuper = true)
public class LoginRequest extends Packet {

  private String username;
  private String password;

  @Override
  public byte getCommand() {
    return LOGIN_REQUEST;
  }
}

@Data
@ToString(callSuper = true)
public class LoginResponse extends Packet {
  /** 登录是否成功 */
  private boolean success;
  /** 返回提示信息 */
  private String msg;

  @Override
  public byte getCommand() {
    return LOGIN_RESPONSE;
  }
}
```

## 客户端发送登录请求

```java
public class LoginHandler extends ChannelInboundHandlerAdapter {

  @Override
  public void channelActive(ChannelHandlerContext ctx) throws Exception {
    ByteBuf byteBuffer = getByteBuffer();
    ctx.channel().writeAndFlush(byteBuffer);
    super.channelActive(ctx);
  }

  private ByteBuf getByteBuffer() {
    LoginRequest packet = new LoginRequest();
    packet.setUsername("hanelalo");
    packet.setPassword("123456");
    return PacketCodeC.INSTANCE.encode(packet);
  }
```

`channelActive` 是管道激活是的回调方法，基本上就相当于建立连接就直接发送登录请求。

## 服务端处理登录请求

```java
/**
 * 登录请求处理器，实现 SimpleChannelInboundHandler，支持对特定类型的处理
 */
@Sharable
public class LoginRequestHandler extends SimpleChannelInboundHandler<LoginRequest> {

  public static final LoginRequestHandler INSTANCE = new LoginRequestHandler();

  @Override
  protected void channelRead0(ChannelHandlerContext ctx, LoginRequest loginRequest) {
    // 登陆成功，在当前管道中设置登录标识
    ctx.channel().attr(Attributes.LOGIN).set(true);
    ctx.channel().writeAndFlush(handleLoginRequest(ctx,loginRequest));
  }

  private LoginResponse handleLoginRequest(ChannelHandlerContext ctx,
      LoginRequest loginRequest) {
    System.out.println(loginRequest);
    LoginResponse loginResponse = new LoginResponse();
    // 给登录用户随机你分配一个 id，并存到 Session 里面
    String userId = UUID.randomUUID().toString().substring(0, 5);
    SessionBinding.bindSession(ctx.channel(),
        Session.builder().userId(userId).username(loginRequest.getUsername()).build());
    loginResponse.setMsg("login success, your userId: "+userId);
    loginResponse.setSuccess(true);
    return loginResponse;
  }

  @Override
  public void channelInactive(ChannelHandlerContext ctx) throws Exception {
    SessionBinding.unbindSession(ctx.channel());
    super.channelInactive(ctx);
  }
}
```

这里的处理登录请求的 handler 并不是直接继承 `ChannelInboundHandlerAdapter`，而是继承了 `SimpleChannelInboundHandler`，直接指定处理 `LoginRequest`，而反序列化后请求类型的匹配，交给了 `SimpleChannelInboundHandler` 实现。

`channel.attr()`方法可以个当前管道设置一个参数，就像 Java 的线程中还有 ThreadLocal 上下文一下。

另外，为了方便后续用户和用户之间的聊天，还生成了 userId，并模仿了一个 Session 的机制，用来存储当前 channel 中的信息，并和 channel 映射。

```java
    String userId = UUID.randomUUID().toString().substring(0, 5);
    SessionBinding.bindSession(ctx.channel(),
        Session.builder().userId(userId).username(loginRequest.getUsername()).build());
```

同时，在客户端断开连接的时候，将用户 Session 和 channel 的绑定关系也断开。

# 点对点互发消息

## 请求和响应

```java
@Data
@ToString
public class MessageRequest extends Packet {

  private String toUserId;

  private String message;

  @Override
  public byte getCommand() {
    return Command.MESSAGE_REQUEST;
  }
}

@Data
@ToString
public class MessageResponse extends Packet {

  private String message;
  private String fromUserId;

  @Override
  public byte getCommand() {
    return Command.MESSAGE_RESPONSE;
  }
}
```

## 客户端启动发送消息的线程

```java
  public static void main(String[] args) {
    Bootstrap bootstrap = new Bootstrap();
    NioEventLoopGroup group = new NioEventLoopGroup();
    // ... 各种配置
    bootstrap
        .addListener(
            future -> {
              if (future.isSuccess()) {
                Channel channel = ((ChannelFuture) future).channel();
                startConsoleThread(channel);
              }
            });
  }

  private static void startConsoleThread(Channel channel) {
    new MessageThread(channel).start();
  }
```

```java
public class MessageThread extends Thread{

  public MessageThread(Channel channel) {
    super(() -> {
      while (!Thread.interrupted()) {
        if (LoginUtils.isLogin(channel)) {
          System.out.println("目标的 userId:");
          Scanner sc = new Scanner(System.in);
          MessageRequest messageRequest = new MessageRequest();
          String userId = sc.nextLine();
          messageRequest.setToUserId(userId);
          System.out.println("输入消息:");
          String line = sc.nextLine();
          messageRequest.setMessage(line);
          channel.writeAndFlush(messageRequest);
        }
      }
    });
  }
}
```

在客户端建立连接就，新启动一个线程，接受控制台的输入，发送消息到指定 userId。

## 服务端将消息发送到指定用户

```java
/**
 * 消息请求处理器
 */
@Sharable
public class MessageRequestHandler extends SimpleChannelInboundHandler<MessageRequest> {

  public static final MessageRequestHandler INSTANCE = new MessageRequestHandler();

  @Override
  protected void channelRead0(ChannelHandlerContext ctx, MessageRequest msg) throws Exception {
    handleResponse(ctx,msg);
  }

  private void handleResponse(ChannelHandlerContext ctx, MessageRequest msg) {
    String toUserId = msg.getToUserId();
    Channel channel = SessionBinding.getChannel(toUserId);
    MessageResponse response = new MessageResponse();
    response.setMessage(msg.getMessage());
    response.setFromUserId(SessionBinding.getSession(ctx.channel()).getUserId());
    channel.writeAndFlush(response);
  }
}
```

这里就借助了前面实现的 Session 机制，来通过消息的目标 userId 找到 channle，实现消息的点对点发送，其实并不是两个客户端之间直接通信，而是服务端做了一次数据转发而已。

MessageRequest 请求包含消息内容和消息的目标 userId，而服务端处理的时候，发送一个 MessageResponse，MessageResponse 中包含的是消息内容和消息的发送人。

## 客户端处理其他用户发来的消息

```java
public class MessageResponseHandler extends SimpleChannelInboundHandler<MessageResponse> {

  @Override
  protected void channelRead0(ChannelHandlerContext ctx, MessageResponse msg) {
    System.out.println("来自 "+msg.getFromUserId()+": \n"+msg.getMessage());
  }
}
```

至此，基本的点对点实现了。

# 客户端空闲超时，服务端主动断开连接

在实际的环境中，有些客户端可能就活跃那么一阵，然后就进入假死状态，跟服务端保持连接，但是啥也不做，这样其实有点浪费服务器的资源。

所以，还需要做一个心跳检测，当某个客户端空闲超过某个时间的时候，服务端主动断开连接。

```java
/**
 * 空闲超时处理器
 */
public class ClientIdleStateHandler extends IdleStateHandler {

  public ClientIdleStateHandler(
      int readerIdleTimeSeconds, int writerIdleTimeSeconds, int allIdleTimeSeconds) {
    super(readerIdleTimeSeconds, writerIdleTimeSeconds, allIdleTimeSeconds);
  }

  @Override
  protected void channelIdle(ChannelHandlerContext ctx, IdleStateEvent evt) throws Exception {
    System.out.println("空闲超时...");
    ctx.channel().close();
  }
}
```

而 Netty 同样也提供了这样一个扩展实现，叫做 `IdleStateHandler`，新增一个它的实现类，当超时的时候，直接调用 `channle().close()` 主动断开连接。

# 心跳检测

前面实现了超时检测，那如果客户端想要一致保持在线状态，就必须要过一段时间向服务端发送消息，标识自己还或者，而服务端也回应客户端，表示“我现在知道了”。

## 心跳请求和响应

```java
public class HeartBeatRequest extends Packet {

  @Override
  public byte getCommand() {
    return Command.HEART_BEAT_REQUEST;
  }

}

public class HeartBeatResponse extends Packet {

  @Override
  public byte getCommand() {
    return Command.HEART_BEAT_RESPONSE;
  }

}
```

## 客户端定时发送心跳信息

```java
public class HeartBeatHandler extends ChannelInboundHandlerAdapter {

  private static final long HEARTBEAT_INTERVAL = 5;

  @Override
  public void channelActive(ChannelHandlerContext ctx) throws Exception {
    scheduleSendHeadBeat(ctx);
    super.channelActive(ctx);
  }

  private void scheduleSendHeadBeat(ChannelHandlerContext ctx) {
    ctx.executor()
        .schedule(
            () -> {
              if (ctx.channel().isActive()) {
                ctx.channel().writeAndFlush(new HeartBeatRequest());
                scheduleSendHeadBeat(ctx);
              }
            },
            HEARTBEAT_INTERVAL,
            TimeUnit.SECONDS);
  }
}
```

当和服务端的连接开始之后就调用`ChannelHandlerContext.executor().schedule()` 方法每 5 秒钟发送一次心跳请求。

## 服务端处理心跳信息

```java
public class HeartBeatRequestHandler extends SimpleChannelInboundHandler<HeartBeatRequest> {

  @Override
  protected void channelRead0(ChannelHandlerContext ctx, HeartBeatRequest msg) {
    System.out.println(msg);
    ctx.writeAndFlush(new HeartBeatResponse());
  }
}
```

其实心跳请求的内容在这里不重要，重要的是，服务端和客户端有交互，才能保证不会断开连接。



> 文章略显仓促，具体代码见 https://github.com/hanelalo/netty-im