# JByteVM

Крайне компактная встраиваемая JVM для модов. Только интерпретатор, без JIT
и `invokedynamic`. Class-файлы Java 25 (`major=69`, `minor=0`).
Компактная библиотека классов, мониторы, диагностика, рефлексия,
преобразование лямбд и CONSTANT_Dynamic при подготовке и три профиля x86.

**Сейчас работаем только над Windows x86 (32 бита).** Это сборка по умолчанию.
Типизированный мост x64 не реализован; регистрация на нём возвращает unsupported.
Параметр старой x64-сборки сохранён, но текущий native-пример требует x86.
Разрядность JDK, компилирующего классы, не определяет разрядность VM.

По решению пользователя **FFM удалён**: Java foreign API, арены, MethodHandle
для FFM, старые FFM-переходники, банк upcalls и генераторы больше не входят в проект.
Прямые Java MethodHandle используются для Java-вызовов и bootstrap в подготовленном байткоде.
Хозяин регистрирует C-обработчики Java `native`-методов и вызывает Java через
компактный C API. Готовые JNI-библиотеки с ним несовместимы.

Название выбрано пользователем 10 ноября 2026 года; проект создан из беседы «Логика» в Tethium.

## Принятый профиль

| Часть | Целевой состав |
|---|---|
| Основа | Object, минимальный Class, массивы, интерфейсы, исключения |
| Строки | String, StringBuilder, CharSequence, строковый `+` без indy |
| Значения | Обёртки примитивов, базовый Math |
| Коллекции | List/ArrayList, Map/HashMap, Set/HashSet, Iterable/Iterator |
| Служебное | System.arraycopy, часы, AutoCloseable, вывод через хозяина |
| Native | C-callbacks, вызовы Java, поля, массивы, ссылки и исключения |
| Рефлексия | В full: Class, поиск/перечисление членов, Method/Field/Constructor, Array, управление доступом и runtime-аннотации |

Группы этого списка представлены в профиле `full`; это выбранный набор API,
а не полная Java SE.
Лямбды преобразуются в обычные классы при подготовке мода
с `--lower-lambdas`: проверены захваты, private/nestmate-доступ, ссылки на методы,
конструкторы и `super`, generics и bridge-методы. VM по-прежнему не исполняет indy.

CONSTANT_Dynamic преобразуется с `--lower-condy` в обычный байткод с ленивым
кэшированием значения/ошибки. Bootstrap исполняется при первом обращении в VM,
а не на машине сборки. Обработчик runtime condy удалён; неподготовленные записи
отклоняются загрузчиком. Рефлексия вызывает интерпретатор непосредственно,
без MethodHandle. Общие преобразования значений вынесены в `src/values.c`.
Генерируемые при подготовке synthetic-методы и классы видны через рефлексию.

**Байткод считается доверенным и корректным.** Verifier исключён из профиля:
нет проверки инструкций, переходов, типов операндов, инициализации locals,
max_stack/max_locals и связей constant pool. Оставлены ограниченное чтение
контейнера и проверка версии/поддержанных тегов. Исполнение повреждённого
байткода имеет неопределённое поведение. Проверки null, деления на ноль,
границ/размеров массивов, casts и array stores сохранены, как и проверки
ссылок на границе C API и ограничения ресурсов VM.

Цель: несжатый Windows runtime меньше **256 КиБ**, с сокращённой библиотекой —
попытаться уложиться в **32 КиБ**. Считаем DLL, классы библиотеки и обязательные
зависимости. SDK, компилятор, тесты, символы и уже существующее приложение-хозяин
не входят в runtime. Самостоятельный демонстрационный комплект учитывает также
EXE хозяина. RAM измеряется отдельно; КиБ = 1024 байта.

## Что работает

- Class-файлы Java 25 без preview. VM копирует буфер; дубликаты классов отклоняются.
- int/long с Java-переполнением, битовые операции и сдвиги; float/double,
  сравнения, остаток, числовые преобразования. Проверены NaN, бесконечности,
  signed zero, subnormal, насыщение при преобразовании в целое и округление
  long → float/double. Обе категории стека, locals/wide, ветвления и switch.
- Объекты, конструкторы, наследование, поля, все примитивные/ссылочные аргументы
  и результаты; invokestatic/invokespecial/invokevirtual/invokeinterface.
  Default/private-методы интерфейсов, наиболее специфичный default,
  abstract-переобъявления, diamond и Interface.super.
- Инициализация суперклассов и интерфейсов с default-методами перед подклассом;
  статический член инициализирует объявивший его класс. Циклы иерархий
  отклоняются при linking. Ошибка clinit запоминается.
- Массивы всех примитивов и ссылок, multianewarray, частично созданные
  многомерные массивы, ковариантность, checkcast и instanceof.
- Object: конструктор, equals/hashCode, getClass и toString с виртуальным hashCode.
  Минимальный Class, литералы классов/массивов/примитивов; метаданные Cloneable,
  Serializable, AutoCloseable, CharSequence, Comparable и Appendable.
- String: UTF-16, литералы и ConstantValue, интернирование, сравнение, поиск,
  подстроки и копирование char[]. StringBuilder и строковый `+` без indy,
  включая все примитивы, Object и пользовательские CharSequence.
- athrow, try/catch/finally, try-with-resources, cause и suppressed exceptions.
  Исключения — GC-объекты, работают пользовательские подклассы.
  ExceptionInInitializerError/NoClassDefFoundError при ошибках инициализации.
- Проверок доступа нет: private/protected/package и nestmates не проверяются,
  запись в final-поля не запрещена. Ошибки разрешения членов
  (NoSuchField/MethodError, IncompatibleClassChangeError) и виртуальный выбор метода
  с учётом пакетов сохранены.
- Разрешение ссылок как в ConstantPoolCache HotSpot: class constant, Fieldref и
  Methodref разрешаются один раз и кэшируются в записи пула; виртуальные и
  интерфейсные вызовы — с мономорфным кэшем (класс последнего получателя → метод).
  Встроенные native-методы вызываются без переключения FPU-окружения.
- Интерпретатор устроен как шаблонный интерпретатор HotSpot. На x86 горячие байткоды
  (170 из 202) исполняет ядро на ассемблере `src/interp_x86.asm`, сгенерированное
  `tools/gen_interp_x86.py`: своя диспетчеризация в конце каждого обработчика, вершина
  стека в `eax` (двухслотовая — ещё и в `xmm7`, со своей таблицей переходов), память
  стека всегда актуальна. Вызовы обычных байткод-методов, возвраты, `new`, поля,
  массивы с барьером записи, checkcast/instanceof, long/double — в ядре; кадры для
  вызовов ядро строит само, настоящими `call`/`ret`. Всё остальное и любые особые
  случаи (null, границы, неразрешённые ссылки, исключения, лимиты) ядро отдаёт C-циклу
  `jbv_run`, который сам по себе — полный интерпретатор. Аргументы вызова становятся
  locals вызванного метода на месте; `JbvLink` хранит разрешённые члены, полиморфный
  кэш на 4 класса получателя. Сверка с `java -Xint` на одном P-ядре: 0.4–1.35×.
  Профиль: `JBV_SAMPLE=файл jbytevm-bench ...`, затем `tools/profile_samples.py`.
- Реентерабельные monitorenter/monitorexit и synchronized-методы; владение,
  IllegalMonitorStateException и очистка при исключении/прерывании по бюджету.
  Object.notify/notifyAll проверяют владение. Потоков и Object.wait нет.
- В `full`: boxing/unboxing, базовый Math, коллекции и System; рефлексия и
  runtime-аннотации, прямые MethodHandle/MethodType.
  StackTraceElement с SourceFile/LineNumberTable, fill/set/get/printStackTrace.
- В x86 Java устанавливает nearest-even, 53-битную точность x87 и gradual
  underflow. Состояние x87/MXCSR вызывающей стороны восстанавливается, в том
  числе при native → Java → native → Java и изменении rounding/DAZ/FTZ в native.
- Синхронные native → Java → native → … на одном системном потоке.
  Общие лимиты инструкций/глубины/слотов; восстановление кадров после ошибок.
  «Инструкции» бюджета — входы в методы и обратные переходы (как safepoint-опросы
  HotSpot): любой цикл и рекурсия ограничены без счётчика на каждом байткоде.
- Неперемещающий mark-and-sweep GC с отдельными метками ссылок 0/1.
  Корни: locals и активные операнды всех приостановленных кадров, статические
  ссылки, pending exception и удержания хозяина. Обход объектов итеративный.
- Независимые VM и аллокатор хозяина. DLL **не импортирует другие DLL**;
  нет CRT startup или CRT DLL. Helpers 64-битной арифметики включены статически.
  Внутренние x86-функции — fastcall, публичный API и callbacks — явно cdecl.

Сигнатуры методов разбираются при создании метаданных; Java-вызовы передают
готовые GC-метки аргументов. Новый кадр очищает только метки неинициализированных
locals. Карты границ инструкций нет. По умолчанию выделяются 16384 int32-слота
и столько же байтов меток (80 КиБ RAM). Общий бюджет аллокаций VM по умолчанию —
10 МиБ, включая метаданные и таблицу дескрипторов; Java-куча использует остаток
этого бюджета. Long/double занимают два слота,
остальные значения — один. В куче `char[]` упакован по 2 байта на элемент
(раньше 4), включая буферы String/StringBuilder; byte/short/boolean пока
занимают по одному 32-битному слоту. Это не меняет формат значений C API.

## Object, Class и строки

Эта часть библиотеки встроена в DLL; дополнительных class-файлов для неё нет.
Метаданные создаются при первом обращении. Имена встроенных классов зарезервированы:
загрузка собственного java/lang/String, Class или Throwable отклоняется даже до
создания их метаданных. Это защищает внутреннюю раскладку объектов, не возвращая verifier.

Поддержанный набор:

| Класс | Методы и возможности |
|---|---|
| Object | `<init>`, equals, hashCode, getClass, toString, clone, notify/notifyAll |
| Class | getName, toString, isArray/isPrimitive/isInterface, getSuperclass/getComponentType, isAssignableFrom, isInstance, cast; в full также forName, getModifiers/getInterfaces, поиск и перечисление членов, runtime-аннотации |
| String | Конструкторы пустой/String/char[]/диапазон char[]; length/isEmpty/charAt, equals/hashCode/compareTo, substring/subSequence, toCharArray/getChars, concat/intern, startsWith/endsWith, indexOf/lastIndexOf для String и code point; valueOf для Object, char[] и всех примитивов |
| StringBuilder | Конструкторы пустой/capacity/String/CharSequence; append для String/Object/CharSequence/char[]/примитивов и диапазонов; length/capacity/ensureCapacity/setLength, charAt/setCharAt, toString/substring/subSequence, reverse, compareTo |
| CharSequence | length, charAt, subSequence, toString; String и StringBuilder реализуют интерфейс |
| Обёртки примитивов | В full: Number, Boolean/Byte/Short/Character/Integer/Long/Float/Double/Void, TYPE, boxing/unboxing, сравнение, hash/equals, числовой вывод/разбор, radix/unsigned/decode и битовые операции; в text — только прежние метаданные и TYPE |

Дополнительно String поддерживает trim, replace(char,char), replace(CharSequence,CharSequence),
contains и repeat. StringBuilder — insert для примитивов, строк, объектов,
char[]/CharSequence и диапазонов, delete/deleteCharAt/replace, appendCodePoint,
trimToSize; проверен в том числе insert из собственного изменяющегося буфера.

StringBuilder реализует Appendable и Comparable, String — Comparable. Это не весь
API перечисленных классов Java 25: нет regex, локалей, смены регистра Unicode,
потоков chars/codePoints, всех конструкторов с кодировками и полной reflection.
Метаданные реализуют интерфейсы из этого минимального профиля; API java.lang.constant
и отражения параметров типов не входят в него. Runtime-аннотации доступны в full.

Индексы строк считают UTF-16 code units. Поддержаны встроенный NUL, supplementary
characters и непарные суррогаты; поиск code point и reverse учитывают пары суррогатов.
String неизменяем: конструкторы из char[] копируют данные, toCharArray возвращает копию,
StringBuilder.toString создаёт независимый снимок. Как и остальные char[], backing
arrays используют два байта на code unit.

Литералы декодируются из modified UTF-8 class-файла и интернируются. Разрешённые
литералы и объекты Class — корни GC до уничтожения VM. Обычный String.intern имеет
слабое членство: строка без других корней может быть собрана. Литерал Foo.class не
запускает Foo.<clinit>; Class-объекты сохраняют идентичность между вызовами и сборками GC.

Десятичный вывод float/double вычисляется целочисленно по точным интервалам округления,
без CRT, FP-операций, локали и больших таблиц. Выбирается короткая запись по правилам
[Double.toString Java 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Double.html#toString(double)).
Алгоритм рассчитан на небольшой размер кода; отдельного обещания высокой скорости
массового форматирования чисел нет. Семантика строк сверяется с
[String Java 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/String.html),
операции над типами — с [Class Java 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Class.html).

## Рефлексия full

`Class.get[Declared]Methods/Fields/Constructors` и поиск по имени/параметрам;
Method.invoke, Constructor.newInstance, Field.get/set и примитивные варианты;
Modifier, AccessibleObject, Array.newInstance/get/set/getLength. Есть boxing,
расширение примитивов, виртуальный вызов, InvocationTargetException,
setAccessible/trySetAccessible/canAccess (доступ всегда разрешён). Статические
final-поля не изменяются; обычные instance final допускают запись после setAccessible.
Модификаторы, типы параметров/результата, объявленные исключения, bridge/varargs/default
и synthetic доступны через API. Отражённые объекты членов независимы: изменение
accessible у одного экземпляра не меняет другой.

RuntimeVisibleAnnotations и параметры методов/конструкторов, AnnotationDefault,
Inherited и Repeatable, значения примитивов/String/Class/enum/вложенных аннотаций
и массивов. Возвращаемые массивы копируются; equals/hashCode аннотаций сравнивают
значения. Реализации аннотаций используют небольшие VM-метаданные и обычные
объекты; машинный код не генерируется.

Это выбранный набор reflection, не весь пакет Java SE: нет generic Type/TypeVariable,
Parameter, type-use annotations, RecordComponent, Proxy и модульной модели доступа.
Единственное пространство классов принадлежит хозяину; getClassLoader возвращает
null, forName работает в этом пространстве. setAccessible разрешён для его классов.
Не заявляется точное поведение annotation evolution при отсутствующих типах,
несовпавших типах элементов и точный формат annotation.toString.

## Библиотека full

Java-часть — собственные исходники в [classpath](classpath), скомпилированные в
class-файлы 69 без indy. Они склеены в одну запись `jbv/classes.bin`
(индекс имя → смещение/размер и образы классов подряд), сжатую одним потоком DEFLATE
в обычном JAR (`build/<arch>/classpath.jar`), который встроен в DLL. VM распаковывает
запись целиком один раз при первом обращении (~177 КБ RAM внутри общего бюджета,
~1 мс); классы ссылаются на этот буфер без копирования. Из встраиваемой копии
удаляется только StackMapTable, не используемый VM без verifier; исходный вывод
javac на диске остаётся пригодным для стандартных Java-инструментов. Классы загружаются
лениво. Генераторы обёрток и функциональных интерфейсов находятся в tools;
таблица Unicode-цифр Character строится из используемого JDK 25.

| Группа | Реализовано |
|---|---|
| Числа | signed/unsigned parsing и вывод, сравнение, bitCount/rotate/reverse, raw IEEE bits; десятичный/hex разбор float/double с округлением |
| Math | abs/min/max, sqrt, floor/ceil/rint/round, signum/copySign, nextUp/Down/After, ulp/scalb/getExponent, toDegrees/toRadians, exact integer arithmetic, floor/ceil div/mod, random |
| StrictMath | sin/cos/tan, asin/acos/atan/atan2, exp/log/log10/log1p/expm1, pow, cbrt, hypot, sinh/cosh/tanh — порт fdlibm 5.3 (лицензия Sun), бит в бит как StrictMath HotSpot. `Math` делегирует сюда, поэтому результаты одинаковы на любой машине; HotSpot-интринсики Math могут отличаться на 1 ulp |
| Последовательности | Iterable/Iterator/ListIterator, Collection/SequencedCollection/List, AbstractCollection/List, ArrayList, подкреплённые исходным списком subList/reversed, sort/replaceAll/removeIf |
| Ассоциативные коллекции | Map/Set, AbstractMap/Set, HashMap/HashSet, null, коллизии, представления keySet/values/entrySet, изменяемые Entry и fail-fast итераторы |
| Фабрики | List/Set/Map.of, copyOf, Map.entry/ofEntries, SimpleEntry/SimpleImmutableEntry |
| Arrays | sort (примитивы — heapsort, объекты — стабильная сортировка, диапазоны, Comparator), binarySearch, fill, copyOf/copyOfRange, equals/hashCode/toString, deepEquals/deepHashCode/deepToString, setAll, asList |
| Collections | sort, binarySearch, reverse/shuffle/swap/rotate/fill/copy/replaceAll, min/max, frequency/disjoint/addAll, indexOfSubList, reverseOrder, empty*/singleton*/nCopies, unmodifiable Collection/List/Set/Map |
| Random | LCG java.util.Random с теми же последовательностями, что в JDK: nextInt/Long/Double/Float/Boolean/Gaussian/Bytes, nextInt(origin,bound); конструктор без seed нужны часы хозяина |
| Функции | Используемые коллекциями и лямбдами Function/BiFunction/Consumer/BiConsumer/Predicate/Supplier/Runnable, операторы и часть примитивных специализаций, Comparator (comparing*/thenComparing*/nullsFirst/Last), Objects |
| Generics в рефлексии | Type, ParameterizedType, TypeVariable, WildcardType, GenericArrayType; Class.getGenericSuperclass/Interfaces/getTypeParameters/getTypeName, Field.getGenericType, Method/Constructor getGeneric*Types, getTypeParameters, getParameters (имена — при компиляции с `-parameters`). Сигнатуры разбираются по запросу, без кэша |
| Исключения IO | java.io.IOException/UncheckedIOException, InterruptedException, TypeNotPresentException (без самого IO) |
| Коллекции | Queue/Deque, ArrayDeque, PriorityQueue (тот же порядок кучи, что в JDK), LinkedList, LinkedHashMap/Set (в т.ч. access order и removeEldestEntry), TreeMap/TreeSet (treap) с Navigable-представлениями, EnumMap/EnumSet |
| Строки | toLowerCase/toUpperCase (полный Unicode, SpecialCasing, final sigma), equalsIgnoreCase/compareToIgnoreCase/regionMatches как в JDK, split/matches/replaceAll, strip/isBlank/indent, join, format/formatted, кодовые точки, getBytes/new String с UTF-8/UTF-16/ISO-8859-1/US-ASCII (правила замены как в JDK); StringBuilder.indexOf. Методы реализованы на Java в `jbv.runtime.Strings` и подключены к встроенному String |
| Character | getType, isLetter/isLetterOrDigit/isUpperCase/isLowerCase/isAlphabetic/isSpaceChar/isJavaIdentifier*, toUpperCase/toLowerCase/toTitleCase, getNumericValue — по таблицам из JDK сборки (`tools/GenerateUnicode.java` проверяет все кодовые точки) |
| Регулярные выражения | java.util.regex Pattern/Matcher: классы символов, \d\w\s, якоря, группы (в т.ч. именованные), жадные/ленивые квантификаторы, флаги; split/replaceAll с JDK-семантикой |
| Форматирование | String.format/formatted: %s %d %x %o %c %b %e %f %g %h %n, ширина/точность/флаги/индексы, точное округление; всегда как Locale.ROOT |
| Прочее | Charset/StandardCharsets, минимальный Locale (не влияет на результат), Record, MatchException; Class.getSimpleName/getCanonicalName/getPackageName/getEnumConstants/isRecord/getDeclaringClass |
| System | arraycopy с overlap/type/bounds/частичной reference-копией, identityHashCode, gc, lineSeparator, часы и PrintStream через хозяина |

`jbv_set_host_services` задаёт часы и текстовый вывод, не добавляя DLL-импортов.
clock возвращает миллисекунды Unix или монотонные наносекунды; write получает
заимствованный удержанный String и признак stderr. Без соответствующего callback
вызов возвращает NATIVE_ERROR/UnsatisfiedLinkError. Конфигурация меняется только
на неактивной VM. System.in, файлового/сетевого IO и загрузки native DLL нет.

В `full` OOM по бюджету Java-кучи и переполнение глубины/слотов превращаются в
Java OutOfMemoryError/StackOverflowError. Для OOM допускается один небольшой
аварийный объект сверх бюджета; отказ аллокатора хозяина всё ещё может дать
только C-статус. Бюджет инструкций — прерывание хозяина, Java его не перехватывает.

### Раскладка объектов в памяти и GC

Заголовок объекта — одно слово: указатель на класс (4 байта на x86). Длина массива
лежит в слове перед заголовком, бит пометки GC и признак интернирования — в битовых
картах при таблице дескрипторов, закрепления хоста (`jbv_retain`) — в отдельной
таблице, глубина мониторов — числом записей в таблице мониторов. Ссылка —
`поколение << 24 | индекс`: до 16 млн живых объектов; поколение 1..127 ловит
устаревшие ссылки (после 127 переиспользований слота — нет). Дескриптор — 4 байта
плюс байт поколения. На x86: пустой `Object` — 4 байта кучи плюс ~5 байт дескриптора,
`Integer` — 8 + 5, `int[2]` — 16 + 5 (HotSpot с compressed oops: 16, 16, 24).

GC — serial (stop-the-world), поколенческий:

- **Молодое поколение** — одна область 1/16 кучи, до 256 КиБ (меньше 16 КиБ — не
  создаётся), выделение сдвигом указателя. Малая сборка копирует выживших в старое
  поколение; корни — обычные плюс запомненные барьером записи старые объекты и
  объекты, созданные в старом поколении со времени прошлой малой сборки.
- **Старое поколение** — куски 2–64 КиБ со списками свободных блоков по размерам
  (блоки до 512 байт), крупные объекты — у хоста.
- **Объекты перемещаются при любом выделении** — из байткода, из встроенных
  native-методов, из API хоста. Правило для C-кода VM: функции, которые могут
  выделить память в куче Java или вызвать Java-код, помечены `JBV_GC` в заголовках;
  прямой указатель на объект или его данные (`jbv_data`, `jbv_chars`, `JbvTextView`)
  после такого вызова недействителен — хранится ссылка, указатель берётся заново через
  `jbv_object`. Свежий объект, на который ссылается только локальная переменная C,
  закрепляется `jbv_retain` на время следующих выделений. Ссылки — дескрипторы,
  поэтому перемещение меняет только запись в таблице.
  Разметку проверяет `tools/checkgc/CheckGc.java`, исполняемый на самой JByteVM через
  `jbytevm-run` (запускается в `build.py --test`; `--fix` расставляет метки): строит граф
  вызовов функций и макросов VM, отправные точки — `jbv_new`, `jbv_execute`, сборщик и
  любые вызовы через указатели на функции (native-методы, колбэки хоста), — и требует
  `JBV_GC` у каждой функции, из которой они достижимы; лишние метки — предупреждение.
- **Барьер записи** — в `putfield`/`aastore` и в C-коде при каждой записи ссылки в
  объект, если между созданием объекта и записью было другое выделение
  (`jbv_barrier_checked`): объект мог успеть стать старым.
- `python tools/build.py --gc-stress [N] --test` собирает `build/x86-stress`, где малая
  сборка с перемещением идёт на каждом N-м выделении (по умолчанию 4), а полная с
  уплотнением — на каждом 32·N-м; освобождённая молодая область заполняется мусором.
  Так ловятся устаревшие указатели и пропущенные барьеры; весь набор тестов проходит
  при N = 3 и N = 4.

## Native API

Основной API: [include/jbytevm.h](include/jbytevm.h).
Доступ к Java из native: [include/jbytevm_native.h](include/jbytevm_native.h).
Реализация: [src/native.c](src/native.c), общий переходник [src/native_x86.asm](src/native_x86.asm).

Java объявляет обычный `static native int add(int a, int b);`.
После загрузки класса хозяин регистрирует обычные типизированные C-функции таблицей:

```c
static int32_t JBV_CALL add(JbvVM *vm, int32_t a, int32_t b) {
    (void)vm;
    return (int32_t)((uint32_t)a + (uint32_t)b);
}
static int64_t JBV_CALL add_long(JbvVM *vm, int64_t a, int64_t b) {
    (void)vm;
    return (int64_t)((uint64_t)a + (uint64_t)b);
}
static const JbvNativeEntry natives[] = {
    { "add", "(II)I", JBV_NATIVE_FN(add) },
    { "add", "(JJ)J", JBV_NATIVE_FN(add_long) }
};
/* After loading MyMod, before invoking Java: */
JbvStatus status = jbv_register_natives(vm, "MyMod", natives, 2, user);
```

В Java для этого примера нужны обе перегрузки `static native int add(int,int)`
и `static native long add(long,long)`. Ключ — класс, имя и полный JVM-дескриптор,
включая результат; имя C-функции произвольное. Двадцать функций — двадцать записей,
одна регистрация, без двадцати адаптеров. Адрес сохраняется в метаданных метода.
Таблица проверяется целиком до привязки: ошибка, дублирующийся ключ, отсутствие
метода или instance native оставляют прежние привязки неизменными.
Таблицу/строки можно освободить после регистрации; код функций и user должны
оставаться действительными до перепривязки или уничтожения VM.

ABI: `R JBV_CALL function(JbvVM *vm, Java-параметры...)`, только cdecl x86,
только static native. Первый аргумент служебный, в Java-дескриптор не входит;
скрытого receiver нет. Сигнатура C обязана соответствовать зарегистрированному
дескриптору — из адреса её проверить невозможно. JBV_NATIVE_FN только приводит
указатель к общему типу хранения. Пользовательские функции не распаковывают слоты.

| Java | C |
|---|---|
| boolean | uint8_t, значения 0/1 |
| byte / char / short | int8_t / uint16_t / int16_t |
| int / long | int32_t / int64_t |
| float / double | float / double |
| Объект / массив | JbvRef, null = 0 |
| void | void |

Обратный вызов статического Java-метода также не требует ручной упаковки:

```c
JbvMethodId method;
JbvValue result;
JbvStatus status = jbv_resolve_method(vm, "MyMod", "add", "(JJ)J", &method);
if (status == JBV_OK)
    status = jbv_invoke_args(vm, &method, &result, INT64_C(7), INT64_C(9));
if (status != JBV_OK) { jbv_native_fail(vm, status); return 0; }
return result.j;
```

ID можно сохранить для повторных вызовов. В C-varargs long передаётся как int64_t,
float продвигается до double, byte/char/short/boolean — до int; ссылки — JbvRef.
Результат читается через result.i/j/f/d/ref по объявленному Java-типу.
Это удобная функция вызова Java; регистрируемые native-функции сами не variadic.

Прежние JbvNative/JbvNativeSlots и jbv_call/jbv_call_slots сохранены для совместимости.
Их аргументы — int32-слоты, long/double занимают два, младшее слово первым;
FP передаётся битами IEEE. Новые регистрации рекомендуется делать через таблицу.

| Действие | API |
|---|---|
| Регистрация типизированных native | jbv_register_natives |
| Статический вызов по имени | jbv_call_slots, jbv_call |
| Найти метод один раз, вызывать по ID | jbv_resolve_method, jbv_invoke_args; jbv_invoke для слотов |
| Контекст и ошибки типизированной функции | jbv_native_context, jbv_native_fail |
| Создание объекта/массива | jbv_alloc_object, jbv_new_array |
| Поиск и чтение/запись поля | jbv_resolve_field, jbv_get_field, jbv_set_field |
| Тип/длина массива, копирование диапазона | jbv_array_info, jbv_array_read, jbv_array_write |
| Владение ссылкой | jbv_retain, jbv_release |
| Исключения | jbv_throw, jbv_exception, jbv_clear_exception |
| Создать String из UTF-8/UTF-16 | jbv_string_new_utf8, jbv_string_new_utf16 |
| Длина и копирование String | jbv_string_length, jbv_string_read_utf16, jbv_string_read_utf8 |

Строковые C API принимают явные длины, сохраняют встроенный ноль и не добавляют
терминатор. new возвращает удержанную ссылку; read ничего не удерживает. UTF-8 на этой
границе — обычный строгий Unicode UTF-8: неверная последовательность возвращает
BAD_ARGUMENT без изменения выходных параметров. UTF-16 допускает непарные суррогаты;
при чтении в UTF-8 они заменяются U+FFFD. Это явно заданный контракт C API, не JNI MUTF-8.

```c
JbvRef text;
JbvStatus status = jbv_string_new_utf8(vm, "hello", 5, &text);
if (status == JBV_OK) {
    uint32_t bytes;
    status = jbv_string_read_utf8(vm, text, NULL, 0, &bytes); /* Query size. */
    /* Allocate bytes in the host, then call read_utf8 with that capacity. */
    jbv_release(vm, text);
}
```

Чтение UTF-8 с недостаточным буфером возвращает BAD_ARGUMENT, не меняя буфер и bytes;
сначала размер можно запросить с out=NULL/capacity=0. UTF-16 читается диапазоном
start/count в code units. Для вызова Java созданную строку передают как обычный JbvRef.

JbvMethodId/JbvFieldId — два непрозрачных указателя каждый, без отдельных
аллокаций. Они принадлежат VM и действуют до её уничтожения; изменять,
подделывать или передавать в другую VM их нельзя. Native-код доверенный.
Обычные instance-методы вызываются виртуально, private и конструкторы — напрямую.
Конструктор разрешается только в объявившем его классе. jbv_alloc_object
инициализирует класс и выделяет нулевые поля; `<init>` вызывается отдельно
с receiver в первом слоте. Альтернатива — Java factory-метод.

При копировании массивов и полей одно значение занимает один uint64_t в C:
long/double используют все биты, остальные — младшие 32. Это формат копирования,
а не раскладка Java-стека. Запись сужает Z/B/C/S и проверяет типы ссылок;
пакетная запись проверяет весь диапазон и элементы до изменения. Прямых
указателей на Java-объекты API не выдаёт.

### Владение и повторный вход

- JbvRef — локальный для VM дескриптор с поколением, не адрес. Устаревшие
  дескрипторы отклоняются. Между VM ссылки не переносятся.
- Аргументы native-callback заимствованы и защищены от GC до возврата.
  Для сохранения в C-контексте после возврата нужен jbv_retain.
- Объекты/массивы, созданные через C API, ссылочные результаты вызовов и чтения
  полей удержаны для хозяина; каждый результат требует одного jbv_release.
  Чтение ссылочного массива удерживает каждое вхождение, включая повторения.
- Возвращая удержанную ссылку из callback, снимите своё удержание и сразу
  верните ссылку. Между снятием и возвратом не вызывайте GC или
  другие операции VM. Ссылки в Java-полях/массивах отслеживает GC.
- Ссылочные аргументы удерживаются до clinit и до завершения вызова.
  Запись статического поля удерживает значение во время инициализации владельца.
- jbv_collect допустим из callback: приостановленные кадры остаются корнями.
  Автосборка запускается при нехватке бюджета/дескрипторов или отказе выделения
  объекта, без вспомогательных аллокаций. Local остаётся корнем до перезаписи
  или выхода из метода; дальнейшее использование locals не анализируется.
- Вложенные вызовы разделяют лимиты. В типизированной native-функции ошибка
  передаётся через jbv_native_fail(vm, status) перед возвратом фиктивного значения;
  в прежних slot-callback возвращается статус. jbv_throw устанавливает корень
  Throwable: при возврате типизированной функции VM распространяет исключение
  автоматически; удержание хозяина остаётся его обязанностью. Для восстановления после
  вложенного исключения есть jbv_clear_exception. Внешний вызов Java очищает
  прежний pending exception.
- jbv_native_context(vm) возвращает user текущей типизированной функции.
  Контекст и код ошибки хранятся в её кадре: вложенные вызовы восстанавливают
  внешний контекст и не затирают его ошибку. Снаружи context возвращает null,
  native_fail — BAD_ARGUMENT. Внутри native нужно обработать или передать ошибку
  вызванной Java-функции; продолжение после неё не считается автоматическим успехом.
- Одна VM исполняется на одном системном потоке, это обеспечивает хозяин;
  автоматической проверки thread ID нет. Аллокатор не должен повторно входить
  в VM. Загрузка классов, перепривязка native, изменение бюджета кучи и
  уничтожение активной VM возвращают JBV_BUSY.

Стороннюю функцию с другим ABI/прототипом можно вызвать из обычного тела native-метода;
это делает C-компилятор. Обратный callback сторонней библиотеки — C-функция с
контекстом VM, вызывающая jbv_invoke_args. Создания callback-адресов, загрузки DLL и поиска символов
внутри VM нет. Хозяин управляет временем жизни C-контекстов и native-библиотек.
Пример с long/double, типизированным stdcall-callback и повторным входом:
[examples/native_host.c](examples/native_host.c),
[tests/java/NativeDemo.java](tests/java/NativeDemo.java).
Исполняемая память не генерируется.

## Сборка и проверки

Нужны Windows, Python 3.10+, Visual Studio 2022 Build Tools с C++ x86/CMake
и JDK 25. Проверено под Windows x64 через WOW64; отдельная 32-битная Windows
не проверялась. VM, хозяин и native-библиотеки должны иметь одну разрядность.

```powershell
python tools/build.py --test
python tools/build.py --profile text --test
python tools/build.py --profile core --test
# Явное указание инструментов:
python tools/build.py --jdk C:/path/to/jdk-25 --test --test-python C:/path/to/python-x86/python.exe
```

| Профиль | Состав | Каталог |
|---|---|---|
| full, по умолчанию | Ядро, native, текст, Java-библиотека, рефлексия и аннотации, Java MethodHandle, диагностика | build/x86 |
| text | Ядро, native, Object/Class/String/StringBuilder, C-реализация базовых исключений; без Java-библиотеки, рефлексии и stack traces | build/x86-text |
| core | Ядро, native, идентичность/клонирование Object, массивы, базовые исключения и мониторы; без строк и Class mirrors | build/x86-core |

C ABI одинаков; доступность групп возвращает `jbv_features()`. Строковые C API
в core возвращают UNSUPPORTED_FEATURE. Уменьшенные профили сознательно меняют
доступный classpath; это не эквивалентные по возможностям варианты full.
Флаг JBV_FEATURE_CONDY больше не возвращается; JBV_FEATURE_REFLECTION обозначает
описанный набор reflection в full. Подготовленный condy использует Java MethodHandle
из full; перенос в обычный байткод сам по себе не добавляет эту библиотеку в text/core.

JDK ищется в JAVA_HOME, .tools/jdk-25* и PATH; сборка ничего не скачивает.
Скрипт может работать в x64 Python; ctypes-тестам нужен x86 Python, автоматически
выбираемый из .tools/python-x86 или заданный через --test-python. Для embeddable
Python нужны tests и tools в python*._pth. `build.py` сначала генерирует
classpath и generated_classpath.c, затем вызывает CMake. Для full используйте
этот вход в сборку, а не чистый CMake без сгенерированного исходника.

```powershell
.\build\x86\Release\jbytevm-demo.exe .\build\classes\Core.class
.\build\x86\Release\jbytevm-native-demo.exe .\build\classes\NativeDemo.class
```

Проверки: **74 теста full, 52 text, 45 core**,
плюс два C-примера в каждой конфигурации. Полный набор включает:

- сравнения с HotSpot 25: 846 целочисленных, 37 объектных/массивных,
  5264 числовых, 7982 вывода float/double, 7910 операций обёрток/Math,
  4278 разбора float/double, 35 сценариев коллекций;
- исключения/clinit, интерфейсы/default-методы, nestmates и ошибки
  бинарной совместимости, condy с вложенными bootstrap, кэшем и рекурсией;
- source/line stack traces, cause/suppressed, печать через хозяина, Java OOM
  и StackOverflowError, ограниченность повторных удержанных OOM;
- original HotSpot → lowered HotSpot с `-Xverify:all` → JByteVM для лямбд и condy;
  подготовка каталога/JAR, сохранение ресурсов и атомарный отказ;
- condy в интерфейсе с private-bootstrap, null/long, GC и повторная попытка после
  прерывания host callback; рефлексия, повторный native-вход, наследование/доступ,
  массивы, инициализация, runtime-аннотации/defaults/Inherited/Repeatable под GC;
- типизированная таблица из 22 native-функций, перегрузки, все примитивы,
  mixed signatures, 255 слотов, x87 FP-результаты, ссылки, GC, вложенные
  контексты/ошибки и 100 повторных вызовов с испорченным native FP-окружением;
- allocator cleanup, слабый intern, stale handles, GC из callback/clinit,
  лимиты, PE32/x86 и отсутствие DLL-импортов. Verifier намеренно отсутствует.
- общий лимит памяти: точный учёт относительно запросов к host-аллокатору,
  граничные размеры при старте, откат загрузки класса, раздельный лимит кучи,
  повторная попытка после GC, общий бюджет native/Java и объект больше 4 МиБ
  при настройках по умолчанию.

Это регрессионный набор и дифференциальные проверки, **не Java SE TCK**.

## Размер и RAM

Лимит задаётся в `JbvConfig` при создании VM, в байтах:

```c
JbvConfig config = {0};
config.alloc = allocate;
config.free = release;
config.max_memory = 10 * 1024 * 1024; /* 0 также выбирает 10 МиБ */
config.max_heap = 0;                 /* или отдельный меньший лимит Java-кучи */
/* config.max_slots = 2048; */        /* при необходимости уменьшить Java-стек */
```

Память выделяется по мере надобности; весь бюджет заранее не резервируется.
`max_memory` ограничивает сумму живых блоков, запрошенных у аллокатора хозяина:
сама VM, заголовки учёта, Java-стек/метки, class-файлы и метаданные, таблицы
дескрипторов, мониторы, объекты и временные буферы. Пики при замене/росте
таблиц тоже учитываются. Расход/пик/предел доступны через `jbv_memory_stats`.
Служебные данные malloc хозяина, системный C-стек, страницы DLL и память,
выделяемая native-кодом самостоятельно, в этот лимит не входят.

`max_heap=0` использует общий предел; ненулевой `max_heap` задаёт дополнительный
предел Java-объектов и не может превышать `max_memory`. Он также меняется через
`jbv_set_heap_limit` на неактивной VM. Аварийный OOM может выйти за отдельный
лимит Java-кучи, но **никогда за общий лимит аллокаций**. Если для исключения
нет памяти, возвращается C-статус OUT_OF_MEMORY. Неудачная загрузка class-файла
освобождает свои частичные аллокации; неудачное создание VM освобождает всё.

`JbvConfig` расширен двумя полями: существующий C-хозяин нужно пересобрать
с обновлённым заголовком, а FFI-описание структуры обновить. Zero-initialization
выбирает значения по умолчанию. У VM нет проверки thread ID; хозяин по-прежнему
обеспечивает доступ с одного потока и отсутствие повторного входа из аллокатора.

Windows x86, MSVC 19.44, Release /O1, без упаковки исполняемого кода и LTO:

| Runtime | Байты | КиБ |
|---|---:|---:|
| full, со всей встроенной библиотекой (JAR, один поток) | **221 184** | **216,0** |
| full до коллекций/строк/regex/Unicode | 158 720 | 155,0 |
| full до Arrays/Collections/StrictMath/generics | 129 024 | 126,0 |
| full, JAR с отдельной записью на класс | 178 176 | 174,0 |
| full, несжатые class-файлы | 259 584 | 253,5 |
| text | **58 368** | **57,0** |
| core | **39 936** | **39,0** |
| Базовая DLL до версии 0.8 | 46 592 | 45,5 |

В full встроен JAR 133 984 байта (прирост над 155 КиБ: regex ~15 КБ, коллекции ~19 КБ, Unicode ~9 КБ, строки/кодировки ~8 КБ, форматирование ~7 КБ). Ранее — JAR 75 826 байт: все классы библиотеки (261 386 байт class-файлов)
в одной записи. Из прироста над 126 КиБ: StrictMath ~9 КиБ, Arrays, Collections и
разбор generics — по ~5 КиБ. Распаковщик DEFLATE и чтение ZIP занимают около 2,5 КиБ кода; внешние классы библиотеки и runtime DLL-зависимости не нужны.
Цель меньше 256 КиБ соблюдена. Цель **32 КиБ пока не достигнута**:
core превышает её на 6144 байта, из них около 3 КиБ — распаковщик JAR приложения.
Типизированный x86 ABI-переходник занимает около 96 байт по linker map.

Хозяин не включён в размер runtime: демонстрационный native EXE со своим
статическим CRT занимает 130 560 байт,
комплект full DLL + этот EXE + NativeDemo.class —
390 450 байт. Это не размер
прироста уже существующего приложения-хозяина.

RAM считается отдельно. Измерения `tools/measure_ram.py` используют суммы
размеров, запрошенных у аллокатора хозяина: без его служебных заголовков,
OS page overhead и C-стека. В full при 16384 слотах начальное состояние VM
занимает около 83 КБ; при 2048 слотах — около 11,4 КБ. `char[1024]` занимает
2056 байт вместе с заголовком; `int[1024]` — 4104. `boolean[]`/`byte[]` хранят 1 байт на элемент, `short[]`/`char[]` — 2.
После загрузки тестовых классов коллекций, их инициализации и GC замер дал
около 425 КБ живых аллокаций, из них 4100 байт Java-объектов; пик — около
470 КБ. Тесты рефлексии и аннотаций в отдельной VM дали 384 390 байт после GC,
из них 7964 байта Java-объектов, пик 400 770 байт. Это примеры нагрузки, не
гарантированный расход произвольного мода. Значения включают заголовки учёта. Метаданные и
копии class-файлов сохраняются до уничтожения VM; это существенный расход RAM.

До добавления общего лимита памяти, на 25 чередующихся раундах относительно
DLL 0.7 получено current/baseline:
**0,999** для int-цикла, **1,016** для массивов, **0,990** для long/double и
**0,431** для вызовов. Меньше — быстрее. Кэш class constants ускорил вызовы;
остальные три нагрузки в последнем прогоне близки к исходной скорости. В более
раннем прогоне int-цикл был на 8% медленнее: стабильного ускорения всех нагрузок
не заявляем. Результаты сверяются с HotSpot, SHA-256 обеих DLL записывается в
отчёт. Это четыре микротеста, не замер произвольного мода; коэффициенты зависят
от нагрузки системы.

```powershell
python tools/size_breakdown.py build/x86/Release/jbytevm.dll
.tools/python-x86/python.exe tools/measure_ram.py --jdk .tools/jdk-25.0.5+8 --build build/x86
.tools/python-x86/python.exe tools/profile_core.py --jdk .tools/jdk-25.0.5+8 --build build/x86 --baseline path/to/old-x86.dll --rounds 25
```

size-report.json, image-breakdown.json, timing-report.json, core-profile.json
и ram-report.json сохраняются в каталоге соответствующей сборки. Размеры
секций точные; распределение кода по функциям из linker map приблизительное.

## Пробные проекты

`tests/projects/pNN_*` — небольшие «моды» (инвентарь, события на лямбдах, enum,
исключения, рефлексия-плагины, JSON-парсер, физика, поиск пути и т.д.). Каждый
компилируется, проходит `prepare.py` в общий JAR и запускается в JByteVM; результат
`pNN.Main.run()` сравнивается с HotSpot. Часть проектов намеренно использует ещё
не поддержанные API (records, switch с паттернами, streams, EnumMap, PriorityQueue,
String.split/format) — это список пробелов, а не регрессии.

```powershell
.tools/python-x86/python.exe tests/run_projects.py --jdk .tools/jdk-25.0.5+8 [p05_enumcollections ...]
build/x86/Release/jbytevm-bench.exe app.jar pkg/Class method 5   # время статического ()I метода, хост на malloc
build/x86/Release/jbytevm-run.exe app.jar pkg/Class args...      # static int run(String[]); файлы через jbvhost.Host
```

## Сборка модов без indy

```powershell
javac --release 25 -XDstringConcat=inline -d classes MyMod.java
# Все моды (каталоги классов и/или JAR) — в один общий JAR приложения:
python tools/prepare.py --lower-lambdas --lower-condy classes other-mod.jar -o app.jar
# Обратно в обычный каталог классов (для HotSpot и инструментов):
python tools/prepare.py --unpack app.jar -o app-classes
```

Результат всегда один JAR: все классы лежат в одной записи `jbv/classes.bin`,
сжатой одним потоком DEFLATE (тот же формат, что у встроенной библиотеки), ресурсы —
обычными записями. Хозяин передаёт его целиком: `jbv_load_jar(vm, bytes, size)`.
VM сразу распаковывает классы в свою память (входит в бюджет), буфер хозяина
не удерживает; классы загружаются лениво при первом обращении, в том числе
при привязке native-функций. На VM — один такой JAR. Отдельные class-файлы
по-прежнему можно передать через `jbv_load_class`.

Подготовка отклоняет одинаковые классы или ресурсы из разных входов, классы в
пакетах библиотеки (`java/`, `javax/`, `jdk/`, `sun/`, `jbv/`), indy/condy без
преобразования и не Java 25 class-файлы. Работа идёт во временном каталоге;
при ошибке результат не создаётся. Подписанные и multi-release JAR нужно сначала
пересобрать/привести к одной версии.

`--lower-lambdas` преобразует LambdaMetafactory/altMetafactory в обычные классы, а records (ObjectMethods) и switch с паттернами (SwitchBootstraps.typeSwitch/enumSwitch) — в обычный байткод с той же семантикой, что у JDK,
и удаляет InvokeDynamic из constant pool. Произвольные bootstrap для indy
не поддерживаются. Serializable-лямбды получают marker interface, но протокол
Java serialization/SerializedLambda не реализован. Замыкания и их nest host
должны находиться в одном входном наборе. Генерация не исполняет код мода.

`--lower-condy` заменяет ldc CONSTANT_Dynamic вызовами сгенерированных методов.
Для каждой достижимой записи CP создаётся отдельный кэш, включая null и ошибку;
вложенные константы сохраняют общие ссылки на свой кэш. Вспомогательный класс
в том же nest хранит результат, а private synthetic-метод исходного класса
вызывает bootstrap с исходным Lookup. Преобразователь не вычисляет bootstrap.
Поддержаны static/constructor bootstrap handles; их выполнение ограничено
поддержанным набором java.lang.invoke. Циклы завершаются StackOverflowError,
host abort без Java-исключения не фиксируется как ошибка bootstrap.
Nest host должен присутствовать на входе; конфликт генерируемого имени и
неподдержанный вид bootstrap приводят к отказу подготовки. Добавленные synthetic
члены видны через reflection; сериализация преобразованных классов не обещается.

`-XDstringConcat=inline` — внутренний флаг javac, проверенный на Temurin 25.0.5;
сам по себе он не преобразует лямбды. Загрузчик VM отклоняет CONSTANT_InvokeDynamic,
даже неиспользуемые записи; выполнение opcode indy также запрещено.
CONSTANT_Dynamic также отклоняется во всех профилях; для него нужен `--lower-condy`.

## Точные границы совместимости

Нет JIT, verifier, JNI/FFM, Java-потоков/wait, класслоадеров, выгрузки классов,
полной reflection, файлов/сети, serialization, streams/Spliterator, regex/локалей
и полного Java SE classpath. Отдельные отсутствующие методы не подменяются
успешными заглушками: обращение завершается ошибкой разрешения/unsupported.

В частности, Math не содержит sin/cos/log/exp/pow/fma; Character не содержит
полных Unicode case/category API. Нет публичных java.util.Arrays/Collections,
TreeMap/LinkedHashMap и деревьев в collision buckets HashMap. Представленные
интерфейсы java.util.function содержат выбранные специализации и defaults.
PrintStream обслуживает текст через хозяина, а не весь java.io.

MethodHandle ограничен прямыми Java-целями: Lookup для методов/конструкторов/
полей, invokeExact/invoke/invokeWithArguments и необходимые condy преобразования.
Нет asType/bindTo/combinators, VarHandle и полного режима Lookup. Не вся
адаптация `invoke` соответствует JDK (в том числе диагностика несовместимых
типов и void → primitive). Полную совместимость java.lang.invoke не заявляем.

Проверены основной linking/access control и исполнение доверенного байткода;
это не доказательство всей семантики JVM. Набор конструкторов встроенных
исключений не полностью совпадает с JDK, helpful NPE messages отсутствуют.
При нехватке памяти stack trace может быть неполным; один живой аварийный OOM
переиспользуется, его trace не гарантирован. C++/SEH-исключения не должны
пересекать VM. Реализация и проверки этой версии относятся только к x86.

Исходные спецификации:
[формат Java 25](https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-4.html),
[linking и dynamic constants](https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-5.html),
[инструкции JVM](https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-6.html),
[Class-File API](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/classfile/package-summary.html).
