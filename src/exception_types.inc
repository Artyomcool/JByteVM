; From exceptions.c (types[]): counted name (also 0-terminated), then the parent as a byte offset of its record (0FFFFh: Object).
types LABEL BYTE
t_Throwable DB 19, 'java/lang/Throwable', 0
    DW 0FFFFh
t_Exception DB 19, 'java/lang/Exception', 0
    DW t_Throwable - types
t_RuntimeException DB 26, 'java/lang/RuntimeException', 0
    DW t_Exception - types
t_Error DB 15, 'java/lang/Error', 0
    DW t_Throwable - types
t_ArithmeticException DB 29, 'java/lang/ArithmeticException', 0
    DW t_RuntimeException - types
t_NullPointerException DB 30, 'java/lang/NullPointerException', 0
    DW t_RuntimeException - types
t_IndexOutOfBoundsException DB 35, 'java/lang/IndexOutOfBoundsException', 0
    DW t_RuntimeException - types
t_ArrayIndexOutOfBoundsException DB 40, 'java/lang/ArrayIndexOutOfBoundsException', 0
    DW t_IndexOutOfBoundsException - types
t_StringIndexOutOfBoundsException DB 41, 'java/lang/StringIndexOutOfBoundsException', 0
    DW t_IndexOutOfBoundsException - types
t_NegativeArraySizeException DB 36, 'java/lang/NegativeArraySizeException', 0
    DW t_RuntimeException - types
t_ArrayStoreException DB 29, 'java/lang/ArrayStoreException', 0
    DW t_RuntimeException - types
t_ClassCastException DB 28, 'java/lang/ClassCastException', 0
    DW t_RuntimeException - types
t_IllegalArgumentException DB 34, 'java/lang/IllegalArgumentException', 0
    DW t_RuntimeException - types
t_NumberFormatException DB 31, 'java/lang/NumberFormatException', 0
    DW t_IllegalArgumentException - types
t_IllegalStateException DB 31, 'java/lang/IllegalStateException', 0
    DW t_RuntimeException - types
t_IllegalMonitorStateException DB 38, 'java/lang/IllegalMonitorStateException', 0
    DW t_RuntimeException - types
t_UnsupportedOperationException DB 39, 'java/lang/UnsupportedOperationException', 0
    DW t_RuntimeException - types
t_LinkageError DB 22, 'java/lang/LinkageError', 0
    DW t_Error - types
t_UnsatisfiedLinkError DB 30, 'java/lang/UnsatisfiedLinkError', 0
    DW t_LinkageError - types
t_NoClassDefFoundError DB 30, 'java/lang/NoClassDefFoundError', 0
    DW t_LinkageError - types
t_IncompatibleClassChangeError DB 38, 'java/lang/IncompatibleClassChangeError', 0
    DW t_LinkageError - types
t_IllegalAccessError DB 28, 'java/lang/IllegalAccessError', 0
    DW t_IncompatibleClassChangeError - types
t_AbstractMethodError DB 29, 'java/lang/AbstractMethodError', 0
    DW t_IncompatibleClassChangeError - types
t_InstantiationError DB 28, 'java/lang/InstantiationError', 0
    DW t_IncompatibleClassChangeError - types
t_NoSuchMethodError DB 27, 'java/lang/NoSuchMethodError', 0
    DW t_IncompatibleClassChangeError - types
t_NoSuchFieldError DB 26, 'java/lang/NoSuchFieldError', 0
    DW t_IncompatibleClassChangeError - types
t_BootstrapMethodError DB 30, 'java/lang/BootstrapMethodError', 0
    DW t_LinkageError - types
t_ExceptionInInitializerError DB 37, 'java/lang/ExceptionInInitializerError', 0
    DW t_LinkageError - types
t_VirtualMachineError DB 29, 'java/lang/VirtualMachineError', 0
    DW t_Error - types
t_OutOfMemoryError DB 26, 'java/lang/OutOfMemoryError', 0
    DW t_VirtualMachineError - types
t_StackOverflowError DB 28, 'java/lang/StackOverflowError', 0
    DW t_VirtualMachineError - types
t_AssertionError DB 24, 'java/lang/AssertionError', 0
    DW t_Error - types
t_ReflectiveOperationException DB 38, 'java/lang/ReflectiveOperationException', 0
    DW t_Exception - types
t_NoSuchMethodException DB 31, 'java/lang/NoSuchMethodException', 0
    DW t_ReflectiveOperationException - types
t_NoSuchFieldException DB 30, 'java/lang/NoSuchFieldException', 0
    DW t_ReflectiveOperationException - types
IF JBV_PROFILE_FULL
t_ClassNotFoundException DB 32, 'java/lang/ClassNotFoundException', 0
    DW t_ReflectiveOperationException - types
ENDIF
IF JBV_PROFILE_FULL
t_InstantiationException DB 32, 'java/lang/InstantiationException', 0
    DW t_ReflectiveOperationException - types
ENDIF
IF JBV_PROFILE_FULL
t_IncompleteAnnotationException DB 50, 'java/lang/annotation/IncompleteAnnotationException', 0
    DW t_RuntimeException - types
ENDIF
IF JBV_PROFILE_FULL
t_EnumConstantNotPresentException DB 41, 'java/lang/EnumConstantNotPresentException', 0
    DW t_RuntimeException - types
ENDIF
t_WrongMethodTypeException DB 41, 'java/lang/invoke/WrongMethodTypeException', 0
    DW t_RuntimeException - types
t_IllegalAccessException DB 32, 'java/lang/IllegalAccessException', 0
    DW t_ReflectiveOperationException - types
t_CloneNotSupportedException DB 36, 'java/lang/CloneNotSupportedException', 0
    DW t_Exception - types
t_NoSuchElementException DB 32, 'java/util/NoSuchElementException', 0
    DW t_RuntimeException - types
t_ConcurrentModificationException DB 41, 'java/util/ConcurrentModificationException', 0
    DW t_RuntimeException - types
types_end LABEL BYTE
