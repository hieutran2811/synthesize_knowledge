---
title: "Stream API (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Stream API (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Stream API là gì?

**Stream API** (Java 8+) là API xử lý **sequence of elements** *(dãy phần tử liên tiếp)* theo phong cách **functional** *(hàm — mô tả phép biến đổi thay vì vòng lặp)*, **declarative** *(khai báo — nói "muốn gì" thay vì "làm từng bước ra sao")*, hỗ trợ **lazy evaluation** *(chỉ tính toán khi thực sự cần, không tính trước)* và **parallelism** *(xử lý song song nhiều luồng)* tích hợp.

> Stream **không phải** là data structure *(cấu trúc dữ liệu)*. Stream không lưu dữ liệu — nó mô tả **pipeline** *(dây chuyền)* xử lý trên nguồn dữ liệu.

> 💡 **Giải thích dễ hiểu:**
> Hãy tưởng tượng một **dây chuyền phân loại trái cây trong nhà máy**. Nguồn dữ liệu (List, mảng...) là các thùng trái cây đổ vào đầu băng chuyền. Mỗi công đoạn trên băng chuyền — rửa, loại quả hỏng, dán tem — là một phép xử lý. Bản thân băng chuyền **không chứa trái cây**; nó chỉ định nghĩa "trái cây đi qua sẽ được làm gì". Trái cây chỉ thực sự chạy khi bạn bật công tắc ở cuối dây chuyền (terminal operation). Đó chính là Stream: nó mô tả **quy trình xử lý**, chứ không phải là cái kho chứa dữ liệu.

**3 phần của Stream pipeline:**
```
Source → [Intermediate Operations]* → Terminal Operation
```

> 💡 **Giải thích dễ hiểu — 3 phần của một pipeline:**
> - **Source** *(nguồn)*: đầu vào của băng chuyền — nơi trái cây đổ vào (List, array, file...).
> - **Intermediate Operations** *(các phép trung gian)*: những công đoạn dọc thân băng chuyền như `filter`, `map`, `sorted`. Chúng chỉ **lắp đặt máy móc**, chưa chạy gì cả.
> - **Terminal Operation** *(phép kết thúc)*: cái công tắc ở cuối như `collect`, `forEach`, `count`. Bấm vào nó thì cả dây chuyền mới thực sự chuyển động và cho ra thành phẩm. Không có terminal → cả băng chuyền đứng yên.

---

## How – Stream Creation (nguồn tạo Stream)

```java
// 1. Từ Collection
List<String> list = List.of("a", "b", "c");
Stream<String> s1 = list.stream();
Stream<String> s2 = list.parallelStream();

// 2. Từ Array
Stream<String> s3 = Arrays.stream(new String[]{"a", "b"});
IntStream s4 = Arrays.stream(new int[]{1, 2, 3}); // primitive stream

// 3. Stream.of()
Stream<String> s5 = Stream.of("a", "b", "c");

// 4. Stream.generate() – infinite stream
Stream<Double> randoms = Stream.generate(Math::random);
Stream<UUID> uuids = Stream.generate(UUID::randomUUID);

// 5. Stream.iterate() – infinite stream với seed
Stream<Integer> naturals = Stream.iterate(0, n -> n + 1); // 0, 1, 2, ...
// Java 9+ với predicate (finite):
Stream<Integer> lessThan10 = Stream.iterate(0, n -> n < 10, n -> n + 1);

// 6. Stream.builder()
Stream.Builder<String> builder = Stream.builder();
builder.add("a"); builder.add("b");
Stream<String> s6 = builder.build();

// 7. Files.lines() – read file line by line
try (Stream<String> lines = Files.lines(Path.of("file.txt"))) {
    lines.filter(l -> !l.isBlank()).forEach(System.out::println);
}

// 8. String.chars()
"hello".chars().forEach(c -> System.out.print((char) c));
```

---

## How – Lazy Evaluation (Quan trọng!)

Intermediate operations **không thực thi ngay** — chúng chỉ tạo ra một **pipeline definition** *(bản thiết kế dây chuyền, chưa chạy)*. Terminal operation mới **trigger** *(kích hoạt)* thực thi.

> 💡 **Giải thích dễ hiểu — lazy evaluation:**
> "Lazy" nghĩa là **lười, để nước tới chân mới nhảy**. Hãy tưởng tượng bạn đọc thực đơn nhà hàng và gọi "cho tôi món A, xào kiểu B, thêm sốt C". Nhà bếp **không nấu ngay khi bạn nói từng ý** — họ chỉ ghi phiếu order. Chỉ khi bạn chốt "mang ra đi" (terminal operation) thì bếp mới thật sự nấu. Và điều hay ho: nếu bạn chỉ cần **1 phần tử đầu tiên** thỏa điều kiện (`findFirst`), dây chuyền xử lý đúng 1 quả rồi dừng, không phí công xử lý cả thùng. Đây là lý do stream thường tiết kiệm hơn vòng lặp ngây thơ.
>
> Cũng vì "lười" mà nếu bạn quên bấm terminal operation, **không có gì chạy cả** — giống như ghi phiếu order rồi để đó, bếp không đụng tới. Và stream xử lý theo "chiều dọc": **một phần tử đi hết chuỗi công đoạn rồi mới tới phần tử kế** (quả táo đầu tiên rửa → phân loại → dán tem xong xuôi rồi quả thứ hai mới bắt đầu), chứ không phải rửa cả thùng rồi mới phân loại cả thùng — nhờ vậy `findFirst` mới dừng được ngay sau quả đầu tiên đạt yêu cầu.

```java
List<String> names = List.of("Alice", "Bob", "Charlie", "David", "Eve");

// Không có terminal → KHÔNG có gì được thực thi
Stream<String> stream = names.stream()
    .filter(s -> { System.out.println("filter: " + s); return s.length() > 3; })
    .map(s -> { System.out.println("map: " + s); return s.toUpperCase(); });

System.out.println("--- Starting terminal ---");
stream.findFirst(); // trigger!

// Output:
// --- Starting terminal ---
// filter: Alice    ← filter Alice
// map: Alice       ← map Alice (passed filter)
// (STOP! findFirst() đã có kết quả, không xử lý tiếp Bob, Charlie...)
```

**Short-circuit operations** *(phép "chập mạch" — dừng sớm)* dừng ngay khi có đủ kết quả:
- `findFirst()`, `findAny()`, `anyMatch()`, `allMatch()`, `noneMatch()`, `limit()`

> 💡 **Giải thích dễ hiểu — short-circuiting:**
> Tên gọi "short-circuit" mượn từ mạch điện: khi dòng điện tìm được đường tắt, nó dừng luôn, không đi hết mạch. Trong đời thực giống như bạn đi tìm **một** người mặc áo đỏ trong đám đông: vừa thấy người đầu tiên mặc áo đỏ là bạn dừng ngay, đâu cần soi hết cả nghìn người. `anyMatch` (có ai thỏa không?) chỉ cần gặp 1 phần tử đúng là trả `true` lập tức; `allMatch` (tất cả có thỏa không?) chỉ cần gặp 1 phần tử sai là trả `false` lập tức. Nhờ vậy stream tránh làm việc thừa.

---

## How – Intermediate Operations

> 💡 **Giải thích dễ hiểu — stateless vs stateful:**
> - **Stateless** *(không trạng thái)*: phép xử lý chỉ nhìn **đúng phần tử đang cầm trên tay**, không cần nhớ các phần tử trước đó. Ví dụ `filter`, `map` — như công nhân dán tem: cầm quả nào dán quả đó, chẳng cần nhớ đã dán bao nhiêu quả.
> - **Stateful** *(có trạng thái)*: phép xử lý cần **thấy nhiều phần tử, đôi khi cả lô** mới làm được. Ví dụ `sorted` (muốn sắp xếp phải có đủ hàng mới xếp được), `distinct` (muốn loại trùng phải nhớ những gì đã thấy). Giống công nhân xếp trái cây theo kích cỡ: phải chờ gom đủ cả thùng mới xếp được thứ tự. Vì vậy stateful ops tốn bộ nhớ hơn và cản trở tối ưu "dừng sớm".

### Stateless (thứ tự phần tử không ảnh hưởng kết quả)
```java
stream.filter(Predicate)         // O(1) per element
stream.map(Function)             // O(1) per element
stream.mapToInt/Long/Double()    // boxing-free primitive stream
stream.flatMap(Function)         // flatten nested streams
stream.peek(Consumer)            // debug (không thay đổi stream)
stream.limit(n)                  // lấy tối đa n phần tử
stream.skip(n)                   // bỏ qua n phần tử đầu
```

### Stateful (cần xem nhiều/tất cả phần tử)
```java
stream.distinct()                // loại trùng (dùng equals/hashCode)
stream.sorted()                  // sắp xếp (cần tất cả phần tử)
stream.sorted(Comparator)
```

### flatMap – Quan trọng!

> 💡 **Giải thích dễ hiểu — flatMap:**
> `map` biến mỗi phần tử thành **một** phần tử khác. Nhưng đôi khi mỗi phần tử lại "nở ra" thành **cả một danh sách** — ví dụ mỗi đơn hàng có nhiều món. Nếu dùng `map` bạn được "danh sách của các danh sách" (thùng chứa nhiều túi con). `flatMap` *(map rồi làm phẳng)* làm thêm một bước: **đổ hết các túi con ra chung một mặt bàn** thành một dòng phẳng duy nhất. Ví von: bạn có nhiều vali (đơn hàng), mỗi vali đựng nhiều quần áo (món hàng); `flatMap` mở tất cả vali và trải toàn bộ quần áo ra một dây phơi liền mạch để xử lý từng cái.

```java
// map vs flatMap
List<List<Integer>> nested = List.of(List.of(1, 2), List.of(3, 4), List.of(5));

// map → Stream<List<Integer>> (vẫn còn nested)
nested.stream().map(List::stream);   // Stream<Stream<Integer>>

// flatMap → Stream<Integer> (đã flatten)
nested.stream()
    .flatMap(Collection::stream)      // Stream<Integer>: 1, 2, 3, 4, 5
    .collect(Collectors.toList());

// Ứng dụng thực tế: lấy tất cả items từ tất cả orders
List<Item> allItems = orders.stream()
    .flatMap(order -> order.getItems().stream())
    .collect(Collectors.toList());
```

---

## How – Terminal Operations

```java
// Collect
List<String> list = stream.collect(Collectors.toList());
Set<String> set = stream.collect(Collectors.toSet());
String joined = stream.collect(Collectors.joining(", ", "[", "]"));

// Reduce
Optional<Integer> sum = stream.reduce((a, b) -> a + b);
Integer sum2 = stream.reduce(0, Integer::sum); // với identity (giá trị khởi đầu)

// Search / Match
Optional<T> first = stream.findFirst();  // encounter order
Optional<T> any   = stream.findAny();    // không đảm bảo thứ tự (nhanh hơn với parallel)
boolean any   = stream.anyMatch(predicate);
boolean all   = stream.allMatch(predicate);
boolean none  = stream.noneMatch(predicate);

// Aggregate
long count = stream.count();
Optional<T> min = stream.min(comparator);
Optional<T> max = stream.max(comparator);

// Side-effect
stream.forEach(consumer);
stream.forEachOrdered(consumer); // giữ thứ tự (quan trọng với parallel)

// Convert to array
Object[] arr = stream.toArray();
String[] arr2 = stream.toArray(String[]::new);

// Primitive streams
IntStream ints = IntStream.range(0, 10); // 0..9
int[] intArr = ints.toArray();
OptionalInt max = ints.max();
int sum = IntStream.rangeClosed(1, 100).sum(); // 5050
```

---

## How – Collectors (Deep Dive)

> 💡 **Giải thích dễ hiểu — reduce và collect:**
> Cả hai đều là cách **gộp cả dây chuyền lại thành một kết quả**, nhưng khác nhau ở phong cách:
> - **reduce** *(gộp dồn)*: như **cộng dồn tiền** — cầm tổng hiện tại, gặp phần tử mới thì cộng vào, ra tổng mới. Cứ thế "cuộn" từ đầu đến cuối thành một giá trị. `identity` là số khởi đầu (thường là 0 cho phép cộng, 1 cho phép nhân, chuỗi rỗng cho nối chuỗi).
> - **collect** *(thu gom vào thùng chứa)*: như **công nhân cuối băng chuyền cầm sẵn cái rổ/thùng** và bỏ từng thành phẩm vào. `Collectors.toList()` là "bỏ vào rổ danh sách", `groupingBy` là "phân loại vào nhiều ngăn theo nhãn", `joining` là "dán các mẩu giấy thành một băng dài". `collect` mạnh hơn `reduce` khi kết quả là một container có thể thay đổi (mutable) như List, Map.

### Basic Collectors
```java
Collectors.toList()
Collectors.toSet()
Collectors.toUnmodifiableList()      // Java 10+
Collectors.toCollection(TreeSet::new) // custom collection
Collectors.counting()
Collectors.summingInt(Person::getAge)
Collectors.averagingDouble(Person::getGpa)
Collectors.joining(", ", "[", "]")
```

### groupingBy – Phổ biến nhất
```java
List<Person> people = ...;

// Group đơn giản: Map<City, List<Person>>
Map<String, List<Person>> byCity = people.stream()
    .collect(Collectors.groupingBy(Person::getCity));

// Group + downstream collector: Map<City, Long>
Map<String, Long> countByCity = people.stream()
    .collect(Collectors.groupingBy(
        Person::getCity,
        Collectors.counting()
    ));

// Group + map downstream: Map<City, List<String>>
Map<String, List<String>> namesByCity = people.stream()
    .collect(Collectors.groupingBy(
        Person::getCity,
        Collectors.mapping(Person::getName, Collectors.toList())
    ));

// Multi-level grouping: Map<City, Map<Gender, List<Person>>>
Map<String, Map<String, List<Person>>> grouped = people.stream()
    .collect(Collectors.groupingBy(
        Person::getCity,
        Collectors.groupingBy(Person::getGender)
    ));

// Group + sort value: Map<City, List<Person>> sorted by age
Map<String, List<Person>> sortedByAge = people.stream()
    .collect(Collectors.groupingBy(
        Person::getCity,
        Collectors.collectingAndThen(
            Collectors.toList(),
            list -> list.stream().sorted(Comparator.comparing(Person::getAge)).collect(Collectors.toList())
        )
    ));
```

### partitioningBy – 2 nhóm (true/false)
```java
Map<Boolean, List<Person>> adultPartition = people.stream()
    .collect(Collectors.partitioningBy(p -> p.getAge() >= 18));

List<Person> adults = adultPartition.get(true);
List<Person> minors = adultPartition.get(false);
```

### toMap – Tạo Map từ stream
```java
// Map<id, user>
Map<Long, User> userMap = users.stream()
    .collect(Collectors.toMap(User::getId, Function.identity()));

// Conflict: nếu trùng key → merge function
Map<String, Integer> wordLengths = words.stream()
    .collect(Collectors.toMap(
        Function.identity(),
        String::length,
        (existing, newVal) -> existing  // giữ value cũ nếu trùng key
    ));
```

### teeing (Java 12+) – Collect vào 2 collector đồng thời
```java
// Tính min và max trong 1 lần pass
Map.Entry<Optional<Integer>, Optional<Integer>> minMax = numbers.stream()
    .collect(Collectors.teeing(
        Collectors.minBy(Integer::compare),
        Collectors.maxBy(Integer::compare),
        Map::entry
    ));
```

---

## How – Optional API

`Optional<T>` bao bọc giá trị có thể null, buộc caller xử lý trường hợp không có giá trị.

```java
// Tạo Optional
Optional<String> opt1 = Optional.of("value");         // throw NPE nếu null
Optional<String> opt2 = Optional.ofNullable(nullable); // OK với null → empty
Optional<String> opt3 = Optional.empty();

// Kiểm tra và lấy giá trị
opt1.isPresent()          // true
opt1.isEmpty()            // false (Java 11+)
opt1.get()                // "value" (ném NoSuchElementException nếu empty!)

// Safe access
opt1.orElse("default")               // lấy hoặc default
opt1.orElseGet(() -> computeDefault()) // lazy default (tốt hơn orElse với heavy computation)
opt1.orElseThrow()                   // ném NoSuchElementException
opt1.orElseThrow(() -> new NotFoundException("not found"))

// Transform (map, flatMap, filter)
Optional<Integer> length = opt1.map(String::length);       // Optional<Integer>
Optional<String> found = opt1.filter(s -> s.length() > 3); // Optional<String>

// flatMap: khi function đã trả về Optional
Optional<String> email = userOpt.flatMap(User::getEmail); // nếu User::getEmail trả về Optional<String>

// ifPresent, ifPresentOrElse (Java 9+)
opt1.ifPresent(System.out::println);
opt1.ifPresentOrElse(
    System.out::println,
    () -> System.out.println("Not found")
);

// or (Java 9+): trả về Optional khác nếu empty
Optional<String> result = opt1.or(() -> Optional.of("fallback"));

// stream (Java 9+): Optional → Stream (0 hoặc 1 phần tử)
opt1.stream().forEach(System.out::println);
```

**Anti-patterns với Optional:**
```java
// KHÔNG: isPresent() + get() = dùng null check kiểu cũ
if (opt.isPresent()) { String s = opt.get(); }  // không khác null check gì!

// ĐÚNG: dùng map, orElse, ifPresent
opt.map(String::toUpperCase).orElse("NONE");

// KHÔNG: dùng Optional làm field, parameter, collection element
class User { Optional<String> email; }  // WRONG!
void process(Optional<User> user) { }   // WRONG!

// ĐÚNG: Optional chỉ dùng làm return type của method
Optional<User> findById(Long id) { ... }
```

---

## How – Primitive Streams

Tránh boxing/unboxing overhead với `IntStream`, `LongStream`, `DoubleStream`:

```java
// IntStream
IntStream.range(0, 10)          // 0..9 (exclusive end)
IntStream.rangeClosed(1, 10)    // 1..10 (inclusive end)
IntStream.of(1, 2, 3, 4, 5)

// Chuyển đổi
Stream<Integer> boxed = IntStream.range(0, 5).boxed();
IntStream unboxed = Stream.of(1, 2, 3).mapToInt(Integer::intValue);

// Statistics
IntSummaryStatistics stats = IntStream.range(1, 100)
    .filter(n -> n % 2 == 0)
    .summaryStatistics();
stats.getMin(); stats.getMax(); stats.getSum(); stats.getAverage(); stats.getCount();
```

---

## How – Parallel Streams

> 💡 **Giải thích dễ hiểu — parallel stream:**
> **parallel stream** *(luồng xử lý song song)* chia dữ liệu thành nhiều khúc và giao cho **nhiều nhân CPU cùng làm một lúc**, rồi ghép kết quả lại. Ví von: thay vì một thu ngân quét 1000 món hàng (sequential), siêu thị mở **nhiều quầy cùng lúc** (parallel), mỗi quầy quét một phần rồi cộng tổng. Nghe thì nhanh, nhưng có cái giá: phải tốn công **chia hàng ra các quầy và gom kết quả về** (overhead của fork/join). Nếu chỉ có vài món (dữ liệu nhỏ), mở nhiều quầy còn chậm hơn một quầy vì mất thời gian điều phối.
>
> Cạm bẫy chết người: nếu các quầy cùng ghi vào **một sổ chung** không có khóa an toàn (shared mutable state), chúng ghi đè lên nhau → sai số, gọi là **race condition** *(tranh chấp dữ liệu do chạy đua)*. Vì vậy với parallel, luôn dùng collector thread-safe thay vì tự gom vào biến ngoài.
>
> Việc "chia hàng ra các quầy" do một bộ phận tên là **Spliterator** *(bộ chia + duyệt phần tử)* đảm nhiệm — nguồn nào dễ cắt đôi theo chỉ số (ArrayList, mảng) thì chia nhanh; nguồn dạng xâu chuỗi như `LinkedList` phải lần từng mắt xích nên chia chậm, parallel ít lợi.

```java
// Sequential
long count = list.stream().filter(...).count();

// Parallel: dùng ForkJoinPool.commonPool()
long count = list.parallelStream().filter(...).count();
// hoặc
long count = list.stream().parallel().filter(...).count();

// Custom pool (Java 8+)
ForkJoinPool customPool = new ForkJoinPool(4);
long result = customPool.submit(
    () -> list.parallelStream().mapToLong(work::compute).sum()
).get();
```

### Khi nào parallel stream thực sự nhanh hơn?

**Parallel nhanh hơn khi:**
- Dữ liệu lớn (> 10.000 phần tử)
- Mỗi phần tử xử lý tốn thời gian (IO, heavy CPU)
- Source dễ split (ArrayList, array > LinkedList, Set)
- Pipeline không có trạng thái chia sẻ (stateless)

**Parallel KHÔNG nên dùng khi:**
- Dữ liệu nhỏ (overhead fork/join > lợi ích)
- Có side effects (shared mutable state → race condition)
- Cần thứ tự (`forEachOrdered`, `reduce` phức tạp)
- Source khó split (LinkedList, Stream.iterate)

```java
// NGUY HIỂM: shared mutable state + parallel
List<Integer> result = Collections.synchronizedList(new ArrayList<>());
numbers.parallelStream().forEach(result::add); // race condition dù synchronized!

// ĐÚNG: stateless collector
List<Integer> result = numbers.parallelStream()
    .filter(n -> n > 0)
    .collect(Collectors.toList()); // thread-safe collector
```

---

## Compare – Stream vs for-each Loop

| | Stream | For-each Loop |
|--|--------|--------------|
| Phong cách | Declarative | Imperative |
| Readable | Cao (khi ngắn) | Cao (khi phức tạp) |
| Debug | Khó (lazy, no breakpoint) | Dễ |
| Parallel | Built-in | Manual phức tạp |
| Performance (đơn giản) | Tương đương | Micro-nhanh hơn |
| Performance (phức tạp) | Tốt hơn (short-circuit, parallel) | Thủ công |
| Reusable | Không (1 lần) | Có |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Code ngắn, declarative | Debug khó (stack trace phức tạp) |
| Lazy evaluation | Stream không reusable |
| Parallel tích hợp | Parallel không phải lúc nào cũng nhanh hơn |
| Short-circuit tiết kiệm CPU | Stateful ops (sorted, distinct) cần toàn bộ data |
| Composable | Lambda side-effects gây bug khó tìm |

---

## Real-world Usage (Production)

### 1. Data Transformation Pipeline
```java
List<OrderDto> recentOrders = orderRepository.findAll().stream()
    .filter(o -> o.getCreatedAt().isAfter(LocalDateTime.now().minusDays(30)))
    .filter(o -> o.getStatus() == OrderStatus.COMPLETED)
    .sorted(Comparator.comparing(Order::getTotalAmount).reversed())
    .limit(100)
    .map(OrderDto::from)
    .collect(Collectors.toList());
```

### 2. Report Generation
```java
// Tổng doanh thu theo tháng
Map<YearMonth, BigDecimal> revenueByMonth = orders.stream()
    .collect(Collectors.groupingBy(
        o -> YearMonth.from(o.getCreatedAt()),
        Collectors.reducing(BigDecimal.ZERO, Order::getTotalAmount, BigDecimal::add)
    ));

// Top 5 sản phẩm bán chạy
List<Map.Entry<String, Long>> top5 = orders.stream()
    .flatMap(o -> o.getItems().stream())
    .collect(Collectors.groupingBy(Item::getProductName, Collectors.counting()))
    .entrySet().stream()
    .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
    .limit(5)
    .collect(Collectors.toList());
```

### 3. Batch Processing với Parallel
```java
// Xử lý parallel nhưng collect thread-safe
Map<Long, ProcessingResult> results = taskIds.parallelStream()
    .map(id -> Map.entry(id, processTask(id))) // IO-heavy
    .collect(Collectors.toConcurrentMap(
        Map.Entry::getKey,
        Map.Entry::getValue
    ));
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Exception Handling** (deep dive)
>
> Keyword: Exception hierarchy, checked vs unchecked, try-with-resources (AutoCloseable, multiple resources, suppressed exceptions), multi-catch, custom exception best practices, exception chaining, exception in lambda/stream, finally vs try-with-resources, common anti-patterns (exception swallowing, overly broad catch)
