//
//  Future.swift
//  Parallel
//
//  Created by Robert Widmann on 9/23/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

public final class Future<A> : K1<A> {
	let threadID : MVar<Optional<ThreadID>>
	let cResult : IVar<Result<A>>
	let finalizers : MVar<[Result<A> -> IO<()>]>

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
		let msTid : MVar<Optional<ThreadID>> = !newEmptyMVar()
		let result : IVar<Result<A>> = !newEmptyIVar()
		let msTodo : MVar<[Result<A> -> IO<()>]> = !newMVar([])

		let p = Future(msTid, result, msTodo)
		let act : IO<()> = do_ { () -> () in
			!putMVar(p.threadID)(Optional.Some(!myTheadID()))
			let val = !(try(io).bind { (let r : Either<Exception, A>) -> IO<Result<A>> in
				let res : Result<A> = asResult(r)({ e in return NSError(domain: "", code: 0, userInfo: [ NSLocalizedDescriptionKey : e.description ]) })
				return completeFuture(p)(res)
			})
			switch val.destruct() {
				case .Error(let err):
					return error("")
				case .Value(_):
					return ()
			}
		}

		let process : IO<()> = do_ { () -> () in
			let paranoid = Result<A>.error(NSError(domain: "", code: 0, userInfo: nil));
			!modifyMVar_(p.threadID)(f: const(do_ { .None }))

			let val = !completeFuture(p)(paranoid)
			let sTodo = !swapMVar(p.finalizers)([])
			!mapM_(runFinalizerWithResult(val))(sTodo)
		}

		let thr = !forkIO(finally(act)(then: process))
		return p
	}
}

public func forkFutures<A>(ios : [IO<A>]) -> IO<Chan<Result<A>>> {
	return do_ { () -> Chan<Result<A>> in
		let c : Chan<Result<A>> = !newChan()
		let ps = !mapM(forkFuture)(ios)
		!forM_(ps)({ addFinalizer($0)(writeChan(c)) })
		return c
	}
}

private func completeFuture<A>(p : Future<A>) -> Result<A> -> IO<Result<A>> {
	return { n in
		do_({ () -> Result<A> in
			return !tryPutIVar(p.cResult)(x: n) ? n : readIVar(p.cResult)
		})
	}
}

public func addFinalizer<A>(p : Future<A>) -> (Result<A> -> IO<()>) -> IO<()> {
	return { todo in
		do_ { () -> IO<()> in
			let ma : Optional<Result<A>> = !modifyMVar(p.finalizers)(f: { (let sTodo) in
				return do_ { () -> ([Result<A> -> IO<()>], Result<A>) in
					let ma : Optional<Result<A>> = !tryReadIVar(p.cResult)
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
