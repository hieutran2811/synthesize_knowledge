# Reflection & Annotations

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Reflection là gì?

**Reflection** là khả năng của Java cho phép chương trình **kiểm tra và thao tác cấu trúc của chính nó** tại runtime: đọc class metadata, gọi method, truy cập field — mà không cần biết type tại compile time.

```java
// Compile-time (static): biết type trước
UserService service = new UserService();
service.findById(1L);

// Runtime (reflection): type biết sau khi chạy
Class<?> clazz = Class.forName("com.example.UserService");
Object service = clazz.getDeclaredConstructor().newInstance();
Method method = clazz.getMethod("findById", Long.class);
Object result = method.invoke(service, 1L);
```

---

## How – Class Object

**`java.lang.Class<T>`** là entry point của mọi reflection operation.

```java
// 3 cách lấy Class object

// 1. .class literal (compile-time, most efficient)
Class<String> strClass = String.class;
Class<int[]>  arrClass = int[].class;
Class<Void>   voidClass = void.class;

// 2. getClass() trên instance (runtime type)
Object obj = "hello";
Class<?> clazz = obj.getClass(); // String.class (không phải Object.class!)

// 3. Class.forName() (tên đầy đủ, ClassLoader)
Class<?> c1 = Class.forName("java.util.ArrayList");
// Overload với ClassLoader control:
Class<?> c2 = Class.forName("com.example.Plugin", true, pluginClassLoader);

// Class metadata
System.out.println(clazz.getName());          // "java.lang.String"
System.out.println(clazz.getSimpleName());    // "String"
System.out.println(clazz.getPackageName());   // "java.lang"
System.out.println(clazz.getSuperclass());    // class java.lang.Object
System.out.println(Arrays.toString(clazz.getInterfaces())); // [Serializable, Comparable, CharSequence]
System.out.println(clazz.isInterface());      // false
System.out.println(clazz.isEnum());           // false
System.out.println(clazz.isRecord());         // false (Java 16+)
System.out.println(clazz.isArray());          // false
System.out.println(Modifier.isPublic(clazz.getModifiers())); // true
```

---

## How – Fields

```java
// getDeclaredFields() vs getFields():
// getDeclaredFields(): tất cả fields của CLASS NÀY (kể cả private), không kế thừa
// getFields(): tất cả public fields (kể cả kế thừa)

class Person {
    public String name;
    private int age;
    protected String email;
}

Class<Person> clazz = Person.class;

// Tất cả fields trong class (kể cả private)
Field[] allFields = clazz.getDeclaredFields();

// Truy cập từng field
Field ageField = clazz.getDeclaredField("age");
ageField.setAccessible(true); // bypass private access!

Person person = new Person();
ageField.set(person, 25);               // set value
int age = (int) ageField.get(person);  // get value → 25

// Field metadata
System.out.println(ageField.getName());          // "age"
System.out.println(ageField.getType());          // int
System.out.println(ageField.getGenericType());   // int (nếu là List<String> → thấy generic)
System.out.println(Modifier.isPrivate(ageField.getModifiers())); // true

// Traverse cả hierarchy (kể cả superclass fields)
public static List<Field> getAllFields(Class<?> clazz) {
    List<Field> fields = new ArrayList<>();
    Class<?> current = clazz;
    while (current != null && current != Object.class) {
        fields.addAll(Arrays.asList(current.getDeclaredFields()));
        current = current.getSuperclass();
    }
    return fields;
}
```

---

## How – Methods

```java
// getMethods(): public methods (kể cả inherited)
// getDeclaredMethods(): tất cả methods của class này (không inherited)

class Calculator {
    public int add(int a, int b) { return a + b; }
    private int multiply(int a, int b) { return a * b; }
    public static double pi() { return 3.14159; }
}

Class<Calculator> clazz = Calculator.class;

// Lookup by name + parameter types
Method addMethod = clazz.getMethod("add", int.class, int.class);

// Invoke method
Calculator calc = new Calculator();
int result = (int) addMethod.invoke(calc, 3, 4); // → 7

// Private method
Method multiplyMethod = clazz.getDeclaredMethod("multiply", int.class, int.class);
multiplyMethod.setAccessible(true);
int product = (int) multiplyMethod.invoke(calc, 3, 4); // → 12

// Static method (first arg = null)
Method piMethod = clazz.getMethod("pi");
double pi = (double) piMethod.invoke(null); // → 3.14159

// Method metadata
System.out.println(addMethod.getName());                    // "add"
System.out.println(addMethod.getReturnType());              // int
System.out.println(Arrays.toString(addMethod.getParameterTypes())); // [int, int]
System.out.println(Arrays.toString(addMethod.getExceptionTypes())); // []
System.out.println(addMethod.getAnnotation(Override.class));        // null

// invoke throws InvocationTargetException wrapping the actual exception
try {
    method.invoke(target, args);
} catch (InvocationTargetException e) {
    Throwable realCause = e.getCause(); // actual exception from method
    throw realCause;
}
```

---

## How – Constructors

```java
class Product {
    private final String name;
    private final BigDecimal price;

    public Product(String name, BigDecimal price) {
        this.name = name;
        this.price = price;
    }

    private Product() { this.name = "default"; this.price = BigDecimal.ZERO; }
}

Class<Product> clazz = Product.class;

// Public constructor
Constructor<Product> ctor = clazz.getConstructor(String.class, BigDecimal.class);
Product p = ctor.newInstance("Widget", new BigDecimal("9.99"));

// Private constructor (e.g., Singleton bypass)
Constructor<Product> privateCtor = clazz.getDeclaredConstructor();
privateCtor.setAccessible(true);
Product p2 = privateCtor.newInstance(); // default product

// Simple no-arg: getDeclaredConstructor().newInstance()
// vs clazz.newInstance() (deprecated Java 9+, uses public no-arg only)
```

---

## How – Generic Types (Type Tokens)

**Type erasure** xóa generic info tại runtime, nhưng có thể recover từ bytecode:

```java
class Repository<T> {
    private List<T> data = new ArrayList<>();
}

// Superclass generic type:
class UserRepository extends Repository<User> {}

// Lấy T = User tại runtime:
Type superType = UserRepository.class.getGenericSuperclass();
ParameterizedType paramType = (ParameterizedType) superType;
Type[] typeArgs = paramType.getActualTypeArguments();
Class<?> entityType = (Class<?>) typeArgs[0]; // User.class ✓

// Field generic type:
class Container {
    List<String> items;
}
Field field = Container.class.getDeclaredField("items");
ParameterizedType fieldType = (ParameterizedType) field.getGenericType();
Class<?> elementType = (Class<?>) fieldType.getActualTypeArguments()[0]; // String.class

// Method parameter generic type:
class Service {
    public void process(Map<String, List<Integer>> data) {}
}
Method m = Service.class.getMethod("process", Map.class);
Type paramType2 = m.getGenericParameterTypes()[0];
// → java.util.Map<java.lang.String, java.util.List<java.lang.Integer>>

// Jackson TypeReference pattern:
// TypeReference<List<User>>() {} → anonymous subclass → preserves generic info
```

---

## How – Annotations

**Annotation** là metadata gắn vào class/method/field, được đọc tại compile time hoặc runtime.

### Định nghĩa Annotation

```java
// @interface = annotation type definition
@Target({ElementType.METHOD, ElementType.TYPE})     // áp dụng ở đâu
@Retention(RetentionPolicy.RUNTIME)                  // giữ đến runtime
@Documented                                           // xuất hiện trong Javadoc
@Inherited                                            // subclass kế thừa nếu đặt trên class
public @interface Cacheable {
    String value() default "";           // tên cache
    int ttlSeconds() default 300;        // default 5 phút
    boolean condition() default true;
    String[] keyGenerators() default {}; // array
}

// Meta-annotations:
// @Target: ElementType.TYPE/METHOD/FIELD/PARAMETER/CONSTRUCTOR/LOCAL_VARIABLE/ANNOTATION_TYPE/PACKAGE/MODULE
// @Retention:
//   SOURCE  → chỉ source code (bị javac bỏ): @Override, @SuppressWarnings
//   CLASS   → trong .class file nhưng không load vào JVM: Lombok, APT
//   RUNTIME → load vào JVM, đọc được bằng reflection: Spring, JPA, Jackson
```

### Đọc Annotation tại runtime

```java
// Đọc từ class
Cacheable classAnnotation = MyService.class.getAnnotation(Cacheable.class);
if (classAnnotation != null) {
    System.out.println(classAnnotation.ttlSeconds()); // 300
}

// Đọc từ method
Method method = MyService.class.getMethod("findUser", Long.class);
Cacheable methodAnnotation = method.getAnnotation(Cacheable.class);

// Đọc tất cả annotations
Annotation[] annotations = method.getDeclaredAnnotations();

// Đọc từ parameter
Parameter[] params = method.getParameters();
for (Parameter param : params) {
    RequestParam rp = param.getAnnotation(RequestParam.class);
    if (rp != null) {
        System.out.println(rp.value()); // param name
    }
}

// Đọc từ field
Field field = User.class.getDeclaredField("email");
Column column = field.getAnnotation(Column.class);
if (column != null) {
    System.out.println(column.name()); // "email_address"
    System.out.println(column.nullable()); // false
}

// isAnnotationPresent() - quick check
boolean hasTransactional = method.isAnnotationPresent(Transactional.class);

// getAnnotationsByType() - repeatable annotations
Scheduled[] schedules = method.getAnnotationsByType(Scheduled.class);
```

### Annotation Processing (Compile-time)

```java
// Custom Annotation Processor (chạy tại compile time, không runtime)
@SupportedAnnotationTypes("com.example.AutoBuilder")
@SupportedSourceVersion(SourceVersion.RELEASE_17)
public class AutoBuilderProcessor extends AbstractProcessor {

    @Override
    public boolean process(Set<? extends TypeElement> annotations, RoundEnvironment roundEnv) {
        for (TypeElement annotation : annotations) {
            for (Element element : roundEnv.getElementsAnnotatedWith(annotation)) {
                // element = class được annotate với @AutoBuilder
                TypeElement classElement = (TypeElement) element;
                generateBuilderClass(classElement); // tạo Builder.java source file
            }
        }
        return true;
    }

    private void generateBuilderClass(TypeElement clazz) {
        // Dùng processingEnv.getFiler().createSourceFile() để tạo .java file
        // Lombok, MapStruct, Dagger dùng approach này
    }
}

// Đăng ký:
// META-INF/services/javax.annotation.processing.Processor
// com.example.AutoBuilderProcessor
```

---

## How – Dynamic Proxy

`java.lang.reflect.Proxy` tạo proxy implementation của interface tại runtime:

```java
// 1. Interface
public interface UserService {
    User findById(Long id);
    void save(User user);
}

// 2. InvocationHandler: xử lý mọi method call
public class LoggingInvocationHandler implements InvocationHandler {
    private final Object target;
    private final Logger log = LoggerFactory.getLogger(getClass());

    public LoggingInvocationHandler(Object target) { this.target = target; }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        log.info("Calling: {}({})", method.getName(), Arrays.toString(args));
        long start = System.nanoTime();
        try {
            Object result = method.invoke(target, args); // gọi method thực
            log.info("Done in {}µs", (System.nanoTime() - start) / 1000);
            return result;
        } catch (InvocationTargetException e) {
            log.error("Failed: {}", e.getCause().getMessage());
            throw e.getCause(); // unwrap
        }
    }
}

// 3. Tạo proxy
UserService realService = new UserServiceImpl();
UserService proxy = (UserService) Proxy.newProxyInstance(
    UserService.class.getClassLoader(),
    new Class<?>[]{ UserService.class },  // interfaces to implement
    new LoggingInvocationHandler(realService)
);

proxy.findById(1L);
// → log: Calling: findById([1])
// → calls realService.findById(1L)
// → log: Done in 45µs

// Spring AOP: dùng JDK Proxy (nếu bean implement interface)
// hoặc CGLIB (nếu không có interface, subclass bean)
```

---

## How – setAccessible và Module System

```java
// Java 8: setAccessible(true) bypass mọi access control
field.setAccessible(true); // thường works

// Java 9+ Modules: strict encapsulation
// Nếu class trong module không mở → setAccessible() ném InaccessibleObjectException!

// JVM flags (temporary bypass trong migration):
--add-opens java.base/java.lang=ALL-UNNAMED   // mở java.lang cho unnamed module
--add-opens java.base/java.util=ALL-UNNAMED

// module-info.java cách đúng:
module my.library {
    exports com.example.api;
    opens com.example.model to jackson.databind; // chỉ mở cho Jackson reflection
}

// MethodHandles.privateLookupIn() – module-aware alternative to setAccessible:
MethodHandles.Lookup lookup = MethodHandles.privateLookupIn(TargetClass.class,
    MethodHandles.lookup());
VarHandle fieldHandle = lookup.findVarHandle(TargetClass.class, "privateField", String.class);
```

---

## How – MethodHandles (Reflection Alternative)

`MethodHandle` là typed reference tới method/field — **nhanh hơn reflection** (JIT có thể inline):

```java
import java.lang.invoke.*;

// MethodHandle cho method
MethodHandles.Lookup lookup = MethodHandles.lookup();
MethodHandle mh = lookup.findVirtual(String.class, "toUpperCase",
    MethodType.methodType(String.class));
String result = (String) mh.invoke("hello"); // "HELLO"

// MethodHandle cho static method
MethodHandle parseInt = lookup.findStatic(Integer.class, "parseInt",
    MethodType.methodType(int.class, String.class));
int n = (int) parseInt.invoke("42"); // 42

// MethodHandle cho field (getter/setter)
MethodHandle getter = lookup.findGetter(User.class, "name", String.class);
MethodHandle setter = lookup.findSetter(User.class, "name", String.class);

User user = new User();
setter.invoke(user, "Alice");
String name = (String) getter.invoke(user); // "Alice"

// invokeExact vs invoke:
// invokeExact: type must match EXACTLY → no boxing, fastest
// invoke: auto-boxing/widening allowed → more flexible

// MethodHandle là immutable, thread-safe, cacheable
// JIT treat như direct method call (sau warmup) → zero overhead
```

---

## Components – Reflection API Overview

| Class | Mô tả |
|-------|-------|
| `Class<T>` | Represents a class/interface/array/primitive |
| `Field` | Class field (instance or static) |
| `Method` | Class method |
| `Constructor<T>` | Class constructor |
| `Parameter` | Method/constructor parameter |
| `Annotation` | Marker interface for all annotation types |
| `AnnotatedElement` | Interface: Class/Method/Field/Parameter implement |
| `Modifier` | Utility for decoding access flags |
| `Proxy` | Creates dynamic proxy implementations |
| `InvocationHandler` | Handler for proxy method calls |
| `MethodHandle` | Fast typed reference to method |
| `VarHandle` | Fast typed reference to field |
| `MethodHandles.Lookup` | Factory for MethodHandle/VarHandle |

---

## Why – Tại sao Reflection quan trọng?

```
Framework magic dựa trên reflection:

Spring DI:        @Autowired → scan classpath → find @Component → instantiate → inject
Spring MVC:       @RequestMapping → find methods → map URL → invoke with bound params
Spring AOP:       @Transactional → create proxy → intercept method calls
JPA/Hibernate:    @Entity → read @Column → map fields ↔ DB columns
Jackson:          @JsonProperty → serialize/deserialize field ↔ JSON key
JUnit 5:          @Test → find methods → invoke → collect results
Lombok (APT):     @Data → generate equals/hashCode/getters at compile time (not runtime!)
```

---

## When – Khi nào dùng Reflection?

**Nên dùng:**
- Framework/library code (Spring, Hibernate, Jackson)
- Testing (mock frameworks, test utilities)
- Configuration-driven behavior (plugin systems)
- Generic utilities (object mapping, deep copy)

**Không nên dùng:**
- Business logic thông thường (dùng interface/polymorphism)
- Performance-critical hot paths (overhead vs MethodHandle)
- Khi strong typing khả thi
- Khi module system ngăn access

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Runtime flexibility | Chậm hơn direct call (nhưng JIT optimize sau warmup) |
| Framework magic | Bypasses compile-time type safety |
| Dynamic plugin loading | Verbose code |
| Configuration-driven | setAccessible() breaks encapsulation |
| Generic utilities | Module system restrictions (Java 9+) |

---

## Real-world Usage (Production)

### 1. Generic Object Mapper (như Jackson đơn giản)

```java
public class SimpleObjectMapper {

    public Map<String, Object> toMap(Object obj) throws IllegalAccessException {
        Map<String, Object> map = new LinkedHashMap<>();
        Class<?> clazz = obj.getClass();

        for (Field field : getAllFields(clazz)) {
            field.setAccessible(true);
            String key = getFieldName(field); // check @JsonProperty
            Object value = field.get(obj);
            map.put(key, value);
        }
        return map;
    }

    private String getFieldName(Field field) {
        JsonProperty ann = field.getAnnotation(JsonProperty.class);
        return (ann != null && !ann.value().isEmpty()) ? ann.value() : field.getName();
    }

    public <T> T fromMap(Map<String, Object> map, Class<T> type) throws Exception {
        T instance = type.getDeclaredConstructor().newInstance();
        for (Field field : getAllFields(type)) {
            field.setAccessible(true);
            String key = getFieldName(field);
            if (map.containsKey(key)) {
                field.set(instance, convertType(map.get(key), field.getType()));
            }
        }
        return instance;
    }
}
```

### 2. Custom Validator Framework

```java
// Annotation
@Target(ElementType.FIELD)
@Retention(RetentionPolicy.RUNTIME)
public @interface NotBlank {
    String message() default "must not be blank";
}

@Target(ElementType.FIELD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Range {
    int min() default 0;
    int max() default Integer.MAX_VALUE;
    String message() default "out of range";
}

// Validator
public class BeanValidator {
    public List<String> validate(Object obj) throws IllegalAccessException {
        List<String> errors = new ArrayList<>();
        for (Field field : getAllFields(obj.getClass())) {
            field.setAccessible(true);
            Object value = field.get(obj);

            NotBlank notBlank = field.getAnnotation(NotBlank.class);
            if (notBlank != null) {
                if (value == null || value.toString().isBlank()) {
                    errors.add(field.getName() + ": " + notBlank.message());
                }
            }

            Range range = field.getAnnotation(Range.class);
            if (range != null && value instanceof Number n) {
                int v = n.intValue();
                if (v < range.min() || v > range.max()) {
                    errors.add(field.getName() + ": " + range.message());
                }
            }
        }
        return errors;
    }
}

// Dùng
public class CreateUserRequest {
    @NotBlank
    private String name;
    @NotBlank(message = "email is required")
    private String email;
    @Range(min = 18, max = 120, message = "age must be 18-120")
    private int age;
}

List<String> errors = validator.validate(request);
```

### 3. MethodHandle Cache (High Performance)

```java
// Cache MethodHandle để tái dùng (tránh overhead mỗi lần lookup)
public class FieldAccessor {
    private final Map<String, MethodHandle> getterCache = new ConcurrentHashMap<>();
    private final Map<String, MethodHandle> setterCache = new ConcurrentHashMap<>();

    public Object get(Object obj, String fieldName) throws Throwable {
        MethodHandle getter = getterCache.computeIfAbsent(
            obj.getClass().getName() + "." + fieldName,
            key -> buildGetter(obj.getClass(), fieldName)
        );
        return getter.invoke(obj);
    }

    private MethodHandle buildGetter(Class<?> clazz, String fieldName) {
        try {
            MethodHandles.Lookup lookup = MethodHandles.privateLookupIn(clazz, MethodHandles.lookup());
            Field field = clazz.getDeclaredField(fieldName);
            return lookup.unreflectGetter(field);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
// MethodHandle sau warmup: JIT inline → tốc độ gần như direct field access
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Date/Time API (java.time)**
>
> Keyword: LocalDate/LocalTime/LocalDateTime (no timezone), ZonedDateTime/OffsetDateTime (timezone-aware), Instant (machine time/epoch), Duration (time-based), Period (date-based), DateTimeFormatter (thread-safe, pattern), ChronoUnit, Clock (testable), migration từ java.util.Date/Calendar, daylight saving time pitfalls
