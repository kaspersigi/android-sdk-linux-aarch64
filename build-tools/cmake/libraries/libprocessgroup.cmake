# libprocessgroup

add_library(libprocessgroup STATIC
    ${SRC}/core/libprocessgroup/cgroup_map.cpp
    ${SRC}/core/libprocessgroup/processgroup.cpp
    ${SRC}/core/libprocessgroup/sched_policy.cpp
    ${SRC}/core/libprocessgroup/task_profiles.cpp
    ${SRC}/core/libprocessgroup/util/cgroup_controller.cpp
    ${SRC}/core/libprocessgroup/util/cgroup_descriptor.cpp
    ${SRC}/core/libprocessgroup/util/util.cpp
    )

target_include_directories(libprocessgroup PRIVATE
    ${SRC}/core/libprocessgroup/include
    ${SRC}/core/libprocessgroup/util/include
    ${SRC}/libbase/include
    ${SRC}/core/libcutils/include
    ${SRC}/jsoncpp/include
    )
target_include_directories(libprocessgroup PRIVATE
    ${SRC}/core/libprocessgroup
    )
