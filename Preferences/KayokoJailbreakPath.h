//
//  KayokoJailbreakPath.h
//  Kayoko
//
//  越狱根路径解析的唯一入口：jbroot()。
//
//  roothide 方案下 jbroot() 由 <roothide.h>（libroothide）提供；rootless / rootful 方案改用
//  Theos 自带 libroot 的 ROOT_PATH_NS()，它在运行时探测越狱根（rootful 下原样返回）。
//  因此除本文件外，任何 target 都不应再直接 #import <roothide.h>——那样会强制整个项目
//  依赖 roothide 工具链，连 rootless 包也打不出来。
//
//  放在 Preferences/ 是因为 Core / Helper / Preferences / Updater 四个 target 都已把该目录
//  加进头文件搜索路径（各 Makefile 的 -I../Preferences 与 project.yml 的 HEADER_SEARCH_PATHS），
//  与 KayokoPreferenceKeys.h 等跨 target 头文件一致，无需再改构建配置。
//

#import <Foundation/Foundation.h>

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && THEOS_PACKAGE_SCHEME_ROOTHIDE

#import <roothide.h>

#else

#import <rootless.h>

static inline NSString *jbroot(NSString *path) {
    return ROOT_PATH_NS(path);
}

#endif
