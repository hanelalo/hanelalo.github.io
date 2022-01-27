---
title: SpringBoot集成RocketMQ
date: 2020-10-06 22:44:30
tags: RocketMQ
categories: 消息中间件
cover: https://hanelalo.github.io/images/202111061355260.png
---

# Spring Boot 集成 RocketMQ

Spring Boot 官方并没有提供 RocketMQ 的 starter，不过 Apache 倒是提供了一个https://github.com/apache/rocketmq-spring，后来 Alibaba 又基于 Apache 提供的版本做了封装，结合 Spring Cloud Stream 的使用文档在此https://github.com/alibaba/spring-cloud-alibaba/wiki/RocketMQ-en。

# 定义消息生产者和消费者

```Java
// 消费者通道
public interface SpringConsumer {

  String INPUT = "SPRING_CONSUMER";

  @Input(INPUT)
  SubscribableChannel springConsumer();
}

// 生产者通道
public interface SpringProducer {

  String OUTPUT = "SPRING_PRODUCER";

  @Output(OUTPUT)
  MessageChannel springProducer();

}
```

配置生产者和消费者相关信息：

```properties
# 配置 Name Server
spring.cloud.stream.rocketmq.binder.name-server=localhost:9876
# 设置消费者订阅消息的 Tag
spring.cloud.stream.rocketmq.bindings.SPRING_CONSUMER.consumer.tags=TagA
# 发送消息时是否是同步发送
spring.cloud.stream.rocketmq.bindings.SPRING_PRODUCER.producer.sync=true
# 设置消费者组
spring.cloud.stream.bindings.SPRING_CONSUMER.group=SPRING_CONSUMER
# 设置消费者订阅的 Topic
spring.cloud.stream.bindings.SPRING_CONSUMER.destination=TopicTest
# 设置生产者组
spring.cloud.stream.bindings.SPRING_PRODUCER.group=SPRING_PRODUCER
# 设置生产者发送消息的目标 Topic
spring.cloud.stream.bindings.SPRING_PRODUCER.destination=TopicTest
```

# 处理订阅消息

好像说的不是很直白，就是消费消息的意思。

Spring Cloud Stream 提供了 @StreamListener 来表明某方法是用来处理订阅消息的监听器，同时还需要绑定上面注册的消费者通道到当前的监听器

```Java
@EnableBinding(SpringConsumer.class)
public class ConsumerHandler {

  private static final Logger logger = LoggerFactory.getLogger(ConsumerHandler.class);

  @StreamListener(SpringConsumer.INPUT)
  public void handle(String message){
    // 消息处理逻辑，这里只是打印一下消息内容
    logger.info(message);
  }
}
```

# 发送消息

```Java
@RestController
@EnableBinding(SpringProducer.class)
public class ProducerHandler {

  private static final Logger logger = LoggerFactory.getLogger(ProducerHandler.class);

  @Autowired
  private SpringProducer springProducer;

  @GetMapping("send")
  public void send() {
    MessageBuilder<User> builder =
        MessageBuilder.withPayload(new User().setAge(23).setName("hanelalo").setSex("MALE"))
            // 设置消息的 Tag
            .setHeader(RocketMQHeaders.TAGS, "TagA")
            // 如果是延时消息，还需要设置延时等级
            // 查看源码得知，只有同步发送消息的时候，这玩意儿才有用
            .setHeader(MessageConst.PROPERTY_DELAY_TIME_LEVEL, "5");
    Message<User> userMessage = builder.build();
    springProducer.springProducer().send(userMessage);
    logger.info("message sent: {}",userMessage);
  }
}
```

延时等级是 5，在 RocketMQ 默认的 18 个延时等级里面，第 5 个是 1 分钟。

启动起来，访问 `localhost:8080/send` ，查看控制台日志：

```
2020-08-09 23:16:47.781  INFO 9228 --- [nio-8080-exec-1] o.h.r.handler.ProducerHandler            : message sent: GenericMessage [payload=User{name='hanelalo', sex='MALE', age=23}, headers={id=d7c2daa3-1421-61e1-758a-9c7e6b0252df, DELAY=5, contentType=application/json, TAGS=TagA, timestamp=1596986207377}]
2020-08-09 23:17:48.127  INFO 9228 --- [MessageThread_1] o.h.r.handler.ConsumerHandler            : {"name":"hanelalo","sex":"MALE","age":23}
```

嗯，发送消息的时间和消费消息的时间间隔刚好是一分钟。