#import "EJDBModel.h"
#import "EJDBDatabase.h"
#import <objc/objc-runtime.h>

//static char EJDBModelPropertiesInfoKey;

@interface EJDBModel ()
@property (nonatomic,readonly) NSDictionary *propertyGetters;
@property (nonatomic,readonly) NSDictionary *propertySetters;
@property (nonatomic,readonly) NSDictionary *propertyTypes;
@property (nonatomic,readonly) NSDictionary *modelInfo;
@property (nonatomic) NSMutableDictionary *values;
@end

@implementation EJDBModel

- (id)init
{
    self = [super init];
    if (self)
    {
        [self parseProperties];
        
    }
    return self;
}

- (NSString *)collectionName
{
    return NSStringFromClass([self class]);
}

/*
+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    NSString *selectorString = NSStringFromSelector(sel);
    NSDictionary *modelInfo = (NSDictionary *)objc_getAssociatedObject([self class],&EJDBModelPropertiesInfoKey);
    
    for (NSDictionary *info in modelInfo)
    {
        if ([info[@"setter"]isEqualToString:selectorString])
        {
            class_addMethod([self class], sel, (IMP)modelObjectSetterIMP, "v@:@");
            return YES;
        }
        else if ([info[@"getter"] isEqualToString:selectorString])
        {
            class_addMethod([self class], sel, (IMP)modelObjectGetterIMP, "@@:");
        }
    }
    return [super resolveInstanceMethod:sel];
}

void modelObjectSetterIMP(id self, SEL _cmd,id<EJDBDocument>model)
{
    NSLog(@"collection name for class is %@",[model collectionName]);
    NSLog(@"set my model object self is %@ _cmd is %@",self,NSStringFromSelector(_cmd));
}

id<EJDBDocument> modelObjectGetterIMP(id self, SEL _cmd)
{
    return nil;
}
*/

- (void)parseProperties
{
    NSMutableDictionary *propertyGetters = [NSMutableDictionary dictionary];
    NSMutableDictionary *propertySetters = [NSMutableDictionary dictionary];
    NSMutableDictionary *propertyTypes = [NSMutableDictionary dictionary];
    NSMutableDictionary *modelInfo = [NSMutableDictionary dictionary];
    Class klass = [self class];
    while (klass != [NSObject class])
    {
        unsigned int outCount,i;
        objc_property_t *properties = class_copyPropertyList(klass, &outCount);
        for (i = 0;i < outCount;i++)
        {
            objc_property_t property = properties[i];
            char *dynamic = property_copyAttributeValue(property, "D");
            if (dynamic)
            {
                free(dynamic);
                NSString *propertyName = [NSString stringWithUTF8String:property_getName(property)];
                
                if ([self checkIfReadOnlyProperty:property])
                {
                    free(properties);
                    @throw [NSException exceptionWithName:@"EJDBKitUnsupportedDynamicPropertyAttribute!"
                                                   reason:[NSString stringWithFormat:@"The property: %@ contains a readonly attribute!",propertyName]
                                                 userInfo:nil];
                    return;
                }
                
                /*
                Class ejdbModelClass = [self classForEJDBModelProperty:property];
                if (ejdbModelClass)
                {
                    [self loadModelGetterAndSetterForClass:ejdbModelClass withPropertyName:propertyName intoDictionary:modelInfo];
                    continue;
                }
                */
                
                if (![self loadPropertyTypeFromProperty:property withName:propertyName intoDictionary:propertyTypes])
                {
                    free(properties);
                    @throw [NSException exceptionWithName:@"EJDBKitUnsupportedDynamicPropertyType!"
                                                   reason:[NSString stringWithFormat:@"The property: %@ is an unsupported type!",propertyName]
                                                 userInfo:nil];
                    return;
                }
                [self loadGetterFromProperty:property withName:propertyName intoDictionary:propertyGetters];
                [self loadSetterFromProperty:property withName:propertyName intoDictionary:propertySetters];
            }
        }
        free(properties);
        klass = [klass superclass];
    }
    _propertyGetters = propertyGetters;
    _propertySetters = propertySetters;
    _propertyTypes = propertyTypes;
    _modelInfo = modelInfo;
    _values = [[NSMutableDictionary alloc] init];
    //objc_setAssociatedObject([self class], &EJDBModelPropertiesInfoKey, _modelInfo, OBJC_ASSOCIATION_ASSIGN);
}

- (BOOL)checkIfReadOnlyProperty:(objc_property_t)property
{
    BOOL isReadOnly = NO;
    char *readonly = property_copyAttributeValue(property, "R");
    if (readonly)
    {
        free(readonly);
        isReadOnly = YES;
    }
    return isReadOnly;
}

- (Class)classForEJDBModelProperty:(objc_property_t)property
{
    Class ejdbModelClass = nil;
    char *type = property_copyAttributeValue(property, "T");
    if (type)
    {
        NSString *typeString = [NSString stringWithUTF8String:type];
        if ([typeString hasPrefix:@"@"])
        {
            NSString *classString = [typeString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@\""]];
            Class klass = NSClassFromString(classString);
            if ([klass isSubclassOfClass:[EJDBModel class]]) ejdbModelClass = klass;
        }
        free(type);
    }
    return ejdbModelClass;
}

- (BOOL)loadPropertyTypeFromProperty:(objc_property_t)property withName:(NSString *)propertyName intoDictionary:(NSMutableDictionary *)dictionary
{
    BOOL isSupportedType = YES;
    char *type = property_copyAttributeValue(property, "T");
    if (type)
    {
        NSString *typeString = [NSString stringWithUTF8String:type];
        if (![typeString hasPrefix:@"@"])
        {
            if (![typeString isEqualToString:@"i"] && ![typeString isEqualToString:@"q"] &&
                ![typeString isEqualToString:@"B"] && ![typeString isEqualToString:@"f"] &&
                ![typeString isEqualToString:@"d"])
            {
                isSupportedType = NO;
            }
        }
        else
        {
            NSString *classString = [typeString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@\""]];
            Class klass =  NSClassFromString(classString);
            if (![klass isSubclassOfClass:[NSString class]] && ![klass isSubclassOfClass:[NSNumber class]] &&
                ![klass isSubclassOfClass:[NSDate class]] && ![klass isSubclassOfClass:[NSDictionary class]] &&
                ![klass isSubclassOfClass:[NSArray class]] && ![klass isSubclassOfClass:[NSData class]] && ![klass isSubclassOfClass:[EJDBModel class]])
            {
                isSupportedType = NO;
            }
        }
        if (isSupportedType)
        {
            [dictionary setObject:typeString forKey:propertyName];
        }
        free(type);
    }
    return isSupportedType;
}

- (void)loadModelGetterAndSetterForClass:(Class)modelClass withPropertyName:(NSString *)propertyName intoDictionary:(NSMutableDictionary *)dictionary
{
    NSString *aGetSelector = [propertyName stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                   withString:[[propertyName substringToIndex:1] uppercaseString]];
    aGetSelector = [NSString stringWithFormat:@"get%@:",aGetSelector];
    
    NSString *aSetSelector = [propertyName stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                               withString:[[propertyName substringToIndex:1] uppercaseString]];
    aSetSelector = [NSString stringWithFormat:@"set%@:",aSetSelector];
    NSDictionary *modelInfo = @{@"getter" : aGetSelector,@"setter":aSetSelector,@"className": modelClass};
    [dictionary setObject:propertyName forKey:modelInfo];
}


- (void)loadGetterFromProperty:(objc_property_t)property withName:(NSString *)propertyName intoDictionary:(NSMutableDictionary *)dictionary
{
    char *getterName = property_copyAttributeValue(property, "G");
    if (getterName)
    {
        [dictionary setObject:propertyName forKey:[NSString stringWithUTF8String:getterName]];
        free(getterName);
    }
    else
    {
        [dictionary setObject:propertyName forKey:propertyName];
    }

}

- (void)loadSetterFromProperty:(objc_property_t)property withName:(NSString *)propertyName intoDictionary:(NSMutableDictionary *)dictionary
{
    char *setterName = property_copyAttributeValue(property, "S");
    if (setterName)
    {
        [dictionary setObject:propertyName forKey:[NSString stringWithUTF8String:setterName]];
        free(setterName);
    }
    else
    {
        NSString *selector = [propertyName stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                   withString:[[propertyName substringToIndex:1] uppercaseString]];
        selector = [NSString stringWithFormat:@"set%@:",selector];
        [dictionary setObject:propertyName forKey:selector];
    }

}

- (id)dynamicValueForKey:(NSString *)key
{
    return [self.values objectForKey:key];
}

- (void)setDynamicValue:(id)value forKey:(NSString *)key
{
    if (value == nil) {
        [self.values setObject:[NSNull null] forKey:key];
    } else {
        [self.values setObject:value forKey:key];
    }
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    NSString *selectorAsString = NSStringFromSelector(aSelector);
    NSString *propertyName = nil;
    
    // Getter
    propertyName = [self.propertyGetters objectForKey:selectorAsString];
    if (propertyName)
    {
        NSString *propertyType = [self.propertyTypes objectForKey:propertyName];
        return [NSMethodSignature signatureWithObjCTypes:
                [[NSString stringWithFormat:@"%@@:", propertyType] UTF8String]];
    }
    
    // Setter
    propertyName = [self.propertySetters objectForKey:selectorAsString];
    if (propertyName)
    {
        NSString *propertyType = [self.propertyTypes objectForKey:propertyName];
        return [NSMethodSignature signatureWithObjCTypes:
                [[NSString stringWithFormat:@"v@:%@", propertyType] UTF8String]];
    }
    
    return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSString *selectorAsString = NSStringFromSelector([anInvocation selector]);
    NSString *propertyName = nil;
    
    // Getter
    propertyName = [self.propertyGetters objectForKey:selectorAsString];
    if (propertyName)
    {
        NSString *propertyType = [self.propertyTypes objectForKey:propertyName];
        
        if (![propertyType hasPrefix:@"@"])
        {
            [self fetchPrimitiveValueForPropertyName:propertyName invocation:anInvocation];
            return;
        }
        else
        {
            id value = [self dynamicValueForKey:propertyName];
            if (value == nil) value = [NSNull null];
            [anInvocation setReturnValue:&value];
            [anInvocation retainArguments];
            return;
        }
    }
    
    // Setter
    propertyName = [self.propertySetters objectForKey:selectorAsString];
    if (propertyName)
    {
        NSString *propertyType = [self.propertyTypes objectForKey:propertyName];
        
        if (![propertyType hasPrefix:@"@"])
        {
            [self savePrimitiveValueForPropertyName:propertyName invocation:anInvocation];
            return;
        }
        else
        {
            __unsafe_unretained id value = nil;
            [anInvocation getArgument:&value atIndex:2];
            [self setDynamicValue:value forKey:propertyName];
            return;
        }
    }
    [super forwardInvocation:anInvocation];
}

- (void)fetchPrimitiveValueForPropertyName:(NSString *)propertyName invocation:(NSInvocation *)anInvocation
{
    NSNumber *aNumber = [self dynamicValueForKey:propertyName];
    NSString *propertyType = [self.propertyTypes objectForKey:propertyName];
    
    if ([propertyType isEqualToString:@"i"])
    {
        int value = [aNumber intValue];
        [anInvocation setReturnValue:&value];
    }
    else if ([propertyType isEqualToString:@"q"])
    {
        long long value = [aNumber longLongValue];
        [anInvocation setReturnValue:&value];
    }
    else if ([propertyType isEqualToString:@"B"])
    {
        bool value = [aNumber boolValue];
        [anInvocation setReturnValue:&value];
    }
    else if ([propertyType isEqualToString:@"f"])
    {
        float value = [aNumber floatValue];
        [anInvocation setReturnValue:&value];
    }
    else if ([propertyType isEqualToString:@"d"])
    {
        double value = [aNumber doubleValue];
        [anInvocation setReturnValue:&value];
    }
}

- (void)savePrimitiveValueForPropertyName:(NSString *)propertyName invocation:(NSInvocation *)anInvocation
{
    NSString *propertyType = [self.propertyTypes objectForKey:propertyName];
    
    if ([propertyType isEqualToString:@"i"])
    {
        int value;
        [anInvocation getArgument:&value atIndex:2];
        [self setDynamicValue:[NSNumber numberWithInt:value] forKey:propertyName];
    }
    else if ([propertyType isEqualToString:@"q"])
    {
        long long value;
        [anInvocation getArgument:&value atIndex:2];
        [self setDynamicValue:[NSNumber numberWithLongLong:value] forKey:propertyName];
    }
    else if ([propertyType isEqualToString:@"B"])
    {
        bool value;
        [anInvocation getArgument:&value atIndex:2];
        [self setDynamicValue:[NSNumber numberWithBool:value] forKey:propertyName];
    }
    else if ([propertyType isEqualToString:@"f"])
    {
        float value;
        [anInvocation getArgument:&value atIndex:2];
        [self setDynamicValue:[NSNumber numberWithFloat:value] forKey:propertyName];
    }
    else if ([propertyType isEqualToString:@"d"])
    {
        double value;
        [anInvocation getArgument:&value atIndex:2];
        [self setDynamicValue:[NSNumber numberWithDouble:value] forKey:propertyName];
    }
}

- (void)setValue:(id)value forKey:(NSString *)key
{
    [self setDynamicValue:value forKey:key];
}

- (id)valueForKey:(NSString *)key
{
    return [self dynamicValueForKey:key];
}

#pragma mark - BSONArchiving delegate methods

- (NSString *)type
{
    return NSStringFromClass([self class]);
}

- (NSString *)oidPropertyName
{
    return @"oid";
}

- (NSDictionary *)toDictionary
{
    NSMutableDictionary *propertyKeysAndValues = [NSMutableDictionary dictionary];
    for (NSString *key in [_propertyGetters keyEnumerator])
    {
        NSMethodSignature *signature = [self methodSignatureForSelector:NSSelectorFromString(_propertyGetters[key])];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:NSSelectorFromString(_propertyGetters[key])];
        [self forwardInvocation:invocation];
        propertyKeysAndValues[key] = [self dynamicValueForKey:key] == nil ? [NSNull null] : self.values[key];
    }
    propertyKeysAndValues[@"type"] = [self type];
    return [NSDictionary dictionaryWithDictionary:propertyKeysAndValues];
}

- (void)fromDictionary:(NSDictionary *)dictionary
{
    for (NSString  *key in [dictionary keyEnumerator])
    {
        NSArray *keys = [_propertySetters allKeysForObject:key];
        if ([keys count] > 0)
        {
            if ([[dictionary valueForKey:key] isEqual:[NSNull null]]) continue;
            NSMethodSignature *signature = [self methodSignatureForSelector:NSSelectorFromString(keys[0])];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setSelector:NSSelectorFromString(keys[0])];
            NSString *type = _propertyTypes[key];
            if (![type hasPrefix:@"@"])
            {
                if ([type isEqualToString:@"i"])
                {
                    int value = [[dictionary valueForKey:key] intValue];
                    [invocation setArgument:&value atIndex:2];
                }
                else if ([type isEqualToString:@"q"])
                {
                    long long value = [[dictionary valueForKey:key] longLongValue];
                    [invocation setArgument:&value atIndex:2];
                }
                else if([type isEqualToString:@"B"])
                {
                    bool value = [[dictionary valueForKey:key]boolValue];
                    [invocation setArgument:&value atIndex:2];
                }
                else if([type isEqualToString:@"f"])
                {
                    float value = [[dictionary valueForKey:key]floatValue];
                    [invocation setArgument:&value atIndex:2];
                }
                else if([type isEqualToString:@"d"])
                {
                    double value = [[dictionary valueForKey:key]doubleValue];
                    [invocation setArgument:&value atIndex:2];
                }
            }
            else
            {
                __unsafe_unretained id value = [dictionary valueForKey:key];
                [invocation setArgument:&value atIndex:2];
            }
            [self forwardInvocation:invocation];
        }
    }
    _oid = dictionary[@"oid"];
}

@end