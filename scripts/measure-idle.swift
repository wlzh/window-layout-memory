import Foundation
import Darwin

guard (3...4).contains(CommandLine.arguments.count),let pid=Int32(CommandLine.arguments[1]),pid > 0,
      let seconds=Double(CommandLine.arguments[2]),seconds.isFinite,seconds >= 10,seconds <= 28800,
      let interval=Double(CommandLine.arguments.count == 4 ? CommandLine.arguments[3]:"10"),
      interval.isFinite,interval >= 1,interval <= seconds else {
    fputs("Usage: swift scripts/measure-idle.swift PID SECONDS (10...28800) [INTERVAL (1...SECONDS)]\n",stderr);exit(2)
}
func sample() throws -> rusage_info_v4 {
    var info=rusage_info_v4()
    let result=withUnsafeMutablePointer(to:&info) { pointer in
        pointer.withMemoryRebound(to:rusage_info_t?.self,capacity:1) { proc_pid_rusage(pid,RUSAGE_INFO_V4,$0) }
    }
    guard result==0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
    return info
}
let first=try sample(),start=ProcessInfo.processInfo.systemUptime
print("Measuring PID \(pid) for \(seconds)s. Keep workload stable; any permission/mode change invalidates comparison.")
func memoryRow(_ info:rusage_info_v4,_ elapsed:Double) -> [String:Double] {
    ["elapsedSeconds":elapsed,"physicalFootprintMiB":Double(info.ri_phys_footprint)/1048576,
     "residentMiB":Double(info.ri_resident_size)/1048576]
}
var last=first,rows=[memoryRow(first,0)],elapsed=0.0
while elapsed < seconds {
    Thread.sleep(forTimeInterval:min(interval,seconds-elapsed))
    last=try sample();elapsed=ProcessInfo.processInfo.systemUptime-start
    guard last.ri_proc_start_abstime == first.ri_proc_start_abstime else { fatalError("PID reused; discard measurement") }
    rows.append(memoryRow(last,elapsed))
}
let cpu=Double(last.ri_user_time+last.ri_system_time-first.ri_user_time-first.ri_system_time)/1e9/elapsed*100
let report:[String:Any] = ["elapsedSeconds":elapsed,"cpuPercentOneCore":cpu,
    "cpuSecondsSinceProcessStart":Double(last.ri_user_time+last.ri_system_time)/1e9,
    "physicalFootprintMiB":Double(last.ri_phys_footprint)/1048576,
    "physicalFootprintChangeMiB":(Double(last.ri_phys_footprint)-Double(first.ri_phys_footprint))/1048576,
    "sampledPeakFootprintMiB":rows.compactMap {$0["physicalFootprintMiB"]}.max() ?? 0,
    "lifetimePeakFootprintMiB":Double(last.ri_lifetime_max_phys_footprint)/1048576,
    "residentMiB":Double(last.ri_resident_size)/1048576,
    "diskReadBytes":last.ri_diskio_bytesread-first.ri_diskio_bytesread,
    "diskWrittenBytes":last.ri_diskio_byteswritten-first.ri_diskio_byteswritten,
    "logicalWrittenBytes":last.ri_logical_writes-first.ri_logical_writes,
    "interruptWakeupsPerSecond":Double(last.ri_interrupt_wkups-first.ri_interrupt_wkups)/elapsed,
    "packageIdleWakeupsPerSecond":Double(last.ri_pkg_idle_wkups-first.ri_pkg_idle_wkups)/elapsed,
    "memorySamples":rows,
    "note":"Energy in watts/Wh is NOT measured. Sampled memory peaks can miss spikes. Record permission, mode and workload separately; transitions invalidate a steady-state comparison."]
print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
