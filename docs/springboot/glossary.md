---
title: "📖 Spring Boot Glossary – Bảng thuật ngữ"
topic: springboot
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# 📖 Spring Boot Glossary – Bảng thuật ngữ

> Tra cứu nhanh thuật ngữ Spring Boot bằng tiếng Việt. Thuật ngữ tiếng Anh được giữ nguyên để dễ đối chiếu code, cấu hình và tài liệu chính thức.

---

## A

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Acknowledgment (ack)** | Xác nhận đã xử lý | Tín hiệu consumer/listener gửi để broker biết message có thể commit offset hoặc loại khỏi queue theo semantics đã chọn. |
| **Actuator** | Bộ endpoint vận hành Spring Boot | Cung cấp health, metrics, info và endpoint quản trị; phải giới hạn exposure và bảo vệ như control plane. |
| **AMQP (Advanced Message Queuing Protocol)** | Giao thức hàng đợi message | Wire protocol trung lập cho message broker; Spring AMQP thường dùng RabbitMQ làm implementation. |
| **AOT (Ahead-of-Time)** | Xử lý trước khi chạy | Phân tích ứng dụng ở build time để tạo metadata/code cần thiết, giảm công việc lúc startup và hỗ trợ native image. |
| **AOT Cache** | Cache tối ưu startup của JVM | Cơ chế Spring Boot/JDK tạo cache training để giảm startup và footprint trên JVM; khác với native image. |
| **ApplicationContext** | Ngữ cảnh ứng dụng | IoC container giữ bean, dependency, event, resource và cấu hình của ứng dụng Spring. |
| **ApplicationEvent** | Sự kiện trong ứng dụng | Thông điệp nội bộ được publish trong `ApplicationContext`; mặc định không phải message broker và thường chạy đồng bộ. |
| **ApplicationRunner** | Tác vụ sau startup | Callback chạy sau khi context đã khởi tạo, nhận đối số đã được Spring phân tích thành `ApplicationArguments`. |
| **@Async** | Thực thi bất đồng bộ | Annotation đưa method qua proxy và chạy bằng `TaskExecutor`; không tự tạo độ bền, retry hoặc transaction phân tán. |
| **Authentication** | Xác thực danh tính | Quá trình chứng minh client/user là ai bằng credential như password, session hoặc token. |
| **Authorization** | Cấp quyền | Quyết định principal đã xác thực được phép thực hiện action nào trên resource nào. |
| **Auto-configuration** | Tự động cấu hình | Spring Boot tạo bean dựa trên classpath, property và bean hiện có; thường back off khi ứng dụng tự khai báo bean phù hợp. |
| **AutoConfiguration.imports** | File đăng ký auto-configuration | Resource trong `META-INF/spring` liệt kê các auto-configuration class để Spring Boot nạp. |

## B

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Back-off** | Tự nhường cấu hình | Auto-configuration không tạo bean mặc định khi phát hiện ứng dụng đã cung cấp bean hoặc điều kiện thay thế. |
| **Backpressure** | Điều tiết ngược | Consumer báo tốc độ có thể xử lý để publisher không đẩy dữ liệu nhanh hơn khả năng downstream. |
| **Baseline-on-migrate** | Đánh dấu baseline khi migrate | Tùy chọn Flyway tạo mốc lịch sử cho database đã tồn tại; dùng sai có thể bỏ qua schema chưa được kiểm chứng. |
| **Batch fetching** | Tải association theo lô | Hibernate gom nhiều lazy association/proxy vào query `IN` để giảm N+1 mà không fetch join toàn bộ collection. |
| **Batch processing** | Xử lý dữ liệu theo lô | Xử lý tập dữ liệu hữu hạn theo job/step, thường có chunk, metadata và khả năng restart thay vì giữ request chờ đến khi hoàn tất. |
| **Bean lifecycle** | Vòng đời bean | Các bước tạo instance, inject dependency, callback khởi tạo, sử dụng và hủy bean trong container. |
| **Bean Validation** | Kiểm tra ràng buộc bean | Chuẩn Jakarta Validation dùng annotation như `@NotNull`, `@Size` và `@Valid` để kiểm tra input/object. |
| **Binder** | Bộ ánh xạ cấu hình | Thành phần chuyển property từ `Environment` thành field/constructor của `@ConfigurationProperties`. |
| **Broker** | Máy chủ trung gian message | Hệ thống nhận, lưu/định tuyến và giao message như Kafka broker hoặc RabbitMQ node. |

## C

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Cache abstraction** | Lớp trừu tượng cache | API Spring như `@Cacheable`, `@CachePut`, `@CacheEvict` tách code nghiệp vụ khỏi cache provider cụ thể. |
| **Cache stampede** | Dồn tải khi cache miss | Nhiều request đồng thời cùng miss một key và cùng truy vấn nguồn, gây spike tải; cần sync/single-flight hoặc phân tán phù hợp. |
| **Caffeine** | Cache trong bộ nhớ | Thư viện local cache hiệu năng cao, phù hợp cache trên từng instance nhưng không tự chia sẻ state giữa nhiều pod. |
| **Cardinality** | Số lượng tổ hợp label khác nhau | Cardinality metric quá cao làm tăng memory/storage và chi phí truy vấn; tránh dùng user ID/request ID làm label. |
| **Carrier thread** | Platform thread mang virtual thread | JVM mount virtual thread lên carrier để chạy; blocking trong vùng pinning có thể giữ carrier và giảm scalability. |
| **CDS (Class Data Sharing)** | Chia sẻ metadata class | Cơ chế JVM lưu metadata class đã load vào archive để giảm startup và memory giữa các JVM tương thích. |
| **Choreography** | Saga phân tán theo sự kiện | Mỗi service phản ứng với event và phát event tiếp theo, không có coordinator trung tâm. |
| **Chunk** | Khối item trong Spring Batch | Nhóm item được read–process–write rồi commit trong một transaction; kích thước chunk cân bằng throughput với chi phí làm lại khi lỗi. |
| **Circuit breaker** | Cầu dao ngắt lỗi | Tạm ngừng gọi downstream đang lỗi để tránh khuếch đại sự cố, sau đó thăm dò phục hồi theo trạng thái. |
| **Closed projection** | Projection đóng | Interface projection chỉ dùng accessor trực tiếp, cho phép Spring Data tối ưu cột cần select tốt hơn. |
| **Cloud Native Buildpacks** | Công cụ build OCI image | Phân tích ứng dụng và tạo container image theo layer mà không cần tự viết Dockerfile cho mọi chi tiết. |
| **CommandLineRunner** | Tác vụ dòng lệnh sau startup | Callback chạy sau khi context sẵn sàng và nhận trực tiếp mảng `String` argument. |
| **Compensating transaction** | Giao dịch bù | Hành động nghiệp vụ đảo hoặc giảm tác động của bước Saga đã thành công khi bước sau thất bại. |
| **CompletableFuture** | Kết quả bất đồng bộ có thể ghép | Java API biểu diễn computation hoàn thành trong tương lai; executor, timeout và exception phải được quản lý rõ. |
| **@ConditionalOnClass** | Điều kiện có class | Chỉ kích hoạt auto-configuration khi class yêu cầu tồn tại trên classpath. |
| **@ConditionalOnMissingBean** | Điều kiện thiếu bean | Chỉ tạo bean mặc định khi container chưa có bean phù hợp, tạo cơ chế back-off. |
| **ConditionEvaluationReport** | Báo cáo điều kiện cấu hình | Báo cáo cho biết auto-configuration nào được áp dụng hoặc bị loại và nguyên nhân của từng condition. |
| **Config Data** | Hệ thống nạp cấu hình | Cơ chế Spring Boot nạp `application.*`, profile document và import như file/config tree theo thứ tự xác định. |
| **Configuration metadata** | Metadata cấu hình | Mô tả property, type, default và documentation để IDE autocomplete và validation tốt hơn. |
| **@ConfigurationProperties** | Ánh xạ cấu hình có kiểu | Bind một nhóm property vào object Java, hỗ trợ type conversion, validation và metadata. |
| **ConnectionFactory** | Nhà máy kết nối reactive | Abstraction R2DBC tạo connection không blocking, tương tự vai trò `DataSource` trong JDBC. |
| **Constructor binding** | Bind qua constructor | Tạo object configuration bất biến bằng constructor/record thay vì setter; là mặc định tự nhiên cho một constructor. |
| **Consumer group** | Nhóm consumer chia việc | Các consumer cùng group phối hợp để mỗi partition/message được giao cho một member theo cơ chế broker tương ứng. |
| **Content negotiation** | Thương lượng định dạng | Chọn representation như JSON/XML dựa trên `Accept`, `Content-Type` và message converter. |
| **Context cache** | Cache Spring test context | Tái sử dụng `ApplicationContext` giữa các test có cấu hình tương đương để giảm thời gian suite. |
| **Context propagation** | Truyền context qua thread/reactive boundary | Chuyển trace, observation hoặc security context khi execution đổi thread; không nên giả định `ThreadLocal` tự đi theo. |
| **Contract test** | Kiểm thử hợp đồng | Xác minh producer và consumer thống nhất request/response hoặc message contract mà không cần chạy toàn hệ thống. |
| **@ControllerAdvice** | Xử lý controller dùng chung | Component áp dụng exception handler, binder hoặc model attribute cho nhiều controller. |
| **CORS (Cross-Origin Resource Sharing)** | Chia sẻ tài nguyên khác origin | Cơ chế trình duyệt cho phép hoặc chặn JavaScript gọi API từ origin khác dựa trên header HTTP. |
| **Cron** | Biểu thức lịch định kỳ | Chuỗi field mô tả thời điểm kích hoạt; cú pháp và số field phụ thuộc scheduler nên cần kiểm tra theo chính framework đang dùng. |
| **CSRF (Cross-Site Request Forgery)** | Giả mạo request liên site | Tấn công lợi dụng credential tự gửi của trình duyệt; đặc biệt cần phòng vệ với session/cookie authentication. |
| **Custom starter** | Starter tự xây dựng | Module đóng gói dependency và auto-configuration dùng chung cho nhiều ứng dụng. |

## D

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **DataSource** | Nguồn kết nối JDBC | Abstraction tạo connection blocking tới database, thường được pool bởi HikariCP. |
| **Dead Letter Topic/Queue (DLT/DLQ)** | Nơi giữ message lỗi | Topic hoặc queue nhận message không thể xử lý sau retry hữu hạn để điều tra và replay có kiểm soát. |
| **Debezium CDC** | Thu thập thay đổi database | Connector đọc transaction log rồi phát insert/update/delete thành event, thường dùng chuyển outbox row sang broker. |
| **DefaultErrorHandler** | Error handler của Spring Kafka | Điều phối seek/retry/recover cho listener exception và có thể chuyển record sang DLT bằng recoverer. |
| **@DirtiesContext** | Đánh dấu context test bị bẩn | Yêu cầu Spring đóng và không tái sử dụng test context; hữu ích khi test thay đổi global state nhưng làm suite chậm hơn. |
| **Dirty checking** | Phát hiện entity thay đổi | Persistence provider so sánh managed entity và phát SQL update khi flush, dù code không gọi repository `save()` lại. |
| **DispatcherServlet** | Bộ điều phối request MVC | Front controller nhận request Servlet, tìm handler, gọi controller và render response. |
| **Distributed lock** | Khóa dùng chung giữa nhiều node | Cơ chế cho phép một node giữ quyền thực hiện critical section; không tự tạo retry, durability hoặc idempotency cho nghiệp vụ. |
| **Distributed tracing** | Truy vết phân tán | Liên kết span qua nhiều service bằng trace context để tìm đường đi và điểm chậm/lỗi của một request. |
| **DTO (Data Transfer Object)** | Object truyền dữ liệu | Model dành cho boundary API/service, giúp tách contract bên ngoài khỏi entity và persistence model. |

## E

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **EntityGraph** | Đồ thị fetch entity | Cách khai báo association cần tải trong một query để kiểm soát lazy/eager fetch và giảm N+1. |
| **Environment** | Môi trường cấu hình | Tập hợp property source và profile active mà Spring dùng để tra giá trị cấu hình. |
| **Error budget** | Ngân sách lỗi | Phần mức lỗi/không sẵn sàng được phép trong SLO window, dùng để cân bằng tốc độ thay đổi với độ tin cậy. |
| **Event envelope** | Vỏ metadata của event | Cấu trúc chung chứa `eventId`, type, version, timestamp, trace/correlation và payload nghiệp vụ. |
| **Event loop** | Vòng lặp xử lý sự kiện | Một số ít thread xử lý nhiều I/O non-blocking; tác vụ blocking trên event loop có thể làm nghẽn toàn bộ luồng. |
| **Event Publication Registry** | Sổ theo dõi event publication | Cơ chế Spring Modulith ghi publication và trạng thái listener để phát hiện/hoàn thành event delivery chưa xong. |
| **Exactly-Once Semantics (EOS)** | Ngữ nghĩa đúng một lần | Trong Kafka transaction, read–process–write Kafka có thể commit nguyên tử; không tự bao phủ DB/API bên ngoài. |
| **ExecutionContext** | Trạng thái restart của Batch | Kho key/value được Spring Batch lưu cùng job/step execution để reader hoặc tasklet tiếp tục từ checkpoint sau khi dừng. |
| **Executor / ThreadPoolTaskExecutor** | Bộ thực thi tác vụ | Quản lý thread, queue, rejection và context cho `@Async`; cần sizing và shutdown theo workload. |
| **Expand–migrate–contract** | Mở rộng–chuyển dữ liệu–thu hẹp | Chiến lược migration tương thích ngược: thêm cấu trúc mới, chuyển code/data, rồi mới xóa cấu trúc cũ. |
| **Externalized configuration** | Cấu hình bên ngoài ứng dụng | Đưa config ra file, environment variable, command line hoặc secret store để một artifact chạy ở nhiều môi trường. |

## F

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Fetch join** | Join và tải association | JPQL/HQL join đồng thời nạp relation trong cùng query, thường dùng để tránh N+1 theo use case cụ thể. |
| **Filter** | Bộ lọc request/response | Thành phần chạy quanh request ở tầng Servlet hoặc WebFlux, phù hợp concern thấp như correlation ID hoặc security chain. |
| **Flaky test** | Test lúc đậu lúc rớt | Test cho kết quả không ổn định do timing, shared state, network, clock hoặc race condition thay vì thay đổi code. |
| **Flux** | Luồng reactive 0..N phần tử | Publisher Reactor có thể phát không, một hoặc nhiều phần tử và tín hiệu hoàn tất/lỗi. |
| **Flyway** | Công cụ migration database | Quản lý thay đổi schema bằng migration có version/repeatable và bảng lịch sử. |

## G

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **GraalVM Native Image** | Binary native biên dịch trước | Biên dịch ứng dụng Java thành executable native để startup nhanh/footprint thấp, đổi lại build và reflection/resource config phức tạp hơn. |
| **Graceful shutdown** | Dừng ứng dụng có trật tự | Ngừng nhận request mới, chờ request/task đang chạy trong thời hạn rồi đóng resource và process. |

## H

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **HandlerInterceptor** | Bộ chặn handler MVC | Hook trước/sau controller trong Spring MVC, thường dùng cho logging, locale hoặc authorization bổ sung. |
| **HealthIndicator** | Thành phần đóng góp health | Kiểm tra một dependency/component và đóng góp trạng thái/detail vào health endpoint/group. |
| **Heap** | Bộ nhớ object của JVM | Vùng bộ nhớ GC quản lý cho object; sizing phải chừa RAM cho metaspace, thread stack, direct buffer và page cache. |
| **HikariCP** | Pool kết nối JDBC | Connection pool mặc định phổ biến trong Spring Boot, cần sizing theo database và workload thay vì số thread tùy ý. |
| **Histogram** | Phân phối metric theo bucket | Cấu trúc ghi phân bố latency/size để tính percentile phía backend, đổi lại tăng time series và chi phí. |
| **HTTP Service Client** | HTTP client từ interface | Khai báo interface bằng HTTP exchange annotation rồi Spring tạo proxy client dựa trên `RestClient` hoặc `WebClient`. |

## I

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Idempotency key** | Khóa chống xử lý lặp | ID ổn định giúp server nhận biết request retry và tránh tạo hiệu ứng nghiệp vụ trùng. |
| **Inbox pattern** | Hộp thư chống xử lý trùng | Consumer ghi `eventId` đã xử lý trong cùng transaction nghiệp vụ để duplicate delivery không tạo hiệu ứng lặp. |
| **ItemProcessor** | Bộ biến đổi item của Batch | Nhận item từ reader, kiểm tra/biến đổi rồi trả item cho writer; trả `null` có nghĩa filter item chứ không phải skip lỗi. |
| **ItemReader** | Bộ đọc item của Batch | Cung cấp từng item từ file, database hoặc nguồn khác; reader restartable phải lưu vị trí đọc trong `ExecutionContext`. |
| **ItemWriter** | Bộ ghi item của Batch | Ghi một chunk item ra database, file hoặc hệ thống ngoài; cần xét transaction và idempotency khi retry/restart. |

## J

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Job** | Định nghĩa công việc Batch | Luồng gồm một hoặc nhiều step, mô tả cách xử lý nhưng không đại diện cho một lần chạy cụ thể. |
| **JobExecution** | Một lần thử chạy job | Bản ghi trạng thái, thời gian, lỗi và kết quả của một lần chạy `JobInstance`; một instance có thể có nhiều execution khi restart. |
| **JobInstance** | Phiên bản nghiệp vụ của job | Được xác định bởi job name và identifying `JobParameters`; dùng cùng identity để restart công việc thất bại. |
| **JobOperator** | API vận hành Spring Batch | Facade dùng để start, stop, restart và truy vấn job operation; hướng API chính trong Spring Batch 6. |
| **JobParameters** | Tham số nhận diện/làm input cho job | Giá trị truyền vào lúc launch; identifying parameter tham gia xác định `JobInstance`, non-identifying parameter thì không. |
| **JobRepository** | Kho metadata Spring Batch | Lưu job/step execution, status và execution context để kiểm soát concurrency và hỗ trợ restart. |
| **JPA (Jakarta Persistence)** | Chuẩn ánh xạ object–relational | Specification định nghĩa entity, persistence context, query và transaction; Hibernate là một implementation phổ biến. |
| **JVM** | Máy ảo Java | Runtime chạy bytecode, quản lý heap/GC/thread/JIT; container limit và workload quyết định cách tuning thực tế. |
| **JWK Set** | Tập khóa JSON Web Key | Endpoint/tài liệu chứa public key để resource server xác minh chữ ký JWT và xoay khóa theo `kid`. |
| **JWT (JSON Web Token)** | Token JSON có chữ ký | Chuỗi claim được ký để resource server xác minh tính toàn vẹn; không tự mã hóa nội dung và cần kiểm tra issuer/audience/expiry. |

## K

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **@KafkaListener** | Listener nhận record Kafka | Annotation tạo listener container, poll record và gọi method theo group, topic, ack/error configuration. |
| **Kafka partition** | Phân vùng Kafka | Đơn vị ordering, parallelism và assignment; thứ tự chỉ được bảo đảm trong từng partition. |
| **KafkaTemplate** | Client gửi Kafka của Spring | Abstraction producer bất đồng bộ để serialize và gửi record, hỗ trợ callback và Kafka transaction khi cấu hình. |
| **Kubernetes probe** | Probe sức khỏe cho Kubernetes | Liveness quyết định restart, readiness quyết định route traffic; startup probe bảo vệ ứng dụng khởi động chậm. |

## L

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **L1 cache** | Cache cấp một | Persistence-context cache gắn với một `EntityManager`/transaction; luôn tồn tại trong JPA. |
| **L2 cache** | Cache cấp hai | Cache tùy chọn dùng chung giữa nhiều persistence context; cần chiến lược invalidation và consistency phù hợp. |
| **Layered JAR** | JAR chia layer | Sắp dependency, loader và application class thành layer để container cache phần ít thay đổi giữa các build. |
| **Lazy initialization** | Khởi tạo bean khi cần | Trì hoãn tạo bean đến lần sử dụng đầu để giảm startup, đổi lại lỗi cấu hình có thể xuất hiện muộn. |
| **Liquibase** | Công cụ migration database | Quản lý schema bằng changelog XML/YAML/JSON/SQL, hỗ trợ changeset, checksum và rollback có khai báo. |
| **Liveness probe** | Kiểm tra tiến trình còn sống | Tín hiệu cho orchestrator biết ứng dụng bị kẹt và có nên restart; không nên phụ thuộc downstream dễ lỗi. |

## M

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Micrometer** | Facade metric/observation | API instrumentation trung lập backend mà Spring Boot dùng cho metric và observation. |
| **Misfire policy** | Chính sách xử lý lịch bị lỡ | Quyết định scheduler làm gì khi trigger đáng lẽ chạy trong lúc ứng dụng dừng hoặc không đủ tài nguyên. |
| **@MockitoBean** | Thay bean bằng Mockito mock trong test | Annotation Spring Framework ghi đè bean trong test context; là hướng thay thế hiện đại cho `@MockBean`. |
| **MockMvc** | Test Spring MVC không mở socket | Gửi request giả lập qua `DispatcherServlet` và filter chain trong test context. |
| **Mono** | Luồng reactive 0..1 phần tử | Publisher Reactor phát tối đa một value hoặc chỉ tín hiệu hoàn tất/lỗi. |
| **Multi-datasource** | Nhiều nguồn dữ liệu | Ứng dụng cấu hình nhiều `DataSource`/repository/transaction manager cho database hoặc workload khác nhau. |
| **Multi-level cache** | Cache nhiều tầng | Kết hợp local L1 tốc độ cao với distributed L2; cần đồng bộ invalidation và tránh mỗi tầng giữ TTL/serialization mâu thuẫn. |
| **MultipleBagFetchException** | Lỗi fetch nhiều bag | Hibernate từ chối join-fetch đồng thời nhiều collection dạng bag vì tích Descartes không thể ghép phần tử đáng tin cậy. |

## N

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **N+1 query problem** | Lỗi truy vấn 1 cộng N | Một query tải danh sách rồi phát sinh thêm một query cho từng phần tử, làm latency và tải database tăng mạnh. |

## O

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **OAuth 2.0** | Khung ủy quyền | Protocol framework cấp access token để client truy cập resource theo scope; không phải format token cụ thể. |
| **OAuth2 Resource Server** | Server bảo vệ tài nguyên | API xác minh access token dạng JWT hoặc opaque token rồi áp authorization. |
| **Opaque token** | Token không tự mô tả | Chuỗi token cần introspection tại authorization server hoặc cache an toàn để biết claim và trạng thái active. |
| **OpenAPI** | Đặc tả API HTTP | Mô tả endpoint, schema, parameter, response và security để sinh tài liệu/client hoặc kiểm tra contract. |
| **Open projection** | Projection mở | Projection dùng SpEL/default computation; có thể buộc framework lấy nhiều dữ liệu hơn và khó tối ưu SQL. |
| **Orchestration** | Saga có bộ điều phối | Coordinator ra lệnh cho từng bước, theo dõi state/timeout và kích hoạt compensation khi cần. |
| **OSIV (Open Session in View)** | Mở persistence context tới web view | Giữ session qua tầng web để lazy load sau service; tiện nhưng dễ che N+1 và phát query ngoài transaction nghiệp vụ. |
| **OTLP (OpenTelemetry Protocol)** | Giao thức xuất telemetry | Giao thức HTTP/gRPC để gửi trace, metric hoặc log tới OpenTelemetry Collector/backend. |

## P

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Partitioning** | Chia một step thành nhiều phần | Manager tạo các `ExecutionContext` không giao nhau để nhiều worker step xử lý song song và theo dõi trạng thái từng phần. |
| **Persistence context** | Ngữ cảnh quản lý entity | Theo dõi identity và thay đổi của entity; flush đồng bộ thay đổi xuống database trong transaction phù hợp. |
| **Pinning** | Virtual thread bị ghim vào carrier | Một số vùng synchronized/native giữ virtual thread trên carrier khi blocking, làm giảm lợi ích concurrency. |
| **Preflight request** | Request kiểm tra CORS | Request `OPTIONS` do trình duyệt gửi trước để hỏi server có cho phép method/header/origin dự kiến hay không. |
| **ProblemDetail** | Mô hình lỗi HTTP chuẩn | Kiểu Spring biểu diễn RFC 9457 với `type`, `title`, `status`, `detail`, `instance` và extension fields. |
| **Profile** | Nhóm cấu hình theo môi trường | Điều kiện kích hoạt bean/config cho môi trường hoặc use case; không nên dùng để giấu mọi biến thể nghiệp vụ. |
| **Profile group** | Nhóm profile | Tên profile logic kích hoạt nhiều profile con cùng lúc. |
| **Projection** | Hình chiếu dữ liệu | Chỉ lấy các field cần thiết vào interface/DTO thay vì luôn materialize toàn bộ entity. |
| **Prometheus** | Hệ thống metric time-series | Scrape metric endpoint, lưu time series và đánh giá rule/alert; label cardinality phải được kiểm soát. |
| **PropertySource** | Nguồn property | Nguồn key/value có thứ tự ưu tiên trong `Environment`, như file, system property, environment variable hoặc command line. |
| **Publisher Confirm/Return** | Xác nhận publish RabbitMQ | Confirm cho biết broker nhận publish; return báo message mandatory không route được tới queue. |

## Q

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Quartz** | Scheduler có trạng thái | Thư viện lập lịch hỗ trợ job/trigger động, calendar, misfire và JDBC job store cho môi trường cluster. |
| **Querydsl** | DSL truy vấn có kiểu | Thư viện tạo query type-safe bằng metamodel sinh từ entity, hữu ích cho điều kiện động phức tạp. |
| **Quorum queue** | Queue nhân bản theo quorum | Loại RabbitMQ queue dùng Raft để replicate và failover, đổi lại tốn tài nguyên hơn classic queue. |

## R

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **R2DBC** | Kết nối database reactive | SPI truy cập relational database theo mô hình non-blocking; không phải JPA reactive. |
| **R2dbcEntityTemplate** | Template dữ liệu R2DBC | API Spring Data R2DBC cho query/update mapping có kiểu khi repository method không đủ linh hoạt. |
| **RabbitTemplate / @RabbitListener** | API gửi/nhận RabbitMQ | `RabbitTemplate` publish message; `@RabbitListener` tạo consumer container nhận từ queue. |
| **Rate limiting** | Giới hạn tốc độ | Hạn chế request theo user/client/key và khoảng thời gian để bảo vệ capacity và fairness. |
| **Reactive programming** | Lập trình luồng bất đồng bộ | Mô hình xử lý signal/data stream không blocking, có composition và backpressure. |
| **Reactive transaction** | Giao dịch theo Reactor context | Transaction gắn với subscription/context thay vì `ThreadLocal`; publisher phải nằm trong cùng reactive chain. |
| **Readiness probe** | Kiểm tra sẵn sàng nhận traffic | Tín hiệu cho orchestrator biết instance có nên nằm trong load balancer hay tạm thời bị loại. |
| **Read/write split** | Tách luồng đọc và ghi | Gửi write tới primary và một phần read tới replica; phải chấp nhận replication lag và read-after-write inconsistency. |
| **RED method** | Phương pháp quan sát request | Theo dõi Rate, Errors và Duration cho request-driven service để phát hiện tải, lỗi và latency. |
| **@RefreshScope** | Scope tái tạo bean khi refresh | Cơ chế Spring Cloud cho phép một số bean nhận config mới; không tương thích mọi kiểu bean/AOT và không tự bảo đảm consistency. |
| **Relaxed binding** | Bind tên linh hoạt | Cho phép nhiều cách viết property như kebab-case, camelCase và environment variable ánh xạ về cùng field. |
| **Replica lag** | Độ trễ bản sao database | Khoảng thời gian/LSN replica chậm hơn primary, khiến read replica có thể chưa thấy write vừa commit. |
| **Repository** | Abstraction truy cập dữ liệu | Interface Spring Data cung cấp CRUD/query composition và được framework tạo implementation khi chạy. |
| **REST** | Phong cách kiến trúc tài nguyên HTTP | Thiết kế API quanh resource, representation, stateless interaction và semantics chuẩn của HTTP. |
| **RestClient** | HTTP client đồng bộ | Fluent synchronous client của Spring Framework dành cho luồng imperative. |
| **RFC 9457** | Chuẩn Problem Details | Chuẩn mô tả response lỗi HTTP có cấu trúc thống nhất cho client và server. |
| **Routing DataSource** | DataSource định tuyến | Chọn datasource tại runtime theo context read/write/tenant; quyết định route phải xảy ra trước khi lấy connection/transaction. |
| **Runtime hints / reachability metadata** | Metadata cho native image | Khai báo reflection, resource, proxy và serialization mà static analysis không tự suy ra. |

## S

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Saga** | Giao dịch phân tán bằng chuỗi bước | Mỗi service commit local transaction và dùng compensation khi bước sau lỗi thay vì một ACID transaction xuyên service. |
| **SBOM (Software Bill of Materials)** | Danh mục thành phần phần mềm | Liệt kê dependency/component và version trong artifact/image để quản trị lỗ hổng và chuỗi cung ứng. |
| **Scheduler** | Bộ kích hoạt công việc theo thời gian | Thành phần quyết định khi nào gọi tác vụ; không đồng nghĩa với engine xử lý Batch hoặc workflow bền vững. |
| **Schema evolution** | Tiến hóa schema message | Thay đổi cấu trúc event theo compatibility rule và version để producer/consumer có thể deploy độc lập. |
| **Schema migration** | Di trú schema database | Thay đổi database theo version có lịch sử, thứ tự và quy trình deploy/rollback được kiểm soát. |
| **Server-Sent Events (SSE)** | Luồng sự kiện một chiều qua HTTP | Server giữ kết nối HTTP và liên tục đẩy text event xuống browser/client; client không gửi message ngược trên cùng stream. |
| **Service connection** | Kết nối dịch vụ cho test/dev | Spring Boot lấy connection detail từ container hoặc development service và tự cấu hình client/DataSource tương ứng. |
| **Servlet stack** | Ngăn xếp web Servlet | Mô hình request-per-thread/blocking phổ biến của Spring MVC trên Servlet container. |
| **ShedLock** | Khóa cho scheduled task | Thư viện phối hợp qua shared storage để chỉ một node thực hiện một lượt; node không lấy được khóa thường bỏ qua lượt đó. |
| **SLO (Service Level Objective)** | Mục tiêu mức dịch vụ | Mục tiêu đo được cho availability/latency/correctness trong một time window, làm cơ sở alert và error budget. |
| **SmartLifecycle** | Lifecycle có phase | Contract cho component cần auto-start/stop theo thứ tự phase khi context khởi động hoặc đóng. |
| **Smoke test** | Kiểm thử khói | Bộ test nhỏ xác nhận đường đi quan trọng nhất hoạt động sau build/deploy trước khi chạy kiểm tra sâu hơn. |
| **Span** | Một đoạn công việc trong trace | Ghi thời gian, status, attribute và quan hệ cha-con của một operation trong distributed trace. |
| **Specification** | Đặc tả điều kiện truy vấn | Spring Data JPA abstraction đóng gói predicate Criteria để tái sử dụng và kết hợp query động. |
| **SPI (Service Provider Interface)** | Giao diện mở rộng framework | Contract và cơ chế đăng ký để thư viện cung cấp implementation mà framework phát hiện khi chạy. |
| **SpringApplication** | Bộ khởi động Spring Boot | Chuẩn bị environment, tạo context, chạy lifecycle event và runner cho ứng dụng Boot. |
| **Spring Boot starter** | Gói dependency theo mục đích | Dependency descriptor gom các thư viện tương thích cho một capability như web, data hoặc security. |
| **Spring MVC** | Web framework Servlet | Framework web blocking dựa trên Servlet API, `DispatcherServlet`, controller và message converter. |
| **Step** | Một giai đoạn của Batch job | Đơn vị xử lý tuần tự hoặc song song, thường là chunk-oriented step hoặc tasklet step. |
| **StepExecution** | Một lần thử chạy step | Metadata trạng thái, read/write/filter/skip count và context của một step trong một `JobExecution`. |

## T

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Tasklet** | Tác vụ một bước của Spring Batch | Mô hình step thực hiện một đơn vị công việc như gọi procedure, xóa file hoặc chạy script thay vì read–process–write item. |
| **Testcontainers** | Thư viện chạy dependency bằng container | Khởi động database/broker thật trong container cho integration test với lifecycle và isolation có kiểm soát. |
| **TestContext** | Hạ tầng context của Spring Test | Quản lý việc nạp, cache, inject dependency và listener cho test sử dụng Spring context. |
| **Test double** | Đối tượng thay thế khi test | Tên chung cho dummy, fake, stub, spy và mock dùng để thay dependency thật theo mục tiêu test. |
| **Test fidelity** | Mức giống production của test | Mức environment/dependency/behavior trong test phản ánh hệ thống thực tế; fidelity cao thường tốn thời gian hơn. |
| **Test pyramid** | Kim tự tháp kiểm thử | Phân bổ nhiều test nhỏ nhanh ở đáy và ít test tích hợp/E2E đắt hơn ở trên. |
| **Test slice** | Lát cắt kiểm thử | Chỉ nạp bean/auto-configuration của một tầng như MVC hoặc JPA để test nhanh và cô lập hơn full context. |
| **Token bucket** | Thuật toán xô token | Mỗi request tiêu một token; token được nạp lại theo tốc độ định trước để cho phép burst nhỏ nhưng giới hạn tải dài hạn. |
| **Transaction** | Giao dịch | Ranh giới atomicity/consistency cho thao tác dữ liệu; proxy Spring quản lý theo propagation và rollback rule. |
| **@TransactionalEventListener** | Listener gắn với transaction phase | Chạy listener theo phase như AFTER_COMMIT; không tự biến việc gọi API/message broker thành delivery bền vững. |
| **TransactionalOperator** | Toán tử transaction reactive | Bao một reactive chain trong transaction R2DBC mà không dựa vào thread-bound transaction. |
| **Transactional outbox** | Outbox giao dịch | Ghi dữ liệu nghiệp vụ và event vào cùng database transaction rồi relay/CDC phát event ra broker. |
| **Trigger** | Điều kiện kích hoạt scheduler | Mô tả thời điểm hoặc lịch làm một job được fire; trong Quartz, trigger tách biệt khỏi định nghĩa `JobDetail`. |

## V

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **Validation** | Kiểm tra dữ liệu | Xác nhận input/config thỏa constraint trước khi đi sâu vào xử lý nghiệp vụ. |
| **Vault** | Kho bí mật | Hệ thống quản lý secret tập trung, có policy, audit và khả năng cấp credential động. |
| **Virtual thread** | Luồng ảo | Thread nhẹ do JVM quản lý, giúp code blocking đạt concurrency cao hơn nhưng không làm I/O trở thành non-blocking. |

## W

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|-----------|------------------|-----------------|
| **WebClient** | HTTP client reactive | Client non-blocking của Spring WebFlux, trả `Mono`/`Flux` và vẫn có thể dùng trong ứng dụng Spring MVC. |
| **WebFlux** | Web framework reactive | Framework web non-blocking của Spring dựa trên Reactive Streams, hỗ trợ annotated và functional endpoint. |
| **WebTestClient** | Client kiểm thử WebFlux/MVC | Fluent test client có thể bind trực tiếp application context hoặc gọi live server qua HTTP. |
| **WireMock** | HTTP stub server | Server giả lập HTTP để kiểm soát response, verify request và mô phỏng lỗi/latency của downstream. |

---

> Glossary được dùng chung cho toàn bộ nhóm tài liệu Spring Boot và sẽ tiếp tục được mở rộng khi xuất hiện thuật ngữ mới.
