# Design Patterns – Structural (Cấu trúc)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Structural Patterns là gì?

**Structural Patterns** giải quyết cách **kết hợp class và object** thành cấu trúc lớn hơn trong khi vẫn giữ cấu trúc linh hoạt và hiệu quả.

**7 Structural Patterns (GoF):**
1. Adapter – chuyển đổi interface
2. Bridge – tách abstraction khỏi implementation
3. Composite – cây đối tượng
4. Decorator – thêm hành vi động
5. Facade – interface đơn giản hóa
6. Flyweight – chia sẻ state
7. Proxy – kiểm soát truy cập

---

## 1. Adapter

### What
Chuyển đổi interface của một class thành interface khác mà client mong đợi — giống adapter phích cắm điện.

### How

```java
// Existing class – interface cũ, không thể sửa
public class LegacyPaymentSystem {
    public boolean processVisa(String cardNumber, double amount, String currency) {
        System.out.println("Processing via legacy system: " + cardNumber);
        return true;
    }
}

// Target interface – interface mới mà client muốn dùng
public interface PaymentGateway {
    PaymentResult pay(PaymentRequest request);
}

// Adapter – wraps legacy, implements new interface
public class LegacyPaymentAdapter implements PaymentGateway {
    private final LegacyPaymentSystem legacy;

    public LegacyPaymentAdapter(LegacyPaymentSystem legacy) {
        this.legacy = legacy;
    }

    @Override
    public PaymentResult pay(PaymentRequest request) {
        // Convert new request → old parameters
        boolean success = legacy.processVisa(
            request.getCardNumber(),
            request.getAmount().doubleValue(),
            request.getCurrency().getCode()
        );
        return success ? PaymentResult.success() : PaymentResult.failure("Legacy system error");
    }
}

// Client dùng qua interface mới, không biết về LegacyPaymentSystem
PaymentGateway gateway = new LegacyPaymentAdapter(new LegacyPaymentSystem());
gateway.pay(new PaymentRequest(...));
```

### Object Adapter vs Class Adapter
- **Object Adapter** (trên): dùng composition → linh hoạt hơn (Java thường dùng cái này)
- **Class Adapter**: extends Adaptee + implements Target → chỉ dùng khi ngôn ngữ hỗ trợ multiple inheritance

### Real-world
- `Arrays.asList()` – Array → List
- `Collections.list(Enumeration)` – Enumeration → List
- `InputStreamReader` – InputStream → Reader (byte → char)
- Spring `HandlerAdapter` – nhiều loại handler → unified interface

---

## 2. Bridge

### What
Tách **abstraction** (high-level control) khỏi **implementation** (low-level work) để chúng có thể thay đổi độc lập nhau.

**Bài toán**: Nếu dùng inheritance cho cả 2 chiều → explosion of subclasses.

```
Không có Bridge:
Shape (abstract)
  ├── CircleRedColor
  ├── CircleBlueColor
  ├── SquareRedColor
  └── SquareBlueColor  → thêm 1 shape + 1 color = 4 class mới!

Với Bridge: (shapes) × (colors) thay vì (shapes + colors)
  Shape → Color (bridge)
  ├── Circle ──────┤├── Red
  └── Square       └── Blue
```

### How

```java
// Implementation interface (chiều thứ nhất)
public interface Renderer {
    void renderCircle(double radius);
    void renderSquare(double side);
}

public class VectorRenderer implements Renderer {
    public void renderCircle(double r)  { System.out.println("SVG circle r=" + r); }
    public void renderSquare(double s)  { System.out.println("SVG square s=" + s); }
}

public class RasterRenderer implements Renderer {
    public void renderCircle(double r)  { System.out.println("Pixel circle r=" + r); }
    public void renderSquare(double s)  { System.out.println("Pixel square s=" + s); }
}

// Abstraction (chiều thứ hai) – chứa bridge đến Implementation
public abstract class Shape {
    protected final Renderer renderer; // BRIDGE

    protected Shape(Renderer renderer) { this.renderer = renderer; }

    public abstract void draw();
    public abstract void resize(double factor);
}

public class Circle extends Shape {
    private double radius;
    public Circle(Renderer renderer, double radius) {
        super(renderer);
        this.radius = radius;
    }
    @Override public void draw()  { renderer.renderCircle(radius); }
    @Override public void resize(double f) { radius *= f; }
}

public class Square extends Shape {
    private double side;
    public Square(Renderer renderer, double side) {
        super(renderer);
        this.side = side;
    }
    @Override public void draw()  { renderer.renderSquare(side); }
    @Override public void resize(double f) { side *= f; }
}

// Dùng: tự do kết hợp
Shape c1 = new Circle(new VectorRenderer(), 5);
Shape c2 = new Circle(new RasterRenderer(), 5);
Shape s1 = new Square(new VectorRenderer(), 10);
c1.draw(); // SVG circle
c2.draw(); // Pixel circle
```

### Real-world
- JDBC: `Connection`, `Statement`, `ResultSet` = abstraction; Driver = implementation
- Java AWT: `Component` (abstraction) → `Peer` (platform-specific implementation)
- Spring: `DataAccessException` hierarchy bridge over different DB exceptions

---

## 3. Composite

### What
Tổ chức object thành **cây phân cấp** (tree structure) để client xử lý object đơn lẻ và composition giống nhau.

**Ví dụ**: File system (File và Folder đều có `size()`, `delete()`)

### How

```java
// Component interface – chung cho cả leaf và composite
public interface FileSystemItem {
    String getName();
    long getSize();
    void delete();
    void print(String indent);
}

// Leaf
public class File implements FileSystemItem {
    private final String name;
    private final long size;

    public File(String name, long size) { this.name = name; this.size = size; }

    @Override public String getName() { return name; }
    @Override public long getSize()   { return size; }
    @Override public void delete()    { System.out.println("Deleting file: " + name); }
    @Override public void print(String indent) {
        System.out.println(indent + "📄 " + name + " (" + size + " bytes)");
    }
}

// Composite
public class Directory implements FileSystemItem {
    private final String name;
    private final List<FileSystemItem> children = new ArrayList<>();

    public Directory(String name) { this.name = name; }

    public void add(FileSystemItem item) { children.add(item); }
    public void remove(FileSystemItem item) { children.remove(item); }

    @Override public String getName() { return name; }

    @Override
    public long getSize() {
        return children.stream().mapToLong(FileSystemItem::getSize).sum(); // recursive
    }

    @Override
    public void delete() {
        children.forEach(FileSystemItem::delete); // recursive
        System.out.println("Deleting directory: " + name);
    }

    @Override
    public void print(String indent) {
        System.out.println(indent + "📁 " + name + "/");
        children.forEach(child -> child.print(indent + "  "));
    }
}

// Dùng
Directory root = new Directory("project");
Directory src = new Directory("src");
src.add(new File("Main.java", 1024));
src.add(new File("Utils.java", 512));
root.add(src);
root.add(new File("pom.xml", 256));
root.print("");
System.out.println("Total: " + root.getSize()); // 1792 bytes
```

### Real-world
- Java AWT/Swing: `Component` → `Container` → `Panel`, `Window`...
- Spring Security: `FilterChain` (Composite of Filters)
- JSON/XML: `JsonNode` (object, array, value đều là `JsonNode`)
- HTML DOM: Element có thể chứa Element khác

---

## 4. Decorator

### What
Gắn thêm hành vi **động** vào object mà không ảnh hưởng các object khác cùng class — thay thế subclassing bằng wrapping.

### How

```java
// Component interface
public interface TextProcessor {
    String process(String text);
}

// Concrete Component
public class PlainTextProcessor implements TextProcessor {
    @Override
    public String process(String text) { return text; }
}

// Base Decorator
public abstract class TextDecorator implements TextProcessor {
    protected final TextProcessor wrapped;
    protected TextDecorator(TextProcessor wrapped) { this.wrapped = wrapped; }

    @Override
    public String process(String text) { return wrapped.process(text); } // delegate + extend
}

// Concrete Decorators
public class TrimDecorator extends TextDecorator {
    public TrimDecorator(TextProcessor w) { super(w); }
    @Override public String process(String text) { return super.process(text).trim(); }
}

public class UpperCaseDecorator extends TextDecorator {
    public UpperCaseDecorator(TextProcessor w) { super(w); }
    @Override public String process(String text) { return super.process(text).toUpperCase(); }
}

public class HtmlEscapeDecorator extends TextDecorator {
    public HtmlEscapeDecorator(TextProcessor w) { super(w); }
    @Override public String process(String text) {
        return super.process(text)
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}

// Kết hợp động tại runtime
TextProcessor processor = new HtmlEscapeDecorator(
    new UpperCaseDecorator(
        new TrimDecorator(
            new PlainTextProcessor()
        )
    )
);

String result = processor.process("  <Hello World>  ");
// trim → "<Hello World>" → UPPER → "<HELLO WORLD>" → escape → "&lt;HELLO WORLD&gt;"
```

### Java I/O là ví dụ Decorator điển hình
```java
InputStream is = new GZIPInputStream(      // Decorator: decompress
    new BufferedInputStream(               // Decorator: buffering
        new FileInputStream("data.gz")     // Component: read bytes
    )
);
```

### Lambda-based Decorator (modern approach)
```java
// Functional approach – không cần class hierarchy
Function<String, String> trim = String::trim;
Function<String, String> upper = String::toUpperCase;
Function<String, String> addPrefix = s -> "[PROCESSED] " + s;

// Compose decorators
Function<String, String> pipeline = trim.andThen(upper).andThen(addPrefix);
pipeline.apply("  hello  "); // "[PROCESSED] HELLO"
```

### Real-world
- Java I/O: `BufferedInputStream`, `GZIPInputStream`, `DataInputStream`
- Spring: `HttpServletRequestWrapper`, Spring Security Filter Chain
- Caffeine Cache: `LoadingCache.wrap()`, `AsyncCache`

---

## 5. Facade

### What
Cung cấp **interface đơn giản** cho một hệ thống con (subsystem) phức tạp — giấu complexity.

### How

```java
// Subsystems phức tạp
class VideoDecoder { VideoFile decode(String filename) { ... } }
class AudioMixer { AudioData mix(VideoFile video) { ... } }
class BitrateReader { VideoFile read(String filename, CodecFactory factory) { ... } }
class CodecFactory {
    Codec extract(VideoFile video) { ... }
    Codec find(String format) { ... }
}

// Facade – đơn giản hóa
public class VideoConverter {
    private final VideoDecoder decoder = new VideoDecoder();
    private final AudioMixer mixer = new AudioMixer();
    private final BitrateReader reader = new BitrateReader();
    private final CodecFactory codecFactory = new CodecFactory();

    // Một method thay vì 4 subsystem calls
    public File convert(String filename, String format) {
        VideoFile file = decoder.decode(filename);
        Codec sourceCodec = codecFactory.extract(file);
        Codec destCodec = codecFactory.find(format);
        VideoFile buffer = reader.read(filename, sourceCodec);
        VideoFile intermediateResult = reader.read(buffer, destCodec);
        AudioData audio = mixer.mix(intermediateResult);
        return new FileWriter().writeFile(intermediateResult, audio, format);
    }
}

// Client chỉ cần biết 1 class
File mp4 = new VideoConverter().convert("video.avi", "mp4");
```

### Real-world
- `SLF4J` – facade over Log4j, Logback, JUL
- Spring `JdbcTemplate` – facade over JDBC
- Spring `RestTemplate` / `WebClient` – facade over HTTP
- Hibernate `Session` – facade over SQL, transaction, connection

---

## 6. Flyweight

### What
Chia sẻ **intrinsic state** (không đổi, chia sẻ được) giữa nhiều objects thay vì lưu riêng → tiết kiệm memory khi có cực nhiều objects tương tự.

```
Object state:
  Intrinsic: không phụ thuộc context, có thể share
  Extrinsic: phụ thuộc context, không share
```

### How

```java
// Flyweight: chỉ chứa intrinsic state
public final class CharGlyph {
    private final char character; // intrinsic – shared
    private final Font font;      // intrinsic – shared

    CharGlyph(char c, Font f) { this.character = c; this.font = f; }

    // Extrinsic state (x, y) được truyền vào khi draw
    public void draw(int x, int y, Color color) {
        System.out.printf("Draw '%c' at (%d,%d) color=%s font=%s%n",
            character, x, y, color, font);
    }
}

// Flyweight Factory – cache và reuse
public class CharGlyphFactory {
    private static final Map<String, CharGlyph> cache = new HashMap<>();

    public static CharGlyph getGlyph(char c, Font font) {
        String key = c + font.getName();
        return cache.computeIfAbsent(key, k -> new CharGlyph(c, font));
    }
}

// Document: lưu extrinsic state riêng
public class TextEditor {
    record GlyphPosition(CharGlyph glyph, int x, int y, Color color) {}
    private final List<GlyphPosition> positions = new ArrayList<>();

    public void addChar(char c, Font font, int x, int y, Color color) {
        CharGlyph glyph = CharGlyphFactory.getGlyph(c, font); // shared!
        positions.add(new GlyphPosition(glyph, x, y, color));
    }
    // 1 triệu ký tự 'a' → chỉ 1 CharGlyph object, không phải 1 triệu!
}
```

### Real-world
- Java `Integer.valueOf(-128 to 127)` – Integer cache pool
- `String.intern()` – String pool
- Java `Boolean.TRUE` / `Boolean.FALSE` – không tạo mới
- Font/Glyph rendering trong các editor
- Entity objects được cache trong JPA

---

## 7. Proxy

### What
Cung cấp **placeholder** kiểm soát truy cập tới object thực — thêm behavior trước/sau mà không sửa object gốc.

**Các loại Proxy:**
- **Virtual Proxy**: lazy initialization
- **Protection Proxy**: access control
- **Remote Proxy**: local interface cho remote object
- **Caching Proxy**: cache kết quả
- **Logging Proxy**: ghi log

### How – Static Proxy

```java
public interface UserService {
    User findById(Long id);
    User save(User user);
}

// Real subject
public class UserServiceImpl implements UserService {
    public User findById(Long id) { return repo.findById(id); }
    public User save(User user) { return repo.save(user); }
}

// Logging Proxy
public class LoggingUserServiceProxy implements UserService {
    private final UserService delegate;
    private final Logger log = LoggerFactory.getLogger(getClass());

    public LoggingUserServiceProxy(UserService delegate) { this.delegate = delegate; }

    @Override
    public User findById(Long id) {
        log.info("Finding user by id: {}", id);
        long start = System.currentTimeMillis();
        User result = delegate.findById(id);
        log.info("Found user in {}ms", System.currentTimeMillis() - start);
        return result;
    }

    @Override
    public User save(User user) {
        log.info("Saving user: {}", user.getEmail());
        User saved = delegate.save(user);
        log.info("Saved user with id: {}", saved.getId());
        return saved;
    }
}
```

### How – JDK Dynamic Proxy (Runtime)

```java
UserService realService = new UserServiceImpl(repo);

// Dynamic proxy tạo tại runtime
UserService proxy = (UserService) Proxy.newProxyInstance(
    UserService.class.getClassLoader(),
    new Class[]{UserService.class},
    (proxyObj, method, args) -> {
        System.out.println("Before: " + method.getName());
        Object result = method.invoke(realService, args);
        System.out.println("After: " + method.getName());
        return result;
    }
);

proxy.findById(1L);
// Before: findById
// [actual findById]
// After: findById
```

### How – CGLIB Proxy (Subclass-based)

JDK Proxy chỉ work với **interface**. CGLIB tạo subclass → work với **class thường**:
```java
// Spring AOP dùng cả hai:
// - JDK Proxy: nếu bean implement interface
// - CGLIB: nếu bean không implement interface (default từ Spring 5.2)
@Aspect
@Component
public class LoggingAspect {
    @Around("@annotation(Loggable)")
    public Object log(ProceedingJoinPoint pjp) throws Throwable {
        log.info("Calling: {}", pjp.getSignature());
        Object result = pjp.proceed(); // call real method
        log.info("Returned: {}", result);
        return result;
    }
}
```

### How – Virtual Proxy (Lazy Initialization)
```java
public class ExpensiveImageProxy implements Image {
    private final String filename;
    private Image realImage; // null cho đến khi cần

    public ExpensiveImageProxy(String filename) { this.filename = filename; }

    @Override
    public void display() {
        if (realImage == null) {
            realImage = new RealImage(filename); // load từ disk – chỉ khi cần!
        }
        realImage.display();
    }
}
```

### Real-world
- Spring AOP: `@Transactional`, `@Cacheable`, `@Async` → tất cả là Proxy
- Hibernate Lazy Loading: `getAddress()` trả về proxy, load DB khi access
- Spring Security: method security proxy
- `java.lang.reflect.Proxy` trong nhiều framework

---

## Compare – Structural Patterns

| Pattern | Giải quyết | Cơ chế chính |
|---------|-----------|-------------|
| Adapter | Interface incompatible | Wrapping + translation |
| Bridge | Explosion of subclasses | Composition (abstraction + impl) |
| Composite | Tree structure | Uniform interface cho leaf + composite |
| Decorator | Add behavior dynamically | Wrapping (same interface) |
| Facade | Complex subsystem | Simplified interface |
| Flyweight | Memory (many similar objects) | Shared intrinsic state |
| Proxy | Access control, AOP | Wrapping + intercept |

---

## Trade-offs tổng hợp

| Pattern | Ưu | Nhược |
|---------|-----|-------|
| Adapter | Reuse legacy code | Thêm complexity nếu quá nhiều adapter |
| Bridge | Flexible 2D extension | Tăng complexity ban đầu |
| Composite | Uniform tree ops | Khó restrict kiểu component |
| Decorator | Dynamic, stackable | Nhiều object nhỏ, debug khó |
| Facade | Đơn giản hóa | Có thể trở thành God Object |
| Flyweight | Tiết kiệm memory | Phức tạp state management |
| Proxy | Transparent AOP | Reflection overhead |

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Design Patterns – Behavioral** (Strategy, Observer, Template Method, Command, Chain of Responsibility, Iterator, State, Visitor, Mediator)
>
> Keyword: Strategy (algorithm family), Observer (event system, push vs pull model), Template Method (skeleton + hooks), Command (request as object, undo/redo), Chain of Responsibility (handler chain), State (FSM), Visitor (double dispatch), Mediator (loose coupling between objects)
