---
title: Java内存模型
date: 2021-04-01 12:00:00
tags: Java
categories: 多线程技术
cover: http://image.hanelalo.cn/image/20220401111755.jpg
---

> 发现我的博客竟没有专门将整个的文章，不得不当一次缝合怪，结合《Java并发编程的艺术》和网络大神的文章做总结。

> JMM 也就是 Java 内存模型，和 JVM 内存区域划分是两回事。

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
  
  

> 字节码指令参考链接：https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-6.html

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

#### as-if-serial 语义

保证单线程下不会影响程序执行结果，才会进行指令重排序，比如上面的例子，因为执行 init() 方法的进程认为重排序不会影响当前线程的执行结果，所以就进行了重排序。

#### 禁止重排序

为了保证多线程环境下的正确性，通过内存屏障指令来禁止指令重排序，在 Java 这种语言里面，为了方便开发人员使用内存屏障，又指定了一些 happen-before 规则来供开发人员参考，而这些规则，则可以通过 volatile、synchronized、final 关键字来使用。

