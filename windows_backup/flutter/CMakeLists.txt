cmake_minimum_required(VERSION 3.14)
set(EPHEMERAL_DIR "${CMAKE_CURRENT_LIST_DIR}/ephemeral")
include("${CMAKE_CURRENT_LIST_DIR}/generated_config.cmake")

add_library(flutter INTERFACE)

add_dependencies(flutter flutter_assemble)

add_custom_target(flutter_assemble DEPENDS
  "${EPHEMERAL_DIR}/flutter_windows.dll"
)

# Placeholder rules for generated files
add_custom_command(
  OUTPUT "${EPHEMERAL_DIR}/flutter_windows.dll"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${EPHEMERAL_DIR}"
  COMMAND ${CMAKE_COMMAND} -E touch "${EPHEMERAL_DIR}/flutter_windows.dll"
  VERBATIM
)

list(APPEND FLUTTER_LIBRARY "${EPHEMERAL_DIR}/flutter_windows.dll")
set(FLUTTER_INCLUDE_DIRS "${EPHEMERAL_DIR}/flutter_windows.dll")

