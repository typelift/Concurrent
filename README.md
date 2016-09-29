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
let chan = Chan<Int>()

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

`MVar`s can also be used purely as a synchronization point between multiple threads:

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

Concurrent also exposes a structure for [Software Transactional
Memory](https://en.wikipedia.org/wiki/Software_transactional_memory) for
safe and structured access to shared memory:

```swift
typealias Account = TVar<UInt>

/// Some atomic operations
func withdraw(from account : Account, amount : UInt) -> STM<()> { 
    return account.read().flatMap { balance in
        if balance > amount {
            return account.write(balance - amount)
        }
        return STM<()>.pure(())
    } 
}
func deposit(into account : Account, amount : UInt) -> STM<()> { 
    return account.read().flatMap { balance in
        return account.write(balance + amount)
    }
}

func transfer(from : Account, to : Account, amount : UInt) -> STM<()> { 
    return from.read().flatMap { fromBalance in
        if fromBalance > amount {
            return withdraw(from: from, amount: amount)
                .then(deposit(into: to, amount: amount))
        }
        return STM<()>.pure(())
    }
}

/// Here are some bank accounts represented as TVars - transactional memory
/// variables.
let alice = Account(200)
let bob = Account(100)

/// All account activity that will be applied in one contiguous transaction.
/// Either all of the effects of this transaction apply to the accounts or
/// everything is completely rolled back and it was as if nothing ever happened.
let finalStatement = 
    transfer(from: alice, to: bob, 100)
        .then(transfer(from: bob, to: alice, 20))
        .then(deposit(into: bob, amount: 1000))
        .then(transfer(from: bob, to: alice, amount: 500))
        .atomically()
```

System Requirements
===================

Concurrent supports OS X 10.9+ and iOS 7.0+.

Installation
=====

#### Swift Package Manager

- Add SwiftCheck to your `Package.swift` file's dependencies section:

```
.Package(url: "https://github.com/typelift/Concurrent.git", versions: Version(0,4,0)..<Version(1,0,0))
```

#### Carthage
Create a `Cartfile` that lists the framework and run `carthage bootstrap`. Follow the [instructions](https://github.com/Carthage/Carthage#if-youre-building-for-ios) to add `$(SRCROOT)/Carthage/Build/iOS/Concurrent.framework` to an iOS project.

```
github "typelift/Concurrent"
```

#### Manually
1. Download and drop `/Sources` folder in your project.  
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

