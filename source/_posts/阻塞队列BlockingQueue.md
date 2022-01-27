---
title: 阻塞队列BlockingQueue
date: 2021-11-28 22:13:00
tags: Java
categories: 多线程技术
cover: https://hanelalo.github.io/images/202111281136045.png
---

# BlockingQueue

在介绍 BlockingQueue 之前，先了解一下 Queue 这种数据结构。

Queue，也就是队列，遵循先入先出（FIFO）的规则，就像去窗口排队买票一样，先排队的人先买票。

```java
public interface Queue<E> extends Collection<E> {
    /** 入队，如果超出容量限制会抛异常 */
    boolean add(E e);
	/** 入队，超出容量返回 false */
    boolean offer(E e);
	/** 删除并返回队头结点，出队，如果队列为空会抛异常 */
    E remove();
	/** 删除并返回队头结点，出队，队列为空返回 null */
    E poll();
	/** 获取对头节点，但不删除，如果队列为空，会抛异常 */
    E element();
	/** 获取对头节点，但不删除，如果队列为空返回 null */
    E peek();
}
```

java 中对 Queue 提供 6 个 api，注释已经说明。

BlockingQueue 继承了 Queue，并再次基础上又增加了一些能力。

```java
public interface BlockingQueue<E> extends Queue<E> {
	//other methods...
    /** 入队，队列满了会阻塞，响应中断 */
    void put(E e) throws InterruptedException;
	/** 入队，队列满了会阻塞，响应中断，有超时机制 */
    boolean offer(E e, long timeout, TimeUnit unit) throws InterruptedException;
	/** 出队，获取并删除队首元素，队列是空时阻塞，响应中断 */
    E take() throws InterruptedException;
	/** 出队，获取并删除队首元素，队列是空时阻塞，有超时机制，响应中断 */
    E poll(long timeout, TimeUnit unit) throws InterruptedException;
	/** 从队列中删除 */
    boolean remove(Object o);
}
```

## ArrayBlockingQueue

ArrayBlockingQueue 底层使用数组结构实现，内部维护了一把锁和两个 Condition。

```java
public class ArrayBlockingQueue<E> extends AbstractQueue<E>
        implements BlockingQueue<E>, java.io.Serializable {
	final Object[] items;
	int takeIndex;
	int putIndex;
	final ReentrantLock lock;
    private final Condition notEmpty;
    private final Condition notFull;
	
    public ArrayBlockingQueue(int capacity, boolean fair) {
        if (capacity <= 0)
            throw new IllegalArgumentException();
        this.items = new Object[capacity];
        lock = new ReentrantLock(fair);
        notEmpty = lock.newCondition();
        notFull =  lock.newCondition();
    }
}
```

当队列是空的时候，出队操作会阻塞，当队列是满的时候，入队操作会阻塞。

### 入队

```java
public void put(E e) throws InterruptedException {
    checkNotNull(e);
    final ReentrantLock lock = this.lock;
    lock.lockInterruptibly();
    try {
        while (count == items.length)
            notFull.await();
        enqueue(e);
    } finally {
        lock.unlock();
    }
}
```

1. put 方法首先获取锁，且响应中断。
2. 判断当前队列是否已满。
3. 如果队列已经满了，调用 `notFull.await()` 方法阻塞当前线程，此时在 `await()` 方法里面释放锁，避免出现死锁问题。
4. 当队列不是满的时候，将元素加入到 ArryBlockingQueue 队列中，其实就是设置到它维护的数组里面。
5. 释放锁。

```java
private void enqueue(E x) {
    // assert lock.getHoldCount() == 1;
    // assert items[putIndex] == null;
    final Object[] items = this.items;
    items[putIndex] = x;
    if (++putIndex == items.length)
        putIndex = 0;
    count++;
    notEmpty.signal();
}
```

上面是入队的 `enqueue()` 方法逻辑。因为到这里已经拿到了锁，所以不需要通过 CAS 的方式来入队，将新元素放进数组之后，判断了 `++putIndex` 是否和数组的长度相等，如果相等，说明队尾的位置已经到了数组的最后一个元素的位置，此时将 putIndex 置为 0，标识又从头开始，说明 ArrayBlockingQueue 维护的其实是一个环形的数组结构。

在入队成功之后，当前队列肯定就不是空队列了，所以调用了 `notEmpty.signal()` 方法通知在 notEmpty 这个 Condition 上阻塞的线程。

### 出队

```java
public E take() throws InterruptedException {
    final ReentrantLock lock = this.lock;
    lock.lockInterruptibly();
    try {
        while (count == 0)
            notEmpty.await();
        return dequeue();
    } finally {
        lock.unlock();
    }
}
```

1. 获取响应中断的锁。
2. 判断当前队列是否为空队列。
3. 如果队列是空的，调用 notEmpty.await()` 阻塞当前线程。
4. 如果不是空队列，或者被其他线程通过 notEmpty 唤醒，调用 `dequeue()` 出队。
5. 解锁。

```java
private E dequeue() {
    final Object[] items = this.items;
    E x = (E) items[takeIndex];
    items[takeIndex] = null;
    if (++takeIndex == items.length)
        takeIndex = 0;
    count--;
    if (itrs != null)
        itrs.elementDequeued();
    notFull.signal();
    return x;
}
```

出队操作其实就是获取队头节点，删除并返回。和入队类似，如果 `++takeIndex` 等于队列的容量大小，就置 0。然后通过 `notFull.signal()` 方法通知在 notFull 这个 Condition 上阻塞的线程。

### 总结

* ArrayBlockingQueue 底层由数组实现，初始化时会初始化这个数组的大小，这个数组在逻辑上是一个环形的数组。
* 当队列满了的时候，线程调用 put 入队时，会在 notFull 这个 Condition 上面阻塞。
* 新元素一旦入队成功，队列肯定不再为空队列，会通过 notEmpty 这个 Condition 激活其他的出队操作线程。
* 当队列为空队列是，线程调用 take 出队时，会在 notEmpty 这个 Condition 上面阻塞。
* 出队成功后，队列肯定是未满状态，所以通过 notFull 唤醒其他的入队线程。

## LinkedBlockingQueue

LinkedBlockingQueue 底层数据结构是用链表实现，链表的 head 是队头，tail 是队尾，新入队的元素放在 tail 后面，链表长度可以通过构造函数指定，如果不指定，默认长度为 `Integer.MAX_VALUE`。

```java
public class LinkedBlockingQueue<E> extends AbstractQueue<E>
        implements BlockingQueue<E>, java.io.Serializable {
	    private final int capacity;

    private final AtomicInteger count = new AtomicInteger();

    transient Node<E> head;

    private transient Node<E> last;

    private final ReentrantLock takeLock = new ReentrantLock();

    private final Condition notEmpty = takeLock.newCondition();

    private final ReentrantLock putLock = new ReentrantLock();

    private final Condition notFull = putLock.newCondition();
    
    public LinkedBlockingQueue() {
        this(Integer.MAX_VALUE);
    }

    public LinkedBlockingQueue(int capacity) {
        if (capacity <= 0) throw new IllegalArgumentException();
        this.capacity = capacity;
        last = head = new Node<E>(null);
    }
}
```

为了提高并发度，LinkedBlockingQueue 维护的了两个 ReentrantLock，put 和 take 各一个，分别又生成了 notEmpty 和 notFull 两个 Condition 对象，也因此专门维护了一个 AtomicInteger 原子操作类型的对象来记录当前队列中的元素个数。

需要注意的是，LinkedBlockingQueue 初始化的队首和队尾节点不为 null，但是 Node 中的值为 null。

### 入队

```java
public void put(E e) throws InterruptedException {
    if (e == null) throw new NullPointerException();
    int c = -1;
    Node<E> node = new Node<E>(e);
    final ReentrantLock putLock = this.putLock;
    final AtomicInteger count = this.count;
    putLock.lockInterruptibly();
    try {
        while (count.get() == capacity) {
            notFull.await();
        }
        enqueue(node);
        c = count.getAndIncrement();
        if (c + 1 < capacity)
            notFull.signal();
    } finally {
        putLock.unlock();
    }
    if (c == 0)
        signalNotEmpty();
}
```

1. 创建新的 Node 对象。
2. 获取 putLock 的支持中断的锁。
3. 判断当前队列是否满了，如果满了，调用 `notFull.await()` 阻塞当前线程，等待唤醒。
4. 如果当前队列未满，调用 enqueue() 方法入队。
5. 获取 count 变量的值并加一。
6. 然后判断此次 put 操作后，队列是否满了，如果未满，通过 notFull 唤醒其他线程，按照前面 ArrayBlockingQueue 的逻辑来看，这一段唤醒的逻辑应该是在 take 的时候做，我认为在这里做其实是为了提高吞吐量而做的优化。
7. 释放锁。
8. 如果在本次 put 前队列为空，此时调用 signalNotEmpty 唤醒 take 的线程。

因为此时当前线程已经拿到了 putLock 的锁，所以 `enqueue()` 方法的逻辑直接正常和队尾元素 last 关联即可。

```java
    private void enqueue(Node<E> node) {
        // assert putLock.isHeldByCurrentThread();
        // assert last.next == null;
        last = last.next = node;
    }
```

在通知 take 操作上阻塞的线程的时候，因为在 LinkedBlockingQueue 里面 take 和 put 是分开的两把锁，notEmpty 是通过调用 takeLock.newCondition() 生成了，所以在 put 操作中要调用 notEmpty.signal() 方法时，还需要获取 takeLock 才能执行。

```java
private void signalNotEmpty() {
    final ReentrantLock takeLock = this.takeLock;
    takeLock.lock();
    try {
        notEmpty.signal();
    } finally {
        takeLock.unlock();
    }
}
```

### 出队

```java
public E take() throws InterruptedException {
    E x;
    int c = -1;
    final AtomicInteger count = this.count;
    final ReentrantLock takeLock = this.takeLock;
    takeLock.lockInterruptibly();
    try {
        while (count.get() == 0) {
            notEmpty.await();
        }
        x = dequeue();
        c = count.getAndDecrement();
        if (c > 1)
            notEmpty.signal();
    } finally {
        takeLock.unlock();
    }
    if (c == capacity)
        signalNotFull();
    return x;
}
```

1. 通过 takeLock 获取响应中断的锁。
2. 如果当前队列是空队列，则调用 `notEmpty.await()` 方法阻塞线程。
3. 如果不是空队列，调用 dequeue() 方法出队。
4. count 变量减一。
5. 如果 count 减一前大于 1，说明此时队列的元素个数至少也是 1，依然不是空的，调用 notEmpty.signal() 方法唤醒其他的 take 操作线程。
6. 解锁。
7. 如果 count 减一前等于 capacity，也就是说，在此次 take  前，队列是满的，那就调用 signalNotFull() 唤醒 put 操作线程。

因为到调用 dequeue() 方法时，线程已经拿到了 takeLock，所以直接断开头节点对象和 head 变量关联，并将 head 变量关联到原来头节点的 next 节点即可。

```java
private E dequeue() {
    // assert takeLock.isHeldByCurrentThread();
    // assert head.item == null;
    Node<E> h = head;
    Node<E> first = h.next;
    h.next = h; // help GC
    head = first;
    E x = first.item;
    first.item = null;
    return x;
}
```

和 `signalNotEmpty()` 一样的道理，在 `signalNotFull()` 中相应的也需要获取 putLock 才能调用 `notFull.signal()` 方法：

```java
    private void signalNotFull() {
        final ReentrantLock putLock = this.putLock;
        putLock.lock();
        try {
            notFull.signal();
        } finally {
            putLock.unlock();
        }
    }
```

### LinkedBlockingDeque

LinkedBlockingDeque 也是一个阻塞队列，和 LinkedBlockingQueue 不同的是，LinkedBlockingDeque 是基于一个双向链表实现，而 LinkedBlockingQueue 是基于一个单向链表实现的。

**因为单向链表只有前一个节点对后一个节点的单向引用，所以 LinkedBlockingQueue 是从链表的 head 出队，tail 入队，而 LinkedBlockingDqueu 因为前一个节点和后一个节点之间相互都有引用，所以出队和入队都可以选择链表的任意一边进行。**

### 总结

* LinkedBlockingQueue 底层使用一个单向链表实现。
* 为了提高并发度，put 和 take 操作各维护了一个 ReentrantLock 锁。
* take 和 take 互斥，put 和 put 操作互斥，但是 take 和 put 操作不互斥。
* 为了记录队列中的元素个数，同时也是因为 put 和 take 各持一把锁不互斥，所以单独维护了一个 AtomicInteger 类型的变量来记录元素个数，以判断队列是满还是空队列。

## PriorityBlockingQueue

PriorityBlockingQueue，优先级队列，入队和出队顺序并不是按照先后顺序，而是根据每一个 Node 的优先级做排序，所以每一个优先级队列还需要维护一个 Comparator 接口来支持排序功能。

PriorityBlockingQueue 的数据结构是基于一个数组实现的最小二叉堆，堆顶元素便是要出队的元素，队列可以指定一个初始化的大小，如果不指定，默认是 11，当队列满了之后再进行扩容，所以 ProrityBlockingQueue 的 put 操作和其他队列不一样，不会阻塞，因为 put 不需要阻塞，所以也不需要像 LinkedBlockingQueue 那样维护两个锁，PriorityBlockingQueue 只维护了一把锁，主要是在进行 take 操作时使用。

```java
public class PriorityBlockingQueue<E> extends AbstractQueue<E>
    implements BlockingQueue<E>, java.io.Serializable {

    private transient Object[] queue;

    private transient int size;

    private transient Comparator<? super E> comparator;

    private final ReentrantLock lock;

    private final Condition notEmpty;

    public PriorityBlockingQueue() {
        this(DEFAULT_INITIAL_CAPACITY, null);
    }

    public PriorityBlockingQueue(int initialCapacity, Comparator<? super E> comparator) {
        if (initialCapacity < 1)
            throw new IllegalArgumentException();
        this.lock = new ReentrantLock();
        this.notEmpty = lock.newCondition();
        this.comparator = comparator;
        this.queue = new Object[initialCapacity];
    }
}
```

### 入队
```java
    public void put(E e) {
        offer(e); // never need to block
    }

    public boolean offer(E e) {
        if (e == null)
            throw new NullPointerException();
        final ReentrantLock lock = this.lock;
        lock.lock();
        int n, cap;
        Object[] array;
        while ((n = size) >= (cap = (array = queue).length))
            tryGrow(array, cap);
        try {
            Comparator<? super E> cmp = comparator;
            if (cmp == null)
                siftUpComparable(n, e, array);
            else
                siftUpUsingComparator(n, e, array, cmp);
            size = n + 1;
            notEmpty.signal();
        } finally {
            lock.unlock();
        }
        return true;
    }
```
put 方法直接调用了 offer 方法，在最开始就讲过 offer 这个方法不会阻塞，一般的队列如果满了会返回 false 而已，但是 PriorityBlockingQueue 的做法不是这样的。

1. 获取锁对象，这里获取锁，是为了线程安全。
2. 判断当前队列中的元素个数是否和队列当前的容量相等，如果相等，说明队列已经满了，调用 tryGrow() 方法进行扩容。
3. 如果 comparator 对象为 null，调用 siftUpComparator() 方法，使用默认的比较器比较后入队。
4. 如果 comparator 对象不为 null，调用 siftUpUsingComparator() 方法，使用指定的比较器比较后入队。
5. 入队后 size 加 1，并通过 notEmpty.signal() 方法唤醒 take 操作的线程。
6. 解锁。

需要注意的是，扩容的时候，如果当前容量小于 64，那么原来的容量加 2 即是扩容后的容量，如果原来的大于等于 64，就增加原来容量的一半，容量的上限为 `Integer.MAX_VALUE - 8`。

### 出队

```java
    public E take() throws InterruptedException {
        final ReentrantLock lock = this.lock;
        lock.lockInterruptibly();
        E result;
        try {
            while ( (result = dequeue()) == null)
                notEmpty.await();
        } finally {
            lock.unlock();
        }
        return result;
    }
```

1. 获取锁，响应中断。
2. 调用 dequeue() 方法出队。
3. 如果 dequeue() 返回结果是 null，说明当前队列是空队列，调用 notEmpty.await() 方法阻塞当前线程，等待唤醒。
4. 解锁。

### 总结

* PriorityBlockingQueue 默认大小为 11，容量上限为 `Integer.MAX_VALUE - 8`。
* 因为满了会自动扩容，容量上限其实很大，所以其实是一个无界队列。
* 每次扩容，如果当前容量小于 64，扩容后比原来多 2 的容量，如果大于等于 64，扩容后比原来多一般容量，当达到容量上限后，会抛出 `OutOfMemoryError`。
* 因为存在自动扩容机制，所以一般不存在队列慢的情况，所以 put 操作不会阻塞，take 操作依然会因为队列为空而在 notEmpty 上阻塞。

## DelayQueue

DelayQueue，延迟队列，和 PriorityBlockingQueue 一样，不是严格按照入队顺序出队，而是为每一个元素设置过期时间，只有过期的元素才能出队。

```java
public class DelayQueue<E extends Delayed> extends AbstractQueue<E>
    implements BlockingQueue<E> {

    private final transient ReentrantLock lock = new ReentrantLock();
    private final PriorityQueue<E> q = new PriorityQueue<E>();
    // 正在等待出队的线程
    private Thread leader = null;
	private final Condition available = lock.newCondition();
    
    public DelayQueue() {}
```

查看源码发现，DelayQueue 其实就是基于 PriorityQueue （不是 PriorityBlockingQueue）实现的，这是一个普通的优先级队列，而且队列的每一个元素都实现了 Delayed 接口。

```java
public interface Delayed extends Comparable<Delayed> {
    long getDelay(TimeUnit unit);
}
```

Delayed 接口继承了 Comparable 接口，Comparable 接口提供比较优先级的方法，初始化 PriorityQueue 时没有指定 Comparator，所以在 ProrityQueue 中使用了队列元素自己的 `compareTo()` 方法比较优先级，而 Delayed 接口提供的 `getDelay()` 方法则是获取队列元素到期时间，以判断是否过期。

### 入队

```java
    public void put(E e) {
        offer(e);
    }

    public boolean offer(E e) {
        final ReentrantLock lock = this.lock;
        lock.lock();
        try {
            q.offer(e);
            if (q.peek() == e) {
                leader = null;
                available.signal();
            }
            return true;
        } finally {
            lock.unlock();
        }
    }
```

与 ProrityBlockingQueue 类似，DelayQueue 的 `put()` 方法也是直接调用的 `offer()`  方法。

1. 获取锁。
2. 调用 `PriorityQueue.offer()` 入队。
3. 通过 `PriorityQueue.peek()` 获取队尾元素。
4. 比较队尾元素和刚入队的元素是否相等，如果相等，说明新元素的超时时间是最小的，在小顶堆的堆顶，将 leader 变量置空（需要结合下面的出队操作来理解），`leader` 是正在等待出队的线程，然后通过 available.signal() 唤醒线程。
5. 解锁。

### 出队

```java
    public E take() throws InterruptedException {
        final ReentrantLock lock = this.lock;
        // 获取锁，响应中断
        lock.lockInterruptibly();
        try {
            for (;;) {
                // 获取队头节点
                E first = q.peek();
                // 如果头节点是 null，说明队列是空的
                if (first == null)
                    // 阻塞线程等待有新元素入队后唤醒
                    available.await();
                else {
                    // 如果头节点不为空
                    // 获取头节点剩余延迟时间
                    long delay = first.getDelay(NANOSECONDS);
                    if (delay <= 0)
                        // 已经过期，直接出队
                        return q.poll();
                    // 时间还没有过期，线程还需要等待，防止干扰 gc, 这里断开引用
                    first = null; // don't retain ref while waiting
                    if (leader != null)
						// 如果 leader 不为 null，说明已经有线程在等待了，所以这里直接无限期阻塞
                        available.await();
                    else {
                        // leader 为 null，设置当前线程为 leader
                        Thread thisThread = Thread.currentThread();
                        leader = thisThread;
                        try {
                            // 等待 delay 的毫秒数，因为前面计算出头节点还有 delay 毫秒过期
                            available.awaitNanos(delay);
                        } finally {
                            // 重新将 leader 置空
                            if (leader == thisThread)
                                leader = null;
                        }
                    }
                }
            }
        } finally {
            if (leader == null && q.peek() != null)
				// 如果 leader 为 null，但是 q.peek() 不为 null，说明队列不是空的，通过 available.signal() 方法通知其他的 take() 线程
                available.signal();
            // 解锁
            lock.unlock();
        }
    }
```

1. 获取锁。
2. 获取头节点，如果头节点为 null，说明队列是空的，就无限期阻塞，等待其他线程 `put()` 的时候唤醒。
3. 如果头节点不为 null，此时还需要查看该节点是否已经超时，只有时间已经过期的才可以出队。
4. 如果已经过期，直接出队。
5. 如果没有过期，查看 leader 是否为 null，如果不为 null，说明已经有其他的线程在等待，直接无限期阻塞，等待 `put()` 唤醒；如果 leader 为 null，则当前线程的 Thread 对象赋值给 leader，并通过 `available.awaitNanos()` 阻塞当前线程 `delay` 毫秒，这里的 `delay` 就是前面拿到的头节点剩余的超时时间。
6. 当线程在 delay 毫秒后或者中途被 `put()` 唤醒，会将 leader 置空，进行新一轮出队循环逻辑。
7. 最终，出队成功后，如果 leader 为 null，并且队列不为空，也就是 `q.peek()!=null`，就通过 available.signal() 唤醒其他的 take() 线程。
8. 解锁。

这里面还有一个细节，就是当发现头节点还没有超时的时候，将 first 变量于头节点的引用断开，我的理解是：

> 这是防止当其他线程将该节点出队之后，因为这个线程的 first 变量还引用着这个已经出队的节点，导致这个节点在 gc 的时候不能有效的回收。

### 总结

* DelayQueue 是基于 PriorityQueue 优先级队列实现的。
* 因为优先级队列是无界队列，所以 DelayQueue 也是无界队列，所以 DleayQueue 的 `put()` 方法不会阻塞。
* DelayQueue 的 `take()` 操作在队列是空时会阻塞。
* DelayQueue 的 `take()` 操作在队列的头节点还没有超时的情况下也会阻塞。
* 增加 leader 变量来记录第一个在 take() 上阻塞着的线程，因为能够明确知道还需要多久头节点就可以出队，所以 leader 变量所指向的线程不会无限期阻塞，而是阻塞一段时间后自动唤醒。因为 `Condition.awaitNanos(long delay)` 会释放当前线程持有的锁，所以当线程在阻塞 delay 毫秒的过程中，可能也有其他线程调用 `put()` 操作产生了新的头节点，所以在这 delay 毫秒内，leader 变量指向的线程可能会变，因为头节点变了，所以当 `Condition.awaitNanos(long delay)` 返回后，又开启了新的循环获取新的头节点尝试出队。
