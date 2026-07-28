import Foundation

enum BuildVariant {
#if LIFTOFF_DEV
    static let portOffset: UInt16 = 100
    static let settingsDirectoryName = ".liftoff-dev"
    static let keychainService = "com.shostkevych.liftoff.dev"
#else
    static let portOffset: UInt16 = 0
    static let settingsDirectoryName = ".liftoff"
    static let keychainService = "com.shostkevych.liftoff"
#endif
}
