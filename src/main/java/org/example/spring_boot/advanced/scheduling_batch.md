# Scheduling & Batch – Xử lý tác vụ định kỳ và hàng loạt

## @Scheduled – Tác vụ định kỳ

### Setup

```java
@SpringBootApplication
@EnableScheduling  // Bắt buộc
public class App {}
```

### Cron Expressions

```java
@Component
@Slf4j
public class ScheduledTasks {

    // Cron: giây phút giờ ngay tháng thứInTuần
    @Scheduled(cron = "0 0 2 * * ?")           // 2:00 AM mỗi ngày
    @Scheduled(cron = "0 0 9-17 * * MON-FRI")  // mỗi giờ từ 9-17 các ngày trong tuần
    @Scheduled(cron = "0 */15 * * * ?")         // mỗi 15 phút
    @Scheduled(cron = "0 0 0 1 * ?")            // đầu tháng

    // Fixed delay: N ms sau khi task trước HOÀN THÀNH (tránh overlap)
    @Scheduled(fixedDelay = 5000)               // 5s sau khi task xong

    // Fixed rate: mỗi N ms (tính từ START, có thể overlap nếu task chậm)
    @Scheduled(fixedRate = 10000)               // mỗi 10s

    // Delay lần đầu
    @Scheduled(fixedDelay = 5000, initialDelay = 30000) // bắt đầu sau 30s, rồi mỗi 5s

    // Từ properties (externalized)
    @Scheduled(cron = "${app.tasks.cleanup.cron:0 0 3 * * ?}")
    public void cleanupOldData() {
        log.info("Running cleanup task at {}", LocalDateTime.now());
        dataCleanupService.deleteOlderThan(30, ChronoUnit.DAYS);
    }

    @Scheduled(fixedDelayString = "${app.tasks.metrics.interval:60000}")
    public void collectMetrics() {
        metricsService.collect();
    }
}
```

### Thread Pool cho Scheduling

Mặc định Spring dùng **1 thread** cho tất cả @Scheduled tasks → tasks chạy tuần tự, blocking nhau.

```java
@Configuration
public class SchedulingConfig implements SchedulingConfigurer {

    @Override
    public void configureTasks(ScheduledTaskRegistrar registrar) {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(5);              // 5 threads
        scheduler.setThreadNamePrefix("sched-");
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(30);
        scheduler.initialize();
        registrar.setTaskScheduler(scheduler);
    }
}

// application.yml alternative
spring:
  task:
    scheduling:
      pool:
        size: 5
      thread-name-prefix: sched-
```

### Distributed Scheduling – Tránh chạy trên nhiều nodes

```java
// Vấn đề: 3 instances cùng chạy cleanup job → duplicate work, conflict

// Giải pháp 1: ShedLock (phổ biến nhất)
@Bean
public LockProvider lockProvider(DataSource dataSource) {
    return new JdbcTemplateLockProvider(
        JdbcTemplateLockProvider.Configuration.builder()
            .withJdbcTemplate(new JdbcTemplate(dataSource))
            .usingDbTime()
            .build()
    );
}

@SchedulerLock(name = "cleanup-task", lockAtLeastFor = "PT5M", lockAtMostFor = "PT10M")
@Scheduled(cron = "0 0 3 * * ?")
public void cleanupOldData() {
    // Chỉ 1 instance chạy được tại 1 thời điểm (lock trên DB)
}

// Giải pháp 2: Kubernetes CronJob (scheduled pod – single instance)
// Giải pháp 3: Quartz với JDBC JobStore (cluster-aware)
```

---

## Quartz Scheduler

Phù hợp khi cần: persistent jobs, cluster-aware, dynamic job creation/cancellation, complex scheduling.

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-quartz</artifactId>
</dependency>
```

```yaml
spring:
  quartz:
    job-store-type: jdbc          # JDBC = cluster-aware, persistent
    jdbc:
      initialize-schema: always  # tạo Quartz tables
    properties:
      org.quartz.scheduler.instanceId: AUTO
      org.quartz.jobStore.isClustered: true
      org.quartz.jobStore.clusterCheckinInterval: 10000
      org.quartz.threadPool.threadCount: 10
```

```java
// Job Definition
@Component
@PersistJobDataAfterExecution  // Lưu JobDataMap sau mỗi lần chạy
@DisallowConcurrentExecution   // Không chạy 2 instances cùng lúc
public class ReportGenerationJob implements Job {

    @Autowired  // Quartz hỗ trợ Spring injection qua AutowireCapableBeanFactory
    private ReportService reportService;

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

// Schedule jobs programmatically
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
            .withIdentity("report-trigger-" + tenantId, "reports")
            .withSchedule(CronScheduleBuilder.cronSchedule("0 0 0 1 * ?")) // first of month
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

    public void pauseJob(String jobName, String group) throws SchedulerException {
        scheduler.pauseJob(new JobKey(jobName, group));
    }
}
```

---

## Spring Batch – Xử lý khối dữ liệu lớn

Spring Batch dùng kiến trúc **chunk-oriented processing** tối ưu cho ETL, data migration, report generation.

### Core Concepts

```
Job → N Steps → (optional Step flow: sequential / parallel / conditional)
Step → ItemReader → ItemProcessor → ItemWriter (chunk-based)
     hoặc Tasklet (single operation)

Chunk: read N items → process N items → write N items → commit → repeat
```

### Setup

```java
@SpringBootApplication
@EnableBatchProcessing  // Spring Boot 3: thường không cần, auto-configure
public class App {}
```

```yaml
spring:
  batch:
    job:
      enabled: false      # Không auto-run khi start (kiểm soát manual)
    jdbc:
      initialize-schema: always  # Tạo Spring Batch metadata tables
```

### Ví dụ: Import CSV → Database

```java
@Configuration
@RequiredArgsConstructor
public class UserImportBatchConfig {

    private final JobRepository jobRepository;
    private final PlatformTransactionManager transactionManager;
    private final UserRepository userRepository;

    // ===== READER =====
    @Bean
    @StepScope
    public FlatFileItemReader<UserCsvRecord> userCsvReader(
            @Value("#{jobParameters['filePath']}") String filePath) {

        return new FlatFileItemReaderBuilder<UserCsvRecord>()
            .name("userCsvReader")
            .resource(new FileSystemResource(filePath))
            .linesToSkip(1)  // skip header
            .delimited()
                .delimiter(",")
                .names("name", "email", "role", "tenantId")
            .targetType(UserCsvRecord.class)
            .build();
    }

    // ===== PROCESSOR =====
    @Bean
    public ItemProcessor<UserCsvRecord, User> userProcessor() {
        return record -> {
            // Validation + transformation
            if (!isValidEmail(record.getEmail())) {
                log.warn("Skipping invalid email: {}", record.getEmail());
                return null; // null = skip this item
            }

            return User.builder()
                .name(record.getName())
                .email(record.getEmail().toLowerCase())
                .role(Role.of(record.getRole()))
                .tenantId(Long.parseLong(record.getTenantId()))
                .passwordHash(passwordEncoder.encode(generateTempPassword()))
                .build();
        };
    }

    // ===== WRITER =====
    @Bean
    public RepositoryItemWriter<User> userWriter() {
        return new RepositoryItemWriterBuilder<User>()
            .repository(userRepository)
            .methodName("save")
            .build();
    }

    // Alternative: JdbcBatchItemWriter (faster for bulk)
    @Bean
    public JdbcBatchItemWriter<User> jdbcUserWriter(DataSource dataSource) {
        return new JdbcBatchItemWriterBuilder<User>()
            .sql("INSERT INTO users (name, email, role, tenant_id, password_hash) " +
                 "VALUES (:name, :email, :role, :tenantId, :passwordHash) " +
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name")
            .dataSource(dataSource)
            .beanMapped()
            .build();
    }

    // ===== STEP =====
    @Bean
    public Step userImportStep() {
        return new StepBuilder("userImportStep", jobRepository)
            .<UserCsvRecord, User>chunk(500, transactionManager) // commit mỗi 500 records
            .reader(userCsvReader(null))
            .processor(userProcessor())
            .writer(userWriter())
            .faultTolerant()
                .skipLimit(100)  // bỏ qua tối đa 100 lỗi
                .skip(ValidationException.class)
                .retryLimit(3)   // retry 3 lần cho transient errors
                .retry(TransientDataAccessException.class)
            .listener(new ItemReadListener<>() {
                @Override
                public void onReadError(Exception ex) {
                    log.error("Read error: {}", ex.getMessage());
                }
            })
            .build();
    }

    // ===== JOB =====
    @Bean
    public Job userImportJob(Step userImportStep) {
        return new JobBuilder("userImportJob", jobRepository)
            .incrementer(new RunIdIncrementer())
            .listener(new JobExecutionListener() {
                @Override
                public void afterJob(JobExecution jobExecution) {
                    StepExecution step = jobExecution.getStepExecutions().iterator().next();
                    log.info("Import complete: read={}, written={}, skipped={}",
                        step.getReadCount(), step.getWriteCount(), step.getSkipCount());
                }
            })
            .flow(userImportStep)
            .end()
            .build();
    }
}
```

### Trigger Job

```java
@Service
@RequiredArgsConstructor
public class BatchJobService {

    private final JobLauncher jobLauncher;
    private final Job userImportJob;

    public void triggerImport(String filePath) throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("filePath", filePath)
            .addLong("startTime", System.currentTimeMillis()) // unique để re-run
            .toJobParameters();

        JobExecution execution = jobLauncher.run(userImportJob, params);
        log.info("Job {} status: {}", execution.getId(), execution.getStatus());
    }

    // Async launch
    @Autowired
    private AsyncJobLauncher asyncJobLauncher;

    public String triggerImportAsync(String filePath) throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("filePath", filePath)
            .addLong("startTime", System.currentTimeMillis())
            .toJobParameters();

        JobExecution execution = asyncJobLauncher.run(userImportJob, params);
        return execution.getId().toString();
    }
}
```

### Parallel Steps

```java
@Bean
public Job parallelJob(Step step1, Step step2, Step step3) {
    Flow flow1 = new FlowBuilder<Flow>("flow1").start(step1).build();
    Flow flow2 = new FlowBuilder<Flow>("flow2").start(step2).build();

    Flow parallelFlow = new FlowBuilder<Flow>("parallelFlow")
        .split(new SimpleAsyncTaskExecutor())
        .add(flow1, flow2)
        .build();

    return new JobBuilder("parallelJob", jobRepository)
        .start(parallelFlow)
        .next(step3) // sau khi flow1 + flow2 xong
        .end()
        .build();
}
```

---

## Trade-offs

| @Scheduled | Quartz | Spring Batch |
|-----------|--------|-------------|
| Simple, no setup | Persistent, cluster-aware | ETL, large data |
| Single node risk | Complex config | Chunk + retry |
| No persistence | Jobs survive restart | Job metadata |
| Memory-only | DB overhead | DB overhead |
| Best: simple periodic tasks | Best: dynamic, persistent jobs | Best: bulk data processing |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `advanced/async_concurrency.md` – @Async, CompletableFuture, Virtual Threads
- `production/performance_tuning.md` – Batch sizing, parallel step tuning
- **Keywords:** ShedLock, Quartz JobDataMap, Spring Batch JobRepository, Partitioning (parallel chunk), Remote chunking, MultiResourceItemReader, CompositeItemProcessor, ItemStream (stateful reader/writer), Spring Batch Admin, Cron timezone, @EnableScheduling caveats với lazy beans
