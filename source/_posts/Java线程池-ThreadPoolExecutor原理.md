---
title: Java线程池-ThreadPoolExecutor原理
date: 2021-03-12 22:05:36
tags: Java
categories: 多线程技术
cover: https://hanelalo.github.io/images/202111061349153.png
---

# ThreadPoolExecutor 原理

上一讲中，从测试的角度了解了 `ThreadPoolExecutor`，但是并没有透过源码来解释它的运行。

在开始之前，需要解释一个 `ThreadPoolExecutor` 核心参数：

```java
private final AtomicInteger ctl = new AtomicInteger(ctlOf(RUNNING, 0));
```

`ctl` 算是最核心的控制参数，它是一个 `AtomicInteger` 类型，支持原子操作的 `int` 类型，在 Java 中，`int` 类型有 32 位，4 个字节，`ThreadPoolExecutor` 将这 32 位的高 3 位用来记录线程池的状态，低 29 位用来记录当前有效的工作线程数。

内部提供以下方法来解析 `ctl` 参数：

```java
    private static int runStateOf(int c)     { return c & ~CAPACITY; } // 通过 ctl 计算当前线程池状态
    private static int workerCountOf(int c)  { return c & CAPACITY; } // 通过 ctl 计算当前工作线程数
    private static int ctlOf(int rs, int wc) { return rs | wc; } // 通过状态和线程数反算 ctl
```

## execute() 执行任务

那么，一切就从 `ThreadPoolExecutor.execute()` 开始吧。

```java
public void execute(Runnable command) {
    	// 当执行的任务为 null，抛出空指针
        if (command == null)
            throw new NullPointerException();
        int c = ctl.get();
    	// 比较当前工作线程数和配置的核心线程数
        if (workerCountOf(c) < corePoolSize) {
            // 新增工作线程
            if (addWorker(command, true))
                return;
            c = ctl.get();
        }
    	// 走到这里，说明工作线程数已经达到了核心线程数
    	// 如果线程池处于运行状态，尝试将新任务放入到缓存工作队列中
        if (isRunning(c) && workQueue.offer(command)) {
            int recheck = ctl.get();
            // 任务成功放入工作队列后再次检测线程池运行状态
            if (! isRunning(recheck) && remove(command))
                reject(command);
            else if (workerCountOf(recheck) == 0)
                addWorker(null, false);
        }
    	// 尝试增加新的线程来执行任务，这里其实就是线程数达到核心线程并且任务队列也已经满了
        else if (!addWorker(command, false))
            reject(command);
    }
```

上述代码中，已经有了注释。总结一下就是：

> 1. 如果当前线程数还没达到核心线程数，则创建新的工作线程，当前任务作为工作线程的第一个任务执行。
> 2. 如果当前工作线程数达到了核心线程数，尝试将任务放到任务的缓存队列中。
> 3. 如果放入缓存队列失败，这种一般都是缓存队列也满了，那就尝试增加新的线程来执行当前任务，如果最终创建新的工作线程也失败，那就执行拒绝策略了。

那么接下来再深入婆媳以下 `addWorker()` 和 `reject()` 这两个方法。

### 增加新的工作线程 addWorker()

```java
private boolean addWorker(Runnable firstTask, boolean core) {
    retry:
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // 也就是说，要么线程池是 RUNNING，要么是 SHUTDOWN 并且任务为 null 且任务队列不为空，
        // 不然直接返回 false
        if (rs >= SHUTDOWN &&
            ! (rs == SHUTDOWN &&
               firstTask == null &&
               ! workQueue.isEmpty()))
            return false;

        for (;;) {
            int wc = workerCountOf(c);
            // 第一种情况，没有限制工作线程数，那么工作线程数上限为 2^32 - 1
            // 第二种情况，根据 core 来决定要不要创建新线程。
            if (wc >= CAPACITY ||
                wc >= (core ? corePoolSize : maximumPoolSize))
                return false;
            // 以 CAS 方式将工作线程数 +1，如果失败，跳转到 retry 重来
            if (compareAndIncrementWorkerCount(c))
                break retry;
            c = ctl.get();  // Re-read ctl
            // 如果工作线程 +1 后线程池状态发生改变，依然跳转到 retry
            if (runStateOf(c) != rs)
                continue retry;
        }
    }
    // 走到这里，已经保证现在创建一个线程后，线程数不会超过核心线程数或者最大线程数（主要还是由方法参数 core 判断）
    // 开始真正创建工作线程
    boolean workerStarted = false;
    boolean workerAdded = false;
    Worker w = null;
    try {
        w = new Worker(firstTask);
        final Thread t = w.thread;
        if (t != null) {
            // 对与下增工作线程这个过程加锁，防止并发新建线程导致线程池持有不正确的线程数
            final ReentrantLock mainLock = this.mainLock;
            mainLock.lock();
            try {
                // 再次检查线程池状态
                int rs = runStateOf(ctl.get());
                if (rs < SHUTDOWN ||
                    (rs == SHUTDOWN && firstTask == null)) {
                    if (t.isAlive())
                        throw new IllegalThreadStateException();
                    workers.add(w);
                    int s = workers.size();
                    if (s > largestPoolSize)
                        largestPoolSize = s;
                    workerAdded = true;
                }
            } finally {
                mainLock.unlock();
            }
            if (workerAdded) {
                // 启动工作线程
                t.start();
                workerStarted = true;
            }
        }
    } finally {
        if (! workerStarted)
            addWorkerFailed(w);
    }
    return workerStarted;
}
```

`addWorker` 方法有两个入参，第一个是 `firstWorker` ，也就是新线程要执行的第一个任务对象，第二个是 `core`，用来标识当前调用是否是要创建一个核心线程。

这里只考虑调用 `execute` 时创建核心线程和非核心线程的时候，可以知道，当 `core==true`，如果线程数已经达到 `corePoolSize`，或者 `core==false`，且当前线程数达到最大线程数 `maximumPoolSize`，将会返回 `false`。

### 拒绝处理 reject()

```java
    final void reject(Runnable command) {
        handler.rejectedExecution(command, this);
    }
```

`ThreadPoolExecutor` 提供了四种拒绝处理策略。

1. AbortPolicy 直接抛出 RejectedExecutionException
2. CallerRunsPolicy  由调用线程池的线程去执行任务，如果线程池不是 RUNNING 状态，则任务会丢失
3. DiscardOldestPolicy 如果线程不是 RUNNING 状态，任务将丢失，如果是 RUNNING 状态，将会丢弃队列中最旧的任务，然后再次尝试执行任务
4. DiscardPolicy  直接丢弃任务，不做任何处理

默认的拒绝处理策略时 `AbortPolicy`，也就是抛异常。

## 工作线程 Worker

```java
    private final class Worker extends AbstractQueuedSynchronizer implements Runnable{
        /** Thread this worker is running in.  Null if factory fails. */
        final Thread thread;
        /** Initial task to run.  Possibly null. */
        Runnable firstTask;
    }
```

* thread 当前持有的线程对象
* firstTask 当前执行的任务

```java
    final void runWorker(Worker w) {
        Thread wt = Thread.currentThread();
        Runnable task = w.firstTask;
        w.firstTask = null;
        w.unlock(); // 允许中断
        boolean completedAbruptly = true;
        try {
            // 获取要执行的任务
            while (task != null || (task = getTask()) != null) {
                w.lock();
                // 处理中断
                if ((runStateAtLeast(ctl.get(), STOP) ||
                     (Thread.interrupted() &&
                      runStateAtLeast(ctl.get(), STOP))) &&
                    !wt.isInterrupted())
                    wt.interrupt();
                try {
                    beforeExecute(wt, task);
                    Throwable thrown = null;
                    try {
                        task.run();
                    } catch (RuntimeException x) {
                        thrown = x; throw x;
                    } catch (Error x) {
                        thrown = x; throw x;
                    } catch (Throwable x) {
                        thrown = x; throw new Error(x);
                    } finally {
                        afterExecute(task, thrown);
                    }
                } finally {
                    task = null;
                    w.completedTasks++;
                    w.unlock();
                }
            }
            completedAbruptly = false;
        } finally {
            // 销毁工作线程
            processWorkerExit(w, completedAbruptly);
        }
    }
```

其实最终执行任务倒是没什么好讲的，主要是，这段代码里面还涉及到了工作线程的销毁。

`runWorker` 方法内部通过一个 `while` 循环一直保持工作线程处于运行状态，但是循环的条件是：

```java
task != null || (task = getTask()) != null
```

第一个判断是判 worker 当前是否已经有了一个待执行任务，这种情况一般是，线程刚创建，执行第一个任务。

第二个判断先调用了 `getTask()` 方法来获取任务，然后才判空，所以接下来主要再看看 `getTask()` 方法。

```java
    private Runnable getTask() {
        // 最后一次调用工作队列的 poll 是否超时
        boolean timedOut = false;
        for (;;) {
            int c = ctl.get();
            int rs = runStateOf(c);
            // 如果线程池状态不是运行中，调用了 shutdownNow() 或者工作队列为空，
            // 返回 false，此时需要将工作线程数减一，返回 null，该工作线程将会销毁
            if (rs >= SHUTDOWN && (rs >= STOP || workQueue.isEmpty())) {
                decrementWorkerCount();
                return null;
            }
            int wc = workerCountOf(c);
            // allowCoreThreadTimeOut 用来控制核心线程在空闲一段时间后是否也要销毁，一般为 false
            // 所以这里主要是判断当前工作线程是否需要按照空闲的非核心线程处理，所以判断线程数是否大于核心线程数
            boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;
            // 如果线程数大于最大线程数或者需要做线程空闲超时处理
            if ((wc > maximumPoolSize || (timed && timedOut))
                // 在前一个判断的基础上，如果当线程数大于 1 或者工作缓存队列为空，则线程数减一，
                // 返回 null，将会销毁当前工作线程
                && (wc > 1 || workQueue.isEmpty())) {
                if (compareAndDecrementWorkerCount(c))
                    return null;
                continue;
            }
            try {
                // 这里如果 timed 为 true 时，有两种情况
                // 1. 当前请求先任务的线程是核心线程并且核心线程也需要做空闲超时处理（不常用）
                // 2. 当前请求新任务的工作线程是非核心线程

                Runnable r = timed ?                
                    // 以上两种情况，将会调用 poll() 方法，并且有 keepAliveTime 的超时时间，
                    // 谨记该时间是初始化线程池时可以构造函数传入的
                    workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) :
                    // 如果不是上述两种情况，那么当前线程数没超过核心线程数，并且核心线程不做空闲超时处理
                    // 所以调用 take() 方法获取新任务，该方法会一直阻塞到有新任务到来再返回
                    workQueue.take();
                if (r != null)
                    return r;
                // 标识最后一次 poll() 方法超时了，这会使席次循环直接返回 null，
                // 然后在 runWorker() 中销毁工作线程
                timedOut = true;
            } catch (InterruptedException retry) {
                timedOut = false;
            }
        }
    }
```

这段代码已经加上详细注释，主要还是得明白队列的 ` poll(long timeout, TimeUnit unit))` 和 `take()` 的用法和区别。

其次就是还得明白这里面处理处理空闲超时，还优先处理了线程池调用了 `shutdown()` 和 `shutdownNow()` 这两种情况。

* 如果调用了 `shutdown()` 将不会直接销毁线程，而是尝试让它继续执行任务队列中的任务，最终任务队列为空时才会销毁线程。

* 如果调用的是 `shutdownNow()`，将直接销毁线程，这样做，将会丢失任务队列中的所有任务。

关于 `shutdown()` 和 `shutdownNow()` 的区别将在后面讲解，现在先深挖一下工作线程的销毁。

当 `getTask()` 返回 null 时，`runWorker()` 将会调用 `processWorkerExit()` 方法来销毁线程。

```java
    private void processWorkerExit(Worker w, boolean completedAbruptly) {
        if (completedAbruptly)
            decrementWorkerCount();

        final ReentrantLock mainLock = this.mainLock;
        mainLock.lock();
        try {
            completedTaskCount += w.completedTasks;
            // 从 workers 中删除当前工作线程的引用，留待 gc 来回收
            workers.remove(w);
        } finally {
            mainLock.unlock();
        }
        // 尝试设置线程池状态，这里一般都是销毁最后一个线程池了，不然其实没什么实际效果
        tryTerminate();
        int c = ctl.get();
        if (runStateLessThan(c, STOP)) {
            if (!completedAbruptly) {
                int min = allowCoreThreadTimeOut ? 0 : corePoolSize;
                if (min == 0 && ! workQueue.isEmpty())
                    min = 1;
                if (workerCountOf(c) >= min)
                    return; // replacement not needed
            }
            addWorker(null, false);
        }
    }
```

线程资源的回收，主要依靠 JVM 的 GC，所以这里只是断开了引用而已，而线程数减一这一步操作其实在 `getTask()` 方法返回之前就已经做了。

## shutdown() 和 shutdownNow()

* shutdown()

  ```java
      public void shutdown() {
          // 加锁，方式并发调用 shutdown()
          final ReentrantLock mainLock = this.mainLock;
          mainLock.lock();
          try {
              checkShutdownAccess();
              // 尝试设置状态为 SHUTDOWN
              advanceRunState(SHUTDOWN);
              // 向工作线程发送中断
              interruptIdleWorkers();
              // 执行一些 shutdown 后的扩展处理
              onShutdown(); // hook for ScheduledThreadPoolExecutor
          } finally {
              mainLock.unlock();
          }
          // 尝试终止线程池
          tryTerminate();
      }
  ```

* shutdownNow()

  ```java
      public List<Runnable> shutdownNow() {
          List<Runnable> tasks;
          // 加锁
          final ReentrantLock mainLock = this.mainLock;
          mainLock.lock();
          try {
              checkShutdownAccess();
              // 尝试设置线程池状态为 STOP
              advanceRunState(STOP);
              //向工作线程发送中断
              interruptWorkers();
              // 返回未执行的任务
              tasks = drainQueue();
          } finally {
              mainLock.unlock();
          }
          tryTerminate();
          return tasks;
      }
  ```

  这两者最大的区别在于前者将线程池设置为为 `SHUTDOWN`，后者将线程池状态设置为 `STOP` 状态，而对于这两种状态，工作线程会有不同的处理，前面已经讲过了。

  然后就是，因为 `shutdown()` 会等待线程池将所有任务执行完，而 `shutdownNow()` 会直接不再执行任务队列中的所有任务，所以为了方便处理，`shutdownNow()` 将未执行的任务返回。