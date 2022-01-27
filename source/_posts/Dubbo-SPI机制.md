---
title: Dubbo SPI 机制
date: 2021-05-21 22:59:40
tags: Dubbo
categories: Dubbo
cover: https://hanelalo.github.io/images/202111061323558.png
---

# Dubbo SPI 机制

## 为什么需要 SPI？

其实就是为了可扩展性，比如现在写一个通用框架的代码，里面有一个 ExtensionChecker 接口，是需要使用方自行实现。

也就是说，在这个框架中是没有 ExtensionChecker 的实现类的，那要怎么在运行时拿到这个接口实现类的实例对象呢？此时就可以考虑使用 SPI (Service Provider Interface)，其实就是可以通过接口类，拿到它的实现类的实例。

## JDK SPI 机制

JDK 原生支持了 SPI 机制，只需要在 `classpath` 下的 `META-INF/services` 目录下创建一个以接口名称命名的文件即可，文件内容填写接口的实现类的路径，然后就可以通过 `ServiceLoader` 加载。

比如现在有一个 HelloService：

```java
package com.hanelalo;
public interface HelloService{
    void say(String msg);
}
```

它还有两个实现类：

```java
package com.hanelalo.impl;
public class HelloServiceOneImpl implements HelloService{
    
    @Override
    public void say(String msg){
        System.out.println("one impl, " + msg);
    }
}
```

```java
package com.hanelalo.impl;
public class HelloServiceTwoImpl implements HelloService{
    
    @Override
    public void say(String msg){
        System.out.println("two impl, " + msg);
    }
}
```

如果要加载这两个实现类，现在有两种方式，第一种，直接 `new`：

```java
HelloService one = new HelloServiceOneImpl();
HelloService two = new HelloServiceTwoImpl();
```

好像没毛病，但是，如果 HelloService 是由第三方框架提供的扩展点，而实现类的调用逻辑是写在框架内无法修改的，而 HellosService 的两个实现类是框架的使用者自己写的，所以，就第三方框架的代码而言，在编译时，是没办法知道 HelloService 还有这样两个实现类的，所以，就有了 SPI 的实现方式。

首先在 classpath 的 `META-INF/services` 目录下新建一个 `com.hanelalo.HelloService` 文件：

```java
com.hanelalo.impl.HelloServiceOneImpl
com.hanelalo.impl.HelloServiceTwoImpl
```

然后通过 ServiceLoader 加载：

```java
    ServiceLoader<HelloService> helloServices = ServiceLoader.load(HelloService.class);
    Iterator<HelloService> iterator = helloServices.iterator();
    while (iterator.hasNext()){
      iterator.next().say("hello");
    }
```

这样就将调用接口的逻辑和具体实现解耦了，这其实就是一个遵循 OCP 原则的设计，**对扩展开放，对修改封闭**。

## Dubbo 为什么自己实现 SPI？

从前面的讲解来看，JDK 原生的 SPI 机制的设计遵循了 OCP 原则，似乎很完美了。

但是，如果我要从多个实现中找到某个特定的实现，那就只能把所有实现类遍历一遍，那就可能会把大量的不需要的实现类都加载一次。

为了解决这个问题，Dubbo 自己单独实现了一套 SPI 机制，在配置文件中以 key-value 的形式，为接口的每个实现指定一个名称，key 是扩展名称，value 就是实现类的路径，这样的话，只需要加载配置文件，从 key-value 键值对中找到想要的扩展加载即可。

```properties
one=com.hanelalo.impl.HelloServiceOneImpl
two=com.hanelalo.impl.HelloServiceTwoImpl
```

针对这套 SPI 机制，Dubbo 提供了 3 个注解来辅助扩展点的加载，分别是 `@SPI`、`@Adaptive`、`@Activate`，下面将一一介绍着 3 个注解。

## ExtnsionLoader

先介绍 Dubbo 中用来加载扩展的工具类 `ExtensionLoader`，是用来加载和获取扩展实现的工具类。

先介绍一下其中比较重要的几个全局变量：

* `Holder<Object> cachedAdaptiveInstance`

  其实是用来封装某个扩展的匹配逻辑的对象，运行时动态生成这个类，这里先记住它的作用，后面讲到的时候就知道意义了，暂且叫它**扩展自适应对象**。

* `Class<?> cachedAdaptiveClass`

  它是 `cachedAdaptiveInstance` 所持有的对象的 Class 对象。

* `Map<String, Object> cachedActivates`

  @Activate 注解的扩展名和对应的实例对象，这里是拿的对象，而不是 Class，说明使用 @Activate 注解的扩展实现肯定得是无状态的。

## @SPI

```java
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE})
public @interface SPI {
    
    String value() default "";

}
```

`@SPI` 注解其实就是表示这个接口是一个扩展的接口。

```java
@SPI("simple")
public interface HelloService {
}
```

它有一个可选的参数，用来指定默认的扩展实现的名称。

## @Adaptive

```java
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface Adaptive {
    String[] value() default {};
}
```

`@Adaptive`接收一个字符串数组，这个字符串数组，其实是用来指定匹配扩展实现的参数的，这里的参数，主要来自于 URL，之前讲过，Dubbo 中 URL 是一切资源的标识，服务提供者、服务消费者、注册中心都有自己的 URL。

```java
@SPI("simple")
public interface HelloService {
  @Adaptive("impl")
  void say(String msg, URLGetter urlGetter);
}
```

上面的示例，表示这个接口的 `say()` 方法调用时，具体的扩展选择，将由 URL 中的 `impl` 参数决定。

那么，URL 从哪里来？

在参数列表里面有一个 `URLGetter`：

```java
public class URLGetter {

  private final URL url;

  public URLGetter(URL url) {
    this.url = url;
  }

  public URL getUrl() {
    return url;
  }
}
```

这个类是我自己的写的，主要就是用来提供 URL。

那么，为什么这样写，那就一定能根据 URL 匹配扩展？

在 Dubbo 中，要获取一个扩展的实现，都是通过 `ExtensionLoader` 实现，比如获取前面的 HelloService 的实现：

```java
    ExtensionLoader<HelloService> extensionLoader =
        ExtensionLoader.getExtensionLoader(HelloService.class);
    extensionLoader.getAdaptiveExtension()
        .say("hello", new URLGetter(URL.valueOf("dubbo://127.0.0.1:2030/org.hanelalo.HelloService?impl=hard")));
```

它本身就提供了一个 `getExtensionLoader(T t)` 静态方法来得到某个接口的 ExtensionLoader：

```java
    public static <T> ExtensionLoader<T> getExtensionLoader(Class<T> type) {
        if (type == null) {
            throw new IllegalArgumentException("Extension type == null");
        }
        if (!type.isInterface()) {
            throw new IllegalArgumentException("Extension type (" + type + ") is not an interface!");
        }
        if (!withExtensionAnnotation(type)) {
            throw new IllegalArgumentException("Extension type (" + type +
                    ") is not an extension, because it is NOT annotated with @" + SPI.class.getSimpleName() + "!");
        }

        ExtensionLoader<T> loader = (ExtensionLoader<T>) EXTENSION_LOADERS.get(type);
        if (loader == null) {
            EXTENSION_LOADERS.putIfAbsent(type, new ExtensionLoader<T>(type));
            loader = (ExtensionLoader<T>) EXTENSION_LOADERS.get(type);
        }
        return loader;
    }

    private static <T> boolean withExtensionAnnotation(Class<T> type) {
        return type.isAnnotationPresent(SPI.class);
    }
```

1. 判断 type 是否为 null。
2. 判断 type 是不是一个接口类
3. type 这个接口是否有扩展的注解，其实就是看它是不是有 `@SPI` 注解。 
4. 以 type 为 key，从缓存中查询是否已经创建过这个接口的 `ExtensionLoader`，如果有，直接返回，如果没有，创建后返回。

然后，通过 `extensionLoader.getAdaptiveExtension()` 方法获取到了一个封装了根据 URL 匹配扩展实现的 HelloService 的扩展自适应对象，稍微有点绕，意思就是说 `getAdaptiveExtension()` 返回的不是最终调用的扩展实现，它只是封装了匹配的逻辑，在真正调用 `say()` 这个方法的时候，才会根据 URL 中的参数来选择具体的扩展实现并调用 `say()` 方法。

现在来看看 `getAdaptiveExtension()` 的逻辑。

```java
    public T getAdaptiveExtension() {
        // 这个在前面讲过，是封装了扩展适应性逻辑的对象，第一次调用的时候，这里肯定是 null
        Object instance = cachedAdaptiveInstance.get();
        if (instance == null) {
            if (createAdaptiveInstanceError != null) {
                throw new IllegalStateException("Failed to create adaptive instance: " +
                        createAdaptiveInstanceError.toString(),
                        createAdaptiveInstanceError);
            }
            // 对 cachedAdaptiveInstance 加锁，下面的代码其实就是要实例化一个单例对象，同时也能看到这里有经典的单例模式中的双重检测
            synchronized (cachedAdaptiveInstance) {
                // 再次确认是否已经有了扩展适应性逻辑的对象
                instance = cachedAdaptiveInstance.get();
                if (instance == null) {
                    try {
                        // 创建适应性逻辑对象
                        instance = createAdaptiveExtension();
                        // 设置
                        cachedAdaptiveInstance.set(instance);
                    } catch (Throwable t) {
                        createAdaptiveInstanceError = t;
                        throw new IllegalStateException("Failed to create adaptive instance: " + t.toString(), t);
                    }
                }
            }
        }
        return (T) instance;
    }
```

明确一点，当调用 `getAdaptiveExtension()` 这个方法的时候，拿到的 ExtensionLoader 肯定是某个特定接口的扩展加载器，而 `cachedAdaptiveInstance` 这个属性所持有的对象，只在 ExtensionLoader 对象第一次调用 `getAdaptiveExtension()` 时通过字节码工具创建，后续再调用直接返回。

1. 判断 cachedAdaptiveInstance 是否为 null，如果为 null，就创建，否则直接返回即可。
2. cachedAdaptiveInstance 为 null，开始执行创建逻辑，对 cachedAdaptiveInstance 加锁，这里是单例模式双重检测开始了。
3. 再次确认 cachedAdaptiveInstance 是否为 null。
4. 创建 cachedAdaptiveInstance，最后创建出来的对象其实也是一个 HelloService 的实现类。
5. 设置 cachedAdaptiveInstance。

上面的步骤比较简单，主要在于 `createAdaptiveExtension()` 这个方法：

```java
    private T createAdaptiveExtension() {
        try {
            return injectExtension((T) getAdaptiveExtensionClass().newInstance());
        } catch (Exception e) {
            throw new IllegalStateException("Can't create adaptive extension " + type + ", cause: " + e.getMessage(), e);
        }
    }
```

`injectExtension()` 则是填充新生成类对象中的成员变量，就类似 Spring 中 bean 初始化时会装配依赖的 bean，这段逻辑不关注，知道用途就行。

`getAdaptiveExtensionClass().newInstance()` 是以字节码的方式动态创建一个类并实例化：

```java
private Class<?> getAdaptiveExtensionClass() {
    // 加载 SPI 配置文件
    getExtensionClasses();
    // 判断
    if (cachedAdaptiveClass != null) {
        return cachedAdaptiveClass;
    }
    return cachedAdaptiveClass = createAdaptiveExtensionClass();
}
```

首先通过 `getExtensionClasses()` 加载扩展实现的 Class，其实就是读取 SPI 配置文件，Dubbo 的 SPI 配置文件的位置，有三种策略，分别由 `LoadingStrategy` 接口的三个实现决定，这三个实现通过 JDK 原生的 SPI 机制加载，在 Dubbo 源码中已经有了 SPI 的配置文件。

```java
org.apache.dubbo.common.extension.DubboInternalLoadingStrategy
org.apache.dubbo.common.extension.DubboLoadingStrategy
org.apache.dubbo.common.extension.ServicesLoadingStrategy
```

这三个实现类，分别指定了三个用来放 Dubbo SPI 配置文件的地址，分别是：

* META-INF/dubbo/internal/
* META-INF/dubbo/
* META-INF/services/

加载扩展实现的 Class 的逻辑就不再展开，紧接着看看扩展适应性对象的 Class 的创建。

同样先判断 `cachedAdaptiveClass` 是否为空，如果不为空，直接返回，如果为空，就调用 `createAdaptiveExtensionClass()` 创建：

```java
    private Class<?> createAdaptiveExtensionClass() {
        // 生成代码内容
        String code = new AdaptiveClassCodeGenerator(type, cachedDefaultName).generate();
        // 获取 ClassLoader
        ClassLoader classLoader = findClassLoader();
        // 编译
        org.apache.dubbo.common.compiler.Compiler compiler = ExtensionLoader.getExtensionLoader(org.apache.dubbo.common.compiler.Compiler.class).getAdaptiveExtension();
        return compiler.compile(code, classLoader);
    }
```

这里更关注生成的类的内部逻辑是什么，我专门 Debug 把 `code` 给 copy 了出来。

```java
package org.hanelalo;

import org.apache.dubbo.common.extension.ExtensionLoader;

public class HelloService$Adaptive implements org.hanelalo.HelloService {

  public void say(java.lang.String arg0, org.hanelalo.impl.URLGetter arg1) {、
    // 参数检查
    if (arg1 == null)
      throw new IllegalArgumentException("org.hanelalo.impl.URLGetter argument == null");
    if (arg1.getUrl() == null)
      throw new IllegalArgumentException("org.hanelalo.impl.URLGetter argument getUrl() == null");
    // 获取 URL, 用于后续匹配逻辑
    org.apache.dubbo.common.URL url = arg1.getUrl();
    // 获取 URL 中的 impl 参数值
    String extName = url.getParameter("impl", "simple");
    // 检查 URL 中 impl 字段是否为 null
    if (extName == null)
      throw new IllegalStateException(
          "Failed to get extension (org.hanelalo.HelloService) name from url ("
              + url.toString()
              + ") use keys([impl])");
    // 通过扩展名拿到扩展实现
    org.hanelalo.HelloService extension =
        (org.hanelalo.HelloService)
            ExtensionLoader.getExtensionLoader(org.hanelalo.HelloService.class)
                .getExtension(extName);
    // 调用 say() 方法
    extension.say(arg0, arg1);
  }
}
```

1. 参数检查，这里主要是针对可以获取 URL 的参数做检查。
2. 获取 URL。
3. 解析 URL 中的 impl 参数的值，这里到底应该解析哪个参数的值，其实是由 @Adaptive 注解的内容决定，在 Helloservice 中我们指定了解析 impl 这个参数。
4. 检查 impl 参数的值 extName 是否为 null，如果是 null，直接抛异常。
5. 如果 extName 不为 null，那么就可以尝试通过 extName 获取扩展实现的实例对象，这里是调用 `ExtensionLoader.getExtension(String extName)` 来实现。
6. 调用 `say()` 方法。

逻辑其实还是挺简单，那么 `@Adaptive` 的原理就算是讲完了。

讲个题外话，在 Dubbo 里面，当调用 `getExtension(String extName)` 时，如果扩展接口有包装类的实现，会返回一个包装类的实例，包装类中有目标扩展实例的引用。而判断接口的实现类是不是包装类的逻辑，以 HelloService 为例，如果它有一个实现类的构造函数的入参就是 HelloService 类型，就认为它是 HelloService 的包装类。

```java
public class HelloServiceWrapper implements HelloService {
    
    private HelloService instance;
    
    public HelloServiceWrapper(HelloService instance) {
        // 包装类逻辑
    }
    
  	public void say(String msg, URLGetter urlGetter){
        // ...
    }  
}
```

## @Activate

```java
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface Activate {
	// 分组
    String[] group() default {};
	// 和 @Adaptive 的参数作用一样，通过 URL 特定参数选择实现
    String[] value() default {};

    @Deprecated
    String[] before() default {};

    @Deprecated
    String[] after() default {};
	// 优先级
    int order() default 0;
}
```

和 `@Adaptive` 不同的是 `@Activate` 多了 group 属性和 order 属性，group 属性是扩展的分组，order 属性用来做排序用，并且 `@Activate` 的 value 属性虽然也是 URL 中的匹配参数，但是并不是用属性值来匹配扩展，而是只要 value 中指定的参数在 URL 中存在，扩展就可以激活。

`@Activate` 注解的扩展，一般都是通过 `ExtensionLoader.getActivateExtension()` 来获取：

```java
List<T> getActivateExtension(URL url, String[] values, String group)
```

从方法的定义可以看出，这里其实返回的是一个 List，所以可以猜测根据 `@Activate` 的 order 属性排序，其实就是对返回的这个 List 排序。

接下来看看 `getActivateExtension()` 方法的具体实现。

```java
    public List<T> getActivateExtension(URL url, String[] values, String group) {
        List<T> activateExtensions = new ArrayList<>();
        // 初始化一个 TreeMap，通过 @Activate order 属性排序
        TreeMap<Class, T> activateExtensionsMap = new TreeMap<>(ActivateComparator.COMPARATOR);
        List<String> names = values == null ? new ArrayList<>(0) : asList(values);
        // 加载 group 和 value 能匹配上，但是 names 中没有配置或没有以 - 的形式排除的扩展
        if (!names.contains(REMOVE_VALUE_PREFIX + DEFAULT_KEY)) {
            // 加载扩展 Class,这里也会将 @Activate 注解的实现放到 cachedActivates 中
            getExtensionClasses();
            for (Map.Entry<String, Object> entry : cachedActivates.entrySet()) {
                // 扩展名称
                String name = entry.getKey();
                // @Activate 注解实例
                Object activate = entry.getValue();

                String[] activateGroup, activateValue;

                if (activate instanceof Activate) {
                    // @Activate 注解 group 属性值
                    activateGroup = ((Activate) activate).group();
                    // @Activate 注解 value 属性值
                    activateValue = ((Activate) activate).value();
                } else if (activate instanceof com.alibaba.dubbo.common.extension.Activate) {
                    // 针对 Dubbo 移交 apache 以前得遗留代码得处理，不管，挺 sb 的
                    activateGroup = ((com.alibaba.dubbo.common.extension.Activate) activate).group();
                    activateValue = ((com.alibaba.dubbo.common.extension.Activate) activate).value();
                } else {
                    continue;
                }
                // 匹配 group 属性，如果方法参数中的 group 为空，返回 true
                if (isMatchGroup(group, activateGroup)
                        // 配置中不包含该扩展名
                        && !names.contains(name)
                        // 没有在配置中明确排除扩展名，认为 - 后面接扩展名是不激活该扩展的意思
                        && !names.contains(REMOVE_VALUE_PREFIX + name)
                        // 通过 value 属性和 URL 判断该扩展是否需要激活
                        && isActive(activateValue, url)) {
                    activateExtensionsMap.put(getExtensionClass(name), getExtension(name));
                }
            }
            // 添加默认激活的扩展实现
            if(!activateExtensionsMap.isEmpty()){
                // 此时拿到的是已经通过 order 排序过的结果
                activateExtensions.addAll(activateExtensionsMap.values());
            }
        }
        List<T> loadedExtensions = new ArrayList<>();
        // 开始加载 names 中指定配置的扩展
        for (int i = 0; i < names.size(); i++) {
            String name = names.get(i);
            // 以 - 开头直接跳过
            if (!name.startsWith(REMOVE_VALUE_PREFIX)
                // 这是一个防痴呆的设计，就是害怕出现names是 ext1,-ext1 这种情况，此时排除 ext1
                    && !names.contains(REMOVE_VALUE_PREFIX + name)) {
                // 如果 name 是 default
                if (DEFAULT_KEY.equals(name)) {
                    // 这里个判断导致如果 default 是 names 中的第一个会被忽略
                    if (!loadedExtensions.isEmpty()) {
                        // 头插法将默认的扩展实现实例插入
                        activateExtensions.addAll(0, loadedExtensions);
                        loadedExtensions.clear();
                    }
                } else {
                    loadedExtensions.add(getExtension(name));
                }
            }
        }
        if (!loadedExtensions.isEmpty()) {
            // 将通过 names 加载的扩展放到最后，从这里可以看出在 names 中 name 的顺序就是这些扩展的顺序
            activateExtensions.addAll(loadedExtensions);
        }
        return activateExtensions;
    }
```

> 说实话不知道为什么，感觉这段代码写的稀烂。。。

代码注释已经写的很详细了，简单说一下。

在方法的 values 参数中，以 `-` 加扩展名形式的配置，约定为要排除的扩展。加载逻辑分为两部分，首先加载 `@Activate` 的 group 参数和 value 参数能匹配上且扩展名不在 values 中的扩展实现，这部分扩展实现通过 `@Activate`  的 order 属性排序，排序逻辑在初始化 `activateExtensionsMap` 这个 `TreeMap` 的局部变量时封装在了 `ActivateComparator.COMPARATOR` 中，主要是通过 `@Activate` 的 before 、after 、order 三个属性排序，但是 before 和 after 已经废弃了，所以其实是通过 order 排序；然后通过 values 参数加载扩展实现，扩展名为 default 的实现在 values 中的优先级最高，但是如果 default 是在 values 中是第一个元素，那就会被忽略（这段逻辑有点不明白为什么），values 中扩展名的顺序也决定这些扩展的优先级，并且通过 values 加载的扩展优先级都比通过 `@Activate` 的 group 和 value 属性加载的扩展优先级低。
