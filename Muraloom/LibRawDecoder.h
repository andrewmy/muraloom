#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LibRawDecoder : NSObject

/// True when the app is built with LibRaw headers available and LibRaw enabled in build settings.
+ (BOOL)isAvailable;

/// Decodes RAW image bytes (ARW/DNG/etc) and returns a wallpaper-safe JPEG, optionally downscaled.
+ (nullable NSData *)decodeRAWToJPEGData:(NSData *)rawData
                            maxDimension:(NSInteger)maxDimension
                                 quality:(double)quality
                                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

