import Darwin

/// Converts CoreMIDI host time stamps (mach_absolute_time units) to nanoseconds.
public enum HostTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func now() -> UInt64 {
        mach_absolute_time()
    }

    public static func nanoseconds(_ hostTime: UInt64) -> UInt64 {
        hostTime * UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}
