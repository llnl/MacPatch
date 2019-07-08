//
//  CollectionItem.m
//  TestViews
//
//  Created by Heizer, Charles on 12/12/12.
//  Copyright (c) 2012 LLNL. All rights reserved.
//

#import "CollectionItem.h"
#import "HistoryItem.h"
#import "SWInstallItem.h"

//#import "ASIHTTPRequest.h"
//#import "ASIDownloadCache.h"

@interface HumanReadableDataSizeHelper : NSObject

/**
 @brief  Produces a string containing the largest appropriate units and the new fractional value.
 @param  sizeInBytes  The value to convert in bytes.
 
 This function converts the bytes value to a value in the greatest units that produces a value >= 1 and returns the new value and units as a string.
 
 The magnitude multiplier used is 1024 and the prefixes used are the binary prefixes (ki, Mi, ...).
 */
+ (NSString *)humanReadableSizeFromBytes:(NSNumber *)sizeInBytes;

/**
 @brief  Produces a string containing the largest appropriate units and the new fractional value.
 @param  sizeInBytes  The value to convert in bytes.
 @param  useSiPrefixes  Controls what prefix-set is used.
 @param  useSiMultiplier  Controls what magnitude multiplier is used.
 
 This function converts the bytes value to a value in the greatest units that produces a value >= 1 and returns the new value and units as a string.
 
 When useSiPrefixes is true, the prefixes used are the SI unit prefixes (k, M, ...).
 When useSiPrefixes is false, the prefixes used are the binary prefixes (ki, Mi, ...).
 
 When useSiMultiplier is true, the magnitude multiplier used is 1000
 When useSiMultiplier is false, the magnitude multiplier used is 1024.
 */
+ (NSString *)humanReadableSizeFromBytes:(NSNumber *)sizeInBytes  useSiPrefixes:(BOOL)useSiPrefixes  useSiMultiplier:(BOOL)useSiMultiplier;

@end

@implementation HumanReadableDataSizeHelper

+ (NSString *)humanReadableSizeFromBytes:(NSNumber *)sizeInBytes
{
    return [self humanReadableSizeFromBytes:sizeInBytes  useSiPrefixes:NO  useSiMultiplier:NO];
}

+ (NSString *)humanReadableSizeFromBytes:(NSNumber *)sizeInBytes  useSiPrefixes:(BOOL)useSiPrefixes  useSiMultiplier:(BOOL)useSiMultiplier
{
    NSString *unitSymbol = @"B";
    NSInteger multiplier;
    NSArray *prefixes;
    
    if (useSiPrefixes)
    {
        /*  SI prefixes
         http://en.wikipedia.org/wiki/Kilo-
         kilobyte   (kB)    10^3
         megabyte   (MB)    10^6
         gigabyte   (GB)    10^9
         terabyte   (TB)    10^12
         petabyte   (PB)    10^15
         exabyte    (EB)    10^18
         zettabyte  (ZB)    10^21
         yottabyte  (YB)    10^24
         */
        
        prefixes = [NSArray arrayWithObjects: @"", @"k", @"M", @"G", @"T", @"P", @"E", @"Z", @"Y", nil];
    }
    else
    {
        /*  Binary prefixes
         http://en.wikipedia.org/wiki/Binary_prefix
         kibibyte   (KiB)   2^10 = 1.024 × 10^3
         mebibyte   (MiB)   2^20 ≈ 1.049 × 10^6
         gibibyte   (GiB)   2^30 ≈ 1.074 × 10^9
         tebibyte   (TiB)   2^40 ≈ 1.100 × 10^12
         pebibyte   (PiB)   2^50 ≈ 1.126 × 10^15
         exbibyte   (EiB)   2^60 ≈ 1.153 × 10^18
         zebibyte   (ZiB)   2^70 ≈ 1.181 × 10^21
         yobibyte   (YiB)   2^80 ≈ 1.209 × 10^24
         */
        
        prefixes = [NSArray arrayWithObjects: @"", @"ki", @"Mi", @"Gi", @"Ti", @"Pi", @"Ei", @"Zi", @"Yi", nil];
    }
    
    if (useSiMultiplier)
    {
        multiplier = 1000;
    }
    else
    {
        multiplier = 1024;
    }
    
    NSInteger exponent = 0;
    double size = ([sizeInBytes doubleValue] * 1024);
    
    while ( (size >= multiplier) && (exponent < [prefixes count]) )
    {
        size /= multiplier;
        exponent++;
    }
    
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    [formatter setMaximumFractionDigits:2];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle]; // Uses localized number formats.
    
    NSString *sizeInUnits = [formatter stringFromNumber:[NSNumber numberWithDouble:size]];
    
    return [NSString stringWithFormat:@"%@ %@%@", sizeInUnits, [prefixes objectAtIndex:exponent], unitSymbol];
}
@end

@interface CollectionItem ()

- (void)prepProgressBarForDownload;

@end

@implementation CollectionItem


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}


-(id)copyWithZone:(NSZone *)zone
{
	id result = [super copyWithZone:zone];
    [[NSBundle mainBundle] loadNibNamed:@"CollectionItem" owner:result topLevelObjects:nil];
	//[NSBundle loadNibNamed:@"CollectionItem" owner:result];
	return result;
}

- (void)setRepresentedObject:(id)object
{
	[super setRepresentedObject: object];
	
	if (object == nil)
		return;
	
	NSDictionary *data = (NSDictionary *)[self representedObject];
    _rowData = data;
    _swTitle.stringValue = [data valueForKeyPath:@"Software.name"];
    _swCompany.stringValue = [data valueForKeyPath:@"Software.vendor"];
    _swDescription.stringValue = [data valueForKeyPath:@"Software.description"];
    _swVersion.stringValue = [NSString stringWithFormat:@"Version %@",[data valueForKeyPath:@"Software.version"]];
    _swSize.stringValue = [NSString stringWithFormat:@"%@",[HumanReadableDataSizeHelper humanReadableSizeFromBytes:[NSNumber numberWithInt:(int)[[data valueForKeyPath:@"Software.sw_size"] integerValue]] useSiPrefixes:YES  useSiMultiplier:YES ]];
    if ([[data valueForKeyPath:@"sw_task_type"] isEqualToString:@"o"]) {
        [_swInstallBy setHidden:YES];
    } else {
        _swInstallBy.stringValue = [NSString stringWithFormat:@"Install By %@",[data valueForKeyPath:@"sw_start_datetime"]];
    }
    if ([[data valueForKeyPath:@"Software.reboot"] isEqualTo:@"1"]) {
        _rebootImage.image = [NSImage imageNamed:@"RebootImage"];
    } else {
        _rebootImage.image = [NSImage imageNamed:@"emptyIcon.tif"];
        _swReootTextFlag.stringValue = @"";
    }
    if ([[data objectForKey:@"installed"] intValue] == 1) {
        [self.actionButton setTitle:@"Uninstall"];
        _rebootImage.image = [NSImage imageNamed:@"GoodImage"];
    }
    if ([data objectForKey:@"mpEnable"]){
        if ([[data objectForKey:@"mpEnable"] intValue] == 1) {
            [self.actionButton setEnabled:NO];
        } else {
            [self.actionButton setEnabled:YES];
        }
    }
}

- (void) awakeFromNib
{
    
}

- (IBAction)runInstall:(id)sender
{
    if (![sender isKindOfClass:[NSButton class]])
        return;
    /*
    id collectionViewItem = [sender superview];
    NSInteger index = [[NSCollectionView subviews]  indexOfObject:collectionViewItem];
    NSLog(@"%@",index);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TestNotification" object:self];
    */
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TestNotification" object:self];
    NSString *title = [(NSButton *)sender title];
    if ([title isEqualToString:@"Install"])
    {
        [self performSelectorInBackground:@selector(installSoftware) withObject:nil];
    }
    else
    {
        [self performSelectorInBackground:@selector(uninstallSoftware) withObject:nil];
    }
    
    //NSLog(@"%@",_rowData);
}

- (void)installSoftware
{
    [_progressBar setHidden:NO];
    [_progressBar startAnimation:nil];
    [_swActionStatusText setHidden:NO];
    _swActionStatusText.stringValue = @"Starting install...";
    [_swActionStatusText display];
    
    [self.actionButton setStringValue:@"Installing"];
    [self.actionButton setEnabled:NO];
    
    DBLocal *db = [DBLocal sharedInstance];
    HistoryItem *hi = [[HistoryItem alloc] init];
    
    [NSThread sleepForTimeInterval:5.0];
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_rowData
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];
    
    if (!jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        hi.action = 0;
        hi.type = @"Software";
        hi.name = [_rowData objectForKey:@"name"];
        hi.errorcode = 0;
        hi.rawdata = jsonString;
        [db recordAction:hi];
    }
    [self recordSWInstall:_rowData];
    [self.actionButton setTitle:@"Uninstall"];
    _rebootImage.image = [NSImage imageNamed:@"GoodImage"];
    [self progressBarCompleted];
    [self.actionButton setEnabled:YES];
}

- (void)uninstallSoftware
{
    DBLocal *db = [DBLocal sharedInstance];
    HistoryItem *hi = [[HistoryItem alloc] init];
    [db softwareItemIsUnInstalled:[_rowData objectForKey:@"id"]];
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_rowData options:NSJSONWritingPrettyPrinted error:&error];
    
    if (!jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        hi.action = 1;
        hi.type = @"Software";
        hi.name = [_rowData objectForKey:@"name"];
        hi.errorcode = 0;
        hi.rawdata = jsonString;
        [db recordAction:hi];
    }
    
    [self.actionButton setTitle:@"Install"];
    _rebootImage.image = [NSImage imageNamed:@"Empty"];
}

- (void)prepProgressBarForDownload
{
    _swActionStatusText.stringValue = @"Preparing to download...";
    [_progressBar setIndeterminate:NO];
    [_progressBar setMaxValue:100];
    [_progressBar setDoubleValue:0.0];
    maxValLong = 0;
    curValLong = 0;
    [_progressBar display];
}

- (void)prepProgressBarForInstall
{
    _swActionStatusText.stringValue = @"Preparing to install...";
    [_progressBar setIndeterminate:NO];
    [_progressBar setMaxValue:100];
    [_progressBar setDoubleValue:0.0];
    maxValLong = 0;
    curValLong = 0;
    [_progressBar display];
}

- (void)progressBarCompleted
{
    _swActionStatusText.stringValue = @" ";
    [_progressBar setIndeterminate:YES];
    [_progressBar setHidden:YES];
    [_progressBar display];
}

- (void)recordSWInstall:(NSDictionary *)data
{
    DBLocal *db = [DBLocal sharedInstance];
    SWInstallItem *s = [[SWInstallItem alloc] init];
    s.swuuid = [data objectForKey:@"id"];
    s.name = [data objectForKey:@"name"];
    if ([[[data objectForKey:@"Software"] objectForKey:@"sw_uninstall"] length] > 1) {
        s.hasUninstall = 1;
    } else {
        s.hasUninstall = 0;
    }
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    s.jsonData = jsonString;
    [db recordSoftwareInstall:s];
}

/*
- (void)request:(ASIHTTPRequest *)request incrementDownloadSizeBy:(long long)newLength
{
	[self request:request didReceiveBytes:0];
	maxValLong = newLength;
}

- (void)request:(ASIHTTPRequest *)request didReceiveBytes:(long long)bytes;
{
	curValLong = (curValLong + bytes);
	if (curValLong != 0)
    {
        _swActionStatusText.stringValue = [NSString stringWithFormat:@"Downloading ... %.0f%%",((double)curValLong / (double)maxValLong) * 100];
        [_progressBar setDoubleValue:[[NSString stringWithFormat:@"%.0f%",((double)curValLong / (double)maxValLong) * 100] doubleValue]];
        [_progressBar display];
	}
}
*/
@end
