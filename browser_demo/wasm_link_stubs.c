// Link-time-only stubs for symbols that some wasm32 SIDE_MODULEs in this
// build declare as "needed" (Emscripten's MAIN_MODULE dynamic linker
// resolves every declared import eagerly, even ones dead-code-elimination
// would otherwise drop) but that this demo never actually calls at runtime:
//
//  - rmw_get_* graph-introspection functions: rmw_zenoh_pico (esol-community)
//    implements the core pub/sub/service lifecycle but not the "list
//    topics/services/nodes" introspection family -- confirmed via `nm` on
//    its own .so, 2026-09-09. librcl.so unconditionally exports wrappers
//    around these, so any rcl-based executable needs them resolvable even
//    if, like this talker, it never calls rcl_get_topic_names_and_types().
//  - dlinfo/pthread_setname_np/pthread_getname_np: rcutils/rcpputils use
//    these Linux-only APIs for a thread-naming debug utility with no
//    Emscripten guard (same class of gap as tracetools/
//    rmw_test_fixture_implementation elsewhere in this build).
//  - Python C-API symbols: the combined rosidl message-typesupport .so's
//    (rcl_interfaces, std_msgs, etc.) declare a dylink "needed" dependency
//    on their own sibling *_rosidl_generator_py.so purely as an artifact of
//    how those packages bundle every typesupport variant together -- no
//    code here uses rclpy/Python.
//
// None of these are ever actually invoked by this C-only demo; they exist
// solely so Emscripten's MAIN_MODULE loader can resolve every import.

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>

#include <rcutils/allocator.h>
#include <rmw/rmw.h>
#include <rmw/get_node_info_and_types.h>
#include <rmw/get_service_endpoint_info.h>
#include <rmw/get_topic_names_and_types.h>
#include <rmw/get_service_names_and_types.h>

// ---- rmw graph-introspection stubs -----------------------------------
const char * rmw_get_implementation_identifier(void) { return "rmw_zenoh_pico"; }

rmw_ret_t rmw_get_topic_names_and_types(
  const rmw_node_t * node, rcutils_allocator_t * allocator, bool no_demangle,
  rmw_names_and_types_t * topic_names_and_types)
{
  (void)node; (void)allocator; (void)no_demangle; (void)topic_names_and_types;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_service_names_and_types(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  rmw_names_and_types_t * service_names_and_types)
{
  (void)node; (void)allocator; (void)service_names_and_types;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_publisher_names_and_types_by_node(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  const char * node_name, const char * node_namespace, bool no_demangle,
  rmw_names_and_types_t * topic_names_and_types)
{
  (void)node; (void)allocator; (void)node_name; (void)node_namespace;
  (void)no_demangle; (void)topic_names_and_types;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_subscriber_names_and_types_by_node(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  const char * node_name, const char * node_namespace, bool no_demangle,
  rmw_names_and_types_t * topic_names_and_types)
{
  (void)node; (void)allocator; (void)node_name; (void)node_namespace;
  (void)no_demangle; (void)topic_names_and_types;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_service_names_and_types_by_node(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  const char * node_name, const char * node_namespace,
  rmw_names_and_types_t * service_names_and_types)
{
  (void)node; (void)allocator; (void)node_name; (void)node_namespace;
  (void)service_names_and_types;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_client_names_and_types_by_node(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  const char * node_name, const char * node_namespace,
  rmw_names_and_types_t * service_names_and_types)
{
  (void)node; (void)allocator; (void)node_name; (void)node_namespace;
  (void)service_names_and_types;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_clients_info_by_service(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  const char * service_name, bool no_mangle,
  rmw_service_endpoint_info_array_t * clients_info)
{
  (void)node; (void)allocator; (void)service_name; (void)no_mangle; (void)clients_info;
  return RMW_RET_UNSUPPORTED;
}

rmw_ret_t rmw_get_servers_info_by_service(
  const rmw_node_t * node, rcutils_allocator_t * allocator,
  const char * service_name, bool no_mangle,
  rmw_service_endpoint_info_array_t * servers_info)
{
  (void)node; (void)allocator; (void)service_name; (void)no_mangle; (void)servers_info;
  return RMW_RET_UNSUPPORTED;
}

// ---- posix thread-naming / dl introspection stubs ----------------------
int dlinfo(void * handle, int request, void * info)
{
  (void)handle; (void)request; (void)info;
  return -1;
}

int pthread_setname_np(unsigned long thread, const char * name)
{
  (void)thread; (void)name;
  return 0;
}

int pthread_getname_np(unsigned long thread, char * name, size_t len)
{
  (void)thread;
  if (name != NULL && len > 0) { name[0] = '\0'; }
  return 0;
}

// ---- CPython C-API stubs (never reached: this demo doesn't use rclpy) --
typedef struct _object PyObject;
typedef struct _object PyTypeObject;
struct _stub_py_storage { long placeholder; };

#define STUB_TYPE(name) struct _stub_py_storage name##_storage; \
  PyTypeObject * name = (PyTypeObject *)&name##_storage;

PyObject * PyBool_FromLong(long v) { (void)v; return NULL; }
STUB_TYPE(PyBool_Type)
void PyBuffer_Release(void * view) { (void)view; }
int PyBuffer_ToContiguous(void * buf, void * view, size_t len, char order)
{ (void)buf; (void)view; (void)len; (void)order; return -1; }
PyObject * PyBytes_FromStringAndSize(const char * v, ssize_t len) { (void)v; (void)len; return NULL; }
void PyErr_Clear(void) {}
void PyErr_SetString(PyObject * type, const char * message) { (void)type; (void)message; }
struct _stub_py_storage _PyExc_RuntimeError_storage;
PyObject * PyExc_RuntimeError = (PyObject *)&_PyExc_RuntimeError_storage;
PyObject * PyFloat_FromDouble(double v) { (void)v; return NULL; }
STUB_TYPE(PyFloat_Type)
PyObject * PyImport_ImportModule(const char * name) { (void)name; return NULL; }
PyObject * PyList_New(ssize_t len) { (void)len; return NULL; }
int PyList_SetItem(PyObject * list, ssize_t index, PyObject * item)
{ (void)list; (void)index; (void)item; return -1; }
long PyLong_AsLong(PyObject * obj) { (void)obj; return 0; }
long long PyLong_AsLongLong(PyObject * obj) { (void)obj; return 0; }
size_t PyLong_AsSize_t(PyObject * obj) { (void)obj; return 0; }
unsigned long PyLong_AsUnsignedLong(PyObject * obj) { (void)obj; return 0; }
unsigned long long PyLong_AsUnsignedLongLong(PyObject * obj) { (void)obj; return 0; }
PyObject * PyLong_FromLong(long v) { (void)v; return NULL; }
PyObject * PyLong_FromLongLong(long long v) { (void)v; return NULL; }
PyObject * PyLong_FromUnsignedLong(unsigned long v) { (void)v; return NULL; }
PyObject * PyLong_FromUnsignedLongLong(unsigned long long v) { (void)v; return NULL; }
PyObject * PyObject_CallFunctionObjArgs(PyObject * callable, ...) { (void)callable; return NULL; }
PyObject * PyObject_CallObject(PyObject * callable, PyObject * args) { (void)callable; (void)args; return NULL; }
int PyObject_CheckBuffer(PyObject * obj) { (void)obj; return 0; }
PyObject * PyObject_GetAttrString(PyObject * obj, const char * attr) { (void)obj; (void)attr; return NULL; }
int PyObject_GetBuffer(PyObject * obj, void * view, int flags) { (void)obj; (void)view; (void)flags; return -1; }
int PyObject_SetAttrString(PyObject * obj, const char * attr, PyObject * value)
{ (void)obj; (void)attr; (void)value; return -1; }
ssize_t PyObject_Size(PyObject * obj) { (void)obj; return -1; }
int PySequence_Check(PyObject * obj) { (void)obj; return 0; }
PyObject * PySequence_Fast(PyObject * obj, const char * message) { (void)obj; (void)message; return NULL; }
ssize_t PySequence_Size(PyObject * obj) { (void)obj; return -1; }
int PyType_IsSubtype(PyTypeObject * a, PyTypeObject * b) { (void)a; (void)b; return 0; }
const char * PyUnicode_AsUTF8(PyObject * obj) { (void)obj; return NULL; }
PyObject * PyUnicode_AsUTF8String(PyObject * obj) { (void)obj; return NULL; }
PyObject * PyUnicode_DecodeUTF8(const char * s, ssize_t size, const char * errors)
{ (void)s; (void)size; (void)errors; return NULL; }
void _Py_Dealloc(PyObject * obj) { (void)obj; }
struct _stub_py_storage _Py_TrueStruct_storage;
PyObject * _Py_TrueStruct = (PyObject *)&_Py_TrueStruct_storage;
