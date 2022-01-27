---
title: Redis 分布式锁
date: 2021-04-11 13:54:36
tags: 
	- Java
	- Redis
categories: Redis
cover: https://hanelalo.github.io/images/202111061352025.png
---

在分布式应用场景下，总是会涉及到多个应用并发操作同一个业务数据得问题，在这种情况下，就会采用分布式锁来限制并发操作。

目前业界的分布式锁实现方式主要有 Zookeeper 实现和 Redis 实现，本文主要介绍 Redis 实现的分布式锁。

# 要解决的问题？

* 加锁

  简单点直接使用 set 指令。

  ```bash
  set key value
  ```

  如果在锁已经被持有的时候，有其他线程获取锁，是不能成功的，所以考虑使用 `setnx` 指令，这个指令只有在 key 不存在时才会设置成功，key 不存在，那就是未加锁。

  ```bash
  setnx key value
  ```

  其实上面的解决方案太过片面，是有问题的，继续往下看吧。

* 解锁

  从前面加锁的操作来看，其实解锁直接将 key 删除即可。

  ```bash
  del key
  ```

* 锁超时

  如果锁超时，不续锁的话，肯定是要让锁释放的，要做到这种效果，可以考虑 `expire` 指令，用来设置 key 的过期时间。

  ```bash
  expire key 10 # key 10 秒后过期
  ```

  `set` 指令是支持直接一步到位的。

  ```bash
  set key value ex 10 # 设置 key 和 value 键值对，有效期为 10 秒
  ```

  但是 `setnx` 是不支持的，只能单独再执行一次 `expire` 指令。

  ```bash
  setnx key value
  expire key 10
  ```

  既然 `setnx` 指令不能一步到位，那如果说在 `setnx` 后 Redis 宕机了，那么这个锁就会一直存在，因为没设置过期时间。

  其实 set 指令也可以通过参数控制，做到 setnx 的效果。

  ```bash
  set key value ex 10 nx # 设置一个 key-value 键值对，有效期为 10 秒，当 key 不存在时做这个操作
  ```

  在锁超时场景下，上述解决方案依然还有问题。

  试想这样一个场景：

  A 线程持有 orderId 的锁，有效期 10 秒，但是 10 秒后，A 线程的业务操作还没有做完，这个时候锁超时，被释放，紧接着 B 线程请求锁并成功持有了锁，然后 A 线程终于操作完成，大家都知道，写代码的时候，有加锁，那必定会在结尾调用解锁，A 最终调用了解锁，将 Redis 中的锁删除。

  上面的问题在于， A 线程删除的锁，并不是自己所持有的锁。要如何保证多线程环境下，不会删除其他线程的锁呢？

  Redis 官网给除了很多种语言平台基于 Redis 的分布式锁解决方案，其中 Java 的 Redisson 框架上榜。

  

  

# Redisson 实现分布式锁

[Redisson](https://redisson.org/) 是一个封装了基于 Redis 的分布式操作的 Java 框架。

先尝试使用一下 Redisson 的锁：

```java
    Config config = new Config();
    config.setTransportMode(TransportMode.NIO);
    config.useSingleServer().setAddress("redis://127.0.0.1:6379");
    RedissonClient redissonClient = Redisson.create(config);
    RLock myLock = redissonClient.getLock("myLock");
    // 加锁，有效期 20 秒
    myLock.lock(20, TimeUnit.SECONDS);
```

启动程序后，查看一下 redis 中的数据:

```bash
127.0.0.1:6379> type myLock
hash
127.0.0.1:6379> ttl myLock
(integer) 13
127.0.0.1:6379> hgetall myLock
1) "cc405566-7cfb-40ea-a1e3-7ddbe998e348:1"
2) "1"
127.0.0.1:6379>
```

可以看见， myLock 这个锁在 Redis 里面其实是以 hash 的数据结构实现的，hash 内部的 key 和 value 是什么暂且先不讨论。

通过 `ttl` 指令也可以看见此时 myLock 的有效期还剩下 13 秒。

接下来再通过一个测试来看看前面提到了多线程的问题在 Redisson 中是否得到了解决。

```java
  public static void main(String[] args) {
    Config config = new Config();
    config.setTransportMode(TransportMode.NIO);
    config.useSingleServer().setAddress("redis://127.0.0.1:6379");
    RedissonClient redissonClient = Redisson.create(config);
    RLock myLock = redissonClient.getLock("myLock");
    CountDownLatch countDownLatch = new CountDownLatch(1);
    Thread first =
        new Thread(
            () -> {
              // 加锁，有效期 10 秒
              myLock.lock(10, TimeUnit.SECONDS);
              System.out.println(new Date() + "-" + Thread.currentThread().getName() + "获取锁成功");
              System.out.println(new Date());
              countDownLatch.countDown();
              try {
                Thread.sleep(15000);
                System.out.println(
                    new Date() + "-" + Thread.currentThread() + " 锁持有情况:" + myLock.isHeldByCurrentThread());
                System.out.println(new Date() + "-" +Thread.currentThread().getName()+" 释放锁");
                myLock.unlock();
              } catch (InterruptedException e) {
                e.printStackTrace();
              }
            },
            "thread-first");
    first.start();
    Thread second =
        new Thread(
            () -> {
              try {
                countDownLatch.await();
              } catch (InterruptedException e) {
                e.printStackTrace();
              }
              // 加锁，有效期 10 秒
              myLock.lock(10, TimeUnit.SECONDS);
              System.out.println(new Date() + "-" + Thread.currentThread().getName() + "获取锁成功");
              try {
                Thread.sleep(7000);
                System.out.println(
                    new Date() + "-" + Thread.currentThread() + " 锁持有情况:" + myLock.isHeldByCurrentThread());
              } catch (InterruptedException e) {
                e.printStackTrace();
              }
            },
            "thread-second");
    second.start();
  }
```

容我稍微从时间线的角度解释一下这段代码：

1. 主线程建立 Redis 连接，先创建一个 myLock 的锁引用，这个时候其实 Redis 中还没有 myLock 这个 hash。
2. 线程 first-thread 和 second-thread 启动。
3. 通过 CountDownLatch 使得 first-thread 先获得锁后 second-thread 才开始获取锁，以产生可控的锁竞争情景，两个线程获取锁时设置的有效时间都是 10 秒。
4. first-thread 拿到锁之后，线程休眠 15 秒，静等锁自动超时。
5. 10 秒后，线程 first-thread 锁超时自动释放，second-thread 里面持有了锁，并开始休眠 7 秒。
6. first-thread 的 15 秒休眠结束，检查当前的锁状态，持有锁的是否为本线程，尝试释放锁，注意在此之前其实已经自动释放了。
7. 又过了大概 2 秒的时间，second-thread 休眠 7 秒结束，查看当前锁状态，是否为本线程持有锁。

运行的结果如下：

```
Sun Apr 11 17:44:08 CST 2021-thread-first获取锁成功
Sun Apr 11 17:44:08 CST 2021
Sun Apr 11 17:44:18 CST 2021-thread-second获取锁成功
Sun Apr 11 17:44:23 CST 2021-Thread[thread-first,5,main] 锁持有情况:false
Sun Apr 11 17:44:23 CST 2021-thread-first 释放锁
Exception in thread "thread-first" java.lang.IllegalMonitorStateException: attempt to unlock lock, not locked by current thread by node id: c1fa6349-d087-49d1-8db4-ba48ed427de1 thread-id: 47
	at org.redisson.RedissonBaseLock.lambda$unlockAsync$1(RedissonBaseLock.java:312)
	at org.redisson.misc.RedissonPromise.lambda$onComplete$0(RedissonPromise.java:187)
Sun Apr 11 17:44:25 CST 2021-Thread[thread-second,5,main] 锁持有情况:true
```

可以看见，first-thread 休眠结束后，发现当前的锁并非自己持有的，尝试释放锁直接报错。

first-thread 线程在 08 秒获取到锁，10 秒后超时自动释放，second-thread 刚好在 18 秒拿到锁，最终 second-thread 在休眠 7 秒后，此时 first-thread 已经尝试释放过一次锁，然而此时 second-thread 的检查结果为当前持有锁的线程为 second-thread。

所以， Redisson 的锁实现是没有前面讲到的 A 线程释放掉 B 线程的锁的问题。

那么，是如何做到的呢？

通过上面的报错信息先猜想一下，是不是在 Redis 里面还存了当前持有锁的线程的"身份信息"？以此来判断释放锁的线程和持有锁的线程是否为同一个线程。

# Redisson 分布式锁源码浅析

在看源码之前，先复习一下 Java 本身提供的 Lock 接口：

```java
public interface Lock {
    // 加锁，不支持中断
	void lock();
    // 加锁，支持中断
	void lockInterruptibly() throws InterruptedException;
	// 尝试加锁，不支持中断
	boolean tryLock();
    // 支持超时机制，尝试获取锁，支持中断
	boolean tryLock(long time, TimeUnit unit) throws InterruptedException;
	// 解锁
	void unlock();
	Condition newCondition();
}
```

其中 `lock()` 是会阻塞线程的。

而 Java 中经典的锁有三种：

* 普通的互斥锁

  一个线程锁之后，其他线程再想要持有锁都必须等锁被释放，哪怕后来请求加锁的线程是持有锁的线程都不行。

* 重入锁

  在前面一种锁的基础上支持同一个线程多次加锁。

* 读写锁

  内部维护两个锁，一把读锁和一把写锁，写锁被持有时，其他所有线程请求读锁和写锁都被阻塞，读锁被持有时，其他线程获取写锁会阻塞，获取读锁会成功。

然后，再看看 Redisson 中的锁实现。

## RedissonLock

这是调用 `RedissonClient.getLock()` 方法返回的锁对象：

```java
	protected final CommandAsyncExecutor commandExecutor;
	public RLock getLock(String name) {
		return new RedissonLock(commandExecutor, name);
	}
```

紧接着看看 RedissonLock 的 lock 方法（艹了，源码一行注释都没有）：

```java
    private void lock(long leaseTime, TimeUnit unit, boolean interruptibly) throws InterruptedException {
        .// 当前线程 id
        long threadId = Thread.currentThread().getId();
        // 尝试获取锁，这里的 ttl 后面解释
        Long ttl = tryAcquire(-1, leaseTime, unit, threadId);
        // lock acquired
        if (ttl == null) {
            return;
        }
	   // 尝试获取锁失败，后续操作
    }
```

先不看其他的，就看看 `tryAcquire()` 方法的实现，最后会追踪到如下代码：

```java
    <T> RFuture<T> tryLockInnerAsync(long waitTime, long leaseTime, TimeUnit unit, long threadId, RedisStrictCommand<T> command) {
        return evalWriteAsync(getName(), LongCodec.INSTANCE, command,
                "if (redis.call('exists', KEYS[1]) == 0) then " +
                        "redis.call('hincrby', KEYS[1], ARGV[2], 1); " +
                        "redis.call('pexpire', KEYS[1], ARGV[1]); " +
                        "return nil; " +
                        "end; " +
                        "if (redis.call('hexists', KEYS[1], ARGV[2]) == 1) then " +
                        "redis.call('hincrby', KEYS[1], ARGV[2], 1); " +
                        "redis.call('pexpire', KEYS[1], ARGV[1]); " +
                        "return nil; " +
                        "end; " +
                        "return redis.call('pttl', KEYS[1]);",
                Collections.singletonList(getName()), unit.toMillis(leaseTime), getLockName(threadId));
    }
```

那一大串拼接的字符串，其实是一段 lua 脚本，Redis 执行 lua 脚本是能保证原子性的，同时当 Redis 在执行一段 lua 脚本时，是不会有其他的 lua 脚本或者命令同时执行的，这就为同一时间真正能加锁成功的只有一个线程提供了保证。

这段 lua 脚本抽出来看看：

```lua
-- RLock 在 redis 种采用 hash 数据结构
-- KEYS[1] 就是 hash 的名字，项目的例子中 KEYS[1]=myLock
-- hash 的 key 是线程 id, value 是数字
-- 先判断 myLock 这个 redis 是否存在，如果不存在，返回 0
if (redis.call('exists', KEYS[1]) == 0) then
    -- hincrby 指令，如果指定域的某个 field 存在，就将该 field 的值 +1
    -- 如果不存在，就创建，初始化为 0 并 +1
    redis.call('hincrby', KEYS[1], ARGV[2], 1);
    -- 设置过期时间
    redis.call('pexpire', KEYS[1], ARGV[1]);
    return nil;
end ;
-- hash 存在，则判断 field 是否存在
if (redis.call('hexists', KEYS[1], ARGV[2]) == 1) then
    -- field 得值 +1
    redis.call('hincrby', KEYS[1], ARGV[2], 1);
    -- 重置过期时间
    redis.call('pexpire', KEYS[1], ARGV[1]);
    return nil;
end ;
-- 证明锁已经被持有，那就返回锁的有效期
return redis.call('pttl', KEYS[1]);
```

看注释就够了，简单解释一下参数列表：

* KEYS[1] 

  其实就是前面的例子中的 myLock，锁的名字，也是 Redis 中 hash 的名字

* ARGV[1]

  线程持有锁的有效时间，单位为**毫秒**。

* ARGV[2]

  持有锁的线程 id，其实不是简单的 id，注意 getLockName() 这个方法，后续会再来剖析。

从这里也就能猜到 tryAcquire() 方法返回的 Long 是当锁被其他线程持有时剩余的有效期，注意这里是 long 的封装类型，允许为 null。

现在将视线回到 RedissonLock 的 lock 方法里面，当 tryAcquire() 方法返回后，如果返回值为 null，从 lua 脚本的逻辑和 Java 代码的处理逻辑可以知道，此时是获取锁成功了。

当返回值不为 null 时，会放进一个 while 循环里面一致请求锁，直到成功：

```java
			while (true) {
                // 尝试获取锁，再次获取一次 ttl
                ttl = tryAcquire(-1, leaseTime, unit, threadId);
                // lock acquired
                if (ttl == null) {
                    // 获取锁失败
                    break;
                }

                // waiting for message
                if (ttl >= 0) {
                    // 阻塞当前线程 ttl 的时长
                    try {
                        future.getNow().getLatch().tryAcquire(ttl, TimeUnit.MILLISECONDS);
                    } catch (InterruptedException e) {
                        if (interruptibly) {
                            throw e;
                        }
                        future.getNow().getLatch().tryAcquire(ttl, TimeUnit.MILLISECONDS);
                    }
                } else {
                    if (interruptibly) {
                        future.getNow().getLatch().acquire();
                    } else {
                        future.getNow().getLatch().acquireUninterruptibly();
                    }
                }
            }
```

OK，到目前为止，Redisson 实现分布式锁的大致原理知道了。到这里基本上就结束了，下面只是我个人疑问的探索。

有个问题，在加锁的时候，我们在 hash 里面放入的键值对的 key 是一个线程 id 相关的字符串，既然是线程 id，那么当有多台服务器上的线程都在请求同一把锁时，肯定会出现不同服务器上的线程 id 重复的情况，那这种情况又要怎么解决？

前面在执行 lua 脚本的时候，又提过要主要 getLockName 这个方法，现在一起来看看吧。

## 分布式场景下如何做到锁的 key 唯一

拉到最前面执行 lua 脚本的地方，仔细翻看源码不难发现 getLockName() 方法的返回值其实就是在加锁时，hash 中的 key，同样，在最开始使用 Redisson 的分布式锁的时候，就看见过这个 key 的样子：

```bash
cc405566-7cfb-40ea-a1e3-7ddbe998e348:1
```

嗯，看不懂，还是看看代码吧。

```java
    protected String getLockName(long threadId) {
        return id + ":" + threadId;
    }
```

嗯，格式对上了，那么这个 id 是什么，在什么时候，通过什么生成的？

```java
    public RedissonBaseLock(CommandAsyncExecutor commandExecutor, String name) {
        super(commandExecutor, name);
        this.commandExecutor = commandExecutor;
        this.id = commandExecutor.getConnectionManager().getId();
        this.internalLockLeaseTime = commandExecutor.getConnectionManager().getCfg().getLockWatchdogTimeout();
        this.entryName = id + ":" + name;
    }
```

这个 id 是 RedissonLock 的父类 RedissonBaseLock 中定义的，最终其实又是从ConnectionManager 中获取，这个 ConnectionManager 从名字就可以知道其实是建立 redis 连接的时候初始化的，那就再看看初始化 ConnectionManager 的代码吧。

啊算了不看了，找了几秒钟发现其实就是一个 UUID，而 UUID 本身就是通过纳秒级的时间戳和宿主机的以太网卡地址等等一些信息生成的，本身就保证了分布式的唯一性，所以再搭配上线程 id，也就解决了前面提到的问题。