---
title: Java内存模型
date: 2021-04-01 12:00:00
tags: Java
categories: 多线程技术
cover: http://image.hanelalo.cn/image/20220401111755.jpg
---

> 发现我的博客竟没有专门将整个的文章，不得不当一次缝合怪，结合《Java并发编程的艺术》和网络大神的文章做总结。
>
> JMM 也就是 Java 内存模型，和 JVM 内存区域划分是两回事，这是容易搞混的概念。

# Java 内存模型

## Java 内存模型抽象结构

为了屏蔽不同处理器、平台之间的差异，Java 建立了一套抽象的内存模型。

![Java内存抽象结构](http://image.hanelalo.cn/image/202204011406467.svg)

每个线程都有一个自己的本地内存，当一个线程 A 访问共享变量时，会将共享变量复制一份副本到自己的本地内存中，如果要修改，也是修改的本地内存中的副本的值，当另一个线程 B 也要读取这个共享变量时，又会将 A 的本地内存中的值同步到主内存中，以保证 B 读到的是最新的值。

如果没有 JMM 的控制，就会出现 A 线程修改了本地内存的副本，但是没有同步到主内存，此时 B 线程有去主内存读取了共享变量，导致 B 拿到的不是最新的值。

## Java 并发编程必须解决的问题

Java 并发编程要解决的 3 大问题是：

1. 线程切换导致的原子性问题；
2. 处理器缓存导致了内存可见性问题；
3. 指令优化导致重排序问题；

### 线程切换导致的原子性问题

比如大家熟知的 `i++` 操作，代码只有一行，实际上分了 3 步：

1. 从内存取 i 的值；
2. 执行 +1 得到新值；
3. 将新值赋值给 i；

在多线程环境下，如果这个 i 是共享变量，因为线程切换问题，就会有问题。

> 这里的 i 既然是共享变量，那就肯定不是方法内定义的局部变量，而是类的成员变量。

下面举个例子：

```java
public class MainTest {

  private int i = 0;

  public static void main(String[] args)  {
    new MainTest().i++;
  }
}
```

编译后，用 javap 查看字节码：

```bash
$ javap -c MainTest.class
Compiled from "MainTest.java"
public class org.hanelalo.MainTest {
  public org.hanelalo.MainTest();
    Code:
       0: aload_0
       1: invokespecial #1                  // Method java/lang/Object."<init>":()V
       4: aload_0
       5: iconst_0
       6: putfield      #2                  // Field i:I
       9: return

  public static void main(java.lang.String[]);
    Code:
       0: new           #3                  // class org/hanelalo/MainTest
       3: dup
       4: invokespecial #4                  // Method "<init>":()V
       7: dup
       8: getfield      #2                  // Field i:I
      11: iconst_1
      12: iadd
      13: putfield      #2                  // Field i:I
      16: return
}
```

这里主要关注 `main` 方法对应的字节码：

```
  public static void main(java.lang.String[]);
    Code:
       0: new           #3                  // class org/hanelalo/MainTest
       3: dup
       4: invokespecial #4                  // Method "<init>":()V
       7: dup
       8: getfield      #2                  // Field i:I
      11: iconst_1
      12: iadd
      13: putfield      #2                  // Field i:I
      16: return
  }
```

* new

  创建一个新对象。

* dup

  复制顶部操作堆栈值。

* invokespecial

  调用实例化方法。

* getfield

  获取对象的字段。

* iconst_1

  后面的 1 是指令参数，将参数值 push 到操作数栈顶部。

* iadd

  `加`操作。

* putfield

  设置对象字段。

* return

  从方法返回 void。
  

可以看出，一个单纯的将累的属性值加 1 的操作，其实从获取属性值到结束一共执行了 4 条指令，这个过程中，多线程环境下，执行到中间某个指令时发生线程切换也是有可能的。

比如下面的代码：

```java
public class MainTest {

  private static int count = 0;

  public static void main(String[] args) throws InterruptedException {
    Thread t1 = new Thread(() -> {
      for (int i = 0; i < 100000; i++) {
        count++;
      }
    });
    Thread t2 = new Thread(() -> {
      for (int i = 0; i < 100000; i++) {
        count++;
      }
    });
    t1.start();
    t2.start();
    t1.join();
    t2.join();
    System.out.println(count);
  }
}
```

执行结果：

```
142862
```

此时就有可能出现问题：A、B 两个线程对 i 字段进行加 1 操作，初始值为 1，当 A 线程对 i 进行 i已经执行了 iadd，但是还没执行 putfield，切换到了 B 线程，B 线程直接完成了所有字节码操作，此时 i 等于 2，然后 A 线程继续执行，因为 iadd 之后也等于 2，所以执行 putfield 之后，i 还是等于 2，但是两个线程各加 1，最后期望的结果应该是 3 才对，所以上面的代码执行后的实际结果并不是 200000。

这就是线程切换带来的原子性问题。

### 处理器缓存导致了内存可见性问题

现代的处理器，在 CPU 核心跟内存之间还隔了 L1、L2、L3 一共 3 级的缓存，这三个越往后，离处理器核心越远，缓存空间越大（相对来讲比较大，和内存、硬盘等硬件比起来，不管哪一级缓存都小的可怜），访问速度越慢，但肯定比内存快很多倍。

这里的 L1、L2、L3 可以理解为 JMM 抽象模型中的本地内存，每个线程访问共享变量时，都会复制到缓存中，修改时，也是修改的缓存中的副本，然后再同步到主内存。

在单个 CPU 的机器上自然是没问题的，因为所有线程用的都是同一个 CPU 缓存，但是在拥有多个 CPU 的机器上，难免发生多个线程分布在多个不同的 CPU 上执行，每个线程只能看见自己 CPU 的缓存内容，其他 CPU 缓存中的改动是看不见的，这就是多线程情况下的内存可见性的问题。

其实上一节举的`i++` 的例子，最终结果不是 200000，也有可能是这个原因。

### 指令优化导致重排序问题

现代的编译器和处理器，为了提升程序性能，会允许指令不按照源代码的顺序执行，甚至有些还会并行执行，这便是指令优化，也就是指令重排序。

指令重排序，分为 2 大类，3小类：

* 编译器指令重排序

  编译器在保证不影响单线程执行结果的情况下，允许改变指令执行顺序。

* 处理器指令重排序

  * 指令集并行重排序

    现代处理器采用了指令并行执行技术，在没有数据依赖时，允许多条指令并行执行。

  * 内存级重排序

    因为有些处理器使用了写缓冲区，导致读/写操作看起来像是乱序执行。

下面举一个简单地例子说明一下。

```java
public class Main {
     private static int value;
     private static boolean flag;
     public static  void  init(){
         value=8;
         flag=true;
     }

     public static void getValue(){
         if(flag){
             System.out.println(value);
         }
     }
}
```

试想现在有两个线程，分别调用 init() 方法和 getValue() 方法，正常来讲，如果 getValue() 有输出值，那就应该是 8，但其实有可能依然是 0，为什么呢？

因为 `value=8` 和 `flag=true` 可能会发生指令重排序，先执行 `flag=true` 然后执行 `value=8`，此时对调用 getValue() 的线程来讲，就可能会出现 `flag=true` 但是 `value=0` 的情况。

> 经典的有双重检测机制的单例写法中，就考虑到了指令重排序带来空指针问题，使用 volatile 关键字解决。

## 原子性问题解决方案

为了解决多线程切换带来的原子操作问题，Java 提供了一系列原子操作类，比如 AtomicInteger，原理上，都是基于 CAS（Compare And Swap）来解决问题。

## CPU 缓存带来的内存可见性问题解决方案

### 基于总线的一致性解决方案

![总线解决方案](http://image.hanelalo.cn/image/202204041026988.svg)

CPU 都通过总线和内存进行通信，CPU 想要读写数据，就必须发起一个总线事务来从内存读写。

#### 总线嗅探

当有一个 CPU 通过总线修改了共享数据时，如何保证其他的 CPU 缓存中的缓存失效呢？

只需要在一个 CPU 修改共享数据时，通知其他 CPU 将自己缓存中的目标缓存行失效即可，后续再读取数据，因为缓存中数据已经过期，就得从内存中获取最新的数据，这种机制就是总线嗅探。

1. CPU1 修改缓存数据后发起总线事务，想要同步数据到主内存。
2. 其他 CPU 收到缓存行失效的消息，将对应的缓存行标记为失效后响应。
3. 同步新的数据到内存。

这样，就保证了可见性，即当 CPU1 修改了某个数据后，CPU2 读取到的是最新的修改后的值。

#### 总线仲裁

前面的总线嗅探是基于两个 CPU 一读一写的情况，那如果多个 CPU 都要写呢？或者说，如果多个 CPU 同时发起总线事务时，要如何应对？

如果多个 CPU 之间对共享变量的操作顺序不可控，还会导致一致性问题问题。对于这种并发操作，要保证正确性，最容易想到的就是加锁，也确实是这样，只有当前面一个总线事务释放了锁，后面的总线事务才能获取到锁。

这种机制就是总线仲裁，当发起多个总线事务发起时，由总线仲裁决定谁获得总线使用权。

#### 总线的性能问题及优化

通过前面的讲解，不难发现，不过多少个线程，总线仲裁在一个时刻最终只会允许一个总线事务执行，这并发度就不高了，也就是说如果 8 个 CPU，每个时刻其实都有 7 个 CPU 闲着的，因为总线不让跑（经典的 1 核有难，7 核围观）。

这里的性能问题就在于 CPU 要通过总线和内存进行交互，保证 CPU 之间的可见性。

那如果减少总线和内存的交互呢？那就少了很多总线仲，性能不就提升了，这种优化主要分读写两方面：一方面要减少对主内存的读操作；一方面减少 CPU 写缓存之后同步到内存的操作。

##### 减少总线对主内存的读操作

1. 当一个 CPU1 发起读操作时，如果自己的缓存里没有有效的缓存，就发起一个总线事务读取数据。
2. 总线首先不直接和内存交互，而是给其他 CPU 发送消息询问是否有相应的有效的缓存。
3. 其他 CPU 如果有，那就直接复制该缓存行，通过总线传给 CPU1。
4. 如果没有，总线再和内存交互读取数据。

##### 减少修改数据后同步缓存到内存的写操作

如果只有一个线程，其实没必要做这次同步，因为不管内存还是缓存中的数据都只有自己一个线程使用。

如果是多线程情况下，也没必要每次修改都立马同步到内存，因为可能后面还会修改，而且可能在 n 次修改后，才会有其他线程会读取同一个共享变量，那么就会有 n-1 次的同步都是没必要的。

所以解决方案是：修改缓存后，不立马同步到内存，而是等到其他线程也发起了该共享变量的读取时，才同步，数据也从独占变成共享。

#### MESI 缓存一致性协议

对于上面的总线解决方案，业界已经有很多实现，比如 MESI、MESOI、MSI，其实都是通过给缓存行设置不同状态标识来实现的。

MESI 协议为 CPU 缓存中的数据规定了 4 中标识：

* M：Modified，已被修改，该缓存有效，缓存中的数据已经被修改，和其他 CPU 的缓存中数据不一致。
* E：Exclusive，独占，该缓存有效，且不存在于其他 CPU 的缓存中。
* S：Shared，共享，该缓存有效，且和其他 CPU 缓存数据一致。
* I：Invalid，该缓存无效。

一个简单地状态流转例子：

1. 当 CPU1 先读取了变量 A 到自己的缓存中时，该缓存行是 E 状态，因为只有 CPU1 的缓存中有 A；

2. 当 CPU2 也读取了变量 A 到自己的缓存中时，CPU1、CPU2 中缓存行状态都变为 S；

3. 当 CPU1 修改了缓存中的 A 变量时，CPU1 中缓存行状态从 S 变为 M，CPU2 收到缓存无效化的消息后，CPU2 中相应的缓存行状态从 S 变为 I；

4. 当 CPU2 再次发起 A 的读取请求，自己的缓存无效，需要发起总线事务，CPU1 中的缓存同步到内存，状态从 M 变为 S，CPU2 拿到新值，缓存行状态从 I 变为 S；

#### MESI 协议优化

##### 写缓冲区 Store Buffer

在上一节的状态流转的例子中，当 CPU1 修改变量 A 时，因为 A 处于共享状态，所以不能直接修改，还需要通知 CPU2 将自己的缓存失效，当 CPU1 收到 CPU2 已经将缓存失效的 ACK 之后，才会真的修改自己缓存中的数据。

那么，当 CPU2 还没响应的这段时间，CPU1 就只能等着，CPU 是很快的，这一点点时间也是一种浪费，所以有些处理器增加了写缓冲区，先把新的数据放在写缓冲区中，在 CPU2 还没响应的这段时间继续执行其他指令，等收到 CPU2 的响应后再将写缓冲区的改动同步到缓存中。

> 这也是在指令重排序中写缓冲区会导致内存指令重排序的原因。

##### 存储转发 Store Forward

当 CPU1 将变量 A 的改动写到写缓冲区后，继续执行后续的指令，如果在 CPU2 响应之前，CPU1 又执行了指令读取 A，这时就会先读取写缓冲区中的值，而不是直接读缓存，这就是存储转发。

##### 无效化队列 Invalidate Queue

还是前面讲的例子，如果 CPU2 正在执行指令，突然收到缓存失效的消息，如果立马就处理该消息，将缓存行标记为 I，然后响应，那么当这种操作比较频繁时，也是比较耗费性能的，因为可能这个缓存是否失效短期内并不影响，为何不等空闲时再处理呢？

所以，CPU2 选择收到消息后，将消息扔到一个队列中，然后立马响应，等到空闲时，再来处理队列中的缓存失效的消息，这个队列，就是无效化队列。

#### MESI 性能优化带来的问题

MESI 性能优化加入了写缓冲区和无效化队列两种技术，在没引入之前，虽然有性能问题，但 CPU 之间的缓存数据还是能保持一致的，而引入之后，有些步骤变成异步操作，就变成了弱一致性。

这也是 JMM 要解决的并发问题。

## 重排序问题解决方案

为了保证多线程环境下的正确性，通过内存屏障指令来禁止指令重排序，在 Java 这种语言里面，为了方便开发人员使用内存屏障，又指定了一些 happen-before 规则来供开发人员参考，而这些规则，则可以通过 volatile、synchronized、final 关键字来使用。

> 需要知道，内存级重排序的原因是使用了写缓冲区，而内存屏障也是用来弥补写缓冲区带来的问题的。

### happen-before 规则

JMM 制定了一系列隐式的和需要显式使用的 happen-before 规则。

* 程序顺序规则

  一个线程的任意操作，happen-before 于该线程中的任意后续操作。

* 监视器锁规则

  对于一个锁的解锁，happen-before 于对这个锁的加锁。

* volatile 变量规则

  对一个 volatile 域的写，happen-before 于对 volatile 域的读。

* 传递性

   A happen-before 于 B，B happen-before 于 C，那么 A happen-before 于 C。

* start() 规则

  线程的 Thread.start() happen-before 于线程中的任意操作。

* join() 规则

  如果线程 A 执行 ThreadB.join() 成功返回，那么 ThreadB 中的任意操作 happen-before 于 A 中执行 ThreadB.join() 之后的任意操作。

happen-before 规则为了方便开发者理解而制定的，每一个 happen-before 规则后面可能是通过编译器和处理器禁止多种重排序的规则实现的。

参考《Java并发编程的艺术》中的图：

![happen-before](http://image.hanelalo.cn/image/202204041144789.svg)

### as-if-serial 语义

保证单线程下不会影响程序执行结果，才会进行指令重排序，比如上面的例子，因为执行 init() 方法的进程认为重排序不会影响当前线程的执行结果，所以就进行了重排序。

## 内存屏障

内存屏障是为了禁止一些指定位置的重排序而采用的技术，分为 Load Barrier 和 Store Barrier，同时也保证了 CPU 修改了共享数据能被其他线程及时感知到数据变动。

下面结合前面讲到的无效化队列和写缓冲区讲解。

### Load Barrier

读屏障，强制所有在 load barrier 之后的 load 指令，都在 load barrier 指令后执行，并一直等到 load 缓冲区被该 CPU 读完才能执行该 load 指令。

也就是说，读屏障指令和 load 指令不会重排序，且读屏障会强制 CPU 将无效化队列中的消息处理完之后再执行 load 指令。

### Store Barrier

写屏障，强制所有在写屏障指令之前的 store 指令都在写屏障指令之前执行，并把写缓冲区的数据强制写入 CPU 缓存。

也就是说，写屏障指令不会和前面的 store 指令重排序，且执行写屏障之后， CPU 写缓冲区的数据都已经同步到缓存。

## volatile 关键字

### 特性

* 可见性，对一个 volatile 变量的读，总是能看见在此之前任意线程对这个 volatile 变量的最后写入。
* 原子性，对单个 volatile 变量的读/写操作具有原子性，而对于 volatile++ 这种复合操作不具有原子性。

### volatile 原理

volatile 解决的问题是：CPU1 修改了共享变量 A 到自己的写缓冲区，紧接着 CPU2 又去读变量 A 时，因为无效化队列还没处理导致 B 线程读取的是原来的值。

这种处理方式，其实是使用了内存屏障来禁止一些重排序，并强制操作写缓冲区和无效化队列实现的。

首先看看 volatile 关键字重排序的规则：

| 第一个操作  | 第二个操作  | 是否能重排序 |
| :---------: | :---------: | :----------: |
|  普通读/写  |  普通读/写  |      Y       |
|  普通读/写  | volatile 读 |      Y       |
|  普通读/写  | volatile 写 |      N       |
| volatile 读 |  普通读/写  |      N       |
| volatile 读 | volatile 读 |      N       |
| volatile 读 | volatile 写 |      N       |
| volatile 写 |  普通读/写  |      Y       |
| volatile 写 | volatile 读 |      N       |
| volatile 写 | volatile 写 |      N       |

可以看出：

* 当第二个操作是 volatile 写时，第一个操作不管是什么，都不允许重排序，该规则保证 volatile 写之前的操作不会被重排序到 volatile 写之后。
* 当第一个操作是 volatile 读时，第二个操作不管是什么，都不允许重排序，改规则保证 volatile 读之后的操作不会重排序到 volatile 读之前。
* 当第一个操作为 volatile 写，第二个操作为 volatile 读时，不允许重排序。

具体实现时，JMM 是通过插入内存屏障来实现上述的规则：

* 在每个 volatile 写之前插入一个 Store-Store 屏障。
* 在每个 volatile 写之后插入一个 Store-Load 屏障。
* 在每个 volatile 读后面插入一个 Load-Load 屏障。
* 在每个 volatile 读后面插入一个 Load-Store 屏障。

volatile 写之前加入一个 Store-Store 屏障是为了保证之前的共享变量写入已经对其他所有线程可见。

volatile 写之后加入一个 Store-Load 屏障是为了保证不会和后面的 volatile 读写重排序。

volatile 读之后加一个 Load-Load 屏障也是为了保证其他线程的写入操作对当前线程可见，也禁止 volatile 读和后面的普通读重排序。

volatile 读之后加一个 Load-Store 屏障禁止后面的普通读写重排序。

实际编译时，也会根据实际的情况选择不插入一些没必要的内存屏障。

## synchronized 关键字

### happen-before 关系

首先看一段代码。

```java
public class Main {
    
    int a = 0;
    
    public synchronized void writer() { // 1
        a++; // 2
    } // 3
    
    public synchronized void reader() { // 4
        int i = a; // 5
    } // 6
}
```

现在有两个线程 A、B 分别执行 writer()、reader。

结果都知道，因为 synchronized 使用锁对象就是当前的对象，也就是 this，所以不会有问题。

但是结合前面讲到的内存模型来讲，为什么不会出现执行 a++ 之后，reader() 方法的线程缓冲区依然是 a=0 的情况？ 

在前面讲 happen-before 时提到，锁的释放肯定 happen-before 于其他线程获取到锁，基于锁的互斥性，假设 writer() 线程先拿到锁，那么，1 happen-before 2 happen-before 3 happen-before 4 happen-before 5 happen-before 6。

也就是 2 happen-before 5，所以 2 对共享变量的修改是对 5 可见的。

### 实现原理

简单来讲其实就是，writer() 线程释放锁时，会将改动的数据刷新到主内存中，reader() 线程获取到锁时会将自己的缓存置为无效，后面就只能从内存读取新数据。

另外，Java 中的 AQS 系列的锁实现，其实核心是基于一个 volatile 修饰的 state 字段实现的，自然也就有了 volatile 相关的保证。

## final 关键字

### final 关键字重排序规则

* 在构造一个对象时，在对象的构造函数对一个 final 域的写入，跟随后将被构造对象赋值给一个变量的操作，这两者不能重排序，比如 A 对象中 b 字段是 final 修改，那么在 A 的构造函数中为 b 字段赋值的操作，跟后续将 A 的对象赋值给另一个变量 a 的操作不能重排序（毕竟先初始化 A 对象，在对 b 赋值也挺奇怪）。
* 初次读一个包含 final 域的对象引用，和随后初次读这个 final 域，这两者不能重排序，也就是说 A 对象中有 final 修饰的 b 字段，那么当要访问 `A.b` 时，肯定是先访问 A，再通过 A 访问 b，这两者不能重排序，编译器在写 final 域之后，构造函数 return 之前，会插入一个 Store-Store 屏障，保证处理器不会把 final 域的写重排序到构造函数外。。

> 个人感觉这两个规则好像很理所当然，但是计算机是机器，不是有思考的人类。

> 所以普通成员变量可能就会被重排序到构造函数 return 之后。

### 引用类型 final 域

对于 final 域的引用类型，增加了如下约束：

在构造函数内对一个 final 引用对象的成员域的写入，跟随后在构造函数外将被构造对象赋值给一个变量，这两者不能重排序。

```java
public class FinalReferenceExample {
    
    final int[] arrays;
    static FinalReferenceExample obj;
    
    public FinalReferenceExample {
        arrays = new int[1]; // 1
        arrays[0] = 1; // 2
    }
    
    public static void writerOne() { // 线程 A
        obj = new FinalReferenceExample(); // 3
    }
    
    public static void writerTwo() { // 线程 B
        obj.arrays[0] = 2; // 4
    }
    
    public static void reader() { // 线程 C
        if(obj != null) { // 5
            int tmp = obj.arrays[0]; // 6
        }
    }
    
}
```

现在如果一个线程 A 先执行 writerOne()，然后 B 在致辞那个 writerTwo()，最后 C 执行 reader()。

最终 reader() 中的 tmp 变量可能依然是 1 而不是 2。

整个过程中，因为 final 域的重排序规则，所以 1 happen-before 3，2 happen-before 3，所以 C 线程中如果 obj 不为 null，那么肯定能看见 arrays[0] 的初始值，而线程 B 虽然将 arrays[0] 改成了 2，但因内存可见性问题，可能并没有来得及同步到内存。 

# 参考链接

* 《Java 并发编程的艺术》方腾飞  魏鹏  程晓明  著
* https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-6.html
* [并发基础理论：缓存可见性、MESI协议、内存屏障、JMM](https://zhuanlan.zhihu.com/p/84500221)
