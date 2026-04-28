# Design Patterns – Creational (Khởi tạo)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Creational Patterns là gì?

**Creational Patterns** giải quyết bài toán **tạo object** một cách linh hoạt và phù hợp:
- Ẩn logic khởi tạo khỏi client code
- Tăng flexibility: quyết định object nào được tạo tại runtime
- Tái sử dụng object đã có thay vì luôn tạo mới

**5 Creational Patterns (GoF):**
1. Singleton
2. Builder
3. Factory Method
4. Abstract Factory
5. Prototype

---

## 1. Singleton

### What
Đảm bảo class chỉ có **1 instance duy nhất** trong suốt vòng đời application và cung cấp global access point.

### How – Các cách implement

#### Cách 1: Eager Initialization
```java
public class Singleton {
    // Tạo ngay khi class được load
    private static final Singleton INSTANCE = new Singleton();
    private Singleton() { }
    public static Singleton getInstance() { return INSTANCE; }
}
// Thread-safe (class loading là thread-safe), nhưng tạo dù không dùng
```

#### Cách 2: Double-Checked Locking (DCL)
```java
public class Singleton {
    private static volatile Singleton instance; // PHẢI volatile!

    private Singleton() { }

    public static Singleton getInstance() {
        if (instance == null) {                   // check 1: avoid locking if created
            synchronized (Singleton.class) {
                if (instance == null) {           // check 2: avoid race
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
// Tại sao volatile? Prevent partial initialization visibility:
// new Singleton() = 3 bước: allocate memory, init fields, assign reference
// Không có volatile: JIT có thể reorder → assign trước init → other thread thấy instance != null nhưng chưa init
```

#### Cách 3: Initialization-on-Demand Holder (Best Practice)
```java
public class Singleton {
    private Singleton() { }

    // Inner class chỉ được load khi getInstance() được gọi lần đầu
    // Class loading là thread-safe by JVM guarantee
    private static class Holder {
        private static final Singleton INSTANCE = new Singleton();
    }

    public static Singleton getInstance() {
        return Holder.INSTANCE; // lazy, thread-safe, no sync overhead
    }
}
```

#### Cách 4: Enum Singleton (Effective Java – Joshua Bloch)
```java
public enum Singleton {
    INSTANCE;

    private final SomeService service = new SomeService();

    public void doWork() { service.perform(); }
}

// Dùng:
Singleton.INSTANCE.doWork();

// Ưu điểm:
// - Thread-safe by JVM
// - Serialization-safe (không tạo new instance khi deserialize)
// - Reflection-proof (không thể tạo instance qua reflection)
```

#### Cách 5: Spring Singleton Bean (Thực tế nhất)
```java
@Service // Spring quản lý, default scope = singleton per ApplicationContext
public class UserService {
    // Spring inject dependencies, không cần static Singleton pattern
}
```

### Why
- Configuration objects (1 instance config toàn app)
- Connection pools (không tạo mới pool mỗi lần)
- Logging (1 logger per category)

### When – Khi nào KHÔNG nên dùng Singleton
- Khi cần test (Singleton tạo global state → khó mock)
- Khi có nhiều ClassLoader (mỗi ClassLoader có instance riêng)
- Khi muốn multiple instance sau này (design inflexible)

### Trade-offs
| Ưu | Nhược |
|-----|-------|
| 1 instance duy nhất | Global state → khó test |
| Lazy initialization (Holder) | Concurrency phức tạp nếu implement sai |
| Control global access | Vi phạm SRP (manage lifetime + provide service) |

---

## 2. Builder

### What
Tách việc **xây dựng** object phức tạp ra khỏi **representation** của nó, cho phép cùng 1 quá trình xây dựng tạo ra các representation khác nhau.

**Bài toán**: Telescoping Constructor — constructor với nhiều optional parameter:
```java
// Anti-pattern: Telescoping Constructor
public Pizza(String size, boolean cheese, boolean pepperoni, boolean mushrooms,
             boolean onions, boolean peppers) { ... }

new Pizza("LARGE", true, false, true, false, true); // Khó đọc! Tham số nào là gì?
```

### How – Builder Pattern

```java
public class Pizza {
    private final String size;          // required
    private final boolean cheese;
    private final boolean pepperoni;
    private final boolean mushrooms;
    private final boolean onions;
    private final String sauce;

    private Pizza(Builder builder) {    // private constructor
        this.size = builder.size;
        this.cheese = builder.cheese;
        this.pepperoni = builder.pepperoni;
        this.mushrooms = builder.mushrooms;
        this.onions = builder.onions;
        this.sauce = builder.sauce;
    }

    // Getters only (immutable)
    public String getSize() { return size; }

    public static class Builder {
        // Required
        private final String size;

        // Optional – default values
        private boolean cheese = false;
        private boolean pepperoni = false;
        private boolean mushrooms = false;
        private boolean onions = false;
        private String sauce = "tomato";

        public Builder(String size) {
            this.size = Objects.requireNonNull(size);
        }

        public Builder cheese(boolean val)    { this.cheese = val; return this; }
        public Builder pepperoni(boolean val) { this.pepperoni = val; return this; }
        public Builder mushrooms(boolean val) { this.mushrooms = val; return this; }
        public Builder onions(boolean val)    { this.onions = val; return this; }
        public Builder sauce(String val)      { this.sauce = val; return this; }

        public Pizza build() {
            validate(); // validate trước khi build
            return new Pizza(this);
        }

        private void validate() {
            if (pepperoni && !sauce.equals("tomato"))
                throw new IllegalStateException("Pepperoni requires tomato sauce");
        }
    }
}

// Dùng – readable, flexible
Pizza pizza = new Pizza.Builder("LARGE")
    .cheese(true)
    .mushrooms(true)
    .sauce("bbq")
    .build();
```

### How – Lombok @Builder (Production shortcut)
```java
@Builder
@Getter
public class CreateOrderRequest {
    @NonNull private String customerId;
    @NonNull private List<OrderItem> items;
    @Builder.Default private Currency currency = Currency.USD;
    @Builder.Default private boolean sendConfirmation = true;
}

// Dùng:
CreateOrderRequest request = CreateOrderRequest.builder()
    .customerId("customer-123")
    .items(items)
    .currency(Currency.EUR)
    .build();
```

### How – Builder cho HTTP Request
```java
// Java 11 HttpClient dùng Builder pattern
HttpClient client = HttpClient.newBuilder()
    .version(HttpClient.Version.HTTP_2)
    .connectTimeout(Duration.ofSeconds(10))
    .followRedirects(HttpClient.Redirect.NORMAL)
    .build();

HttpRequest request = HttpRequest.newBuilder()
    .uri(URI.create("https://api.example.com/users"))
    .header("Authorization", "Bearer " + token)
    .timeout(Duration.ofSeconds(30))
    .GET()
    .build();
```

### Trade-offs
| Ưu | Nhược |
|-----|-------|
| Readable, self-documenting | Nhiều code (Lombok giải quyết) |
| Immutable object | Copy trạng thái từ Builder sang object |
| Validation tập trung | Không phù hợp object đơn giản |
| Flexible optional params | |

---

## 3. Factory Method

### What
Định nghĩa interface để tạo object, nhưng để **subclass** quyết định class nào được instantiate.

```
Creator (abstract)          Product (interface)
  + factoryMethod(): Product    ← implement
  + operation()
        |
  ConcreteCreator         ConcreteProduct
  + factoryMethod()     implements Product
```

### How

```java
// Product interface
public interface Logger {
    void log(String message);
}

// Concrete Products
public class ConsoleLogger implements Logger {
    public void log(String message) { System.out.println("[CONSOLE] " + message); }
}
public class FileLogger implements Logger {
    private final Path logFile;
    FileLogger(Path file) { this.logFile = file; }
    public void log(String message) { Files.writeString(logFile, message + "\n", APPEND); }
}
public class JsonLogger implements Logger {
    public void log(String message) { System.out.println("{\"msg\":\"" + message + "\"}"); }
}

// Creator abstract class với Factory Method
public abstract class Application {
    private Logger logger;

    // Template method dùng factory method
    public final void run() {
        this.logger = createLogger(); // factory method
        logger.log("Application started");
        execute();
        logger.log("Application stopped");
    }

    // Factory Method – subclass override
    protected abstract Logger createLogger();
    protected abstract void execute();
}

// Concrete Creators
public class ConsoleApp extends Application {
    @Override
    protected Logger createLogger() { return new ConsoleLogger(); }
    @Override
    protected void execute() { System.out.println("Running console app"); }
}

public class ServerApp extends Application {
    @Override
    protected Logger createLogger() { return new FileLogger(Path.of("/var/log/app.log")); }
    @Override
    protected void execute() { startHttpServer(); }
}
```

### How – Static Factory Method (Effective Java pattern)

Không nhất thiết phải dùng class hierarchy. Static factory method là biến thể phổ biến hơn:

```java
public class Connection {
    private final String url;
    private final ConnectionType type;

    // Static factory methods – có tên mô tả
    public static Connection ofDatabase(String url) {
        return new Connection(url, ConnectionType.DATABASE);
    }
    public static Connection ofCache(String url) {
        return new Connection(url, ConnectionType.CACHE);
    }
    public static Connection ofMessageQueue(String url) {
        return new Connection(url, ConnectionType.MQ);
    }

    // Private constructor
    private Connection(String url, ConnectionType type) {
        this.url = url;
        this.type = type;
    }
}

// Dùng: tên method tự document
Connection db = Connection.ofDatabase("jdbc:postgresql://localhost/mydb");
Connection cache = Connection.ofCache("redis://localhost:6379");

// JDK examples:
List.of(1, 2, 3)
Optional.of("value")
Optional.empty()
Collections.unmodifiableList(list)
```

---

## 4. Abstract Factory

### What
Cung cấp interface để tạo **họ (family) các object liên quan** mà không cần specify concrete class.

**Khác Factory Method**: Factory Method tạo 1 product, Abstract Factory tạo họ products liên quan.

### How

```java
// Products
public interface Button { void render(); void onClick(); }
public interface Checkbox { void render(); boolean isChecked(); }
public interface TextField { void render(); String getValue(); }

// Abstract Factory
public interface UIFactory {
    Button createButton();
    Checkbox createCheckbox();
    TextField createTextField();
}

// Concrete Factories (themes)
public class LightThemeFactory implements UIFactory {
    public Button createButton()     { return new LightButton(); }
    public Checkbox createCheckbox() { return new LightCheckbox(); }
    public TextField createTextField(){ return new LightTextField(); }
}

public class DarkThemeFactory implements UIFactory {
    public Button createButton()     { return new DarkButton(); }
    public Checkbox createCheckbox() { return new DarkCheckbox(); }
    public TextField createTextField(){ return new DarkTextField(); }
}

// Client – không biết concrete class, chỉ biết factory
public class FormRenderer {
    private final UIFactory factory;

    public FormRenderer(UIFactory factory) { this.factory = factory; }

    public void renderLoginForm() {
        Button submit = factory.createButton();
        TextField username = factory.createTextField();
        TextField password = factory.createTextField();
        // Tất cả components đều cùng theme – consistency!
        submit.render(); username.render(); password.render();
    }
}

// Tạo đúng factory theo config
UIFactory factory = userPreference.isDarkMode()
    ? new DarkThemeFactory()
    : new LightThemeFactory();
new FormRenderer(factory).renderLoginForm();
```

### Real-world: JDBC DriverManager
```java
// DriverManager.getConnection() là Abstract Factory:
// Trả về Connection, Statement, ResultSet phù hợp với driver (MySQL, PostgreSQL...)
Connection conn = DriverManager.getConnection(url, user, password);
// Dù url là MySQL hay PostgreSQL, code của bạn không thay đổi
```

---

## 5. Prototype

### What
Tạo object mới bằng cách **clone** từ một prototype (object mẫu) thay vì tạo từ đầu.

**Khi nào dùng**: khởi tạo object tốn kém (database query, heavy computation) → clone nhanh hơn.

### How

```java
public interface Prototype<T> {
    T clone();
}

public class ExpensiveConfig implements Prototype<ExpensiveConfig>, Cloneable {
    private Map<String, String> settings = new HashMap<>();
    private List<Rule> rules = new ArrayList<>();

    // Giả sử constructor load từ database
    public ExpensiveConfig(DataSource ds) {
        // expensive initialization...
        loadFromDatabase(ds);
    }

    // Private constructor cho clone
    private ExpensiveConfig(ExpensiveConfig source) {
        this.settings = new HashMap<>(source.settings); // deep copy
        this.rules = source.rules.stream()
            .map(Rule::copy)                            // deep copy
            .collect(Collectors.toList());
    }

    @Override
    public ExpensiveConfig clone() {
        return new ExpensiveConfig(this); // deep copy
    }
}

// Cache prototype
ExpensiveConfig prototype = new ExpensiveConfig(dataSource); // 1 lần load

// Clone cho mỗi request (nhanh hơn nhiều)
ExpensiveConfig config1 = prototype.clone();
config1.set("feature.x", "enabled");  // chỉ thay đổi clone

ExpensiveConfig config2 = prototype.clone();
// config2 vẫn là bản gốc
```

### Shallow vs Deep Clone
```java
// Object.clone() – SHALLOW copy
// Primitive fields: copied by value
// Reference fields: copied by reference (SAME object!)

class Order implements Cloneable {
    int id;                       // primitive → safe
    List<Item> items;             // reference → SHARED!

    @Override
    protected Order clone() throws CloneNotSupportedException {
        Order clone = (Order) super.clone();
        // Shallow: clone.items == this.items (nguy hiểm!)

        // Deep copy:
        clone.items = new ArrayList<>(this.items);
        // Nếu Item cũng mutable → phải deep copy Item nữa
        return clone;
    }
}
```

---

## Compare – Creational Patterns

| Pattern | Bài toán giải quyết | Khi dùng |
|---------|-------------------|---------|
| Singleton | 1 instance | Config, Pool, Logger |
| Builder | Object phức tạp, optional params | DTO, Config object |
| Factory Method | Subclass chọn class cụ thể | Framework, Plugin |
| Abstract Factory | Họ objects liên quan | UI Themes, Cross-platform |
| Prototype | Clone object tốn kém | Cache, Object Pool |

---

## Real-world Usage Summary

```java
// Singleton: Spring @Bean singleton
@Configuration
public class AppConfig {
    @Bean // singleton by default
    public ObjectMapper objectMapper() {
        return new ObjectMapper()
            .configure(FAIL_ON_UNKNOWN_PROPERTIES, false);
    }
}

// Builder: RequestBuilder, ResponseBuilder
return ResponseEntity.status(HttpStatus.CREATED)
    .header("Location", "/users/" + user.getId())
    .body(UserDto.from(user));

// Factory Method: JPA Repository
public interface UserRepository extends JpaRepository<User, Long> { }
// Spring Data tự tạo implementation

// Abstract Factory: DataSource (HikariCP, DBCP2...)
@Bean
public DataSource dataSource(DataSourceProperties properties) {
    return properties.initializeDataSourceBuilder().build();
    // Trả về HikariDataSource hoặc implementation khác tùy config
}

// Prototype: MapStruct mapping (clone-like)
User userCopy = modelMapper.map(userDto, User.class);
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Design Patterns – Structural** (Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy)
>
> Keyword: Adapter (object adapter vs class adapter), Bridge (abstraction + implementation), Composite (tree structure), Decorator (dynamic wrapping), Facade (simplify subsystem), Flyweight (shared intrinsic state), Proxy (virtual proxy, protection proxy, JDK dynamic proxy, CGLIB)
