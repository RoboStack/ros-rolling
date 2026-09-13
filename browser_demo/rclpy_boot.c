// Embeds CPython + rclpy directly, rather than launching a standalone
// python.js: this Python is built with --enable-wasm-pthreads (see
// extra_recipes/python/), and CPython's own docs flag pthreads + its
// --enable-wasm-dynamic-linking (needed for Python's normal `import` of a
// compiled .so extension module) as known-crashy together -- so this build
// doesn't enable dynamic linking, and every compiled extension module any
// imported code might reach (rclpy's own pybind11 module, each message
// package's rosidl_generator_py typesupport accessor, numpy's C extensions)
// has to be registered ahead of time via PyImport_AppendInittab() instead of
// left for Python's import system to dlopen on demand.

#include <Python.h>
#include <stdio.h>
#include <stdlib.h>

PyMODINIT_FUNC PyInit__rclpy_pybind11(void);
PyMODINIT_FUNC PyInit_rcl_interfaces_s__rosidl_typesupport_c(void);
PyMODINIT_FUNC PyInit_builtin_interfaces_s__rosidl_typesupport_c(void);
PyMODINIT_FUNC PyInit_std_msgs_s__rosidl_typesupport_c(void);
PyMODINIT_FUNC PyInit_type_description_interfaces_s__rosidl_typesupport_c(void);
PyMODINIT_FUNC PyInit_service_msgs_s__rosidl_typesupport_c(void);
PyMODINIT_FUNC PyInit__multiarray_umath(void);
PyMODINIT_FUNC PyInit__simd(void);
PyMODINIT_FUNC PyInit__umath_linalg(void);
PyMODINIT_FUNC PyInit_lapack_lite(void);
PyMODINIT_FUNC PyInit__pocketfft_umath(void);
PyMODINIT_FUNC PyInit__common(void);
PyMODINIT_FUNC PyInit__bounded_integers(void);
PyMODINIT_FUNC PyInit_bit_generator(void);
PyMODINIT_FUNC PyInit_mtrand(void);
PyMODINIT_FUNC PyInit__philox(void);
PyMODINIT_FUNC PyInit__sfc64(void);
PyMODINIT_FUNC PyInit__generator(void);
PyMODINIT_FUNC PyInit__pcg64(void);
PyMODINIT_FUNC PyInit__mt19937(void);

int main(int argc, char *argv[]) {
  setenv("RCL_LOGGING_IMPLEMENTATION", "rcl_logging_noop", 1);
  // rcl_interfaces / type_description_interfaces / service_msgs below are
  // linked against a rebuild with STATIC_ROSIDL_TYPESUPPORT_C=microxrcedds_c
  // but STATIC_ROSIDL_TYPESUPPORT_CPP left on introspection: the known
  // rosidl_typesupport_microxrcedds_cpp codegen gap for service "_Event"
  // messages is specific to the C++ backend -- the C backend those packages
  // need for rmw_zenoh_pico builds fine.
  struct { const char *name; PyObject *(*init)(void); } mods[] = {
    {"_rclpy_pybind11", PyInit__rclpy_pybind11},
    {"rcl_interfaces.rcl_interfaces_s__rosidl_typesupport_c", PyInit_rcl_interfaces_s__rosidl_typesupport_c},
    {"builtin_interfaces.builtin_interfaces_s__rosidl_typesupport_c", PyInit_builtin_interfaces_s__rosidl_typesupport_c},
    {"std_msgs.std_msgs_s__rosidl_typesupport_c", PyInit_std_msgs_s__rosidl_typesupport_c},
    {"type_description_interfaces.type_description_interfaces_s__rosidl_typesupport_c", PyInit_type_description_interfaces_s__rosidl_typesupport_c},
    {"service_msgs.service_msgs_s__rosidl_typesupport_c", PyInit_service_msgs_s__rosidl_typesupport_c},
    {"numpy._core._multiarray_umath", PyInit__multiarray_umath},
    {"numpy._core._simd", PyInit__simd},
    {"numpy.linalg._umath_linalg", PyInit__umath_linalg},
    {"numpy.linalg.lapack_lite", PyInit_lapack_lite},
    {"numpy.fft._pocketfft_umath", PyInit__pocketfft_umath},
    {"numpy.random._common", PyInit__common},
    {"numpy.random._bounded_integers", PyInit__bounded_integers},
    {"numpy.random.bit_generator", PyInit_bit_generator},
    {"numpy.random.mtrand", PyInit_mtrand},
    {"numpy.random._philox", PyInit__philox},
    {"numpy.random._sfc64", PyInit__sfc64},
    {"numpy.random._generator", PyInit__generator},
    {"numpy.random._pcg64", PyInit__pcg64},
    {"numpy.random._mt19937", PyInit__mt19937},
  };
  for (size_t i = 0; i < sizeof(mods) / sizeof(mods[0]); i++) {
    if (PyImport_AppendInittab(mods[i].name, mods[i].init) == -1) {
      printf("rclpy_boot: AppendInittab failed for %s\n", mods[i].name);
      return 1;
    }
  }
  Py_SetPythonHome(L"/pyhome");
  Py_Initialize();

  int rc = PyRun_SimpleString(
    "import sys\n"
    "sys.path.insert(0, '/pyhome/site-packages')\n"
    "exec(open('/pyhome/talker_rclpy.py').read())\n"
  );
  printf("rclpy_boot: PyRun_SimpleString rc=%d\n", rc);
  if (rc != 0) {
    PyErr_Print();
  }
  Py_Finalize();
  return rc;
}
