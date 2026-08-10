---
title: "Java Module System (JPMS) – Java 9+"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Java Module System (JPMS) – Java 9+

> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

## Mục lục
1. [What & Why – Module System](#1-what--why--module-system)
2. [module-info.java – Cú pháp](#2-module-infojava--cú-pháp)
3. [Module Types](#3-module-types)
4. [Services – Loose Coupling](#4-services--loose-coupling)
5. [Migration từ Classpath](#5-migration-từ-classpath)
6. [jlink – Custom JRE](#6-jlink--custom-jre)
7. [Trade-offs & Khi nào dùng](#7-trade-offs--khi-nào-dùng)

---

## 1. What & Why – Module System

### 1.1 Vấn đề trước Java 9

> 💡 **Giải thích dễ hiểu — "Module" là gì và vì sao cần nó?**
> **Module** *(mô-đun — một khối code có tên, đóng gói kèm khai báo rõ nó cần gì và cho ai dùng gì)* nâng cấp cách Java tổ chức code. Trước đây mọi thư viện bị ném chung vào **classpath** *(đường dẫn chứa tất cả class — như một cái sọt to)*, ai cũng với tay vào lấy được mọi thứ, kể cả đồ nội bộ không nên đụng.
> Ví von: hãy hình dung một **tòa chung cư**. Trước Java 9, tòa nhà không có tường ngăn phòng — ai cũng đi lại khắp nơi, lấy đồ của bất kỳ ai (kể cả phòng kỹ thuật, phòng điện). Module system dựng lại **tường và cửa có khóa**: mỗi căn hộ (module) tự quyết định **cửa nào mở ra ngoài** (`exports`) và **mình cần dùng dịch vụ của căn hộ nào** (`requires`). Đồ đạc bên trong không mở cửa thì người ngoài không đụng được → an toàn, rõ ràng hơn.

```
Classpath Hell (trước Java 9):
  - JAR hell: nhiều phiên bản cùng class trên classpath → ClassCastException
  - No encapsulation at package level: bất kỳ ai cũng dùng được internal APIs
    (e.g., sun.misc.Unsafe, com.sun.* packages)
  - Monolithic JDK: phải ship toàn bộ JDK dù app chỉ dùng 10%
  - Startup time: load toàn bộ classpath
  - No explicit dependencies: không biết module A cần module B

JPMS giải quyết:
  ✅ Strong encapsulation: chỉ export packages explicitly
  ✅ Reliable configuration: khai báo dependencies, lỗi lúc startup (không phải runtime)
  ✅ Scalable platform: jlink tạo custom JRE chỉ với modules cần thiết
  ✅ Improved security: internal APIs không thể access từ outside
```

### 1.2 Cấu trúc Module

```
Module = named unit containing packages + resources + module-info.class

my-app/
├── src/
│   └── com.example.myapp/           ← module directory (= module name)
│       ├── module-info.java         ← module descriptor
│       └── com/example/myapp/
│           ├── Main.java
│           ├── service/
│           │   ├── OrderService.java  ← exported
│           │   └── OrderRepository.java  ← exported
│           └── internal/
│               └── OrderCache.java    ← NOT exported (hidden)
└── pom.xml / build.gradle
```

---

## 2. module-info.java – Cú pháp

### 2.1 Directives

```java
// src/module-info.java
module com.example.orderservice {

    // ── requires: declare dependencies ───────────────────────────────────
    requires java.base;          // implicit (always required)
    requires java.sql;           // JDK module
    requires java.logging;
    requires java.net.http;      // HttpClient (Java 11)
    requires com.fasterxml.jackson.databind;  // third-party
    requires com.example.common; // internal module

    // requires transitive: re-export dependency (consumers see it too)
    requires transitive com.example.model;  // anyone requiring us also gets model

    // requires static: compile-time only, optional at runtime
    requires static lombok;     // annotation processor, not needed at runtime

    // ── exports: make packages accessible ────────────────────────────────
    exports com.example.orderservice.api;       // accessible to anyone
    exports com.example.orderservice.model;

    // exports ... to: qualified export (only to specific modules)
    exports com.example.orderservice.internal
        to com.example.orderservice.test,       // only test module
           com.example.orderfrontend;

    // ── opens: reflection access (needed for frameworks) ─────────────────
    // Note: exports allows compile-time + runtime API use
    //       opens allows deep reflection (getDeclaredFields, setAccessible)

    opens com.example.orderservice.model
        to com.fasterxml.jackson.databind;  // Jackson needs reflection to serialize

    opens com.example.orderservice.config
        to spring.core, spring.beans;       // Spring DI needs reflection

    // opens without qualifier: open to everyone (legacy migration)
    opens com.example.orderservice.dto;

    // ── uses: declare service interface usage (ServiceLoader) ────────────
    uses com.example.orderservice.spi.PaymentProvider;

    // ── provides ... with: declare service implementation ─────────────────
    provides com.example.orderservice.spi.PaymentProvider
        with com.example.orderservice.payment.StripePaymentProvider,
             com.example.orderservice.payment.VNPayProvider;
}
```

> 💡 **Giải thích dễ hiểu — `exports` khác `opens` ở chỗ nào? (điểm hay nhầm nhất)**
> Hai từ khóa này đều "mở cửa", nhưng mở ở hai mức khác nhau:
> - **`exports`** *(xuất khẩu — cho phép dùng API công khai lúc biên dịch và lúc chạy)*: cho người khác **gọi các method/class public** của package. Như cho khách vào **phòng khách** đã dọn dẹp sẵn: họ dùng được những gì bạn bày ra, đúng phép lịch sự.
> - **`opens`** *(mở toang — cho phép reflection soi cả ruột)*: cho phép **reflection** *(soi sâu — đọc cả field private, gọi `setAccessible`)* thọc vào cả những chỗ private. Như đưa khách **chìa khóa vào tận phòng ngủ, mở cả ngăn kéo**. Framework như Jackson (đọc field để serialize) hay Spring (tiêm dependency vào field private) cần mức này.
> Vì sao tách ra? Vì bạn thường muốn cho dùng API (exports) nhưng **không** muốn ai cũng lục ruột object của mình (opens). Reflection mạnh nhưng nguy hiểm, nên Java bắt khai báo riêng và thường giới hạn `opens ... to <framework cụ thể>`.
>
> **`requires transitive`** *(phụ-thuộc lan-truyền)* cũng đáng nhớ: khi module A `requires transitive` module B, thì bất kỳ ai dùng A sẽ **tự động thấy** B luôn mà không cần khai báo lại. Ví von: bạn mượn cái máy in (A), và A đi kèm sẵn giấy + mực (B) — người mượn máy in của bạn dùng luôn được giấy mực, khỏi phải đi xin riêng.

### 2.2 Module Directives Summary

```
requires <module>              depend on module, module not visible to our consumers
requires transitive <module>   depend on module, also re-export to our consumers
requires static <module>       compile-time dependency only (annotation processors)
exports <package>              allow any module to use our package
exports <package> to <module>  restrict use to specific module(s)
opens <package>                allow deep reflection from any module
opens <package> to <module>    allow deep reflection from specific module(s)
uses <interface>               declare we use this service (ServiceLoader)
provides <interface> with <class>  declare our implementation of service
```

---

## 3. Module Types

> 💡 **Giải thích dễ hiểu — 3 "hạng công dân" của module:**
> Khi chuyển code cũ sang thế giới module, không phải mọi JAR đều có "giấy tờ" (`module-info.java`). Java phân 3 loại như 3 tình trạng cư trú:
> - **Named Module** *(module có tên chính thức)*: có đầy đủ `module-info.java` — công dân chính thức, khai báo rõ cần gì/cho gì, được đóng gói kín (encapsulated).
> - **Automatic Module** *(module tự-động)*: một JAR cũ chưa có giấy tờ nhưng được đặt lên `--module-path` → Java **tạm cấp cho một cái tên** (suy từ tên file hoặc manifest). Như **thẻ tạm trú**: được coi là module, nhưng "mở toang mọi cửa" (export hết) vì chưa ai khai báo giới hạn.
> - **Unnamed Module** *(module vô danh)*: JAR cũ nằm trên **classpath** truyền thống — như **người chưa đăng ký hộ khẩu**, gom chung một rọ, thấy được mọi module có tên nhưng module có tên thì (cố ý) không được phép `requires` nó.
> Đây chính là 3 chặng của **con đường di cư dần dần** (migration path) ghi ở cuối đoạn: bắt đầu ở classpath → dời lên module-path → cuối cùng cấp "giấy tờ" đầy đủ.

```java
// ── 1. Named Module: has module-info.java ─────────────────────────────────
// Strongly encapsulated, explicit dependencies
// Created when you add module-info.java

// ── 2. Unnamed Module: JARs on classpath (no module-info) ────────────────
// Old JARs, legacy code
// Can access all other unnamed modules
// Named modules CANNOT require unnamed modules (by design)
// But unnamed module can read all named modules

// ── 3. Automatic Module: named module from JAR without module-info ────────
// JAR placed on --module-path (not classpath)
// Module name derived from JAR filename: jackson-databind-2.15.0.jar → jackson.databind
//   or from Manifest: Automatic-Module-Name: com.fasterxml.jackson.databind
// exports ALL its packages (no encapsulation)
// requires ALL other modules

// ── Migration path ────────────────────────────────────────────────────────
// Step 1: Keep old JARs on classpath (unnamed modules)
// Step 2: Move to --module-path (automatic modules)
// Step 3: Add module-info.java (named modules)
```

---

## 4. Services – Loose Coupling

> 💡 **Giải thích dễ hiểu — Service/`ServiceLoader` (SPI) là gì?**
> **SPI (Service Provider Interface)** *(giao diện nhà-cung-cấp-dịch-vụ)* + **`ServiceLoader`** *(bộ nạp dịch vụ lúc chạy)* cho phép module tiêu dùng chỉ cần biết **một interface** (ví dụ `PaymentProvider`), còn ai cài đặt cụ thể thì tính sau — thậm chí thêm bớt mà **không đụng vào code người tiêu dùng**.
> Ví von: như **ổ cắm điện tiêu chuẩn** trên tường. Bức tường (consumer) chỉ định nghĩa "hình dạng ổ cắm" (interface). Bạn muốn cắm quạt, sạc điện thoại hay đèn (Stripe, VNPay...) đều được, miễn phích cắm đúng chuẩn. Muốn đổi thiết bị chỉ việc rút cái này cắm cái kia (`provides ... with`), tường không cần sửa gì. `ServiceLoader` chính là người đi **rà xem hiện có những thiết bị nào đang cắm vào** để đưa ra danh sách dùng.

```java
// Provider interface (in com.example.payment module):
module com.example.payment {
    exports com.example.payment.spi;  // export the SPI
}

// SPI interface:
package com.example.payment.spi;
public interface PaymentProvider {
    String name();
    PaymentResult charge(long amount, String currency, PaymentDetails details);
}

// ── Stripe implementation (separate module) ───────────────────────────────
module com.example.payment.stripe {
    requires com.example.payment;
    requires stripe.java;
    provides com.example.payment.spi.PaymentProvider
        with com.example.payment.stripe.StripePaymentProvider;
    // Does NOT export implementation package! (encapsulated)
}

// ── Consumer module ───────────────────────────────────────────────────────
module com.example.orderservice {
    requires com.example.payment;
    uses com.example.payment.spi.PaymentProvider;  // declares usage
}

// ── Runtime discovery with ServiceLoader ─────────────────────────────────
public class PaymentService {
    private final List<PaymentProvider> providers;

    public PaymentService() {
        this.providers = ServiceLoader.load(PaymentProvider.class)
            .stream()
            .map(ServiceLoader.Provider::get)
            .toList();
    }

    public PaymentResult charge(String providerName, long amount, ...) {
        return providers.stream()
            .filter(p -> p.name().equals(providerName))
            .findFirst()
            .orElseThrow(() -> new UnsupportedProviderException(providerName))
            .charge(amount, currency, details);
    }
}

// Deploy different implementations without changing consumer:
// java --module-path mods/payment:mods/payment.stripe:mods/orderservice
//      -m com.example.orderservice/com.example.orderservice.Main
```

---

## 5. Migration từ Classpath

### 5.1 Bottom-up Migration Strategy

```
Step 1: Run on classpath first (unnamed module)
  java -cp app.jar:lib/* com.example.Main

Step 2: Identify dependencies
  jdeps --list-deps app.jar
  jdeps --check com.example.app --module-path lib/ app.jar

Step 3: Add module-info.java to your code (others stay on classpath as unnamed)
  module com.example.app {
      requires java.sql;
      requires java.logging;
      // Third-party still on classpath (unnamed module, accessible implicitly)
  }

Step 4: Move third-party JARs to module-path (automatic modules)
  java --module-path lib/ --class-path app.jar com.example.Main

Step 5: Full migration — all modules named
```

### 5.2 Common Issues & Fixes

```java
// ── Issue 1: InaccessibleObjectException (reflection) ────────────────────
// java.lang.reflect.InaccessibleObjectException:
//   Unable to make field private java.lang.String accessible:
//   module java.base does not "opens java.lang" to com.example.app

// Fix: opens directive in module-info:
opens com.example.mypackage to com.fasterxml.jackson.databind;

// Or at command line (for gradual migration):
// --add-opens java.base/java.lang=com.example.app

// ── Issue 2: Cannot access class in unnamed module ────────────────────────
// Named modules cannot require unnamed modules
// Fix: use automatic modules or keep both on classpath

// ── Issue 3: Split packages ───────────────────────────────────────────────
// Same package in two modules → NOT allowed in module system
// Fix: consolidate packages or use multi-release JARs

// ── Issue 4: reflection on internal JDK classes ───────────────────────────
// sun.misc.Unsafe, com.sun.*, jdk.internal.*
// Fix: use public APIs, or add JVM arg:
// --add-opens jdk.internal.misc/jdk.internal.misc=ALL-UNNAMED

// ── Issue 5: Spring Framework with modules ────────────────────────────────
// Spring needs opens for dependency injection (reflection on private fields)
module com.example.app {
    requires spring.context;
    requires spring.beans;
    requires spring.web;
    opens com.example.app.controller to spring.web;
    opens com.example.app.service    to spring.beans, spring.context;
    opens com.example.app.config     to spring.context;
}
```

### 5.3 Maven / Gradle Setup

```xml
<!-- Maven: add module-info.java to src/main/java -->
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-compiler-plugin</artifactId>
  <configuration>
    <release>21</release>
    <!-- Maven handles module-info.java automatically -->
  </configuration>
</plugin>

<!-- Test module access (surefire): -->
<plugin>
  <artifactId>maven-surefire-plugin</artifactId>
  <configuration>
    <argLine>
      --add-opens com.example.app/com.example.app.service=ALL-UNNAMED
    </argLine>
  </configuration>
</plugin>
```

```kotlin
// build.gradle.kts
tasks.withType<JavaCompile> {
    options.jvmArgs = listOf(
        "--add-opens=java.base/java.lang=ALL-UNNAMED"  // for testing
    )
}
```

---

## 6. jlink – Custom JRE

> 💡 **Giải thích dễ hiểu — `jlink` đóng gói JRE "may đo":**
> **`jlink`** *(công cụ ghép link tạo JRE riêng)* tạo ra một **custom JRE** *(bộ chạy Java thu gọn, chỉ chứa đúng module app cần)*. JDK đầy đủ ~300MB vì mang theo mọi thư viện phòng khi cần; nhưng app của bạn thường chỉ dùng vài module.
> Ví von: như **may một bộ vest vừa in người** thay vì mua bộ đồ đại trà rộng thùng thình. `jlink` đo xem app dùng đúng những module nào (nhờ `jdeps`) rồi cắt may một JRE chỉ gồm bấy nhiêu → còn ~50-80MB, khởi động nhanh hơn, image Docker nhẹ hơn. Điều kiện: mọi dependency phải "đã module hóa" thì thợ mới đo được.

```bash
# Create minimal JRE containing only modules your app needs:

# Step 1: Find required modules
jdeps --print-module-deps --ignore-missing-deps app.jar
# Output: java.base,java.sql,java.logging

# Step 2: Build custom JRE
jlink \
  --module-path $JAVA_HOME/jmods:mods/ \
  --add-modules com.example.app,java.sql,java.logging \
  --output custom-jre/ \
  --compress 2 \                    # compression level 0-2
  --no-header-files \               # remove header files
  --no-man-pages \                  # remove man pages
  --strip-debug                     # remove debug info

# Step 3: Run with custom JRE
custom-jre/bin/java -m com.example.app/com.example.Main

# Size comparison:
# Full JDK:    ~300MB
# Custom JRE:  ~50-80MB (for typical app)

# Dockerfile with jlink:
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app
COPY . .
RUN mvn package -DskipTests
RUN jlink --module-path $JAVA_HOME/jmods:target/mods \
    --add-modules $(jdeps --print-module-deps target/app.jar) \
    --output /custom-jre

FROM debian:slim
COPY --from=builder /custom-jre /jre
COPY --from=builder /app/target/app.jar /app.jar
ENTRYPOINT ["/jre/bin/java", "-m", "com.example.app/com.example.Main"]
# Result: ~150MB total Docker image vs ~400MB with full JDK
```

---

## 7. Trade-offs & Khi nào dùng

### 7.1 Trade-offs

| Aspect | Pros | Cons |
|--------|------|------|
| Strong encapsulation | Internal APIs hidden, better API design | More boilerplate (opens, exports) |
| Reliable config | Fail-fast at startup | Complex migration from classpath |
| jlink | Smaller deployments, faster startup | All dependencies must be modular |
| ServiceLoader | Loose coupling, plugin architecture | No IoC, manual discovery |
| Security | Prevent reflection attacks | Breaks many frameworks/libraries |

### 7.2 Khi nào dùng?

```
✅ Dùng JPMS khi:
   - Library/framework development (expose public API clearly)
   - Plugin architecture (ServiceLoader pattern)
   - Deployment size matters (jlink custom JRE)
   - Long-lived project with strict API boundaries
   - Microservice với custom JRE in Docker

⚠️ Cân nhắc khi:
   - Application code (added complexity may not be worth it)
   - Using Spring Boot (many opens needed, complex setup)
   - Team not familiar with module system

❌ Tránh dùng khi:
   - Legacy project with many old JARs (migration painful)
   - Using many libraries that aren't modular yet
   - Tight deadline

Reality check (2024):
   - Most Spring Boot apps run on classpath (unnamed module)
   - JPMS most useful for library/SDK development
   - Java 21 Virtual Threads more impactful for most apps
   - GraalVM native image also achieves small deployments without modules
```

### 7.3 Useful Commands

```bash
# List JDK modules:
java --list-modules

# Show module info:
java --describe-module java.sql

# Show module dependencies of a JAR:
jdeps --module-deps --ignore-missing-deps my.jar

# Show split packages between two JARs:
jdeps --check module1.jar module2.jar

# Open package at runtime (bypass encapsulation):
java --add-opens java.base/java.lang=ALL-UNNAMED -jar app.jar

# Export package at runtime:
java --add-exports java.base/sun.nio.ch=ALL-UNNAMED -jar app.jar

# Add module from path:
java --module-path mods/ --add-modules com.example.lib -jar app.jar

# Run modular app:
java --module-path mods/ -m com.example.app/com.example.Main
```

---

## Ghi chú – Keywords

- **Keywords**: JPMS (Java Platform Module System), module-info.java, requires transitive, qualified exports, opens for reflection, ServiceLoader SPI, jlink custom JRE, jdeps dependency analysis, --add-opens, --add-exports, --add-modules, split packages, unnamed module, automatic module, Automatic-Module-Name manifest attribute, multi-release JAR, ModuleLayer, ModuleFinder, StackWalker (module-aware)
