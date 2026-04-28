# Generics (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Generics là gì?

**Generics** (Java 5+) cho phép định nghĩa class, interface, method với **type parameters** — placeholder cho kiểu dữ liệu cụ thể được cung cấp khi sử dụng.

**Trước Generics (Java < 5):**
```java
List list = new ArrayList();
list.add("hello");
list.add(42);           // OK lúc compile, WRONG về semantic
String s = (String) list.get(1); // ClassCastException tại RUNTIME!
```

**Với Generics:**
```java
List<String> list = new ArrayList<>();
list.add("hello");
// list.add(42);        // COMPILE ERROR – phát hiện sớm!
String s = list.get(0); // không cần cast
```

---

## How – Type Parameters

### Naming Convention
| Symbol | Meaning |
|--------|---------|
| `T` | Type |
| `E` | Element (Collections) |
| `K`, `V` | Key, Value (Map) |
| `N` | Number |
| `R` | Return type |
| `S`, `U`, `V` | 2nd, 3rd, 4th type |

### Generic Class
```java
public class Pair<A, B> {
    private final A first;
    private final B second;

    public Pair(A first, B second) {
        this.first = first;
        this.second = second;
    }

    public A getFirst() { return first; }
    public B getSecond() { return second; }

    // static factory: compiler infer type từ arguments
    public static <A, B> Pair<A, B> of(A first, B second) {
        return new Pair<>(first, second);
    }

    @Override
    public String toString() { return "(" + first + ", " + second + ")"; }
}

// Dùng:
Pair<String, Integer> nameAge = Pair.of("Alice", 30);
Pair<Double, Double> coordinates = new Pair<>(10.5, 20.3);
```

### Generic Interface
```java
public interface Transformer<T, R> {
    R transform(T input);

    default <V> Transformer<T, V> andThen(Transformer<R, V> after) {
        return input -> after.transform(this.transform(input));
    }
}

// Implementation
Transformer<String, Integer> length = String::length;
Transformer<Integer, Boolean> isEven = n -> n % 2 == 0;
Transformer<String, Boolean> isEvenLength = length.andThen(isEven);

isEvenLength.transform("hello"); // false (5 là lẻ)
isEvenLength.transform("java");  // true (4 là chẵn)
```

### Generic Method
```java
public class Utils {
    // T được infer từ arguments
    public static <T extends Comparable<T>> T max(T a, T b) {
        return a.compareTo(b) >= 0 ? a : b;
    }

    // Swap 2 elements trong array
    public static <T> void swap(T[] arr, int i, int j) {
        T temp = arr[i]; arr[i] = arr[j]; arr[j] = temp;
    }

    // Return multiple values
    public static <K, V> Map.Entry<K, V> entry(K key, V value) {
        return Map.entry(key, value);
    }
}

int max = Utils.max(3, 7);           // compiler infer T = Integer
String maxStr = Utils.max("a", "z"); // compiler infer T = String
```

---

## How – Bounded Type Parameters

### Upper Bound: `<T extends SomeType>`
```java
// T phải là SomeType hoặc subtype của nó
public <T extends Number> double sum(List<T> list) {
    return list.stream()
        .mapToDouble(Number::doubleValue)
        .sum();
}

sum(List.of(1, 2, 3));         // OK – Integer extends Number
sum(List.of(1.5, 2.5));       // OK – Double extends Number
// sum(List.of("a", "b"));    // COMPILE ERROR

// Multiple bounds (& syntax)
public <T extends Comparable<T> & Serializable> T findMax(List<T> list) {
    return Collections.max(list);
}
```

### Multiple Bounds – Thứ tự quan trọng
```java
// Class phải đứng trước interface
<T extends AbstractBase & Interface1 & Interface2>  // ĐÚNG
// <T extends Interface1 & AbstractBase>            // SAI – class phải đứng đầu
```

---

## How – Wildcards

### 1. Unbounded Wildcard `<?>`
```java
// Chấp nhận List của bất kỳ type nào
public void printList(List<?> list) {
    for (Object item : list) {
        System.out.println(item); // chỉ đọc được dưới dạng Object
    }
}

printList(List.of(1, 2, 3));
printList(List.of("a", "b"));
// Không thể add phần tử vào List<?> (trừ null)
```

### 2. Upper Bounded Wildcard `<? extends T>` — Producer
```java
// Đọc phần tử ra (producer)
public double sumList(List<? extends Number> list) {
    return list.stream().mapToDouble(Number::doubleValue).sum();
}

sumList(new ArrayList<Integer>());  // OK
sumList(new ArrayList<Double>());   // OK
sumList(new ArrayList<Number>());   // OK

// KHÔNG THỂ add vào List<? extends Number>:
// list.add(1);   // Compiler error! Vì không biết exact type
// list.add(1.0); // Compiler error!
```

### 3. Lower Bounded Wildcard `<? super T>` — Consumer
```java
// Ghi phần tử vào (consumer)
public void addNumbers(List<? super Integer> list) {
    for (int i = 1; i <= 5; i++) {
        list.add(i); // OK – Integer IS-A type
    }
}

addNumbers(new ArrayList<Integer>());  // OK
addNumbers(new ArrayList<Number>());   // OK
addNumbers(new ArrayList<Object>());   // OK
// addNumbers(new ArrayList<Double>()); // COMPILE ERROR
```

### PECS – Producer Extends, Consumer Super
```java
// copy từ src vào dest
public static <T> void copy(List<? super T> dest, List<? extends T> src) {
    for (T item : src) {  // src produce T
        dest.add(item);   // dest consume T
    }
}

List<Number> numbers = new ArrayList<>(List.of(1.0, 2.0));
List<Integer> ints = List.of(3, 4, 5);
copy(numbers, ints); // ĐÚNG: dest=List<Number>(super Integer), src=List<Integer>(extends Number)
```

```
         <? extends T>    <? super T>    <T>
Read (get)     T              Object      T
Write (add)    Không được     T           T
Mnemonic       Producer       Consumer    Both
```

---

## How – Type Erasure

**Type Erasure** = compiler xóa tất cả type parameter tại compile-time, thay bằng bound hoặc `Object`:

```java
// Source code
public class Box<T> {
    private T value;
    public T get() { return value; }
}

// Sau khi erasure (bytecode level)
public class Box {
    private Object value;
    public Object get() { return value; }
}

// Với bound:
// <T extends Number> → T bị thay bằng Number
```

### Hệ quả của Type Erasure

**1. Không thể dùng `instanceof` với parameterized type:**
```java
List<String> strings = new ArrayList<>();
// if (strings instanceof List<String>) // COMPILE ERROR
if (strings instanceof List<?>) { }     // OK – unbounded wildcard
if (strings instanceof List) { }        // OK – raw type
```

**2. Không thể tạo instance của type parameter:**
```java
public class Container<T> {
    private T value;
    // value = new T();  // COMPILE ERROR – không biết constructor của T
}

// Fix: dùng Supplier hoặc Class<T>
public class Container<T> {
    private T value;
    public Container(Supplier<T> supplier) { this.value = supplier.get(); }
    // hoặc
    public Container(Class<T> clazz) throws Exception {
        this.value = clazz.getDeclaredConstructor().newInstance();
    }
}
```

**3. Không thể tạo generic array:**
```java
// T[] arr = new T[10];         // COMPILE ERROR
Object[] arr = new Object[10];  // workaround (kém)
@SuppressWarnings("unchecked")
T[] arr = (T[]) new Object[10]; // cast (cẩn thận heap pollution)
```

**4. Overloading bị giới hạn:**
```java
void process(List<String> list) { }
// void process(List<Integer> list) { } // COMPILE ERROR – same erasure: process(List)
```

**5. Static members không dùng được type parameter của class:**
```java
public class Singleton<T> {
    // private static T instance; // COMPILE ERROR – T không tồn tại ở class level (static)
}
```

---

## How – Reifiable vs Non-Reifiable Types

**Reifiable**: type đầy đủ thông tin tại runtime
- Primitive types, raw types, unbounded wildcards, non-generic classes
- `int`, `String`, `List`, `List<?>`

**Non-Reifiable**: type bị erasure mất thông tin
- `List<String>`, `List<Integer>`, `T`, `? extends Number`

```java
// Reifiable → có thể dùng với instanceof, new, varargs
Object[] arr = new String[10]; // OK
new ArrayList<String>();        // OK

// Non-reifiable → không thể
// new List<String>[10];        // COMPILE ERROR – generic array creation
```

---

## How – Heap Pollution & @SafeVarargs

```java
// Heap pollution: variable của parameterized type refer đến object không phải type đó
List<String> strings = new ArrayList<>();
List rawList = strings;         // unchecked warning
rawList.add(42);                // heap pollution! List<String> có Integer
String s = strings.get(0);     // ClassCastException!

// Varargs với generics → tiềm ẩn heap pollution
public static <T> List<T> asList(T... elements) { // T[] là non-reifiable → unsafe!
    return Arrays.asList(elements);
}

// @SafeVarargs: cam kết với compiler rằng method không gây heap pollution
@SafeVarargs
public static <T> List<T> listOf(T... elements) {
    return Collections.unmodifiableList(Arrays.asList(elements));
}
```

---

## Components – Generics với Collections

### Type-safe Heterogeneous Container
```java
// Typesafe container: lưu object của nhiều type nhưng vẫn type-safe
public class TypeSafeContainer {
    private final Map<Class<?>, Object> map = new HashMap<>();

    public <T> void put(Class<T> type, T value) {
        map.put(type, type.cast(value));
    }

    public <T> T get(Class<T> type) {
        return type.cast(map.get(type));
    }
}

TypeSafeContainer container = new TypeSafeContainer();
container.put(String.class, "Hello");
container.put(Integer.class, 42);
container.put(Class.class, String.class);

String s = container.get(String.class);   // "Hello" – no cast needed
Integer i = container.get(Integer.class); // 42
```

---

## When – Khi nào dùng gì?

| Tình huống | Dùng |
|-----------|------|
| Collection với 1 type cụ thể | `List<T>`, `Map<K,V>` |
| Method nhận "bất kỳ List nào để đọc" | `List<? extends T>` |
| Method nhận "List để ghi Integer vào" | `List<? super Integer>` |
| Method xử lý object mà không quan tâm type | `List<?>` |
| Cần type info tại runtime | `Class<T>` token |

---

## Compare – Generics vs Raw Type vs Object

| | `List<String>` | `List` (raw) | `List<Object>` |
|--|----------------|-------------|----------------|
| Type-safe | Có | Không | Chỉ với Object |
| Nhận `List<Integer>` | Không | Có | Không |
| Cần cast khi get | Không | Có | Có |
| Compiler warning | Không | Có | Không |
| Nên dùng | Luôn | Không nên | Khi thực sự muốn List của Object |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Type safety tại compile-time | Type erasure → mất info tại runtime |
| Không cần cast | Không thể tạo generic array |
| Tái sử dụng code | Không dùng được với primitive (`List<int>` → `List<Integer>`) |
| Biểu đạt intent rõ ràng | Wildcard syntax phức tạp |

---

## Real-world Usage (Production)

### 1. Generic Repository
```java
public interface Repository<T, ID> {
    Optional<T> findById(ID id);
    List<T> findAll();
    T save(T entity);
    void deleteById(ID id);
    boolean existsById(ID id);
}

// Generic implementation
public abstract class JpaRepository<T, ID> implements Repository<T, ID> {
    private final Class<T> entityClass;
    private final EntityManager em;

    protected JpaRepository(Class<T> entityClass, EntityManager em) {
        this.entityClass = entityClass;
        this.em = em;
    }

    @Override
    public Optional<T> findById(ID id) {
        return Optional.ofNullable(em.find(entityClass, id));
    }
}

// Concrete
public class UserRepository extends JpaRepository<User, Long> {
    public UserRepository(EntityManager em) { super(User.class, em); }
}
```

### 2. Result Type (Monadic pattern)
```java
public sealed interface Result<T> permits Result.Success, Result.Failure {
    record Success<T>(T value) implements Result<T> {}
    record Failure<T>(Exception error) implements Result<T> {}

    static <T> Result<T> of(Supplier<T> action) {
        try { return new Success<>(action.get()); }
        catch (Exception e) { return new Failure<>(e); }
    }

    default <R> Result<R> map(Function<T, R> mapper) {
        return switch (this) {
            case Success<T> s -> Result.of(() -> mapper.apply(s.value()));
            case Failure<T> f -> new Failure<>(f.error());
        };
    }

    default T orElseThrow() {
        return switch (this) {
            case Success<T> s -> s.value();
            case Failure<T> f -> throw new RuntimeException(f.error());
        };
    }
}

// Dùng:
Result<User> result = Result.of(() -> userRepository.findById(id).orElseThrow());
Result<UserDto> dto = result.map(UserDto::from);
```

### 3. Builder với Generics và Self-referential type
```java
// Fluent builder với generic self-type (Curiously Recurring Template Pattern)
public abstract class Builder<T, SELF extends Builder<T, SELF>> {
    @SuppressWarnings("unchecked")
    protected SELF self() { return (SELF) this; }

    public abstract T build();
}

public class PersonBuilder extends Builder<Person, PersonBuilder> {
    private String name;
    private int age;

    public PersonBuilder name(String name) { this.name = name; return self(); }
    public PersonBuilder age(int age) { this.age = age; return self(); }

    @Override
    public Person build() { return new Person(name, age); }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Lambda & Functional Interface** (deep dive)
>
> Keyword: @FunctionalInterface, 4 loại method reference (static, instance of type, instance of object, constructor), closure & effectively final, lambda vs anonymous class (syntax, scope, `this`), composing Function/Predicate/Consumer, currying, partial application
