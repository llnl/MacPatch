# Guide: Linking MPLibrary to MPAgentTests

## Current Status

The test file `MPAgentTests.m` currently has many tests commented out because they depend on `MPLibrary`. Once you link MPLibrary to your test target, you can uncomment these tests.

## How to Link MPLibrary to Your Test Target

### Method 1: Link Binary With Libraries (Recommended if MPLibrary is a static library)

1. **Select Your Test Target**
   - In Xcode, click on your project file in the navigator
   - Select the `MPAgentTests` target from the list

2. **Open Build Phases**
   - Click on the "Build Phases" tab
   - Expand "Link Binary With Libraries"

3. **Add MPLibrary**
   - Click the "+" button
   - Find and select `libMPLibrary.a` or `MPLibrary.framework`
   - Click "Add"

4. **Add Target Dependency**
   - In the same Build Phases tab
   - Expand "Target Dependencies"
   - Click the "+" button
   - Select `MPLibrary` from the list
   - Click "Add"

5. **Configure Header Search Paths**
   - Go to "Build Settings" tab
   - Search for "Header Search Paths"
   - Add the path to MPLibrary headers (usually something like):
     - `$(PROJECT_DIR)/MPLibrary` (non-recursive)
     - Or wherever your MPLibrary source files are located

### Method 2: Add Source Files to Test Target (Alternative)

If MPLibrary is just a collection of source files rather than a separate target:

1. **Add Required Files**
   - In Xcode's Project Navigator, find these files:
     - `Constants.h` and `Constants.m`
     - `MPSettings.h` and `MPSettings.m`
     - `MPSimpleKeychain.h` and `MPSimpleKeychain.m`
     - Any other MPLibrary files they depend on

2. **Update Target Membership**
   - Select each file
   - Open the File Inspector (right panel, ⌥⌘1)
   - Under "Target Membership", check the box for `MPAgentTests`

### Method 3: Create an Aggregate Target

If you want to keep things more organized:

1. Create a new aggregate target that includes MPLibrary
2. Have MPAgentTests depend on this aggregate target
3. Configure proper header and library search paths

## After Linking MPLibrary

Once MPLibrary is properly linked, you need to:

### 1. Update the Import Statement

In `MPAgentTests.m`, change:
```objective-c
#import <XCTest/XCTest.h>
#import "MPAgentRegister.h"
```

To:
```objective-c
#import <XCTest/XCTest.h>
#import "MPAgentRegister.h"
#import "Constants.h"
#import "MPSettings.h"
#import "MPSimpleKeychain.h"
```

### 2. Uncomment the Tests

Search for these comment blocks and uncomment them:

- **MPSettings Tests** (line ~80)
  - testMPSettingsSingletonPattern
  - testMPSettingsReadOnlyProperties
  - testMPSettingsOSVersionFormat
  - testMPSettingsSerialNumberNotEmpty
  - testMPSettingsClientUUIDFormat
  - testMPSettingsRefreshMethod

- **Constants Tests** (line ~150)
  - testConstantPathsAreDefined
  - testConstantPathsHaveCorrectPrefix
  - testWebServiceConstants
  - testPatchContentTypeEnum

- **File System Tests** (line ~195)
  - testMacPatchDirectoryStructure
  - testPlistFileExtensions

- **Integration Tests** (line ~230)
  - testConstantsIntegration

### 3. Update setUp Method

Add back the MPSettings property:
```objective-c
@property (nonatomic, strong) MPSettings *settings;
```

And in setUp:
```objective-c
- (void)setUp {
    [super setUp];
    self.fileManager = [NSFileManager defaultManager];
    self.settings = [MPSettings sharedInstance];
}
```

## Troubleshooting

### "File not found" errors
- Make sure Header Search Paths includes the MPLibrary directory
- Check that MPLibrary files are in the correct location

### Linker errors
- Verify that MPLibrary is in "Link Binary With Libraries"
- Check that all required .m files are compiled in Build Phases > Compile Sources

### Missing symbols
- Make sure all dependencies of MPLibrary are also linked
- Check for any missing frameworks (Foundation, Security, etc.)

## Test Coverage After Linking

Once MPLibrary is linked, you'll have:

- **MPAgentRegister Tests**: 4 tests ✓ (currently working)
- **MPSettings Tests**: 6 tests (commented out)
- **Constants Tests**: 4 tests (commented out)
- **File System Tests**: 2 tests (commented out)
- **Integration Tests**: 2 tests (commented out)
- **Performance Tests**: 2 tests ✓ (1 working, 1 commented)
- **Error Handling Tests**: 1 test ✓ (currently working)
- **Memory Management Tests**: 1 test ✓ (currently working)
- **String Validation Tests**: 2 tests ✓ (currently working)

**Total when fully enabled: 24 tests**

## Questions?

If you encounter issues:
1. Check that MPLibrary builds successfully on its own
2. Verify all file paths are correct
3. Make sure there are no circular dependencies
4. Check the build log for specific error messages
