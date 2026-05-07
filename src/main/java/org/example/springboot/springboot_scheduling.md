# Spring Boot Scheduling & Batch – Deep Dive

## Mục lục
1. [@Scheduled – Tác vụ định kỳ](#1-scheduled--tác-vụ-định-kỳ)
2. [Distributed Scheduling – ShedLock](#2-distributed-scheduling--shedlock)
3. [Quartz Scheduler](#3-quartz-scheduler)
4. [Spring Batch – Xử lý dữ liệu lớn](#4-spring-batch--xử-lý-dữ-liệu-lớn)

---

## 1. @Scheduled – Tác vụ định kỳ

### 1.1 Setup

```java
@SpringBootApplication
@EnableScheduling   // bắt buộc
public class App {}
```

### 1.2 Cron Expressions & Variants

```java
@Component
@Slf4j
public class ScheduledTasks {

    // Cron format: giây phút giờ ngày tháng thứInTuần
    @Scheduled(cron = "0 0 2 * * ?")            // 2:00 AM mỗi ngày
    @Scheduled(cron = "0 0 9-17 * * MON-FRI")   // mỗi giờ, giờ hành chính T2-T6
    @Scheduled(cron = "0 */15 * * * ?")          // mỗi 15 phút
    @Scheduled(cron = "0 0 0 1 * ?")             // đầu mỗi tháng

    // fixedDelay: N ms sau khi task trước HOÀN THÀNH (ngăn overlap)
    @Scheduled(fixedDelay = 5000)

    // fixedRate: mỗi N ms (tính từ START — có thể overlap nếu task chậm)
    @Scheduled(fixedRate = 10000)

    // initialDelay: delay trước lần chạy đầu tiên
    @Scheduled(fixedDelay = 5000, initialDelay = 30000)

    // Từ properties (externalized — dễ thay đổi không cần rebuild)
    @Scheduled(cron = "${app.tasks.cleanup.cron:0 0 3 * * ?}")
    public void cleanupOldData() {
        log.info("Running cleanup at {}", LocalDateTime.now());
        dataCleanupService.deleteOlderThan(30, ChronoUnit.DAYS);
    }

    @Scheduled(fixedDelayString = "${app.tasks.metrics.interval:60000}")
    public void collectMetrics() {
        metricsService.collect();
    }

    // Cron với timezone
    @Scheduled(cron = "0 0 8 * * MON-FRI", zone = "Asia/Ho_Chi_Minh")
    public void morningReport() {
        reportService.sendDailyDigest();
    }
}
```

### 1.3 Thread Pool cho Scheduling

```java
// Mặc định: 1 thread cho tất cả @Scheduled → tasks block nhau!

@Configuration
public class SchedulingConfig implements SchedulingConfigurer {

    @Override
    public void configureTasks(ScheduledTaskRegistrar registrar) {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(5);
        scheduler.setThreadNamePrefix("sched-");
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(30);
        scheduler.initialize();
        registrar.setTaskScheduler(scheduler);
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

### 1.4 Dynamic Scheduling (Runtime)

```java
@Service
public class DynamicSchedulerService {

    @Autowired
    private TaskScheduler taskScheduler;

    private final Map<String, ScheduledFuture<?>> scheduledTasks = new ConcurrentHashMap<>();

    public void schedule(String taskId, Runnable task, String cronExpression) {
        ScheduledFuture<?> future = taskScheduler.schedule(
            task, new CronTrigger(cronExpression)
        );
        scheduledTasks.put(taskId, future);
    }

    public void cancel(String taskId) {
        ScheduledFuture<?> future = scheduledTasks.remove(taskId);
        if (future != null) {
            future.cancel(false);  // false = don't interrupt if running
        }
    }

    public void reschedule(String taskId, Runnable task, String newCron) {
        cancel(taskId);
        schedule(taskId, task, newCron);
    }
}
```

---

## 2. Distributed Scheduling – ShedLock

### 2.1 Problem

```
3 instances cùng chạy cleanup job → duplicate work, conflict, data corruption
```

### 2.2 ShedLock (JDBC-backed distributed lock)

```xml
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-spring</artifactId>
    <version>5.10.0</version>
</dependency>
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-provider-jdbc-template</artifactId>
    <version>5.10.0</version>
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
        // Chỉ 1 instance chạy tại 1 thời điểm
        dataCleanupService.deleteOlderThan(30, ChronoUnit.DAYS);
    }

    @Scheduled(cron = "0 0 1 * * ?")
    @SchedulerLock(name = "monthly-report", lockAtMostFor = "PT30M")
    public void generateMonthlyReport() {
        reportService.generateAndSend();
    }
}
```

### 2.3 Other Distributed Scheduling Options

| Approach | Pros | Cons |
|----------|------|------|
| ShedLock + JDBC | Simple, DB-backed | Requires DB table |
| ShedLock + Redis | Fast, no DB schema | Redis dependency |
| Quartz + JDBC store | Full-featured, cluster-aware | Complex config |
| K8s CronJob | Native K8s, single pod | Need K8s |

---

## 3. Quartz Scheduler

Phù hợp khi cần: persistent jobs, cluster-aware, dynamic job creation/cancellation, complex triggers.

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
    job-store-type: jdbc            # MEMORY (dev) | JDBC (prod, cluster-aware)
    jdbc:
      initialize-schema: always     # create Quartz tables automatically
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
        JobDataMap data = context.getMergedJobDataMap();
        String tenantId = data.getString("tenantId");
        String reportType = data.getString("reportType");

        try {
            Report report = reportService.generate(tenantId, reportType);
            data.put("lastReportId", report.getId()); // persist for next run
        } catch (Exception e) {
            throw new JobExecutionException(e, true); // true = refire immediately
        }
    }
}
```

### 3.3 Programmatic Job Scheduling

```java
@Service
@RequiredArgsConstructor
public class JobSchedulerService {

    private final Scheduler scheduler;

    public void scheduleMonthlyReport(String tenantId, String reportType) throws SchedulerException {
        JobDetail job = JobBuilder.newJob(ReportGenerationJob.class)
            .withIdentity("report-" + tenantId + "-" + reportType, "reports")
            .usingJobData("tenantId", tenantId)
            .usingJobData("reportType", reportType)
            .storeDurably()
            .build();

        CronTrigger trigger = TriggerBuilder.newTrigger()
            .withIdentity("trigger-" + tenantId, "reports")
            .withSchedule(CronScheduleBuilder.cronSchedule("0 0 0 1 * ?"))  // 1st of month
            .build();

        if (scheduler.checkExists(job.getKey())) {
            scheduler.rescheduleJob(trigger.getKey(), trigger);
        } else {
            scheduler.scheduleJob(job, trigger);
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

---

## 4. Spring Batch – Xử lý dữ liệu lớn

### 4.1 Core Concepts

```
Job ──→ N Steps (sequential | parallel | conditional)
         └── Step:
             ├── Chunk-oriented: ItemReader → ItemProcessor → ItemWriter (batched commit)
             └── Tasklet: single atomic operation (e.g., cleanup, init)

Chunk processing:
  Read N items → Process N items → Write N items → commit → repeat until EOF
```

### 4.2 Setup

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-batch</artifactId>
</dependency>
```

```yaml
spring:
  batch:
    job:
      enabled: false         # không auto-run khi startup — control manually
    jdbc:
      initialize-schema: always   # tạo Spring Batch metadata tables
```

### 4.3 Complete Example: CSV → Database Import

```java
@Configuration
@RequiredArgsConstructor
public class UserImportBatchConfig {

    private final JobRepository jobRepository;
    private final PlatformTransactionManager txManager;
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    // === READER: đọc từng dòng CSV ===
    @Bean
    @StepScope  // tạo mới mỗi Step execution (required for JobParameters injection)
    public FlatFileItemReader<UserCsvRecord> userCsvReader(
            @Value("#{jobParameters['filePath']}") String filePath) {

        return new FlatFileItemReaderBuilder<UserCsvRecord>()
            .name("userCsvReader")
            .resource(new FileSystemResource(filePath))
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
                log.warn("Skipping invalid email: {}", record.getEmail());
                return null;  // null = skip this item (counted in skipCount)
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
    public Step userImportStep() {
        return new StepBuilder("userImportStep", jobRepository)
            .<UserCsvRecord, User>chunk(500, txManager)  // commit every 500 records
            .reader(userCsvReader(null))
            .processor(userProcessor())
            .writer(userWriter(null))
            .faultTolerant()
                .skipLimit(100)                          // allow up to 100 skips
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
            .incrementer(new RunIdIncrementer())   // unique run ID for re-runs
            .listener(new JobExecutionListener() {
                @Override
                public void afterJob(JobExecution execution) {
                    StepExecution step = execution.getStepExecutions().iterator().next();
                    log.info("Import complete: read={}, written={}, skipped={}, status={}",
                        step.getReadCount(), step.getWriteCount(),
                        step.getSkipCount(), execution.getStatus());
                }
            })
            .flow(userImportStep)
            .end()
            .build();
    }
}
```

### 4.4 Trigger Job

```java
@Service
@RequiredArgsConstructor
public class BatchJobService {

    private final JobLauncher jobLauncher;
    private final AsyncJobLauncher asyncJobLauncher;
    private final Job userImportJob;

    // Synchronous — blocks until done
    public JobExecution triggerImport(String filePath) throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("filePath", filePath)
            .addLong("startTime", System.currentTimeMillis())  // unique key for re-runs
            .toJobParameters();

        return jobLauncher.run(userImportJob, params);
    }

    // Asynchronous — returns immediately, check status by execution ID
    public Long triggerImportAsync(String filePath) throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("filePath", filePath)
            .addLong("startTime", System.currentTimeMillis())
            .toJobParameters();

        JobExecution execution = asyncJobLauncher.run(userImportJob, params);
        return execution.getId();
    }

    // Check status
    @Autowired
    private JobExplorer jobExplorer;

    public BatchStatus getStatus(Long executionId) {
        return jobExplorer.getJobExecution(executionId).getStatus();
    }
}

// REST endpoint to trigger and monitor
@RestController
@RequestMapping("/api/batch")
public class BatchController {

    @PostMapping("/import")
    public ResponseEntity<Map<String, Object>> triggerImport(
            @RequestParam String filePath) throws Exception {

        Long executionId = batchJobService.triggerImportAsync(filePath);
        return ResponseEntity.accepted()
            .body(Map.of("executionId", executionId, "status", "STARTED"));
    }

    @GetMapping("/status/{executionId}")
    public BatchStatus getStatus(@PathVariable Long executionId) {
        return batchJobService.getStatus(executionId);
    }
}
```

### 4.5 Parallel Steps

```java
@Bean
public Job parallelJob(Step enrichStep, Step validateStep, Step finalizeStep) {

    Flow enrichFlow = new FlowBuilder<Flow>("enrichFlow").start(enrichStep).build();
    Flow validateFlow = new FlowBuilder<Flow>("validateFlow").start(validateStep).build();

    // enrichStep + validateStep run in parallel, then finalizeStep
    Flow parallelFlow = new FlowBuilder<Flow>("parallelFlow")
        .split(new SimpleAsyncTaskExecutor())
        .add(enrichFlow, validateFlow)
        .build();

    return new JobBuilder("parallelJob", jobRepository)
        .start(parallelFlow)
        .next(finalizeStep)    // runs after both flows complete
        .end()
        .build();
}
```

### 4.6 Partitioned Step (Scale-out)

```java
// Partition: split data into chunks, process in parallel threads/nodes
@Bean
public Step partitionedStep(Step workerStep) {
    return new StepBuilder("partitionedStep", jobRepository)
        .partitioner("workerStep", partitioner())
        .step(workerStep)
        .taskExecutor(new SimpleAsyncTaskExecutor())
        .gridSize(10)          // 10 partitions = 10 parallel worker steps
        .build();
}

@Bean
public Partitioner partitioner() {
    return gridSize -> {
        Map<String, ExecutionContext> partitions = new HashMap<>();
        long totalRecords = userRepository.count();
        long pageSize = totalRecords / gridSize;

        for (int i = 0; i < gridSize; i++) {
            ExecutionContext ctx = new ExecutionContext();
            ctx.putLong("offset", (long) i * pageSize);
            ctx.putLong("limit", pageSize);
            partitions.put("partition-" + i, ctx);
        }
        return partitions;
    };
}
```

---

## Summary: Trade-offs

| | @Scheduled | ShedLock | Quartz | Spring Batch |
|--|-----------|---------|--------|-------------|
| Setup complexity | Minimal | Low | Medium | High |
| Cluster-aware | ❌ No | ✅ Yes | ✅ Yes | N/A |
| Persistent jobs | ❌ No | ❌ No | ✅ Yes | ✅ Yes (metadata) |
| Dynamic scheduling | ❌ No | ❌ No | ✅ Yes | ❌ No |
| Restart/retry | ❌ No | ❌ No | ✅ Yes | ✅ Yes |
| Large data processing | ❌ No | ❌ No | ❌ No | ✅ Yes |
| Best for | Simple periodic tasks | Distributed cron | Dynamic persistent jobs | ETL, bulk import/export |
