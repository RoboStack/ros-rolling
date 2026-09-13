#include <Python.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
  printf("pytest_boot: initializing CPython\n");
  Py_SetPythonHome(L"/pyhome");
  Py_Initialize();
  printf("pytest_boot: initialized, running script\n");
  int rc = PyRun_SimpleString("import sys; print('hello from embedded cpython', sys.version)");
  printf("pytest_boot: PyRun_SimpleString rc=%d\n", rc);
  Py_Finalize();
  return 0;
}
