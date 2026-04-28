# String – Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – String trong Java

`String` là class đặc biệt nhất trong Java:
- **Immutable**: một khi tạo ra, nội dung không thay đổi
- **Interned**: string literals chia sẻ từ String Pool
- **Overloaded operators**: `+` và `+=` được compile-time xử lý đặc biệt
- **char[] backed**: Java 8 và trước. **byte[] backed**: Java 9+ (Compact Strings)

```java
// String là object nhưng hoạt động như primitive
String s = "hello"; // không cần new
"hello".length();   // method call trên literal hợp lệ
```

---

## How – String Pool & Immutability

### String Pool (String Interning)

```java
// String literals → tự động vào String Pool (Heap, Java 7+)
String a = "hello";
String b = "hello";
System.out.println(a == b);       // true! (cùng reference trong pool)
System.out.println(a.equals(b));  // true (nội dung bằng nhau)

// new String() → KHÔNG từ pool, tạo object mới trong heap
String c = new String("hello");
System.out.println(a == c);       // false (khác object)
System.out.println(a.equals(c));  // true (cùng nội dung)

// c.intern() → trả về reference từ pool (hoặc thêm vào pool nếu chưa có)
String d = c.intern();
System.out.println(a == d);       // true! (cùng pool reference)

// Compile-time constant folding → vào pool
String e = "hel" + "lo";         // compiler tính = "hello" → pool
System.out.println(a == e);       // true! (compiler optimized)

// Runtime concatenation → KHÔNG compile-time
String f = "hel";
String g = f + "lo";              // runtime → new String object
System.out.println(a == g);       // false!

final String h = "hel";           // final → compile-time constant!
String i = h + "lo";              // compile-time = "hello" → pool
System.out.println(a == i);       // true!

// Tại sao a.equals(b) chứ không phải a == b?
// == so sánh reference (địa chỉ bộ nhớ)
// .equals() so sánh nội dung (phải dùng trong code production)
```

### Tại sao String Immutable?

```java
// 1. String Pool khả thi nhờ immutability
// Nếu String mutable: thay đổi "hello" → ảnh hưởng tất cả references trong pool!

// 2. Thread-safety: không cần synchronization
String s = "hello";
// Thread 1 và Thread 2 đều đọc s → an toàn, không ai thay đổi được

// 3. Hash code caching: HashMap key an toàn
// String.hashCode() được cache sau lần tính đầu tiên (field hash)
// Nếu mutable: hashCode thay đổi → HashMap corrupt!

// 4. Security: không ai sửa được (class names, file paths, DB URL)
String url = "jdbc:postgresql://localhost/mydb";
connect(url); // không ai có thể modify url sau khi truyền vào

// Cơ chế immutability:
// - char[] value là private final (không thể reassign)
// - Không có setter methods
// - char[] không exposed ra ngoài (defensive copy nếu cần)
```

### Compact Strings (Java 9+)

```java
// Java 8: String backed by char[] (UTF-16, 2 bytes per char)
// Java 9+: String backed by byte[] + encoding flag
//   LATIN-1: 1 byte per char (nếu tất cả chars fit in Latin-1)
//   UTF-16: 2 bytes per char (fallback)

// Kết quả:
// ASCII string "hello" (5 chars): 8 bytes thay vì 10 bytes
// Tiết kiệm ~40% memory cho ASCII-heavy applications (common in web apps)

// Transparent với developer, không cần thay đổi code
-XX:+CompactStrings  // default ON (Java 9+)
-XX:-CompactStrings  // disable nếu cần diagnose
```

---

## How – String Concatenation Internals

```java
// String + operator: compiler KHÔNG nối trực tiếp (gây nhiều objects trung gian)

// Source code:
String result = "Hello, " + name + "! You are " + age + " years old.";

// Java 8 compiler → StringBuilder:
String result = new StringBuilder()
    .append("Hello, ")
    .append(name)
    .append("! You are ")
    .append(age)
    .append(" years old.")
    .toString();

// Java 9+ compiler → invokedynamic + StringConcatFactory (nhanh hơn)
// JVM tự optimize concatenation pattern tốt hơn

// NHƯNG: trong loop vẫn là vấn đề!
// Anti-pattern:
String s = "";
for (String item : list) {
    s += item + ", "; // mỗi vòng tạo StringBuilder MỚI + String mới!
}
// n items → n StringBuilder + n String objects → O(n²) chars copied!

// Fix: một StringBuilder cho toàn bộ loop
StringBuilder sb = new StringBuilder();
for (String item : list) {
    sb.append(item).append(", ");
}
// Xóa trailing ", "
if (sb.length() >= 2) sb.setLength(sb.length() - 2);
String result = sb.toString();

// Hoặc: String.join() (clean, readable)
String result2 = String.join(", ", list);

// Hoặc: Collectors.joining() trong Stream
String result3 = list.stream().collect(Collectors.joining(", "));
String result4 = list.stream().collect(Collectors.joining(", ", "[", "]")); // prefix/suffix
```

---

## How – StringBuilder vs StringBuffer

```java
// StringBuilder (Java 5+): NOT thread-safe, fast
// StringBuffer (Java 1.0): thread-safe (synchronized methods), slower

// Cả hai đều resizable (initial capacity 16, double when full)
StringBuilder sb = new StringBuilder(64); // initial capacity hint

// StringBuilder API
sb.append("hello").append(' ').append(42);   // chaining
sb.insert(5, " world");                      // insert at index
sb.delete(5, 11);                            // delete [5, 11)
sb.replace(0, 5, "Hi");                      // replace
sb.reverse();                                // reverse in place
sb.deleteCharAt(0);                          // delete single char
sb.setCharAt(0, 'H');                        // replace single char
sb.setLength(3);                             // truncate (hay để clear trailing)
sb.indexOf("ell");                           // search
char c = sb.charAt(2);                       // read char
String sub = sb.substring(1, 3);            // substring (non-destructive)
int len = sb.length();                       // current length
int cap = sb.capacity();                     // current capacity

// Khi nào StringBuffer?
// Hầu như KHÔNG BAO GIỜ trong code mới.
// Nếu cần thread-safe String building → dùng local StringBuilder + synchronized block riêng
// StringBuffer synchronized per-method không đủ cho compound operations anyway

// Capacity growth: if (count > capacity) → newCapacity = (value.length + 1) * 2
// → có thể setCapacity upfront nếu biết kích thước
```

---

## How – String Methods (Essential)

```java
String s = "  Hello, World!  ";

// Whitespace
s.trim();                    // "Hello, World!" (chỉ xóa ASCII whitespace: \t\n\r\f)
s.strip();                   // "Hello, World!" (Java 11+, xóa Unicode whitespace)
s.stripLeading();            // "Hello, World!  "
s.stripTrailing();           // "  Hello, World!"
s.isBlank();                 // false (Java 11+, true nếu empty or only whitespace)
"   ".isBlank();             // true
"".isEmpty();                // true (length == 0)

// Search
s = "Hello, World!";
s.contains("World");         // true
s.startsWith("Hello");       // true
s.endsWith("!");             // true
s.indexOf("o");              // 4 (first occurrence)
s.lastIndexOf("o");          // 8
s.indexOf("o", 5);           // 8 (start search from index 5)
s.matches("Hello.*");        // true (full regex match)

// Extract
s.charAt(0);                 // 'H'
s.substring(7);              // "World!"
s.substring(7, 12);          // "World"
char[] chars = s.toCharArray();
byte[] bytes = s.getBytes(StandardCharsets.UTF_8);

// Transform
s.toLowerCase();             // "hello, world!"
s.toUpperCase();             // "HELLO, WORLD!"
s.toLowerCase(Locale.ROOT);  // locale-insensitive (important for Turkish!)
s.replace('l', 'r');         // "Herro, Worrd!" (char replace)
s.replace("World", "Java");  // "Hello, Java!" (literal replace)
s.replaceAll("l+", "r");     // regex replace (beware performance)
s.replaceFirst("l", "r");    // replace first match

// Split & Join
"a,b,,c".split(",");         // ["a", "b", "", "c"]
"a,b,,c".split(",", -1);     // ["a", "b", "", "c"] (keep trailing empty)
"a,b,,c".split(",", 2);      // ["a", "b,,c"] (max 2 parts)
String.join(", ", "a", "b"); // "a, b"
String.join(", ", list);     // join collection

// Java 11+ additions
"hello\n".stripTrailing();   // "hello"
" ".repeat(5);               // "     "
"abc".repeat(3);             // "abcabcabc"
"line1\nline2\nline3".lines() // Stream<String>
    .filter(l -> !l.isBlank())
    .toList();

// Java 12+
String.formatted("Hello %s, you are %d", name, age); // = String.format(...)

// Comparison
"Hello".equalsIgnoreCase("hello"); // true
"Hello".compareTo("World");        // < 0 (lexicographic)
"Hello".compareToIgnoreCase("hello"); // 0

// NEVER use == for content comparison!
// "hello".equals(null) → false (safe, no NPE)
// Objects.equals(s1, s2) → null-safe equals
```

---

## How – Text Blocks (Java 15+)

```java
// Text block: multi-line string literal, no escape hell
String json = """
        {
            "name": "Alice",
            "age": 30,
            "email": "alice@example.com"
        }
        """;
// Trailing """ sets the indentation baseline
// Leading whitespace up to the closing """ column is stripped

// HTML
String html = """
        <html>
            <body>
                <p>Hello, %s!</p>
            </body>
        </html>
        """.formatted("Alice");

// SQL
String sql = """
        SELECT u.id, u.name, o.total
        FROM users u
        JOIN orders o ON o.user_id = u.id
        WHERE u.status = 'ACTIVE'
          AND o.created_at > :since
        ORDER BY o.total DESC
        """;

// Indentation rules:
// - Common leading whitespace (up to closing """) stripped automatically
// - \n at end of last content line before """ is included
// - """ on same line as last content → no trailing newline

// Escape sequences in text blocks:
// \s → single space (prevent trailing whitespace trimming)
// \   → line continuation (no newline at this point)
String oneLine = """
        Hello, \
        World!
        """; // → "Hello, World!\n"

// String.indent() (Java 12+)
"Hello\nWorld".indent(4);
// → "    Hello\n    World\n"

// String.stripIndent() (Java 15+)
// Remove common leading whitespace from multiline string
```

---

## How – Regular Expressions

### Pattern & Matcher

```java
// Pattern: compiled regex → THREAD-SAFE, cache và tái dùng!
// Matcher: stateful, NOT thread-safe (tạo mới từ Pattern cho mỗi use)

// ANTI-PATTERN: compile pattern mỗi lần
public boolean isValidEmail(String email) {
    return email.matches("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}");
    // String.matches() compile regex mỗi lần gọi!
}

// ĐÚNG: cache Pattern
public class EmailValidator {
    private static final Pattern EMAIL_PATTERN = Pattern.compile(
        "^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$"
    );

    public boolean isValid(String email) {
        return EMAIL_PATTERN.matcher(email).matches();
    }
}

// Matcher API
String text = "Hello, my name is Alice and I am 30 years old.";
Pattern numbers = Pattern.compile("\\d+");
Matcher m = numbers.matcher(text);

// find() vs matches():
// find(): tìm kiếm trong chuỗi (partial match)
// matches(): toàn bộ chuỗi phải khớp
while (m.find()) {
    System.out.println(m.group());      // "30"
    System.out.println(m.start());      // start index
    System.out.println(m.end());        // end index
}

// Groups
Pattern nameAge = Pattern.compile("name is (\\w+) and I am (\\d+)");
Matcher m2 = nameAge.matcher(text);
if (m2.find()) {
    System.out.println(m2.group(0)); // entire match
    System.out.println(m2.group(1)); // "Alice" (group 1)
    System.out.println(m2.group(2)); // "30" (group 2)
}

// Named groups (cleaner)
Pattern named = Pattern.compile("name is (?<name>\\w+) and I am (?<age>\\d+)");
Matcher m3 = named.matcher(text);
if (m3.find()) {
    System.out.println(m3.group("name")); // "Alice"
    System.out.println(m3.group("age"));  // "30"
}

// Replace with groups
String result = Pattern.compile("(\\w+)@(\\w+)")
    .matcher("alice@example.com")
    .replaceAll("[$1 at $2]"); // "[$1 at $2]" → "[alice at example]"

// replaceAll with lambda (Java 9+)
String result2 = Pattern.compile("\\d+")
    .matcher("I have 3 cats and 12 dogs")
    .replaceAll(mr -> String.valueOf(Integer.parseInt(mr.group()) * 2));
// → "I have 6 cats and 24 dogs"
```

### Common Regex Patterns

```java
// Pattern constants để tái dùng
public final class Patterns {
    // Email
    public static final Pattern EMAIL = Pattern.compile(
        "^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$"
    );
    // Phone (Vietnamese)
    public static final Pattern VN_PHONE = Pattern.compile(
        "^(\\+84|0)(3[2-9]|5[6-9]|7[0|6-9]|8[0-9]|9[0-9])[0-9]{7}$"
    );
    // UUID
    public static final Pattern UUID = Pattern.compile(
        "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        Pattern.CASE_INSENSITIVE
    );
    // IP Address
    public static final Pattern IPV4 = Pattern.compile(
        "^((25[0-5]|2[0-4]\\d|[01]?\\d\\d?)\\.){3}(25[0-5]|2[0-4]\\d|[01]?\\d\\d?)$"
    );
    // URL slug
    public static final Pattern SLUG = Pattern.compile("^[a-z0-9]+(?:-[a-z0-9]+)*$");
}
```

### Lookahead & Lookbehind

```java
// Positive lookahead: (?=...)  – match nếu tiếp theo là ...
// Negative lookahead: (?!...)  – match nếu tiếp theo KHÔNG phải ...
// Positive lookbehind: (?<=...) – match nếu trước đó là ...
// Negative lookbehind: (?<!...) – match nếu trước đó KHÔNG phải ...

// Tách theo dấu phẩy nhưng không tách trong ngoặc
// Đơn giản hóa: dùng (?<=...) lookbehind
Pattern splitOnCommaNotInParens = Pattern.compile(",(?![^(]*\\))");

// Password strength: phải có chữ hoa, chữ thường, số, ký tự đặc biệt
Pattern password = Pattern.compile(
    "^(?=.*[A-Z])(?=.*[a-z])(?=.*\\d)(?=.*[!@#$%^&*]).{8,}$"
);
// (?=.*[A-Z]) = lookahead: có ít nhất 1 chữ hoa ở đâu đó
// (?=.*[a-z]) = lookahead: có ít nhất 1 chữ thường
// (?=.*\\d) = lookahead: có ít nhất 1 số
// (?=.*[!@#$%^&*]) = lookahead: có ít nhất 1 special char
// .{8,} = ít nhất 8 ký tự

// Mask credit card (chỉ giữ 4 số cuối)
"1234-5678-9012-3456".replaceAll("\\d(?=\\d{4})", "*");
// → "****-****-****-3456"
// \\d(?=\\d{4}): mỗi digit theo sau bởi ít nhất 4 digits → mask
```

---

## How – String.format & Formatted Output

```java
// String.format() / String.formatted() (Java 15+)
String s1 = String.format("Hello, %s! You are %d years old.", name, age);
String s2 = "Hello, %s! You are %d years old.".formatted(name, age); // Java 15+

// Format specifiers:
// %s  → String (toString)
// %d  → decimal integer
// %f  → floating point (default 6 decimal places)
// %.2f → 2 decimal places
// %n  → platform line separator (\n trên Unix, \r\n trên Windows)
// %t  → date/time (nhiều subformats: %tY=year, %tm=month, %td=day)
// %b  → boolean
// %c  → char
// %x  → hex integer
// %o  → octal integer
// %e  → scientific notation
// %10s → right-align in field of 10 chars
// %-10s → left-align in field of 10 chars
// %010d → zero-pad to 10 chars

// Ví dụ
System.out.printf("%-20s | %10.2f%n", "Widget", 9.99);
// → "Widget               |       9.99"

// Table formatting
String header = "%-15s %-20s %10s%n".formatted("Name", "Email", "Amount");
String row = "%-15s %-20s %10.2f%n".formatted(name, email, amount);

// Formatted numbers
NumberFormat nf = NumberFormat.getNumberInstance(new Locale("vi", "VN"));
String formattedNum = nf.format(1234567.89); // "1.234.567,89"

NumberFormat currency = NumberFormat.getCurrencyInstance(new Locale("vi", "VN"));
String vnd = currency.format(1234567); // "1.234.567 ₫"
```

---

## How – Charset & Encoding

```java
// LUÔN chỉ định encoding explicitly!

// String → bytes
byte[] utf8Bytes = "Xin chào".getBytes(StandardCharsets.UTF_8);
byte[] utf16Bytes = "Xin chào".getBytes(StandardCharsets.UTF_16);

// bytes → String
String str = new String(utf8Bytes, StandardCharsets.UTF_8);

// Đọc file với encoding
try (BufferedReader reader = new BufferedReader(
        new InputStreamReader(new FileInputStream("file.txt"), StandardCharsets.UTF_8))) {
    reader.lines().forEach(System.out::println);
}

// Files API (Java 11+)
String content = Files.readString(Path.of("file.txt"), StandardCharsets.UTF_8);
Files.writeString(Path.of("output.txt"), content, StandardCharsets.UTF_8);

// Charset pitfalls:
// 1. Mặc định: Charset.defaultCharset() (platform-dependent, tránh dùng!)
//    Windows: Cp1252 (Windows-1252)
//    Linux: UTF-8
//    → Code chạy khác nhau trên các môi trường!

// 2. HTTP response encoding
// response.setCharacterEncoding("UTF-8"); // PHẢI set trước response.getWriter()
// Content-Type: application/json; charset=UTF-8

// 3. Java 18+: default charset là UTF-8 (cross-platform)
//    -Dfile.encoding=UTF-8 (Java 17 và trước)
//    -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8

// StandardCharsets constants (tránh "UTF-8" string typos):
StandardCharsets.UTF_8        // U+0000 - U+10FFFF
StandardCharsets.UTF_16       // UTF-16 với BOM
StandardCharsets.ISO_8859_1   // Latin-1
StandardCharsets.US_ASCII
StandardCharsets.UTF_16BE     // Big Endian
StandardCharsets.UTF_16LE     // Little Endian
```

---

## Components – String Performance Guide

| Operation | Performance | Ghi chú |
|-----------|------------|---------|
| `str1.equals(str2)` | O(n) | So sánh từng char |
| `str.hashCode()` | O(1) sau lần đầu | Cached in String |
| `str + other` (một lần) | OK | Compiler optimize |
| `str + other` (trong loop) | O(n²)! | Dùng StringBuilder |
| `String.join()` | O(n) | Optimal |
| `str.split(regex)` | Chậm nếu regex phức tạp | Cache Pattern nếu nhiều calls |
| `str.matches(regex)` | Chậm: compile mỗi lần | Dùng Pattern.compile() + cache |
| `str.intern()` | Synchronization overhead | Cẩn thận với volume lớn |
| `StringBuilder.append()` | O(1) amortized | Preferred for building |

---

## Why – String là immutable

```
Security:    class names, file paths, DB URLs không bị thay đổi sau khi truyền đi
Thread-safe: multiple threads đọc cùng String, không cần synchronization
Caching:     hashCode() có thể cache (HashMap key an toàn)
String Pool: reuse literals tiết kiệm memory
```

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Immutable → thread-safe, safe key | Tạo nhiều objects khi concat |
| String Pool → memory efficient | intern() có overhead |
| Rich API | split() regex overhead |
| Text blocks → readable multiline | Compact Strings: encoding checks per char |

---

## Real-world Usage (Production)

### 1. Efficient CSV Builder

```java
// StringBuilder với initial capacity ước tính
public String buildCsv(List<Order> orders) {
    StringBuilder sb = new StringBuilder(orders.size() * 100); // estimate
    sb.append("id,date,amount,status\n");
    for (Order o : orders) {
        sb.append(o.getId()).append(',')
          .append(o.getDate()).append(',')
          .append(o.getAmount()).append(',')
          .append(o.getStatus()).append('\n');
    }
    return sb.toString();
}
```

### 2. Input Sanitization với Regex

```java
public class InputSanitizer {
    // Cached patterns
    private static final Pattern HTML_TAGS = Pattern.compile("<[^>]+>");
    private static final Pattern MULTIPLE_SPACES = Pattern.compile("\\s{2,}");
    private static final Pattern SPECIAL_CHARS = Pattern.compile("[^a-zA-Z0-9\\s.,!?-]");

    public String sanitize(String input) {
        if (input == null) return null;
        return HTML_TAGS.matcher(input)
            .replaceAll("")                               // remove HTML
            .transform(s -> SPECIAL_CHARS.matcher(s).replaceAll("")) // remove special chars
            .strip()                                       // trim whitespace
            .transform(s -> MULTIPLE_SPACES.matcher(s).replaceAll(" ")); // collapse spaces
    }
}

// String.transform() (Java 12+): apply function to String → flexible chaining
String result = "  hello world  "
    .strip()
    .transform(String::toUpperCase)
    .transform(s -> "[" + s + "]");
// → "[HELLO WORLD]"
```

### 3. Template Engine đơn giản

```java
public class SimpleTemplate {
    private static final Pattern PLACEHOLDER = Pattern.compile("\\$\\{(\\w+)}");

    public String render(String template, Map<String, String> vars) {
        Matcher m = PLACEHOLDER.matcher(template);
        // Java 9+: replaceAll với Function
        return m.replaceAll(mr -> {
            String key = mr.group(1);
            String value = vars.get(key);
            return value != null ? Matcher.quoteReplacement(value) : mr.group();
            // Matcher.quoteReplacement(): escape $ và \ trong replacement string
        });
    }
}

// Template: "Hello, ${name}! Your order ${orderId} is ${status}."
// vars: {name: "Alice", orderId: "ORD-001", status: "shipped"}
// Result: "Hello, Alice! Your order ORD-001 is shipped."
```

---

## Ghi chú – Java Core bổ sung hoàn thành

> Đã thêm vào Java Core:
> - **reflection_annotations.md**: Class/Field/Method/Constructor API, Annotation (@Target/@Retention), AnnotationProcessor, Dynamic Proxy, MethodHandle
> - **datetime.md**: Instant/LocalDate/LocalDateTime/ZonedDateTime/Duration/Period, DateTimeFormatter, Clock, migration từ Date/Calendar, DST pitfalls
> - **strings.md**: String Pool, immutability internals, Compact Strings, StringBuilder, regex (Pattern/Matcher/groups/lookahead), text blocks, Charset/encoding
>
> Tiếp theo (nếu muốn tiếp tục core): **Serialization** (Java serialization, serialVersionUID, Externalizable, transient, security issues, alternatives: JSON/Protobuf/Kryo)
> Hoặc: **Testing** (JUnit 5, Mockito, Testcontainers, @SpringBootTest layers)
