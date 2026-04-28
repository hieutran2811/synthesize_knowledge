# Collections Internals – Advanced Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## How – PriorityQueue Internals (Binary Heap)

`PriorityQueue` dùng **min-heap** (hoặc max-heap với Comparator): phần tử nhỏ nhất luôn ở đỉnh.

### Binary Heap = Array

```
Min-Heap được lưu trong array:
         1
       /   \
      3     2
     / \   / \
    7   4  5   6

Index: [_, 1, 3, 2, 7, 4, 5, 6]  (1-indexed cho dễ tính)
                                    hoặc
       [1, 3, 2, 7, 4, 5, 6]      (0-indexed trong Java)

Parent(i) = (i - 1) / 2
Left(i)   = 2*i + 1
Right(i)  = 2*i + 2
```

### offer() – Sift-Up (Swim)

```java
// Thêm phần tử mới vào PriorityQueue: O(log n)
// 1. Thêm vào cuối array
// 2. Sift-up: so sánh với parent, nếu nhỏ hơn → swap, lặp lại

void siftUp(int[] heap, int index) {
    while (index > 0) {
        int parent = (index - 1) / 2;
        if (heap[parent] <= heap[index]) break; // heap property satisfied
        swap(heap, parent, index);
        index = parent;
    }
}

// Ví dụ: thêm 0 vào [1, 3, 2, 7, 4, 5, 6]
// [1, 3, 2, 7, 4, 5, 6, 0]  ← thêm vào cuối (index=7)
// parent(7)=3, heap[3]=7 > 0 → swap: [1, 3, 2, 0, 4, 5, 6, 7]  (index=3)
// parent(3)=1, heap[1]=3 > 0 → swap: [1, 0, 2, 3, 4, 5, 6, 7]  (index=1)
// parent(1)=0, heap[0]=1 > 0 → swap: [0, 1, 2, 3, 4, 5, 6, 7]  (index=0)
// index=0, done
```

### poll() – Sift-Down (Sink)

```java
// Lấy min (root): O(log n)
// 1. Lấy root (min element)
// 2. Di chuyển phần tử cuối lên root
// 3. Sift-down: so sánh với children nhỏ hơn, nếu lớn hơn → swap

void siftDown(int[] heap, int index, int size) {
    while (true) {
        int smallest = index;
        int left  = 2 * index + 1;
        int right = 2 * index + 2;

        if (left < size && heap[left] < heap[smallest])   smallest = left;
        if (right < size && heap[right] < heap[smallest]) smallest = right;

        if (smallest == index) break; // heap property OK
        swap(heap, index, smallest);
        index = smallest;
    }
}
```

### Java PriorityQueue

```java
// Min-heap (default)
PriorityQueue<Integer> minHeap = new PriorityQueue<>();
minHeap.offer(5); minHeap.offer(1); minHeap.offer(3);
System.out.println(minHeap.peek()); // 1 (min)
System.out.println(minHeap.poll()); // 1, heap: [3, 5]

// Max-heap (với Comparator.reverseOrder)
PriorityQueue<Integer> maxHeap = new PriorityQueue<>(Comparator.reverseOrder());

// Custom Comparator
PriorityQueue<Task> taskQueue = new PriorityQueue<>(
    Comparator.comparingInt(Task::getPriority)
              .thenComparingLong(Task::getCreatedAt) // tiebreaker: FIFO
);

// heapify từ Collection: O(n) thay vì O(n log n) khi add từng cái
PriorityQueue<Integer> pq = new PriorityQueue<>(List.of(5, 3, 1, 4, 2));
// Constructor dùng Floyd's heapify algorithm: O(n)

// Top-K pattern (K phần tử lớn nhất)
PriorityQueue<Integer> topK = new PriorityQueue<>(k); // min-heap size k
for (int num : numbers) {
    topK.offer(num);
    if (topK.size() > k) topK.poll(); // loại phần tử nhỏ nhất
}
// topK chứa K phần tử lớn nhất

// Performance
// offer(): O(log n)
// poll(): O(log n)
// peek(): O(1)  ← luôn O(1)!
// contains(): O(n)  ← linear scan (không có index)
// remove(Object): O(n) để tìm + O(log n) để sift
```

---

## How – ArrayDeque Internals (Circular Buffer)

`ArrayDeque` là **double-ended queue** dùng **circular array** — nhanh hơn `LinkedList` và `Stack`.

### Circular Buffer

```
Circular array, head và tail pointer:

Initial (capacity=8):
array: [_, _, _, _, _, _, _, _]
        0  1  2  3  4  5  6  7
head=0, tail=0 (empty)

After addLast(A), addLast(B), addLast(C):
array: [A, B, C, _, _, _, _, _]
head=0, tail=3

After addFirst(X):
array: [A, B, C, _, _, _, _, X]
                              ↑ head wraps to 7!
head=7, tail=3

After addFirst(Y):
array: [A, B, C, _, _, _, Y, X]
head=6, tail=3

Circular: index = (head - 1 + capacity) & (capacity - 1)
                                          ↑ bitmask (capacity luôn là power of 2)
```

```java
// Internals (simplified)
class ArrayDeque<E> {
    Object[] elements;
    int head; // index of head element
    int tail; // index AFTER tail element

    void addLast(E e) {
        elements[tail] = e;
        tail = (tail + 1) & (elements.length - 1); // circular increment
        if (tail == head) grow(); // full → double capacity
    }

    void addFirst(E e) {
        head = (head - 1) & (elements.length - 1); // circular decrement
        elements[head] = e;
        if (head == tail) grow();
    }

    E pollFirst() {
        E e = (E) elements[head];
        elements[head] = null; // GC
        head = (head + 1) & (elements.length - 1);
        return e;
    }
}
```

```java
// ArrayDeque vs Stack
// Java Stack (extends Vector): synchronized, legacy, avoid!
Stack<Integer> stack = new Stack<>();

// ArrayDeque as stack (preferred)
Deque<Integer> stack2 = new ArrayDeque<>();
stack2.push(1);  // = addFirst
stack2.pop();    // = removeFirst
stack2.peek();   // = peekFirst

// ArrayDeque as queue
Deque<Integer> queue = new ArrayDeque<>();
queue.offer(1);  // = addLast
queue.poll();    // = removeFirst
queue.peek();    // = peekFirst

// Performance: ArrayDeque beats LinkedList in most cases
// Cache-friendly (contiguous memory vs node chasing in LinkedList)
// No object overhead per element (vs Node in LinkedList)
// Only exception: insertion in middle (but Deque rarely does that)
```

---

## How – EnumSet (Bit Vector)

`EnumSet` là implementation **cực kỳ hiệu quả** cho Set của enum values — dùng bit manipulation.

```java
// Cấu trúc: long (64 bit) cho enum ≤ 64 values
// Mỗi bit position = 1 enum value (theo ordinal)
// enum Day { MON=0, TUE=1, WED=2, THU=3, FRI=4, SAT=5, SUN=6 }

// EnumSet.of(MON, WED, FRI):
//   long elements = 0b0010101 = 21
//   bit 0 = MON, bit 2 = WED, bit 4 = FRI

// add(WED): elements |= (1L << WED.ordinal()) = elements | 4
// remove(WED): elements &= ~(1L << WED.ordinal())
// contains(WED): (elements & (1L << WED.ordinal())) != 0

// RegularEnumSet: ≤ 64 values → 1 long
// JumboEnumSet: > 64 values → long[]

// Performance: O(1) for all basic operations!
// Iteration: bit scan, O(n) but constant per bit

enum Day { MON, TUE, WED, THU, FRI, SAT, SUN }

// Tạo EnumSet
EnumSet<Day> weekdays  = EnumSet.of(Day.MON, Day.TUE, Day.WED, Day.THU, Day.FRI);
EnumSet<Day> weekend   = EnumSet.of(Day.SAT, Day.SUN);
EnumSet<Day> allDays   = EnumSet.allOf(Day.class);
EnumSet<Day> noDays    = EnumSet.noneOf(Day.class);
EnumSet<Day> complement = EnumSet.complementOf(weekdays); // weekend
EnumSet<Day> copy       = EnumSet.copyOf(weekdays);

// Range
EnumSet<Day> midweek = EnumSet.range(Day.TUE, Day.THU); // TUE, WED, THU

// Set operations (all O(1) or O(n) based on enum size):
weekdays.containsAll(EnumSet.of(Day.MON, Day.TUE)); // true, O(1)
weekdays.retainAll(EnumSet.of(Day.MON, Day.WED));   // intersection in-place
```

---

## How – EnumMap (Array-based)

`EnumMap` dùng **array indexed by enum ordinal** — nhanh và compact hơn `HashMap<Enum, V>`.

```java
// Internal: Object[] values, indexed by enum.ordinal()
// values[0] = value for first enum constant
// O(1) get/put với KHÔNG CÓ hashing, collision, boxing

EnumMap<Day, String> schedule = new EnumMap<>(Day.class);
schedule.put(Day.MON, "Meeting");
schedule.put(Day.FRI, "Review");

// Tốc độ: ~2-4x nhanh hơn HashMap<Day, String>
// Memory: compact array thay vì hash table với entry objects

// Iteration order: enum declaration order (not insertion order)
schedule.forEach((day, event) -> System.out.println(day + ": " + event));
// MON: Meeting
// FRI: Review  (skip TUE, WED, THU: null)

// Dùng khi: key là enum type → luôn prefer EnumMap over HashMap
```

---

## How – WeakHashMap

Key là `WeakReference` → key bị GC khi không còn strong reference → entry tự động xóa.

```java
// Dùng cho: cache không muốn prevent GC của key objects
WeakHashMap<Widget, WidgetData> cache = new WeakHashMap<>();

Widget button = new Button("OK");
cache.put(button, new WidgetData());

System.out.println(cache.size()); // 1

button = null; // strong reference mất
System.gc();   // hint GC (không đảm bảo ngay)
System.out.println(cache.size()); // có thể 0 (entry đã bị GC!)

// Cơ chế:
// Key là WeakReference → GC xóa key → đưa WeakReference vào ReferenceQueue
// WeakHashMap poll ReferenceQueue mỗi lần mutate → xóa stale entries

// KHÔNG THREAD-SAFE! Cần:
Map<Widget, WidgetData> safeCache = Collections.synchronizedMap(new WeakHashMap<>());

// Use case thực tế:
// - Listener registry (listener tự remove khi widget bị GC)
// - Metadata cho objects mà không prevent GC
// - Canonicalization mapping

// CẢNH BÁO: key phải có strong ref ở đâu đó nếu muốn giữ entry!
// Dùng String literal → String pool là strong ref → entry không bị xóa
WeakHashMap<String, Data> map = new WeakHashMap<>();
map.put("hello", data); // "hello" in pool, never GC'd → entry permanent!
map.put(new String("hello"), data); // NO pool → entry sẽ bị GC!
```

---

## How – IdentityHashMap

Dùng `==` (reference equality) thay vì `equals()` để so sánh key.

```java
// HashMap: key equality = equals() + hashCode()
// IdentityHashMap: key equality = == (reference identity) + System.identityHashCode()

IdentityHashMap<String, Integer> map = new IdentityHashMap<>();
String a = new String("hello");
String b = new String("hello");

map.put(a, 1);
map.put(b, 2); // KHÁC KEY dù a.equals(b)! Vì a != b (khác reference)

System.out.println(map.size()); // 2!
System.out.println(map.get(a)); // 1
System.out.println(map.get(b)); // 2

// Cấu trúc: open-addressing array (không dùng chaining)
// Performance: nhanh cho reference identity checks

// Use case:
// 1. Object graph traversal (tránh cycle bằng cách track visited objects)
Set<Object> visited = Collections.newSetFromMap(new IdentityHashMap<>());
void traverse(Object obj) {
    if (!visited.add(obj)) return; // đã thấy (same reference)
    // process...
}

// 2. Serialization framework (track object identity để handle shared refs)
// 3. Proxy detection (proxy != original dù equals() có thể true)
```

---

## How – Java 9+ Immutable Collections

`List.of()`, `Set.of()`, `Map.of()` — compact, unmodifiable, null-disallowed.

### Internals

```java
// List.of(1, 2, 3):
// 0-2 elements: specialized classes (List0, List1, List2)
// 3-10 elements: ImmutableCollections.ListN (stores in Object[])
// > 10: same ListN

// Compact array layout:
// [1, 2, 3] stored in minimal Object[]
// NO null allowed (throws NullPointerException)
// Iteration order preserved for List.of() and Map.entry()

// Set.of(1, 2, 3):
// Uses hash table without LinkedList (no chaining)
// Randomly shuffled internally (iteration order NOT guaranteed!)
// Duplicates throw IllegalArgumentException

// Map.of(k1, v1, k2, v2, ...):
// Up to 10 key-value pairs (Map.of() overloads)
// > 10 pairs: Map.ofEntries(Map.entry(k, v), ...)
// Randomly shuffled internally

List<String> list  = List.of("a", "b", "c");
Set<String>  set   = Set.of("x", "y", "z");
Map<String, Integer> map = Map.of("one", 1, "two", 2);
Map<String, Integer> map2 = Map.ofEntries(
    Map.entry("one", 1),
    Map.entry("two", 2),
    Map.entry("three", 3)
);

// Unmodifiable: throws UnsupportedOperationException
list.add("d"); // throws!
map.put("four", 4); // throws!

// Copy factory (Java 10+): mutable → immutable
List<String> mutable = new ArrayList<>(List.of("a", "b"));
mutable.add("c");
List<String> immutable = List.copyOf(mutable); // snapshot

// Collections.unmodifiable* vs List.of():
// unmodifiableList: wrapper around mutable list, mutations visible through original!
List<String> original = new ArrayList<>(List.of("a", "b"));
List<String> view = Collections.unmodifiableList(original);
original.add("c"); // view.get(2) = "c" now! (not truly immutable!)

// List.of(): truly immutable, never changes
```

---

## How – Spliterator (Parallel Stream Engine)

`Spliterator` là iterator hỗ trợ **split** cho parallel processing.

```java
// Spliterator characteristics (bit flags)
Spliterator<String> sp = list.spliterator();
sp.characteristics(); // ORDERED | SIZED | SUBSIZED | IMMUTABLE (for List.of)

// Key characteristics:
// ORDERED: encounter order defined
// SIZED: knows exact size (estimateSize() is exact)
// SUBSIZED: splits also know their size
// SORTED: elements are sorted
// DISTINCT: no duplicates
// IMMUTABLE: source won't change
// CONCURRENT: can be modified concurrently

// tryAdvance: like Iterator.next() but returns boolean
sp.tryAdvance(element -> process(element));

// forEachRemaining: process all remaining
sp.forEachRemaining(element -> process(element));

// trySplit: split into two roughly equal parts (for parallel)
Spliterator<String> prefix = sp.trySplit(); // prefix gets first half
// sp now covers second half
// prefix == null: cannot split further

// Custom Spliterator (for custom data structure)
class RangeSpliterator implements Spliterator<Integer> {
    private int current, end;

    RangeSpliterator(int start, int end) {
        this.current = start; this.end = end;
    }

    @Override
    public boolean tryAdvance(Consumer<? super Integer> action) {
        if (current >= end) return false;
        action.accept(current++);
        return true;
    }

    @Override
    public Spliterator<Integer> trySplit() {
        int mid = (current + end) >>> 1;
        if (mid <= current) return null; // too small to split
        RangeSpliterator prefix = new RangeSpliterator(current, mid);
        this.current = mid;
        return prefix;
    }

    @Override
    public long estimateSize() { return end - current; }

    @Override
    public int characteristics() {
        return ORDERED | SIZED | SUBSIZED | IMMUTABLE | DISTINCT;
    }
}

// Tạo Stream từ Spliterator
Stream<Integer> stream = StreamSupport.stream(
    new RangeSpliterator(0, 1_000_000),
    true // parallel = true
);
```

---

## How – Collections Utility Class (Deep Dive)

```java
List<Integer> list = new ArrayList<>(List.of(3, 1, 4, 1, 5, 9, 2, 6));

// Sort
Collections.sort(list);                  // [1, 1, 2, 3, 4, 5, 6, 9]
Collections.sort(list, Comparator.reverseOrder()); // [9, 6, 5, 4, 3, 2, 1, 1]

// Binary search (PHẢI sorted trước!)
Collections.sort(list);
int idx = Collections.binarySearch(list, 5); // index của 5 (nếu tồn tại)
// Returns: index (nếu found) hoặc -(insertion_point) - 1 (nếu not found)

// Shuffle (random permutation)
Collections.shuffle(list); // in-place random shuffle
Collections.shuffle(list, new Random(42)); // seeded for reproducibility

// Rotate
Collections.rotate(list, 3); // shift right by 3 (circular)
// [1,2,3,4,5] rotate 2 → [4,5,1,2,3]

// Reverse
Collections.reverse(list); // in-place reverse

// Fill + Copy
Collections.fill(list, 0);          // fill tất cả với 0
List<Integer> dest = new ArrayList<>(list.size());
Collections.copy(dest, list);        // dest phải đủ lớn!

// Frequency & disjoint
int freq = Collections.frequency(list, 1); // đếm số lần xuất hiện của 1
boolean noCommon = Collections.disjoint(list1, list2); // true nếu không có phần tử chung

// Min/Max
int min = Collections.min(list);
int max = Collections.max(list, Comparator.reverseOrder()); // min với custom comparator

// Singletons (immutable, cached)
List<String> single = Collections.singletonList("only");  // size=1, immutable
Set<String>  singleSet = Collections.singleton("only");
Map<String, Integer> singleMap = Collections.singletonMap("key", 1);

// nCopies: immutable list with n copies of same element
List<String> zeros = Collections.nCopies(10, "zero"); // ["zero", "zero", ...]

// Wrappers
List<String> sync = Collections.synchronizedList(new ArrayList<>());
// WARNING: iteration STILL needs external synchronization!
synchronized (sync) {
    for (String s : sync) { process(s); } // lock for iteration
}

List<String> unmod = Collections.unmodifiableList(new ArrayList<>(list));
// View: mutations on original list ARE visible here
// Prefer List.copyOf() for true immutability

Set<String> checked = Collections.checkedSet(new HashSet<>(), String.class);
// Type-checked at runtime (for interoperability with legacy raw types)
checked.add("ok");  // fine
// Raw type bypass attempt:
((Set) checked).add(42); // throws ClassCastException at runtime!
```

---

## How – Deque vs Queue Interface Methods

```java
// Queue methods (throw exception on failure):
queue.add(e);    // throws IllegalStateException if full
queue.remove();  // throws NoSuchElementException if empty
queue.element(); // throws NoSuchElementException if empty

// Queue methods (return special value):
queue.offer(e);  // returns false if full
queue.poll();    // returns null if empty
queue.peek();    // returns null if empty

// Deque additional:
deque.addFirst(e);   deque.offerFirst(e);
deque.addLast(e);    deque.offerLast(e);
deque.removeFirst(); deque.pollFirst();
deque.removeLast();  deque.pollLast();
deque.getFirst();    deque.peekFirst();
deque.getLast();     deque.peekLast();
deque.push(e);       // = addFirst (stack)
deque.pop();         // = removeFirst (stack)

// ArrayDeque as stack (PREFERRED over Stack class):
Deque<T> stack = new ArrayDeque<>();
stack.push(item);  stack.pop();  stack.peek();

// ArrayDeque as queue (PREFERRED over LinkedList):
Queue<T> queue2 = new ArrayDeque<>();
queue2.offer(item); queue2.poll(); queue2.peek();
```

---

## Components – Collection Selection Guide (Expanded)

| Need | Options | Prefer |
|------|---------|--------|
| Ordered, indexed | ArrayList, LinkedList | ArrayList (cache-friendly) |
| Stack (LIFO) | ArrayDeque, Stack | ArrayDeque |
| Queue (FIFO) | ArrayDeque, LinkedList | ArrayDeque |
| Priority queue | PriorityQueue | PriorityQueue (min-heap) |
| Deque (both ends) | ArrayDeque, LinkedList | ArrayDeque |
| Unique elements | HashSet, LinkedHashSet, TreeSet | HashSet (if order N/A) |
| Sorted unique | TreeSet | TreeSet |
| Enum set | EnumSet | EnumSet (bit vector!) |
| Key-value, fast | HashMap | HashMap |
| Insertion-ordered map | LinkedHashMap | LinkedHashMap |
| Sorted map | TreeMap | TreeMap |
| Enum key | EnumMap | EnumMap (array-based!) |
| Weak key map | WeakHashMap | WeakHashMap |
| Reference identity | IdentityHashMap | IdentityHashMap |
| Thread-safe map | ConcurrentHashMap | ConcurrentHashMap |
| Thread-safe list (read-heavy) | CopyOnWriteArrayList | CopyOnWriteArrayList |
| Thread-safe queue | ArrayBlockingQueue, LinkedBlockingQueue | ArrayBlockingQueue (bounded) |
| Immutable collection | List.of(), Set.of(), Map.of() | List/Set/Map.of() (Java 9+) |

---

## Trade-offs

| Collection | Time | Space | Thread-safe | Null | Order |
|-----------|------|-------|------------|------|-------|
| ArrayList | O(1) get | Low | No | Yes | Insertion |
| ArrayDeque | O(1) ends | Low | No | No | Insertion |
| PriorityQueue | O(log n) poll/offer | Low | No | No | Priority |
| EnumSet | O(1) | Minimal (bit) | No | No | Enum declaration |
| EnumMap | O(1) | Minimal (array) | No | No | Enum declaration |
| WeakHashMap | O(1) avg | Varies (GC) | No | Key: No | None |
| List.of() | O(1) get | Compact | N/A | No | Insertion |
| Set.of() | O(1) contains | Compact | N/A | No | Random! |

---

## Real-world Usage (Production)

### 1. Dijkstra's Shortest Path với PriorityQueue

```java
public Map<Integer, Integer> dijkstra(int source, int[][] graph) {
    int n = graph.length;
    int[] dist = new int[n];
    Arrays.fill(dist, Integer.MAX_VALUE);
    dist[source] = 0;

    // [distance, node] min-heap
    PriorityQueue<int[]> pq = new PriorityQueue<>(Comparator.comparingInt(a -> a[0]));
    pq.offer(new int[]{0, source});

    while (!pq.isEmpty()) {
        int[] curr = pq.poll(); // O(log n)
        int currDist = curr[0], node = curr[1];

        if (currDist > dist[node]) continue; // stale entry

        for (int[] neighbor : getNeighbors(graph, node)) {
            int newDist = dist[node] + neighbor[1];
            if (newDist < dist[neighbor[0]]) {
                dist[neighbor[0]] = newDist;
                pq.offer(new int[]{newDist, neighbor[0]}); // O(log n)
            }
        }
    }
    return toMap(dist);
}
```

### 2. EnumMap cho State Machine

```java
enum OrderStatus { PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED }

// Map mỗi trạng thái → danh sách trạng thái hợp lệ tiếp theo
private static final Map<OrderStatus, Set<OrderStatus>> TRANSITIONS =
    new EnumMap<>(OrderStatus.class);

static {
    TRANSITIONS.put(PENDING,   EnumSet.of(CONFIRMED, CANCELLED));
    TRANSITIONS.put(CONFIRMED, EnumSet.of(SHIPPED, CANCELLED));
    TRANSITIONS.put(SHIPPED,   EnumSet.of(DELIVERED));
    TRANSITIONS.put(DELIVERED, EnumSet.noneOf(OrderStatus.class)); // terminal
    TRANSITIONS.put(CANCELLED, EnumSet.noneOf(OrderStatus.class)); // terminal
}

public void transitionTo(OrderStatus next) {
    Set<OrderStatus> valid = TRANSITIONS.get(this.status); // O(1) EnumMap lookup
    if (!valid.contains(next)) {                            // O(1) EnumSet contains
        throw new InvalidTransitionException(this.status, next);
    }
    this.status = next;
}
```

### 3. WeakHashMap cho Metadata Cache

```java
// Cache metadata về objects mà không prevent GC
@Component
public class ObjectMetadataCache {
    // Key: object reference (weak) → entry xóa khi object bị GC
    private final Map<Object, ObjectMetadata> cache =
        Collections.synchronizedMap(new WeakHashMap<>());

    public ObjectMetadata getOrCompute(Object obj) {
        return cache.computeIfAbsent(obj, k -> computeMetadata(k));
    }
    // Không cần manual cache eviction! GC tự dọn khi object không còn dùng
}
```

### 4. Immutable Collections cho Configuration

```java
@Configuration
public class AppConfig {
    // Immutable config map (fail-fast: NullPointerException nếu ai put null)
    public static final Map<String, String> DEFAULTS = Map.of(
        "timeout",      "30s",
        "retry.count",  "3",
        "retry.delay",  "1s"
    );

    // Immutable whitelist
    public static final Set<String> ALLOWED_ORIGINS = Set.of(
        "https://app.example.com",
        "https://admin.example.com"
    );

    // Merge immutable defaults with mutable overrides
    public Map<String, String> effectiveConfig(Map<String, String> overrides) {
        Map<String, String> result = new HashMap<>(DEFAULTS);
        result.putAll(overrides);
        return Collections.unmodifiableMap(result); // freeze the merged result
    }
}
```

---

## Ghi chú – Chủ đề liên quan

> Xem thêm:
> - **collections.md**: ArrayList/HashMap/ConcurrentHashMap nền tảng
> - **concurrency.md**: BlockingQueue, ConcurrentHashMap thread-safety
> - **concurrency_advanced.md**: lock-free, CAS patterns trong collections
> - **streams.md**: Spliterator được dùng bởi Stream API, parallel streams
