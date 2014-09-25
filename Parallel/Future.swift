//
//  Future.swift
//  Parallel
//
//  Created by Robert Widmann on 9/23/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

public final class Future<A> : K1<A> {
	var threadID    : MVar<Optional<ThreadID>>
	var cResult : IVar<Result<A>>
	var finalizers   : MVar<[Result<A> -> IO<()>]>

	init(_ threadID : MVar<Optional<ThreadID>>, _ cResult : IVar<Result<A>>, _ finalizers : MVar<[Result<A> -> IO<()>]>) {
		self.threadID = threadID
		self.cResult = cResult
		self.finalizers = finalizers
	}
}

public func readFuture<A>(p : Future<A>) -> IO<Result<A>> {
	return do_ { () -> Result<A> in
		return readIVar(p.cResult)
	}
}

public func forkFuture<A>(io : IO<A>) -> IO<Future<A>> {
	return do_ { () -> Future<A> in
		var msTid    : MVar<Optional<ThreadID>>!
		var result : IVar<Result<A>>!
		var msTodo   : MVar<[Result<A> -> IO<()>]>!
		var thr : ThreadID!

		msTid <- newEmptyMVar()
		result <- newEmptyIVar()
		msTodo <- newMVar([])

		let p = Future(msTid, result, msTodo)
		let act = do_ { () -> () in
			var val : Result<A>!
			var exec : ()

			exec <- putMVar(p.threadID)(x: Optional.Some(myTheadID().unsafePerformIO()))
			val <- setFuture(p)(Result<A>.right(io.unsafePerformIO()))
			switch val.destruct() {
				case .Error(let err):
					return error("")
				case .Value(_):
					return ()
			}
		}

		let process = do_ { () -> () in
			let paranoid = Result<A>.left(NSError(domain: "", code: 0, userInfo: nil));

			var sTodo : [Result<A> -> IO<()>]!
			var val : Result<A>!
			var exec : ()

			exec <- modifyMVar_(p.threadID)(f: const(do_ { .None }))

			val <- setFuture(p)(paranoid)
			sTodo <- swapMVar(p.finalizers)(x: Array.mempty())
			exec <- mapM_(runFinalizerWithResult(val))(sTodo)
		}

		thr <- forkIO(finally(act)(then: process))
		return p
	}
}

public func forkFutures<A>(ios : [IO<A>]) -> IO<Chan<Result<A>>> {
	return do_ { () -> Chan<Result<A>> in
		var c : Chan<Result<A>>!
		var ps : [Future<A>]!
		var exec : ()

		c <- newChan()
		ps <- mapM(forkFuture)(ios)
		exec <- forM(ps)({ addFinalizer($0)(writeChan(c)) })
		return c
	}
}

private func setFuture<A>(p : Future<A>) -> Result<A> -> IO<Result<A>> {
	return { n in
		do_({ () -> Result<A> in
			var result : Result<A>!
			var put : Bool!
			var exec : ()

			put <- tryPutIVar(p.cResult)(x: n)
			if put! == false {
				return readIVar(p.cResult)
			}
			return n
		})
	}
}

public func addFinalizer<A>(p : Future<A>) -> (Result<A> -> IO<()>) -> IO<()> {
	return { todo in
		do_ { () -> IO<()> in
			var ma : Optional<Result<A>>

			ma <- modifyMVar(p.finalizers)(f: { (let sTodo) in
				return do_ { () -> ([Result<A> -> IO<()>], Result<A>) in
					var ma : Optional<Result<A>>

					ma <- tryReadIVar(p.cResult)
					switch ma {
						case .None:
							return (sTodo + [todo], ma!)
						case .Some(_):
							return (sTodo, ma!)
					}
				}
			})

			switch ma {
				case .None:
					return do_ { () -> () in }
				case .Some(let val):
					return runFinalizerWithResult(val)(todo) >> do_ { () -> () in }
			}
		}
	}
}

private func runFinalizerWithResult<A>(val : Result<A>) -> (Result<A> -> IO<()>) -> IO<ThreadID> {
	return { todo in forkIO(todo(val)) }
}
