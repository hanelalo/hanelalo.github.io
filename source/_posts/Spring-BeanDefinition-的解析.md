---
title: 'Spring: BeanDefinition 的解析'
date: 2021-08-25 23:08:32
tags: Spring
categories: Spring
cover: http://image.hanelalo.cn/images/202111061316748.jpg
---

# Resource 接口

在 Spring 中，配置 bean 的方式有很多，可以是 xml，可以是 Java 代码，可以是注解，甚至配置文件可以在 classpath 下，也可以在操作系统的文件系统中或者在一个远程的服务器中，这些资源，都统一抽象成了一个 Resource 接口，不同的资源类型对应不同的实现。

```java
public interface Resource extends InputStreamSource {

    boolean exists();

    default boolean isReadable() {
        return exists();
    }
    
    default boolean isOpen() {
        return false;
    }

    default boolean isFile() {
        return false;
    }

    URL getURL() throws IOException;

    URI getURI() throws IOException;

    File getFile() throws IOException;

    default ReadableByteChannel readableChannel() throws IOException {
        return Channels.newChannel(getInputStream());
    }

    long contentLength() throws IOException;

    long lastModified() throws IOException;

    Resource createRelative(String relativePath) throws IOException;

    @Nullable
    String getFilename();

    String getDescription();
}
```

Resource 接口的方法，从名字上就能体现出其功能。

# ResourceLoader 接口

对于不同的资源类型，从一个资源地址到一个 Resource 对象的转换，这个过程，Spring 交给了 ResourceLoader 接口完成，查看 ClassPathXmlApplicationContext 的源码可以知道，它本身就实现了 ResourceLoader 接口。

# BeanDefinition 接口

bean 定义，是对一个 bean 的描述信息，比如是否是单例、是否延迟加载、依赖哪些 bean 等等，配置文件中对于每个 bean 的配置，解析之后就是一个具体的 BeanDefinition 对象。

BeanDefinition 有一个抽象的子类 AbstractBeanDefinition，其中有专门的属性记录 bean 的 scope、是否延迟加载、构造函数参数等。

```java
public abstract class AbstractBeanDefinition extends BeanMetadataAttributeAccessor
        implements BeanDefinition, Cloneable {
    
    @Nullable
    private volatile Object beanClass;

    @Nullable
    private String scope = SCOPE_DEFAULT;

    private boolean abstractFlag = false;

    @Nullable
    private Boolean lazyInit;  
    
    // ...
}
```

# DefaultListableBeanFactory 类

BeanFactory、SingletonBeanRegistry、AliasRegistry 的实现类。

![DefaultListableBeanFactory](/img/post/DefaultListableBeanFactory.png)

- AliasRegistry 别名管理接口，BeanDefinitionRegistry 的超级父接口，提供别名的注册、删除、查询、判断等能力
- SimpleAliasRgistry  AliasRegistry 的一个基础功能的实现，基于一个 ConcurrentHashMap 的增删改查。
- BeanDefinitionRegistry 在 AliasRegistry 基础上提供对 BeanDefinition 进行操作的公共能力，BeanDefinition 的注册、删除、查询，通过 beanName 判断 BeanDefinition 是否存在，获取已有的 BeanDefinition 的名字
- SingletonBeanRegistry  提供单例 bean 的管理能力
- BeanFactory  Spring Bean 容器的抽象，提供各种获取 Bean 的能力
- ListableBeanFactory  BeanFactory 子接口，提供各种条件获取 Bean 的能力，主要是枚举容器中的 bean
- HierarchicalBeanFactory  BeanFactory 子接口，增加对 ParentBeanFactory 的支持
- DefaultSingletonBeanFactory  SingletonBeanRegistry 的实现
- FactoryBeanRegistrySupport   在 DefaultSingletonBeanFactory 基础上增加 FactoryBean 的支持
- ConfigurationBeanFactory  HierarchicalBeanFactory 和 SingletonBeanRegistry 子接口，提供配置 BeanFactory 的能力
- AutowireCapableBeanFactory  BeanFactory 子接口，在 BeanFactory 基础上增加自动装配的能力，以及创建和注销 bean
- AbstractBeanFactory  BeanFactory 的实现基类，实现了 ConfigurableBeanFactory 的所有能力，同时也继承了 FactoryBeanRegistrySupport，这里终于将 Bean 的 Registry 系列接口和 BeanFactory 系列接口融合到了一起。
- ConfigurableListableBeanFactory  ListableBeanFactory 、ConfigurationBeanFactory、AutowireCapableBeanFactory 的子接口，主要提供忽略接口的能力
- AbstractAutowiredCapableBeanFactory   AbstractBeanFactory 的子类，因为实现了 AutowireCapableBeanFactory 接口，所以具备了自动注入能力
- DefaultListableBeanFactory  聚合了上面所有的功能

# Xml 配置下的 BeanDefinition 解析

在 Spring 源码中有 ClassPathApplicationContextTests.testSingleConfigLocaltion() 测试方法：

```xml
    @Test
    public void testSingleConfigLocation() {
        ClassPathXmlApplicationContext ctx = new ClassPathXmlApplicationContext(FQ_SIMPLE_CONTEXT);
        assertThat(ctx.containsBean("someMessageSource")).isTrue();
        ctx.close();
    }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE beans PUBLIC "-//SPRING//DTD BEAN 2.0//EN" "https://www.springframework.org/dtd/spring-beans-2.0.dtd">
<beans>
    <bean id="someMessageSource" name="yourMessageSource"
            class="org.springframework.context.support.StaticMessageSource"/>
    <bean class="org.springframework.context.support.ClassPathXmlApplicationContext" lazy-init="true">
        <constructor-arg value="someNonExistentFile.xml"/>
    </bean>
</beans>
```

初始化 ClassPathXmlApplicationContext 的流程在其父类 AbstractApplicationContext 中：

```java
    @Override
    public void refresh() throws BeansException, IllegalStateException {
        synchronized (this.startupShutdownMonitor) {
            StartupStep contextRefresh = this.applicationStartup.start("spring.context.refresh");

            // Prepare this context for refreshing.
            prepareRefresh();

            // Tell the subclass to refresh the internal bean factory.
            // 获取一个 BeanFactory，其实是告诉具体的实现类创建 BeadFactory, 解析出 BeanDefinition
            ConfigurableListableBeanFactory beanFactory = obtainFreshBeanFactory();

            // Prepare the bean factory for use in this context.
            // BeanFactory 使用前的前序处理，比如 ClassLoader 和 post-processor 的设置
            prepareBeanFactory(beanFactory);

            try {
                // Allows post-processing of the bean factory in context subclasses.
                // 在标准初始化之后，修改应用程序上下文的内部 Bean 工厂。所有 BeanDefinition 都将被加载，
                // 但尚未实例化任何bean。这允许在某些 ApplicationContext 实现中注册特殊的 BeanPostProcessor 等。
                postProcessBeanFactory(beanFactory);

                StartupStep beanPostProcess = this.applicationStartup.start("spring.context.beans.post-process");
                // Invoke factory processors registered as beans in the context.
                // BeanFactory 初始化后处理，这里会将 @Configuration 配置类 @Bean 修饰的 method 注册到 beanDefinitionMap
                invokeBeanFactoryPostProcessors(beanFactory);

                // Register bean processors that intercept bean creation.
                // 注册 Bean 初始化前后处理器 BeanPostProcessor
                registerBeanPostProcessors(beanFactory);
                beanPostProcess.end();

                // Initialize message source for this context.
                // 初始化一些国际化配置信息
                initMessageSource();

                // Initialize event multicaster for this context.
                // 应用初始化事件广播
                initApplicationEventMulticaster();

                // Initialize other special beans in specific context subclasses.
                // 初始化其他的特殊 bean， 这是一个提供给子类实现的方法
                // 可以重写的模板方法以添加特定于上下文的刷新工作。在实例化单例之前，先指定一些 bean 初始化。
                onRefresh();

                // Check for listener beans and register them.
                registerListeners();

                // Instantiate all remaining (non-lazy-init) singletons.
                // 完成此上下文的bean工厂的初始化，初始化所有剩余的单例 bean。
                finishBeanFactoryInitialization(beanFactory);

                // Last step: publish corresponding event.
                // 发布事件
                finishRefresh();
            }

            catch (BeansException ex) {
                if (logger.isWarnEnabled()) {
                    logger.warn("Exception encountered during context initialization - " +
                            "cancelling refresh attempt: " + ex);
                }

                // Destroy already created singletons to avoid dangling resources.
                destroyBeans();

                // Reset 'active' flag.
                cancelRefresh(ex);

                // Propagate exception to caller.
                throw ex;
            }

            finally {
                // Reset common introspection caches in Spring's core, since we
                // might not ever need metadata for singleton beans anymore...
                resetCommonCaches();
                contextRefresh.end();
            }
        }
    }
```

在第 11 行，创建了一个 ConfigurableListableBeanFactory，这里就是进行 BeanDefinition 的加载，然后跟踪到 AbstractRefreshableApplicationContext 中：

```java
    protected final void refreshBeanFactory() throws BeansException {
        // 如果当前存在 beanFactory，就销毁掉，创建一个新的
        if (hasBeanFactory()) {
            destroyBeans();
            closeBeanFactory();
        }
        try {
            // 实例化一个 beanFactory
            DefaultListableBeanFactory beanFactory = createBeanFactory();
            beanFactory.setSerializationId(getId());
            customizeBeanFactory(beanFactory);
            // 加载 beanDefinition
            loadBeanDefinitions(beanFactory);
            this.beanFactory = beanFactory;
        }
        catch (IOException ex) {
            throw new ApplicationContextException("I/O error parsing bean definition source for " + getDisplayName(), ex);
        }
    }
```

- 创建了一个 DefaultListableBeanFactory，这个类前面讲过
- 设置 beanFactory 的序列号
- `customizeBeanFactory()` 方法自定义配置，protected 修饰的，留给子类自定义实现
- 加载 BeanDefinition，这里开始解析配置文件并加载 BeanDefinition

loadBeanDefinitions() 是一个抽象方法，在 ClassPathXmlApplicationContext 的父类 AbstractXmlApplicationContext 中有实现：

```java
    protected void loadBeanDefinitions(DefaultListableBeanFactory beanFactory) throws BeansException, IOException {
        // Create a new XmlBeanDefinitionReader for the given BeanFactory.
        // 用来阅读实际的 Xml 文件的功能实现，注意这里将 beanFactory 放进去了
        // 后面解析 xml 会将 BeanDefinition 放到 beanFactory 中
        XmlBeanDefinitionReader beanDefinitionReader = new XmlBeanDefinitionReader(beanFactory);

        // Configure the bean definition reader with this context's
        // resource loading environment.
        beanDefinitionReader.setEnvironment(this.getEnvironment());
        beanDefinitionReader.setResourceLoader(this);
        beanDefinitionReader.setEntityResolver(new ResourceEntityResolver(this));

        // Allow a subclass to provide custom initialization of the reader,
        // then proceed with actually loading the bean definitions.
        initBeanDefinitionReader(beanDefinitionReader);
        // 开始真正 load BeanDefinition
        loadBeanDefinitions(beanDefinitionReader);
    }
```

可以看见这个方法创建了一个 XmlBeanDefinitionReader 对象，然后调用了另一个 loadBeanDefinitions() 方法，其实就是通过 XmlBeanDefinitionReader 读取并加载 BeanDefinition。初始化 XmlBeanDefinitionReader 时传入了一个 BeanDefinitionRegistry 对象，从前面的代码可以知道其实就是传的 DefaultListbleBeanFactory。除此之外，还设置了一个 ResourceLoader，就是当前的 ClassPathXmlApplicationContext 对象。XmlBeanDefinitionReader 其实就是用来加载 BeanDefinition 的。

```
    public XmlBeanDefinitionReader(BeanDefinitionRegistry registry) {
        super(registry);
    }
```

## XmlBeanDefinitionReader 加载 BeanDefinition

```java
    protected void loadBeanDefinitions(XmlBeanDefinitionReader reader) throws BeansException, IOException {
        // 这里其实是最开始穿配置文件的资源对象
        // 1.这里会判断当前是否拿到了配置资源对象，
        Resource[] configResources = getConfigResources();
        if (configResources != null) {
            // 2.如果有，就直接通过资源对象解析 BeanDefinition
            reader.loadBeanDefinitions(configResources);
        }
        // 3. 判断是否有配置文件的路径信息
        String[] configLocations = getConfigLocations();
        if (configLocations != null) {
            // 4. 如果有，解析 Xml 为 BeanDefinition，这里最终依然会拿到配置文件的配置资源对象，
            // 然后调用上面的 loadBeanDefinitions
            // 注意这里有两个 loadBeanDefinitions() 方法，但是入参一个是 Resource 对象，
            // 一个是配置文件的路径，后者最终依然会调到入参是 Resource 对象的 loadBeanDefinitions()
            reader.loadBeanDefinitions(configLocations);
        }
    }
```

XmlBeanDefinitionReader 本身提供了两种方式 load，一种是直接通过准备好的 Resource 对象加载，一种是通过资源配置文件地址加载。第二种方式其实依然会通过 ResourceLoader 将配置文件加载称为 Resource 对象，然后调用第一种方式的逻辑，所以着重理解第一种方式的原理，最终调用到 XmlBeanDefinitionReader 的 loadBeanDefinitions(EncodedResource encodedResource) 方法，EncodedResource  并不是一种特定的资源类型的抽象，而是以特定编码持有的 Resource，它内部维护了一个 Resource 对象，而不是实现 Resource 接口。

```java
public class EncodedResource implements InputStreamSource {
    private final Resource resource;
    @Nullable
    private final String encoding;
    @Nullable
    private final Charset charset;
    /**
     * Create a new {@code EncodedResource} for the given {@code Resource},
     * not specifying an explicit encoding or {@code Charset}.
     * @param resource the {@code Resource} to hold (never {@code null})
     */
    public EncodedResource(Resource resource) {
        this(resource, null, null);
    }
}
    public int loadBeanDefinitions(EncodedResource encodedResource) throws BeanDefinitionStoreException {
        Assert.notNull(encodedResource, "EncodedResource must not be null");
        if (logger.isTraceEnabled()) {
            logger.trace("Loading XML bean definitions from " + encodedResource);
        }

        Set<EncodedResource> currentResources = this.resourcesCurrentlyBeingLoaded.get();

        if (!currentResources.add(encodedResource)) {
            throw new BeanDefinitionStoreException(
                    "Detected cyclic loading of " + encodedResource + " - check your import definitions!");
        }

        try (InputStream inputStream = encodedResource.getResource().getInputStream()) {
            InputSource inputSource = new InputSource(inputStream);
            if (encodedResource.getEncoding() != null) {
                inputSource.setEncoding(encodedResource.getEncoding());
            }
            // 真的加载 BeanDefinition
            return doLoadBeanDefinitions(inputSource, encodedResource.getResource());
        }
        catch (IOException ex) {
            throw new BeanDefinitionStoreException(
                    "IOException parsing XML document from " + encodedResource.getResource(), ex);
        }
        finally {
            currentResources.remove(encodedResource);
            if (currentResources.isEmpty()) {
                this.resourcesCurrentlyBeingLoaded.remove();
            }
        }
    }
```

这里的 loadBeanDefinitions() 方法依然没有开始解析配置文件，而是又交给了 doLoadBeanDefinitions() 方法：

```java
    protected int doLoadBeanDefinitions(InputSource inputSource, Resource resource)
            throws BeanDefinitionStoreException {

        try {
            Document doc = doLoadDocument(inputSource, resource);
            // 注册 BeanDefinition
            int count = registerBeanDefinitions(doc, resource);
            if (logger.isDebugEnabled()) {
                logger.debug("Loaded " + count + " bean definitions from " + resource);
            }
            return count;
        }
        catch (BeanDefinitionStoreException ex) {
            throw ex;
        }
        catch (SAXParseException ex) {
            throw new XmlBeanDefinitionStoreException(resource.getDescription(),
                    "Line " + ex.getLineNumber() + " in XML document from " + resource + " is invalid", ex);
        }
        catch (SAXException ex) {
            throw new XmlBeanDefinitionStoreException(resource.getDescription(),
                    "XML document from " + resource + " is invalid", ex);
        }
        catch (ParserConfigurationException ex) {
            throw new BeanDefinitionStoreException(resource.getDescription(),
                    "Parser configuration exception parsing XML from " + resource, ex);
        }
        catch (IOException ex) {
            throw new BeanDefinitionStoreException(resource.getDescription(),
                    "IOException parsing XML document from " + resource, ex);
        }
        catch (Throwable ex) {
            throw new BeanDefinitionStoreException(resource.getDescription(),
                    "Unexpected exception parsing XML document from " + resource, ex);
        }
    }
```

- 通过 SAX 将 Resource 对象解析成 Document 对象，Resource 是 InputStream 的子接口，是 IO 流，Document 是反映了 Xml 的文档结构的对象
- 调用 registerBeanDefinitions(doc, resource) 方法，从 Document 对象中解析出包含的 BeanDefinition 并注册

然后进入 registerBeanDefinitions(doc, resource) 方法：

```java
    public int registerBeanDefinitions(Document doc, Resource resource) throws BeanDefinitionStoreException {
        BeanDefinitionDocumentReader documentReader = createBeanDefinitionDocumentReader();
        int countBefore = getRegistry().getBeanDefinitionCount();
        documentReader.registerBeanDefinitions(doc, createReaderContext(resource));
        return getRegistry().getBeanDefinitionCount() - countBefore;
    }
```

- 对于 Document 对象，又定义了 BeanDefinitionDocumentReader 进行读取，BeanDefinitionDocumentReader  通过  createBeanDefinitionDocumentReader() 方法创建，实际上就是一个 DefaultBeanDefinitionDocumentReader 的对象。
- 调用 DefaultBeanDefinitionDocumentReader.registerBeanDefinitions() 方法，同时还创建了一个 XmlReaderContext，发现这个 XmlReaderContext 不仅持有当前解析的配置文件的 Resource，还持有 XmlBeanDefinitionReader 的引用，那就相当于持有了前面创建的最关键的 DefaultListableBeanfFactory 对象的引用。

```java
    public XmlReaderContext createReaderContext(Resource resource) {
        return new XmlReaderContext(resource, this.problemReporter, this.eventListener,
                this.sourceExtractor, this, getNamespaceHandlerResolver());
    }
```

接下来看看 DefaultBeanDefinitionDocumentReader.registerBeanDefinitions() 方法：

```java
    public void registerBeanDefinitions(Document doc, XmlReaderContext readerContext) {
        this.readerContext = readerContext;
        doRegisterBeanDefinitions(doc.getDocumentElement());
    }
```

- 首先设置了 readerContext
- 调用 doc.getDocumentElement() 方法，因为是第一次调用，所以拿到的是根节点 <beans> 标签
- 将上一步拿到的根节点传入 doRegisterBeanDefinitions() 方法，开始从根节点解析配置文件

```java
    protected void doRegisterBeanDefinitions(Element root) {
        // BeanDefinitionParserDelegate 本身所具有的能力是提供解析单个节点的能力
        BeanDefinitionParserDelegate parent = this.delegate;
        this.delegate = createDelegate(getReaderContext(), root, parent);
        // 是否是默认的命名空间
        if (this.delegate.isDefaultNamespace(root)) {
            // 获取 profile 属性
            String profileSpec = root.getAttribute(PROFILE_ATTRIBUTE);
            if (StringUtils.hasText(profileSpec)) {
                String[] specifiedProfiles = StringUtils.tokenizeToStringArray(
                        profileSpec, BeanDefinitionParserDelegate.MULTI_VALUE_ATTRIBUTE_DELIMITERS);
                // We cannot use Profiles.of(...) since profile expressions are not supported
                // in XML config. See SPR-12458 for details.
                if (!getReaderContext().getEnvironment().acceptsProfiles(specifiedProfiles)) {
                    if (logger.isDebugEnabled()) {
                        logger.debug("Skipped XML bean definition file due to specified profiles [" + profileSpec +
                                "] not matching: " + getReaderContext().getResource());
                    }
                    return;
                }
            }
        }
        // 前置处理
        preProcessXml(root);
        // 解析 BeanDefinition
        parseBeanDefinitions(root, this.delegate);
        // 后置处理 
        postProcessXml(root);

        this.delegate = parent;
    }
```

- 首先构建一个 BeanDefinitionParserDelegate，这个对象本身持有某个节点的 Node 对象，对外提供了这个节点的解析函数，比如获取节点的属性列表、属性值、子节点等。在创建新的 BeanDefinitionParserDelegate 之前，先使用一个 parent 变量持有原来的 BeanDefinitionParserDelegate 对象，是因为当配置文件里面有 <beans> 标签嵌套时，会出现 doRegisterBeanDefinitions() 方法的递归调用，很多时候内层的 <beans> 标签解析可能还要依赖外层的 <beans> 标签的内容。
- 解析 <beans> 标签的 profile 属性
- 解析 xml 的前置处理，空方法，交给子类实现
- 调用 parseBeanDefinitions() 方法开始解析
- 解析 xml 后置处理，也是空方法，交给子类实现

这里着重理解 parseBeanDefinitions() 方法的内容。

```java
    protected void parseBeanDefinitions(Element root, BeanDefinitionParserDelegate delegate) {
        // 是否是 spring 默认的命名空间
        if (delegate.isDefaultNamespace(root)) {
            // 获取子节点列表
            NodeList nl = root.getChildNodes();
            for (int i = 0; i < nl.getLength(); i++) {
                Node node = nl.item(i);
                if (node instanceof Element) {
                    Element ele = (Element) node;
                    // 子节点是否是默认命名空间中的标签
                    if (delegate.isDefaultNamespace(ele)) {
                        // 解析默认标签节点
                        parseDefaultElement(ele, delegate);
                    }
                    else {
                        // 自定义标签解析
                        delegate.parseCustomElement(ele);
                    }
                }
            }
        }
        else {
            // 解析自定义标签
            delegate.parseCustomElement(root);
        }
    }
```

可以看见对于每一个节点，都会判断是否是默认命名空间中的标签，如果是，调用 parseDefaultElement() 方法进行解析，如果不是，就调用 delegate.parseCustomElement() 方法解析自定义标签，这里主要关注默认节点的解析。

```java
    private void parseDefaultElement(Element ele, BeanDefinitionParserDelegate delegate) {
        // 解析<import>标签
        if (delegate.nodeNameEquals(ele, IMPORT_ELEMENT)) {
            importBeanDefinitionResource(ele);
        }
        else if (delegate.nodeNameEquals(ele, ALIAS_ELEMENT)) {
            // 解析<alias>标签
            processAliasRegistration(ele);
        }
        else if (delegate.nodeNameEquals(ele, BEAN_ELEMENT)) {
            // 解析<bean>标签
            processBeanDefinition(ele, delegate);
        }
        else if (delegate.nodeNameEquals(ele, NESTED_BEANS_ELEMENT)) {
            // recurse
            doRegisterBeanDefinitions(ele);
        }
    }
```

这里解析了四种节点标签，分别是

- <import> 标签，其实就是读取另一个配置文件，最终生成一个 Document 对象，然后在解析。 
- <alias> 标签，别名标签，这里的操作逻辑主要是在 SimpleAliasRegistry 类中，其实就是注册别名和 beanName 的对应关系
- <bean> 标签，解析成一个 BeanDefinition 对象
- 嵌套的 <beans> 标签，递归调用 doRegisterBeanDefinitions() 方法进行解析

上面简单介绍了四种标签和解析，现在深入剖析一下 <bean> 标签的解析：

```java
    protected void processBeanDefinition(Element ele, BeanDefinitionParserDelegate delegate) {
        // BeanDefinitionHolder 中保存了 BeanDefinition 和 bean 名称以及别名
        BeanDefinitionHolder bdHolder = delegate.parseBeanDefinitionElement(ele);
        if (bdHolder != null) {
            // 解析 xml 中的自定义命名空间（如果有的话）
            bdHolder = delegate.decorateBeanDefinitionIfRequired(ele, bdHolder);
            try {
                // Register the final decorated instance.
                // 将 BeanDefinition 注册到 BeanFactory 的 beanDefinitionMap
                BeanDefinitionReaderUtils.registerBeanDefinition(bdHolder, getReaderContext().getRegistry());
            }
            catch (BeanDefinitionStoreException ex) {
                getReaderContext().error("Failed to register bean definition with name '" +
                        bdHolder.getBeanName() + "'", ele, ex);
            }
            // Send registration event. 发送 BeanDefinition 注册完成事件
            getReaderContext().fireComponentRegistered(new BeanComponentDefinition(bdHolder));
        }
    }
```

- 从委托类中解析出一个 BeanDefinitionHolder，它持有的 BeanDefinition 的引用，因为可能还并不完整，所以这里使用了一个 Holder 类来做过渡
- 解析 <bean> 标签中的自定义标签
- 发送当前这个 BeanDefinition 解析完成的事件

所以其实最主要的 <bean> 标签解析逻辑在第 3 行代码 delegate.parseBeanDefinitionElement(ele) 里面。

```java
    public BeanDefinitionHolder parseBeanDefinitionElement(Element ele, @Nullable BeanDefinition containingBean) {
        /**
         * containingBean 其实是父 bean 的 BeanDefiniton
         */
        
        // 获取 id 属性值
        String id = ele.getAttribute(ID_ATTRIBUTE);

        // 获取 name 属性值，解析成 bean 的别名，多个别名用英文逗号分割
        String nameAttr = ele.getAttribute(NAME_ATTRIBUTE);
        List<String> aliases = new ArrayList<>();
        if (StringUtils.hasLength(nameAttr)) {
            String[] nameArr = StringUtils.tokenizeToStringArray(nameAttr, MULTI_VALUE_ATTRIBUTE_DELIMITERS);
            aliases.addAll(Arrays.asList(nameArr));
        }

        // 如果 id 为空，则取 name 属性中的第一个别名作为默认的 beanName
        String beanName = id;
        if (!StringUtils.hasText(beanName) && !aliases.isEmpty()) {
            beanName = aliases.remove(0);
            if (logger.isTraceEnabled()) {
                logger.trace("No XML 'id' specified - using '" + beanName +
                        "' as bean name and " + aliases + " as aliases");
            }
        }
        
        if (containingBean == null) {
            checkNameUniqueness(beanName, aliases, ele);
        }

        // 解析一个 AbstractBeanDefinition 对象，其实是一个 GenericBeanDefinition 对象
        AbstractBeanDefinition beanDefinition = parseBeanDefinitionElement(ele, beanName, containingBean);
        // 生成默认的 beanName
        if (beanDefinition != null) {
            if (!StringUtils.hasText(beanName)) {
                try {
                    if (containingBean != null) {
                        beanName = BeanDefinitionReaderUtils.generateBeanName(
                                beanDefinition, this.readerContext.getRegistry(), true);
                    }
                    else {
                        beanName = this.readerContext.generateBeanName(beanDefinition);
                        // Register an alias for the plain bean class name, if still possible,
                        // if the generator returned the class name plus a suffix.
                        // This is expected for Spring 1.2/2.0 backwards compatibility.
                        String beanClassName = beanDefinition.getBeanClassName();
                        if (beanClassName != null &&
                                beanName.startsWith(beanClassName) && beanName.length() > beanClassName.length() &&
                                !this.readerContext.getRegistry().isBeanNameInUse(beanClassName)) {
                            aliases.add(beanClassName);
                        }
                    }
                    if (logger.isTraceEnabled()) {
                        logger.trace("Neither XML 'id' nor 'name' specified - " +
                                "using generated bean name [" + beanName + "]");
                    }
                }
                catch (Exception ex) {
                    error(ex.getMessage(), ele);
                    return null;
                }
            }
            String[] aliasesArray = StringUtils.toStringArray(aliases);
            return new BeanDefinitionHolder(beanDefinition, beanName, aliasesArray);
        }

        return null;
    }
```

这一层的逻辑主要是解析 id 和 name 属性，生成 beanName 和别名。

- 获取 id 属性值
- 获取 name 属性值，并按规则拆分成多个别名
- 如果 id 属性值为空，使用 name 属性值中的第一个别名作为 beanName，如果依然为空，解析完 BeanDefinition 后会按照规则生成一个 beanName
- 通过 parseBeanDefinitionElement() 方法解析得到 AbstractBeanDefinition，其实就是一个 GenericBeanDefinition。

```java
    public AbstractBeanDefinition parseBeanDefinitionElement(
            Element ele, String beanName, @Nullable BeanDefinition containingBean) {

        this.parseState.push(new BeanEntry(beanName));

        // 解析 class 属性
        String className = null;
        if (ele.hasAttribute(CLASS_ATTRIBUTE)) {
            className = ele.getAttribute(CLASS_ATTRIBUTE).trim();
        }
        // 解析 parent 属性
        String parent = null;
        if (ele.hasAttribute(PARENT_ATTRIBUTE)) {
            parent = ele.getAttribute(PARENT_ATTRIBUTE);
        }
        try {
            // 创建 AbstractBeanDefinition 的子类 GenericBeanDefinition
            AbstractBeanDefinition bd = createBeanDefinition(className, parent);
            // 解析 bean 标签属性
            parseBeanDefinitionAttributes(ele, beanName, containingBean, bd);
            // 设置 description
            bd.setDescription(DomUtils.getChildElementValueByTagName(ele, DESCRIPTION_ELEMENT));
            // 解析元数据
            parseMetaElements(ele, bd);
            // 解析 lookup-method 子标签
            parseLookupOverrideSubElements(ele, bd.getMethodOverrides());
            // 解析 replaced-method 子标签
            parseReplacedMethodSubElements(ele, bd.getMethodOverrides());
            // 解析 constructor-arg 子标签
            parseConstructorArgElements(ele, bd);
            // 解析 property 子标签
            parsePropertyElements(ele, bd);
            // 解析 Qualifier 子节点
            parseQualifierElements(ele, bd);

            bd.setResource(this.readerContext.getResource());
            bd.setSource(extractSource(ele));

            return bd;
        }
        catch (ClassNotFoundException ex) {
            error("Bean class [" + className + "] not found", ele, ex);
        }
        catch (NoClassDefFoundError err) {
            error("Class that bean class [" + className + "] depends on not found", ele, err);
        }
        catch (Throwable ex) {
            error("Unexpected failure during bean definition parsing", ele, ex);
        }
        finally {
            this.parseState.pop();
        }

        return null;
    }
```

- 解析 className 属性
- 解析 parent 属性
- 初始化一个 GenericBeanDefinition 对象
- 解析 <bean> 标签本身的属性，比如 scope、abstract、lazy-init 等属性
- 解析 <description> 子节点并设置
- 解析元数据 <meta> 节点
- 解析 <lookup-method> 节点
- 解析 <replaced-method> 节点
- 解析 <constructor-arg> 节点
- 解析 <property> 节点
- 解析 <qualifier> 节点

## 自定义标签解析

前面讲到过通过 BeanDefinitionParserDelegate.parseCustomElement(ele) 方法解析自定义标签。

```java
    public BeanDefinition parseCustomElement(Element ele, @Nullable BeanDefinition containingBd) {
        // 获取命名空间的名字
        String namespaceUri = getNamespaceURI(ele);
        if (namespaceUri == null) {
            return null;
        }
        // 获取对应的处理器对象
        NamespaceHandler handler = this.readerContext.getNamespaceHandlerResolver().resolve(namespaceUri);
        if (handler == null) {
            error("Unable to locate Spring NamespaceHandler for XML schema namespace [" + namespaceUri + "]", ele);
            return null;
        }
        // 解析
        return handler.parse(ele, new ParserContext(this.readerContext, this, containingBd));
    }
```

- 获取命名空间的名字
- 通过命名空间的名字获取响应的解析器
- 解析成 BeanDefinition

在第 8 行，首先调用 getNamespaceHandlerResolver() 方法，得到了一 个DefaultNamespaceHandlerResolver 对象，然后调用它的 resovle(String namespaceUri) 方法拿到相应的解析器：

```java
    public NamespaceHandler resolve(String namespaceUri) {
        // 获取命名空间 uri 和对应解析器的 Map
        Map<String, Object> handlerMappings = getHandlerMappings();
        // 获取解析器对象或者 class 名称
        Object handlerOrClassName = handlerMappings.get(namespaceUri);
        if (handlerOrClassName == null) {
            return null;
        }
        else if (handlerOrClassName instanceof NamespaceHandler) {
            // 如果是 NamespaceHandler 对象，直接返回
            return (NamespaceHandler) handlerOrClassName;
        }
        else {
            String className = (String) handlerOrClassName;
            try {
                // 加载 class
                Class<?> handlerClass = ClassUtils.forName(className, this.classLoader);
                if (!NamespaceHandler.class.isAssignableFrom(handlerClass)) {
                    throw new FatalBeanException("Class [" + className + "] for namespace [" + namespaceUri +
                            "] does not implement the [" + NamespaceHandler.class.getName() + "] interface");
                }
                // 初始化对象
                NamespaceHandler namespaceHandler = (NamespaceHandler) BeanUtils.instantiateClass(handlerClass);
                // 初始化
                namespaceHandler.init();
                // 放入缓存的 map 中
                handlerMappings.put(namespaceUri, namespaceHandler);
                return namespaceHandler;
            }
            catch (ClassNotFoundException ex) {
                throw new FatalBeanException("Could not find NamespaceHandler class [" + className +
                        "] for namespace [" + namespaceUri + "]", ex);
            }
            catch (LinkageError err) {
                throw new FatalBeanException("Unresolvable class definition for NamespaceHandler class [" +
                        className + "] for namespace [" + namespaceUri + "]", err);
            }
        }
    }
```

- 通过 getHandlerMappings() 获取命名空间 URI 和对应的处理器对象或者 className 的映射
- 通过 uri 获取对应的的处理器对象或者 className
- 如果是 NamespaceHandler 接口实现类的对象，说明不是 className，直接返回
- 如果不是 NamespaceHandler 接口实现类的对象，正常情况下，那就是 className
- 加载 class 并实例化
- 调用新创建的对象的 init() 方法初始化，这个方法是 NamespaceHandler 接口中有定义
- 将 uri 和对象的映射关系放入缓存

既然是这样，那么这个 handlerMappings 的缓存内容从何而来？接下来看看在第一步中调用的 getHandlerMappings() 方法：

```java
    private Map<String, Object> getHandlerMappings() {
        // 初始化 Map
        Map<String, Object> handlerMappings = this.handlerMappings;
        if (handlerMappings == null) {
            // 同步代码块加锁，防止并发操作
            synchronized (this) {
                handlerMappings = this.handlerMappings;
                if (handlerMappings == null) {
                    if (logger.isTraceEnabled()) {
                        logger.trace("Loading NamespaceHandler mappings from [" + this.handlerMappingsLocation + "]");
                    }
                    try {
                        // 加载 properties 文件
                        Properties mappings =
                                PropertiesLoaderUtils.loadAllProperties(this.handlerMappingsLocation, this.classLoader);
                        if (logger.isTraceEnabled()) {
                            logger.trace("Loaded NamespaceHandler mappings: " + mappings);
                        }
                        // 将解析结果放到 map 中
                        handlerMappings = new ConcurrentHashMap<>(mappings.size());
                        CollectionUtils.mergePropertiesIntoMap(mappings, handlerMappings);
                        this.handlerMappings = handlerMappings;
                    }
                    catch (IOException ex) {
                        throw new IllegalStateException(
                                "Unable to load NamespaceHandler mappings from location [" + this.handlerMappingsLocation + "]", ex);
                    }
                }
            }
        }
        return handlerMappings;
```

发现其实主要就是加载了一个配置文件，里面记录了每个命名空间 uri 对应的 handler 的 className。

在前面多次提到 NamespacceHandler 接口是用来作为自定义标签的扩展处理器的，其实并不是说 Spring 自己的原生的标签就不使用这个接口，只是不过是都实现且注册了而已。

```java
public interface NamespaceHandler {
    // 初始化处理器
    void init();
    // 解析入口
    @Nullable
    BeanDefinition parse(Element element, ParserContext parserContext);
    // 解析并返回一个 BeanDefinitionHolder，这里有可能会返回一个全新的 BeanDefinition
    @Nullable
    BeanDefinitionHolder decorate(Node source, BeanDefinitionHolder definition, ParserContext parserContext);
}
```

NamespaceHandler 有一个默认的抽象类实现 NamespaceHandlerSupport，定义了基本的标签解析流程，这里主要关注常用的 parse() 方法。

```java
public abstract class NamespaceHandlerSupport implements NamespaceHandler {
    public BeanDefinition parse(Element element, ParserContext parserContext) {
        // 获取解析器
        BeanDefinitionParser parser = findParserForElement(element, parserContext);
        // 解析
        return (parser != null ? parser.parse(element, parserContext) : null);
    }

    /**
     * Locates the {@link BeanDefinitionParser} from the register implementations using
     * the local name of the supplied {@link Element}.
     */
    @Nullable
    private BeanDefinitionParser findParserForElement(Element element, ParserContext parserContext) {
        // 比如 bean 配置文件中开启事务的注解支持时使用 <tx:annotation-driven>，在这里拿到的 localName 就是 annotation-driven
        String localName = parserContext.getDelegate().getLocalName(element);
        // 通过 localName 获取对应的解析器
        BeanDefinitionParser parser = this.parsers.get(localName);
        if (parser == null) {
            parserContext.getReaderContext().fatal(
                    "Cannot locate BeanDefinitionParser for element [" + localName + "]", element);
        }
        return parser;
    }
}
```

- 调用 findParserForElement() 获取解析器

- - 首先拿到标签的 localName，比如 <tx:annotation-driven> 标签的 localName 就是 annotation-driven
  - 通过 localName 获取对应的 parser 并返回

- 解析

在获取 parser 的时候，从 `parsers` 这样一个全局变量中获取，那么如果初始化的这个变量呢？

在前面讲过命名空间 uri 和 handler 的关系，是通过配置文件得到的，查看 Spring 源码发现配置文件的默认位置是 `META-INF/spring.handlers` ，我找了一个源码里面已经有的示例：

```properties
http\://www.springframework.org/schema/c=org.springframework.beans.factory.xml.SimpleConstructorNamespaceHandler
http\://www.springframework.org/schema/p=org.springframework.beans.factory.xml.SimplePropertyNamespaceHandler
http\://www.springframework.org/schema/util=org.springframework.beans.factory.xml.UtilNamespaceHandler
```

挑上面其中一个 handler 作为示例看看。

```java
public class UtilNamespaceHandler extends NamespaceHandlerSupport {

    private static final String SCOPE_ATTRIBUTE = "scope";


    @Override
    public void init() {
        registerBeanDefinitionParser("constant", new ConstantBeanDefinitionParser());
        registerBeanDefinitionParser("property-path", new PropertyPathBeanDefinitionParser());
        registerBeanDefinitionParser("list", new ListBeanDefinitionParser());
        registerBeanDefinitionParser("set", new SetBeanDefinitionParser());
        registerBeanDefinitionParser("map", new MapBeanDefinitionParser());
        registerBeanDefinitionParser("properties", new PropertiesBeanDefinitionParser());
    }
}
```

发现它本身继承了  NamespaceHandlerSupport 类，只实现了 init() 方法，而这个 init() 方法只是调用 父类的 registerBeanDefinitionParser() 方法注册了 localName 和对应的 Parser 对象的映射关系。

```java
    protected final void registerBeanDefinitionParser(String elementName, BeanDefinitionParser parser) {
        this.parsers.put(elementName, parser);
    }
```
