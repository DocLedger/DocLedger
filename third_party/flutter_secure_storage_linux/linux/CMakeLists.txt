cmake_minimum_required(VERSION 3.10)
project(flutter_secure_storage_linux LANGUAGES C)

# No-op stub target to satisfy plugin cmake without building native code
add_library(flutter_secure_storage_linux_plugin SHARED stub.c)
target_sources(flutter_secure_storage_linux_plugin PRIVATE stub.c)
target_compile_definitions(flutter_secure_storage_linux_plugin PRIVATE PLUGIN_STUB=1)

