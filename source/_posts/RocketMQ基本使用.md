---
title: RocketMQ基本使用
date: 2020-10-06 22:36:07
tags: RocketMQ
categories: 消息中间件
cover: https://hanelalo.github.io/images/202111061353729.png
---

# RocketMQ 基本使用

# 安装和启动

启动程序：http://rocketmq.apache.org/dowloading/releases/

## 启动 Name Server

```bash
$ bin/mqnamesrv
```

Name Server 会默认监听 9876 端口。

## 启动 Broker

```bash
$ bin/mqbroker -n localhost:9876
```

 默认监听 10911 端口。

## 创建 Topic

```bash
$ bin/mqadmin updateTopic -n localhost:9876 -b localhost:10911 -t TopicTest
```

这里创建了一个加 `TopicTest` 的 Topic。

# 发送消息

## 同步发送

```Java
public class SyncProducer {

  public static void main(String[] args)
      throws MQClientException, RemotingException, InterruptedException, MQBrokerException {
    DefaultMQProducer producer = new DefaultMQProducer("test_producer");
    producer.setNamesrvAddr("localhost:9876");
    producer.start();
    for(int i=0;i<100;i++){
      Message msg = new Message("TopicTest", "TagTest", ("Hello RocketMQ" + i).getBytes());
      SendResult sendResult = producer.send(msg);
      System.out.printf("%s%n",sendResult);
    }
    producer.shutdown();
  }
}
```

## 异步发送

```Java
public class AsyncProducer {

  public static void main(String[] args) throws MQClientException, InterruptedException {
    DefaultMQProducer producer = new DefaultMQProducer("test_producer");
    producer.setNamesrvAddr("localhost:9876");
    producer.start();
    producer.setRetryTimesWhenSendAsyncFailed(0);
    int messageCount = 100;
    final CountDownLatch countDownLatch = new CountDownLatch(messageCount);
    for (int i = 0; i < messageCount; i++) {
      try{
        final int index = 1;
        Message message = new Message("TopicTest","TagA","OrderID188","Hello World".getBytes());
        producer.send(message, new SendCallback() { // 发送消息的回调函数
          public void onSuccess(SendResult sendResult) {
            countDownLatch.countDown();
            System.out.printf("%-10d OK %s %n", index, sendResult.getMsgId());
          }

          public void onException(Throwable e) {
            countDownLatch.countDown();
            System.out.printf("%-10d Exception %s %n", index, e);
            e.printStackTrace();
          }
        });
      } catch (RemotingException e) {
        e.printStackTrace();
      } catch (InterruptedException e) {
        e.printStackTrace();
      }
    }
    countDownLatch.await(5, TimeUnit.SECONDS);
    producer.shutdown();
  }
}
```

## OneWay

```
public class OneWayProducer {

  public static void main(String[] args)
      throws MQClientException, RemotingException, InterruptedException {
    DefaultMQProducer producer = new DefaultMQProducer("test_producer");
    producer.setNamesrvAddr("localhost:9876");
    producer.start();
    for (int i = 0; i < 100; i++) {
      Message message = new Message("TopicTest", "TagA", ("Hello MQ" + i).getBytes());
      producer.sendOneway(message);
    }
    Thread.sleep(5000);
    producer.shutdown();
  }
}
```

## 消费消息

```Java
public class Consumer {

  public static void main(String[] args) throws MQClientException {
    DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("TEST_CONSUMER");
    consumer.setNamesrvAddr("localhost:9876");
    // 第一个参数时订阅的 Topic 的名字，第二个参数时筛选条件，比如 Tag
    consumer.subscribe("TopicTest", "*");
    consumer.registerMessageListener(new MessageListenerConcurrently() {
      public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> list,
          ConsumeConcurrentlyContext consumeConcurrentlyContext) {
        System.out.printf("%s Receive New Messages: %s %n", Thread.currentThread().getName(), list);
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
      }
    });
    consumer.start();
    System.out.printf("Consumer Started.%n");
  }
}
```

# 顺序消息

发送消息，给定不同的 Tag：

```Java
public class OrderedProducer {

  public static void main(String[] args)
      throws MQClientException, RemotingException, InterruptedException, MQBrokerException {
    //    生产者组名
    DefaultMQProducer producer = new DefaultMQProducer("ordered_test_producer");
    producer.setNamesrvAddr("localhost:9876");
    producer.start();
    String[] tags = new String[] {"TagA", "TagB", "TagC", "TagD", "TagE"};
    for (int i = 0; i < 100; i++) {
      int orderId = i % 10;
      // 新建一条消息
      Message message =
          new Message(
              "OrderedTopic", tags[i % tags.length], "KEY" + i, ("Hello RocketMQ " + i).getBytes());
      SendResult sendResult = producer.send(message, new MessageQueueSelector() {
        public MessageQueue select(List<MessageQueue> list, Message message, Object o) {
          Integer id  = (Integer) o;
          int index = id % list.size();
          return list.get(index);
        }
      }, orderId);
      System.out.printf("%s%n", sendResult);
    }
    producer.shutdown();
  }
}
```

消费消息：

```Java
public class OrderConsumer {

  public static void main(String[] args) throws MQClientException {
    DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("ordered_consumer");
    consumer.setNamesrvAddr("localhost:9876");
    consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);
    consumer.subscribe("OrderedTopic","TagB || TagC");
    //
    consumer.registerMessageListener(
        // 分区顺序消息 参考 https://www.yuque.com/hanelalo/hwzbuc/xah303#uRjgL
        new MessageListenerOrderly() {
          private AtomicLong consumeTimes = new AtomicLong(0);

          public ConsumeOrderlyStatus consumeMessage(
              List<MessageExt> list, ConsumeOrderlyContext consumeOrderlyContext) {
            consumeOrderlyContext.setAutoCommit(false);
            System.out.println(
                Thread.currentThread().getName() + " Receive New Messages: " + list + "%n");
            this.consumeTimes.incrementAndGet();
            if ((this.consumeTimes.get() % 2) == 0) {
              return ConsumeOrderlyStatus.SUCCESS;
            }
            if ((this.consumeTimes.get() % 3) == 0) {
              return ConsumeOrderlyStatus.ROLLBACK;
            }
            if ((this.consumeTimes.get() % 4) == 0) {
              return ConsumeOrderlyStatus.COMMIT;
            }
            if ((this.consumeTimes.get() % 5) == 0) {
              consumeOrderlyContext.setSuspendCurrentQueueTimeMillis(3000);
              return ConsumeOrderlyStatus.SUSPEND_CURRENT_QUEUE_A_MOMENT;
            }
            return ConsumeOrderlyStatus.SUCCESS;
          }
        });
    consumer.start();
    System.out.println("Consumer Stared.");
  }
}
```

# 集群消费和广播消费

关于集群消费和广播消费的描述：https://www.yuque.com/hanelalo/hwzbuc/xah303#PEryb

## 生产者

```Java
public class Producer {

  public static void main(String[] args)
      throws MQClientException, RemotingException, InterruptedException, MQBrokerException {
    DefaultMQProducer producer = new DefaultMQProducer("broadcast_producer");
    producer.setNamesrvAddr("localhost:9876");
    producer.start();
    for (int i = 0; i < 100; i++) {
      Message message =
          new Message("broadcast_topic", "TagA", "OrderID118", ("Hello World" + i).getBytes());
      SendResult sendResult = producer.send(message);
      System.out.println(sendResult);
    }
    producer.shutdown();
  }
}
```

## 消费者

```Java
public class BroadcastConsumerOne {

  public static void main(String[] args) throws MQClientException {
    DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("broadcast_consumer");
    consumer.setNamesrvAddr("localhost:9876");
    // 设置消费模式。CLUSTERING: 集群消费  BROADCASTING:广播消费
    consumer.setMessageModel(MessageModel.CLUSTERING);
    consumer.subscribe("broadcast_topic","TagA");
    consumer.registerMessageListener(new MessageListenerConcurrently() {
      public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs,
          ConsumeConcurrentlyContext context) {
        System.out.printf(Thread.currentThread().getName() + " Receive New Messages: " + msgs + "%n");
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
      }
    });
    consumer.start();
    System.out.printf("Broadcast Consumer Started.%n");
  }
}

public class BroadcastConsumerTwo {

  public static void main(String[] args) throws MQClientException {
    DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("broadcast_consumer");
    consumer.setNamesrvAddr("localhost:9876");
    consumer.setMessageModel(MessageModel.CLUSTERING);
    consumer.subscribe("broadcast_topic","TagA");
    consumer.registerMessageListener(new MessageListenerConcurrently() {
      public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs
          ConsumeConcurrentlyContext context) {
        System.out.printf(Thread.currentThread().getName() + " Receive New Messages: " + msgs + "%n");
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
      }
    });
    consumer.start();
    System.out.printf("Broadcast Consumer Started.%n");
  }
}
```

一样的消费者，至少启动两个才能看出效果。

# 延时消息

延时消息说明：https://www.yuque.com/hanelalo/hwzbuc/xah303#rlGyD

发送消息：

```Java
public class ScheduledProducer {

  public static void main(String[] args)
      throws MQClientException, RemotingException, InterruptedException, MQBrokerException {
    DefaultMQProducer producer = new DefaultMQProducer("scheduled_topic");
    producer.setNamesrvAddr("localhost:9876");
    producer.start();
    int totalMessagesToSend = 100;
    for (int i = 0; i < totalMessagesToSend; i++) {
      Message message = new Message("ScheduledTopic", "TagA", ("Hello World" + i).getBytes());
      // 延时等级
      message.setDelayTimeLevel(10);
      SendResult sendResult = producer.send(message);
      System.out.println(sendResult);
    }
    producer.shutdown();
  }
}
```

消费消息：

```Java
public class ScheduledConsumer {

  public static void main(String[] args) throws MQClientException {
    DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("scheduled_consumer");
    consumer.setNamesrvAddr("localhost:9876");
    consumer.subscribe("ScheduledTopic","*");
    consumer.registerMessageListener(new MessageListenerConcurrently() {
      public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs,
          ConsumeConcurrentlyContext context) {
        for (MessageExt message : msgs) {
          // Print approximate delay time period
          System.out.println("Receive message[msgId=" + message.getMsgId() + "] "
              + (System.currentTimeMillis() - message.getStoreTimestamp()) + "ms later");
        }
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
      }
    });
    consumer.start();
    System.out.println("Consumer Stared.");
  }
}
```