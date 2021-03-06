//
//  Internal.m
//  ECHO
//
//  Created by Fedorenko Nikita on 7.09.2018.
//  Copyright © 2018 PixelPlex. All rights reserved.
//

#import "Internal.h"

#import <openssl/sha.h>
#import <openssl/ripemd.h>
#import <openssl/hmac.h>
#import <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/evp.h>
#include <openssl/obj_mac.h>
#include <openssl/bn.h>
#include <openssl/rand.h>
#import "BTCData.h"

#import <CommonCrypto/CommonCrypto.h>

@implementation CryptoHash

+ (NSData *)sha256:(NSData *)data {
    NSMutableData *result = [NSMutableData dataWithLength:SHA256_DIGEST_LENGTH];
    SHA256(data.bytes, data.length, result.mutableBytes);
    return result;
}

+ (NSData *)sha512:(NSData *)data {
    NSMutableData *result = [NSMutableData dataWithLength:SHA512_DIGEST_LENGTH];
    SHA512(data.bytes, data.length, result.mutableBytes);
    return result;
}

+ (NSData *)ripemd160:(NSData *)data {
    NSMutableData *result = [NSMutableData dataWithLength:RIPEMD160_DIGEST_LENGTH];
    RIPEMD160(data.bytes, data.length, result.mutableBytes);
    return result;
}

@end

@implementation Secp256k1

+ (NSData *)dataFromHexString:(NSString *)string {
    string = [string lowercaseString];
    NSMutableData *data= [NSMutableData new];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    int i = 0;
    int length = (int)string.length;
    while (i < length-1) {
        char c = [string characterAtIndex:i++];
        if (c < '0' || (c > '9' && c < 'a') || c > 'f')
            continue;
        byte_chars[0] = c;
        byte_chars[1] = [string characterAtIndex:i++];
        whole_byte = strtol(byte_chars, NULL, 16);
        [data appendBytes:&whole_byte length:1];
    }
    return data;
}

+ (NSString *)hexFromData:(NSData *)data {
    
    NSUInteger length = data.length;
    if (length == 0) return @"";
    
    NSMutableData* resultdata = [NSMutableData dataWithLength:length * 2];
    char *dest = resultdata.mutableBytes;
    unsigned const char *src = data.bytes;
    for (int i = 0; i < length; ++i) {
        sprintf(dest + i*2, "%02x", (unsigned int)(src[i]));
    }
    return [[NSString alloc] initWithData:resultdata encoding:NSASCIIStringEncoding];
}

#pragma mark - Encryption / Decryption

+ (NSMutableData*) encryptData:(NSData*)data key:(NSData*)key iv:(NSData*)initializationVector {
    return [Secp256k1 cryptData:data key:key iv:initializationVector operation:kCCEncrypt];
}

+ (NSMutableData*) decryptData:(NSData*)data key:(NSData*)key iv:(NSData*)initializationVector {
    return [Secp256k1 cryptData:data key:key iv:initializationVector operation:kCCDecrypt];
}

+ (NSMutableData*) cryptData:(NSData*)data key:(NSData*)key iv:(NSData*)iv operation:(CCOperation)operation {
    if (!data || !key) return nil;
    
    int blockSize = kCCBlockSizeAES128;
    int encryptedDataCapacity = (int)(data.length / blockSize + 1) * blockSize;
    NSMutableData* encryptedData = [[NSMutableData alloc] initWithLength:encryptedDataCapacity];
    
    // Treat empty IV as nil
    if (iv.length == 0) {
        iv = nil;
    }
    
    // If IV is supplied, validate it.
    if (iv) {
        if (iv.length == blockSize) {
            // perfect.
        } else if (iv.length > blockSize) {
            // IV is bigger than the block size. CCCrypt will take only the first 16 bytes.
        } else {
            // IV is smaller than needed. This should not happen. It's better to crash than to leak something.
            @throw [NSException exceptionWithName:@"IV is invalid"
                                           reason:[NSString stringWithFormat:@"Invalid size of IV: %d", (int)iv.length]
                                         userInfo:nil];
        }
    }
    
    size_t dataOutMoved = 0;
    CCCryptorStatus cryptstatus = CCCrypt(
                                          operation,                   // CCOperation op,         /* kCCEncrypt, kCCDecrypt */
                                          kCCAlgorithmAES,             // CCAlgorithm alg,        /* kCCAlgorithmAES128, etc. */
                                          kCCOptionPKCS7Padding,       // CCOptions options,      /* kCCOptionPKCS7Padding, etc. */
                                          key.bytes,                   // const void *key,
                                          key.length,                  // size_t keyLength,
                                          iv ? iv.bytes : NULL,        // const void *iv,         /* optional initialization vector */
                                          data.bytes,                  // const void *dataIn,     /* optional per op and alg */
                                          data.length,                 // size_t dataInLength,
                                          encryptedData.mutableBytes,  // void *dataOut,          /* data RETURNED here */
                                          encryptedData.length,        // size_t dataOutAvailable,
                                          &dataOutMoved                // size_t *dataOutMoved
                                          );
    
    if (cryptstatus == kCCSuccess) {
        // Resize the result key to the correct size.
        encryptedData.length = dataOutMoved;
        return encryptedData;
    } else {
        //kCCSuccess          = 0,
        //kCCParamError       = -4300,
        //kCCBufferTooSmall   = -4301,
        //kCCMemoryFailure    = -4302,
        //kCCAlignmentError   = -4303,
        //kCCDecodeError      = -4304,
        //kCCUnimplemented    = -4305,
        //kCCOverflow         = -4306
        @throw [NSException exceptionWithName:@"CCCrypt failed"
                                       reason:[NSString stringWithFormat:@"error: %d", cryptstatus] userInfo:nil];
        return nil;
    }
}

/**
 * Decodes an ascii string to a byte array.
 */
+ (NSData *)hexlify:(NSData *)data {
    
    NSString *hexString = [Secp256k1 hexFromData:data];
    NSData *newData = [hexString dataUsingEncoding:NSASCIIStringEncoding];
    
    return newData;
}

+ (NSData *)encryptMessageWithPrivateKey:(NSData *)privateKey publicKey:(NSData *)publicKey nonce:(NSString *)nonce message:(NSString *)message {
    
    // Nonce bytes
    NSData *nonceData = [nonce dataUsingEncoding:NSUTF8StringEncoding];
    
    // Private key
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *private = EC_KEY_new_by_curve_name(NID_secp256k1);
    const EC_GROUP *privateGroup = EC_KEY_get0_group(private);
    
    BIGNUM *prv = BN_new();
    BN_bin2bn(privateKey.bytes, (int)privateKey.length, prv);
    
    EC_POINT *pub = EC_POINT_new(privateGroup);
    EC_POINT_mul(privateGroup, pub, prv, nil, nil, ctx);
    EC_KEY_set_private_key(private, prv);
    EC_KEY_set_public_key(private, pub);
    
    // Public key
    EC_KEY *public = EC_KEY_new_by_curve_name(NID_secp256k1);
    const unsigned char* bytes = publicKey.bytes;
    o2i_ECPublicKey(&public, &bytes, publicKey.length);
    
    // Bignum pk
    BIGNUM pk;
    BN_init(&pk);
    BN_bin2bn(privateKey.bytes, (int)privateKey.length, &pk);
    
    // Curve point
    const EC_POINT* ecpoint = EC_KEY_get0_public_key(public);
    const EC_GROUP* group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    BN_CTX* bnctx = BN_CTX_new();
    EC_POINT* point = EC_POINT_new(group);
    EC_POINT_copy(point, ecpoint);
    
    // Multiply
    EC_POINT_mul(group, point, NULL, point, &pk, bnctx);
    
    // X Point
    BN_CTX_start(bnctx);
    BIGNUM* xPoint = BN_CTX_get(bnctx);
    EC_POINT_get_affine_coordinates_GFp(group, point, xPoint /* x */, NULL  /* y */, bnctx);
    BN_CTX_end(bnctx);
    
    // X.unsignedBigEndian
    int num_bytes = BN_num_bytes(xPoint);
    NSMutableData* xPointData = [[NSMutableData alloc] initWithLength:32];
    BN_bn2bin(xPoint, &xPointData.mutableBytes[32 - num_bytes]);
    
    // Free
    BN_free(prv);
    EC_POINT_free(pub);
    EC_KEY_free(private);
    BN_CTX_free(ctx);
    
    NSData* hash = [CryptoHash sha512:xPointData];
    NSData* hashInASCII = [Secp256k1 hexlify:hash];
    
    NSMutableData* seed = [nonceData mutableCopy];
    [seed appendData:hashInASCII];
    
    NSData* checksum = [[CryptoHash sha256:[message dataUsingEncoding:NSUTF8StringEncoding]] subdataWithRange:NSMakeRange(0, 4)];
    
    NSMutableData* payload = checksum.mutableCopy;
    [payload appendData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData* hashedSeedData = [CryptoHash sha512:seed];
    NSString* hashedSeed = [Secp256k1 hexFromData:hashedSeedData];
    
    NSData *key = [Secp256k1 dataFromHexString:[hashedSeed substringWithRange:NSMakeRange(0, 64)]];
    NSData* iv = [Secp256k1 dataFromHexString:[hashedSeed substringWithRange:NSMakeRange(64, 32)]];
    
    return [Secp256k1 encryptData:payload key:key iv:iv];
}

+ (NSString *)decryptMessageWithPrivateKey:(NSData *)privateKey publicKey:(NSData *)publicKey nonce:(NSString *)nonce message:(NSData *)message {
    
    // Nonce bytes
    NSData *nonceData = [nonce dataUsingEncoding:NSUTF8StringEncoding];
    
    // Private key
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *private = EC_KEY_new_by_curve_name(NID_secp256k1);
    const EC_GROUP *privateGroup = EC_KEY_get0_group(private);
    
    BIGNUM *prv = BN_new();
    BN_bin2bn(privateKey.bytes, (int)privateKey.length, prv);
    
    EC_POINT *pub = EC_POINT_new(privateGroup);
    EC_POINT_mul(privateGroup, pub, prv, nil, nil, ctx);
    EC_KEY_set_private_key(private, prv);
    EC_KEY_set_public_key(private, pub);
    
    // Public key
    EC_KEY *public = EC_KEY_new_by_curve_name(NID_secp256k1);
    const unsigned char* bytes = publicKey.bytes;
    o2i_ECPublicKey(&public, &bytes, publicKey.length);
    
    // Bignum pk
    BIGNUM pk;
    BN_init(&pk);
    BN_bin2bn(privateKey.bytes, (int)privateKey.length, &pk);
    
    // Curve point
    const EC_POINT* ecpoint = EC_KEY_get0_public_key(public);
    const EC_GROUP* group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    BN_CTX* bnctx = BN_CTX_new();
    EC_POINT* point = EC_POINT_new(group);
    EC_POINT_copy(point, ecpoint);
    
    // Multiply
    EC_POINT_mul(group, point, NULL, point, &pk, bnctx);
    
    // X Point
    BN_CTX_start(bnctx);
    BIGNUM* xPoint = BN_CTX_get(bnctx);
    EC_POINT_get_affine_coordinates_GFp(group, point, xPoint /* x */, NULL  /* y */, bnctx);
    BN_CTX_end(bnctx);
    
    // X.unsignedBigEndian
    int num_bytes = BN_num_bytes(xPoint);
    NSMutableData* xPointData = [[NSMutableData alloc] initWithLength:32];
    BN_bn2bin(xPoint, &xPointData.mutableBytes[32 - num_bytes]);
    
    // Free
    BN_free(prv);
    EC_POINT_free(pub);
    EC_KEY_free(private);
    BN_CTX_free(ctx);
    
    NSData* hash = [CryptoHash sha512:xPointData];
    NSData* hashInASCII = [Secp256k1 hexlify:hash];
    
    NSMutableData* seed = [nonceData mutableCopy];
    [seed appendData:hashInASCII];
    
    NSData* hashedSeedData = [CryptoHash sha512:seed];
    NSString* hashedSeed = [Secp256k1 hexFromData:hashedSeedData];
    
    NSData* key = [Secp256k1 dataFromHexString:[hashedSeed substringWithRange:NSMakeRange(0, 64)]];
    NSData* iv = [Secp256k1 dataFromHexString:[hashedSeed substringWithRange:NSMakeRange(64, 32)]];
    
    NSData* decoded = [Secp256k1 decryptData:message key:key iv:iv];
    NSData* decodedMessageData = [decoded subdataWithRange:NSMakeRange(4, decoded.length - 4)];
    NSData* checkSum = [decoded subdataWithRange:NSMakeRange(0, 4)];
    NSData* verificationCheckSum = [[CryptoHash sha256:decodedMessageData] subdataWithRange:NSMakeRange(0, 4)];
    
    if (![checkSum isEqual:verificationCheckSum] ) {
        NSLog(@"Checksums not equals");
        return [NSString new];
    }
    
    NSString* string = [NSString stringWithUTF8String:[decodedMessageData bytes]];
    
    return string;
}

+ (NSData *)generatePublicKeyWithPrivateKey:(NSData *)privateKeyData compression:(BOOL)isCompression {
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *key = EC_KEY_new_by_curve_name(NID_secp256k1);
    const EC_GROUP *group = EC_KEY_get0_group(key);
    
    BIGNUM *prv = BN_new();
    BN_bin2bn(privateKeyData.bytes, (int)privateKeyData.length, prv);
    
    EC_POINT *pub = EC_POINT_new(group);
    EC_POINT_mul(group, pub, prv, nil, nil, ctx);
    EC_KEY_set_private_key(key, prv);
    EC_KEY_set_public_key(key, pub);
    
    NSMutableData *result;
    if (isCompression) {
        EC_KEY_set_conv_form(key, POINT_CONVERSION_COMPRESSED);
        unsigned char *bytes = NULL;
        int length = i2o_ECPublicKey(key, &bytes);
        result = [NSMutableData dataWithBytesNoCopy:bytes length:length];
    } else {
        result = [NSMutableData dataWithLength:65];
        BIGNUM *n = BN_new();
        EC_POINT_point2bn(group, pub, POINT_CONVERSION_UNCOMPRESSED, n, ctx);
        BN_bn2bin(n, result.mutableBytes);
        BN_free(n);
    }
    
    BN_free(prv);
    EC_POINT_free(pub);
    EC_KEY_free(key);
    BN_CTX_free(ctx);
    
    return result;
}
    
+ (NSData *)sign:(NSData *)hash privateKey:(NSData *)privateKeyData isPubKeyCompressed:(BOOL)isPubKeyCompressed {
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *key = EC_KEY_new_by_curve_name(NID_secp256k1);
    const EC_GROUP *group = EC_KEY_get0_group(key);
    
    BIGNUM *prv = BN_new();
    BN_bin2bn(privateKeyData.bytes, (int)privateKeyData.length, prv);
    
    EC_POINT *pub = EC_POINT_new(group);
    EC_POINT_mul(group, pub, prv, nil, nil, ctx);
    EC_KEY_set_private_key(key, prv);
    EC_KEY_set_public_key(key, pub);
    
    NSMutableData* sigdata = [NSMutableData dataWithLength:65];
    unsigned char* sigbytes = sigdata.mutableBytes;
    const unsigned char* hashbytes = hash.bytes;
    int hashlength = (int)hash.length;
    
    int rec = -1;
    
    unsigned char *p64 = (sigbytes + 1); // first byte is reserved for header.
    
    ECDSA_SIG *sig = ECDSA_do_sign(hashbytes, hashlength, key);
    if (sig==NULL) {
        return nil;
    }
    memset(p64, 0, 64);
    int nBitsR = BN_num_bits(sig->r);
    int nBitsS = BN_num_bits(sig->s);
    if (nBitsR <= 256 && nBitsS <= 256) {
        NSData* pubkey = [Secp256k1 generatePublicKeyWithPrivateKey:privateKeyData compression:YES];
        BOOL foundMatchingPubkey = NO;
        for (int i=0; i < 4; i++) {
            // It will be updated via direct access to _key ivar.
            EC_KEY* key2 = EC_KEY_new_by_curve_name(NID_secp256k1);
            if (ECDSA_SIG_recover_key_GFp(key2, sig, hashbytes, hashlength, i, 1) == 1) {
                EC_KEY_set_conv_form(key2, POINT_CONVERSION_COMPRESSED);
                unsigned char *bytes = NULL;
                int length = i2o_ECPublicKey(key2, &bytes);
                NSData* pubkey2 = [NSMutableData dataWithBytesNoCopy:bytes length:length];
                if ([pubkey isEqual:pubkey2]) {
                    rec = i;
                    foundMatchingPubkey = YES;
                    break;
                }
            }
        }
        NSAssert(foundMatchingPubkey, @"At least one signature must work.");
        BN_bn2bin(sig->r,&p64[32-(nBitsR+7)/8]);
        BN_bn2bin(sig->s,&p64[64-(nBitsS+7)/8]);
    }
    ECDSA_SIG_free(sig);
    
    BN_free(prv);
    EC_POINT_free(pub);
    EC_KEY_free(key);
    BN_CTX_free(ctx);
    
    // First byte is a header
    sigbytes[0] = 0x1b + rec + (isPubKeyCompressed ? 4 : 0);
    return sigdata;
}

// Perform ECDSA key recovery (see SEC1 4.1.6) for curves over (mod p)-fields
// recid selects which key is recovered
// if check is non-zero, additional checks are performed
static int ECDSA_SIG_recover_key_GFp(EC_KEY *eckey, ECDSA_SIG *ecsig, const unsigned char *msg, int msglen, int recid, int check) {
    if (!eckey) return 0;
    
    int ret = 0;
    BN_CTX *ctx = NULL;
    
    BIGNUM *x = NULL;
    BIGNUM *e = NULL;
    BIGNUM *order = NULL;
    BIGNUM *sor = NULL;
    BIGNUM *eor = NULL;
    BIGNUM *field = NULL;
    EC_POINT *R = NULL;
    EC_POINT *O = NULL;
    EC_POINT *Q = NULL;
    BIGNUM *rr = NULL;
    BIGNUM *zero = NULL;
    int n = 0;
    int i = recid / 2;
    
    const EC_GROUP *group = EC_KEY_get0_group(eckey);
    if ((ctx = BN_CTX_new()) == NULL) { ret = -1; goto err; }
    BN_CTX_start(ctx);
    order = BN_CTX_get(ctx);
    if (!EC_GROUP_get_order(group, order, ctx)) { ret = -2; goto err; }
    x = BN_CTX_get(ctx);
    if (!BN_copy(x, order)) { ret=-1; goto err; }
    if (!BN_mul_word(x, i)) { ret=-1; goto err; }
    if (!BN_add(x, x, ecsig->r)) { ret=-1; goto err; }
    field = BN_CTX_get(ctx);
    if (!EC_GROUP_get_curve_GFp(group, field, NULL, NULL, ctx)) { ret=-2; goto err; }
    if (BN_cmp(x, field) >= 0) { ret=0; goto err; }
    if ((R = EC_POINT_new(group)) == NULL) { ret = -2; goto err; }
    if (!EC_POINT_set_compressed_coordinates_GFp(group, R, x, recid % 2, ctx)) { ret=0; goto err; }
    if (check) {
        if ((O = EC_POINT_new(group)) == NULL) { ret = -2; goto err; }
        if (!EC_POINT_mul(group, O, NULL, R, order, ctx)) { ret=-2; goto err; }
        if (!EC_POINT_is_at_infinity(group, O)) { ret = 0; goto err; }
    }
    if ((Q = EC_POINT_new(group)) == NULL) { ret = -2; goto err; }
    n = EC_GROUP_get_degree(group);
    e = BN_CTX_get(ctx);
    if (!BN_bin2bn(msg, msglen, e)) { ret=-1; goto err; }
    if (8*msglen > n) BN_rshift(e, e, 8-(n & 7));
    zero = BN_CTX_get(ctx);
    if (!BN_zero(zero)) { ret=-1; goto err; }
    if (!BN_mod_sub(e, zero, e, order, ctx)) { ret=-1; goto err; }
    rr = BN_CTX_get(ctx);
    if (!BN_mod_inverse(rr, ecsig->r, order, ctx)) { ret=-1; goto err; }
    sor = BN_CTX_get(ctx);
    if (!BN_mod_mul(sor, ecsig->s, rr, order, ctx)) { ret=-1; goto err; }
    eor = BN_CTX_get(ctx);
    if (!BN_mod_mul(eor, e, rr, order, ctx)) { ret=-1; goto err; }
    if (!EC_POINT_mul(group, Q, eor, R, sor, ctx)) { ret=-2; goto err; }
    if (!EC_KEY_set_public_key(eckey, Q)) { ret=-2; goto err; }
    
    ret = 1;
    
err:
    if (ctx) {
        BN_CTX_end(ctx);
        BN_CTX_free(ctx);
    }
    if (R != NULL) EC_POINT_free(R);
    if (O != NULL) EC_POINT_free(O);
    if (Q != NULL) EC_POINT_free(Q);
    return ret;
}

@end


#define BTCBigNumberCompare(a, b) (BN_cmp(&(a->_bignum), &(b->_bignum)))

@implementation BTCBigNumber {
    @package
    BIGNUM _bignum;
    
    // Used as a guard in case a private setter is called on immutable instance after initialization.
    BOOL _immutable;
}

@dynamic compact;
@dynamic uint32value;
@dynamic int32value;
@dynamic uint64value;
@dynamic int64value;
@dynamic hexString;
@dynamic decimalString;
@dynamic signedLittleEndian;
@dynamic unsignedBigEndian;
@dynamic littleEndianData; // deprecated
@dynamic unsignedData; // deprecated

+ (instancetype) zero {
    static BTCBigNumber* bn = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bn = [[self alloc] init];
        BN_zero(&(bn->_bignum));
    });
    return bn;
}

+ (instancetype) one {
    static BTCBigNumber* bn = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bn = [[self alloc] init];
        BN_one(&(bn->_bignum));
    });
    return bn;
}

+ (instancetype) negativeOne {
    static BTCBigNumber* bn = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bn = [[self alloc] initWithInt32:-1];
    });
    return bn;
}

- (id) init {
    if (self = [super init]) {
        BN_init(&_bignum);
    }
    return self;
}

- (void) dealloc {
    BN_clear_free(&_bignum);
}

- (void) clear {
    BN_clear(&_bignum);
}

- (void) throwIfImmutable {
    if (_immutable) {
        @throw [NSException exceptionWithName:@"Immutable BTCBigNumber is modified" reason:@"" userInfo:nil];
    }
}

// Since we use private setters in the init* methods,
- (id) initWithCompact:(uint32_t)value {
    if (self = [self init]) self.compact = value;
    _immutable = YES;
    return self;
}
- (id) initWithUInt32:(uint32_t)value {
    if (self = [self init]) self.uint32value = value;
    _immutable = YES;
    return self;
}
- (id) initWithInt32:(int32_t)value {
    if (self = [self init]) self.int32value = value;
    _immutable = YES;
    return self;
}
- (id) initWithUInt64:(uint64_t)value {
    if (self = [self init]) self.uint64value = value;
    _immutable = YES;
    return self;
}
- (id) initWithInt64:(int64_t)value {
    if (self = [self init]) self.int64value = value;
    _immutable = YES;
    return self;
}
- (id) initWithSignedLittleEndian:(NSData *)data {
    if (!data) return nil;
    if (self = [self init]) self.signedLittleEndian = data;
    _immutable = YES;
    return self;
}
- (id) initWithUnsignedBigEndian:(NSData *)data {
    if (!data) return nil;
    if (self = [self init]) self.unsignedBigEndian = data;
    _immutable = YES;
    return self;
}
- (id) initWithLittleEndianData:(NSData*)data { // deprecated
    if (!data) return nil;
    if (self = [self init]) self.signedLittleEndian = data;
    _immutable = YES;
    return self;
}
- (id) initWithUnsignedData:(NSData *)data { // deprecated
    if (!data) return nil;
    if (self = [self init]) self.unsignedBigEndian = data;
    _immutable = YES;
    return self;
}
- (id) initWithString:(NSString*)string base:(NSUInteger)base {
    if (!string) return nil;
    if (self = [self init]) [self setString:string base:base];
    _immutable = YES;
    return self;
}

- (id) initWithHexString:(NSString*)hexString {
    return [self initWithString:hexString base:16];
}

- (id) initWithDecimalString:(NSString*)decimalString {
    return [self initWithString:decimalString base:10];
}

- (id) initWithBIGNUM:(const BIGNUM*)otherBIGNUM {
    if (self = [self init]) {
        BN_copy(&_bignum, otherBIGNUM);
    }
    return self;
}

- (const BIGNUM*) BIGNUM {
    return &_bignum;
}

- (BOOL) isZero {
    return BN_is_zero(&_bignum);
}

- (BOOL) isOne {
    return BN_is_one(&_bignum);
}


#pragma mark - NSObject



- (BTCBigNumber*) copy {
    return [self copyWithZone:nil];
}

- (BTCMutableBigNumber*) mutableCopy {
    return [self mutableCopyWithZone:nil];
}

- (BTCBigNumber*) copyWithZone:(NSZone *)zone {
    BTCBigNumber* to = [[BTCBigNumber alloc] init];
    if (BN_copy(&(to->_bignum), &_bignum)) {
        return to;
    }
    return nil;
}

- (BTCMutableBigNumber*) mutableCopyWithZone:(NSZone *)zone {
    BTCMutableBigNumber* to = [[BTCMutableBigNumber alloc] init];
    if (BN_copy(&(to->_bignum), &_bignum)) {
        return to;
    }
    return nil;
}


- (BOOL) isEqual:(BTCBigNumber*)other {
    if (![other isKindOfClass:[BTCBigNumber class]]) return NO;
    return BTCBigNumberCompare(self, other) == NSOrderedSame;
}

- (NSComparisonResult)compare:(BTCBigNumber *)other {
    return BTCBigNumberCompare(self, other);
}

- (NSUInteger)hash {
    return (NSUInteger)BN_get_word(&_bignum);
}

- (NSString*) description {
    return [NSString stringWithFormat:@"<%@:0x%p 0x%@ (%@)>", [self class], self, [self stringInBase:16], [self stringInBase:10]];
}




#pragma mark - Comparison


- (BTCBigNumber*) min:(BTCBigNumber*)other {
    return (BTCBigNumberCompare(self, other) <= 0) ? self : other;
}

- (BTCBigNumber*) max:(BTCBigNumber*)other {
    return (BTCBigNumberCompare(self, other) >= 0) ? self : other;
}

- (BOOL) less:(BTCBigNumber *)other           { return BTCBigNumberCompare(self, other) <  0; }
- (BOOL) lessOrEqual:(BTCBigNumber *)other    { return BTCBigNumberCompare(self, other) <= 0; }
- (BOOL) greater:(BTCBigNumber *)other        { return BTCBigNumberCompare(self, other) >  0; }
- (BOOL) greaterOrEqual:(BTCBigNumber *)other { return BTCBigNumberCompare(self, other) >= 0; }




#pragma mark - Conversion




- (NSString*) hexString {
    return [self stringInBase:16];
}

- (void) setHexString:(NSString *)hexString {
    [self throwIfImmutable];
    [self setString:hexString base:16];
}

- (NSString*) decimalString {
    return [self stringInBase:10];
}

- (void) setDecimalString:(NSString *)decimalString {
    [self throwIfImmutable];
    [self setString:decimalString base:10];
}

- (void) setString:(NSString*)string base:(NSUInteger)base {
    [self throwIfImmutable];
    if (base > 36 || base < 2) return;
    
    BN_set_word(&_bignum, 0);
    
    if (string.length == 0) return;
    
    const unsigned char *psz = (const unsigned char*)[string cStringUsingEncoding:NSASCIIStringEncoding];
    
    while (isspace(*psz)) psz++;
    
    bool isNegative = false;
    if (*psz == '-') {
        isNegative = true;
        psz++;
    }
    
    // Strip 0x from a 16-base string and 0b from a binary string.
    // String is null-terminated, so it's safe to check for [1] if [0] is not null
    if (base == 16 && psz[0] == '0' && tolower(psz[1]) == 'x') psz += 2;
    if (base == 2  && psz[0] == '0' && tolower(psz[1]) == 'b') psz += 2;
    
    while (isspace(*psz)) psz++;
    
    static const signed char digits[256] = {
        //  0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  0,  0,  0,  0,  0,  0,
        //  @   A   B   C   D   E   F   G   H   I   J   K   L   M   N   O
        0, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        //  P   Q   R   S   T   U   V   W   X   Y   Z   [   \   ]   ^   _
        25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,  0,  0,  0,  0,  0,
        //  `   a   b   c   d   e   f   g   h   i   j   k   l   m   n   o
        0, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        //  p   q   r   s   t   u   v   w   x   y   z   {   |   }   ~   del
        25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    };
    
    BN_CTX* pctx = NULL;
    BIGNUM bnBase; BN_init(&bnBase); BN_set_word(&bnBase, (BN_ULONG)base);
    
    while (1) {
        unsigned char c = (unsigned char)*psz++;
        if (c == 0) break; // break when null-terminator is hit
        
        if (c != 0x20) { // skip space
            
            int n = digits[c];
            if (n == 0 && c != 0x30) break; // discard characters outside the 36-char range
            if (n >= base) break; // discard character outside the base range.
            
            if (base == 16) {
                BN_lshift(&_bignum, &_bignum, 4);
            } else if (base == 8) {
                BN_lshift(&_bignum, &_bignum, 3);
            } else if (base == 4) {
                BN_lshift(&_bignum, &_bignum, 2);
            } else if (base == 2) {
                BN_lshift(&_bignum, &_bignum, 1);
            } else if (base == 32) {
                BN_lshift(&_bignum, &_bignum, 5);
            } else {
                if (!pctx) pctx = BN_CTX_new();
                BN_mul(&_bignum, &_bignum, &bnBase, pctx);
            }
            
            BN_add_word(&_bignum, n);
        }
    }
    
    if (isNegative) {
        BN_set_negative(&_bignum, 1);
    }
    
    BN_free(&bnBase);
    if (pctx) BN_CTX_free(pctx);
}

- (NSString*) stringInBase:(NSUInteger)base {
    if (base > 36 || base < 2) return nil;
    
    NSMutableData* resultData = nil;
    
    BN_CTX* pctx = BN_CTX_new();
    BIGNUM bnBase; BN_init(&bnBase); BN_set_word(&bnBase, (BN_ULONG)base);
    BIGNUM bn0;    BN_init(&bn0);    BN_zero(&bn0);
    BIGNUM bn;     BN_init(&bn);     BN_copy(&bn, &_bignum);
    
    BN_set_negative(&bn, false);
    
    BIGNUM dv;  BN_init(&dv);
    BIGNUM rem; BN_init(&rem);
    
    if (BN_cmp(&bn, &bn0) == 0) {
        resultData = [NSMutableData dataWithBytes:"0" length:1];
    } else {
        while (BN_cmp(&bn, &bn0) > 0) {
            if (!BN_div(&dv, &rem, &bn, &bnBase, pctx)) {
                NSLog(@"BTCBigNumber: stringInBase failed to BN_div");
                break;
            }
            BN_copy(&bn, &dv);
            BN_ULONG c = BN_get_word(&rem);
            
            if (!resultData) resultData = [NSMutableData data];
            
            // 36 characters:   0123456789 123456789 123456789 12345
            unsigned char ch = "0123456789abcdefghijklmnopqrstuvwxyz"[c];
            
            [resultData replaceBytesInRange:NSMakeRange(0, 0) withBytes:&ch length:1];
        }
        if (resultData && BN_is_negative(&_bignum)) {
            unsigned char ch = '-';
            [resultData replaceBytesInRange:NSMakeRange(0, 0) withBytes:&ch length:1];
        }
    }
    
    BN_clear_free(&dv);
    BN_clear_free(&rem);
    BN_clear_free(&bn);
    BN_free(&bn0);
    BN_free(&bnBase);
    BN_CTX_free(pctx);
    return resultData ? [[NSString alloc] initWithData:resultData encoding:NSASCIIStringEncoding] : nil;
}


// The "compact" format is a representation of a whole
// number N using an unsigned 32bit number similar to a
// floating point format.
// The most significant 8 bits are the unsigned exponent of base 256.
// This exponent can be thought of as "number of bytes of N".
// The lower 23 bits are the mantissa.
// Bit number 24 (0x800000) represents the sign of N.
// N = (-1^sign) * mantissa * 256^(exponent-3)
//
// Satoshi's original implementation used BN_bn2mpi() and BN_mpi2bn().
// MPI uses the most significant bit of the first byte as sign.
// Thus 0x1234560000 is compact (0x05123456)
// and  0xc0de000000 is compact (0x0600c0de)
// (0x05c0de00) would be -0x40de000000
//
// Bitcoin only uses this "compact" format for encoding difficulty
// targets, which are unsigned 256bit quantities.  Thus, all the
// complexities of the sign bit and using base 256 are probably an
// implementation accident.
//
// This implementation directly uses shifts instead of going
// through an intermediate MPI representation.
- (uint32_t) compact {
    uint32_t size = BN_num_bytes(&_bignum);
    uint32_t result = 0;
    if (size <= 3) {
        result = (uint32_t)(BN_get_word(&_bignum) << 8*(3-size));
    } else {
        BIGNUM bn;
        BN_init(&bn);
        BN_rshift(&bn, &_bignum, 8*(size-3));
        result = (uint32_t)BN_get_word(&bn);
    }
    // The 0x00800000 bit denotes the sign.
    // Thus, if it is already set, divide the mantissa by 256 and increase the exponent.
    if (result & 0x00800000) {
        result >>= 8;
        size++;
    }
    result |= size << 24;
    result |= (BN_is_negative(&_bignum) ? 0x00800000 : 0);
    return result;
}

- (void) setCompact:(uint32_t)value {
    [self throwIfImmutable];
    unsigned int size = value >> 24;
    bool isNegative   = (value & 0x00800000) != 0;
    unsigned int word = value & 0x007fffff;
    if (size <= 3) {
        word >>= 8*(3-size);
        BN_set_word(&_bignum, word);
    } else {
        BN_set_word(&_bignum, word);
        BN_lshift(&_bignum, &_bignum, 8*(size-3));
    }
    BN_set_negative(&_bignum, isNegative);
}

- (uint32_t) uint32value {
    return (uint32_t)BN_get_word(&_bignum);
}

- (void) setUint32value:(uint32_t)value {
    [self throwIfImmutable];
    BN_set_word(&_bignum, value);
}

- (int32_t) int32value {
    uint32_t value = [self uint32value];
    if (!BN_is_negative(&_bignum)) {
        if (value > INT32_MAX)
            return INT32_MAX;
        else
            return value;
    } else {
        if (value > INT32_MAX)
            return INT32_MIN;
        else
            return -value;
    }
}

- (void) setInt32value:(int32_t)value {
    [self throwIfImmutable];
    if (value >= 0) {
        self.uint32value = value;
    } else {
        self.int64value = value;
    }
}

- (uint64_t) uint64value {
    return (uint64_t)BN_get_word(&_bignum);
}

- (int64_t) int64value {
    return (int64_t)BN_get_word(&_bignum);
}

- (void) setUint64value:(uint64_t)value {
    [self throwIfImmutable];
    [self setUint64valuePrivate:value negative:NO];
}

- (void) setInt64value:(int64_t)value {
    [self throwIfImmutable];
    bool isNegative = NO;
    uint64_t uintValue;
    if (value < 0) {
        // Since the minimum signed integer cannot be represented as
        // positive so long as its type is signed, and it's not well-defined
        // what happens if you make it unsigned before negating it, we
        // instead increment the negative integer by 1, convert it, then
        // increment the (now positive) unsigned integer by 1 to compensate.
        uintValue = -(value + 1);
        ++uintValue;
        isNegative = YES;
    } else {
        uintValue = value;
    }
    
    [self setUint64valuePrivate:uintValue negative:isNegative];
}

- (void) setUint64valuePrivate:(uint64_t)value negative:(BOOL)isNegative {
    // Numbers are represented in OpenSSL using the MPI format. 4 byte length.
    unsigned char rawMPI[sizeof(value) + 6];
    unsigned char* currentByte = &rawMPI[4];
    BOOL leadingZeros = YES;
    for (int i = 0; i < 8; ++i) {
        uint8_t c = (value >> 56) & 0xff;
        value <<= 8;
        if (leadingZeros) {
            if (c == 0) continue; // Skip beginning zeros
            
            if (c & 0x80) {
                *currentByte = (isNegative ? 0x80 : 0);
                ++currentByte;
            } else if (isNegative) {
                c |= 0x80;
            }
            leadingZeros = false;
        }
        *currentByte = c;
        ++currentByte;
    }
    unsigned long size = currentByte - (rawMPI + 4);
    rawMPI[0] = (size >> 24) & 0xff;
    rawMPI[1] = (size >> 16) & 0xff;
    rawMPI[2] = (size >> 8) & 0xff;
    rawMPI[3] = (size) & 0xff;
    BN_mpi2bn(rawMPI, (int)(currentByte - rawMPI), &_bignum);
}

- (NSData*) signedLittleEndian {
    size_t size = BN_bn2mpi(&_bignum, NULL);
    if (size <= 4) {
        return [NSData data];
    }
    NSMutableData* data = [NSMutableData dataWithLength:size];
    BN_bn2mpi(&_bignum, data.mutableBytes);
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:NULL length:0];
    BTCDataReverse(data);
    return data;
}

- (void) setSignedLittleEndian:(NSData *)data {
    [self throwIfImmutable];
    NSUInteger size = data.length;
    NSMutableData* mdata = [data mutableCopy];
    // Reverse to convert to OpenSSL bignum endianess
    BTCDataReverse(mdata);
    // BIGNUM's byte stream format expects 4 bytes of
    // big endian size data info at the front
    [mdata replaceBytesInRange:NSMakeRange(0, 0) withBytes:"\0\0\0\0" length:4];
    unsigned char* bytes = mdata.mutableBytes;
    bytes[0] = (size >> 24) & 0xff;
    bytes[1] = (size >> 16) & 0xff;
    bytes[2] = (size >> 8) & 0xff;
    bytes[3] = (size >> 0) & 0xff;
    
    BN_mpi2bn(bytes, (int)mdata.length, &_bignum);
}

// deprecated
- (NSData*) littleEndianData {
    return self.signedLittleEndian;
}
// deprecated
- (void) setLittleEndianData:(NSData *)data {
    [self setSignedLittleEndian:data];
}

- (NSData*) unsignedBigEndian {
    int num_bytes = BN_num_bytes(&_bignum);
    NSMutableData* data = [[NSMutableData alloc] initWithLength:32]; // zeroed data
    int copied_bytes = BN_bn2bin(&_bignum, &data.mutableBytes[32 - num_bytes]); // fill the tail of the data so it's zero-padded to the left
    if (copied_bytes != num_bytes) return nil;
    return data;
}

- (void) setUnsignedBigEndian:(NSData *)data {
    [self throwIfImmutable];
    if (!data) return;
    if (!BN_bin2bn(data.bytes, (int)data.length, &_bignum)) {
        return;
    }
}

// deprecated
- (NSData*) unsignedData {
    return self.unsignedBigEndian;
}

// deprecated
- (void) setUnsignedData:(NSData *)data {
    self.unsignedBigEndian = data;
}


// Divides receiver by another bignum.
// Returns an array of two new BTCBigNumber instances: @[ quotient, remainder ]
- (NSArray*) divmod:(BTCBigNumber*)other
{
    BN_CTX* pctx = BN_CTX_new();
    BTCBigNumber* r = [BTCBigNumber new];
    BTCBigNumber* m = [BTCBigNumber new];
    BN_div(&(r->_bignum), &(m->_bignum), &(self->_bignum), &(other->_bignum), pctx);
    BN_CTX_free(pctx);
    return @[r, m];
}


#pragma mark - Util



- (void) withContext:(void(^)(BN_CTX* pctx))block
{
    BN_CTX* pctx = BN_CTX_new();
    block(pctx);
    BN_CTX_free(pctx);
}



@end




@implementation BTCMutableBigNumber

@dynamic compact;
@dynamic uint32value;
@dynamic int32value;
@dynamic uint64value;
@dynamic int64value;
@dynamic hexString;
@dynamic decimalString;
@dynamic signedLittleEndian;
@dynamic unsignedBigEndian;
@dynamic littleEndianData;
@dynamic unsignedData;

- (BIGNUM*) mutableBIGNUM {
    return &(self->_bignum);
}

+ (instancetype) zero {
    return [[BTCBigNumber zero] mutableCopy];
}

+ (instancetype) one {
    return [[BTCBigNumber one] mutableCopy];
}

+ (instancetype) negativeOne {
    return [[BTCBigNumber negativeOne] mutableCopy];
}

// We are mutable, disable checks.
- (void) throwIfImmutable {
}

- (void) setString:(NSString*)string base:(NSUInteger)base {
    [super setString:string base:base];
}


#pragma mark - Operations


- (instancetype) add:(BTCBigNumber*)other { // +=
    BN_add(&(self->_bignum), &(self->_bignum), &(other->_bignum));
    return self;
}

- (instancetype) add:(BTCBigNumber*)other mod:(BTCBigNumber*)mod {
    BN_CTX* pctx = BN_CTX_new();
    BN_mod_add(&(self->_bignum), &(self->_bignum), &(other->_bignum), &(mod->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) subtract:(BTCBigNumber *)other { // -=
    BN_sub(&(self->_bignum), &(self->_bignum), &(other->_bignum));
    return self;
}

- (instancetype) subtract:(BTCBigNumber*)other mod:(BTCBigNumber*)mod {
    BN_CTX* pctx = BN_CTX_new();
    BN_mod_sub(&(self->_bignum), &(self->_bignum), &(other->_bignum), &(mod->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) multiply:(BTCBigNumber*)other { // *=
    BN_CTX* pctx = BN_CTX_new();
    BN_mul(&(self->_bignum), &(self->_bignum), &(other->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) multiply:(BTCBigNumber*)other mod:(BTCBigNumber *)mod {
    BN_CTX* pctx = BN_CTX_new();
    BN_mod_mul(&(self->_bignum), &(self->_bignum), &(other->_bignum), &(mod->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) divide:(BTCBigNumber*)other { // /=
    BN_CTX* pctx = BN_CTX_new();
    BN_div(&(self->_bignum), NULL, &(self->_bignum), &(other->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) mod:(BTCBigNumber*)other { // %=
    BN_CTX* pctx = BN_CTX_new();
    BN_div(NULL, &(self->_bignum), &(self->_bignum), &(other->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) lshift:(unsigned int)shift { // <<=
    BN_lshift(&(self->_bignum), &(self->_bignum), shift);
    return self;
}

- (instancetype) rshift:(unsigned int)shift { // >>=
    // Note: BN_rshift segfaults on 64-bit if 2^shift is greater than the number
    //   if built on ubuntu 9.04 or 9.10, probably depends on version of OpenSSL
    BTCMutableBigNumber* a = [BTCMutableBigNumber one];
    [a lshift:shift];
    if (BN_cmp(&(a->_bignum), &(self->_bignum)) > 0) {
        BN_zero(&(self->_bignum));
        return self;
    }
    
    BN_rshift(&(self->_bignum), &(self->_bignum), shift);
    return self;
}

- (instancetype) inverseMod:(BTCBigNumber*)mod { // (a^-1) mod n
    BN_CTX* pctx = BN_CTX_new();
    BN_mod_inverse(&(self->_bignum), &(self->_bignum), &(mod->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) exp:(BTCBigNumber*)power { // pow(self, p)
    BN_CTX* pctx = BN_CTX_new();
    BN_exp(&(self->_bignum), &(self->_bignum), &(power->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}

- (instancetype) exp:(BTCBigNumber*)power mod:(BTCBigNumber *)mod { // pow(self,p) % m
    BN_CTX* pctx = BN_CTX_new();
    BN_mod_exp(&(self->_bignum), &(self->_bignum), &(power->_bignum), &(mod->_bignum), pctx);
    BN_CTX_free(pctx);
    return self;
}



@end

