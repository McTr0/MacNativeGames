// Content-addressed, offline-built user libraries. Invalid or missing entries
// leave the runtime source compiler available; this is only a cache lookup.
#pragma once
#import "totk_shader_scope.h"

static NSDictionary<NSString *, NSString *> *totk_shader_libraries_read(NSString *root, NSString *chain) {
    if (!root.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"manifest.json"]];
    id m = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![m isKindOfClass:NSDictionary.class] || ![m[@"schema"] isEqual:@1] || ![m[@"chain"] isEqual:chain] ||
        ![m[@"options"] isKindOfClass:NSDictionary.class] || ![m[@"options"][@"math"] isEqual:@"safe"] ||
        ![m[@"options"][@"flags"] isEqual:@[@"-fmetal-math-mode=safe"]] ||
        ![m[@"options"][@"target"] isEqual:@"compiler-default"] ||
        ![m[@"compiler_identity"] isKindOfClass:NSDictionary.class] ||
        ![m[@"compiler_identity"][@"platform"] isEqual:@"darwin"] ||
        !totk_shader_scope_hex(m[@"directory"], 64) || ![m[@"libraries"] isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary<NSString *, NSString *> *paths = [NSMutableDictionary dictionary];
    NSString *directory = m[@"directory"];
    for (id digest in m[@"libraries"]) {
        if (!totk_shader_scope_hex(digest, 64)) return nil;
        NSString *relative = [NSString stringWithFormat:@"%@/%@.metallib", directory, digest];
        if (![m[@"libraries"][digest] isEqual:relative]) return nil;
        paths[digest] = [root stringByAppendingPathComponent:relative];
    }
    return [paths copy];
}
