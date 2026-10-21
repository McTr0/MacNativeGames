// Exercise the production archive writer with a synthetic Metal archive.
// Only a private fixture is accessed; no Metal device is created.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static NSString *fixture, *cache_root, *builder_dir, *other_dir;
static unsigned cache_queries;
static BOOL fail_write;
static size_t fixture_confstr(int name, char *buf, size_t size) {
    (void)name; cache_queries++;
    const char *path = cache_root.fileSystemRepresentation;
    if (buf && size) strlcpy(buf, path, size);
    return strlen(path) + 1;
}
#define confstr fixture_confstr
static void fixture_log(const char *format, ...) { (void)format; }
#define MLOG(...) fixture_log(__VA_ARGS__)
#include "fixture_pipeline_archive.h"
#undef confstr
NSString *totk_rt_dir(void) { return [fixture stringByAppendingPathComponent:@"translation"]; }
static int par_game_idle(void) { return 0; }

@interface FixtureArchive : NSObject
@end
@implementation FixtureArchive
- (BOOL)addComputePipelineFunctionsWithDescriptor:(id)descriptor error:(NSError **)error {
    (void)descriptor; (void)error;
    if (mkdir(builder_dir.fileSystemRepresentation, 0700)) return NO;
    // A second process creates a same-prefix directory during our archive write.
    const char *directory = other_dir.fileSystemRepresentation;
    const char *marker = [other_dir stringByAppendingPathComponent:@"sentinel"].fileSystemRepresentation;
    pid_t child = fork();
    if (child == 0) {
        if (mkdir(directory, 0700)) _exit(1);
        int fd = open(marker, O_CREAT | O_EXCL | O_WRONLY, 0600);
        if (fd < 0) _exit(2);
        ssize_t n = write(fd, "other-process", 13); close(fd); _exit(n == 13 ? 0 : 3);
    }
    if (child < 0) return NO;
    int status = 0;
    return waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
- (BOOL)serializeToURL:(NSURL *)url error:(NSError **)error {
    BOOL written = [@"synthetic archive" writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:error];
    return written && !fail_write;   // Failure leaves a partial .tmp for the production writer to remove.
}
@end
@interface FixtureDevice : NSObject
- (id<MTLBinaryArchive>)newBinaryArchiveWithDescriptor:(id)descriptor error:(NSError **)error;
@end
@implementation FixtureDevice
- (id<MTLBinaryArchive>)newBinaryArchiveWithDescriptor:(id)descriptor error:(NSError **)error {
    (void)descriptor; (void)error; return (id<MTLBinaryArchive>)[FixtureArchive new];
}
@end

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 3) return 2;
    fixture = @(argv[1]); fail_write = !strcmp(argv[2], "fail");
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *shared = [fixture stringByAppendingPathComponent:@"shared/com.apple.gpuarchiver"];
    cache_root = [fixture stringByAppendingPathComponent:TEST_PRIVATE_POLICY ? @"private" : @"shared"];
    NSString *builder_parent = [cache_root stringByAppendingPathComponent:@"com.apple.gpuarchiver"];
    NSString *existing = [builder_parent stringByAppendingPathComponent:@"gpuarchiver-existing"];
    NSString *foreign_existing = [shared stringByAppendingPathComponent:@"gpuarchiver-foreign-existing"];
    builder_dir = [builder_parent stringByAppendingPathComponent:@"gpuarchiver-own-new"];
    other_dir = [shared stringByAppendingPathComponent:@"gpuarchiver-foreign-new"];
    for (NSString *path in @[existing, foreign_existing, par_dir()])
        if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]) return 3;
    g_par_have = [NSMutableSet set]; g_par_open = [NSMutableDictionary dictionary]; g_par_on = 1;
    par_write((id<MTLDevice>)[FixtureDevice new], @"fixture-key", [NSObject new]);
    NSString *marker = [NSString stringWithContentsOfFile:[other_dir stringByAppendingPathComponent:@"sentinel"]
                                                encoding:NSUTF8StringEncoding error:nil];
    NSString *saved = [NSString stringWithContentsOfFile:par_file(@"fixture-key") encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *report = @{@"existing_preserved": @([fm fileExistsAtPath:existing]),
        @"foreign_existing_preserved": @([fm fileExistsAtPath:foreign_existing]),
        @"foreign_new_preserved": @([marker isEqualToString:@"other-process"]),
        @"builder_new_preserved": @([fm fileExistsAtPath:builder_dir]),
        @"archive_published": @([saved isEqualToString:@"synthetic archive"]),
        @"archive_indexed": @([g_par_have containsObject:@"fixture-key"]),
        @"partial_absent": @(![fm fileExistsAtPath:[par_file(@"fixture-key") stringByAppendingString:@".tmp"]]),
        @"cache_queries": @(cache_queries), @"written": @(atomic_load(&g_par_written)),
        @"write_failures": @(atomic_load(&g_par_write_failed)), @"removed": @(atomic_load(&g_par_ga_removed))};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
    puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    return 0;
} }
