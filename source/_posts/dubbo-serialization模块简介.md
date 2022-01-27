---
title: dubbo-serialization模块简介
date: 2021-07-05 21:56:31
tags: Dubbo
categories: Dubbo
cover: https://hanelalo.github.io/images/202111061322860.png
---

dubbo 中专门分了一个 dubbo-serialization 模块，用来承载序列化的工作。

## 常见的序列化算法

* FastJson

  看名字就知道是将对象序列化成 json 的算法，是 Alibaba 的产物，虽然速度比 Jackson 快，但是近几年出的 bug 也比较多。

* Apache Avro

  一种语言无关的序列化算法，依赖 schema 实现序列化的规则，在 Kafka、Hadoop 以及 Dubbo 中都可以使用这种序列化算法。

* fst

  全程 fast-serialization，一款高性能的 Java 序列化框架，速度比 JDK 原生的序列化算法快，序列化的体积也比 JDK 原生的小。

* Kryo

  Kryo 是一款高效得 Java 序列化框架，无论是数据库存储还是网络数据传输都可以使用 Kryo 来序列化 Java 对象。

* Hessian

  一种支持跨语言的、动态类型的序列化协议。和 Avro 一样都是语言无关的序列化算法，但是又不像 Avro 那样需要依赖外部的 schema 文件来进行序列化和反序列化。Dubbo 默认的序列化方式是 Hessian，但是并不是直接使用了 Hessian，而是基于 Hessian 进行了二次开发的 hessian-lite，但同时也提供了原生的 Hessian 的实现。

* Protobuf

  是由 Google 开发的一款灵活、高效、自动化、用于对结构化数据进行序列化的协议。同时它也是一款语言无关的协议。gRPC 底层使用的就是 Protobuf。

## 核心类

核心接口是 `Serialization`：

```java
@SPI("hessian2")
public interface Serialization {

    byte getContentTypeId();
	/**
	 * 每种序列化算法都有自己的 ContentType，这里就是用来获取序列化算法各自的 ContentType
	 */
    String getContentType();
    
    /**
     * 创建一个 ObjectOutput 对象，它负责实现序列化的逻辑，既将 Java 对象序列化成为二进制数据。
     */
    @Adaptive
    ObjectOutput serialize(URL url, OutputStream output) throws IOException;
	
    /**
     * 创建一个 ObjectInput 对象，负责实现反序列化的逻辑，既将二进制数据反序列化成为 Java 对象。
     */
    @Adaptive
    ObjectInput deserialize(URL url, InputStream input) throws IOException;
}
```

Serialization 接口使用了 @SPI 注解修饰，表示是一个扩展接口，并且默认使用 hessian2 序列化协议的扩展实现，下面以 hessian2 的实现为例，需要注意的是 serialization 有两个 hessian 相关的子模块，一个是 dubbo-serialization-hessian2，基于 alibaba 的 hessian2-lite 实现，一个是 dubbo-serialization-native-hessian，基于原生的 Hessian 实现。

```java
public class Hessian2Serialization implements Serialization {

    @Override
    public byte getContentTypeId() {
        return HESSIAN2_SERIALIZATION_ID;
    }

    @Override
    public String getContentType() {
        return "x-application/hessian2";// hessian2 序列化协议的 ContentType
    }

    @Override
    public ObjectOutput serialize(URL url, OutputStream out) throws IOException {
        return new Hessian2ObjectOutput(out);// 返回一个 Hessian2ObjectOutput 对象
    }

    @Override
    public ObjectInput deserialize(URL url, InputStream is) throws IOException {
        return new Hessian2ObjectInput(is);// 返回一个 Hessian2ObjectInput 对象
    }
}
```

### 序列化

在前面讲过，序列化的逻辑是在 ObjectOutput 种实现，hessian2 的实现是返回了一个 Hessian2ObjectOutput 对象。

首先看看 ObjectOutput 的代码:

```java
public interface ObjectOutput extends DataOutput {

    /**
     * 写对象
     */
    void writeObject(Object obj) throws IOException;

    /**
     * 这个方法是为了 Dubbo 的 RPC 协议中的一些自定义的实现，旧版的协议实现会尝试写入 Map、Throwable、Null 等值，并不满足所有序列化协议的限制。
     */
    default void writeThrowable(Object obj) throws IOException {
        writeObject(obj);
    }

    /**
     * 写事件，这个方法，default 修饰，默认直接调用 writeObject()，只有两个自定义的实现，主要是用来做心跳检测的。
     */
    default void writeEvent(Object data) throws IOException {
        writeObject(data);
    }

    /**
     * 写附件，似乎是写文件用的。
     */
    default void writeAttachments(Map<String, Object> attachments) throws IOException {
        writeObject(attachments);
    }
}
```

主要就只有四个方法，但是它还有一个父接口 DataOutput:

```java
import java.io.IOException;

/**
 * Basic data type output interface.
 */
public interface DataOutput {

    void writeBool(boolean v) throws IOException;

    void writeByte(byte v) throws IOException;

    void writeShort(short v) throws IOException;

    void writeInt(int v) throws IOException;

    void writeLong(long v) throws IOException;

    void writeFloat(float v) throws IOException;

    void writeDouble(double v) throws IOException;

    void writeUTF(String v) throws IOException;

    void writeBytes(byte[] v) throws IOException;

    void writeBytes(byte[] v, int off, int len) throws IOException;

    void flushBuffer() throws IOException;
}
```

从方法的名称上就能看出来其用途。

然后看看 Hessian2 的实现：

```java
public class Hessian2ObjectOutput implements ObjectOutput, Cleanable {

    private static ThreadLocal<Hessian2Output> OUTPUT_TL = ThreadLocal.withInitial(() -> {
        Hessian2Output h2o = new Hessian2Output(null);
        h2o.setSerializerFactory(Hessian2FactoryInitializer.getInstance().getSerializerFactory());
        h2o.setCloseStreamOnClose(true);
        return h2o;
    });

    private final Hessian2Output mH2o;

    public Hessian2ObjectOutput(OutputStream os) {
        mH2o = OUTPUT_TL.get();
        mH2o.init(os);
    }
    
    @Override
    public void writeObject(Object obj) throws IOException {
        mH2o.writeObject(obj);
    }
}
```

上面的代码只贴了一个重写的方法，但也足以明白，Hessian2 的实现其实是依赖一个 Hessian2Output 对象实现的，而从 Hessian2ObjectOutput 的构造方法的逻辑也可以看出，这个 Hessian2Output 对象是和线程绑定的。

### 反序列化

`Hessian2Serialization.deserialize()` 方法返回了一个 ObjectInput 的 Hessian2ObjectInput 子对象。

同样还是先看看 ObjectInput 的结构：

```java
public interface ObjectInput extends DataInput {

    /**
     * 从二进制数据读取一个 Object 对象，已过时。
     */
    @Deprecated
    Object readObject() throws IOException, ClassNotFoundException;

    /**
     * 从二进制数据读取一个指定类型的对象
     */
    <T> T readObject(Class<T> cls) throws IOException, ClassNotFoundException;

    /**
     * 从二进制数据读取一个指定类型的对象
     */
    <T> T readObject(Class<T> cls, Type type) throws IOException, ClassNotFoundException;


    /**
     * 和 ObjectOutput.writeThrowable() 一样，是为了解决 Dubbo RPC 协议中写 Map、Throwable、Null
     */
    default Throwable readThrowable() throws IOException, ClassNotFoundException {
        Object obj = readObject();
        if (!(obj instanceof Throwable)) {
            throw new IOException("Response data error, expect Throwable, but get " + obj);
        }
        return (Throwable) obj;
    }

    default Object readEvent() throws IOException, ClassNotFoundException {
        return readObject();
    }

    default Map<String, Object> readAttachments() throws IOException, ClassNotFoundException {
        return readObject(Map.class);
    }
}
```

以及 ObjectInput 的父类 DataInput：

```java
public interface DataInput {

    boolean readBool() throws IOException;

    byte readByte() throws IOException;

    short readShort() throws IOException;

    int readInt() throws IOException;

    long readLong() throws IOException;

    float readFloat() throws IOException;

    double readDouble() throws IOException;

    String readUTF() throws IOException;

    byte[] readBytes() throws IOException;
}
```

最后就是 Hessian2ObjectInput 的反序列化逻辑：

```java
public class Hessian2ObjectInput implements ObjectInput, Cleanable {

    private static ThreadLocal<Hessian2Input> INPUT_TL = ThreadLocal.withInitial(() -> {
        Hessian2Input h2i = new Hessian2Input(null);
        h2i.setSerializerFactory(Hessian2FactoryInitializer.getInstance().getSerializerFactory());
        h2i.setCloseStreamOnClose(true);
        return h2i;
    });

    private final Hessian2Input mH2i;

    public Hessian2ObjectInput(InputStream is) {
        mH2i = INPUT_TL.get();
        mH2i.init(is);
    }
}
```

和 Hessian2ObjectOutput 类似，Hessian2ObjectInput 是依赖一个 Hessian2Input 对象实现的反序列化，并且这个对象也是和 ThreadLocal 相关联的，也就是和线程绑定的。

## 总结

* dubbo-serialization 模块，dubbo-serialization-api 子模块提供了同一个序列化和反序列化的 API。

* Serialization 是序列化的核心接口，默认使用 hessian2 的扩展实现，其中 serialize() 方法返回一个 ObjectOutput 对象，deserialize() 方法返回一个 ObjectInput 对象。
* ObjectOutput 本身是一个接口，是序列化逻辑的抽象。
* ObjectInput 本身是一个接口，是反序列化逻辑的抽象。
