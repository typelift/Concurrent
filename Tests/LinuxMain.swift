import XCTest

@testable import ConcurrentTests

#if !os(macOS)
XCTMain([
  ChanSpec.allTests,
  IVarSpec.allTests,
  MVarSpec.allTests,
  QSemSpec.allTests,
  STMSpec.allTests,
  SVarSpec.allTests,
  TMVarSpec.allTests,
])
#endif
