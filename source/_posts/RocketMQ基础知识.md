---
title: RocketMQ基础知识
date: 2020-10-06 22:33:28
tags: RocketMQ
categories: 消息中间件
cover: https://hanelalo.github.io/images/202111061353767.png
---

# RocketMQ 基础知识

# 基本概念

## 消息模型

RocketMQ 主要由 Producer、Consumer、Broker 三部分组成，Broker 负责存储消息，一台服务器对应一个 Broker。每个 Broker 可能存储了多个 Topic 的消息。Topic 可以认为是消息的分类，每个 Topic 的消息数据有多个数据分片，而这些分片可能分散在多个不同的 Broker 上存储。

## 消息生产者：Producer

负责生产消息。消息生产者会把消息发送到 Broker 服务器。RocketMQ 提供了多种发送消息的方式：同步发送、异步发送、顺序发送、单向发送。同步和异步方式，需要 Broker 返回确认信息。

## 消息消费者：Consumer

负责消费消息，会从 Broker 获取到消息，提供给应用进行消费。消费方式分为：拉取式消费、推动式消费。

## Broker

负责存储消息，转发消息，接受从生产者发来的消息并存储，为消费者拉取消息的操作做准备。除了这些，Broker 中还存储了消费者组（ConsumerGroup）、消费进度、主题和队列消息等相关元数据。多个 Broker 组成一个集群，同一个集群中 BrokerId 为 0 的是 Mater，BrokerId 大于 0 的是 Slave。

## Name Server

按照微服务的思维来理解的话，Name Server 类似于注册中心，充当路由组件，提供给消费者和生产者查找各个 Topic 所在的 Broker IP 的服务。多个 Name Server 组成一个集群，但是每个节点之间没有通信。

## 拉取式消费

消息由消费者主动从 Broker 拉取，消费行为由消费者端主动发起。因为需要消费者主动拉取消息，所以消费的实时性比较低。

## 推动式消费

由 Broker 主动推送消息到消费者端，实时性比较高。

## 生产者组（ProducerGroup）

同一类消息生产者的集合，一个 Producer Group 内的生产者发送的是同一类消息，且生产逻辑一致。如果发送的是事务消息，但是在发送消息之后，生产者崩溃了，Broker 会联系同一个 Producer Group 中的其他生产者提交或回滚事务。

## 消费者组（ConsumerGroup）

同一类消息消费者的集合。一个 Consumer Group 内的消费者消费的是同一类消息，并且消费的逻辑应该是一致的。也就是说，同一个消费者组里面的消费者必须订阅的是同一个 Topic。RocketMQ 支持两种消费模式：集群消费和广播消费。

## 集群消费（Clustering）

同一 ConsumerGroup 下每个 Consumer 平均分摊消息。

## 广播消费（Broadcasting）

广播消费模式下，同一 ConsumerGroup 所有 Consumer 接受全量消息。

## 普通顺序消息（Normal Ordered Message）

在普通顺序消费模式下，消费者在同一消息队列消费的消息是有序的，但是在多个消息队列之间消费是无序的。

## 严格顺序消息（Strictly Ordered Message）

严格顺序模式下，消费者收到的所有消息是有序的。

## 消息（Message）

消息系传输信息的载体，生产和消费数据的最小单位，每个消息只属于某一个 Topic，并且每个消息都有一个唯一的 Message ID，还可以携带具有业务意义的 key，RocketMQ 提供了通过 ID 和 key 查找消息的功能。

## 标签（Tag）

同一 Topic 下不同类型消息的标识。



# 特性

## 订阅

前面讲到每个 Topic 中的消息都有 Tag 用来区分不同的类型。而订阅，就是消费者关注 Topic 中带有某些特定 Tag 的消息，进而拉取相应的消息进行消费。

## 消息顺序

消息顺序分为全局顺序和分区顺序。依然是前面有提到过，普通顺序消息和严格顺序消息有关。在 Broker 中，消息会根据一个 sharding key 字段来将消息放到不同的分区。也就是说，同一类的消息，先发送的消息 A 可能是 a 分区，而后发送的消息 B 可能在 b 分区，而分区顺序不要求你先消费 A 再消费 B，因为两个消息不在同一个分区，但是全局顺序则要求按必须先消费 A 再消费 B。对比一下就会发现，保证绝对的顺序的同时，并发的性能会有所下降，所以要是性能要求不高，可以考虑全局顺序。

## 消息过滤

在 Broker 端对 Tag 进行过滤，以减少对消费者的无用网络传输，除了可通过 Tag 进行过滤，还可自定义其他的过滤规则，最终都是在 Broker 端进行而已。

## 消息可靠性

首先了解 RocketMQ 的 Broker 集群的同步方式。分为异步刷盘和同步双写。顾名思义，异步刷盘的意思就是来了一个消息，我先在 Master 保存了，立马返回信息给生产者，而这条消息会以异步方式发送给其他的从节点保存；同步双写是当接收到一个新消息的时候，不仅仅要在 Mater 保存成功，还得等到其他节点也保存成功，才会返回信息给生产者。

影响消息可靠性的情况一般有一下几种：

- Broker非正常关闭
- Broker异常Crash
- OS Crash
- 机器掉电，但是能立即恢复供电情况
- 机器无法开机（可能是cpu、主板、内存等关键设备损坏）
- 磁盘设备损坏

前面四种情况都属于服务器资源可恢复的情况，所以能做到不丢失消息或者丢失少量消息，这取决于是否使用的同步双写的机制。

而最后两种，该 Broker 节点消息直接丢失。在这两种情况下，因为还有消息同步机制，所以挂掉的 Broker 上的消息依然能保存大部分，这依然是取决于使用的是同步双写还是异步刷盘。

使用同步双写固然可以更有效保证消息的可靠性，但是相应的性能也会下降。

## 事务消息

应用本地事务和发送消息操作被应用到全局事务，要么同是失败，要么同时成功。用于保证最终一致性。

## 回溯消息

当消费者已经消费了消息，但是因为业务原因需要重新消费消息，为了实现此功能，Broker 在消息被消费之后依然保留消息。比如因为 Consumer 系统故障，恢复后需要消费前面一个小时的消息，那么 Broker  就得提供一个可以在时间维度上回退消费进度的功能，而 RocketMQ 也确实支持按照时间维度回溯消息的功能，时间维度精确到毫秒。

## 定时消息

定时消息是指那些发送到 broker 后不会被立即消费的消息，而是等待特定延时之后再被投递给 Topic 消费。broker 配置有 messageDelayLevel，默认有 18 个 level：1s、5s、10s、30s、1m、2m、3m、4m、5m、6m、7m、8m、9m、10m、20m、30m、1h、2h。可配置自定义的 messageDelayLevel。

这里的 messageDelayLevel 是 broker 的配置属性，发送消息时设置消息的 delayLevel 即可：`msg.setDelayLevel(level)`。设置的 level 有如下三种情况：

- level == 0，非延迟消息。
- 1 <= level <= maxLevel，消息延迟特定时间，比如 level == 5 时，延时为 1m。
- level > maxLevel，此时 level == maxLevel，延时为 2h。

定时消息会暂存在 SCHEDULE_TOPIC_XXXX 的 topic 中，并根据 delayTimeLevel 放入特定的 queue，queueId = delayTimeLevel - 1，也就是一个 queue 中存储的是有相同延时的消息，broker 会调度的消费 SCHEDULE_TOPIC_XXXX，再特定的时间将消息写入真实的 Topic。

## 消息重试

在消息消费失败后，需要提供一种重试机制，让消息能再次被消费。而消息消费失败通常有以下情况：

- 因为消息本身原因，导致消息本身无法被处理，这种的消息，一般情况下即使立马重试也不会成功。这样的通常都会跳过，转而消费其他的消息，这样的情况一般定时 10s 重试。
- 依赖的下游应用不可用，这样的情况，即使消费其他的消息也依然会失败，所以一般会 sleep 30s 再消费下一条消息。

RocketMQ 为每个消费组都提供了一个 Topic 名称为 `%RETRY%+consumerGroup` 的重试队列，用于暂时保存因为各种异常导致无法消费的消息，这个 Topic 是针对消费者组设置，而非是每个正常 Topic 都有这样一个 重试用的 Topic。

针对不同延时的重试消息，RocketMQ 为重试队列设置了多个重试级别，每个重试级别都有对应的重新投递延时，重试次数越多，投递的延时就越大。RocketMQ 对消息重试的处理方式是，先将需要重试的消息放到 SCHEDULE_TOPIC_XXXX 的延迟队列中，后台定时任务按照对应的时间进行 Delay 后保存到 "%RETRY+consumerGroup%" 的重试队列中。

## 消息重投

生产者在发送消息时会有失败的情况出现，消息重投保证消息尽可能发送成功、不丢失，但是相应的可能会造成重复消息。

RocketMQ 的重投策略有以下三种：

1. retryTimesWhenSendFailed，同步发送失败重投次数，默认是 2，也就是说默认配置下，同步发送消息最多会发送 retryTimesWhenSendFailed+1 次。消息发送失败后，下次重投不会选择失败过的 broker，会尝试向其他 broker 发送，尽力保证消息不丢失，超过重投次数时抛出异常。当出现 RemotingException、MQClientException 和部分 MQBrokerException 时会重投。
2. retryTimesWhenSendAsyncFailed，异步发送消息重试次数。异步重试不会选择其他的 broker，所以不能保证消息不丢失。
3. retryAnotherBrokerWhenNotStoreOK，消息刷盘（主或备）超时或 slave 不可用（返回状态非SEND_OK），是否尝试发送到其他 broker，默认 false。十分重要消息可以开启。

## 流量控制

- 生产者流控，不会尝试消息重投

- - commitLog 文件被锁时间超过 osPageCacheBusyTimeOutMills 时，参数默认为 1000ms，返回流控。
  - 如果开启 transientStorePoolEnable == true，且 broker 为异步刷盘的主机，且 transientStorePool 中资源不足，拒绝当前 send 请求。
  - broker 每隔 10ms 检查 send 请求队列头部请求的等待时间，如果超过 waitTimeMillsInSendQueue，默认 200ms，拒绝当前 send 请求。
  - broker 通过拒绝 send 请求实现流量控制。

- 消费者流控，会降低拉取频率。

- - 消费者本地缓存消息数超过 pullThresholdForQueue 时，默认 1000。
  - 消费者本地缓存消息大小超过 pullThresholdSizeForQueue 时，默认 100MB。
  - 消费者本地缓存消息跨度超过 consumeConcurrentlyMaxSpan 时，默认 2000。

## 死信队列

死信队列用于处理无法被正常消费的消息。当一条消息初次消费失败，消息队列会自动进行消息重试；达到最大重试次数后，若消费依然失败，则表明消费者在正常情况下无法正确地消费该消息，此时，消息队列 不会立刻将消息丢弃，而是将其发送到该消费者对应的特殊队列中。

RocketMQ 将这种正常情况下无法被消费的消息称为死信消息（Dead-Letter Message），将存储死信消息的特殊队列称为死信队列（Dead-Letter Queue）。在 RocketMQ 中，可以通过使用 console 控制台对死信队列中的消息进行重发来使得消费者实例再次进行消费。