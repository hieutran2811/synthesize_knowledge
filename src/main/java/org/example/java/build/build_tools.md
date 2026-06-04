# Build Tools: Maven & Gradle (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Build tool là gì & giải quyết gì?

**Build tool** tự động hóa vòng đời build: **compile → test → package → quản lý dependency → publish**. Trước Maven, lập trình viên tự tải JAR, viết script `javac`/`jar` thủ công, "JAR hell" (xung đột version). Maven & Gradle chuẩn hóa việc này bằng **convention** + **dependency management bắc cầu (transitive)**.

| | Maven | Gradle |
|--|-------|--------|
| Ra đời | 2004, XML | 2008, Groovy/Kotlin DSL |
| Triết lý | Convention over configuration | Flexible, programmable |
| Cấu hình | `pom.xml` (khai báo) | `build.gradle(.kts)` (script) |

---

# Phần 1 – Maven

## Components – POM & Coordinates

`pom.xml` (Project Object Model) mô tả project. Mỗi artifact định danh bằng **GAV**:
```xml
<groupId>org.example</groupId>       <!-- tổ chức/namespace -->
<artifactId>order-service</artifactId> <!-- tên module -->
<version>1.2.0-SNAPSHOT</version>     <!-- SNAPSHOT = đang phát triển, RELEASE = ổn định -->
<packaging>jar</packaging>            <!-- jar/war/pom -->
```
> `-SNAPSHOT`: Maven cho phép cập nhật đè (mỗi build lấy bản mới nhất). RELEASE: bất biến, không được publish đè.

## How – Build Lifecycle, Phase, Goal

Maven có **3 lifecycle**: `clean`, `default` (build), `site`. Mỗi lifecycle gồm các **phase** tuần tự; chạy 1 phase = chạy **tất cả phase trước nó**.

```
default lifecycle (rút gọn):
validate → compile → test → package → verify → install → deploy
                      │        │                  │          │
              (unit test)  (jar/war)      (~/.m2 local)  (remote repo)
```
```bash
mvn clean install   # clean + build tới install (chạy mọi phase từ validate→install)
mvn test            # chỉ tới test
mvn package -DskipTests  # build jar, bỏ qua test
```
- **Goal**: việc cụ thể của 1 plugin (`compiler:compile`). Plugin **gắn goal vào phase**. Vd `maven-surefire-plugin:test` gắn vào phase `test`.
- `install` vs `deploy`: install → repo **local** (`~/.m2`); deploy → repo **remote** (Nexus/Artifactory) để team dùng chung.

## How – Dependency Scopes

```xml
<dependency>
    <groupId>org.springframework</groupId>
    <artifactId>spring-context</artifactId>
    <scope>compile</scope>   <!-- mặc định -->
</dependency>
```

| Scope | Compile | Test | Runtime | Đóng gói | Ví dụ |
|-------|:-------:|:----:|:-------:|:--------:|-------|
| `compile` (default) | ✔ | ✔ | ✔ | ✔ | thư viện chính |
| `provided` | ✔ | ✔ | ✘ | ✘ | servlet-api (container cấp) |
| `runtime` | ✘ | ✔ | ✔ | ✔ | JDBC driver |
| `test` | ✘ | ✔ | ✘ | ✘ | JUnit, Mockito |
| `import` | – | – | – | – | chỉ trong `dependencyManagement` (BOM) |

## How – Transitive Dependency & Mediation

Maven tự kéo dependency **bắc cầu** (A→B→C). Khi 2 đường dẫn cùng artifact khác version:
- **Mediation "nearest wins"**: version ở **độ sâu nhỏ nhất** trong cây thắng (KHÔNG phải version cao nhất!).
- Cùng độ sâu → khai báo **đầu tiên** thắng.

```bash
mvn dependency:tree            # xem cây dependency, chẩn đoán xung đột
mvn dependency:tree -Dverbose -Dincludes=com.fasterxml.jackson.core:jackson-databind
```
```xml
<!-- Loại bỏ transitive không mong muốn -->
<dependency>
    <artifactId>some-lib</artifactId>
    <exclusions>
        <exclusion><groupId>commons-logging</groupId><artifactId>commons-logging</artifactId></exclusion>
    </exclusions>
</dependency>
```

## How – `dependencyManagement` & BOM (quản lý version tập trung)

```xml
<dependencyManagement>
    <dependencies>
        <dependency>                <!-- import BOM: ép version đồng bộ cả họ thư viện -->
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>3.3.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
<!-- Khai báo dependency KHÔNG cần version → lấy từ BOM → đồng nhất, tránh xung đột -->
<dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
</dependencies>
```
> `dependencyManagement` chỉ **khai báo version**, không thêm dependency. BOM = "Bill of Materials" — bộ version đã test tương thích.

## How – Multi-module (Reactor)

```xml
<!-- parent pom.xml -->
<packaging>pom</packaging>
<modules>
    <module>common</module>
    <module>order-service</module>
    <module>payment-service</module>
</modules>
```
> Maven Reactor sắp xếp thứ tự build theo phụ thuộc giữa module. Module con kế thừa version/config từ parent. Liên hệ cấu trúc dự án đa module.

## How – Profiles & Plugin phổ biến

```xml
<profiles>
    <profile><id>prod</id><properties><env>production</env></properties></profile>
</profiles>
```
```bash
mvn package -Pprod
```
Plugin hay gặp: `maven-compiler-plugin` (Java version), `surefire` (unit test), `failsafe` (integration test), `maven-shade-plugin`/`assembly` (fat jar), `spring-boot-maven-plugin` (executable jar + buildpack image).

---

# Phần 2 – Gradle

## Components – Build script & Task graph

Gradle dùng **DSL** (Groovy `build.gradle` hoặc Kotlin `build.gradle.kts`) và mô hình **task DAG** (đồ thị tác vụ).

```kotlin
// build.gradle.kts
plugins {
    java
    id("org.springframework.boot") version "3.3.0"
    id("io.spring.dependency-management") version "1.1.5"
}
group = "org.example"
version = "1.2.0-SNAPSHOT"

repositories { mavenCentral() }

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    runtimeOnly("org.postgresql:postgresql")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
tasks.test { useJUnitPlatform() }
```
```kotlin
// settings.gradle.kts — khai báo project & module
rootProject.name = "my-app"
include("common", "order-service", "payment-service")
```

## How – Configurations (quan trọng nhất: `api` vs `implementation`)

Gradle "scope" gọi là **configuration**:

| Configuration | ~ Maven scope | Lộ ra consumer? |
|---------------|---------------|-----------------|
| `implementation` | compile | **KHÔNG** (ẩn khỏi module phụ thuộc) |
| `api` | compile | **CÓ** (transitive) |
| `compileOnly` | provided | Không |
| `runtimeOnly` | runtime | runtime |
| `testImplementation` | test | – |
| `annotationProcessor` | – | – (Lombok, MapStruct) |

### `api` vs `implementation` – tăng tốc build + đóng gói tốt hơn
```kotlin
// module "common"
dependencies {
    api("com.google.guava:guava:33.0.0")        // module dùng common sẽ THẤY guava
    implementation("org.apache.commons:commons-lang3:3.14")  // ẨN – chi tiết nội bộ
}
```
> Dùng `implementation` (mặc định nên ưu tiên) → đổi dependency nội bộ **không** buộc recompile các module phụ thuộc → build nhanh hơn, ranh giới module rõ ràng (liên hệ encapsulation [[oop/encapsulation.md]] ở cấp module, và JPMS [[modern/java_modules.md]]). Chỉ dùng `api` khi type của dependency **xuất hiện trong public API** của module.

## How – Vì sao Gradle nhanh hơn Maven?

| Cơ chế | Tác dụng |
|--------|----------|
| **Incremental build** | Chỉ build lại task có input/output thay đổi (up-to-date checking) |
| **Build cache** | Tái dùng output từ cache (cả local & remote, chia sẻ giữa CI/máy dev) |
| **Gradle Daemon** | JVM thường trú, tránh khởi động lại JVM mỗi lần build |
| **Configuration cache** | Cache giai đoạn cấu hình build graph |
| **Parallel execution** | Build module song song |

```bash
./gradlew build --build-cache --parallel
./gradlew build --scan          # build scan: phân tích thời gian, dependency
```

## How – Version Catalog & Platform (BOM)

```toml
# gradle/libs.versions.toml — quản lý version tập trung, type-safe
[versions]
spring-boot = "3.3.0"
[libraries]
spring-web = { module = "org.springframework.boot:spring-boot-starter-web", version.ref = "spring-boot" }
```
```kotlin
dependencies {
    implementation(libs.spring.web)                                   // tham chiếu type-safe
    implementation(platform("org.springframework.boot:spring-boot-dependencies:3.3.0")) // ~ BOM import
}
```

## How – Custom task & Wrapper

```kotlin
tasks.register("hello") { doLast { println("Hello") } }
// gradlew (Gradle Wrapper): cố định version Gradle, không cần cài sẵn → build reproducible
```
> **Luôn commit Gradle Wrapper** (`gradlew`, `gradle/wrapper/`) → mọi máy/CI build cùng version Gradle.

---

## Compare – Maven vs Gradle

| Tiêu chí | Maven | Gradle |
|----------|-------|--------|
| Cú pháp | XML (dài, rõ ràng, dễ đọc máy) | DSL Groovy/Kotlin (gọn, lập trình được) |
| Hiệu năng | Chậm hơn (không cache incremental tốt) | **Nhanh** (cache, daemon, incremental) |
| Linh hoạt | Hạn chế (theo convention) | Cao (custom task tùy ý) |
| Đường cong học | Thoải, dễ đoán | Dốc hơn (DSL + lifecycle phức tạp) |
| Dependency mediation | Nearest wins | **Highest version wins** (khác Maven!) |
| IDE/tooling | Rất ổn định | Tốt, Kotlin DSL có auto-complete |
| Reproducibility | Cao | Cao (wrapper) |
| Hệ sinh thái | Lớn nhất, chuẩn enterprise | Mặc định Android, phổ biến dự án mới |

> ⚠️ Khác biệt mediation dễ gây bug khi migrate: Maven chọn **gần nhất**, Gradle chọn **version cao nhất**.

---

## When – Chọn build tool nào?

| Tình huống | Lựa chọn |
|-----------|----------|
| Enterprise Java truyền thống, team quen XML | **Maven** |
| Android | **Gradle** (bắt buộc) |
| Monorepo lớn, build chậm, cần custom logic | **Gradle** (build cache, incremental) |
| Dự án đơn giản, ưu tiên ổn định/đoán trước | Maven |
| Cần plugin/automation phức tạp | Gradle |

---

## Trade-offs

- **Maven**: (+) đơn giản, chuẩn hóa, dễ đọc, ổn định, hệ sinh thái khổng lồ. (−) chậm, XML dài dòng, custom logic khó (phải viết plugin).
- **Gradle**: (+) nhanh (cache/incremental/daemon), linh hoạt, DSL gọn, version catalog. (−) học khó hơn, build script dễ thành "code rối", daemon/cache đôi khi gây lỗi khó hiểu (`--no-daemon`, clean cache).

---

## Real-world Usage

### Bảo mật & quản trị dependency (cho cả 2)
- **Dependency scanning**: OWASP `dependency-check`, Snyk, GitHub Dependabot → phát hiện CVE trong transitive deps (vd Log4Shell, gadget chain ở [[core/serialization.md]]). Liên hệ [[security/devsecops/devsecops_pipeline.md]] nếu có.
- **Lock version**: Maven `dependency:tree` review; Gradle `dependencies` + lockfile (`./gradlew dependencies --write-locks`).
- **Reproducible build**: cố định version (không dùng range/`+`), commit wrapper.

### CI/CD
```bash
# CI Maven
mvn -B clean verify          # -B batch mode (non-interactive)
# CI Gradle
./gradlew build --no-daemon  # CI thường tắt daemon
```
> Cache `~/.m2` hoặc Gradle cache giữa các CI run để tăng tốc. Build fat-jar/layered-jar rồi đóng Docker image — liên hệ [[docker/production/cicd_integration.md]] nếu có.

### Spring Boot
- Maven: `spring-boot-maven-plugin` → `mvn spring-boot:run`, build executable jar / OCI image (`build-image`).
- Gradle: plugin `org.springframework.boot` → `./gradlew bootRun`, `bootJar`, `bootBuildImage`.

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[modern/java_modules.md]] (JPMS – ranh giới module ở cấp ngôn ngữ; `api`/`implementation` ở cấp build), [[oop/encapsulation.md]] (đóng gói cấp module), [[core/serialization.md]] (CVE trong dependency), [[modern/graalvm_native.md]] (build native qua plugin), [[docker/production/cicd_integration.md]] (đóng gói image), [[security/devsecops/devsecops_pipeline.md]] (dependency scanning).
>
> Đã hoàn thành 4 cụm bổ sung: Core language completeness, Serialization/JSON/Validation, HTTP & Spring Cloud, Spring features & Build tools.

*Cập nhật lần cuối: 2026-06-04*
