cmake_minimum_required(VERSION 3.20)
project(niri-settings LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
find_package(Qt6 REQUIRED COMPONENTS Widgets Network)
add_executable(niri-settings
  src/main.cpp src/common.h src/common.cpp
  src/appearance.cpp src/power.cpp src/tuning.cpp src/misc.cpp)
target_link_libraries(niri-settings PRIVATE Qt6::Widgets Qt6::Network)
