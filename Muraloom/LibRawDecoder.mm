#import "LibRawDecoder.h"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#if __has_include(<libraw/libraw.h>) && defined(LIBRAW_ENABLED)
  #import <libraw/libraw.h>
  #include <memory>
  #define GPH_LIBRAW_AVAILABLE 1
#else
  #define GPH_LIBRAW_AVAILABLE 0
#endif

static NSError *GPHMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"LibRawDecoder"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Unknown error." }];
}

static CGImageRef _Nullable GPHCreateCGImageFromInterleavedBytesNoCopy(
    const UInt8 *bytes,
    size_t byteCount,
    size_t width,
    size_t height,
    size_t bytesPerRow,
    size_t bitsPerPixel,
    CGBitmapInfo bitmapInfo
) {
    if (bytes == NULL || byteCount == 0 || width == 0 || height == 0 || bytesPerRow == 0) { return nil; }
    const size_t required = bytesPerRow * height;
    if (byteCount < required) { return nil; }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) { return nil; }

    // Important: this does not copy `bytes`. Caller must ensure the memory stays valid for the lifetime
    // of the CGImage use (we keep the LibRaw buffer alive until after encoding).
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bytes, required, NULL);
    if (provider == NULL) {
        CGColorSpaceRelease(colorSpace);
        return nil;
    }

    CGImageRef image = CGImageCreate(
        width,
        height,
        8,
        bitsPerPixel,
        bytesPerRow,
        colorSpace,
        bitmapInfo,
        provider,
        NULL,
        true,
        kCGRenderingIntentDefault
    );

    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return image;
}

static CGImageRef _Nullable GPHDownscaleImage(CGImageRef image, NSInteger maxDimension) {
    if (image == NULL) { return nil; }
    const size_t srcW = (size_t)CGImageGetWidth(image);
    const size_t srcH = (size_t)CGImageGetHeight(image);
    if (srcW == 0 || srcH == 0) { return nil; }

    const NSInteger maxDim = MAX(1, maxDimension);
    const size_t srcMax = MAX(srcW, srcH);
    if ((NSInteger)srcMax <= maxDim) {
        CGImageRetain(image);
        return image;
    }

    const double scale = (double)maxDim / (double)srcMax;
    const size_t dstW = (size_t)MAX(1, (NSInteger)llround((double)srcW * scale));
    const size_t dstH = (size_t)MAX(1, (NSInteger)llround((double)srcH * scale));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) { return nil; }

    const size_t bytesPerRow = dstW * 4;
    CGContextRef ctx = CGBitmapContextCreate(
        NULL,
        dstW,
        dstH,
        8,
        bytesPerRow,
        colorSpace,
        (CGBitmapInfo)kCGImageAlphaNoneSkipLast | (CGBitmapInfo)kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);
    if (ctx == NULL) { return nil; }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)dstW, (CGFloat)dstH), image);
    CGImageRef scaled = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return scaled;
}

static NSData * _Nullable GPHEncodeJPEG(CGImageRef image, double quality, NSError **error) {
    if (image == NULL) {
        if (error) { *error = GPHMakeError(3, @"Image resize failed."); }
        return nil;
    }

    NSMutableData *out = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)out, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
    if (dest == NULL) {
        if (error) { *error = GPHMakeError(4, @"JPEG encoder setup failed."); }
        return nil;
    }

    const double clamped = MIN(1.0, MAX(0.0, quality));
    NSDictionary *props = @{ (__bridge NSString *)kCGImageDestinationLossyCompressionQuality : @(clamped) };
    CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)props);
    const bool ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);

    if (!ok) {
        if (error) { *error = GPHMakeError(5, @"JPEG encode failed."); }
        return nil;
    }

    return out;
}

@implementation LibRawDecoder

+ (BOOL)isAvailable {
    return (BOOL)GPH_LIBRAW_AVAILABLE;
}

+ (NSData *)decodeRAWToJPEGData:(NSData *)rawData
                   maxDimension:(NSInteger)maxDimension
                        quality:(double)quality
                          error:(NSError **)error {
#if !GPH_LIBRAW_AVAILABLE
    if (error) {
        *error = GPHMakeError(
            1,
            @"RAW decoding is not enabled in this build. See LibRaw.xcconfig.example for setup."
        );
    }
    return nil;
#else
    @autoreleasepool {
        if (rawData.length == 0) {
            if (error) { *error = GPHMakeError(2, @"Invalid RAW data."); }
            return nil;
        }

        // LibRaw's open_buffer takes a non-const pointer. Use a writable copy so we're not relying on the
        // mutability/ownership details of bridged Swift `Data` buffers.
        NSMutableData *mutableData = [rawData mutableCopy];
        if (mutableData == nil || mutableData.length == 0) {
            if (error) { *error = GPHMakeError(2, @"Invalid RAW data."); }
            return nil;
        }

        // LibRaw is a large C++ object; keep it off the stack to avoid stack overflows on some systems.
        auto processor = std::make_unique<LibRaw>();
        libraw_output_params_t *params = &processor->imgdata.params;
        params->output_bps = 8;
        params->output_color = 1;     // sRGB
        params->use_camera_wb = 1;
        params->use_auto_wb = 0;
        params->no_auto_bright = 0;
        params->user_qual = 3;        // AHD
        params->user_flip = -1;       // auto
        params->use_fuji_rotate = 1;

        int ret = processor->open_buffer((void *)mutableData.mutableBytes, (size_t)mutableData.length);
        if (ret != LIBRAW_SUCCESS) {
            if (error) {
                *error = GPHMakeError(10, [NSString stringWithFormat:@"RAW open failed (%s).", libraw_strerror(ret)]);
            }
            return nil;
        }

        ret = processor->unpack();
        if (ret != LIBRAW_SUCCESS) {
            if (error) {
                *error = GPHMakeError(11, [NSString stringWithFormat:@"RAW unpack failed (%s).", libraw_strerror(ret)]);
            }
            processor->recycle();
            return nil;
        }

        ret = processor->dcraw_process();
        if (ret != LIBRAW_SUCCESS) {
            if (error) {
                *error = GPHMakeError(12, [NSString stringWithFormat:@"RAW process failed (%s).", libraw_strerror(ret)]);
            }
            processor->recycle();
            return nil;
        }

        int errCode = 0;
        libraw_processed_image_t *img = processor->dcraw_make_mem_image(&errCode);
        if (img == NULL) {
            if (error) {
                *error = GPHMakeError(13, [NSString stringWithFormat:@"RAW render failed (%s).", libraw_strerror(errCode)]);
            }
            processor->recycle();
            return nil;
        }

        NSData *result = nil;

        if (img->type == LIBRAW_IMAGE_JPEG) {
            // Some cameras may yield an already-compressed JPEG; still run it through downscale+encode for consistency.
            NSData *jpegBytes = [NSData dataWithBytes:img->data length:img->data_size];
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)jpegBytes, NULL);
            if (source) {
                CGImageRef cg = CGImageSourceCreateImageAtIndex(source, 0, NULL);
                CFRelease(source);
                if (cg) {
                    CGImageRef scaled = GPHDownscaleImage(cg, maxDimension);
                    CGImageRelease(cg);
                    NSError *encodeError = nil;
                    NSData *encoded = GPHEncodeJPEG(scaled, quality, &encodeError);
                    if (scaled) { CGImageRelease(scaled); }
                    result = encoded;
                    if (!result && error) { *error = encodeError; }
                }
            }
            if (!result && error && *error == nil) {
                *error = GPHMakeError(14, @"RAW JPEG decode failed.");
            }
        } else if (img->type == LIBRAW_IMAGE_BITMAP && img->bits == 8) {
            const size_t w = (size_t)img->width;
            const size_t h = (size_t)img->height;
            const int colors = img->colors;
            const size_t pixelCount = w * h;

            if (w == 0 || h == 0 || colors < 3 || pixelCount == 0) {
                if (error) { *error = GPHMakeError(15, @"RAW bitmap had invalid dimensions."); }
            } else {
                const UInt8 *src = (const UInt8 *)img->data;
                const size_t bytesPerRow = (size_t)colors * w;

                CGImageRef cg = NULL;
                if (colors == 3) {
                    cg = GPHCreateCGImageFromInterleavedBytesNoCopy(
                        src,
                        (size_t)img->data_size,
                        w,
                        h,
                        bytesPerRow,
                        24,
                        (CGBitmapInfo)kCGImageAlphaNone | (CGBitmapInfo)kCGBitmapByteOrderDefault
                    );
                } else if (colors == 4) {
                    cg = GPHCreateCGImageFromInterleavedBytesNoCopy(
                        src,
                        (size_t)img->data_size,
                        w,
                        h,
                        bytesPerRow,
                        32,
                        (CGBitmapInfo)kCGImageAlphaNoneSkipLast | (CGBitmapInfo)kCGBitmapByteOrderDefault
                    );
                } else {
                    if (error) { *error = GPHMakeError(19, @"RAW bitmap had unsupported color channel count."); }
                }

                if (cg) {
                    CGImageRef scaled = GPHDownscaleImage(cg, maxDimension);
                    CGImageRelease(cg);
                    NSError *encodeError = nil;
                    NSData *encoded = GPHEncodeJPEG(scaled, quality, &encodeError);
                    if (scaled) { CGImageRelease(scaled); }
                    result = encoded;
                    if (!result && error) { *error = encodeError; }
                } else if (result == nil) {
                    if (error && *error == nil) { *error = GPHMakeError(16, @"RAW bitmap decode failed."); }
                }
            }
        } else {
            if (error) {
                *error = GPHMakeError(17, [NSString stringWithFormat:@"Unsupported RAW output type (%d).", img->type]);
            }
        }

        LibRaw::dcraw_clear_mem(img);
        processor->recycle();
        return result;
    }
#endif
}

@end
