# Prefer VS Community over Build Tools when both are installed (Windows on ARM64).
# Copy to: <your_app>/windows/cmake/community_vs.cmake
# Set: CMAKE_TOOLCHAIN_FILE=<your_app>/windows/cmake/community_vs.cmake
if(NOT CMAKE_GENERATOR_INSTANCE)
  set(_VS_COMMUNITY "C:/Program Files/Microsoft Visual Studio/18/Community")
  if(EXISTS "${_VS_COMMUNITY}/VC/Auxiliary/Build/vcvarsarm64.bat")
    set(CMAKE_GENERATOR_INSTANCE "${_VS_COMMUNITY}" CACHE INTERNAL "" FORCE)
  endif()
  if(NOT CMAKE_GENERATOR_INSTANCE)
    set(_VS_COMMUNITY "C:/Program Files/Microsoft Visual Studio/2022/Community")
    if(EXISTS "${_VS_COMMUNITY}/VC/Auxiliary/Build/vcvarsarm64.bat")
      set(CMAKE_GENERATOR_INSTANCE "${_VS_COMMUNITY}" CACHE INTERNAL "" FORCE)
    endif()
  endif()
endif()
