---
title: Spring-AOP原理
date: 2021-10-24 10:03:42
tags: Spring
categories: Spring
cover: https://hanelalo.github.io/images/202110241726321.png
---

> 图来自 unsplash 

# Spring-AOP 原理

> 之前写过一篇 AOP 的笔记，不过是站在使用的角度来讲，略微涉及两种动态代理的区别，本文是在 Spring 源码角度来看 Spring AOP 的实现。

## 配置 AOP

Spring AOP 的动态代理方式有两种，一种是 Jdk 原生实现的，原理是基于实现代理接口，一种是使用 Cglib 这一开源的字节码生成器实现，原理是继承被代理类。

在 Spring 中，默认是优先使用 Jdk 动态代理的方式实现，那么，如何配置成使用 Cglib 作为默认实现呢？源码层面又是如何实现的？

在 Spring AOP 配置体系中有 `<aop:config/>` 标签，它的 `proxy-target-class` 属性决定默认使用 Jdk 动态代理还是 Cglib，这个属性默认是 false，false 是默认使用 Jdk 动态代理实现，true 表示默认使用 Cglib。

下面举个例子来证明。

定义一个接口 TestBean 及其实现类：

```java
public interface TestBean {
  void sayHello();
}
```



```java
public class TestBeanImpl implements TestBean {

  @Override
  public void sayHello() {
    System.out.println("hello world");
  }
}
```

定义 TestBean 的切面：

```java
@Aspect
public class DynamicProxy {

  @Pointcut("execution(public void org.hanelalo.TestBean.sayHello())")
  public void pointCut(){

  }

  @Before("pointCut()")
  public void before() {
    System.out.println("before");
  }
}
```

最后编写启动类，因为使用原始的 xml 配置方式启动，所以使用 ClassPathXmlApplicationContext 启动容器：

```java
public class BootStrap {

  public static void main(String[] args) {
    ClassPathXmlApplicationContext context =
        new ClassPathXmlApplicationContext("classpath:spring-context.xml");
    TestBean testBean = context.getBean(TestBean.class);
    testBean.sayHello();
  }
}
```

下面是 `spring-context.xml` 配置文件：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:aop="http://www.springframework.org/schema/aop"
  xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd http://www.springframework.org/schema/aop https://www.springframework.org/schema/aop/spring-aop.xsd">
  <bean id="testBean" class="org.hanelalo.TestBeanImpl"/>
  <bean class="org.hanelalo.DynamicProxy"/>
  <aop:aspectj-autoproxy/>
  <aop:config/>
</beans>
```

此时 proxy-target-proxy 属性没有配置，默认是 false，所以此时会使用 Jdk 动态代理的方式生成 TestBeanImpl 的代理类。

![](https://hanelalo.github.io/images/202110241718290.png)

可以看见此时从容器中获取到的 TestBean 的实例是 Jdk 动态代理生成的 Proxy 类型。

接下来把 proxy-target-class 设置为 tue 再运行一次：

![](https://hanelalo.github.io/images/202110241721679.png)

此时会发现变成了 Cglib 代理的实现。

配置了 AOP 之后，再看看如何解析的配置。

## AOP 配置解析

再上一篇文章中讲到 Spring 对于 xml 配置的解析，都是有命名空间的概念，Spring 本身比较基础的配置想都有默认的明明空间，自定义的配置，一般都会自己再实现相应的配置的 NameSpaceHandler，并在其中注册命名空间下每一个 tag 对应的解析器。

从上一节的内容来看，AOP 的命名空间就是 `aop`，在 Spring 中直接就能找到 `AopNameSpaceHandler` 这个实现类。

```java
public class AopNamespaceHandler extends NamespaceHandlerSupport {

	@Override
	public void init() {
		// In 2.0 XSD as well as in 2.5+ XSDs
		registerBeanDefinitionParser("config", new ConfigBeanDefinitionParser());
		registerBeanDefinitionParser("aspectj-autoproxy", new AspectJAutoProxyBeanDefinitionParser());
		registerBeanDefinitionDecorator("scoped-proxy", new ScopedProxyBeanDefinitionDecorator());

		// Only in 2.0 XSD: moved to context namespace in 2.5+
		registerBeanDefinitionParser("spring-configured", new SpringConfiguredBeanDefinitionParser());
	}

}
```

在这里可以看见 aop 这个命名空间下，注册了 config、aspectj-autoproxy、scoped-proxy、sprinh-configured 这四个 tag 的名称，这里主要关注 aspectj-auotproxy 对应的解析器 `AspectJAutoProxyBeanDefinitionParser`。

```java
public BeanDefinition parse(Element element, ParserContext parserContext) {
 // 注册AspectJAnnotationAutoProxyCreator
 AopNamespaceUtils.registerAspectJAnnotationAutoProxyCreatorIfNecessary(parserContext, element);
 extendBeanDefinition(element, parserContext);
 return null;
}
```

它的 parse 方法有两行，第一行通常是为了 AspectJAnnotationAutoProxyCreator 用于后面初始化 bean 时创建代理类，第二行是根据配置决定要不要对前一步注册的 bean 做一些额外的配置。

这里我们主要关注第一步中注册的 bean。

```java
	public static void registerAspectJAnnotationAutoProxyCreatorIfNecessary(
			ParserContext parserContext, Element sourceElement) {

		BeanDefinition beanDefinition = AopConfigUtils.registerAspectJAnnotationAutoProxyCreatorIfNecessary(
				parserContext.getRegistry(), parserContext.extractSource(sourceElement));
		// 处理 proxy-target-class 和 expose-proxy
		useClassProxyingIfNecessary(parserContext.getRegistry(), sourceElement);
		// 注册组件并通知
		registerComponentIfNecessary(beanDefinition, parserContext);
	}
```

1. 通过 AopConfigUtils 创建 beanDefinition。
2. 处理配置钟大哥 proxy-target-class 和 expose-proxy 两种配置。
3. 将第一步的 bean 注册到解析器的上下文中。

创建 beanDefinition 的时候，会发现，这里创建的是一个有特定名称的 bean ：

```java
	public static final String AUTO_PROXY_CREATOR_BEAN_NAME =
			"org.springframework.aop.config.internalAutoProxyCreator";

	private static BeanDefinition registerOrEscalateApcAsRequired(
			Class<?> cls, BeanDefinitionRegistry registry, @Nullable Object source) {

		Assert.notNull(registry, "BeanDefinitionRegistry must not be null");

		if (registry.containsBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME)) {
			// 找到 beanName 为 org.springframework.aop.config.internalAutoProxyCreator 的 bean
			BeanDefinition apcDefinition = registry.getBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME);
			if (!cls.getName().equals(apcDefinition.getBeanClassName())) {
				// 如果这个组件已经注册过，就以优先级判断使用谁的 class
				int currentPriority = findPriorityForClass(apcDefinition.getBeanClassName());
				int requiredPriority = findPriorityForClass(cls);
				if (currentPriority < requiredPriority) {
					apcDefinition.setBeanClassName(cls.getName());
				}
			}
			return null;
		}

		// 注册 org.springframework.aop.config.internalAutoProxyCreator
		RootBeanDefinition beanDefinition = new RootBeanDefinition(cls);
		beanDefinition.setSource(source);
		beanDefinition.getPropertyValues().add("order", Ordered.HIGHEST_PRECEDENCE);
		beanDefinition.setRole(BeanDefinition.ROLE_INFRASTRUCTURE);
		registry.registerBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME, beanDefinition);
		return beanDefinition;
	}
```

1. 首先判断了 BeanRegistry 中是否存在 `AUTO_PROXY_CREATOR_BEAN_NAME` 这个 bean。
2. 如果存在，找到对应的 beanDefinition 对象，比较 beanDefinition 中的 className 是否就是 AnnotationAwareAspectJAutoProxyCreator（这是在调用 `registerOrEscalateApcAsRequired` 方法时写死的参数），如果是，到此结束，因为 BeanRegistry 中已经存在目标 beanDefinition，不需要再注册一次，直接返回 null；如果 className 不是 AnnotationAwareAspectJAutoProxyCreator，需要根据两个类的优先级决定 beanDefinition 应该持有哪个 class。
3. 如果不存在，那就需要创建一个新的 BeanDefinition，并把 beanName 设置为 `AUTO_PROXY_CREATOR_BEAN_NAME`。

创建了 beanDefinition 后，需要再对 proxy-target-class 和 expose-proxy 两个属性进行处理。

```java
	private static void useClassProxyingIfNecessary(BeanDefinitionRegistry registry, @Nullable Element sourceElement) {
		if (sourceElement != null) {
			boolean proxyTargetClass = Boolean.parseBoolean(sourceElement.getAttribute(PROXY_TARGET_CLASS_ATTRIBUTE));
			if (proxyTargetClass) {
				AopConfigUtils.forceAutoProxyCreatorToUseClassProxying(registry);
			}
			boolean exposeProxy = Boolean.parseBoolean(sourceElement.getAttribute(EXPOSE_PROXY_ATTRIBUTE));
			if (exposeProxy) {
				AopConfigUtils.forceAutoProxyCreatorToExposeProxy(registry);
			}
		}
	}
```

首先读取标签的 proxy-target-class 属性，这个属性是否要使用 cglib 的方式进行代理实现，如果不填，就是 false，那就是默认使用 Jdk 动态代理，配置为 true 就是默认使用 Cglib 的方式实现。

然后是 expose-proxy 属性的处理，这个打破了我一直以来对 Spring 的 @Transactional 注解的理解。

比如下面的代码：

```java
public interface AopService {
    void a();
    void b();
}

@Service
public class AopServiceImpl implements AopService {
    
    @Transactional(propagation = Propagation.REQUIRED)
    public void a(){
        this.b();
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void b(){
        doSomething();
    }
    
}
```

AopService 提供了两个方法，通常情况下，另一个类直接调用 AopService 中的任何一个方法，对应的方法上的 @Transactional 注解都会起作用，这是大家都理解的，但是 a 方法调用了 b 方法，所以调用 a 方法，a 再调用 b，这次调用中，b 方法上的注解是没有生效的，那如果这种情况下想要 b 方法上的注解也生效要如何做？

首先需要修改配置，将 `expose-proxy` 设置为 true，然后修改代码，不直接使用 `this.b()`，而是写成下面这样。

```java
@Service
public class AopServiceImpl implements AopService {
    
    @Transactional(propagation = Propagation.REQUIRED)
    public void a(){
        ((AopService)AopContext.currentProxy()).b()
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void b(){
        doSomething();
    }
    
}
```

最后，将第一步创建的 beanDefinition 注册到 BeanRegistry 中：

```java
	private static void registerComponentIfNecessary(@Nullable BeanDefinition beanDefinition, ParserContext parserContext) {
		if (beanDefinition != null) {
			parserContext.registerComponent(
					new BeanComponentDefinition(beanDefinition, AopConfigUtils.AUTO_PROXY_CREATOR_BEAN_NAME));
		}
	}
```

在第一步就提到 AnnotationAwareAspectJAutoProxyCreator，接下就开始剖析 AnnotationAwareAspectJAutoProxyCreator 是如何创建 AOP 代理的。

## AOP 代理创建

在之前将 bean 初始化时，有讲过 Spring 会尽量让 bean 在初始化前后都运行 BeanPostProcessor 中相应的方法，找到在它的实现类中有一个 AnnotationAwareAspectJAutoProxyCreator 类，这个类继承自 AbstractAutoProxyCreator，在这个父类中实现了 `#postProcessAfterInitialization` 方法：

```java
	@Override
	public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
		// bean 创建后的处理逻辑
		if (bean != null) {
			Object cacheKey = getCacheKey(bean.getClass(), beanName);
			if (this.earlyProxyReferences.remove(cacheKey) != bean) {
				// 如果有必要，就开始代理逻辑
				return wrapIfNecessary(bean, beanName, cacheKey);
			}
		}
		return bean;
	}
```

终于，在 `#wrapIfNecessary` 方法中有了开始了 AOP 的处理逻辑。

```java
	protected Object wrapIfNecessary(Object bean, String beanName, Object cacheKey) {
		// 已经处理过了，直接返回即可
		if (StringUtils.hasLength(beanName) && this.targetSourcedBeans.contains(beanName)) {
			return bean;
		}
		// 不需要代理
		if (Boolean.FALSE.equals(this.advisedBeans.get(cacheKey))) {
			return bean;
		}
		// 是基础设施 bean 或者是配置了不需要代理的类
		if (isInfrastructureClass(bean.getClass()) || shouldSkip(bean.getClass(), beanName)) {
			this.advisedBeans.put(cacheKey, Boolean.FALSE);
			return bean;
		}

		// Create proxy if we have advice.
		// 如果存在增强方法，就创建代理
		Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(bean.getClass(), beanName, null);
		if (specificInterceptors != DO_NOT_PROXY) {
			this.advisedBeans.put(cacheKey, Boolean.TRUE);
			// 创建代理类
			Object proxy = createProxy(
					bean.getClass(), beanName, specificInterceptors, new SingletonTargetSource(bean));
			this.proxyTypes.put(cacheKey, proxy.getClass());
			return proxy;
		}

		this.advisedBeans.put(cacheKey, Boolean.FALSE);
		return bean;
	}
```

1. 如果是已经进行过 AOP 处理的 bean 就直接跳过。

2. 如果是基础设施的 bean 直接跳过。
3. 通过 `#getAdvicesAndAdvisorsForBean` 方法获取需要增强的方法，如果不为 null，通过 `#createProxy` 创建代理类。

4. 如果为 null，在缓存中记录改 bean 不需要做 AOP 处理。

### 获取增强的方法列表

`Advisor` 接口可以理解为 AOP 的增强描述信息。

`#getAdvicesAndAdvisorsForBean()` 方法获取的就是 bean 能够使用的增强的列表。

```java
	protected Object[] getAdvicesAndAdvisorsForBean(
			Class<?> beanClass, String beanName, @Nullable TargetSource targetSource) {
		// 获取 Advisor
		List<Advisor> advisors = findEligibleAdvisors(beanClass, beanName);
		if (advisors.isEmpty()) {
			return DO_NOT_PROXY;
		}
		return advisors.toArray();
	}
```

通过 `#findEligibleAdvisors()` 方法获取符合条件的 Advisor 列表，如果是空的，就返回 DO_NOT_PROXY，其实就是个 null。

`#findEligibleAdvisors()` 方法会获取所有的 Advisor，然后再循环筛选：

```java
	protected List<Advisor> findEligibleAdvisors(Class<?> beanClass, String beanName) {
		List<Advisor> candidateAdvisors = findCandidateAdvisors();
		List<Advisor> eligibleAdvisors = findAdvisorsThatCanApply(candidateAdvisors, beanClass, beanName);
		extendAdvisors(eligibleAdvisors);
		if (!eligibleAdvisors.isEmpty()) {
			eligibleAdvisors = sortAdvisors(eligibleAdvisors);
		}
		return eligibleAdvisors;
	}
```

* 获取所有的 Advisor，这里获取的 Advisor，我的理解是，它其实就是切面信息描述。
* 通过 beanClass 和 beanName 筛选 Advisor，因为并不是每一个 bean 都需要被代理，也并不是每一个切面对每一个 bean 都使用。
* 对筛选后的 advisor 排序

接下来主要关注第一步即可。

#### 获取所有的 Advisor

AnnotationAwareAspectJAutoProxyCreator 重写了父类的 `findCandidateAdvisors()` 方法：

```java
	protected List<Advisor> findCandidateAdvisors() {
		// Add all the Spring advisors found according to superclass rules.
		List<Advisor> advisors = super.findCandidateAdvisors();
		// Build Advisors for all AspectJ aspects in the bean factory.
		if (this.aspectJAdvisorsBuilder != null) {
			advisors.addAll(this.aspectJAdvisorsBuilder.buildAspectJAdvisors());
		}
		return advisors;
	}
```

首先通过父类的 `findCandidateAdvisors()` 方法拿到了所有的 Advisor，最终是调用 `BeanFactoryAdvisorRetrievalHelper#findAdvisorBeans` 方法实现。

```java
	public List<Advisor> findAdvisorBeans() {
		// Determine list of advisor bean names, if not cached already.
		String[] advisorNames = this.cachedAdvisorBeanNames;
		if (advisorNames == null) {
			// Do not initialize FactoryBeans here: We need to leave all regular beans
			// uninitialized to let the auto-proxy creator apply to them!
			advisorNames = (
					this.beanFactory, Advisor.class, true, false);
			this.cachedAdvisorBeanNames = advisorNames;
		}
		if (advisorNames.length == 0) {
			return new ArrayList<>();
		}

		List<Advisor> advisors = new ArrayList<>();
		for (String name : advisorNames) {
			if (isEligibleBean(name)) {
				if (this.beanFactory.isCurrentlyInCreation(name)) {
					if (logger.isTraceEnabled()) {
						logger.trace("Skipping currently created advisor '" + name + "'");
					}
				}
				else {
					try {
						advisors.add(this.beanFactory.getBean(name, Advisor.class));
					}
					catch (BeanCreationException ex) {
						Throwable rootCause = ex.getMostSpecificCause();
						if (rootCause instanceof BeanCurrentlyInCreationException) {
							BeanCreationException bce = (BeanCreationException) rootCause;
							String bceBeanName = bce.getBeanName();
							if (bceBeanName != null && this.beanFactory.isCurrentlyInCreation(bceBeanName)) {
								if (logger.isTraceEnabled()) {
									logger.trace("Skipping advisor '" + name +
											"' with dependency on currently created bean: " + ex.getMessage());
								}
								// Ignore: indicates a reference back to the bean we're trying to advise.
								// We want to find advisors other than the currently created bean itself.
								continue;
							}
						}
						throw ex;
					}
				}
			}
		}
		return advisors;
	}
```

这里其实主要就是通过 `BeanFactoryUtils#beanNamesForTypeIncludingAncestors` 方法找到在容器中的那些 `Advisor` 接口的 bean。

调用完父类方法后，再通过 `aspectJAdvisorsBuilder.buildAspectJAdvisors()` 找 Advisor。

```java
	public List<Advisor> buildAspectJAdvisors() {
		List<String> aspectNames = this.aspectBeanNames;

		if (aspectNames == null) {
			synchronized (this) {
				aspectNames = this.aspectBeanNames;
				if (aspectNames == null) {
					List<Advisor> advisors = new ArrayList<>();
					aspectNames = new ArrayList<>();
					// 获取所有的 beanNames
					String[] beanNames = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
							this.beanFactory, Object.class, true, false);
					for (String beanName : beanNames) {
						// 是否是符合规则的 bean, 默认返回 true，具体规则由子类定义
						if (!isEligibleBean(beanName)) {
							continue;
						}
						// We must be careful not to instantiate beans eagerly as in this case they
						// would be cached by the Spring container but would not have been weaved.
						Class<?> beanType = this.beanFactory.getType(beanName, false);
						if (beanType == null) {
							continue;
						}
						// 是否存在 @Aspect 注解
						if (this.advisorFactory.isAspect(beanType)) {
							aspectNames.add(beanName);
							AspectMetadata amd = new AspectMetadata(beanType, beanName);
							if (amd.getAjType().getPerClause().getKind() == PerClauseKind.SINGLETON) {
								MetadataAwareAspectInstanceFactory factory =
										new BeanFactoryAspectInstanceFactory(this.beanFactory, beanName);
								// 通过 Factory 解析其中的增强方法
								List<Advisor> classAdvisors = this.advisorFactory.getAdvisors(factory);
								if (this.beanFactory.isSingleton(beanName)) {
									// 如果是单例 bean，直接将解析出的 advisors 放入缓存即可
									this.advisorsCache.put(beanName, classAdvisors);
								}
								else {
									// 不视单例 bean, 那么每次创建 bean 的时候都应该再从 factory 中解析 advisors,
									// 所以单独设计了一个 factory 的缓存
									this.aspectFactoryCache.put(beanName, factory);
								}
								advisors.addAll(classAdvisors);
							}
							else {
								// Per target or per this.
								if (this.beanFactory.isSingleton(beanName)) {
									throw new IllegalArgumentException("Bean with name '" + beanName +
											"' is a singleton, but aspect instantiation model is not singleton");
								}
								MetadataAwareAspectInstanceFactory factory =
										new PrototypeAspectInstanceFactory(this.beanFactory, beanName);
								this.aspectFactoryCache.put(beanName, factory);
								advisors.addAll(this.advisorFactory.getAdvisors(factory));
							}
						}
					}
					this.aspectBeanNames = aspectNames;
					return advisors;
				}
			}
		}

		// 如果增强的 bean 为空，返回一个空的 list
		if (aspectNames.isEmpty()) {
			return Collections.emptyList();
		}
		List<Advisor> advisors = new ArrayList<>();
		for (String aspectName : aspectNames) {
			List<Advisor> cachedAdvisors = this.advisorsCache.get(aspectName);
			// 从缓存中获取 beanName 对应的 advisors 列表
			if (cachedAdvisors != null) {
				// 如果不为 null，从前面的解析逻辑看，说明是单例 bean
				advisors.addAll(cachedAdvisors);
			}
			else {
				// 混村中获取的 advisors 是 null, 可能是因为不视单例 bean，尝试从 aspectFactory 的缓存中获取，
				// 然后通过 aspectFactory 获取 advisors
				MetadataAwareAspectInstanceFactory factory = this.aspectFactoryCache.get(aspectName);
				advisors.addAll(this.advisorFactory.getAdvisors(factory));
			}
		}
		return advisors;
	}
```

这里的 aspectBeanNames 可以理解为编写 AOP 代码时加了 @Aspect 注解的 bean 的名称。

* 首先获取容器中所有的 beanName（这里通过 Object.class 获取，所以可以认为是所有的）

* 通过 isEligibleBean() 方法判断每个 bean 是否符合要求，默认返回 true，具体规则可以由子类自己实现。

* 判断每个 bean 的 class 上面是否有 @Aspect 注解修饰。

* 对于前面两项检查都通过的 bean，开始构建 Advisor。

  > 构建 Advisor 时，发现有两个分支逻辑，一个是直接将构建好的 Advisor 放到缓存（其实就是一个内存中的 map）中，一种是类似 bean 初始化时用到的第三级缓存一样，保存了一个 Advisor 的工厂到缓存中，但是在这里，这两种其实区别不大，主要关注 Advisor 的构造就行了。

```java
MetadataAwareAspectInstanceFactory factory = new BeanFactoryAspectInstanceFactory(this.beanFactory, beanName);
// 通过 Factory 解析其中的增强方法
List<Advisor> classAdvisors = this.advisorFactory.getAdvisors(factory);
```

当 bean 符合条件时，会将 beanFactory 和 beanName 封装到一个 `BeanFactoryAspectInstanceFactory` 中，然后调用 `advisorFactory#getAdvisors` 方法构建 Advisor。

```java
	public List<Advisor> getAdvisors(MetadataAwareAspectInstanceFactory aspectInstanceFactory) {
		Class<?> aspectClass = aspectInstanceFactory.getAspectMetadata().getAspectClass();
		String aspectName = aspectInstanceFactory.getAspectMetadata().getAspectName();
		validate(aspectClass);
		MetadataAwareAspectInstanceFactory lazySingletonAspectInstanceFactory =
				new LazySingletonAspectInstanceFactoryDecorator(aspectInstanceFactory);

		List<Advisor> advisors = new ArrayList<>();
		for (Method method : getAdvisorMethods(aspectClass)) {
			// 获取增强器
			Advisor advisor = getAdvisor(method, lazySingletonAspectInstanceFactory, 0, aspectName);
			if (advisor != null) {
				advisors.add(advisor);
			}
		}

		// If it's a per target aspect, emit the dummy instantiating aspect.
		if (!advisors.isEmpty() && lazySingletonAspectInstanceFactory.getAspectMetadata().isLazilyInstantiated()) {
			Advisor instantiationAdvisor = new SyntheticInstantiationAdvisor(lazySingletonAspectInstanceFactory);
			advisors.add(0, instantiationAdvisor);
		}

		// Find introduction fields.
		for (Field field : aspectClass.getDeclaredFields()) {
			// 解析 @DeclaredParent 注解
			Advisor advisor = getDeclareParentsAdvisor(field);
			if (advisor != null) {
				advisors.add(advisor);
			}
		}

		return advisors;
	}

	private List<Method> getAdvisorMethods(Class<?> aspectClass) {
		List<Method> methods = new ArrayList<>();
		// adviceMethodFilter 的规则会排除 @PointCut 的方法
		ReflectionUtils.doWithMethods(aspectClass, methods::add, adviceMethodFilter);
		if (methods.size() > 1) {
			methods.sort(adviceMethodComparator);
		}
		return methods;
	}
```

1. 通过 getAdvisorMethods() 方法获取有 @PointCut 注解修饰的方法。

2. 通过 getAdvisor() 方法解析出 Advisor 对象

   ```java
   	public Advisor getAdvisor(Method candidateAdviceMethod, MetadataAwareAspectInstanceFactory aspectInstanceFactory,
   			int declarationOrderInAspect, String aspectName) {
   
   		validate(aspectInstanceFactory.getAspectMetadata().getAspectClass());
   
   		// 获取 @PointCut 等切点信息
   		AspectJExpressionPointcut expressionPointcut = getPointcut(
   				candidateAdviceMethod, aspectInstanceFactory.getAspectMetadata().getAspectClass());
   		if (expressionPointcut == null) {
   			return null;
   		}
   		// 通过切点信息生成增强器
   		return new InstantiationModelAwarePointcutAdvisorImpl(expressionPointcut, candidateAdviceMethod,
   				this, aspectInstanceFactory, declarationOrderInAspect, aspectName);
   	}
   ```

   a. 首先通过方法上的注解得到了方法上的切点表达式信息 AspectJExpressionPointcut，其实就是 @Before、@After 等注解的解析内容。

   b. 通过切点信息，封装成一个 InstantiationModelAwarePointcutAdvisorImpl 对象，这是一个 Advisor 实现类，初始化时就已经针对不同注解初始化了不同的增强逻辑。

#### 筛选使用的 Advisor

当拿到所有的 Advisor 之后，需要根据 bean 的定义筛选使用的 Advisor：

```java
	protected List<Advisor> findAdvisorsThatCanApply(
			List<Advisor> candidateAdvisors, Class<?> beanClass, String beanName) {

		ProxyCreationContext.setCurrentProxiedBeanName(beanName);
		try {
			return AopUtils.findAdvisorsThatCanApply(candidateAdvisors, beanClass);
		}
		finally {
			ProxyCreationContext.setCurrentProxiedBeanName(null);
		}
	}
```

这里其实也不用太过关注了，知道有这样一部操作即可。

### 创建代理

```java
	protected Object createProxy(Class<?> beanClass, @Nullable String beanName,
			@Nullable Object[] specificInterceptors, TargetSource targetSource) {

		if (this.beanFactory instanceof ConfigurableListableBeanFactory) {
			// 设置代理前的 class 对象引用
			AutoProxyUtils.exposeTargetClass((ConfigurableListableBeanFactory) this.beanFactory, beanName, beanClass);
		}

		// 创建 proxyFactory
		ProxyFactory proxyFactory = new ProxyFactory();
		proxyFactory.copyFrom(this);

		// 是否使用 targetClass 方式代理
		if (!proxyFactory.isProxyTargetClass()) {
			if (shouldProxyTargetClass(beanClass, beanName)) {
				proxyFactory.setProxyTargetClass(true);
			}
			else {
				// 解析 bean 实现的接口，筛选出其中需要代理的接口，并设置到 proxyFactory 中
				evaluateProxyInterfaces(beanClass, proxyFactory);
			}
		}

		Advisor[] advisors = buildAdvisors(beanName, specificInterceptors);
		proxyFactory.addAdvisors(advisors);
		proxyFactory.setTargetSource(targetSource);
		customizeProxyFactory(proxyFactory);

		proxyFactory.setFrozen(this.freezeProxy);
		if (advisorsPreFiltered()) {
			proxyFactory.setPreFiltered(true);
		}

		// Use original ClassLoader if bean class not locally loaded in overriding class loader
		ClassLoader classLoader = getProxyClassLoader();
		if (classLoader instanceof SmartClassLoader && classLoader != beanClass.getClassLoader()) {
			classLoader = ((SmartClassLoader) classLoader).getOriginalClassLoader();
		}
		// 创建代理类
		return proxyFactory.getProxy(classLoader);
	}
```

1. 将代理前的 class 设置到 beanDefinition 的 ORIGINAL_TARGET_CLASS_ATTRIBUTE 属性中记录。
2. 创建代理工厂 ProxyFactory，这里就能看见在配置解析阶段时涉及到的 proxy-target-class 的影子。
3. 创建代理类。

主要关注创建代理类这一步，到这里，具体是怎么从一个 class 创建一个 对象实例反而不需要关心了，因为那是字节码级别或者原生的 Jdk 动态代理的写法，这里反而要关系怎么决定是用 Jdk 动态代理还是使用 Cglib，往下看代码发现这段逻辑在 DefaultAopProxyFactory 中实现。

```java
public class DefaultAopProxyFactory implements AopProxyFactory, Serializable {


	@Override
	public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
		// config.isProxyTargetClass() 这里其实返回的就是是否使用 Jdk 动态代理作为默认代理方式
		if (!NativeDetector.inNativeImage() &&
				(config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config))) {
			Class<?> targetClass = config.getTargetClass();
			if (targetClass == null) {
				throw new AopConfigException("TargetSource cannot determine target class: " +
						"Either an interface or a target is required for proxy creation.");
			}
			// 接口默认使用 JDK 动态代理
			if (targetClass.isInterface() || Proxy.isProxyClass(targetClass)) {
				return new JdkDynamicAopProxy(config);
			}
			// Cglib 代理
			return new ObjenesisCglibAopProxy(config);
		}
		else {
			return new JdkDynamicAopProxy(config);
		}
	}

	private boolean hasNoUserSuppliedProxyInterfaces(AdvisedSupport config) {
		Class<?>[] ifcs = config.getProxiedInterfaces();
		return (ifcs.length == 0 || (ifcs.length == 1 && SpringProxy.class.isAssignableFrom(ifcs[0])));
	}

}
```

从代码逻辑上也可以印证前面的那句话，**Spring 默认的动态代理方式是 Jdk 动态代理。**
