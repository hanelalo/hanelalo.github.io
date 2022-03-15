---
title: Spring数据库事务原理
date: 2021-11-07 15:37:23
tags: Spring
categories: Spring
cover: http://image.hanelalo.cn/images/202111071541201.jpg
---

# Spring数据库事务原理

## 激活数据库事务

同样还是以 xml 配置的方式进行源码剖析。

Spring 里面开启事务管理主要通过 `<tx:annotation-driven/>` 来实现，从之前的 bean 加载的源码解析时就知道，对于这些注解，有相应的 NamespaceHandler 来处理，`tx` 这个命名空间则是由 TxNamespaceHandler 负责。

```java
public class TxNamespaceHandler extends NamespaceHandlerSupport {

	static final String TRANSACTION_MANAGER_ATTRIBUTE = "transaction-manager";

	static final String DEFAULT_TRANSACTION_MANAGER_BEAN_NAME = "transactionManager";


	static String getTransactionManagerName(Element element) {
		return (element.hasAttribute(TRANSACTION_MANAGER_ATTRIBUTE) ?
				element.getAttribute(TRANSACTION_MANAGER_ATTRIBUTE) : DEFAULT_TRANSACTION_MANAGER_BEAN_NAME);
	}

	@Override
	public void init() {
		registerBeanDefinitionParser("advice", new TxAdviceBeanDefinitionParser());
		registerBeanDefinitionParser("annotation-driven", new AnnotationDrivenBeanDefinitionParser());
		registerBeanDefinitionParser("jta-transaction-manager", new JtaTransactionManagerBeanDefinitionParser());
	}

}
```

在 `init()` 方法中可以看见，定义了对 `annotation-driven` 的解析器 `AnnotationDrivenBeanDefinitionParser`，它的 parse 方法如下：

```java
public BeanDefinition parse(Element element, ParserContext parserContext) {
 registerTransactionalEventListenerFactory(parserContext);
 String mode = element.getAttribute("mode");
 if ("aspectj".equals(mode)) {
  // mode="aspectj"
  registerTransactionAspect(element, parserContext);
  if (ClassUtils.isPresent("javax.transaction.Transactional", getClass().getClassLoader())) {
   registerJtaTransactionAspect(element, parserContext);
  }
 }
 else {
  // mode="proxy"
  AopAutoProxyConfigurer.configureAutoProxyCreator(element, parserContext);
 }
 return null;
}
```

这里读取了 mode 属性，但是一般都没有设置过，所以一般都是调用到了 `AopAutoProxyConfigurer#configureAutoProxyCreator` 中。

```java
public static void configureAutoProxyCreator(Element element, ParserContext parserContext) {
			// 注册 InfrastructureAdvisorAutoProxyCreator
			AopNamespaceUtils.registerAutoProxyCreatorIfNecessary(parserContext, element);
			// 事务的注解的 Advisor 的 beanName
			String txAdvisorBeanName = TransactionManagementConfigUtils.TRANSACTION_ADVISOR_BEAN_NAME;
			if (!parserContext.getRegistry().containsBeanDefinition(txAdvisorBeanName)) {
				// beanRegistry 中不存在 txAdvisorBeanName 这个 bean 时，需要手动注册一次
				Object eleSource = parserContext.extractSource(element);

				// 注册 AnnotationTransactionAttributeSource 的 BeanDefinition
				RootBeanDefinition sourceDef = new RootBeanDefinition(
						"org.springframework.transaction.annotation.AnnotationTransactionAttributeSource");
				sourceDef.setSource(eleSource);
				sourceDef.setRole(BeanDefinition.ROLE_INFRASTRUCTURE);
				String sourceName = parserContext.getReaderContext().registerWithGeneratedName(sourceDef);

				// 注册 TransactionInterceptor 的 BeanDefinition
				RootBeanDefinition interceptorDef = new RootBeanDefinition(TransactionInterceptor.class);
				interceptorDef.setSource(eleSource);
				interceptorDef.setRole(BeanDefinition.ROLE_INFRASTRUCTURE);
				registerTransactionManager(element, interceptorDef);
				// 将前面的 AnnotationTransactionAttributeSource 注入
				interceptorDef.getPropertyValues().add("transactionAttributeSource", new RuntimeBeanReference(sourceName));
				String interceptorName = parserContext.getReaderContext().registerWithGeneratedName(interceptorDef);

				// 注册 TransactionAttributeSourceAdvisor 的 BeanDefinition
				RootBeanDefinition advisorDef = new RootBeanDefinition(BeanFactoryTransactionAttributeSourceAdvisor.class);
				advisorDef.setSource(eleSource);
				advisorDef.setRole(BeanDefinition.ROLE_INFRASTRUCTURE);
				// 将前面的 AnnotationTransactionAttributeSource 和 TransactionInterceptor 一起注入
				advisorDef.getPropertyValues().add("transactionAttributeSource", new RuntimeBeanReference(sourceName));
				advisorDef.getPropertyValues().add("adviceBeanName", interceptorName);
				if (element.hasAttribute("order")) {
					advisorDef.getPropertyValues().add("order", element.getAttribute("order"));
				}
				parserContext.getRegistry().registerBeanDefinition(txAdvisorBeanName, advisorDef);

				CompositeComponentDefinition compositeDef = new CompositeComponentDefinition(element.getTagName(), eleSource);
				compositeDef.addNestedComponent(new BeanComponentDefinition(sourceDef, sourceName));
				compositeDef.addNestedComponent(new BeanComponentDefinition(interceptorDef, interceptorName));
				compositeDef.addNestedComponent(new BeanComponentDefinition(advisorDef, txAdvisorBeanName));
				parserContext.registerComponent(compositeDef);
			}
		}
```

这里会发现 `AopNamespaceUtils#registerAutoProxyCreatorIfNecessary` 很眼熟，在上一篇文章中将 AOP 的配置初始化时有提到一个 `AopNamespaceUtils#registerAspectJAnnotationAutoProxyCreatorIfNecessary` 方法，这两者的主要区别是，前者注册的是 InfrastructureAdvisorAutoProxyCreator，后者注册的是 AnnotationAwareAspectJAutoProxyCreator。

在注册了 InfrastructureAdvisorAutoProxyCreator 之后，就要开始注册一些必要的 BeanDefinition，这里注册了三个 BeanDefinition，分别是 AnnotationTransactionAttributeSource、TransactionInterceptor、TransactionAttributeSourceAdvisor，这里暂且先不细说其作用。仔细观察会发现，TransactionInterceptor 中注入了 AnnotationTransactionAttributeSource，而 TransactionAttributeSourceAdvisor 中把 AnnotationTransactionAttributeSource 和 TransactionInterceptor 都注入了。

![](http://image.hanelalo.cn/images/202111072035357.png)

## TransactionAttributeSourceAdvisor 对 bean 的适用性判断

在 [Spring-AOP原理](/2021/10/24/Spring-AOP原理/)中讲到过，创建代理之前，会先拿到所有的 Advisor，然后再根绝 beanClass 筛选出使用的 Advisor，那么每个 Advisor 肯定都有一套自己的适用规则的判断逻辑。接下来就看看怎么 TransactionAttributeSourceAdvisor 是如何判断适用性的。

在拿到所有的 Advisor 之后，会再筛选一次，Advisor 的适用性匹配逻辑就在其中，代码入口在  [Spring-AOP 原理](/2021/10/24/Spring-AOP原理/)中就能找到，这里主要关注其中的一个 `#canApply(Advisor advisor, Class<?> targetClass, boolean hasIntroductions)` 方法。

```java
	public static boolean canApply(Advisor advisor, Class<?> targetClass, boolean hasIntroductions) {
		if (advisor instanceof IntroductionAdvisor) {
			return ((IntroductionAdvisor) advisor).getClassFilter().matches(targetClass);
		}
		else if (advisor instanceof PointcutAdvisor) {
			PointcutAdvisor pca = (PointcutAdvisor) advisor;
			return canApply(pca.getPointcut(), targetClass, hasIntroductions);
		}
		else {
			// It doesn't have a pointcut so we assume it applies.
			return true;
		}
	}
```

这里又调用了重载的一个 `#canApply(Pointcut pc, Class<?> targetClass, boolean hasIntroductions)` 方法，传入的是一个 PointCut 对象，这个 PointCut 对象来自于 `advisor.getPointCut()`，这里我们只关注当 advisor 是 TransactionAttributeSourceAdvisor 的情况，查看它的源码发现它的 pointCut 属性如下：

```java
public class BeanFactoryTransactionAttributeSourceAdvisor extends AbstractBeanFactoryPointcutAdvisor {

	@Nullable
	private TransactionAttributeSource transactionAttributeSource;

	private final TransactionAttributeSourcePointcut pointcut = new TransactionAttributeSourcePointcut() {
		@Override
		@Nullable
		protected TransactionAttributeSource getTransactionAttributeSource() {
			return transactionAttributeSource;
		}
	};

    // other code...
    
	@Override
	public Pointcut getPointcut() {
		return this.pointcut;
	}

}
```

这里需要注意的是，pointCut 是初始化 BeanFactoryTransactionAttributeSourceAdvisor 时 new 出来的 TransactionAttributeSourcePointcut 对象，transactionAttributeSource 是在解析事务的配置 `<tx:annotation-driven>` 时注入的，这在上一节的内容中已经明确讲述了。

接下来再看拿到 pointCut 之后的处理。

```java
	public static boolean canApply(Pointcut pc, Class<?> targetClass, boolean hasIntroductions) {
		Assert.notNull(pc, "Pointcut must not be null");
		if (!pc.getClassFilter().matches(targetClass)) {
			return false;
		}

		MethodMatcher methodMatcher = pc.getMethodMatcher();
		if (methodMatcher == MethodMatcher.TRUE) {
			// No need to iterate the methods if we're matching any method anyway...
			return true;
		}

		IntroductionAwareMethodMatcher introductionAwareMethodMatcher = null;
		if (methodMatcher instanceof IntroductionAwareMethodMatcher) {
			introductionAwareMethodMatcher = (IntroductionAwareMethodMatcher) methodMatcher;
		}

		Set<Class<?>> classes = new LinkedHashSet<>();
		if (!Proxy.isProxyClass(targetClass)) {
			classes.add(ClassUtils.getUserClass(targetClass));
		}
		classes.addAll(ClassUtils.getAllInterfacesForClassAsSet(targetClass));

		for (Class<?> clazz : classes) {
			Method[] methods = ReflectionUtils.getAllDeclaredMethods(clazz);
			for (Method method : methods) {
				if (introductionAwareMethodMatcher != null ?
						introductionAwareMethodMatcher.matches(method, targetClass, hasIntroductions) :
						methodMatcher.matches(method, targetClass)) {
					return true;
				}
			}
		}
		return false;
	}
```

虽然代码有一大段，但是结合多个类来看这段逻辑及会发现最终调用的时 `#methodMatch.matchs(Method method, Class<?> targetClass)` 这个方法，这个 methodMatch 从 PointCut 中来，而此时的 PointCut 是 TransactionAttributeSourcePointcut 对象，所以接下来查看 TransactionAttributeSourcePointcut 的 matchs 方法。

```java
@Override
public boolean matches(Method method, Class<?> targetClass) {
 TransactionAttributeSource tas = getTransactionAttributeSource();
 return (tas == null || tas.getTransactionAttribute(method, targetClass) != null);
}
```

首先拿到了 TransactionAttributeSource 对象，这是在初始化配置时就已经注册了 BeanDefinition 的 AnnotationTransactionAttributeSource。

然后调用 AnnotationTransactionAttributeSource 的 getTransactionAttribute() 方法。

```java
public TransactionAttribute getTransactionAttribute(Method method, @Nullable Class<?> targetClass) {
 if (method.getDeclaringClass() == Object.class) {
  return null;
 }

 // First, see if we have a cached value.
 Object cacheKey = getCacheKey(method, targetClass);
 TransactionAttribute cached = this.attributeCache.get(cacheKey);
 if (cached != null) {
  // Value will either be canonical value indicating there is no transaction attribute,
  // or an actual transaction attribute.
  if (cached == NULL_TRANSACTION_ATTRIBUTE) {
   return null;
  }
  else {
   return cached;
  }
 }
 else {
  // We need to work it out.
  TransactionAttribute txAttr = computeTransactionAttribute(method, targetClass);
  // Put it in the cache.
  if (txAttr == null) {
   this.attributeCache.put(cacheKey, NULL_TRANSACTION_ATTRIBUTE);
  }
  else {
   String methodIdentification = ClassUtils.getQualifiedMethodName(method, targetClass);
   if (txAttr instanceof DefaultTransactionAttribute) {
    DefaultTransactionAttribute dta = (DefaultTransactionAttribute) txAttr;
    dta.setDescriptor(methodIdentification);
    dta.resolveAttributeStrings(this.embeddedValueResolver);
   }
   if (logger.isTraceEnabled()) {
    logger.trace("Adding transactional method '" + methodIdentification + "' with attribute: " + txAttr);
   }
   this.attributeCache.put(cacheKey, txAttr);
  }
  return txAttr;
 }
}
```

这个方法的主旨其实就是要解析 @Transactional 注解的内容，然后使用 TransactionAttribute 封装解析结果。

通过跟踪 computeTransactionAttribute() 方法，发现主要逻辑通过 findTransactionAttribute() 方法来实现，而最终来到了 `SpringTransactionAnnotationParser#parseTransactionAnnotation` 方法中。

```java
	public TransactionAttribute parseTransactionAnnotation(AnnotatedElement element) {
		AnnotationAttributes attributes = AnnotatedElementUtils.findMergedAnnotationAttributes(
				element, Transactional.class, false, false);
		if (attributes != null) {
			return parseTransactionAnnotation(attributes);
		}
		else {
			return null;
		}
	}
```

> 终于在这里看见了 @Transactional 注解。

首先获取了 @Transactional 的注解信息，然后再进行解析，这里主要关注解析逻辑。

```java
	protected TransactionAttribute parseTransactionAnnotation(AnnotationAttributes attributes) {
		RuleBasedTransactionAttribute rbta = new RuleBasedTransactionAttribute();
		// 事务传播类型
		Propagation propagation = attributes.getEnum("propagation");
		rbta.setPropagationBehavior(propagation.value());
		// 隔离级别
		Isolation isolation = attributes.getEnum("isolation");
		rbta.setIsolationLevel(isolation.value());
		// 超时时间
		rbta.setTimeout(attributes.getNumber("timeout").intValue());
		String timeoutString = attributes.getString("timeoutString");
		Assert.isTrue(!StringUtils.hasText(timeoutString) || rbta.getTimeout() < 0,
				"Specify 'timeout' or 'timeoutString', not both");
		rbta.setTimeoutString(timeoutString);
		// 是否只读
		rbta.setReadOnly(attributes.getBoolean("readOnly"));
		rbta.setQualifier(attributes.getString("value"));
		rbta.setLabels(Arrays.asList(attributes.getStringArray("label")));

		List<RollbackRuleAttribute> rollbackRules = new ArrayList<>();
		// 设置回滚策略
		for (Class<?> rbRule : attributes.getClassArray("rollbackFor")) {
			rollbackRules.add(new RollbackRuleAttribute(rbRule));
		}
		for (String rbRule : attributes.getStringArray("rollbackForClassName")) {
			rollbackRules.add(new RollbackRuleAttribute(rbRule));
		}
		for (Class<?> rbRule : attributes.getClassArray("noRollbackFor")) {
			rollbackRules.add(new NoRollbackRuleAttribute(rbRule));
		}
		for (String rbRule : attributes.getStringArray("noRollbackForClassName")) {
			rollbackRules.add(new NoRollbackRuleAttribute(rbRule));
		}
		rbta.setRollbackRules(rollbackRules);

		return rbta;
	}
```

这里也有了常见的几种配置的解析逻辑，比如事务传播方式、隔离级别、异常回滚策略等。

到现阶段，TransactionAttributeSourceAdvisor 在判断使用性的同时也初始化了 bean 的 @Transactionla 注解的解析逻辑。

当适用性的匹配成功过后，就来到了创建代理的过程。

## 数据库事务代理创建和执行

在 [Spring-AOP原理](/2021/10/24/Spring-AOP原理/)中就已经大概解析过创建代理的代码，以 Jdk 动态代理为例，最终来到 `JdkDynamicAopProxy#getProxy` 方法，我们知道在使用 Jdk 动态代理时，需要实现一个 InvocationHandler 接口，代理逻辑中会调用它的 invoke() 方法。

```java
	public Object getProxy(@Nullable ClassLoader classLoader) {
		if (logger.isTraceEnabled()) {
			logger.trace("Creating JDK dynamic proxy: " + this.advised.getTargetSource());
		}
		return Proxy.newProxyInstance(classLoader, this.proxiedInterfaces, this);
	}
```

这里传入的 InvokeHandler 接口就是 JdkDynamicAopProxy 自己，跟踪 JdkDynamicAopProxy 的 invoke 方法，只关注 TransactionAttributeSourceAdvisor 的话就能发现，最终调用到了 `TransactionInterceptor#invoke` 方法：

```java
	public Object invoke(MethodInvocation invocation) throws Throwable {
		Class<?> targetClass = (invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null);
		return invokeWithinTransaction(invocation.getMethod(), targetClass, new CoroutinesInvocationCallback() {
			@Override
			@Nullable
			public Object proceedWithInvocation() throws Throwable {
				return invocation.proceed();
			}
			@Override
			public Object getTarget() {
				return invocation.getThis();
			}
			@Override
			public Object[] getArguments() {
				return invocation.getArguments();
			}
		});
	}
```

直接调用了 `#invokeWithinTransaction` 方法，这个方法太长了，就不一股脑贴代码了。

首先获取了 TransactionAttributeSource，然后又拿到了 TransactionAttribute，然后通过 TransactionAttribute 又拿到了 TransactionManager 对象。

```java
TransactionAttributeSource tas = getTransactionAttributeSource();
final TransactionAttribute txAttr = (tas != null ? tas.getTransactionAttribute(method, targetClass) : null);
final TransactionManager tm = determineTransactionManager(txAttr);
```

这里的 TransactionAttributeSource 是在前面解析 xml 配置时就知道它时注入进来的，在筛选 Advisor 时，又初始化过了 TransactionAttribute 的缓存，所以这里的 tas 和 txAttr 两个变量通常不为 null。最后才拿到了 TransactionManager 的实例（这个一般情况下时需要自己定义这个 bean 要采用哪种 TransactionManager）。

然后是判断 TransactionManager 是不是 ReactiveTransactionManager 类型，本文先不关注，后面可以考虑加餐，所以直接掠过。

不是 ReactiveTransactionManager，那就默认是 PlatformTransactionManager 类型了，所以这里会对 TransactionManager 进行一次转型，如果失败了，就会抛异常了，紧接着获取需要代理的方法名称。

```java
PlatformTransactionManager ptm = asPlatformTransactionManager(tm);
final String joinpointIdentification = methodIdentification(method, targetClass, txAttr);
```

然后再判断 TransactionManager 是否是 `CallbackPreferringPlatformTransactionManager` 的实例，通常也不是。

```java
		if (txAttr == null || !(ptm instanceof CallbackPreferringPlatformTransactionManager)) {
			// Standard transaction demarcation with getTransaction and commit/rollback calls.
			// 创建事务
			TransactionInfo txInfo = createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

			Object retVal;
			try {
				// This is an around advice: Invoke the next interceptor in the chain.
				// This will normally result in a target object being invoked.
				// 执行事务逻辑（CRUD）
				retVal = invocation.proceedWithInvocation();
			}
			catch (Throwable ex) {
				// target invocation exception
				// 失败回滚逻辑
				completeTransactionAfterThrowing(txInfo, ex);
				throw ex;
			}
			finally {
				cleanupTransactionInfo(txInfo);
			}

			if (retVal != null && vavrPresent && VavrDelegate.isVavrTry(retVal)) {
				// Set rollback-only in case of Vavr failure matching our rollback rules...
				TransactionStatus status = txInfo.getTransactionStatus();
				if (status != null && txAttr != null) {
					retVal = VavrDelegate.evaluateTryFailure(retVal, txAttr, status);
				}
			}
			// 提交
			commitTransactionAfterReturning(txInfo);
			return retVal;
		}
```

这个看起来就像极了我们在找的逻辑了。

代码中已经加了注释，可以看见比较清晰的划分了 4 步：

1. 创建事务
2. 执行事务逻辑（CRUD）
3. 如果失败，根据配置回滚事务并抛异常
4. 提交事务

接下来一步一步分析事务的执行。

### 创建事务

```java
	protected TransactionInfo createTransactionIfNecessary(@Nullable PlatformTransactionManager tm,
			@Nullable TransactionAttribute txAttr, final String joinpointIdentification) {

		// some other code...

		TransactionStatus status = null;
		if (txAttr != null) {
			if (tm != null) {
				status = tm.getTransaction(txAttr);
			}
			else {
				// log...
			}
		}
		return prepareTransactionInfo(tm, txAttr, joinpointIdentification, status);
	}
```

总体上就是获取事务状态 TransactionStatus，然后封装 TransactionInfo。

先看看获取事务状态，这里面就有了对于不同的事务传播方式、隔离级别的差异化处理。

```java
	public final TransactionStatus getTransaction(@Nullable TransactionDefinition definition)
			throws TransactionException {

		// Use defaults if no transaction definition given.
		TransactionDefinition def = (definition != null ? definition : TransactionDefinition.withDefaults());
		// 获取事务实例
		Object transaction = doGetTransaction();
		boolean debugEnabled = logger.isDebugEnabled();
		// 当前线程中是否已经存在了事务
		if (isExistingTransaction(transaction)) {
			// 处理线程中已经存在事务的情况
			return handleExistingTransaction(def, transaction, debugEnabled);
		}
		// 检查超时时间配置是否有效
		if (def.getTimeout() < TransactionDefinition.TIMEOUT_DEFAULT) {
			throw new InvalidTimeoutException("Invalid transaction timeout", def.getTimeout());
		}
		// 进行不存在事务的处理
		// 如果事务传播方式是 PROPAGATION_MANDATORY, 直接抛异常
		if (def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_MANDATORY) {
			throw new IllegalTransactionStateException(
					"No existing transaction found for transaction marked with propagation 'mandatory'");
		}
		else if (def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRED ||
				def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW ||
				def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {
			// 如果当前事务传播类型是 必须有事务、必须新建事务、嵌套事务中的一种
			// 挂起已有事务，但因为当前不存在事务，所以传了 null
			SuspendedResourcesHolder suspendedResources = suspend(null);
			if (debugEnabled) {
				logger.debug("Creating new transaction with name [" + def.getName() + "]: " + def);
			}
			try {
				// 开始事务
				return startTransaction(def, transaction, debugEnabled, suspendedResources);
			}
			catch (RuntimeException | Error ex) {
				resume(null, suspendedResources);
				throw ex;
			}
		}
		else {
			// Create "empty" transaction: no actual transaction, but potentially synchronization.
			if (def.getIsolationLevel() != TransactionDefinition.ISOLATION_DEFAULT && logger.isWarnEnabled()) {
				logger.warn("Custom isolation level specified but no actual transaction initiated; " +
						"isolation level will effectively be ignored: " + def);
			}
			boolean newSynchronization = (getTransactionSynchronization() == SYNCHRONIZATION_ALWAYS);
			return prepareTransactionStatus(def, null, true, newSynchronization, debugEnabled, null);
		}
	}
```

1. 获取事务实例

```java
	protected Object doGetTransaction() {
		// 创建基于 JDBC 的事务
		DataSourceTransactionObject txObject = new DataSourceTransactionObject();
		// 设置保存点, 从方法名可以看出这里还取决于是否支持嵌套事务，默认是 true
		txObject.setSavepointAllowed(isNestedTransactionAllowed());
		// 获取数据库连接，如果当前线程已经持有了数据库连接，就会使用原有的连接
		ConnectionHolder conHolder =
				(ConnectionHolder) TransactionSynchronizationManager.getResource(obtainDataSource());
		txObject.setConnectionHolder(conHolder, false);
		return txObject;
	}
```

这里使用的是 DataSourceTransactionManager，所以创建的是基于 JDBC 的事务实例，然后根据是否支持嵌套事务来设置是否允许保存点，最后获取数据库连接，如果当前线程中已经持有了数据库连接，就会使用已有的连接。

2. 当前线程已存在事务的处理

如果当前线程已经存在事务，就开始进行线程以存在事务的处理逻辑。

```java
		// 当前线程中是否已经存在了事务
		if (isExistingTransaction(transaction)) {
			// 处理线程中已经存在事务的情况
			return handleExistingTransaction(def, transaction, debugEnabled);
		}
```

3. 检查超时设置是由有效
4. 如果事务传播类型验证，如果是 PROPAGATION_MANDATORY，直接抛异常，如果当前事务传播类型是 必须有事务、必须新建事务、嵌套事务中的一种，调用 startTransaction() 创建新的事务，构建 TransactionStatus。

整个过程中，需要注意接下来要讲的四种操作。

#### 创建新事务

```java
	private TransactionStatus startTransaction(TransactionDefinition definition, Object transaction,
			boolean debugEnabled, @Nullable SuspendedResourcesHolder suspendedResources) {

		boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
		DefaultTransactionStatus status = newTransactionStatus(
				definition, transaction, true, newSynchronization, debugEnabled, suspendedResources);
		doBegin(transaction, definition);
		prepareSynchronization(status, definition);
		return status;
	}
```

> newTransactionStatus 方法的第三个参数表示是否创建新的事务。

不管是什么传播类型，只要需要事务，都是从 doBegin() 这个方法才真的开启了本次事务。

```java
	protected void doBegin(Object transaction, TransactionDefinition definition) {
		DataSourceTransactionObject txObject = (DataSourceTransactionObject) transaction;
		Connection con = null;

		try {
			// 判断当前线程是否已经建立了数据库连接
			if (!txObject.hasConnectionHolder() ||
					txObject.getConnectionHolder().isSynchronizedWithTransaction()) {
				// 如果没有数据库连接，则获取数据库连接，构建新的 ConnectionHolder 对象
				Connection newCon = obtainDataSource().getConnection();
				if (logger.isDebugEnabled()) {
					logger.debug("Acquired Connection [" + newCon + "] for JDBC transaction");
				}
				txObject.setConnectionHolder(new ConnectionHolder(newCon), true);
			}

			txObject.getConnectionHolder().setSynchronizedWithTransaction(true);
			con = txObject.getConnectionHolder().getConnection();
			// 准备事务，主要是设置只读事务标识和隔离级别
			Integer previousIsolationLevel = DataSourceUtils.prepareConnectionForTransaction(con, definition);
			txObject.setPreviousIsolationLevel(previousIsolationLevel);
			txObject.setReadOnly(definition.isReadOnly());
			// 关闭自动提交
			if (con.getAutoCommit()) {
				txObject.setMustRestoreAutoCommit(true);
				if (logger.isDebugEnabled()) {
					logger.debug("Switching JDBC Connection [" + con + "] to manual commit");
				}
				con.setAutoCommit(false);
			}
			// 如果是只读事务，先直接执行 sql，将当前事务变为只读事务
			prepareTransactionalConnection(con, definition);
			// 表示事务已经激活，设置激活标识
			txObject.getConnectionHolder().setTransactionActive(true);
			// 设置超时时间
			int timeout = determineTimeout(definition);
			if (timeout != TransactionDefinition.TIMEOUT_DEFAULT) {
				txObject.getConnectionHolder().setTimeoutInSeconds(timeout);
			}

			// 如果是新建立的数据库连接，将连接的引用绑定到线程的上下文中
			if (txObject.isNewConnectionHolder()) {
				TransactionSynchronizationManager.bindResource(obtainDataSource(), txObject.getConnectionHolder());
			}
		}

		catch (Throwable ex) {
			// 如果出错了，并且是新建立的连接，那么就将连接释放并抛出异常
			if (txObject.isNewConnectionHolder()) {
				DataSourceUtils.releaseConnection(con, obtainDataSource());
				txObject.setConnectionHolder(null, false);
			}
			throw new CannotCreateTransactionException("Could not open JDBC Connection for transaction", ex);
		}
	}
```

1. 首先是判断当前线程是否已经持有数据库连接，这里需要注意的是，数据库连接和线程的 ThreadLocal 绑定时，还有 dataSource 做映射，也就是说，这个判断针对的是同一个 DataSource，是否在线程中已经持有连接。
2. 如果没有连接，则创建一个。
3. 修改连接对象的配置，为事务做准备，修改的配置主要是设置是否为只读事务标识和隔离级别。
4. 如果当前连接时自动提交，则关闭自动提交。
5. 如果是只读事务，则执行 sql，将当前事务设置为只读事务，在此之前只读事务只是内存中的一个对象的标识，这一步之后，数据库中为这个连接开启的事务就真的是只读事务了。
6. 设置事务已经激活的标识。
7. 设置事务超时时间。
8. 如果是新建的连接，将连接绑定到上下文中。
9. 如果以上步骤失败，且是新建的连接，就需要将连接释放。

现在再看看第 8 步，是如何跟线程绑定的。

```java
	private static final ThreadLocal<Map<Object, Object>> resources =
			new NamedThreadLocal<>("Transactional resources");

	public static void bindResource(Object key, Object value) throws IllegalStateException {
		Object actualKey = TransactionSynchronizationUtils.unwrapResourceIfNecessary(key);
		Assert.notNull(value, "Value must not be null");
		Map<Object, Object> map = resources.get();
		// set ThreadLocal Map if none found
		if (map == null) {
			map = new HashMap<>();
			resources.set(map);
		}
		Object oldValue = map.put(actualKey, value);
		// Transparently suppress a ResourceHolder that was marked as void...
		if (oldValue instanceof ResourceHolder && ((ResourceHolder) oldValue).isVoid()) {
			oldValue = null;
		}
		if (oldValue != null) {
			throw new IllegalStateException("Already value [" + oldValue + "] for key [" +
					actualKey + "] bound to thread [" + Thread.currentThread().getName() + "]");
		}
		if (logger.isTraceEnabled()) {
			logger.trace("Bound value [" + value + "] for key [" + actualKey + "] to thread [" +
					Thread.currentThread().getName() + "]");
		}
	}
```

可以看见，这里其实就是以 dataSource 为 key，以数据库连接对象为 value，放进了一个 ThreadLocal 维护的 map 里面，以此达到和线程绑定的目的。

开始了事务之后，还会调用 prepareSynchronization() 方法，将当前事务的状态记录到线程中。

```java
	protected void prepareSynchronization(DefaultTransactionStatus status, TransactionDefinition definition) {
		if (status.isNewSynchronization()) {
			TransactionSynchronizationManager.setActualTransactionActive(status.hasTransaction());
			TransactionSynchronizationManager.setCurrentTransactionIsolationLevel(
					definition.getIsolationLevel() != TransactionDefinition.ISOLATION_DEFAULT ?
							definition.getIsolationLevel() : null);
			TransactionSynchronizationManager.setCurrentTransactionReadOnly(definition.isReadOnly());
			TransactionSynchronizationManager.setCurrentTransactionName(definition.getName());
			TransactionSynchronizationManager.initSynchronization();
		}
	}
```

#### 处理已存在的事务

```java
    private TransactionStatus handleExistingTransaction(
      TransactionDefinition definition, Object transaction, boolean debugEnabled)
      throws TransactionException {
     // 如果是不允许事务，而当前线程中有事务，直接抛异常
     if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NEVER) {
      throw new IllegalTransactionStateException(
        "Existing transaction found for transaction marked with propagation 'never'");
     }
     // 如果是不支持事务，直接将当前线程中已经存在的事务挂起
     if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NOT_SUPPORTED) {
      if (debugEnabled) {
       logger.debug("Suspending current transaction");
      }
      Object suspendedResources = suspend(transaction);
      boolean newSynchronization = (getTransactionSynchronization() == SYNCHRONIZATION_ALWAYS);
      return prepareTransactionStatus(
        definition, null, false, newSynchronization, debugEnabled, suspendedResources);
     }
     // 如果是必须新建事务，则挂起线程中已有的事务，开启新的事务
     if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW) {
      if (debugEnabled) {
       logger.debug("Suspending current transaction, creating new transaction with name [" +
         definition.getName() + "]");
      }
      SuspendedResourcesHolder suspendedResources = suspend(transaction);
      try {
       return startTransaction(definition, transaction, debugEnabled, suspendedResources);
      }
      catch (RuntimeException | Error beginEx) {
       resumeAfterBeginException(transaction, suspendedResources, beginEx);
       throw beginEx;
      }
     }
     // 如果是嵌套事务
     if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {
      // 如果事务传播类型是嵌套事务，但是又不支持嵌套事务，抛异常
      if (!isNestedTransactionAllowed()) {
       throw new NestedTransactionNotSupportedException(
         "Transaction manager does not allow nested transactions by default - " +
         "specify 'nestedTransactionAllowed' property with value 'true'");
      }
      if (debugEnabled) {
       logger.debug("Creating nested transaction with name [" + definition.getName() + "]");
      }
      // 是否以你 savePoint 的方式实现嵌套事务
      if (useSavepointForNestedTransaction()) {
       // 在已存在的事务中创建 savepoint，因为是嵌套事务，所以也不需要挂起原来的事务
       DefaultTransactionStatus status =
         prepareTransactionStatus(definition, transaction, false, false, debugEnabled, null);
       status.createAndHoldSavepoint();
       return status;
      }
      else {
       // 直接开启新的事务
       return startTransaction(definition, transaction, debugEnabled, null);
      }
     }

     // Assumably PROPAGATION_SUPPORTS or PROPAGATION_REQUIRED.
     if (debugEnabled) {
      logger.debug("Participating in existing transaction");
     }
     if (isValidateExistingTransaction()) {
      if (definition.getIsolationLevel() != TransactionDefinition.ISOLATION_DEFAULT) {
       Integer currentIsolationLevel = TransactionSynchronizationManager.getCurrentTransactionIsolationLevel();
       if (currentIsolationLevel == null || currentIsolationLevel != definition.getIsolationLevel()) {
        Constants isoConstants = DefaultTransactionDefinition.constants;
        throw new IllegalTransactionStateException("Participating transaction with definition [" +
          definition + "] specifies isolation level which is incompatible with existing transaction: " +
          (currentIsolationLevel != null ?
            isoConstants.toCode(currentIsolationLevel, DefaultTransactionDefinition.PREFIX_ISOLATION) :
            "(unknown)"));
       }
      }
      if (!definition.isReadOnly()) {
       if (TransactionSynchronizationManager.isCurrentTransactionReadOnly()) {
        throw new IllegalTransactionStateException("Participating transaction with definition [" +
          definition + "] is not marked as read-only but existing transaction is");
       }
      }
     }
     boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
     return prepareTransactionStatus(definition, transaction, false, newSynchronization, debugEnabled, null);
    }
```

针对已经存在事务的处理，Spring 提供了 4 中类型的处理方式。

* PROPAGATION_NEVER

  不允许事务，当前线程中都不允许存在事务，所以直接抛异常。

* PROPAGATION_NOT_SUPPORTED

  不支持事务，如果当前线程中有事务开启，将该事务挂起，以无事务的方式执行。

* PROPAGATION_REQUIRES_NEW

  必须新建事务，将当前事务挂起，新建事务执行。

* PROPAGATION_NESTED

  嵌套事务，有两种实现方式，一种是通过 savePoint 实现，一种是直接开启新事务执行，这两种都不会挂起原有事务。

上面的代码，除了上一节讲到的 startTransaction 方法，还有一个 prepareTransactionStatus 方法。

```java
	protected final DefaultTransactionStatus prepareTransactionStatus(
			TransactionDefinition definition, @Nullable Object transaction, boolean newTransaction,
			boolean newSynchronization, boolean debug, @Nullable Object suspendedResources) {
		// 构建 DefaultTransactionStatus
		DefaultTransactionStatus status = newTransactionStatus(
				definition, transaction, newTransaction, newSynchronization, debug, suspendedResources);
		// 保存事务信息到线程上下文中，这里和开始新事务的区别主要是还是在于没有调用 doBegin() 方法
		prepareSynchronization(status, definition);
		return status;
	}
```

这个方法一般都是以不新建事务的方式执行的，所以比 startTransaction 少调用了 doBegin 方法来启动事务。

#### 挂起事务

在前面提到过，事务和线程绑定是，通过 DataSource 和 ThreadLocal 来实现，现在要将事务挂起，可以理解为暂停事务，那么只要在这个要被挂起的事务上暂时不再做任何操作即可，要实现这种操作，只需要将这种绑定关系断开即可，其实挂起事务就是这样做的。

```java
	protected final SuspendedResourcesHolder suspend(@Nullable Object transaction) throws TransactionException {
		if (TransactionSynchronizationManager.isSynchronizationActive()) {
			List<TransactionSynchronization> suspendedSynchronizations = doSuspendSynchronization();
			try {
				Object suspendedResources = null;
				if (transaction != null) {
					// 挂起事务，并返回挂起事务的连接，这里其实返回的是 ConnectionHolder
					suspendedResources = doSuspend(transaction);
				}
				// 挂起事务后，设置线程中的事务信息
				String name = TransactionSynchronizationManager.getCurrentTransactionName();
				TransactionSynchronizationManager.setCurrentTransactionName(null);
				boolean readOnly = TransactionSynchronizationManager.isCurrentTransactionReadOnly();
				TransactionSynchronizationManager.setCurrentTransactionReadOnly(false);
				Integer isolationLevel = TransactionSynchronizationManager.getCurrentTransactionIsolationLevel();
				TransactionSynchronizationManager.setCurrentTransactionIsolationLevel(null);
				boolean wasActive = TransactionSynchronizationManager.isActualTransactionActive();
				TransactionSynchronizationManager.setActualTransactionActive(false);
				// 构建挂起事务的 Holder
				return new SuspendedResourcesHolder(
						suspendedResources, suspendedSynchronizations, name, readOnly, isolationLevel, wasActive);
			}
			catch (RuntimeException | Error ex) {
				// doSuspend failed - original transaction is still active...
				// 如果抛出异常，需要将挂起的事务再次绑定到线程上下文中
				doResumeSynchronization(suspendedSynchronizations);
				throw ex;
			}
		}
		else if (transaction != null) {
			// Transaction active but no synchronization active.
			Object suspendedResources = doSuspend(transaction);
			return new SuspendedResourcesHolder(suspendedResources);
		}
		else {
			// Neither transaction nor synchronization active.
			return null;
		}
	}
```

1. 挂起事务，拿到被挂起的事务的连接信息 ConnectionHolder。
2. 事务挂起后，更新线程中记录的事务信息。
3. 构建挂起事务的资源的 SuspendedResourcesHolder。
4. 如果抛出异常，需要接触事务的挂起状态。

最核心的逻辑在于 doSuspend 方法：

```java
	protected Object doSuspend(Object transaction) {
		DataSourceTransactionObject txObject = (DataSourceTransactionObject) transaction;
		txObject.setConnectionHolder(null);
		// 挂起事务的方式其实就是将数据库连接和线程的绑定断开，并返回连接信息对象，这里返回的连接信息会被新的事务对象持有，方便后面解挂
		return TransactionSynchronizationManager.unbindResource(obtainDataSource());
	}
```

```java
	public static Object unbindResource(Object key) throws IllegalStateException {
		Object actualKey = TransactionSynchronizationUtils.unwrapResourceIfNecessary(key);
		Object value = doUnbindResource(actualKey);
		if (value == null) {
			throw new IllegalStateException(
					"No value for key [" + actualKey + "] bound to thread [" + Thread.currentThread().getName() + "]");
		}
		return value;
	}
```

```java
	private static Object doUnbindResource(Object actualKey) {
		Map<Object, Object> map = resources.get();
		if (map == null) {
			return null;
		}
		Object value = map.remove(actualKey);
		// Remove entire ThreadLocal if empty...
		if (map.isEmpty()) {
			resources.remove();
		}
		// Transparently suppress a ResourceHolder that was marked as void...
		if (value instanceof ResourceHolder && ((ResourceHolder) value).isVoid()) {
			value = null;
		}
		if (value != null && logger.isTraceEnabled()) {
			logger.trace("Removed value [" + value + "] for key [" + actualKey + "] from thread [" +
					Thread.currentThread().getName() + "]");
		}
		return value;
	}
```

最终追踪到 doUnbindResource 方法中，果然是将线程的 ThreadLocal 中的数据库连接删除。

### 提交和回滚事务

这两个倒是没什么可讲的，其实最终都是通过 connection 对象来提交或者回滚而已，只不过回滚之前还会有一个 Exception 的匹配逻辑。







