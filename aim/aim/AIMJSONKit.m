//
//  AIMJSONKit.m
//  http://github.com/johnezang/JSONKit
//  Dual licensed under either the terms of the BSD License, or alternatively
//  under the terms of the Apache License, Version 2.0, as specified below.
//

/*
 Copyright (c) 2011, John Engelhart
 
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 * Neither the name of the Zang Industries nor the names of its
 contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/*
 Copyright 2011 John Engelhart
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/


/*
  Acknowledgments:

  The bulk of the UTF8 / UTF32 conversion and verification comes
  from ConvertUTF.[hc].  It has been modified from the original sources.

  The original sources were obtained from http://www.unicode.org/.
  However, the web site no longer seems to host the files.  Instead,
  the Unicode FAQ http://www.unicode.org/faq//utf_bom.html#gen4
  points to International Components for Unicode (ICU)
  http://site.icu-project.org/ as an example of how to write a UTF
  converter.

  The decision to use the ConvertUTF.[ch] code was made to leverage
  "proven" code.  Hopefully the local modifications are bug free.

  The code in isValidCodePoint() is derived from the ICU code in
  utf.h for the macros U_IS_UNICODE_NONCHAR and U_IS_UNICODE_CHAR.

  From the original ConvertUTF.[ch]:

 * Copyright 2001-2004 Unicode, Inc.
 * 
 * Disclaimer
 * 
 * This source code is provided as is by Unicode, Inc. No claims are
 * made as to fitness for any particular purpose. No warranties of any
 * kind are expressed or implied. The recipient agrees to determine
 * applicability of information provided. If this file has been
 * purchased on magnetic or optical media from Unicode, Inc., the
 * sole remedy for any claim will be exchange of defective media
 * within 90 days of receipt.
 * 
 * Limitations on Rights to Redistribute This Code
 * 
 * Unicode, Inc. hereby grants the right to freely use the information
 * supplied in this file in the creation of products supporting the
 * Unicode Standard, and to make copies of this file in any form
 * for internal or external distribution as long as this notice
 * remains attached.

*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include <sys/errno.h>
#include <math.h>
#include <limits.h>
#include <objc/runtime.h>

#import "AIMJSONKit.h"

//#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFNumber.h>

//#import <Foundation/Foundation.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSObjCRuntime.h>

#ifndef __has_feature
#define __has_feature(x) 0
#endif

#ifdef AIMJK_ENABLE_CF_TRANSFER_OWNERSHIP_CALLBACKS
#warning As of AIMJSONKit v1.4, AIMJK_ENABLE_CF_TRANSFER_OWNERSHIP_CALLBACKS is no longer required.  It is no longer a valid option.
#endif

#ifdef __OBJC_GC__
#error AIMJSONKit does not support Objective-C Garbage Collection
#endif

#if __has_feature(objc_arc)
#error AIMJSONKit does not support Objective-C Automatic Reference Counting (ARC)
#endif

// The following checks are really nothing more than sanity checks.
// AIMJSONKit technically has a few problems from a "strictly C99 conforming" standpoint, though they are of the pedantic nitpicking variety.
// In practice, though, for the compilers and architectures we can reasonably expect this code to be compiled for, these pedantic nitpicks aren't really a problem.
// Since we're limited as to what we can do with pre-processor #if checks, these checks are not nearly as through as they should be.

#if (UINT_MAX != 0xffffffffU) || (INT_MIN != (-0x7fffffff-1)) || (ULLONG_MAX != 0xffffffffffffffffULL) || (LLONG_MIN != (-0x7fffffffffffffffLL-1LL))
#error AIMJSONKit requires the C 'int' and 'long long' types to be 32 and 64 bits respectively.
#endif

#if !defined(__LP64__) && ((UINT_MAX != ULONG_MAX) || (INT_MAX != LONG_MAX) || (INT_MIN != LONG_MIN) || (WORD_BIT != LONG_BIT))
#error AIMJSONKit requires the C 'int' and 'long' types to be the same on 32-bit architectures.
#endif

// Cocoa / Foundation uses NS*Integer as the type for a lot of arguments.  We make sure that NS*Integer is something we are expecting and is reasonably compatible with size_t / ssize_t

#if (NSUIntegerMax != ULONG_MAX) || (NSIntegerMax != LONG_MAX) || (NSIntegerMin != LONG_MIN)
#error AIMJSONKit requires NSInteger and NSUInteger to be the same size as the C 'long' type.
#endif

#if (NSUIntegerMax != SIZE_MAX) || (NSIntegerMax != SSIZE_MAX)
#error AIMJSONKit requires NSInteger and NSUInteger to be the same size as the C 'size_t' type.
#endif


// For DJB hash.
#define AIMJK_HASH_INIT           (1402737925UL)

// Use __builtin_clz() instead of trailingBytesForUTF8[] table lookup.
#define AIMJK_FAST_TRAILING_BYTES

// AIMJK_CACHE_SLOTS must be a power of 2.  Default size is 1024 slots.
#define AIMJK_CACHE_SLOTS_BITS    (10)
#define AIMJK_CACHE_SLOTS         (1UL << AIMJK_CACHE_SLOTS_BITS)
// AIMJK_CACHE_PROBES is the number of probe attempts.
#define AIMJK_CACHE_PROBES        (4UL)
// AIMJK_INIT_CACHE_AGE must be < (1 << AGE) - 1, where AGE is sizeof(typeof(AGE)) * 8.
#define AIMJK_INIT_CACHE_AGE      (0)

// AIMJK_TOKENBUFFER_SIZE is the default stack size for the temporary buffer used to hold "non-simple" strings (i.e., contains \ escapes)
#define AIMJK_TOKENBUFFER_SIZE    (1024UL * 2UL)

// AIMJK_STACK_OBJS is the default number of spaces reserved on the stack for temporarily storing pointers to Obj-C objects before they can be transferred to a NSArray / NSDictionary.
#define AIMJK_STACK_OBJS          (1024UL * 1UL)

#define AIMJK_JSONBUFFER_SIZE     (1024UL * 4UL)
#define AIMJK_UTF8BUFFER_SIZE     (1024UL * 16UL)

#define AIMJK_ENCODE_CACHE_SLOTS  (1024UL)


#if       defined (__GNUC__) && (__GNUC__ >= 4)
#define AIMJK_ATTRIBUTES(attr, ...)        __attribute__((attr, ##__VA_ARGS__))
#define AIMJK_EXPECTED(cond, expect)       __builtin_expect((long)(cond), (expect))
#define AIMJK_EXPECT_T(cond)               AIMJK_EXPECTED(cond, 1U)
#define AIMJK_EXPECT_F(cond)               AIMJK_EXPECTED(cond, 0U)
#define AIMJK_PREFETCH(ptr)                __builtin_prefetch(ptr)
#else  // defined (__GNUC__) && (__GNUC__ >= 4) 
#define AIMJK_ATTRIBUTES(attr, ...)
#define AIMJK_EXPECTED(cond, expect)       (cond)
#define AIMJK_EXPECT_T(cond)               (cond)
#define AIMJK_EXPECT_F(cond)               (cond)
#define AIMJK_PREFETCH(ptr)
#endif // defined (__GNUC__) && (__GNUC__ >= 4) 

#define AIMJK_STATIC_INLINE                         static __inline__ AIMJK_ATTRIBUTES(always_inline)
#define AIMJK_ALIGNED(arg)                                            AIMJK_ATTRIBUTES(aligned(arg))
#define AIMJK_UNUSED_ARG                                              AIMJK_ATTRIBUTES(unused)
#define AIMJK_WARN_UNUSED                                             AIMJK_ATTRIBUTES(warn_unused_result)
#define AIMJK_WARN_UNUSED_CONST                                       AIMJK_ATTRIBUTES(warn_unused_result, const)
#define AIMJK_WARN_UNUSED_PURE                                        AIMJK_ATTRIBUTES(warn_unused_result, pure)
#define AIMJK_WARN_UNUSED_SENTINEL                                    AIMJK_ATTRIBUTES(warn_unused_result, sentinel)
#define AIMJK_NONNULL_ARGS(arg, ...)                                  AIMJK_ATTRIBUTES(nonnull(arg, ##__VA_ARGS__))
#define AIMJK_WARN_UNUSED_NONNULL_ARGS(arg, ...)                      AIMJK_ATTRIBUTES(warn_unused_result, nonnull(arg, ##__VA_ARGS__))
#define AIMJK_WARN_UNUSED_CONST_NONNULL_ARGS(arg, ...)                AIMJK_ATTRIBUTES(warn_unused_result, const, nonnull(arg, ##__VA_ARGS__))
#define AIMJK_WARN_UNUSED_PURE_NONNULL_ARGS(arg, ...)                 AIMJK_ATTRIBUTES(warn_unused_result, pure, nonnull(arg, ##__VA_ARGS__))

#if       defined (__GNUC__) && (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)
#define AIMJK_ALLOC_SIZE_NON_NULL_ARGS_WARN_UNUSED(as, nn, ...) AIMJK_ATTRIBUTES(warn_unused_result, nonnull(nn, ##__VA_ARGS__), alloc_size(as))
#else  // defined (__GNUC__) && (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)
#define AIMJK_ALLOC_SIZE_NON_NULL_ARGS_WARN_UNUSED(as, nn, ...) AIMJK_ATTRIBUTES(warn_unused_result, nonnull(nn, ##__VA_ARGS__))
#endif // defined (__GNUC__) && (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)


@class AIMJKArray, AIMJKDictionaryEnumerator, AIMJKDictionary;

enum {
  AIMJSONNumberStateStart                 = 0,
  AIMJSONNumberStateFinished              = 1,
  AIMJSONNumberStateError                 = 2,
  AIMJSONNumberStateWholeNumberStart      = 3,
  AIMJSONNumberStateWholeNumberMinus      = 4,
  AIMJSONNumberStateWholeNumberZero       = 5,
  AIMJSONNumberStateWholeNumber           = 6,
  AIMJSONNumberStatePeriod                = 7,
  AIMJSONNumberStateFractionalNumberStart = 8,
  AIMJSONNumberStateFractionalNumber      = 9,
  AIMJSONNumberStateExponentStart         = 10,
  AIMJSONNumberStateExponentPlusMinus     = 11,
  AIMJSONNumberStateExponent              = 12,
};

enum {
  AIMJSONStringStateStart                           = 0,
  AIMJSONStringStateParsing                         = 1,
  AIMJSONStringStateFinished                        = 2,
  AIMJSONStringStateError                           = 3,
  AIMJSONStringStateEscape                          = 4,
  AIMJSONStringStateEscapedUnicode1                 = 5,
  AIMJSONStringStateEscapedUnicode2                 = 6,
  AIMJSONStringStateEscapedUnicode3                 = 7,
  AIMJSONStringStateEscapedUnicode4                 = 8,
  AIMJSONStringStateEscapedUnicodeSurrogate1        = 9,
  AIMJSONStringStateEscapedUnicodeSurrogate2        = 10,
  AIMJSONStringStateEscapedUnicodeSurrogate3        = 11,
  AIMJSONStringStateEscapedUnicodeSurrogate4        = 12,
  AIMJSONStringStateEscapedNeedEscapeForSurrogate   = 13,
  AIMJSONStringStateEscapedNeedEscapedUForSurrogate = 14,
};

enum {
  AIMJKParseAcceptValue      = (1 << 0),
  AIMJKParseAcceptComma      = (1 << 1),
  AIMJKParseAcceptEnd        = (1 << 2),
  AIMJKParseAcceptValueOrEnd = (AIMJKParseAcceptValue | AIMJKParseAcceptEnd),
  AIMJKParseAcceptCommaOrEnd = (AIMJKParseAcceptComma | AIMJKParseAcceptEnd),
};

enum {
  AIMJKClassUnknown    = 0,
  AIMJKClassString     = 1,
  AIMJKClassNumber     = 2,
  AIMJKClassArray      = 3,
  AIMJKClassDictionary = 4,
  AIMJKClassNull       = 5,
};

enum {
  AIMJKManagedBufferOnStack        = 1,
  AIMJKManagedBufferOnHeap         = 2,
  AIMJKManagedBufferLocationMask   = (0x3),
  AIMJKManagedBufferLocationShift  = (0),
  
  AIMJKManagedBufferMustFree       = (1 << 2),
};
typedef AIMJKFlags AIMJKManagedBufferFlags;

enum {
  AIMJKObjectStackOnStack        = 1,
  AIMJKObjectStackOnHeap         = 2,
  AIMJKObjectStackLocationMask   = (0x3),
  AIMJKObjectStackLocationShift  = (0),
  
  AIMJKObjectStackMustFree       = (1 << 2),
};
typedef AIMJKFlags AIMJKObjectStackFlags;

enum {
  AIMJKTokenTypeInvalid     = 0,
  AIMJKTokenTypeNumber      = 1,
  AIMJKTokenTypeString      = 2,
  AIMJKTokenTypeObjectBegin = 3,
  AIMJKTokenTypeObjectEnd   = 4,
  AIMJKTokenTypeArrayBegin  = 5,
  AIMJKTokenTypeArrayEnd    = 6,
  AIMJKTokenTypeSeparator   = 7,
  AIMJKTokenTypeComma       = 8,
  AIMJKTokenTypeTrue        = 9,
  AIMJKTokenTypeFalse       = 10,
  AIMJKTokenTypeNull        = 11,
  AIMJKTokenTypeWhiteSpace  = 12,
};
typedef NSUInteger AIMJKTokenType;

// These are prime numbers to assist with hash slot probing.
enum {
  AIMJKValueTypeNone             = 0,
  AIMJKValueTypeString           = 5,
  AIMJKValueTypeLongLong         = 7,
  AIMJKValueTypeUnsignedLongLong = 11,
  AIMJKValueTypeDouble           = 13,
};
typedef NSUInteger AIMJKValueType;

enum {
  AIMJKEncodeOptionAsData              = 1,
  AIMJKEncodeOptionAsString            = 2,
  AIMJKEncodeOptionAsTypeMask          = 0x7,
  AIMJKEncodeOptionCollectionObj       = (1 << 3),
  AIMJKEncodeOptionStringObj           = (1 << 4),
  AIMJKEncodeOptionStringObjTrimQuotes = (1 << 5),
  
};
typedef NSUInteger AIMJKEncodeOptionType;

typedef NSUInteger AIMJKHash;

typedef struct AIMJKTokenCacheItem  AIMJKTokenCacheItem;
typedef struct AIMJKTokenCache      AIMJKTokenCache;
typedef struct AIMJKTokenValue      AIMJKTokenValue;
typedef struct AIMJKParseToken      AIMJKParseToken;
typedef struct AIMJKPtrRange        AIMJKPtrRange;
typedef struct AIMJKObjectStack     AIMJKObjectStack;
typedef struct AIMJKBuffer          AIMJKBuffer;
typedef struct AIMJKConstBuffer     AIMJKConstBuffer;
typedef struct AIMJKConstPtrRange   AIMJKConstPtrRange;
typedef struct AIMJKRange           AIMJKRange;
typedef struct AIMJKManagedBuffer   AIMJKManagedBuffer;
typedef struct AIMJKFastClassLookup AIMJKFastClassLookup;
typedef struct AIMJKEncodeCache     AIMJKEncodeCache;
typedef struct AIMJKEncodeState     AIMJKEncodeState;
typedef struct AIMJKObjCImpCache    AIMJKObjCImpCache;
typedef struct AIMJKHashTableEntry  AIMJKHashTableEntry;

typedef id (*NSNumberAllocImp)(id receiver, SEL selector);
typedef id (*NSNumberInitWithUnsignedLongLongImp)(id receiver, SEL selector, unsigned long long value);
typedef id (*AIMJKClassFormatterIMP)(id receiver, SEL selector, id object);
#ifdef __BLOCKS__
typedef id (^AIMJKClassFormatterBlock)(id formatObject);
#endif


struct AIMJKPtrRange {
  unsigned char *ptr;
  size_t         length;
};

struct AIMJKConstPtrRange {
  const unsigned char *ptr;
  size_t               length;
};

struct AIMJKRange {
  size_t location, length;
};

struct AIMJKManagedBuffer {
  AIMJKPtrRange           bytes;
  AIMJKManagedBufferFlags flags;
  size_t               roundSizeUpToMultipleOf;
};

struct AIMJKObjectStack {
  void               **objects, **keys;
  CFHashCode          *cfHashes;
  size_t               count, index, roundSizeUpToMultipleOf;
  AIMJKObjectStackFlags   flags;
};

struct AIMJKBuffer {
  AIMJKPtrRange bytes;
};

struct AIMJKConstBuffer {
  AIMJKConstPtrRange bytes;
};

struct AIMJKTokenValue {
  AIMJKConstPtrRange   ptrRange;
  AIMJKValueType       type;
  AIMJKHash            hash;
  union {
    long long          longLongValue;
    unsigned long long unsignedLongLongValue;
    double             doubleValue;
  } number;
  AIMJKTokenCacheItem *cacheItem;
};

struct AIMJKParseToken {
  AIMJKConstPtrRange tokenPtrRange;
  AIMJKTokenType     type;
  AIMJKTokenValue    value;
  AIMJKManagedBuffer tokenBuffer;
};

struct AIMJKTokenCacheItem {
  void          *object;
  AIMJKHash         hash;
  CFHashCode     cfHash;
  size_t         size;
  unsigned char *bytes;
  AIMJKValueType    type;
};

struct AIMJKTokenCache {
  AIMJKTokenCacheItem *items;
  size_t            count;
  unsigned int      prng_lfsr;
  unsigned char     age[AIMJK_CACHE_SLOTS];
};

struct AIMJKObjCImpCache {
  Class                               NSNumberClass;
  NSNumberAllocImp                    NSNumberAlloc;
  NSNumberInitWithUnsignedLongLongImp NSNumberInitWithUnsignedLongLong;
};

struct AIMJKParseState {
  AIMJKParseOptionFlags  parseOptionFlags;
  AIMJKConstBuffer       stringBuffer;
  size_t              atIndex, lineNumber, lineStartIndex;
  size_t              prev_atIndex, prev_lineNumber, prev_lineStartIndex;
  AIMJKParseToken        token;
  AIMJKObjectStack       objectStack;
  AIMJKTokenCache        cache;
  AIMJKObjCImpCache      objCImpCache;
  NSError            *error;
  int                 errorIsPrev;
  BOOL                mutableCollections;
};

struct AIMJKFastClassLookup {
  void *stringClass;
  void *numberClass;
  void *arrayClass;
  void *dictionaryClass;
  void *nullClass;
};

struct AIMJKEncodeCache {
  id object;
  size_t offset;
  size_t length;
};

struct AIMJKEncodeState {
  AIMJKManagedBuffer         utf8ConversionBuffer;
  AIMJKManagedBuffer         stringBuffer;
  size_t                  atIndex;
  AIMJKFastClassLookup       fastClassLookup;
  AIMJKEncodeCache           cache[AIMJK_ENCODE_CACHE_SLOTS];
  AIMJKSerializeOptionFlags  serializeOptionFlags;
  AIMJKEncodeOptionType      encodeOption;
  size_t                  depth;
  NSError                *error;
  id                      classFormatterDelegate;
  SEL                     classFormatterSelector;
  AIMJKClassFormatterIMP     classFormatterIMP;
#ifdef __BLOCKS__
  AIMJKClassFormatterBlock   classFormatterBlock;
#endif
};

// This is a AIMJSONKit private class.
@interface AIMJKSerializer : NSObject {
  AIMJKEncodeState *encodeState;
}

#ifdef __BLOCKS__
#define AIMJKSERIALIZER_BLOCKS_PROTO id(^)(id object)
#else
#define AIMJKSERIALIZER_BLOCKS_PROTO id
#endif

+ (id)serializeObject:(id)object options:(AIMJKSerializeOptionFlags)optionFlags encodeOption:(AIMJKEncodeOptionType)encodeOption block:(AIMJKSERIALIZER_BLOCKS_PROTO)block delegate:(id)delegate selector:(SEL)selector error:(NSError **)error;
- (id)serializeObject:(id)object options:(AIMJKSerializeOptionFlags)optionFlags encodeOption:(AIMJKEncodeOptionType)encodeOption block:(AIMJKSERIALIZER_BLOCKS_PROTO)block delegate:(id)delegate selector:(SEL)selector error:(NSError **)error;
- (void)releaseState;

@end

struct AIMJKHashTableEntry {
  NSUInteger keyHash;
  id key, object;
};


typedef uint32_t UTF32; /* at least 32 bits */
typedef uint16_t UTF16; /* at least 16 bits */
typedef uint8_t  UTF8;  /* typically 8 bits */

typedef enum {
  conversionOK,           /* conversion successful */
  sourceExhausted,        /* partial character in source, but hit end */
  targetExhausted,        /* insuff. room in target for conversion */
  sourceIllegal           /* source sequence is illegal/malformed */
} ConversionResult;

#define UNI_REPLACEMENT_CHAR (UTF32)0x0000FFFD
#define UNI_MAX_BMP          (UTF32)0x0000FFFF
#define UNI_MAX_UTF16        (UTF32)0x0010FFFF
#define UNI_MAX_UTF32        (UTF32)0x7FFFFFFF
#define UNI_MAX_LEGAL_UTF32  (UTF32)0x0010FFFF
#define UNI_SUR_HIGH_START   (UTF32)0xD800
#define UNI_SUR_HIGH_END     (UTF32)0xDBFF
#define UNI_SUR_LOW_START    (UTF32)0xDC00
#define UNI_SUR_LOW_END      (UTF32)0xDFFF


#if !defined(AIMJK_FAST_TRAILING_BYTES)
static const char trailingBytesForUTF8[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
};
#endif

static const UTF32 offsetsFromUTF8[6] = { 0x00000000UL, 0x00003080UL, 0x000E2080UL, 0x03C82080UL, 0xFA082080UL, 0x82082080UL };
static const UTF8  firstByteMark[7]   = { 0x00, 0x00, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC };

#define AIMJK_AT_STRING_PTR(x)  (&((x)->stringBuffer.bytes.ptr[(x)->atIndex]))
#define AIMJK_END_STRING_PTR(x) (&((x)->stringBuffer.bytes.ptr[(x)->stringBuffer.bytes.length]))


static AIMJKArray          *_JKArrayCreate(id *objects, NSUInteger count, BOOL mutableCollection);
static void              _JKArrayInsertObjectAtIndex(AIMJKArray *array, id newObject, NSUInteger objectIndex);
static void              _JKArrayReplaceObjectAtIndexWithObject(AIMJKArray *array, NSUInteger objectIndex, id newObject);
static void              _JKArrayRemoveObjectAtIndex(AIMJKArray *array, NSUInteger objectIndex);


static NSUInteger        _JKDictionaryCapacityForCount(NSUInteger count);
static AIMJKDictionary     *_JKDictionaryCreate(id *keys, NSUInteger *keyHashes, id *objects, NSUInteger count, BOOL mutableCollection);
static AIMJKHashTableEntry *_JKDictionaryHashEntry(AIMJKDictionary *dictionary);
static NSUInteger        _JKDictionaryCapacity(AIMJKDictionary *dictionary);
static void              _JKDictionaryResizeIfNeccessary(AIMJKDictionary *dictionary);
static void              _JKDictionaryRemoveObjectWithEntry(AIMJKDictionary *dictionary, AIMJKHashTableEntry *entry);
static void              _JKDictionaryAddObject(AIMJKDictionary *dictionary, NSUInteger keyHash, id key, id object);
static AIMJKHashTableEntry *_JKDictionaryHashTableEntryForKey(AIMJKDictionary *dictionary, id aKey);


static void _JSONDecoderCleanup(AIMJSONDecoder *decoder);

static id _NSStringObjectFromJSONString(NSString *jsonString, AIMJKParseOptionFlags parseOptionFlags, NSError **error, BOOL mutableCollection);


static void AIMJK_managedBuffer_release(AIMJKManagedBuffer *managedBuffer);
static void AIMJK_managedBuffer_setToStackBuffer(AIMJKManagedBuffer *managedBuffer, unsigned char *ptr, size_t length);
static unsigned char *AIMJK_managedBuffer_resize(AIMJKManagedBuffer *managedBuffer, size_t newSize);
static void AIMJK_objectStack_release(AIMJKObjectStack *objectStack);
static void AIMJK_objectStack_setToStackBuffer(AIMJKObjectStack *objectStack, void **objects, void **keys, CFHashCode *cfHashes, size_t count);
static int  AIMJK_objectStack_resize(AIMJKObjectStack *objectStack, size_t newCount);

static void   AIMJK_error(AIMJKParseState *parseState, NSString *format, ...);
static int    AIMJK_parse_string(AIMJKParseState *parseState);
static int    AIMJK_parse_number(AIMJKParseState *parseState);
static size_t AIMJK_parse_is_newline(AIMJKParseState *parseState, const unsigned char *atCharacterPtr);
AIMJK_STATIC_INLINE int AIMJK_parse_skip_newline(AIMJKParseState *parseState);
AIMJK_STATIC_INLINE void AIMJK_parse_skip_whitespace(AIMJKParseState *parseState);
static int    AIMJK_parse_next_token(AIMJKParseState *parseState);
static void   AIMJK_error_parse_accept_or3(AIMJKParseState *parseState, int state, NSString *or1String, NSString *or2String, NSString *or3String);
static void  *AIMJK_create_dictionary(AIMJKParseState *parseState, size_t startingObjectIndex);
static void  *AIMJK_parse_dictionary(AIMJKParseState *parseState);
static void  *AIMJK_parse_array(AIMJKParseState *parseState);
static void  *AIMJK_object_for_token(AIMJKParseState *parseState);
static void  *AIMJK_cachedObjects(AIMJKParseState *parseState);
AIMJK_STATIC_INLINE void AIMJK_cache_age(AIMJKParseState *parseState);
AIMJK_STATIC_INLINE void AIMJK_set_parsed_token(AIMJKParseState *parseState, const unsigned char *ptr, size_t length, AIMJKTokenType type, size_t advanceBy);


static void AIMJK_encode_error(AIMJKEncodeState *encodeState, NSString *format, ...);
static int AIMJK_encode_printf(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object, const char *format, ...);
static int AIMJK_encode_write(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object, const char *format);
static int AIMJK_encode_writePrettyPrintWhiteSpace(AIMJKEncodeState *encodeState);
static int AIMJK_encode_write1slow(AIMJKEncodeState *encodeState, ssize_t depthChange, const char *format);
static int AIMJK_encode_write1fast(AIMJKEncodeState *encodeState, ssize_t depthChange AIMJK_UNUSED_ARG, const char *format);
static int AIMJK_encode_writen(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object, const char *format, size_t length);
AIMJK_STATIC_INLINE AIMJKHash AIMJK_encode_object_hash(void *objectPtr);
AIMJK_STATIC_INLINE void AIMJK_encode_updateCache(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object);
static int AIMJK_encode_add_atom_to_buffer(AIMJKEncodeState *encodeState, void *objectPtr);

#define AIMJK_encode_write1(es, dc, f)  (AIMJK_EXPECT_F(_jk_encode_prettyPrint) ? AIMJK_encode_write1slow(es, dc, f) : AIMJK_encode_write1fast(es, dc, f))


AIMJK_STATIC_INLINE size_t AIMJK_min(size_t a, size_t b);
AIMJK_STATIC_INLINE size_t AIMJK_max(size_t a, size_t b);
AIMJK_STATIC_INLINE AIMJKHash AIMJK_calculateHash(AIMJKHash currentHash, unsigned char c);

// AIMJSONKit v1.4 used both a AIMJKArray : NSArray and AIMJKMutableArray : NSMutableArray, and the same for the dictionary collection type.
// However, Louis Gerbarg (via cocoa-dev) pointed out that Cocoa / Core Foundation actually implements only a single class that inherits from the 
// mutable version, and keeps an ivar bit for whether or not that instance is mutable.  This means that the immutable versions of the collection
// classes receive the mutating methods, but this is handled by having those methods throw an exception when the ivar bit is set to immutable.
// We adopt the same strategy here.  It's both cleaner and gets rid of the method swizzling hackery used in AIMJSONKit v1.4.


// This is a workaround for issue #23 https://github.com/johnezang/JSONKit/pull/23
// Basically, there seem to be a problem with using +load in static libraries on iOS.  However, __attribute__ ((constructor)) does work correctly.
// Since we do not require anything "special" that +load provides, and we can accomplish the same thing using __attribute__ ((constructor)), the +load logic was moved here.

static Class                               _JKArrayClass                           = NULL;
static size_t                              _JKArrayInstanceSize                    = 0UL;
static Class                               _JKDictionaryClass                      = NULL;
static size_t                              _JKDictionaryInstanceSize               = 0UL;

// For AIMJSONDecoder...
static Class                               _jk_NSNumberClass                       = NULL;
static NSNumberAllocImp                    _jk_NSNumberAllocImp                    = NULL;
static NSNumberInitWithUnsignedLongLongImp _jk_NSNumberInitWithUnsignedLongLongImp = NULL;

extern void AIMJK_collectionClassLoadTimeInitialization(void) __attribute__ ((constructor));

void AIMJK_collectionClassLoadTimeInitialization(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; // Though technically not required, the run time environment at load time initialization may be less than ideal.
  
  _JKArrayClass             = objc_getClass("JKArray");
  _JKArrayInstanceSize      = AIMJK_max(16UL, class_getInstanceSize(_JKArrayClass));
  
  _JKDictionaryClass        = objc_getClass("JKDictionary");
  _JKDictionaryInstanceSize = AIMJK_max(16UL, class_getInstanceSize(_JKDictionaryClass));
  
  // For AIMJSONDecoder...
  _jk_NSNumberClass = [NSNumber class];
  _jk_NSNumberAllocImp = (NSNumberAllocImp)[NSNumber methodForSelector:@selector(alloc)];
  
  // Hacktacular.  Need to do it this way due to the nature of class clusters.
  id temp_NSNumber = [NSNumber alloc];
  _jk_NSNumberInitWithUnsignedLongLongImp = (NSNumberInitWithUnsignedLongLongImp)[temp_NSNumber methodForSelector:@selector(initWithUnsignedLongLong:)];
  [[temp_NSNumber init] release];
  temp_NSNumber = NULL;
  
  [pool release]; pool = NULL;
}


#pragma mark -
@interface AIMJKArray : NSMutableArray <NSCopying, NSMutableCopying, NSFastEnumeration> {
  id         *objects;
  NSUInteger  count, capacity, mutations;
}
@end

@implementation AIMJKArray

+ (id)allocWithZone:(NSZone *)zone
{
#pragma unused(zone)
  [NSException raise:NSInvalidArgumentException format:@"*** - [%@ %@]: The %@ class is private to AIMJSONKit and should not be used in this fashion.", NSStringFromClass([self class]), NSStringFromSelector(_cmd), NSStringFromClass([self class])];
  return(NULL);
}

static AIMJKArray *_JKArrayCreate(id *objects, NSUInteger count, BOOL mutableCollection) {
  NSCParameterAssert((objects != NULL) && (_JKArrayClass != NULL) && (_JKArrayInstanceSize > 0UL));
  AIMJKArray *array = NULL;
  if(AIMJK_EXPECT_T((array = (AIMJKArray *)calloc(1UL, _JKArrayInstanceSize)) != NULL)) { // Directly allocate the AIMJKArray instance via calloc.
    array->isa      = _JKArrayClass;
    if((array = [array init]) == NULL) { return(NULL); }
    array->capacity = count;
    array->count    = count;
    if(AIMJK_EXPECT_F((array->objects = (id *)malloc(sizeof(id) * array->capacity)) == NULL)) { [array autorelease]; return(NULL); }
    memcpy(array->objects, objects, array->capacity * sizeof(id));
    array->mutations = (mutableCollection == NO) ? 0UL : 1UL;
  }
  return(array);
}

// Note: The caller is responsible for -retaining the object that is to be added.
static void _JKArrayInsertObjectAtIndex(AIMJKArray *array, id newObject, NSUInteger objectIndex) {
  NSCParameterAssert((array != NULL) && (array->objects != NULL) && (array->count <= array->capacity) && (objectIndex <= array->count) && (newObject != NULL));
  if(!((array != NULL) && (array->objects != NULL) && (objectIndex <= array->count) && (newObject != NULL))) { [newObject autorelease]; return; }
  if((array->count + 1UL) >= array->capacity) {
    id *newObjects = NULL;
    if((newObjects = (id *)realloc(array->objects, sizeof(id) * (array->capacity + 16UL))) == NULL) { [NSException raise:NSMallocException format:@"Unable to resize objects array."]; }
    array->objects = newObjects;
    array->capacity += 16UL;
    memset(&array->objects[array->count], 0, sizeof(id) * (array->capacity - array->count));
  }
  array->count++;
  if((objectIndex + 1UL) < array->count) { memmove(&array->objects[objectIndex + 1UL], &array->objects[objectIndex], sizeof(id) * ((array->count - 1UL) - objectIndex)); array->objects[objectIndex] = NULL; }
  array->objects[objectIndex] = newObject;
}

// Note: The caller is responsible for -retaining the object that is to be added.
static void _JKArrayReplaceObjectAtIndexWithObject(AIMJKArray *array, NSUInteger objectIndex, id newObject) {
  NSCParameterAssert((array != NULL) && (array->objects != NULL) && (array->count <= array->capacity) && (objectIndex < array->count) && (array->objects[objectIndex] != NULL) && (newObject != NULL));
  if(!((array != NULL) && (array->objects != NULL) && (objectIndex < array->count) && (array->objects[objectIndex] != NULL) && (newObject != NULL))) { [newObject autorelease]; return; }
  CFRelease(array->objects[objectIndex]);
  array->objects[objectIndex] = NULL;
  array->objects[objectIndex] = newObject;
}

static void _JKArrayRemoveObjectAtIndex(AIMJKArray *array, NSUInteger objectIndex) {
  NSCParameterAssert((array != NULL) && (array->objects != NULL) && (array->count > 0UL) && (array->count <= array->capacity) && (objectIndex < array->count) && (array->objects[objectIndex] != NULL));
  if(!((array != NULL) && (array->objects != NULL) && (array->count > 0UL) && (array->count <= array->capacity) && (objectIndex < array->count) && (array->objects[objectIndex] != NULL))) { return; }
  CFRelease(array->objects[objectIndex]);
  array->objects[objectIndex] = NULL;
  if((objectIndex + 1UL) < array->count) { memmove(&array->objects[objectIndex], &array->objects[objectIndex + 1UL], sizeof(id) * ((array->count - 1UL) - objectIndex)); array->objects[array->count - 1UL] = NULL; }
  array->count--;
}

- (void)dealloc
{
  if(AIMJK_EXPECT_T(objects != NULL)) {
    NSUInteger atObject = 0UL;
    for(atObject = 0UL; atObject < count; atObject++) { if(AIMJK_EXPECT_T(objects[atObject] != NULL)) { CFRelease(objects[atObject]); objects[atObject] = NULL; } }
    free(objects); objects = NULL;
  }
  
  [super dealloc];
}

- (NSUInteger)count
{
  NSParameterAssert((objects != NULL) && (count <= capacity));
  return(count);
}

- (void)getObjects:(id *)objectsPtr range:(NSRange)range
{
  NSParameterAssert((objects != NULL) && (count <= capacity));
  if((objectsPtr     == NULL)  && (NSMaxRange(range) > 0UL))   { [NSException raise:NSRangeException format:@"*** -[%@ %@]: pointer to objects array is NULL but range length is %lu", NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)NSMaxRange(range)];        }
  if((range.location >  count) || (NSMaxRange(range) > count)) { [NSException raise:NSRangeException format:@"*** -[%@ %@]: index (%lu) beyond bounds (%lu)",                          NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)NSMaxRange(range), (unsigned long)count]; }
#ifndef __clang_analyzer__
  memcpy(objectsPtr, objects + range.location, range.length * sizeof(id));
#endif
}

- (id)objectAtIndex:(NSUInteger)objectIndex
{
  if(objectIndex >= count) { [NSException raise:NSRangeException format:@"*** -[%@ %@]: index (%lu) beyond bounds (%lu)", NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)objectIndex, (unsigned long)count]; }
  NSParameterAssert((objects != NULL) && (count <= capacity) && (objects[objectIndex] != NULL));
  return(objects[objectIndex]);
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
  NSParameterAssert((state != NULL) && (stackbuf != NULL) && (len > 0UL) && (objects != NULL) && (count <= capacity));
  if(AIMJK_EXPECT_F(state->state == 0UL))   { state->mutationsPtr = (unsigned long *)&mutations; state->itemsPtr = stackbuf; }
  if(AIMJK_EXPECT_F(state->state >= count)) { return(0UL); }
  
  NSUInteger enumeratedCount  = 0UL;
  while(AIMJK_EXPECT_T(enumeratedCount < len) && AIMJK_EXPECT_T(state->state < count)) { NSParameterAssert(objects[state->state] != NULL); stackbuf[enumeratedCount++] = objects[state->state++]; }
  
  return(enumeratedCount);
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)objectIndex
{
  if(mutations   == 0UL)   { [NSException raise:NSInternalInconsistencyException format:@"*** -[%@ %@]: mutating method sent to immutable object", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  if(anObject    == NULL)  { [NSException raise:NSInvalidArgumentException       format:@"*** -[%@ %@]: attempt to insert nil",                    NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  if(objectIndex >  count) { [NSException raise:NSRangeException                 format:@"*** -[%@ %@]: index (%lu) beyond bounds (%lu)",          NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)objectIndex, (unsigned long)(count + 1UL)]; }
#ifdef __clang_analyzer__
  [anObject retain]; // Stupid clang analyzer...  Issue #19.
#else
  anObject = [anObject retain];
#endif
  _JKArrayInsertObjectAtIndex(self, anObject, objectIndex);
  mutations = (mutations == NSUIntegerMax) ? 1UL : mutations + 1UL;
}

- (void)removeObjectAtIndex:(NSUInteger)objectIndex
{
  if(mutations   == 0UL)   { [NSException raise:NSInternalInconsistencyException format:@"*** -[%@ %@]: mutating method sent to immutable object", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  if(objectIndex >= count) { [NSException raise:NSRangeException                 format:@"*** -[%@ %@]: index (%lu) beyond bounds (%lu)",          NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)objectIndex, (unsigned long)count]; }
  _JKArrayRemoveObjectAtIndex(self, objectIndex);
  mutations = (mutations == NSUIntegerMax) ? 1UL : mutations + 1UL;
}

- (void)replaceObjectAtIndex:(NSUInteger)objectIndex withObject:(id)anObject
{
  if(mutations   == 0UL)   { [NSException raise:NSInternalInconsistencyException format:@"*** -[%@ %@]: mutating method sent to immutable object", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  if(anObject    == NULL)  { [NSException raise:NSInvalidArgumentException       format:@"*** -[%@ %@]: attempt to insert nil",                    NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  if(objectIndex >= count) { [NSException raise:NSRangeException                 format:@"*** -[%@ %@]: index (%lu) beyond bounds (%lu)",          NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)objectIndex, (unsigned long)count]; }
#ifdef __clang_analyzer__
  [anObject retain]; // Stupid clang analyzer...  Issue #19.
#else
  anObject = [anObject retain];
#endif
  _JKArrayReplaceObjectAtIndexWithObject(self, objectIndex, anObject);
  mutations = (mutations == NSUIntegerMax) ? 1UL : mutations + 1UL;
}

- (id)copyWithZone:(NSZone *)zone
{
  NSParameterAssert((objects != NULL) && (count <= capacity));
  return((mutations == 0UL) ? [self retain] : [(NSArray *)[NSArray allocWithZone:zone] initWithObjects:objects count:count]);
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
  NSParameterAssert((objects != NULL) && (count <= capacity));
  return([(NSMutableArray *)[NSMutableArray allocWithZone:zone] initWithObjects:objects count:count]);
}

@end


#pragma mark -
@interface AIMJKDictionaryEnumerator : NSEnumerator {
  id         collection;
  NSUInteger nextObject;
}

- (id)initWithJKDictionary:(AIMJKDictionary *)initDictionary;
- (NSArray *)allObjects;
- (id)nextObject;

@end

@implementation AIMJKDictionaryEnumerator

- (id)initWithJKDictionary:(AIMJKDictionary *)initDictionary
{
  NSParameterAssert(initDictionary != NULL);
  if((self = [super init]) == NULL) { return(NULL); }
  if((collection = (id)CFRetain(initDictionary)) == NULL) { [self autorelease]; return(NULL); }
  return(self);
}

- (void)dealloc
{
  if(collection != NULL) { CFRelease(collection); collection = NULL; }
  [super dealloc];
}

- (NSArray *)allObjects
{
  NSParameterAssert(collection != NULL);
  NSUInteger count = [(NSDictionary *)collection count], atObject = 0UL;
  id         objects[count];

  while((objects[atObject] = [self nextObject]) != NULL) { NSParameterAssert(atObject < count); atObject++; }

  return([NSArray arrayWithObjects:objects count:atObject]);
}

- (id)nextObject
{
  NSParameterAssert((collection != NULL) && (_JKDictionaryHashEntry(collection) != NULL));
  AIMJKHashTableEntry *entry        = _JKDictionaryHashEntry(collection);
  NSUInteger        capacity     = _JKDictionaryCapacity(collection);
  id                returnObject = NULL;

  if(entry != NULL) { while((nextObject < capacity) && ((returnObject = entry[nextObject++].key) == NULL)) { /* ... */ } }
  
  return(returnObject);
}

@end

#pragma mark -
@interface AIMJKDictionary : NSMutableDictionary <NSCopying, NSMutableCopying, NSFastEnumeration> {
  NSUInteger count, capacity, mutations;
  AIMJKHashTableEntry *entry;
}
@end

@implementation AIMJKDictionary

+ (id)allocWithZone:(NSZone *)zone
{
#pragma unused(zone)
  [NSException raise:NSInvalidArgumentException format:@"*** - [%@ %@]: The %@ class is private to AIMJSONKit and should not be used in this fashion.", NSStringFromClass([self class]), NSStringFromSelector(_cmd), NSStringFromClass([self class])];
  return(NULL);
}

// These values are taken from Core Foundation CF-550 CFBasicHash.m.  As a bonus, they align very well with our AIMJKHashTableEntry struct too.
static const NSUInteger AIMJK_dictionaryCapacities[] = {
  0UL, 3UL, 7UL, 13UL, 23UL, 41UL, 71UL, 127UL, 191UL, 251UL, 383UL, 631UL, 1087UL, 1723UL,
  2803UL, 4523UL, 7351UL, 11959UL, 19447UL, 31231UL, 50683UL, 81919UL, 132607UL,
  214519UL, 346607UL, 561109UL, 907759UL, 1468927UL, 2376191UL, 3845119UL,
  6221311UL, 10066421UL, 16287743UL, 26354171UL, 42641881UL, 68996069UL,
  111638519UL, 180634607UL, 292272623UL, 472907251UL
};

static NSUInteger _JKDictionaryCapacityForCount(NSUInteger count) {
  NSUInteger bottom = 0UL, top = sizeof(AIMJK_dictionaryCapacities) / sizeof(NSUInteger), mid = 0UL, tableSize = (NSUInteger)lround(floor(((double)count) * 1.33));
  while(top > bottom) { mid = (top + bottom) / 2UL; if(AIMJK_dictionaryCapacities[mid] < tableSize) { bottom = mid + 1UL; } else { top = mid; } }
  return(AIMJK_dictionaryCapacities[bottom]);
}

static void _JKDictionaryResizeIfNeccessary(AIMJKDictionary *dictionary) {
  NSCParameterAssert((dictionary != NULL) && (dictionary->entry != NULL) && (dictionary->count <= dictionary->capacity));

  NSUInteger capacityForCount = 0UL;
  if(dictionary->capacity < (capacityForCount = _JKDictionaryCapacityForCount(dictionary->count + 1UL))) { // resize
    NSUInteger        oldCapacity = dictionary->capacity;
#ifndef NS_BLOCK_ASSERTIONS
    NSUInteger oldCount = dictionary->count;
#endif
    AIMJKHashTableEntry *oldEntry    = dictionary->entry;
    if(AIMJK_EXPECT_F((dictionary->entry = (AIMJKHashTableEntry *)calloc(1UL, sizeof(AIMJKHashTableEntry) * capacityForCount)) == NULL)) { [NSException raise:NSMallocException format:@"Unable to allocate memory for hash table."]; }
    dictionary->capacity = capacityForCount;
    dictionary->count    = 0UL;
    
    NSUInteger idx = 0UL;
    for(idx = 0UL; idx < oldCapacity; idx++) { if(oldEntry[idx].key != NULL) { _JKDictionaryAddObject(dictionary, oldEntry[idx].keyHash, oldEntry[idx].key, oldEntry[idx].object); oldEntry[idx].keyHash = 0UL; oldEntry[idx].key = NULL; oldEntry[idx].object = NULL; } }
    NSCParameterAssert((oldCount == dictionary->count));
    free(oldEntry); oldEntry = NULL;
  }
}

static AIMJKDictionary *_JKDictionaryCreate(id *keys, NSUInteger *keyHashes, id *objects, NSUInteger count, BOOL mutableCollection) {
  NSCParameterAssert((keys != NULL) && (keyHashes != NULL) && (objects != NULL) && (_JKDictionaryClass != NULL) && (_JKDictionaryInstanceSize > 0UL));
  AIMJKDictionary *dictionary = NULL;
  if(AIMJK_EXPECT_T((dictionary = (AIMJKDictionary *)calloc(1UL, _JKDictionaryInstanceSize)) != NULL)) { // Directly allocate the AIMJKDictionary instance via calloc.
    dictionary->isa      = _JKDictionaryClass;
    if((dictionary = [dictionary init]) == NULL) { return(NULL); }
    dictionary->capacity = _JKDictionaryCapacityForCount(count);
    dictionary->count    = 0UL;
    
    if(AIMJK_EXPECT_F((dictionary->entry = (AIMJKHashTableEntry *)calloc(1UL, sizeof(AIMJKHashTableEntry) * dictionary->capacity)) == NULL)) { [dictionary autorelease]; return(NULL); }

    NSUInteger idx = 0UL;
    for(idx = 0UL; idx < count; idx++) { _JKDictionaryAddObject(dictionary, keyHashes[idx], keys[idx], objects[idx]); }

    dictionary->mutations = (mutableCollection == NO) ? 0UL : 1UL;
  }
  return(dictionary);
}

- (void)dealloc
{
  if(AIMJK_EXPECT_T(entry != NULL)) {
    NSUInteger atEntry = 0UL;
    for(atEntry = 0UL; atEntry < capacity; atEntry++) {
      if(AIMJK_EXPECT_T(entry[atEntry].key    != NULL)) { CFRelease(entry[atEntry].key);    entry[atEntry].key    = NULL; }
      if(AIMJK_EXPECT_T(entry[atEntry].object != NULL)) { CFRelease(entry[atEntry].object); entry[atEntry].object = NULL; }
    }
  
    free(entry); entry = NULL;
  }

  [super dealloc];
}

static AIMJKHashTableEntry *_JKDictionaryHashEntry(AIMJKDictionary *dictionary) {
  NSCParameterAssert(dictionary != NULL);
  return(dictionary->entry);
}

static NSUInteger _JKDictionaryCapacity(AIMJKDictionary *dictionary) {
  NSCParameterAssert(dictionary != NULL);
  return(dictionary->capacity);
}

static void _JKDictionaryRemoveObjectWithEntry(AIMJKDictionary *dictionary, AIMJKHashTableEntry *entry) {
  NSCParameterAssert((dictionary != NULL) && (entry != NULL) && (entry->key != NULL) && (entry->object != NULL) && (dictionary->count > 0UL) && (dictionary->count <= dictionary->capacity));
  CFRelease(entry->key);    entry->key    = NULL;
  CFRelease(entry->object); entry->object = NULL;
  entry->keyHash = 0UL;
  dictionary->count--;
  // In order for certain invariants that are used to speed up the search for a particular key, we need to "re-add" all the entries in the hash table following this entry until we hit a NULL entry.
  NSUInteger removeIdx = entry - dictionary->entry, idx = 0UL;
  NSCParameterAssert((removeIdx < dictionary->capacity));
  for(idx = 0UL; idx < dictionary->capacity; idx++) {
    NSUInteger entryIdx = (removeIdx + idx + 1UL) % dictionary->capacity;
    AIMJKHashTableEntry *atEntry = &dictionary->entry[entryIdx];
    if(atEntry->key == NULL) { break; }
    NSUInteger keyHash = atEntry->keyHash;
    id key = atEntry->key, object = atEntry->object;
    NSCParameterAssert(object != NULL);
    atEntry->keyHash = 0UL;
    atEntry->key     = NULL;
    atEntry->object  = NULL;
    NSUInteger addKeyEntry = keyHash % dictionary->capacity, addIdx = 0UL;
    for(addIdx = 0UL; addIdx < dictionary->capacity; addIdx++) {
      AIMJKHashTableEntry *atAddEntry = &dictionary->entry[((addKeyEntry + addIdx) % dictionary->capacity)];
      if(AIMJK_EXPECT_T(atAddEntry->key == NULL)) { NSCParameterAssert((atAddEntry->keyHash == 0UL) && (atAddEntry->object == NULL)); atAddEntry->key = key; atAddEntry->object = object; atAddEntry->keyHash = keyHash; break; }
    }
  }
}

static void _JKDictionaryAddObject(AIMJKDictionary *dictionary, NSUInteger keyHash, id key, id object) {
  NSCParameterAssert((dictionary != NULL) && (key != NULL) && (object != NULL) && (dictionary->count < dictionary->capacity) && (dictionary->entry != NULL));
  NSUInteger keyEntry = keyHash % dictionary->capacity, idx = 0UL;
  for(idx = 0UL; idx < dictionary->capacity; idx++) {
    NSUInteger entryIdx = (keyEntry + idx) % dictionary->capacity;
    AIMJKHashTableEntry *atEntry = &dictionary->entry[entryIdx];
    if(AIMJK_EXPECT_F(atEntry->keyHash == keyHash) && AIMJK_EXPECT_T(atEntry->key != NULL) && (AIMJK_EXPECT_F(key == atEntry->key) || AIMJK_EXPECT_F(CFEqual(atEntry->key, key)))) { _JKDictionaryRemoveObjectWithEntry(dictionary, atEntry); }
    if(AIMJK_EXPECT_T(atEntry->key == NULL)) { NSCParameterAssert((atEntry->keyHash == 0UL) && (atEntry->object == NULL)); atEntry->key = key; atEntry->object = object; atEntry->keyHash = keyHash; dictionary->count++; return; }
  }

  // We should never get here.  If we do, we -release the key / object because it's our responsibility.
  CFRelease(key);
  CFRelease(object);
}

- (NSUInteger)count
{
  return(count);
}

static AIMJKHashTableEntry *_JKDictionaryHashTableEntryForKey(AIMJKDictionary *dictionary, id aKey) {
  NSCParameterAssert((dictionary != NULL) && (dictionary->entry != NULL) && (dictionary->count <= dictionary->capacity));
  if((aKey == NULL) || (dictionary->capacity == 0UL)) { return(NULL); }
  NSUInteger        keyHash = CFHash(aKey), keyEntry = (keyHash % dictionary->capacity), idx = 0UL;
  AIMJKHashTableEntry *atEntry = NULL;
  for(idx = 0UL; idx < dictionary->capacity; idx++) {
    atEntry = &dictionary->entry[(keyEntry + idx) % dictionary->capacity];
    if(AIMJK_EXPECT_T(atEntry->keyHash == keyHash) && AIMJK_EXPECT_T(atEntry->key != NULL) && ((atEntry->key == aKey) || CFEqual(atEntry->key, aKey))) { NSCParameterAssert(atEntry->object != NULL); return(atEntry); break; }
    if(AIMJK_EXPECT_F(atEntry->key == NULL)) { NSCParameterAssert(atEntry->object == NULL); return(NULL); break; } // If the key was in the table, we would have found it by now.
  }
  return(NULL);
}

- (id)objectForKey:(id)aKey
{
  NSParameterAssert((entry != NULL) && (count <= capacity));
  AIMJKHashTableEntry *entryForKey = _JKDictionaryHashTableEntryForKey(self, aKey);
  return((entryForKey != NULL) ? entryForKey->object : NULL);
}

- (void)getObjects:(id *)objects andKeys:(id *)keys
{
  NSParameterAssert((entry != NULL) && (count <= capacity));
  NSUInteger atEntry = 0UL; NSUInteger arrayIdx = 0UL;
  for(atEntry = 0UL; atEntry < capacity; atEntry++) {
    if(AIMJK_EXPECT_T(entry[atEntry].key != NULL)) {
      NSCParameterAssert((entry[atEntry].object != NULL) && (arrayIdx < count));
      if(AIMJK_EXPECT_T(keys    != NULL)) { keys[arrayIdx]    = entry[atEntry].key;    }
      if(AIMJK_EXPECT_T(objects != NULL)) { objects[arrayIdx] = entry[atEntry].object; }
      arrayIdx++;
    }
  }
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
  NSParameterAssert((state != NULL) && (stackbuf != NULL) && (len > 0UL) && (entry != NULL) && (count <= capacity));
  if(AIMJK_EXPECT_F(state->state == 0UL))      { state->mutationsPtr = (unsigned long *)&mutations; state->itemsPtr = stackbuf; }
  if(AIMJK_EXPECT_F(state->state >= capacity)) { return(0UL); }
  
  NSUInteger enumeratedCount  = 0UL;
  while(AIMJK_EXPECT_T(enumeratedCount < len) && AIMJK_EXPECT_T(state->state < capacity)) { if(AIMJK_EXPECT_T(entry[state->state].key != NULL)) { stackbuf[enumeratedCount++] = entry[state->state].key; } state->state++; }
    
  return(enumeratedCount);
}

- (NSEnumerator *)keyEnumerator
{
  return([[[AIMJKDictionaryEnumerator alloc] initWithJKDictionary:self] autorelease]);
}

- (void)setObject:(id)anObject forKey:(id)aKey
{
  if(mutations == 0UL)  { [NSException raise:NSInternalInconsistencyException format:@"*** -[%@ %@]: mutating method sent to immutable object", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];       }
  if(aKey      == NULL) { [NSException raise:NSInvalidArgumentException       format:@"*** -[%@ %@]: attempt to insert nil key",                NSStringFromClass([self class]), NSStringFromSelector(_cmd)];       }
  if(anObject  == NULL) { [NSException raise:NSInvalidArgumentException       format:@"*** -[%@ %@]: attempt to insert nil value (key: %@)",    NSStringFromClass([self class]), NSStringFromSelector(_cmd), aKey]; }
  
  _JKDictionaryResizeIfNeccessary(self);
#ifndef __clang_analyzer__
  aKey     = [aKey     copy];   // Why on earth would clang complain that this -copy "might leak", 
  anObject = [anObject retain]; // but this -retain doesn't!?
#endif // __clang_analyzer__
  _JKDictionaryAddObject(self, CFHash(aKey), aKey, anObject);
  mutations = (mutations == NSUIntegerMax) ? 1UL : mutations + 1UL;
}

- (void)removeObjectForKey:(id)aKey
{
  if(mutations == 0UL)  { [NSException raise:NSInternalInconsistencyException format:@"*** -[%@ %@]: mutating method sent to immutable object", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  if(aKey      == NULL) { [NSException raise:NSInvalidArgumentException       format:@"*** -[%@ %@]: attempt to remove nil key",                NSStringFromClass([self class]), NSStringFromSelector(_cmd)]; }
  AIMJKHashTableEntry *entryForKey = _JKDictionaryHashTableEntryForKey(self, aKey);
  if(entryForKey != NULL) {
    _JKDictionaryRemoveObjectWithEntry(self, entryForKey);
    mutations = (mutations == NSUIntegerMax) ? 1UL : mutations + 1UL;
  }
}

- (id)copyWithZone:(NSZone *)zone
{
  NSParameterAssert((entry != NULL) && (count <= capacity));
  return((mutations == 0UL) ? [self retain] : [[NSDictionary allocWithZone:zone] initWithDictionary:self]);
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
  NSParameterAssert((entry != NULL) && (count <= capacity));
  return([[NSMutableDictionary allocWithZone:zone] initWithDictionary:self]);
}

@end



#pragma mark -

AIMJK_STATIC_INLINE size_t AIMJK_min(size_t a, size_t b) { return((a < b) ? a : b); }
AIMJK_STATIC_INLINE size_t AIMJK_max(size_t a, size_t b) { return((a > b) ? a : b); }

AIMJK_STATIC_INLINE AIMJKHash AIMJK_calculateHash(AIMJKHash currentHash, unsigned char c) { return((((currentHash << 5) + currentHash) + (c - 29)) ^ (currentHash >> 19)); }


static void AIMJK_error(AIMJKParseState *parseState, NSString *format, ...) {
  NSCParameterAssert((parseState != NULL) && (format != NULL));

  va_list varArgsList;
  va_start(varArgsList, format);
  NSString *formatString = [[[NSString alloc] initWithFormat:format arguments:varArgsList] autorelease];
  va_end(varArgsList);

#if 0
  const unsigned char *lineStart      = parseState->stringBuffer.bytes.ptr + parseState->lineStartIndex;
  const unsigned char *lineEnd        = lineStart;
  const unsigned char *atCharacterPtr = NULL;

  for(atCharacterPtr = lineStart; atCharacterPtr < AIMJK_END_STRING_PTR(parseState); atCharacterPtr++) { lineEnd = atCharacterPtr; if(AIMJK_parse_is_newline(parseState, atCharacterPtr)) { break; } }

  NSString *lineString = @"", *carretString = @"";
  if(lineStart < AIMJK_END_STRING_PTR(parseState)) {
    lineString   = [[[NSString alloc] initWithBytes:lineStart length:(lineEnd - lineStart) encoding:NSUTF8StringEncoding] autorelease];
    carretString = [NSString stringWithFormat:@"%*.*s^", (int)(parseState->atIndex - parseState->lineStartIndex), (int)(parseState->atIndex - parseState->lineStartIndex), " "];
  }
#endif

  if(parseState->error == NULL) {
    parseState->error = [NSError errorWithDomain:@"JKErrorDomain" code:-1L userInfo:
                                   [NSDictionary dictionaryWithObjectsAndKeys:
                                                                              formatString,                                             NSLocalizedDescriptionKey,
                                                                              [NSNumber numberWithUnsignedLong:parseState->atIndex],    @"JKAtIndexKey",
                                                                              [NSNumber numberWithUnsignedLong:parseState->lineNumber], @"JKLineNumberKey",
                                                 //lineString,   @"JKErrorLine0Key",
                                                 //carretString, @"JKErrorLine1Key",
                                                                              NULL]];
  }
}

#pragma mark -
#pragma mark Buffer and Object Stack management functions

static void AIMJK_managedBuffer_release(AIMJKManagedBuffer *managedBuffer) {
  if((managedBuffer->flags & AIMJKManagedBufferMustFree)) {
    if(managedBuffer->bytes.ptr != NULL) { free(managedBuffer->bytes.ptr); managedBuffer->bytes.ptr = NULL; }
    managedBuffer->flags &= ~AIMJKManagedBufferMustFree;
  }

  managedBuffer->bytes.ptr     = NULL;
  managedBuffer->bytes.length  = 0UL;
  managedBuffer->flags        &= ~AIMJKManagedBufferLocationMask;
}

static void AIMJK_managedBuffer_setToStackBuffer(AIMJKManagedBuffer *managedBuffer, unsigned char *ptr, size_t length) {
  AIMJK_managedBuffer_release(managedBuffer);
  managedBuffer->bytes.ptr     = ptr;
  managedBuffer->bytes.length  = length;
  managedBuffer->flags         = (managedBuffer->flags & ~AIMJKManagedBufferLocationMask) | AIMJKManagedBufferOnStack;
}

static unsigned char *AIMJK_managedBuffer_resize(AIMJKManagedBuffer *managedBuffer, size_t newSize) {
  size_t roundedUpNewSize = newSize;

  if(managedBuffer->roundSizeUpToMultipleOf > 0UL) { roundedUpNewSize = newSize + ((managedBuffer->roundSizeUpToMultipleOf - (newSize % managedBuffer->roundSizeUpToMultipleOf)) % managedBuffer->roundSizeUpToMultipleOf); }

  if((roundedUpNewSize != managedBuffer->bytes.length) && (roundedUpNewSize > managedBuffer->bytes.length)) {
    if((managedBuffer->flags & AIMJKManagedBufferLocationMask) == AIMJKManagedBufferOnStack) {
      NSCParameterAssert((managedBuffer->flags & AIMJKManagedBufferMustFree) == 0);
      unsigned char *newBuffer = NULL, *oldBuffer = managedBuffer->bytes.ptr;
      
      if((newBuffer = (unsigned char *)malloc(roundedUpNewSize)) == NULL) { return(NULL); }
      memcpy(newBuffer, oldBuffer, AIMJK_min(managedBuffer->bytes.length, roundedUpNewSize));
      managedBuffer->flags        = (managedBuffer->flags & ~AIMJKManagedBufferLocationMask) | (AIMJKManagedBufferOnHeap | AIMJKManagedBufferMustFree);
      managedBuffer->bytes.ptr    = newBuffer;
      managedBuffer->bytes.length = roundedUpNewSize;
    } else {
      NSCParameterAssert(((managedBuffer->flags & AIMJKManagedBufferMustFree) != 0) && ((managedBuffer->flags & AIMJKManagedBufferLocationMask) == AIMJKManagedBufferOnHeap));
      if((managedBuffer->bytes.ptr = (unsigned char *)reallocf(managedBuffer->bytes.ptr, roundedUpNewSize)) == NULL) { return(NULL); }
      managedBuffer->bytes.length = roundedUpNewSize;
    }
  }

  return(managedBuffer->bytes.ptr);
}



static void AIMJK_objectStack_release(AIMJKObjectStack *objectStack) {
  NSCParameterAssert(objectStack != NULL);

  NSCParameterAssert(objectStack->index <= objectStack->count);
  size_t atIndex = 0UL;
  for(atIndex = 0UL; atIndex < objectStack->index; atIndex++) {
    if(objectStack->objects[atIndex] != NULL) { CFRelease(objectStack->objects[atIndex]); objectStack->objects[atIndex] = NULL; }
    if(objectStack->keys[atIndex]    != NULL) { CFRelease(objectStack->keys[atIndex]);    objectStack->keys[atIndex]    = NULL; }
  }
  objectStack->index = 0UL;

  if(objectStack->flags & AIMJKObjectStackMustFree) {
    NSCParameterAssert((objectStack->flags & AIMJKObjectStackLocationMask) == AIMJKObjectStackOnHeap);
    if(objectStack->objects  != NULL) { free(objectStack->objects);  objectStack->objects  = NULL; }
    if(objectStack->keys     != NULL) { free(objectStack->keys);     objectStack->keys     = NULL; }
    if(objectStack->cfHashes != NULL) { free(objectStack->cfHashes); objectStack->cfHashes = NULL; }
    objectStack->flags &= ~AIMJKObjectStackMustFree;
  }

  objectStack->objects  = NULL;
  objectStack->keys     = NULL;
  objectStack->cfHashes = NULL;

  objectStack->count    = 0UL;
  objectStack->flags   &= ~AIMJKObjectStackLocationMask;
}

static void AIMJK_objectStack_setToStackBuffer(AIMJKObjectStack *objectStack, void **objects, void **keys, CFHashCode *cfHashes, size_t count) {
  NSCParameterAssert((objectStack != NULL) && (objects != NULL) && (keys != NULL) && (cfHashes != NULL) && (count > 0UL));
  AIMJK_objectStack_release(objectStack);
  objectStack->objects  = objects;
  objectStack->keys     = keys;
  objectStack->cfHashes = cfHashes;
  objectStack->count    = count;
  objectStack->flags    = (objectStack->flags & ~AIMJKObjectStackLocationMask) | AIMJKObjectStackOnStack;
#ifndef NS_BLOCK_ASSERTIONS
  size_t idx;
  for(idx = 0UL; idx < objectStack->count; idx++) { objectStack->objects[idx] = NULL; objectStack->keys[idx] = NULL; objectStack->cfHashes[idx] = 0UL; }
#endif
}

static int AIMJK_objectStack_resize(AIMJKObjectStack *objectStack, size_t newCount) {
  size_t roundedUpNewCount = newCount;
  int    returnCode = 0;

  void       **newObjects  = NULL, **newKeys = NULL;
  CFHashCode  *newCFHashes = NULL;

  if(objectStack->roundSizeUpToMultipleOf > 0UL) { roundedUpNewCount = newCount + ((objectStack->roundSizeUpToMultipleOf - (newCount % objectStack->roundSizeUpToMultipleOf)) % objectStack->roundSizeUpToMultipleOf); }

  if((roundedUpNewCount != objectStack->count) && (roundedUpNewCount > objectStack->count)) {
    if((objectStack->flags & AIMJKObjectStackLocationMask) == AIMJKObjectStackOnStack) {
      NSCParameterAssert((objectStack->flags & AIMJKObjectStackMustFree) == 0);

      if((newObjects  = (void **     )calloc(1UL, roundedUpNewCount * sizeof(void *    ))) == NULL) { returnCode = 1; goto errorExit; }
      memcpy(newObjects, objectStack->objects,   AIMJK_min(objectStack->count, roundedUpNewCount) * sizeof(void *));
      if((newKeys     = (void **     )calloc(1UL, roundedUpNewCount * sizeof(void *    ))) == NULL) { returnCode = 1; goto errorExit; }
      memcpy(newKeys,     objectStack->keys,     AIMJK_min(objectStack->count, roundedUpNewCount) * sizeof(void *));

      if((newCFHashes = (CFHashCode *)calloc(1UL, roundedUpNewCount * sizeof(CFHashCode))) == NULL) { returnCode = 1; goto errorExit; }
      memcpy(newCFHashes, objectStack->cfHashes, AIMJK_min(objectStack->count, roundedUpNewCount) * sizeof(CFHashCode));

      objectStack->flags    = (objectStack->flags & ~AIMJKObjectStackLocationMask) | (AIMJKObjectStackOnHeap | AIMJKObjectStackMustFree);
      objectStack->objects  = newObjects;  newObjects  = NULL;
      objectStack->keys     = newKeys;     newKeys     = NULL;
      objectStack->cfHashes = newCFHashes; newCFHashes = NULL;
      objectStack->count    = roundedUpNewCount;
    } else {
      NSCParameterAssert(((objectStack->flags & AIMJKObjectStackMustFree) != 0) && ((objectStack->flags & AIMJKObjectStackLocationMask) == AIMJKObjectStackOnHeap));
      if((newObjects  = (void  **    )realloc(objectStack->objects,  roundedUpNewCount * sizeof(void *    ))) != NULL) { objectStack->objects  = newObjects;  newObjects  = NULL; } else { returnCode = 1; goto errorExit; }
      if((newKeys     = (void  **    )realloc(objectStack->keys,     roundedUpNewCount * sizeof(void *    ))) != NULL) { objectStack->keys     = newKeys;     newKeys     = NULL; } else { returnCode = 1; goto errorExit; }
      if((newCFHashes = (CFHashCode *)realloc(objectStack->cfHashes, roundedUpNewCount * sizeof(CFHashCode))) != NULL) { objectStack->cfHashes = newCFHashes; newCFHashes = NULL; } else { returnCode = 1; goto errorExit; }

#ifndef NS_BLOCK_ASSERTIONS
      size_t idx;
      for(idx = objectStack->count; idx < roundedUpNewCount; idx++) { objectStack->objects[idx] = NULL; objectStack->keys[idx] = NULL; objectStack->cfHashes[idx] = 0UL; }
#endif
      objectStack->count = roundedUpNewCount;
    }
  }

 errorExit:
  if(newObjects  != NULL) { free(newObjects);  newObjects  = NULL; }
  if(newKeys     != NULL) { free(newKeys);     newKeys     = NULL; }
  if(newCFHashes != NULL) { free(newCFHashes); newCFHashes = NULL; }

  return(returnCode);
}

////////////
#pragma mark -
#pragma mark Unicode related functions

AIMJK_STATIC_INLINE ConversionResult isValidCodePoint(UTF32 *u32CodePoint) {
  ConversionResult result = conversionOK;
  UTF32            ch     = *u32CodePoint;

  if(AIMJK_EXPECT_F(ch >= UNI_SUR_HIGH_START) && (AIMJK_EXPECT_T(ch <= UNI_SUR_LOW_END)))                                                        { result = sourceIllegal; ch = UNI_REPLACEMENT_CHAR; goto finished; }
  if(AIMJK_EXPECT_F(ch >= 0xFDD0U) && (AIMJK_EXPECT_F(ch <= 0xFDEFU) || AIMJK_EXPECT_F((ch & 0xFFFEU) == 0xFFFEU)) && AIMJK_EXPECT_T(ch <= 0x10FFFFU)) { result = sourceIllegal; ch = UNI_REPLACEMENT_CHAR; goto finished; }
  if(AIMJK_EXPECT_F(ch == 0U))                                                                                                                { result = sourceIllegal; ch = UNI_REPLACEMENT_CHAR; goto finished; }

 finished:
  *u32CodePoint = ch;
  return(result);
}


static int isLegalUTF8(const UTF8 *source, size_t length) {
  const UTF8 *srcptr = source + length;
  UTF8 a;

  switch(length) {
    default: return(0); // Everything else falls through when "true"...
    case 4: if(AIMJK_EXPECT_F(((a = (*--srcptr)) < 0x80) || (a > 0xBF))) { return(0); }
    case 3: if(AIMJK_EXPECT_F(((a = (*--srcptr)) < 0x80) || (a > 0xBF))) { return(0); }
    case 2: if(AIMJK_EXPECT_F( (a = (*--srcptr)) > 0xBF               )) { return(0); }
      
      switch(*source) { // no fall-through in this inner switch
        case 0xE0: if(AIMJK_EXPECT_F(a < 0xA0)) { return(0); } break;
        case 0xED: if(AIMJK_EXPECT_F(a > 0x9F)) { return(0); } break;
        case 0xF0: if(AIMJK_EXPECT_F(a < 0x90)) { return(0); } break;
        case 0xF4: if(AIMJK_EXPECT_F(a > 0x8F)) { return(0); } break;
        default:   if(AIMJK_EXPECT_F(a < 0x80)) { return(0); }
      }
      
    case 1: if(AIMJK_EXPECT_F((AIMJK_EXPECT_T(*source < 0xC2)) && AIMJK_EXPECT_F(*source >= 0x80))) { return(0); }
  }

  if(AIMJK_EXPECT_F(*source > 0xF4)) { return(0); }

  return(1);
}

static ConversionResult ConvertSingleCodePointInUTF8(const UTF8 *sourceStart, const UTF8 *sourceEnd, UTF8 const **nextUTF8, UTF32 *convertedUTF32) {
  ConversionResult result = conversionOK;
  const UTF8 *source = sourceStart;
  UTF32 ch = 0UL;

#if !defined(AIMJK_FAST_TRAILING_BYTES)
  unsigned short extraBytesToRead = trailingBytesForUTF8[*source];
#else
  unsigned short extraBytesToRead = __builtin_clz(((*source)^0xff) << 25);
#endif

  if(AIMJK_EXPECT_F((source + extraBytesToRead + 1) > sourceEnd) || AIMJK_EXPECT_F(!isLegalUTF8(source, extraBytesToRead + 1))) {
    source++;
    while((source < sourceEnd) && (((*source) & 0xc0) == 0x80) && ((source - sourceStart) < (extraBytesToRead + 1))) { source++; } 
    NSCParameterAssert(source <= sourceEnd);
    result = ((source < sourceEnd) && (((*source) & 0xc0) != 0x80)) ? sourceIllegal : ((sourceStart + extraBytesToRead + 1) > sourceEnd) ? sourceExhausted : sourceIllegal;
    ch = UNI_REPLACEMENT_CHAR;
    goto finished;
  }

  switch(extraBytesToRead) { // The cases all fall through.
    case 5: ch += *source++; ch <<= 6;
    case 4: ch += *source++; ch <<= 6;
    case 3: ch += *source++; ch <<= 6;
    case 2: ch += *source++; ch <<= 6;
    case 1: ch += *source++; ch <<= 6;
    case 0: ch += *source++;
  }
  ch -= offsetsFromUTF8[extraBytesToRead];

  result = isValidCodePoint(&ch);
  
 finished:
  *nextUTF8       = source;
  *convertedUTF32 = ch;
  
  return(result);
}


static ConversionResult ConvertUTF32toUTF8 (UTF32 u32CodePoint, UTF8 **targetStart, UTF8 *targetEnd) {
  const UTF32       byteMask     = 0xBF, byteMark = 0x80;
  ConversionResult  result       = conversionOK;
  UTF8             *target       = *targetStart;
  UTF32             ch           = u32CodePoint;
  unsigned short    bytesToWrite = 0;

  result = isValidCodePoint(&ch);

  // Figure out how many bytes the result will require. Turn any illegally large UTF32 things (> Plane 17) into replacement chars.
       if(ch < (UTF32)0x80)          { bytesToWrite = 1; }
  else if(ch < (UTF32)0x800)         { bytesToWrite = 2; }
  else if(ch < (UTF32)0x10000)       { bytesToWrite = 3; }
  else if(ch <= UNI_MAX_LEGAL_UTF32) { bytesToWrite = 4; }
  else {                               bytesToWrite = 3; ch = UNI_REPLACEMENT_CHAR; result = sourceIllegal; }
        
  target += bytesToWrite;
  if (target > targetEnd) { target -= bytesToWrite; result = targetExhausted; goto finished; }

  switch (bytesToWrite) { // note: everything falls through.
    case 4: *--target = (UTF8)((ch | byteMark) & byteMask); ch >>= 6;
    case 3: *--target = (UTF8)((ch | byteMark) & byteMask); ch >>= 6;
    case 2: *--target = (UTF8)((ch | byteMark) & byteMask); ch >>= 6;
    case 1: *--target = (UTF8) (ch | firstByteMark[bytesToWrite]);
  }

  target += bytesToWrite;

 finished:
  *targetStart = target;
  return(result);
}

AIMJK_STATIC_INLINE int AIMJK_string_add_unicodeCodePoint(AIMJKParseState *parseState, uint32_t unicodeCodePoint, size_t *tokenBufferIdx, AIMJKHash *stringHash) {
  UTF8             *u8s = &parseState->token.tokenBuffer.bytes.ptr[*tokenBufferIdx];
  ConversionResult  result;

  if((result = ConvertUTF32toUTF8(unicodeCodePoint, &u8s, (parseState->token.tokenBuffer.bytes.ptr + parseState->token.tokenBuffer.bytes.length))) != conversionOK) { if(result == targetExhausted) { return(1); } }
  size_t utf8len = u8s - &parseState->token.tokenBuffer.bytes.ptr[*tokenBufferIdx], nextIdx = (*tokenBufferIdx) + utf8len;
  
  while(*tokenBufferIdx < nextIdx) { *stringHash = AIMJK_calculateHash(*stringHash, parseState->token.tokenBuffer.bytes.ptr[(*tokenBufferIdx)++]); }

  return(0);
}

////////////
#pragma mark -
#pragma mark Decoding / parsing / deserializing functions

static int AIMJK_parse_string(AIMJKParseState *parseState) {
  NSCParameterAssert((parseState != NULL) && (AIMJK_AT_STRING_PTR(parseState) <= AIMJK_END_STRING_PTR(parseState)));
  const unsigned char *stringStart       = AIMJK_AT_STRING_PTR(parseState) + 1;
  const unsigned char *endOfBuffer       = AIMJK_END_STRING_PTR(parseState);
  const unsigned char *atStringCharacter = stringStart;
  unsigned char       *tokenBuffer       = parseState->token.tokenBuffer.bytes.ptr;
  size_t               tokenStartIndex   = parseState->atIndex;
  size_t               tokenBufferIdx    = 0UL;

  int      onlySimpleString        = 1,  stringState     = AIMJSONStringStateStart;
  uint16_t escapedUnicode1         = 0U, escapedUnicode2 = 0U;
  uint32_t escapedUnicodeCodePoint = 0U;
  AIMJKHash   stringHash              = AIMJK_HASH_INIT;
    
  while(1) {
    unsigned long currentChar;

    if(AIMJK_EXPECT_F(atStringCharacter == endOfBuffer)) { /* XXX Add error message */ stringState = AIMJSONStringStateError; goto finishedParsing; }
    
    if(AIMJK_EXPECT_F((currentChar = *atStringCharacter++) >= 0x80UL)) {
      const unsigned char *nextValidCharacter = NULL;
      UTF32                u32ch              = 0U;
      ConversionResult     result;

      if(AIMJK_EXPECT_F((result = ConvertSingleCodePointInUTF8(atStringCharacter - 1, endOfBuffer, (UTF8 const **)&nextValidCharacter, &u32ch)) != conversionOK)) { goto switchToSlowPath; }
      stringHash = AIMJK_calculateHash(stringHash, currentChar);
      while(atStringCharacter < nextValidCharacter) { NSCParameterAssert(AIMJK_AT_STRING_PTR(parseState) <= AIMJK_END_STRING_PTR(parseState)); stringHash = AIMJK_calculateHash(stringHash, *atStringCharacter++); }
      continue;
    } else {
      if(AIMJK_EXPECT_F(currentChar == (unsigned long)'"')) { stringState = AIMJSONStringStateFinished; goto finishedParsing; }

      if(AIMJK_EXPECT_F(currentChar == (unsigned long)'\\')) {
      switchToSlowPath:
        onlySimpleString = 0;
        stringState      = AIMJSONStringStateParsing;
        tokenBufferIdx   = (atStringCharacter - stringStart) - 1L;
        if(AIMJK_EXPECT_F((tokenBufferIdx + 16UL) > parseState->token.tokenBuffer.bytes.length)) { if((tokenBuffer = AIMJK_managedBuffer_resize(&parseState->token.tokenBuffer, tokenBufferIdx + 1024UL)) == NULL) { AIMJK_error(parseState, @"Internal error: Unable to resize temporary buffer. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; } }
        memcpy(tokenBuffer, stringStart, tokenBufferIdx);
        goto slowMatch;
      }

      if(AIMJK_EXPECT_F(currentChar < 0x20UL)) { AIMJK_error(parseState, @"Invalid character < 0x20 found in string: 0x%2.2x.", currentChar); stringState = AIMJSONStringStateError; goto finishedParsing; }

      stringHash = AIMJK_calculateHash(stringHash, currentChar);
    }
  }

 slowMatch:

  for(atStringCharacter = (stringStart + ((atStringCharacter - stringStart) - 1L)); (atStringCharacter < endOfBuffer) && (tokenBufferIdx < parseState->token.tokenBuffer.bytes.length); atStringCharacter++) {
    if((tokenBufferIdx + 16UL) > parseState->token.tokenBuffer.bytes.length) { if((tokenBuffer = AIMJK_managedBuffer_resize(&parseState->token.tokenBuffer, tokenBufferIdx + 1024UL)) == NULL) { AIMJK_error(parseState, @"Internal error: Unable to resize temporary buffer. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; } }

    NSCParameterAssert(tokenBufferIdx < parseState->token.tokenBuffer.bytes.length);

    unsigned long currentChar = (*atStringCharacter), escapedChar;

    if(AIMJK_EXPECT_T(stringState == AIMJSONStringStateParsing)) {
      if(AIMJK_EXPECT_T(currentChar >= 0x20UL)) {
        if(AIMJK_EXPECT_T(currentChar < (unsigned long)0x80)) { // Not a UTF8 sequence
          if(AIMJK_EXPECT_F(currentChar == (unsigned long)'"'))  { stringState = AIMJSONStringStateFinished; atStringCharacter++; goto finishedParsing; }
          if(AIMJK_EXPECT_F(currentChar == (unsigned long)'\\')) { stringState = AIMJSONStringStateEscape; continue; }
          stringHash = AIMJK_calculateHash(stringHash, currentChar);
          tokenBuffer[tokenBufferIdx++] = currentChar;
          continue;
        } else { // UTF8 sequence
          const unsigned char *nextValidCharacter = NULL;
          UTF32                u32ch              = 0U;
          ConversionResult     result;
          
          if(AIMJK_EXPECT_F((result = ConvertSingleCodePointInUTF8(atStringCharacter, endOfBuffer, (UTF8 const **)&nextValidCharacter, &u32ch)) != conversionOK)) {
            if((result == sourceIllegal) && ((parseState->parseOptionFlags & AIMJKParseOptionLooseUnicode) == 0)) { AIMJK_error(parseState, @"Illegal UTF8 sequence found in \"\" string.");              stringState = AIMJSONStringStateError; goto finishedParsing; }
            if(result == sourceExhausted)                                                                      { AIMJK_error(parseState, @"End of buffer reached while parsing UTF8 in \"\" string."); stringState = AIMJSONStringStateError; goto finishedParsing; }
            if(AIMJK_string_add_unicodeCodePoint(parseState, u32ch, &tokenBufferIdx, &stringHash))                { AIMJK_error(parseState, @"Internal error: Unable to add UTF8 sequence to internal string buffer. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; }
            atStringCharacter = nextValidCharacter - 1;
            continue;
          } else {
            while(atStringCharacter < nextValidCharacter) { tokenBuffer[tokenBufferIdx++] = *atStringCharacter; stringHash = AIMJK_calculateHash(stringHash, *atStringCharacter++); }
            atStringCharacter--;
            continue;
          }
        }
      } else { // currentChar < 0x20
        AIMJK_error(parseState, @"Invalid character < 0x20 found in string: 0x%2.2x.", currentChar); stringState = AIMJSONStringStateError; goto finishedParsing;
      }

    } else { // stringState != AIMJSONStringStateParsing
      int isSurrogate = 1;

      switch(stringState) {
        case AIMJSONStringStateEscape:
          switch(currentChar) {
            case 'u': escapedUnicode1 = 0U; escapedUnicode2 = 0U; escapedUnicodeCodePoint = 0U; stringState = AIMJSONStringStateEscapedUnicode1; break;

            case 'b':  escapedChar = '\b'; goto parsedEscapedChar;
            case 'f':  escapedChar = '\f'; goto parsedEscapedChar;
            case 'n':  escapedChar = '\n'; goto parsedEscapedChar;
            case 'r':  escapedChar = '\r'; goto parsedEscapedChar;
            case 't':  escapedChar = '\t'; goto parsedEscapedChar;
            case '\\': escapedChar = '\\'; goto parsedEscapedChar;
            case '/':  escapedChar = '/';  goto parsedEscapedChar;
            case '"':  escapedChar = '"';  goto parsedEscapedChar;
              
            parsedEscapedChar:
              stringState = AIMJSONStringStateParsing;
              stringHash  = AIMJK_calculateHash(stringHash, escapedChar);
              tokenBuffer[tokenBufferIdx++] = escapedChar;
              break;
              
            default: AIMJK_error(parseState, @"Invalid escape sequence found in \"\" string."); stringState = AIMJSONStringStateError; goto finishedParsing; break;
          }
          break;

        case AIMJSONStringStateEscapedUnicode1:
        case AIMJSONStringStateEscapedUnicode2:
        case AIMJSONStringStateEscapedUnicode3:
        case AIMJSONStringStateEscapedUnicode4:           isSurrogate = 0;
        case AIMJSONStringStateEscapedUnicodeSurrogate1:
        case AIMJSONStringStateEscapedUnicodeSurrogate2:
        case AIMJSONStringStateEscapedUnicodeSurrogate3:
        case AIMJSONStringStateEscapedUnicodeSurrogate4:
          {
            uint16_t hexValue = 0U;

            switch(currentChar) {
              case '0' ... '9': hexValue =  currentChar - '0';        goto parsedHex;
              case 'a' ... 'f': hexValue = (currentChar - 'a') + 10U; goto parsedHex;
              case 'A' ... 'F': hexValue = (currentChar - 'A') + 10U; goto parsedHex;
                
              parsedHex:
              if(!isSurrogate) { escapedUnicode1 = (escapedUnicode1 << 4) | hexValue; } else { escapedUnicode2 = (escapedUnicode2 << 4) | hexValue; }
                
              if(stringState == AIMJSONStringStateEscapedUnicode4) {
                if(((escapedUnicode1 >= 0xD800U) && (escapedUnicode1 < 0xE000U))) {
                  if((escapedUnicode1 >= 0xD800U) && (escapedUnicode1 < 0xDC00U)) { stringState = AIMJSONStringStateEscapedNeedEscapeForSurrogate; }
                  else if((escapedUnicode1 >= 0xDC00U) && (escapedUnicode1 < 0xE000U)) { 
                    if((parseState->parseOptionFlags & AIMJKParseOptionLooseUnicode)) { escapedUnicodeCodePoint = UNI_REPLACEMENT_CHAR; }
                    else { AIMJK_error(parseState, @"Illegal \\u Unicode escape sequence."); stringState = AIMJSONStringStateError; goto finishedParsing; }
                  }
                }
                else { escapedUnicodeCodePoint = escapedUnicode1; }
              }

              if(stringState == AIMJSONStringStateEscapedUnicodeSurrogate4) {
                if((escapedUnicode2 < 0xdc00) || (escapedUnicode2 > 0xdfff)) {
                  if((parseState->parseOptionFlags & AIMJKParseOptionLooseUnicode)) { escapedUnicodeCodePoint = UNI_REPLACEMENT_CHAR; }
                  else { AIMJK_error(parseState, @"Illegal \\u Unicode escape sequence."); stringState = AIMJSONStringStateError; goto finishedParsing; }
                }
                else { escapedUnicodeCodePoint = ((escapedUnicode1 - 0xd800) * 0x400) + (escapedUnicode2 - 0xdc00) + 0x10000; }
              }
                
              if((stringState == AIMJSONStringStateEscapedUnicode4) || (stringState == AIMJSONStringStateEscapedUnicodeSurrogate4)) { 
                if((isValidCodePoint(&escapedUnicodeCodePoint) == sourceIllegal) && ((parseState->parseOptionFlags & AIMJKParseOptionLooseUnicode) == 0)) { AIMJK_error(parseState, @"Illegal \\u Unicode escape sequence."); stringState = AIMJSONStringStateError; goto finishedParsing; }
                stringState = AIMJSONStringStateParsing;
                if(AIMJK_string_add_unicodeCodePoint(parseState, escapedUnicodeCodePoint, &tokenBufferIdx, &stringHash)) { AIMJK_error(parseState, @"Internal error: Unable to add UTF8 sequence to internal string buffer. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; }
              }
              else if((stringState >= AIMJSONStringStateEscapedUnicode1) && (stringState <= AIMJSONStringStateEscapedUnicodeSurrogate4)) { stringState++; }
              break;

              default: AIMJK_error(parseState, @"Unexpected character found in \\u Unicode escape sequence.  Found '%c', expected [0-9a-fA-F].", currentChar); stringState = AIMJSONStringStateError; goto finishedParsing; break;
            }
          }
          break;

        case AIMJSONStringStateEscapedNeedEscapeForSurrogate:
          if(currentChar == '\\') { stringState = AIMJSONStringStateEscapedNeedEscapedUForSurrogate; }
          else { 
            if((parseState->parseOptionFlags & AIMJKParseOptionLooseUnicode) == 0) { AIMJK_error(parseState, @"Required a second \\u Unicode escape sequence following a surrogate \\u Unicode escape sequence."); stringState = AIMJSONStringStateError; goto finishedParsing; }
            else { stringState = AIMJSONStringStateParsing; atStringCharacter--;    if(AIMJK_string_add_unicodeCodePoint(parseState, UNI_REPLACEMENT_CHAR, &tokenBufferIdx, &stringHash)) { AIMJK_error(parseState, @"Internal error: Unable to add UTF8 sequence to internal string buffer. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; } }
          }
          break;

        case AIMJSONStringStateEscapedNeedEscapedUForSurrogate:
          if(currentChar == 'u') { stringState = AIMJSONStringStateEscapedUnicodeSurrogate1; }
          else { 
            if((parseState->parseOptionFlags & AIMJKParseOptionLooseUnicode) == 0) { AIMJK_error(parseState, @"Required a second \\u Unicode escape sequence following a surrogate \\u Unicode escape sequence."); stringState = AIMJSONStringStateError; goto finishedParsing; }
            else { stringState = AIMJSONStringStateParsing; atStringCharacter -= 2; if(AIMJK_string_add_unicodeCodePoint(parseState, UNI_REPLACEMENT_CHAR, &tokenBufferIdx, &stringHash)) { AIMJK_error(parseState, @"Internal error: Unable to add UTF8 sequence to internal string buffer. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; } }
          }
          break;

        default: AIMJK_error(parseState, @"Internal error: Unknown stringState. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); stringState = AIMJSONStringStateError; goto finishedParsing; break;
      }
    }
  }

finishedParsing:

  if(AIMJK_EXPECT_T(stringState == AIMJSONStringStateFinished)) {
    NSCParameterAssert((parseState->stringBuffer.bytes.ptr + tokenStartIndex) < atStringCharacter);

    parseState->token.tokenPtrRange.ptr    = parseState->stringBuffer.bytes.ptr + tokenStartIndex;
    parseState->token.tokenPtrRange.length = (atStringCharacter - parseState->token.tokenPtrRange.ptr);

    if(AIMJK_EXPECT_T(onlySimpleString)) {
      NSCParameterAssert(((parseState->token.tokenPtrRange.ptr + 1) < endOfBuffer) && (parseState->token.tokenPtrRange.length >= 2UL) && (((parseState->token.tokenPtrRange.ptr + 1) + (parseState->token.tokenPtrRange.length - 2)) < endOfBuffer));
      parseState->token.value.ptrRange.ptr    = parseState->token.tokenPtrRange.ptr    + 1;
      parseState->token.value.ptrRange.length = parseState->token.tokenPtrRange.length - 2UL;
    } else {
      parseState->token.value.ptrRange.ptr    = parseState->token.tokenBuffer.bytes.ptr;
      parseState->token.value.ptrRange.length = tokenBufferIdx;
    }
    
    parseState->token.value.hash = stringHash;
    parseState->token.value.type = AIMJKValueTypeString;
    parseState->atIndex          = (atStringCharacter - parseState->stringBuffer.bytes.ptr);
  }

  if(AIMJK_EXPECT_F(stringState != AIMJSONStringStateFinished)) { AIMJK_error(parseState, @"Invalid string."); }
  return(AIMJK_EXPECT_T(stringState == AIMJSONStringStateFinished) ? 0 : 1);
}

static int AIMJK_parse_number(AIMJKParseState *parseState) {
  NSCParameterAssert((parseState != NULL) && (AIMJK_AT_STRING_PTR(parseState) <= AIMJK_END_STRING_PTR(parseState)));
  const unsigned char *numberStart       = AIMJK_AT_STRING_PTR(parseState);
  const unsigned char *endOfBuffer       = AIMJK_END_STRING_PTR(parseState);
  const unsigned char *atNumberCharacter = NULL;
  int                  numberState       = AIMJSONNumberStateWholeNumberStart, isFloatingPoint = 0, isNegative = 0, backup = 0;
  size_t               startingIndex     = parseState->atIndex;
  
  for(atNumberCharacter = numberStart; (AIMJK_EXPECT_T(atNumberCharacter < endOfBuffer)) && (AIMJK_EXPECT_T(!(AIMJK_EXPECT_F(numberState == AIMJSONNumberStateFinished) || AIMJK_EXPECT_F(numberState == AIMJSONNumberStateError)))); atNumberCharacter++) {
    unsigned long currentChar = (unsigned long)(*atNumberCharacter), lowerCaseCC = currentChar | 0x20UL;
    
    switch(numberState) {
      case AIMJSONNumberStateWholeNumberStart: if   (currentChar == '-')                                                                              { numberState = AIMJSONNumberStateWholeNumberMinus;      isNegative      = 1; break; }
      case AIMJSONNumberStateWholeNumberMinus: if   (currentChar == '0')                                                                              { numberState = AIMJSONNumberStateWholeNumberZero;                            break; }
                                       else if(  (currentChar >= '1') && (currentChar <= '9'))                                                     { numberState = AIMJSONNumberStateWholeNumber;                                break; }
                                       else                                                     { /* XXX Add error message */                        numberState = AIMJSONNumberStateError;                                      break; }
      case AIMJSONNumberStateExponentStart:    if(  (currentChar == '+') || (currentChar == '-'))                                                     { numberState = AIMJSONNumberStateExponentPlusMinus;                          break; }
      case AIMJSONNumberStateFractionalNumberStart:
      case AIMJSONNumberStateExponentPlusMinus:if(!((currentChar >= '0') && (currentChar <= '9'))) { /* XXX Add error message */                        numberState = AIMJSONNumberStateError;                                      break; }
                                       else {                                              if(numberState == AIMJSONNumberStateFractionalNumberStart) { numberState = AIMJSONNumberStateFractionalNumber; }
                                                                                           else                                                    { numberState = AIMJSONNumberStateExponent;         }                         break; }
      case AIMJSONNumberStateWholeNumberZero:
      case AIMJSONNumberStateWholeNumber:      if   (currentChar == '.')                                                                              { numberState = AIMJSONNumberStateFractionalNumberStart; isFloatingPoint = 1; break; }
      case AIMJSONNumberStateFractionalNumber: if   (lowerCaseCC == 'e')                                                                              { numberState = AIMJSONNumberStateExponentStart;         isFloatingPoint = 1; break; }
      case AIMJSONNumberStateExponent:         if(!((currentChar >= '0') && (currentChar <= '9')) || (numberState == AIMJSONNumberStateWholeNumberZero)) { numberState = AIMJSONNumberStateFinished;              backup          = 1; break; }
        break;
      default:                                                                                    /* XXX Add error message */                        numberState = AIMJSONNumberStateError;                                      break;
    }
  }
  
  parseState->token.tokenPtrRange.ptr    = parseState->stringBuffer.bytes.ptr + startingIndex;
  parseState->token.tokenPtrRange.length = (atNumberCharacter - parseState->token.tokenPtrRange.ptr) - backup;
  parseState->atIndex                    = (parseState->token.tokenPtrRange.ptr + parseState->token.tokenPtrRange.length) - parseState->stringBuffer.bytes.ptr;

  if(AIMJK_EXPECT_T(numberState == AIMJSONNumberStateFinished)) {
    unsigned char  numberTempBuf[parseState->token.tokenPtrRange.length + 4UL];
    unsigned char *endOfNumber = NULL;

    memcpy(numberTempBuf, parseState->token.tokenPtrRange.ptr, parseState->token.tokenPtrRange.length);
    numberTempBuf[parseState->token.tokenPtrRange.length] = 0;

    errno = 0;
    
    // Treat "-0" as a floating point number, which is capable of representing negative zeros.
    if(AIMJK_EXPECT_F(parseState->token.tokenPtrRange.length == 2UL) && AIMJK_EXPECT_F(numberTempBuf[1] == '0') && AIMJK_EXPECT_F(isNegative)) { isFloatingPoint = 1; }

    if(isFloatingPoint) {
      parseState->token.value.number.doubleValue = strtod((const char *)numberTempBuf, (char **)&endOfNumber); // strtod is documented to return U+2261 (identical to) 0.0 on an underflow error (along with setting errno to ERANGE).
      parseState->token.value.type               = AIMJKValueTypeDouble;
      parseState->token.value.ptrRange.ptr       = (const unsigned char *)&parseState->token.value.number.doubleValue;
      parseState->token.value.ptrRange.length    = sizeof(double);
      parseState->token.value.hash               = (AIMJK_HASH_INIT + parseState->token.value.type);
    } else {
      if(isNegative) {
        parseState->token.value.number.longLongValue = strtoll((const char *)numberTempBuf, (char **)&endOfNumber, 10);
        parseState->token.value.type                 = AIMJKValueTypeLongLong;
        parseState->token.value.ptrRange.ptr         = (const unsigned char *)&parseState->token.value.number.longLongValue;
        parseState->token.value.ptrRange.length      = sizeof(long long);
        parseState->token.value.hash                 = (AIMJK_HASH_INIT + parseState->token.value.type) + (AIMJKHash)parseState->token.value.number.longLongValue;
      } else {
        parseState->token.value.number.unsignedLongLongValue = strtoull((const char *)numberTempBuf, (char **)&endOfNumber, 10);
        parseState->token.value.type                         = AIMJKValueTypeUnsignedLongLong;
        parseState->token.value.ptrRange.ptr                 = (const unsigned char *)&parseState->token.value.number.unsignedLongLongValue;
        parseState->token.value.ptrRange.length              = sizeof(unsigned long long);
        parseState->token.value.hash                         = (AIMJK_HASH_INIT + parseState->token.value.type) + (AIMJKHash)parseState->token.value.number.unsignedLongLongValue;
      }
    }

    if(AIMJK_EXPECT_F(errno != 0)) {
      numberState = AIMJSONNumberStateError;
      if(errno == ERANGE) {
        switch(parseState->token.value.type) {
          case AIMJKValueTypeDouble:           AIMJK_error(parseState, @"The value '%s' could not be represented as a 'double' due to %s.",           numberTempBuf, (parseState->token.value.number.doubleValue == 0.0) ? "underflow" : "overflow"); break; // see above for == 0.0.
          case AIMJKValueTypeLongLong:         AIMJK_error(parseState, @"The value '%s' exceeded the minimum value that could be represented: %lld.", numberTempBuf, parseState->token.value.number.longLongValue);                                   break;
          case AIMJKValueTypeUnsignedLongLong: AIMJK_error(parseState, @"The value '%s' exceeded the maximum value that could be represented: %llu.", numberTempBuf, parseState->token.value.number.unsignedLongLongValue);                           break;
          default:                          AIMJK_error(parseState, @"Internal error: Unknown token value type. %@ line #%ld",                     [NSString stringWithUTF8String:__FILE__], (long)__LINE__);                                      break;
        }
      }
    }
    if(AIMJK_EXPECT_F(endOfNumber != &numberTempBuf[parseState->token.tokenPtrRange.length]) && AIMJK_EXPECT_F(numberState != AIMJSONNumberStateError)) { numberState = AIMJSONNumberStateError; AIMJK_error(parseState, @"The conversion function did not consume all of the number tokens characters."); }

    size_t hashIndex = 0UL;
    for(hashIndex = 0UL; hashIndex < parseState->token.value.ptrRange.length; hashIndex++) { parseState->token.value.hash = AIMJK_calculateHash(parseState->token.value.hash, parseState->token.value.ptrRange.ptr[hashIndex]); }
  }

  if(AIMJK_EXPECT_F(numberState != AIMJSONNumberStateFinished)) { AIMJK_error(parseState, @"Invalid number."); }
  return(AIMJK_EXPECT_T((numberState == AIMJSONNumberStateFinished)) ? 0 : 1);
}

AIMJK_STATIC_INLINE void AIMJK_set_parsed_token(AIMJKParseState *parseState, const unsigned char *ptr, size_t length, AIMJKTokenType type, size_t advanceBy) {
  parseState->token.tokenPtrRange.ptr     = ptr;
  parseState->token.tokenPtrRange.length  = length;
  parseState->token.type                  = type;
  parseState->atIndex                    += advanceBy;
}

static size_t AIMJK_parse_is_newline(AIMJKParseState *parseState, const unsigned char *atCharacterPtr) {
  NSCParameterAssert((parseState != NULL) && (atCharacterPtr != NULL) && (atCharacterPtr >= parseState->stringBuffer.bytes.ptr) && (atCharacterPtr < AIMJK_END_STRING_PTR(parseState)));
  const unsigned char *endOfStringPtr = AIMJK_END_STRING_PTR(parseState);

  if(AIMJK_EXPECT_F(atCharacterPtr >= endOfStringPtr)) { return(0UL); }

  if(AIMJK_EXPECT_F((*(atCharacterPtr + 0)) == '\n')) { return(1UL); }
  if(AIMJK_EXPECT_F((*(atCharacterPtr + 0)) == '\r')) { if((AIMJK_EXPECT_T((atCharacterPtr + 1) < endOfStringPtr)) && ((*(atCharacterPtr + 1)) == '\n')) { return(2UL); } return(1UL); }
  if(parseState->parseOptionFlags & AIMJKParseOptionUnicodeNewlines) {
    if((AIMJK_EXPECT_F((*(atCharacterPtr + 0)) == 0xc2)) && (((atCharacterPtr + 1) < endOfStringPtr) && ((*(atCharacterPtr + 1)) == 0x85))) { return(2UL); }
    if((AIMJK_EXPECT_F((*(atCharacterPtr + 0)) == 0xe2)) && (((atCharacterPtr + 2) < endOfStringPtr) && ((*(atCharacterPtr + 1)) == 0x80) && (((*(atCharacterPtr + 2)) == 0xa8) || ((*(atCharacterPtr + 2)) == 0xa9)))) { return(3UL); }
  }

  return(0UL);
}

AIMJK_STATIC_INLINE int AIMJK_parse_skip_newline(AIMJKParseState *parseState) {
  size_t newlineAdvanceAtIndex = 0UL;
  if(AIMJK_EXPECT_F((newlineAdvanceAtIndex = AIMJK_parse_is_newline(parseState, AIMJK_AT_STRING_PTR(parseState))) > 0UL)) { parseState->lineNumber++; parseState->atIndex += (newlineAdvanceAtIndex - 1UL); parseState->lineStartIndex = parseState->atIndex + 1UL; return(1); }
  return(0);
}

AIMJK_STATIC_INLINE void AIMJK_parse_skip_whitespace(AIMJKParseState *parseState) {
#ifndef __clang_analyzer__
  NSCParameterAssert((parseState != NULL) && (AIMJK_AT_STRING_PTR(parseState) <= AIMJK_END_STRING_PTR(parseState)));
  const unsigned char *atCharacterPtr   = NULL;
  const unsigned char *endOfStringPtr   = AIMJK_END_STRING_PTR(parseState);

  for(atCharacterPtr = AIMJK_AT_STRING_PTR(parseState); (AIMJK_EXPECT_T((atCharacterPtr = AIMJK_AT_STRING_PTR(parseState)) < endOfStringPtr)); parseState->atIndex++) {
    if(((*(atCharacterPtr + 0)) == ' ') || ((*(atCharacterPtr + 0)) == '\t')) { continue; }
    if(AIMJK_parse_skip_newline(parseState)) { continue; }
    if(parseState->parseOptionFlags & AIMJKParseOptionComments) {
      if((AIMJK_EXPECT_F((*(atCharacterPtr + 0)) == '/')) && (AIMJK_EXPECT_T((atCharacterPtr + 1) < endOfStringPtr))) {
        if((*(atCharacterPtr + 1)) == '/') {
          parseState->atIndex++;
          for(atCharacterPtr = AIMJK_AT_STRING_PTR(parseState); (AIMJK_EXPECT_T((atCharacterPtr = AIMJK_AT_STRING_PTR(parseState)) < endOfStringPtr)); parseState->atIndex++) { if(AIMJK_parse_skip_newline(parseState)) { break; } }
          continue;
        }
        if((*(atCharacterPtr + 1)) == '*') {
          parseState->atIndex++;
          for(atCharacterPtr = AIMJK_AT_STRING_PTR(parseState); (AIMJK_EXPECT_T((atCharacterPtr = AIMJK_AT_STRING_PTR(parseState)) < endOfStringPtr)); parseState->atIndex++) {
            if(AIMJK_parse_skip_newline(parseState)) { continue; }
            if(((*(atCharacterPtr + 0)) == '*') && (((atCharacterPtr + 1) < endOfStringPtr) && ((*(atCharacterPtr + 1)) == '/'))) { parseState->atIndex++; break; }
          }
          continue;
        }
      }
    }
    break;
  }
#endif
}

static int AIMJK_parse_next_token(AIMJKParseState *parseState) {
  NSCParameterAssert((parseState != NULL) && (AIMJK_AT_STRING_PTR(parseState) <= AIMJK_END_STRING_PTR(parseState)));
  const unsigned char *atCharacterPtr   = NULL;
  const unsigned char *endOfStringPtr   = AIMJK_END_STRING_PTR(parseState);
  unsigned char        currentCharacter = 0U;
  int                  stopParsing      = 0;

  parseState->prev_atIndex        = parseState->atIndex;
  parseState->prev_lineNumber     = parseState->lineNumber;
  parseState->prev_lineStartIndex = parseState->lineStartIndex;

  AIMJK_parse_skip_whitespace(parseState);

  if((AIMJK_AT_STRING_PTR(parseState) == endOfStringPtr)) { stopParsing = 1; }

  if((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T((atCharacterPtr = AIMJK_AT_STRING_PTR(parseState)) < endOfStringPtr))) {
    currentCharacter = *atCharacterPtr;

         if(AIMJK_EXPECT_T(currentCharacter == '"')) { if(AIMJK_EXPECT_T((stopParsing = AIMJK_parse_string(parseState)) == 0)) { AIMJK_set_parsed_token(parseState, parseState->token.tokenPtrRange.ptr, parseState->token.tokenPtrRange.length, AIMJKTokenTypeString, 0UL); } }
    else if(AIMJK_EXPECT_T(currentCharacter == ':')) { AIMJK_set_parsed_token(parseState, atCharacterPtr, 1UL, AIMJKTokenTypeSeparator,   1UL); }
    else if(AIMJK_EXPECT_T(currentCharacter == ',')) { AIMJK_set_parsed_token(parseState, atCharacterPtr, 1UL, AIMJKTokenTypeComma,       1UL); }
    else if((AIMJK_EXPECT_T(currentCharacter >= '0') && AIMJK_EXPECT_T(currentCharacter <= '9')) || AIMJK_EXPECT_T(currentCharacter == '-')) { if(AIMJK_EXPECT_T((stopParsing = AIMJK_parse_number(parseState)) == 0)) { AIMJK_set_parsed_token(parseState, parseState->token.tokenPtrRange.ptr, parseState->token.tokenPtrRange.length, AIMJKTokenTypeNumber, 0UL); } }
    else if(AIMJK_EXPECT_T(currentCharacter == '{')) { AIMJK_set_parsed_token(parseState, atCharacterPtr, 1UL, AIMJKTokenTypeObjectBegin, 1UL); }
    else if(AIMJK_EXPECT_T(currentCharacter == '}')) { AIMJK_set_parsed_token(parseState, atCharacterPtr, 1UL, AIMJKTokenTypeObjectEnd,   1UL); }
    else if(AIMJK_EXPECT_T(currentCharacter == '[')) { AIMJK_set_parsed_token(parseState, atCharacterPtr, 1UL, AIMJKTokenTypeArrayBegin,  1UL); }
    else if(AIMJK_EXPECT_T(currentCharacter == ']')) { AIMJK_set_parsed_token(parseState, atCharacterPtr, 1UL, AIMJKTokenTypeArrayEnd,    1UL); }
    
    else if(AIMJK_EXPECT_T(currentCharacter == 't')) { if(!((AIMJK_EXPECT_T((atCharacterPtr + 4UL) < endOfStringPtr)) && (AIMJK_EXPECT_T(atCharacterPtr[1] == 'r')) && (AIMJK_EXPECT_T(atCharacterPtr[2] == 'u')) && (AIMJK_EXPECT_T(atCharacterPtr[3] == 'e'))))                                            { stopParsing = 1; /* XXX Add error message */ } else { AIMJK_set_parsed_token(parseState, atCharacterPtr, 4UL, AIMJKTokenTypeTrue,  4UL); } }
    else if(AIMJK_EXPECT_T(currentCharacter == 'f')) { if(!((AIMJK_EXPECT_T((atCharacterPtr + 5UL) < endOfStringPtr)) && (AIMJK_EXPECT_T(atCharacterPtr[1] == 'a')) && (AIMJK_EXPECT_T(atCharacterPtr[2] == 'l')) && (AIMJK_EXPECT_T(atCharacterPtr[3] == 's')) && (AIMJK_EXPECT_T(atCharacterPtr[4] == 'e')))) { stopParsing = 1; /* XXX Add error message */ } else { AIMJK_set_parsed_token(parseState, atCharacterPtr, 5UL, AIMJKTokenTypeFalse, 5UL); } }
    else if(AIMJK_EXPECT_T(currentCharacter == 'n')) { if(!((AIMJK_EXPECT_T((atCharacterPtr + 4UL) < endOfStringPtr)) && (AIMJK_EXPECT_T(atCharacterPtr[1] == 'u')) && (AIMJK_EXPECT_T(atCharacterPtr[2] == 'l')) && (AIMJK_EXPECT_T(atCharacterPtr[3] == 'l'))))                                            { stopParsing = 1; /* XXX Add error message */ } else { AIMJK_set_parsed_token(parseState, atCharacterPtr, 4UL, AIMJKTokenTypeNull,  4UL); } }
    else { stopParsing = 1; /* XXX Add error message */ }    
  }

  if(AIMJK_EXPECT_F(stopParsing)) { AIMJK_error(parseState, @"Unexpected token, wanted '{', '}', '[', ']', ',', ':', 'true', 'false', 'null', '\"STRING\"', 'NUMBER'."); }
  return(stopParsing);
}

static void AIMJK_error_parse_accept_or3(AIMJKParseState *parseState, int state, NSString *or1String, NSString *or2String, NSString *or3String) {
  NSString *acceptStrings[16];
  int acceptIdx = 0;
  if(state & AIMJKParseAcceptValue) { acceptStrings[acceptIdx++] = or1String; }
  if(state & AIMJKParseAcceptComma) { acceptStrings[acceptIdx++] = or2String; }
  if(state & AIMJKParseAcceptEnd)   { acceptStrings[acceptIdx++] = or3String; }
       if(acceptIdx == 1) { AIMJK_error(parseState, @"Expected %@, not '%*.*s'",           acceptStrings[0],                                     (int)parseState->token.tokenPtrRange.length, (int)parseState->token.tokenPtrRange.length, parseState->token.tokenPtrRange.ptr); }
  else if(acceptIdx == 2) { AIMJK_error(parseState, @"Expected %@ or %@, not '%*.*s'",     acceptStrings[0], acceptStrings[1],                   (int)parseState->token.tokenPtrRange.length, (int)parseState->token.tokenPtrRange.length, parseState->token.tokenPtrRange.ptr); }
  else if(acceptIdx == 3) { AIMJK_error(parseState, @"Expected %@, %@, or %@, not '%*.*s", acceptStrings[0], acceptStrings[1], acceptStrings[2], (int)parseState->token.tokenPtrRange.length, (int)parseState->token.tokenPtrRange.length, parseState->token.tokenPtrRange.ptr); }
}

static void *AIMJK_parse_array(AIMJKParseState *parseState) {
  size_t  startingObjectIndex = parseState->objectStack.index;
  int     arrayState          = AIMJKParseAcceptValueOrEnd, stopParsing = 0;
  void   *parsedArray         = NULL;

  while(AIMJK_EXPECT_T((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T(parseState->atIndex < parseState->stringBuffer.bytes.length)))) {
    if(AIMJK_EXPECT_F(parseState->objectStack.index > (parseState->objectStack.count - 4UL))) { if(AIMJK_objectStack_resize(&parseState->objectStack, parseState->objectStack.count + 128UL)) { AIMJK_error(parseState, @"Internal error: [array] objectsIndex > %zu, resize failed? %@ line %#ld", (parseState->objectStack.count - 4UL), [NSString stringWithUTF8String:__FILE__], (long)__LINE__); break; } }

    if(AIMJK_EXPECT_T((stopParsing = AIMJK_parse_next_token(parseState)) == 0)) {
      void *object = NULL;
#ifndef NS_BLOCK_ASSERTIONS
      parseState->objectStack.objects[parseState->objectStack.index] = NULL;
      parseState->objectStack.keys   [parseState->objectStack.index] = NULL;
#endif
      switch(parseState->token.type) {
        case AIMJKTokenTypeNumber:
        case AIMJKTokenTypeString:
        case AIMJKTokenTypeTrue:
        case AIMJKTokenTypeFalse:
        case AIMJKTokenTypeNull:
        case AIMJKTokenTypeArrayBegin:
        case AIMJKTokenTypeObjectBegin:
          if(AIMJK_EXPECT_F((arrayState & AIMJKParseAcceptValue)          == 0))    { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected value.");              stopParsing = 1; break; }
          if(AIMJK_EXPECT_F((object = AIMJK_object_for_token(parseState)) == NULL)) {                              AIMJK_error(parseState, @"Internal error: Object == NULL"); stopParsing = 1; break; } else { parseState->objectStack.objects[parseState->objectStack.index++] = object; arrayState = AIMJKParseAcceptCommaOrEnd; }
          break;
        case AIMJKTokenTypeArrayEnd: if(AIMJK_EXPECT_T(arrayState & AIMJKParseAcceptEnd)) { NSCParameterAssert(parseState->objectStack.index >= startingObjectIndex); parsedArray = (void *)_JKArrayCreate((id *)&parseState->objectStack.objects[startingObjectIndex], (parseState->objectStack.index - startingObjectIndex), parseState->mutableCollections); } else { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected ']'."); } stopParsing = 1; break;
        case AIMJKTokenTypeComma:    if(AIMJK_EXPECT_T(arrayState & AIMJKParseAcceptComma)) { arrayState = AIMJKParseAcceptValue; } else { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected ','."); stopParsing = 1; } break;
        default: parseState->errorIsPrev = 1; AIMJK_error_parse_accept_or3(parseState, arrayState, @"a value", @"a comma", @"a ']'"); stopParsing = 1; break;
      }
    }
  }

  if(AIMJK_EXPECT_F(parsedArray == NULL)) { size_t idx = 0UL; for(idx = startingObjectIndex; idx < parseState->objectStack.index; idx++) { if(parseState->objectStack.objects[idx] != NULL) { CFRelease(parseState->objectStack.objects[idx]); parseState->objectStack.objects[idx] = NULL; } } }
#if !defined(NS_BLOCK_ASSERTIONS)
  else { size_t idx = 0UL; for(idx = startingObjectIndex; idx < parseState->objectStack.index; idx++) { parseState->objectStack.objects[idx] = NULL; parseState->objectStack.keys[idx] = NULL; } }
#endif
  
  parseState->objectStack.index = startingObjectIndex;
  return(parsedArray);
}

static void *AIMJK_create_dictionary(AIMJKParseState *parseState, size_t startingObjectIndex) {
  void *parsedDictionary = NULL;

  parseState->objectStack.index--;

  parsedDictionary = _JKDictionaryCreate((id *)&parseState->objectStack.keys[startingObjectIndex], (NSUInteger *)&parseState->objectStack.cfHashes[startingObjectIndex], (id *)&parseState->objectStack.objects[startingObjectIndex], (parseState->objectStack.index - startingObjectIndex), parseState->mutableCollections);

  return(parsedDictionary);
}

static void *AIMJK_parse_dictionary(AIMJKParseState *parseState) {
  size_t  startingObjectIndex = parseState->objectStack.index;
  int     dictState           = AIMJKParseAcceptValueOrEnd, stopParsing = 0;
  void   *parsedDictionary    = NULL;

  while(AIMJK_EXPECT_T((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T(parseState->atIndex < parseState->stringBuffer.bytes.length)))) {
    if(AIMJK_EXPECT_F(parseState->objectStack.index > (parseState->objectStack.count - 4UL))) { if(AIMJK_objectStack_resize(&parseState->objectStack, parseState->objectStack.count + 128UL)) { AIMJK_error(parseState, @"Internal error: [dictionary] objectsIndex > %zu, resize failed? %@ line #%ld", (parseState->objectStack.count - 4UL), [NSString stringWithUTF8String:__FILE__], (long)__LINE__); break; } }

    size_t objectStackIndex = parseState->objectStack.index++;
    parseState->objectStack.keys[objectStackIndex]    = NULL;
    parseState->objectStack.objects[objectStackIndex] = NULL;
    void *key = NULL, *object = NULL;

    if(AIMJK_EXPECT_T((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T((stopParsing = AIMJK_parse_next_token(parseState)) == 0)))) {
      switch(parseState->token.type) {
        case AIMJKTokenTypeString:
          if(AIMJK_EXPECT_F((dictState & AIMJKParseAcceptValue)        == 0))    { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected string.");           stopParsing = 1; break; }
          if(AIMJK_EXPECT_F((key = AIMJK_object_for_token(parseState)) == NULL)) {                              AIMJK_error(parseState, @"Internal error: Key == NULL."); stopParsing = 1; break; }
          else {
            parseState->objectStack.keys[objectStackIndex] = key;
            if(AIMJK_EXPECT_T(parseState->token.value.cacheItem != NULL)) { if(AIMJK_EXPECT_F(parseState->token.value.cacheItem->cfHash == 0UL)) { parseState->token.value.cacheItem->cfHash = CFHash(key); } parseState->objectStack.cfHashes[objectStackIndex] = parseState->token.value.cacheItem->cfHash; }
            else { parseState->objectStack.cfHashes[objectStackIndex] = CFHash(key); }
          }
          break;

        case AIMJKTokenTypeObjectEnd: if((AIMJK_EXPECT_T(dictState & AIMJKParseAcceptEnd)))   { NSCParameterAssert(parseState->objectStack.index >= startingObjectIndex); parsedDictionary = AIMJK_create_dictionary(parseState, startingObjectIndex); } else { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected '}'."); } stopParsing = 1; break;
        case AIMJKTokenTypeComma:     if((AIMJK_EXPECT_T(dictState & AIMJKParseAcceptComma))) { dictState = AIMJKParseAcceptValue; parseState->objectStack.index--; continue; } else { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected ','."); stopParsing = 1; } break;

        default: parseState->errorIsPrev = 1; AIMJK_error_parse_accept_or3(parseState, dictState, @"a \"STRING\"", @"a comma", @"a '}'"); stopParsing = 1; break;
      }
    }

    if(AIMJK_EXPECT_T(stopParsing == 0)) {
      if(AIMJK_EXPECT_T((stopParsing = AIMJK_parse_next_token(parseState)) == 0)) { if(AIMJK_EXPECT_F(parseState->token.type != AIMJKTokenTypeSeparator)) { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Expected ':'."); stopParsing = 1; } }
    }

    if((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T((stopParsing = AIMJK_parse_next_token(parseState)) == 0))) {
      switch(parseState->token.type) {
        case AIMJKTokenTypeNumber:
        case AIMJKTokenTypeString:
        case AIMJKTokenTypeTrue:
        case AIMJKTokenTypeFalse:
        case AIMJKTokenTypeNull:
        case AIMJKTokenTypeArrayBegin:
        case AIMJKTokenTypeObjectBegin:
          if(AIMJK_EXPECT_F((dictState & AIMJKParseAcceptValue)           == 0))    { parseState->errorIsPrev = 1; AIMJK_error(parseState, @"Unexpected value.");               stopParsing = 1; break; }
          if(AIMJK_EXPECT_F((object = AIMJK_object_for_token(parseState)) == NULL)) {                              AIMJK_error(parseState, @"Internal error: Object == NULL."); stopParsing = 1; break; } else { parseState->objectStack.objects[objectStackIndex] = object; dictState = AIMJKParseAcceptCommaOrEnd; }
          break;
        default: parseState->errorIsPrev = 1; AIMJK_error_parse_accept_or3(parseState, dictState, @"a value", @"a comma", @"a '}'"); stopParsing = 1; break;
      }
    }
  }

  if(AIMJK_EXPECT_F(parsedDictionary == NULL)) { size_t idx = 0UL; for(idx = startingObjectIndex; idx < parseState->objectStack.index; idx++) { if(parseState->objectStack.keys[idx] != NULL) { CFRelease(parseState->objectStack.keys[idx]); parseState->objectStack.keys[idx] = NULL; } if(parseState->objectStack.objects[idx] != NULL) { CFRelease(parseState->objectStack.objects[idx]); parseState->objectStack.objects[idx] = NULL; } } }
#if !defined(NS_BLOCK_ASSERTIONS)
  else { size_t idx = 0UL; for(idx = startingObjectIndex; idx < parseState->objectStack.index; idx++) { parseState->objectStack.objects[idx] = NULL; parseState->objectStack.keys[idx] = NULL; } }
#endif

  parseState->objectStack.index = startingObjectIndex;
  return(parsedDictionary);
}

static id AIMJSON_parse_it(AIMJKParseState *parseState) {
  id  parsedObject = NULL;
  int stopParsing  = 0;

  while((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T(parseState->atIndex < parseState->stringBuffer.bytes.length))) {
    if((AIMJK_EXPECT_T(stopParsing == 0)) && (AIMJK_EXPECT_T((stopParsing = AIMJK_parse_next_token(parseState)) == 0))) {
      switch(parseState->token.type) {
        case AIMJKTokenTypeArrayBegin:
        case AIMJKTokenTypeObjectBegin: parsedObject = [(id)AIMJK_object_for_token(parseState) autorelease]; stopParsing = 1; break;
        default:                     AIMJK_error(parseState, @"Expected either '[' or '{'.");             stopParsing = 1; break;
      }
    }
  }

  NSCParameterAssert((parseState->objectStack.index == 0) && (AIMJK_AT_STRING_PTR(parseState) <= AIMJK_END_STRING_PTR(parseState)));

  if((parsedObject == NULL) && (AIMJK_AT_STRING_PTR(parseState) == AIMJK_END_STRING_PTR(parseState))) { AIMJK_error(parseState, @"Reached the end of the buffer."); }
  if(parsedObject == NULL) { AIMJK_error(parseState, @"Unable to parse AIMJSON."); }

  if((parsedObject != NULL) && (AIMJK_AT_STRING_PTR(parseState) < AIMJK_END_STRING_PTR(parseState))) {
    AIMJK_parse_skip_whitespace(parseState);
    if((parsedObject != NULL) && ((parseState->parseOptionFlags & AIMJKParseOptionPermitTextAfterValidJSON) == 0) && (AIMJK_AT_STRING_PTR(parseState) < AIMJK_END_STRING_PTR(parseState))) {
      AIMJK_error(parseState, @"A valid AIMJSON object was parsed but there were additional non-white-space characters remaining.");
      parsedObject = NULL;
    }
  }

  return(parsedObject);
}

////////////
#pragma mark -
#pragma mark Object cache

// This uses a Galois Linear Feedback Shift Register (LFSR) PRNG to pick which item in the cache to age. It has a period of (2^32)-1.
// NOTE: A LFSR *MUST* be initialized to a non-zero value and must always have a non-zero value. The LFSR is initalized to 1 in -initWithParseOptions:
AIMJK_STATIC_INLINE void AIMJK_cache_age(AIMJKParseState *parseState) {
  NSCParameterAssert((parseState != NULL) && (parseState->cache.prng_lfsr != 0U));
  parseState->cache.prng_lfsr = (parseState->cache.prng_lfsr >> 1) ^ ((0U - (parseState->cache.prng_lfsr & 1U)) & 0x80200003U);
  parseState->cache.age[parseState->cache.prng_lfsr & (parseState->cache.count - 1UL)] >>= 1;
}

// The object cache is nothing more than a hash table with open addressing collision resolution that is bounded by AIMJK_CACHE_PROBES attempts.
//
// The hash table is a linear C array of AIMJKTokenCacheItem.  The terms "item" and "bucket" are synonymous with the index in to the cache array, i.e. cache.items[bucket].
//
// Items in the cache have an age associated with them.  An items age is incremented using saturating unsigned arithmetic and decremeted using unsigned right shifts.
// Thus, an items age is managed using an AIMD policy- additive increase, multiplicative decrease.  All age calculations and manipulations are branchless.
// The primitive C type MUST be unsigned.  It is currently a "char", which allows (at a minimum and in practice) 8 bits.
//
// A "useable bucket" is a bucket that is not in use (never populated), or has an age == 0.
//
// When an item is found in the cache, it's age is incremented.
// If a useable bucket hasn't been found, the current item (bucket) is aged along with two random items.
//
// If a value is not found in the cache, and no useable bucket has been found, that value is not added to the cache.

static void *AIMJK_cachedObjects(AIMJKParseState *parseState) {
  unsigned long  bucket     = parseState->token.value.hash & (parseState->cache.count - 1UL), setBucket = 0UL, useableBucket = 0UL, x = 0UL;
  void          *parsedAtom = NULL;
    
  if(AIMJK_EXPECT_F(parseState->token.value.ptrRange.length == 0UL) && AIMJK_EXPECT_T(parseState->token.value.type == AIMJKValueTypeString)) { return(@""); }

  for(x = 0UL; x < AIMJK_CACHE_PROBES; x++) {
    if(AIMJK_EXPECT_F(parseState->cache.items[bucket].object == NULL)) { setBucket = 1UL; useableBucket = bucket; break; }
    
    if((AIMJK_EXPECT_T(parseState->cache.items[bucket].hash == parseState->token.value.hash)) && (AIMJK_EXPECT_T(parseState->cache.items[bucket].size == parseState->token.value.ptrRange.length)) && (AIMJK_EXPECT_T(parseState->cache.items[bucket].type == parseState->token.value.type)) && (AIMJK_EXPECT_T(parseState->cache.items[bucket].bytes != NULL)) && (AIMJK_EXPECT_T(memcmp(parseState->cache.items[bucket].bytes, parseState->token.value.ptrRange.ptr, parseState->token.value.ptrRange.length) == 0U))) {
      parseState->cache.age[bucket]     = (((uint32_t)parseState->cache.age[bucket]) + 1U) - (((((uint32_t)parseState->cache.age[bucket]) + 1U) >> 31) ^ 1U);
      parseState->token.value.cacheItem = &parseState->cache.items[bucket];
      NSCParameterAssert(parseState->cache.items[bucket].object != NULL);
      return((void *)CFRetain(parseState->cache.items[bucket].object));
    } else {
      if(AIMJK_EXPECT_F(setBucket == 0UL) && AIMJK_EXPECT_F(parseState->cache.age[bucket] == 0U)) { setBucket = 1UL; useableBucket = bucket; }
      if(AIMJK_EXPECT_F(setBucket == 0UL))                                                     { parseState->cache.age[bucket] >>= 1; AIMJK_cache_age(parseState); AIMJK_cache_age(parseState); }
      // This is the open addressing function.  The values length and type are used as a form of "double hashing" to distribute values with the same effective value hash across different object cache buckets.
      // The values type is a prime number that is relatively coprime to the other primes in the set of value types and the number of hash table buckets.
      bucket = (parseState->token.value.hash + (parseState->token.value.ptrRange.length * (x + 1UL)) + (parseState->token.value.type * (x + 1UL)) + (3UL * (x + 1UL))) & (parseState->cache.count - 1UL);
    }
  }
  
  switch(parseState->token.value.type) {
    case AIMJKValueTypeString:           parsedAtom = (void *)CFStringCreateWithBytes(NULL, parseState->token.value.ptrRange.ptr, parseState->token.value.ptrRange.length, kCFStringEncodingUTF8, 0); break;
    case AIMJKValueTypeLongLong:         parsedAtom = (void *)CFNumberCreate(NULL, kCFNumberLongLongType, &parseState->token.value.number.longLongValue);                                             break;
    case AIMJKValueTypeUnsignedLongLong:
      if(parseState->token.value.number.unsignedLongLongValue <= LLONG_MAX) { parsedAtom = (void *)CFNumberCreate(NULL, kCFNumberLongLongType, &parseState->token.value.number.unsignedLongLongValue); }
      else { parsedAtom = (void *)parseState->objCImpCache.NSNumberInitWithUnsignedLongLong(parseState->objCImpCache.NSNumberAlloc(parseState->objCImpCache.NSNumberClass, @selector(alloc)), @selector(initWithUnsignedLongLong:), parseState->token.value.number.unsignedLongLongValue); }
      break;
    case AIMJKValueTypeDouble:           parsedAtom = (void *)CFNumberCreate(NULL, kCFNumberDoubleType,   &parseState->token.value.number.doubleValue);                                               break;
    default: AIMJK_error(parseState, @"Internal error: Unknown token value type. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); break;
  }
  
  if(AIMJK_EXPECT_T(setBucket) && (AIMJK_EXPECT_T(parsedAtom != NULL))) {
    bucket = useableBucket;
    if(AIMJK_EXPECT_T((parseState->cache.items[bucket].object != NULL))) { CFRelease(parseState->cache.items[bucket].object); parseState->cache.items[bucket].object = NULL; }
    
    if(AIMJK_EXPECT_T((parseState->cache.items[bucket].bytes = (unsigned char *)reallocf(parseState->cache.items[bucket].bytes, parseState->token.value.ptrRange.length)) != NULL)) {
      memcpy(parseState->cache.items[bucket].bytes, parseState->token.value.ptrRange.ptr, parseState->token.value.ptrRange.length);
      parseState->cache.items[bucket].object = (void *)CFRetain(parsedAtom);
      parseState->cache.items[bucket].hash   = parseState->token.value.hash;
      parseState->cache.items[bucket].cfHash = 0UL;
      parseState->cache.items[bucket].size   = parseState->token.value.ptrRange.length;
      parseState->cache.items[bucket].type   = parseState->token.value.type;
      parseState->token.value.cacheItem      = &parseState->cache.items[bucket];
      parseState->cache.age[bucket]          = AIMJK_INIT_CACHE_AGE;
    } else { // The realloc failed, so clear the appropriate fields.
      parseState->cache.items[bucket].hash   = 0UL;
      parseState->cache.items[bucket].cfHash = 0UL;
      parseState->cache.items[bucket].size   = 0UL;
      parseState->cache.items[bucket].type   = 0UL;
    }
  }
  
  return(parsedAtom);
}


static void *AIMJK_object_for_token(AIMJKParseState *parseState) {
  void *parsedAtom = NULL;
  
  parseState->token.value.cacheItem = NULL;
  switch(parseState->token.type) {
    case AIMJKTokenTypeString:      parsedAtom = AIMJK_cachedObjects(parseState);    break;
    case AIMJKTokenTypeNumber:      parsedAtom = AIMJK_cachedObjects(parseState);    break;
    case AIMJKTokenTypeObjectBegin: parsedAtom = AIMJK_parse_dictionary(parseState); break;
    case AIMJKTokenTypeArrayBegin:  parsedAtom = AIMJK_parse_array(parseState);      break;
    case AIMJKTokenTypeTrue:        parsedAtom = (void *)kCFBooleanTrue;          break;
    case AIMJKTokenTypeFalse:       parsedAtom = (void *)kCFBooleanFalse;         break;
    case AIMJKTokenTypeNull:        parsedAtom = (void *)kCFNull;                 break;
    default: AIMJK_error(parseState, @"Internal error: Unknown token type. %@ line #%ld", [NSString stringWithUTF8String:__FILE__], (long)__LINE__); break;
  }
  
  return(parsedAtom);
}

#pragma mark -
@implementation AIMJSONDecoder

+ (id)decoder
{
  return([self decoderWithParseOptions:AIMJKParseOptionStrict]);
}

+ (id)decoderWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags
{
  return([[[self alloc] initWithParseOptions:parseOptionFlags] autorelease]);
}

- (id)init
{
  return([self initWithParseOptions:AIMJKParseOptionStrict]);
}

- (id)initWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags
{
  if((self = [super init]) == NULL) { return(NULL); }

  if(parseOptionFlags & ~AIMJKParseOptionValidFlags) { [self autorelease]; [NSException raise:NSInvalidArgumentException format:@"Invalid parse options."]; }

  if((parseState = (AIMJKParseState *)calloc(1UL, sizeof(AIMJKParseState))) == NULL) { goto errorExit; }

  parseState->parseOptionFlags = parseOptionFlags;
  
  parseState->token.tokenBuffer.roundSizeUpToMultipleOf = 4096UL;
  parseState->objectStack.roundSizeUpToMultipleOf       = 2048UL;

  parseState->objCImpCache.NSNumberClass                    = _jk_NSNumberClass;
  parseState->objCImpCache.NSNumberAlloc                    = _jk_NSNumberAllocImp;
  parseState->objCImpCache.NSNumberInitWithUnsignedLongLong = _jk_NSNumberInitWithUnsignedLongLongImp;
  
  parseState->cache.prng_lfsr = 1U;
  parseState->cache.count     = AIMJK_CACHE_SLOTS;
  if((parseState->cache.items = (AIMJKTokenCacheItem *)calloc(1UL, sizeof(AIMJKTokenCacheItem) * parseState->cache.count)) == NULL) { goto errorExit; }

  return(self);

 errorExit:
  if(self) { [self autorelease]; self = NULL; }
  return(NULL);
}

// This is here primarily to support the NSString and NSData convenience functions so the autoreleased AIMJSONDecoder can release most of its resources before the pool pops.
static void _JSONDecoderCleanup(AIMJSONDecoder *decoder) {
  if((decoder != NULL) && (decoder->parseState != NULL)) {
    AIMJK_managedBuffer_release(&decoder->parseState->token.tokenBuffer);
    AIMJK_objectStack_release(&decoder->parseState->objectStack);
    
    [decoder clearCache];
    if(decoder->parseState->cache.items != NULL) { free(decoder->parseState->cache.items); decoder->parseState->cache.items = NULL; }
    
    free(decoder->parseState); decoder->parseState = NULL;
  }
}

- (void)dealloc
{
  _JSONDecoderCleanup(self);
  [super dealloc];
}

- (void)clearCache
{
  if(AIMJK_EXPECT_T(parseState != NULL)) {
    if(AIMJK_EXPECT_T(parseState->cache.items != NULL)) {
      size_t idx = 0UL;
      for(idx = 0UL; idx < parseState->cache.count; idx++) {
        if(AIMJK_EXPECT_T(parseState->cache.items[idx].object != NULL)) { CFRelease(parseState->cache.items[idx].object); parseState->cache.items[idx].object = NULL; }
        if(AIMJK_EXPECT_T(parseState->cache.items[idx].bytes  != NULL)) { free(parseState->cache.items[idx].bytes);       parseState->cache.items[idx].bytes  = NULL; }
        memset(&parseState->cache.items[idx], 0, sizeof(AIMJKTokenCacheItem));
        parseState->cache.age[idx] = 0U;
      }
    }
  }
}

// This needs to be completely rewritten.
static id _JKParseUTF8String(AIMJKParseState *parseState, BOOL mutableCollections, const unsigned char *string, size_t length, NSError **error) {
  NSCParameterAssert((parseState != NULL) && (string != NULL) && (parseState->cache.prng_lfsr != 0U));
  parseState->stringBuffer.bytes.ptr    = string;
  parseState->stringBuffer.bytes.length = length;
  parseState->atIndex                   = 0UL;
  parseState->lineNumber                = 1UL;
  parseState->lineStartIndex            = 0UL;
  parseState->prev_atIndex              = 0UL;
  parseState->prev_lineNumber           = 1UL;
  parseState->prev_lineStartIndex       = 0UL;
  parseState->error                     = NULL;
  parseState->errorIsPrev               = 0;
  parseState->mutableCollections        = (mutableCollections == NO) ? NO : YES;
  
  unsigned char stackTokenBuffer[AIMJK_TOKENBUFFER_SIZE] AIMJK_ALIGNED(64);
  AIMJK_managedBuffer_setToStackBuffer(&parseState->token.tokenBuffer, stackTokenBuffer, sizeof(stackTokenBuffer));
  
  void       *stackObjects [AIMJK_STACK_OBJS] AIMJK_ALIGNED(64);
  void       *stackKeys    [AIMJK_STACK_OBJS] AIMJK_ALIGNED(64);
  CFHashCode  stackCFHashes[AIMJK_STACK_OBJS] AIMJK_ALIGNED(64);
  AIMJK_objectStack_setToStackBuffer(&parseState->objectStack, stackObjects, stackKeys, stackCFHashes, AIMJK_STACK_OBJS);
  
  id parsedJSON = AIMJSON_parse_it(parseState);
  
  if((error != NULL) && (parseState->error != NULL)) { *error = parseState->error; }
  
  AIMJK_managedBuffer_release(&parseState->token.tokenBuffer);
  AIMJK_objectStack_release(&parseState->objectStack);
  
  parseState->stringBuffer.bytes.ptr    = NULL;
  parseState->stringBuffer.bytes.length = 0UL;
  parseState->atIndex                   = 0UL;
  parseState->lineNumber                = 1UL;
  parseState->lineStartIndex            = 0UL;
  parseState->prev_atIndex              = 0UL;
  parseState->prev_lineNumber           = 1UL;
  parseState->prev_lineStartIndex       = 0UL;
  parseState->error                     = NULL;
  parseState->errorIsPrev               = 0;
  parseState->mutableCollections        = NO;
  
  return(parsedJSON);
}

////////////
#pragma mark Deprecated as of v1.4
////////////

// Deprecated in AIMJSONKit v1.4.  Use objectWithUTF8String:length: instead.
- (id)parseUTF8String:(const unsigned char *)string length:(size_t)length
{
  return([self objectWithUTF8String:string length:length error:NULL]);
}

// Deprecated in AIMJSONKit v1.4.  Use objectWithUTF8String:length:error: instead.
- (id)parseUTF8String:(const unsigned char *)string length:(size_t)length error:(NSError **)error
{
  return([self objectWithUTF8String:string length:length error:error]);
}

// Deprecated in AIMJSONKit v1.4.  Use objectWithData: instead.
- (id)parseJSONData:(NSData *)jsonData
{
  return([self objectWithData:jsonData error:NULL]);
}

// Deprecated in AIMJSONKit v1.4.  Use objectWithData:error: instead.
- (id)parseJSONData:(NSData *)jsonData error:(NSError **)error
{
  return([self objectWithData:jsonData error:error]);
}

////////////
#pragma mark Methods that return immutable collection objects
////////////

- (id)objectWithUTF8String:(const unsigned char *)string length:(NSUInteger)length
{
  return([self objectWithUTF8String:string length:length error:NULL]);
}

- (id)objectWithUTF8String:(const unsigned char *)string length:(NSUInteger)length error:(NSError **)error
{
  if(parseState == NULL) { [NSException raise:NSInternalInconsistencyException format:@"parseState is NULL."];          }
  if(string     == NULL) { [NSException raise:NSInvalidArgumentException       format:@"The string argument is NULL."]; }
  
  return(_JKParseUTF8String(parseState, NO, string, (size_t)length, error));
}

- (id)objectWithData:(NSData *)jsonData
{
  return([self objectWithData:jsonData error:NULL]);
}

- (id)objectWithData:(NSData *)jsonData error:(NSError **)error
{
  if(jsonData == NULL) { [NSException raise:NSInvalidArgumentException format:@"The AIMJSONData argument is NULL."]; }
  return([self objectWithUTF8String:(const unsigned char *)[jsonData bytes] length:[jsonData length] error:error]);
}

////////////
#pragma mark Methods that return mutable collection objects
////////////

- (id)mutableObjectWithUTF8String:(const unsigned char *)string length:(NSUInteger)length
{
  return([self mutableObjectWithUTF8String:string length:length error:NULL]);
}

- (id)mutableObjectWithUTF8String:(const unsigned char *)string length:(NSUInteger)length error:(NSError **)error
{
  if(parseState == NULL) { [NSException raise:NSInternalInconsistencyException format:@"parseState is NULL."];          }
  if(string     == NULL) { [NSException raise:NSInvalidArgumentException       format:@"The string argument is NULL."]; }
  
  return(_JKParseUTF8String(parseState, YES, string, (size_t)length, error));
}

- (id)mutableObjectWithData:(NSData *)jsonData
{
  return([self mutableObjectWithData:jsonData error:NULL]);
}

- (id)mutableObjectWithData:(NSData *)jsonData error:(NSError **)error
{
  if(jsonData == NULL) { [NSException raise:NSInvalidArgumentException format:@"The AIMJSONData argument is NULL."]; }
  return([self mutableObjectWithUTF8String:(const unsigned char *)[jsonData bytes] length:[jsonData length] error:error]);
}

@end

/*
 The NSString and NSData convenience methods need a little bit of explanation.
 
 Prior to AIMJSONKit v1.4, the NSString -objectFromJSONStringWithParseOptions:error: method looked like
 
 const unsigned char *utf8String = (const unsigned char *)[self UTF8String];
 if(utf8String == NULL) { return(NULL); }
 size_t               utf8Length = strlen((const char *)utf8String); 
 return([[JSONDecoder decoderWithParseOptions:parseOptionFlags] parseUTF8String:utf8String length:utf8Length error:error]);
 
 This changed with v1.4 to a more complicated method.  The reason for this is to keep the amount of memory that is
 allocated, but not yet freed because it is dependent on the autorelease pool to pop before it can be reclaimed.
 
 In the simpler v1.3 code, this included all the bytes used to store the -UTF8String along with the AIMJSONDecoder and all its overhead.
 
 Now we use an autoreleased CFMutableData that is sized to the UTF8 length of the NSString in question and is used to hold the UTF8
 conversion of said string.
 
 Once parsed, the CFMutableData has its length set to 0.  This should, hopefully, allow the CFMutableData to realloc and/or free
 the buffer.
 
 Another change made was a slight modification to AIMJSONDecoder so that most of the cleanup work that was done in -dealloc was moved
 to a private, internal function.  These convenience routines keep the pointer to the autoreleased AIMJSONDecoder and calls
 _JSONDecoderCleanup() to early release the decoders resources since we already know that particular decoder is not going to be used
 again.  
 
 If everything goes smoothly, this will most likely result in perhaps a few hundred bytes that are allocated but waiting for the
 autorelease pool to pop.  This is compared to the thousands and easily hundreds of thousands of bytes that would have been in
 autorelease limbo.  It's more complicated for us, but a win for the user.
 
 Autorelease objects are used in case things don't go smoothly.  By having them autoreleased, we effectively guarantee that our
 requirement to -release the object is always met, not matter what goes wrong.  The downside is having a an object or two in
 autorelease limbo, but we've done our best to minimize that impact, so it all balances out.
 */

@implementation NSString (JSONKitDeserializing)

static id _NSStringObjectFromJSONString(NSString *jsonString, AIMJKParseOptionFlags parseOptionFlags, NSError **error, BOOL mutableCollection) {
  id                returnObject = NULL;
  CFMutableDataRef  mutableData  = NULL;
  AIMJSONDecoder      *decoder      = NULL;
  
  CFIndex    stringLength     = CFStringGetLength((CFStringRef)jsonString);
  NSUInteger stringUTF8Length = [jsonString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  
  if((mutableData = (CFMutableDataRef)[(id)CFDataCreateMutable(NULL, (NSUInteger)stringUTF8Length) autorelease]) != NULL) {
    UInt8   *utf8String = CFDataGetMutableBytePtr(mutableData);
    CFIndex  usedBytes  = 0L, convertedCount = 0L;
    
    convertedCount = CFStringGetBytes((CFStringRef)jsonString, CFRangeMake(0L, stringLength), kCFStringEncodingUTF8, '?', NO, utf8String, (NSUInteger)stringUTF8Length, &usedBytes);
    if(AIMJK_EXPECT_F(convertedCount != stringLength) || AIMJK_EXPECT_F(usedBytes < 0L)) { if(error != NULL) { *error = [NSError errorWithDomain:@"JKErrorDomain" code:-1L userInfo:[NSDictionary dictionaryWithObject:@"An error occurred converting the contents of a NSString to UTF8." forKey:NSLocalizedDescriptionKey]]; } goto exitNow; }
    
    if(mutableCollection == NO) { returnObject = [(decoder = [AIMJSONDecoder decoderWithParseOptions:parseOptionFlags])        objectWithUTF8String:(const unsigned char *)utf8String length:(size_t)usedBytes error:error]; }
    else                        { returnObject = [(decoder = [AIMJSONDecoder decoderWithParseOptions:parseOptionFlags]) mutableObjectWithUTF8String:(const unsigned char *)utf8String length:(size_t)usedBytes error:error]; }
  }
  
exitNow:
  if(mutableData != NULL) { CFDataSetLength(mutableData, 0L); }
  if(decoder     != NULL) { _JSONDecoderCleanup(decoder);     }
  return(returnObject);
}

- (id)objectFromJSONString
{
  return([self objectFromJSONStringWithParseOptions:AIMJKParseOptionStrict error:NULL]);
}

- (id)objectFromJSONStringWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags
{
  return([self objectFromJSONStringWithParseOptions:parseOptionFlags error:NULL]);
}

- (id)objectFromJSONStringWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags error:(NSError **)error
{
  return(_NSStringObjectFromJSONString(self, parseOptionFlags, error, NO));
}


- (id)mutableObjectFromJSONString
{
  return([self mutableObjectFromJSONStringWithParseOptions:AIMJKParseOptionStrict error:NULL]);
}

- (id)mutableObjectFromJSONStringWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags
{
  return([self mutableObjectFromJSONStringWithParseOptions:parseOptionFlags error:NULL]);
}

- (id)mutableObjectFromJSONStringWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags error:(NSError **)error
{
  return(_NSStringObjectFromJSONString(self, parseOptionFlags, error, YES));
}

@end

@implementation NSData (JSONKitDeserializing)

- (id)objectFromJSONData
{
  return([self objectFromJSONDataWithParseOptions:AIMJKParseOptionStrict error:NULL]);
}

- (id)objectFromJSONDataWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags
{
  return([self objectFromJSONDataWithParseOptions:parseOptionFlags error:NULL]);
}

- (id)objectFromJSONDataWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags error:(NSError **)error
{
  AIMJSONDecoder *decoder = NULL;
  id returnObject = [(decoder = [AIMJSONDecoder decoderWithParseOptions:parseOptionFlags]) objectWithData:self error:error];
  if(decoder != NULL) { _JSONDecoderCleanup(decoder); }
  return(returnObject);
}

- (id)mutableObjectFromJSONData
{
  return([self mutableObjectFromJSONDataWithParseOptions:AIMJKParseOptionStrict error:NULL]);
}

- (id)mutableObjectFromJSONDataWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags
{
  return([self mutableObjectFromJSONDataWithParseOptions:parseOptionFlags error:NULL]);
}

- (id)mutableObjectFromJSONDataWithParseOptions:(AIMJKParseOptionFlags)parseOptionFlags error:(NSError **)error
{
  AIMJSONDecoder *decoder = NULL;
  id returnObject = [(decoder = [AIMJSONDecoder decoderWithParseOptions:parseOptionFlags]) mutableObjectWithData:self error:error];
  if(decoder != NULL) { _JSONDecoderCleanup(decoder); }
  return(returnObject);
}


@end

////////////
#pragma mark -
#pragma mark Encoding / deserializing functions

static void AIMJK_encode_error(AIMJKEncodeState *encodeState, NSString *format, ...) {
  NSCParameterAssert((encodeState != NULL) && (format != NULL));

  va_list varArgsList;
  va_start(varArgsList, format);
  NSString *formatString = [[[NSString alloc] initWithFormat:format arguments:varArgsList] autorelease];
  va_end(varArgsList);

  if(encodeState->error == NULL) {
    encodeState->error = [NSError errorWithDomain:@"JKErrorDomain" code:-1L userInfo:
                                   [NSDictionary dictionaryWithObjectsAndKeys:
                                                                              formatString, NSLocalizedDescriptionKey,
                                                                              NULL]];
  }
}

AIMJK_STATIC_INLINE void AIMJK_encode_updateCache(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object) {
  NSCParameterAssert(encodeState != NULL);
  if(AIMJK_EXPECT_T(cacheSlot != NULL)) {
    NSCParameterAssert((object != NULL) && (startingAtIndex <= encodeState->atIndex));
    cacheSlot->object = object;
    cacheSlot->offset = startingAtIndex;
    cacheSlot->length = (size_t)(encodeState->atIndex - startingAtIndex);  
  }
}

static int AIMJK_encode_printf(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object, const char *format, ...) {
  va_list varArgsList, varArgsListCopy;
  va_start(varArgsList, format);
  va_copy(varArgsListCopy, varArgsList);

  NSCParameterAssert((encodeState != NULL) && (encodeState->atIndex < encodeState->stringBuffer.bytes.length) && (startingAtIndex <= encodeState->atIndex) && (format != NULL));

  ssize_t  formattedStringLength = 0L;
  int      returnValue           = 0;

  if(AIMJK_EXPECT_T((formattedStringLength = vsnprintf((char *)&encodeState->stringBuffer.bytes.ptr[encodeState->atIndex], (encodeState->stringBuffer.bytes.length - encodeState->atIndex), format, varArgsList)) >= (ssize_t)(encodeState->stringBuffer.bytes.length - encodeState->atIndex))) {
    NSCParameterAssert(((encodeState->atIndex + (formattedStringLength * 2UL) + 256UL) > encodeState->stringBuffer.bytes.length));
    if(AIMJK_EXPECT_F(((encodeState->atIndex + (formattedStringLength * 2UL) + 256UL) > encodeState->stringBuffer.bytes.length)) && AIMJK_EXPECT_F((AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + (formattedStringLength * 2UL)+ 4096UL) == NULL))) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); returnValue = 1; goto exitNow; }
    if(AIMJK_EXPECT_F((formattedStringLength = vsnprintf((char *)&encodeState->stringBuffer.bytes.ptr[encodeState->atIndex], (encodeState->stringBuffer.bytes.length - encodeState->atIndex), format, varArgsListCopy)) >= (ssize_t)(encodeState->stringBuffer.bytes.length - encodeState->atIndex))) { AIMJK_encode_error(encodeState, @"vsnprintf failed unexpectedly."); returnValue = 1; goto exitNow; }
  }
  
exitNow:
  va_end(varArgsList);
  va_end(varArgsListCopy);
  if(AIMJK_EXPECT_T(returnValue == 0)) { encodeState->atIndex += formattedStringLength; AIMJK_encode_updateCache(encodeState, cacheSlot, startingAtIndex, object); }
  return(returnValue);
}

static int AIMJK_encode_write(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object, const char *format) {
  NSCParameterAssert((encodeState != NULL) && (encodeState->atIndex < encodeState->stringBuffer.bytes.length) && (startingAtIndex <= encodeState->atIndex) && (format != NULL));
  if(AIMJK_EXPECT_F(((encodeState->atIndex + strlen(format) + 256UL) > encodeState->stringBuffer.bytes.length)) && AIMJK_EXPECT_F((AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + strlen(format) + 1024UL) == NULL))) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }

  size_t formatIdx = 0UL;
  for(formatIdx = 0UL; format[formatIdx] != 0; formatIdx++) { NSCParameterAssert(encodeState->atIndex < encodeState->stringBuffer.bytes.length); encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = format[formatIdx]; }
  AIMJK_encode_updateCache(encodeState, cacheSlot, startingAtIndex, object);
  return(0);
}

static int AIMJK_encode_writePrettyPrintWhiteSpace(AIMJKEncodeState *encodeState) {
  NSCParameterAssert((encodeState != NULL) && ((encodeState->serializeOptionFlags & AIMJKSerializeOptionPretty) != 0UL));
  if(AIMJK_EXPECT_F((encodeState->atIndex + ((encodeState->depth + 1UL) * 2UL) + 16UL) > encodeState->stringBuffer.bytes.length) && AIMJK_EXPECT_T(AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + ((encodeState->depth + 1UL) * 2UL) + 4096UL) == NULL)) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }
  encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\n';
  size_t depthWhiteSpace = 0UL;
  for(depthWhiteSpace = 0UL; depthWhiteSpace < (encodeState->depth * 2UL); depthWhiteSpace++) { NSCParameterAssert(encodeState->atIndex < encodeState->stringBuffer.bytes.length); encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = ' '; }
  return(0);
}  

static int AIMJK_encode_write1slow(AIMJKEncodeState *encodeState, ssize_t depthChange, const char *format) {
  NSCParameterAssert((encodeState != NULL) && (encodeState->atIndex < encodeState->stringBuffer.bytes.length) && (format != NULL) && ((depthChange >= -1L) && (depthChange <= 1L)) && ((encodeState->depth == 0UL) ? (depthChange >= 0L) : 1) && ((encodeState->serializeOptionFlags & AIMJKSerializeOptionPretty) != 0UL));
  if(AIMJK_EXPECT_F((encodeState->atIndex + ((encodeState->depth + 1UL) * 2UL) + 16UL) > encodeState->stringBuffer.bytes.length) && AIMJK_EXPECT_F(AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + ((encodeState->depth + 1UL) * 2UL) + 4096UL) == NULL)) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }
  encodeState->depth += depthChange;
  if(AIMJK_EXPECT_T(format[0] == ':')) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = format[0]; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = ' '; }
  else {
    if(AIMJK_EXPECT_F(depthChange == -1L)) { if(AIMJK_EXPECT_F(AIMJK_encode_writePrettyPrintWhiteSpace(encodeState))) { return(1); } }
    encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = format[0];
    if(AIMJK_EXPECT_T(depthChange != -1L)) { if(AIMJK_EXPECT_F(AIMJK_encode_writePrettyPrintWhiteSpace(encodeState))) { return(1); } }
  }
  NSCParameterAssert(encodeState->atIndex < encodeState->stringBuffer.bytes.length);
  return(0);
}

static int AIMJK_encode_write1fast(AIMJKEncodeState *encodeState, ssize_t depthChange AIMJK_UNUSED_ARG, const char *format) {
  NSCParameterAssert((encodeState != NULL) && (encodeState->atIndex < encodeState->stringBuffer.bytes.length) && ((encodeState->serializeOptionFlags & AIMJKSerializeOptionPretty) == 0UL));
  if(AIMJK_EXPECT_T((encodeState->atIndex + 4UL) < encodeState->stringBuffer.bytes.length)) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = format[0]; }
  else { return(AIMJK_encode_write(encodeState, NULL, 0UL, NULL, format)); }
  return(0);
}

static int AIMJK_encode_writen(AIMJKEncodeState *encodeState, AIMJKEncodeCache *cacheSlot, size_t startingAtIndex, id object, const char *format, size_t length) {
  NSCParameterAssert((encodeState != NULL) && (encodeState->atIndex < encodeState->stringBuffer.bytes.length) && (startingAtIndex <= encodeState->atIndex));
  if(AIMJK_EXPECT_F((encodeState->stringBuffer.bytes.length - encodeState->atIndex) < (length + 4UL))) { if(AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + 4096UL + length) == NULL) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); } }
  memcpy(encodeState->stringBuffer.bytes.ptr + encodeState->atIndex, format, length);
  encodeState->atIndex += length;
  AIMJK_encode_updateCache(encodeState, cacheSlot, startingAtIndex, object);
  return(0);
}

AIMJK_STATIC_INLINE AIMJKHash AIMJK_encode_object_hash(void *objectPtr) {
  return( ( (((AIMJKHash)objectPtr) >> 21) ^ (((AIMJKHash)objectPtr) >> 9)   ) + (((AIMJKHash)objectPtr) >> 4) );
}

static int AIMJK_encode_add_atom_to_buffer(AIMJKEncodeState *encodeState, void *objectPtr) {
  NSCParameterAssert((encodeState != NULL) && (encodeState->atIndex < encodeState->stringBuffer.bytes.length) && (objectPtr != NULL));

  id     object          = (id)objectPtr, encodeCacheObject = object;
  int    isClass         = AIMJKClassUnknown;
  size_t startingAtIndex = encodeState->atIndex;

  AIMJKHash         objectHash = AIMJK_encode_object_hash(objectPtr);
  AIMJKEncodeCache *cacheSlot  = &encodeState->cache[objectHash % AIMJK_ENCODE_CACHE_SLOTS];

  if(AIMJK_EXPECT_T(cacheSlot->object == object)) {
    NSCParameterAssert((cacheSlot->object != NULL) &&
                       (cacheSlot->offset < encodeState->atIndex)                   && ((cacheSlot->offset + cacheSlot->length) < encodeState->atIndex)                                    &&
                       (cacheSlot->offset < encodeState->stringBuffer.bytes.length) && ((cacheSlot->offset + cacheSlot->length) < encodeState->stringBuffer.bytes.length)                  &&
                       ((encodeState->stringBuffer.bytes.ptr + encodeState->atIndex)                     < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)) &&
                       ((encodeState->stringBuffer.bytes.ptr + cacheSlot->offset)                        < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)) &&
                       ((encodeState->stringBuffer.bytes.ptr + cacheSlot->offset + cacheSlot->length)    < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)));
    if(AIMJK_EXPECT_F(((encodeState->atIndex + cacheSlot->length + 256UL) > encodeState->stringBuffer.bytes.length)) && AIMJK_EXPECT_F((AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + cacheSlot->length + 1024UL) == NULL))) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }
    NSCParameterAssert(((encodeState->atIndex + cacheSlot->length) < encodeState->stringBuffer.bytes.length) &&
                       ((encodeState->stringBuffer.bytes.ptr + encodeState->atIndex)                     < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)) &&
                       ((encodeState->stringBuffer.bytes.ptr + encodeState->atIndex + cacheSlot->length) < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)) &&
                       ((encodeState->stringBuffer.bytes.ptr + cacheSlot->offset)                        < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)) &&
                       ((encodeState->stringBuffer.bytes.ptr + cacheSlot->offset + cacheSlot->length)    < (encodeState->stringBuffer.bytes.ptr + encodeState->stringBuffer.bytes.length)) &&
                       ((encodeState->stringBuffer.bytes.ptr + cacheSlot->offset + cacheSlot->length)    < (encodeState->stringBuffer.bytes.ptr + encodeState->atIndex)));
    memcpy(encodeState->stringBuffer.bytes.ptr + encodeState->atIndex, encodeState->stringBuffer.bytes.ptr + cacheSlot->offset, cacheSlot->length);
    encodeState->atIndex += cacheSlot->length;
    return(0);
  }

  // When we encounter a class that we do not handle, and we have either a delegate or block that the user supplied to format unsupported classes,
  // we "re-run" the object check.  However, we re-run the object check exactly ONCE.  If the user supplies an object that isn't one of the
  // supported classes, we fail the second time (i.e., double fault error).
  BOOL rerunningAfterClassFormatter = NO;
 rerunAfterClassFormatter:;

  // XXX XXX XXX XXX
  //     
  //     We need to work around a bug in 10.7, which breaks ABI compatibility with Objective-C going back not just to 10.0, but OpenStep and even NextStep.
  //     
  //     It has long been documented that "the very first thing that a pointer to an Objective-C object "points to" is a pointer to that objects class".
  //     
  //     This is euphemistically called "tagged pointers".  There are a number of highly technical problems with this, most involving long passages from
  //     the C standard(s).  In short, one can make a strong case, couched from the perspective of the C standard(s), that that 10.7 "tagged pointers" are
  //     fundamentally Wrong and Broken, and should have never been implemented.  Assuming those points are glossed over, because the change is very clearly
  //     breaking ABI compatibility, this should have resulted in a minimum of a "minimum version required" bump in various shared libraries to prevent
  //     causes code that used to work just fine to suddenly break without warning.
  //
  //     In fact, the C standard says that the hack below is "undefined behavior"- there is no requirement that the 10.7 tagged pointer hack of setting the
  //     "lower, unused bits" must be preserved when casting the result to an integer type, but this "works" because for most architectures
  //     `sizeof(long) == sizeof(void *)` and the compiler uses the same representation for both.  (note: this is informal, not meant to be
  //     normative or pedantically correct).
  //     
  //     In other words, while this "works" for now, technically the compiler is not obligated to do "what we want", and a later version of the compiler
  //     is not required in any way to produce the same results or behavior that earlier versions of the compiler did for the statement below.
  //
  //     Fan-fucking-tastic.
  //     
  //     Why not just use `object_getClass()`?  Because `object->isa` reduces to (typically) a *single* instruction.  Calling `object_getClass()` requires
  //     that the compiler potentially spill registers, establish a function call frame / environment, and finally execute a "jump subroutine" instruction.
  //     Then, the called subroutine must spend half a dozen instructions in its prolog, however many instructions doing whatever it does, then half a dozen
  //     instructions in its prolog.  One instruction compared to dozens, maybe a hundred instructions.
  //     
  //     Yes, that's one to two orders of magnitude difference.  Which is compelling in its own right.  When going for performance, you're often happy with
  //     gains in the two to three percent range.
  //     
  // XXX XXX XXX XXX


  BOOL   workAroundMacOSXABIBreakingBug = (AIMJK_EXPECT_F(((NSUInteger)object) & 0x1))     ? YES  : NO;
  void  *objectISA                      = (AIMJK_EXPECT_F(workAroundMacOSXABIBreakingBug)) ? NULL : *((void **)objectPtr);
  if(AIMJK_EXPECT_F(workAroundMacOSXABIBreakingBug)) { goto slowClassLookup; }

       if(AIMJK_EXPECT_T(objectISA == encodeState->fastClassLookup.stringClass))     { isClass = AIMJKClassString;     }
  else if(AIMJK_EXPECT_T(objectISA == encodeState->fastClassLookup.numberClass))     { isClass = AIMJKClassNumber;     }
  else if(AIMJK_EXPECT_T(objectISA == encodeState->fastClassLookup.dictionaryClass)) { isClass = AIMJKClassDictionary; }
  else if(AIMJK_EXPECT_T(objectISA == encodeState->fastClassLookup.arrayClass))      { isClass = AIMJKClassArray;      }
  else if(AIMJK_EXPECT_T(objectISA == encodeState->fastClassLookup.nullClass))       { isClass = AIMJKClassNull;       }
  else {
  slowClassLookup:
         if(AIMJK_EXPECT_T([object isKindOfClass:[NSString     class]])) { if(workAroundMacOSXABIBreakingBug == NO) { encodeState->fastClassLookup.stringClass     = objectISA; } isClass = AIMJKClassString;     }
    else if(AIMJK_EXPECT_T([object isKindOfClass:[NSNumber     class]])) { if(workAroundMacOSXABIBreakingBug == NO) { encodeState->fastClassLookup.numberClass     = objectISA; } isClass = AIMJKClassNumber;     }
    else if(AIMJK_EXPECT_T([object isKindOfClass:[NSDictionary class]])) { if(workAroundMacOSXABIBreakingBug == NO) { encodeState->fastClassLookup.dictionaryClass = objectISA; } isClass = AIMJKClassDictionary; }
    else if(AIMJK_EXPECT_T([object isKindOfClass:[NSArray      class]])) { if(workAroundMacOSXABIBreakingBug == NO) { encodeState->fastClassLookup.arrayClass      = objectISA; } isClass = AIMJKClassArray;      }
    else if(AIMJK_EXPECT_T([object isKindOfClass:[NSNull       class]])) { if(workAroundMacOSXABIBreakingBug == NO) { encodeState->fastClassLookup.nullClass       = objectISA; } isClass = AIMJKClassNull;       }
    else {
      if((rerunningAfterClassFormatter == NO) && (
#ifdef __BLOCKS__
           ((encodeState->classFormatterBlock) && ((object = encodeState->classFormatterBlock(object))                                                                         != NULL)) ||
#endif
           ((encodeState->classFormatterIMP)   && ((object = encodeState->classFormatterIMP(encodeState->classFormatterDelegate, encodeState->classFormatterSelector, object)) != NULL))    )) { rerunningAfterClassFormatter = YES; goto rerunAfterClassFormatter; }
      
      if(rerunningAfterClassFormatter == NO) { AIMJK_encode_error(encodeState, @"Unable to serialize object class %@.", NSStringFromClass([encodeCacheObject class])); return(1); }
      else { AIMJK_encode_error(encodeState, @"Unable to serialize object class %@ that was returned by the unsupported class formatter.  Original object class was %@.", (object == NULL) ? @"NULL" : NSStringFromClass([object class]), NSStringFromClass([encodeCacheObject class])); return(1); }
    }
  }

  // This is here for the benefit of the optimizer.  It allows the optimizer to do loop invariant code motion for the AIMJKClassArray
  // and AIMJKClassDictionary cases when printing simple, single characters via AIMJK_encode_write(), which is actually a macro:
  // #define AIMJK_encode_write1(es, dc, f) (_jk_encode_prettyPrint ? AIMJK_encode_write1slow(es, dc, f) : AIMJK_encode_write1fast(es, dc, f))
  int _jk_encode_prettyPrint = AIMJK_EXPECT_T((encodeState->serializeOptionFlags & AIMJKSerializeOptionPretty) == 0) ? 0 : 1;
  
  switch(isClass) {
    case AIMJKClassString:
      {
        {
          const unsigned char *cStringPtr = (const unsigned char *)CFStringGetCStringPtr((CFStringRef)object, kCFStringEncodingMacRoman);
          if(cStringPtr != NULL) {
            const unsigned char *utf8String = cStringPtr;
            size_t               utf8Idx    = 0UL;

            CFIndex stringLength = CFStringGetLength((CFStringRef)object);
            if(AIMJK_EXPECT_F(((encodeState->atIndex + (stringLength * 2UL) + 256UL) > encodeState->stringBuffer.bytes.length)) && AIMJK_EXPECT_F((AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + (stringLength * 2UL) + 1024UL) == NULL))) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }

            if(AIMJK_EXPECT_T((encodeState->encodeOption & AIMJKEncodeOptionStringObjTrimQuotes) == 0UL)) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\"'; }
            for(utf8Idx = 0UL; utf8String[utf8Idx] != 0U; utf8Idx++) {
              NSCParameterAssert(((&encodeState->stringBuffer.bytes.ptr[encodeState->atIndex]) - encodeState->stringBuffer.bytes.ptr) < (ssize_t)encodeState->stringBuffer.bytes.length);
              NSCParameterAssert(encodeState->atIndex < encodeState->stringBuffer.bytes.length);
              if(AIMJK_EXPECT_F(utf8String[utf8Idx] >= 0x80U)) { encodeState->atIndex = startingAtIndex; goto slowUTF8Path; }
              if(AIMJK_EXPECT_F(utf8String[utf8Idx] <  0x20U)) {
                switch(utf8String[utf8Idx]) {
                  case '\b': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'b'; break;
                  case '\f': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'f'; break;
                  case '\n': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'n'; break;
                  case '\r': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'r'; break;
                  case '\t': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 't'; break;
                  default: if(AIMJK_EXPECT_F(AIMJK_encode_printf(encodeState, NULL, 0UL, NULL, "\\u%4.4x", utf8String[utf8Idx]))) { return(1); } break;
                }
              } else {
                if(AIMJK_EXPECT_F(utf8String[utf8Idx] == '\"') || AIMJK_EXPECT_F(utf8String[utf8Idx] == '\\') || (AIMJK_EXPECT_F(encodeState->serializeOptionFlags & AIMJKSerializeOptionEscapeForwardSlashes) && AIMJK_EXPECT_F(utf8String[utf8Idx] == '/'))) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; }
                encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = utf8String[utf8Idx];
              }
            }
            NSCParameterAssert((encodeState->atIndex + 1UL) < encodeState->stringBuffer.bytes.length);
            if(AIMJK_EXPECT_T((encodeState->encodeOption & AIMJKEncodeOptionStringObjTrimQuotes) == 0UL)) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\"'; }
            AIMJK_encode_updateCache(encodeState, cacheSlot, startingAtIndex, encodeCacheObject);
            return(0);
          }
        }

      slowUTF8Path:
        {
          CFIndex stringLength        = CFStringGetLength((CFStringRef)object);
          CFIndex maxStringUTF8Length = CFStringGetMaximumSizeForEncoding(stringLength, kCFStringEncodingUTF8) + 32L;
        
          if(AIMJK_EXPECT_F((size_t)maxStringUTF8Length > encodeState->utf8ConversionBuffer.bytes.length) && AIMJK_EXPECT_F(AIMJK_managedBuffer_resize(&encodeState->utf8ConversionBuffer, maxStringUTF8Length + 1024UL) == NULL)) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }
        
          CFIndex usedBytes = 0L, convertedCount = 0L;
          convertedCount = CFStringGetBytes((CFStringRef)object, CFRangeMake(0L, stringLength), kCFStringEncodingUTF8, '?', NO, encodeState->utf8ConversionBuffer.bytes.ptr, encodeState->utf8ConversionBuffer.bytes.length - 16L, &usedBytes);
          if(AIMJK_EXPECT_F(convertedCount != stringLength) || AIMJK_EXPECT_F(usedBytes < 0L)) { AIMJK_encode_error(encodeState, @"An error occurred converting the contents of a NSString to UTF8."); return(1); }
        
          if(AIMJK_EXPECT_F((encodeState->atIndex + (maxStringUTF8Length * 2UL) + 256UL) > encodeState->stringBuffer.bytes.length) && AIMJK_EXPECT_F(AIMJK_managedBuffer_resize(&encodeState->stringBuffer, encodeState->atIndex + (maxStringUTF8Length * 2UL) + 1024UL) == NULL)) { AIMJK_encode_error(encodeState, @"Unable to resize temporary buffer."); return(1); }
        
          const unsigned char *utf8String = encodeState->utf8ConversionBuffer.bytes.ptr;
        
          size_t utf8Idx = 0UL;
          if(AIMJK_EXPECT_T((encodeState->encodeOption & AIMJKEncodeOptionStringObjTrimQuotes) == 0UL)) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\"'; }
          for(utf8Idx = 0UL; utf8Idx < (size_t)usedBytes; utf8Idx++) {
            NSCParameterAssert(((&encodeState->stringBuffer.bytes.ptr[encodeState->atIndex]) - encodeState->stringBuffer.bytes.ptr) < (ssize_t)encodeState->stringBuffer.bytes.length);
            NSCParameterAssert(encodeState->atIndex < encodeState->stringBuffer.bytes.length);
            NSCParameterAssert((CFIndex)utf8Idx < usedBytes);
            if(AIMJK_EXPECT_F(utf8String[utf8Idx] < 0x20U)) {
              switch(utf8String[utf8Idx]) {
                case '\b': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'b'; break;
                case '\f': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'f'; break;
                case '\n': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'n'; break;
                case '\r': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 'r'; break;
                case '\t': encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = 't'; break;
                default: if(AIMJK_EXPECT_F(AIMJK_encode_printf(encodeState, NULL, 0UL, NULL, "\\u%4.4x", utf8String[utf8Idx]))) { return(1); } break;
              }
            } else {
              if(AIMJK_EXPECT_F(utf8String[utf8Idx] >= 0x80U) && (encodeState->serializeOptionFlags & AIMJKSerializeOptionEscapeUnicode)) {
                const unsigned char *nextValidCharacter = NULL;
                UTF32                u32ch              = 0U;
                ConversionResult     result;

                if(AIMJK_EXPECT_F((result = ConvertSingleCodePointInUTF8(&utf8String[utf8Idx], &utf8String[usedBytes], (UTF8 const **)&nextValidCharacter, &u32ch)) != conversionOK)) { AIMJK_encode_error(encodeState, @"Error converting UTF8."); return(1); }
                else {
                  utf8Idx = (nextValidCharacter - utf8String) - 1UL;
                  if(AIMJK_EXPECT_T(u32ch <= 0xffffU)) { if(AIMJK_EXPECT_F(AIMJK_encode_printf(encodeState, NULL, 0UL, NULL, "\\u%4.4x", u32ch)))                                                           { return(1); } }
                  else                              { if(AIMJK_EXPECT_F(AIMJK_encode_printf(encodeState, NULL, 0UL, NULL, "\\u%4.4x\\u%4.4x", (0xd7c0U + (u32ch >> 10)), (0xdc00U + (u32ch & 0x3ffU))))) { return(1); } }
                }
              } else {
                if(AIMJK_EXPECT_F(utf8String[utf8Idx] == '\"') || AIMJK_EXPECT_F(utf8String[utf8Idx] == '\\') || (AIMJK_EXPECT_F(encodeState->serializeOptionFlags & AIMJKSerializeOptionEscapeForwardSlashes) && AIMJK_EXPECT_F(utf8String[utf8Idx] == '/'))) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\\'; }
                encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = utf8String[utf8Idx];
              }
            }
          }
          NSCParameterAssert((encodeState->atIndex + 1UL) < encodeState->stringBuffer.bytes.length);
          if(AIMJK_EXPECT_T((encodeState->encodeOption & AIMJKEncodeOptionStringObjTrimQuotes) == 0UL)) { encodeState->stringBuffer.bytes.ptr[encodeState->atIndex++] = '\"'; }
          AIMJK_encode_updateCache(encodeState, cacheSlot, startingAtIndex, encodeCacheObject);
          return(0);
        }
      }
      break;

    case AIMJKClassNumber:
      {
             if(object == (id)kCFBooleanTrue)  { return(AIMJK_encode_writen(encodeState, cacheSlot, startingAtIndex, encodeCacheObject, "true",  4UL)); }
        else if(object == (id)kCFBooleanFalse) { return(AIMJK_encode_writen(encodeState, cacheSlot, startingAtIndex, encodeCacheObject, "false", 5UL)); }
        
        const char         *objCType = [object objCType];
        char                anum[256], *aptr = &anum[255];
        int                 isNegative = 0;
        unsigned long long  ullv;
        long long           llv;
        
        if(AIMJK_EXPECT_F(objCType == NULL) || AIMJK_EXPECT_F(objCType[0] == 0) || AIMJK_EXPECT_F(objCType[1] != 0)) { AIMJK_encode_error(encodeState, @"NSNumber conversion error, unknown type.  Type: '%s'", (objCType == NULL) ? "<NULL>" : objCType); return(1); }
        
        switch(objCType[0]) {
          case 'c': case 'i': case 's': case 'l': case 'q':
            if(AIMJK_EXPECT_T(CFNumberGetValue((CFNumberRef)object, kCFNumberLongLongType, &llv)))  {
              if(llv < 0LL)  { ullv = -llv; isNegative = 1; } else { ullv = llv; isNegative = 0; }
              goto convertNumber;
            } else { AIMJK_encode_error(encodeState, @"Unable to get scalar value from number object."); return(1); }
            break;
          case 'C': case 'I': case 'S': case 'L': case 'Q': case 'B':
            if(AIMJK_EXPECT_T(CFNumberGetValue((CFNumberRef)object, kCFNumberLongLongType, &ullv))) {
            convertNumber:
              if(AIMJK_EXPECT_F(ullv < 10ULL)) { *--aptr = ullv + '0'; } else { while(AIMJK_EXPECT_T(ullv > 0ULL)) { *--aptr = (ullv % 10ULL) + '0'; ullv /= 10ULL; NSCParameterAssert(aptr > anum); } }
              if(isNegative) { *--aptr = '-'; }
              NSCParameterAssert(aptr > anum);
              return(AIMJK_encode_writen(encodeState, cacheSlot, startingAtIndex, encodeCacheObject, aptr, &anum[255] - aptr));
            } else { AIMJK_encode_error(encodeState, @"Unable to get scalar value from number object."); return(1); }
            break;
          case 'f': case 'd':
            {
              double dv;
              if(AIMJK_EXPECT_T(CFNumberGetValue((CFNumberRef)object, kCFNumberDoubleType, &dv))) {
                if(AIMJK_EXPECT_F(!isfinite(dv))) { AIMJK_encode_error(encodeState, @"Floating point values must be finite.  AIMJSON does not support NaN or Infinity."); return(1); }
                return(AIMJK_encode_printf(encodeState, cacheSlot, startingAtIndex, encodeCacheObject, "%.17g", dv));
              } else { AIMJK_encode_error(encodeState, @"Unable to get floating point value from number object."); return(1); }
            }
            break;
          default: AIMJK_encode_error(encodeState, @"NSNumber conversion error, unknown type.  Type: '%c' / 0x%2.2x", objCType[0], objCType[0]); return(1); break;
        }
      }
      break;
    
    case AIMJKClassArray:
      {
        int     printComma = 0;
        CFIndex arrayCount = CFArrayGetCount((CFArrayRef)object), idx = 0L;
        if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 1L, "["))) { return(1); }
        if(AIMJK_EXPECT_F(arrayCount > 1020L)) {
          for(id arrayObject in object)          { if(AIMJK_EXPECT_T(printComma)) { if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 0L, ","))) { return(1); } } printComma = 1; if(AIMJK_EXPECT_F(AIMJK_encode_add_atom_to_buffer(encodeState, arrayObject)))  { return(1); } }
        } else {
          void *objects[1024];
          CFArrayGetValues((CFArrayRef)object, CFRangeMake(0L, arrayCount), (const void **)objects);
          for(idx = 0L; idx < arrayCount; idx++) { if(AIMJK_EXPECT_T(printComma)) { if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 0L, ","))) { return(1); } } printComma = 1; if(AIMJK_EXPECT_F(AIMJK_encode_add_atom_to_buffer(encodeState, objects[idx]))) { return(1); } }
        }
        return(AIMJK_encode_write1(encodeState, -1L, "]"));
      }
      break;

    case AIMJKClassDictionary:
      {
        int     printComma      = 0;
        CFIndex dictionaryCount = CFDictionaryGetCount((CFDictionaryRef)object), idx = 0L;
        id      enumerateObject = AIMJK_EXPECT_F(_jk_encode_prettyPrint) ? [[object allKeys] sortedArrayUsingSelector:@selector(compare:)] : object;

        if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 1L, "{"))) { return(1); }
        if(AIMJK_EXPECT_F(_jk_encode_prettyPrint) || AIMJK_EXPECT_F(dictionaryCount > 1020L)) {
          for(id keyObject in enumerateObject) {
            if(AIMJK_EXPECT_T(printComma)) { if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 0L, ","))) { return(1); } }
            printComma = 1;
            void *keyObjectISA = *((void **)keyObject);
            if(AIMJK_EXPECT_F((keyObjectISA != encodeState->fastClassLookup.stringClass)) && AIMJK_EXPECT_F(([keyObject isKindOfClass:[NSString class]] == NO))) { AIMJK_encode_error(encodeState, @"Key must be a string object."); return(1); }
            if(AIMJK_EXPECT_F(AIMJK_encode_add_atom_to_buffer(encodeState, keyObject)))                                                        { return(1); }
            if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 0L, ":")))                                                                      { return(1); }
            if(AIMJK_EXPECT_F(AIMJK_encode_add_atom_to_buffer(encodeState, (void *)CFDictionaryGetValue((CFDictionaryRef)object, keyObject)))) { return(1); }
          }
        } else {
          void *keys[1024], *objects[1024];
          CFDictionaryGetKeysAndValues((CFDictionaryRef)object, (const void **)keys, (const void **)objects);
          for(idx = 0L; idx < dictionaryCount; idx++) {
            if(AIMJK_EXPECT_T(printComma)) { if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 0L, ","))) { return(1); } }
            printComma = 1;
            void *keyObjectISA = *((void **)keys[idx]);
            if(AIMJK_EXPECT_F(keyObjectISA != encodeState->fastClassLookup.stringClass) && AIMJK_EXPECT_F([(id)keys[idx] isKindOfClass:[NSString class]] == NO)) { AIMJK_encode_error(encodeState, @"Key must be a string object."); return(1); }
            if(AIMJK_EXPECT_F(AIMJK_encode_add_atom_to_buffer(encodeState, keys[idx])))    { return(1); }
            if(AIMJK_EXPECT_F(AIMJK_encode_write1(encodeState, 0L, ":")))                  { return(1); }
            if(AIMJK_EXPECT_F(AIMJK_encode_add_atom_to_buffer(encodeState, objects[idx]))) { return(1); }
          }
        }
        return(AIMJK_encode_write1(encodeState, -1L, "}"));
      }
      break;

    case AIMJKClassNull: return(AIMJK_encode_writen(encodeState, cacheSlot, startingAtIndex, encodeCacheObject, "null", 4UL)); break;

    default: AIMJK_encode_error(encodeState, @"Unable to serialize object class %@.", NSStringFromClass([object class])); return(1); break;
  }

  return(0);
}


@implementation AIMJKSerializer

+ (id)serializeObject:(id)object options:(AIMJKSerializeOptionFlags)optionFlags encodeOption:(AIMJKEncodeOptionType)encodeOption block:(AIMJKSERIALIZER_BLOCKS_PROTO)block delegate:(id)delegate selector:(SEL)selector error:(NSError **)error
{
  return([[[[self alloc] init] autorelease] serializeObject:object options:optionFlags encodeOption:encodeOption block:block delegate:delegate selector:selector error:error]);
}

- (id)serializeObject:(id)object options:(AIMJKSerializeOptionFlags)optionFlags encodeOption:(AIMJKEncodeOptionType)encodeOption block:(AIMJKSERIALIZER_BLOCKS_PROTO)block delegate:(id)delegate selector:(SEL)selector error:(NSError **)error
{
#ifndef __BLOCKS__
#pragma unused(block)
#endif
  NSParameterAssert((object != NULL) && (encodeState == NULL) && ((delegate != NULL) ? (block == NULL) : 1) && ((block != NULL) ? (delegate == NULL) : 1) &&
                    (((encodeOption & AIMJKEncodeOptionCollectionObj) != 0UL) ? (((encodeOption & AIMJKEncodeOptionStringObj)     == 0UL) && ((encodeOption & AIMJKEncodeOptionStringObjTrimQuotes) == 0UL)) : 1) &&
                    (((encodeOption & AIMJKEncodeOptionStringObj)     != 0UL) ?  ((encodeOption & AIMJKEncodeOptionCollectionObj) == 0UL)                                                                 : 1));

  id returnObject = NULL;

  if(encodeState != NULL) { [self releaseState]; }
  if((encodeState = (struct AIMJKEncodeState *)calloc(1UL, sizeof(AIMJKEncodeState))) == NULL) { [NSException raise:NSMallocException format:@"Unable to allocate state structure."]; return(NULL); }

  if((error != NULL) && (*error != NULL)) { *error = NULL; }

  if(delegate != NULL) {
    if(selector                               == NULL) { [NSException raise:NSInvalidArgumentException format:@"The delegate argument is not NULL, but the selector argument is NULL."]; }
    if([delegate respondsToSelector:selector] == NO)   { [NSException raise:NSInvalidArgumentException format:@"The serializeUnsupportedClassesUsingDelegate: delegate does not respond to the selector argument."]; }
    encodeState->classFormatterDelegate = delegate;
    encodeState->classFormatterSelector = selector;
    encodeState->classFormatterIMP      = (AIMJKClassFormatterIMP)[delegate methodForSelector:selector];
    NSCParameterAssert(encodeState->classFormatterIMP != NULL);
  }

#ifdef __BLOCKS__
  encodeState->classFormatterBlock                          = block;
#endif
  encodeState->serializeOptionFlags                         = optionFlags;
  encodeState->encodeOption                                 = encodeOption;
  encodeState->stringBuffer.roundSizeUpToMultipleOf         = (1024UL * 32UL);
  encodeState->utf8ConversionBuffer.roundSizeUpToMultipleOf = 4096UL;
    
  unsigned char stackJSONBuffer[AIMJK_JSONBUFFER_SIZE] AIMJK_ALIGNED(64);
  AIMJK_managedBuffer_setToStackBuffer(&encodeState->stringBuffer,         stackJSONBuffer, sizeof(stackJSONBuffer));

  unsigned char stackUTF8Buffer[AIMJK_UTF8BUFFER_SIZE] AIMJK_ALIGNED(64);
  AIMJK_managedBuffer_setToStackBuffer(&encodeState->utf8ConversionBuffer, stackUTF8Buffer, sizeof(stackUTF8Buffer));

  if(((encodeOption & AIMJKEncodeOptionCollectionObj) != 0UL) && (([object isKindOfClass:[NSArray  class]] == NO) && ([object isKindOfClass:[NSDictionary class]] == NO))) { AIMJK_encode_error(encodeState, @"Unable to serialize object class %@, expected a NSArray or NSDictionary.", NSStringFromClass([object class])); goto errorExit; }
  if(((encodeOption & AIMJKEncodeOptionStringObj)     != 0UL) &&  ([object isKindOfClass:[NSString class]] == NO))                                                         { AIMJK_encode_error(encodeState, @"Unable to serialize object class %@, expected a NSString.", NSStringFromClass([object class])); goto errorExit; }

  if(AIMJK_encode_add_atom_to_buffer(encodeState, object) == 0) {
    BOOL stackBuffer = ((encodeState->stringBuffer.flags & AIMJKManagedBufferMustFree) == 0UL) ? YES : NO;
    
    if((encodeState->atIndex < 2UL))
    if((stackBuffer == NO) && ((encodeState->stringBuffer.bytes.ptr = (unsigned char *)reallocf(encodeState->stringBuffer.bytes.ptr, encodeState->atIndex + 16UL)) == NULL)) { AIMJK_encode_error(encodeState, @"Unable to realloc buffer"); goto errorExit; }

    switch((encodeOption & AIMJKEncodeOptionAsTypeMask)) {
      case AIMJKEncodeOptionAsData:
        if(stackBuffer == YES) { if((returnObject = [(id)CFDataCreate(                 NULL,                encodeState->stringBuffer.bytes.ptr, (CFIndex)encodeState->atIndex)                                  autorelease]) == NULL) { AIMJK_encode_error(encodeState, @"Unable to create NSData object"); } }
        else                   { if((returnObject = [(id)CFDataCreateWithBytesNoCopy(  NULL,                encodeState->stringBuffer.bytes.ptr, (CFIndex)encodeState->atIndex, NULL)                            autorelease]) == NULL) { AIMJK_encode_error(encodeState, @"Unable to create NSData object"); } }
        break;

      case AIMJKEncodeOptionAsString:
        if(stackBuffer == YES) { if((returnObject = [(id)CFStringCreateWithBytes(      NULL, (const UInt8 *)encodeState->stringBuffer.bytes.ptr, (CFIndex)encodeState->atIndex, kCFStringEncodingUTF8, NO)       autorelease]) == NULL) { AIMJK_encode_error(encodeState, @"Unable to create NSString object"); } }
        else                   { if((returnObject = [(id)CFStringCreateWithBytesNoCopy(NULL, (const UInt8 *)encodeState->stringBuffer.bytes.ptr, (CFIndex)encodeState->atIndex, kCFStringEncodingUTF8, NO, NULL) autorelease]) == NULL) { AIMJK_encode_error(encodeState, @"Unable to create NSString object"); } }
        break;

      default: AIMJK_encode_error(encodeState, @"Unknown encode as type."); break;
    }

    if((returnObject != NULL) && (stackBuffer == NO)) { encodeState->stringBuffer.flags &= ~AIMJKManagedBufferMustFree; encodeState->stringBuffer.bytes.ptr = NULL; encodeState->stringBuffer.bytes.length = 0UL; }
  }

errorExit:
  if((encodeState != NULL) && (error != NULL) && (encodeState->error != NULL)) { *error = encodeState->error; encodeState->error = NULL; }
  [self releaseState];

  return(returnObject);
}

- (void)releaseState
{
  if(encodeState != NULL) {
    AIMJK_managedBuffer_release(&encodeState->stringBuffer);
    AIMJK_managedBuffer_release(&encodeState->utf8ConversionBuffer);
    free(encodeState); encodeState = NULL;
  }  
}

- (void)dealloc
{
  [self releaseState];
  [super dealloc];
}

@end

@implementation NSString (JSONKitSerializing)

////////////
#pragma mark Methods for serializing a single NSString.
////////////

// Useful for those who need to serialize just a NSString.  Otherwise you would have to do something like [NSArray arrayWithObject:stringToBeJSONSerialized], serializing the array, and then chopping of the extra ^\[.*\]$ square brackets.

// NSData returning methods...

- (NSData *)JSONData
{
  return([self AIMJSONDataWithOptions:AIMJKSerializeOptionNone includeQuotes:YES error:NULL]);
}

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions includeQuotes:(BOOL)includeQuotes error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | ((includeQuotes == NO) ? AIMJKEncodeOptionStringObjTrimQuotes : 0UL) | AIMJKEncodeOptionStringObj) block:NULL delegate:NULL selector:NULL error:error]);
}

// NSString returning methods...

- (NSString *)JSONString
{
  return([self AIMJSONStringWithOptions:AIMJKSerializeOptionNone includeQuotes:YES error:NULL]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions includeQuotes:(BOOL)includeQuotes error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | ((includeQuotes == NO) ? AIMJKEncodeOptionStringObjTrimQuotes : 0UL) | AIMJKEncodeOptionStringObj) block:NULL delegate:NULL selector:NULL error:error]);
}

@end

@implementation NSArray (JSONKitSerializing)

// NSData returning methods...

- (NSData *)JSONData
{
  return([AIMJKSerializer serializeObject:self options:AIMJKSerializeOptionNone encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:NULL]);
}

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:error]);
}

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingDelegate:(id)delegate selector:(SEL)selector error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:NULL delegate:delegate selector:selector error:error]);
}

// NSString returning methods...

- (NSString *)JSONString
{
  return([AIMJKSerializer serializeObject:self options:AIMJKSerializeOptionNone encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:NULL]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:error]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingDelegate:(id)delegate selector:(SEL)selector error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:NULL delegate:delegate selector:selector error:error]);
}

@end

@implementation NSDictionary (JSONKitSerializing)

// NSData returning methods...

- (NSData *)JSONData
{
  return([AIMJKSerializer serializeObject:self options:AIMJKSerializeOptionNone encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:NULL]);
}

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:error]);
}

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingDelegate:(id)delegate selector:(SEL)selector error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:NULL delegate:delegate selector:selector error:error]);
}

// NSString returning methods...

- (NSString *)JSONString
{
  return([AIMJKSerializer serializeObject:self options:AIMJKSerializeOptionNone encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:NULL]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:NULL delegate:NULL selector:NULL error:error]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingDelegate:(id)delegate selector:(SEL)selector error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:NULL delegate:delegate selector:selector error:error]);
}

@end


#ifdef __BLOCKS__

@implementation NSArray (JSONKitSerializingBlockAdditions)

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingBlock:(id(^)(id object))block error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:block delegate:NULL selector:NULL error:error]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingBlock:(id(^)(id object))block error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:block delegate:NULL selector:NULL error:error]);
}

@end

@implementation NSDictionary (JSONKitSerializingBlockAdditions)

- (NSData *)JSONDataWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingBlock:(id(^)(id object))block error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsData | AIMJKEncodeOptionCollectionObj) block:block delegate:NULL selector:NULL error:error]);
}

- (NSString *)JSONStringWithOptions:(AIMJKSerializeOptionFlags)serializeOptions serializeUnsupportedClassesUsingBlock:(id(^)(id object))block error:(NSError **)error
{
  return([AIMJKSerializer serializeObject:self options:serializeOptions encodeOption:(AIMJKEncodeOptionAsString | AIMJKEncodeOptionCollectionObj) block:block delegate:NULL selector:NULL error:error]);
}

@end

#endif // __BLOCKS__

