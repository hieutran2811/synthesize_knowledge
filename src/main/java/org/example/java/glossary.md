# 📖 Glossary – Bảng thuật ngữ Java

> Bảng tra cứu nhanh các thuật ngữ tiếng Anh xuất hiện trong package `java`. Sắp xếp A–Z.
> Quy ước: **Thuật ngữ** | Nghĩa tiếng Việt | Giải thích ngắn gọn dễ hiểu.

---

## A

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **ABA problem** | Vấn đề A–B–A | Giá trị đổi từ A sang B rồi về A khiến CAS tưởng trạng thái chưa từng thay đổi. |
| **Access modifier** | Phạm vi truy cập | Từ khóa `private`, `protected`, `public` hoặc package-private quy định code nào được dùng một member. |
| **Adapter Pattern** | Mẫu bộ chuyển đổi | Bọc và dịch một interface hiện có sang interface mà client mong đợi. |
| **ADT (Algebraic Data Type)** | Kiểu dữ liệu đại số | Model một giá trị bằng các cách kết hợp kiểu; sealed hierarchy thường biểu diễn lựa chọn “A hoặc B”. |
| **Age (object age)** | Tuổi của object | Số lần một object sống sót qua các đợt dọn rác Young GC. Đủ "già" thì được chuyển sang Old Gen. |
| **Aggregate root** | Gốc aggregate | Entity làm cổng bảo vệ invariant và điều phối thay đổi bên trong một aggregate. |
| **Aggregator POM** | POM tổng hợp | POM khai báo `<modules>` để gom nhiều Maven module vào cùng một reactor build. |
| **Allocation** | Cấp phát (bộ nhớ) | Việc xin một chỗ trong bộ nhớ để chứa object mới (`new`). |
| **Allowlist** | Danh sách cho phép | Chỉ chấp nhận class, subtype hoặc giá trị đã được liệt kê rõ; mọi trường hợp khác bị từ chối mặc định. |
| **Anemic Domain Model** | Mô hình miền thiếu hành vi | Domain object chủ yếu chứa getter/setter trong khi business rule bị đẩy hết ra service. |
| **Anti-pattern** | Mẫu giải pháp phản tác dụng | Cách làm lặp lại có vẻ hợp lý nhưng tạo hậu quả lớn hơn lợi ích trong bối cảnh sử dụng. |
| **ArrayDeque** | Hàng đợi hai đầu dạng mảng | Deque dựa trên circular buffer, thường phù hợp hơn LinkedList cho queue/deque local. |
| **ArrayList** | Danh sách dựa trên mảng | List có truy cập index O(1), thêm cuối amortized O(1) và cần dịch phần tử khi chèn giữa. |
| **Artifact** | Sản phẩm build | File hoặc metadata được định danh bằng tọa độ dependency, thường là JAR, WAR hoặc POM. |
| **Atomic** | Nguyên tử / bất khả chia cắt | Thao tác chạy "một phát ăn ngay", không thể bị xen giữa chừng → không lo dữ liệu sai khi nhiều luồng cùng chạy. |
| **AtomicStampedReference / AtomicMarkableReference** | Tham chiếu nguyên tử kèm phiên bản/dấu | Ghép reference với stamp hoặc boolean mark để CAS phát hiện thêm trạng thái như ABA. |
| **AutoCloseable** | Tài nguyên có thể tự đóng | Contract có method `close()` để try-with-resources tự giải phóng resource khi rời block. |

## B

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Backpressure** | Điều tiết ngược | Consumer báo lượng dữ liệu nó xử lý được để producer không đẩy nhanh hơn sức chứa. |
| **Binary heap** | Heap nhị phân | Cây gần hoàn chỉnh lưu trong mảng, duy trì quan hệ cha–con để lấy min/max ở gốc. |
| **BlockingQueue** | Hàng đợi có thể chặn | Queue thread-safe khiến producer chờ khi đầy và consumer chờ khi rỗng. |
| **BOM (Bill of Materials)** | Bảng kê phiên bản | POM/platform tập trung version của một họ artifact; không tự thêm dependency vào project. |
| **Bridge Pattern** | Mẫu cầu nối | Tách abstraction và implementation thành hai hierarchy có thể phát triển và kết hợp độc lập. |
| **Build cache** | Bộ nhớ đệm build | Tái sử dụng output của task có cùng input thay vì thực thi lại. |
| **Build tool** | Công cụ dựng dự án | Tự động hóa compile, test, package, quản lý dependency và publish artifact. |
| **Bulkhead Pattern** | Mẫu vách ngăn | Cô lập quota tài nguyên để lỗi ở một dependency không làm cạn tài nguyên của phần khác. |
| **Bytecode** | Mã trung gian Java | Lệnh trong file `.class`, được JVM thông dịch hoặc JIT biên dịch thành mã máy. |

## C

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Call stack** | Ngăn xếp lời gọi | Chuỗi stack frame từ method hiện tại ngược về các method đã gọi nó; exception được truyền ngược dọc chuỗi này. |
| **Canonical constructor** | Constructor chuẩn của record | Constructor nhận đầy đủ component theo đúng thứ tự và là nơi duy trì invariant của record. |
| **Carrier thread** | Luồng vận chuyển | Platform thread tạm thời chạy một virtual thread trên CPU. |
| **CAS (Compare-And-Swap)** | So sánh rồi hoán đổi | Cập nhật nguyên tử chỉ khi giá trị hiện tại vẫn bằng giá trị kỳ vọng; có thể phải retry khi contention. |
| **Checked exception** | Ngoại lệ được compiler kiểm tra | Exception mà caller phải `catch` hoặc khai báo tiếp bằng `throws`; đây là quyết định thiết kế API, không đồng nghĩa luôn phục hồi được. |
| **Circuit Breaker Pattern** | Mẫu cầu dao | Ngắt tạm lời gọi tới dependency đang lỗi để fail fast và cho hệ thống thời gian hồi phục. |
| **Circular buffer** | Bộ đệm vòng | Mảng mà con trỏ đầu/cuối chạy vòng để tái sử dụng chỗ trống, nền tảng của ArrayDeque. |
| **ClassLoader** | Bộ nạp lớp | Thành phần tìm, kiểm tra và đưa bytecode của class vào JVM. |
| **Classpath** | Đường dẫn lớp/thư viện | Tập vị trí JVM/compiler dùng để tìm class và resource ở một giai đoạn build hoặc runtime. |
| **Code Cache** | Bộ nhớ đệm mã máy | Vùng chứa native code do JIT tạo ra; đầy vùng này có thể làm JVM ngừng biên dịch thêm. |
| **Cohesion** | Độ gắn kết | Mức độ các field và method trong một module cùng phục vụ một mục đích liên quan. |
| **Colored pointers** | Con trỏ "tô màu" | Kỹ thuật của ZGC: nhét vài bit trạng thái GC vào ngay địa chỉ con trỏ để biết object đã xử lý hay chưa. |
| **Compact / Mark-Compact** | Dồn nén | Sau khi đánh dấu object sống, dồn chúng về một phía heap cho liền mạch → hết phân mảnh. |
| **Comparable** | Thứ tự tự nhiên | Interface để chính class định nghĩa một cách so sánh qua `compareTo`. |
| **Comparator** | Bộ so sánh bên ngoài | Object/lambda định nghĩa ordering thay thế hoặc bổ sung cho natural ordering. |
| **CompletableFuture** | Kết quả bất đồng bộ có thể ghép | Future hỗ trợ pipeline transform, combine, timeout và xử lý lỗi mà không phải block ở mỗi bước. |
| **Composite Pattern** | Mẫu hợp thể | Tổ chức object thành cây và cho leaf/composite dùng chung một contract. |
| **Composition** | Hợp thành | Object chứa và ủy quyền cho dependency theo quan hệ “có một”, thay vì kế thừa theo quan hệ “là một”. |
| **Concurrency** | Tính đồng thời | Nhiều task cùng tiến triển trong một khoảng thời gian, không nhất thiết chạy cùng một thời điểm. |
| **Concurrent** | Chạy song song (đồng thời) | GC làm việc *cùng lúc* với ứng dụng thay vì bắt ứng dụng dừng lại. Đối lập với stop-the-world. |
| **ConcurrentHashMap** | Map đồng thời | Map thread-safe với operation nguyên tử và đồng thời cao hơn map khóa toàn cục. |
| **Condition** | Điều kiện chờ của lock | Hàng chờ gắn với `Lock`, cho phép thread `await()` và được thread khác `signal()`. |
| **Configuration cache** | Bộ đệm cấu hình Gradle | Tái sử dụng kết quả giai đoạn cấu hình khi build và plugin đáp ứng yêu cầu tương thích. |
| **Constructor chaining** | Chuỗi gọi constructor | Quá trình constructor lớp con gọi constructor lớp cha trước khi khởi tạo phần riêng của nó. |
| **Contention** | Tranh chấp tài nguyên | Nhiều thread cùng cạnh tranh lock, CPU cache line hoặc tài nguyên hữu hạn. |
| **Continuation** | Phần việc có thể tạm dừng/tiếp tục | Trạng thái thực thi được JVM lưu lại khi virtual thread unmount và khôi phục khi chạy tiếp. |
| **Copying (algorithm)** | Thuật toán sao chép | Dọn rác bằng cách copy object còn sống sang vùng mới, rồi xóa sạch vùng cũ — nhanh, không phân mảnh. |
| **CopyOnWriteArrayList** | List sao chép khi ghi | Collection phù hợp đọc nhiều ghi ít; mỗi lần ghi tạo mảng snapshot mới cho iterator. |
| **CountDownLatch** | Chốt đếm ngược | Cho một hay nhiều thread chờ đến khi bộ đếm một chiều giảm về 0. |
| **CQRS** | Phân tách lệnh và truy vấn | Tách model/path ghi khỏi model/path đọc để mỗi phía tối ưu theo nhu cầu riêng. |
| **Custom serializer / deserializer** | Bộ ghi/đọc dữ liệu tùy biến | Code tự định nghĩa cách một type được chuyển sang hoặc dựng từ định dạng ngoài; phải kiểm tra input như tại một trust boundary. |
| **CyclicBarrier** | Hàng rào tái sử dụng | Cho một nhóm thread chờ nhau tại checkpoint rồi cùng tiếp tục sang vòng kế tiếp. |

## D

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Data binding** | Ánh xạ dữ liệu | Tự động chuyển giữa cấu trúc dữ liệu ngoài như JSON và object/DTO Java. |
| **Deadlock** | Bế tắc khóa | Các thread giữ tài nguyên và chờ lẫn nhau theo vòng nên không thread nào tiến tiếp. |
| **Decorator Pattern** | Mẫu trang trí | Bọc object để bổ sung hành vi trong khi vẫn giữ contract tương thích với object được bọc. |
| **Defensive copy** | Bản sao phòng vệ | Sao chép dữ liệu mutable khi nhận hoặc trả ra để caller không sửa được state nội bộ. |
| **Delegation** | Ủy quyền | Object chuyển một phần công việc cho object cộng tác thông qua method của dependency. |
| **Denial of Service (DoS)** | Từ chối dịch vụ | Làm cạn CPU, bộ nhớ, thread hoặc tài nguyên khác khiến hệ thống không phục vụ được request hợp lệ. |
| **Deoptimization** | Hủy tối ưu | JVM bỏ native code tối ưu khi giả định profiling không còn đúng, rồi quay lại thông dịch/biên dịch lại. |
| **Dependency Injection (DI)** | Tiêm phụ thuộc | Truyền dependency từ bên ngoài vào object thay vì để object tự khởi tạo dependency. |
| **Dependency Inversion Principle (DIP)** | Nguyên lý đảo ngược phụ thuộc | Module chính sách và chi tiết cùng phụ thuộc abstraction; chi tiết triển khai hướng về contract. |
| **Dependency locking** | Khóa phiên bản phụ thuộc | Ghi lại version đã resolve để các lần build sau không tự thay đổi dependency ngoài ý muốn. |
| **Dependency mediation** | Hòa giải phiên bản phụ thuộc | Quy tắc chọn một version khi dependency graph yêu cầu nhiều version của cùng module. |
| **Dependency scope** | Phạm vi phụ thuộc | Quy định dependency xuất hiện trên compile/test/runtime classpath và có truyền tiếp hay không. |
| **Deserialization** | Giải tuần tự hóa | Dựng lại dữ liệu hoặc object từ chuỗi byte/văn bản; input phải được xem là chưa tin cậy tại boundary. |
| **Double logging** | Ghi log trùng lỗi | Cùng một exception bị log ở nhiều layer rồi ném tiếp, tạo nhiều bản ghi cho một sự cố và làm nhiễu cảnh báo. |
| **Downcasting** | Ép kiểu xuống | Ép reference từ type cha về type con; cần kiểm tra vì có thể gây `ClassCastException`. |
| **DTO (Data Transfer Object)** | Đối tượng truyền dữ liệu | Object dùng để mang dữ liệu giữa các tầng hoặc qua API, thường không chứa business logic phức tạp. |
| **Dynamic dispatch** | Phân phối động | JVM chọn overridden instance method theo kiểu thực của object tại runtime. |

## E

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Eden** | Vườn địa đàng (khu sinh) | Vùng trong Young Gen nơi mọi object mới `new` được đặt vào đầu tiên. |
| **Eligible for GC** | Đủ điều kiện bị dọn | Object không còn ai tham chiếu tới → GC được phép thu hồi. |
| **Encapsulation** | Đóng gói | Gom state và behavior vào class, đồng thời kiểm soát cách code bên ngoài tương tác với chúng. |
| **EnumMap** | Map theo enum | Map dùng mảng/index theo enum key, thường gọn và nhanh hơn HashMap tương ứng. |
| **EnumSet** | Set theo enum | Set biểu diễn enum bằng bit vector, hiệu quả khi tập phần tử thuộc cùng một enum type. |
| **Error** | Lỗi nghiêm trọng ngoài luồng xử lý thông thường | Nhánh `Throwable` thường báo vấn đề JVM/môi trường mà ứng dụng không nên bắt rộng rồi tiếp tục như bình thường. |
| **Event Sourcing** | Lưu nguồn sự kiện | Lưu chuỗi domain event và dựng state bằng replay thay vì chỉ lưu state hiện tại. |
| **Exception** | Ngoại lệ | Object mô tả tình huống bất thường; khi được `throw`, nó làm JVM tìm `catch` phù hợp dọc call stack. |
| **Exception chaining / translation** | Nối chuỗi / chuyển đổi ngoại lệ | Đổi exception sang abstraction của layer hiện tại nhưng giữ exception gốc trong `cause` để truy vết. |
| **Exception swallowing** | Nuốt exception | Bắt lỗi nhưng xóa hoặc che tín hiệu thất bại mà không xử lý có chủ đích. |
| **Exchanger** | Điểm trao đổi hai thread | Cho đúng hai thread gặp nhau để hoán đổi object tại một điểm đồng bộ. |
| **ExecutorService** | Dịch vụ thực thi task | Quản lý việc submit, chạy và shutdown nhóm task tách biệt khỏi cách tạo thread. |
| **Exhaustive matching** | So khớp đầy đủ trường hợp | Compiler xác nhận `switch` đã xử lý mọi subtype/case có thể xảy ra. |
| **Externalizable** | Tuần tự hóa do class tự kiểm soát | Contract buộc class tự ghi/đọc toàn bộ serial form và có public no-arg constructor; linh hoạt nhưng dễ sai. |
| **Extrinsic state** | Trạng thái ngoại tại | Phần state phụ thuộc từng context sử dụng, được truyền vào flyweight thay vì lưu dùng chung. |

## F

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Facade Pattern** | Mẫu mặt tiền | Cung cấp API đơn giản cho một subsystem phức tạp mà không nhất thiết che kín API cấp thấp. |
| **Fail-fast iterator** | Iterator phát hiện sửa đổi | Iterator best-effort phát hiện structural modification ngoài iterator và thường ném `ConcurrentModificationException`. |
| **Field shadowing** | Che khuất field | Lớp con khai báo field trùng tên lớp cha; field được chọn theo kiểu khai báo, không đa hình. |
| **Finalization / finalize()** | Dọn dẹp cuối đời | Cơ chế cũ cho object tự dọn tài nguyên trước khi bị thu hồi — đã lỗi thời, thay bằng `Cleaner`. |
| **Flyweight Pattern** | Mẫu hạng ruồi | Chia sẻ intrinsic state giữa rất nhiều object nhỏ để giảm bộ nhớ. |
| **Fork/Join Framework** | Khung chia để trị song song | Chia task lớn thành task con, chạy trên ForkJoinPool rồi ghép kết quả. |
| **Fragmentation** | Phân mảnh bộ nhớ | Chỗ trống nằm rải rác xen kẽ, tổng thì đủ nhưng không khe nào đủ lớn cho object to. |
| **Full GC** | Dọn toàn bộ | Đợt dọn rác quét cả Young + Old + Metaspace; dừng ứng dụng lâu nhất → nên tránh. |
| **Functional interface** | Interface hàm | Interface chỉ có một abstract method, có thể được triển khai bằng lambda hoặc method reference. |
| **Future** | Kết quả sẽ có | Handle để chờ, lấy kết quả hoặc yêu cầu hủy một computation bất đồng bộ. |

## G

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **G1 GC (Garbage First)** | GC ưu tiên rác | GC chia heap thành nhiều "region" nhỏ, dọn region nhiều rác nhất trước. Mặc định từ Java 9. |
| **Gadget chain** | Chuỗi mảnh code có thể bị lợi dụng | Chuỗi hành vi từ các class sẵn có bị kích hoạt bởi input độc hại, có thể dẫn tới RCE hoặc tác động khác. |
| **Garbage Collection (GC)** | Thu gom rác bộ nhớ | Cơ chế tự động thu hồi bộ nhớ của object không còn dùng. |
| **GAV (Group–Artifact–Version)** | Tọa độ Maven | Bộ ba định danh một artifact và version cụ thể trong repository. |
| **GC Root** | Gốc dò tìm | Điểm gốc chắc chắn đang hoạt động (biến cục bộ, static, thread...) mà GC bắt đầu lần theo để xác định object nào còn sống. |
| **Generational GC** | GC phân thế hệ | Chia object theo "tuổi" (Young/Old) để dọn khu trẻ thường xuyên, khu già ít khi. |
| **God Object** | Đối tượng ôm đồm | Class tập trung quá nhiều trách nhiệm và nguồn thay đổi không liên quan. |
| **Gradle Daemon** | Tiến trình Gradle thường trú | JVM nền chạy build và giữ cache/trạng thái để giảm chi phí khởi động ở các lần sau. |
| **Gradle Platform** | Nền tảng ràng buộc version | Tập dependency constraints tham gia vào quá trình resolve version của Gradle. |
| **Gradle Wrapper** | Bộ chạy Gradle cố định version | Script và metadata giúp developer/CI tải, kiểm tra và chạy đúng Gradle version của dự án. |

## H

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Happens-before** | Quan hệ xảy-ra-trước có bảo đảm | Nếu A happens-before B thì mọi thay đổi bộ nhớ của A được bảo đảm hiển thị với B. |
| **HashMap** | Map dựa trên bảng băm | Map key-value lookup trung bình O(1), dùng bucket và có thể treeify collision trong Java 8+. |
| **HashSet** | Set dựa trên bảng băm | Set không trùng dựa trên HashMap, không bảo đảm thứ tự phần tử. |
| **Heap** | Vùng nhớ động | Khu bộ nhớ chính chứa tất cả object của chương trình. |
| **HotSpot** | (Tên JVM của Oracle) | Máy ảo Java phổ biến nhất, nơi các cơ chế GC/JIT này được triển khai. |
| **Humongous object** | Object khổng lồ | (Trong G1) object lớn hơn nửa một region, được xếp vào vùng riêng. |

## I

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Idempotency** | Tính lũy đẳng | Xử lý cùng request/event nhiều lần vẫn tạo hiệu ứng nghiệp vụ tương đương một lần. |
| **Idempotency key** | Khóa chống thực thi trùng | Mã ổn định gắn với một operation để lần retry cùng mã nhận lại kết quả cũ thay vì tạo hiệu ứng lần nữa. |
| **IdentityHashMap** | Map theo danh tính object | So sánh key bằng `==` và `System.identityHashCode()` thay vì `equals()`/`hashCode()`. |
| **Immutable** | Bất biến | Trạng thái không đổi sau khi tạo; với record, tính bất biến mặc định chỉ là bất biến nông. |
| **Information hiding** | Che giấu thông tin | Giấu chi tiết triển khai để caller chỉ phụ thuộc vào API cần thiết. |
| **InheritableThreadLocal** | Biến thread-local có kế thừa | Child thread nhận giá trị ban đầu từ parent lúc được tạo; không phù hợp để truyền context qua thread pool tái sử dụng. |
| **Inheritance** | Kế thừa | Class con nhận và mở rộng hành vi của class cha, tạo quan hệ subtype “is-a”. |
| **Inlining** | Chèn thân hàm tại điểm gọi | JIT thay lời gọi method bằng chính nội dung method để giảm overhead và mở thêm cơ hội tối ưu. |
| **Insecure deserialization** | Giải tuần tự hóa không an toàn | Dựng object từ dữ liệu không đáng tin mà thiếu giới hạn/allowlist, có thể kích hoạt gadget hoặc làm cạn tài nguyên. |
| **Interface Segregation Principle (ISP)** | Nguyên lý phân tách interface | Client chỉ nên phụ thuộc vào các operation nó thực sự sử dụng. |
| **Interpreter** | Trình thông dịch | Chạy bytecode từng lệnh; khởi động nhanh nhưng chậm hơn native code đã được JIT tối ưu. |
| **Interruption** | Tín hiệu yêu cầu dừng hợp tác | Cơ chế báo cho thread nên dừng/chuyển hướng; task phải kiểm tra hoặc xử lý `InterruptedException`. |
| **Intrinsic lock** | Khóa nội tại | Monitor gắn với object/class và được chiếm qua `synchronized`. |
| **Intrinsic state** | Trạng thái nội tại | Phần state ổn định, không phụ thuộc context và có thể chia sẻ giữa nhiều flyweight. |
| **Invariant** | Điều kiện bất biến nghiệp vụ | Quy tắc phải luôn đúng đối với state hợp lệ của object, ví dụ số dư không âm. |
| **invokedynamic** | Lệnh gọi liên kết động | Bytecode trì hoãn việc chọn cách thực thi tới runtime; được dùng để triển khai lambda. |
| **I/O-bound** | Bị giới hạn bởi thời gian chờ I/O | Workload dành phần lớn thời gian chờ database, mạng hoặc file thay vì tính toán trên CPU. |
| **IoC (Inversion of Control)** | Đảo ngược quyền điều khiển | Framework hoặc composition root quản lý việc tạo, nối và vòng đời object thay cho business object. |

## J

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Jackson** | Hệ sinh thái xử lý dữ liệu cho Java | Bộ thư viện thường dùng để parse, tạo và ánh xạ JSON với object Java qua streaming, tree model hoặc data binding. |
| **JAR hell** | Địa ngục JAR | Xung đột, thiếu hoặc trùng version thư viện làm classpath khó dự đoán. |
| **JIT (Just-In-Time compiler)** | Trình biên dịch tức thời | Biên dịch bytecode nóng thành mã máy khi chạy để tăng tốc. |
| **JMM (Java Memory Model)** | Mô hình bộ nhớ Java | Hợp đồng quy định visibility, ordering và đồng bộ giữa các thread. |
| **JNI (Java Native Interface)** | Cầu nối mã native | Cho phép Java gọi mã C/C++; các reference từ đây cũng là GC Root. |
| **JSON (JavaScript Object Notation)** | Định dạng dữ liệu văn bản | Biểu diễn object, array và giá trị nguyên thủy theo cấu trúc dễ trao đổi giữa nhiều ngôn ngữ. |
| **JsonNode / MissingNode** | Node cây JSON / node báo thiếu | `JsonNode` biểu diễn một phần của tree model; `path()` trả `MissingNode` khi không có field thay vì Java `null`. |

## L

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Latency** | Độ trễ | Thời gian phản hồi một yêu cầu. GC pause dài làm latency tăng đột biến. |
| **Leaky abstraction** | Abstraction bị rò | Contract để lộ chi tiết triển khai mà caller buộc phải biết hoặc có thể làm hỏng. |
| **LinkedHashMap** | Map giữ thứ tự liên kết | HashMap bổ sung linked list để giữ insertion/access order, thường dùng làm nền LRU local. |
| **LinkedList** | Danh sách liên kết đôi | List/Deque gồm node rời rạc; nối đầu/cuối O(1) nhưng truy cập index O(n). |
| **Liskov Substitution Principle (LSP)** | Nguyên tắc thay thế Liskov | Object type con phải thay được type cha mà không phá hành vi đúng hay hợp đồng đã hứa. |
| **Livelock** | Khóa sống | Thread không bị chặn nhưng liên tục phản ứng/nhường nhau nên không tạo tiến triển hữu ích. |
| **Load barrier** | Rào chắn khi đọc | (ZGC) đoạn kiểm tra tí hon chạy kèm mỗi lần đọc con trỏ, tự sửa con trỏ nếu object vừa bị dời. |
| **Load factor** | Hệ số tải | Ngưỡng số entry/capacity khiến HashMap resize; mặc định HashMap thường là 0.75. |
| **Lock-free** | Không khóa ở cấp thuật toán | Ít nhất một operation có thể tiến triển dù thread khác bị trì hoãn; thường dựa trên CAS/retry. |
| **LongAdder** | Bộ cộng phân mảnh | Counter chia cập nhật ra nhiều cell để giảm contention; `sum()` không là snapshot nguyên tử khi đang ghi. |

## M

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Magic number/string** | Giá trị bí ẩn | Literal mang ý nghĩa nghiệp vụ nhưng không có tên hoặc type giải thích mục đích. |
| **Major GC** | Dọn rác khu già | Đợt dọn Old Generation, chậm hơn Minor GC. |
| **Marker interface** | Interface đánh dấu | Interface không cần method, dùng sự hiện diện của nó để báo một đặc tính cho runtime/framework, như `Serializable`. |
| **Mark-Sweep** | Đánh dấu – quét | Thuật toán GC: đánh dấu object sống rồi quét xóa object không được đánh dấu. |
| **Maven Reactor** | Bộ điều phối đa module Maven | Thu thập module của một build và sắp thứ tự theo quan hệ phụ thuộc. |
| **Maven Wrapper** | Bộ chạy Maven cố định version | Script và metadata để dự án dùng Maven version thống nhất mà máy không cần cài sẵn. |
| **Memory barrier / fence** | Hàng rào bộ nhớ | Ranh giới buộc các thao tác đọc/ghi tuân theo thứ tự và visibility cần thiết giữa các core CPU. |
| **Memory leak** | Rò rỉ bộ nhớ | Object đáng lẽ thành rác nhưng vẫn bị giữ tham chiếu → không được dọn → bộ nhớ phình dần tới OOM. |
| **Metaspace** | Vùng metadata lớp | Nơi lưu thông tin về class (thay cho PermGen từ Java 8). Nằm ngoài heap. |
| **Method overriding** | Ghi đè phương thức | Lớp con cung cấp implementation mới cho instance method có cùng signature từ lớp cha/interface. |
| **Minor GC / Young GC** | Dọn rác khu trẻ | Đợt dọn nhanh chỉ quét Young Generation. |
| **Monitor** | Bộ giám sát khóa | Cơ chế khóa/chờ nội tại đứng sau `synchronized`, `wait()` và `notify()`. |
| **Multi-catch** | Bắt nhiều loại ngoại lệ | Một `catch` xử lý nhiều exception không có quan hệ kế thừa trực tiếp bằng cú pháp `A | B`. |

## N

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **N+1 query** | Một truy vấn cộng N truy vấn con | ORM tải danh sách bằng một query rồi phát thêm một query cho từng phần tử. |
| **Native code** | Mã máy bản địa | Lệnh chạy trực tiếp trên CPU cụ thể, thường do JIT tạo từ bytecode. |
| **Native serialization** | Tuần tự hóa object gốc của Java | Cơ chế `ObjectOutputStream`/`ObjectInputStream` ghi và dựng object graph Java cùng serial form riêng. |
| **Null sentinel** | `null` làm tín hiệu | Dùng `null` cho nhiều trạng thái như vắng mặt, lỗi hoặc chưa tải khiến contract mơ hồ. |

## O

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Object** | Đối tượng | Một thực thể dữ liệu tạo ra bằng `new`, chiếm chỗ trong heap. |
| **Object graph** | Đồ thị object | Một object cùng mọi object có thể đi tới qua reference, bao gồm shared reference và vòng tham chiếu. |
| **ObjectInputFilter** | Bộ lọc giải tuần tự hóa Java | Filter JEP 290 kiểm tra class và giới hạn độ sâu, reference, byte hoặc array trước/trong khi `readObject()`. |
| **ObjectMapper** | Bộ ánh xạ chính của Jackson | Thành phần cấu hình và thực hiện data binding/tree/streaming integration; nên cấu hình xong rồi tái sử dụng. |
| **ObjectReader / ObjectWriter** | Bộ đọc / ghi Jackson đã cấu hình | Object bất biến, có thể tái sử dụng cho một type hoặc policy cụ thể mà không mutate mapper dùng chung. |
| **Old Generation (Tenured)** | Khu "già" | Vùng heap chứa object sống lâu, được thăng cấp từ Young Gen. |
| **OOM (OutOfMemoryError)** | Hết bộ nhớ | Lỗi khi JVM không còn chỗ cấp phát object mới. |
| **Open/Closed Principle (OCP)** | Nguyên lý mở/đóng | Thiết kế mở cho extension nhưng hạn chế sửa phần ổn định đã hoạt động. |
| **Optimistic read** | Đọc lạc quan | Đọc không giữ read lock trước, sau đó validate để biết có writer chen vào hay không. |
| **Outbox Pattern** | Mẫu hộp thư đi | Ghi event vào bảng outbox cùng transaction với dữ liệu nghiệp vụ rồi relay bất đồng bộ. |
| **Overloading** | Nạp chồng phương thức | Nhiều method cùng tên nhưng khác danh sách tham số; compiler chọn overload tại compile-time. |
| **Overriding** | Ghi đè phương thức | Subtype thay implementation của instance method và được chọn bằng dynamic dispatch ở runtime. |

## P

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Parallelism** | Tính song song | Nhiều task thực sự chạy cùng lúc, thường nhờ nhiều CPU core. |
| **Parent delegation** | Ủy quyền cho bộ nạp cha | ClassLoader hỏi parent trước rồi mới tự tìm class, giúp bảo vệ class lõi và tránh nạp trùng. |
| **Parent POM** | POM cha | POM được module con kế thừa properties, plugin management và dependency management. |
| **PermGen** | Vùng vĩnh viễn (cũ) | Vùng lưu metadata class trước Java 8, đã bị Metaspace thay thế. |
| **Phaser** | Hàng rào nhiều giai đoạn | Đồng bộ các party qua nhiều phase và cho phép đăng ký/rời nhóm động. |
| **Pinning** | Ghim virtual thread | Virtual thread không thể unmount khi blocking nên giữ luôn carrier thread. |
| **Platform thread** | Luồng nền tảng | Java thread được ánh xạ tới OS thread và do hệ điều hành lập lịch. |
| **Pointer bump** | Dịch con trỏ | Cách cấp phát siêu nhanh: chỉ dời con trỏ tới ô trống kế tiếp (như `++`). |
| **Polymorphic typing** | Ánh xạ kiểu đa hình | Chọn subtype cụ thể từ type metadata; cần allowlist hẹp khi input có thể bị kiểm soát từ bên ngoài. |
| **Polymorphism** | Đa hình | Một abstraction hoặc lời gọi có nhiều implementation/hình thái tùy kiểu và ngữ cảnh. |
| **Primitive Obsession** | Ám ảnh kiểu nguyên thủy | Dùng String/số cho domain concept có invariant hoặc ý nghĩa riêng thay vì Value Object. |
| **PriorityQueue** | Hàng đợi ưu tiên | Queue trả phần tử ưu tiên nhất theo comparator; `peek` O(1), `offer/poll` O(log n). |
| **Promote / Promotion** | Thăng cấp | Chuyển object đủ "già" từ Young Gen sang Old Gen. |
| **Proxy Pattern** | Mẫu đại diện | Đặt object cùng contract trước subject thật để kiểm soát truy cập, lazy-load, cache hoặc chèn advice. |

## R

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Race condition** | Tranh chấp gây sai kết quả | Kết quả phụ thuộc timing khi nhiều thread đọc/ghi state chung mà thiếu đồng bộ phù hợp. |
| **RCE (Remote Code Execution)** | Thực thi mã từ xa | Khả năng attacker khiến hệ thống chạy code/lệnh do họ kiểm soát qua một lỗ hổng từ xa. |
| **ReadWriteLock** | Khóa đọc–ghi | Cho nhiều reader cùng vào nhưng writer cần quyền độc quyền. |
| **Record** | Lớp biểu diễn dữ liệu cô đọng | Class đặc biệt tự sinh constructor, accessor, `equals`, `hashCode` và `toString` từ các component. |
| **Red-black tree** | Cây đỏ-đen | Cây tìm kiếm tự cân bằng dùng trong TreeMap và bucket HashMap bị treeify. |
| **ReentrantLock** | Khóa tái nhập linh hoạt | Lock tường minh hỗ trợ timeout, interruption, fairness và nhiều `Condition`; phải unlock trong `finally`. |
| **Reference** | Tham chiếu | "Sợi dây" trỏ từ chỗ này tới một object; còn dây thì object còn sống. |
| **Region** | Vùng nhỏ | (G1) một ô heap kích thước cố định (1–32MB), đóng vai Eden/Survivor/Old linh hoạt. |
| **Reject-list** | Danh sách từ chối | Chặn các class/giá trị đã biết là xấu; thường yếu hơn allowlist vì trường hợp nguy hiểm mới có thể chưa được liệt kê. |
| **Relocation** | Dời chỗ object | Việc GC di chuyển object sang vị trí mới (ZGC làm việc này song song với ứng dụng). |
| **Repository Pattern** | Mẫu kho lưu trữ | Abstraction theo ngôn ngữ domain để truy xuất/lưu aggregate mà không lộ persistence. |
| **Reproducible build** | Build tái lập | Cùng đầu vào và môi trường đã kiểm soát tạo ra artifact tương đương qua các lần build. |
| **Retry** | Thử lại | Thực hiện lại operation sau failure tạm thời, thường kèm giới hạn lần thử, backoff, jitter và idempotency. |
| **Role interface** | Interface theo vai trò | Interface nhỏ mô tả đúng nhóm năng lực mà một loại client cần sử dụng. |
| **Root cause** | Nguyên nhân gốc | Exception hoặc sự kiện ban đầu gây ra chuỗi lỗi được wrap/chuyển tiếp qua nhiều layer. |

## S

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Safe publication** | Công bố object an toàn | Chia sẻ object sao cho thread khác chắc chắn thấy trạng thái đã khởi tạo hoàn chỉnh. |
| **Saga Pattern** | Mẫu Saga | Chuỗi local transaction có bước bù để quản lý tiến trình nghiệp vụ phân tán. |
| **Sealed class/interface** | Lớp/interface niêm phong | Type giới hạn chính xác các subtype được phép kế thừa hoặc triển khai. |
| **Semaphore** | Bộ đếm giấy phép | Giới hạn số thread được đồng thời sử dụng một tài nguyên; không tự giới hạn tốc độ theo thời gian. |
| **Serialization** | Tuần tự hóa | Chuyển dữ liệu hoặc object thành dạng byte/văn bản để lưu trữ hay truyền đi. |
| **Serialization Proxy Pattern** | Mẫu đại diện tuần tự hóa | Ghi một proxy ổn định thay cho object thật rồi gọi constructor/domain API khi đọc để tái lập invariant. |
| **serialVersionUID** | Mã phiên bản serial form | Giá trị dùng để kiểm tra tương thích giữa class Serializable hiện tại và dữ liệu đã ghi trước đó. |
| **Service Locator** | Bộ định vị dịch vụ | Global registry cho business object tự tìm dependency, khiến dependency bị ẩn. |
| **Set** | Tập hợp không trùng | Collection không cho duplicate; implementation quyết định hash, thứ tự chèn hoặc sorting. |
| **Shenandoah** | (Tên một GC) | GC độ trễ thấp của OpenJDK, dồn nén song song với ứng dụng. |
| **Sift-down** | Đẩy phần tử xuống | Bước sửa heap sau khi lấy root, đổi chỗ phần tử với child phù hợp cho tới khi đúng heap property. |
| **Sift-up** | Đẩy phần tử lên | Bước sửa heap sau khi chèn, đưa phần tử lên qua parent cho tới khi đúng heap property. |
| **Single Responsibility Principle (SRP)** | Nguyên lý đơn trách nhiệm | Một module nên có một nguồn hoặc actor tạo ra lý do thay đổi. |
| **Singleton overuse** | Lạm dụng singleton | Dùng global instance quá mức, đặc biệt với mutable state và dependency ẩn. |
| **Snapshot Pattern** | Mẫu ảnh chụp | Lưu state tại một version để giảm số event cần replay; event log vẫn là nguồn sự thật. |
| **Soft reference** | Tham chiếu mềm | GC chỉ dọn khi sắp hết bộ nhớ. Hợp cho cache. |
| **SOLID** | Bộ năm nguyên lý thiết kế | Nhóm SRP, OCP, LSP, ISP và DIP giúp đánh giá khả năng thay đổi của thiết kế OOP. |
| **Spliterator** | Bộ lặp có thể tách | Iterator hỗ trợ chia dữ liệu thành các đoạn để stream xử lý song song. |
| **Stack frame** | Khung ngăn xếp | Vùng dữ liệu của một lần gọi method, chứa biến cục bộ, operand stack và địa chỉ trả về. |
| **Stack trace** | Dấu vết ngăn xếp | Danh sách các lời gọi method tại thời điểm lỗi, dùng để lần ngược nơi exception phát sinh và truyền qua. |
| **StampedLock** | Khóa dùng stamp | Lock không tái nhập hỗ trợ read/write và optimistic read; phải validate hoặc mở khóa bằng đúng stamp. |
| **Starvation** | Bỏ đói | Một thread liên tục không được cấp CPU/lock/tài nguyên dù hệ thống vẫn có tiến triển. |
| **Stop-the-world (STW)** | Tạm dừng toàn bộ | GC bắt mọi thread ứng dụng đứng im để dọn an toàn → ứng dụng "khựng" trong lúc đó. |
| **Strategy Pattern** | Mẫu chiến lược | Đóng gói thuật toán thành object để có thể thay thế hành vi qua composition. |
| **Streaming API** | API xử lý tuần tự | Đọc/ghi từng token hoặc phần tử mà không cần giữ toàn bộ document trong bộ nhớ. |
| **Strong reference** | Tham chiếu mạnh | Tham chiếu mặc định; còn nó thì GC không bao giờ dọn object. |
| **Structural Pattern** | Mẫu cấu trúc | Nhóm pattern tổ chức và kết nối class/object thành cấu trúc lớn hơn. |
| **Structured concurrency** | Đồng thời có cấu trúc | Tổ chức task con trong scope của task cha để quản lý chờ, hủy và lỗi theo một vòng đời rõ ràng. |
| **Suppressed exception** | Ngoại lệ bị đính kèm | Lỗi phụ, thường từ `close()`, được giữ trong exception chính thay vì che mất failure ban đầu. |
| **Survivor (S0/S1)** | Khu sống sót | Hai vùng nhỏ trong Young Gen, luân phiên chứa object sống sót sau mỗi Minor GC. |
| **Synchronization** | Đồng bộ hóa | Cơ chế khóa để nhiều thread truy cập an toàn; tốn thời gian chờ. |

## T

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Task DAG** | Đồ thị tác vụ không chu trình | Mô tả dependency và thứ tự giữa các task build mà không tạo vòng chờ. |
| **Tenuring threshold** | Ngưỡng lên lão | Số tuổi tối thiểu (mặc định 15) để object được thăng cấp sang Old Gen. |
| **Thread confinement** | Giới hạn dữ liệu trong một thread | Bảo đảm object không được chia sẻ sang thread khác nên không cần đồng bộ truy cập. |
| **Thread lifecycle** | Vòng đời thread | Tập trạng thái NEW, RUNNABLE, BLOCKED, WAITING, TIMED_WAITING và TERMINATED cùng các chuyển đổi. |
| **ThreadLocal** | Biến riêng theo luồng | Biến mỗi thread giữ một bản riêng; nếu không `remove()` trong thread pool sẽ gây memory leak. |
| **ThreadLocalMap** | Map riêng trong Thread | Cấu trúc nội bộ giữ weak key là ThreadLocal và strong value cho từng thread. |
| **ThreadPoolExecutor** | Bộ thực thi dùng thread pool | Điều phối core/max thread, task queue, keep-alive và rejection policy. |
| **Throughput** | Thông lượng | Tỷ lệ thời gian CPU dành cho công việc thật (thay vì cho GC). |
| **TLAB (Thread Local Allocation Buffer)** | Bộ đệm cấp phát riêng luồng | Mỗi thread có một "khay" riêng trong Eden để cấp phát object không phải tranh khóa. |
| **Token bucket** | Xô token giới hạn tốc độ | Request phải lấy token; token được bù theo thời gian nên cho phép burst trong giới hạn. |
| **transient** | Field không thuộc default serial form | Từ khóa loại field instance khỏi cơ chế serialization mặc định; custom hook vẫn có thể tự ghi nó. |
| **Transitive dependency** | Phụ thuộc bắc cầu | Dependency được kéo vào vì một dependency trực tiếp khác cần nó. |
| **TreeMap** | Map dựa trên cây | Map giữ key theo thứ tự và hỗ trợ range/navigation query với chi phí O(log n). |
| **Trust boundary** | Ranh giới tin cậy | Điểm dữ liệu đi từ nguồn có mức tin cậy khác vào hệ thống, nơi cần xác thực, giới hạn và validation. |
| **Try-with-resources** | Khối tự đóng tài nguyên | Cú pháp tự gọi `close()` theo thứ tự ngược và giữ lỗi đóng dưới dạng suppressed exception khi cần. |
| **Type metadata** | Thông tin nhận diện kiểu | Dữ liệu giúp binder chọn subtype cụ thể; nếu nhận tên class quá rộng từ input có thể tạo rủi ro. |
| **TypeReference** | Mô tả generic type cho Jackson | Giữ thông tin như `List<User>` để Jackson không mất phần generic do type erasure. |

## U

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Unchecked exception** | Ngoại lệ không bị compiler bắt buộc xử lý | `RuntimeException` mà caller không buộc phải `catch`/khai báo; API vẫn nên document failure quan trọng. |
| **Unit of Work** | Đơn vị công việc | Theo dõi thay đổi entity trong một transaction và commit như một đơn vị nhất quán. |
| **Unknown-field policy** | Chính sách xử lý field lạ | Quyết định reject hay bỏ qua property JSON chưa biết theo contract và trust boundary cụ thể. |
| **Upcasting** | Ép kiểu lên | Xem object type con qua reference type cha; diễn ra ngầm định và luôn an toàn về kiểu. |
| **Update policy** | Chính sách kiểm tra cập nhật | Quy định repository client kiểm tra metadata/artifact mới thường xuyên đến mức nào. |

## V

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Version Catalog** | Danh mục phiên bản Gradle | Gom alias và version dependency type-safe; không tự ép version cuối cùng khi resolve xung đột. |
| **Virtual thread** | Luồng ảo | Luồng nhẹ do JVM lập lịch, có thể mount/unmount trên carrier thread khi chờ I/O. |
| **Visibility** | Khả năng nhìn thấy thay đổi | Bảo đảm một thread đọc được giá trị mới do thread khác ghi. |
| **volatile** | Biến có bảo đảm hiển thị/thứ tự | Từ khóa bảo đảm visibility và ordering cho một biến, nhưng không biến thao tác ghép như `++` thành atomic. |
| **Vtable (Virtual Method Table)** | Bảng phương thức ảo | Bảng ánh xạ slot method tới implementation mà JVM dùng để hỗ trợ dynamic dispatch. |

## W

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Weak Generational Hypothesis** | Giả thuyết phân thế hệ | Quan sát: hầu hết object "chết trẻ", chỉ số ít sống lâu. |
| **WeakHashMap** | Map giữ key yếu | Map dùng weak key để entry có thể tự biến mất khi key không còn strong reference. |
| **Weakly consistent iterator** | Iterator nhất quán yếu | Iterator concurrent không fail-fast và có thể thấy một phần thay đổi trong lúc duyệt. |
| **Weak reference** | Tham chiếu yếu | Không ngăn GC thu hồi object; object có thể bị dọn khi GC chạy, không được đảm bảo thời điểm cụ thể. Dùng cho `WeakHashMap`. |
| **Wither method** | Phương thức tạo bản sao có thay đổi | Trả về value object mới với một component được đổi, không mutate object gốc. |
| **Work-stealing** | Trộm việc | Worker rảnh lấy task từ deque của worker khác để cân bằng tải trong ForkJoinPool. |
| **Write-only property** | Thuộc tính chỉ nhận khi đọc input | Jackson có thể nhận field từ JSON nhưng không ghi nó ra output; không có nghĩa dữ liệu được che khỏi log/debugger. |

## Y / Z

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Young Generation** | Khu "trẻ" | Vùng heap chứa object mới sinh (gồm Eden + 2 Survivor). |
| **ZGC (Z Garbage Collector)** | GC độ trễ siêu thấp | GC dừng < 1ms kể cả với heap hàng TB, nhờ concurrent + colored pointers + load barrier. |

---

> Ghi chú: Bảng này sẽ được bổ sung dần khi các file khác trong package `java` được nâng cấp giải thích. Nếu một thuật ngữ chưa có ở đây, hãy thêm vào đúng mục chữ cái.
