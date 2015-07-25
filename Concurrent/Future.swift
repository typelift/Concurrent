//
//  Future.swift
//  Parallel
//
//  Created by Robert Widmann on 9/23/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

public struct Future<A> {
	let threadID : MVar<Optional<ThreadID>>
	let cOptional : IVar<Optional<A>>
	let finalizers : MVar<[Optional<A> -> ()]>

	private init(_ threadID : MVar<Optional<ThreadID>>, _ cOptional : IVar<Optional<A>>, _ finalizers : MVar<[Optional<A> -> ()]>) {
		self.threadID = threadID
		self.cOptional = cOptional
		self.finalizers = finalizers
	}
	
	public func read() -> Optional<A> {
		return self.cOptional.read()
	}
	
	public func then(finalize : Optional<A> -> ()) -> Future<A> {
		do {
			let ma : Optional<Optional<A>> = try self.finalizers.modify { sTodo in
				let res = self.cOptional.tryRead()
				if res == nil {
					return (sTodo + [finalize], res)
				}
				return (sTodo, res)
			}
			
			switch ma {
			case .None:
				return self
			case .Some(let val):
				self.runFinalizerWithOptional(val)(finalize)
				return self
			}
		} catch _ {
			fatalError("Fatal: Could not read underlying MVar to spark finalizers.")
		}
	}
	
	private func complete(r : Optional<A>) -> Optional<A> {
		return self.cOptional.tryPut(r) ? r : self.cOptional.read()
	}
	
	private func runFinalizerWithOptional<A>(val : Optional<A>) -> (Optional<A> -> ()) -> ThreadID {
		return { todo in forkIO(todo(val)) }
	}
}

public func forkFutures<A>(ios : [() -> A]) -> Chan<Optional<A>> {
	let c : Chan<Optional<A>> = Chan()
	_ = ios.map({ forkFuture($0) }).map({ f in f.then({ c.write($0) }) })
	return c
}

public func forkFuture<A>(io : () throws -> A) -> Future<A> {
	let msTid = MVar<ThreadID?>()
	let Optional : IVar<A?> = IVar()
	let msTodo : MVar<[A? -> ()]> = MVar(initial: [])

	let p = Future(msTid, Optional, msTodo)
	let act : () -> () = {
		p.threadID.put(.Some(myTheadID()))
		_ = p.complete({
			do {
				return try io()
			} catch _ {
				return nil
			}
		}())
	}

	let process : dispatch_block_t = {
		let paranoid : A? = nil
		p.threadID.modify_({ _ in .None })
		let val = p.complete(paranoid)
		let sTodo = p.finalizers.swap([])
		let _ = sTodo.map(p.runFinalizerWithOptional(val))
	}

	_ = forkIO {
		act()
		process()
	}
	return p
}
