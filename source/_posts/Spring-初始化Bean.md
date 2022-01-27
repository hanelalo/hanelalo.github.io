---
title: 'Spring: 初始化Bean'
date: 2021-09-24 23:10:14
tags: Spring
categories: Spring
cover: /img/top_img/di_jia.webp
---

> 题外话 1：今天，发现《迪迦奥特曼》被下架了，就比较离谱，所以封面选了迪迦。然后就是，我看了网上传的一些消息，说可能是被所谓的“家长”举报了，仿佛我国的未成年人的思想已经脆弱到连《迪迦奥特曼》、《全职高手》、《刺客伍六七》等特摄和动漫都看不了，如果这是真的，那我觉得，这样做与其说是保护，不如说是为了让未成年人以后能更容易被社会彻底摧毁，因为他们被保护的太好了，从生活的角度上讲，他们的思维从来没有过涅槃。教育，从来不是一直告诉孩子什么是对错，孩子们也需要英雄来懂得什么是正义，而不是做一个只知道语文数学英语的人工智能，家长的作用不仅是保护，还是辅助他们能够正确理解这些作品的意义，从来不会有一部作品只有正派没有反派，因为从创作的角度讲不合理，也从来不会有一部作品适合所有年龄阶段的人群，因为人的思想随着成长会发生变化。最近几年，有很多动漫被下架，不管是国产还是日漫，似乎下架原因总是和什么暴力啥的有关系，我理解那些家长对孩子的保护之心切，但是那些家长认为问题在于这些影视剧和动漫作品，我也为这些家长的愚蠢感到悲哀。我突然明白为什么《迪迦奥特曼》最后一集，变成光的都是小孩子，因为大人太蠢了。

> 题外话 2：近日，收获了爱情，我心甚喜，亦有孑然一身的彷徨。我始终相信，人是感情生物，如果感情于物质中超脱，必将堕落于物质，只有如道生一一般自然的感情，然后超脱于物质之上，才能免于物质的俗套。

# Spring: 初始化 Bean

在 Spring 里面，如果我们想获取一个 bean 的实例，不依靠依赖注入的方式，我们可以通过 `BeanFactory.getBean(String beanName)` 方法获取到 bean 的实例。

查看 Spring 容器启动的源码，在 `AbstractApplicationContext.refresh()` 方法中调用了一个 `finishBeanFactoryInitialization()` 方法，在这之前，已经将通过 xml、Java API、注解方式配置的 bean 全都解析成为了 BeanDefiniton，到这里终于开始初始化 bean 实例了。

```java
protected void finishBeanFactoryInitialization(ConfigurableListableBeanFactory beanFactory) {
 // ...
 // 实例化 bean 对象, 更多时候这里实例化的是一些业务逻辑上的 bean
 beanFactory.preInstantiateSingletons();
}
```

进入 `beanFactory.preInstantiateSingletons()`，会发现它除了各种判断之外，竟然也调用了`getBean(String beanName)`方法，看一段这里面的核心点的调用

```java
		// 获取所有的 beanName
		List<String> beanNames = new ArrayList<>(this.beanDefinitionNames);
		// Trigger initialization of all non-lazy singleton beans...
		for (String beanName : beanNames) {
            // 获取每个 beanName 对应的 RootBeanDefinition
			RootBeanDefinition bd = getMergedLocalBeanDefinition(beanName);
            // 如果 bean 不是抽象的并且是单例，且没有配置懒加载
			if (!bd.isAbstract() && bd.isSingleton() && !bd.isLazyInit()) {
                // 如果 beanName 对应的是一个 FactoryBean, 其实一般是指通过 @Bean 注解修饰的一个方法初始化的 bean
				if (isFactoryBean(beanName)) {
					Object bean = getBean(FACTORY_BEAN_PREFIX + beanName);
					if (bean instanceof FactoryBean) {
						FactoryBean<?> factory = (FactoryBean<?>) bean;
						boolean isEagerInit;
						if (System.getSecurityManager() != null && factory instanceof SmartFactoryBean) {
							isEagerInit = AccessController.doPrivileged(
									(PrivilegedAction<Boolean>) ((SmartFactoryBean<?>) factory)::isEagerInit,
									getAccessControlContext());
						}
						else {
							isEagerInit = (factory instanceof SmartFactoryBean &&
									((SmartFactoryBean<?>) factory).isEagerInit());
						}
						if (isEagerInit) {
							getBean(beanName);
						}
					}
				}
				else {
					// 通过 beanName 获取 bean 实例
					getBean(beanName);
				}
			}
		}
```

虽然分支逻辑区分了 FactoryBean 和普通的 Bean，但是最终都是调用的 getBean(String beanName) 方法，而且都没有接收它的返回值，这说明，这个方法虽然对外可以用来作为获取 bean 实例的入口，对内却也可以作为初始化 bean 的方式。

所以，bean 的初始化工作，就围绕 `getBean(String beanName)` 方法展开。getBean 这个方法直接调用了 doGetBean() 方法：

```java
	@Override
	public Object getBean(String name) throws BeansException {
		// 真正执行获取实例的方法
		return doGetBean(name, null, null, false);
	}

	protected <T> T doGetBean(
			String name, @Nullable Class<T> requiredType, @Nullable Object[] args, boolean typeCheckOnly)
			throws BeansException {
		// 处理别名或者传入的是 FactoryBean 的名字的情况
		String beanName = transformedBeanName(name);
		Object beanInstance;

		// Eagerly check singleton cache for manually registered singletons.
		// 尝试从缓存中加载单例 bean
		Object sharedInstance = getSingleton(beanName);
		if (sharedInstance != null && args == null) {
			if (logger.isTraceEnabled()) {
				if (isSingletonCurrentlyInCreation(beanName)) {
					logger.trace("Returning eagerly cached instance of singleton bean '" + beanName +
							"' that is not fully initialized yet - a consequence of a circular reference");
				}
				else {
					logger.trace("Returning cached instance of singleton bean '" + beanName + "'");
				}
			}
			// 如果拿到的是 FactoryBean，则需要拿到 factory-method 最终返回的 bean 实例
			beanInstance = getObjectForBeanInstance(sharedInstance, name, beanName, null);
		}

		else {
			// Fail if we're already creating this bean instance:
			// We're assumably within a circular reference.
			// 从单例缓存中没有找到 bean，检查是不是还在创建中，如果是，抛异常
			if (isPrototypeCurrentlyInCreation(beanName)) {
				throw new BeanCurrentlyInCreationException(beanName);
			}
			// Check if bean definition exists in this factory.
			BeanFactory parentBeanFactory = getParentBeanFactory();
			// 如果有父 BeanFactory，当前 BeanFactory 中又没有 beanName 对应的 BeanDefinition 对象，就尝试从父容器获取
			if (parentBeanFactory != null && !containsBeanDefinition(beanName)) {
				// Not found -> check parent.
				String nameToLookup = originalBeanName(name);
				if (parentBeanFactory instanceof AbstractBeanFactory) {
					return ((AbstractBeanFactory) parentBeanFactory).doGetBean(
							nameToLookup, requiredType, args, typeCheckOnly);
				}
				else if (args != null) {
					// Delegation to parent with explicit args.
					return (T) parentBeanFactory.getBean(nameToLookup, args);
				}
				else if (requiredType != null) {
					// No args -> delegate to standard getBean method.
					return parentBeanFactory.getBean(nameToLookup, requiredType);
				}
				else {
					return (T) parentBeanFactory.getBean(nameToLookup);
				}
			}
			// 如果不是只检查 bean 类型，那说明是要创建 bean，这里标签为已创建
			if (!typeCheckOnly) {
				// 这里将 BeanDefinition 的 stale 属性设置为了 true
				markBeanAsCreated(beanName);
			}

			StartupStep beanCreation = this.applicationStartup.start("spring.beans.instantiate")
					.tag("beanName", name);
			try {
				if (requiredType != null) {
					beanCreation.tag("beanType", requiredType::toString);
				}
				// 获取 merge 之后的 BeanDefinition，在最开始加载的时候，都是 GenericBeanDefinition
				// merge 其实就是转换成 RootBeanDefinition, 后续工作都基于 RootBeanDefinition 进行
				// 合并的时候，其实主要就是将原来的 GenericBeanDefinition 内容转移到 RootBeanDefinition，
				// 如果有父 BeanDefinition，也要合并到 RootBeanDefinition 中
				RootBeanDefinition mbd = getMergedLocalBeanDefinition(beanName);
				// 如果当前 BeanDefinition 是抽象的 bean，抛异常
				checkMergedBeanDefinition(mbd, beanName, args);

				// Guarantee initialization of beans that the current bean depends on.
				String[] dependsOn = mbd.getDependsOn();
				if (dependsOn != null) {
					for (String dep : dependsOn) {
						// 这里是为了避免出现 A 和 B 得初始化顺寻互相依赖，和循环依赖得注入不一样
						if (isDependent(beanName, dep)) {
							throw new BeanCreationException(mbd.getResourceDescription(), beanName,
									"Circular depends-on relationship between '" + beanName + "' and '" + dep + "'");
						}
						// 注册依赖关系
						registerDependentBean(dep, beanName);
						try {
							// 递归调用，获取依赖的 bean，这里其实主要是为了在依赖的 bean 没有创建时进行创建
							getBean(dep);
						}
						catch (NoSuchBeanDefinitionException ex) {
							throw new BeanCreationException(mbd.getResourceDescription(), beanName,
									"'" + beanName + "' depends on missing bean '" + dep + "'", ex);
						}
					}
				}

				// Create bean instance.
				if (mbd.isSingleton()) {
					// 根据 beanName 获取单例 bean, 并传入一个 BeanFactory 函数时接口的回调
					// 当 bean 不存在时，需要调用这个回调函数来创建 bean
					sharedInstance = getSingleton(beanName, () -> {
						try {
							// 当 bean 不存在时，最终会调用到这里的 creatBean 方法来创建单例 bean
							return createBean(beanName, mbd, args);
						}
						catch (BeansException ex) {
							// Explicitly remove instance from singleton cache: It might have been put there
							// eagerly by the creation process, to allow for circular reference resolution.
							// Also remove any beans that received a temporary reference to the bean.
							destroySingleton(beanName);
							throw ex;
						}
					});
					beanInstance = getObjectForBeanInstance(sharedInstance, name, beanName, mbd);
				}
				// 不是单例，判断是否是原型模式
				else if (mbd.isPrototype()) {
					// It's a prototype -> create a new instance.
					Object prototypeInstance = null;
					try {
						beforePrototypeCreation(beanName);
						prototypeInstance = createBean(beanName, mbd, args);
					}
					finally {
						afterPrototypeCreation(beanName);
					}
					beanInstance = getObjectForBeanInstance(prototypeInstance, name, beanName, mbd);
				}

				else {
					String scopeName = mbd.getScope();
					if (!StringUtils.hasLength(scopeName)) {
						throw new IllegalStateException("No scope name defined for bean ´" + beanName + "'");
					}
					Scope scope = this.scopes.get(scopeName);
					if (scope == null) {
						throw new IllegalStateException("No Scope registered for scope name '" + scopeName + "'");
					}
					try {
						// 指定 Scope 进行初始化
						Object scopedInstance = scope.get(beanName, () -> {
							beforePrototypeCreation(beanName);
							try {
								return createBean(beanName, mbd, args);
							}
							finally {
								afterPrototypeCreation(beanName);
							}
						});
						beanInstance = getObjectForBeanInstance(scopedInstance, name, beanName, mbd);
					}
					catch (IllegalStateException ex) {
						throw new ScopeNotActiveException(beanName, scopeName, ex);
					}
				}
			}
			catch (BeansException ex) {
				beanCreation.tag("exception", ex.getClass().toString());
				beanCreation.tag("message", String.valueOf(ex.getMessage()));
				cleanupAfterBeanCreationFailure(beanName);
				throw ex;
			}
			finally {
				beanCreation.end();
			}
		}
		return adaptBeanInstance(name, beanInstance, requiredType);
	}
```

1. 转换 beanName，在 Spring 中有一种 bean 叫做 FactoryBean，从名称上看，它是一种工厂 bean，事实上也是如此，它本身提供了某种 bean 的初始化能力，换句话说，它就是某个 bean 的工厂，不过这个工厂本身也托管到了 Spring 容器中，如果 beanName 前面加上一个 `&`，就能获取到相应的 FactoryBean 的实例，不加 `&` 获取到的就是 bean 的实例。
2. 从缓存中获取 bean 实例，这里涉及到 Spring 容器启动时的**三级缓存**。
3. 如果从缓存里面取到了实例，调用 `getObjectForBeanInstance()` 方法，该方法也是用来处理 FactoryBean，如果要获取的是最终的 bean 实例，那么在这里会调用 `FactoryBean.getObject()` 方法。
4. 如果从缓存中没有找到 beanName 对应的 bean 实例，判断这个 beanName 对应的 bean 是否是在创建中，如果是，就报错。这里是一个 **bean 注入的循环依赖**的问题，后面会专门讲这一点。
5. 前面几步都是在当前的 BeanFactory 的上下文中查找 bean，如果有父 BeanFactory 存在，直接调用父 BeanFactory 的 getBean() 方法获取 bean 实例。
6. 将 beanName 放到 beanFactory 的 alreadyCreated 列表中，表示这个 bean 已经在创建中了。
7. 转换 RootBeanDefinition，从上一篇 Spring 的文章来看，其实一开始加载配置时，解析出来的是 GenericDeanDefinition，现在需要再转换成 RootBeanDefinition，可以理解为一次数据拷贝，这一步拷贝的作用，我得理解是为了后面的初始化流程操作的对象统一，所以将其他所有类型的 BeanDefinition 都转换成了 RootBeanDefinition。
8. 判断 bean 是否是抽象的，如果是，抛异常。
9. 解决 bean 的初始化依赖，其实就是解决通过 `depends-on` 属性建立的 bean 初始化顺序的关系，在这里会尝试初始化 depends-on 的 bean。在这一步，如果出现了 A depends-on B、B depends-on A 的情况，就会报出循环依赖的异常。
10. 如果是单例 bean，开始创建 bean 实例。
11. 如果不是单例 bean，通过 scope 创建 bean。
12. 调用 adaptBeanInstance() 方法进行类型转换。

接下来会挑选其最终的关键步骤进行深入剖析。

## FactoryBean

FactoryBean 是 Spring 官方提供的 Bean 工厂接口。

```java
public interface FactoryBean<T> {

	@Nullable
	T getObject() throws Exception;

	@Nullable
	Class<?> getObjectType();


	default boolean isSingleton() {
		return true;
	}

}

```

* getObject() 方法用来获取 bean 实例，bean 的初始化的逻辑就在这个方法中实现。
* getObjectType() 返回 bean 类型。
* isSingleton() 返回 bean 是否为单例 bean。

FactoryBean 本身也是托管给了 Spring 容器的，它的 beanName 比正常的 beanName 多了一个 `&` 的前缀。

举个例子，现在配置了一个 FactoryBeanC，name 为 `factoryBeanC`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE beans PUBLIC "-//SPRING//DTD BEAN 2.0//EN" "https://www.springframework.org/dtd/spring-beans-2.0.dtd">

<beans>
	<bean name="c" class="org.springframework.context.support.FactoryBeanC"/>
</beans>
```

```java
public class FactoryBeanC implements FactoryBean<C> {

  @Override
  public C getObject() throws Exception {
    return new C();
  }

  @Override
  public Class<?> getObjectType() {
    return C.class;
  }

  @Override
  public boolean isSingleton() {
    return true;
  }
}

public class C {

  public void say(){
    System.out.println("I am C");
  }

}
```

然后，通过 `ClassPathXmlApplication` 加载配置文件。

```java
	@Test
	public void testFactoryBean(){
		ClassPathXmlApplicationContext ctx =
				new ClassPathXmlApplicationContext(FACTORY_BEAN_CONTEXT);
    C c = (C) ctx.getBean("c");
		c.say();
	}
```

输出结果：

```
I am C
```

然后改一下代码，在 beanName 前加一个 `&`：

```java
	@Test
	public void testFactoryBean(){
		ClassPathXmlApplicationContext ctx =
				new ClassPathXmlApplicationContext(FACTORY_BEAN_CONTEXT);
    C c = (C) ctx.getBean("&c");
		c.say();
	}
```

此时会报出一下错误：

```
java.lang.ClassCastException: class org.springframework.context.support.FactoryBeanC cannot be cast to class org.springframework.context.support.C (org.springframework.context.support.FactoryBeanC and org.springframework.context.support.C are in unnamed module of loader 'app')
```

这说明此时 getBean() 返回的是 FactoryBean 的实例。

## Spring 三级缓存

最初接触这个概念的时候，是关于 Spring 的自动注入的循环依赖。

Spring 的三级缓存，其实就是在内存中的三个 Map。

```java
	// 一级缓存，key: beanName，value: 已经初始化完成的完整的 bean 实例
	private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>(256);
	// 二级缓存，key: beanName，value：还没有完成依赖注入的 bean 实例
	private final Map<String, Object> earlySingletonObjects = new ConcurrentHashMap<>(16);
	// 三级缓存，key：beanName，value：bean 实例工厂
	private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>(16);
```

关于这三级缓存，用处主要体现在 `DefaultSingletonBeanRegistry.getSingleton()` 里面。

```java
	protected Object getSingleton(String beanName, boolean allowEarlyReference) {
		// Quick check for existing instance without full singleton lock
		// singletonObjects，一级缓存，存储 beanName 和 bean 实例对象的映射关系
		Object singletonObject = this.singletonObjects.get(beanName);
		if (singletonObject == null
				// 目标 bean 是否还在创建中
				&& isSingletonCurrentlyInCreation(beanName)) {
			// 从二级缓存中获取 bean 实例，二级缓存中的 bean 实例一般都是还没创建完成的实例
			singletonObject = this.earlySingletonObjects.get(beanName);
			if (singletonObject == null
					// 二级缓存中依然没有，如果允许提前暴露引用，就访问三级缓存
					&& allowEarlyReference) {
				// 单例模式同步双重校验
				synchronized (this.singletonObjects) {
					// Consistent creation of early reference within full singleton lock
					singletonObject = this.singletonObjects.get(beanName);
					if (singletonObject == null) {
						singletonObject = this.earlySingletonObjects.get(beanName);
						if (singletonObject == null) {
							ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
							if (singletonFactory != null) {
								// 从三级缓存中拿到 bean 的 ObjectFactory 对象，从而拿到 bean 的早期引用
								singletonObject = singletonFactory.getObject();
								// 将 bean 实例放入二级缓存
								this.earlySingletonObjects.put(beanName, singletonObject);
								// 将 beanName 和 ObjectFactory 的映射关系从三级缓存中删除
								this.singletonFactories.remove(beanName);
							}
						}
					}
				}
			}
		}
		return singletonObject;
	}
```

优先从一级缓存中获取 bean 实例，如果一级缓存中不存在，再从二级缓存中获取，最后才是从三级缓存中获取 bean 的工厂，然后调用工厂的 `getObject()` 方法获取 bean 实例。

前面提到这里涉及到 Spring 解决依赖注入的循环依赖问题，需要结合下面一步，才能更好的解释该问题。

> 为了方便理解，这里需要说明的是，启动过程中拿到的 bean 实例，可能只是刚创建的对象，内部定义的 field 可能还没有开始填充，所以需要主义的是，创建 bean 实例可以理解为调用了构造函数 new 出来的对象，而初始化是通过 new 关键字得到一个对象之后，对它的属性填充或者执行 `init-method`，或者执行 `@PostConstruct` 的逻辑。

## 创建 Bean 实例

创建 bean 实例的时候，首先调用了一个 `getSingleton(String beanName, ObjectFactory objectFactory)` 方法。

```java
					sharedInstance = getSingleton(beanName, () -> {
						try {
							// 当 bean 不存在时，最终会调用到这里的 creatBean 方法来创建单例 bean
							return createBean(beanName, mbd, args);
						}
						catch (BeansException ex) {
							// Explicitly remove instance from singleton cache: It might have been put there
							// eagerly by the creation process, to allow for circular reference resolution.
							// Also remove any beans that received a temporary reference to the bean.
							destroySingleton(beanName);
							throw ex;
						}
					});
```

需要注意的是 getSinglton() 方法的入参是一个 beanName，和一个 ObjectFactory 的函数式接口。

```java
	public Object getSingleton(String beanName, ObjectFactory<?> singletonFactory) {
		Assert.notNull(beanName, "Bean name must not be null");
		synchronized (this.singletonObjects) {
			// 检查 bean 是否已经创建
			Object singletonObject = this.singletonObjects.get(beanName);
			if (singletonObject == null) {
				if (this.singletonsCurrentlyInDestruction) {
					throw new BeanCreationNotAllowedException(beanName,
							"Singleton bean creation not allowed while singletons of this factory are in destruction " +
							"(Do not request a bean from a BeanFactory in a destroy method implementation!)");
				}
				if (logger.isDebugEnabled()) {
					logger.debug("Creating shared instance of singleton bean '" + beanName + "'");
				}
				// 设置 bean 加载状态
				beforeSingletonCreation(beanName);
				boolean newSingleton = false;
				boolean recordSuppressedExceptions = (this.suppressedExceptions == null);
				if (recordSuppressedExceptions) {
					this.suppressedExceptions = new LinkedHashSet<>();
				}
				try {
					// 调用工厂方法创建 bean
					singletonObject = singletonFactory.getObject();
					newSingleton = true;
				}
				catch (IllegalStateException ex) {
					// Has the singleton object implicitly appeared in the meantime ->
					// if yes, proceed with it since the exception indicates that state.
					singletonObject = this.singletonObjects.get(beanName);
					if (singletonObject == null) {
						throw ex;
					}
				}
				catch (BeanCreationException ex) {
					if (recordSuppressedExceptions) {
						for (Exception suppressedException : this.suppressedExceptions) {
							ex.addRelatedCause(suppressedException);
						}
					}
					throw ex;
				}
				finally {
					if (recordSuppressedExceptions) {
						this.suppressedExceptions = null;
					}
					// 创建成功后，通过 beanName 标记为已经创建
					afterSingletonCreation(beanName);
				}
				if (newSingleton) {
					// 将 beanName 和 bean 实例放到一级缓存
					addSingleton(beanName, singletonObject);
				}
			}
			return singletonObject;
		}
	}
```

首先从一级缓存里面获取 bean 的实例，如果不为 null，直接返回，如果为 null，如果为 null，也就是 bean 还没创建完成，就调用 singletonFactory.getObject() 创建 bean，在调用用 singletonFactory.getObject() 前，有一个 `beforeSingletonCreation()` 方法，将当前 beanName 放入 singletonCurrentlyInCreation 中，以表示这个 bean 正在创建中，所以 singletonCurrentlyInCreation 也就设计成了 beanFactory 中的全局变量，在创建 bean 之后调用 `afterSingletonCreation()` 又将 beanName 从 singletonCurrentlyCreation 中移除。

singletonFactory 是 getSinglton() 的函数式入参，最终调用到了 `AbstractBeanFactory.createBean()` 方法中，在 creatBean 方法中才是创建 bean 实例的主要逻辑。

```java
	protected Object createBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
			throws BeanCreationException {

		if (logger.isTraceEnabled()) {
			logger.trace("Creating instance of bean '" + beanName + "'");
		}
		RootBeanDefinition mbdToUse = mbd;

		// Make sure bean class is actually resolved at this point, and
		// clone the bean definition in case of a dynamically resolved Class
		// which cannot be stored in the shared merged bean definition.
		Class<?> resolvedClass = resolveBeanClass(mbd, beanName);
		if (resolvedClass != null && !mbd.hasBeanClass() && mbd.getBeanClassName() != null) {
			mbdToUse = new RootBeanDefinition(mbd);
			mbdToUse.setBeanClass(resolvedClass);
		}

		// Prepare method overrides.
		try {
			// 准备覆盖的方法
			mbdToUse.prepareMethodOverrides();
		}
		catch (BeanDefinitionValidationException ex) {
			throw new BeanDefinitionStoreException(mbdToUse.getResourceDescription(),
					beanName, "Validation of method overrides failed", ex);
		}

		try {
			//给BeanPostProcessor一个返回代理而不是目标 bean 实例的机会，AOP 就是在这一步实现
			Object bean = resolveBeforeInstantiation(beanName, mbdToUse);
			if (bean != null) {
				return bean;
			}
		}
		catch (Throwable ex) {
			throw new BeanCreationException(mbdToUse.getResourceDescription(), beanName,
					"BeanPostProcessor before instantiation of bean failed", ex);
		}

		try {
			// 通过 beanName BeanDefinition 创建 bean 实例
			Object beanInstance = doCreateBean(beanName, mbdToUse, args);
			if (logger.isTraceEnabled()) {
				logger.trace("Finished creating instance of bean '" + beanName + "'");
			}
			return beanInstance;
		}
		catch (BeanCreationException | ImplicitlyAppearedSingletonException ex) {
			// A previously detected exception with proper bean creation context already,
			// or illegal singleton state to be communicated up to DefaultSingletonBeanRegistry.
			throw ex;
		}
		catch (Throwable ex) {
			throw new BeanCreationException(
					mbdToUse.getResourceDescription(), beanName, "Unexpected exception during bean creation", ex);
		}
	}
```

* 首先设置了 bean 对应的 class 对象。
* resolveBeforeInstantiation() 方法在必要情况下，会返回通过动态代理处理之后的对象，有些 bean 可能本身不需要 aop 切面的增强，这一步就会返回 null。
* 调用 doCreation() 方法创建 bean 实例。

```java
	protected Object doCreateBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
			throws BeanCreationException {

		// Instantiate the bean.
		BeanWrapper instanceWrapper = null;
		if (mbd.isSingleton()) {
			instanceWrapper = this.factoryBeanInstanceCache.remove(beanName);
		}
		if (instanceWrapper == null) {
			// 创建 bean 实例
			instanceWrapper = createBeanInstance(beanName, mbd, args);
		}
		Object bean = instanceWrapper.getWrappedInstance();
		Class<?> beanType = instanceWrapper.getWrappedClass();
		if (beanType != NullBean.class) {
			mbd.resolvedTargetType = beanType;
		}

		// Allow post-processors to modify the merged bean definition.
		synchronized (mbd.postProcessingLock) {
			if (!mbd.postProcessed) {
				try {
					// mergeBeanDefinitionPostProcessor，@Autowired 注解的预解析就在这里
					applyMergedBeanDefinitionPostProcessors(mbd, beanType, beanName);
				}
				catch (Throwable ex) {
					throw new BeanCreationException(mbd.getResourceDescription(), beanName,
							"Post-processing of merged bean definition failed", ex);
				}
				mbd.postProcessed = true;
			}
		}

		// Eagerly cache singletons to be able to resolve circular references
		// even when triggered by lifecycle interfaces like BeanFactoryAware.
		// 开始解决循环依赖
		// 是否支持单例 bean 实例提前暴露，Spring 目前只解决了单例 bean 的循环依赖
		boolean earlySingletonExposure = (mbd.isSingleton() && this.allowCircularReferences &&
				isSingletonCurrentlyInCreation(beanName));
		if (earlySingletonExposure) {
			if (logger.isTraceEnabled()) {
				logger.trace("Eagerly caching bean '" + beanName +
						"' to allow for resolving potential circular references");
			}
			// 为解决循环依赖做准备，在这里将 beanName 和 bean 的对象工厂放进缓存中
			addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
		}

		// Initialize the bean instance.
		Object exposedObject = bean;
		try {
			// 填充 bean，注入各个属性值，如果依赖的 bean 没有初始化，那也会初始化依赖的 bean
			populateBean(beanName, mbd, instanceWrapper);
			// 调用初始化方法（init-method）
			exposedObject = initializeBean(beanName, exposedObject, mbd);
		}
		catch (Throwable ex) {
			if (ex instanceof BeanCreationException && beanName.equals(((BeanCreationException) ex).getBeanName())) {
				throw (BeanCreationException) ex;
			}
			else {
				throw new BeanCreationException(
						mbd.getResourceDescription(), beanName, "Initialization of bean failed", ex);
			}
		}

		if (earlySingletonExposure) {
			Object earlySingletonReference = getSingleton(beanName, false);
			if (earlySingletonReference != null) {
				// 是同一个对象，说明没有被增强
				if (exposedObject == bean) {
					exposedObject = earlySingletonReference;
				}
				else if (!this.allowRawInjectionDespiteWrapping && hasDependentBean(beanName)) {
					String[] dependentBeans = getDependentBeans(beanName);
					Set<String> actualDependentBeans = new LinkedHashSet<>(dependentBeans.length);
					for (String dependentBean : dependentBeans) {
						if (!removeSingletonIfCreatedForTypeCheckOnly(dependentBean)) {
							actualDependentBeans.add(dependentBean);
						}
					}
					// 到这里如果 actualDependentBeans 不为空，说明这个 bean 所依赖的 bean 还没有创建完，
					// 存在初始化顺序上的循环依赖
					if (!actualDependentBeans.isEmpty()) {
						throw new BeanCurrentlyInCreationException(beanName,
								"Bean with name '" + beanName + "' has been injected into other beans [" +
								StringUtils.collectionToCommaDelimitedString(actualDependentBeans) +
								"] in its raw version as part of a circular reference, but has eventually been " +
								"wrapped. This means that said other beans do not use the final version of the " +
								"bean. This is often the result of over-eager type matching - consider using " +
								"'getBeanNamesForType' with the 'allowEagerInit' flag turned off, for example.");
					}
				}
			}
		}

		// Register bean as disposable.
		try {
			// 根据 scope 注册 bean 的 destroy-method
			registerDisposableBeanIfNecessary(beanName, bean, mbd);
		}
		catch (BeanDefinitionValidationException ex) {
			throw new BeanCreationException(
					mbd.getResourceDescription(), beanName, "Invalid destruction signature", ex);
		}

		return exposedObject;
	}
```

> 这个方法，108 行，真的看的好为难。

* 如果 bean 是单例的，就需要尝试从缓存中删除 beanName 对应的 BeanWrapper。
* 调用 `createBeanInstance()` 初始化 BeanWrapper，核心逻辑，后面细讲。
* 调用 applyMergeBeanDefinitionPostProcessors() 方法，其中有一个 `AutowiredAnnotationBeanPostProcessor`，`@Autowired` 注解的预解析逻辑就在这个里面。
* 判断 bean 是否可以提前暴露，如果可以，将 beanName 和获取 bean 实例引用的逻辑映射关系放进 Spring 的第三级缓存中。
* 调用 `populateBean()` 填充属性值，这里会涉及到循环依赖的问题。
* 调用 `initialzeBean()` 方法，这里会调用 bean 配置的 `init-method`。
* 再次检查 bean 的依赖，也就是通过 `depends-on` 属性建立的初始化依赖关系。
* 调用 `registerDisposableBeanIfNecessary()` 方法，注册 bean 的 `destory-method`。

### createBeanInstance() 创建 bean 实例

```java
	protected BeanWrapper createBeanInstance(String beanName, RootBeanDefinition mbd, @Nullable Object[] args) {
		// Make sure bean class is actually resolved at this point.
		Class<?> beanClass = resolveBeanClass(mbd, beanName);

		if (beanClass != null && !Modifier.isPublic(beanClass.getModifiers()) && !mbd.isNonPublicAccessAllowed()) {
			throw new BeanCreationException(mbd.getResourceDescription(), beanName,
					"Bean class isn't public, and non-public access not allowed: " + beanClass.getName());
		}

		Supplier<?> instanceSupplier = mbd.getInstanceSupplier();
		if (instanceSupplier != null) {
			return obtainFromSupplier(instanceSupplier, beanName);
		}

		// 如果配置了工厂方法，就以工厂方法初始化
		if (mbd.getFactoryMethodName() != null) {
			return instantiateUsingFactoryMethod(beanName, mbd, args);
		}

		// Shortcut when re-creating the same bean...
		boolean resolved = false;
		boolean autowireNecessary = false;
		if (args == null) {
			// 如果有多个构造函数，需要根据参数锁定构造函数或者对应工厂方法
			synchronized (mbd.constructorArgumentLock) {
				if (mbd.resolvedConstructorOrFactoryMethod != null) {
					resolved = true;
					autowireNecessary = mbd.constructorArgumentsResolved;
				}
			}
		}
		// 如果已经解析过，使用解析好的构造函数
		if (resolved) {
			// 是否需要构造器注入
			if (autowireNecessary) {
				// 构造器注入方式初始化
				return autowireConstructor(beanName, mbd, null, null);
			}
			else {
				// 使用默认构造器初始化
				return instantiateBean(beanName, mbd);
			}
		}

		// 到这里就需要开始决策使用哪一个构造函数进行初始化
		Constructor<?>[] ctors = determineConstructorsFromBeanPostProcessors(beanClass, beanName);
		if (ctors != null || mbd.getResolvedAutowireMode() == AUTOWIRE_CONSTRUCTOR ||
				mbd.hasConstructorArgumentValues() || !ObjectUtils.isEmpty(args)) {
			// 构造器注入
			return autowireConstructor(beanName, mbd, ctors, args);
		}

		// Preferred constructors for default construction?
		ctors = mbd.getPreferredConstructors();
		if (ctors != null) {
			return autowireConstructor(beanName, mbd, ctors, null);
		}

		// 使用默认构造器初始化，无参构造
		// No special handling: simply use no-arg constructor.
		return instantiateBean(beanName, mbd);
	}

```

* 获取 bean 的 Supplier，这里的 Supplier 是 JDK 原生的 Supplier 接口，提供了一个 get() 方法，如果这个 bean 配置了 Supplier，就通过 Supplier.get() 获取 bean 实例，然后封装到 BeanWrapper 中返回。

* 获取 `factory-method`，在配置 bean 的时候，可以为 bean 配置一个 `factory-method` 方法来指定通过什么方法来创建 bean。

* 通过构造函数初始化。

这里需要注意的是：

  * 因为如果有构造函数参数的自动注入，在这里就会获取依赖的 bean 实例，这就意味着，那么如果有两个形成循环依赖的 bean 都是互相通过构造器注入的，就会抛出异常，因为此时在一二三级缓存中都找不到依赖的 bean，所以会尝试创建 bean，但是创建时又发现在这之前已经被标记为创建中。这就是为什么 **Spring 解决不了构造函数的依赖注入**，而如果所有依赖都不是构造器注入，那么此时用来是创建 bean 实例的就是默认的无参构造了。

  * 不管是什么对象，在这里肯定都是选择了一个构造函数来进行对象的创建的，无参构造创建对象调用的是 `instantiateBean()` 方法，通过其他的构造函数创建对象调用的是 `autowireConstructor()` 方法。

### 非无参构造创建 bean 实例

接下来看看这两个方法的逻辑，首先看看非无参构造创建 bean 对象的逻辑。

```java
	public BeanWrapper autowireConstructor(String beanName, RootBeanDefinition mbd,
			@Nullable Constructor<?>[] chosenCtors, @Nullable Object[] explicitArgs) {

		BeanWrapperImpl bw = new BeanWrapperImpl();
		this.beanFactory.initBeanWrapper(bw);

		Constructor<?> constructorToUse = null;
		ArgumentsHolder argsHolderToUse = null;
		// 使用的参数
		Object[] argsToUse = null;

		if (explicitArgs != null) {
			argsToUse = explicitArgs;
		}
		else {
			Object[] argsToResolve = null;
			synchronized (mbd.constructorArgumentLock) {
				constructorToUse = (Constructor<?>) mbd.resolvedConstructorOrFactoryMethod;
				// 如果构造函数的解析已经完成
				if (constructorToUse != null && mbd.constructorArgumentsResolved) {
					// Found a cached constructor...
					argsToUse = mbd.resolvedConstructorArguments;
					if (argsToUse == null) {
						argsToResolve = mbd.preparedConstructorArguments;
					}
				}
			}
			if (argsToResolve != null) {
				// 参数类型转换，到这里主要是做类型转换，比如参数是 int 类型，那么在这里需要将 “1” 转换成 1
				argsToUse = resolvePreparedArguments(beanName, mbd, bw, constructorToUse, argsToResolve);
			}
		}

		/**
		 * 以上代码说明在解析构造函数参数时，resolvedConstructorArguments 是经过了类型转换之后的，
		 * preparedConstructorArguments 肯能还没有做类型转换，个人认为其实主要集中在基本类型的相互转换上
		 */

		/**
		 * 从逻辑上看，这里可用的构造函数引用和可用的构造函数参数列表是 null 的情况，说明其实还没有解析
		 */

		if (constructorToUse == null || argsToUse == null) {
			// Take specified constructors, if any.
			Constructor<?>[] candidates = chosenCtors;
			if (candidates == null) {
				Class<?> beanClass = mbd.getBeanClass();
				try {
					// 如果允许访问非 public 的方法，就返回所有的构造函数，不然就只取 public 的构造函数
					candidates = (mbd.isNonPublicAccessAllowed() ?
							beanClass.getDeclaredConstructors() : beanClass.getConstructors());
				}
				catch (Throwable ex) {
					throw new BeanCreationException(mbd.getResourceDescription(), beanName,
							"Resolution of declared constructors on bean Class [" + beanClass.getName() +
							"] from ClassLoader [" + beanClass.getClassLoader() + "] failed", ex);
				}
			}

			// 只有一个构造函数，且传入的构造函数参数列表为 null，且 BeanDefinition 解析时就确定没有构造函数参数
			if (candidates.length == 1 && explicitArgs == null && !mbd.hasConstructorArgumentValues()) {
				Constructor<?> uniqueCandidate = candidates[0];
				// 如果唯一的构造函数的参数列表长度也为 0，那就可以开始初始化实例了
				if (uniqueCandidate.getParameterCount() == 0) {
					synchronized (mbd.constructorArgumentLock) {
						mbd.resolvedConstructorOrFactoryMethod = uniqueCandidate;
						mbd.constructorArgumentsResolved = true;
						mbd.resolvedConstructorArguments = EMPTY_ARGS;
					}
					// 调用 instantiate() 方法构建实例, 这里是一个无参构造初始化
					bw.setBeanInstance(instantiate(beanName, mbd, uniqueCandidate, EMPTY_ARGS));
					return bw;
				}
			}

			/**
			 * 到这里可以确定，对于这个 bean 初始化所需要的构造函数或者工厂方法、构造函数参数值的解析工作还没有进行
			 * 所以，接下来需要进行解析
			 */

			// 是否需要解决构造器注入
			boolean autowiring = (chosenCtors != null ||
					mbd.getResolvedAutowireMode() == AutowireCapableBeanFactory.AUTOWIRE_CONSTRUCTOR);
			ConstructorArgumentValues resolvedValues = null;
			// 确定参数列表长度
			int minNrOfArgs;
			if (explicitArgs != null) {
				minNrOfArgs = explicitArgs.length;
			}
			else {
				// 从 BeanDefinition 中获取参数列表
				ConstructorArgumentValues cargs = mbd.getConstructorArgumentValues();
				resolvedValues = new ConstructorArgumentValues();
				// 在这里就会解决初始化以依赖的 bean，需要注意的是，需要注意的是，这里是使用有参构造初始化 bean，
				// 这就导致 如果 A 和 B 有相互的构造器注入，A 还没有初始化，正在寻找并初始化构造器参数时，会初始化 B，
				// 而 B 又会尝试初始化 A, 但是从前序逻辑上看，此时 A 已经被标记为创建中，所有就会报循环依赖的异常
				minNrOfArgs = resolveConstructorArguments(beanName, mbd, bw, cargs, resolvedValues);
			}
			// 构造函数排序，先是 public 方法然后是非 public 的方法，同样的修饰符的方法，又以参数列表长度降序排序
			AutowireUtils.sortConstructors(candidates);
			int minTypeDiffWeight = Integer.MAX_VALUE;
			Set<Constructor<?>> ambiguousConstructors = null;
			Deque<UnsatisfiedDependencyException> causes = null;

			for (Constructor<?> candidate : candidates) {
				int parameterCount = candidate.getParameterCount();

				if (constructorToUse != null && argsToUse != null && argsToUse.length > parameterCount) {
					// Already found greedy constructor that can be satisfied ->
					// do not look any further, there are only less greedy constructors left.
					break;
				}
				// 对于参数列表长度比 BeanDefinition 中定义的参数列表长度还小的，直接跳过
				if (parameterCount < minNrOfArgs) {
					continue;
				}

				ArgumentsHolder argsHolder;
				Class<?>[] paramTypes = candidate.getParameterTypes();
				if (resolvedValues != null) {
					try {
						// 获取参数名称数组
						String[] paramNames = getParamNames(candidate, parameterCount);
						// 获取参数列表的 Holder
						argsHolder = createArgumentArray(beanName, mbd, resolvedValues, bw, paramTypes, paramNames,
								getUserDeclaredConstructor(candidate), autowiring, candidates.length == 1);
					}
					catch (UnsatisfiedDependencyException ex) {
						if (logger.isTraceEnabled()) {
							logger.trace("Ignoring constructor [" + candidate + "] of bean '" + beanName + "': " + ex);
						}
						// Swallow and try next constructor.
						if (causes == null) {
							causes = new ArrayDeque<>(1);
						}
						causes.add(ex);
						continue;
					}
				}
				else {
					// 从前面的逻辑看，到这里 explicitArgs 肯定不为 null, 如果长度不一致，直接忽略
					// Explicit arguments given -> arguments length must match exactly.
					if (parameterCount != explicitArgs.length) {
						continue;
					}
					// 直接使用 explicitArgs 作为参数
					argsHolder = new ArgumentsHolder(explicitArgs);
				}

				int typeDiffWeight = (mbd.isLenientConstructorResolution() ?
						argsHolder.getTypeDifferenceWeight(paramTypes) : argsHolder.getAssignabilityWeight(paramTypes));
				// Choose this constructor if it represents the closest match.
				if (typeDiffWeight < minTypeDiffWeight) {
					constructorToUse = candidate;
					argsHolderToUse = argsHolder;
					argsToUse = argsHolder.arguments;
					minTypeDiffWeight = typeDiffWeight;
					ambiguousConstructors = null;
				}
				else if (constructorToUse != null && typeDiffWeight == minTypeDiffWeight) {
					if (ambiguousConstructors == null) {
						ambiguousConstructors = new LinkedHashSet<>();
						ambiguousConstructors.add(constructorToUse);
					}
					ambiguousConstructors.add(candidate);
				}
			}

			// 构造函数解析结束，如果此时可用的构造函数依然是 null ，那就没法初始化了，只能报错
			if (constructorToUse == null) {
				if (causes != null) {
					UnsatisfiedDependencyException ex = causes.removeLast();
					for (Exception cause : causes) {
						this.beanFactory.onSuppressedException(cause);
					}
					throw ex;
				}
				throw new BeanCreationException(mbd.getResourceDescription(), beanName,
						"Could not resolve matching constructor " +
						"(hint: specify index/type/name arguments for simple parameters to avoid type ambiguities)");
			}
			// 匹配上的构造函数有多个，而且不允许模糊匹配，那也只能报错
			else if (ambiguousConstructors != null && !mbd.isLenientConstructorResolution()) {
				throw new BeanCreationException(mbd.getResourceDescription(), beanName,
						"Ambiguous constructor matches found in bean '" + beanName + "' " +
						"(hint: specify index/type/name arguments for simple parameters to avoid type ambiguities): " +
						ambiguousConstructors);
			}

			if (explicitArgs == null && argsHolderToUse != null) {
				argsHolderToUse.storeCache(mbd, constructorToUse);
			}
		}

		Assert.state(argsToUse != null, "Unresolved constructor arguments");
		// 终于找到了构造函数和参数，初始化对象
		bw.setBeanInstance(instantiate(beanName, mbd, constructorToUse, argsToUse));
		return bw;
	}
```

> 这段代码看吐了，太长了

代码中已经添加了很多注释，就简单讲讲。这个方法最终返回的是 BeanWrapperImpl 的实例，它持有对创建的 bean 对象的引用。解析来梳理一下这个方法里面的逻辑步骤，其实大的流程上也比较简单。

* 初始化一个 BeanWrapperImpl 实例。
* 选择构造函数和构造函数参数值，在通过构造函数注入时，如果有多个构造函数，会根据配置文件中配置的构造函数参数个数，进行选择。最终会将所有构造函数进行排序，优先级以修饰符区分，public 优先级最高，如果优先级相同，有按照参数个数从小到大排序，最终选择取的是参数个数大于等于且最接近配置文件中配置的参数个数的构造函数创建 bean 实例。
* 调用 `instantiate` 方法创建 bean 实例。

虽然代码很多，但其实这一层的逻辑是比较简单的。

然后看看 `instantiate()` 方法：

```java
	private Object instantiate(
			String beanName, RootBeanDefinition mbd, Constructor<?> constructorToUse, Object[] argsToUse) {

		try {
			// 获取对象初始化策略
			InstantiationStrategy strategy = this.beanFactory.getInstantiationStrategy();
			if (System.getSecurityManager() != null) {
				return AccessController.doPrivileged((PrivilegedAction<Object>) () ->
						strategy.instantiate(mbd, beanName, this.beanFactory, constructorToUse, argsToUse),
						this.beanFactory.getAccessControlContext());
			}
			else {
				return strategy.instantiate(mbd, beanName, this.beanFactory, constructorToUse, argsToUse);
			}
		}
		catch (Throwable ex) {
			throw new BeanCreationException(mbd.getResourceDescription(), beanName,
					"Bean instantiation via constructor failed", ex);
		}
	}
```

获取了对象的初始化策略之后直接就创建了 bean 实例，但是具体的逻辑在这里不关注，之所以写出来是为了和无参构造创建 bean 的逻辑做对比。

### 无参构造初始化 bean 实例

理解了有参构造创建 bean 的逻辑之后，再看无参构造创建 bean 的逻辑就比较简单了。

```java
	protected BeanWrapper instantiateBean(String beanName, RootBeanDefinition mbd) {
		try {
			Object beanInstance;
			if (System.getSecurityManager() != null) {
				beanInstance = AccessController.doPrivileged(
						(PrivilegedAction<Object>) () -> getInstantiationStrategy().instantiate(mbd, beanName, this),
						getAccessControlContext());
			}
			else {
				beanInstance = getInstantiationStrategy().instantiate(mbd, beanName, this);
			}
			BeanWrapper bw = new BeanWrapperImpl(beanInstance);
			initBeanWrapper(bw);
			return bw;
		}
		catch (Throwable ex) {
			throw new BeanCreationException(
					mbd.getResourceDescription(), beanName, "Instantiation of bean failed", ex);
		}
	}
```

会发现其实和有参数构造方法创建 bean 实例最后调用的 `instantiate()` 方法是一模一样的。

### populateBean() 方法填充属性值

在前面已经拿到了 bean 的对象实例之后，对象中的一些需要自动注入的属性还是 null，因为创建时只注入了构造函数中的参数。

```java
	protected void populateBean(String beanName, RootBeanDefinition mbd, @Nullable BeanWrapper bw) {
		if (bw == null) {
			if (mbd.hasPropertyValues()) {
				throw new BeanCreationException(
						mbd.getResourceDescription(), beanName, "Cannot apply property values to null instance");
			}
			else {
				// Skip property population phase for null instance.
				return;
			}
		}

		// Give any InstantiationAwareBeanPostProcessors the opportunity to modify the
		// state of the bean before properties are set. This can be used, for example,
		// to support styles of field injection.
		if (!mbd.isSynthetic() && hasInstantiationAwareBeanPostProcessors()) {
			for (InstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().instantiationAware) {
				if (!bp.postProcessAfterInstantiation(bw.getWrappedInstance(), beanName)) {
					// 如果后处理器一旦有一个返回 false, 就不填充属性值
					return;
				}
			}
		}

		PropertyValues pvs = (mbd.hasPropertyValues() ? mbd.getPropertyValues() : null);

		int resolvedAutowireMode = mbd.getResolvedAutowireMode();
		if (resolvedAutowireMode == AUTOWIRE_BY_NAME || resolvedAutowireMode == AUTOWIRE_BY_TYPE) {
			MutablePropertyValues newPvs = new MutablePropertyValues(pvs);
			// Add property values based on autowire by name if applicable.
			if (resolvedAutowireMode == AUTOWIRE_BY_NAME) {
				// 按 beanName 注入
				autowireByName(beanName, mbd, bw, newPvs);
			}
			// Add property values based on autowire by type if applicable.
			if (resolvedAutowireMode == AUTOWIRE_BY_TYPE) {
				// 按照 bean 的类型注入
				autowireByType(beanName, mbd, bw, newPvs);
			}
			pvs = newPvs;
		}

		boolean hasInstAwareBpps = hasInstantiationAwareBeanPostProcessors();
		boolean needsDepCheck = (mbd.getDependencyCheck() != AbstractBeanDefinition.DEPENDENCY_CHECK_NONE);

		PropertyDescriptor[] filteredPds = null;
		if (hasInstAwareBpps) {
			if (pvs == null) {
				pvs = mbd.getPropertyValues();
			}
			for (InstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().instantiationAware) {
				PropertyValues pvsToUse = bp.postProcessProperties(pvs, bw.getWrappedInstance(), beanName);
				if (pvsToUse == null) {
					if (filteredPds == null) {
						filteredPds = filterPropertyDescriptorsForDependencyCheck(bw, mbd.allowCaching);
					}
					// 后处理
					pvsToUse = bp.postProcessPropertyValues(pvs, filteredPds, bw.getWrappedInstance(), beanName);
					if (pvsToUse == null) {
						return;
					}
				}
				pvs = pvsToUse;
			}
		}
		if (needsDepCheck) {
			if (filteredPds == null) {
				filteredPds = filterPropertyDescriptorsForDependencyCheck(bw, mbd.allowCaching);
			}
			// 依赖检查
			checkDependencies(beanName, mbd, filteredPds, pvs);
		}

		if (pvs != null) {
			// 将属性应用到 bean 中, 前面只是找到了每一个依赖的 bean 而已
			applyPropertyValues(beanName, mbd, bw, pvs);
		}
	}
```

代码依然能很长，但是不用关注太多，主要需要知道这里的 `PropertyValues` 类型的局部变量 `pvs` 就是要注入的属性的值的容器。

Spring 中依赖注入有根据名称注入和根据 type 注入两种，分别对应 `autowireByName()` 和 `autowireByType()` 两个方法，这两个方法都会拿到以来的 bean 的实例引用，而且都是通过 beanFactory.getBean() 方法获取的，这说明如果依赖的 bean 没有创建的话，这次调用会创建依赖的 bean，次数如果有循环依赖的话，通过 Spring 的三级缓存，就能解决，因为就算依赖的 bean 没有创建完成，不能从一级缓存中取得，但是依然可以尝试从二级或者三级缓存中获取。

最后时通过 `applyPropertyValues()` 方法将属性值赋值到了 bean 实例中。

## Bean 实例类型转换

```java
	<T> T adaptBeanInstance(String name, Object bean, @Nullable Class<?> requiredType) {
		// Check if required type matches the type of the actual bean instance.
		// 类型检查，检查得到的 bean 类型和期望的类型是否一致
		if (requiredType != null && !requiredType.isInstance(bean)) {
			try {
				Object convertedBean = getTypeConverter().convertIfNecessary(bean, requiredType);
				if (convertedBean == null) {
					throw new BeanNotOfRequiredTypeException(name, requiredType, bean.getClass());
				}
				return (T) convertedBean;
			}
			catch (TypeMismatchException ex) {
				if (logger.isTraceEnabled()) {
					logger.trace("Failed to convert bean '" + name + "' to required type '" +
							ClassUtils.getQualifiedName(requiredType) + "'", ex);
				}
				throw new BeanNotOfRequiredTypeException(name, requiredType, bean.getClass());
			}
		}
		return (T) bean;
	}
```

这一段倒是比较简单了，其实是因为前序逻辑最终返回的 bean 实例对象是 Object 而不是具体的某个类型的对象，到这一步最后需要转换为调用方需要的类型而已。

* 如果 requiredType 不为 null，并且获取到的 bean 类型和 requiredType 不一致时，尝试做一次类型转换，如果转换成功了直接返回，没成功就抛异常。
* 如果 requiredType 为 null，或者拿到的 bean 类型和 requiredType 一致，直接做一次原生的转型操作返回即可。

