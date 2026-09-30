# libyaml 0.2.5

Pinned to upstream stable tag `0.2.5` from the [canonical repository](https://github.com/yaml/libyaml/tree/0.2.5).
License: MIT; the complete upstream notice is in LICENSE.

Downloaded archive: https://codeload.github.com/yaml/libyaml/tar.gz/refs/tags/0.2.5
Archive SHA-256: `fa240dbf262be053f3898006d502d514936c818e422afdcf33921c63bed9bf2e`.

The unmodified parser subset is vendored: include/yaml.h and src/api.c,
reader.c, scanner.c, parser.c, yaml_private.h. No emitter, loader, executable
objects, or network dependency is used. The app's tiny Sources/CChitYAML bridge
exposes parser events with their locations. Swift enforces a shallow schema,
rejects aliases/custom tags, and stops processing nesting beyond eight levels;
this also bounds nesting before libyaml's event parser proceeds further.
The schema uses YAML 1.2 core scalar resolution. The canonical writer is a
schema-specific serializer; it is not a handwritten YAML parser.

Both the Xcode target and direct compiler scripts build these C sources offline
using the local config.h version definitions (0, 2, 5, "0.2.5").
