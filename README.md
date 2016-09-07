 [![Build Status](https://travis-ci.org/typelift/Concurrent.svg?branch=master)](https://travis-ci.org/typelift/Concurrent)

Concurrent
==========

Concurrent is a collection of functional concurrency primitives inspired by
[Concurrent ML](http://cml.cs.uchicago.edu/) and [Concurrent
Haskell](http://hackage.haskell.org/package/base-4.7.0.2/docs/Control-Concurrent.html).
Traditional approaches to concurrency like locks, latches, and semaphores all
fall under the same category of basic resource protection.  While this affords
them a large measure of simplicity, their use is entirely ad-hoc, and failing to
properly lock or unlock critical sections can lead a program to beachball or
worse.  In addition, though we have become accustomed to performing work on
background threads, communication between these threads is frought with peril.  

The primitives in this library instead focus on *merging* data with protection,
choosing to abstract away the use of locks entirely.  By approaching concurrency
from the data side, rather than the code side, thread-safety, synchronization,
and protection become inherent in types rather than in code.

Take this simple example:

```swift
import struct Concurrent.Chan

/// A Channel is an unbounded FIFO stream of values with special semantics
/// for reads and writes.
let chan : Chan<Int> = Chan()

/// All writes to the Channel always succeed.  The Channel now contains `1`.
chan.write(1) // happens immediately

/// Reads to non-empty Channels occur immediately.  The Channel is now empty.
let x1 = chan.read()

/// But if we read from an empty Channel the read blocks until we write to the Channel again.
let time = dispatch_time(DISPATCH_TIME_NOW, 1 * Double(NSEC_PER_SEC))
dispatch_after(time, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
	chan.write(2) // Causes the read to suceed and unblocks the reading thread.
})

let x2 = chan.read() // Blocks until the dispatch block is executed and the Channel becomes non-empty.
```

Unlike lock-based protection mechanisms, we can wrap mutable variables that must
be accessed concurrently in an MVar.

```swift
import class Concurrent.MVar

/// An MVar (Mutable Variable) is a thread-safe synchronizing variable that can be used for 
/// communication between threads.
/// 
/// This MVar is currently empty.  Any reads or writes to it will block until it becomes "full".
let counter : MVar<Int> = MVar()

/// Attempt to increment the counter from 3 different threads.  Because the counter is empty, 
/// all of these writes will block until a value is put into the MVar.
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
	counter.modify_(+1)
	println("Modifier #1")
})
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
	counter.modify_(+1)
	println("Modifier #2")
})
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
	counter.modify_(+1)
	println("Modifier #3")
})

/// All the writes will now proceed and unblock each thread in turn.  The order of writes
/// is determined by the order in which each thread called `modify(_ :)`.
counter.put(0)

// > "Modifier #1"
// > "Modifier #3"
// > "Modifier #2"

/// Empties the MVar.  If we just wanted the value without emptying it, we would use
/// `read()` instead.
///
/// Because our take occured after the put, all of the modifications we made before will
/// complete before we read the final value.
println(counter.take()) // 3
```

MVars can also be used purely as a synchronization point between multiple threads:

```swift
import class Concurrent.MVar

let pingvar : MVar<String> = MVar()
let pongvar : MVar<String> = MVar()
let done = MVar<()>() // The synchronization point

/// Puts a value into the now-empty ping variable then blocks waiting for the
/// pong variable to have a value put into it.  Once we have read the pong variable,
/// we unblock the done MVar, and in doing so, unblock the main thread.
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
	pingvar.put("ping")
	let contents = pongvar.take()
	done.put(())
}

/// Takes the contents of the ping variable then puts a value into the pong variable
/// to unblock the take we just performed.
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
	let contents = pingvar.take()
	pongvar.put("pong")
}
		
/// Blocks until all work has completed.
done.take()
```

Of course, what concurrency library would be complete without Futures:

```swift
/// X will be the number 4 at some point in the future.
let x : Future<Int> = forkFuture {
	usleep(1)
	return 4
} .then({ res in // attaches an effect to be run when the future completes.
	println(res)
})
		 
/// Reading the Future for the first time forces its evaluation.  Subsequent
/// read calls will return a memoized result rather than evaluate the whole
/// Future again.
let result = x.read()  // Result.Value(4)
```

System Requirements
===================

Concurrent supports OS X 10.9+ and iOS 7.0+.

Installation
=====

#### Carthage
Create a `Cartfile` that lists the framework and run `carthage bootstrap`. Follow the [instructions](https://github.com/Carthage/Carthage#if-youre-building-for-ios) to add `$(SRCROOT)/Carthage/Build/iOS/Concurrent.framework` to an iOS project.

```
github "typelift/Concurrent"
```

#### Manually
1. Download and drop ```/Sources``` folder in your project.  
2. Congratulations!  

#### Framework

- Drag Concurrent.xcodeproj or Concurrent-iOS.xcodeproj into your project tree as a subproject
- Under your project's Build Phases, expand Target Dependencies
- Click the + and add Concurrent
- Expand the Link Binary With Libraries phase
- Click the + and add Concurrent
- Click the + at the top left corner to add a Copy Files build phase
- Set the directory to Frameworks
- Click the + and add Concurrent

License
=======

Concurrent is released under the MIT license.

