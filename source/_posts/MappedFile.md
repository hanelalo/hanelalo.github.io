---
title: MappedFile
date: 2020-10-06 23:19:21
tags: RocketMQ
categories: 消息中间件
cover: https://hanelalo.github.io/images/202111061350034.png
---

# MappedFile

在将 MappedFile 之前, 先讲讲 MappedFileQueue, 因为 MappedFileQueue 是用来管理 MappedFile 的容器. 它主要有一下几个属性, 相应的用途也已经注明.

```Java
    /** MappedFile 存储目录 */
    private final String storePath;
    /** 单个 MappedFile 文件存储大小 */
    private final int mappedFileSize;
    /** MappedFile 文件集合 */
    private final CopyOnWriteArrayList<MappedFile> mappedFiles = new CopyOnWriteArrayList<MappedFile>();
    /** 用于创建 MappedFile 的服务类 */
    private final AllocateMappedFileService allocateMappedFileService;
    /** 当前刷盘指针， 在该指针位置之前的消息都已经存储到磁盘 */
    private long flushedWhere = 0;
    /** 当前提交指针， 内存中 ByteBuffer 当前的写指针，大于等于刷盘指针的值 */
    private long committedWhere = 0;
```

MappedFile 的大小是固定的, 每次存储消息, 存储不下时,才会创建新的 MappedFile, 每个 MappedFile 的名称就是其初始偏移量.

# 查询 MappedFile 的公共方法

## 根据时间戳获取 MappedFile

```Java
    public MappedFile getMappedFileByTime(final long timestamp) {
        Object[] mfs = this.copyMappedFiles(0);

        if (null == mfs)
            return null;

        for (int i = 0; i < mfs.length; i++) {
            MappedFile mappedFile = (MappedFile) mfs[i];
            if (mappedFile.getLastModifiedTimestamp() >= timestamp) {
                return mappedFile;
            }
        }

        return (MappedFile) mfs[mfs.length - 1];
    }
```

首先获取了 MappedFile 的对象数组, 然后遍历数组找到第一个最后修改时间在查询时间之后的 MappedFile 返回, 如果没找到, 就默认返回数组的最后一个 MappedFile 对象.

## 根据数据偏移量查询 MappedFile

```Java
    /**
     * Finds a mapped file by offset.
     *
     * @param offset Offset.
     * @param returnFirstOnNotFound If the mapped file is not found, then return the first one.
     * @return Mapped file or null (when not found and returnFirstOnNotFound is <code>false</code>).
     */
    public MappedFile findMappedFileByOffset(final long offset, final boolean returnFirstOnNotFound) {
        try {
            MappedFile firstMappedFile = this.getFirstMappedFile();
            MappedFile lastMappedFile = this.getLastMappedFile();
            if (firstMappedFile != null && lastMappedFile != null) {
                // 如果第一个 MappedFile 的初始偏移量大于查询的偏移量, 或者最后一个文件的初始偏移量加文件大小比查询偏移量小, 则报错, 也就是查询的偏移量必须在目前已有的 MappedFile 范围内 
                if (offset < firstMappedFile.getFileFromOffset() || offset >= lastMappedFile.getFileFromOffset() + this.mappedFileSize) {
                    LOG_ERROR.warn("Offset not matched. Request offset: {}, firstOffset: {}, lastOffset: {}, mappedFileSize: {}, mappedFiles count: {}",
                        offset,
                        firstMappedFile.getFileFromOffset(),
                        lastMappedFile.getFileFromOffset() + this.mappedFileSize,
                        this.mappedFileSize,
                        this.mappedFiles.size());
                } else {
                    // 计算偏移量所在 MappedFile 在数组中的下标
                    int index = (int) ((offset / this.mappedFileSize) - (firstMappedFile.getFileFromOffset() / this.mappedFileSize));
                    MappedFile targetFile = null;
                    try {
                        targetFile = this.mappedFiles.get(index);
                    } catch (Exception ignored) {
                    }
                    
                    // 判断查询的目标偏移量是否在计算出的 MappedFile 中
                    if (targetFile != null && offset >= targetFile.getFileFromOffset()
                        && offset < targetFile.getFileFromOffset() + this.mappedFileSize) {
                        return targetFile;
                    }
                    // 如果查询的目标偏移量不在按照前面的方式找到的 MappedFile 中, 就直接强行遍历 MappedFile 数组查找
                    for (MappedFile tmpMappedFile : this.mappedFiles) {
                        if (offset >= tmpMappedFile.getFileFromOffset()
                            && offset < tmpMappedFile.getFileFromOffset() + this.mappedFileSize) {
                            return tmpMappedFile;
                        }
                    }
                }
                // 根据参数返回第一个 MappedFile
                if (returnFirstOnNotFound) {
                    return firstMappedFile;
                }
            }
        } catch (Exception e) {
            log.error("findMappedFileByOffset Exception", e);
        }

        return null;
    }
```

1. 首先找到最后一个和第一个 MappedFile
2. 如果查询的偏移量不在第一个 MappedFile 的初始偏移量和最后一个 MappedFile 的最大偏移量之间, 打印错误日志, 然后根据参数判断是否要在为查询到时返回第一个 MappedFile.
3. 根据文件大小的第一个 MappedFile 的初始偏移量, 计算查询的偏移量所在 MappedFile 在 mappedFiles 中的索引下标, 并从 mappedFiles 中获取到目标 MappedFile.
4. 如果查询的 offset 在第三步找到的 MappedFile 中, 直接返回, 如果不在, 就直接遍历 mappedFiles 查找, 如果找到了也是直接返回.
5. 在前面几种办法都查找无果时, 根据方法参数 returnFirstOnNotFound 判断要不要在没查询到结果时直接返回第一个 MappedFile.

这里在计算 MappedFile 在 mappedFiles 中的下标时, 没有直接使用 offset / mappedFileSize, 是因为 RocketMQ 会删除一些无效过期的消息, 所以映射到内存中的 MappedFile 的初始偏移量害真的不一定是从 00000000000000000000 开始.

## 获取最大、最小偏移量

从前一节的代码来看应该已经能知道怎么获取最大最小偏移量:

```Java
    // 获取最小偏移量
    public long getMinOffset() {

        if (!this.mappedFiles.isEmpty()) {
            try {
                return this.mappedFiles.get(0).getFileFromOffset();
            } catch (IndexOutOfBoundsException e) {
                //continue;
            } catch (Exception e) {
                log.error("getMinOffset has exception.", e);
            }
        }
        return -1;
    }

    // 获取最大偏移量
    public long getMaxOffset() {
        MappedFile mappedFile = getLastMappedFile();
        if (mappedFile != null) {
            return mappedFile.getFileFromOffset() + mappedFile.getReadPosition();
        }
        return 0;
    }
```

最小偏移量直接取的 mappedFiles 的第一个 MappedFile 的初始偏移量, 如果 mappedFiles 为空, 就返回 -1.

最大偏移量取的是 mappedFiles 中最后一个 MappedFile 的初始偏移量加上其读指针位置, 同样, 如果获取到的是空的 MappedFile, 就直接返回 0.

## 获取最大写指针

```Java
    public long getMaxWrotePosition() {
        MappedFile mappedFile = getLastMappedFile();
        if (mappedFile != null) {
            return mappedFile.getFileFromOffset() + mappedFile.getWrotePosition();
        }
        return 0;
    }
```

# MappedFile

MappedFile 主要属性和其用途如下:

```Java
    /** 操作系统缓存每页大小 */
    public static final int OS_PAGE_SIZE = 1024 * 4;
    /** 当前 JVM 中 MappedFile 虚拟内存 */
    private static final AtomicLong TOTAL_MAPPED_VIRTUAL_MEMORY = new AtomicLong(0);
    /** 当前 JVM 中 MappedFile 对象个数 */
    private static final AtomicInteger TOTAL_MAPPED_FILES = new AtomicInteger(0);
    /** 当前该文件的写指针, 从 0 开始 */
    protected final AtomicInteger wrotePosition = new AtomicInteger(0);
    /** 当前文件提交指针 */
    protected final AtomicInteger committedPosition = new AtomicInteger(0);
    /** 当前刷盘指针 */
    private final AtomicInteger flushedPosition = new AtomicInteger(0);
    /** 文件大小 */
    protected int fileSize;
    /** 文件通道 */
    protected FileChannel fileChannel;
    /**
     * Message will put to here first, and then reput to FileChannel if writeBuffer is not null.
     */
    protected ByteBuffer writeBuffer = null;
    /** 堆外内存池 */
    protected TransientStorePool transientStorePool = null;
    /** 文件名称 */
    private String fileName;
    /** 文件初始偏移量 */
    private long fileFromOffset;
    /** 物理文件 */
    private File file;
    /** 物理文件对应内存映射的 buffer */
    private MappedByteBuffer mappedByteBuffer;
    /** 最后一次写入时间戳 */
    private volatile long storeTimestamp = 0;
    /** 是否是 MappedFileQueue 中的第一个文件 */
    private boolean firstCreateInQueue = false;
```

MappedFile 提供了两个构造方法:

```Java
    public MappedFile(final String fileName, final int fileSize) throws IOException {
        init(fileName, fileSize);
    }

    public MappedFile(final String fileName, final int fileSize,
        final TransientStorePool transientStorePool) throws IOException {
        init(fileName, fileSize, transientStorePool);
    }
```

区别在于 transientStorePool 这个对外内存池, 调用的也是不同的初始化方法, 但是当提供了堆外内存池时, 也只是多初始化了 writeBuffer 和 transientStorePool.

```Java
    public void init(final String fileName, final int fileSize,
        final TransientStorePool transientStorePool) throws IOException {
        init(fileName, fileSize);
        this.writeBuffer = transientStorePool.borrowBuffer();
        this.transientStorePool = transientStorePool;
    }

    private void init(final String fileName, final int fileSize) throws IOException {
        this.fileName = fileName;
        this.fileSize = fileSize;
        this.file = new File(fileName);
        this.fileFromOffset = Long.parseLong(this.file.getName());
        boolean ok = false;

        ensureDirOK(this.file.getParent());

        try {
            this.fileChannel = new RandomAccessFile(this.file, "rw").getChannel();
            this.mappedByteBuffer = this.fileChannel.map(MapMode.READ_WRITE, 0, fileSize);
            TOTAL_MAPPED_VIRTUAL_MEMORY.addAndGet(fileSize);
            TOTAL_MAPPED_FILES.incrementAndGet();
            ok = true;
        } catch (FileNotFoundException e) {
            log.error("Failed to create file " + this.fileName, e);
            throw e;
        } catch (IOException e) {
            log.error("Failed to map file " + this.fileName, e);
            throw e;
        } finally {
            if (!ok && this.fileChannel != null) {
                this.fileChannel.close();
            }
        }
    }
```

1. 首先设置了文件名和文件大小以及文件的 File 对象, 紧接着是文件中数据的初始偏移量, 从这里可以看出来, 每个 MappedFile 的文件名就是其初始偏移量,
2. 判断 file 对象的父文件夹是否存在, 不存在还得给创建.
3. 初始化 FileChannel.
4. 通过前面初始化的 fileChannel 初始化 mappedByteBuffer, MappedByteBuffer 是物理文件在内存中的映射,对它进行的读写操作最终都会传播到物理文件上, 这里设置了 MapMode 为 READ_WRITE 表示读写权限都具有.
5. 设置当前 JVM 实例中 MappedFile 文件占用虚拟内存大小.
6. 设置当前 JVM 实例中 MappedFile 文件个数.

## 提交(commit)

在叫提交之前, 接上面的堆外内存池讲讲提交是什么场景, 当 transientStorePoolEnable  为 true 时, 初始化了堆外内存池, 额外初始化了 writeBuffer, 当有新数据写入时, 并不是直接将数据写入操作, 而是先将数据写入 transientStorePool, 然后另一个 commit 线程再异步的从堆外内存池提交数据到 FileChannel., 

```Java
    public int commit(final int commitLeastPages) {
        if (writeBuffer == null) {
            //no need to commit data to file channel, so just regard wrotePosition as committedPosition.
            return this.wrotePosition.get();
        }
        if (this.isAbleToCommit(commitLeastPages)) {
            if (this.hold()) {
                commit0(commitLeastPages);
                this.release();
            } else {
                log.warn("in commit, hold failed, commit offset = " + this.committedPosition.get());
            }
        }

        // All dirty data has been committed to FileChannel.
        if (writeBuffer != null && this.transientStorePool != null && this.fileSize == this.committedPosition.get()) {
            this.transientStorePool.returnBuffer(writeBuffer);
            this.writeBuffer = null;
        }

        return this.committedPosition.get();
    }
```

1. 判断 writeBuffer 是否为 null, 因为 commit 操作主要是通过 writeBuffer 进行,  writeBuffer 是从 transientStorePool 中获得, 所以如果 writeBuffer 为 null 时根本就不存在 commit 这个操作, 此时应该直接返回.
2. 判断当前是否能 commit.

1. 1. 如果文件已经满了直接返回 true
   2. 如果 commitLeastPage > 0, 通过 OS_PAGE_SIZE 计算当前未提交页数, 如果大于等于 commitLeastPages, 返回 true, 否则范湖 false.
   3. 如果 commitLeastPages 不大于 0, 直接比较写指针是否大于刷盘指针位置, 标识只要有为提交的数据就直接提交.

```Java
    protected boolean isAbleToCommit(final int commitLeastPages) {
        int flush = this.committedPosition.get();
        int write = this.wrotePosition.get();

        if (this.isFull()) {
            return true;
        }

        if (commitLeastPages > 0) {
            return ((write / OS_PAGE_SIZE) - (flush / OS_PAGE_SIZE)) >= commitLeastPages;
        }

        return write > flush;
    }
```

1. 提交数据(commit0)

```Java
    protected void commit0(final int commitLeastPages) {
        int writePos = this.wrotePosition.get();
        int lastCommittedPosition = this.committedPosition.get();

        if (writePos - this.committedPosition.get() > 0) {
            try {
                ByteBuffer byteBuffer = writeBuffer.slice();
                byteBuffer.position(lastCommittedPosition);
                byteBuffer.limit(writePos);
                this.fileChannel.position(lastCommittedPosition);
                this.fileChannel.write(byteBuffer);
                this.committedPosition.set(writePos);
            } catch (Throwable e) {
                log.error("Error occurred when commit data to FileChannel.", e);
            }
        }
    }
```

1. 1. 如果当前写指针大于提交指针位置, 标识当前有数据可以提交, 否则打印一行 error 日志而不进行提交操作.
   2. 开始提交操作, 首先调用 slice 创建一个跟 writeBuffer 共享内存的 byteBuffer, 但是有自己的 position 和 limit.
   3. 设置 byteBuffer 的 position 为最后一次提交的位置, limit 设置为当前写指针位置.
   4. 将 MappedFile 对应的 FlieChannel 的 position 设置为最后一次提交的指针位置, 表示接下来要从这个位置写入新数据, 调用 FileChannel.write() 方法将 byteBuffer 的内容写入
   5. 将提交指针设置为和写指针一个位置, 表示中间的数据已经提交.

## 刷盘(flush)

前面讲了将数据从 transientStorePool 提交到 flieChannel. 但是现在数据只是写入 MappedFile 对应的内存中, 还没有真的写入到磁盘中, 刷盘就是为了将数据彻底写入磁盘.

```Java
    public int flush(final int flushLeastPages) {
        if (this.isAbleToFlush(flushLeastPages)) {
            if (this.hold()) {
                int value = getReadPosition();

                try {
                    //We only append data to fileChannel or mappedByteBuffer, never both.
                    if (writeBuffer != null || this.fileChannel.position() != 0) {
                        this.fileChannel.force(false);
                    } else {
                        this.mappedByteBuffer.force();
                    }
                } catch (Throwable e) {
                    log.error("Error occurred when force data to disk.", e);
                }

                this.flushedPosition.set(value);
                this.release();
            } else {
                log.warn("in flush, hold failed, flush offset = " + this.flushedPosition.get());
                this.flushedPosition.set(getReadPosition());
            }
        }
        return this.getFlushedPosition();
    }
```

1. 首先判断是否可以进行刷盘操作

```Java
    private boolean isAbleToFlush(final int flushLeastPages) {
        int flush = this.flushedPosition.get();
        int write = getReadPosition();

        if (this.isFull()) {
            return true;
        }

        if (flushLeastPages > 0) {
            return ((write / OS_PAGE_SIZE) - (flush / OS_PAGE_SIZE)) >= flushLeastPages;
        }

        return write > flush;
    }
```

1. 1. 首先拿到刷盘指针位置.
   2. 拿到读指针位置, 这里的读指针, 如果 writeBuffer 为空就返回当前写指针位置, 否则就返回提交指针位置, 因为如果使用了 transientStorePool, 数据就先提交再刷盘, 此时提交指针的位置才是真正数据文件末尾的位置.
   3. 如果文件满了, 直接返回 true.
   4. 如果传入的刷盘最少页数(flushLeastPages) 大于 0, 计算当前未刷盘页数是否大于 flushLeastPages.
   5. 如果 flushLeastPages 小于等于 0, 表示只要有未刷盘的数据就进行刷盘, 所以直接比较当前写指针是否大于刷盘指针即可.

1. 通过判断 writeBuffer 是否为 0 来判断通过 FileChannel 还是MappedByteBuffer 刷盘, 如果 writeBuffer 不为空, 就通过 FileChannel.force() 刷盘, 否则就用 mappedByteBuffer.force() 刷盘.

```Java
    //We only append data to fileChannel or mappedByteBuffer, never both.
    if (writeBuffer != null || this.fileChannel.position() != 0) {
        this.fileChannel.force(false);
    } else {
        this.mappedByteBuffer.force();
    }
```

1. 重新设置刷盘指针为前面读取到的读指针位置, 并返回最新的刷盘指针位置.

**看到这里发现, 对ByteBuffer 的操作, 一般都不会直接操作, 而总是先调用 slice() 创建一个共享内存的 ByteBuffer, 自己设置新的 ByteBuffer 对象的 limit 和 position, 然后通过这个新的 ByteBuffer 进行数据操作.** 

## 销毁(destroy)

```Java
    public boolean destroy(final long intervalForcibly) {
        this.shutdown(intervalForcibly);

        if (this.isCleanupOver()) {
            try {
                this.fileChannel.close();
                log.info("close file channel " + this.fileName + " OK");

                long beginTime = System.currentTimeMillis();
                boolean result = this.file.delete();
                log.info("delete file[REF:" + this.getRefCount() + "] " + this.fileName
                    + (result ? " OK, " : " Failed, ") + "W:" + this.getWrotePosition() + " M:"
                    + this.getFlushedPosition() + ", "
                    + UtilAll.computeElapsedTimeMilliseconds(beginTime));
            } catch (Exception e) {
                log.warn("close file channel " + this.fileName + " Failed. ", e);
            }

            return true;
        } else {
            log.warn("destroy mapped file[REF:" + this.getRefCount() + "] " + this.fileName
                + " Failed. cleanupOver: " + this.cleanupOver);
        }

        return false;
    }
```

intervalForcibly 表示拒绝销毁的最大活动时间.

1. 首先调用 shutdown 方法

```Java
    public void shutdown(final long intervalForcibly) {
        if (this.available) {
            this.available = false;
            this.firstShutdownTimestamp = System.currentTimeMillis();
            this.release();
        } else if (this.getRefCount() > 0) {
            if ((System.currentTimeMillis() - this.firstShutdownTimestamp) >= intervalForcibly) {
                this.refCount.set(-1000 - this.getRefCount());
                this.release();
            }
        }
    }
```

第一次调用 destory 时, available 为 true, 将 available 设置为 false, 表示资源已经不可用, 然后设置第一次调用销毁时间戳为当前时间, 最后调用 release() 释放资源.

如果本次调用时 available 为 false, 表示已经调用过销毁方法, 但是没能立即销毁, 然后就判断当前对 MappedFile 的引用是否大于 0. 如果大于 0 , 判断距离第一次调用时间是否大于了最大存活时间, 如果大于, 就直接将引用次数设置为一个很小的负数 , 调用 release() 方法强制销毁.

那么为什么第一次调用 release() 时没能销毁成功呢?

看看 release() 的代码, 发现其中也对文件对象引用数进行了判断, 如果引用大于 0, 就不释放资源, 所以当销毁超时时, 会先将引用数强行设置为了负数, 这样就会调用 cleanup 同步销毁文件.

```Java
    public void release() {
        long value = this.refCount.decrementAndGet();
        if (value > 0)
            return;

        synchronized (this) {

            this.cleanupOver = this.cleanup(value);
        }
    }
```

然后再深挖一下 cleanup() 方法:

```Java
    @Override
    public boolean cleanup(final long currentRef) {
        if (this.isAvailable()) {
            log.error("this file[REF:" + currentRef + "] " + this.fileName
                + " have not shutdown, stop unmapping.");
            return false;
        }

        if (this.isCleanupOver()) {
            log.error("this file[REF:" + currentRef + "] " + this.fileName
                + " have cleanup, do not do it again.");
            return true;
        }

        clean(this.mappedByteBuffer);
        TOTAL_MAPPED_VIRTUAL_MEMORY.addAndGet(this.fileSize * (-1));
        TOTAL_MAPPED_FILES.decrementAndGet();
        log.info("unmap file[REF:" + currentRef + "] " + this.fileName + " OK");
        return true;
    }
```

首先判断 MappedFile 是否可用, 如果可用直接返回 false, 不走销毁逻辑, 然后判断当前是否已经释放资源完成, 如果已经释放了, 就直接返回 true 即可.

然后才是真正的销毁流程, 直接通过 mappedByteBuffer 对文件进行清理, 然后维护 TOTAL_MAPPED_VIRTUAL_MEMORY 和 TOTAL_MAPPED_FILES, 最后返回 true, cleanupOver 也就变成了 true ,表示资源释放完成.

1. 关闭 FileChannel, 通过最开始创建的 File 对象, 将文件删除.

# TransientStorePool

前面讲提交和刷盘时多次提到 TransientStorePool, 那么它到底是什么?

它是 RocketMQ 为 MappedByteBuffer 单独创建的一个缓存池, 数据先写入这个缓存池, 然后由 commit 线程将数据从缓存池写入文件对应的内存映射中,

这么做的原因是, **为了将将当前堆外内存一直锁定在内存中, 避免被进程将内存交换到磁盘.** 

看看 TransientStorePool 的一些主要属性:

```Java
// availableBuffers 个数, 默认 5 个, 可在 broker 配置文件中配置. 
private final int poolSize;
// 每个 ByteBuffer 大小, 默认是 mappedFileSizeCommitLog, 也就是默认 1G 的样子
private final int fileSize;
// ByteBuffer 容器, 双端队列
private final Deque<ByteBuffer> availableBuffers;
// 消息存储配置
private final MessageStoreConfig storeConfig;
```