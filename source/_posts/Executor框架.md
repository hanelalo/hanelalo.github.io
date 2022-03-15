---
title: Executor框架
date: 2020-10-17 23:43:55
tags: Java
categories: 多线程技术
cover: http://image.hanelalo.cn/images/202111061348509.png
---

虽然 Java 提供了手动创建线程的操作方式，但是实际生产环境中，肯定不会允许无限创建线程，因为服务器会炸，所以 JDK 提供了 Exexutor 框架用来管理线程。

Executor 是一个接口，也是整个框架最核心的接口。

```java
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

整个 Executor 框架的主要成员和相应的功能如下：

* `ThreadPoolExecutor`

  ThreadPoolExecutor 的核心参数如下：

  * `corePoolSize`

    核心线程数。

  * maximumPoolSize

    最大线程数

  * `keepAliveTime`

    线程空闲时间

  * `unit`

    线程空闲时间单位

  * `workQueue`

    任务队列，是一个阻塞队列。

  * `threadFactory`

    线程工厂。

  通常通过 Executors 工厂类创建，Executors 能创建三种 ThreadPoolExecutor：

  * `SingleThreadExecutor`

    只有一个工作线程，所以初始化 ThreadPoolExecutor 时传入的核心线程数和最大线程数都是 1。适用于需要异步但是也需要按照某种顺序执行的场景。

    ```java
        public static ExecutorService newSingleThreadExecutor() {
            return new FinalizableDelegatedExecutorService
                (new ThreadPoolExecutor(1, 1,
                                        0L, TimeUnit.MILLISECONDS,
                                        new LinkedBlockingQueue<Runnable>()));
        }
    ```

  * `FixedThreadPool`

    固定线程数的线程池。核心线程数和最大线程数一样。适用于需要进行资源管理的服务。

    ```java
        public static ExecutorService newFixedThreadPool(int nThreads, ThreadFactory threadFactory) {
            return new ThreadPoolExecutor(nThreads, nThreads,
                                          0L, TimeUnit.MILLISECONDS,
                                          new LinkedBlockingQueue<Runnable>(),
                                          threadFactory);
        }
    ```

  * `CachedThreadPool`

    核心线程数为 0，但是最大线程数位 `Integer.MAX_VALUE` 基本相当于不限制，线程空闲存活时间位为 1 分钟，因为线程可以无限创建，所以更适合做一些能快速完成的任务，不然就会出现一台服务器上创建成千上万个线程的情况。

    ```java
        public static ExecutorService newCachedThreadPool() {
            return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                          60L, TimeUnit.SECONDS,
                                          new SynchronousQueue<Runnable>());
        }
    ```

* `ScheduledThreadPoolExecutor`

  和 ThreadPoolExecutor 一样，通常也是通过 Executors 创建。创建的 ScheduledThreadPoolExecutor 其实最后也是基于 ThreadPoolExecutor 实现的，不同点在于前面讲到的三种普通的 ThreadPoolExecutor 传入的任务队列是基于链表实现的`LinkedBlockingQueue`， 因为 `ScheduledThreadPoolExecutor` 一般都是用来做定时任务或者延迟任务，所以传入的是`DelayWorkQueue`。

  ```java
  public ScheduledThreadPoolExecutor(int corePoolSize) {
      super(corePoolSize, Integer.MAX_VALUE, 0, NANOSECONDS,
            new DelayedWorkQueue());
  }
  ```

  Executors 可以创建两种 `ScheduledThreadPoolExecutor`:

  * `ScheduledThreadPoolExecutor`

    `ScheduledThreadPoolExecutor`是`ThreadPoolExecutor`的子类，适用于有多个定时任务的场景。
    
    ```java
        public ScheduledThreadPoolExecutor(int corePoolSize) {
            super(corePoolSize, Integer.MAX_VALUE, 0, NANOSECONDS,
                  new DelayedWorkQueue());
    }
    ```
    
  * `SingleThreadScheduledExecutor`
  
    适用于需要单个线程执行后台任务且有顺序要求的场景。
  
* `Future`接口

  当一个任务需要返回值时，通过 `submit` 方法将任务（`Runnable`或`Callable`接口的实现）提交到 `ThreadPoolExecutor`或 `ScheduledThreadPoolExecutor` ，会返回一个 Future 接口的实现类，一般是 `FutureTask`。

* `Runnable` 和 `Callable`

  这两个接口的实现都可以当作任务提交到 ThreadPoolExecutor 执行，区别在于 `Runnable` 没有返回值，`Callable` 有返回值，`Executors`提供了一个将 `Runnable`接口封装成 `Callable` 接口的方法。

  ```java
      public static <T> Callable<T> callable(Runnable task, T result) {
          if (task == null)
              throw new NullPointerException();
          return new RunnableAdapter<T>(task, result);
      }
  ```

  当 submit 的任务是 Runnable 接口时，会调用上面的方法进行转换。