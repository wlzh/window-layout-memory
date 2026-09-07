import Foundation
import Darwin

guard CommandLine.arguments.count == 3,let pid=Int32(CommandLine.arguments[1]),
      let seconds=Double(CommandLine.arguments[2]),seconds >= 10,seconds <= 28800 else {
    fputs("Usage: swift scripts/measure-idle.swift PID SECONDS (10...28800)\n",stderr);exit(2)
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
Thread.sleep(forTimeInterval:seconds)
let last=try sample(),elapsed=ProcessInfo.processInfo.systemUptime-start
guard last.ri_proc_start_abstime == first.ri_proc_start_abstime else { fatalError("PID reused") }
let cpu=Double(last.ri_user_time+last.ri_system_time-first.ri_user_time-first.ri_system_time)/1e9/elapsed*100
let report:[String:Any] = ["elapsedSeconds":elapsed,"cpuPercentOneCore":cpu,
    "physicalFootprintMiB":Double(last.ri_phys_footprint)/1048576,
    "residentMiB":Double(last.ri_resident_size)/1048576,
    "interruptWakeupsPerSecond":Double(last.ri_interrupt_wkups-first.ri_interrupt_wkups)/elapsed,
    "packageIdleWakeupsPerSecond":Double(last.ri_pkg_idle_wkups-first.ri_pkg_idle_wkups)/elapsed,
    "note":"Not a full performance gate without recorded permission, mode and representative window workload."]
print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
