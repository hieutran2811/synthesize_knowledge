# JVM Runtime Data Areas & Bytecode

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – JVM Runtime Data Areas là gì?

Khi JVM chạy, nó chia memory thành các vùng với mục đích khác nhau. Hiểu cấu trúc này giúp diagnose memory issues, hiểu stack traces, và optimize JVM settings.

```
JVM Memory Layout:
┌────────────────────────────────────────────────────┐
│  Method Area / Metaspace (per JVM, shared)         │
│  → class metadata, constant pool, method bytecode  │
├────────────────────────────────────────────────────┤
│  Heap (per JVM, shared between threads)            │
│  → all object instances, arrays                    │
├──────────────────────┬─────────────────────────────┤
│  Java Stack (Thread) │ Java Stack (Thread)         │
│  ┌────────────────┐  │ ┌────────────────┐          │
│  │  Stack Frame 1 │  │ │  Stack Frame 1 │          │
│  │  Stack Frame 2 │  │ │  Stack Frame 2 │          │
│  │  Stack Frame 3 │  │ └────────────────┘          │
│  └────────────────┘  │                             │
├──────────────────────┴─────────────────────────────┤
│  PC Register (per thread)                          │
│  → current bytecode instruction address            │
├────────────────────────────────────────────────────┤
│  Native Method Stack (per thread)                  │
│  → C/C++ stack for JNI native methods              │
└────────────────────────────────────────────────────┘
Non-heap (separate):
  Code Cache → JIT compiled native code
```

---

## How – Method Area / Metaspace

### Java 7: PermGen (Permanent Generation)

```
PermGen (in Heap):
  - Class metadata (fields, methods, superclass)
  - Runtime Constant Pool
  - Static variables (Java 7: moved to Heap)
  - Method bytecode
  - Interned Strings (Java 7: moved to Heap)

Problem:
  -XX:MaxPermSize=256m (fixed size!)
  → OOM: java.lang.OutOfMemoryError: PermGen space
  → Dynamic class generation (Groovy, Hibernate proxy) → PermGen leak
```

### Java 8+: Metaspace (Native Memory)

```
Metaspace (off-heap, native memory):
  - Class metadata
  - Runtime Constant Pool (per class)
  - Method bytecode

Benefits:
  - Grows automatically (no fixed max by default!)
  - Less OOM PermGen (nhưng vẫn có thể OOM native memory)
  - Better GC (CMS no longer needs to collect Metaspace)

Configure:
  -XX:MetaspaceSize=256m       # initial size (also triggers first GC)
  -XX:MaxMetaspaceSize=512m    # max (default = unlimited → danger!)
  # Luôn set MaxMetaspaceSize để tránh native memory exhaustion!
```

```java
// Metaspace OOM triggers:
// 1. Too many dynamically generated classes (Groovy scripts, CGLIB proxies)
// 2. ClassLoader leaks (web app reload without unloading old classes)
// 3. Reflection-generated accessor classes (older Jackson/Spring versions)

// Diagnose:
jcmd <pid> VM.metaspace          // Metaspace usage summary
jcmd <pid> VM.classloader_stats  // classes per ClassLoader
```

### Runtime Constant Pool

```java
class Example {
    static final int MAX = 100;          // compile-time constant → inlined
    static final String NAME = "hello";  // string literal → String pool ref
    int value = MAX;
}

// Constant Pool trong class file chứa:
// - Literal values: 100, "hello"
// - Symbolic references: "com/example/UserService.findById:(J)Lcom/example/User;"
// - Runtime: symbolic → direct reference (resolution phase)
```

---

## How – Heap

### Object Allocation

```java
// Object header trong Heap (64-bit JVM):
// Mark Word: 8 bytes → hash code, GC age, lock state, GC flags
// Class Pointer: 4 bytes (compressed) hoặc 8 bytes → points to Metaspace
// Instance Data: field values
// Padding: align to 8-byte boundary

// -XX:+UseCompressedOops (default on 64-bit):
//   Compress 64-bit reference → 32-bit (tiết kiệm 50% reference size)
//   Works for heap <= 32GB (64GB with -XX:ObjectAlignmentInBytes=16)

// Object overhead: minimum 16 bytes (8 mark + 4 class + 4 padding)
// int field: 4 bytes | long field: 8 bytes | reference: 4 bytes (compressed)

// Arrays: header (mark + class + length=4 bytes) + elements
// int[10]: 16 (header) + 40 (10×4) = 56 bytes
```

### String Pool (String Interning)

```java
// String literal → automatically interned
String s1 = "hello";        // from String pool (Heap, Java 7+)
String s2 = "hello";        // same reference from pool
System.out.println(s1 == s2); // true!

// new String() → KHÔNG từ pool
String s3 = new String("hello"); // new object in Heap
System.out.println(s1 == s3);    // false!

// Manual interning
String s4 = s3.intern();    // returns reference from pool (= s1)
System.out.println(s1 == s4); // true!

// String.intern() performance:
// - Tăng object reuse (tiết kiệm memory)
// - Pool size is GC managed (trong Heap từ Java 7)
// - intern() overhead: hash lookup (O(1) nhưng có overhead)
// - Khi nào dùng: large number of repeated strings (ZIP codes, country codes)

// Java 8u20+: String Deduplication (G1 only, -XX:+UseStringDeduplication)
// GC tự động tìm String objects có cùng content → share char[] array
// Transparent, không cần intern()
```

---

## How – Java Stack (Thread Stack)

Mỗi thread có **Stack riêng** chứa các **Stack Frames**.

### Stack Frame

```
Stack Frame (tạo mỗi khi method được gọi):
┌─────────────────────────────────────┐
│  Local Variable Array               │
│  [0] this (instance method)         │
│  [1] param1                         │
│  [2] param2                         │
│  [3] localVar1                      │
│  [4] localVar2                      │
├─────────────────────────────────────┤
│  Operand Stack                      │
│  (working area, JVM computation)    │
│  push/pop values during execution   │
├─────────────────────────────────────┤
│  Constant Pool Reference            │
│  → pointer back to class CP         │
├─────────────────────────────────────┤
│  Return Address                     │
│  → where to return after method     │
└─────────────────────────────────────┘
```

```java
// Demo: tracing một method call
public class StackDemo {
    public int add(int a, int b) {
        int result = a + b;  // thêm stack frame
        return result;       // pop stack frame
    }

    public void caller() {
        int x = 10;
        int y = 20;
        int sum = add(x, y); // push frame, execute, pop frame
        System.out.println(sum);
    }
}

// Local Variable Array cho add(int a, int b):
// [0] = this (reference to StackDemo instance)
// [1] = a (value 10)
// [2] = b (value 20)
// [3] = result (computed)

// Operand Stack tracing:
// iload_1          → stack: [10]
// iload_2          → stack: [10, 20]
// iadd             → pop 2, push sum: [30]
// istore_3         → pop 30, store to local[3]: []
// iload_3          → stack: [30]
// ireturn          → return 30, pop frame
```

### Stack Size & StackOverflowError

```java
// StackOverflowError: quá nhiều stack frames (deep recursion)
public long factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1); // deep recursion → SOE
}

// Fix 1: Iterative
public long factorial(int n) {
    long result = 1;
    for (int i = 2; i <= n; i++) result *= i;
    return result;
}

// Fix 2: Tail recursion (Scala/Kotlin tối ưu, Java chưa)
// Fix 3: Increase stack size -Xss4m (default 512k-1m depending on platform)
-Xss2m     # 2MB per thread stack
# Warning: tăng Xss × số threads = tăng memory đáng kể
# 1000 threads × 2MB = 2GB!

// Stack frame size phụ thuộc vào:
// - Số local variables
// - Depth của operand stack
// - Không liên quan tới object size (objects trong Heap)
```

---

## How – PC Register (Program Counter)

```
Mỗi thread có PC Register riêng
Value: địa chỉ của bytecode instruction đang thực thi
       (undefined nếu thread đang thực thi native method)

Dùng bởi: JVM instruction fetch cycle
           Thread context switch (save/restore PC)

Thread dump có thể thấy: "at com.example.Foo.bar(Foo.java:42)"
→ PC Register → 42 = line number trong source (debug info)
```

---

## How – Bytecode (Intermediate Language)

### Class File Structure

```
Class File (Magic: 0xCAFEBABE):
  ├── Minor/Major Version
  │     Java 8 → major 52, Java 11 → 55, Java 17 → 61, Java 21 → 65
  ├── Constant Pool
  │     # Strings, class names, field/method descriptors, literals
  ├── Access Flags (public/final/abstract/interface/enum/...)
  ├── This Class (index vào CP → class name)
  ├── Super Class (index vào CP)
  ├── Interfaces[]
  ├── Fields[]
  │     # name_index, descriptor_index, access_flags, attributes
  ├── Methods[]
  │     # name, descriptor, access_flags, Code attribute
  │     Code attribute: max_stack, max_locals, bytecode[], exception_table
  └── Attributes (SourceFile, InnerClasses, BootstrapMethods...)
```

### Bytecode Instructions

```java
// Xem bytecode: javap -c -verbose ClassName

public class BytecodeExample {
    public static int add(int a, int b) {
        return a + b;
    }
}

/* javap output:
  public static int add(int, int);
    descriptor: (II)I
    Code:
      stack=2, locals=2, args_size=2
         0: iload_0        // push local[0] (param a) onto operand stack
         1: iload_1        // push local[1] (param b) onto operand stack
         2: iadd           // pop 2, push sum
         3: ireturn        // return top of stack
*/

// Type prefix:
// i = int, l = long, f = float, d = double, a = reference (object/array)
// b = byte, c = char, s = short

// Key instructions:
// iload_N/istore_N  → load/store int local variable
// ldc               → load constant from constant pool
// invokevirtual     → virtual method call (polymorphic, vtable)
// invokeinterface   → interface method call
// invokestatic      → static method call (no vtable)
// invokespecial     → constructor, super, private (no vtable)
// invokedynamic     → lambda, method handles (Java 7+)
// new               → allocate object on heap
// checkcast         → runtime type check (ClassCastException)
// instanceof        → type check (returns boolean)
// getfield/putfield → instance field access
// getstatic/putstatic → static field access
// arraylength       → array.length
// athrow            → throw exception
// monitorenter/monitorexit → synchronized block entry/exit
```

### invokedynamic (Lambda Implementation)

```java
// Lambda compilation
Runnable r = () -> System.out.println("hello");
// Compiled to invokedynamic instruction
// First call: LambdaMetafactory creates anonymous class at runtime
// Subsequent calls: reuse generated class

// invokedynamic advantages over anonymous inner class:
// - No class file per lambda at compile time
// - JVM can optimize (e.g., merge identical lambdas)
// - Method handle based (more flexible)

// javap shows:
// invokedynamic #5, 0              // InvokeDynamic #0:run:()Ljava/lang/Runnable;
// BootstrapMethods:
//   0: invokestatic LambdaMetafactory.metafactory:...
```

---

## How – Reading Stack Traces

```java
// Đọc stack trace từ Exception
Exception in thread "main" java.lang.NullPointerException: Cannot invoke "String.length()"
    at com.example.UserService.processName(UserService.java:45)   ← most recent
    at com.example.UserService.processUser(UserService.java:32)
    at com.example.OrderService.createOrder(OrderService.java:78)
    at com.example.OrderController.post(OrderController.java:23)
    at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)  ← JNI
    at ...
    at java.lang.Thread.run(Thread.java:748)                         ← thread entry

// Đọc từ dưới lên để hiểu call chain:
// Thread.run → OrderController.post → OrderService.createOrder
// → UserService.processUser → UserService.processName (line 45) → NPE

// Helpful JVM flags:
-XX:-OmitStackTraceInFastThrow  // JVM sometimes omits stack traces for frequent exceptions
// Nếu thấy NPE không có stack trace → thêm flag này
```

```java
// Thread dump (khi app hang)
// jstack <pid> hoặc kill -3 <pid> hoặc jcmd <pid> Thread.print

"pool-1-thread-1" #12 prio=5 os_prio=0 cpu=1.23ms elapsed=42.1s tid=0x... nid=0x...
   java.lang.Thread.State: BLOCKED (on object monitor)
    at com.example.A.doWork(A.java:25)
    - waiting to lock <0x000000076ac3d8a0> (a java.lang.Object)  ← WAITING FOR LOCK
    at ...

"pool-1-thread-2" #13 prio=5 os_prio=0 cpu=0.56ms elapsed=42.1s tid=0x... nid=0x...
   java.lang.Thread.State: BLOCKED (on object monitor)
    at com.example.B.doWork(B.java:30)
    - waiting to lock <0x000000076ab3e760> (a java.lang.Object)
    at ...
    - locked <0x000000076ac3d8a0> (a java.lang.Object)           ← HOLDS LOCK thread-1 wants!
// → DEADLOCK! Thread 1 holds lock B, waiting for lock A
//             Thread 2 holds lock A, waiting for lock B
```

---

## How – Native Method Stack & JNI

```java
// JNI (Java Native Interface): gọi C/C++ từ Java
public class NativeExample {
    static { System.loadLibrary("native-lib"); }

    public native String processData(byte[] data); // implemented in C
}

// C implementation (native-lib.c):
JNIEXPORT jstring JNICALL Java_NativeExample_processData(JNIEnv* env, jobject obj, jbyteArray data) {
    // C code runs on Native Method Stack
    // GC roots: jobject, jbyteArray references in JNI are strong references
    // Must call env->DeleteLocalRef() to release
}

// JNI pitfalls:
// 1. Memory management: Java GC không quản lý native objects
// 2. JNI GlobalRef: explicit DeleteGlobalRef() nếu không → memory leak
// 3. Critical region (GetPrimitiveArrayCritical): pin GC, avoid long operations
// 4. Exception handling: check exception after every JNI call
```

---

## Components – Runtime Areas Summary

| Area | Scope | Holds | Size Config |
|------|-------|-------|-------------|
| Metaspace | Per JVM | Class metadata, bytecode, CP | `-XX:MaxMetaspaceSize` |
| Heap | Per JVM | Objects, arrays, String pool | `-Xms`, `-Xmx` |
| Java Stack | Per Thread | Stack frames, local vars | `-Xss` |
| PC Register | Per Thread | Current instruction address | Fixed (tiny) |
| Native Method Stack | Per Thread | JNI C-level stack | OS-managed |
| Code Cache | Per JVM | JIT compiled native code | `-XX:ReservedCodeCacheSize` |

---

## Why – Hiểu Runtime Areas để làm gì?

```
OOM Error interpretation:
  java.lang.OutOfMemoryError: Java heap space           → -Xmx hoặc memory leak
  java.lang.OutOfMemoryError: Metaspace                  → -XX:MaxMetaspaceSize hoặc CL leak
  java.lang.OutOfMemoryError: unable to create native thread → -Xss, ulimit, thread leak
  java.lang.OutOfMemoryError: GC overhead limit exceeded  → GC tốn quá 98% time
  java.lang.StackOverflowError                            → deep recursion, tăng -Xss

Tuning decisions:
  Heap OOM → tăng -Xmx hoặc fix memory leak
  High GC frequency → heap quá nhỏ, hoặc object allocation quá nhiều
  Thread OOM → giảm -Xss hoặc giảm số threads
  Metaspace OOM → fix ClassLoader leak, set MaxMetaspaceSize
  Code Cache full → tăng ReservedCodeCacheSize
```

---

## Real-world Usage (Production)

### 1. JVM Memory Sizing cho Container (Kubernetes)

```bash
# Container-aware JVM (Java 8u191+, Java 11+)
-XX:+UseContainerSupport              # use container memory limits
-XX:MaxRAMPercentage=75.0            # 75% của container memory
-XX:InitialRAMPercentage=50.0        # initial 50%
# Tự tính Xmx dựa trên container limit:
# 4GB container → Xmx ≈ 3GB (75%)

# Explicit sizing cho container:
# 512MB container:
-Xms128m -Xmx384m -XX:MaxMetaspaceSize=128m -Xss512k
# Tổng: Heap(384) + Metaspace(128) + Stack(0.5k × threads) + CodeCache + JVM overhead ≈ 512MB
```

### 2. Diagnose Memory Leak với jmap + MAT

```bash
# Heap histogram (nhanh, không cần dump)
jmap -histo:live <pid> | head -30
# num     #instances         #bytes  class name
#   1:       1234567      123456789  [B (byte array)
#   2:        234567       56789012  java.lang.String
# → Nhiều byte[] → kiểm tra image/pdf in memory? Cache không expire?

# Full heap dump (cần disk space = heap size)
jmap -dump:live,format=b,file=/tmp/heap.hprof <pid>

# Mở trong Eclipse MAT:
# - Dominator tree: object lớn nhất và tại sao alive
# - Leak suspects: MAT tự phân tích
# - OQL (Object Query Language): SELECT * FROM java.util.ArrayList WHERE size > 10000
```

### 3. Bytecode Instrumentation (APM Agents)

```java
// APM agents (Datadog, New Relic, Dynatrace) dùng Java Agent + Bytecode Instrumentation
// Instrument tại load time: thêm timing/tracing code vào method bytecode

// -javaagent:agent.jar → agent.premain() gọi trước main()
public class Agent {
    public static void premain(String args, Instrumentation inst) {
        inst.addTransformer((loader, className, classBeingRedefined, protectionDomain, classfileBuffer) -> {
            // Modify bytecode using ASM/Javassist/Byte Buddy
            if (className.startsWith("com/example/service/")) {
                return addTimingInstrumentation(classfileBuffer);
            }
            return classfileBuffer; // unchanged
        });
    }
}

// Byte Buddy (easier API than raw ASM)
new AgentBuilder.Default()
    .type(nameStartsWith("com.example.service"))
    .transform((builder, type, loader, module, domain) ->
        builder.method(isPublic())
               .intercept(MethodDelegation.to(TimingInterceptor.class)))
    .installOn(instrumentation);
```

---

## Ghi chú – JVM Deep Dive hoàn thành

> Đã hoàn thành JVM Internals:
> - **classloader.md**: Parent delegation, class loading phases, custom CL, isolation
> - **jit_compiler.md**: Tiered compilation, inlining, escape analysis, devirtualization, GraalVM
> - **gc.md**: Heap layout (Young/Old/Eden/Survivor), GC algorithms, G1/ZGC, reference types, memory leaks
> - **java_memory_model.md**: happens-before, volatile, synchronized, safe publication, DCL, VarHandle
> - **runtime_data_areas.md**: Metaspace, Heap, Stack Frame, bytecode, invokedynamic, stack traces
>
> Tiếp theo (nếu muốn tiếp tục JVM): **GC Tuning in Practice** (detailed G1/ZGC tuning case studies)
> Hoặc: **Testing** (JUnit 5, Mockito, Testcontainers, @SpringBootTest layers)
