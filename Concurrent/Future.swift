//
//  Future.swift
//  Parallel
//
//  Created by Robert Widmann on 9/23/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

public struct Future<A> {
	let threadID : MVar<Optional<ThreadID>>
	let cResult : IVar<Result<A>>
	let finalizers : MVar<[Result<A> -> ()]>

	private init(_ threadID : MVar<Optional<ThreadID>>, _ cResult : IVar<Result<A>>, _ finalizers : MVar<[Result<A> -> ()]>) {
		self.threadID = threadID
		self.cResult = cResult
		self.finalizers = finalizers
	}
	
	public func read() -> Result<A> {
		return self.cResult.read()
	}
	
	public func then(finalize : Result<A> -> ()) -> Future<A> {
        do {
            let ma : Optional<Result<A>> = try self.finalizers.modify { sTodo in
                let res = self.cResult.tryRead()
                if res == nil {
                    return (sTodo + [finalize], res)
                }
                return (sTodo, res)
            }
            
            switch ma {
            case .None:
                return self
            case .Some(let val):
                self.runFinalizerWithResult(val)(finalize)
                return self
            }
        } catch _ {
            fatalError("Fatal: Could not read underlying MVar to spark finalizers.")
        }
	}
	
	private func complete(r : Result<A>) -> Result<A> {
		return self.cResult.tryPut(r) ? r : self.cResult.read()
	}
	
	private func runFinalizerWithResult<A>(val : Result<A>) -> (Result<A> -> ()) -> ThreadID {
		return { todo in forkIO(todo(val)) }
	}
}

public func forkFutures<A>(ios : [() -> A]) -> Chan<Result<A>> {
	let c : Chan<Result<A>> = Chan()
	_ = ios.map({ forkFuture($0) }).map({ f in f.then({ c.write($0) }) })
	return c
}

public func forkFuture<A>(io : () throws -> A) -> Future<A> {
	let msTid : MVar<Optional<ThreadID>> = MVar()
	let result : IVar<Result<A>> = IVar()
	let msTodo : MVar<[Result<A> -> ()]> = MVar(initial: [])

	let p = Future(msTid, result, msTodo)
	let act : () throws -> () = {
		p.threadID.put(.Some(myTheadID()))
		
		let val : Result<A> = { res in
			return p.complete(res)
        }({
        do {
            return Result.Value(try io())
        } catch let e {
            return Result.Error(e as NSError)
        }
        }())
		
		switch val {
			case .Error(let err):
				throw err
			case .Value(_):
				return ()
		}
	}

	let process : dispatch_block_t = {
		let paranoid = Result<A>.error(NSError(domain: "", code: 0, userInfo: nil))
		
		p.threadID.modify_(const(.None))
		let val = p.complete(paranoid)
		let sTodo = p.finalizers.swap([])
		let _ = sTodo.map(p.runFinalizerWithResult(val))
	}

    _ = forkIO {
        do {
            try act()
            process()
        } catch _ {
            process()
        }
    }
	return p
}
