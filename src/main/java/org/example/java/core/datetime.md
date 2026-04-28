# Date/Time API (java.time)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – java.time là gì?

**java.time** (Java 8, JSR-310) là Date/Time API hoàn toàn mới, thay thế `java.util.Date` và `java.util.Calendar` vốn rất nhiều vấn đề.

```
Trước Java 8 (Legacy):                After Java 8 (java.time):
  java.util.Date      → mutable!        Instant          → machine time (epoch)
  java.util.Calendar  → mutable!        LocalDate        → date only, no timezone
  java.sql.Date       → confusion!      LocalTime        → time only, no timezone
  SimpleDateFormat    → NOT thread-safe! LocalDateTime   → date + time, no timezone
                                         ZonedDateTime   → date + time + timezone
                                         OffsetDateTime  → date + time + UTC offset
                                         Duration        → time-based amount
                                         Period          → date-based amount
                                         DateTimeFormatter → thread-safe!
```

**Thiết kế nguyên tắc:**
1. **Immutable**: mọi operation tạo object mới
2. **Fluent API**: method chaining rõ ràng
3. **Clear separation**: timezone vs no timezone, date vs time vs datetime
4. **Thread-safe**: DateTimeFormatter, không như SimpleDateFormat

---

## How – Instant (Machine Time)

`Instant` = điểm trên timeline tuyệt đối, tính từ Unix epoch (1970-01-01T00:00:00Z).

```java
// Tạo Instant
Instant now = Instant.now();                        // current moment in UTC
Instant epoch = Instant.EPOCH;                      // 1970-01-01T00:00:00Z
Instant fromEpoch = Instant.ofEpochSecond(1700000000L);
Instant fromMilli  = Instant.ofEpochMilli(System.currentTimeMillis());
Instant parsed = Instant.parse("2024-01-15T10:30:00Z"); // ISO-8601

// Arithmetic
Instant later = now.plusSeconds(3600);               // + 1 hour
Instant earlier = now.minus(Duration.ofHours(2));

// Compare
boolean isBefore = now.isBefore(later);
boolean isAfter  = now.isAfter(earlier);
long diffMs = ChronoUnit.MILLIS.between(earlier, now);

// Conversion
long epochSecond = now.getEpochSecond();
long epochMilli  = now.toEpochMilli();

// Dùng khi nào: timestamps trong log, event sourcing, API responses
// Lưu trong DB: TIMESTAMPTZ (PostgreSQL), BIGINT epoch millis
System.out.println(now); // "2024-01-15T10:30:00.123456789Z" (UTC)
```

---

## How – LocalDate (Date Only)

`LocalDate` = ngày không có time, không có timezone. Dùng cho: sinh nhật, ngày đặt hàng, ngày lễ.

```java
// Tạo LocalDate
LocalDate today = LocalDate.now();
LocalDate date  = LocalDate.of(2024, 1, 15);
LocalDate date2 = LocalDate.of(2024, Month.JANUARY, 15); // dùng enum
LocalDate parsed = LocalDate.parse("2024-01-15");        // ISO format (default)

// Components
int year   = date.getYear();     // 2024
int month  = date.getMonthValue(); // 1
Month m    = date.getMonth();    // JANUARY
int day    = date.getDayOfMonth(); // 15
DayOfWeek dow = date.getDayOfWeek(); // MONDAY
int dayOfYear = date.getDayOfYear(); // 15
boolean isLeap = date.isLeapYear(); // false

// Arithmetic (always immutable – tạo mới)
LocalDate nextWeek   = date.plusWeeks(1);
LocalDate lastMonth  = date.minusMonths(1);
LocalDate nextYear   = date.plus(1, ChronoUnit.YEARS);
LocalDate firstOfMonth = date.withDayOfMonth(1);
LocalDate lastOfMonth  = date.with(TemporalAdjusters.lastDayOfMonth());

// Useful TemporalAdjusters
LocalDate nextMonday = date.with(TemporalAdjusters.next(DayOfWeek.MONDAY));
LocalDate firstMonday = date.with(TemporalAdjusters.firstInMonth(DayOfWeek.MONDAY));

// Compare
boolean isBefore = date.isBefore(LocalDate.of(2025, 1, 1));
boolean isAfter  = date.isAfter(LocalDate.of(2020, 1, 1));
boolean isEqual  = date.isEqual(today);
long daysBetween = ChronoUnit.DAYS.between(date, today);

// Range check (business use case)
boolean isInRange = !date.isBefore(startDate) && !date.isAfter(endDate);

// Date range iteration
startDate.datesUntil(endDate)              // Stream<LocalDate> (Java 9+)
    .filter(d -> d.getDayOfWeek() != DayOfWeek.SATURDAY
              && d.getDayOfWeek() != DayOfWeek.SUNDAY)
    .forEach(workingDay -> process(workingDay));
```

---

## How – LocalTime (Time Only)

```java
// Tạo LocalTime
LocalTime now    = LocalTime.now();
LocalTime time   = LocalTime.of(14, 30, 45);          // 14:30:45
LocalTime time2  = LocalTime.of(14, 30, 45, 123456789); // with nanoseconds
LocalTime parsed = LocalTime.parse("14:30:45");

// Special values
LocalTime midnight = LocalTime.MIDNIGHT; // 00:00:00
LocalTime noon     = LocalTime.NOON;     // 12:00:00

// Components
int hour   = time.getHour();          // 14
int minute = time.getMinute();        // 30
int second = time.getSecond();        // 45
int nano   = time.getNano();          // 0

// Arithmetic
LocalTime later   = time.plusHours(2);    // 16:30:45
LocalTime earlier = time.minusMinutes(15); // 14:15:45

// Compare
boolean isBefore = time.isBefore(LocalTime.of(15, 0));
long minutesBetween = ChronoUnit.MINUTES.between(time, later);

// Business hours check
boolean isBusinessHours = !time.isBefore(LocalTime.of(9, 0))
                       && time.isBefore(LocalTime.of(17, 0));
```

---

## How – LocalDateTime

```java
// Tạo LocalDateTime
LocalDateTime now  = LocalDateTime.now();
LocalDateTime dt   = LocalDateTime.of(2024, 1, 15, 14, 30, 45);
LocalDateTime dt2  = LocalDateTime.of(LocalDate.of(2024, 1, 15), LocalTime.of(14, 30));
LocalDateTime parsed = LocalDateTime.parse("2024-01-15T14:30:45");

// Decompose
LocalDate date = dt.toLocalDate();
LocalTime time = dt.toLocalTime();

// Arithmetic
LocalDateTime nextHour = dt.plusHours(1);
LocalDateTime yesterday = dt.minusDays(1);

// QUAN TRỌNG: LocalDateTime KHÔNG có timezone!
// Dùng cho: meeting schedules (local time), recurring events, UI display
// KHÔNG dùng cho: timestamps, cross-timezone operations

// Convert sang ZonedDateTime khi cần timezone
ZonedDateTime zdt = dt.atZone(ZoneId.of("Asia/Ho_Chi_Minh"));
```

---

## How – ZonedDateTime và OffsetDateTime

```java
// ZonedDateTime = LocalDateTime + ZoneId (timezone rules: DST, historical changes)
ZoneId vn = ZoneId.of("Asia/Ho_Chi_Minh"); // +07:00
ZoneId us = ZoneId.of("America/New_York");  // -05:00 (EST) / -04:00 (EDT)

ZonedDateTime vnNow = ZonedDateTime.now(vn);
ZonedDateTime usNow = ZonedDateTime.now(us);

// Same instant, different representation
Instant instant = Instant.now();
ZonedDateTime inVN = instant.atZone(vn); // hiển thị theo giờ VN
ZonedDateTime inUS = instant.atZone(us); // hiển thị theo giờ NY

// Convert timezone
ZonedDateTime converted = vnNow.withZoneSameInstant(us); // same moment, NY timezone

// DST pitfall: ngày chuyển giờ
ZonedDateTime beforeDST = ZonedDateTime.of(2024, 3, 10, 1, 30, 0, 0, us);
ZonedDateTime afterAdd  = beforeDST.plusHours(1);
// 1:30 + 1h → 3:30 AM (2:30 không tồn tại vì DST gap)
// ZonedDateTime xử lý đúng!

// OffsetDateTime = LocalDateTime + fixed UTC offset (không có DST rules)
// Dùng cho: API contracts, serialization (unambiguous)
OffsetDateTime odt = OffsetDateTime.now();
System.out.println(odt); // "2024-01-15T14:30:45.123+07:00"

OffsetDateTime fromInstant = instant.atOffset(ZoneOffset.ofHours(7));
Instant back = odt.toInstant();

// ZoneId.getAvailableZoneIds() → tất cả timezone names
// Luôn dùng tên (Asia/Ho_Chi_Minh) thay vì offset (+07:00) vì offset có thể thay đổi
```

---

## How – Duration & Period

```java
// Duration = time-based amount (seconds, nanoseconds)
Duration oneHour     = Duration.ofHours(1);
Duration thirtyMin   = Duration.ofMinutes(30);
Duration twoAndHalf  = Duration.parse("PT2H30M");   // ISO-8601
Duration between     = Duration.between(time1, time2);

// Duration arithmetic
Duration doubled = oneHour.multipliedBy(2);          // PT2H
Duration half    = oneHour.dividedBy(2);             // PT30M
Duration total   = oneHour.plus(thirtyMin);          // PT1H30M
boolean neg = oneHour.isNegative();

// Extract components
long hours   = oneHour.toHours();         // 1
long minutes = oneHour.toMinutesPart();   // 0 (minutes part, not total)
long seconds = oneHour.toSecondsPart();   // 0

// Period = date-based amount (years, months, days)
Period twoYears  = Period.ofYears(2);
Period sixMonths = Period.ofMonths(6);
Period tenDays   = Period.ofDays(10);
Period complex   = Period.of(1, 6, 15);  // 1 year, 6 months, 15 days
Period between2  = Period.between(date1, date2);

// Period arithmetic (calendar-aware)
LocalDate birthday = LocalDate.of(1990, 5, 15);
LocalDate today    = LocalDate.of(2024, 1, 15);
Period age = Period.between(birthday, today);
System.out.printf("Age: %d years, %d months, %d days%n",
    age.getYears(), age.getMonths(), age.getDays()); // 33 years, 8 months, 0 days

// Period + LocalDate: accounts for different month lengths
LocalDate lastOfJan = LocalDate.of(2024, 1, 31);
LocalDate plusOneMonth = lastOfJan.plus(Period.ofMonths(1));
System.out.println(plusOneMonth); // 2024-02-29 (adjusted for Feb)
```

---

## How – DateTimeFormatter

**Thread-safe** (không như SimpleDateFormat):

```java
// Predefined formatters
String iso  = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE); // "2024-01-15"
String iso2 = LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);

// Custom patterns
DateTimeFormatter f1 = DateTimeFormatter.ofPattern("dd/MM/yyyy");
DateTimeFormatter f2 = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm:ss");
DateTimeFormatter f3 = DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy", Locale.ENGLISH);

String formatted = LocalDate.of(2024, 1, 15).format(f1); // "15/01/2024"
String verbose   = LocalDate.of(2024, 1, 15).format(f3); // "Monday, January 15, 2024"

// Parse
LocalDate parsed  = LocalDate.parse("15/01/2024", f1);
LocalDateTime dt  = LocalDateTime.parse("15/01/2024 14:30:00", f2);

// Formatter với timezone
DateTimeFormatter withZone = DateTimeFormatter
    .ofPattern("yyyy-MM-dd HH:mm:ss z")
    .withZone(ZoneId.of("Asia/Ho_Chi_Minh"));
String result = withZone.format(Instant.now()); // "2024-01-15 14:30:00 ICT"

// Pattern cheat sheet:
// y=year, M=month, d=day, H=hour(0-23), h=hour(1-12), m=minute, s=second
// E=day-of-week (Mon), EEEE=full (Monday)
// MMM=Jan, MMMM=January
// a=AM/PM
// z=timezone name (ICT), Z=offset (+0700), X=offset (Z for UTC)
// S=fraction of second (S=tenth, SS=hundredth, SSS=millisecond, SSSSSS=microsecond)

// FormatStyle (locale-aware)
DateTimeFormatter localized = DateTimeFormatter
    .ofLocalizedDate(FormatStyle.LONG)
    .withLocale(Locale.of("vi", "VN"));
System.out.println(LocalDate.now().format(localized)); // "15 tháng 1, 2024"
```

---

## How – ChronoUnit & TemporalAdjusters

```java
// ChronoUnit: mọi unit đo lường time
long days   = ChronoUnit.DAYS.between(date1, date2);
long hours  = ChronoUnit.HOURS.between(dt1, dt2);
long months = ChronoUnit.MONTHS.between(date1, date2);
long weeks  = ChronoUnit.WEEKS.between(date1, date2);

// Supported: NANOS, MICROS, MILLIS, SECONDS, MINUTES, HOURS,
//            HALF_DAYS, DAYS, WEEKS, MONTHS, YEARS, DECADES, CENTURIES, MILLENNIA

// TemporalAdjusters: complex date arithmetic
LocalDate date = LocalDate.of(2024, 1, 15);

// Day adjusters
LocalDate next = date.with(TemporalAdjusters.next(DayOfWeek.FRIDAY));
LocalDate prev = date.with(TemporalAdjusters.previous(DayOfWeek.MONDAY));
LocalDate nextOrSame = date.with(TemporalAdjusters.nextOrSame(DayOfWeek.MONDAY));

// Month adjusters
LocalDate first   = date.with(TemporalAdjusters.firstDayOfMonth()); // 2024-01-01
LocalDate last    = date.with(TemporalAdjusters.lastDayOfMonth());  // 2024-01-31
LocalDate firstQ  = date.with(TemporalAdjusters.firstDayOfNextMonth()); // 2024-02-01
LocalDate firstY  = date.with(TemporalAdjusters.firstDayOfYear());

// Nth occurrence
LocalDate thirdMonday = date.with(TemporalAdjusters.dayOfWeekInMonth(3, DayOfWeek.MONDAY));

// Custom adjuster
TemporalAdjuster skipWeekend = temporal -> {
    DayOfWeek dow = DayOfWeek.from(temporal);
    if (dow == DayOfWeek.SATURDAY) return temporal.plus(2, ChronoUnit.DAYS);
    if (dow == DayOfWeek.SUNDAY)   return temporal.plus(1, ChronoUnit.DAYS);
    return temporal;
};
LocalDate nextWorkDay = LocalDate.now().with(skipWeekend);
```

---

## How – Clock (Testability)

```java
// Clock: source of Instant, injectable → testable!
public class OrderService {
    private final Clock clock;

    public OrderService(Clock clock) { this.clock = clock; }

    public Order createOrder(OrderRequest req) {
        Instant now = Instant.now(clock); // sử dụng clock
        return new Order(req, now);
    }
}

// Production: Clock.systemUTC()
OrderService service = new OrderService(Clock.systemUTC());

// Test: Clock.fixed() → deterministic
Instant fixedTime = Instant.parse("2024-01-15T10:00:00Z");
Clock testClock = Clock.fixed(fixedTime, ZoneOffset.UTC);
OrderService testService = new OrderService(testClock);
Order order = testService.createOrder(req);
assertEquals(fixedTime, order.getCreatedAt()); // always passes!

// Clock.offset: simulate future/past
Clock futureByOneHour = Clock.offset(Clock.systemUTC(), Duration.ofHours(1));
```

---

## How – Migration từ Legacy Date/Calendar

```java
// java.util.Date ↔ Instant
Date legacyDate = new Date();
Instant instant = legacyDate.toInstant();
Date back = Date.from(instant);

// java.util.Date ↔ LocalDateTime
LocalDateTime ldt = legacyDate.toInstant()
    .atZone(ZoneId.systemDefault())
    .toLocalDateTime();
Date backFromLdt = Date.from(ldt.atZone(ZoneId.systemDefault()).toInstant());

// java.util.Date ↔ LocalDate
LocalDate ld = legacyDate.toInstant()
    .atZone(ZoneId.systemDefault())
    .toLocalDate();

// java.util.Calendar ↔ ZonedDateTime
Calendar cal = Calendar.getInstance();
ZonedDateTime zdt = cal.toInstant().atZone(cal.getTimeZone().toZoneId());
Calendar backCal = GregorianCalendar.from(zdt);

// java.sql.Date ↔ LocalDate
java.sql.Date sqlDate = java.sql.Date.valueOf(LocalDate.now());
LocalDate fromSql = sqlDate.toLocalDate();

// java.sql.Timestamp ↔ LocalDateTime
java.sql.Timestamp ts = java.sql.Timestamp.valueOf(LocalDateTime.now());
LocalDateTime fromTs = ts.toLocalDateTime();

// Hibernate/JPA tự động map với Java 8+ (không cần converter):
@Column(name = "created_at")
private Instant createdAt;      // → TIMESTAMPTZ

@Column(name = "event_date")
private LocalDate eventDate;    // → DATE

@Column(name = "scheduled_at")
private LocalDateTime scheduledAt; // → TIMESTAMP (no timezone!)
```

---

## Components – Type Selection Guide

| Type | Timezone | Use case |
|------|---------|----------|
| `Instant` | UTC (absolute) | Timestamps, logging, DB storage |
| `LocalDate` | None | Birthdays, deadlines, calendar dates |
| `LocalTime` | None | Business hours, recurring daily times |
| `LocalDateTime` | None | Calendar events (user's local time) |
| `ZonedDateTime` | Full rules (DST) | Cross-timezone scheduling |
| `OffsetDateTime` | Fixed offset | API interchange, serialization |
| `Duration` | N/A | Elapsed time, timeouts |
| `Period` | N/A | Age, subscription length (calendar-aware) |

---

## Why – Tại sao java.util.Date/Calendar tệ?

```java
// java.util.Date: mutable → thread-unsafe, kluge API
Date d = new Date();
d.setTime(d.getTime() + 3600000); // cộng 1 giờ? Cực kỳ không rõ ràng

// getYear() trả về năm - 1900! getMonth() bắt đầu từ 0!
Date date = new Date(124, 0, 15); // 2024-01-15 (không ai nhớ nổi)

// Calendar: mutable, verbose
Calendar cal = Calendar.getInstance();
cal.set(Calendar.YEAR, 2024);
cal.set(Calendar.MONTH, 0); // January = 0, vì sao???
cal.set(Calendar.DAY_OF_MONTH, 15);
cal.add(Calendar.DAY_OF_MONTH, 30); // 30 ngày sau

// SimpleDateFormat: NOT THREAD-SAFE!
private static final SimpleDateFormat SDF = new SimpleDateFormat("yyyy-MM-dd");
// Hai threads gọi SDF.format() cùng lúc → corrupt output!
// Fix: ThreadLocal<SimpleDateFormat> hoặc... dùng java.time!
```

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Immutable → thread-safe | Verbosity khi convert với legacy code |
| Clear separation (date/time/zone) | Learning curve từ legacy |
| Fluent API, readable | Thêm nhiều types phải nhớ |
| DateTimeFormatter thread-safe | jackson-datatype-jsr310 cần thêm vào |
| Clock → testable | |

---

## Real-world Usage (Production)

### 1. Cấu hình Jackson serialize/deserialize java.time

```java
// build.gradle / pom.xml
// com.fasterxml.jackson.datatype:jackson-datatype-jsr310

@Configuration
public class JacksonConfig {
    @Bean
    public ObjectMapper objectMapper() {
        return new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .configure(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS, false);
            // → serialize Instant/LocalDate thành ISO-8601 strings, không phải số
    }
}

// application.yml (Spring Boot)
spring:
  jackson:
    serialization:
      write-dates-as-timestamps: false
    deserialization:
      adjust-dates-to-context-time-zone: false

// Kết quả:
// Instant   → "2024-01-15T07:30:00.000Z"
// LocalDate → "2024-01-15"
// LocalDateTime → "2024-01-15T14:30:00"
```

### 2. Tính business days (ngày làm việc)

```java
public class BusinessCalendar {
    private final Set<LocalDate> holidays;

    public long countBusinessDays(LocalDate start, LocalDate end) {
        return start.datesUntil(end)
            .filter(this::isBusinessDay)
            .count();
    }

    public LocalDate addBusinessDays(LocalDate from, int days) {
        LocalDate date = from;
        int count = 0;
        while (count < days) {
            date = date.plusDays(1);
            if (isBusinessDay(date)) count++;
        }
        return date;
    }

    public boolean isBusinessDay(LocalDate date) {
        return date.getDayOfWeek() != DayOfWeek.SATURDAY
            && date.getDayOfWeek() != DayOfWeek.SUNDAY
            && !holidays.contains(date);
    }
}
```

### 3. Scheduling: Next Occurrence

```java
// Tính thời điểm chạy tiếp theo của daily job
public Instant nextRunAt(LocalTime scheduledTime, ZoneId zone) {
    ZonedDateTime now = ZonedDateTime.now(zone);
    ZonedDateTime todayAt = now.toLocalDate().atTime(scheduledTime).atZone(zone);

    // Nếu giờ đó hôm nay đã qua → lấy ngày mai
    if (!now.isBefore(todayAt)) {
        todayAt = todayAt.plusDays(1);
    }

    return todayAt.toInstant();
}

// DST-safe: ZonedDateTime.plusDays(1) cộng theo lịch
// không phải cộng 24*3600 giây (sai khi DST)
```

### 4. Audit Log với Instant

```java
@Entity
public abstract class AuditableEntity {
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void onCreate() {
        createdAt = updatedAt = Instant.now();
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }
}

// API response: serialize Instant → ISO-8601 UTC
// "createdAt": "2024-01-15T07:30:00.000Z"
// Frontend display: convert to user's local timezone in browser
// → "01/15/2024 2:30 PM" (in Ho Chi Minh City)
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **String – Deep Dive**
>
> Keyword: String Pool (intern, compile-time constants), String immutability (why), `+` operator compile to StringBuilder (không phải trong loop!), StringBuilder vs StringBuffer, String methods (split/join/strip/repeat/formatted – Java 12+), text blocks (Java 15+), regex (Pattern/Matcher, groups, lookahead/lookbehind), String.format vs MessageFormat vs formatted(), Charset/encoding pitfalls
