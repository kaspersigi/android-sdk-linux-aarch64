# aapt2 - Android Asset Packaging Tool 2 (Linux build)
#
# Key change from upstream: removed c++_static, added pthread

# Generated protobuf C++ sources are checked in so configuring a cross build
# never executes a target-architecture program or modifies the source tree.
set(AAPT2_PROTO_SRC
    ${SRC}/base/tools/aapt2/ApkInfo.pb.cc
    ${SRC}/base/tools/aapt2/Configuration.pb.cc
    ${SRC}/base/tools/aapt2/ResourceMetadata.pb.cc
    ${SRC}/base/tools/aapt2/Resources.pb.cc
    ${SRC}/base/tools/aapt2/ResourcesInternal.pb.cc
    )


set(INCLUDES
    ${SRC}/base/tools/aapt2
    ${SRC}/protobuf/src
    ${SRC}/logging/liblog/include
    ${SRC}/expat/lib
    ${SRC}/fmtlib/include
    ${SRC}/native/include
    ${SRC}/libpng
    ${SRC}/libbase/include
    ${SRC}/base/libs/androidfw/include
    ${SRC}/base/libs/androidfw/include_pathutils
    ${SRC}/base/cmds/idmap2/libidmap2_policies/include
    ${SRC}/core/libsystem/include
    ${SRC}/core/libutils/include
    ${SRC}/googletest/googletest/include
    ${SRC}/libziparchive/include
    ${SRC}/soong/cc/libbuildversion/include
    ${SRC}/incremental_delivery/incfs/util/include
    ${SRC}/incremental_delivery/incfs/kernel-headers
    )

set(COMPILE_FLAGS
    -Wno-unused-parameter
    -Wno-missing-field-initializers
    -fno-exceptions
    -fno-rtti
    )

set(TOOL_SOURCE
    ${SRC}/base/tools/aapt2/cmd/ApkInfo.cpp
    ${SRC}/base/tools/aapt2/cmd/Command.cpp
    ${SRC}/base/tools/aapt2/cmd/Compile.cpp
    ${SRC}/base/tools/aapt2/cmd/Convert.cpp
    ${SRC}/base/tools/aapt2/cmd/Diff.cpp
    ${SRC}/base/tools/aapt2/cmd/Dump.cpp
    ${SRC}/base/tools/aapt2/cmd/Link.cpp
    ${SRC}/base/tools/aapt2/cmd/Optimize.cpp
    ${SRC}/base/tools/aapt2/cmd/Util.cpp
    )

add_library(libaapt2 STATIC
    ${SRC}/base/tools/aapt2/compile/IdAssigner.cpp
    ${SRC}/base/tools/aapt2/compile/InlineXmlFormatParser.cpp
    ${SRC}/base/tools/aapt2/compile/PseudolocaleGenerator.cpp
    ${SRC}/base/tools/aapt2/compile/Pseudolocalizer.cpp
    ${SRC}/base/tools/aapt2/compile/XmlIdCollector.cpp
    ${SRC}/base/tools/aapt2/configuration/ConfigurationParser.cpp
    ${SRC}/base/tools/aapt2/dump/DumpManifest.cpp
    ${SRC}/base/tools/aapt2/filter/AbiFilter.cpp
    ${SRC}/base/tools/aapt2/filter/ConfigFilter.cpp
    ${SRC}/base/tools/aapt2/format/Archive.cpp
    ${SRC}/base/tools/aapt2/format/Container.cpp
    ${SRC}/base/tools/aapt2/format/binary/BinaryResourceParser.cpp
    ${SRC}/base/tools/aapt2/format/binary/ResChunkPullParser.cpp
    ${SRC}/base/tools/aapt2/format/binary/ResEntryWriter.cpp
    ${SRC}/base/tools/aapt2/format/binary/TableFlattener.cpp
    ${SRC}/base/tools/aapt2/format/binary/XmlFlattener.cpp
    ${SRC}/base/tools/aapt2/format/proto/ProtoDeserialize.cpp
    ${SRC}/base/tools/aapt2/format/proto/ProtoSerialize.cpp
    ${SRC}/base/tools/aapt2/io/File.cpp
    ${SRC}/base/tools/aapt2/io/FileSystem.cpp
    ${SRC}/base/tools/aapt2/io/StringStream.cpp
    ${SRC}/base/tools/aapt2/io/Util.cpp
    ${SRC}/base/tools/aapt2/io/ZipArchive.cpp
    ${SRC}/base/tools/aapt2/link/AutoVersioner.cpp
    ${SRC}/base/tools/aapt2/link/FeatureFlagsFilter.cpp
    ${SRC}/base/tools/aapt2/link/FlagDisabledResourceRemover.cpp
    ${SRC}/base/tools/aapt2/link/FlaggedXmlVersioner.cpp
    ${SRC}/base/tools/aapt2/link/ManifestFixer.cpp
    ${SRC}/base/tools/aapt2/link/NoDefaultResourceRemover.cpp
    ${SRC}/base/tools/aapt2/link/PrivateAttributeMover.cpp
    ${SRC}/base/tools/aapt2/link/ReferenceLinker.cpp
    ${SRC}/base/tools/aapt2/link/ResourceExcluder.cpp
    ${SRC}/base/tools/aapt2/link/TableMerger.cpp
    ${SRC}/base/tools/aapt2/link/XmlCompatVersioner.cpp
    ${SRC}/base/tools/aapt2/link/XmlNamespaceRemover.cpp
    ${SRC}/base/tools/aapt2/link/XmlReferenceLinker.cpp
    ${SRC}/base/tools/aapt2/optimize/MultiApkGenerator.cpp
    ${SRC}/base/tools/aapt2/optimize/ResourceDeduper.cpp
    ${SRC}/base/tools/aapt2/optimize/ResourceFilter.cpp
    ${SRC}/base/tools/aapt2/optimize/Obfuscator.cpp
    ${SRC}/base/tools/aapt2/optimize/VersionCollapser.cpp
    ${SRC}/base/tools/aapt2/process/ProductFilter.cpp
    ${SRC}/base/tools/aapt2/process/SymbolTable.cpp
    ${SRC}/base/tools/aapt2/split/TableSplitter.cpp
    ${SRC}/base/tools/aapt2/text/Printer.cpp
    ${SRC}/base/tools/aapt2/text/Unicode.cpp
    ${SRC}/base/tools/aapt2/text/Utf8Iterator.cpp
    ${SRC}/base/tools/aapt2/util/Files.cpp
    ${SRC}/base/tools/aapt2/util/Util.cpp
    ${SRC}/base/tools/aapt2/Debug.cpp
    ${SRC}/base/tools/aapt2/DominatorTree.cpp
    ${SRC}/base/tools/aapt2/java/AnnotationProcessor.cpp
    ${SRC}/base/tools/aapt2/java/ClassDefinition.cpp
    ${SRC}/base/tools/aapt2/java/JavaClassGenerator.cpp
    ${SRC}/base/tools/aapt2/java/ManifestClassGenerator.cpp
    ${SRC}/base/tools/aapt2/java/ProguardRules.cpp
    ${SRC}/base/tools/aapt2/LoadedApk.cpp
    ${SRC}/base/tools/aapt2/Resource.cpp
    ${SRC}/base/tools/aapt2/ResourceParser.cpp
    ${SRC}/base/tools/aapt2/ResourceTable.cpp
    ${SRC}/base/tools/aapt2/ResourceUtils.cpp
    ${SRC}/base/tools/aapt2/ResourceValues.cpp
    ${SRC}/base/tools/aapt2/SdkConstants.cpp
    ${SRC}/base/tools/aapt2/trace/TraceBuffer.cpp
    ${SRC}/base/tools/aapt2/xml/XmlActionExecutor.cpp
    ${SRC}/base/tools/aapt2/xml/XmlDom.cpp
    ${SRC}/base/tools/aapt2/xml/XmlPullParser.cpp
    ${SRC}/base/tools/aapt2/xml/XmlUtil.cpp
    ${SRC}/base/tools/aapt2/ApkInfo.proto
    ${SRC}/base/tools/aapt2/Configuration.proto
    ${SRC}/base/tools/aapt2/Resources.proto
    ${SRC}/base/tools/aapt2/ResourceMetadata.proto
    ${SRC}/base/tools/aapt2/ResourcesInternal.proto
    ${SRC}/base/tools/aapt2/ValueTransformer.cpp
    ${AAPT2_PROTO_SRC} ${AAPT2_PROTO_HDRS}
    )
target_include_directories(libaapt2 PRIVATE ${INCLUDES})
target_compile_options(libaapt2 PRIVATE ${COMPILE_FLAGS})

# build the executable file aapt2
add_executable(aapt2
    ${SRC}/base/tools/aapt2/Main.cpp
    ${TOOL_SOURCE}
    )
target_include_directories(aapt2 PRIVATE ${INCLUDES})
target_compile_options(aapt2 PRIVATE ${COMPILE_FLAGS})
target_link_libraries(aapt2
    libaapt2
    libandroidfw
    libincfs
    libselinux
    libsepol
    libpackagelistparser
    libutils
    libcutils
    libziparchive
    libbase
    libbuildversion
    liblog
    protobuf::libprotoc
    protobuf::libprotobuf
    expat
    crypto
    ssl
    pcre2-8
    png_static
    Threads::Threads
    dl
    z
    )
