# gl4metal renderer integration

Select **gl4metal - OpenGL on Metal (experimental)** in the launcher's renderer
settings or a profile's renderer settings. The saved renderer identifier is
`libgl4metal.dylib`. Auto selection continues to use the existing renderers.

## Build and package

### Windows: build with GitHub's Mac

The **Build Hynis + custom gl4metal** workflow (`development.yml`) builds the
modified renderer and the launcher together on `macos-latest`. You do not need
a local Mac or a separate gl4metal fork. The patch in
`patches/gl4metal/custom-resources.patch` contains this task's 3D image, SSBO and
compute changes; `manifest.json` pins their upstream base and checksum.

1. Upload/commit the modified Hynis files to your Hynis-JE repository, keeping the
   folder structure, including `.github`, `patches`, `scripts` and `Natives`.
   If using the supplied upload ZIP, extract it and upload its **contents** at the
   repository root. Uploading the ZIP itself does not update the source files.
2. Commit to your default branch (usually `main`). Open **Actions** and enable
   workflows if GitHub asks. The push starts **Build Hynis + custom gl4metal**;
   you can also select it and click **Run workflow**.
3. When the run succeeds, open its **Artifacts** section and download
   **Hynis-custom-gl4metal-iOS**. Extract the artifact ZIP. It contains the regular
   `.ipa`, the TrollStore `.tipa`, and `gl4metal-build.json` identifying the patch
   and library checksum. The slimmed artifact omits the bundled Java runtimes.
4. Install the appropriate app package, then choose **gl4metal - OpenGL on Metal
   (experimental)** in Hynis's renderer settings. Auto does not select gl4metal.

Use this workflow, not the old **Release build**, which requires the project's
private MacStadium runner. Workflow setup and local checks are not a completed
GitHub build; obtain the IPA from a successful run before device testing.

### Local macOS/iOS build

Use Hynis's normal macOS/iOS build prerequisites, plus Python 3 for the Mach-O
validation step. Initialize the pinned renderer and its compiler dependencies:

```sh
git submodule update --init --recursive
python3 scripts/apply_gl4metal_patch.py Natives/external/gl4metal
gmake package PLATFORM=2
```

`native` builds gl4metal separately, checks its architecture, device platform and
C exports, and stages `Natives/build/libgl4metal.dylib`. The existing payload
recipe copies it into `Hynis.app/Frameworks` and signs it with the other dylibs.
Xcode's legacy target invokes this same Makefile. The custom development workflow
also checks out and applies the bundled renderer patch before building.
No manual dylib injection or EGL wrapper is needed.

To include the custom image, SSBO and compute work in a separate gl4metal checkout,
explicitly select that checkout. The bundled patch is a snapshot; it does not
automatically import subsequent changes from another directory:

```sh
gmake package PLATFORM=2 GL4METAL_SOURCE_DIR="$(cd ../gl4metal && pwd)"
```

Or provide an already built, thin arm64 **iOS device** library:

```sh
gmake package PLATFORM=2 GL4METAL_LIBRARY="/absolute/path/libgl4metal.dylib"
```

The source build uses the selected `SDKPATH`, iOS 14 deployment target and an
`@rpath` install name. Device GPU capabilities still determine which backend
features work. This integration targets physical iOS devices; the launcher's
other platform conversion recipes do not establish simulator compatibility.

## Context and function loading

The JVM receives an absolute `org.lwjgl.opengl.libname` path before LWJGL loads
its GL provider. The native bridge opens the same bundled library and resolves
`gl4metalInit`, `glMakeCurrent`, `glSwapBuffers`, `glSwapInterval`, and `glFinish`
from that library's handle. It does not resolve these through ANGLE/EGL or the
process's global symbol table. GLFW function lookups use LWJGL's selected provider.

Window creation allocates a launcher context token. The first successful
`glfwMakeContextCurrent` initializes gl4metal on Minecraft's rendering thread
and supplies the `CAMetalLayer`. Presenting refreshes the layer reference so an
external-display switch can replace the surface. The shared thread-local context
pointer makes `glfwGetCurrentContext` agree with the rendering bridge.

The current upstream gl4metal ABI has a process-wide initialization guard,
thread-local GL state, and no context sharing or teardown/reset API. Consequently:

- One live GL context and one rendering thread are supported.
- Shared contexts, a second live context, and migration to another thread report
  GLFW errors, with an explanation in the launcher log.
- Unbinding finishes outstanding work and clears the calling thread's current
  context. It preserves the backend's thread ownership.
- Destroying an initialized context requires restarting the game before creating
  another. Disable mod loading screens that create their own GL context/thread.
- The library remains loaded while LWJGL holds its function pointers.

The launcher does not change the OpenGL version/extensions advertised by gl4metal.
Renderer selection alone does not guarantee compatibility with every Minecraft
version or shader pack. `glSwapInterval` currently inherits gl4metal's no-op.

## Validation

Portable lifecycle and Mach-O validation tests:

```sh
cmake -S tests -B build/bridge-tests
cmake --build build/bridge-tests
ctest --test-dir build/bridge-tests --output-on-failure
```

The bridge workflow also compiles the patched GLFW class against Hynis's bundled
LWJGL jars. Before releasing an IPA, test on a physical device: select gl4metal,
launch a world, verify the GL vendor/renderer strings identify the selected
backend, render several frames, resize/rotate, switch displays if available, and
exit. Verify `glfwGetCurrentContext()` returns the created window after binding
and zero after unbinding; check that shared-context requests return zero and a
GLFW error. Exercise image/SSBO/compute shaders with the corresponding modified
gl4metal build. Host tests and cross compilation do not exercise Metal execution.
