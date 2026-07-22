# Reflection & Annotations

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Reflection là gì?

**Reflection** *(khả năng chương trình tự "soi gương" và thao tác cấu trúc của chính nó lúc chạy)* là khả năng của Java cho phép chương trình **kiểm tra và thao tác cấu trúc của chính nó** tại **runtime** *(lúc chương trình đang chạy)*: đọc **class metadata** *(thông tin mô tả về class — tên, field, method, annotation...)*, gọi **method** *(phương thức)*, truy cập **field** *(thuộc tính/biến thành viên)* — mà không cần biết **type** *(kiểu dữ liệu)* tại **compile time** *(lúc biên dịch, trước khi chạy)*.

> 💡 **Giải thích dễ hiểu:**
> Bình thường khi viết code, bạn phải biết trước class tên gì, có method nào, gọi kiểu gì — giống như bạn phải học thuộc menu nhà hàng trước khi gọi món. **Reflection** giống như bạn đưa cho chương trình một tấm gương và bảo: "hãy tự nhìn mình đi, xem mình có những gì rồi tự quyết định làm gì". Chương trình có thể tự khám phá: "à, class này tên là UserService, có method findById nhận vào một Long" — rồi tự gọi method đó, dù lúc viết code ta chưa hề biết class ấy tồn tại.
>
> Ví von khác: như một **thợ khóa vạn năng**. Thợ mộc bình thường chỉ mở được cửa mình đã lắp (biết trước). Thợ khóa vạn năng (reflection) đứng trước bất kỳ cánh cửa lạ nào cũng dò được cấu tạo ổ khóa rồi mở — không cần biết trước đó là cửa gì.

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

**`java.lang.Class<T>`** là **entry point** *(điểm khởi đầu — cửa vào)* của mọi reflection operation. Với mỗi class bạn nạp vào JVM, JVM giữ đúng **một** object `Class` mô tả toàn bộ thông tin về class đó (tên, field, method, constructor, annotation...).

> 💡 **Giải thích dễ hiểu — Class object là "tấm bản thiết kế":**
> Đừng nhầm object kiểu `Class` với object bình thường. Nếu `new Person()` là một **ngôi nhà** đã xây, thì object `Class` (`Person.class`) là **bản thiết kế** của ngôi nhà đó — nó không phải nhà, mà là tờ giấy mô tả nhà có mấy phòng, mỗi phòng tên gì, kích thước ra sao. Từ tấm bản thiết kế này, reflection đọc ra mọi chi tiết, thậm chí "xây" ra nhà mới (`newInstance()`). Cả triệu ngôi nhà `Person` cùng dùng chung đúng một bản thiết kế — nên JVM chỉ giữ một object `Class` duy nhất cho mỗi class.
>
> Đây cũng là lý do gọi là **metadata** *(dữ liệu mô tả dữ liệu)*: `Class` không chứa dữ liệu thật (tên "Alice", tuổi 25), mà chứa dữ liệu về cấu trúc ("có field tên `name` kiểu String").

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

> 💡 **Giải thích dễ hiểu — `setAccessible(true)` là "chìa khóa vạn năng":**
> Bình thường một field khai báo `private` bị "khóa" — code bên ngoài không đọc/ghi được, đó là nguyên tắc **encapsulation** *(đóng gói — che giấu chi tiết nội bộ)*. Dòng `field.setAccessible(true)` giống như bảo bảo vệ: "cho tôi mượn chìa khóa vạn năng, mở hết mọi cửa phòng riêng". Sau lệnh đó, reflection sờ được cả field `private`, `protected` — bất chấp mọi rào chắn của trình biên dịch.
>
> Đây là con dao hai lưỡi: framework (Spring, Jackson, Hibernate) cần nó để tự động gán giá trị vào field private của object bạn; nhưng nó cũng **phá vỡ đóng gói** — nếu lạm dụng trong code nghiệp vụ thì mất hết ý nghĩa của `private`.

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

> 💡 **Giải thích dễ hiểu — `getDeclaredMethod` + `invoke`: gọi tên rồi bấm nút:**
> Gọi method qua reflection gồm 2 bước. Bước 1, `getMethod("add", int.class, int.class)` — bạn **tra danh bạ** tìm đúng method tên `add` nhận vào 2 số `int`. Phải nêu cả tên lẫn kiểu tham số vì có thể có nhiều method trùng tên khác tham số (**overload** — nạp chồng). Kết quả là một object `Method`, giống như bạn có được **cây điều khiển từ xa** trỏ đúng vào method đó.
> Bước 2, `method.invoke(calc, 3, 4)` — bạn **bấm nút** để chạy method, truyền vào object đích (`calc`) và các đối số. Java sẽ thực thi `calc.add(3, 4)` giúp bạn.
>
> Ví von: `getMethod` như tra số điện thoại của một người trong danh bạ; `invoke` như bấm gọi. Với **static method** *(method của class, không thuộc object nào)*, không cần object đích nên truyền `null` vào chỗ đó — như gọi tổng đài chung, không gọi riêng ai.
>
> Lưu ý cái bẫy: nếu method bên trong ném lỗi, `invoke` không ném thẳng lỗi đó mà bọc lại trong `InvocationTargetException` *(ngoại lệ "lỗi phát sinh từ method được gọi")*. Muốn thấy lỗi thật phải bóc lớp vỏ ra bằng `e.getCause()` — giống bưu kiện lỗi được gói trong một lớp giấy báo "hàng bên trong có vấn đề".

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

**Type erasure** *(xóa kiểu — trình biên dịch bỏ thông tin generic sau khi biên dịch)* xóa generic info tại runtime, nhưng có thể recover *(khôi phục)* từ **bytecode** *(mã trung gian JVM đọc)*:

> 💡 **Giải thích dễ hiểu — type erasure:**
> Khi bạn viết `List<String>`, phần `<String>` chỉ tồn tại để trình biên dịch **kiểm tra giúp bạn** lúc viết code. Biên dịch xong, Java "xóa dấu vết" — trong bytecode chỉ còn `List` trơn, không còn biết là list của String hay Integer. Giống như bạn dán nhãn "hộp đựng táo" lên thùng carton lúc đóng gói cho khỏi nhầm, nhưng khi giao hàng người ta bóc nhãn đi, chỉ còn cái thùng. Đó là lý do tại runtime thường không biết generic là gì — trừ vài chỗ đặc biệt (như superclass, field) trình biên dịch có lưu lại "biên lai" trong bytecode để reflection dò ngược.

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

**Annotation** *(chú thích — nhãn metadata gắn kèm vào code)* là metadata gắn vào class/method/field, được đọc tại compile time hoặc runtime.

> 💡 **Giải thích dễ hiểu — annotation là "tờ giấy nhắn dán lên code":**
> Annotation như những **mảnh giấy nhớ (sticky note)** bạn dán lên code: `@Override`, `@Deprecated`, `@Entity`... Bản thân mảnh giấy không làm gì cả — nó chỉ **ghi chú** để một ai đó (trình biên dịch, framework, hay chính bạn qua reflection) đọc rồi hành xử theo. Ví dụ dán `@Test` lên một method là nhắn với JUnit: "đây là một test, hãy chạy nó". Dán `@Column(name="email")` lên field là nhắn với Hibernate: "field này ánh xạ tới cột `email` trong DB".
>
> Điểm mấu chốt: annotation **không tự thực thi**. Phải có "người đọc giấy nhắn" — thường là code dùng reflection quét qua và xử lý. Không có ai đọc thì annotation vô nghĩa như tờ giấy dán mà không ai ngó tới.

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

> 💡 **Giải thích dễ hiểu — `@Retention`: giấy nhắn "sống" được bao lâu?**
> **Retention policy** *(chính sách lưu giữ — quyết định annotation tồn tại tới giai đoạn nào)* trả lời câu hỏi: mảnh giấy nhắn này tồn tại tới đâu trong vòng đời của code? Có 3 mức, ví như 3 loại mực viết:
> - **SOURCE** *(chỉ có trong mã nguồn)*: viết bằng **bút chì** — trình biên dịch đọc xong là **tẩy sạch**, không vào file `.class`. Dùng cho những ghi chú chỉ có ý nghĩa lúc biên dịch, như `@Override` (nhắc trình biên dịch kiểm tra), `@SuppressWarnings`.
> - **CLASS** *(có trong file .class nhưng không nạp vào JVM)*: viết bằng **bút mực thường** — còn lưu trên file `.class` nhưng khi JVM nạp class vào bộ nhớ thì bỏ qua, không đọc được lúc chạy. Dùng cho công cụ xử lý bytecode.
> - **RUNTIME** *(sống tới lúc chạy)*: viết bằng **bút không phai** — theo class vào tận JVM, và reflection **đọc được lúc chạy**. Đây là mức Spring, JPA, Jackson dùng, vì các framework này quét annotation ngay khi chương trình đang chạy.
>
> Ghi nhớ: annotation muốn được reflection đọc lúc chạy thì **bắt buộc** phải khai `@Retention(RetentionPolicy.RUNTIME)`. Quên khai (mặc định là CLASS) là lỗi kinh điển khiến "annotation của tôi không thấy tác dụng gì".

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

> 💡 **Giải thích dễ hiểu — Annotation Processing: "robot sinh code" lúc biên dịch:**
> **Annotation processing** *(xử lý annotation lúc biên dịch — quét annotation rồi tự sinh ra code mới)* khác hẳn việc đọc annotation bằng reflection. Reflection đọc annotation **lúc chạy**; còn annotation processing chạy **ngay trong lúc biên dịch**, trước khi có chương trình để chạy.
> Ví von: như một **dây chuyền sản xuất có robot phụ**. Bạn đưa vào bản vẽ (class dán annotation `@Data`), robot (annotation processor) đọc bản vẽ rồi **tự chế thêm linh kiện** (sinh ra file `.java` mới chứa getter/setter/equals...). Tất cả xảy ra trước khi sản phẩm xuất xưởng. Lombok, MapStruct, Dagger hoạt động kiểu này — nên chúng **không tốn chi phí runtime**, vì code đã được sinh sẵn lúc biên dịch, chạy nhanh như code viết tay.

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

`java.lang.reflect.Proxy` tạo **proxy** *(đối tượng ủy nhiệm — đứng thay mặt object thật, chặn mọi lời gọi để xử lý thêm)* implementation của interface tại runtime:

> 💡 **Giải thích dễ hiểu — Dynamic Proxy là "người trợ lý đứng cửa":**
> Hình dung bạn muốn gọi giám đốc (object thật), nhưng mọi cuộc gọi đều phải qua **thư ký** trước. Thư ký ghi sổ ("có cuộc gọi lúc 9h"), rồi mới chuyển máy cho giám đốc, xong lại ghi ("đã xong sau 45µs"). **Dynamic proxy** chính là người thư ký sinh ra tự động lúc chạy: nó **implement cùng interface** với object thật nên bên ngoài tưởng đang gọi thẳng, nhưng thực chất mọi lời gọi đều bị `InvocationHandler` *(bộ xử lý — nơi bạn nhét logic chặn giữa)* chặn lại để thêm việc (log, đo thời gian, mở transaction...). Đây là nền tảng của Spring AOP: `@Transactional` hoạt động được là nhờ proxy tự động mở/đóng transaction quanh method của bạn.

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

`MethodHandle` là typed reference tới method/field — **nhanh hơn reflection** (**JIT** *(Just-In-Time compiler — trình biên dịch nóng, dịch bytecode thành mã máy lúc chạy)* có thể **inline** *(nhúng thẳng lời gọi vào nơi gọi, bỏ chi phí gọi hàm)*):

> 💡 **Giải thích dễ hiểu — vì sao reflection chậm, và MethodHandle nhanh hơn:**
> Gọi method trực tiếp (`calc.add(3,4)`) giống như bạn tự tay bật công tắc đèn — tức thì. Gọi qua reflection giống như mỗi lần muốn bật đèn lại phải: tra danh bạ tìm số công tắc, kiểm tra bạn có quyền chạm vào không, rồi mới nhờ người khác bật hộ. Những bước "tra cứu + kiểm tra quyền + gọi gián tiếp" lặp lại mỗi lần gọi chính là **overhead** *(chi phí phụ trội)* khiến reflection chậm hơn.
> **MethodHandle** giải quyết bằng cách làm phần tra cứu/kiểm tra **một lần duy nhất** lúc tạo handle, sau đó giữ lại "đường dây nóng" trỏ thẳng method. Sau vài lần chạy (**warmup** — khởi động nóng), JIT nhìn ra đây thực chất là lời gọi cố định và **inline** nó — nhanh gần như gọi trực tiếp. Đó là lý do code hiệu năng cao nên **cache** *(lưu lại tái dùng)* MethodHandle thay vì tra reflection lặp đi lặp lại.
>
> Thực tế: đừng lo reflection "chậm" trong đa số trường hợp — nó chỉ đáng bận tâm ở **hot path** *(đoạn code chạy cực nhiều lần, điểm nóng hiệu năng)*. Với vài lần gọi lúc khởi động (như Spring quét bean), chi phí này không đáng kể.

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
