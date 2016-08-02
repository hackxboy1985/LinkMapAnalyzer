//
//  ViewController.m
//  WMLinkMapAnalyzer
//
//  Created by Mac on 16/1/5.
//  Copyright © 2016年 wmeng. All rights reserved.
//

#import "ViewController.h"
#import "symbolModel.h"

@interface ViewController()
@property (weak) IBOutlet NSTextField *fileTF;//显示选择的文件路径
@property (weak) IBOutlet NSTextField *filterTF;//过滤显示某模块的细节
@property (weak) IBOutlet NSProgressIndicator *INdicator;//指示器


@property (weak) IBOutlet NSScrollView *contentView;//分析的内容
@property (unsafe_unretained) IBOutlet NSTextView *contentTextView;

@property (nonatomic,strong)NSURL *ChooseLinkMapFileURL;
@property (nonatomic,strong)NSString *linkMapContent;

@property (nonatomic,strong)NSMutableString *result;//分析的结果


@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    self.INdicator.hidden = YES;
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)ChooseFile:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setResolvesAliases:NO];
    [panel setCanChooseFiles:YES];
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSURL*  theDoc = [[panel URLs] objectAtIndex:0];
            NSLog(@"%@", theDoc);
            _fileTF.stringValue = [theDoc path];
            self.ChooseLinkMapFileURL = theDoc;
        }
    }];

    
}
- (IBAction)StartAnalyzer:(id)sender {
    
    if (!_ChooseLinkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_ChooseLinkMapFileURL path] isDirectory:nil])
    {
        NSAlert *alert = [[NSAlert alloc]init];
        alert.messageText = @"没有找到该路径！";
        [alert addButtonWithTitle:@"是的"];
        [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
            
        }];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *content = [NSString stringWithContentsOfURL:_ChooseLinkMapFileURL encoding:NSMacOSRomanStringEncoding error:&error];
        
        
        
        NSRange objsFileTagRange = [content rangeOfString:@"# Object files:"];
        NSString *subObjsFileSymbolStr = [content substringFromIndex:objsFileTagRange.location + objsFileTagRange.length];
        NSRange symbolsRange = [subObjsFileSymbolStr rangeOfString:@"# Symbols:"];
        if ([content rangeOfString:@"# Path:"].length <= 0||objsFileTagRange.location == NSNotFound||symbolsRange.location == NSNotFound)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc]init];
                alert.messageText = @"文件格式不正确";
                [alert addButtonWithTitle:@"是的"];
                [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
                    
                }];
                
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.INdicator.hidden = NO;
            [self.INdicator startAnimation:self];
            
        });
        
        NSMutableDictionary <NSString *,symbolModel *>*sizeMap = [NSMutableDictionary new];
        // 符号文件列表
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        
        BOOL reachFiles = NO;
        BOOL reachSymbols = NO;
        BOOL reachSections = NO;
        
        for(NSString *line in lines)
        {
            if([line hasPrefix:@"#"])   //注释行
            {
                if([line hasPrefix:@"# Object files:"])
                    reachFiles = YES;
                else if ([line hasPrefix:@"# Sections:"])
                    reachSections = YES;
                else if ([line hasPrefix:@"# Symbols:"])
                    reachSymbols = YES;
            }
            else
            {
                if(reachFiles == YES && reachSections == NO && reachSymbols == NO)
                {
                    NSRange range = [line rangeOfString:@"]"];
                    if(range.location != NSNotFound)
                    {
                        symbolModel *symbol = [symbolModel new];
                        symbol.file = [line substringFromIndex:range.location+1];
                        NSString *key = [line substringToIndex:range.location+1];
                        sizeMap[key] = symbol;
                    }
                }
                else if (reachFiles == YES &&reachSections == YES && reachSymbols == NO)
                {
                }
                else if (reachFiles == YES && reachSections == YES && reachSymbols == YES)
                {
                    NSArray <NSString *>*symbolsArray = [line componentsSeparatedByString:@"\t"];
                    if(symbolsArray.count == 3)
                    {
                        //Address Size File Name
                        NSString *fileKeyAndName = symbolsArray[2];
                        NSUInteger size = strtoul([symbolsArray[1] UTF8String], nil, 16);
                        
                        NSRange range = [fileKeyAndName rangeOfString:@"]"];
                        if(range.location != NSNotFound)
                        {
                            NSString* key = [fileKeyAndName substringToIndex:range.location+1];
                            NSString* suffix = [fileKeyAndName substringFromIndex:range.location+1];
                            //NSString* className = [self getClassName:suffix];
                            
                            symbolModel *symbol = sizeMap[key];
                            if(symbol)
                            {
                                //NSLog(@"%@ %@ + %u",key, className, (uint)size);
                                symbol.size += size;
                            }
                        }
                    }
                }
            }
            
        }
        
        
        NSString* keyworkFramework = self.filterTF.stringValue;//@"Framework";//@".o"
        NSString* keyworkFrameworkName = keyworkFramework;//@"Framework";//@"主工程"
        
        NSArray <symbolModel *>*symbols = [sizeMap allValues];
        
        NSMutableArray* mainProjectClassAry = [NSMutableArray new];
        NSMutableDictionary* libDict = [NSMutableDictionary new];
        
        //默认为主工程
        if(keyworkFramework.length == 0 || [keyworkFramework isEqualToString:@"主工程"]){
            keyworkFramework = @".o";
            keyworkFrameworkName = @"主工程";
        }
        
        
        for(symbolModel *symbol in symbols)
        {
            NSString* suffix = [[symbol.file componentsSeparatedByString:@"/"] lastObject];
            
            if([keyworkFrameworkName isEqualToString:@"主工程"] == false){

                if([suffix containsString:keyworkFramework]){
                    [mainProjectClassAry addObject:symbol];
                }
            }
            
            
            NSRange range = [suffix rangeOfString:@"("];
            if(range.location != NSNotFound){
                suffix = [suffix substringToIndex:range.location];
            }else{
                //主工程的.o文件，属于主工程代码
                range = [suffix rangeOfString:@".o"];
                if(range.location != NSNotFound){
                    
                    if([keyworkFrameworkName isEqualToString:@"主工程"]){
                        [mainProjectClassAry addObject:symbol];
                    }
                    suffix = @"主工程";
                }
            }
            
            
            
            
            symbolModel *libModel = [libDict objectForKey:suffix];
            
            if (libModel == NULL) {
                libModel = [symbolModel new];
                libModel.file = suffix;
                [libDict setObject:libModel forKey:suffix];
            }
            
            libModel.size += symbol.size;
            if([suffix isEqualToString:keyworkFrameworkName])
                NSLog(@"lib: %@ : %@ + %u",suffix , [[symbol.file componentsSeparatedByString:@"/"] lastObject], (uint)symbol.size);
        }
        
        symbols = [libDict allValues];
        NSArray *sorted = [symbols sortedArrayUsingComparator:^NSComparisonResult(symbolModel *  _Nonnull obj1, symbolModel *  _Nonnull obj2) {
            if(obj1.size > obj2.size)
                return NSOrderedAscending;
            else if (obj1.size < obj2.size)
                return NSOrderedDescending;
            else
                return NSOrderedSame;
        }];
        
        if (self.result) {
            self.result = nil;
        }
        self.result = [@"各模块体积大小:\n" mutableCopy];
        NSUInteger totalSize = 0;
        
        
        for(symbolModel *symbol in sorted)
        {
            [_result appendFormat:@"%@\t%.5fM\n",[[symbol.file componentsSeparatedByString:@"/"] lastObject],(symbol.size/(1024.0*1024.0))];
            //NSLog(@"%@",_result);
            totalSize += symbol.size;
        }
        
        [_result appendFormat:@"总体积: %.2fM\n",(totalSize/(1024.0*1024.0))];

        
        
        
        
        
        //分析主工程当中每个类大小:
        sorted = [mainProjectClassAry sortedArrayUsingComparator:^NSComparisonResult(symbolModel *  _Nonnull obj1, symbolModel *  _Nonnull obj2) {
            if(obj1.size > obj2.size)
                return NSOrderedAscending;
            else if (obj1.size < obj2.size)
                return NSOrderedDescending;
            else
                return NSOrderedSame;
        }];

        
        [_result appendFormat:@"\n--------------------------------------------\n\n\n\n%@类文件统计(降序):\n",keyworkFrameworkName];

        
        
        for(symbolModel *symbol in sorted)
        {
            [_result appendFormat:@"%@\t%.5fM\n",[[symbol.file componentsSeparatedByString:@"/"] lastObject],(symbol.size/(1024.0*1024.0))];
        }
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.contentTextView.string = _result;
            self.INdicator.hidden = YES;
            [self.INdicator stopAnimation:self];
            
        });
    });
    
}

-(NSString*)getClassName:(NSString*)suffix{
    //class name
    NSRange range = [suffix rangeOfString:@"["];
    if(range.location != NSNotFound)
    {
        suffix = [suffix substringFromIndex:range.location+1];
        range = [suffix rangeOfString:@" "];
        if(range.location != NSNotFound)
        {
            suffix = [suffix substringToIndex:range.location+1];
        }
    }
    return suffix;
}

- (IBAction)inputFile:(id)sender {
    
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setResolvesAliases:NO];
    [panel setCanChooseFiles:NO];
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSURL*  theDoc = [[panel URLs] objectAtIndex:0];
            NSLog(@"%@", theDoc);
            NSMutableString *content =[[NSMutableString alloc]initWithCapacity:0];
            [content appendString:[theDoc path]];
            [content appendString:@"/linkMap.txt"];
            NSLog(@"content=%@",content);
            [_result writeToFile:content atomically:YES encoding:NSUTF8StringEncoding error:nil];

        }
    }];

    
    
}

@end
