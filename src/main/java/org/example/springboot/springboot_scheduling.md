# Spring Boot Scheduling & Batch – Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Production – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)
>
> Phạm vi chính: Spring Boot 3.5/4.1, Spring Framework 6.2/7.0 và Spring Batch 5.2/6.x. Những API khác nhau theo major version được ghi rõ tại chỗ.

---

## What – Scheduling và Batch giải quyết việc gì?

**Scheduling** *(lập lịch)* quyết định **khi nào** một tác vụ được kích hoạt. **Batch processing** *(xử lý theo lô)* quyết định cách chia, lưu trạng thái, retry và restart một khối lượng dữ liệu lớn.

```text
Clock / trigger ──► Scheduler ──► gọi tác vụ
                                      │
                                      └─► Spring Batch Job
                                           └─► Step → chunk/tasklet → metadata
```

`@Scheduled`, ShedLock và Quartz là các lựa chọn kích hoạt công việc. Spring Batch là processing framework; nó không thay thế scheduler. Một hệ thống production thường dùng scheduler để khởi chạy một Batch Job có metadata và restart semantics rõ ràng.

> 💡 **Giải thích dễ hiểu:**
> Scheduler giống đồng hồ báo thức: nó nhắc “đến giờ làm”. Spring Batch giống quy trình vận hành kho: chia hàng thành lô, ghi lô nào đã xong và biết tiếp tục từ đâu nếu mất điện.

## Why – Vì sao không đặt mọi việc vào một cron method?

- Cron method đơn giản không tự lưu execution state, retry history hoặc checkpoint.
- Nhiều application instance có thể cùng kích hoạt một tác vụ.
- Tác vụ chạy lâu có thể chặn scheduler thread hoặc vượt quá lần kích hoạt kế tiếp.
- Retry không idempotent có thể tạo duplicate email, payment hoặc dữ liệu.
- Khi deploy/restart, lịch chạy bị lỡ cần **misfire policy** *(chính sách xử lý lần chạy bị lỡ)* rõ ràng.

## Components – Bản đồ lựa chọn

| Công cụ | Vai trò chính | Có metadata bền vững? | Khi phù hợp |
|---------|---------------|-----------------------|-------------|
| `@Scheduled` | Lịch đơn giản trong process | Không | Tác vụ ngắn, lịch tĩnh, chấp nhận lifecycle theo ứng dụng |
| ShedLock | Lock quanh tác vụ đã được schedule | Chỉ lưu lock | Nhiều instance nhưng chỉ một instance được chạy mỗi lần |
| Quartz | Scheduler với job/trigger/misfire/calendar | Có với JDBC store | Lịch động, persistent, cluster-aware |
| Spring Batch | Xử lý theo step/chunk có checkpoint | Có `JobRepository` | ETL, import/export, reconciliation, restart/retry |

## When – Chọn nhanh

- Dùng `@Scheduled` nếu lịch ít, cố định và task có thể chạy lặp an toàn.
- Thêm ShedLock nếu cùng ứng dụng chạy nhiều replica và “lần khác bỏ qua” là chấp nhận được.
- Dùng Quartz nếu người dùng tạo/sửa lịch runtime, cần persistent trigger hoặc misfire policy.
- Dùng Spring Batch khi cần chunk transaction, skip/retry, execution metadata và restart.

## Mục lục

1. [@Scheduled – Tác vụ định kỳ](#1-scheduled--tác-vụ-định-kỳ)
2. [Distributed Scheduling – ShedLock](#2-distributed-scheduling--shedlock)
3. [Quartz Scheduler](#3-quartz-scheduler)
4. [Spring Batch – Xử lý dữ liệu lớn](#4-spring-batch--xử-lý-dữ-liệu-lớn)
5. [Compare – Chọn công cụ nào?](#5-compare--chọn-công-cụ-nào)
6. [Trade-offs](#6-trade-offs--các-đánh-đổi-quan-trọng)
7. [Production checklist](#7-production-checklist)
8. [Ghi chú](#8-ghi-chú)
9. [Nguồn tham khảo chính thức](#9-nguồn-tham-khảo-chính-thức)

---

## 1. @Scheduled – Tác vụ định kỳ

### 1.1 Setup

```java
@SpringBootApplication
@EnableScheduling   // bắt buộc
public class App {}
```

### 1.2 Cron Expressions & Variants

Spring cron dùng **6 trường**: `second minute hour day-of-month month day-of-week`. Không copy trực tiếp biểu thức cron 5 trường của Linux mà chưa kiểm tra.

```java
@Component
@Slf4j
public class ScheduledTasks {

    // 03:00 mỗi ngày; cấu hình ngoài để đổi lịch không rebuild.
    @Scheduled(
        cron = "${app.tasks.cleanup.cron:0 0 3 * * *}",
        zone = "${app.tasks.cleanup.zone:Asia/Ho_Chi_Minh}"
    )
    public void cleanupOldData() {
        log.info("Running cleanup at {}", LocalDateTime.now());
        dataCleanupService.deleteOlderThan(30, ChronoUnit.DAYS);
    }

    // Khoảng nghỉ được tính từ lúc lần trước HOÀN THÀNH.
    @Scheduled(
        fixedDelayString = "${app.tasks.metrics.delay:60s}",
        initialDelayString = "${app.tasks.metrics.initial-delay:10s}"
    )
    public void collectMetrics() {
        metricsService.collect();
    }

    // Khoảng thời gian được tính giữa hai thời điểm BẮT ĐẦU.
    @Scheduled(fixedRate = 15, timeUnit = TimeUnit.MINUTES)
    public void refreshReferenceData() {
        referenceDataService.refresh();
    }

    @Scheduled(cron = "0 0 8 * * MON-FRI", zone = "Asia/Ho_Chi_Minh")
    public void morningReport() {
        reportService.sendDailyDigest();
    }
}
```

| Kiểu trigger | Cách tính | Lưu ý |
|--------------|-----------|-------|
| `fixedDelay` | Từ lúc lần trước hoàn thành | Phù hợp polling; không tạo nhịp cố định theo đồng hồ |
| `fixedRate` | Giữa thời điểm bắt đầu các lần chạy | Nếu task chậm, lần kế tiếp có thể chạy muộn; `ScheduledExecutorService` không tự chạy chồng cùng periodic task |
| `cron` | Theo lịch và timezone | Phải xử lý DST, clock và lần deploy/restart bị lỡ |
| `initialDelay` | Chờ trước lần đầu | Có thể dùng một mình cho one-time task ở Spring Framework hiện đại |

`@Scheduled` là repeatable. Nếu đặt nhiều annotation trên cùng method, mỗi trigger độc lập và có thể kích hoạt gần nhau hoặc chồng nhau. Vì vậy ví dụ production nên dùng mỗi method một lịch trừ khi chủ đích thật sự là nhiều trigger.

> 💡 **Giải thích dễ hiểu:**
> `fixedDelay` giống nghỉ 10 phút sau khi làm xong một ca. `fixedRate` giống chuông reo mỗi 10 phút; nếu ca trước kéo dài, ca sau bị trễ chứ đồng hồ không đổi ý định ban đầu. Cron giống lịch treo tường, nên timezone và giờ mùa hè cũng ảnh hưởng.

### 1.3 Thread Pool cho Scheduling

```java
@Configuration
@Slf4j
public class SchedulingConfig {

    @Bean
    public ThreadPoolTaskScheduler taskScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(5);
        scheduler.setThreadNamePrefix("sched-");
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(30);
        scheduler.setErrorHandler(
            error -> log.error("Uncaught scheduled task error", error)
        );
        return scheduler; // Spring quản lý initialize/shutdown của bean
    }
}
```

```yaml
# Or via application.yml (Spring Boot auto-config)
spring:
  task:
    scheduling:
      pool:
        size: 5
      thread-name-prefix: "sched-"
      shutdown:
        await-termination: true
        await-termination-period: 30s
```

`ThreadPoolTaskScheduler` mặc định có một scheduler thread. Task chạy blocking lâu sẽ làm các lịch khác bị trễ nếu pool không đủ. Tăng pool chỉ sau khi xác định task có thread-safe, idempotent và downstream đủ capacity.

Khi bật virtual thread trên Spring Boot hiện đại, Boot có thể dùng `SimpleAsyncTaskScheduler`. Fixed-delay task của scheduler này chạy trên một scheduler thread, nên không nên dùng fixed-delay cho công việc blocking dài nếu chưa kiểm chứng implementation/version.

> 💡 **Giải thích dễ hiểu:**
> Scheduler pool giống số nhân viên trực tổng đài. Một nhân viên gặp cuộc gọi kéo dài thì các lịch khác phải chờ. Tuy nhiên, thuê thêm nhân viên không giúp nếu database chỉ có hai quầy phục vụ.

### 1.4 Dynamic Scheduling (Runtime)

```java
@Service
public class DynamicSchedulerService {

    private final TaskScheduler taskScheduler;

    private final Map<String, ScheduledFuture<?>> scheduledTasks = new ConcurrentHashMap<>();

    public DynamicSchedulerService(TaskScheduler taskScheduler) {
        this.taskScheduler = taskScheduler;
    }

    public synchronized void schedule(
            String taskId, Runnable task, String cronExpression, ZoneId zone) {

        CronExpression.parse(cronExpression); // fail fast nếu cron sai
        cancel(taskId);

        ScheduledFuture<?> future = taskScheduler.schedule(
            task,
            new CronTrigger(cronExpression, zone)
        );
        scheduledTasks.put(taskId, Objects.requireNonNull(future));
    }

    public synchronized void cancel(String taskId) {
        ScheduledFuture<?> future = scheduledTasks.remove(taskId);
        if (future != null) {
            future.cancel(false); // không interrupt lần đang chạy
        }
    }

    @PreDestroy
    void cancelAll() {
        scheduledTasks.values().forEach(future -> future.cancel(false));
        scheduledTasks.clear();
    }
}
```

Map trên chỉ nằm trong memory: restart sẽ mất lịch và mỗi replica tự có một bản. Nếu lịch do người dùng tạo phải sống qua restart hoặc chạy duy nhất trong cluster, lưu definition trong database và dùng Quartz/JobRunr/db-scheduler hoặc một control plane chuyên dụng.

> 💡 **Giải thích dễ hiểu:**
> Dynamic scheduler trong memory giống viết lịch lên bảng trắng của một văn phòng. Tắt điện hoặc mở thêm chi nhánh thì mỗi nơi có một bảng khác nhau; lịch quan trọng cần được lưu vào “sổ chung” bền vững.

---

## 2. Distributed Scheduling – ShedLock

### 2.1 Why – Bài toán nhiều replica

```text
3 instances cùng chạy cleanup job → duplicate work, conflict, data corruption
```

ShedLock là **distributed lock** *(khóa phối hợp qua kho dùng chung)*, không phải distributed scheduler. Node không lấy được lock sẽ **bỏ qua lần chạy**, không đứng chờ đến lượt.

### 2.2 How – ShedLock với JDBC

```xml
<properties>
    <!-- Pin một release tương thích; 7.7.0 là mốc kiểm tra 2026-07-27. -->
    <shedlock.version>7.7.0</shedlock.version>
</properties>

<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-spring</artifactId>
    <version>${shedlock.version}</version>
</dependency>
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-provider-jdbc-template</artifactId>
    <version>${shedlock.version}</version>
</dependency>
```

```sql
-- Required table
CREATE TABLE shedlock (
    name       VARCHAR(64)  NOT NULL,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
```

```java
@SpringBootApplication
@EnableScheduling
@EnableSchedulerLock(defaultLockAtMostFor = "10m")
public class App {}

@Bean
public LockProvider lockProvider(DataSource dataSource) {
    return new JdbcTemplateLockProvider(
        JdbcTemplateLockProvider.Configuration.builder()
            .withJdbcTemplate(new JdbcTemplate(dataSource))
            .usingDbTime()  // use DB server time for consistency
            .build()
    );
}
```

```java
@Component
public class DistributedTasks {

    // lockAtLeastFor: hold lock min N minutes (prevent rapid re-runs)
    // lockAtMostFor: release lock after max N minutes (safety if instance crashes)
    @Scheduled(cron = "0 0 3 * * ?")
    @SchedulerLock(name = "cleanup-task",
                   lockAtLeastFor = "PT5M",
                   lockAtMostFor = "PT10M")
    public void cleanupOldData() {
        LockAssert.assertLocked();
        // Vẫn phải idempotent vì crash/retry có thể chạy lại.
        dataCleanupService.deleteOlderThan(30, ChronoUnit.DAYS);
    }

    @Scheduled(cron = "0 0 1 * * ?")
    @SchedulerLock(name = "monthly-report", lockAtMostFor = "PT30M")
    public void generateMonthlyReport() {
        reportService.generateAndSend();
    }
}
```

- `lockAtMostFor` là safety net khi JVM chết, phải dài hơn **worst-case runtime** có headroom.
- Nếu task chạy lâu hơn `lockAtMostFor`, instance khác có thể lấy lock và hai task chạy đồng thời.
- `lockAtLeastFor` hữu ích với task rất ngắn/clock skew, không phải timeout thực thi.
- `usingDbTime()` dùng clock của database và giảm lỗi lệch giờ giữa application node.
- Lock không thay thế unique constraint, idempotency key hoặc transaction nghiệp vụ.

> 💡 **Giải thích dễ hiểu:**
> ShedLock giống chiếc chìa khóa phòng máy dùng chung. Ai không lấy được chìa khóa thì bỏ ca, không xếp hàng. `lockAtMostFor` giống giờ chìa khóa tự hết hiệu lực; đặt quá ngắn thì người thứ hai có thể vào khi người thứ nhất vẫn đang làm.

### 2.3 Other Distributed Scheduling Options

| Approach | Pros | Cons |
|----------|------|------|
| ShedLock + JDBC | Đơn giản, dùng DB time | Cạnh tranh DB; lần không có lock bị skip |
| ShedLock + Redis | Không cần bảng SQL | Phụ thuộc availability/semantics của Redis provider |
| Quartz + JDBC store | Scheduler đầy đủ, cluster-aware | Schema và vận hành phức tạp hơn |
| Kubernetes CronJob | Tách lifecycle job khỏi web app | Cần policy concurrency, retry, deadline và idempotency |

---

## 3. Quartz Scheduler

Quartz phù hợp khi cần persistent jobs, dynamic job creation/cancellation, calendars, misfire policy và cluster-aware JDBC store. **Job** mô tả công việc; **Trigger** mô tả thời điểm chạy; **Scheduler** phối hợp thực thi.

> 💡 **Giải thích dễ hiểu:**
> Quartz giống phòng điều độ có sổ lịch bền vững. Tác vụ là “đội thợ”, trigger là “phiếu hẹn”; mất điện xong phòng điều độ vẫn biết phiếu nào tồn tại và áp quy tắc cho lịch đã lỡ.

### 3.1 Setup

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-quartz</artifactId>
</dependency>
```

```yaml
spring:
  quartz:
    job-store-type: jdbc
    jdbc:
      # Production: quản lý Quartz schema bằng Flyway/Liquibase.
      # Script chuẩn của Boot có thể drop bảng/dữ liệu khi initialize.
      initialize-schema: never
    properties:
      org.quartz.scheduler.instanceId: AUTO
      org.quartz.jobStore.isClustered: true
      org.quartz.jobStore.clusterCheckinInterval: 10000
      org.quartz.threadPool.threadCount: 10
```

### 3.2 Job Definition

```java
@Component
@PersistJobDataAfterExecution   // save JobDataMap after each run
@DisallowConcurrentExecution    // no overlap across cluster nodes
public class ReportGenerationJob implements Job {

    @Autowired
    private ReportService reportService;  // Spring injection via AutowireCapableBeanFactory

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        JobDataMap input = context.getMergedJobDataMap();
        JobDataMap persistentState = context.getJobDetail().getJobDataMap();
        String tenantId = input.getString("tenantId");
        String reportType = input.getString("reportType");

        try {
            Report report = reportService.generate(tenantId, reportType);
            // Chỉ thay đổi JobDetail map mới được @Persist... ghi lại.
            persistentState.put("lastReportId", report.getId());
        } catch (Exception e) {
            // Tránh refireImmediately vô hạn tạo hot loop.
            throw new JobExecutionException(e);
        }
    }
}
```

`@DisallowConcurrentExecution` được áp theo `JobKey`, không phải toàn bộ class. `@PersistJobDataAfterExecution` ghi lại `JobDetail.getJobDataMap()`; thay đổi trên merged map không được lưu ngược. Dữ liệu trong map phải nhỏ, serializable/stable và không nên chứa secret hay object domain lớn.

Chọn **misfire instruction** theo nghiệp vụ: chạy ngay một lần, bỏ qua lần lỡ, hoặc tiếp tục lịch kế tiếp. Không có một mặc định đúng cho billing, report và cleanup cùng lúc.

### 3.3 Programmatic Job Scheduling

```java
@Service
@RequiredArgsConstructor
public class JobSchedulerService {

    private final Scheduler scheduler;

    public void scheduleMonthlyReport(String tenantId, String reportType) throws SchedulerException {
        JobKey jobKey = new JobKey(
            "report-" + tenantId + "-" + reportType, "reports"
        );
        TriggerKey triggerKey = new TriggerKey(
            "trigger-" + tenantId + "-" + reportType, "reports"
        );

        JobDetail job = JobBuilder.newJob(ReportGenerationJob.class)
            .withIdentity(jobKey)
            .usingJobData("tenantId", tenantId)
            .usingJobData("reportType", reportType)
            .storeDurably()
            .build();

        CronTrigger trigger = TriggerBuilder.newTrigger()
            .withIdentity(triggerKey)
            .forJob(jobKey)
            .withSchedule(
                CronScheduleBuilder.cronSchedule("0 0 0 1 * ?")
                    .inTimeZone(TimeZone.getTimeZone("Asia/Ho_Chi_Minh"))
                    .withMisfireHandlingInstructionDoNothing()
            )
            .build();

        if (!scheduler.checkExists(jobKey)) {
            scheduler.scheduleJob(job, trigger);
            return;
        }

        scheduler.addJob(job, true);
        if (scheduler.checkExists(triggerKey)) {
            scheduler.rescheduleJob(triggerKey, trigger);
        } else {
            scheduler.scheduleJob(trigger);
        }
    }

    public void cancelJob(String tenantId, String reportType) throws SchedulerException {
        scheduler.deleteJob(new JobKey("report-" + tenantId + "-" + reportType, "reports"));
    }

    public void pauseAllJobsInGroup(String group) throws SchedulerException {
        scheduler.pauseJobs(GroupMatcher.jobGroupEquals(group));
    }

    public JobDetail getJobDetails(String name, String group) throws SchedulerException {
        return scheduler.getJobDetail(new JobKey(name, group));
    }
}
```

Cluster node phải dùng cùng Quartz table set và đồng bộ clock. Thread count phải được cân bằng với connection pool/downstream capacity; nhiều Quartz thread không giúp nếu mọi job cùng chờ một database nhỏ.

Luồng tạo/cập nhật phía trên vẫn cần được serialize theo `JobKey` hoặc bắt `ObjectAlreadyExistsException` nếu nhiều request quản trị có thể sửa cùng một lịch đồng thời.

---

## 4. Spring Batch – Xử lý dữ liệu lớn

Spring Batch là framework xử lý dữ liệu theo job/step có **execution metadata** *(metadata lần chạy)*, transaction, skip/retry và restart. Nó phù hợp với workload hữu hạn; không phải stream processor chạy vô hạn.

### 4.1 Components – Core Concepts

```text
JobInstance = Job name + identifying JobParameters
  └─ JobExecution = một lần thử chạy JobInstance
       └─ StepExecution = trạng thái một lần chạy Step

Job ──→ N Steps (sequential | parallel | conditional)
         └── Step:
             ├── Chunk-oriented: ItemReader → ItemProcessor → ItemWriter (batched commit)
             └── Tasklet: single atomic operation (e.g., cleanup, init)

Chunk processing:
  Read N items → Process N items → Write N items → commit → repeat until EOF
```

`JobRepository` lưu metadata/checkpoint. Restart chỉ đúng khi reader/writer lưu state cần thiết vào `ExecutionContext` và input vẫn có identity/order ổn định.

> 💡 **Giải thích dễ hiểu:**
> Batch Job giống hồ sơ nhập một container hàng. `JobInstance` là container cụ thể, `JobExecution` là mỗi lần thử dỡ container, còn `StepExecution` ghi từng công đoạn. Restart không phải tạo container mới; nó mở đúng hồ sơ cũ để tiếp tục.

### 4.2 Setup

Spring Boot 3.x thường dùng:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-batch</artifactId>
</dependency>
```

Spring Boot 4 modular hóa starter; batch dùng JDBC metadata cần `spring-boot-starter-batch-jdbc`. Luôn kiểm tra dependency guide của đúng major version.

```yaml
spring:
  batch:
    job:
      enabled: false         # không auto-run khi startup — control manually
    jdbc:
      # Production: dùng Flyway/Liquibase và đặt never.
      initialize-schema: never
```

`initialize-schema: always` chỉ thuận tiện cho dev/test. Production phải version-control bảng metadata Batch; xóa hoặc lệch schema sẽ làm mất khả năng nhận diện instance/restart.

### 4.3 Complete Example: CSV → Database Import

```java
@Configuration
@RequiredArgsConstructor
public class UserImportBatchConfig {

    private final JobRepository jobRepository;
    private final PlatformTransactionManager txManager;
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final ImportResourceResolver importResourceResolver;

    // === READER: đọc từng dòng CSV ===
    @Bean
    @StepScope  // tạo mới mỗi Step execution (required for JobParameters injection)
    public FlatFileItemReader<UserCsvRecord> userCsvReader(
            @Value("#{jobParameters['inputKey']}") String inputKey) {

        return new FlatFileItemReaderBuilder<UserCsvRecord>()
            .name("userCsvReader")
            .resource(importResourceResolver.resolve(inputKey))
            .linesToSkip(1)   // skip CSV header
            .delimited()
                .delimiter(",")
                .names("name", "email", "role", "tenantId")
            .targetType(UserCsvRecord.class)
            .build();
    }

    // === PROCESSOR: validate + transform ===
    @Bean
    public ItemProcessor<UserCsvRecord, User> userProcessor() {
        return record -> {
            if (!isValidEmail(record.getEmail())) {
                log.warn("Filtering invalid email: {}", record.getEmail());
                return null;  // null = filter, được tính vào filterCount
            }

            return User.builder()
                .name(record.getName())
                .email(record.getEmail().toLowerCase())
                .role(Role.of(record.getRole()))
                .tenantId(Long.parseLong(record.getTenantId()))
                .passwordHash(passwordEncoder.encode(UUID.randomUUID().toString()))
                .build();
        };
    }

    // === WRITER: bulk upsert (faster than RepositoryItemWriter) ===
    @Bean
    public JdbcBatchItemWriter<User> userWriter(DataSource dataSource) {
        return new JdbcBatchItemWriterBuilder<User>()
            .sql("""
                INSERT INTO users (name, email, role, tenant_id, password_hash)
                VALUES (:name, :email, :role, :tenantId, :passwordHash)
                ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
                """)
            .dataSource(dataSource)
            .beanMapped()
            .build();
    }

    // === STEP: wires reader + processor + writer with chunk size ===
    @Bean
    public Step userImportStep(
            FlatFileItemReader<UserCsvRecord> userCsvReader,
            ItemProcessor<UserCsvRecord, User> userProcessor,
            JdbcBatchItemWriter<User> userWriter) {

        return new StepBuilder("userImportStep", jobRepository)
            .<UserCsvRecord, User>chunk(500, txManager)  // commit every 500 records
            .reader(userCsvReader)
            .processor(userProcessor)
            .writer(userWriter)
            .faultTolerant()
                .skipLimit(100)                          // exception skips, không tính filter
                .skip(ValidationException.class)
                .retryLimit(3)                           // retry transient errors 3x
                .retry(TransientDataAccessException.class)
            .listener(new ItemReadListener<UserCsvRecord>() {
                @Override
                public void onReadError(Exception ex) {
                    log.error("CSV read error: {}", ex.getMessage());
                }
            })
            .build();
    }

    // === JOB: top-level unit ===
    @Bean
    public Job userImportJob(Step userImportStep) {
        return new JobBuilder("userImportJob", jobRepository)
            .listener(new JobExecutionListener() {
                @Override
                public void afterJob(JobExecution execution) {
                    StepExecution step = execution.getStepExecutions().iterator().next();
                    log.info("Import: read={}, written={}, filtered={}, skipped={}, status={}",
                        step.getReadCount(), step.getWriteCount(),
                        step.getFilterCount(), step.getSkipCount(),
                        execution.getStatus());
                }
            })
            .flow(userImportStep)
            .end()
            .build();
    }
}
```

Các caveat production:

- `filePath` từ HTTP là input nguy hiểm; dùng object storage key/allow-list thay vì cho client đọc arbitrary filesystem path.
- CSV cần giới hạn kích thước dòng/file, encoding, quote/escape và dữ liệu công thức nếu xuất lại Excel.
- Chunk size là transaction boundary, không phải “càng lớn càng nhanh”; benchmark cùng DB batch size, lock time và memory.
- Retry chỉ dành cho lỗi transient. Validation/business error nên filter, skip có audit hoặc chuyển sang reject output.
- Writer/upsert phải idempotent vì chunk rollback/restart có thể xử lý lại item.

> 💡 **Giải thích dễ hiểu:**
> Chunk giống đóng dấu từng khay 500 hồ sơ. Khay lỗi thì làm lại cả khay, nên writer phải chịu được hồ sơ được đưa qua lần nữa. Khay quá lớn giữ khóa lâu; khay quá nhỏ tốn nhiều lần commit.

### 4.4 Trigger Job

```java
@Service
@RequiredArgsConstructor
public class BatchJobService {

    // Cấu hình implementation với TaskExecutor để HTTP không bị giữ lâu.
    private final JobLauncher jobLauncher;
    private final Job userImportJob;
    private final JobExplorer jobExplorer;

    public Long triggerImportAsync(
            String objectStorageKey, LocalDate businessDate) throws Exception {

        JobParameters params = new JobParametersBuilder()
            // Identifying params tạo identity của JobInstance.
            .addString("inputKey", objectStorageKey, true)
            .addLocalDate("businessDate", businessDate, true)
            .toJobParameters();

        JobExecution execution = jobLauncher.run(userImportJob, params);
        return execution.getId();
    }

    public Optional<JobExecution> getExecution(Long executionId) {
        return Optional.ofNullable(jobExplorer.getJobExecution(executionId));
    }
}

// REST endpoint to trigger and monitor
@RestController
@RequestMapping("/api/batch")
public class BatchController {

    @PostMapping("/import")
    public ResponseEntity<Map<String, Object>> triggerImport(
            @RequestParam String inputKey,
            @RequestParam
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
            LocalDate businessDate)
            throws Exception {

        Long executionId = batchJobService.triggerImportAsync(inputKey, businessDate);
        return ResponseEntity.accepted()
            .body(Map.of("executionId", executionId, "status", "STARTED"));
    }

    @GetMapping("/status/{executionId}")
    public ResponseEntity<JobExecutionView> getStatus(@PathVariable Long executionId) {
        return batchJobService.getExecution(executionId)
            .map(JobExecutionView::from)
            .map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.notFound().build());
    }
}

public record JobExecutionView(
        Long executionId,
        BatchStatus status,
        String exitCode) {

    static JobExecutionView from(JobExecution execution) {
        return new JobExecutionView(
            execution.getId(),
            execution.getStatus(),
            execution.getExitStatus().getExitCode()
        );
    }
}
```

`JobInstance` được xác định bởi job name và **identifying parameters**. Thêm `System.currentTimeMillis()` mỗi lần sẽ luôn tạo instance mới và vô hiệu hóa ý nghĩa restart của instance thất bại. Muốn restart, gửi lại đúng identifying parameters; muốn chạy một instance nghiệp vụ mới, thay `businessDate`, input version hoặc một run ID có ý nghĩa.

Với Spring Batch 5.2, có thể cấu hình `TaskExecutorJobLauncher` bằng bounded `TaskExecutor`. Spring Batch 6 chuyển trọng tâm sang `JobOperator`/`TaskExecutorJobOperator`; không hard-code class launcher nếu thư viện dùng chung phải hỗ trợ cả hai major version.

API trigger cần authentication, authorization, idempotency, concurrency limit và audit. Không trả trực tiếp toàn bộ `JobExecution` entity vì có thể lộ parameter/stack trace; map sang DTO ổn định.

### 4.5 Parallel Steps

```java
@Bean
public ThreadPoolTaskExecutor batchTaskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setThreadNamePrefix("batch-");
    executor.setCorePoolSize(4);
    executor.setMaxPoolSize(8);
    executor.setQueueCapacity(20);
    executor.setWaitForTasksToCompleteOnShutdown(true);
    executor.setAwaitTerminationSeconds(30);
    return executor; // Spring gọi initialize() và shutdown()
}

@Bean
public Job parallelJob(
        Step enrichStep,
        Step validateStep,
        Step finalizeStep,
        @Qualifier("batchTaskExecutor") TaskExecutor taskExecutor) {

    Flow enrichFlow = new FlowBuilder<Flow>("enrichFlow").start(enrichStep).build();
    Flow validateFlow = new FlowBuilder<Flow>("validateFlow").start(validateStep).build();

    // enrichStep + validateStep run in parallel, then finalizeStep
    Flow parallelFlow = new FlowBuilder<Flow>("parallelFlow")
        .split(taskExecutor)
        .add(enrichFlow, validateFlow)
        .build();

    return new JobBuilder("parallelJob", jobRepository)
        .start(parallelFlow)
        .next(finalizeStep)    // runs after both flows complete
        .end()
        .build();
}
```

Parallel flow phù hợp khi các step **độc lập về dữ liệu**. Nếu `validateStep` cần output của `enrichStep`, chúng phải chạy tuần tự. Mọi reader, processor, writer và service được gọi đồng thời cũng phải thread-safe hoặc có instance riêng theo step.

> 💡 **Ví von:** Hai đầu bếp có thể đồng thời làm món khai vị và món tráng miệng, nhưng không thể làm song song bước “nướng bánh” và “trang trí chính chiếc bánh đó”.

### 4.6 Partitioned Step (xử lý song song theo partition)

```java
@Bean
public Step partitionedStep(
        Step workerStep,
        Partitioner userIdRangePartitioner,
        @Qualifier("batchTaskExecutor") TaskExecutor taskExecutor) {

    return new StepBuilder("partitionedStep", jobRepository)
        .partitioner("workerStep", userIdRangePartitioner)
        .step(workerStep)
        .taskExecutor(taskExecutor)
        .gridSize(10) // Số partition mục tiêu, không phải cam kết có 10 thread
        .build();
}

@Bean
public Partitioner userIdRangePartitioner(UserRepository userRepository) {
    return gridSize -> {
        Map<String, ExecutionContext> partitions = new HashMap<>();
        Optional<Long> minId = userRepository.findMinId();
        Optional<Long> maxId = userRepository.findMaxId();

        if (minId.isEmpty() || maxId.isEmpty()) {
            return partitions;
        }

        long first = minId.get();
        long last = maxId.get();
        long totalIdRange = last - first + 1;
        long rangeSize = Math.max(1, (totalIdRange + gridSize - 1) / gridSize);

        int partitionNumber = 0;
        for (long start = first; start <= last; start += rangeSize) {
            long end = Math.min(last, start + rangeSize - 1);
            ExecutionContext ctx = new ExecutionContext();
            ctx.putLong("minId", start);
            ctx.putLong("maxId", end);
            partitions.put("partition-" + partitionNumber++, ctx);
        }
        return partitions;
    };
}

@Bean
@StepScope
public JdbcPagingItemReader<User> workerReader(
        DataSource dataSource,
        @Value("#{stepExecutionContext['minId']}") Long minId,
        @Value("#{stepExecutionContext['maxId']}") Long maxId) {

    return new JdbcPagingItemReaderBuilder<User>()
        .name("workerReader")
        .dataSource(dataSource)
        .selectClause("select id, email, status")
        .fromClause("from users")
        .whereClause("where id between :minId and :maxId")
        .parameterValues(Map.of("minId", minId, "maxId", maxId))
        .sortKeys(Map.of("id", Order.ASCENDING))
        .rowMapper(new UserRowMapper())
        .pageSize(500)
        .saveState(true)
        .build();
}
```

Phân vùng theo `offset/limit` trên bảng đang thay đổi dễ đọc trùng hoặc bỏ sót record; phép chia nguyên còn có thể làm mất phần dư hoặc tạo partition kích thước `0`. Khoảng ID ổn định hơn, dù ID có lỗ hổng vẫn không sai. Nếu dữ liệu phân bố lệch mạnh, hãy chọn partition key theo tenant, ngày nghiệp vụ hoặc hash bucket để tải cân bằng hơn.

`gridSize` chỉ gợi ý số mảnh công việc. Mức song song thật bị giới hạn bởi thread pool, connection pool, tài nguyên database và cách triển khai worker. Local partitioning chạy nhiều worker step trong một JVM; remote partitioning cần middleware và worker process riêng.

> 💡 **Ví von:** Partitioning giống chia một kho hồ sơ thành các dãy số kệ. Mỗi đội nhận một khoảng không giao nhau; kệ trống không gây sai, còn chia theo “20 thùng kế tiếp” sẽ dễ lệch nếu ai đó vẫn đang thêm hoặc bớt thùng.

---

## 5. Compare – Chọn công cụ nào?

| Tiêu chí | `@Scheduled` | `@Scheduled` + ShedLock | Quartz JDBC | Spring Batch |
|---|---|---|---|---|
| Vai trò chính | Kích hoạt tác vụ đơn giản | Chặn nhiều replica chạy cùng một lượt | Scheduler bền vững, động | Pipeline xử lý dữ liệu có trạng thái |
| Cluster-aware | Không | Có khóa dùng chung | Có khi bật JDBC job store và clustering | Metadata dùng chung; cách kích hoạt tùy hệ thống |
| Lưu lịch chạy | Không | Không; chỉ lưu khóa tạm thời | Có | Không phải scheduler |
| Thay đổi lịch runtime | Có thể tự lập trình, nhưng không qua annotation | Tương tự `@Scheduled` | Có API quản lý job/trigger | Job parameter động, không quản lý cron |
| Misfire sau downtime | Không tự bù | Không tự bù | Có policy misfire | Có thể restart execution thất bại |
| Restart theo checkpoint | Không | Không | Không phải chunk checkpoint | Có qua `JobRepository` và `ExecutionContext` |
| Xử lý ETL/bulk | Tự xây mọi cơ chế | Tự xây mọi cơ chế | Chỉ nên kích hoạt/orchestrate | Phù hợp |
| Độ phức tạp | Thấp | Thấp–trung bình | Trung bình–cao | Trung bình–cao |
| Dùng tốt nhất khi | Cleanup, refresh cache, heartbeat | Cron ngắn trên nhiều replica | Lịch động, calendar, misfire, lịch cần lưu | Import/export, reconciliation, migration dữ liệu |

Quartz và Spring Batch không loại trừ nhau: Quartz có thể quyết định **khi nào** chạy, còn Batch quyết định **xử lý dữ liệu như thế nào** và restart từ đâu.

## 6. Trade-offs – Các đánh đổi quan trọng

- Tăng scheduler pool giúp chạy đồng thời nhưng cũng tăng áp lực lên database, API downstream và connection pool.
- Distributed lock ngăn chạy trùng giữa replica nhưng không làm business operation tự động idempotent.
- Retry vô hạn có thể biến lỗi dữ liệu thành vòng lặp gây tải. Luôn đặt giới hạn, backoff và nơi lưu item lỗi.
- Chunk lớn giảm số transaction nhưng tăng thời gian giữ lock và lượng dữ liệu phải làm lại; chunk nhỏ an toàn hơn nhưng tăng overhead.
- Metadata bền vững giúp restart, nhưng schema Batch/Quartz phải được migrate và backup như dữ liệu production khác.

## 7. Production checklist

- Chọn một timezone rõ ràng; đồng bộ clock bằng NTP và kiểm thử thời điểm DST nếu nghiệp vụ chạy theo giờ địa phương.
- Đặt tên job, step, trigger và lock ổn định; xem chúng như identifier đã được lưu trong database.
- Giới hạn thread pool, queue, connection pool và số job chạy đồng thời; áp dụng backpressure ở điểm trigger.
- Thiết kế idempotency cho side effect như gửi email, gọi API và ghi file; “exactly once” không tự xuất hiện từ scheduler.
- Theo dõi thời gian chạy, lần chạy gần nhất, lỗi, skip/filter/retry count, queue depth và lock age.
- Dùng migration riêng cho schema Quartz, Spring Batch và ShedLock; tránh `initialize-schema: always` trong production.
- Bảo vệ API quản trị bằng authentication, authorization, audit log và idempotency key.
- Thử nghiệm shutdown, crash giữa chunk, restart, nhiều replica, misfire và job chạy lâu hơn chu kỳ lịch.

## 8. Ghi chú

- `@Scheduled` phù hợp nhất khi lịch là cấu hình triển khai và mất một lượt chạy sau downtime là chấp nhận được.
- ShedLock là thư viện khóa, không phải distributed scheduler. Node không lấy được khóa sẽ bỏ qua lượt đó thay vì chờ.
- `lockAtMostFor` là “dây an toàn” khi node chết, không phải timeout hủy method. Giá trị này phải dài hơn thời gian chạy tối đa thực tế.
- Spring Batch phân biệt `filter` (`ItemProcessor` trả `null`) với `skip` (framework bỏ qua item lỗi theo policy).
- Job restart được xác định bằng job name cộng identifying `JobParameters`; timestamp ngẫu nhiên luôn tạo một `JobInstance` mới.

## 9. Nguồn tham khảo chính thức

- [Spring Framework – Task Execution and Scheduling](https://docs.spring.io/spring-framework/reference/integration/scheduling.html)
- [Spring Boot – Task Execution and Scheduling](https://docs.spring.io/spring-boot/reference/features/task-execution-and-scheduling.html)
- [ShedLock – tài liệu dự án](https://github.com/lukas-krecan/ShedLock)
- [Quartz Scheduler Documentation](https://www.quartz-scheduler.org/documentation/)
- [Spring Batch Reference](https://docs.spring.io/spring-batch/reference/)
- [Spring Batch – Scaling and Parallel Processing](https://docs.spring.io/spring-batch/reference/scalability.html)
