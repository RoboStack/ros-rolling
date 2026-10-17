# RoboStack (for ROS rolling)

[![Conda](https://img.shields.io/conda/dn/robostack-rolling/ros-rolling-desktop?style=flat-square)](https://anaconda.org/robostack/)
[![GitHub Repo stars](https://img.shields.io/github/stars/robostack/ros-rolling?style=flat-square)](https://github.com/RoboStack/ros-rolling/)
[![QUT Centre for Robotics](https://img.shields.io/badge/collection-QUT%20Robotics-%23043d71?style=flat-square)](https://qcr.github.io/)

[![Platforms](https://img.shields.io/badge/platforms-linux%20%7C%20win%20%7C%20macos%20%7C%20macos_arm64%20%7C%20linux_aarch64-green.svg?style=flat-square)](https://github.com/RoboStack/ros-rolling)
[![Azure DevOps builds (branch)](https://img.shields.io/github/actions/workflow/status/robostack/ros-rolling/linux.yml?branch=buildbranch_linux&label=build%20linux&style=flat-square)](https://github.com/RoboStack/ros-rolling/actions/workflows/linux.yml)
[![Azure DevOps builds (branch)](https://img.shields.io/github/actions/workflow/status/robostack/ros-rolling/win.yml?branch=buildbranch_win&label=build%20win&style=flat-square)](https://github.com/RoboStack/ros-rolling/actions/workflows/win.yml)
[![Azure DevOps builds (branch)](https://img.shields.io/github/actions/workflow/status/robostack/ros-rolling/osx.yml?branch=buildbranch_osx&label=build%20osx&style=flat-square)](https://github.com/RoboStack/ros-rolling/actions/workflows/osx.yml)
[![Azure DevOps builds (branch)](https://img.shields.io/github/actions/workflow/status/robostack/ros-rolling/osx_arm64.yml?branch=buildbranch_osx_arm64&label=build%20osx-arm64&style=flat-square)](https://github.com/RoboStack/ros-rolling/actions/workflows/osx_arm64.yml)
[![Azure DevOps builds (branch)](https://img.shields.io/github/actions/workflow/status/robostack/ros-rolling/build_linux_aarch64.yml?branch=buildbranch_linux_aarch64&label=build%20aarch64&style=flat-square)](https://github.com/RoboStack/ros-rolling/actions/workflows/build_linux_aarch64.yml)

[![GitHub issues](https://img.shields.io/github/issues-raw/robostack/ros-rolling?style=flat-square)](https://github.com/RoboStack/ros-rolling/issues)
[![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/robostack/ros-rolling?style=flat-square)](https://github.com/RoboStack/ros-rolling/issues?q=is%3Aissue+is%3Aclosed)
[![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/robostack/ros-rolling?style=flat-square)](https://github.com/RoboStack/ros-rolling/pulls)
[![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed-raw/robostack/ros-rolling?style=flat-square)](https://github.com/RoboStack/ros-rolling/pulls?q=is%3Apr+is%3Aclosed)

[__Table with all available packages & architectures__](https://robostack.github.io/rolling.html)

## Why ROS and Conda?

Welcome to RoboStack, which tightly couples ROS with Conda, a cross-platform, language-agnostic package manager. We provide ROS binaries for Linux, macOS, Windows and ARM (Linux). Installing other recent packages via conda-forge side-by-side works easily, e.g. you can install TensorFlow/PyTorch in the same environment as ROS rolling without any issues. As no system libraries are used, you can also easily install ROS rolling on any recent Linux Distribution - including older versions of Ubuntu. As the packages are pre-built, it saves you from compiling from source, which is especially helpful on macOS and Windows. No root access is required, all packages live in your home directory. We have recently written up a [paper](https://arxiv.org/abs/2104.12910) and [blog post](https://medium.com/robostack/cross-platform-conda-packages-for-ros-fa1974fd1de3) with more information.

## Attribution

If you use RoboStack in your academic work, please refer to the following paper:

```bibtex
@article{FischerRAM2021,
    title={A RoboStack Tutorial: Using the Robot Operating System Alongside the Conda and Jupyter Data Science Ecosystems},
    author={Tobias Fischer and Wolf Vollprecht and Silvio Traversaro and Sean Yen and Carlos Herrero and Michael Milford},
    journal={IEEE Robotics and Automation Magazine},
    year={2021},
    doi={10.1109/MRA.2021.3128367},
}
```

## Installation, FAQ, and Contributing Instructions

Please see our instructions [here](https://robostack.github.io/GettingStarted.html).

## CUDA buffer builds

On Linux, `cuda_buffer` and `cuda_buffer_backend` build two variants. The
`cuda_buffer_cuda_version` matrix in `conda_build_config.yaml` is preserved by
the matching override in `vinca_pinning.yaml`.

| Build SDK | Runtime constraint | CUDA runtime ABI |
| --- | --- | --- |
| 12.9 | `cuda-version >=12.9,<13` | `libcudart.so.12` |
| 13.0 | `cuda-version >=13.0,<14` | `libcudart.so.13` |

`pixi run build` builds both variants. To debug the dependency chain, run
`pixi run build-one ros2-cuda-buffer` followed by
`pixi run build-one ros2-cuda-buffer-backend`. Select the installed variant by
constraining `cuda-version` in the consuming environment; the package build
hashes distinguish the two variants. Match that CUDA major with GPU LibTorch
when using both libraries in the same environment.

CUDA buffer and GPU LibTorch builds use GCC 14 on Linux, to satisfy the CUDA
tool packages' compiler constraints. Native build tools live in the build
prefix; target CUDA runtime,
driver stubs and CRT headers live in the host prefix. The installed packages
depend on the CUDA runtime, without bundling driver stubs or requiring nvcc at
runtime. The NVIDIA driver supplies `libcuda.so.1` on the target machine.
macOS and Windows skip these packages because the sources use POSIX IPC and
`librt`. LibTorch and the message-only packages retain their existing platform
support.

## LibTorch CPU and GPU builds

`libtorch_vendor` reuses conda-forge's `libtorch` through `find_package(Torch)`.
The default builds use its CPU variant. Set `CF_CUDA_ENABLED=True` to additionally
build CUDA 12.9 and 13.0 variants on `linux-64`, `linux-aarch64`, and `win-64`:

```bash
CF_CUDA_ENABLED=True pixi run build
```

This uses the existing `cuda_compiler_version` matrix in `vinca_pinning.yaml`;
macOS keeps CPU builds even with the flag enabled. LibTorch and
`torch_conversions` runtime dependencies select the same CPU/CUDA variant.
Linux GPU `torch_conversions` also enables `cuda_buffer`, with the matching
CUDA major. Builds use the CUDA SDK and driver stubs, so an NVIDIA driver and
GPU are not required for compilation. Running CUDA tensor operations requires
a compatible NVIDIA driver and GPU.
