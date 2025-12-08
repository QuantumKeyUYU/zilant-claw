cmake_minimum_required(VERSION 3.14)

set(BINARY_NAME "digital_defender")
set(APPLICATION_ID "digital_defender")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(${BINARY_NAME}
  main.cpp
  flutter_window.cpp
  flutter_window.h
  win32_window.cpp
  win32_window.h
  utils.cpp
  utils.h
)

target_link_libraries(${BINARY_NAME} PRIVATE flutter)

if (MSVC)
  target_compile_definitions(${BINARY_NAME} PRIVATE "UNICODE" "_UNICODE")
endif()
