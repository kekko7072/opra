cmake_minimum_required(VERSION 3.16)
project(OpraShared)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include directories
include_directories(include)

# Source files
set(SOURCES
    src/PDFTextExtractor.cpp
    src/TextToSpeech.cpp
)

# Platform-specific source files
if(WIN32)
    list(APPEND SOURCES src/PDFTextExtractor_Windows.cpp)
    list(APPEND SOURCES src/TextToSpeech_Windows.cpp)
    
    # Windows-specific libraries
    find_library(SAPI_LIB sapi.lib)
    if(SAPI_LIB)
        target_link_libraries(OpraShared ${SAPI_LIB})
    endif()
    
elseif(APPLE)
    list(APPEND SOURCES src/PDFTextExtractor_macOS.cpp)
    list(APPEND SOURCES src/TextToSpeech_macOS.cpp)
    
    # macOS-specific frameworks
    find_library(COREFOUNDATION_LIB CoreFoundation)
    find_library(PDFKIT_LIB PDFKit)
    find_library(AVFOUNDATION_LIB AVFoundation)
    find_library(FOUNDATION_LIB Foundation)
    
    if(COREFOUNDATION_LIB)
        target_link_libraries(OpraShared ${COREFOUNDATION_LIB})
    endif()
    if(PDFKIT_LIB)
        target_link_libraries(OpraShared ${PDFKIT_LIB})
    endif()
    if(AVFOUNDATION_LIB)
        target_link_libraries(OpraShared ${AVFOUNDATION_LIB})
    endif()
    if(FOUNDATION_LIB)
        target_link_libraries(OpraShared ${FOUNDATION_LIB})
    endif()
endif()

# Create shared library
add_library(OpraShared SHARED ${SOURCES})

# Set output directory
set_target_properties(OpraShared PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

# Install targets
install(TARGETS OpraShared
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

# Install headers
install(DIRECTORY include/ DESTINATION include)