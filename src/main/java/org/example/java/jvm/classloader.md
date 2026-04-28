# JVM ClassLoader (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – ClassLoader là gì?

**ClassLoader** là thành phần của JVM chịu trách nhiệm **tìm kiếm, load, và link** class files (.class bytecode) vào JVM runtime. Mỗi class trong JVM được identify bởi cả **class name** lẫn **ClassLoader** load nó.

---

## How – 3 Giai đoạn Class Loading

```
Class Loading Pipeline:
1. Loading    → Tìm bytecode (.class file), tạo Class object
2. Linking
   2a. Verification  → Kiểm tra bytecode hợp lệ
   2b. Preparation   → Allocate static fields, set default values
   2c. Resolution    → Resolve symbolic references → direct references
3. Initialization → Chạy static initializer (<clinit>)
```

### Giai đoạn 1: Loading
- Tìm `.class` file từ classpath, JAR, network...
- Đọc bytecode vào memory
- Tạo `java.lang.Class` object đại diện cho class

### Giai đoạn 2: Linking

**Verification** (quan trọng nhất về security):
```
- Bytecode format hợp lệ (magic number 0xCAFEBABE)
- Kiểm tra type safety (không dùng sai kiểu)
- Kiểm tra stack consistency (không underflow/overflow)
- Kiểm tra access control (private không bị gọi ngoài class)
```

**Preparation**:
```java
class Example {
    static int count;          // → set về 0 (default)
    static String name;        // → set về null (default)
    static final int MAX = 100; // → 100 (compile-time constant, done ở preparation)
}
```

**Resolution**:
```
// Thay symbolic reference bằng direct reference
// Symbolic: "com/example/UserService.findById:(J)Lcom/example/User;"
// Direct: memory address của actual method
```

### Giai đoạn 3: Initialization
```java
class Example {
    static int x = 10;              // static field initializer
    static List<String> list;

    static {                         // static initializer block
        list = new ArrayList<>();
        list.add("init");
        System.out.println("Class initialized!");
    }
}
// <clinit> method (static initializer) chạy ONCE, thread-safe by JVM
```

**Initialization trigger** (6 trường hợp):
1. `new`, `getstatic`, `putstatic`, `invokestatic` lần đầu
2. Reflect: `Class.forName()` (trừ khi `initialize=false`)
3. Subclass được initialize → superclass phải initialize trước
4. JVM startup class
5. Method handle resolve
6. Record class, sealed class (Java 16+)

---

## Components – ClassLoader Hierarchy

```
Bootstrap ClassLoader (C++, không phải Java)
  └── Platform ClassLoader (Java 9+, trước là Extension CL)
        └── Application ClassLoader (System ClassLoader)
              └── Custom ClassLoader (nếu có)
                    └── Child Custom ClassLoader
```

### Bootstrap ClassLoader
- Load **core Java API**: `java.lang.*`, `java.util.*`, `java.io.*`...
- Đọc từ: `$JAVA_HOME/lib/` (Java 8) hoặc built vào JDK (Java 9+ Modules)
- Viết bằng C++, không có Java instance (`ClassLoader.getParent()` = null)

```java
String.class.getClassLoader();  // null → bootstrap
Object.class.getClassLoader(); // null → bootstrap
```

### Platform ClassLoader (Java 9+) / Extension ClassLoader (Java 8)
- Load **extension APIs**: `java.sql.*`, `java.xml.*`, `javax.*`...
- Java 8: đọc từ `$JAVA_HOME/lib/ext/`
- Java 9+: load từ platform modules

### Application ClassLoader
- Load **application code**: `-classpath`, `-cp`
- Đây là ClassLoader mặc định khi bạn viết code

```java
MyClass.class.getClassLoader();        // AppClassLoader
Thread.currentThread().getContextClassLoader(); // thường là AppClassLoader
ClassLoader.getSystemClassLoader();    // AppClassLoader
```

---

## How – Parent Delegation Model

**Quy tắc**: Khi ClassLoader được yêu cầu load class, nó **hỏi parent trước**:

```
1. Child CL nhận yêu cầu load "com.example.MyClass"
2. Delegate lên Parent CL (Application CL)
3. Application CL delegate lên Platform CL
4. Platform CL delegate lên Bootstrap CL
5. Bootstrap tìm → không thấy (không phải core class)
6. Platform tìm → không thấy
7. Application tìm → thấy trong classpath → load!
```

```java
// Implementation concept
public Class<?> loadClass(String name) throws ClassNotFoundException {
    // 1. Check cache
    Class<?> c = findLoadedClass(name);
    if (c != null) return c;

    // 2. Delegate to parent first
    try {
        if (parent != null) c = parent.loadClass(name);
        else c = bootstrapLoadClass(name);
    } catch (ClassNotFoundException e) {
        // parent không load được → tự tìm
    }

    // 3. Self load nếu parent không có
    if (c == null) c = findClass(name);
    return c;
}
```

**Tại sao cần parent delegation?**
1. **Security**: không thể hijack `java.lang.String` bằng class mình viết
2. **Consistency**: `java.lang.Object` chỉ load 1 lần, tất cả đều dùng chung
3. **Avoid duplication**: class không load 2 lần nếu parent đã có

---

## How – Custom ClassLoader

```java
public class HotReloadClassLoader extends ClassLoader {
    private final Path classesDir;
    private final Map<String, Long> lastModified = new HashMap<>();

    public HotReloadClassLoader(Path classesDir, ClassLoader parent) {
        super(parent);
        this.classesDir = classesDir;
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        Path classFile = classesDir.resolve(name.replace('.', '/') + ".class");

        if (!Files.exists(classFile)) throw new ClassNotFoundException(name);

        try {
            byte[] bytes = Files.readAllBytes(classFile);
            lastModified.put(name, Files.getLastModifiedTime(classFile).toMillis());
            return defineClass(name, bytes, 0, bytes.length); // register với JVM
        } catch (IOException e) {
            throw new ClassNotFoundException(name, e);
        }
    }

    public boolean isModified(String name) throws IOException {
        Path classFile = classesDir.resolve(name.replace('.', '/') + ".class");
        long current = Files.getLastModifiedTime(classFile).toMillis();
        return !current.equals(lastModified.get(name));
    }

    // Reload: tạo ClassLoader mới (ClassLoader không thể unload class riêng lẻ)
    public HotReloadClassLoader reload() {
        return new HotReloadClassLoader(classesDir, getParent());
    }
}

// Dùng
HotReloadClassLoader loader = new HotReloadClassLoader(Path.of("build/classes"), getClass().getClassLoader());
Class<?> clazz = loader.loadClass("com.example.Handler");
Object handler = clazz.getDeclaredConstructor().newInstance();
```

---

## How – ClassLoader Isolation (ClassLoader Hell)

**Quan trọng**: 2 class cùng tên nhưng load bởi 2 ClassLoader khác nhau = 2 class **khác nhau** hoàn toàn!

```java
ClassLoader cl1 = new URLClassLoader(urls, null); // parent = bootstrap only!
ClassLoader cl2 = new URLClassLoader(urls, null);

Class<?> c1 = cl1.loadClass("com.example.Plugin");
Class<?> c2 = cl2.loadClass("com.example.Plugin");

System.out.println(c1 == c2);          // FALSE! Khác ClassLoader → khác Class
System.out.println(c1.isInstance(c2.newInstance())); // FALSE! ClassCastException nếu cast!
```

**ClassCastException trong application server**:
```
Cause: class com.example.Service cannot be cast to com.example.Service
// Thực ra: 2 class cùng tên nhưng khác ClassLoader (WAR và container scope)
```

**Giải pháp**: dùng **context ClassLoader**:
```java
// SPI (Service Provider Interface) pattern
Thread.currentThread().getContextClassLoader().loadClass("driver.ClassName");
```

---

## How – Class.forName() vs ClassLoader.loadClass()

```java
// Class.forName() – load VÀ initialize (chạy static initializer)
Class<?> c = Class.forName("com.example.Plugin"); // <clinit> chạy

// Class.forName() với initialize=false – load KHÔNG initialize
Class<?> c2 = Class.forName("com.example.Plugin", false, loader);

// ClassLoader.loadClass() – load KHÔNG initialize (giống forName với false)
Class<?> c3 = loader.loadClass("com.example.Plugin");

// Thực tế: dùng Class.forName() cho SPI, JDBC driver registration
Class.forName("org.postgresql.Driver"); // trigger static block đăng ký driver
```

---

## How – Memory & GC của ClassLoader

```
Metaspace (Java 8+):
  Lưu: Class metadata, method bytecode, constant pool
  Không thuộc Heap → không bị GC thông thường

Class Unloading:
  Class được unload khi:
  1. ClassLoader bị garbage collected
  2. Không có reference nào đến Class object nữa
  Bootstrap-loaded classes: KHÔNG BAO GIỜ được unload

Metaspace OOM:
  Nguyên nhân: load quá nhiều class (code generation, hot reload mà không unload)
  Fix: -XX:MaxMetaspaceSize=256m hoặc sửa ClassLoader leak
```

---

## When – Khi nào cần Custom ClassLoader?

| Use case | Custom ClassLoader |
|---------|-------------------|
| Hot reload (không restart) | Tạo ClassLoader mới khi file thay đổi |
| Plugin system | Mỗi plugin có ClassLoader riêng, isolation |
| Load class từ DB/network | Override `findClass()` |
| Bytecode manipulation | Transform bytecode trước khi `defineClass()` |
| OSGi, Java EE containers | Bundle/WAR isolation |

---

## Compare – ClassLoader trong Java 8 vs Java 9+

| | Java 8 | Java 9+ (Modules) |
|--|--------|------------------|
| Bootstrap | JRE core classes | JDK modules (java.base...) |
| Extension CL | `lib/ext/` | Platform ClassLoader |
| Classpath | `-classpath` | `-classpath` hoặc `--module-path` |
| Encapsulation | Yếu (reflection bypass) | Mạnh (module boundary) |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Security (parent delegation) | ClassLoader hell phức tạp |
| Isolation (plugin system) | ClassCastException giữa ClassLoader |
| Lazy loading (tiết kiệm memory) | Metaspace leak nếu không unload |
| Hot reload khả thi | Performance overhead khi load nhiều class |

---

## Real-world Usage (Production)

### 1. SPI (Service Provider Interface)
```java
// Java 6+: ServiceLoader dùng context ClassLoader
ServiceLoader<PaymentProvider> providers =
    ServiceLoader.load(PaymentProvider.class, Thread.currentThread().getContextClassLoader());
providers.forEach(provider -> registry.register(provider));
```

### 2. JDBC Driver Registration (Java 4 cách cũ)
```java
Class.forName("org.postgresql.Driver"); // static block đăng ký driver
// Java 6+: JDBC 4.0 auto-registration qua SPI (không cần Class.forName nữa)
```

### 3. Tomcat – WAR Isolation
```java
// Mỗi WAR có WebappClassLoader riêng
// Parent: shared classloader (common libs)
// Mỗi WAR: độc lập, không ảnh hưởng nhau
// Quan trọng: context ClassLoader = WebappClassLoader trong mỗi request thread
```

### 4. Spring Boot – Fat JAR ClassLoader
```java
// Spring Boot LaunchedURLClassLoader wrap JarFile trong JAR
// Load class từ BOOT-INF/classes/ và BOOT-INF/lib/*.jar
// Cho phép "nested JARs" pattern
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **JIT Compiler & JVM Performance**
>
> Keyword: Interpreter vs JIT, tiered compilation (C1/C2/Graal), hot methods, method inlining, escape analysis, loop unrolling, on-stack replacement (OSR), JVM flags (`-XX:+PrintCompilation`, `-XX:+UnlockDiagnosticVMOptions`), GraalVM AOT, JVM profiling tools (JFR, JMC, async-profiler)
