---
title: RocketMQ消息长轮询机制
date: 2020-11-14 15:04:13
tags: RocketMQ
categories: 消息中间件
cover: http://image.hanelalo.cn/images/202111061354467.png
---

# 消息拉取长轮询机制

RocketMQ 并未真的实现 push 模式，而是基于 pull 模式，让消费者循环向 broker 拉取消息来实现的 push 模式。

如果消费者拉取消息的请求到达 broker，但是消息却未到达消息队列，如果 broker 未开启长轮询模式，请求的处理会在 broker 挂起 shortPollingTimeMills（默认 1s），然后检查是否有新消息到达，如果依然没有新消息，返回 PULL_NOT_FOUND。当 broker 开启场轮询模式时，挂起的时长从拉取消息的请求里面取，push 模式默认 15s，pull 模式默认 20s，可通过 brokerSuspendMaxTimeMillis 进行配置。

当 PullRequest 未拉取到请求时，broker 的处理如下：

```java
private RemotingCommand processRequest(final Channel channel, RemotingCommand request, boolean brokerAllowSuspend) throws RemotingCommandException {
	switch (response.getCode()) {
         // 未拉拉取到消息时，code = PULL_NOT_FOUND
		case ResponseCode.PULL_NOT_FOUND:
             // 当第一次处理该请求时，brokerAllowSuspend = true，挂起之后，在被唤醒处理的时候，brokerAllowSuspend = false
            // hasSuspendFlag 从请求中获取
			if (brokerAllowSuspend && hasSuspendFlag) {
				long pollingTimeMills = suspendTimeoutMillisLong;
				if (!this.brokerController.getBrokerConfig().isLongPollingEnable()) {
                  	pollingTimeMills = this.brokerController.getBrokerConfig().getShortPollingTimeMills();
                 }
                 String topic = requestHeader.getTopic();
                 long offset = requestHeader.getQueueOffset();
                 int queueId = requestHeader.getQueueId();
                 PullRequest pullRequest = new PullRequest(request, channel, pollingTimeMills, this.brokerController.getMessageStore().now(), offset, subscriptionData, messageFilter);
                 // 挂起当前请求
                 this.brokerController.getPullRequestHoldService().suspendPullRequest(topic, queueId, pullRequest);
                 response = null;
                 break;
            }
}
```

`brokerAllowSuspend` 在从 PullMessageProcessor 中调用时，值为 true，也就是 broker 在接收到新的拉取消息的请求时是默认支持挂起的，但是当请求被挂起后，该请求再次被处理时，就不会支持挂起，后面会讲到。

最后通过 PullRequestHoldService 将请求挂起：

```java
private ConcurrentMap<String/* topic@queueId */, ManyPullRequest> pullRequestTable = new ConcurrentHashMap<String, ManyPullRequest>(1024);

public void suspendPullRequest(final String topic, final int queueId, final PullRequest pullRequest) {
	// 根据主题和消费队列构建 key（topic@queueId）
	String key = this.buildKey(topic, queueId);
	// ManyPullRequest 中维护一个在同一个主题的同一个消费队列上挂起的 PullRequest 的 List，
	ManyPullRequest mpr = this.pullRequestTable.get(key);
	if (null == mpr) {
		mpr = new ManyPullRequest();
		ManyPullRequest prev = this.pullRequestTable.putIfAbsent(key, mpr);
		if (prev != null) {
			mpr = prev;
		}
	}
	mpr.addPullRequest(pullRequest);
}
```

PullRequestHoldService  内部维护了一个 pullRequestTable，key  为`主题名@消费队列ID`，ManyPullRequest 中收集了同一个主题同一个消费队列上挂起的 PullRequest。

PullRequestHoldService 继承了 ServiceThread 类，其本身其实是一个线程，在 Broker 启动时，在 BrokerController 中启动，看一下 PullRequestHoldService 的 `run()`：

```java
    public void run() {
        log.info("{} service started", this.getServiceName());
        while (!this.isStopped()) {
            try {
                // 如果broker的longPollingEnable开启，默认每次循环后 sleep 5s
                if (this.brokerController.getBrokerConfig().isLongPollingEnable()) {
                    this.waitForRunning(5 * 1000);
                } else {
                // 否则取 shortPollingTimeMills，默认 1s
                	this.waitForRunning(this.brokerController.getBrokerConfig().getShortPollingTimeMills());
                }

                long beginLockTimestamp = this.systemClock.now();
                // 检查持有的 PullRequest
                this.checkHoldRequest();
                long costTime = this.systemClock.now() - beginLockTimestamp;
                if (costTime > 5 * 1000) {
                    log.info("[NOTIFYME] check hold request cost {} ms.", costTime);
                }
            } catch (Throwable e) {
                log.warn(this.getServiceName() + " service has exception. ", e);
            }
        }

        log.info("{} service end", this.getServiceName());
    }
```

PullRequestHoldService 依然是以死循环的方式运行，每次循环都会通过`checkHoldRequest()`检查挂起的请求。

```java
    private void checkHoldRequest() {
        for (String key : this.pullRequestTable.keySet()) {
            String[] kArray = key.split(TOPIC_QUEUEID_SEPARATOR);
            if (2 == kArray.length) {
                String topic = kArray[0];
                int queueId = Integer.parseInt(kArray[1]);
                // 根据 topic 和消费队列 id 查询消费队列的最大偏移量
                final long offset = this.brokerController.getMessageStore().getMaxOffsetInQueue(topic, queueId);
                try {
                    this.notifyMessageArriving(topic, queueId, offset);
                } catch (Throwable e) {
                    log.error("check hold request failed. topic={}, queueId={}", topic, queueId, e);
                }
            }
        }
    }
```

检查 pullRequestTable 中所有请求，通过 key 进行遍历，然后查询每个请求对应的主题和消费队列的最大偏移量，然后调用`notifyMessageArriving`尝试提示有新消息道到达。

```java
    public void notifyMessageArriving(final String topic, final int queueId, final long maxOffset, final Long tagsCode,
        long msgStoreTime, byte[] filterBitMap, Map<String, String> properties) {
        String key = this.buildKey(topic, queueId);
        ManyPullRequest mpr = this.pullRequestTable.get(key);
        if (mpr != null) {
            List<PullRequest> requestList = mpr.cloneListAndClear();
            if (null == requestList) {
                return;
            }
            List<PullRequest> replayList = new ArrayList<PullRequest>();
            for (PullRequest request : requestList) {
                // 获取最新的最大偏移量
                long newestOffset = getNewestMaxOffset(topic, queueId, maxOffset, request);
                // 如果消费队列中最大偏移量大于请求中待拉取偏移量，说明有新消息到达,尝试处理被挂起的请求
                if (newestOffset > request.getPullFromThisOffset()) {
                    boolean match = request.getMessageFilter().isMatchedByConsumeQueue(tagsCode,
                        new ConsumeQueueExt.CqExtUnit(tagsCode, msgStoreTime, filterBitMap));
                    // match by bit map, need eval again when properties is not null.
                    if (match && properties != null) {
                        match = request.getMessageFilter().isMatchedByCommitLog(null, properties);
                    }

                    if (match) {
                        try {
                            this.brokerController.getPullMessageProcessor().executeRequestWhenWakeup(request.getClientChannel(),
                                request.getRequestCommand());
                        } catch (Throwable e) {
                            log.error("execute request when wakeup failed.", e);
                        }
                        continue;
                    }
                }
                // 请求超时，无条件做最后一次请求处理，如果依然未查找到消息，消费者会收到未查询到信息的响应
                if (System.currentTimeMillis() >= (request.getSuspendTimestamp() + request.getTimeoutMillis())) {
                    try {
                        this.brokerController.getPullMessageProcessor().executeRequestWhenWakeup(request.getClientChannel(),
                            request.getRequestCommand());
                    } catch (Throwable e) {
                        log.error("execute request when wakeup failed.", e);
                    }
                    continue;
                }

                replayList.add(request);
            }

            if (!replayList.isEmpty()) {
                mpr.addPullRequest(replayList);
            }
        }
    }

    private long getNewestMaxOffset(String topic, int queueId, long maxOffset,
        PullRequest request) {
        long newestOffset = maxOffset;
        if (newestOffset <= request.getPullFromThisOffset()) {
            // 查询新消息
            newestOffset = this.brokerController.getMessageStore().getMaxOffsetInQueue(topic,
                queueId);
        }
        return newestOffset;
    }
```

提示新消息到达时，依然会获取最新的消费队列最大偏移量，以此决定要不要将当前挂起的请求唤醒处理并返回。

如果当前请求挂起已经超时，就无条件做最后一次请求处理，尝试查询新消息，按照 PullMessageProcessor 中的处理流程，如果未拉取到消息，会返回 PULL_NOT_FOUND，但是 PullRequestHoldService 唤醒请求时调用的 `PullMessageProcessor.executeRequestWhenWakeup()`传入的 `brokerAllowSuspend`参数为`false`，所以此时会直接返回结果给消费者。

前面讲的是请求挂起后，通过轮询来再次出发处理请求的动作，但是从 PullRequestHoldService 的 run 方法就能看出，当消息达到时，可能依然会延迟几秒才会将请求从挂起状态唤醒，在实时性上就不是很友好，所以 Broker 在接受到新消息时，同步消费队列的最大偏移量等信息时，会尝试提醒新消息到达，以唤醒挂起状态的请求。

在新消息到达时，SendMessageProcessor 会将新消息写入 CommitLog，然后 ReputMessageService 感知到 CommitLog 消息偏移量的变化，尝试同步消费队列等文件的最大偏移量，顺便发出新消息到达的通知。

ReputMessageService 继承 ServiceThread，是 MessageStore 内部维护的一个线程，在 `DefaultMessageStore.start()` 中启动，ReputMessageService 的 run 方法代码如下：

```java
    @Override
    public void run() {
      DefaultMessageStore.log.info(this.getServiceName() + " service started");

      while (!this.isStopped()) {
        try {
          Thread.sleep(1);
          this.doReput();
        } catch (Exception e) {
          DefaultMessageStore.log.warn(this.getServiceName() + " service has exception. ", e);
        }
      }

      DefaultMessageStore.log.info(this.getServiceName() + " service end");
    }
```

同样还是以死循环的方式执行，每次循环先让线程休眠 1s，然后执行 `doReput()` 。

```java
                  if (BrokerRole.SLAVE
                          != DefaultMessageStore.this.getMessageStoreConfig().getBrokerRole()
                      && DefaultMessageStore.this.brokerConfig.isLongPollingEnable()) {
                    DefaultMessageStore.this.messageArrivingListener.arriving(
                        dispatchRequest.getTopic(),
                        dispatchRequest.getQueueId(),
                        dispatchRequest.getConsumeQueueOffset() + 1,
                        dispatchRequest.getTagsCode(),
                        dispatchRequest.getStoreTimestamp(),
                        dispatchRequest.getBitMap(),
                        dispatchRequest.getPropertiesMap());
                  }
```

当前 broker 不是从服务器，并且支持长轮询时，才会通过`DefaultMessageStore.this.messageArrivingListener.arriving`提示由新消息到达。

```java
    @Override
    public void arriving(String topic, int queueId, long logicOffset, long tagsCode,
        long msgStoreTime, byte[] filterBitMap, Map<String, String> properties) {
        this.pullRequestHoldService.notifyMessageArriving(topic, queueId, logicOffset, tagsCode,
            msgStoreTime, filterBitMap, properties);
    }
```

最终依然是调用 PullRequestHoldService 来唤醒请求。