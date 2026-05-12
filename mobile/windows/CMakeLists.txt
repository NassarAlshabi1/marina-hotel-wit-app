cmake_minimum_required(VERSION 3.14)
project(marina_hotel_mobile LANGUAGES CXX)

set(BINARY_NAME "marina_hotel_mobile")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build type
if(NOT CMAKE_BUILD_TYPE OR CMAKE_BUILD_TYPE STREQUAL "")
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

# Compilation settings
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Application name
set(APPLICATION_NAME "Marina Hotel")

# Apply standard settings
add_definitions(-DUNICODE -D_UNICODE)

# Flutter library
add_library(flutter_windows SHARED IMPORTED)
set_target_properties(flutter_windows PROPERTIES
  IMPORTED_LOCATION "${FLUTTER_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${FLUTTER_HEADER_DIR}"
)

# Plugin libraries
foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_library(${plugin} SHARED IMPORTED)
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin})
endforeach()

# Link Flutter
target_link_libraries(${BINARY_NAME} PRIVATE flutter_windows)

# Sources
add_executable(${BINARY_NAME}
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANIFEST_DIR}/Runner.rc"
)

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}"
)

target_link_libraries(${BINARY_NAME} PRIVATE
  "dwmapi.lib"
  "imm32.lib"
  "ole32.lib"
  "oleaut32.lib"
  "shcore.lib"
  "user32.lib"
  "winmm.lib"
  "winspool.lib"
)

if(BUILD_PLUGIN_SYOLS)
  target_link_libraries(${BINARY_NAME} PRIVATE ${BUILD_PLUGIN_SYOLS})
endif()

# Install
install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${INSTALL_BUNDLE_DIR}")
