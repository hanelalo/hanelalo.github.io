---
title: Java 线程池
date: 2021-03-09 22:50:07
tags: Java
categories: 多线程技术
cover: http://image.hanelalo.cn/images/202111061349789.png
---

之前有写过一篇讲 Executor 框架的，最近发现其实讲的不是很清晰，只是介绍了分别有什么特性，而没有真正的使用。

所以这一篇的宗旨是 `talk is cheap, show me the code`。

JDK 提供了原生的 `Executor` 接口，下面有很多的可以管理线程池的实现。

```
public interface Executor {

    /**
     * Executes the given command at some time in the future.  The command
     * may execute in a new thread, in a pooled thread, or in the calling
     * thread, at the discretion of the {@code Executor} implementation.
     *
     * @param command the runnable task
     * @throws RejectedExecutionException if this task cannot be
     * accepted for execution
     * @throws NullPointerException if command is null
     */
    void execute(Runnable command);
}
```

`Executor` 接口提供了一个 `execute` 方法，入参是一个 `Runnable` 作为要执行的任务，方法执行时允许抛出一个 `RejectedExecutionException`，在接口的具体实现类中可以定义对这个异常的处理。

`Executor` 主要的实现 `ThreadPoolExecutor` 和 `ScheduleThreadPoolExecutor` 两种，`ScheduleThreadPoolExecutor` 是 `ThreadPoolExecutor` 的子类。

## ThreadPoolExecutor

```java
    public ThreadPoolExecutor(int corePoolSize,
                              int maximumPoolSize,
                              long keepAliveTime,
                              TimeUnit unit,
                              BlockingQueue<Runnable> workQueue,
                              ThreadFactory threadFactory,
                              RejectedExecutionHandler handler)
```

上面是 ThreadPoolExecutor 覆盖主要参数最齐全的构造函数。

* corePoolSize 

  线程池核心线程数，线程池并不是创建的时候就会创建很多个线程，而是在执行任务的时候才会开始创建，每次执行一个新的任务时，如果当前线程数小于核心线程池数，就选择建立一个新的线程来执行这个任务。

* maximumPoolSize

  线程池最大线程数，当线程创建得越来越多，为了避免资源占用过高，所以设置了最大的线程数，线程池中的线程数不会超过这个值。

* keepAliveTime

  线程池中空闲线程的存活时间。就像电商平台一样，可能有时候会有访问的高峰期，很多请求过来的时候，会创建很多的线程，但是当高峰期过了之后，可能就只需要几个线程就能处理所有请求，此时，为了避免资源浪费，需要释放掉其他的空闲状态的线程，当一个线程空闲时间超过 `keepAliveTime` 时，该线程就会关闭，资源释放。

* unit

  `keepAliveTime` 的时间单位。

* threadFactory

  线程工厂，这个工厂会用来创建线程池的工作线程，一般都会在这里对每个线程进行命名，方便追踪线程的执行。

* handler

  是一个 RejectedExecutionHandler 接口。在最前面讲到 `Executor#execute` 方法时，讲到它可能会抛出 `RejectedExecutionException` 异常，而这个异常默认时不做任何处理，直接抛出来的。RejectedExecutionHandler 就是在抛出 `RejectedExecutionException` 异常时，调用的异常处理逻辑。

* workQueue

  `BlockingQueue<Runnable>` 类型的阻塞队列。主要分为以下几种：

  1.  `ArrayBlockingQueue` 基于数组实现的有界队列，遵循先进先出（FIFO）原则，队列一旦创建，不能再更改大小，当队列满了的时候，调用 `put` 会阻塞，当队列是空队列时，调用 `take` 也会阻塞队列。
  2. `LinkedBlockingQueue` 基于链表实现的无界队列，这里无界的意思是容量上限为 `Integer.MAX_VALUE`，同样也遵循 `FIFO` 原则。
  3. `SynchronousQueue` 内部没有实际订单容量的队列，只有当一个线程在这个队列上调用了 `remove` 方法后，其他线程才可以调用 `put` 方法，否则会阻塞。
  4. `PriorityBlockingQueue` 优先级队列。

解释完了 `ThreadPoolExecutor` 的主要参数，现在尝试通过它创建一个线程池。

* 创建一个 `corePoolSize=3, maximumPoolSize=5` 的线程池：

  ```java
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(3, 5, 20, TimeUnit.SECONDS, new ArrayBlockingQueue<>(10), 
                                 new MyThreadFactory(), 
                                 (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle: queueSize is" + executor.getQueue().size());
              });
  ```

  ```java
  class MyThreadFactory implements ThreadFactory {
  	@Override
  	public Thread newThread(Runnable r) {
  		// 为每一个线程命名，方便追踪
  		return new Thread(r, "thread-" + threadNumber++);
  	}
  }
  ```

  上面创建了一个核心线程数为 3，最大线程数为 5 的线程池，线程最大空闲时间为 20 秒，任务缓存使用了 `ArrayBlockingQueue`，可缓存数为 10，创建线程的工厂 `MyThreadFactory` 只是对每个工作线程命名，对与抛出 `RejectedExecutionException`，只是打印当前线程池中工作线程数和队列中缓存任务数。

  下面通过一个测试来探索一下：

  ```java
  public class ThreadPoolExecutorTest {
    /** 线程编号 */
    private static int threadNumber = 1;
    // 后续例子中，只展示 main 方法，其他部分代码默认不变
    public static void main(String[] args) {
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(
              3,
              5,
              20,
              TimeUnit.SECONDS,
              new ArrayBlockingQueue<>(10),
              new MyThreadFactory(),
              (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle, queueSize is:" + executor.getQueue().size());
              });
      for (int i = 0; i < 10; i++) {
        threadPoolExecutor.execute(new MyThread());
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      System.out.println("queueSize is:" + threadPoolExecutor.getQueue().size());
      threadPoolExecutor.shutdown();
    }
  
    /**
     * 线程工厂，主要是命名线程
     */
    static class MyThreadFactory implements ThreadFactory {
      @Override
      public Thread newThread(Runnable r) {
        return new Thread(r, "thread-" + threadNumber++);
      }
    }
  }
  
  /**
   * 工作线程，启动先 sleep 5 秒，然后打印当前线程名称
   */
  class MyThread implements Runnable {
    @Override
    public void run() {
      try {
        Thread.sleep(5000);
      } catch (InterruptedException e) {
        e.printStackTrace();
      }
      System.out.println(Thread.currentThread().getName());
    }
  }
  ```

  ```
  poolSize is: 3
  queueSize is:7
  thread-2
  thread-3
  thread-1
  thread-2
  thread-1
  thread-3
  thread-3
  thread-1
  thread-2
  thread-3
  ```

  通过日志看到，当有 10 个任务放进线程池之后，线程池中的工作线程数依然是 3，不过任务队列中有 7 个待执行的任务，此时任务缓存还没被填满。

  然后，现在将要执行的任务数量改为 14：

  ```java
    public static void main(String[] args) {
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(
              3,
              5,
              20,
              TimeUnit.SECONDS,
              new ArrayBlockingQueue<>(10),
              new MyThreadFactory(),
              (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle, queueSize is:" + executor.getQueue().size());
              });
      for (int i = 0; i < 14; i++) {
        threadPoolExecutor.execute(new MyThread());
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      System.out.println("queueSize is:" + threadPoolExecutor.getQueue().size());
      threadPoolExecutor.shutdown();
    }
  ```

  ```java
  poolSize is: 4
  queueSize is:10
  thread-3
  thread-1
  thread-2
  thread-4
  thread-2
  thread-1
  thread-3
  thread-4
  thread-1
  thread-3
  thread-2
  thread-4
  thread-1
  thread-3
  ```

  可以看见，当任务数为 14 时，因为有 3 个任务由核心线程在执行，还剩 11 个任务待执行，而任务缓存队列是 `ArrayBlockingQueue` 类型的有界队列，创建时已经初始化容量为 10 不可更改，放入任务队列缓存后，还剩下一个任务，此时工作线程数为 3，小于最大线程数，所以选择创建一个新的线程来执行任务，所以最终输出的工作线程数为 4，而队列大小为 10。

  通过上面两次试验可以知道，**线程池在执行任务时，会尽量只开启 corePoolSize 个线程来执行任务；当待执行任务数大于了核心线程数时，会将剩余的任务放到缓存队列中；如果任务队列为有界队列，当队列满了且有新的待执行任务到来时，如果工作线程数还未达到最大值，会创建一个新的线程来执行任务。**

  那么，如果工作线程数达到最大并都处于执行任务的状态中，且任务队列满了，此时如果有新的任务放入线程池会发生什么？

  ```java
    public static void main(String[] args) {
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(
              3,
              5,
              20,
              TimeUnit.SECONDS,
              new ArrayBlockingQueue<>(10),
              new MyThreadFactory(),
              (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle, queueSize is:" + executor.getQueue().size());
              });
      for (int i = 0; i < 16; i++) {
        threadPoolExecutor.execute(new MyThread());
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      System.out.println("queueSize is:" + threadPoolExecutor.getQueue().size());
      threadPoolExecutor.shutdown();
    }
  ```

  ```
  exception handle, poolSize is: 5
  exception handle, queueSize is:10
  poolSize is: 5
  queueSize is:10
  thread-4
  thread-2
  thread-3
  thread-5
  thread-1
  thread-5
  thread-3
  thread-2
  thread-1
  thread-4
  thread-2
  thread-4
  thread-1
  thread-5
  thread-3
  ```

  将任务数改为 16 后，刚好出现了上述问题锁描述的情况。通过输出日志可以看到，此时触发了 `RejectedExecutionException` 异常的处理逻辑，也就是说，**当工作线程数达到最大并都处于执行任务的状态中，且任务队列满了，此时如果有新的任务放入线程池，会抛出 `RejectedExecutionException`**。

  接下来，在测试一下线程的销毁时间。

  ```java
    public static void main(String[] args) {
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(
              3,
              5,
              10,
              TimeUnit.SECONDS,
              new ArrayBlockingQueue<>(10),
              new MyThreadFactory(),
              (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle, queueSize is:" + executor.getQueue().size());
              });
      for (int i = 0; i < 15; i++) {
        threadPoolExecutor.execute(new MyThread());
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      System.out.println("queueSize is:" + threadPoolExecutor.getQueue().size());
      try {
        // 休眠 26 秒，等待空闲线程释放资源
        Thread.sleep(26000);
      } catch (InterruptedException e) {
        e.printStackTrace();
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      threadPoolExecutor.shutdown();
    }
  ```

  上面将线程空闲时间改为 10 秒，并且在所有任务提交后，休眠 26 秒，以等待空闲线程销毁。

  ```
  poolSize is: 5
  queueSize is:10
  thread-5
  thread-3
  thread-1
  thread-2
  thread-4
  thread-5
  thread-3
  thread-4
  thread-1
  thread-2
  thread-5
  thread-3
  thread-4
  thread-2
  thread-1
  poolSize is: 3
  ```

  通过日志看出，线程池工作线程数达到最大值以后并执行完了所有任务。先算算时间，一共 15 个任务，5 个线程执行，每个任务执行 5 秒，所以理论上需要 15 秒就可以执行完所有任务，所以理论上主线程休眠 15 + 10 = 25 秒就可以看到工作线程数变为 3，但考虑到线程切换也需要少许时间，所以 sleep 的时间需要大于 25 秒。最终的结果也如配置一样， 10 秒后，多余的线程被销毁。

  然后，还有一个问题，在上面所有例子中，最开始的 3 个核心工作线程，什么时候创建的？此时只需要将任务调到小于核心线程数即可。

  ```java
    public static void main(String[] args) {
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(
              3,
              5,
              10,
              TimeUnit.SECONDS,
              new ArrayBlockingQueue<>(10),
              new MyThreadFactory(),
              (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle, queueSize is:" + executor.getQueue().size());
              });
      for (int i = 0; i < 2; i++) {
        threadPoolExecutor.execute(new MyThread());
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      System.out.println("queueSize is:" + threadPoolExecutor.getQueue().size());
      threadPoolExecutor.shutdown();
    }
  ```

  ```
  poolSize is: 2
  queueSize is:0
  thread-1
  thread-2
  ```

  从输出可以知道，当任务数小于核心工作线程数时，工作线程数和任务数相等，由此可以的当结论，**核心线程不是初始化线程池时创建，而是有任务提交时动态创建，只要当线程数小于核心线程数，就无条件创建新的工作线程。**

  在上面的所有例子中，都会调用 `threadPoolExecutor.shutdown()` 方法来关闭线程池，但是在主线程中没有 sleep，而是提交了任务后直接就 `shutdown`，而最终所有任务都执行了，这说明，**`shutdown()` 方法会等待所有任务执行完之后才会真正的关闭线程池。**

  最后一个问题，如果在调用 `shutdown()` 之后，线程池正真关闭之前，再提交任务会发生什么？

  ```java
    public static void main(String[] args) {
      ThreadPoolExecutor threadPoolExecutor =
          new ThreadPoolExecutor(
              3,
              5,
              10,
              TimeUnit.SECONDS,
              new ArrayBlockingQueue<>(10),
              new MyThreadFactory(),
              (r, executor) -> {
                System.out.println("exception handle, poolSize is: " + executor.getPoolSize());
                System.out.println("exception handle, queueSize is:" + executor.getQueue().size());
              });
      for (int i = 0; i < 2; i++) {
        threadPoolExecutor.execute(new MyThread());
      }
      System.out.println("poolSize is: " + threadPoolExecutor.getPoolSize());
      System.out.println("queueSize is:" + threadPoolExecutor.getQueue().size());
  
      threadPoolExecutor.shutdown();
      System.out.println("-----------shutdown-------");
      threadPoolExecutor.execute(new MyThread());
    }
  ```

  ```
  poolSize is: 2
  queueSize is:0
  -----------shutdown-------
  exception handle, poolSize is: 2
  exception handle, queueSize is:0
  thread-2
  thread-1
  ```

  通过日志可以得到结论，**在 `shutdown()` 后在提交任务会抛出 `RejectedExecutionException`，触发异常处理逻辑。**

终于，将 `ThreadPoolExecutor` 的基本流程搞明白了，关于内部的一些原理，就在下一篇文章中在讨论。

