# Collections Framework (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Collections Framework là gì?

**Java Collections Framework (JCF)** là kiến trúc thống nhất cung cấp:
- **Interfaces**: contract (List, Set, Map, Queue...)
- **Implementations**: cài đặt cụ thể (ArrayList, HashMap...)
- **Algorithms**: `Collections.sort()`, `Collections.binarySearch()`...

Mục tiêu: tái sử dụng, interoperability, hiệu suất đã được tối ưu sẵn.

> 💡 **Giải thích dễ hiểu — interface là luật chơi, implementation là sân cụ thể:**
> Code nên khai báo `List`, `Set` hoặc `Map` theo nhu cầu hành vi; chỉ chọn `ArrayList`, `HashSet` hay `TreeMap` ở nơi cần quyết định hiệu năng/đặc tính. Giống hợp đồng “có thể xếp hàng”, implementation cụ thể quyết định hàng nằm trong mảng, cây hay bảng băm. Nhờ vậy có thể thay implementation mà ít ảnh hưởng caller, nhưng vẫn phải hiểu trade-off của cấu trúc thật.

---

## How – Tổng quan Hierarchy

```

Iterable<T>
  └── Collection<T>
        ├── List<T>              (thứ tự, cho phép trùng)
        │     ├── ArrayList
        │     ├── LinkedList
        │     ├── Vector (legacy, synchronized)
        │     └── Stack (legacy, extends Vector)
        ├── Set<T>               (không trùng)
        │     ├── HashSet
        │     ├── LinkedHashSet
        │     └── SortedSet → NavigableSet → TreeSet
        └── Queue<T>             (FIFO)
              ├── LinkedList
              ├── PriorityQueue
              └── Deque<T>       (double-ended queue)
                    ├── ArrayDeque
                    └── LinkedList

Map<K,V>  (không extends Collection)
  ├── HashMap
  ├── LinkedHashMap
  ├── SortedMap → NavigableMap → TreeMap
  ├── Hashtable (legacy, synchronized)
  └── ConcurrentHashMap (java.util.concurrent)
```

> 💡 **Giải thích dễ hiểu — chọn collection theo câu hỏi cần trả lời:**
> `List` trả lời “phần tử ở vị trí nào và có thứ tự gì?”, `Set` trả lời “đã có phần tử này chưa?”, `Map` trả lời “key này ánh xạ tới giá trị nào?”, còn `Queue/Deque` trả lời “ai được lấy ra tiếp theo?”. Chọn interface theo câu hỏi trước, rồi mới tối ưu implementation và ordering.

---

## How – ArrayList Internals

### Cấu trúc bên trong
```java
// Simplified ArrayList internals
public class ArrayList<E> {
    private Object[] elementData; // mảng backing
    private int size;             // số phần tử thực tế (khác capacity!)

    private static final int DEFAULT_CAPACITY = 10;

    public ArrayList() {
        elementData = DEFAULTCAPACITY_EMPTY_ELEMENTDATA; // lazy init
    }
}
```

### Growth Strategy
```

Khi add() vượt capacity → grow:
newCapacity = oldCapacity + (oldCapacity >> 1)
           = oldCapacity * 1.5
```

> 💡 **Giải thích dễ hiểu — ArrayList là dãy ghế có thể kéo dài:**
> Mảng backing có capacity hữu hạn. Khi hết chỗ, ArrayList cấp mảng lớn hơn rồi copy toàn bộ phần tử; vì vậy một lần grow có thể O(n), nhưng trung bình nhiều lần `add` cuối là O(1) amortized. Nếu biết trước kích thước gần đúng, truyền initial capacity giúp tránh nhiều lần chuyển kho và giảm garbage tạm.

```java
// Ví dụ growth:
// capacity 10 → add phần tử thứ 11 → capacity 15
// capacity 15 → add phần tử thứ 16 → capacity 22
// capacity 22 → add phần tử thứ 23 → capacity 33
```

**Tại sao cần biết?**
```java
// Anti-pattern: thêm 1 triệu phần tử → nhiều lần copy mảng
List<Integer> list = new ArrayList<>();
for (int i = 0; i < 1_000_000; i++) list.add(i);

// Best practice: khởi tạo với capacity đúng
List<Integer> list = new ArrayList<>(1_000_000);
```

### Performance
| Operation | Complexity | Ghi chú |
|-----------|-----------|---------|
| `get(index)` | O(1) | Direct array access |
| `add(e)` (cuối) | O(1) amortized | O(n) khi grow |
| `add(index, e)` (giữa) | O(n) | Shift elements |
| `remove(index)` (giữa) | O(n) | Shift elements |
| `contains(o)` | O(n) | Linear scan |
| `size()` | O(1) | Field access |

---

## How – LinkedList Internals

### Cấu trúc: Doubly-Linked List
```java
// Node bên trong
private static class Node<E> {
    E item;
    Node<E> next;
    Node<E> prev;
    Node(Node<E> prev, E element, Node<E> next) {
        this.item = element; this.next = next; this.prev = prev;
    }
}

// LinkedList chứa
transient Node<E> first;
transient Node<E> last;
transient int size;
```

### Performance
| Operation | Complexity | Ghi chú |
|-----------|-----------|---------|
| `get(index)` | O(n) | Traverse từ đầu/cuối |
| `add(e)` (cuối) | O(1) | Update last pointer |
| `add(index, e)` (sau khi tìm vị trí) | O(n) + O(1) | Tìm O(n), insert O(1) |
| `remove(first/last)` | O(1) | Update pointer |
| `peek()`, `poll()` | O(1) | Queue/Deque operations |

> **Lưu ý quan trọng**: LinkedList cache memory hơn ArrayList vì mỗi node có 2 pointer (prev, next) + overhead object header. Trong thực tế, ArrayList thường nhanh hơn cả khi insert/delete giữa vì **cache locality** (dữ liệu liên tiếp trong RAM).

> 💡 **Giải thích dễ hiểu — “xóa O(1)” chỉ đúng sau khi đã đứng đúng node:**
> LinkedList không nhảy thẳng tới index; nó phải đi từ đầu hoặc cuối để tìm node. Vì CPU phải dereference nhiều object rời rạc, cache miss và allocation node thường làm LinkedList chậm hơn ArrayList dù phép nối pointer sau khi tìm được là O(1). Chỉ ưu tiên LinkedList khi thực sự thao tác đầu/cuối hoặc đã có iterator/node phù hợp.

---

## How – HashMap Internals (Java 8+)

### Cấu trúc: Array of Buckets
```java
// Simplified
public class HashMap<K,V> {
    Node<K,V>[] table;         // mảng bucket
    int size;                  // số entry
    int threshold;             // size * loadFactor → khi nào resize
    float loadFactor;          // default 0.75
    static final int TREEIFY_THRESHOLD = 8;   // chuyển sang TreeNode khi ≥ 8
    static final int UNTREEIFY_THRESHOLD = 6; // chuyển ngược lại khi ≤ 6
}
```

### Quá trình `put(key, value)`

```
1. hash = hash(key)
   → key.hashCode() XOR (hashCode >>> 16)  [spreading high bits]

2. index = hash & (table.length - 1)
   → table.length luôn là power of 2 → & thay cho %

3. Nếu bucket[index] trống → tạo Node mới

4. Nếu bucket[index] có collision:
   - Nếu key.equals() match → update value
   - Nếu không: thêm vào chain

5. Nếu chain.size() >= 8 và table đủ lớn (thường capacity >= 64)
   → chuyển từ linked nodes sang TreeNode (Red-Black Tree)
   → nếu table còn nhỏ, HashMap ưu tiên resize trước

6. Nếu size > threshold (= capacity * 0.75) → resize (double capacity)
   → rehash tất cả entry
```

### Ví dụ trực quan
```

table[0]: null
table[1]: Node("Alice", 25) → Node("Charlie", 30)  [collision, linked]
table[2]: null
table[3]: TreeNode("Dave", ...)                     [treeified, nhiều collision]
...
table[15]: Node("Bob", 22)
```

> 💡 **Giải thích dễ hiểu — hash chọn ngăn, equals xác nhận hồ sơ:**
> `hashCode()` giúp HashMap chọn bucket nhanh; khi nhiều key rơi cùng bucket, `equals()` mới xác nhận có đúng key cần tìm hay không. Hai object `equals()` với nhau phải có cùng hash, nếu không chúng bị cất ở hai ngăn khác nhau và lookup không gặp được. Mutable key còn nguy hiểm hơn: đổi field dùng trong hash sau `put` có thể làm entry “mất” trong chính map.

### Tại sao loadFactor = 0.75?
- `loadFactor = 1.0`: ít resize hơn nhưng nhiều collision hơn → chậm
- `loadFactor = 0.5`: ít collision nhưng tốn memory gấp đôi
- `0.75`: balance tốt giữa time và space

> 💡 **Giải thích dễ hiểu — load factor là ngưỡng đầy của kho:**
> Ngưỡng thấp nghĩa nhiều ngăn trống, collision ít nhưng tốn bộ nhớ; ngưỡng cao tiết kiệm mảng hơn nhưng bucket dài và lookup dễ chậm. `0.75` là thỏa hiệp mặc định, không phải con số tối ưu cho mọi workload. Nếu biết số entry lớn, đặt initial capacity hợp lý để tránh nhiều lần resize.

### equals() và hashCode() Contract
```java
// NẾU a.equals(b) → a.hashCode() PHẢI == b.hashCode()
// (ngược lại không bắt buộc)

// Vi phạm → HashMap hoạt động sai!
class BadKey {
    int value;
    @Override
    public boolean equals(Object o) { return ((BadKey)o).value == value; }
    // Quên override hashCode! → 2 BadKey bằng nhau vào 2 bucket khác nhau
}

Map<BadKey, String> map = new HashMap<>();
map.put(new BadKey(1), "one");
map.get(new BadKey(1)); // null! không tìm thấy dù equals() trả true
```

---

## How – TreeMap Internals

### Cấu trúc: Red-Black Tree (Self-Balancing BST)
- Mỗi node là RED hoặc BLACK
- Root luôn BLACK
- Không có 2 RED node liên tiếp trên path từ root đến leaf
- Mọi path từ root đến null có cùng số BLACK node

→ Đảm bảo tree luôn cân bằng: height ≤ 2 log(n+1) → O(log n) cho mọi operation.

> 💡 **Giải thích dễ hiểu — TreeMap trả giá để giữ thứ tự:**
> HashMap tối ưu tìm theo key không thứ tự; TreeMap duy trì một cây cân bằng để trả lời thêm `floorKey`, `ceilingKey` và range query. Mỗi thao tác O(log n), đổi lại key phải có natural ordering hoặc Comparator nhất quán. Nếu comparator coi hai key khác nhau là “bằng nhau”, map có thể ghi đè giá trị dù `equals()` của key không bằng.

```java
TreeMap<String, Integer> scores = new TreeMap<>();
scores.put("Charlie", 90);
scores.put("Alice", 95);
scores.put("Bob", 88);
// Tự động sắp xếp theo key: Alice=95, Bob=88, Charlie=90

// NavigableMap operations
scores.firstKey();                    // "Alice"
scores.lastKey();                     // "Charlie"
scores.headMap("Charlie");            // {Alice=95, Bob=88}
scores.tailMap("Bob");                // {Bob=88, Charlie=90}
scores.floorKey("Bravo");            // "Bob" (key lớn nhất ≤ "Bravo")
scores.ceilingKey("Bravo");          // "Charlie" (key nhỏ nhất ≥ "Bravo")
```

---

## How – ConcurrentHashMap (Java 8+)

### Tại sao không dùng HashMap trong multi-thread?
```java
// HashMap.put() không atomic → race condition:
// Thread A và B cùng resize → infinite loop (Java 7!) hoặc data loss (Java 8)
```

> 💡 **Giải thích dễ hiểu — thread-safe là tính chất của cả thao tác, không chỉ method:**
> ConcurrentHashMap bảo vệ cấu trúc map và cung cấp các operation nguyên tử như `putIfAbsent`, `computeIfAbsent`, `merge`. Nó không biến một chuỗi nhiều lệnh tùy ý thành transaction toàn cục; nếu invariant trải qua nhiều key, vẫn cần thiết kế atomicity/lock ở cấp nghiệp vụ.

### ConcurrentHashMap: CAS + synchronized per-bucket (Java 8)
```java
// Java 7: Segment locking (16 segments mặc định)
// Java 8: Lock từng bucket bằng synchronized + CAS (Compare-And-Swap)
//         → fine-grained locking, concurrency cao hơn Java 7

ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();
map.put("key", 1);
map.putIfAbsent("key", 2);                          // atomic
map.computeIfAbsent("key2", k -> k.length());       // atomic
map.merge("key", 1, Integer::sum);                   // atomic increment!
```

### So sánh thread-safe Maps

| | `HashMap` | `Hashtable` | `Collections.synchronizedMap` | `ConcurrentHashMap` |
|--|-----------|------------|-------------------------------|---------------------|
| Thread-safe | Không | Có (method-level lock) | Có (object-level lock) | Có (bucket-level) |
| Performance | Nhất | Tệ nhất | Tệ | Tốt nhất |
| Null key/value | Có | Không | Có | Không |
| Iteration | Fail-fast | Weakly consistent | Fail-fast | Weakly consistent |

---

## How – Fail-fast vs Concurrent Iterators

### Fail-fast (ArrayList, HashMap...)
```java
List<String> list = new ArrayList<>(List.of("a", "b", "c"));
for (String s : list) {
    if (s.equals("b")) list.remove(s); // ConcurrentModificationException!
}

// Fix: dùng Iterator.remove()
Iterator<String> it = list.iterator();
while (it.hasNext()) {
    if (it.next().equals("b")) it.remove(); // safe!
}

// Fix Java 8+: removeIf
list.removeIf(s -> s.equals("b"));
```

**Cơ chế**: `modCount` — mỗi structural modification tăng `modCount`. Iterator snapshot `modCount` lúc tạo, mỗi lần `next()` check → không khớp thì throw `ConcurrentModificationException`.

### Weakly consistent / snapshot iterator (ConcurrentHashMap, CopyOnWriteArrayList...)
```java
// CopyOnWriteArrayList: mỗi write tạo bản copy mới
CopyOnWriteArrayList<String> list = new CopyOnWriteArrayList<>(List.of("a", "b", "c"));
for (String s : list) {
    list.add("new"); // KHÔNG throw exception – iterator đọc bản copy cũ
}
// Phù hợp: đọc nhiều, ghi ít
```

> 💡 **Giải thích dễ hiểu — hai kiểu iterator đều không phải “đảm bảo thấy mọi thay đổi”:**
> Fail-fast của ArrayList/HashMap chỉ là cảnh báo best-effort khi phát hiện sửa cấu trúc ngoài iterator; không được dùng nó để đồng bộ. CopyOnWriteArrayList đọc snapshot cũ, còn ConcurrentHashMap iterator weakly consistent: không ném lỗi và có thể thấy một phần thay đổi. Nếu cần snapshot nhất quán, hãy tạo bản sao hoặc đồng bộ theo transaction riêng.

---

## How – Comparable vs Comparator

### Comparable – Natural Ordering (implemented bởi chính class)
```java
public class Student implements Comparable<Student> {
    private String name;
    private double gpa;

    @Override
    public int compareTo(Student other) {
        return Double.compare(other.gpa, this.gpa); // sort by GPA descending
    }
}

List<Student> students = new ArrayList<>(students);
Collections.sort(students); // dùng Comparable
students.sort(null);        // tương đương
```

> 💡 **Giải thích dễ hiểu — Comparable là “thứ tự hộ chiếu” của class:**
> Một class chỉ nên có natural ordering rõ ràng, ổn định và thường tương thích với `equals` nếu được dùng trong sorted set/map. Nếu cùng object cần nhiều cách sắp xếp hoặc không có thứ tự tự nhiên, đừng nhồi tất cả vào `compareTo`; dùng Comparator bên ngoài.

### Comparator – Custom Ordering (tách rời khỏi class)
```java
// Sắp xếp theo nhiều tiêu chí
Comparator<Student> byName = Comparator.comparing(Student::getName);
Comparator<Student> byGpaDesc = Comparator.comparingDouble(Student::getGpa).reversed();
Comparator<Student> complex = byGpaDesc.thenComparing(byName);

students.sort(complex);

// Hoặc inline
students.sort(Comparator.comparingDouble(Student::getGpa)
    .reversed()
    .thenComparing(Student::getName));
```

| | `Comparable` | `Comparator` |
|--|-------------|-------------|
| Nằm ở | Chính class | Class riêng / lambda |
| Method | `compareTo()` | `compare()` |
| Số ordering | 1 (natural) | Nhiều |
| Thay đổi? | Không (sửa class) | Dễ (tạo mới) |
| Dùng khi | Class có thứ tự tự nhiên | Cần nhiều cách sort khác nhau |

---

## When – Chọn Collection nào?

```
Cần List (thứ tự, cho phép trùng)?
  ├── Truy cập index nhiều → ArrayList
  └── Insert/Delete đầu/giữa nhiều → LinkedList (nhưng cân nhắc kỹ)

Cần Set (không trùng)?
  ├── Không cần thứ tự, tốc độ cao → HashSet
  ├── Cần giữ insertion order → LinkedHashSet
  └── Cần sorted → TreeSet

Cần Map (key-value)?
  ├── Không cần thứ tự, tốc độ cao → HashMap
  ├── Cần giữ insertion order → LinkedHashMap (cho LRU cache)
  ├── Cần sorted key → TreeMap
  └── Multi-thread → ConcurrentHashMap

Cần Queue?
  ├── FIFO đơn giản → ArrayDeque (tốt hơn LinkedList)
  ├── Priority-based → PriorityQueue
  └── Thread-safe → ArrayBlockingQueue, LinkedBlockingQueue
```

> 💡 **Giải thích dễ hiểu — đừng chọn LinkedList chỉ vì nó vừa là List vừa là Queue:**
> Nếu cần queue/deque thuần, ArrayDeque thường có locality tốt và ít overhead node. Nếu cần ưu tiên theo score, dùng PriorityQueue; nếu producer/consumer chạy khác thread, dùng BlockingQueue để có cơ chế chờ và backpressure thay vì tự spin hoặc tự lock.

---

## Compare – Lookup Performance

| Collection | contains/get | add | remove |
|-----------|-------------|-----|--------|
| ArrayList | O(n) | O(1) amortized | O(n) |
| LinkedList | O(n) | O(1) | O(n) tìm + O(1) xóa |
| HashSet/HashMap | O(1) avg | O(1) avg | O(1) avg |
| TreeSet/TreeMap | O(log n) | O(log n) | O(log n) |
| PriorityQueue | peek O(1), contains O(n) | O(log n) | poll O(log n) |

---

## Trade-offs

| Collection | Ưu | Nhược |
|-----------|-----|-------|
| ArrayList | O(1) random access, cache-friendly | Resize cost, insert giữa chậm |
| LinkedList | Insert đầu/cuối O(1) | Memory overhead, cache-miss |
| HashMap | O(1) avg | Không có thứ tự, worst O(n) nếu hashCode tệ |
| TreeMap | Sorted, range query | O(log n) mọi op |
| ConcurrentHashMap | Thread-safe hiệu suất cao | Không hỗ trợ null |
| CopyOnWriteArrayList | Thread-safe, iterator an toàn | Ghi chậm (copy toàn bộ) |

---

## Real-world Usage (Production)

### 1. LRU Cache với LinkedHashMap
```java
public class LRUCache<K, V> extends LinkedHashMap<K, V> {
    private final int capacity;

    public LRUCache(int capacity) {
        super(capacity, 0.75f, true); // accessOrder = true!
        this.capacity = capacity;
    }

    @Override
    protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
        return size() > capacity; // tự động xóa entry cũ nhất khi đầy
    }
}

LRUCache<Integer, String> cache = new LRUCache<>(3);
cache.put(1, "one"); cache.put(2, "two"); cache.put(3, "three");
cache.get(1);         // access 1 → 1 becomes most recent
cache.put(4, "four"); // evict 2 (least recently used)
```

> 💡 **Giải thích dễ hiểu — LRU này là cấu trúc local, chưa phải cache phân tán:**
> `accessOrder=true` đưa entry vừa đọc về cuối danh sách liên kết; entry đầu là nạn nhân ít dùng nhất. Ví dụ phù hợp một thread hoặc cần bọc lock/đưa vào cache library khi nhiều thread. Production cache còn phải quyết định TTL, giới hạn memory, serialize và chiến lược invalidation.

### 2. Producer-Consumer với BlockingQueue
```java
BlockingQueue<Task> queue = new ArrayBlockingQueue<>(100);

// Producer thread
executor.submit(() -> {
    while (running) {
        Task task = fetchTask();
        queue.put(task); // block nếu queue đầy
    }
});

// Consumer threads
for (int i = 0; i < 4; i++) {
    executor.submit(() -> {
        while (running) {
            Task task = queue.take(); // block nếu queue trống
            process(task);
        }
    });
}
```

### 3. Frequency Count với merge()
```java
// Đếm tần suất từ
Map<String, Long> wordFreq = new HashMap<>();
Arrays.stream(text.split("\\s+"))
    .forEach(word -> wordFreq.merge(word, 1L, Long::sum));
// merge(): nếu key chưa có → put value; nếu có → apply remappingFunction
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Generics** (deep dive)
>
> Keyword: Type parameters, bounded wildcards (`? extends T`, `? super T`), PECS, type erasure implications (no `instanceof List<String>`, no `new T()`), generic methods, reifiable vs non-reifiable types, heap pollution, `@SafeVarargs`
