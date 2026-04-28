# Java I/O & NIO (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Java I/O là gì?

Java có 3 thế hệ I/O API:
1. **java.io** (Java 1.0): stream-based, blocking
2. **java.nio** (Java 1.4): buffer + channel, non-blocking
3. **java.nio.file** / NIO.2 (Java 7): high-level file API (`Path`, `Files`)

---

## How – java.io: Stream-based I/O

### Hierarchy

```
InputStream (abstract)           OutputStream (abstract)
  ├── FileInputStream               ├── FileOutputStream
  ├── ByteArrayInputStream          ├── ByteArrayOutputStream
  ├── BufferedInputStream           ├── BufferedOutputStream
  ├── DataInputStream               ├── DataOutputStream
  ├── ObjectInputStream             ├── ObjectOutputStream
  └── FilterInputStream             └── FilterOutputStream

Reader (abstract)                Writer (abstract)
  ├── FileReader                    ├── FileWriter
  ├── BufferedReader                ├── BufferedWriter
  ├── InputStreamReader             ├── OutputStreamWriter
  └── StringReader                  └── PrintWriter
```

### Byte Stream – Binary Data

```java
// Đọc file binary
try (InputStream in  = new BufferedInputStream(new FileInputStream("image.png"));
     OutputStream out = new BufferedOutputStream(new FileOutputStream("copy.png"))) {
    in.transferTo(out); // Java 9+ – copy tất cả bytes
}

// Đọc từng chunk
byte[] buffer = new byte[8192]; // 8KB buffer
int bytesRead;
while ((bytesRead = in.read(buffer)) != -1) {
    out.write(buffer, 0, bytesRead);
}
```

### Character Stream – Text Data (với Charset)

```java
// Đọc text file
try (BufferedReader reader = new BufferedReader(
        new InputStreamReader(new FileInputStream("data.txt"), StandardCharsets.UTF_8))) {
    String line;
    while ((line = reader.readLine()) != null) {
        process(line);
    }
}

// Ghi text file
try (PrintWriter writer = new PrintWriter(
        new OutputStreamWriter(new FileOutputStream("out.txt"), StandardCharsets.UTF_8))) {
    writer.println("Hello, World!");
    writer.printf("Value: %d%n", 42);
}
```

### Tại sao cần Buffering?

```java
// KHÔNG buffer: mỗi read() = 1 system call → chậm
FileInputStream raw = new FileInputStream("large.txt");
int b;
while ((b = raw.read()) != -1) { process(b); } // ~1 tỷ system calls cho file 1GB

// VỚI buffer: đọc 8KB/lần → ít system calls hơn rất nhiều
BufferedInputStream buffered = new BufferedInputStream(raw, 8192);
while ((b = buffered.read()) != -1) { process(b); } // đọc từ buffer trong RAM
```

### Serialization

```java
// Object phải implement Serializable
public class User implements Serializable {
    @Serial
    private static final long serialVersionUID = 1L; // version control
    private String name;
    private transient String password; // transient: không serialize
}

// Serialize
try (ObjectOutputStream oos = new ObjectOutputStream(new FileOutputStream("user.dat"))) {
    oos.writeObject(user);
}

// Deserialize
try (ObjectInputStream ois = new ObjectInputStream(new FileInputStream("user.dat"))) {
    User user = (User) ois.readObject();
}
```

---

## How – java.nio: Channel + Buffer + Selector

### Channel – Bidirectional I/O

```java
// FileChannel – random access, memory-mapped
try (FileChannel channel = FileChannel.open(
        Path.of("data.bin"), StandardOpenOption.READ, StandardOpenOption.WRITE)) {

    // Đọc vào ByteBuffer
    ByteBuffer buffer = ByteBuffer.allocate(1024);
    int bytesRead = channel.read(buffer);

    // Ghi từ ByteBuffer
    buffer.flip(); // switch từ write mode → read mode
    channel.write(buffer);

    // Position
    channel.position(100);    // seek tới byte 100
    channel.size();           // file size
    channel.truncate(1024);   // cắt file
}

// Channel transfer – efficient copy (OS-level, zero-copy)
try (FileChannel src = FileChannel.open(source, READ);
     FileChannel dst = FileChannel.open(dest, CREATE, WRITE)) {
    src.transferTo(0, src.size(), dst); // zero-copy!
}
```

### ByteBuffer – State Machine

```
Capacity: tổng sức chứa (bất biến)
Limit:    vị trí cuối cùng có thể đọc/ghi
Position: vị trí hiện tại

Write mode: position tăng khi ghi, limit = capacity
Read mode:  position tăng khi đọc, limit = số byte đã ghi
```

```java
ByteBuffer buf = ByteBuffer.allocate(10);
// State: [pos=0, lim=10, cap=10]

buf.put((byte) 1);
buf.put((byte) 2);
buf.put((byte) 3);
// State: [pos=3, lim=10, cap=10]  ← write mode

buf.flip();
// State: [pos=0, lim=3, cap=10]   ← switch to read mode

byte b1 = buf.get(); // b1=1
byte b2 = buf.get(); // b2=2
// State: [pos=2, lim=3, cap=10]

buf.clear();
// State: [pos=0, lim=10, cap=10]  ← reset (data vẫn còn nhưng bị "forgotten")

buf.compact();
// Di chuyển unread data về đầu, position sau data còn lại → tiếp tục ghi
```

### Selector – Non-blocking I/O Multiplexing

```java
// 1 thread handle nhiều channel non-blocking
Selector selector = Selector.open();

ServerSocketChannel serverChannel = ServerSocketChannel.open();
serverChannel.bind(new InetSocketAddress(8080));
serverChannel.configureBlocking(false); // NON-BLOCKING!
serverChannel.register(selector, SelectionKey.OP_ACCEPT);

while (true) {
    selector.select(); // block cho đến khi có event
    Set<SelectionKey> keys = selector.selectedKeys();
    Iterator<SelectionKey> iter = keys.iterator();

    while (iter.hasNext()) {
        SelectionKey key = iter.next();
        iter.remove();

        if (key.isAcceptable()) {
            SocketChannel client = serverChannel.accept();
            client.configureBlocking(false);
            client.register(selector, SelectionKey.OP_READ);
        } else if (key.isReadable()) {
            SocketChannel client = (SocketChannel) key.channel();
            ByteBuffer buf = ByteBuffer.allocate(256);
            int bytes = client.read(buf);
            if (bytes == -1) { client.close(); key.cancel(); }
            else { handleData(buf); }
        }
    }
}
```

---

## How – NIO.2 (java.nio.file): High-level File API

### Path

```java
// Tạo Path
Path p1 = Path.of("src/main/java/Main.java");          // Java 11+
Path p2 = Paths.get("src", "main", "java", "Main.java"); // Java 7+

// Navigation
p1.getFileName();    // Main.java
p1.getParent();      // src/main/java
p1.getRoot();        // null (relative) hoặc / (absolute)
p1.isAbsolute();     // false
p1.toAbsolutePath(); // /full/path/to/src/main/java/Main.java

// Resolve và Relativize
Path base = Path.of("/home/user");
base.resolve("docs/file.txt");      // /home/user/docs/file.txt
base.relativize(Path.of("/home/user/docs")); // docs

// Normalize
Path ugly = Path.of("/home/user/../user/./docs");
ugly.normalize(); // /home/user/docs
```

### Files – Utility class

```java
// Đọc toàn bộ file
String content = Files.readString(path);                          // Java 11+
List<String> lines = Files.readAllLines(path, UTF_8);
byte[] bytes = Files.readAllBytes(path);

// Ghi file
Files.writeString(path, content, CREATE, TRUNCATE_EXISTING);     // Java 11+
Files.write(path, lines, UTF_8);
Files.write(path, bytes);

// Stream-based (lazy, với try-with-resources)
try (Stream<String> lines = Files.lines(path, UTF_8)) {
    lines.filter(l -> l.contains("ERROR")).forEach(System.out::println);
}

// Copy, Move, Delete
Files.copy(source, target, REPLACE_EXISTING);
Files.move(source, target, REPLACE_EXISTING, ATOMIC_MOVE);
Files.delete(path);             // throw nếu không tồn tại
Files.deleteIfExists(path);     // không throw

// Tạo file/directory
Files.createFile(path);
Files.createDirectory(path);
Files.createDirectories(path);  // tạo cả parent dirs
Files.createTempFile("prefix", ".tmp");

// Kiểm tra
Files.exists(path);
Files.isDirectory(path);
Files.isRegularFile(path);
Files.isReadable(path);
Files.size(path);
Files.getLastModifiedTime(path);

// Walk directory
try (Stream<Path> walk = Files.walk(Path.of("src"))) {
    walk.filter(Files::isRegularFile)
        .filter(p -> p.toString().endsWith(".java"))
        .forEach(System.out::println);
}

// Find files
try (Stream<Path> found = Files.find(start, maxDepth,
        (path, attrs) -> attrs.isRegularFile() && path.toString().endsWith(".log"))) {
    found.forEach(System.out::println);
}

// List directory (không recursive)
try (Stream<Path> entries = Files.list(Path.of("."))) {
    entries.forEach(System.out::println);
}
```

### WatchService – File System Events

```java
WatchService watcher = FileSystems.getDefault().newWatchService();
Path dir = Path.of("config/");
dir.register(watcher,
    StandardWatchEventKinds.ENTRY_CREATE,
    StandardWatchEventKinds.ENTRY_MODIFY,
    StandardWatchEventKinds.ENTRY_DELETE);

Thread watchThread = new Thread(() -> {
    while (true) {
        WatchKey key = watcher.take(); // block
        for (WatchEvent<?> event : key.pollEvents()) {
            WatchEvent.Kind<?> kind = event.kind();
            Path changed = (Path) event.context();
            System.out.println(kind + ": " + changed);
        }
        key.reset(); // PHẢI reset để tiếp tục nhận event
    }
});
watchThread.setDaemon(true);
watchThread.start();
```

---

## How – Memory-Mapped Files

```java
// Map một phần file vào memory – cực nhanh cho large files
try (FileChannel channel = FileChannel.open(path, READ)) {
    long size = channel.size();
    MappedByteBuffer mapped = channel.map(FileChannel.MapMode.READ_ONLY, 0, size);

    // Đọc như ByteBuffer nhưng data từ file system cache
    while (mapped.hasRemaining()) {
        byte b = mapped.get();
        process(b);
    }
}
// Ứng dụng: đọc file lớn, binary search trong sorted file
```

---

## When – Chọn I/O API nào?

| Tình huống | Dùng |
|-----------|------|
| Đọc/ghi file text đơn giản | `Files.readString()`, `Files.writeString()` |
| Xử lý file lớn line-by-line | `Files.lines()` với Stream |
| Binary data | `FileInputStream` + `BufferedInputStream` |
| Serialization Java object | `ObjectInputStream/OutputStream` |
| Network programming | NIO `SocketChannel` + `Selector` |
| High-throughput server (C10K) | NIO non-blocking + Selector |
| File copy hiệu quả | `FileChannel.transferTo()` |
| Large file random access | `MappedByteBuffer` |
| File system monitoring | `WatchService` |
| Async file I/O | `AsynchronousFileChannel` |

---

## Compare – I/O vs NIO vs NIO.2

| | java.io | java.nio | java.nio.file (NIO.2) |
|--|---------|---------|----------------------|
| API level | Low-level streams | Buffer + Channel | High-level |
| Blocking | Blocking | Non-blocking option | Blocking (high-level) |
| Selector | Không | Có | Không |
| File API | `File` (limited) | `FileChannel` | `Path`, `Files` |
| Async | Không | Có (`AsynchronousChannel`) | `WatchService` async |
| Use case | Simple I/O | Network, high-perf | File system operations |
| Learning curve | Thấp | Cao | Trung bình |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| java.io đơn giản, dễ dùng | java.io blocking: scale kém |
| NIO scalable (1 thread nhiều conn) | NIO phức tạp (ByteBuffer state machine) |
| NIO.2 API đẹp, concise | NIO.2 vẫn blocking ở high-level |
| Memory-mapped: zero-copy performance | Memory-mapped: không unmap được chủ động |
| transferTo: OS-level zero-copy | WatchService: OS-dependent behavior |

---

## Real-world Usage (Production)

### 1. Config File Watcher (Auto-reload)
```java
@Service
public class ConfigWatcher {
    private final WatchService watcher = FileSystems.getDefault().newWatchService();
    private final Path configDir = Path.of("config");

    @PostConstruct
    public void start() throws IOException {
        configDir.register(watcher, ENTRY_MODIFY);
        Thread.ofVirtual().start(this::watch); // Java 21 Virtual Thread
    }

    private void watch() {
        while (true) {
            WatchKey key = watcher.take();
            key.pollEvents().forEach(event -> {
                Path changed = configDir.resolve((Path) event.context());
                log.info("Config changed: {}", changed);
                configService.reload(changed);
            });
            key.reset();
        }
    }
}
```

### 2. Large CSV Processing
```java
public void processCsv(Path csvFile) throws IOException {
    try (Stream<String> lines = Files.lines(csvFile, StandardCharsets.UTF_8)) {
        lines.skip(1) // skip header
            .parallel()
            .map(line -> line.split(","))
            .map(this::parseLine)
            .filter(Objects::nonNull)
            .forEach(this::saveToDatabase);
    }
}
```

### 3. File Upload với efficient copy
```java
public void handleUpload(InputStream inputStream, Path destination) throws IOException {
    Files.createDirectories(destination.getParent());
    try (ReadableByteChannel src = Channels.newChannel(inputStream);
         FileChannel dst = FileChannel.open(destination, CREATE, WRITE, TRUNCATE_EXISTING)) {
        dst.transferFrom(src, 0, Long.MAX_VALUE);
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Design Patterns – Creational** (Singleton, Builder, Factory Method, Abstract Factory, Prototype)
>
> Keyword: Singleton thread-safe variants (DCL, enum, initialization-on-demand holder), Builder (telescoping constructor problem, inner static class), Factory Method vs Abstract Factory, Prototype (shallow vs deep copy)
