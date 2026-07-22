# Build Tools: Maven & Gradle (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Build tool là gì & giải quyết gì?

**Build tool** *(công cụ dựng dự án — tự động biến mã nguồn thành sản phẩm có thể kiểm thử và phân phối)* tự động hóa vòng đời build: **compile** *(biên dịch — dịch mã nguồn sang bytecode)* **→ test → package** *(đóng gói thành file JAR/WAR)* **→ quản lý dependency** *(thư viện phụ thuộc)* **→ publish** *(xuất bản lên kho dùng chung)*. Trước Maven, lập trình viên thường tự tải JAR *(file thư viện Java đã đóng gói)* và viết script `javac`/`jar` thủ công, dễ dẫn tới **JAR hell** *(tình trạng thiếu thư viện hoặc xung đột phiên bản)*. Maven và Gradle giảm vấn đề này bằng quy ước cấu trúc dự án, kho artifact và cơ chế giải quyết **transitive dependency** *(phụ thuộc bắc cầu — thư viện mà dependency trực tiếp cần thêm)*.

> 💡 **Giải thích dễ hiểu:**
> Hãy hình dung build tool như một **đầu bếp trưởng trong nhà hàng**. Bạn (lập trình viên) chỉ đưa ra công thức (mã nguồn) và bảng nguyên liệu cần dùng (danh sách dependency). Đầu bếp trưởng lo hết phần còn lại: đi lấy đủ nguyên liệu từ kho (tải thư viện), sơ chế (compile), nếm thử (test), bày ra đĩa (package) và mang lên phục vụ (publish). Ngày xưa không có đầu bếp trưởng, mỗi người tự chạy đi lấy từng nguyên liệu — dễ lấy nhầm phiên bản, thiếu món, hoặc hai loại nước sốt "cãi nhau" (JAR hell). Maven và Gradle chính là hai đầu bếp trưởng giỏi, mỗi người một phong cách.

| | Maven | Gradle |
|--|-------|--------|
| Ra đời | 2004, XML | 2008, Groovy/Kotlin DSL |
| Triết lý | Convention over configuration | Flexible, programmable |
| Cấu hình | `pom.xml` (khai báo) | `build.gradle(.kts)` (script) |

---

# Phần 1 – Maven

## Components – POM & Coordinates

`pom.xml` **(Project Object Model)** *(mô hình đối tượng dự án — file XML mô tả toàn bộ dự án)* mô tả project. Mỗi **artifact** *(sản phẩm build — file jar/war được tạo ra)* định danh bằng **GAV** *(Group-Artifact-Version — bộ 3 tọa độ định danh duy nhất một thư viện)*:
```xml
<groupId>org.example</groupId>       <!-- tổ chức/namespace -->
<artifactId>order-service</artifactId> <!-- tên module -->
<version>1.2.0-SNAPSHOT</version>     <!-- SNAPSHOT = đang phát triển, RELEASE = ổn định -->
<packaging>jar</packaging>            <!-- jar/war/pom -->
```
> `-SNAPSHOT` *(bản chụp — phiên bản đang phát triển, có thể thay đổi nhưng giữ nguyên chuỗi version)* có thể trỏ tới các bản timestamp mới theo **update policy** *(chính sách kiểm tra cập nhật)* của repository và cache cục bộ. Version không có hậu tố `-SNAPSHOT` thường được xem là bản phát hành; việc cấm publish đè do repository manager áp chính sách, không phải mọi kho đều được Maven tự động ép bất biến.

> 💡 **Giải thích dễ hiểu — GAV và SNAPSHOT:**
> GAV giống **địa chỉ nhà đầy đủ** của một thư viện: `groupId` là tỉnh/thành (tổ chức), `artifactId` là tên đường/số nhà (tên module), `version` là "lần sửa nhà thứ mấy". Nhờ có địa chỉ này Maven mới biết đi đâu để "gõ cửa" lấy đúng thư viện.
> Còn `-SNAPSHOT` với bản phát hành giống **bản nháp và bản in chính thức của một cuốn sách**: cùng nhãn bản nháp (`1.2.0-SNAPSHOT`) nhưng nội dung trong kho có thể được cập nhật; bản phát hành (`1.2.0`) nên được khóa và muốn thay đổi phải ra số mới (`1.2.1`). Tuy vậy, Maven còn nhìn vào cache và chính sách cập nhật của kho, nên “SNAPSHOT luôn được tải mới trong mọi build” là cách hiểu quá đơn giản.

## How – Build Lifecycle, Phase, Goal

Maven có **3 lifecycle** *(vòng đời — chuỗi các giai đoạn build theo trình tự)*: `clean`, `default` (build), `site`. Mỗi lifecycle gồm các **phase** *(giai đoạn — một bước trong vòng đời)* tuần tự; chạy 1 phase = chạy **tất cả phase trước nó**.

```
default lifecycle (rút gọn):
validate → compile → test → package → verify → install → deploy
                      │        │                  │          │
              (unit test)  (jar/war)      (~/.m2 local)  (remote repo)
```
```bash
mvn clean install   # clean + build tới install (chạy mọi phase từ validate→install)
mvn test            # chỉ tới test
mvn package -DskipTests  # vẫn compile test, nhưng không chạy test
```
- **Goal** *(mục tiêu — một tác vụ cụ thể)*: việc cụ thể của 1 **plugin** *(phần cắm thêm — module mở rộng chức năng của Maven)*, ví dụ `compiler:compile`. Plugin **gắn goal vào phase**; goal `surefire:test` thường được gắn vào phase `test`.
- `install` vs `deploy`: install → repo **local** *(kho cục bộ — thư mục trên máy bạn `~/.m2`)*; deploy → repo **remote** *(kho từ xa — máy chủ chung)* (Nexus/Artifactory) để team dùng chung.

> 💡 **Giải thích dễ hiểu — lifecycle, phase, goal:**
> Hãy hình dung vòng đời build như **dây chuyền sản xuất trong nhà máy**. `lifecycle` là cả dây chuyền. `phase` là các trạm theo thứ tự cố định trên dây chuyền: trạm kiểm tra → trạm lắp ráp → trạm đóng gói... Điểm mấu chốt: hàng đi tới trạm nào thì **bắt buộc đã đi qua mọi trạm trước đó** — nên gõ `mvn package` là tự động chạy luôn compile và test trước. `goal` là **thao tác cụ thể một công nhân làm tại trạm** (siết ốc, dán nhãn); một `plugin` là "tổ công nhân" mang các goal tới gắn vào trạm phù hợp.
> Còn `install` với `deploy`: `install` là cất thành phẩm vào **tủ đồ riêng ở nhà bạn** (`~/.m2`) để tự dùng; `deploy` là gửi lên **kho tổng của công ty** (Nexus/Artifactory) cho cả team lấy về.

## How – Dependency Scopes

**Scope** *(phạm vi — quy định dependency xuất hiện trên classpath nào và có truyền sang project phụ thuộc hay không)* quyết định một thư viện được thấy lúc compile, test hoặc chạy. Scope không đồng nghĩa trực tiếp với “được nhét vào JAR”: JAR chuẩn do `maven-jar-plugin` tạo ra không tự chứa các dependency; fat JAR, WAR hoặc plugin đóng gói mới quyết định nội dung artifact cuối.

> 💡 **Giải thích dễ hiểu — dependency scope:**
> Coi các dependency như **thẻ ra vào từng khu của công trường**. Thẻ `compile` vào được khu thiết kế, kiểm thử và vận hành. Thẻ `provided` vào khu thiết kế/kiểm thử nhưng lúc vận hành phải dùng thiết bị do tòa nhà cung cấp. Thẻ `runtime` không cần khi đọc bản vẽ nhưng phải có khi bật máy. Thẻ `test` chỉ vào khu nghiệm thu. Scope chủ yếu kiểm soát “được vào classpath nào”; việc xếp dụng cụ vào thùng hàng cuối cùng là trách nhiệm của kiểu đóng gói và plugin.

```xml
<dependency>
    <groupId>org.springframework</groupId>
    <artifactId>spring-context</artifactId>
    <scope>compile</scope>   <!-- mặc định -->
</dependency>
```

| Scope | Compile classpath | Test classpath | Runtime classpath | Truyền sang project phụ thuộc? | Ví dụ |
|-------|:-----------------:|:--------------:|:-----------------:|:-----------------------------:|-------|
| `compile` (mặc định) | ✔ | ✔ | ✔ | ✔ | thư viện chính |
| `provided` | ✔ | ✔ | ✘ | ✘ | Servlet API do container cấp |
| `runtime` | ✘ | ✔ | ✔ | ✔ | JDBC driver |
| `test` | ✘ | ✔ | ✘ | ✘ | JUnit, Mockito |
| `import` | – | – | – | – | chỉ áp dụng cho dependency kiểu `pom` trong `dependencyManagement` |

## How – Transitive Dependency & Mediation

Maven tự kéo **dependency bắc cầu (transitive)** *(phụ thuộc gián tiếp — thư viện mà thư viện của bạn lại cần)* (A→B→C). Khi 2 đường dẫn cùng artifact khác version, Maven phải **mediation** *(hòa giải — chọn ra một version duy nhất)*:
- **Mediation "nearest wins"** *(gần nhất thắng)*: version ở **độ sâu nhỏ nhất** trong cây thắng (KHÔNG phải version cao nhất!).
- Cùng độ sâu → khai báo **đầu tiên** thắng.

> 💡 **Giải thích dễ hiểu — transitive dependency & "nearest wins":**
> Bạn nhờ một người bạn (thư viện A) đến giúp; người đó lại rủ thêm bạn của họ (thư viện B), rồi B rủ thêm C. Cuối cùng cả một dây chuyền người kéo tới nhà bạn dù bạn chỉ mời một người — đó là **phụ thuộc bắc cầu**.
> Rắc rối xảy ra khi hai nhánh cùng mang tới **hai phiên bản khác nhau của cùng một thứ** (ví dụ Jackson 2.13 và Jackson 2.15). Maven phải chọn một. Quy tắc của Maven là **"ai đứng gần chủ nhà hơn thì thắng"** — tính theo số bước trong cây phụ thuộc, KHÔNG phải phiên bản nào mới hơn. Đây là điểm cực dễ gây bug: bạn tưởng mình đang dùng bản mới, nhưng một nhánh gần hơn lại kéo về bản cũ. Lệnh `mvn dependency:tree` là "cây gia phả" để bạn soi ra ai đã kéo phiên bản nào về.

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
            <version>${spring.boot.version}</version> <!-- pin trong parent/properties của dự án -->
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
> `dependencyManagement` *(quản lý phụ thuộc tập trung)* quản lý version/scope và có thể chi phối cả dependency bắc cầu, nhưng **không tự thêm dependency** vào project. **BOM = Bill of Materials** *(bảng kê vật tư — POM tập trung danh sách version của một họ artifact)*. BOM giúp các version đồng bộ; chỉ nên khẳng định chúng đã được kiểm thử tương thích khi nhà phát hành BOM có cam kết đó.

> 💡 **Giải thích dễ hiểu — BOM & dependencyManagement:**
> BOM giống một **combo/set menu đã được nhà hàng phối sẵn**. Thay vì bạn tự gọi từng món (tự chọn version từng thư viện Spring) và lo chúng "kỵ nhau", bạn gọi nguyên set (`spring-boot-dependencies`) — nhà bếp đã đảm bảo mọi món trong set hợp vị với nhau. Khi khai báo `spring-boot-starter-web` bạn thậm chí không cần ghi version, vì đã lấy từ set. `dependencyManagement` chỉ là "tấm bảng dán giá" — nó quy định *nếu* dùng món này thì version nào, chứ tự nó không gọi món nào cả.

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
> **Maven Reactor** *(bộ điều phối build đa module)* thu thập các module trong một lần chạy và sắp xếp thứ tự build theo quan hệ phụ thuộc. Cần phân biệt hai vai trò: **aggregator POM** *(POM tổng hợp)* khai báo `<modules>` để gom build; **parent POM** *(POM cha)* được module con khai báo trong `<parent>` để kế thừa properties, plugin/dependency management. Một POM thường giữ cả hai vai trò, nhưng không bắt buộc.

> 💡 **Giải thích dễ hiểu — multi-module & Reactor:**
> Dự án đa module giống việc **lắp ráp một chiếc xe từ nhiều xưởng linh kiện**: xưởng động cơ (`common`), xưởng thân xe (`order-service`), xưởng nội thất (`payment-service`). Không thể lắp thân xe trước khi có khung, nên phải làm đúng thứ tự. **Reactor** chính là quản đốc thông minh: nó tự nhìn ra "món nào cần món nào" rồi xếp lịch build sao cho thứ nào phụ thuộc thứ khác thì được làm sau. Bạn không cần tự sắp lịch — chỉ khai ai phụ thuộc ai, Reactor lo phần còn lại.

## How – Profiles & Plugin phổ biến

```xml
<profiles>
    <profile><id>prod</id><properties><env>production</env></properties></profile>
</profiles>
```
```bash
mvn package -Pprod
```
Plugin hay gặp: `maven-compiler-plugin` (compile), `maven-surefire-plugin` (unit test), `maven-failsafe-plugin` (integration test, thường chạy ở `integration-test`/`verify`), `maven-shade-plugin` hoặc `maven-assembly-plugin` (fat JAR), `spring-boot-maven-plugin` (executable JAR và OCI image). Trong production, nên pin version plugin qua `pluginManagement`; không phụ thuộc ngầm vào version mặc định thay đổi theo Maven hoặc parent POM.

---

# Phần 2 – Gradle

## Components – Build script & Task graph

Gradle dùng **DSL** *(Domain-Specific Language — ngôn ngữ chuyên dụng để viết cấu hình build)* (Groovy `build.gradle` hoặc Kotlin `build.gradle.kts`) và mô hình **task DAG** *(Directed Acyclic Graph — đồ thị có hướng không vòng lặp mô tả các tác vụ và thứ tự)*.

> 💡 **Giải thích dễ hiểu — DSL & task DAG:**
> Maven cấu hình bằng XML — giống điền vào **một tờ khai form có sẵn ô trống**: rõ ràng, dễ đọc nhưng cứng nhắc. Gradle cấu hình bằng DSL — giống **viết một đoạn kịch bản** có thể chèn logic (if, vòng lặp), linh hoạt hơn nhưng dễ thành "code rối".
> Còn **task DAG**: hình dung như **sơ đồ nấu một bữa tiệc** — muốn dọn món chính phải nấu xong, muốn nấu phải sơ chế xong. Gradle vẽ ra sơ đồ mũi tên "việc này trước việc kia", đảm bảo không có vòng lặp luẩn quẩn (A chờ B mà B lại chờ A), rồi chạy các nhánh độc lập song song cho nhanh.

```kotlin
// build.gradle.kts
plugins {
    `java-library` // cung cấp api/implementation
}
group = "org.example"
version = "1.2.0-SNAPSHOT"

repositories { mavenCentral() }

dependencies {
    api(project(":public-model"))
    implementation(project(":internal-utils"))
    runtimeOnly(project(":runtime-adapter"))
    testImplementation(project(":test-support"))
}
tasks.test { useJUnitPlatform() }
```
```kotlin
// settings.gradle.kts — khai báo project & module
rootProject.name = "my-app"
include("common", "order-service", "payment-service")
```

## How – Configurations (quan trọng nhất: `api` vs `implementation`)

Gradle không chỉ đổi tên Maven scope. **Configuration** *(cấu hình phụ thuộc — tập dependency/variant phục vụ một mục đích và classpath cụ thể)* tạo thành một đồ thị có thể dùng để khai báo, resolve hoặc công bố dependency. Bảng sau là ánh xạ gần đúng khi dùng `java-library` plugin:

| Configuration | Gần với Maven scope | Consumer compile thấy? | Consumer runtime nhận? |
|---------------|----------------------|:----------------------:|:----------------------:|
| `implementation` | `compile` | ✘ | ✔ |
| `api` | `compile` | ✔ | ✔ |
| `compileOnly` | `provided` | ✘ | ✘ |
| `runtimeOnly` | `runtime` | ✘ | ✔ |
| `testImplementation` | `test` | – | – |
| `annotationProcessor` | – | – | – |

### `api` vs `implementation` – tăng tốc build + đóng gói tốt hơn
```kotlin
// module "common"
dependencies {
    api(libs.guava)                    // alias khai trong Version Catalog; consumer compile thấy
    implementation(libs.commons.lang3) // ẩn khỏi compile classpath của consumer
}
```
> `api` do `java-library` plugin cung cấp. Dùng `implementation` khi dependency chỉ là chi tiết nội bộ sẽ tránh đưa nó lên **compile classpath** *(đường dẫn thư viện dùng khi biên dịch)* của consumer. Nhờ vậy, một thay đổi chỉ tác động nội bộ thường không buộc các module consumer biên dịch lại. Dùng `api` khi type của dependency xuất hiện trong **public API** *(giao diện công khai — kiểu/hàm module khác nhìn thấy)* hoặc consumer thực sự cần compile trực tiếp với dependency đó.

> 💡 **Giải thích dễ hiểu — `api` vs `implementation`:**
> Đây là một trong những điểm hay nhất của Gradle. Hình dung module `common` của bạn như một **nhà bếp**, còn các module khác là **thực khách** dùng bếp đó.
> - `implementation("commons-lang3")` giống nguyên liệu **bếp dùng riêng bên trong** — thực khách không thấy, không đụng tới. Nếu bếp đổi loại gia vị này, thực khách chẳng ảnh hưởng gì (không phải recompile) → build nhanh hơn, và không ai vô tình phụ thuộc vào chi tiết nội bộ của bếp.
> - `api("guava")` giống **món ăn được bày ra bàn** cho khách — khách nhìn thấy và dùng trực tiếp guava. Chỉ khai `api` khi kiểu dữ liệu của thư viện đó *thò ra* trong hàm công khai của bạn (ví dụ hàm trả về một `com.google.common.collect.Multimap`).
> Quy tắc vàng: **mặc định luôn dùng `implementation`**, chỉ nâng lên `api` khi buộc phải lộ kiểu ra ngoài. Càng ít `api`, ranh giới module càng kín và build càng nhanh.

## How – Vì sao Gradle có thể nhanh hơn Maven?

| Cơ chế | Tác dụng |
|--------|----------|
| **Incremental build** *(build tăng dần)* | Chỉ build lại task có input/output thay đổi (up-to-date checking) |
| **Build cache** *(bộ nhớ đệm build)* | Tái dùng output của task có cache key khớp; remote cache cần được cấu hình |
| **Gradle Daemon** *(tiến trình nền thường trú)* | JVM thường trú, tránh khởi động lại JVM mỗi lần build |
| **Configuration cache** *(đệm giai đoạn cấu hình)* | Tái dùng kết quả configuration nếu build/plugin tương thích |
| **Parallel execution** *(thực thi song song)* | Có thể build các project độc lập song song |

> 💡 **Giải thích dễ hiểu — vì sao Gradle nhanh hơn:**
> Các cơ chế trên hợp lại như một **quán ăn tối ưu quy trình**:
> - **Incremental build**: chỉ nấu lại món khách vừa đổi ý, không nấu lại cả mâm.
> - **Build cache**: món đã nấu y hệt lần trước thì lấy trong tủ giữ nóng ra dùng luôn — thậm chí chia sẻ tủ này giữa nhiều bếp (máy dev và server CI).
> - **Gradle Daemon**: đầu bếp *ở lại trong bếp* giữa các đơn hàng thay vì đi về rồi quay lại (không phải khởi động lại JVM mỗi lần — vốn là công đoạn tốn vài giây).
> - **Configuration cache**: giữ lại “sơ đồ phân công” đã tính ở lần trước thay vì họp và chia việc lại từ đầu.
> - **Parallel execution**: nhiều đầu bếp nấu các món độc lập cùng lúc.
> Các tối ưu này chỉ hiệu quả khi task khai báo input/output đúng, plugin tương thích cache và cấu trúc project có đủ việc độc lập. Maven cũng có tối ưu ở plugin/CI và có thể chạy module song song; vì vậy cần đo trên chính dự án thay vì xem “Gradle luôn nhanh hơn” là một định luật.

```bash
./gradlew build --build-cache --parallel
./gradlew build --scan          # build scan: phân tích thời gian, dependency
```

## How – Version Catalog & Platform (BOM)

**Version Catalog** *(danh mục tập trung tên và version dependency)* tạo các alias type-safe dùng chung trong build script. **Platform** *(nền tảng ràng buộc phiên bản)* đưa một tập dependency constraints vào quá trình resolve; Maven BOM có thể được nhập làm Gradle platform.

```toml
# gradle/libs.versions.toml — quản lý version tập trung, type-safe
[versions]
spring-boot = "<version-approved-by-team>" # placeholder: thay bằng version được dự án phê duyệt
[libraries]
spring-boot-bom = { module = "org.springframework.boot:spring-boot-dependencies", version.ref = "spring-boot" }
spring-web = { module = "org.springframework.boot:spring-boot-starter-web", version.ref = "spring-boot" }
```
```kotlin
dependencies {
    implementation(platform(libs.spring.boot.bom)) // platform đưa constraints vào graph
    implementation(libs.spring.web)               // tham chiếu type-safe
}
```

> 💡 **Giải thích dễ hiểu — catalog và platform khác nhau thế nào?**
> Version Catalog giống **danh bạ món ăn**: cho mỗi tọa độ dependency một tên ngắn, type-safe và gom version về một chỗ. Nó không tự ép kết quả cuối khi có xung đột. Platform/BOM giống **bộ quy tắc phối món** tham gia vào dependency graph bằng constraints. Nếu cần đảm bảo chính xác version đã resolve qua nhiều lần build, hãy dùng thêm dependency locking.

## How – Custom task & Wrapper

```kotlin
tasks.register("hello") { doLast { println("Hello") } }
// gradlew (Gradle Wrapper): cố định version Gradle, không cần cài Gradle toàn cục
```
> **Luôn commit Gradle Wrapper** *(bộ bao bọc — script tải và chạy đúng phiên bản Gradle)* gồm `gradlew`, `gradlew.bat` và `gradle/wrapper/`. Nên kiểm tra cả `distributionSha256Sum` để xác minh bản phân phối được tải. Wrapper chuẩn hóa Gradle version, là một điều kiện quan trọng nhưng **chưa đủ** để tạo **reproducible build** *(build tái lập — cùng đầu vào cho ra artifact tương đương)*.

> 💡 **Giải thích dễ hiểu — Gradle Wrapper:**
> Wrapper giống **tờ giấy dán trên hộp đồ nghề ghi rõ "dùng đúng cờ lê số 14"**, kèm khả năng lấy đúng cây cờ lê nếu máy chưa có. Nó loại bỏ một nguồn sai khác là version Gradle, nhưng chưa kiểm soát JDK, dependency động, timezone hay dữ liệu sinh trong lúc build. Muốn kết quả thật sự tái lập còn phải cố định các đầu vào đó. Maven cũng có Maven Wrapper (`mvnw`, `mvnw.cmd`, `.mvn/wrapper/`) với mục tiêu tương tự.

---

## Compare – Maven vs Gradle

| Tiêu chí | Maven | Gradle |
|----------|-------|--------|
| Cú pháp | XML (dài, rõ ràng, dễ đọc máy) | DSL Groovy/Kotlin (gọn, lập trình được) |
| Hiệu năng | Dễ đoán; hiệu năng phụ thuộc plugin/module | Có nhiều cơ chế cache/incremental; hiệu quả phụ thuộc cách khai báo task |
| Linh hoạt | Hạn chế (theo convention) | Cao (custom task tùy ý) |
| Đường cong học | Thoải, dễ đoán | Dốc hơn (DSL + lifecycle phức tạp) |
| Dependency mediation | Nearest definition; cùng độ sâu thì khai báo trước thắng | Mặc định chọn version cao nhất theo quy tắc sắp thứ tự của Gradle |
| IDE/tooling | Rất ổn định | Tốt, Kotlin DSL có auto-complete |
| Chuẩn hóa toolchain | Maven Wrapper + pin plugin/JDK | Gradle Wrapper + pin plugin/JDK |
| Hệ sinh thái | Rất phổ biến trong Java enterprise | Build system tiêu chuẩn của Android; phổ biến trong JVM ecosystem |

> ⚠️ Khác biệt mediation dễ gây bug khi migrate: Maven dùng **nearest definition**; Gradle mặc định xét toàn graph và chọn version cao nhất theo quy tắc của nó. Đây chỉ là mặc định: dependency management, platform/constraints, `strictly`, force, resolution rules và lockfile có thể thay đổi hoặc giới hạn kết quả. Dùng `mvn dependency:tree` hoặc `./gradlew dependencyInsight --dependency <name>` để xem lý do version được chọn.

---

## When – Chọn build tool nào?

| Tình huống | Lựa chọn |
|-----------|----------|
| Enterprise Java truyền thống, team quen XML | **Maven** |
| Android theo toolchain chính thức | **Gradle** với Android Gradle Plugin |
| Monorepo lớn, build chậm, cần custom logic | **Gradle** (build cache, incremental) |
| Dự án đơn giản, ưu tiên ổn định/đoán trước | Maven |
| Cần plugin/automation phức tạp | Gradle |

---

## Trade-offs

- **Maven**: (+) mô hình khai báo và lifecycle chuẩn hóa, POM dễ so sánh giữa dự án, hệ sinh thái plugin lớn. (−) XML dài; custom logic thường cần plugin; tối ưu build lặp lại ít tích hợp thống nhất hơn Gradle.
- **Gradle**: (+) linh hoạt, có incremental build/cache/Daemon, variant-aware dependency management và version catalog. (−) model phức tạp hơn; build script dễ thành code khó bảo trì; cache chỉ đáng tin khi task/plugin khai báo input/output đúng.

---

## Real-world Usage

### Bảo mật & quản trị dependency (cho cả 2)
- **Dependency scanning** *(quét phụ thuộc — dò lỗ hổng bảo mật trong các thư viện)*: OWASP `dependency-check`, Snyk, GitHub Dependabot → phát hiện **CVE** *(Common Vulnerabilities and Exposures — mã định danh một lỗ hổng bảo mật đã công bố)* trong transitive deps (vd Log4Shell, gadget chain ở [[core/serialization.md]]). Liên hệ [[security/devsecops/devsecops_pipeline.md]] nếu có.
- **Kiểm soát version**: Maven dùng dependency/BOM management và có thể thêm Maven Enforcer để cấm graph không hợp lệ; Maven core không cung cấp lockfile tương đương Gradle. Với Gradle, kích hoạt **dependency locking** *(khóa dependency — ghi lại version đã resolve)*, chạy build có `--write-locks`, rồi commit lockfile.
- **Reproducible build**: cố định dependency và plugin (tránh range/`+`), commit wrapper, pin Java toolchain, kiểm soát nguồn sinh timestamp/random và xác minh checksum của artifact tải về.

### CI/CD
```bash
# CI Maven
./mvnw -B clean verify       # Wrapper + batch mode (non-interactive)
# CI Gradle
./gradlew build              # Gradle khuyến nghị Daemon cả trên CI
```
> Chỉ dùng `--no-daemon` khi runner/container ngắn hạn chạy một build hoặc chính sách tài nguyên yêu cầu; trên agent tái sử dụng, Daemon thường giúp build nhanh hơn. Có thể cache Maven local repository hoặc Gradle User Home giữa các CI run, nhưng cache key phải chứa thông tin đủ để tránh tái dùng dữ liệu không tương thích. Remote build cache của Gradle cần cấu hình riêng. Build fat JAR/layered JAR rồi đóng Docker image — liên hệ [[docker/production/cicd_integration.md]] nếu có.

### Spring Boot
- Maven: `spring-boot-maven-plugin` → `mvn spring-boot:run`, build executable jar / OCI image (`build-image`).
- Gradle: plugin `org.springframework.boot` → `./gradlew bootRun`, `bootJar`, `bootBuildImage`.

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[modern/java_modules.md]] (JPMS – ranh giới module ở cấp ngôn ngữ; `api`/`implementation` ở cấp build), [[oop/encapsulation.md]] (đóng gói cấp module), [[core/serialization.md]] (CVE trong dependency), [[modern/graalvm_native.md]] (build native qua plugin), [[docker/production/cicd_integration.md]] (đóng gói image), [[security/devsecops/devsecops_pipeline.md]] (dependency scanning).
>
> Đã hoàn thành 4 cụm bổ sung: Core language completeness, Serialization/JSON/Validation, HTTP & Spring Cloud, Spring features & Build tools.

### Tài liệu chính thức để kiểm tra hành vi theo phiên bản

- [Maven dependency mechanism](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html)
- [Apache Maven Wrapper](https://maven.apache.org/tools/wrapper/)
- [Gradle dependency graph resolution](https://docs.gradle.org/current/userguide/graph_resolution.html)
- [Gradle dependency locking](https://docs.gradle.org/current/userguide/dependency_locking.html)
- [Gradle Daemon](https://docs.gradle.org/current/userguide/gradle_daemon.html)

*Cập nhật lần cuối: 2026-07-22*
