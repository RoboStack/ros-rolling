// Same rmw graph-introspection / posix thread-naming stubs as
// browser_demo/wasm_link_stubs.c, minus the CPython C-API section --
// this build links a real libpython3.13.a, so those symbols are no
// longer stubs, they're the genuine implementations.

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
